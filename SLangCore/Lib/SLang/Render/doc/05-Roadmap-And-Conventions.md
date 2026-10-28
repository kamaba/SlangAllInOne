# SLang 跨平台渲染引擎设计 · 05 路线图与规范

- 所属文档集：`Render/doc/`（01 总览 · 02 Unity 参考 · 03 模块详设 · 04 原生绑定与跨平台 · **05 路线图与规范** · 06 图像编解码）
- 版本：v0.4

---

## 1. 实现路线图

> 每个里程碑有明确验收标准；slr_ 绑定契约（04 §4）在 M0 冻结 v1，之后只增不改。

### M0 设计冻结（本文档集评审）
- 产出：文档集定稿；`Render.jsonc` 登记 `dllImports`（SLangRender 静态名）与新文件；后端侧 `slr_types.h` 枚举值表单点定义（与 SL enum 一致）；描述符布局表（04 §3.4 附录）冻结。
- 验收：评审通过；第 2 章问题清单确认归属里程碑。

### M1 首个三角形（Software 或 OpenGL 后端）+ T1 绑定打通
- 写：`RenderFFI.sl`（窗口/设备/呈现/清屏/基础命令流符号）；PlatformWindow 事件补齐；CommandBuffer 真录制（D1）+ 命令流 ptr 打包；GfxDevice 初始化收敛为 `slr_device_create` 单入口。
- 迁移：窗口/设备/呈现族的存量 `SystemCallExternalFunction` 调用清零（04 §5 批次一）。
- 验收：`PipelineDemo` 在 Win32+OpenGL 打开窗口，画出一个带顶点色的三角形，ESC/关闭正常退出，无句柄泄漏（ResourceRegistry liveResourceCount==0）；**装配期绑定全部命中（无 fallback 回退日志），渲染路径零 T3 调用**。

### M2 资源系统 + 图像编解码
- 写：ResourceRegistry；Mesh.interleave + VertexBuffer.fromMesh 真上传（描述符打包 + `slr_buffer_upload`）；Texture.gpu 懒上传；ConstantBuffer 对齐工具 + `slr_cb_update` 刷新；HlslLibrary 去掉非法 include、ShaderModule 句柄化；ShaderCache。
- **图像编解码（06 全量）**：`Render.jsonc` 登记 `Image/` 8 文件 + Image namespace struct；T1 `slr_image_*/slr_svg_*/slr_blob_*` 与 T2 `RenderImage*` 四接口铺设（RenderFFI.sl + cvm_render_lib）；Texture.uploadToGpu 接 A 路径（零拷贝）；SVG 文档句柄 + SvgCache（v1.1）；截图编码链路（readback → PNG blob → 落盘）。
- **前置任务（06 §3.3）**：VM 侧 `SystemPtrWriteByteArray / SystemPtrReadByteArray` 批量互转（大图字节过 FFI 的前提）。
- 迁移：资源/着色器/状态族 + `Image.*` 18 个调用点 T3 清零（04 §5 批次二 + 06 §5.6）。
- 验收：Mesh.cube() + 棋盘纹理 + Unlit 材质渲染正确；二次运行 shader 命中缓存；修改 mesh 顶点后画面更新；**06 §9 的 5 条图像验收全过（PNG roundtrip 逐字节相等、JPEG PSNR ≥ 40dB、A 路径零拷贝、SVG 四档尺寸光栅化、无 DLL 降级不崩）**。

### M3 URP 骨架（Pass 驱动）+ T3 删除
- 写：URP.render 重写为 Pass 列表执行；drawRenderers 排序修复 + PSO 缓存（D3）+ 三 CBUFFER 路径；RenderTargetPool 帧安全；多相机 depth 排序；Render.sl 兼容层转发。
- 迁移：命令流切换（逐命令 T3 → `slr_cmd_execute_stream`）+ **T3 全量删除**（04 §5 批次三）。
- 验收：两个相机（不同 viewport/depth）正确渲染；不透明前→后、透明后→前顺序经 RenderDoc 命令流验证；旧 `Render.drawMesh` 脚本不改动即可跑；**Render 库 .sl 源码中 `SystemCallExternalFunction` 出现次数 = 0**。

### M4 光照与阴影
- 写：LightMatrixCalculator（正交光 VP + texel snap）；ShadowCasterPass 正确化；UnityLighting CB 主光+附加光数组；DepthOnly 材质 AlphaTest；级联(1/2/4) + PCF 软阴影（HlslLibrary 扩展）。
- 验收：场景 1 主光 + 4 点光：阴影无 acne/peter-panning；级联切换无接缝；点光衰减与范围截断正确。

### M5 HDR 与后处理
- 写：HDR 中间 RT 链路（D6）；PostProcessPass 多效果（Tonemap/Vignette/Bloom/FXAA）；FinalBlitPass（sRGB）；MSAA RT + `slr_resolve_texture`；GPU 时间戳（`slr_gpu_timestamp_*`）。
- 验收：HDR→ACES 无带状色阶；MSAA 4x 边缘锯齿改善且 resolve 后可采样；帧时间统计可用。

### M6 显式 API、移动端与 Web
- 写：D3D12 后端打通（描述符/屏障/fence 全语义）；Vulkan 后端；Metal/GLES 后端；Web 三级链（WebGPU → WebGL2 → Canvas2D，D7）；能力降级表生效。
- **前置任务**：VM FFI 层扩展 arm64 ABI 派发（`gen_sl_ffi_call.py` 增加目标），否则移动端 T1 不可用（降级方案见 04 §6）。
- 验收：同一 demo 在 Win(D3D12)/Linux(Vulkan)/Mac(Metal)/Android(GLES)/浏览器(WebGPU 与 WebGL2) 渲染一致（截图哈希对比，容差内）；禁用硬件加速的浏览器中 Canvas2D 兜底可出图。

### M7 演进（不承诺）
RenderGraph 资源图自动屏障、GPU driven culling（indirect draw + compute 剔除）、SRP Batcher 式合批、相机栈（Base/Overlay）、2D/Sprite 专用管线、Shader 磁盘缓存、Web Worker + OffscreenCanvas 渲染线程。

---

## 2. 现有代码问题清单

### 2.1 Bug 级（M1-M3 内修复）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 1 | RootSignature.sl `EDescriptorType` | 缺 `RTV`/`DSV`，GfxDevice.createDescriptorHeaps 已在使用（枚举不存在，编译应报错或隐式 0） | 补枚举（03 §4.5） |
| 2 | UniversalRenderPipeline.render | buildPasses 组装的 Pass 列表未被执行，render 内手写重复流程；基类 renderSingleCamera 无人调用 | Pass 驱动重写（03 §4.10） |
| 3 | ScriptableRenderContext.drawRenderers | filterByQueue 返回副本后未排序；sortFrontToBack 排的是 _renderers 原数组，对绘制无效 | filter 参数化排序（03 §4.8） |
| 4 | CommandBuffer | handle 恒 0；每个方法直通 T3 字符串分发；CommandBufferPool 池化无意义 | D1 真录制（03 §4.7） |
| 5 | SwapChain.present | currentIndex 由 SL 取模推导，与后端实际 backbuffer index 不同步 | `slr_device_backbuffer_index` 查询（03 §4.7） |
| 6 | SwapChain.create | SL 侧 createTexture 伪造 back buffer，句柄与真实交换链缓冲无关 | 后端注册 + Registry 反查（03 §4.2） |
| 7 | VertexBuffer.fromMesh | 只按 32B stride 建空 buffer：数据未上传，且 stride 与 VertexInputLayout.standard 的 48B 不一致 | interleave 48B + 真上传（03 §4.11） |
| 8 | GfxDevice.createD3D11 | D3D11 无描述符堆却调 createDescriptorHeaps | 删除该分支调用（03 §4.2） |
| 9 | GfxCapabilities.query | 只传 desc.backend，deviceName/vendor 等永远空 | `slr_caps_query` 整块写出（03 §4.2） |
| 10 | HlslLibrary 各源码 | 源码首行 `#include Common` 非法 HLSL，DXC 编译必失败 | 删除该行；拼接由工厂完成（03 §4.4） |
| 11 | RenderPass.begin/end | ctx.cmd 可能为 null（beginCommandBuffer 未先调）时 NPE 风险 | render 协议保证或判空 |
| 12 | Camera.aspect | 无任何代码维护它，投影矩阵用错误宽高比 | 管线每帧按 RT 尺寸写入（03 §4.11） |

### 2.2 设计级（随对应里程碑处理）

- DescriptorSet.growInt 越界静默丢弃 → 告警 + 预留扩容（03 §4.5）。
- RenderTargetPool 匹配键不含 msaa/usage；getDepth 不池化；无帧延迟回收（03 §4.6）。
- URP renderShadows 用相机 VP 冒充光 VP（注释已自认）→ LightMatrixCalculator（M4）。
- updateFrameConstants 走按名 setUniform（D2 要废弃的路径）→ UnityPerFrame CB（03 §4.10）。
- Material 与 PSO 无关联、每次 drawMesh 对象直传 → D3 PSO 缓存 + 槽位绑定（03 §4.8/4.11）。
- GpuTexture.formatBytesPerPixel 把 BC 块当单像素字节算，sizeBytes 严重失真 → 注释 + 按块计算（03 §4.3）。
- CullingParameters.cullingMask 定义了但 isVisible 未使用（03 §4.8）。
- RenderPipelineManager.initialize 在 device 为 null 时 instantiate 会失败且未报错（顺序耦合）→ 文档化调用序或自动 createDevice（03 §4.10）。
- **全部 `SystemCallExternalFunction("Render.xxx")` 调用（约 18 个文件、百余处）需按 04 §5 映射迁移到 RenderFFI.sl 的 T1/T2 绑定**，M3 末清零删除。
- **`Image/` 8 个 .sl 未登记 `Render.jsonc` 的 `compileFiles` 与 `struct` 段**（当前实际不参与编译）——M2 bring-up：登记文件 + 新增 `{ "namespace": "Image", "children": [...] }`（06 §2）。
- **`Image.*` 18 个 T3 调用点**（探测/编解码/SVG）按 06 §5.6 迁移：`jpegExif` 并入 `autoOrient` 选项、`webpFrames` 并入探测出参，其余映射 T1/T2。

---

## 3. SLang 语言注意事项与编码规范

> 编写/评审 .sl 时的硬约束（从现有代码沉淀）。

### 3.1 语言与风格

1. 返回用 `ret`，无 `return`；无 `for`，统一 `while i < n { ... i++ }`。
2. 构造重载链：`_init_(args) { this._init_(); ... }`，先跑无参版再覆写。
3. 类型转换：`if result is Int32 n` / `SystemConvertInt64/Float32/String`；枚举即 Int32，可直存 `Array<Int32>`。
4. 数组无 Append：增长靠「new 大一号 + while 拷贝」模式（见 CullingResults.add）。**性能敏感路径禁止每帧增长**：用固定容量 + used 游标（CommandBuffer 的 _opcodes 即此模式）。
5. 静态可变字段可用（RenderPipelineManager._instance），但注意多设备/热重载场景要提供 reset。
6. 成员命名避开小写关键字构造糖：`queue`/`range` 等已被 Light.lightRange 踩坑（注释里有说明）。
7. `get bool xxx` 属性语法可用；带参逻辑一律普通方法。
8. 注释 `#`；文件头写模块职责 + Unity 对应概念（现有风格，保持）。
9. 跨库引用：Render.jsonc `references` 已挂 Core/Math/Std；禁止反向依赖（Core 不得 import Render）。
10. 每个类登记进 Render.jsonc `struct.children`，新文件登记 `compileFiles.files` 且保持依赖顺序（jsonc 内注释已声明顺序即依赖顺序）。

### 3.2 FFI 绑定规范（D8 配套，硬约束）

11. **新增后端调用一律在 `Pipeline/RenderFFI.sl` 用 `@DllStaticImport` 声明**；其它 .sl 禁止出现 `SystemCallExternalFunction` / `SystemFFICallXxx` / FFI attribute。
12. sig 必须用 **FFI 短名**（`i32/i64/f32/f64/bool/ptr/utf8`）；返回 void 省略返回段（`"i64,i32"`），**禁止 `->void`**；含 `ptr` 的签名**必须手写 sig**（推导排除 Ptr）。
13. **每个绑定函数必须提供 fallback 体**：查询类返回 0/false、创建类返回 0 句柄、void 类空体——无后端 DLL 时引擎可继续走 Software 降级而不是崩溃。
14. `@DllStaticImport` 函数**不参与自动 inline**（调用点是装配期改写锚点）：保持一行转发形态，不要写逻辑；复杂逻辑放调用方。
15. FFI 参数 **≤ 6**；超限一律描述符打包（`Memory.alloc` + `writeXxx` → `ptr`，布局见 04 §3.4），禁止拆成多次调用绕过。
16. 大块数据（矩阵/cbuffer staging/命令流/像素）先写入原生内存再传 `ptr + size`；字符串用 `utf8` 直传。
17. FFI 目前仅 x64 ABI；arm64 移动端依赖 VM FFI 层扩展（M6 前置），扩展前移动端走 T2 包装（04 §6）。
18. `RenderFFI` 首帧调用前做一次绑定探测（任一符号 fallback 即置 `bindingOk=false` 并告警一次），避免「静默全零」误导排障。

### 3.3 HLSL 源码规范

19. 字符串拼接生成 HLSL 时统一 `"\n"` 结尾（HlslLibrary 现风格），避免行粘连。
20. 源码内**禁止** `#include`（非法，DXC 报错）——模块组合由 SL 侧工厂函数拼接完成（03 §4.4）。
21. cbuffer 布局严格遵循 03 附录 B；所有 float4 成员 16B 对齐；附加光数组定长 8。

---

## 4. 附录：术语表

| 术语 | 含义 |
|---|---|
| WSI | Window System Integration，窗口/表面层 |
| PSO | Pipeline State Object，管线状态对象 |
| CBUFFER | 常量缓冲（DX cbuffer / Vulkan UBO） |
| RT | RenderTarget 渲染目标 |
| MRT | Multiple Render Targets，一次绑定多颜色附件 |
| Resolve | MSAA 多重采样纹理 → 可采样单采样纹理的解析 |
| Z-Prepass | 深度预通道，提前建立 Z 减少着色开销 |
| Backbuffer | 交换链呈现缓冲 |
| FrameLatency | CPU 领先 GPU 的帧数（默认 2） |
| Gribb-Hartmann | 从 VP 矩阵提取 6 裁剪平面的经典方法 |
| SRP | Scriptable Render Pipeline（Unity 可编程管线） |
| URP | Unity 通用渲染管线（本引擎 UniversalRenderPipeline 的参照） |
| WebGPU | W3C 标准的 Web 图形 API，浏览器中的现代显式管线形态（对应桌面 Vulkan/D3D12 一档） |
| WGSL | WebGPU Shading Language，WebGPU 着色语言 |
| Canvas 2D | H5 Canvas 2D 上下文；本引擎中作为 Software 光栅在 Web 的呈现目标（最终兜底） |
| OffscreenCanvas | 可脱离 DOM / 在 Worker 中使用的 Canvas（M7 演进项） |
| T1 | 原生 FFI 声明式绑定（`@DllStaticImport`/`@DllImport`，装配期绑定、零 SL 帧） |
| T2 | 系统方法 SystemMethodCall（`.jsonc systemCalls[]` + `cvmFunction` 符号绑定），对象互操作/变参兜底 |
| T3 | `SystemCallExternalFunction("Render.xxx")` 字符串软分发（冻结存量，M3 删除） |
| sig | FFI 签名字符串（`"i32,ptr->bool"` 形式，FFI 短名） |
| 描述符打包 | 多参数封装进原生内存块以 `ptr` 传递的模式（04 §3.4） |
| 命令流 | CommandBuffer 录制的 opcode/args/floats 三段式原生内存块，`slr_cmd_execute_stream` 整包提交（04 §3.6） |
| fallback 体 | `@DllStaticImport` 绑定失败时回退执行的 SL 函数体 |
| `slr_` | 渲染后端 C 符号统一前缀（SLang Render） |
| blob | 原生字节块句柄（`slr_blob_ptr/size/save/free`），承载编码产物等跨 FFI 字节流（06 §3.2） |
| A/B/C 路径 | 图像数据三条通路：A=文件→原生像素→GPU 零拷贝；B=T2 构造 ImageBuffer；C=ImageBuffer→编码→blob→落盘（06 §3.1） |
| 光栅化 | 矢量（SVG）转位图的过程；按 (doc, w, h) 缓存可多尺寸复用（06 §4.4） |
