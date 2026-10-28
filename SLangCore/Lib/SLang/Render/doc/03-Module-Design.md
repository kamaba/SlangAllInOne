# SLang 跨平台渲染引擎设计 · 03 模块详细设计

- 所属文档集：`Render/doc/`（01 总览 · 02 Unity 参考 · **03 模块详设** · 04 原生绑定与跨平台 · 05 路线图与规范 · 06 图像编解码）
- 版本：v0.4
- 本章回答「SLang 需要写什么」：逐模块给出职责 / 现状 / 需要新写或修改的类与方法（SL 签名）/ 绑定要点。
- 「新增」= 新文件或新类；「修改」= 在现有类上补；「修复」= 改 bug（清单见 05 §2）。
- 所有后端调用（文中「绑定：」小节）一律经 `Pipeline/RenderFFI.sl` 的 **T1 原生绑定**（`@DllStaticImport`，01 D8）；`slr_*` 符号、sig 与描述符布局的完整定义见 **04**，本章只列语义。

---

## 4.1 L1 平台窗口层（PlatformWindow.sl）

**职责**：窗口/原生表面（WSI）抽象，句柄透传，消息泵，事件查询。

**现状**：PlatformWindow/Win32Window/X11Window/MobileWindow 已有；Wayland 缺实现类；事件（键盘/鼠标）没有出口——渲染引擎窗口层只保证「活着/尺寸/DPI」。

**需要写**：

```sl
# 1) 修改 PlatformWindow：补事件查询（渲染引擎不消费输入语义，只透传）
public class PlatformWindow
{
    ...
    # 每帧 pump 后可查询；事件由宿主解释（本引擎不做输入系统）
    public Int32 pollEventCount()
    public WindowEvent getEvent( Int32 index )     # WindowEvent: Resized/Close/Minimized...
    public get bool shouldClose()
    public void getFramebufferSize() # 返回实际可绘制尺寸（高 DPI 下 != 窗口尺寸）
}

# 2) 新增 WaylandWindow extends PlatformWindow（占位：wl_surface 句柄透传）
# 3) 修改 Win32Window：resize 事件后同步 clientWidth/Height 到 width/height
# 4) Web 窗口（EWindowSystem.Web，nativeHandle = canvas 句柄）：
#    上下文协商由后端按所选后端完成，SL 侧只透传 canvas 句柄
#      WebGPU      -> canvas.getContext("webgpu")  + navigator.gpu.requestAdapter
#      WebGL2/1    -> canvas.getContext("webgl2") / "webgl"
#      Canvas2D兜底 -> canvas.getContext("2d")     # Software 光栅的呈现目标（D7）
```

**绑定**：`slr_window_create / slr_window_destroy / slr_window_resize / slr_window_set_title / slr_window_set_fullscreen / slr_window_pump / slr_window_poll_event / slr_window_framebuffer_size` 及 `slr_win32_* / slr_wl_* / slr_surface_*` 平台特化族（04 §4.1）。

### 4.2 L1 设备层（GfxBackend.sl / GfxDevice.sl）

**职责**：后端枚举与选择、能力查询、逻辑设备生命周期、三队列、描述符堆、交换链、帧节拍。

**现状**：结构齐全。问题：D3D11 也建描述符堆（D3D11 无此概念，应走 C 层模拟）；`GfxCapabilities.query(desc)` 只传了 backend，拿不到设备名；初始化把 `SwapChain` 的 back buffer 用普通 `createTexture` 伪造；全部调用走 T3 字符串分发（待迁移）。

**需要写**：

```sl
# GfxBackend.sl 修改
public class GfxBackend
{
    ...
    # 探测结果缓存（一次进程一份，避免每帧绑定调用）
    public static Array<Int32> availableBackends()   # 已有，加缓存字段
    public static GfxCapabilities queryCapabilities( EGraphicsBackend chosen ) # 替换现 query
    # parseBackend 识别新增："webgpu" -> EGraphicsBackend.WebGPU；backendName 补 "WebGPU"
}

# 枚举与预设补充（GfxBackend.sl）
enum EGraphicsBackend { Unknown = 0, D3D11, D3D12, Vulkan, Metal, OpenGL, OpenGLES, WebGL, WebGPU, Software }
#   WebGPU 插在 WebGL 之后、Software 仍收尾；M0 冻结前一次性定序，04 的枚举值表同步
public class GfxDeviceDescriptor
{
    ...
    public static GfxDeviceDescriptor webGPU()      # 浏览器 WebGPU（adapter + canvas 上下文）
    public static GfxDeviceDescriptor webDefault()  # Web 降级链（D7）：WebGPU + fallbacks=[WebGL, Software]
}

# GfxDevice.sl 修改
public class GfxDevice
{
    ...
    # 统一初始化：设备创建收敛为单一绑定调用，backend 参数决定 C 层内部路径
    # （废弃按后端拆分的 Render.createDeviceD3D12/D3D11/Vulkan/... 多个入口）
    public bool initialize( GfxDeviceDescriptor desc )       # 修改：删 D3D11 的 createDescriptorHeaps
    #   -> RenderFFI.ffi_deviceCreate( backend, descPackPtr )   # T1，描述符打包见 04 §3.4
    # 新增 WebGPU 分支（D7）
    bool createWebGPU()     # 复用 ffi_deviceCreate( EGraphicsBackend.WebGPU, desc )
    #   - 交换链 = GPUCanvasConfiguration（后端实现），SL 侧 SwapChain 语义不变
    #   - Web 降级链直接复用 desc.fallbackBackends：webDefault() 设
    #     backend=WebGPU + fallbacks=[WebGL, Software]，selectBest 走现有机制
    #   - Software@Web 的 present 由后端转译为 Canvas 2D blit（slr_swapchain_present 内部）
    # 交换链 back buffer 改由后端注册（不再 SL 侧 createTexture 伪造）
    public GpuTexture currentBackBuffer()                    # 修改：slr_device_backbuffer_index 查询 + Registry 取
    # resize 联动：窗口事件 → swapchain.resize → 通知管线 onResize(w,h)
    public event( Int32 type, Int32 w, Int32 h ) onResize    # 或简单回调注册
}
```

**绑定**：`slr_backend_available / slr_backend_current_window_system / slr_caps_query / slr_device_create / slr_device_destroy / slr_device_wait_gpu / slr_device_present / slr_device_backbuffer_index / slr_gl_* 上下文族`（04 §4.2）。

### 4.3 L2 GPU 资源层（GpuResource.sl / GpuTexture.sl / 新增 ResourceRegistry.sl）

**职责**：显存资源（buffer/texture/sampler/view）、上传、状态跟踪、生命周期。

**现状**：GpuResource/GpuBuffer/VertexBuffer/IndexBuffer/ConstantBuffer/GpuTexture/View/Sampler 骨架已有。问题：`VertexBuffer.fromMesh` 没传数据；`ConstantBuffer.staging` 是 `Array<Float32>` 语义歧义（按 float 计数 OK，但要文档化 16 字节对齐规则）；无延迟删除；纹理上传只支持 CPU `Texture` 对象。

**需要写**：

```sl
# 1) 新增 ResourceRegistry.sl —— 全局句柄表 + 帧延迟删除
public class ResourceRegistry
{
    public static ResourceRegistry instance()
    public void register( GpuResource res )            # create 成功后自动登记
    public void destroyLater( GpuResource res )        # 入帧删除队列（frameLatency+1 帧）
    public void flush( Int64 completedFrame )          # endFrame 时调用，真正销毁到期资源
    public GpuTexture findTexture( Int64 handle )      # backbuffer 等后端注册资源反查
    public get Int32 liveResourceCount()               # 调试：泄漏检查
}

# 2) 修改 VertexBuffer / IndexBuffer：交错打包上传
public class VertexBuffer extends GpuBuffer
{
    # 新增：从 Mesh 打包（布局 = VertexInputLayout.standard，stride 48，与 PSO 一致）
    public static VertexBuffer fromMesh( Mesh mesh )
    #   - 逐顶点写 [pos(3f) normal(3f) tangent(4f) uv(2f)]，tangent 缺省 (1,0,0,1)
    #   - create() 后立即 uploadInterleaved(mesh)
}
public bool uploadInterleaved( Mesh mesh )             # GpuBuffer 新增：
    # 1) Mesh.interleave() 展开 -> Memory.alloc + Memory.writeF32 循环写入
    # 2) RenderFFI.ffi_bufferUpload( handle, ptr, sizeBytes )        # T1

# 3) 修改 ConstantBuffer：对齐辅助 + 原生内存刷新
public class ConstantBuffer extends GpuBuffer
{
    public Int32 alignFloatOffset( Int32 floatOffset, Int32 align16 )  # 16B 对齐工具
    # flush 重写：staging(Array<Float32>) -> 原生内存块 -> ffi_cbUpdate(handle, ptr, sizeBytes)
    # 布局规范见附录 B；平台 constantBufferOffsetAlignment 只影响堆内偏移，不影响 staging 布局
}

# 4) 修改 GpuTexture：
#    - ETextureUsage 增加 ResolveDest = 16（MSAA resolve 目标）
#    - formatBytesPerPixel 补 BC* 每像素块说明（BC 按块计，注释写清）
#    - uploadPixels 支持 mip；新增 uploadCompressed( bytes, size, format )（BC/ETC2/ASTC）
#    - 新增 GpuTextureView 支持 mipRange / cube face（字段已有，确保 create 透传）
```

**绑定**：`slr_buffer_create / slr_buffer_destroy / slr_buffer_upload / slr_cb_update / slr_texture_create / slr_texture_destroy / slr_texture_upload / slr_texture_generate_mips / slr_texture_view_create / slr_sampler_create / slr_resolve_texture`（04 §4.3）。

### 4.4 L2 着色器层（Hlsl.sl / HlslLibrary.sl / 新增 ShaderCache.sl）

**职责**：HLSL 源码管理、编译为 ShaderModule、反射参数、变体、缓存。

**现状**：`HlslLibrary` 已内置 Common/Lighting/Lit/Unlit/DepthOnly/Skybox/PostProcess 源码（拼接式 include）。**Bug**：各源码首行 `#include Common` 是非法 HLSL（DXC 会报错）——拼接已经做了，include 行必须删除（05 §2.1-#10）。`Shader.sl`（按名编译的轻量版）与 `Hlsl.sl` 双轨，按 D2 统一。`ShaderModule.compile` 期望后端返回 `ShaderModule` 对象——跨绑定传 SL 对象不可靠，改为返回句柄 + 参数表写出。

**需要写**：

```sl
# 1) 修改 Hlsl.sl
public class ShaderModule
{
    public Int64 handle                       # 后端句柄（slr_shader_compile 返回，0 = 失败）
    public bool isValid
    # compile 改为：T1 绑定返回 i64 句柄；参数反射由 slr_shader_reflect 写出到原生内存，
    # SL 侧读回组装 Array<ShaderParameter>
}
public class HlslShader
{
    ...
    public Array<string> keywords             # 变体：_ADDITIONAL_LIGHTS / _SHADOW_CASCADES ...
    public bool enableKeyword( string kw )
    public bool disableKeyword( string kw )
    public string variantKey()                # 排序后的 keyword 串，做 PSO 缓存键成分
    # setFloat/setMatrix... 按 D2 全部删除，改由管线写 ConstantBuffer
}

# 2) 新增 ShaderCache.sl
public class ShaderCache
{
    public static ShaderCache instance()
    # key = hash(source + entry + target + variantKey)
    public ShaderModule getOrCompile( string name, string source, string entry,
                                      string target, EShaderStage stage, Array<string> keywords )
    public void clear()                       # 设备丢失/热重载时
    public get Int32 cacheHitCount()          # 调试
}

# 3) 扩展 HlslLibrary（附录 C 有完整清单）：
#    - common()：UnityLighting 扩展为定长附加光数组（见附录 B）
#    - 新增 cascadeShadowSampling()：级联选择 + PCF 3x3
#    - 新增 blitShader()：纯拷贝（FinalBlit 用，sRGB 转换注意）
#    - 新增 bloomDownsample()/bloomUpsample()：后处理链（v1.1）
#    - 新增 fxaaShader()（v1.1）
#    - 所有源码删除非法 "#include Common" 行（拼接由 litShader() 等工厂完成）
```

**绑定**：`slr_shader_compile / slr_shader_reflect / slr_shader_destroy`（04 §4.4）。源码以 `utf8` 直传（FFI 原生支持字符串）。

### 4.5 L3 状态与绑定层（PipelineState.sl / RootSignature.sl）

**职责**：把「着色器 + 固定功能状态」烘成不可变对象（PSO），声明资源绑定布局（RootSignature / DescriptorSet）。

**现状**：枚举与类齐全。**Bug**：`EDescriptorType` 缺 `RTV`/`DSV`，而 `GfxDevice.createDescriptorHeaps` 已在使用（05 §2.1-#1）。`DescriptorSet` 槽位固定 8/8/4/4 且 `growInt` 越界静默丢弃。

**需要写**：

```sl
# 1) 修复 RootSignature.sl
enum EDescriptorType { CBV = 0, SRV, UAV, Sampler, RTV, DSV }   # 补 RTV/DSV

# 2) 修改 DescriptorSet：越界告警 + bindless 预留
public void setTexture( Int32 slot, GpuTextureView view )
    # slot >= 容量时：走 Console.log 告警（而不是静默丢弃），预留 grow
public bool apply()   # 保持：把 CPU 绑定刷进堆（slr_descriptor_set_apply，打包见 04）

# 3) 修改 GraphicsPipelineState：
#    - 新增 depthBias 单位说明（DX12 原生 / GL 需后端换算）
#    - 新增 alphaToCoverage（将来植被/粒子用）
#    - 新增 psoKey()：返回字符串键，供 PSO 缓存（D3）
# 4) 新增 PsoCache（放 PipelineState.sl 尾部或独立）
public class PsoCache
{
    public GraphicsPipelineState getOrCreate( string key, ... )
    # key = shaderName|variant|blend|raster|depth|rtFormats|msaa|topology
}
```

**绑定**：`slr_pso_graphics_create / slr_pso_compute_create / slr_pso_destroy / slr_root_signature_create / slr_root_signature_destroy / slr_heap_create / slr_descriptor_set_apply`（04 §4.5）。PSO 与根签名的创建参数多，一律描述符打包（04 §3.4）。

### 4.6 L3 渲染目标层（RenderTarget.sl）

**职责**：RT 描述/标识/绑定（MRT）、池化复用、MSAA resolve、帧安全回收。

**现状**：Descriptor/Identifier/Binding/Pool 已有。问题：池匹配键只有 w/h/format（漏 msaa/usage/depth）；`getDepth` 不池化；没有「GPU 在用」保护（本帧刚用完的 RT 立刻复用，显式 API 下必须等 fence）。

**需要写**：

```sl
# 修改 RenderTextureDescriptor：成为完整池化键
public class RenderTextureDescriptor
{
    ...
    public string poolKey()      # name|w|h|colorFmt|depthFmt|msaa|usage
}

# 修改 RenderTargetPool
public class RenderTargetPool
{
    public RenderTargetIdentifier get( RenderTextureDescriptor desc )   # 用 poolKey 匹配
    public GpuTexture getDepth( RenderTextureDescriptor desc )          # 也走池（深度池独立）
    # 帧安全：帧末 releaseAll 时记录 frameIndex，free 列表里的纹理
    # 未超过 (当前帧 - frameLatency) 不参与匹配 —— 防止 GPU 仍在写
    public void releaseAll( Int64 currentFrame )
}

# 修改 RenderTargetBinding：无变化（结构 OK）

# MSAA resolve：opaque pass 末尾执行
#   cmd.resolveTexture( msaaColor, resolvedColor )   # 4.7 实现，绑定 slr_resolve_texture
```

### 4.7 L3 命令层（CommandBuffer.sl / CommandQueue.sl）

**职责**：命令录制/提交/同步/交换链（按 D1 真录制模型重写）。

**现状**：`CommandBuffer` 直通 T3 字符串分发、`handle=0`、池无意义；`CommandQueue`/`Fence`/`CommandAllocator`/`CommandList`/`SwapChain` 齐全但 `SwapChain.currentIndex` 由 SL 取模，与后端不同步。

**需要写（CommandBuffer.sl 重写核心）**：

```sl
enum ECommandOpcode
{
    Nop = 0, SetViewport, SetScissor, SetRenderTargets, Clear,
    SetPipelineState, SetComputePipelineState, SetRootSignature, SetDescriptorSet,
    SetVertexBuffer, SetIndexBuffer, SetConstantBuffer, SetTexture, SetSampler,
    Draw, DrawIndexed, DrawProcedural, DrawMesh, Dispatch,
    ResourceBarrier, CopyBuffer, CopyTexture, ResolveTexture,
    BeginEvent, EndEvent
}

public class CommandBuffer
{
    Array<Int32> _opcodes
    Array<Int64> _args        # 参数扁平展开（句柄/整数直接放）
    Array<Float32> _floats    # 浮点参数区（视口/清屏色等）
    public Int64 handle       # 后端命令列表句柄（slr_cmd_begin 分配）
    public bool isRecording

    public void begin()                       # 清数组 + RenderFFI.ffi_cmdBegin(name) 分配列表
    public void end()                         # RenderFFI.ffi_cmdEnd(handle)
    # 每个 set/draw 方法：push opcode + args，不再直接调后端
    public void drawIndexed( Int32 indexCount, Int32 instanceCount,
                             Int32 startIndex, Int32 baseVertex )
    public void resolveTexture( GpuTexture msaaSrc, GpuTexture dst )   # 新增
    ...
    public get int commandCount
}

public class CommandQueue
{
    public void execute( CommandBuffer cb )
    # 命令流打包提交（T1）：
    # 1) Memory.alloc 一块原生内存，按布局写入（布局定义见 04 §3.6）：
    #    [header: magic/version/commandCount/argOffset/floatOffset]
    #    [opcodes: commandCount x i32][args: i64 x n][floats: f32 x m]
    # 2) RenderFFI.ffi_cmdExecuteStream( queueHandle, cb.handle, ptr, commandCount )
}

# 修改 SwapChain
public class SwapChain
{
    public void present()
    # currentIndex 改为 present 前 RenderFFI.ffi_device_backbuffer_index 查询
}
```

> 实现备注：矩阵等复杂参数不进命令流，统一通过 ConstantBuffer 承载（D2），命令里只出现槽位与句柄。`DrawMesh`（对象直传）保留为兼容 opcode，仅迁移期 T2 使用，逐步淘汰。

**绑定**：`slr_cmd_begin / slr_cmd_end / slr_cmd_execute_stream / slr_queue_create / slr_queue_destroy / slr_queue_wait / slr_queue_signal / slr_queue_wait_idle / slr_fence_create / slr_fence_value / slr_fence_wait / slr_fence_destroy / slr_allocator_* / slr_cmd_list_* / slr_swapchain_*`（04 §4.6）。

### 4.8 L4 剔除与上下文（ScriptableRenderContext.sl）

**职责**：视锥剔除、可见集分类排序、命令缓冲调度、绘制分发（RendererList）。

**现状**：CullingParameters/VisibleRenderer/CullingResults/ScriptableRenderContext 已有。**Bug**：`drawRenderers` 拿到 `filterByQueue` 的副本数组后没有排序（05 §2.1-#3）；`cull()` 未按 `cullingMask` 过滤 layer；光没有剔除（所有灯全进常量）。

**需要写**：

```sl
# 修改 CullingParameters：补 layerMask 生效（isVisible 判定时 r.layer & cullingMask）
# 修改 CullingResults：
public class CullingResults
{
    ...
    # 修正：按队列过滤并【返回前就地排序】
    public Array<VisibleRenderer> filterByQueue( Int32 minQueue, Int32 maxQueue, bool frontToBack )
    public void collectVisibleLights( Array<Light> allLights, Int32 maxPixelLightCount )
    #   方向光取主光（intensity 最大），其余点/聚光按距离裁剪取前 N
    #   输出：mainLight + Array<Light> additionalLights
}

# 修改 ScriptableRenderContext：
public class ScriptableRenderContext
{
    ...
    # 对齐 Unity 的 DrawRenderers(rl, shaderTagId, sortingSettings)
    public void drawRenderers( CullingResults results, Int32 minQueue, Int32 maxQueue,
                               Material overrideMaterial, bool frontToBack )
    #   1) filterByQueue(min,max,frontToBack)
    #   2) 逐个：D3 的 PSO 缓存查/建 -> cmd.setPipelineState
    #      -> 写 UnityPerDraw CB（localToWorld）-> cmd.setConstantBuffer(b1)
    #      -> 写 UnityPerMaterial CB（材质参数） -> cmd.setConstantBuffer(b2)
    #      -> 绑纹理 t0 -> cmd.setVertexBuffer/setIndexBuffer
    #      -> cmd.drawIndexed(mesh.indexCount, 1, 0, 0)
    #   overrideMaterial 非空时替换材质（深度/阴影通道用）
}
```

本模块为纯 SL 逻辑（剔除/排序/分发），无新增后端绑定。

### 4.9 L4 Pass 体系（RenderPass.sl）

**职责**：一次渲染步骤的封装：声明输入输出 RT、录制命令；管线负责排序与执行。

**现状**：基类 + Clear/ShadowCaster/DepthPrepass/DrawObjects/Skybox/PostProcess 已有。缺失：FinalBlitPass、MSAA resolve 步骤、Pass 输入输出声明（现为散字段）。

**需要写**：

```sl
# 修改 RenderPass 基类：统一 IO 声明（对齐 Unity Configure）
public class RenderPass
{
    ...
    public virtual void configure( RenderTargetIdentifier color,
                                   RenderTargetIdentifier depth,
                                   bool clearC, bool clearD, Color clearCol )
    # 执行协议固定为：begin(事件标记) -> render(ctx) -> end
}

# Pass 清单（7 个内建 + 1 个新增）：
#   ClearPass             清颜色/深度                 [已有]
#   ShadowCasterPass      主光阴影：正交 VP + 深度材质  [重写]
#     - 需要新增 LightMatrixCalculator：方向光正交包围盒（视锥聚合 bounds + texel snapping）
#     - render()：写 unity_MatrixLP 到 UnityShadow CB -> 深度材质画全部投影物
#   DepthPrepass          深度预通道                   [已有，改走统一 drawRenderers]
#   DrawObjectsPass       队列区间绘制（不透明/透明两实例）[修改：排序方向参数化]
#   SkyboxPass            天空盒（全屏三角 + cubemap）  [修改：走 fullscreen VS]
#   PostProcessPass       后处理链                     [扩展：多效果串联]
#   FinalBlitPass         HDR -> backbuffer（含 sRGB） [新增]
#     - configure(backbuffer, null) + blitShader + _BlitTexture
#   ResolvePass           MSAA resolve（可并入 opaque pass 末尾）[新增，v1.1]

# 修改 RenderPassList：sortByEvent 已有；新增 insert(pass, afterEvent) 便于自定义 Pass 插队
```

### 4.10 L5 管线层（RenderPipeline.sl / UniversalRenderPipeline.sl）

**职责**：资产配置 → 管线实例 → 每帧相机循环 → Pass 编排 → 提交。

**现状**：三级结构已有；**URP.render() 的问题**：`buildPasses()` 组装了 Pass 列表但 `render()` 里又手写了一遍顺序（renderShadows/renderColor/renderPost），Pass 列表实际未被执行（05 §2.1-#2）。

**需要写**：

```sl
# 修改 RenderPipeline 基类
public class RenderPipeline
{
    ...
    # 相机循环 + 事件（对齐 Unity RenderPipelineManager 的 begin/end 回调）
    public virtual void render( ScriptableRenderContext ctx, Array<Camera> cameras )
    #   按 camera.depth 排序 -> 逐相机 renderSingleCamera(ctx, cam, _passes)
    public virtual void onResize( Int32 w, Int32 h )    # 窗口变化时重建 RT
}

# 重写 UniversalRenderPipeline.render（Pass 驱动，单一事实来源）
public class UniversalRenderPipeline extends RenderPipeline
{
    ...
    override void render( ScriptableRenderContext ctx, Camera camera )
    {
        # 1) CullingParameters.fromCamera -> ctx.cull（含 layerMask/光源收集）
        # 2) 帧常量：UnityPerFrame CB（VP、相机位置、_Time、_ScreenParams）
        # 3) 光常量：UnityLighting CB（主光 + 附加光数组）
        # 4) setup 各 Pass（注入 cullingResults/camera/RT id）
        # 5) _passes.sortByEvent() 后逐个 begin/render/end —— 不再手写顺序
        # 6) ctx.submit()
    }

    # 资产字段补齐（UniversalRenderPipelineAsset）：
    #   msaaSamples / renderScale / hdr / shadowDistance / cascadeCount
    #   additionalLightsPerObject(默认 4) / supportsHDR
    # RT 管理（D6）：
    #   _cameraColorRT = rtPool.get(RenderTextureDescriptor.hdr(w*scale, h*scale))
    #   _cameraDepthRT = rtPool.getDepth(...)
    #   MSAA>1：颜色 RT 带 msaa -> opaque 后 resolve -> 透明/post 用 resolve 结果
    #   FinalBlitPass 收尾
}
```

**URP 单相机目标流程（v1 全景）**：

```
Cull -> [ShadowCaster(主方向光)] -> [DepthPrepass(可选)] -> [Opaque]
     -> [Resolve(若 MSAA)] -> [Skybox] -> [Transparent]
     -> [PostProcess(可选)] -> [FinalBlit -> backbuffer]
```

### 4.11 L0/L2 上层资源与组件（Mesh/Material/Texture/Vertex/Renderer/Camera/Light/Config）

**职责**：宿主友好的数据层，与 GPU 资源层的桥。

**需要写**：

```sl
# Mesh.sl：新增 GPU 脚手架（D4）
public class Mesh
{
    ...
    public MeshGpuData gpu            # 新增内部类：vb/ib/layout/version/isDirty
    public Int32 version              # setVertices/setTriangles 时 +1
    public Array<Float32> interleave() # 按 standard 布局(48B)展开，供上传
}

# Material.sl：对齐 D3
public class Material
{
    ...
    public Int32 renderQueue          # 显式队列值（默认按 transparent 推 3000/2000）
    public Array<string> keywords
    public ConstantBuffer materialCb  # UnityPerMaterial：_BaseColor/_Emission/_SurfaceParams
    public GpuTexture getMainGpuTexture()   # mainTexture(CPU) 对应的 GPU 纹理（上传后）
    public void markDirty()
}

# Texture.sl：加 GPU 桥
public class Texture
{
    ...
    public GpuTexture gpu             # 懒上传：首次被材质使用时建 GpuTexture 并 uploadPixels
    public void uploadToGpu()         # idempotent；CPU 侧修改后需手动 invalidate
    # uploadToGpu 实现走 06 §6.1 的 A 路径（slr_image_decode_file 原生像素块
    # 直转 slr_texture_upload，像素不过 SL 数组）；ImageBuffer 来源则打包写原生内存上传
}

# Camera.sl：剔除口径统一
#   - worldToViewportPoint 目前用 transformPoint（w 除法）OK；补 pixelRect/viewport(0..1)
#   - aspect 由管线每帧按目标 RT 尺寸刷新（管线写入，禁止宿主手填错值）

# Light.sl：数据已有；新增打包
public class Light
{
    ...
    public Float32_4 packPositionType()    # xyz=位置/方向, w=type
    public Float32_4 packColorAttenRange() # rgb=color*intensity, w=range
}

# Config.sl：字段已有，补 fromJsonc（读 global data）便于 Render.jsonc 驱动
# Renderer.sl：render() 改为「填 VisibleRenderer 后交给管线」，不再直接 Render.drawMesh
```

### 4.12 兼容层（Render.sl）

**职责**：给旧脚本一个最小 API（initialize/beginFrame/drawMesh/endFrame/present），内部全部转发到新体系，避免双实现。

```sl
# Render.sl 修改：
public static bool initialize( Config config )
#   = GfxBackend.createDevice(GfxDeviceDescriptor.fromConfig(config))
#     + RenderPipelineManager.instance().initialize(UniversalRenderPipelineAsset 默认资产)
public static void beginFrame( Color c )  = manager.beginFrame()
public static bool drawMesh(...)          # 转发：组装 VisibleRenderer 注入管线（同步帧内缓存列表）
public static void endFrame() / present() = manager.endFrame() / manager.present()
```

迁移说明：本层现存的 `SystemCallExternalFunction` 调用（Render.initialize/beginFrame/drawMesh/...）按 04 §5 映射表改为 `RenderFFI` 的 T1 绑定或内部转发；对外 API 签名不变。

### 4.13 配套与范围外

| 项 | 处置 |
|---|---|
| `Image/`（Png/Jpeg/Webp/Svg 等 8 个 .sl） | 保留并增强。定位为「纹理数据源 + 图像读写子系统」：探测/容器模型纯 SL，编解码走 T1/T2 绑定（`slr_image_*`/`slr_svg_*`/`slr_blob_*`），纹理加载零拷贝直传 GPU。**完整独立设计见 06**（含 Render.jsonc 登记任务、存量 18 个 `Image.*` T3 调用迁移表、SVG 光栅化与图标缓存、截图编码链路） |
| `Audio/` | **建议迁出**至 `SLang/Audio` 库。渲染引擎不发声；留在 Render 里会让依赖图变脏（Render.jsonc 也无需编译它们，当前未列入 compileFiles，保持） |
| `Behaviour/UIBehaviour/RectTransform` | 标注为「宿主引擎组件适配层」：渲染引擎不解释它们；v1.1 的 2D/Canvas 渲染路径只读取 RectTransform 的矩形数据 |
| `cvm_render_lib/*.c` | 定位调整（04 §3.5）：**T2 兼容注册 + 对象→描述符打包器**——迁移期承载 `Render.cmdDrawMesh` 等对象直传的 T2 系统方法；终态仅保留描述符打包辅助 |
| `Shader.sl` 旧类 | 降级为兼容层内部使用（D2），不再新增能力 |

---

## 附录 B cbuffer 布局规范（HLSL 侧 + SL 写入侧）

```
register(b0) UnityPerFrame   每帧一次（管线写）
    float4x4 unity_MatrixVP;        // 64B
    float4x4 unity_MatrixV;         // 64B
    float4   _TimeParams;           // t/ct/st 常见组合
    float3   _WorldSpaceCameraPos; + pad
    float4   _ScreenParams;         // w,h,1+1/w,1+1/h
register(b1) UnityPerDraw   每个 drawcall（drawRenderers 写）
    float4x4 unity_ObjectToWorld;
    float4x4 unity_WorldToObject;   // 法线变换，暂可用 3x3 逆代替，先留全矩阵
register(b2) UnityPerMaterial 每材质（Material.materialCb flush）
    float4 _BaseColor;
    float4 _EmissionColor;
    float4 _SurfaceParams;          // x=metallic y=smoothness z=alphaClip w=__
register(b3) UnityLighting  每帧（管线写）
    float4 _MainLightPosition;      // w=0 方向光
    float4 _MainLightColor;         // a=强度
    float4 _AmbientColor;
    float4 _AdditionalLightsCount;  // x=数量
    float4 _AdditionalLightsPos[8];     // xyz + w=type
    float4 _AdditionalLightsColor[8];   // rgb + a=range
register(b4) UnityShadow    阴影 pass/采样
    float4x4 unity_MatrixLP;
    float4   _ShadowParams;         // x=strength y=bias z=normalBias w=cascadeCount
    float4x4 unity_WorldToCascade[4];   // M4
    float4   _CascadeSplits;            // M4
```

SL 写入规则：所有 float4 成员按 16B 对齐写 staging；矩阵 16 float 连续；数组定长 8（v1 附加光上限，与 asset.additionalLightsPerObject 一致）；`constantBufferOffsetAlignment`（DX12=256）只影响**堆内偏移**，不影响 staging 布局。staging 经 `Memory.writeF32` 写入原生内存后由 `slr_cb_update` 刷给后端（04 §3.4）。

## 附录 C 内置着色器清单（HlslLibrary 目标态）

| 名字 | 阶段 | 用途 | 关键点 |
|---|---|---|---|
| Hidden/SL/Lit | VS+PS | PBR 不透明 | GGX+Schlick+Smith；keyword：_ADDITIONAL_LIGHTS、_SHADOWS |
| Hidden/SL/Unlit | VS+PS | 无光照 | 调试/占位 |
| Hidden/SL/DepthOnly | VS+PS | 深度预通道/阴影投射 | PS 仅 AlphaTest clip；keyword：_ALPHATEST_ON |
| Hidden/SL/Skybox | VS+PS | 天空盒 | SV_VertexID 全屏三角 + TextureCube |
| Hidden/SL/Blit | VS+PS | FinalBlit | 纯采样 + sRGB 转换 |
| Hidden/SL/PostProcess | VS+PS | Tonemap+Vignette | ACES 近似（已有）；v1.1 拆 Bloom/FXAA |
| Hidden/SL/ShadowSample（库函数） | — | PCF 采样 | 3x3 PCF + 级联选择（M4） |
