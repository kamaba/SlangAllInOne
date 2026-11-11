#ifndef VM_SL_RENDER_H
#define VM_SL_RENDER_H

/* ==========================================================================
 * vm_sl_render.h —— SLangRender 模块原生层导出声明（sl_render_lib.dll）
 * --------------------------------------------------------------------------
 * 本库是 Windows OpenGL（WGL + GL 3.3 core）**离屏渲染**的一层扁平 C ABI
 * 包装，供 Render.sl 通过 @DllStaticImport 静态绑定直调（opcode 77）：
 *
 *   - 零 SDK 依赖：构建期只需要 MSVC（无 gl.h / GL3.h / opengl32.lib），
 *     WGL 入口与 GL 3.3 core 函数全部运行期从 opengl32.dll（系统自带）
 *     LoadLibrary + wglGetProcAddress / GetProcAddress 双通道解析，
 *     因此 sl_render_lib.dll 自包含、随模块分发无额外依赖。
 *   - 离屏渲染模型：隐藏窗口 + WGL 3.3 core 上下文只提供 GL 执行环境，
 *     实际绘制目标为 FBO（RGBA8 颜色纹理 + DEPTH24_STENCIL8 深度缓冲），
 *     每帧经 glReadPixels 回读 RGBA8 像素到调用方原生内存块（SL 侧
 *     Core 的 Memory.alloc 块）——即"renderTexture 通道"，供 QT QLabel
 *     setPixmapRgba 等窗口填充显示，也可自存 PNG / 逐像素校验。
 *   - 句柄化：FBO 渲染目标（SlrContext）收敛为 Int64 句柄（0 恒为无效），
 *     支持多实例（最多 64 个）。
 *
 * 导出命名约定：统一前缀 slr_（SimpleLanguage Render）。
 * 调用约定：x64 cdecl（Windows x64 唯一），与 cvm sl_ffi_call 的
 *          INT 类（含指针 / utf8）/ DBL 类分类调度对齐。
 *
 * 参数个数上限：6（SL_FFI_MAX_ARGS），所有导出函数均满足。
 *
 * 错误约定（与 SLangCuda 的 slc_* 对齐）：
 *   - "成功与否"类导出（init / uninit / clear / draw / read / render_frame
 *     / resize）：int32_t 1 = 成功，0 = 失败，失败原因写入粘性 last_error
 *     （每次 slr_ 入口调用先清零）；
 *   - 返回句柄的函数（context_create）：0 = 失败；
 *   - 查询类（last_error / frame_count）：直接返回值。
 *
 * 线程约定：
 *   - GL 上下文是线程亲和的。本库内部对全部入口加临界区串行化，
 *     并在每次渲染入口处 wglMakeCurrent / 用毕即置空——任意线程调用
 *     均安全，但并发渲染只是串行排队（不并行）。
 *   - 帧循环典型形态：QT QTimer tick 回调（Qt GUI 线程）里调
 *     render_frame + QLabel setPixmapRgba，与 Qt 事件循环天然同线程。
 *
 * 像素布局约定（回读块 dst）：
 *   - RGBA8：每像素 4 字节（R,G,B,A），行主序，**顶行在前**（top-down，
 *     glReadPixels 的 bottom-up 行序已在本库内逐行翻转），与 QImage
 *     Format_RGBA8888 / 常见图像格式一致；
 *   - 块大小 = width * height * 4，由调用方分配（Memory.alloc）。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLR_API __declspec(dllexport)
#else
#  define SLR_API
#endif

/* ------------------------------------------------------------------ */
/* 本库合成错误码（负值；GL 枚举值恒 >= 0，互不冲突）                  */
/* ------------------------------------------------------------------ */

#define SLR_E_OPENGL_MISSING  (-1)   /* opengl32.dll 不存在 / 基础符号缺失 */
#define SLR_E_WINDOW          (-2)   /* 隐藏窗口 / DC 创建失败             */
#define SLR_E_PIXEL_FORMAT    (-3)   /* 像素格式选择 / 设置失败            */
#define SLR_E_CONTEXT         (-4)   /* WGL 上下文创建失败                 */
#define SLR_E_NO_ARB          (-5)   /* WGL_ARB 扩展（attribs context）缺失 */
#define SLR_E_GL_SYMBOL       (-6)   /* GL 3.3 core 符号解析失败           */
#define SLR_E_NOT_INITIALIZED (-7)   /* slr_init 尚未成功调用              */
#define SLR_E_BAD_HANDLE      (-8)   /* 句柄非法                           */
#define SLR_E_BAD_PARAM       (-9)   /* 参数非法（0 尺寸 / 空指针 / 越界） */
#define SLR_E_FBO             (-10)  /* FBO 创建 / 完整性检查失败          */
#define SLR_E_SHADER          (-11)  /* shader 编译 / program 链接失败     */
#define SLR_E_MEMORY          (-12)  /* 内部缓冲分配失败                   */
#define SLR_E_CONTEXT_CURRENT (-13)  /* wglMakeCurrent 失败（线程异常）    */

/* ------------------------------------------------------------------ */
/* 错误 / 设备信息                                                     */
/* ------------------------------------------------------------------ */

/* 粘性最近错误码：0 = 无错。每次 slr_ 入口调用都会先清零再执行。 */
SLR_API int32_t     slr_last_error(void);
/* 错误码转文本；err == 0 时取 last_error。永不返回 NULL。 */
SLR_API const char* slr_error_string(int32_t err);

/* 初始化：隐藏窗口 + WGL 3.3 core 上下文 + GL 符号表 + 三角形管线。
   幂等：成功后重复调用直接返回成功。 */
SLR_API int32_t     slr_init(void);

/* 反初始化：销毁全部渲染目标与 GL 资源（进程退出前可省略，OS 回收）。 */
SLR_API int32_t     slr_uninit(void);

/* GL_RENDERER 字符串（如 "NVIDIA GeForce RTX ..."）；不可用返回 "unknown"。 */
SLR_API const char* slr_renderer_string(void);
/* GL_VERSION 字符串（如 "3.3.0 NVIDIA ..."）；不可用返回 "unknown"。 */
SLR_API const char* slr_version_string(void);

/* ------------------------------------------------------------------ */
/* 渲染目标（FBO 离屏上下文）                                          */
/* ------------------------------------------------------------------ */

/* 创建 w x h 的 RGBA8 渲染目标，返回句柄；0 = 失败（原因见 last_error）。 */
SLR_API int64_t     slr_context_create(int32_t w, int32_t h);

/* 销毁渲染目标。 */
SLR_API int32_t     slr_context_destroy(int64_t ctx);

/* 重建为 w x h（内容丢失）。 */
SLR_API int32_t     slr_context_resize(int64_t ctx, int32_t w, int32_t h);

/* 查询目标宽度 / 高度；句柄非法返回 0。 */
SLR_API int32_t     slr_context_width(int64_t ctx);
SLR_API int32_t     slr_context_height(int64_t ctx);

/* 累计 draw 次数（动画帧计数探针）。 */
SLR_API int64_t     slr_frame_count(int64_t ctx);

/* ------------------------------------------------------------------ */
/* 渲染 / 回读                                                         */
/* ------------------------------------------------------------------ */

/* 纯色清屏（RGBA 各 0..1）。 */
SLR_API int32_t     slr_clear(int64_t ctx, float r, float g, float b, float a);

/* 绘制居中纯色大三角形（NDC 顶点固定；颜色经 uniform uColor 传入）。 */
SLR_API int32_t     slr_draw_triangle(int64_t ctx, float r, float g, float b);

/* 回读当前帧到 dst 块（RGBA8 top-down，w*h*4 字节；dst 为 SL 侧
   Memory.alloc 块地址）。不改变 GL 状态（只读操作）。 */
SLR_API int32_t     slr_read_pixels(int64_t ctx, void* dst);

/* 一步组合：深色背景清屏 + 三角形绘制 + 回读（帧循环主入口；
   背景固定 (0.06, 0.06, 0.10, 1.0)）。 */
SLR_API int32_t     slr_render_frame(int64_t ctx, float r, float g, float b,
                                     void* dst);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_RENDER_H */
