# Render（SLangRender 模块）库说明

- Project Entry File: `Render.sp`
- Project Config File: `Render.jsonc`
- 模块名（export.moduleName）：`SLangRender` → 产物 `SlangAllInOne\out\export\SLangRender\`

Windows OpenGL **离屏渲染**库（WGL + GL 3.3 core，零 SDK 依赖），namespace `SLang`
下五类：

- `Render`（入口 + 原生绑定 + 错误诊断）
- `RenderContext`（v1：FBO 离屏渲染目标，直连快速路径）
- `RenderPipeline`（v2：Unity 风格 13 阶段管线，**逻辑全在 C 层**）
- `RenderObject`（v2：场景对象——mesh/layer/queue/变换/颜色/纹理/动画）
- `RenderTexture`（v2：RGBA8 纹理，SL 侧 top-down 像素块直传）

错误处理以返回值表达（null / false），原因经 `Render.lastError()` /
`Render.errorString()` 取得（粘性：每次原生入口调用先清零），与 `SLangCuda` 同风格。

渲染模型是 **renderTexture 通道**：绘制到 FBO（RGBA8 颜色纹理 + DEPTH24_STENCIL8），
`glReadPixels` 回读 RGBA8 像素到 SL 侧原生块，再由上层窗口组件填充显示
（QT `QLabel.setPixmapRgba` 即为此通道的显示端）。隐藏窗口 + WGL 上下文只提供
GL 执行环境，永不显示、永不 SwapBuffers。

## 渲染层职责对照（RHI 与上层脚本之间的中间层定位）

职责：**连接 RHI 与上层脚本，处理高性能的渲染逻辑**。SL 侧薄 FFI 门面
（`Render.sl`/`Pipeline.sl`）+ C 侧管线层（`Pipeline/sl_pipeline.c`）+
RHI 层（`RHI/` 四后端 vtable）三层协同，三大核心功能：

| 核心功能 | 落点 | 机制 |
|---|---|---|
| **Batching & Sorting** | 阶段 5 `sort_items` + 阶段 7/9 `batch_end` | 不透明排序键 = queue → z（近→远，Early-Z 方向）→ **材质键（prog + tex_desc）**——同材质项自然相邻成批；一个批 = 一次 `desc_bind_tex` 纹理绑定（SetPass 级合批），批内逐项 `draw_item`（PerDraw UBO 槽寻址）。透明段后→前深度序保持不变（合批不得改变混合次序），材质分块只最小化绑定次数 |
| **Culling** | 阶段 4 `stage_cull_layers` | 多相机独立剔除：每相机 cullingMask 按位 layer 0..31 + 正交视域 AABB 剔除（`cull_cams` 位掩码记录对象对各相机的可见性）；统计可见/剔除数（stat VISIBLE/CULLED） |
| **Platform Adaptation** | `sl_render.c` 后端注册表 + `RHI/` 四后端 | `SlrBackendEntry` 静态注册（gl/d3d11/vk/gles）+ 运行期探测（LoadLibrary 后端 dll）+ 缺失优雅降级（init 返回 0 → 测试侧 SKIP）；跨平台差异吸收：D3D11 行序翻转/清屏 quad、GL scissor 局部清、VK 布局跟踪与分段提交、四后端像素/坐标约定逐字节对齐；描述符机制四后端映射（v3.2：DX11 SRV 槽表 / VK descriptor set / GL 纹理单元） |

上层脚本侧数据结构：`Config.sl`（分辨率/同步/MSAA/后端标识/裁剪面/URP 开关）
+ `RenderPipeline/Object/Texture/Camera`（场景侧）+ `Mesh.sl`（几何侧）；
管线侧外层数据结构：`SlrPipeline`（含 `SlrDescTable` 描述符表、相机槽表、
绘制项表）、`SlrDrawItem`（含 `tex_desc` 材质键）、`SlrCamera`。

## v2：Unity 风格 13 阶段管线（sl_render_lib.dll 内实现）

一帧 = 13 个阶段依序执行（C 层静态函数 + `SLR_STAGE_EXPORT` 宏导出），对应
Unity 渲染底层流程；SL 侧 `RenderPipeline` 只做薄 FFI 绑定（每方法 1:1
转发一个 `slr_*` 符号，参数不超过 FFI 上限 6）：

| # | 阶段 | C 符号 | 职责 |
|---|---|---|---|
| 1 | 渲染开始 | `slr_pipeline_begin_frame` | 帧计数、时间推进、脏状态复位 |
| 2 | 准备物料 | `slr_pipeline_prepare_materials` | 着色器/网格/纹理可用性预检 |
| 3 | 提前更新 | `slr_pipeline_early_update` | 动画参数预计算（色相循环相位） |
| 4 | 渲染层分层 | `slr_pipeline_cull_layers` | cullingMask 按位 layer 0..31 + 正交视域剔除 |
| 5 | 层整理数据 | `slr_pipeline_assemble_layer_data` | 生成 drawItem，按队列排序（不透明前→后 / 透明后→前） |
| 6 | 传入渲染数据 | `slr_pipeline_upload_render_data` | PerDraw std140 UBO 批量上传 MVP/颜色 + **纹理描述符表写入**（同纹理查重复用槽，见 v3.2） |
| 7 | shader 分块渲染 | `slr_pipeline_render_shader_chunks` | 按着色器程序分组绘制不透明（分组=少切状态/少 SetPass） |
| 8 | 核心时间更新 | `slr_pipeline_update_core_time` | 帧时间 / 帧间隔统计 |
| 9 | shader 分段渲染 | `slr_pipeline_render_shader_segments` | 透明段绘制（混合开、深度写关） |
| 10 | 整理渲染图层 | `slr_pipeline_assemble_rendered_layers` | scene RT 完成并拷贝到 post RT |
| 11 | 后处理 | `slr_pipeline_post_process` | 亮度/饱和度/暗角全屏 pass（可关，关则纯拷贝） |
| 12 | 层级逻辑整合 | `slr_pipeline_integrate_layers` | post→final 整合 |
| 13 | 输出 renderTexture | `slr_pipeline_output_render_texture` | `glReadPixels` + 逐行翻转 top-down 回读 |

- 一键全流程：`renderFrame( t, pixels )`（C 层 `slr_pipeline_render_frame` 依序跑 1..13）
- 逐阶段驱动：`runStages( t, pixels )`（SL 侧按 1..13 逐个调，帧循环形态，每帧仍完整 13 阶段）
- 统计：`stat( id )` —— FRAME / VISIBLE / CULLED / DRAW_CALLS / OPAQUE_DRAWS /
  TRANSPARENT_DRAWS / POST_ENABLED / LAST_STAGE / OBJECT_COUNT / CHUNK_COUNT /
  LAYERS_MASK / UPLOAD_COUNT / TIME_MS / DT_MS / TEXTURE_COUNT / PROGRAM_SWITCHES /
  CAMERA_COUNT
- 队列语义对齐 Unity：**queue < 2500 不透明**（前→后排序、深度写开）；
  **queue >= 2500 透明**（后→前排序、`SRC_ALPHA/ONE_MINUS_SRC_ALPHA` 混合、深度写关）
- 相机（v2.1 多相机）：
  - 默认相机（槽 0）：`setCamera( cullingMask, l, r, b, t )` 写入，mask=-1 全可见，
    按位 `1<<layer` 控制层；`setClearColor` 同步槽 0 清屏色（保持 v2 兼容）
  - 多相机：`addCamera( depth )` 新建 `RenderCamera`（上限 8 槽），每相机独立
    `setCullMask / setExtents / setViewport / setClearColor / setClearFlags / setDepth /
    setEnabled / destroy`
  - 渲染按 **depth 升序**逐相机执行：视口/清屏（`glClear` 只受 scissor 限制，局部
    清屏内部启用 scissor box）→ 该相机剔除（cullMask + 视域）→ 不透明/透明段绘制；
    阶段 11-13（后处理/整合/输出）全帧一次
  - clearFlags：位 1 = 清颜色，位 2 = 清深度；叠加相机可设 0（透写上一相机画面）
- 图片文件加载（v2.1）：`RenderTexture.loadFile( path )` —— C 层 WIC 解码
  （PNG/JPEG/BMP/TIFF，零 SDK 依赖，windowscodecs.lib 注入），转 32bppRGBA 后
  与 createRgba 同路径上传；path 为 UTF-8；坏路径返回 null（错误码 SLR_E_IMAGE -19，
  细节经 `slr_error_detail()`）

### 理论映射（RTR 三阶段 → 13 阶段，知乎 p/702640844 汇总）

| 理论阶段 | 执行者 | 在本库的落点 |
|---|---|---|
| 应用阶段：剔除/排序/数据上显存、设渲染状态、发 DrawCall | CPU | 阶段 4-6（cullLayers/assembleLayerData/uploadRenderData：视域+层级剔除、先近后远排序、UBO 打包上显存）+ 阶段 7/9 分块分组（少 SetPass）+ `glDrawArrays`（DrawCall） |
| 几何阶段：顶点着色器（模型→齐次裁剪空间 -1..1）、裁剪、屏幕映射 | GPU | VS_PSCENE `uMVP * pos`；裁剪/屏幕映射/三角形设置与遍历为 GL 固定功能 |
| 光栅化阶段：片元着色器纹理采样、逐片元操作（深度/模板测试、混合） | GPU | FS `texture(uTex, vUv)` 采样（VS 出 UV 插值）；不透明前→后排序即 Early-Z 方向；透明混合开 + 深度写关 |

### 用法示例（v2 管线 + QT 窗口帧循环）

```csharp
import Std;
import SLangRender;
import SLangQT;

SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f )          # 全可见 + 正交视域
pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )

# 对象 1：色相循环动画三角（layer0，Geometry 队列）
SLang.RenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
tri.setLayer( 0 )
tri.setQueue( 2000 )
tri.setScale( 1.3f, 1.3f )
tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
tri.setAnimated( pipe.ANIM_HUE_CYCLE, 0.25f )           # 0.25 色相/秒：红→绿→青…

# 纹理：SL 侧生成 top-down RGBA8 像素块（Memory.alloc w*h*4）
Int64 texPtr = Memory.alloc( 64 * 64 * 4 )
# … Memory.writeI8 逐通道填色 …
SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )

# 对象 2：贴图 quad（layer1，Transparent 队列，叠在三角右上）
SLang.RenderObject quad = pipe.addObject( pipe.MESH_QUAD )
quad.setLayer( 1 )
quad.setQueue( 3000 )
quad.setPosition( 0.45f, 0.35f, 0.5f )
quad.setScale( 0.55f, 0.55f )
quad.setColor( 1.0f, 1.0f, 1.0f, 0.85f )                # alpha 0.85 半透明
quad.setTexture( tex )

Int64 pixels = Memory.alloc( 256 * 256 * 4 )
pipe.renderFrame( 0.0f, pixels )                        # 一键 13 阶段 + 回读

# QT 帧循环：QTimer 16ms -> runStages（逐阶段驱动）-> setPixmapRgba
label.setPixmapRgba( pixels, 256, 256 )

# 断言素材：stat( pipe.STAT_DRAW_CALLS )、stat( pipe.STAT_VISIBLE )…
```

## 用法示例（v1 RenderContext 直连）

```csharp
import Std;
import SLangRender;

SLang.Render.initialize()                          # 隐藏窗口 + WGL 3.3 上下文，幂等
Console.println( SLang.Render.rendererInfo() )     # "NVIDIA GeForce RTX 2080 ..."

# ── 离屏渲染 + 像素回读 ──────────────────────────────────────────
SLang.RenderContext ctx = SLang.RenderContext.create( 256, 256 )
Int64 pixels = Memory.alloc( 256 * 256 * 4 )        # RGBA8 原生块

ctx.renderFrame( 1.0f, 0.0f, 0.0f, pixels )        # 红色三角形 + 回读，一步完成
int r = Memory.readUInt8( pixels, ( 128 * 256 + 128 ) * 4 + 0 )   # 中心 R=255
int b = Memory.readUInt8( pixels, ( 4 * 256 + 4 ) * 4 + 2 )      # 角落 B=25(背景)

ctx.clear( 0.0f, 0.0f, 0.0f, 1.0f )                 # 或分步：清屏
ctx.drawTriangle( 0.0f, 0.0f, 1.0f )                #      画三角形
ctx.readPixels( pixels )                            #      回读

ctx.destroy()
Memory.free( pixels )
```

## 与 QT 窗口对接（renderTexture 显示端）

```csharp
import SLangQT;
import SLangRender;

# QTimer onTick 帧循环内：
#   renderFrame(颜色随时间变化) -> QLabel.setPixmapRgba 填充
label.setPixmapRgba( pixels, 256, 256 )   # RGBA8 top-down 块 -> QImage -> QPixmap
```

像素块布局（回读 / 填充两端契约）：RGBA8，每像素 4 字节（R,G,B,A），行主序，
**顶行在前**（top-down；glReadPixels 的 bottom-up 行序已在 C 库内逐行翻转），
块大小 `w * h * 4`，与 QImage `Format_RGBA8888` 直接对接。

## v3.1：Mesh 数学层 + 动态网格通道（3D/程序化几何）

`Mesh.sl`（namespace `SLang`）提供 CPU 侧网格容器：`Array<Float32>` 顶点/法线 +
`Array<Int32>` 三角索引，`Mesh.cube(size)` 工厂产出 24 顶点 36 索引的立方体
（每面独立 4 角点 + 面法线，无 UV——UV 在绘制端按 `vi % 4` 现场计算）。

```csharp
import SLangRender;   # Mesh 在 SLang 命名空间，import SLangRender 后 SLang.Mesh 可见
import Math;          # Float32_3 / Float32_4x4 在 Math 命名空间，必须显式 import

SLang.Mesh mesh = SLang.Mesh.cube( 1.0f )          # 24 顶点 / 36 索引
Int32 nv = mesh.vertexCount                         # getter：属性访问（无括号读）
Array<Int32> tris = mesh.getTriangles()
Float32_3 p0 = mesh.getVertex( 0 )                  # 越界返零向量

# CPU 变换：rotationY/X -> transformPoint -> 手工透视除法 -> NDC 三角形列表
Float32_4x4 m = Float32_4x4.rotationX( t * 0.5f ).multiply( Float32_4x4.rotationY( t * 0.9f ) )
# 顶点写 pos2+uv2 交错块（stride 16B）：
Memory.writeF32( vertsPtr, off + 0, x ); Memory.writeF32( vertsPtr, off + 4, y )
Memory.writeF32( vertsPtr, off + 8, u ); Memory.writeF32( vertsPtr, off + 12, v )

# 上传 + 挂对象：mesh_kind = 4 + slot（MESH_CUSTOM 路由动态网格槽）
pipe.uploadMesh( 0, vertsPtr, vertCount )           # 每帧整块重传（VK 持久映射直写）
SLang.RenderObject obj = pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
```

原生侧（`slr_mesh_upload` → RHI vtable `mesh_upload` 槽，四后端一致）：
- GL/GLES：首传建 VAO/VBO，之后 `glBufferData` DYNAMIC_DRAW 整块重传；
- D3D11：容量不足时重建 DYNAMIC 顶点缓冲（256B 对齐），`Map(WRITE_DISCARD)` 重传；
- VK：持久映射显存直写（容量不足重建）。
- 深度遮挡由 CPU 侧排序保证（painter 算法：三角形按平均深度降序，远先画），
  动态网格不参与深度缓冲分块（透明队列 3000）。
- 上限：`SLR_CUSTOM_MESHES` 4 槽 × `SLR_CUSTOM_MAX_VERTS` 4096 顶点/槽。

SL 语言规则（Mesh.sl 落地实证，写库必读）：
1. **getter 声明必须带括号**：`get int vertexCount() { ... }`（先例
   Render.sl `get Int64 handle()`）；无括号写法解析器把属性名当类型名报
   "有其它未知类型在class中"。
2. **跨命名空间类型必须 import**：`Float32_3` 在 namespace Math 下，使用方
   文件头必须 `import Math;`；无 namespace 的全局类（Memory/Array）裸名可见。
3. **实例成员必须 `this.` 前缀**：`this._positions` / `this.vertexCount()`
   （MetaCallNode 裸名解析仅 static 分支放行）；构造器跨实例字段写不可用，
   用多参构造重载代替。

## v3.2：描述符表机制（DX11 SRV 槽表 / VK descriptor set 的统一抽象）

对齐 DX11/Vulkan 的**"绑定与绘制分离"**：资源先写入描述符槽，绘制前绑定槽，
`draw_item` 只携带整数索引（prog / PerDraw 槽 / mesh），不再传资源指针。

```
管线层（外层数据结构，sl_render_internal.h）          RHI 层（四后端各自映射）
┌─ SlrDescTable（帧级，挂在 SlrPipeline）─┐           desc_write_tex / desc_bind_tex
│  SlrTexDesc tex[16]                     │  写槽/绑槽  ├─ D3D11: SRV 数组 + PSSetShaderResources
│  tex_count（本帧槽数）                  │──────>────├─ VK   : VkTexture 的 set_pipe_tex 表
└─ SlrDrawItem.tex_desc（槽号，-1=无纹理）┘            │          + vkCmdBindDescriptorSets
                                                        ├─ GL/GLES: 纹理名数组 + 纹理单元 t1
```

- **帧级生命周期**：阶段 6（uploadRenderData）遍历绘制项——PTEX 项的纹理
  写入描述符槽（同纹理查重复用，`res` 指针比对），`SlrDrawItem.tex_desc`
  记录槽号；阶段 7/9 绘制时 `desc_bind_tex(tex_desc)` 先绑定再 `draw_item`。
  槽满（>16 张不同纹理）时该项降级为纯色绘制。
- **后端映射**（同一 vtable 槽位 `desc_write_tex`/`desc_bind_tex`）：
  - D3D11：槽表 = `ID3D11ShaderResourceView` 数组，绑定 = `PSSetShaderResources(0,1,...)`
    ——DX11 的 SRV 槽表机制原生形态；
  - VK：槽表 = `VkTexture::set_pipe_tex`（PTEX descriptor set）数组，绑定 =
    记录当前 set，`vkCmdBindDescriptorSets` 绘制时提交——VK descriptor set
    机制原生形态；
  - GL/GLES：槽表 = 纹理名数组，绑定 = 纹理单元 t1（GL 3.3 采样单元固定的
    镜像形态，多采样器扩展时按槽启用多单元）。
- **防悬空**：`free_shared` 清空槽表（slr_uninit 中纹理先于共享资源销毁）；
  `desc_bind_tex(-1)` 绑 NULL（纯色项），阶段 5 组装项默认 `tex_desc=-1`
  （手动逐阶段驱动跳过阶段 6 时不误绑槽 0）。
- v1 直连层（`RenderContext.renderFrame`）不经过描述符表——v1 自带纹理参数，
  各后端 v1 内直绑（DX11 直设 SRV / GL 直绑 t1 / VK 用 v1 专用 set）。
- 四后端像素契约不变：RenderTest 回归实测 quadtex(147,67,137) /
  左图(235,130,40) 等 9 组纹理像素四后端逐字节一致。

## 原生链路（FFI 静态绑定 + 运行期双通道解析）

```
Render.sl / Pipeline/Pipeline.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_render_lib.dll
                                      ──RHI 抽象层（SlrRhi vtable）──> 后端驱动：
                                        "gl"    -> opengl32.dll（WGL + GL 3.3 core，默认）
                                        "d3d11" -> d3d11.dll + d3dcompiler_47.dll（运行期加载，零 .lib）
                                        "vk"    -> vulkan-1.dll（纯离屏 instance；SPIR-V 由 glslang
                                                   一次性预编译固化进 RHI/sl_rhi_vk_shaders.h，零 SDK）
                                        "gles"  -> libEGL.dll + libGLESv2.dll（EGL + GLES 3.0，
                                                   surfaceless 上下文；缺失时 init 优雅降级）
```

- 本库是**渲染中间层**：13 阶段管线逻辑平台无关（Pipeline/ 层），经 RHI
  抽象层（`SlrRhi` 函数表）落到不同驱动后端，**渲染效果跨后端一致**
  （GLRenderTest Phase D/E/F 用与 GL 完全相同的像素断言集分别验证
  D3D11 / Vulkan / GLES，实测四后端逐字节一致）。
- 后端选择：`Render.initialize()` 默认 "gl"（幂等，已初始化时不切后端）；
  `Render.initializeBackend("d3d11"/"vk"/"gles")` 指定后端（已初始化其他
  后端时先 uninit 再切换，环境不可用时返回 false 并给出 errorString，
  测试侧按 SKIP 处理）；`Render.backendList()` / `Render.currentBackend()` 诊断。
- `sl_render_lib.dll` 是扁平 C ABI 包装（`slr_*`）：渲染目标/管线/对象/
  纹理收敛为 Int64 句柄（静态槽表），多目标并存；渲染目标/纹理对上层是
  不透明指针（`SlrRhiTarget*` / `void*`），由各后端私有实现。
- **导出宏 `SLR_API`（vm_sl_render.h）**：公开声明必须带
  `__declspec(dllexport)`（Cuda 库 `SLC_API` 同款）。声明裸写时 DLL **空导出**
  ——LoadLibrary 成功但 GetProcAddress 全 MISS，SL 侧兜底表现即
  `initialize() == false` / "xxx not available"（v2 实测踩坑）。
- **零 OpenGL-SDK 依赖**：构建期只需要 MSVC（无 gl.h / 无 opengl32.lib）。
  WGL 基础符号（wglCreateContext / glReadPixels ...）GetProcAddress 直取；
  GL 1.2+ core 符号（glCreateShader / glGenFramebuffers ...）与
  WGL_ARB 扩展经 wglGetProcAddress 解析（需 dummy context 在前）。
  `slr_sym` 双通道兜底：wglGetProcAddress 命中 NULL/1/2/-1（WGL 文档允许的
  "不支持"指示值）时回退 GetProcAddress(opengl32)，覆盖 ICD 对 GL 1.0/1.1
  老符号（glGenTextures / glTexImage2D ...）返回 NULL 的边角环境
  （RDP / 软件 GDI Generic）。
- **GL 常量表为手写**（不依赖 SDK 头）：逐值核对过一遍；曾踩
  `GL_FRAGMENT_SHADER` 误写 0x8E30（正确 0x8B30）——glCreateShader 非法枚举
  返回 0 句柄，全部片元着色器编译失败且 info log 为空，错误面板只剩通用文案。
- 上下文获取：优先 `wglCreateContextAttribsARB`（GL 3.3 core profile）；
  扩展缺失 / 请求失败时回退传统 `wglCreateContext`（兼容 profile，GL 3.0+
  环境照常可用；GL 2.x 以下会在符号表检查处给出明确错误）。
- 6 个着色器程序：FLAT/TEX（v1 uniform 版）、PFLAT/PTEX（管线 PerDraw UBO 版，
  `layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; }` +
  `uniform int uObjIndex`）、BLIT（全屏拷贝）、POST（亮度/饱和度/暗角）。
  4 组静态网格：单位三角、quad（6 顶点）、全屏大三角、v1 大三角（pos2+uv2）。
- 线程约定：GL 上下文线程亲和 → 全入口临界区 + 每次渲染
  wglMakeCurrent / 用毕置空。任意线程调用安全，并发渲染退化为串行排队
  （帧循环典型形态 = QTimer GUI 线程单调用方，无影响）。

jsonc `dllImports` 用平铺 basename 形态（`{ "path": "sl_render_lib.dll",
"static": "sl_render_lib" }`）：cvm 装载模块即预载该库并注册 FFI 静态绑定表，
绑定失败回退 SL 函数体兜底（`initialize() == false` 即兜底征兆）。
`vmDlls` 挂 `../cvm_render_lib/cvm_sl_render_lib.vcxproj`（C 源位于
`SlangAllInOne\SLangCore\Lib\SLang\Render\cvm_render_lib\`），模块编译时 Front
自动 MSBuild 产出 DLL 并拷入导出目录。

### C 源文件划分（管线层与 SL 一一对应；RHI 层多后端同效果）

```
cvm_render_lib/
├── vm_sl_render.h            对外契约头（SLR_API 导出声明 + 后端 API）
├── sl_render_internal.h      内部共享：结构体（rt_* 不透明目标）、跨文件原型
│                              （C++ 编译单元经 extern "C" 引用 C 层符号）
├── sl_render.c               <-> Render.sl                 生命周期/诊断/v1 直连层
│                                                             + RHI 后端注册表 + 全局资源回收
├── Pipeline/                 （平台无关管线层，只调 g_rhi->*）
│   ├── sl_pipeline.c         <-> Pipeline/Pipeline.sl  13 阶段管线 + 多相机调度 + 统计
│   ├── sl_object.c           <-> RenderObject          场景对象属性
│   ├── sl_texture.c          <-> RenderTexture         纹理注册表 + WIC 图片加载
│   └── sl_camera.c           <-> RenderCamera          多相机槽表
└── RHI/                      （驱动后端：同一 vtable，同一像素契约）
    ├── sl_rhi.h              接口契约（SlrRhi 函数表 + 像素/坐标约定）
    ├── sl_gl_procs.h         GL 函数指针清单（GLDECL 宏双用；GL/GLES 后端共用，
    │                          GLES 侧定义带 static 与 GL 单元隔离）
    ├── sl_rhi_gl.c           "gl"    WGL + GL 3.3（WGL 解析/着色器/网格/UBO/FBO/回读行翻）
    ├── sl_rhi_d3d11.cpp      "d3d11" D3D11（运行期加载 dll；HLSL 六组 + 清屏 quad
    │                          模拟局部清屏 + staging 回读天然 top-down；C++ 编译单元）
    ├── sl_rhi_vk.cpp         "vk"    Vulkan（纯离屏 instance/无 surface；手写零依赖
    │                          声明 + vkGetInstanceProcAddr 解析；SPIR-V 固化着色器；
    │                          即时风格分段提交；vkCmdClearAttachments 矩形级局部清屏；
    │                          CopyImageToBuffer 回读天然 top-down；C++ 编译单元）
    ├── sl_rhi_vk_shaders.h   VK 九组 SPIR-V 字节数组（glslang 一次性预编译固化；
    │                          内嵌 VKSL 源码可重生成）
    └── sl_rhi_gles.c         "gles"  EGL + GLES 3.0（libEGL/libGLESv2 运行期探测，
                               缺失优雅降级；surfaceless 优先回退 1x1 pbuffer；
                               GLSL ES 3.00 六组 + 片段 highp + int 跨级精度对齐；
                               pass 逻辑与 GL 后端逐行同构）
```

约定：公开导出仍集中在 `vm_sl_render.h`（全部带 `SLR_API`）；管线层经
`g_rhi->` 调用后端（`rhi_enter/rhi_exit` 统一清错+就绪检查+锁）；
跨文件内部函数（set_error / tex_from_handle / pipe_from_handle /
pipeline_release_targets）统一非 static 并在 `sl_render_internal.h` 声明；
全局表 `s_pipes` / `s_textures` 定义在各自归属 .c。

**跨后端一致效果的关键约定**（sl_rhi.h 顶部注释为准）：
- 纹理上传：rgba 首行 = 图像底部（sl_texture.c 统一翻行；GL t=0 与
  D3D11/VK v=0 均指首行，采样语义一致）；
- 回读输出：top-down RGBA8（GL/GLES glReadPixels 需行翻；D3D11 staging 与
  VK CopyImageToBuffer 天然 top-down）；
- 相机视口坐标 GL 左下原点（D3D11/VK 内部换算 TopLeftY = h-(y+h)）；
- 相机段绘制裁剪到相机视口：GL/GLES 用 scissor 常开模拟 D3D11/VK 的 viewport 裁剪；
- 局部清屏：D3D11 用"清屏 quad"（clip z=1 + ALWAYS 深度写 1.0）；
  GL/GLES 用 scissor+glClear；VK 直接 vkCmdClearAttachments（矩形级，天然对齐）；
- GL/GLES 清屏前先 `DepthMask(TRUE)`（glClear(DEPTH) 受深度写掩码限制）；
- GL/GLES 后端 draw_item 自绑 glUseProgram（uniform 设置作用于当前绑定程序）；
- D3D11/VK 全屏三角 V 翻转（RT 行序差异；VK 另在每个 VS 内做 NDC y 翻转，
  等价于 D3D11 的 y-up clip space + 行 0 = 图像顶部），blend 因子对齐 glBlendFunc。

## FFI sig 约定（SL 侧手写 sig 与 C 返回值对齐）

- C 端"成功与否"导出（slr_init / slr_clear / slr_draw_triangle /
  slr_read_pixels / slr_render_frame / slr_context_* / slr_pipeline_* /
  slr_object_* ...）返回 **1=成功 / 0=失败**
  → SL 侧一律 sig `->bool` 直取（`->i32` 再 `== 0` 比较会**倒置**语义，
  初始化失败被吞成成功——v1 实测踩坑，见 slr_init 鸡生蛋问题复盘）。
- 含 ptr 形参（回读目标块）必须手写 sig：`"i64,ptr->bool"` /
  `"i64,f32,f32,f32,ptr->bool"` / `"i64,f32,ptr->bool"`（renderFrame）。
- 返回 i64 句柄的创建函数：`"i32,i32->i64"`（create）/ `"i64,i32->i64"`（addObject）/
  `"i64,i32,i64,ptr->i64"` 超 6 参不存在——纹理上传拆为 createRgba(ptr,w,h) 三参
  在 SL 侧组包（top-down 契约，C 内翻行）。
- 统计/查询：`"i64,i32->i32"`（stat）、`"i64->i64"`（frameCount/objectCount）。

## 测试与集成

- 端到端用例集：`SlangAllInOne\SLangCore\test\RenderTest\`（自 GLRenderTest
  迁移并扩展 Phase C 3D 立方体）
  - Phase D/E/F（RHI 多后端同效果）：`initializeBackend("d3d11"/"vk"/"gles")`
    后用**与 GL 完全相同的 A1/A2/A3 断言集**复跑——corner(15,15,25) /
    tri(255,0,0) / quadtex(147,67,137) / t5(127,255,0) / t10(0,244,244) /
    postgray(76,76,76) / 左图(235,130,40) / 右清屏(0,64,25) / 蓝quad(51,102,255)
    全部像素逐字节一致即"不同驱动渲染一样效果"验收通过；后端不可用报 SKIP；
  - Phase A1（v1 兼容回归）：RenderContext 直连 FBO，128x128 红三角中心像素
    (255,0) 断言；
  - Phase A2（13 阶段管线主测，256x256）：清屏色角落 (15,15,25)±6 / 动画三角
    t=0 红 (255,0,0)、t=5 绿 (127,255,0)、t=10 青（色相循环断言）/ 贴图 quad
    混合像素 / stats 断言（lastStage=13、visible=2、culled=0、opaque=1、
    transp=1、layers=3、chunks=2、uploads=4）/ mask=-3 剔除 layer1 后 quad 消失 /
    饱和度=0 灰度断言（R==G==B）/ runStages 逐阶段驱动与 renderFrame 等价；
  - Phase A3（多相机 + 图片）：相机 depth 升序覆盖 / viewport 右半分割 /
    cullingMask 分离 / 禁用相机回退 / WIC 图片加载渲染（橙色断言）；
  - Phase B（QT 窗口 + 后端切换 UI）：窗口顶部 4 按钮
    （OpenGL/D3D11/Vulkan/WebGL-GLES）点击即切换渲染底层（切换 =
    uninit 旧后端 + 新后端 init + 场景全量重建，管线/纹理句柄随 uninit
    失效需重建）；状态栏实时显示当前后端 + 渲染器，当前后端按钮高亮；
    QTimer 16ms → runStages → QLabel.setPixmapRgba；另有 4s 自动轮播
    （d3d11 → vk → gles → gl）自动验证四后端在 QT 帧循环下持续渲染
    （用户点击任一按钮后轮播停止）；30s 退出，帧数 + 后端掩码断言
    （mask 奇数含 gl 位且 >=3：至少一个其他后端渲染过）。
  - Phase C（3D 旋转立方体，Phase B 场景内常驻）：`Mesh.cube(1.0f)`
    24 顶点 36 索引 → `Float32_4x4.rotationY/X(t)` CPU 变换 → 相机 -Z
    朝 +Z 手工透视除法（f=1.7，camZ=2.6）→ 12 三角形 painter 深度降序 →
    `Memory.writeF32` 填 pos2+uv2 → `uploadMesh(0)` 每帧重传 → 对象
    `MESH_CUSTOM`（透明队列叠加在 2D 场景之上）；onTick 驱动绕 X/Y 双轴
    自转，每次后端切换后首帧打印 `[cube] spinning` 验证，Phase B 终判
    加立方体上传断言（`_cubeFirst == 1`）。
- 运行（编译/运行必须同一套 package 工具链，混批会跨模块 methodId 错位
  原生崩溃——开发版 Front 编译产物配旧 VM 运行是已知陷阱）：
  ```
  slang.exe compile SlangAllInOne\SLangCore\test\RenderTest\RenderTest.sp
  slang.exe run    SlangAllInOne\SLangCore\test\RenderTest\export\RenderTest\RenderTest.module.slb
  ```
  （Phase B 需先 `QT\cvm\deploy-qt.ps1 -Combo minimal -Targets package` 铺 Qt runtime；
  本机包内已有 QTTest 时期部署的 full 组合存量，直接可用；重编 SLangRender
  模块后需同步 `out\export\SLangRender` 三件套到 `package\win32-debug\modules\SLangRender`）
- 实测结果（RTX 2080 / 驱动 610.62，GL 3.3.0 core + D3D11 FL 11.0 +
  Vulkan 1.4.341 + ANGLE GLES 3.0.0 四后端）：
  Phase D/E/F/A1/A2/A3/B 全 PASS（四后端像素逐字节一致；QT 30s 1844 帧
  pixOk=1844 mask=15 四后端全渲染；立方体四后端各打 `[cube] spinning` +
  `[cube] Mesh.cube verts=24 indices=36`），`RenderTest: PASS` 七绿，
  exit=0。RenderTest 主流程收尾显式 `initializeBackend("gl")` 强制切回
  （幂等陷阱：initialize 不切后端）。

## 已知取舍（v2 / v3.1）

- 动态网格无深度缓冲参与：MESH_CUSTOM 走透明队列 + CPU painter 排序
  （三角形平均深度降序），复杂互遮挡场景需引入深度写通道；上限 4 槽 ×
  4096 顶点，超出报 SLR_E_BAD_PARAM。
- Mesh 无 UV/切线/骨骼通道：v3.1 定位 CPU 数学容器 + 手工投影；GPU 侧
  MVP 变换（矩阵进 PerDraw UBO）待 v3.2。

- 管线固定为"剔除→排序→UBO 上传→不透明分块→透明分段→后处理"流程；v2.1 已支持
  多相机逐相机执行（阶段 4-9 内部按 depth 排序循环）；多 Pass / 自定义管线编排
  （SRP 式 RenderGraph）待后续版本。
- PerDraw UBO 容量 mat4[64]+vec4[64]：单帧最多 64 个对象全量重传（256x256
  场景 <1ms），Dirty 局部更新与多 UBO 槽轮换待做。
- 后处理单 pass（亮度/饱和度/暗角）；泛光/ACES/FXAA 等 ImageEffect 待扩。
- GL 资源不做 uninit 强制回收：析构顺序无法与 SL 侧对象生命周期对齐
  （与 CUDA 库同策略），进程退出由 OS 统一回收。
- 管线/对象/纹理句柄上限：SLR_MAX_PIPES 32 / SLR_MAX_OBJECTS 64（每管线）/
  SLR_MAX_TEX 64（全局注册表）。
- 回读走中转缓冲逐行翻转（256x256 一次 memcpy 行 ×2，~0.1ms）；
  大分辨率高频回读可改 PBO 异步。
- 多后端已落地（gl / d3d11 / vk / gles 同 vtable 同像素契约）；VK/GLES
  均为运行期探测、缺失优雅降级（init 返回 false + errorString），后续
  平台（macOS Metal / Linux X11+GL）按同模式扩展 SlrRhi 表即可。
