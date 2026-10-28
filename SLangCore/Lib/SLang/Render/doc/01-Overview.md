# SLang 跨平台渲染引擎设计 · 01 总体架构

- 版本：v0.4（设计稿，供评审）
- 日期：2026-10-27
- 变更记录：
  - v0.4：新增 06 图像编解码设计（PNG/JPEG/WebP 读写 + SVG 解析/光栅化 + 纹理零拷贝上传路径）；文档集扩为 6 份
  - v0.3：文档集拆分为 5 份；后端调用策略改为「原生 FFI 绑定优先（T1）→ 系统方法兜底（T2）→ 淘汰 `SystemCallExternalFunction` 字符串分发（T3）」，见 D8 与 04 文档
  - v0.2：新增 WebGPU 后端与 H5 Canvas 2D 呈现路径（D7）
  - v0.1：初稿（单文件）
- 状态：待评审。评审通过后按 05 文档路线图分里程碑实施。

---

## 0. 文档集索引

| 编号 | 文件 | 内容 | 主要读者 |
|---|---|---|---|
| 01 | `01-Overview.md`（本文） | 目标与范围、分层架构、一帧数据流、设计决策 D1-D8 | 全员必读 |
| 02 | `02-Unity-Pipeline-Reference.md` | Unity 渲染管线研究（三层结构 / Built-in / URP）、概念映射表、渲染队列值表 | 管线 / Pass 设计 |
| 03 | `03-Module-Design.md` | 各模块详细设计（.sl 类与方法签名）、cbuffer 布局规范、内置着色器清单 | 模块实现 |
| 04 | `04-NativeBinding-And-Platform.md` | 原生绑定契约（T1/T2/T3 三级策略、slr_ 符号表、描述符打包规范）、跨平台策略 | 后端 / 绑定面 |
| 05 | `05-Roadmap-And-Conventions.md` | 里程碑 M0-M7、现有代码问题清单、SLang 编码规范、术语表 | 排期 / 评审 |
| 06 | `06-Image-Codec.md` | 图像编解码（PNG/JPEG/WebP 读写、SVG 解析/光栅化、blob、纹理零拷贝上传） | 图像 / 纹理链路 |

阅读顺序：01 → 02（可选）→ 03 / 04 / 06（并行）→ 05。

---

## 1. 设计目标与范围

### 1.1 目标

| 目标 | 说明 |
|---|---|
| 纯渲染引擎 | 只做「把一组可见物 + 相机 + 光源变成像素」这一件事。不包含物理、状态机、AI、资源序列化、网络等任何游戏引擎子系统 |
| 跨平台 | Windows / Linux / macOS / Android / iOS / Web / 无头(CI、烘焙) |
| 跨图形 API | D3D12、D3D11、Vulkan、Metal、OpenGL、OpenGL ES、WebGPU、WebGL、Software（CPU 光栅兜底） |
| Web 三级兜底 | WebGPU → WebGL2/WebGL1 → H5 Canvas 2D（Software 光栅呈现），任何浏览器环境均可运行 |
| 可编程管线 | 对齐 Unity SRP 思路：`RenderPipelineAsset -> RenderPipeline -> RenderPass` 三级可扩展，内置一套 URP 风格的通用管线 |
| 图像读写 | 内置 PNG/JPEG/WebP 解码与编码、SVG 解析与按需光栅化；纹理加载零拷贝直传 GPU（06） |
| 分层清晰 | SL 侧只做「编排与状态描述」；GPU 操作优先经**原生 FFI 绑定**（`@DllStaticImport` 直连后端 `extern "C"` 函数，零 SL 帧）提交 |
| 原生绑定优先 | 后端调用三级策略：**T1** `@DllStaticImport`/`@DllImport` 直连（首选）→ **T2** 系统方法 SystemMethodCall（对象互操作 / 变参 / 结构化返回时兜底）→ **T3** `SystemCallExternalFunction` 字符串分发（冻结存量、逐步删除）。详见 04 |
| 单语言实现 | 管线逻辑、剔除、排序、着色器源码组织全部用 SLang（.sl）编写，HLSL 以字符串形式由 SLang 管理 |

### 1.2 非目标（明确不做）

- 物理、碰撞、导航
- 游戏对象状态机、脚本生命周期驱动（MonoBehaviour 那套由宿主引擎负责）
- 场景图 / 序列化 / 资产数据库（渲染引擎只接收「已组装好的可见物列表」）
- 音频（现有 `Audio/` 目录建议迁出 Render 库，见 03 §4.13）
- UI 布局系统（`RectTransform/UIBehaviour` 仅保留为宿主侧适配数据，渲染引擎只提供 2D 绘制路径）
- 多线程渲染（v1 单线程录制，接口为多线程预留）

### 1.3 引擎边界（对外契约）

```
宿主引擎/应用                     SLang 渲染引擎
────────────────                ───────────────────────────────
Array<VisibleRenderer>   ──►    剔除 → 排序 → Pass 编排 → 命令 → 后端 → 屏幕
Array<Camera>            ──►
Array<Light>             ──►    输出：SwapChain 呈现 / 离屏 GpuTexture
RenderPipelineAsset      ──►
```

渲染引擎不持有 GameObject 概念。每帧由宿主把可见候选（`VisibleRenderer`：mesh + material + localToWorld + bounds + renderQueue + layer）注入管线；引擎负责剔除、排序、提交。

---

## 2. 总体架构

### 2.1 分层设计

```
L6 演进预留     GPU Driven / RenderGraph / RayTracing / MeshShader
─────────────────────────────────────────────────────────────
L5 管线编排     RenderPipeline.sl  RenderPass.sl  UniversalRenderPipeline.sl
               RenderPipelineAsset / Manager
─────────────────────────────────────────────────────────────
L4 剔除与上下文  ScriptableRenderContext.sl（CullingParameters/Results、排序、绘制分发）
─────────────────────────────────────────────────────────────
L3 状态与命令    PipelineState.sl  RootSignature.sl  RenderTarget.sl
               CommandBuffer.sl  CommandQueue.sl(SwapChain/Fence)
─────────────────────────────────────────────────────────────
L2 GPU 资源     GpuResource.sl  GpuTexture.sl  Hlsl.sl  HlslLibrary.sl
               ResourceRegistry.sl(句柄注册表 + 延迟删除)  ShaderCache.sl
─────────────────────────────────────────────────────────────
L1 平台与设备   PlatformWindow.sl  GfxBackend.sl  GfxDevice.sl
─────────────────────────────────────────────────────────────
L0 数学与数据   Vector.sl Matrix.sl Color.sl Bounds.sl Ray.sl Plane.sl
               Vertex.sl Mesh.sl Material.sl Texture.sl Shader.sl(轻量)
               Camera.sl Light.sl Config.sl Transform.sl
─────────────────────────────────────────────────────────────
FFI 桥（见 04） T1 原生绑定：RenderFFI.sl 的 @DllStaticImport/@DllImport
                     → slang_render.dll / libslang_render.so（装配期绑定、零 SL 帧）
               T2 系统方法：.jsonc systemCalls[] + cvmFunction 符号绑定
                     （对象构造 / 变参 / 结构化返回的兜底）
               T3 字符串分发：SystemCallExternalFunction("Render.xxx")
                     （存量兼容，M3 末删除）
```

依赖规则：**只允许上层引用下层**；L0 依赖 Math 库（Float32_3/4x4/Mathf）与 Core 库（Component）；Camera/Light/Renderer 依赖 Core 的 Component 是宿主适配性质，标注见 03 §4.13。

### 2.2 目录与文件规划

```
Render/
├── doc/                          # 本文档集（01-05 共 5 份）
├── Render.jsonc                  # 编译清单 + dllImports 绑定配置（见 04 §2）
├── L0（根目录，现有保留）
│   ├── Vector/Matrix/Color/ColorUInt8/Bounds/Ray/Plane/Transform   # 不动
│   ├── Vertex.sl Mesh.sl Material.sl Texture.sl Shader.sl          # 增强（03 §4.11）
│   ├── Renderer.sl Camera/ Camera.sl Light.sl Config.sl            # 增强
│   ├── Behaviour.sl UIBehaviour.sl RectTransform.sl                 # 标注宿主适配层
│   └── Render.sl                 # 兼容层：内部转发到 RenderPipelineManager（03 §4.12）
├── Image/                        # 图像编解码（PNG/JPEG/Webp/Svg 等 8 个 .sl）：探测/容器模型纯 SL，
│   │                            #  编解码走 T1/T2 绑定；完整设计见 06（M2 登记 compileFiles）
│   └── (待新增) ImageCodec.sl    # 06 §6.1：ImageCodec 工具类（toTextureFormat 等）并入现有文件或独立
├── Pipeline/
│   ├── RenderFFI.sl             # 新增：唯一原生绑定面（@DllStaticImport 集中声明，04 §2；
│   │                            #  含图像编解码 slr_image_*/slr_svg_*/slr_blob_*，见 06 §5）
│   ├── PlatformWindow.sl         # 增强：WaylandWindow、事件队列（03 §4.1）
│   ├── GfxBackend.sl             # 增强：后端探测注册表（03 §4.2）
│   ├── GfxDevice.sl              # 重构：初始化流程 + 帧循环（03 §4.2）
│   ├── GpuResource.sl            # 增强：upload/映射 + ResourceRegistry（03 §4.3）
│   ├── GpuTexture.sl             # 增强：MSAA/resolve/压缩格式（03 §4.3）
│   ├── ResourceRegistry.sl       # 新增：句柄表 + 帧延迟删除（03 §4.3）
│   ├── Hlsl.sl                   # 统一：Shader/ShaderModule/变体（03 §4.4）
│   ├── ShaderCache.sl            # 新增：源码哈希 → 编译缓存（03 §4.4）
│   ├── HlslLibrary.sl            # 扩展：光源数组/级联/变体宏（03 §4.4 + 附录 C）
│   ├── PipelineState.sl          # 增强：深度偏移/多RT混合（03 §4.5）
│   ├── RootSignature.sl          # 修复：RTV/DSV 枚举（03 §4.5）
│   ├── RenderTarget.sl           # 增强：池化键/resolve（03 §4.6）
│   ├── CommandBuffer.sl          # 重写：真录制模型 + 命令流打包（03 §4.7）
│   ├── CommandQueue.sl           # 增强：swapchain index 查询（03 §4.7）
│   ├── ScriptableRenderContext.sl# 增强：排序修复/附加光收集（03 §4.8）
│   ├── RenderPass.sl             # 增强：FinalBlitPass/DrawRendererList 规范（03 §4.9）
│   ├── RenderPipeline.sl         # 增强：相机循环/事件回调（03 §4.10）
│   ├── UniversalRenderPipeline.sl# 重写：Pass 驱动 + 级联阴影 + 附加光（03 §4.10）
│   └── PipelineDemo.sl           # 更新为新 API 演示
├── Audio/                        # 建议迁出至 SLang/Audio（03 §4.13）
└── cvm_render_lib/               # C 粘合层：T2 兼容注册 + 对象→描述符打包器（04 §3.5）
```

### 2.3 一帧数据流（目标态）

```
宿主                                SLang 编排层                        C 后端（slang_render）
────                                ────────────                        ────────────────────
RenderPipelineManager.beginFrame ─► GfxDevice.beginFrame()
                                       ├ pumpMessages()                ─► slr_window_pump
                                       ├ frameFence 等待 latency 帧     ─► slr_fence_wait
                                       └ DescriptorHeap.reset()
宿主 setSceneRenderers(...)       ─►
                                   └► foreach camera (depth 排序):
                                        RenderPipeline.render(ctx, cam)
                                          1 CullingParameters.fromCamera
                                          2 ctx.cull()：平面剔除+距离排序
                                          3 收集附加光 → 光常量打包
                                          4 foreach pass(按 event 排序):
                                              pass.begin/configure
                                              pass.render(ctx)  → CommandBuffer
                                                                   .setRenderTarget
                                                                   .setPipelineState
                                                                   .setConstantBuffer
                                                                   .setVertexBuffer/Index
                                                                   .drawIndexed ...
                                              pass.end
                                          5 ctx.submit() ─► 命令流打包(ptr)
                                                         ─► slr_cmd_execute_stream
RenderPipelineManager.endFrame   ─►  GfxDevice.endFrame()
                                       └ queue.signal(frameFence)      ─► slr_queue_signal
RenderPipelineManager.present    ─►  SwapChain.present() ────────────► slr_swapchain_present
                                       frameIndex++ / ResourceRegistry
                                       .flush(frameIndex)  # 释放到期资源
```

图中所有 `slr_*` 均为 T1 原生绑定（经 `RenderFFI.sl` 声明，见 04）。

### 2.4 关键设计决策（评审重点）

- **D1 命令模型：直通 → 真录制。** 现状 `CommandBuffer` 每个方法直接调 FFI（立即执行），`handle` 恒 0，池化无意义，且 Pass 录制的顺序与提交顺序无法解耦。目标：`CommandBuffer` 内部维护命令数组（枚举 opcode + 参数），`begin()` 清空、各 set/draw 方法 push 命令、`end()` 封口；`CommandQueue.execute()` 把三个数组（opcodes/args/floats）按固定布局写入一块原生内存（`Memory.alloc` + `Memory.writeXxx`），再以 `slr_cmd_execute_stream(queue, cmd, ptr, count)` 一次性整包提交（T1）。收益：一帧多相机可并行录制、命令可重放、统计真实。GL 后端按序直译。
- **D2 双轨统一：废弃按名 uniform。** 现状存在 `Shader.setUniform*`（GL 风格按名设值）与 `ConstantBuffer`（DX12 风格）两条路。目标：SL 侧统一走 `ConstantBuffer`（按槽位写 staging，`slr_cb_update(handle, ptr, size)` 刷原生内存），按名接口仅保留在兼容层 `Render.sl` 内部使用。理由：D3D12/Vulkan/Metal/WebGPU 都没有按名 uniform，按名路径迟早成死代码。
- **D3 Material = Shader 变体 + PSO 键 + 材质 CBUFFER。** Material 持有 `shaderId`、`variantKey`（keyword 组合）、材质参数 staging。管线在绘制时以 `(shaderId, variantKey, blend/raster/depth 摘要, RT 格式, MSAA)` 为键查 PSO 缓存（对齐 Unity 的 ShaderLab Pass 编译产物 + SRP Batcher 的 ShaderId 分桶）。
- **D4 Mesh 的 GPU 资源缓存在 Mesh 内（mesh.gpu 脚手架），由管线按需上传。** `Mesh` 新增 `MeshGpuData`（VB/IB/布局/版本号），首次绘制时懒上传，`setVertices` 等修改使版本号 +1 触发重传。剔除用 CPU 侧 bounds，绘制用 GPU 缓存。
- **D5 GL 系后端在 C 层模拟显式 API。** SL 侧不写 `if isGlStyle()` 分支管线逻辑（现状 GfxDevice 里已经有点漏）；描述符/PSO/屏障命令在 C 后端的 GL 实现里翻译成 VAO/Program/状态缓存。SL 侧语义统一为显式 API。
- **D6 渲染路径以 RT 为中心。** URP 全程写 HDR 中间 RT（RGBA16F）+ 独立深度，MSAA 时写 MSAA RT 后 Resolve，最终 `FinalBlitPass` 回 backbuffer。对齐 URP 的 cameraColorTarget 模型，后续接 RenderGraph 也不返工。
- **D7 Web 平台三级降级链。** WebGPU（首选，显式 API 语义直通）→ WebGL2/WebGL1（走 D5 的 GL 模拟路径）→ H5 Canvas 2D（Software 光栅 + putImageData 呈现，保证禁用硬件加速的浏览器也能出图、可截图、可跑 CI）。降级用现有 `GfxDeviceDescriptor.fallbackBackends` 机制表达，上下文协商（navigator.gpu / webgl2 / 2d）在 C 后端设备创建内部完成，SL 侧管线零分支。
- **D8 原生绑定优先（FFI-first）。** 渲染后端调用分三级：
  - **T1 原生绑定（首选）**：`@DllStaticImport("SLangRender", "slr_xxx", "sig")` 声明式直连后端 DLL 的 `extern "C"` 扁平函数。装配期（cvm assembly build）绑定、**零 SL 帧**、库进程级常驻；绑定失败时运行期回退 SL 函数体（可用于无后端环境的 stub / 降级探测）。所有绑定集中在 `Pipeline/RenderFFI.sl` 单一文件，是 SL 侧唯一允许出现 FFI 声明的地方。
  - **T2 系统方法（兜底）**：`.jsonc systemCalls[]` 声明 + `cvmFunction` C 符号绑定的窄接口（VM `CallSystemMethod` 分发）。仅用于 FFI 路径不好表达的场景：需要构造 SL 对象并压栈的返回（如着色器反射参数表）、迁移期的对象直传兼容（`Render.cmdDrawMesh`）。
  - **T3 字符串分发（淘汰）**：`SystemCallExternalFunction("Render.xxx", ...)` 变参 + 字符串名 + 装箱 object 的软分发——冻结不新增，存量按 04 §5 的映射表迁移，**M3 末从 Render 库删除**。
  - 所有后端 C 函数按「**≤ 6 参**（x64 ABI 上限）、**句柄(i64) + 标量 + ptr/utf8**、sig 用 FFI 短名」设计；超参场景一律**描述符打包**（`Memory.alloc` + `writeXxx` 组装结构，以 ptr 传入，见 04 §3.4）。

---

*本文档是文档集总纲。模块细节见 03，绑定契约与跨平台见 04，路线图与规范见 05。*
