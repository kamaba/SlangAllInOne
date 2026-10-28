# SLang 跨平台渲染引擎设计 · 02 Unity 渲染管线参考

- 所属文档集：`Render/doc/`（01 总览 · **02 Unity 参考** · 03 模块详设 · 04 原生绑定与跨平台 · 05 路线图与规范）
- 版本：v0.3
- 本章是设计依据：说明「从 Unity 借什么、怎么映射到 SLang」。

---

## 1. Unity 渲染体系的三层结构

```
┌─────────────────────────────────────────────────────┐
│ 着色层    ShaderLab(.shader) → HLSL + URP ShaderLibrary │
│           CBUFFER: UnityPerFrame / UnityPerDraw /       │
│                    UnityPerMaterial / UnityLighting     │
├─────────────────────────────────────────────────────┤
│ 编排层    RenderPipelineAsset → RenderPipeline          │
│ (C#/SRP)  ScriptableRenderContext + ScriptableRenderPass│
│           CommandBuffer(录制) + RenderGraph(资源依赖图)  │
├─────────────────────────────────────────────────────┤
│ 设备层    GfxDevice 抽象（Unity 内部 C++ 层）             │
│ (C++)     D3D11 / D3D12 / Vulkan / Metal / GL / GLES    │
│           纹理/缓冲/PSO/描述符/查询/同步                   │
└─────────────────────────────────────────────────────┘
```

SLang 版本的对应关系：**着色层 = HlslLibrary.sl + Hlsl.sl**；**编排层 = RenderPipeline/RenderPass/ScriptableRenderContext/CommandBuffer（全部 .sl）**；**设备层 = C 后端（slang_render.dll 及各图形 API 实现），SL 侧以 GfxDevice/GfxBackend 描述与驱动，经 RenderFFI.sl 的原生绑定（T1）调用**。

## 2. Built-in 管线的一帧（经典固定流程）

```
玩家循环 → WaitForTargetFPS → 每个相机（按 depth 排序）：
  Cull(视锥剔除 + 遮挡剔除)
  → ShadowCaster(阴影贴图，方向光级联)
  → DepthPrepass(可选)
  → Opaque(Geometry 队列，前→后排序)
  → Skybox
  → ImageEffects 之前拷贝
  → Transparent(Transparent 队列，后→前排序)
  → ImageEffects(后处理)
  → GUI
→ GfxDevice.Present
```

要点：**队列值驱动排序**（Background 1000 / Geometry 2000 / AlphaTest 2450 / Transparent 3000 / Overlay 4000，完整值表见附录 A）；**不透明与透明排序方向相反**。

## 3. URP（SRP）的一帧

```
RenderPipeline.Render(context, cameras):
  foreach camera (按 depth):
    1. TryGetCullingParameters → context.Cull(ref params) → CullingResults
    2. context.SetupCameraProperties(camera)          // VP、视口、平台剪裁
    3. BeginRenderPass 逐 Pass 执行（可插入自定义 ScriptableRenderPass）:
         MainLightShadowCasterPass                    // 主方向光阴影
         AdditionalLightsShadowCasterPass             // 附加光阴影 atlas
         DepthOnlyPass                                // 深度预通道
         DrawObjectsPass(Opaque)                      // 不透明
         CopyDepthPass / CopyColorPass                // 深度/颜色拷贝
         SkyboxPass
         DrawObjectsPass(Transparent)                 // 透明
         PostProcessPass(Bloom/Tonemap/AA...)         // HDR 链
         FinalBlitPass                                // 回 backbuffer
    4. context.ExecuteCommandBuffer / Submit
  Present
```

SRP 相对 Built-in 的三个本质改进，全部要在 SLang 版实现：

1. **管线即数据**：`RenderPipelineAsset` 持配置，`createPipeline()` 出实例，可热切换管线（Unlit 管线 / URP / 自定义）。
2. **Pass 可插拔**：`RenderPass`（event 顺序 + configure + execute），用户能插入自定义 Pass。
3. **资源显式化**：相机颜色/深度目标是显式 `RTHandle`，URP 14+ 进一步用 **RenderGraph** 声明资源依赖，自动插入屏障与复用（SLang v1 用手工 Pass + RT 池，RenderGraph 列为演进项 M7）。

## 4. Unity 值得借鉴的关键机制（本设计采纳清单）

| 机制 | Unity 做法 | SLang 采纳方式 |
|---|---|---|
| 渲染队列 | RenderQueue 整数值分桶排序 | `VisibleRenderer.renderQueue` + 附录 A 值表 |
| 视锥剔除 | Gribb-Hartmann 平面 + 包围球 | 已有 `CullingParameters.extractPlanes()`，保留并补 cullingMask/light 剔除 |
| SRP Batcher | 按 Shader 分桶，UnityPerDraw/PerMaterial 兼容 CBUFFER 合批 | v1 简化为「按 PSO 分桶 + 三个标准 CBUFFER」（见 03 §4.4 / 附录 B） |
| RT 池 | RenderTexturePool 按描述符复用 + 帧延迟回收 | `RenderTargetPool` 增强（见 03 §4.6） |
| 阴影 | 主方向光级联(1/2/4) + atlas + PCF 软阴影 | `ShadowCasterPass` v1 单级联，v1.1 四级联 + atlas（见 03 §4.9） |
| 附加光 | 主光走专用 CBUFFER，附加光数组 + 每像素上限 | `UnityLighting` 扩展为定长光数组（见附录 B） |
| HDR 中间缓冲 | RGBA16F/B10G11R11 场景色 + 后处理 + FinalBlit 回 sRGB | `RenderTextureDescriptor.hdr()` + `PostProcessPass` + `FinalBlitPass` |
| MSAA | 离屏 MSAA RT + Resolve 到采样纹理 | RT 加 `msaaSamples` + `slr_resolve_texture`（见 03 §4.6） |
| 多相机 | depth 排序 + Base/Overlay 相机栈 | v1：depth 排序 + viewport/rect；相机栈列 v1.1 |
| CommandBuffer | 录制 → ExecuteCommandBuffer 回放 | v1 改为「真录制」（命令数组 + ptr 打包整包提交），见 01 D1 |
| GPU 帧同步 | Frame fence + frameLatency | 已有 `Fence`/`waitForNextFrame()`，保留 |
| 延迟删除 | GPU 仍在用的资源进删除队列，N 帧后销毁 | 新增 `ResourceRegistry`（见 03 §4.3） |
| 后端调用 | 内部 C++ GfxDevice 直调（无字符串分发层） | **对齐做法**：T1 原生 FFI 绑定直调后端 `slr_*` 函数（01 D8 / 04） |

## 5. Unity → SLang 概念映射表

| Unity | SLang 现有 | 状态 |
|---|---|---|
| GfxDevice（内部 C++） | `GfxDevice` + `GfxBackend` + C 后端（slr_ 绑定） | 骨架有，需补契约（03 §4.2 / 04） |
| RenderPipelineAsset | `RenderPipelineAsset` / `UniversalRenderPipelineAsset` | 已有，需补字段 |
| RenderPipeline | `RenderPipeline` / `UniversalRenderPipeline` | 骨架有，render() 需重写为 Pass 驱动 |
| ScriptableRenderContext | `ScriptableRenderContext` | 已有，需补执行接口 |
| ScriptableRenderPass | `RenderPass` + 6 个内建 Pass | 已有，需补 FinalBlitPass/ResolvePass |
| CommandBuffer | `CommandBuffer` | 直通式占位，需改真录制（01 D1） |
| CullingResults | `CullingResults` / `VisibleRenderer` | 已有，排序有 bug（05 §2.1） |
| RenderTexture / RTHandle | `GpuTexture` + `RenderTextureDescriptor` | 已有，需加 MSAA/resolve |
| RenderTexturePool | `RenderTargetPool` | 已有，需帧安全回收 |
| Material | `Material` | 仅数据壳，需绑 CBUFFER/纹理槽（03 §4.11） |
| Shader(ShaderLab) | `Shader` + `HlslShader` + `HlslLibrary` | 双轨需统一（03 §4.4） |
| Mesh(引擎侧) | `Mesh` + `VertexBuffer`/`IndexBuffer` | 上传路径缺失（03 §4.11） |
| Camera / Light | `Camera` / `Light` | 已有，管线未消费 Light |
| SwapChain | `SwapChain` | index 同步 bug（05 §2.1） |
| PSO | `GraphicsPipelineState` / `ComputePipelineState` | 已有 |
| RootSignature/DescriptorHeap | `RootSignature` / `DescriptorHeap` / `DescriptorSet` | 已有，RTV/DSV 枚举缺失（05 §2.1） |
| Fence | `Fence` | 已有 |
| RenderGraph | 无 | M7 演进 |

---

## 附录 A 渲染队列值表（对齐 Unity RenderQueue）

| 队列 | 值 | 用途 | 深度写 | 排序 |
|---|---|---|---|---|
| Background | 1000 | 天空盒前/相机背景 | 视情况 | 不透明 |
| Geometry | 2000 | 默认不透明 | 开 | 前→后 |
| AlphaTest | 2450 | Alpha 测试（植被） | 开 | 前→后 |
| GeometryLast | 2500 | 不透明收尾 | 开 | 前→后 |
| Transparent | 3000 | 半透明 | 关 | 后→前 |
| Overlay | 4000 | UI/后期叠加 | 关 | 后→前 |

现有代码以 2500 为不透明/透明分界，与本表一致；`VisibleRenderer._init_` 中透明推到 3000，保持。
