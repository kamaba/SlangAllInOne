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

> ✅ **已完成（2026-11-13）**：`Pipeline\RenderData.sl` 落地三类数据结构（CullingData / FrameData / PassData，固定容量数组 + 游标，红线风格）；RenderTest 新增 Phase DATA 全过（culling 快照 in/out + FrameData 2 参数 + PassData 断言），全阶段回归零变化。

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

> ✅ **已完成（2026-11-13）**：`Pipeline\Feature.sl` 落地 RenderFeature（type + enabled + injectionPoint，BeforeOpaque/AfterOpaque/BeforeTransparent/AfterTransparent/BeforePost/AfterPost 六注入点，==/!= 派发）+ 参数 Volume 覆盖栈；RenderTest 新增 Phase FEATURE 全过（AfterPost 注入 + volume override：像素 + 统计双断言）。

### P3 —— RenderPipeline 资产层（需求 4）

**目标**：UniversalRenderPipeline 真正接管 Pipeline.sl 单体。

- `RenderPipelineAsset`：管线配置（排序策略、目标 RT 尺寸、Feature 列表模板、FrameSettings 引用）
- `RenderPipeline`（抽象骨架实例化）：`Render(FrameData)` 入口 = P1 的 context submit 流程包装；Pipeline.sl 的 renderCameraScene 改为默认实现或保留为 legacy 分支
- 全局注册：`SLang.Render.usePipeline(asset)` 门面（Render.sl 加方法 + C 侧无需改动，纯 SL 路由）
- 兼容策略：RenderTest 现有 Phase 全部走新管线，Stat/像素断言不变；PipelineDemo.sl 改用新入口

> ✅ **已完成（2026-11-13）**：RenderPipelineAsset + RenderPipeline 实装接管单体（Render(FrameData) 入口 = context submit 流程包装），SLang.Render 门面路由保留；RenderTest 新增 Phase ASSET 全过（asset → instance → Render(FrameData)：路由 + 像素 + 统计与 Phase PASS 逐项一致）。

### P4 —— 资源与配置（RTHandle / FrameSettings）

- RTHandle 池：固定容量 RT 表（对齐 C 侧 SLR\_MAX\_TEX=64）+ request(w,h)/ReleaseAll；RenderTexture 改薄壳
- FrameSettings：每相机开关（post enable、透明序策略、目标尺寸缩放），挂 Camera.sl
- 统计扩充：STAT\_PASS\_COUNT / STAT\_FEATURE\_COUNT；RenderEnvironment 增加 passCount/featureCount 字段
- 验收：Phase RTPOOL（同 RT 反复请求复用计数）+ Phase FS（关 post 后 draws=3）

> ✅ **已完成（2026-11-13）**：RTHandle 尺寸键池（同尺寸复用 + releaseAll，对齐 C 侧 SLR_MAX_TEX）+ FrameSettings（post 门控 / 排序策略 / renderScale）挂 RenderCamera；STAT_PASS_COUNT/STAT_FEATURE_COUNT 与 RenderEnvironment.passes/featureRuns 计数已扩充；RenderTest 新增 Phase RTPOOL + Phase FS 全过。

### P5 —— 着色器与光照（对齐 HDRP 材质/光照面）

- C 侧新增第三程序 PROG\_UNLIT\_LIGHT（法线点积方向光，单方向光够用）；SL 侧 Light.sl 激活 dirLight 参数（≤6 参 FFI：dirX/Y/Z + r/g/b）
- Hlsl.sl 定位收窄为"SL→C 程序枚举映射表"（本链路无 HLSL 编译器，不假装支持）
- 变体机制：程序枚举 + Material 上的 int 关键字位掩码（C 侧 switch）
- 验收：Phase LIGHT（三角形按法线着色渐变断言）

> ✅ **已完成（2026-11-13，实际范围远超原计划）**：
> - 光照：Light.sl 落地方向光 n·l + 聚光灯（锥角/衰减/位置摇晃实时 applyTo）+ 阴影投射 + Phong 高光 + 无光回归，Phase L 全过。
> - 固化 shader：C 侧不止第三程序，扩到 **5 效果（Lambert/Phong/BlinnPhong/NormalMap/Toon）× flat/tex 变体** + material 0..4 全路由固化槽 + Shader/Texture/Material 门面类，Phase G 全过（退化等价/Blinn 高光/Toon 阶梯/NormalMap 零扰动手算断言）。
> - RHI 后端：GL 之外新增 **D3D11 / Vulkan / GLES(ANGLE)** 三后端同效果验证（Phase D/E/F 与 GL 逐像素一致；VK 的 SPIR-V 固化 shader 未消费光照/gen 参数时降级 builtin 断言跳过，GLES 缺运行库优雅 SKIP）。

### N —— 远期方向具体规划（2026-11-13 定稿：N1→N4 建议顺序；每项独立可验收、可单独排期，启动需用户逐项确认）

> 现状锚点（C 侧源码调研，2026-11-13）：RHI 为 `SlrRhi` 函数表（`RHI\sl_rhi.h`），`draw_item(prog,slot,mesh)` 无实例数概念；"阴影"实为阶段 5 生成的 2D 投影黑斑（光源向背离侧偏移 0.10、放大 1.15、黑 α0.35、PFLAT，`light_pick_shadow` 选灯），**非深度图**；全库零实例化（GL `glDrawArrays` / D3D11 `Draw` / VK `vkCmdDraw(...,1)`）；零多线程（四后端仅 CRITICAL_SECTION 进出锁，VK 为 submit + vkQueueWaitIdle 全同步）；VK 零扩展（VK_API_VERSION_1.0，SPIR-V 仅 6 内建槽、gen 槽降级 builtin）；SLMC 30 opcode 仅 8 可执行，`slr_cmd_execute_stream` 每调用全量重置 perdraw/descs/统计；容量 OBJECTS/TEX=64、PIPES=32、LIGHTS=8、DESC_TEX_SLOTS=16。

#### N1 —— GPU 实例化（建议首发：N2 深度 pass 与大场景共用此地基）

> ✅ **已完成（2026-11-13，Phase INST 全过，RenderTest 18/18 相位全绿）**：
> - C 侧：vtable `draw_item` 扩第 4 参 instanceCount（GL/GLES `glDrawArraysInstanced`、D3D11 `DrawInstanced`、VK `vkCmdDraw` 原生；VK gen 槽维持降级 builtin）。PerDraw 槽实例 i = 槽 base+i，VS `obj = uObjIndex + SV_InstanceID/gl_InstanceID`。统计拆两口径：STAT_DRAW_CALLS(2) / STAT_INSTANCE_COUNT(17)。
> - **方案 A→B 偏离（用户未另立项，按"SL 录制端零改动"原则收缩）**：原计划"SLMC DrawItem(26) opcode 扩实例参数 version 1→2 + CommandBuffer/CullingData 扩 instanceCount + 槽基址"，实做改为 **方案 B——SL 录制端零改动，C 侧 `sl_cmd.c` 回放时对连续 DRAW_ITEM 做 RLE 合并**（条件：!transp 且 lookahead 满足 opcode=DrawItem、slot+n<64、prog/mesh/texd 与首项相同、slot 连续递增；任何非 DrawItem 命令如 SetPerDraw 打断合并）。SL 侧仅 Pipeline.sl STAT 常量表加 STAT_INSTANCE_COUNT=17。
> - shader：5 效果 × flat/tex HLSL 单源加 `SV_InstanceID`/`int obj` 插值 + `uColor[i.obj]`/`uSpec[i.obj]`，build-shaders.ps1 重产 GLSL330/ESSL300/DXBC/SPIR-V；vert cross 加 `--no-support-nonzero-baseinstance`（否则 gl_BaseInstanceARB 编译失败）。VK gen 槽 SPIR-V 未消费实例参数时降级 builtin（断言跳过，与 Phase E 现状一致）。
> - 验收 Phase INST（RenderTest.sl runInstancing）：场景 A = 64×setPerDraw 先行 + 连续 64×drawItem → **draws=3（1 合并+post+blit）/ opaque=1 / instances=64**；场景 B = setPerDraw/drawItem 交替打断 RLE → **draws=66 / opaque=64 / instances=64**；双保险 = 64 槽中心颜色抽样（slot0 (16,16,64) / slot63 (239,239,189)，容差 ±3）+ **A/B 全帧 262144 字节逐点一致**。
> - 本轮收尾时发现的 C 侧遗漏：`sl_rhi_d3d11.cpp` v1 兼容路径 `d3d_v1_draw` 调用点漏改四参（`d3d_draw_item(prog,0,3)` → `(prog,0,3,1)`）导致 dll 整体编不过——已修复；此前模块导出时 vmDll msbuild 失败被静默跳过（"build failed, skip copy"），旧 dll 无 RLE 代码，Phase INST 首跑 draws=66 instances=0 即此征兆。
> - **模块重打包链实操记录（N 阶段 C 侧改动后必走）**：① MSBuild `cvm_render_lib\cvm_sl_render_lib.vcxproj`（Debug|x64）；② 新 dll + slb + json 刷 `out\export\SLangRender\`；③ 重打包 **`package\win32-debug\modules\SLangRender.zip`（zip 真源——Program.cs 启动时镜像进宿主 bin\modules\，bin 位直接改会被构建覆盖回旧包）**；④ 跑 RenderTest → spm 检测 zip md5 与已装清单不符 → 自愈重装 → 编译/运行用新模块。SL 侧改动（如 Pipeline.sl）同样走 ②③④（slb 变更令 md5 变化）。

- 目标：同 mesh + 同材质的 N 对象合一次 instanced draw，drawCalls 不随对象数线性涨。注：原记录"drawItem 增 instanceCount，C 侧循环"作废——C 侧循环只是省 SL↔C 往返的伪实例化，本项做真 GPU instanced draw
- C 侧：vtable `draw_item` 扩 instanceCount（四后端同步：GL/GLES `glDrawArraysInstanced`、D3D11 `DrawInstanced`、VK `vkCmdDraw` instanceCount——ES3.0/GL3.3/D3D11/VK1.0 均原生支持）；PerDraw 槽改"实例 i = 槽 base+i 连续排布"，VS 槽索引 = baseSlot + SV_InstanceID / gl_InstanceID（单 draw 实例上限 64，受 PerDraw 64 槽约束）；统计拆 drawCalls / instanceCount 两口径
- shader：`Render\sl_shaders\hlsl\` 5 效果 × flat/tex 单源加实例索引 → `build-shaders.ps1` 重产 GLSL330/ESSL300/DXBC；VK gen 槽 SPIR-V 同步重编或维持降级（断言跳过）
- SL 侧：SLMC 桥接 opcode DrawItem(26) 扩实例参数（version 1→2 或复用预留位，pack/回放两端同步）；CommandBuffer/CullingData 扩 instanceCount + 槽基址；FFI 红线：拆 `setInstanceCount` + `drawItem` 两调用保持 ≤6 参
- 验收：Phase INST——64 实例一次 draw（drawCalls=1、instances=64）与 64 次独立 draw 像素逐点一致

#### N2 —— 真实阴影：Shadow Map → CSM 级联（依赖 P1 Pass 体系 ✅；软依赖 N1 共享绘制路径）

> ✅ **N2a 已完成（2026-11-13，Phase SHADOW2 三后端全 PASS，RenderTest 19/19 相位全绿）**：
> - **架构偏离（相对原规划）**：① 不新增 SLMC opcode——shadow pass 为 C 侧 `sl_pipeline.c` 新增 `stage_shadow_pass()`（阶段 4.5，cull_layers 与 assemble 之间），管线内部驱动，SL 侧零 opcode 变更；② shadow 深度纹理不走 DESC_TEX_SLOTS——vtable 尾部新增四函数 `shadow_target_create/destroy/begin/bind_depth`（GL/GLES：TEXTURE2 + depth-only FBO；D3D11：t1 SRV + R24G8_TYPELESS；VK 全 NULL → `shadow_on=0` 走黑斑回退）；③ LightBlock 96B→176B（追加 `uLightVP` column_major mat4 + `uShadowParam` + `uShadowZx`，尾部追加零破坏旧布局）。
> - **2D 光向扫掠体（核心设计——平面几何零厚度光栅化正解）**：直接 (v→x, u→z) 投影是 rank-1 退化（ε 剪切也无效，深度图实测恒 clear=1.0）。正解 = shadow volume：castShadow 物体沿背光方向仿射拉伸成扫掠体（u∈[u_min,u_max]→[un,u_max]，深度恒 = (uf-u_max)·du 物体最朝光面），覆盖物体自身 + 全部背光投影区；采样端 P 重投影 (v_P, u_P) 单点 + 深度比较（与 3D shadow map 完全同构）。
> - **跨后端适配（uShadowZx 4 参数）**：xy = 深度值域还原（D3D11 直通 (1,0)；GL/GLES 硬件深度 = ndc.z·0.5+0.5 → (2,-1)）；zw = 纹理行 v 适配（GL/GLES RT t=0 = ndc.y=-1 恒等 (1,0)；D3D11 RT v=0 = ndc.y=+1 行序镜像 → (-1,1)）。
> - **D3D11 双坑（实操记录）**：① `glUniform1i` 同款陷阱在 GL/GLES gen 槽重复——sampler 单元设置必须先 `glUseProgram`（uShadowTex→unit 2 / uTex→unit 1 逐槽设置）；② **D3D11 同资源 DSV（OM 输出）+ SRV（PS 输入）冲突时静默拒绑 SRV**（无 debug layer 不报错，`PSGetShaderResources` 回读 NULL 才确诊）——`d3d_shadow_bind_depth` 必须先 `OMSetRenderTargets(0,NULL,NULL)` 清 OM 再绑 t1。
> - **链路**：Light.sl `shadowQuality`（Float32，0=旧黑斑回退/1=shadow map）→ applyTo 7 float → `slr_light_set`（q[6]→`SlrLight.shadow_quality`）→ `light_pick_shadowmap` → `stage_shadow_pass`（512 深度图 + PerDraw 临时槽，阶段 6 全量覆盖重传）→ `light_build_block` 填 shadow 段 → gen shader（5 效果×flat/tex 全槽）`ShadowAttenuation` PCF 4-tap（±0.5/±1.5 纹素）挂直射项。
> - **验收**：Phase SHADOW2——S_in(阴影内)=213（(0.25+0.9×0.65)×255 精确命中理论值）< S_out=255；S_side（投影区外）=255 证阴影限定在光向投影内；GL/D3D11/GLES 三后端逐像素一致（挂入 Phase D/F 复检，VK 与光照同待遇跳过）；build-shaders.ps1 重产（ESSL shadow sampler 显式 highp——ES3.0 默认 lowp 8bit 深度比较不可用）。
> - **状态恢复**：shadow pass 关 ColorMask（GL/GLES）→ `camera_begin` 每相机恢复；D3D11 shadow_begin 绑 0 RTV + viewport → begin_scene 重绑。黑斑回退路径（shadowQuality=0）代码零改动，Phase L 黑斑断言原样全绿。

- N2a 单张 shadow map：C 侧新增深度专用目标（GL depth texture / D3D11 depth-stencil+SRV / VK depth image，独立于 rt_scene 现有深度）+ 深度 pass 走 SLMC 新 opcode（可被 Pass 体系调度）：光源视角正交投影渲 castShadow 对象；LightBlock（96B/8 灯）外挂 lightVP 16 floats + shadowTex 占 DESC_TEX_SLOTS 16 位中 1 位；光照 shader 加 PCF 2×2；旧投影黑斑保留为 shadowQuality=off 回退（**✅ 实现偏离见上方记录：无 SLMC opcode / 不走 DESC_TEX_SLOTS / LightBlock 176B 尾部追加**）
- N2b CSM 4 级联：视锥固定比例分割（0.05/0.25/0.6/1.0），每级独立 lightVP、深度图集单张 4 分区；shader 按 viewZ 选级联 + 固定核 PCF；Light.sl 扩强度/偏移/级联数参数（applyTo 下发）
- 验收：Phase SHADOW2（N2a：遮挡像素断言——阴影内亮度 < 阴影外）+ Phase CSM（N2b：级联采样落位断言）；四后端一致（VK 降级时跳过）

#### N3 —— 异步/多线程录制（SL 侧零改动、FFI 面零变化；架构风险最高，排 N2 后）

- N3a SLMC 双缓冲：pack 帧 N+1 与执行帧 N 交替（同线程流水线起步）；`slr_cmd_execute_stream` 的每调用全量重置改为按帧槽边界重置，pack/execute 各持独立帧槽互不踩写
- N3b 渲染 worker 线程：C 侧起渲染线程 + 深度 2 提交队列；**GL/GLES 线程亲和为核心约束**——context 只能 current 于 worker（wglMakeCurrent/eglMakeCurrent 归 worker，SL 线程纯 pack 生产）；D3D11 immediate context 归 worker；VK 把 submit+WaitIdle 改 per-frame fence（帧首等待上一帧）；readback 命令保持同步回读（fence + map）
- 验收：Phase ASYNC——双缓冲与 worker 两模式各连跑 N 帧，与同步路径逐帧像素一致；Phase D/E 不回退
- 红线：SL 语言无线程原语，并发全部封装 C 侧；现有四后端 CRITICAL_SECTION 保留为 API 进出锁

#### N4 —— RayTracing（N4a 软件光追 demo 纯 CPU 无依赖可插队；N4b 硬件 RT 记录不排期）

- N4a 软光追 demo（对齐本节原始意图）：C 侧逐像素 CPU 求交——固定容量场景（≤16 球 + 地面平面）+ whitted 2 弹射（主射线 + 阴影射线 + 1 反射），场景描述打包 SLMC 新 opcode 的 args/floats，渲 256×256 写纹理；SL 侧 Ray.sl 激活（rayOrigin/rayDir/球求交/hit 记录结构）；QT QLabel 展示；四后端无关（纯离线）
- 验收：Phase RAY——背景/球体漫反射/阴影区/反射四点手算像素断言
- N4b 硬件 RT（真远景）：前提 = VK 从零扩展升级（ray_tracing_pipeline + acceleration_structure + device 扩展）并重生成 SPIR-V RT 管线，或新增 D3D12 后端走 DXR——两者均为 vtable 大扩面工程，明确不排期

***

## 3. 依赖关系与验收基线

```
P0(Data) ──► P1(Pass) ──► P2(Feature) ──► P3(PipelineAsset) ──► P4(资源/配置) ──► P5(光照/着色器)
                                   └────────────────────────────┘ (P4 可与 P3 并行)
                                                    │
                                                    ▼ N 序列（建议排期顺序，非硬依赖；N3/N4a 相互独立）
              N1(实例化) ──软依赖──► N2(真实阴影/CSM)      N3(异步录制)
              N4a(软件光追，无依赖可插队) ──远景──► N4b(硬件RT，不排期)
```

- **总回归基线（2026-11-13 N1 后更新）**：`RenderTest` **18 相位**（A1/A2/A3/L/G/D/E/F/CB/**INST**/PASS/FEATURE/ASSET/ENV/RTPOOL/FS/DATA/B）全 PASS，`GLRenderTest: PASS`。P0-P5 + N1 实现完毕；N1 后复跑 Phase B renderFrames=1971 pixOk=1971 backendMask=15。
- **Phase B 时序定版（根因记录）**：QT 帧循环 animT 16ms、自动轮播 cycleT **7000ms**（repeating）、退出 quitT **60000ms**（single-shot）。根因：后端段最重路径 = gles EGL init（最长 ~1.2s）+ 全量场景重建（~4.8s）合计 ~5.9s，6s 周期余量仅 ~160ms 随时翻车；7s 周期保证每段 ≥1s 渲染余量。断言：renderFrames≥60 && pixOk≥60，backendMask（gl=1 d3d11=2 vk=4 gles=8）须含 gl 位 + 至少一个其他后端位。
- **C 侧改动仅 P5 需要**；P0-P4 全部 SL 侧，走"重编模块 → 重打包 package zip → RenderTest 编译自愈重装 → 运行"验证链。
- **N 阶段全部涉及 C 侧**：sl_render_lib.dll 重编 + package zip 重打包自愈链；N1/N2 追加固化 shader 重产（`build-shaders.ps1`：HLSL 单源 → GLSL330/ESSL300/DXBC/SPIR-V）。
