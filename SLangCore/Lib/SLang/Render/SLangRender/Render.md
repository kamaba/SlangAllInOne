# Render（SLangRender 模块）库说明

- Project Entry File: `Render.sp`
- Project Config File: `Render.jsonc`
- 模块名（export.moduleName）：`SLangRender` → 产物 `SlangAllInOne\out\export\SLangRender\`

Windows OpenGL **离屏渲染**库（WGL + GL 3.3 core，零 SDK 依赖），namespace `SLang`
下五类：

- `Render`（入口 + 原生绑定 + 错误诊断）
- `RenderContext`（v1：FBO 离屏渲染目标，直连快速路径）
- `UnityRenderPipeline`（v2：Unity 风格 13 阶段管线，**逻辑全在 C 层**）
- `UnityRenderObject`（v2：场景对象——mesh/layer/queue/变换/颜色/纹理/动画）
- `UnityRenderTexture`（v2：RGBA8 纹理，SL 侧 top-down 像素块直传）

错误处理以返回值表达（null / false），原因经 `Render.lastError()` /
`Render.errorString()` 取得（粘性：每次原生入口调用先清零），与 `SLangCuda` 同风格。

渲染模型是 **renderTexture 通道**：绘制到 FBO（RGBA8 颜色纹理 + DEPTH24_STENCIL8），
`glReadPixels` 回读 RGBA8 像素到 SL 侧原生块，再由上层窗口组件填充显示
（QT `QLabel.setPixmapRgba` 即为此通道的显示端）。隐藏窗口 + WGL 上下文只提供
GL 执行环境，永不显示、永不 SwapBuffers。

## v2：Unity 风格 13 阶段管线（sl_render_lib.dll 内实现）

一帧 = 13 个阶段依序执行（C 层静态函数 + `SLR_STAGE_EXPORT` 宏导出），对应
Unity 渲染底层流程；SL 侧 `UnityRenderPipeline` 只做薄 FFI 绑定（每方法 1:1
转发一个 `slr_*` 符号，参数不超过 FFI 上限 6）：

| # | 阶段 | C 符号 | 职责 |
|---|---|---|---|
| 1 | 渲染开始 | `slr_pipeline_begin_frame` | 帧计数、时间推进、脏状态复位 |
| 2 | 准备物料 | `slr_pipeline_prepare_materials` | 着色器/网格/纹理可用性预检 |
| 3 | 提前更新 | `slr_pipeline_early_update` | 动画参数预计算（色相循环相位） |
| 4 | 渲染层分层 | `slr_pipeline_cull_layers` | cullingMask 按位 layer 0..31 + 正交视域剔除 |
| 5 | 层整理数据 | `slr_pipeline_assemble_layer_data` | 生成 drawItem，按队列排序（不透明前→后 / 透明后→前） |
| 6 | 传入渲染数据 | `slr_pipeline_upload_render_data` | PerDraw std140 UBO 批量上传 MVP/颜色（简化 SRP Batcher） |
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
  LAYERS_MASK / UPLOAD_COUNT / TIME_MS / DT_MS / TEXTURE_COUNT / PROGRAM_SWITCHES
- 队列语义对齐 Unity：**queue < 2500 不透明**（前→后排序、深度写开）；
  **queue >= 2500 透明**（后→前排序、`SRC_ALPHA/ONE_MINUS_SRC_ALPHA` 混合、深度写关）
- 相机：`setCamera( cullingMask, l, r, b, t )`，mask=-1 全可见，按位 `1<<layer` 控制层

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

SLang.UnityRenderPipeline pipe = SLang.UnityRenderPipeline.create( 256, 256 )
pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f )          # 全可见 + 正交视域
pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )

# 对象 1：色相循环动画三角（layer0，Geometry 队列）
SLang.UnityRenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
tri.setLayer( 0 )
tri.setQueue( 2000 )
tri.setScale( 1.3f, 1.3f )
tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
tri.setAnimated( pipe.ANIM_HUE_CYCLE, 0.25f )           # 0.25 色相/秒：红→绿→青…

# 纹理：SL 侧生成 top-down RGBA8 像素块（Memory.alloc w*h*4）
Int64 texPtr = Memory.alloc( 64 * 64 * 4 )
# … Memory.writeI8 逐通道填色 …
SLang.UnityRenderTexture tex = SLang.UnityRenderTexture.createRgba( texPtr, 64, 64 )

# 对象 2：贴图 quad（layer1，Transparent 队列，叠在三角右上）
SLang.UnityRenderObject quad = pipe.addObject( pipe.MESH_QUAD )
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

## 原生链路（FFI 静态绑定 + 运行期双通道解析）

```
Render.sl / Pipeline/UnityPipeline.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_render_lib.dll
                                      ──运行期 LoadLibrary("opengl32.dll")──> WGL + GL 3.3 core
```

- `sl_render_lib.dll` 是 Windows OpenGL 的扁平 C ABI 包装（`slr_*`）：渲染目标/
  管线/对象/纹理收敛为 Int64 句柄（静态槽表），多目标并存。
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
`vmDlls` 挂 `cvm_sl_render_lib/cvm_sl_render_lib.vcxproj`，模块编译时 Front
自动 MSBuild 产出 DLL 并拷入导出目录。

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

- 端到端用例集：`SlangAllInOne\SLangCore\test\Other\GLRenderTest\`
  - Phase A1（v1 兼容回归）：RenderContext 直连 FBO，128x128 红三角中心像素
    (255,0) 断言；
  - Phase A2（13 阶段管线主测，256x256）：清屏色角落 (15,15,25)±6 / 动画三角
    t=0 红 (255,0,0)、t=5 绿 (127,255,0)、t=10 青（色相循环断言）/ 贴图 quad
    混合像素 / stats 断言（lastStage=13、visible=2、culled=0、opaque=1、
    transp=1、layers=3、chunks=2、uploads=4）/ mask=-3 剔除 layer1 后 quad 消失 /
    饱和度=0 灰度断言（R==G==B）/ runStages 逐阶段驱动与 renderFrame 等价；
  - Phase B（QT 窗口）：QTimer 16ms → runStages（每帧完整 13 阶段）→
    QLabel.setPixmapRgba，5s 自动退出，帧数断言。
- 运行：`dotnet run --project SlangAllInOne\Project\CSimpleVMTest -- SlangAllInOne\SLangCore\test\Other\GLRenderTest\GLRenderTest`
  （Phase B 需先 `QT\cvm\deploy-qt.ps1 -Combo minimal -Targets package` 铺 Qt runtime；
  本机包内已有 QTTest 时期部署的 full 组合存量，直接可用）
- 实测结果（RTX 2080 / GL 3.3.0 core / 驱动 610.62）：
  Phase A1 PASS、Phase A2 PASS（全部像素/统计/剔除/后处理/逐阶段断言）、
  Phase B PASS（renderFrames=312 pixOk=312），`GLRenderTest: PASS` 三绿。

## 已知取舍（v2）

- 管线固定为"剔除→排序→UBO 上传→不透明分块→透明分段→后处理"单相机单目标
  流程；多相机 / 多 Pass / 自定义管线编排（SRP 式 RenderGraph）待后续版本。
- PerDraw UBO 容量 mat4[64]+vec4[64]：单帧最多 64 个对象全量重传（256x256
  场景 <1ms），Dirty 局部更新与多 UBO 槽轮换待做。
- 后处理单 pass（亮度/饱和度/暗角）；泛光/ACES/FXAA 等 ImageEffect 待扩。
- GL 资源不做 uninit 强制回收：析构顺序无法与 SL 侧对象生命周期对齐
  （与 CUDA 库同策略），进程退出由 OS 统一回收。
- 管线/对象/纹理句柄上限：SLR_MAX_PIPES 32 / SLR_MAX_OBJECTS 64（每管线）/
  SLR_MAX_TEX 64（全局注册表）。
- 回读走中转缓冲逐行翻转（256x256 一次 memcpy 行 ×2，~0.1ms）；
  大分辨率高频回读可改 PBO 异步。
- D3D/DX 接入：v1/v2 选 OpenGL（opengl32.dll 系统自带零依赖）；d3d11.dll
  同样随系统分发，DX 后端可按本模块的绑定层/句柄化/回读三件套模式复制扩展
  （13 阶段静态函数结构可直接复用，仅替换阶段 7/9/13 的设备层实现）。
