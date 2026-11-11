# Render（SLangRender 模块）库说明

- Project Entry File: `Render.sp`
- Project Config File: `Render.jsonc`
- 模块名（export.moduleName）：`SLangRender` → 产物 `SlangAllInOne\out\export\SLangRender\`

Windows OpenGL **离屏渲染**库（WGL + GL 3.3 core，零 SDK 依赖），namespace `SLang`
下两类：`Render`（入口 + 原生绑定 + 错误诊断）/ `RenderContext`（FBO 离屏渲染目标）。
错误处理以返回值表达（null / false），原因经 `Render.lastError()` /
`Render.errorString()` 取得（粘性：每次原生入口调用先清零），与 `SLangCuda` 同风格。

渲染模型是 **renderTexture 通道**：绘制到 FBO（RGBA8 颜色纹理 + DEPTH24_STENCIL8），
`glReadPixels` 回读 RGBA8 像素到 SL 侧原生块，再由上层窗口组件填充显示
（QT `QLabel.setPixmapRgba` 即为此通道的显示端）。隐藏窗口 + WGL 上下文只提供
GL 执行环境，永不显示、永不 SwapBuffers。

## 用法示例

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
Render.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_render_lib.dll
           ──运行期 LoadLibrary("opengl32.dll")──> WGL + GL 3.3 core
```

- `sl_render_lib.dll` 是 Windows OpenGL 的扁平 C ABI 包装（`slr_*`）：FBO 渲染
  目标收敛为 Int64 句柄（静态槽表，最多 64 个），多目标并存。
- **零 OpenGL-SDK 依赖**：构建期只需要 MSVC（无 gl.h / 无 opengl32.lib）。
  WGL 基础符号（wglCreateContext / glReadPixels ...）GetProcAddress 直取；
  GL 1.2+ core 符号（glCreateShader / glGenFramebuffers ...）与
  WGL_ARB 扩展经 wglGetProcAddress 解析（需 dummy context 在前）。
  `slr_sym` 双通道兜底：wglGetProcAddress 命中 NULL/1/2/-1（WGL 文档允许的
  "不支持"指示值）时回退 GetProcAddress(opengl32)，覆盖 ICD 对 GL 1.0/1.1
  老符号（glGenTextures / glTexImage2D ...）返回 NULL 的边角环境
  （RDP / 软件 GDI Generic）。
- 上下文获取：优先 `wglCreateContextAttribsARB`（GL 3.3 core profile）；
  扩展缺失 / 请求失败时回退传统 `wglCreateContext`（兼容 profile，GL 3.0+
  环境照常可用；GL 2.x 以下会在符号表检查处给出明确错误）。
- 三角形管线 init 期一次装配：`#version 330 core` VS(aPos) + FS(uColor) +
  VAO/VBO（NDC 顶点 (-0.6,-0.5) (0.6,-0.5) (0.0,0.7)），帧循环零状态切换开销。
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
  slr_read_pixels / slr_render_frame / slr_context_* ...）返回 **1=成功 / 0=失败**
  → SL 侧一律 sig `->bool` 直取（`->i32` 再 `== 0` 比较会**倒置**语义，
  初始化失败被吞成成功——v1 实测踩坑，见 slr_init 鸡生蛋问题复盘）。
- 含 ptr 形参（回读目标块）必须手写 sig：`"i64,ptr->bool"` /
  `"i64,f32,f32,f32,ptr->bool"`。

## 测试与集成

- 端到端用例集：`SlangAllInOne\SLangCore\test\Other\GLRenderTest\`
  - Phase A 纯 GL（headless，无 QT 依赖）：initialize → 渲染红三角 → 中心像素
    (255,0,0) / 角落背景 (15,15,25) 断言 → 蓝三角颜色变化断言 → frameCount；
  - Phase B QT 窗口填充（需真实 Qt 后端，stub 后端 SKIP）：QTimer 16ms 帧循环
    renderFrame（RGB 正弦相位错开变化）→ QLabel.setPixmapRgba，5s 自动退出。
- 运行：`dotnet run --project SlangAllInOne\Project\CSimpleVMTest -- SlangAllInOne\SLangCore\test\Other\GLRenderTest\GLRenderTest`
  （Phase B 需先 `QT\cvm\deploy-qt.ps1 -Combo minimal -Targets package` 铺 Qt runtime；
  本机包内已有 QTTest 时期部署的 full 组合存量，直接可用）
- 实测结果（RTX 2080 / GL 4.6.0 / 驱动 610.62）：
  `glFrames=303 pixOk=303`，`GLRenderTest: PASS`（Phase A + Phase B 双绿）。

## 已知取舍（v1）

- 固定单管线（居中纯色三角）：多 drawable / 自定义 shader / 纹理采样待 v2
  扩展 `slr_*` 符号面（当前定位即"驱动接入试验"最小闭环）。
- GL 资源不做 uninit 强制回收：析构顺序无法与 SL 侧对象生命周期对齐
  （与 CUDA 库同策略），进程退出由 OS 统一回收。
- 渲染目标上限 64 个（SLR_MAX_TARGETS 静态槽表），句柄 = 槽下标 + 1。
- 回读走中转缓冲逐行翻转（256x256 一次 memcpy 行 ×2，~0.1ms）；
  大分辨率高频回读可改 PBO 异步（待 v2）。
- D3D/DX 接入：v1 选 OpenGL（opengl32.dll 系统自带零依赖）；d3d11.dll
  同样随系统分发，DX 后端可按本模块的绑定层/句柄化/回读三件套模式复制扩展。
