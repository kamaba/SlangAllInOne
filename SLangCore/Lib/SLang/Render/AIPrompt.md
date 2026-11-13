# SLangRender 渲染管线演进规划（参照 Unity HDRP 16.0.6 Runtime 机制）

> 原始需求（保留原文）：
>
> 1. 引入 HDRP Runtime 的 feature 机制
> 2. 把数据（专有 Data 层）独立起来
> 3. 增加 Passes 功能块，把 CommandBuffer 和 Pass 的功能结合起来
> 4. RenderPipeline 尽量把这个实现完整
>
> 本文档 = 现状学习结论 + 缺口清单 + P0-N 分阶段实施计划。
> 代码根：`SLangCore\Lib\SLang\Render\SLangRender\`（下称 `<mod>`）。

***

## 0. 现状盘点（2026-11-13 学习结论）

### 0.1 已有且**真实工作**的链路（本模块的"心")

| 文件                          | 角色                                                                                                                                                                      | 状态                            |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `Render.sl`                 | SLang.Render 门面：initialize / camera\_begin / Draw / resolve / 后端信息 / errorString                                                                                        | ✅ 工作中                         |
| `Pipeline\Pipeline.sl`      | RenderPipeline 工作实现：`renderCameraScene`（camera\_begin→opaque 升序 z 升序→透明 queue 升序 z 降序→post→blit→readback）；`executeCommandBuffer(cb)` 门面；`stat(STAT_*)` 统计               | ✅ 工作中（RenderTest Phase CB 全过） |
| `Pipeline\CommandBuffer.sl` | Unity 式三段式：**record**（11 命令扁平数组录制）→ **sortDrawItems**（Early-Z/透明序）→ **pack**（SLMC 命令流：magic 'SLMC' + version + count + offsets + opcodes/args/floats）；CAP 256/2048/8192 | ✅ 工作中                         |
| `Pipeline\RenderFFI.sl`     | FFI 单点（≤6 参红线内包装）：ffiCmdExecuteStream / ffiContextCount / ffiPipelineCount / ffiTextureCount 等                                                                          | ✅ 工作中                         |
| `Pipeline\RenderTexture.sl` | 离屏 RT（createRgba / handle Int64 / destroy）                                                                                                                              | ✅ 工作中                         |
| `Environment.sl`            | RenderEnvironment：available/initialized/backends/backend/GPU renderer+version/资源计数/命令缓冲配置，query()+toString() 快照                                                         | ✅ 工作中（本轮新增）                   |
| `Pipeline\RenderData.sl`    | P0 数据层三类：CullingData（DrawItem 七元组快照）/ FrameData（帧上下文）/ PassData（Pass 数据描述）                                                                                   | ✅ 工作中（Phase DATA 全过）           |
| `Pipeline\RenderPass.sl`    | P1 Pass 体系：RenderPass.execute 按 passType 派发（TYPE_OPAQUE/TRANSPARENT/POST/BLIT）+ OpaquePass/TransparentPass/PostProcessPass/BlitPass 四内置 Pass（C 侧零改动）                | ✅ 工作中（Phase PASS 全过）           |
| `Pipeline\ScriptableRenderContext.sl` | P1 提交器：addPass/passAt + beginPassRecording 预录共享状态 + submitPasses 单流整包（逐 Pass 录制 → sortDrawItems → executeCommandBuffer）                                        | ✅ 工作中（Phase PASS 全过）           |
| C 侧 `sl_cmd.c`              | SLMC 回放执行器（camera\_begin/setRT/clear/draw/post/blit/readback），与 sl\_render\_lib 同 dll 导出                                                                                | ✅ 工作中                         |

### 0.2 骨架（草稿类，已注册但未接入工作链）

`Pipeline\` 下：`RenderPipeline.sl` / `UniversalRenderPipeline.sl` / `ScriptableRenderContext.sl` / `CommandQueue.sl` / `RenderPass.sl` / `GfxDevice.sl` / `GfxBackend.sl` / `GpuResource.sl` / `GpuTexture.sl` / `RenderTarget.sl` / `PipelineState.sl` / `RootSignature.sl` / `PlatformWindow.sl` / `Hlsl.sl` / `HlslLibrary.sl` / `PipelineDemo.sl`；根级 `Renderer.sl`、`Camera\Light.sl`、`Config.sl` 等。

### 0.3 对照 HDRP 16 的机制映射（需求 1-4 的落点）

| HDRP Runtime 机制                                         | SLangRender 现状                                     | 缺口                                                                  |
| ------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| RenderPipelineAsset + RenderPipeline 实例                 | Pipeline.sl 单体函数 + RenderPipeline.sl 骨架            | 资产/实例分离、可切换管线 看是否可以直接使用Unity3d的配置 文件，如果不能使用，则做一个简单的json配置的文件去做对应的功能 |
| ScriptableRenderContext + CommandBuffer(CullingResults) | executeCommandBuffer 已通；ScriptableRenderContext 骨架 | context 聚合 submit 流程                                                |
| RenderPass 体系（HDRP 的 pass 枚举 + 注入点）                     | RenderPass.sl 骨架                                   | Pass 基类 + 执行队列                                                      |
| CustomPass / Volume / VolumeProfile（feature 机制）         | 无                                                  | P2 全新实现                                                             |
| FrameSettings（每相机渲染配置）                                  | Config.sl 骨架                                       | P4                                                                  |
| RTHandleSystem（RT 分配复用）                                 | RenderTexture 手工 create/destroy                    | P4                                                                  |
| Data 层（HDRP 的 RTData/material data 独立）                  | DrawItem/状态散在 CommandBuffer/Pipeline               | **P0**                                                              |
| HDShaderVariants / 材质参数                                 | Hlsl.sl 骨架；C 侧仅 PFLAT/PTEX 两程序                     | P5                                                                  |
| 光照（Light、shadow、SSAO 等后处理链）                             | Light.sl 骨架；C 侧无光照                                 | P5                                                                  |

***

## 1. 缺口总清单（按依赖排序）

1. **Data 层耦合**：DrawItem 字段（prog/slot/mesh/tex/transparent/queue/z/mvp/color）平铺在 CommandBuffer 内部数组；相机/目标/统计状态散在 Pipeline.sl 局部变量 → 无独立"帧数据"结构。
2. **Pass 不存在**：RenderPass.sl 只有类名；排序/绘制/后处理逻辑硬编码在 renderCameraScene。
3. **Feature 注入机制不存在**：无法像 HDRP 那样在渲染前/后插入自定义逻辑（无 CustomPass 注入点、无参数 Volume）。
4. **RenderPipeline 资产层缺失**：UniversalRenderPipeline.sl 未接管 Pipeline.sl；无 asset/instance/全局单例结构。
5. **资源生命周期手工**：RT 无池化复用；Mesh/Texture 无句柄计数与统一释放策略（C 侧有容量上限 16/32/64 但 SL 侧无回收）。
6. **统计/调试面窄**：stat 只有 6 个 STAT\_\*；无逐 pass 计时、无 pass 列表 dump。
7. **着色器/光照空缺**：C 侧两程序、无光照公式、无变体机制。

***

## 2. 分阶段计划（P0 → N，每阶段独立可验证，RenderTest 加 Phase 验收）

> 实现红线（全阶段适用）：SL 语言 `ret` 非 return、无 for 用 while、数组固定容量+游标、FFI ≤6 参、枚举仅 ==/!=、跨类带参构造用无参构造+字段赋值；C 侧改动走 sl\_render\_lib.dll 重编 + package zip 重打包自愈链。

### P0 —— Data 层独立（需求 2，最优先）

**目标**：把"一帧要渲染什么"整理成独立数据结构，逻辑只读写数据，不再各自持有散装状态。

新增 `Pipeline\RenderData.sl`（或 FrameData.sl）：

- `CullingData`：可视物体快照（固定容量 DrawItem 数组 + 游标，字段与现有 drawItem 6 元组对齐）
- `FrameData`：相机参数（viewProj 16 floats）、目标（RT handle + w/h）、清除色、环境（复用 RenderEnvironment 快照）
- `PassData`：每 Pass 的输入/输出 RT 引用 + 预留参数槽
- 改造点：CommandBuffer.record 阶段产出 → 填 CullingData；Pipeline.renderCameraScene 改为吃 FrameData；**行为零变化**（RenderTest 全阶段回归 = 验收标准）

### P1 —— Pass 功能块落地（需求 3 前半：CommandBuffer + Pass 结合）

**目标**：把 renderCameraScene 硬编码流程拆成显式 Pass 序列，每个 Pass = 一个录制单元 + 一个 CommandBuffer。

新增/改造 `Pipeline\RenderPass.sl`：

- `RenderPass` 基类：`Execute(ScriptableRenderContext ctx, CommandBuffer cmd)`（SL 无虚函数则用 type 字段 switch 派发，与 ECommandOpcode 同风格）
- 内置 Pass：`OpaquePass`（queue<2500 升序 z 升序）、`TransparentPass`（z 降序）、`PostProcessPass`、`BlitPass`（对应 C 侧已有 4 类命令，**C 侧零改动**）
- `ScriptableRenderContext`：持有 Pass 列表（固定容量）+ 顺序提交：每 Pass 先 record（"整理要提交的内容"）→ `executeCommandBuffer` 回放
- 验收：RenderTest Phase CB 结果与 P0 完全一致（draws=5 opaque=1 transp=2）

> ✅ **已完成（2026-11-13）**：RenderTest 新增 Phase PASS 全过（4 Pass 单流提交：11 命令 / draws=5 opaque=1 transp=2 / 四像素断言与 Phase CB 逐字节一致，全 13 阶段无回退）。
> 实现偏离记录：C 侧 `slr_cmd_execute_stream` 每次调用都会重置 PerDraw 槽/描述符表并清零统计（sl_cmd.c 帧级前置 memset），分 Pass 分流提交会丢失 setPerDraw/setTexture 状态——故 Pass 序列录进**同一条共享 CommandBuffer**（`beginPassRecording` 预录帧级共享状态 → `submitPasses` 逐 Pass execute 录制 → sortDrawItems → 单流整包），统计口径与单流直提完全一致。派发键为 passType 字段（TYPE_*），子类无参 `_init_` 手动设字段、不调 `this._init_()`（运行期递归地雷）。

### P2 —— Feature 机制（需求 1：HDRP CustomPass/Volume 等价物）

**目标**：不改管线代码即可插入渲染逻辑（HDRP CustomPass 注入点思想）。

新增 `Pipeline\Feature.sl`：

- `RenderFeature`：type + enabled + injectionPoint（枚举：BeforeOpaque/AfterOpaque/BeforeTransparent/AfterTransparent/BeforePost/AfterPost）
- `CustomPass`（Feature 的执行体）：持有自身 CommandBuffer 与参数（Volume 思想：参数结构体 + 全局覆盖栈，固定容量 8 层即可）
- InjectionPoint 执行：ScriptableRenderContext 在 P1 的 Pass 间隙遍历 Feature 表（==/!= 派发）
- 示例 Feature：`ColorOverlayFeature`（全屏色块 pass，用现有 PFLAT 程序即可实现，无需 C 侧新增）
- 验收：RenderTest 新 Phase FEATURE——注册一个 AfterPost Feature，像素断言其影响

### P3 —— RenderPipeline 资产层（需求 4）

**目标**：UniversalRenderPipeline 真正接管 Pipeline.sl 单体。

- `RenderPipelineAsset`：管线配置（排序策略、目标 RT 尺寸、Feature 列表模板、FrameSettings 引用）
- `RenderPipeline`（抽象骨架实例化）：`Render(FrameData)` 入口 = P1 的 context submit 流程包装；Pipeline.sl 的 renderCameraScene 改为默认实现或保留为 legacy 分支
- 全局注册：`SLang.Render.usePipeline(asset)` 门面（Render.sl 加方法 + C 侧无需改动，纯 SL 路由）
- 兼容策略：RenderTest 现有 Phase 全部走新管线，Stat/像素断言不变；PipelineDemo.sl 改用新入口

### P4 —— 资源与配置（RTHandle / FrameSettings）

- RTHandle 池：固定容量 RT 表（对齐 C 侧 SLR\_MAX\_TEX=64）+ request(w,h)/ReleaseAll；RenderTexture 改薄壳
- FrameSettings：每相机开关（post enable、透明序策略、目标尺寸缩放），挂 Camera.sl
- 统计扩充：STAT\_PASS\_COUNT / STAT\_FEATURE\_COUNT；RenderEnvironment 增加 passCount/featureCount 字段
- 验收：Phase RTPOOL（同 RT 反复请求复用计数）+ Phase FS（关 post 后 draws=3）

### P5 —— 着色器与光照（对齐 HDRP 材质/光照面）

- C 侧新增第三程序 PROG\_UNLIT\_LIGHT（法线点积方向光，单方向光够用）；SL 侧 Light.sl 激活 dirLight 参数（≤6 参 FFI：dirX/Y/Z + r/g/b）
- Hlsl.sl 定位收窄为"SL→C 程序枚举映射表"（本链路无 HLSL 编译器，不假装支持）
- 变体机制：程序枚举 + Material 上的 int 关键字位掩码（C 侧 switch）
- 验收：Phase LIGHT（三角形按法线着色渐变断言）

### N —— 远期（不排期，记录方向）

- 异步/多线程录制（SL 单线程，需 C 侧 worker）
- RayTracing（Ray.sl 骨架 → C 侧软件光追小 demo）
- 阴影级联（shadow map RT + 第二次 opaque pass，依赖 P1 Pass 体系）
- GPU instancing（drawItem 增 instanceCount，C 侧循环）

***

## 3. 依赖关系与验收基线

```
P0(Data) ──► P1(Pass) ──► P2(Feature) ──► P3(PipelineAsset) ──► P4(资源/配置) ──► P5(光照/着色器)
                                   └────────────────────────────┘ (P4 可与 P3 并行)
```

- **总回归基线**：`RenderTest` 八相位（A/B/A2/C/D/E + CB + ENV）全 PASS 不得回退，每阶段加一个专属 Phase。
- **C 侧改动仅 P5 需要**；P0-P4 全部 SL 侧，走"重编模块 → 重打包 package zip → RenderTest 编译自愈重装 → 运行"验证链。
