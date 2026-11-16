# 08 — RHI 四后端（已实现）

> 已实现并验收：**OpenGL / D3D11 / Vulkan / WebGL-GLES**。
> 验收标准（RenderTest Phase D/E/F）：同一组像素断言在三后端与 GL 后端**逐位一致**。

## 1. 后端总表

| name | 图形 API | 着色器 | 运行期依赖 | 缺失时行为 |
|---|---|---|---|---|
| `gl` | OpenGL 3.3 core（离屏） | 运行时 GLSL | opengl32 / 驱动 | init 失败 |
| `d3d11` | D3D11 离屏 | 运行时 HLSL | d3d11.dll（系统自带） | init 失败 |
| `vk` | Vulkan 1.x 离屏 | **SPIR-V 固化** | vulkan-1.dll 运行期探测 | init 返回 0 → 上层优雅降级 |
| `gles` | EGL + GLES 3.x 离屏 | 运行时 GLSL ES | libEGL.dll / libGLESv2.dll 探测 | init 返回 0 → 降级 |

共同特征：

- 全部**离屏渲染**（无真实交换链），输出 RGBA8 回读像素块；
- 上下文容量 `SLR_MAX_CTX = 16`，管线容量 `SLR_MAX_PIPES = 32`，纹理容量 64；
- 后端在**管线创建之前**选定并锁定（`initializeBackend` 须在 `create` 前调用）。

## 2. 初始化流程（SL 侧）

```sl
import SLangRender;

# 1) 初始化渲染库（可显式指定后端，缺省 gl）
bool ok = SLang.Render.initialize()
if !ok
{
    Console.println( SLang.Render.errorString() )
}

# 2) 可选：运行期切换后端（QT 演示用；管线句柄/纹理随之失效）
bool vkOk = SLang.Render.initializeBackend( "vk" )
string list = SLang.Render.backendList()        # "gl,d3d11,vk,gles"
string cur  = SLang.Render.currentBackend()     # 当前实际生效后端
bool sup   = SLang.Render.isBackendSupported( "d3d11" )
```

探测语义：`vk` / `gles` 在库缺失时 `initializeBackend` 返回 `false` 而不崩溃，
上层据此跳过（RenderTest 对应阶段输出 SKIP）。

## 3. 后端信息查询

```sl
string gpu = SLang.Render.gpuName()       # glGetString(GL_RENDERER) / DXGI 适配器描述
string ver = SLang.Render.gpuVersion()
string inf = SLang.Render.rendererInfo()  # 一次性描述串
```

这些值也会进入 `RenderEnvironment`（见 `12-Environment-And-Diagnostics.md`）。

## 4. 四后端一致性验收（实现方式）

- GL/D3D11/GLES：运行时着色器翻译自同一份内建着色器源；
- Vulkan：**SPIR-V 固化着色器**（构建期生成，运行期不经 GLSL 编译），
  固化槽 `PROG_VK0..` 与内建槽一一对应（Phase G 复检退化等价）；
- 像素断言集（背景/三角/贴图/混合边界/后处理灰度）在四后端重跑，
  阈值完全一致 → "不同驱动渲染一样效果"。

## 5. 注意事项

1. `initializeBackend` 之后必须**重新创建**管线与纹理（句柄全部失效）；
2. GDI/DXGI 的窗口路径未实现——当前只有离屏 + 回读，QT 显示经
   `QLabel.setPixmapRgba` 完成像素上屏；
3. 后端错误统一写入 `SLang.Render.errorString()`，也可从
   `RenderEnvironment.lastErrorText` 读取。
