# 10 — CommandBuffer 命令缓冲（已实现）

> 对应实现：`Pipeline\CommandBuffer.sl`（录制层）+ `sl_cmd.c`（C 侧回放器，同 dll 导出）。
> 设计对齐 Unity CommandBuffer / DX12 GraphicsCommandList：录制期零后端调用，
> 提交时整包回放。

## 1. 三段式录制结构

```
_opcodes[i]                    条目 i 的 opcode
_args[i] / _floats[i]          整数 / 浮点扁平参数流
_argStart/_argCount/_floatStart/_floatCount[i]   条目 i 的数据区间
```

固定容量（doc/05 §3.1 规则 4，禁止每帧增长）：
`CAP_COMMANDS=256 / CAP_ARGS=2048 / CAP_FLOATS=8192`。
超限只递增 `_overflow` 计数，不脱同步（游标照常推进）。

## 2. 命令集（ECommandOpcode）

- `0..24`：doc/03 §4.7 标准 opcode（SetViewport / SetRenderTargets / SetTexture /
  Draw / Dispatch ...）——当前后端回放记账跳过，前向兼容；
- `25..29`：**桥接扩展**（13 阶段管线整数槽位世界，C 侧可执行）：
  `SetPerDraw=25 / DrawItem=26 / PostProcess=27 / Blit=28 / Readback=29`。

> 2026-11-13 修复记录：文件级 enum 曾把成员访问编译成"最近类"静态槽索引导致
> opcode 全错；现 `ECommandOpcode` 为 Int32 静态常量类，值与 C 侧
> `SLR_CMD_*` 逐值一致，勿改动。

## 3. 主要录制 API

```sl
CommandBuffer cmd = CommandBuffer()
cmd.begin()
cmd.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0,0,256,256,
                      SLang.RenderPipeline.CLEAR_COLOR|SLang.RenderPipeline.CLEAR_DEPTH,
                      Color( 0.06f, 0.06f, 0.10f, 1.0f ) )
cmd.setTexture( 0, tex.handle )                    # slot, 纹理句柄
cmd.setPerDraw( 0, mvp, color )                    # slot, Float32_4x4(列主序), Color
cmd.drawItem( prog, slot, mesh, texDesc, transparent, queue, z )
cmd.postProcess( enabled, brightness, saturation, vignette )
cmd.blitFinal()
cmd.readback( pixelsPtr )                          # Int64 目标指针
cmd.end()
```

目标槽：`TARGET_SCENE=0`（带深度）/ `TARGET_POST=1` / `TARGET_FINAL=2`。
`setPerDraw` 是槽位写，**不构成 DrawItem 段边界**。

## 4. sortDrawItems 排序（与 C 侧 sort_items 键序一致）

扫描条目表找**连续 DrawItem 段**，段内插入排序：

- 不透明（`queue < 2500`）：queue 升序 → z 升序 → prog 升序；
- 透明（`queue >= 2500`）：queue 升序 → **z 降序**（后→前混合）。

排序后写入 `cb.culling`（CullingData 快照，P0 数据层），并返回命中段数。
`clear()` 同步清空 culling。

## 5. 提交与回放

```sl
bool ok = pipe.executeCommandBuffer( cmd )
```

门槛：`handle != 0`、`cb != null`、`isRecording == false`、
`commandCount > 0`、`streamBytes() > 0`。
打包布局 SLMC：`magic|version|count|argOffset|floatOffset|opcodes|args|floats`。

**单流契约（重要）**：`slr_cmd_execute_stream` 每次调用会重置 PerDraw 槽、
描述符表并清零统计。因此一帧内的所有状态 + 绘制命令必须在
**同一条命令流里整包提交**；P1 Pass 体系据此采用"多 Pass 顺序录制 →
单流一次提交"（见 `11-Pass-System.md`）。

提交即回放，`cb.clear()` 后可复用。
