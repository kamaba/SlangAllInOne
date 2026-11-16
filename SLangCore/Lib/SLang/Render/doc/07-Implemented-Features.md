# 07 — SLangRender 已实现功能总览

> 本文盘点 SLangRender 模块**当前已实现且经 RenderTest 端到端验收**的功能。
> 设计与规划见 `01-Overview` / `03-Module-Design` / `05-Roadmap-And-Conventions`；
> 使用方法见 `13-Usage-Guide`。

## 1. 功能地图

| 功能块 | SL 侧 | C 侧 | 验收（RenderTest） |
|---|---|---|---|
| RHI 四后端（gl / d3d11 / vk / gles） | `Render.sl` | `sl_render_lib.c` | Phase D/E/F：像素与 GL 逐位一致 |
| 13 阶段渲染管线 | `Pipeline.sl`（门面） | `sl_render_lib.c`（全部逻辑） | Phase A2 + 分阶段驱动 |
| v1 离屏上下文（Context 直连） | `Render.sl` | `sl_render_lib.c` | Phase A1 |
| 多相机合成 + 图片加载 | `Pipeline.sl` / `RenderTexture.sl` | 同上 | Phase A3 |
| 灯光（平行光/点光/聚光 + 阴影） | `Camera\Light.sl` | 同上 | Phase L |
| 固化 shader（5 效果 × flat/tex） | `Pipeline.sl`（gen 槽 8..17） | 着色器固化编译 | Phase G |
| 命令缓冲（录制/排序/回放） | `Pipeline\CommandBuffer.sl` | `sl_cmd.c`（SLMC 回放） | Phase CB |
| 数据层（CullingData/FrameData/PassData） | `Pipeline\RenderData.sl` | —（纯 SL） | Phase DATA |
| Pass 体系（四内置 Pass + 顺序提交） | `Pipeline\RenderPass.sl` / `ScriptableRenderContext.sl` | 零改动 | Phase PASS |
| 环境查询 | `Environment.sl`（RenderEnvironment） | 计数绑定 | Phase ENV |
| 动态网格（CPU 变换 + uploadMesh） | `Mesh.sl` + `RenderPipeline.uploadMesh` | 同上 | Phase C / Phase B 立方体 |
| Mesh 数学库（三角/四边形/立方体） | `Mesh.sl` | — | Phase C |
| QT 窗口对接（QLabel.setPixmapRgba） | SLangQT 模块 | — | Phase B |

## 2. 架构分层（已实现部分）

```
SL 应用层（RenderTest / 用户工程）
   │  import SLangRender
   ▼
SL 门面层  Render（初始化/后端/错误）  RenderPipeline（13 阶段门面）
           RenderObject / RenderCamera / RenderTexture / Light
           CommandBuffer / RenderPass / ScriptableRenderContext
           CullingData / FrameData / PassData / RenderEnvironment
   │  RenderFFI（1:1 绑定 sl_render_lib 导出）
   ▼
C 侧  sl_render_lib.c  —— 13 阶段管线 + RHI 四后端 + 资源管理
      sl_cmd.c          —— SLMC 命令流回放执行器（与 render_lib 同 dll）
```

## 3. 版本状态（2026-11-13）

- **P0（数据层独立）**：完成。`RenderData.sl` 三类 + `CommandBuffer.culling` 快照。
- **P1（Pass 功能块）**：完成。`RenderPass.execute` 按 `passType` 派发 + OpaquePass /
  TransparentPass / PostProcessPass / BlitPass + `ScriptableRenderContext.submitPasses`
  单流提交。C 侧零改动。
- **P2（Feature 机制）**：未开始（RenderFeature / 注入点 / Volume 参数栈）。
- RenderTest 13 阶段全 PASS（`GLRenderTest: PASS`）。

## 4. 相关文档索引

- 后端细节：`08-RHI-Backends.md`
- 管线阶段：`09-Pipeline-13Stages.md`
- 命令缓冲：`10-CommandBuffer.md`
- Pass 体系：`11-Pass-System.md`
- 环境查询：`12-Environment-And-Diagnostics.md`
- **完整使用指南：`13-Usage-Guide.md`**
