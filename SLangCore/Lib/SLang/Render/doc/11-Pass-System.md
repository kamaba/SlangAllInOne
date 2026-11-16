# 11 — Pass 体系（P0 数据层 + P1 Pass 功能块，已实现）

> 对应实现：`Pipeline\RenderData.sl`（P0）+ `Pipeline\RenderPass.sl` /
> `Pipeline\ScriptableRenderContext.sl`（P1）。把 renderCameraScene 的
> 硬编码流程拆成**显式 Pass 序列**，对齐 Unity SRP（ScriptableRenderPipeline）。
> **C 侧零改动**——四类桥接命令在 `sl_cmd.c` 已存在。

## 1. P0 数据层（RenderData.sl）

| 类 | 角色 | 关键成员 |
|---|---|---|
| `CullingData` | 可视物体快照（排序输入/输出） | `addItem(prog,slot,mesh,texDesc,transp,queue,z)`、`count`、`opaqueCount`、`transparentCount`、`getQueue(i)/getZ(i)/getProg(i)...` |
| `FrameData` | 帧级共享状态 | MVP/贴图槽/颜色槽 |
| `PassData` | 单 Pass 输出数据 | 预留统计 |

`CommandBuffer.sortDrawItems()` 排序结果写入 `cb.culling`（快照），
Pass 层从这里按 queue 分流取条目。

## 2. RenderPass 基类

```sl
public class RenderPass
{
    public string name
    public Int32 passEvent                  # 事件序（RenderPassEvent）
    public Int32 passType                   # 派发键：TYPE_OPAQUE/TRANSPARENT/POST/BLIT
    public CullingData culling              # 本 Pass 要画的可视集
    public Int32 viewportX/Y/W/H
    public bool clearTargetColor / clearTargetDepth
    public Color clearColor                 # 缺省 Color.black()
    # Post 参数
    public bool postEnabled; Float32 postBrightness/Saturation/Vignette
    # Blit 参数
    public Int64 blitReadbackPtr

    public void execute( ScriptableRenderContext ctx, CommandBuffer cmd )
}
```

`execute()` 按 `passType` if-else 派发到四个私有 exec 方法（不用 virtual，
遵守 doc/05 语言红线——文件级 enum 地雷）。派发键为 Int32 静态常量
`RenderPass.TYPE_BASE=0 / TYPE_OPAQUE=1 / TYPE_TRANSPARENT=2 / TYPE_POST=3 /
TYPE_BLIT=4`。

## 3. 四内置 Pass

| Pass | 行为 |
|---|---|
| `OpaquePass` | 录 `setRenderTargets(TARGET_SCENE, viewport, clearFlags, clearColor)`（clearFlags 按 `clearTargetColor/Depth` 组装）→ 遍历 culling 中 `queue < 2500` 逐条 `cmd.drawItem(...)`（Int64→Int32 经 `SystemConvertInt32` 窄化） |
| `TransparentPass` | **不录 setRT**（复用 OpaquePass 已绑定的场景目标槽位，同帧持久）→ 遍历 `queue >= 2500` drawItem |
| `PostProcessPass` | `cmd.postProcess(enabled, brightness, saturation, vignette)`（enabled 由 `postEnabled` 转 0/1） |
| `BlitPass` | `cmd.blitFinal()` + `if blitReadbackPtr != 0 cmd.readback(blitReadbackPtr)` |

新增内置/自定义 Pass 只需：继承 RenderPass + 无参 `_init_()` 手动设字段
（**不得调 `this._init_()`**——基类构造含 RenderPassEvent 访问）+
设 `passType` 复用现有 exec，或扩展基类派发链。

## 4. ScriptableRenderContext（顺序提交器）

```sl
ScriptableRenderContext ctx = ScriptableRenderContext()   # 无参构造
ctx.pipeline = pipe                                        # 挂管线句柄
ctx.addPass( opaquePass )        # 容量 CAP_PASSES=16，判空/判满
ctx.addPass( transparentPass )
ctx.addPass( postPass )
ctx.addPass( blitPass )

ctx.beginPassRecording( setupCmd )     # 可选：帧级共享状态预录
                                        # （setTexture/setPerDraw 等录进同一 cb）
ctx.submitPasses()                     # true = 任一 Pass 提交成功
```

`submitPasses()` 单流方案：逐 Pass 顺序录进**同一条共享 CommandBuffer**
→ 每个 DrawItem 段前 `sortDrawItems()` → `end()` → 一次整包
`pipeline.executeCommandBuffer()`。规避 C 侧"每流重置状态"的契约
（见 `10-CommandBuffer.md` §5）。

## 5. 验收（RenderTest Phase PASS）

四 Pass 序列（Opaque→Transparent→Post(disabled)→Blit）+ CullingData 乱序灌入
3 条 + 帧级 setup 预录；像素断言（corner/tri/quadtex/overlap）与
Phase CB 逐字节一致；stats：draws=5 / opaque=1 / transp=2。
同一场景经「单条手写命令流（Phase CB）」与「Pass 序列（Phase PASS）」
两条路径产出相同画面。
