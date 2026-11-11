/*
 * sl_render_lib.c —— SLangRender 模块原生实现（产物 sl_render_lib.dll）
 * ==========================================================================
 * 位于 Windows OpenGL（opengl32.dll，系统自带）之上的一层扁平 C ABI
 * 包装，供 Render.sl 通过 @DllStaticImport 静态绑定直调（opcode 77）。
 *
 * 设计取舍（与 sl_cuda_lib.c 同哲学）：
 *   1) **零 SDK 依赖**：构建期只需要 MSVC（本工程无任何外部 include /
 *      lib），WGL 入口与 GL 3.3 core 函数全部运行期从 opengl32.dll
 *      解析。GL1.1/WGL1.0 基础符号（wglCreateContext / glReadPixels /
 *      glGetError ...）在 opengl32.dll 导出表，GetProcAddress 直取；
 *      GL 1.2+ / WGL_ARB 扩展符号（glCreateShader /
 *      wglCreateContextAttribsARB ...）经 wglGetProcAddress 解析
 *      （该入口要求当前线程已绑 context，故先建 dummy context）。
 *   2) **离屏渲染**：隐藏窗口 + GL 3.3 core 上下文只提供执行环境，
 *      绘制目标是 FBO（RGBA8 颜色纹理 + DEPTH24_STENCIL8）。窗口
 *      永不显示、永不 SwapBuffers——像素出口是 glReadPixels 回读
 *      到调用方原生块（renderTexture 通道），由上层（QT QLabel
 *      setPixmapRgba 等）填充进真实窗口。
 *   3) **句柄化 + 多目标**：SlrContext（FBO 三件套 + 帧计数）收敛为
 *      Int64 句柄（静态槽表，最多 64 个），0 恒无效。
 *   4) **线程串行化**：GL 上下文线程亲和 → 全入口临界区 + 每次
 *      wglMakeCurrent / 用毕置空。任意线程调用安全，并发渲染退化为
 *      串行排队（对帧循环场景无影响——典型为 QTimer GUI 线程单调用方）。
 *
 * 三角形管线（slr_init 一次装配）：
 *   VS: #version 330 core / in vec2 aPos; -> gl_Position
 *   FS: uniform vec3 uColor; -> outColor = vec4(uColor, 1.0)
 *   顶点（NDC，居中大三角）：(-0.6,-0.5) (0.6,-0.5) (0.0,0.7)
 *
 * 回读行序：glReadPixels 原点在左下（bottom-up），调用方图像约定
 * 顶行在前（top-down，QImage Format_RGBA8888 同构）——本库内部逐行
 * 翻转后写出，上层无需感知。
 */

#include "vm_sl_render.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ========================================================================
 * GL / WGL 最小类型面与常量（等价 GL3 头的公开子集，手写声明）
 * ======================================================================== */

typedef int            GLenum;
typedef int            GLint;
typedef unsigned int   GLuint;
typedef char           GLchar;
typedef unsigned char  GLboolean;
typedef int            GLsizei;
typedef float          GLfloat;
typedef ptrdiff_t      GLsizeiptr;
typedef void           GLvoid;

#define GL_FALSE             0
#define GL_TRUE              1
#define GL_NO_ERROR          0
#define GL_TRIANGLES         0x0004
#define GL_FLOAT             0x1406
#define GL_COLOR_BUFFER_BIT  0x00004000
#define GL_DEPTH_BUFFER_BIT  0x00000100
#define GL_RGBA              0x1908
#define GL_UNSIGNED_BYTE     0x1401
#define GL_COMPILE_STATUS    0x8B81
#define GL_LINK_STATUS       0x8B82
#define GL_ARRAY_BUFFER      0x8892
#define GL_STATIC_DRAW       0x88E4
#define GL_VERTEX_SHADER     0x8B31
#define GL_FRAGMENT_SHADER   0x8B30
#define GL_TEXTURE_2D        0x0DE1
#define GL_TEXTURE0          0x84C0
#define GL_FRAMEBUFFER       0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_RENDERBUFFER      0x8D41
#define GL_DEPTH24_STENCIL8  0x88F0
#define GL_DEPTH_STENCIL_ATTACHMENT 0x821A
#define GL_FRAMEBUFFER_COMPLETE    0x8CD5

#define WGL_CONTEXT_MAJOR_VERSION_ARB   0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB   0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB    0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001

/* GL 1.1 / WGL 1.0 基础符号（opengl32.dll 导出表直取） */
typedef PROC   (WINAPI *PFN_wglGetProcAddress)(LPCSTR);
typedef HGLRC  (WINAPI *PFN_wglCreateContext)(HDC);
typedef BOOL   (WINAPI *PFN_wglMakeCurrent)(HDC, HGLRC);
typedef BOOL   (WINAPI *PFN_wglDeleteContext)(HGLRC);
typedef void   (WINAPI *PFN_glReadPixels)(GLint, GLint, GLint, GLint, GLenum, GLenum, void*);
typedef GLenum (WINAPI *PFN_glGetError)(void);
typedef void   (WINAPI *PFN_glFinish)(void);

/* WGL_ARB 扩展（经 wglGetProcAddress 解析，需 dummy context 在前） */
typedef HGLRC  (WINAPI *PFN_wglCreateContextAttribsARB)(HDC, HGLRC, const int*);

/* GL 1.2+ / 2.0 / 3.0 core（经 wglGetProcAddress 解析） */
typedef void   (WINAPI *PFN_glClearColor)(GLfloat, GLfloat, GLfloat, GLfloat);
typedef void   (WINAPI *PFN_glClear)(GLenum);
typedef void   (WINAPI *PFN_glViewport)(GLint, GLint, GLint, GLint);
typedef GLuint (WINAPI *PFN_glCreateShader)(GLenum);
typedef void   (WINAPI *PFN_glShaderSource)(GLuint, GLint, const GLchar* const*, const GLint*);
typedef void   (WINAPI *PFN_glCompileShader)(GLuint);
typedef void   (WINAPI *PFN_glGetShaderiv)(GLuint, GLenum, GLint*);
typedef void   (WINAPI *PFN_glGetShaderInfoLog)(GLuint, GLint, GLint*, GLchar*);
typedef void   (WINAPI *PFN_glDeleteShader)(GLuint);
typedef GLuint (WINAPI *PFN_glCreateProgram)(void);
typedef void   (WINAPI *PFN_glAttachShader)(GLuint, GLuint);
typedef void   (WINAPI *PFN_glLinkProgram)(GLuint);
typedef void   (WINAPI *PFN_glGetProgramiv)(GLuint, GLenum, GLint*);
typedef void   (WINAPI *PFN_glGetProgramInfoLog)(GLuint, GLint, GLint*, GLchar*);
typedef void   (WINAPI *PFN_glDeleteProgram)(GLuint);
typedef void   (WINAPI *PFN_glUseProgram)(GLuint);
typedef GLint  (WINAPI *PFN_glGetUniformLocation)(GLuint, const GLchar*);
typedef void   (WINAPI *PFN_glUniform3f)(GLint, GLfloat, GLfloat, GLfloat);
typedef void   (WINAPI *PFN_glGenVertexArrays)(GLint, GLuint*);
typedef void   (WINAPI *PFN_glBindVertexArray)(GLuint);
typedef void   (WINAPI *PFN_glDeleteVertexArrays)(GLint, const GLuint*);
typedef void   (WINAPI *PFN_glGenBuffers)(GLint, GLuint*);
typedef void   (WINAPI *PFN_glBindBuffer)(GLenum, GLuint);
typedef void   (WINAPI *PFN_glBufferData)(GLenum, GLsizeiptr, const void*, GLenum);
typedef void   (WINAPI *PFN_glDeleteBuffers)(GLint, const GLuint*);
typedef void   (WINAPI *PFN_glEnableVertexAttribArray)(GLuint);
typedef void   (WINAPI *PFN_glVertexAttribPointer)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void*);
typedef void   (WINAPI *PFN_glDrawArrays)(GLenum, GLint, GLint);
typedef void   (WINAPI *PFN_glGenFramebuffers)(GLint, GLuint*);
typedef void   (WINAPI *PFN_glBindFramebuffer)(GLenum, GLuint);
typedef void   (WINAPI *PFN_glFramebufferTexture2D)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef GLenum (WINAPI *PFN_glCheckFramebufferStatus)(GLenum);
typedef void   (WINAPI *PFN_glDeleteFramebuffers)(GLint, const GLuint*);
typedef void   (WINAPI *PFN_glGenRenderbuffers)(GLint, GLuint*);
typedef void   (WINAPI *PFN_glBindRenderbuffer)(GLenum, GLuint);
typedef void   (WINAPI *PFN_glRenderbufferStorage)(GLenum, GLenum, GLint, GLint);
typedef void   (WINAPI *PFN_glFramebufferRenderbuffer)(GLenum, GLenum, GLenum, GLuint);
typedef void   (WINAPI *PFN_glDeleteRenderbuffers)(GLint, const GLuint*);
typedef void   (WINAPI *PFN_glGenTextures)(GLint, GLuint*);
typedef void   (WINAPI *PFN_glBindTexture)(GLenum, GLuint);
typedef void   (WINAPI *PFN_glTexImage2D)(GLenum, GLint, GLint, GLint, GLint, GLint, GLenum, GLenum, const void*);
typedef void   (WINAPI *PFN_glTexParameteri)(GLenum, GLenum, GLint);
typedef void   (WINAPI *PFN_glDeleteTextures)(GLint, const GLuint*);
typedef const GLchar* (WINAPI *PFN_glGetString)(GLenum);

/* ========================================================================
 * 全局状态
 * ======================================================================== */

static CRITICAL_SECTION s_lock;
static int              s_lock_ready = 0;

static HMODULE s_opengl32 = NULL;      /* LoadLibrary 一次，永不卸载 */
static int     s_load_failed = 0;      /* opengl32.dll 缺失后不再重试 */

/* 基础符号（GetProcAddress 直取） */
static PFN_wglGetProcAddress       p_wglGetProcAddress;
static PFN_wglCreateContext        p_wglCreateContext;
static PFN_wglMakeCurrent          p_wglMakeCurrent;
static PFN_wglDeleteContext        p_wglDeleteContext;
static PFN_glReadPixels            p_glReadPixels;
static PFN_glGetError              p_glGetError;
static PFN_glFinish                p_glFinish;

/* 扩展符号（wglGetProcAddress 解析） */
static PFN_wglCreateContextAttribsARB p_wglCreateContextAttribsARB;
static PFN_glClearColor             p_glClearColor;
static PFN_glClear                  p_glClear;
static PFN_glViewport               p_glViewport;
static PFN_glCreateShader           p_glCreateShader;
static PFN_glShaderSource           p_glShaderSource;
static PFN_glCompileShader          p_glCompileShader;
static PFN_glGetShaderiv            p_glGetShaderiv;
static PFN_glGetShaderInfoLog       p_glGetShaderInfoLog;
static PFN_glDeleteShader           p_glDeleteShader;
static PFN_glCreateProgram          p_glCreateProgram;
static PFN_glAttachShader           p_glAttachShader;
static PFN_glLinkProgram            p_glLinkProgram;
static PFN_glGetProgramiv           p_glGetProgramiv;
static PFN_glGetProgramInfoLog      p_glGetProgramInfoLog;
static PFN_glDeleteProgram          p_glDeleteProgram;
static PFN_glUseProgram             p_glUseProgram;
static PFN_glGetUniformLocation     p_glGetUniformLocation;
static PFN_glUniform3f              p_glUniform3f;
static PFN_glGenVertexArrays        p_glGenVertexArrays;
static PFN_glBindVertexArray        p_glBindVertexArray;
static PFN_glDeleteVertexArrays     p_glDeleteVertexArrays;
static PFN_glGenBuffers             p_glGenBuffers;
static PFN_glBindBuffer             p_glBindBuffer;
static PFN_glBufferData             p_glBufferData;
static PFN_glDeleteBuffers          p_glDeleteBuffers;
static PFN_glEnableVertexAttribArray p_glEnableVertexAttribArray;
static PFN_glVertexAttribPointer    p_glVertexAttribPointer;
static PFN_glDrawArrays             p_glDrawArrays;
static PFN_glGenFramebuffers        p_glGenFramebuffers;
static PFN_glBindFramebuffer        p_glBindFramebuffer;
static PFN_glFramebufferTexture2D   p_glFramebufferTexture2D;
static PFN_glCheckFramebufferStatus p_glCheckFramebufferStatus;
static PFN_glDeleteFramebuffers     p_glDeleteFramebuffers;
static PFN_glGenRenderbuffers       p_glGenRenderbuffers;
static PFN_glBindRenderbuffer       p_glBindRenderbuffer;
static PFN_glRenderbufferStorage    p_glRenderbufferStorage;
static PFN_glFramebufferRenderbuffer p_glFramebufferRenderbuffer;
static PFN_glDeleteRenderbuffers    p_glDeleteRenderbuffers;
static PFN_glGenTextures            p_glGenTextures;
static PFN_glBindTexture            p_glBindTexture;
static PFN_glTexImage2D             p_glTexImage2D;
static PFN_glTexParameteri          p_glTexParameteri;
static PFN_glDeleteTextures         p_glDeleteTextures;
static PFN_glGetString              p_glGetString;

/* GL 执行环境（单实例：隐藏窗口 + DC + 3.3 core 上下文） */
static HWND   s_hwnd   = NULL;
static HDC    s_hdc    = NULL;
static HGLRC  s_hglrc  = NULL;
static int    s_ready  = 0;            /* slr_init 成功过 */

/* 三角形管线（全局共享：shader program + VAO + VBO + uniform 槽） */
static GLuint s_prog   = 0;
static GLuint s_vao    = 0;
static GLuint s_vbo    = 0;
static GLint  s_loc_color = -1;

/* 回读中转缓冲（行翻转用；按需增长） */
static unsigned char* s_stage = NULL;
static size_t         s_stage_cap = 0;

/* 设备信息字符串缓存（init 时抓取一次） */
static char s_renderer[256] = "unknown";
static char s_version[64]   = "unknown";

/* 粘性错误码：每个入口先清零；0 = 无错 */
static __declspec(thread) int t_last = 0;

/* 渲染目标槽表（句柄 = 槽下标 + 1，0 恒无效） */
typedef struct SlrTarget
{
    int     used;
    int     w;
    int     h;
    GLuint  fbo;
    GLuint  colorTex;
    GLuint  depthRb;
    int64_t frames;
} SlrTarget;
#define SLR_MAX_TARGETS 64
static SlrTarget s_targets[SLR_MAX_TARGETS];

/* ========================================================================
 * 内部工具
 * ======================================================================== */

static void slr_set(int err) { t_last = err; }

static void slr_lock(void)
{
    if (!s_lock_ready) { InitializeCriticalSection(&s_lock); s_lock_ready = 1; }
    EnterCriticalSection(&s_lock);
}
static void slr_unlock(void) { LeaveCriticalSection(&s_lock); }

/* opengl32.dll 基础符号装载（幂等；成功返回 1） */
static int slr_load_opengl32(void)
{
    if (s_opengl32 != NULL) return 1;
    if (s_load_failed) { slr_set(SLR_E_OPENGL_MISSING); return 0; }
    s_opengl32 = LoadLibraryA("opengl32.dll");
    if (s_opengl32 == NULL) { s_load_failed = 1; slr_set(SLR_E_OPENGL_MISSING); return 0; }
    p_wglGetProcAddress = (PFN_wglGetProcAddress)(void*)GetProcAddress(s_opengl32, "wglGetProcAddress");
    p_wglCreateContext  = (PFN_wglCreateContext)(void*)GetProcAddress(s_opengl32, "wglCreateContext");
    p_wglMakeCurrent    = (PFN_wglMakeCurrent)(void*)GetProcAddress(s_opengl32, "wglMakeCurrent");
    p_wglDeleteContext  = (PFN_wglDeleteContext)(void*)GetProcAddress(s_opengl32, "wglDeleteContext");
    p_glReadPixels      = (PFN_glReadPixels)(void*)GetProcAddress(s_opengl32, "glReadPixels");
    p_glGetError        = (PFN_glGetError)(void*)GetProcAddress(s_opengl32, "glGetError");
    p_glFinish          = (PFN_glFinish)(void*)GetProcAddress(s_opengl32, "glFinish");
    if (!p_wglGetProcAddress || !p_wglCreateContext || !p_wglMakeCurrent ||
        !p_wglDeleteContext || !p_glReadPixels || !p_glGetError || !p_glFinish)
    {
        s_load_failed = 1;
        slr_set(SLR_E_OPENGL_MISSING);
        return 0;
    }
    return 1;
}

/* 双通道符号解析（要求当前线程已绑 context）：
   1) wglGetProcAddress —— ICD 路由，覆盖 GL 1.1+ 全部。按 WGL 文档，
      命中"不支持"时可能返回 NULL / 1 / 2 / -1，一并视为失败；
   2) GetProcAddress(opengl32.dll) —— 仅 GL 1.0/1.1 老函数在 opengl32
      导出表有兜底（glClearColor / glClear / glViewport / glDrawArrays /
      glGenTextures / glBindTexture / glTexImage2D / glTexParameteri /
      glDeleteTextures / glGetString ...）；GL 1.2+ 符号此处天然落空，
      行为不变。此通道防 ICD 对 1.1 老符号返回 NULL 的边角环境
      （RDP / 软件 GDI Generic 渲染器）。 */
static void* slr_sym(const char* name)
{
    void* p = (void*)(intptr_t)p_wglGetProcAddress(name);
    if (p == NULL || p == (void*)(intptr_t)1 || p == (void*)(intptr_t)2
        || p == (void*)(intptr_t)-1)
    {
        p = (void*)GetProcAddress(s_opengl32, name);
    }
    return p;
}

/* 扩展符号解析（要求当前线程已绑 context）。
   GL core 符号缺失 -> 0（SLR_E_GL_SYMBOL）。 */
static int slr_resolve_ext(void)
{
    p_glClearColor             = (PFN_glClearColor)slr_sym("glClearColor");
    p_glClear                  = (PFN_glClear)slr_sym("glClear");
    p_glViewport               = (PFN_glViewport)slr_sym("glViewport");
    p_glCreateShader           = (PFN_glCreateShader)slr_sym("glCreateShader");
    p_glShaderSource           = (PFN_glShaderSource)slr_sym("glShaderSource");
    p_glCompileShader          = (PFN_glCompileShader)slr_sym("glCompileShader");
    p_glGetShaderiv            = (PFN_glGetShaderiv)slr_sym("glGetShaderiv");
    p_glGetShaderInfoLog       = (PFN_glGetShaderInfoLog)slr_sym("glGetShaderInfoLog");
    p_glDeleteShader           = (PFN_glDeleteShader)slr_sym("glDeleteShader");
    p_glCreateProgram          = (PFN_glCreateProgram)slr_sym("glCreateProgram");
    p_glAttachShader           = (PFN_glAttachShader)slr_sym("glAttachShader");
    p_glLinkProgram            = (PFN_glLinkProgram)slr_sym("glLinkProgram");
    p_glGetProgramiv           = (PFN_glGetProgramiv)slr_sym("glGetProgramiv");
    p_glGetProgramInfoLog      = (PFN_glGetProgramInfoLog)slr_sym("glGetProgramInfoLog");
    p_glDeleteProgram          = (PFN_glDeleteProgram)slr_sym("glDeleteProgram");
    p_glUseProgram             = (PFN_glUseProgram)slr_sym("glUseProgram");
    p_glGetUniformLocation     = (PFN_glGetUniformLocation)slr_sym("glGetUniformLocation");
    p_glUniform3f              = (PFN_glUniform3f)slr_sym("glUniform3f");
    p_glGenVertexArrays        = (PFN_glGenVertexArrays)slr_sym("glGenVertexArrays");
    p_glBindVertexArray        = (PFN_glBindVertexArray)slr_sym("glBindVertexArray");
    p_glDeleteVertexArrays     = (PFN_glDeleteVertexArrays)slr_sym("glDeleteVertexArrays");
    p_glGenBuffers             = (PFN_glGenBuffers)slr_sym("glGenBuffers");
    p_glBindBuffer             = (PFN_glBindBuffer)slr_sym("glBindBuffer");
    p_glBufferData             = (PFN_glBufferData)slr_sym("glBufferData");
    p_glDeleteBuffers          = (PFN_glDeleteBuffers)slr_sym("glDeleteBuffers");
    p_glEnableVertexAttribArray = (PFN_glEnableVertexAttribArray)slr_sym("glEnableVertexAttribArray");
    p_glVertexAttribPointer    = (PFN_glVertexAttribPointer)slr_sym("glVertexAttribPointer");
    p_glDrawArrays             = (PFN_glDrawArrays)slr_sym("glDrawArrays");
    p_glGenFramebuffers        = (PFN_glGenFramebuffers)slr_sym("glGenFramebuffers");
    p_glBindFramebuffer        = (PFN_glBindFramebuffer)slr_sym("glBindFramebuffer");
    p_glFramebufferTexture2D   = (PFN_glFramebufferTexture2D)slr_sym("glFramebufferTexture2D");
    p_glCheckFramebufferStatus = (PFN_glCheckFramebufferStatus)slr_sym("glCheckFramebufferStatus");
    p_glDeleteFramebuffers     = (PFN_glDeleteFramebuffers)slr_sym("glDeleteFramebuffers");
    p_glGenRenderbuffers       = (PFN_glGenRenderbuffers)slr_sym("glGenRenderbuffers");
    p_glBindRenderbuffer       = (PFN_glBindRenderbuffer)slr_sym("glBindRenderbuffer");
    p_glRenderbufferStorage    = (PFN_glRenderbufferStorage)slr_sym("glRenderbufferStorage");
    p_glFramebufferRenderbuffer= (PFN_glFramebufferRenderbuffer)slr_sym("glFramebufferRenderbuffer");
    p_glDeleteRenderbuffers    = (PFN_glDeleteRenderbuffers)slr_sym("glDeleteRenderbuffers");
    p_glGenTextures            = (PFN_glGenTextures)slr_sym("glGenTextures");
    p_glBindTexture            = (PFN_glBindTexture)slr_sym("glBindTexture");
    p_glTexImage2D             = (PFN_glTexImage2D)slr_sym("glTexImage2D");
    p_glTexParameteri          = (PFN_glTexParameteri)slr_sym("glTexParameteri");
    p_glDeleteTextures         = (PFN_glDeleteTextures)slr_sym("glDeleteTextures");
    p_glGetString              = (PFN_glGetString)slr_sym("glGetString");

    if (!p_glClearColor || !p_glClear || !p_glViewport || !p_glCreateShader ||
        !p_glShaderSource || !p_glCompileShader || !p_glGetShaderiv ||
        !p_glCreateProgram || !p_glAttachShader || !p_glLinkProgram ||
        !p_glGetProgramiv || !p_glUseProgram || !p_glGetUniformLocation ||
        !p_glUniform3f || !p_glGenVertexArrays || !p_glBindVertexArray ||
        !p_glGenBuffers || !p_glBindBuffer || !p_glBufferData ||
        !p_glEnableVertexAttribArray || !p_glVertexAttribPointer ||
        !p_glDrawArrays || !p_glGenFramebuffers || !p_glBindFramebuffer ||
        !p_glFramebufferTexture2D || !p_glCheckFramebufferStatus ||
        !p_glGenRenderbuffers || !p_glBindRenderbuffer ||
        !p_glRenderbufferStorage || !p_glFramebufferRenderbuffer ||
        !p_glGenTextures || !p_glBindTexture || !p_glTexImage2D ||
        !p_glTexParameteri || !p_glDeleteTextures)
    {
        slr_set(SLR_E_GL_SYMBOL);
        return 0;
    }
    return 1;
}

/* 三角形 shader 源码 */
static const GLchar* SLR_VS_SRC =
    "#version 330 core\n"
    "layout(location = 0) in vec2 aPos;\n"
    "void main()\n"
    "{\n"
    "    gl_Position = vec4(aPos, 0.0, 1.0);\n"
    "}\n";

static const GLchar* SLR_FS_SRC =
    "#version 330 core\n"
    "uniform vec3 uColor;\n"
    "out vec4 outColor;\n"
    "void main()\n"
    "{\n"
    "    outColor = vec4(uColor, 1.0);\n"
    "}\n";

/* 装配三角形管线（要求上下文已 current）。成功返回 1。 */
static int slr_build_pipeline(void)
{
    GLuint vs = 0, fs = 0;
    GLint ok = 0;
    static const GLfloat verts[6] = { -0.6f, -0.5f,   0.6f, -0.5f,   0.0f, 0.7f };

    vs = p_glCreateShader(GL_VERTEX_SHADER);
    fs = p_glCreateShader(GL_FRAGMENT_SHADER);
    if (!vs || !fs) { slr_set(SLR_E_SHADER); return 0; }
    p_glShaderSource(vs, 1, &SLR_VS_SRC, NULL);
    p_glCompileShader(vs);
    p_glGetShaderiv(vs, GL_COMPILE_STATUS, &ok);
    if (!ok) { p_glDeleteShader(vs); p_glDeleteShader(fs); slr_set(SLR_E_SHADER); return 0; }
    p_glShaderSource(fs, 1, &SLR_FS_SRC, NULL);
    p_glCompileShader(fs);
    p_glGetShaderiv(fs, GL_COMPILE_STATUS, &ok);
    if (!ok) { p_glDeleteShader(vs); p_glDeleteShader(fs); slr_set(SLR_E_SHADER); return 0; }

    s_prog = p_glCreateProgram();
    p_glAttachShader(s_prog, vs);
    p_glAttachShader(s_prog, fs);
    p_glLinkProgram(s_prog);
    p_glGetProgramiv(s_prog, GL_LINK_STATUS, &ok);
    p_glDeleteShader(vs);
    p_glDeleteShader(fs);
    if (!ok || !s_prog) { s_prog = 0; slr_set(SLR_E_SHADER); return 0; }

    s_loc_color = p_glGetUniformLocation(s_prog, "uColor");

    p_glGenVertexArrays(1, &s_vao);
    p_glBindVertexArray(s_vao);
    p_glGenBuffers(1, &s_vbo);
    p_glBindBuffer(GL_ARRAY_BUFFER, s_vbo);
    p_glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
    p_glEnableVertexAttribArray(0);
    p_glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), (void*)0);
    p_glBindVertexArray(0);
    p_glBindBuffer(GL_ARRAY_BUFFER, 0);
    return 1;
}

/* （重）建目标的 FBO 三件套（要求上下文已 current）。成功返回 1。 */
static int slr_target_rebuild(SlrTarget* t)
{
    /* 清旧 */
    if (t->fbo)      { p_glDeleteFramebuffers(1, &t->fbo);      t->fbo = 0; }
    if (t->colorTex) { p_glDeleteTextures(1, &t->colorTex);     t->colorTex = 0; }
    if (t->depthRb)  { p_glDeleteRenderbuffers(1, &t->depthRb); t->depthRb = 0; }

    /* 颜色纹理 RGBA8（无 mipmap，NEAREST 采样） */
    p_glGenFramebuffers(1, &t->fbo);
    p_glGenTextures(1, &t->colorTex);
    p_glBindTexture(GL_TEXTURE_2D, t->colorTex);
    p_glTexParameteri(GL_TEXTURE_2D, 0x2801 /* GL_TEXTURE_MIN_FILTER */, 0x2600 /* GL_NEAREST */);
    p_glTexParameteri(GL_TEXTURE_2D, 0x2800 /* GL_TEXTURE_MAG_FILTER */, 0x2600 /* GL_NEAREST */);
    p_glTexImage2D(GL_TEXTURE_2D, 0, 0x8058 /* GL_RGBA8 */, t->w, t->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    p_glBindTexture(GL_TEXTURE_2D, 0);
    if (!t->fbo || !t->colorTex) { slr_set(SLR_E_FBO); return 0; }

    /* 深度模板渲染缓冲 */
    p_glGenRenderbuffers(1, &t->depthRb);
    p_glBindRenderbuffer(GL_RENDERBUFFER, t->depthRb);
    p_glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, t->w, t->h);
    p_glBindRenderbuffer(GL_RENDERBUFFER, 0);

    /* 组装 FBO */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->colorTex, 0);
    p_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, t->depthRb);
    if (p_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
        slr_set(SLR_E_FBO);
        return 0;
    }
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return 1;
}

/* 句柄 <-> 槽位 */
static SlrTarget* slr_target_of(int64_t h)
{
    if (h <= 0 || h > SLR_MAX_TARGETS) { slr_set(SLR_E_BAD_HANDLE); return NULL; }
    {
        SlrTarget* t = &s_targets[h - 1];
        if (!t->used) { slr_set(SLR_E_BAD_HANDLE); return NULL; }
        return t;
    }
}

/* 绑定 GL 上下文到当前线程。成功返回 1。 */
static int slr_begin_gl(void)
{
    if (!s_ready) { slr_set(SLR_E_NOT_INITIALIZED); return 0; }
    if (!p_wglMakeCurrent(s_hdc, s_hglrc)) { slr_set(SLR_E_CONTEXT_CURRENT); return 0; }
    return 1;
}
static void slr_end_gl(void)
{
    if (p_wglMakeCurrent) p_wglMakeCurrent(NULL, NULL);
}

/* 中转缓冲扩容（>= bytes）。失败置 SLR_E_MEMORY 返回 0。 */
static int slr_stage_reserve(size_t bytes)
{
    unsigned char* p;
    if (s_stage_cap >= bytes) return 1;
    p = (unsigned char*)realloc(s_stage, bytes);
    if (!p) { slr_set(SLR_E_MEMORY); return 0; }
    s_stage = p;
    s_stage_cap = bytes;
    return 1;
}

/* ========================================================================
 * 导出：错误 / 设备信息
 * ======================================================================== */

SLR_API int32_t slr_last_error(void)
{
    return t_last;
}

SLR_API const char* slr_error_string(int32_t err)
{
    if (err == 0) err = t_last;
    switch (err)
    {
    case 0:                      return "no error";
    case SLR_E_OPENGL_MISSING:   return "opengl32.dll missing or base symbols unavailable";
    case SLR_E_WINDOW:           return "hidden window / device context creation failed";
    case SLR_E_PIXEL_FORMAT:     return "pixel format select/set failed";
    case SLR_E_CONTEXT:          return "WGL context creation failed";
    case SLR_E_NO_ARB:           return "WGL_ARB_create_context extension unavailable";
    case SLR_E_GL_SYMBOL:        return "GL 3.3 core symbol resolution failed";
    case SLR_E_NOT_INITIALIZED:  return "slr_init not yet succeeded";
    case SLR_E_BAD_HANDLE:       return "invalid render target handle";
    case SLR_E_BAD_PARAM:        return "invalid argument (zero size / null pointer)";
    case SLR_E_FBO:              return "framebuffer object creation/incomplete";
    case SLR_E_SHADER:           return "shader compile or program link failed";
    case SLR_E_MEMORY:           return "internal staging buffer allocation failed";
    case SLR_E_CONTEXT_CURRENT:  return "wglMakeCurrent failed (thread state corrupted?)";
    default:                      return "unknown error";
    }
}

SLR_API const char* slr_renderer_string(void) { return s_renderer; }
SLR_API const char* slr_version_string(void)  { return s_version; }

/* ========================================================================
 * 导出：init / uninit
 * ======================================================================== */

SLR_API int32_t slr_init(void)
{
    WNDCLASSA wc;
    PIXELFORMATDESCRIPTOR pfd;
    int pf = 0;
    HGLRC dummy = NULL;
    const int attribs[] =
    {
        WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
        WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0
    };
    t_last = 0;
    slr_lock();
    if (s_ready) { slr_unlock(); return 1; }
    if (!slr_load_opengl32()) { slr_unlock(); return 0; }

    /* 1) 隐藏窗口 + 像素格式 */
    memset(&wc, 0, sizeof(wc));
    wc.style         = CS_OWNDC;
    wc.lpfnWndProc   = DefWindowProcA;
    wc.hInstance     = GetModuleHandleA(NULL);
    wc.lpszClassName = "SLangRenderHidden";
    RegisterClassA(&wc);
    s_hwnd = CreateWindowExA(0, wc.lpszClassName, "slrender", WS_OVERLAPPEDWINDOW,
                             0, 0, 8, 8, NULL, NULL, wc.hInstance, NULL);
    if (!s_hwnd) { slr_set(SLR_E_WINDOW); goto fail_unlock; }
    s_hdc = GetDC(s_hwnd);
    if (!s_hdc) { slr_set(SLR_E_WINDOW); goto fail_window; }

    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize      = sizeof(pfd);
    pfd.nVersion   = 1;
    pfd.dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 24;
    pfd.cDepthBits = 24;
    pf = ChoosePixelFormat(s_hdc, &pfd);
    if (!pf || !SetPixelFormat(s_hdc, pf, &pfd))
    {
        slr_set(SLR_E_PIXEL_FORMAT);
        goto fail_window;
    }

    /* 2) dummy context -> 解析符号表 -> 正式上下文。
       像素格式保持不动（FBO 渲染不依赖默认帧缓冲的能力位）。 */
    dummy = p_wglCreateContext(s_hdc);
    if (!dummy) { slr_set(SLR_E_CONTEXT); goto fail_window; }
    if (!p_wglMakeCurrent(s_hdc, dummy)) { p_wglDeleteContext(dummy); slr_set(SLR_E_CONTEXT); goto fail_window; }

    /* WGL_ARB_create_context（仅 wglGetProcAddress 通道，opengl32 导出表
       无此符号）；缺失/失败时下方回退传统上下文 */
    p_wglCreateContextAttribsARB =
        (PFN_wglCreateContextAttribsARB)(void*)p_wglGetProcAddress("wglCreateContextAttribsARB");

    if (!slr_resolve_ext())
    {
        p_wglMakeCurrent(NULL, NULL);
        p_wglDeleteContext(dummy);
        goto fail_window;
    }
    /* 设备信息（dummy context 下即可查询） */
    if (p_glGetString)
    {
        const GLchar* r = p_glGetString(0x1F01 /* GL_RENDERER */);
        const GLchar* v = p_glGetString(0x1F02 /* GL_VERSION */);
        if (r) { strncpy(s_renderer, r, sizeof(s_renderer) - 1); s_renderer[sizeof(s_renderer) - 1] = '\0'; }
        if (v) { strncpy(s_version, v, sizeof(s_version) - 1);   s_version[sizeof(s_version) - 1] = '\0'; }
    }
    p_wglMakeCurrent(NULL, NULL);
    p_wglDeleteContext(dummy);

    /* 3.3 core 上下文；失败回退传统上下文（兼容 profile，RDP / 软件 GL
       等无 WGL_ARB 环境也能跑——FBO/shader 在 GL 3.0+ 照常可用，
       GL 2.x 以下会在符号表检查处给出明确错误）。 */
    s_hglrc = p_wglCreateContextAttribsARB
        ? p_wglCreateContextAttribsARB(s_hdc, NULL, attribs) : NULL;
    if (s_hglrc == NULL)
    {
        s_hglrc = p_wglCreateContext(s_hdc);
        if (s_hglrc == NULL) { slr_set(SLR_E_CONTEXT); goto fail_window; }
    }

    /* 3) 装配三角形管线。此处不能走 slr_begin_gl——它以 s_ready 为门槛
       （未就绪置 SLR_E_NOT_INITIALIZED），而 s_ready 在本函数末尾才置位，
       鸡生蛋；直接 wglMakeCurrent。 */
    if (!p_wglMakeCurrent(s_hdc, s_hglrc))
    {
        p_wglDeleteContext(s_hglrc);
        s_hglrc = NULL;
        slr_set(SLR_E_CONTEXT_CURRENT);
        goto fail_window;
    }
    if (!slr_build_pipeline())
    {
        slr_end_gl();
        p_wglDeleteContext(s_hglrc);
        s_hglrc = NULL;
        goto fail_window;
    }
    slr_end_gl();

    s_ready = 1;
    slr_unlock();
    return 1;

fail_window:
    /* init 失败清理（重试不泄漏：窗口/DC 回收，符号表保留——
       opengl32.dll 仍装载，下次 init 重新走全流程） */
    if (s_hdc) { ReleaseDC(s_hwnd, s_hdc); s_hdc = NULL; }
    if (s_hwnd) { DestroyWindow(s_hwnd); s_hwnd = NULL; }
fail_unlock:
    slr_unlock();
    return 0;
}

SLR_API int32_t slr_uninit(void)
{
    int i;
    t_last = 0;
    slr_lock();
    if (!s_ready)
    {
        /* 幂等：未初始化也算成功 */
        slr_unlock();
        return 1;
    }
    if (slr_begin_gl())
    {
        for (i = 0; i < SLR_MAX_TARGETS; ++i)
        {
            SlrTarget* t = &s_targets[i];
            if (!t->used) continue;
            if (t->fbo)      { p_glDeleteFramebuffers(1, &t->fbo); }
            if (t->colorTex) { p_glDeleteTextures(1, &t->colorTex); }
            if (t->depthRb)  { p_glDeleteRenderbuffers(1, &t->depthRb); }
            memset(t, 0, sizeof(*t));
        }
        if (s_vbo)  { p_glDeleteBuffers(1, &s_vbo); s_vbo = 0; }
        if (s_vao)  { p_glDeleteVertexArrays(1, &s_vao); s_vao = 0; }
        if (s_prog) { p_glDeleteProgram(s_prog); s_prog = 0; }
        slr_end_gl();
    }
    if (s_hglrc) { p_wglDeleteContext(s_hglrc); s_hglrc = NULL; }
    if (s_hwnd)
    {
        if (s_hdc) { ReleaseDC(s_hwnd, s_hdc); s_hdc = NULL; }
        DestroyWindow(s_hwnd);
        s_hwnd = NULL;
    }
    s_ready = 0;
    /* opengl32.dll 保持装载（与 CUDA 库同策略：进程退出统一回收） */
    slr_unlock();
    return 1;
}

/* ========================================================================
 * 导出：渲染目标
 * ======================================================================== */

SLR_API int64_t slr_context_create(int32_t w, int32_t h)
{
    int i;
    t_last = 0;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) { slr_set(SLR_E_BAD_PARAM); return 0; }
    slr_lock();
    if (!s_ready) { slr_set(SLR_E_NOT_INITIALIZED); slr_unlock(); return 0; }

    for (i = 0; i < SLR_MAX_TARGETS; ++i)
    {
        SlrTarget* t = &s_targets[i];
        if (t->used) continue;
        t->used = 1;
        t->w = w;
        t->h = h;
        t->frames = 0;
        if (!slr_begin_gl()) { memset(t, 0, sizeof(*t)); slr_unlock(); return 0; }
        if (!slr_target_rebuild(t))
        {
            slr_end_gl();
            memset(t, 0, sizeof(*t));
            slr_unlock();
            return 0;
        }
        slr_end_gl();
        slr_unlock();
        return (int64_t)(i + 1);
    }
    slr_set(SLR_E_BAD_PARAM); /* 槽满 */
    slr_unlock();
    return 0;
}

SLR_API int32_t slr_context_destroy(int64_t ctx)
{
    SlrTarget* t;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (slr_begin_gl())
    {
        if (t->fbo)      { p_glDeleteFramebuffers(1, &t->fbo); }
        if (t->colorTex) { p_glDeleteTextures(1, &t->colorTex); }
        if (t->depthRb)  { p_glDeleteRenderbuffers(1, &t->depthRb); }
        slr_end_gl();
    }
    memset(t, 0, sizeof(*t));
    slr_unlock();
    return 1;
}

SLR_API int32_t slr_context_resize(int64_t ctx, int32_t w, int32_t h)
{
    SlrTarget* t;
    int ok;
    t_last = 0;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) { slr_set(SLR_E_BAD_PARAM); return 0; }
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (!slr_begin_gl()) { slr_unlock(); return 0; }
    t->w = w;
    t->h = h;
    ok = slr_target_rebuild(t);
    slr_end_gl();
    slr_unlock();
    return ok ? 1 : 0;
}

SLR_API int32_t slr_context_width(int64_t ctx)
{
    SlrTarget* t;
    int32_t v;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    v = t ? t->w : 0;
    slr_unlock();
    return v;
}

SLR_API int32_t slr_context_height(int64_t ctx)
{
    SlrTarget* t;
    int32_t v;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    v = t ? t->h : 0;
    slr_unlock();
    return v;
}

SLR_API int64_t slr_frame_count(int64_t ctx)
{
    SlrTarget* t;
    int64_t v;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    v = t ? t->frames : 0;
    slr_unlock();
    return v;
}

/* ========================================================================
 * 导出：渲染 / 回读
 * ======================================================================== */

SLR_API int32_t slr_clear(int64_t ctx, float r, float g, float b, float a)
{
    SlrTarget* t;
    int ok = 0;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (!slr_begin_gl()) { slr_unlock(); return 0; }
    p_glGetError(); /* 冲刷粘性错误（init/pipeline 期可能残留） */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, t->w, t->h);
    p_glClearColor(r, g, b, a);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (p_glGetError() == GL_NO_ERROR) ok = 1;
    slr_end_gl();
    slr_unlock();
    return ok;
}

SLR_API int32_t slr_draw_triangle(int64_t ctx, float r, float g, float b)
{
    SlrTarget* t;
    int ok = 0;
    t_last = 0;
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (!slr_begin_gl()) { slr_unlock(); return 0; }
    p_glGetError(); /* 冲刷粘性错误 */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, t->w, t->h);
    p_glUseProgram(s_prog);
    if (s_loc_color >= 0) p_glUniform3f(s_loc_color, r, g, b);
    p_glBindVertexArray(s_vao);
    p_glDrawArrays(GL_TRIANGLES, 0, 3);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    p_glFinish();
    if (p_glGetError() == GL_NO_ERROR) { ok = 1; t->frames++; }
    slr_end_gl();
    slr_unlock();
    return ok;
}

SLR_API int32_t slr_read_pixels(int64_t ctx, void* dst)
{
    SlrTarget* t;
    int ok = 0;
    size_t row;
    t_last = 0;
    if (!dst) { slr_set(SLR_E_BAD_PARAM); return 0; }
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (!slr_stage_reserve((size_t)t->w * t->h * 4)) { slr_unlock(); return 0; }
    if (!slr_begin_gl()) { slr_unlock(); return 0; }
    p_glGetError(); /* 冲刷粘性错误 */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glReadPixels(0, 0, t->w, t->h, GL_RGBA, GL_UNSIGNED_BYTE, s_stage);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (p_glGetError() == GL_NO_ERROR)
    {
        /* bottom-up -> top-down 行翻转后写出 */
        const size_t rb = (size_t)t->w * 4;
        unsigned char* out = (unsigned char*)dst;
        for (row = 0; row < (size_t)t->h; ++row)
        {
            memcpy(out + row * rb, s_stage + ((size_t)t->h - 1 - row) * rb, rb);
        }
        ok = 1;
    }
    slr_end_gl();
    slr_unlock();
    return ok;
}

SLR_API int32_t slr_render_frame(int64_t ctx, float r, float g, float b, void* dst)
{
    /* 深蓝黑背景 (0.06, 0.06, 0.10) —— 与三角形前景色形成稳定对比，
       供调用方做角落采样校验（背景像素可精确预测）。 */
    const float BG_R = 0.06f, BG_G = 0.06f, BG_B = 0.10f, BG_A = 1.0f;
    SlrTarget* t;
    int ok = 0;
    size_t row;
    t_last = 0;
    if (!dst) { slr_set(SLR_E_BAD_PARAM); return 0; }
    slr_lock();
    t = slr_target_of(ctx);
    if (!t) { slr_unlock(); return 0; }
    if (!slr_stage_reserve((size_t)t->w * t->h * 4)) { slr_unlock(); return 0; }
    if (!slr_begin_gl()) { slr_unlock(); return 0; }
    p_glGetError(); /* 冲刷粘性错误 */

    /* clear */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, t->w, t->h);
    p_glClearColor(BG_R, BG_G, BG_B, BG_A);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    /* draw */
    p_glUseProgram(s_prog);
    if (s_loc_color >= 0) p_glUniform3f(s_loc_color, r, g, b);
    p_glBindVertexArray(s_vao);
    p_glDrawArrays(GL_TRIANGLES, 0, 3);
    p_glBindVertexArray(0);
    p_glUseProgram(0);

    /* read（行翻转） */
    p_glReadPixels(0, 0, t->w, t->h, GL_RGBA, GL_UNSIGNED_BYTE, s_stage);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    p_glFinish();
    if (p_glGetError() == GL_NO_ERROR)
    {
        const size_t rb = (size_t)t->w * 4;
        unsigned char* out = (unsigned char*)dst;
        for (row = 0; row < (size_t)t->h; ++row)
        {
            memcpy(out + row * rb, s_stage + ((size_t)t->h - 1 - row) * rb, rb);
        }
        ok = 1;
        t->frames++;
    }
    slr_end_gl();
    slr_unlock();
    return ok;
}

/* ========================================================================
 * DLL 入口
 * ======================================================================== */

BOOL APIENTRY DllMain(HMODULE hMod, DWORD reason, LPVOID reserved)
{
    (void)hMod; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
    {
        if (!s_lock_ready) { InitializeCriticalSection(&s_lock); s_lock_ready = 1; }
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        /* GL 资源不在此销毁：析构顺序无法与 SL 侧对象生命周期对齐
           （与 CUDA 库同策略），进程退出由 OS 统一回收。 */
    }
    return TRUE;
}
