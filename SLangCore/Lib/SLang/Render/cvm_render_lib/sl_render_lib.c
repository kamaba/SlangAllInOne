/* =========================================================================
 * sl_render_lib.c —— SLangRender 原生渲染库 v2
 *
 * 零工具链依赖：WGL 与 GL 3.3 core 函数全部运行期从 opengl32.dll
 * 解析（wglGetProcAddress + GetProcAddress 双通道），构建/运行不需要
 * OpenGL SDK 头文件或 .lib。
 *
 * 架构（大部分逻辑在 C 层，SL 侧仅薄绑定）：
 *
 *   隐藏窗口 + WGL 3.3 core 上下文（进程唯一，临界区串行化）
 *     ├── v1 直连层：RenderContext（FBO 清屏/三角/回读）
 *     ├── 纹理注册表：slr_texture_create_rgba（top-down RGBA8 上传）
 *     └── Unity 风格 13 阶段管线 slr_pipeline_*：
 *
 *   1  beginFrame             渲染开始   绑定场景 FBO、清屏、帧计数
 *   2  prepareMaterials       准备物料   确认着色器程序/采样器常量就绪
 *   3  earlyUpdate            提前更新   对象动画（色相循环等）
 *   4  cullLayers             渲染层分层 cullingMask + 视域剔除
 *   5  assembleLayerData      层整理数据 排序出绘制列表（不透明前→后 /
 *                              透明后→前），计算 MVP，按 shader 分块
 *   6  uploadRenderData       传GPU数据  PerDraw CBUFFER（std140 UBO）
 *                              批量上传 MVP/颜色（对齐 SRP Batcher）
 *   7  renderShaderChunks     分块渲染   不透明段：按 shader 分组合批绘制
 *   8  updateCoreTime         核心时间   帧间隔 dt / 累计时间推进
 *   9  renderShaderSegments   分段渲染   透明段：混合开、深度写关、后→前
 *   10 assembleRenderedLayers 整理图层   图层位掩码汇总、状态复位
 *   11 postProcess            后处理     亮度/饱和度/暗角全屏 pass
 *   12 integrateLayers        逻辑整合   后处理结果 → 最终 renderTexture
 *   13 outputRenderTexture    输出       glReadPixels 回读 + 行翻 top-down
 *
 *   renderFrame = 1..13 一键；runStages 由 SL 侧逐阶段驱动（等价）。
 * ========================================================================= */
#include <windows.h>
#include <wincodec.h>       /* WIC 图片解码（PNG/JPEG/BMP），零 SDK .lib 依赖：
                               windowscodecs/uuid 由 pragma 注入 */
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "uuid.lib")
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "vm_sl_render.h"

/* ===================================================================== */
/* GL 类型 / 常量（手写，不依赖 SDK 头）                                  */
/* ===================================================================== */
typedef int         GLint;
typedef int         GLsizei;
typedef unsigned int GLuint;
typedef unsigned int GLenum;
typedef unsigned int GLbitfield;
typedef unsigned char GLboolean;
typedef float       GLfloat;
typedef char        GLchar;
typedef ptrdiff_t   GLintptr;
typedef ptrdiff_t   GLsizeiptr;

#define GL_NO_ERROR               0
#define GL_FALSE                  0
#define GL_TRUE                   1
#define GL_TRIANGLES              0x0004
#define GL_UNSIGNED_BYTE          0x1401
#define GL_FLOAT                  0x1406
#define GL_RGBA                   0x1908
#define GL_RGBA8                  0x8058
#define GL_DEPTH_COMPONENT24      0x81A6
#define GL_COLOR_BUFFER_BIT        0x00004000
#define GL_DEPTH_BUFFER_BIT       0x00000100
#define GL_BLEND                  0x0BE2
#define GL_SRC_ALPHA              0x0302
#define GL_ONE_MINUS_SRC_ALPHA    0x0303
#define GL_DEPTH_TEST             0x0B71
#define GL_DEPTH_FUNC             0x0B74
#define GL_SCISSOR_TEST           0x0C11
#define GL_LESS                   0x0201
#define GL_LEQUAL                 0x0203
#define GL_ARRAY_BUFFER           0x8892
#define GL_STATIC_DRAW            0x88E4
#define GL_DYNAMIC_DRAW           0x88E8
#define GL_UNIFORM_BUFFER         0x8A11
#define GL_TEXTURE_2D             0x0DE1
#define GL_TEXTURE0               0x84C0
#define GL_TEXTURE1               0x84C1
#define GL_TEXTURE_MIN_FILTER     0x2801
#define GL_TEXTURE_MAG_FILTER     0x2800
#define GL_TEXTURE_WRAP_S         0x2802
#define GL_TEXTURE_WRAP_T         0x2803
#define GL_LINEAR                 0x2601
#define GL_CLAMP_TO_EDGE          0x812F
#define GL_FRAMEBUFFER            0x8D40
#define GL_RENDERBUFFER           0x8D41
#define GL_COLOR_ATTACHMENT0      0x8CE0
#define GL_DEPTH_ATTACHMENT       0x8D00
#define GL_FRAMEBUFFER_COMPLETE   0x8CD5
#define GL_VERTEX_SHADER          0x8B31
#define GL_FRAGMENT_SHADER        0x8B30
#define GL_COMPILE_STATUS         0x8B81
#define GL_LINK_STATUS            0x8B82
#define GL_INFO_LOG_LENGTH        0x8B84
#define GL_PACK_ALIGNMENT         0x0D05
#define GL_UNPACK_ALIGNMENT       0x0CF5
#define GL_VENDOR                 0x1F00
#define GL_RENDERER               0x1F01
#define GL_VERSION                0x1F02

#ifndef APIENTRY
#define APIENTRY
#endif

/* ===================================================================== */
/* 全局状态                                                               */
/* ===================================================================== */
#define SLR_MAX_OBJECTS 64
#define SLR_MAX_CTX     16
#define SLR_MAX_PIPES   32
#define SLR_MAX_TEX     64
#define SLR_MAX_CAMERAS 8

/* clear_flags 位定义（相机清屏选项） */
#define SLR_CLEAR_COLOR 1
#define SLR_CLEAR_DEPTH 2

static int      s_ready = 0;
static HMODULE  s_hgl = NULL;
static HWND     s_hwnd = NULL;
static HDC      s_hdc = NULL;
static HGLRC    s_hrc = NULL;
static CRITICAL_SECTION s_lock;
static int      s_lock_init = 0;

static int      s_last_error = SLR_OK;
static char     s_err_detail[256] = { 0 };
static char     s_renderer_str[160] = "unknown";
static char     s_version_str[160] = "unknown";

/* ---- WGL 符号（opengl32.dll 直导出）---- */
typedef HGLRC (WINAPI *PFN_wglCreateContext)(HDC);
typedef BOOL  (WINAPI *PFN_wglMakeCurrent)(HDC, HGLRC);
typedef BOOL  (WINAPI *PFN_wglDeleteContext)(HGLRC);
typedef HGLRC (WINAPI *PFN_wglCreateContextAttribsARB)(HDC, HGLRC, const int*);
typedef PROC  (WINAPI *PFN_wglGetProcAddress)(LPCSTR);

static PFN_wglCreateContext          pwglCreateContext;
static PFN_wglMakeCurrent            pwglMakeCurrent;
static PFN_wglDeleteContext          pwglDeleteContext;
static PFN_wglCreateContextAttribsARB pwglCreateContextAttribsARB;
static PFN_wglGetProcAddress         pwglGetProcAddress;

/* ---- GL 函数指针 ---- */
#define GLDECL(name, ret, params) \
    typedef ret (APIENTRY *PFN_##name) params; \
    static PFN_##name p_##name = NULL;
GLDECL(glGetError,               GLenum, (void))
GLDECL(glEnable,                 void, (GLenum))
GLDECL(glDisable,                void, (GLenum))
GLDECL(glClearColor,             void, (GLfloat, GLfloat, GLfloat, GLfloat))
GLDECL(glClear,                  void, (GLbitfield))
GLDECL(glViewport,               void, (GLint, GLint, GLsizei, GLsizei))
GLDECL(glScissor,                void, (GLint, GLint, GLsizei, GLsizei))
GLDECL(glDepthMask,              void, (GLboolean))
GLDECL(glDepthFunc,              void, (GLenum))
GLDECL(glBlendFunc,              void, (GLenum, GLenum))
GLDECL(glGenVertexArrays,        void, (GLsizei, GLuint*))
GLDECL(glBindVertexArray,        void, (GLuint))
GLDECL(glDeleteVertexArrays,     void, (GLsizei, const GLuint*))
GLDECL(glGenBuffers,             void, (GLsizei, GLuint*))
GLDECL(glBindBuffer,            void, (GLenum, GLuint))
GLDECL(glBufferData,            void, (GLenum, GLsizeiptr, const void*, GLenum))
GLDECL(glBufferSubData,         void, (GLenum, GLintptr, GLsizeiptr, const void*))
GLDECL(glDeleteBuffers,         void, (GLsizei, const GLuint*))
GLDECL(glBindBufferBase,        void, (GLenum, GLuint, GLuint))
GLDECL(glEnableVertexAttribArray, void, (GLuint))
GLDECL(glVertexAttribPointer,  void, (GLuint, GLint, GLenum, GLboolean, GLsizei, const void*))
GLDECL(glCreateShader,          GLuint, (GLenum))
GLDECL(glShaderSource,          void, (GLuint, GLsizei, const GLchar* const*, const GLint*))
GLDECL(glCompileShader,         void, (GLuint))
GLDECL(glGetShaderiv,           void, (GLuint, GLenum, GLint*))
GLDECL(glGetShaderInfoLog,      void, (GLuint, GLsizei, GLsizei*, GLchar*))
GLDECL(glDeleteShader,          void, (GLuint))
GLDECL(glCreateProgram,         GLuint, (void))
GLDECL(glAttachShader,          void, (GLuint, GLuint))
GLDECL(glLinkProgram,           void, (GLuint))
GLDECL(glGetProgramiv,          void, (GLuint, GLenum, GLint*))
GLDECL(glGetProgramInfoLog,     void, (GLuint, GLsizei, GLsizei*, GLchar*))
GLDECL(glDeleteProgram,         void, (GLuint))
GLDECL(glUseProgram,            void, (GLuint))
GLDECL(glGetUniformLocation,    GLint, (GLuint, const GLchar*))
GLDECL(glUniform1f,             void, (GLint, GLfloat))
GLDECL(glUniform1i,             void, (GLint, GLint))
GLDECL(glUniform4f,             void, (GLint, GLfloat, GLfloat, GLfloat, GLfloat))
GLDECL(glUniformMatrix4fv,      void, (GLint, GLsizei, GLboolean, const GLfloat*))
GLDECL(glGetUniformBlockIndex,  GLuint, (GLuint, const GLchar*))
GLDECL(glUniformBlockBinding,   void, (GLuint, GLuint, GLuint))
GLDECL(glGenTextures,           void, (GLsizei, GLuint*))
GLDECL(glDeleteTextures,        void, (GLsizei, const GLuint*))
GLDECL(glBindTexture,           void, (GLenum, GLuint))
GLDECL(glTexImage2D,            void, (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*))
GLDECL(glTexParameteri,         void, (GLenum, GLenum, GLint))
GLDECL(glActiveTexture,         void, (GLenum))
GLDECL(glGenFramebuffers,       void, (GLsizei, GLuint*))
GLDECL(glDeleteFramebuffers,    void, (GLsizei, const GLuint*))
GLDECL(glBindFramebuffer,       void, (GLenum, GLuint))
GLDECL(glFramebufferTexture2D, void, (GLenum, GLenum, GLenum, GLuint, GLint))
GLDECL(glCheckFramebufferStatus, GLenum, (GLenum))
GLDECL(glGenRenderbuffers,      void, (GLsizei, GLuint*))
GLDECL(glDeleteRenderbuffers,   void, (GLsizei, const GLuint*))
GLDECL(glBindRenderbuffer,      void, (GLenum, GLuint))
GLDECL(glRenderbufferStorage,   void, (GLenum, GLenum, GLsizei, GLsizei))
GLDECL(glFramebufferRenderbuffer, void, (GLenum, GLenum, GLenum, GLuint))
GLDECL(glReadPixels,            void, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*))
GLDECL(glPixelStorei,           void, (GLenum, GLint))
GLDECL(glGetString,             const unsigned char*, (GLenum))
GLDECL(glDrawArrays,            void, (GLenum, GLint, GLsizei))

/* ===================================================================== */
/* 错误处理（粘性）                                                       */
/* ===================================================================== */
static void set_error(int e) { s_last_error = e; }

static void set_error_detail(int e, const char* detail)
{
    s_last_error = e;
    if (detail) { _snprintf(s_err_detail, sizeof(s_err_detail) - 1, "%s", detail); s_err_detail[sizeof(s_err_detail) - 1] = 0; }
    else { s_err_detail[0] = 0; }
}

static int enter_gl(void)
{
    s_last_error = SLR_OK;
    s_err_detail[0] = 0;
    if (!s_ready) { set_error(SLR_E_NOT_INITIALIZED); return 0; }
    EnterCriticalSection(&s_lock);
    if (!pwglMakeCurrent(s_hdc, s_hrc))
    {
        LeaveCriticalSection(&s_lock);
        set_error(SLR_E_CONTEXT_CURRENT);
        return 0;
    }
    return 1;
}

static void exit_gl(void) { LeaveCriticalSection(&s_lock); }

/* ===================================================================== */
/* 数学辅助                                                               */
/* ===================================================================== */
static void mat4_identity(float* m)
{
    int i;
    for (i = 0; i < 16; i++) m[i] = 0.0f;
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

/* 列主序正交投影（GL 语义）*/
static void mat4_ortho(float* m, float l, float r, float b, float t, float n, float f)
{
    float rl = r - l, tb = t - b, fn = f - n;
    int i;
    for (i = 0; i < 16; i++) m[i] = 0.0f;
    m[0]  = 2.0f / rl;
    m[5]  = 2.0f / tb;
    m[10] = -2.0f / fn;
    m[12] = -(r + l) / rl;
    m[13] = -(t + b) / tb;
    m[14] = -(f + n) / fn;
    m[15] = 1.0f;
}

/* out = a * b（列主序）*/
static void mat4_mul(float* out, const float* a, const float* b)
{
    int c, r, k;
    float tmp[16];
    for (c = 0; c < 4; c++)
        for (r = 0; r < 4; r++)
        {
            float s = 0.0f;
            for (k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
            tmp[c * 4 + r] = s;
        }
    memcpy(out, tmp, sizeof(tmp));
}

/* 2D 模型矩阵：平移 + 绕 Z 旋转 + 缩放（列主序）*/
static void mat4_model2d(float* m, float x, float y, float rz, float sx, float sy)
{
    float c = cosf(rz), s = sinf(rz);
    m[0] = c * sx;  m[1] = s * sx;  m[2] = 0.0f; m[3] = 0.0f;
    m[4] = -s * sy; m[5] = c * sy;  m[6] = 0.0f; m[7] = 0.0f;
    m[8] = 0.0f;    m[9] = 0.0f;    m[10] = 1.0f; m[11] = 0.0f;
    m[12] = x;      m[13] = y;      m[14] = 0.0f; m[15] = 1.0f;
}

static void hsv_to_rgb(float h, float* r, float* g, float* b)
{
    float hh, ff, p, q, t;
    int i;
    h = h - floorf(h);
    if (h < 0.0f) h += 1.0f;
    hh = h * 6.0f;
    i = (int)hh;
    if (i < 0) i = 0;
    ff = hh - (float)i;
    p = 0.0f;   /* v = s = 1 时：p = v*(1-s) = 0 */
    q = 1.0f - ff;
    t = ff;
    switch (i % 6)
    {
    case 0: *r = 1.0f; *g = t;   *b = p; break;
    case 1: *r = q;    *g = 1.0f; *b = p; break;
    case 2: *r = p;    *g = 1.0f; *b = t; break;
    case 3: *r = p;    *g = q;    *b = 1.0f; break;
    case 4: *r = t;    *g = p;    *b = 1.0f; break;
    default: *r = 1.0f; *g = p;    *b = q; break;
    }
}

/* ===================================================================== */
/* 着色器                                                                 */
/* ===================================================================== */
enum
{
    SLR_PROG_FLAT = 0,   /* v1：uniform MVP/Color                */
    SLR_PROG_TEX,        /* v1：uniform MVP/Color + 纹理         */
    SLR_PROG_PFLAT,      /* 管线：PerDraw UBO + 纯色              */
    SLR_PROG_PTEX,       /* 管线：PerDraw UBO + 纹理              */
    SLR_PROG_BLIT,       /* 全屏拷贝                             */
    SLR_PROG_POST,       /* 后处理                               */
    SLR_PROG_COUNT
};

typedef struct
{
    int mvp, color, tex;
    int obj_index;
    int src, bright, sat, vig;
} slr_prog_uni;

static GLuint       s_progs[SLR_PROG_COUNT];
static slr_prog_uni s_uni[SLR_PROG_COUNT];

static const char* VS_SCENE =
    "#version 330 core\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "uniform mat4 uMVP;\n"
    "out vec2 vUv;\n"
    "void main(){ vUv = aUv; gl_Position = uMVP * vec4(aPos, 0.0, 1.0); }\n";

static const char* FS_FLAT =
    "#version 330 core\n"
    "out vec4 oCol;\n"
    "uniform vec4 uColor;\n"
    "void main(){ oCol = uColor; }\n";

static const char* FS_TEX =
    "#version 330 core\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "uniform vec4 uColor;\n"
    "uniform sampler2D uTex;\n"
    "void main(){ oCol = uColor * texture(uTex, vUv); }\n";

static const char* VS_PSCENE =
    "#version 330 core\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; };\n"
    "uniform int uObjIndex;\n"
    "out vec2 vUv;\n"
    "void main(){ vUv = aUv; gl_Position = uMVP[uObjIndex] * vec4(aPos, 0.0, 1.0); }\n";

static const char* FS_PFLAT =
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; };\n"
    "uniform int uObjIndex;\n"
    "out vec4 oCol;\n"
    "void main(){ oCol = uColor[uObjIndex]; }\n";

static const char* FS_PTEX =
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; };\n"
    "uniform int uObjIndex;\n"
    "uniform sampler2D uTex;\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "void main(){ oCol = uColor[uObjIndex] * texture(uTex, vUv); }\n";

static const char* VS_FULL =
    "#version 330 core\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "out vec2 vUv;\n"
    "void main(){ vUv = aUv; gl_Position = vec4(aPos, 0.0, 1.0); }\n";

static const char* FS_BLIT =
    "#version 330 core\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "uniform sampler2D uSrc;\n"
    "void main(){ oCol = texture(uSrc, vUv); }\n";

static const char* FS_POST =
    "#version 330 core\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "uniform sampler2D uSrc;\n"
    "uniform float uBrightness;\n"
    "uniform float uSaturation;\n"
    "uniform float uVignette;\n"
    "void main(){\n"
    "  vec3 c = texture(uSrc, vUv).rgb;\n"
    "  c *= uBrightness;\n"
    "  float l = dot(c, vec3(0.299, 0.587, 0.114));\n"
    "  c = mix(vec3(l), c, uSaturation);\n"
    "  vec2 d = vUv - vec2(0.5);\n"
    "  c *= 1.0 - uVignette * (d.x*d.x + d.y*d.y) * 2.67;\n"
    "  oCol = vec4(c, 1.0);\n"
    "}\n";

static int compile_stage(GLuint prog, GLenum kind, const char* src)
{
    GLuint sh = p_glCreateShader(kind);
    GLint ok = 0, len = 0;
    char log[512];
    p_glShaderSource(sh, 1, &src, NULL);
    p_glCompileShader(sh);
    p_glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok)
    {
        log[0] = 0;
        p_glGetShaderiv(sh, GL_INFO_LOG_LENGTH, &len);
        if (len > 0) p_glGetShaderInfoLog(sh, sizeof(log) - 1, NULL, log);
        set_error_detail(SLR_E_SHADER, log);
        p_glDeleteShader(sh);
        return 0;
    }
    p_glAttachShader(prog, sh);
    p_glDeleteShader(sh);
    return 1;
}

static int link_program(GLuint prog)
{
    GLint ok = 0, len = 0;
    char log[512];
    p_glLinkProgram(prog);
    p_glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok)
    {
        log[0] = 0;
        p_glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &len);
        if (len > 0) p_glGetProgramInfoLog(prog, sizeof(log) - 1, NULL, log);
        set_error_detail(SLR_E_SHADER, log);
        return 0;
    }
    return 1;
}

static int make_program(int slot, const char* vs, const char* fs)
{
    GLuint prog = p_glCreateProgram();
    if (!compile_stage(prog, GL_VERTEX_SHADER, vs)) return 0;
    if (!compile_stage(prog, GL_FRAGMENT_SHADER, fs)) return 0;
    if (!link_program(prog)) { p_glDeleteProgram(prog); return 0; }
    s_progs[slot] = prog;
    return 1;
}

/* PerDraw UBO（std140）：mat4[64] + vec4[64] */
typedef struct
{
    float mvp[SLR_MAX_OBJECTS][16];
    float color[SLR_MAX_OBJECTS][4];
} slr_perdraw;

static slr_perdraw s_perdraw;
static GLuint      s_ubo = 0;

static int ensure_programs(void)
{
    int i;
    for (i = 0; i < SLR_PROG_COUNT; i++) s_progs[i] = 0;

    if (!make_program(SLR_PROG_FLAT, VS_SCENE, FS_FLAT)) return 0;
    if (!make_program(SLR_PROG_TEX,  VS_SCENE, FS_TEX))  return 0;
    if (!make_program(SLR_PROG_PFLAT, VS_PSCENE, FS_PFLAT)) return 0;
    if (!make_program(SLR_PROG_PTEX,  VS_PSCENE, FS_PTEX))  return 0;
    if (!make_program(SLR_PROG_BLIT, VS_FULL,  FS_BLIT))  return 0;
    if (!make_program(SLR_PROG_POST, VS_FULL,  FS_POST))  return 0;

    /* uniform 位置缓存 */
    s_uni[SLR_PROG_FLAT].mvp   = p_glGetUniformLocation(s_progs[SLR_PROG_FLAT], "uMVP");
    s_uni[SLR_PROG_FLAT].color = p_glGetUniformLocation(s_progs[SLR_PROG_FLAT], "uColor");

    s_uni[SLR_PROG_TEX].mvp   = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uMVP");
    s_uni[SLR_PROG_TEX].color = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uColor");
    s_uni[SLR_PROG_TEX].tex   = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uTex");

    s_uni[SLR_PROG_PFLAT].obj_index = p_glGetUniformLocation(s_progs[SLR_PROG_PFLAT], "uObjIndex");
    s_uni[SLR_PROG_PTEX].obj_index  = p_glGetUniformLocation(s_progs[SLR_PROG_PTEX], "uObjIndex");
    s_uni[SLR_PROG_PTEX].tex        = p_glGetUniformLocation(s_progs[SLR_PROG_PTEX], "uTex");

    s_uni[SLR_PROG_BLIT].src  = p_glGetUniformLocation(s_progs[SLR_PROG_BLIT], "uSrc");
    s_uni[SLR_PROG_POST].src  = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uSrc");
    s_uni[SLR_PROG_POST].bright = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uBrightness");
    s_uni[SLR_PROG_POST].sat    = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uSaturation");
    s_uni[SLR_PROG_POST].vig     = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uVignette");

    /* 采样器常量：管线纹理走 unit 1，全屏拷贝走 unit 0 */
    p_glUseProgram(s_progs[SLR_PROG_TEX]);
    p_glUniform1i(s_uni[SLR_PROG_TEX].tex, 1);
    p_glUseProgram(s_progs[SLR_PROG_PTEX]);
    p_glUniform1i(s_uni[SLR_PROG_PTEX].tex, 1);
    p_glUseProgram(s_progs[SLR_PROG_BLIT]);
    p_glUniform1i(s_uni[SLR_PROG_BLIT].src, 0);
    p_glUseProgram(s_progs[SLR_PROG_POST]);
    p_glUniform1i(s_uni[SLR_PROG_POST].src, 0);
    p_glUseProgram(0);

    /* PerDraw UBO：块绑定 0，全局一次 */
    {
        GLuint blk;
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PFLAT], "PerDraw");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PFLAT], blk, 0);
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PTEX], "PerDraw");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PTEX], blk, 0);
        p_glGenBuffers(1, &s_ubo);
        p_glBindBuffer(GL_UNIFORM_BUFFER, s_ubo);
        p_glBufferData(GL_UNIFORM_BUFFER, (GLsizeiptr)sizeof(slr_perdraw), &s_perdraw, GL_DYNAMIC_DRAW);
        p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, s_ubo);
        p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }
    return 1;
}

/* ===================================================================== */
/* 网格（静态 VAO：pos2 + uv2，stride 16B）                                */
/* ===================================================================== */
typedef struct { GLuint vao, vbo; int count; } slr_mesh;
static slr_mesh s_meshes[4];   /* 0 单位三角 1 四边形 2 全屏三角 3 v1 大三角 */

static int make_mesh(slr_mesh* m, const float* data, int vert_count)
{
    p_glGenVertexArrays(1, &m->vao);
    p_glGenBuffers(1, &m->vbo);
    p_glBindVertexArray(m->vao);
    p_glBindBuffer(GL_ARRAY_BUFFER, m->vbo);
    p_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(vert_count * 16), data, GL_STATIC_DRAW);
    p_glEnableVertexAttribArray(0);
    p_glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (const void*)0);
    p_glEnableVertexAttribArray(1);
    p_glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (const void*)8);
    p_glBindVertexArray(0);
    m->count = vert_count;
    return 1;
}

static int ensure_meshes(void)
{
    static const float tri[] = {
        -0.5f, -0.35f, 0.0f, 0.0f,
         0.5f, -0.35f, 1.0f, 0.0f,
         0.0f,  0.65f, 0.5f, 1.0f,
    };
    static const float quad[] = {
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f, -0.5f, 1.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f, -0.5f, 0.0f, 0.0f,
         0.5f,  0.5f, 1.0f, 1.0f,
        -0.5f,  0.5f, 0.0f, 1.0f,
    };
    static const float fs_tri[] = {
        -1.0f, -1.0f, 0.0f, 0.0f,
         3.0f, -1.0f, 2.0f, 0.0f,
        -1.0f,  3.0f, 0.0f, 2.0f,
    };
    static const float ctx_tri[] = {
        -0.8f, -0.6f, 0.0f, 0.0f,
         0.8f, -0.6f, 1.0f, 0.0f,
         0.0f,  0.9f, 0.5f, 1.0f,
    };
    if (!make_mesh(&s_meshes[0], tri,     3)) return 0;
    if (!make_mesh(&s_meshes[1], quad,    6)) return 0;
    if (!make_mesh(&s_meshes[2], fs_tri,  3)) return 0;
    if (!make_mesh(&s_meshes[3], ctx_tri, 3)) return 0;
    return 1;
}

/* ===================================================================== */
/* FBO 构造辅助                                                           */
/* ===================================================================== */
static int make_render_target(int w, int h, GLuint* fbo, GLuint* tex, GLuint* rb, int with_depth)
{
    GLenum st;
    p_glGenFramebuffers(1, fbo);
    p_glGenTextures(1, tex);
    p_glBindTexture(GL_TEXTURE_2D, *tex);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLint)GL_CLAMP_TO_EDGE);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLint)GL_CLAMP_TO_EDGE);
    p_glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
    p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
    if (with_depth)
    {
        p_glGenRenderbuffers(1, rb);
        p_glBindRenderbuffer(GL_RENDERBUFFER, *rb);
        p_glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
        p_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, *rb);
    }
    else
    {
        *rb = 0;
    }
    st = p_glCheckFramebufferStatus(GL_FRAMEBUFFER);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (st != GL_FRAMEBUFFER_COMPLETE)
    {
        set_error(SLR_E_FBO);
        return 0;
    }
    return 1;
}

/* 回读 + 行翻 top-down（原地交换行序）*/
static void read_pixels_flip(int w, int h, int64_t dst_ptr)
{
    unsigned char* buf = (unsigned char*)(intptr_t)dst_ptr;
    int stride = w * 4, rows = h / 2, y;
    unsigned char* tmp = (unsigned char*)malloc((size_t)stride);
    p_glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    if (!tmp) return;
    for (y = 0; y < rows; y++)
    {
        int y2 = h - 1 - y;
        memcpy(tmp, buf + (size_t)y * stride, (size_t)stride);
        memcpy(buf + (size_t)y * stride, buf + (size_t)y2 * stride, (size_t)stride);
        memcpy(buf + (size_t)y2 * stride, tmp, (size_t)stride);
    }
    free(tmp);
}

/* ===================================================================== */
/* v1：RenderContext（直连 FBO）                                           */
/* ===================================================================== */
typedef struct
{
    int used, w, h;
    GLuint fbo, tex, rb;
    int64_t frame_count;
} slr_ctx;
static slr_ctx s_ctxs[SLR_MAX_CTX];

static slr_ctx* ctx_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_CTX || !s_ctxs[i].used) return NULL;
    return &s_ctxs[i];
}

static void ctx_draw_triangle(slr_ctx* c, float r, float g, float b)
{
    float ident[16];
    p_glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    p_glViewport(0, 0, c->w, c->h);
    p_glUseProgram(s_progs[SLR_PROG_FLAT]);
    mat4_identity(ident);
    p_glUniformMatrix4fv(s_uni[SLR_PROG_FLAT].mvp, 1, GL_FALSE, ident);
    p_glUniform4f(s_uni[SLR_PROG_FLAT].color, r, g, b, 1.0f);
    p_glBindVertexArray(s_meshes[3].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[3].count);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
}

int64_t slr_context_create(int w, int h)
{
    int i;
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!enter_gl()) return 0;
    for (i = 0; i < SLR_MAX_CTX; i++)
    {
        if (!s_ctxs[i].used)
        {
            GLuint fbo = 0, tex = 0, rb = 0;
            if (!make_render_target(w, h, &fbo, &tex, &rb, 1))
            {
                exit_gl();
                return 0;
            }
            memset(&s_ctxs[i], 0, sizeof(slr_ctx));
            s_ctxs[i].used = 1; s_ctxs[i].w = w; s_ctxs[i].h = h;
            s_ctxs[i].fbo = fbo; s_ctxs[i].tex = tex; s_ctxs[i].rb = rb;
            s_ctxs[i].frame_count = 0;
            exit_gl();
            return (int64_t)(i + 1);
        }
    }
    set_error(SLR_E_LIMIT);
    exit_gl();
    return 0;
}

int slr_context_destroy(int64_t ctx)
{
    slr_ctx* c;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    p_glDeleteFramebuffers(1, &c->fbo);
    p_glDeleteTextures(1, &c->tex);
    if (c->rb) p_glDeleteRenderbuffers(1, &c->rb);
    memset(c, 0, sizeof(slr_ctx));
    exit_gl();
    return 1;
}

int slr_context_resize(int64_t ctx, int w, int h)
{
    slr_ctx* c;
    GLuint fbo = 0, tex = 0, rb = 0;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); exit_gl(); return 0; }
    if (!make_render_target(w, h, &fbo, &tex, &rb, 1)) { exit_gl(); return 0; }
    p_glDeleteFramebuffers(1, &c->fbo);
    p_glDeleteTextures(1, &c->tex);
    if (c->rb) p_glDeleteRenderbuffers(1, &c->rb);
    c->fbo = fbo; c->tex = tex; c->rb = rb; c->w = w; c->h = h;
    exit_gl();
    return 1;
}

int slr_context_width(int64_t ctx)
{
    slr_ctx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->w;
}

int slr_context_height(int64_t ctx)
{
    slr_ctx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->h;
}

int64_t slr_frame_count(int64_t ctx)
{
    slr_ctx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->frame_count;
}

int slr_clear(int64_t ctx, float r, float g, float b, float a)
{
    slr_ctx* c;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    p_glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    p_glViewport(0, 0, c->w, c->h);
    p_glClearColor(r, g, b, a);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    exit_gl();
    return 1;
}

int slr_draw_triangle(int64_t ctx, float r, float g, float b)
{
    slr_ctx* c;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    ctx_draw_triangle(c, r, g, b);
    exit_gl();
    return 1;
}

int slr_read_pixels(int64_t ctx, int64_t dst_ptr)
{
    slr_ctx* c;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); exit_gl(); return 0; }
    p_glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    read_pixels_flip(c->w, c->h, dst_ptr);
    exit_gl();
    return 1;
}

int slr_render_frame(int64_t ctx, float r, float g, float b, int64_t dst_ptr)
{
    slr_ctx* c;
    if (!enter_gl()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); exit_gl(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); exit_gl(); return 0; }
    p_glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    p_glViewport(0, 0, c->w, c->h);
    p_glClearColor(0.06f, 0.06f, 0.10f, 1.0f);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    ctx_draw_triangle(c, r, g, b);
    read_pixels_flip(c->w, c->h, dst_ptr);
    c->frame_count++;
    exit_gl();
    return 1;
}

/* ===================================================================== */
/* v2：纹理注册表（全局）                                                 */
/* ===================================================================== */
typedef struct { int used, w, h; GLuint gltex; } slr_texres;
static slr_texres s_textures[SLR_MAX_TEX];

static slr_texres* tex_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_TEX || !s_textures[i].used) return NULL;
    return &s_textures[i];
}

/* 纹理注册：top-down RGBA8 像素块 -> 翻行 -> 上传 -> 注册表占位。
 * 调用方须已 enter_gl。返回句柄（0 = 失败）。 */
static int64_t texture_register(int w, int h, const unsigned char* topdown)
{
    int i;
    unsigned char* flipped;
    int stride, y;
    stride = w * 4;
    flipped = (unsigned char*)malloc((size_t)stride * (size_t)h);
    if (!flipped) { set_error(SLR_E_MEMORY); return 0; }
    /* SL/WIC 契约 top-down：翻成 GL bottom-up 再上传 */
    for (y = 0; y < h; y++)
        memcpy(flipped + (size_t)(h - 1 - y) * stride, topdown + (size_t)y * stride, (size_t)stride);
    for (i = 0; i < SLR_MAX_TEX; i++)
    {
        GLuint t = 0;
        if (s_textures[i].used) continue;
        p_glGenTextures(1, &t);
        p_glBindTexture(GL_TEXTURE_2D, t);
        p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, flipped);
        p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, (GLint)GL_LINEAR);
        p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (GLint)GL_LINEAR);
        p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLint)GL_CLAMP_TO_EDGE);
        p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLint)GL_CLAMP_TO_EDGE);
        p_glBindTexture(GL_TEXTURE_2D, 0);
        free(flipped);
        memset(&s_textures[i], 0, sizeof(slr_texres));
        s_textures[i].used = 1; s_textures[i].w = w; s_textures[i].h = h; s_textures[i].gltex = t;
        return (int64_t)(i + 1);
    }
    free(flipped);
    set_error(SLR_E_LIMIT);
    return 0;
}

int64_t slr_texture_create_rgba(int w, int h, int64_t data_ptr)
{
    unsigned char* src;
    int64_t handle;
    if (w <= 0 || h <= 0 || !data_ptr) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!enter_gl()) return 0;
    src = (unsigned char*)(intptr_t)data_ptr;
    handle = texture_register(w, h, src);
    exit_gl();
    return handle;
}

/* 从图片文件创建纹理：WIC 解码 -> 转 32bppRGBA -> 上传。
 * path 为 UTF-8（SL string 契约）；支持 PNG/JPEG/BMP/TIFF 等 WIC 解码器。 */
int64_t slr_texture_load_file(const char* path_utf8)
{
    int64_t handle = 0;
    IWICImagingFactory* factory = NULL;
    IWICBitmapDecoder* decoder = NULL;
    IWICBitmapFrameDecode* frame = NULL;
    IWICFormatConverter* conv = NULL;
    UINT w = 0, h = 0;
    unsigned char* pixels = NULL;
    wchar_t wpath[MAX_PATH * 2];
    int wlen;
    HRESULT hr;
    int com_init = 0;

    if (!path_utf8 || !path_utf8[0]) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!s_ready) { set_error(SLR_E_NOT_INITIALIZED); return 0; }

    wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1);
    if (wlen <= 0) { set_error_detail(SLR_E_IMAGE, "bad path encoding"); return 0; }

    /* COM 初始化：已初始化（任意 apartment）可直接用 */
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;

    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IWICImagingFactory, (void**)&factory);
    if (FAILED(hr) || !factory) { set_error_detail(SLR_E_IMAGE, "WIC factory"); goto done; }

    hr = factory->lpVtbl->CreateDecoderFromFilename(factory, wpath, NULL, GENERIC_READ,
                                                    WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(hr) || !decoder) { set_error_detail(SLR_E_IMAGE, "open file"); goto done; }

    hr = decoder->lpVtbl->GetFrame(decoder, 0, &frame);
    if (FAILED(hr) || !frame) { set_error_detail(SLR_E_IMAGE, "frame"); goto done; }

    hr = factory->lpVtbl->CreateFormatConverter(factory, &conv);
    if (FAILED(hr) || !conv) { set_error_detail(SLR_E_IMAGE, "converter"); goto done; }

    hr = conv->lpVtbl->Initialize(conv, (IWICBitmapSource*)frame,
                                  &GUID_WICPixelFormat32bppRGBA,
                                  WICBitmapDitherTypeNone, NULL, 0.0,
                                  WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) { set_error_detail(SLR_E_IMAGE, "convert format"); goto done; }

    hr = conv->lpVtbl->GetSize(conv, &w, &h);
    if (FAILED(hr) || w == 0 || h == 0 || w > 8192 || h > 8192)
    { set_error_detail(SLR_E_IMAGE, "size"); goto done; }

    pixels = (unsigned char*)malloc((size_t)w * (size_t)h * 4);
    if (!pixels) { set_error(SLR_E_MEMORY); goto done; }

    hr = conv->lpVtbl->CopyPixels(conv, NULL, w * 4, (UINT)w * (UINT)h * 4, pixels);
    if (FAILED(hr)) { set_error_detail(SLR_E_IMAGE, "copy pixels"); goto done; }

    if (!enter_gl()) goto done;
    handle = texture_register((int)w, (int)h, pixels);
    exit_gl();

done:
    if (pixels) free(pixels);
    if (conv) conv->lpVtbl->Release(conv);
    if (frame) frame->lpVtbl->Release(frame);
    if (decoder) decoder->lpVtbl->Release(decoder);
    if (factory) factory->lpVtbl->Release(factory);
    if (com_init) CoUninitialize();
    return handle;
}

int slr_texture_destroy(int64_t tex)
{
    slr_texres* t;
    if (!enter_gl()) return 0;
    t = tex_from_handle(tex);
    if (!t) { set_error(SLR_E_TEXTURE); exit_gl(); return 0; }
    p_glDeleteTextures(1, &t->gltex);
    memset(t, 0, sizeof(slr_texres));
    exit_gl();
    return 1;
}

int slr_texture_count(void)
{
    int i, n = 0;
    for (i = 0; i < SLR_MAX_TEX; i++) if (s_textures[i].used) n++;
    return n;
}

/* ===================================================================== */
/* v2：管线                                                               */
/* ===================================================================== */
typedef struct
{
    int used, mesh, layer, queue, visible, anim_mode, cull_cams;
    float pos[3], rot_z, scale[2], color[4], anim_speed;
    int64_t texture;
} slr_object;

typedef struct
{
    int obj;        /* objects 下标          */
    int slot;       /* PerDraw UBO 槽位      */
    int prog;        /* SLR_PROG_PFLAT/PTEX   */
    int queue, layer;
    int cam;        /* 所属相机位号（0..SLR_MAX_CAMERAS-1）*/
    float z;
    float mvp[16];
} slr_draw_item;

/* 相机：独立剔除掩码/正交视域/视口/清屏参数，depth 决定绘制次序 */
typedef struct
{
    int used, enabled, depth, cull_mask, clear_flags;
    float cam_l, cam_r, cam_b, cam_t;
    float clear_color[4];
    int vp_x, vp_y, vp_w, vp_h;
} slr_camera;

/* 每帧逐相机绘制项区间（items 内 [start, start+n_opaque+n_trans) ）*/
typedef struct
{
    int start, n_opaque, n_trans;
} slr_cam_range;

typedef struct
{
    int used, w, h;
    GLuint fbo_scene, tex_scene, rb_scene;
    GLuint fbo_post,  tex_post,  rb_post;
    GLuint fbo_final, tex_final, rb_final;

    slr_object objects[SLR_MAX_OBJECTS];
    int object_count;

    slr_draw_item items[SLR_MAX_OBJECTS];
    int item_count, opaque_count;

    slr_camera   cameras[SLR_MAX_CAMERAS];
    int          active_cams[SLR_MAX_CAMERAS];   /* 本帧相机位号（depth 升序）*/
    int          active_cam_count;
    slr_cam_range cam_ranges[SLR_MAX_CAMERAS];
    int camera_count;                            /* 已启用相机数（stat）*/

    int visible_count, culled_count;
    int draw_calls, opaque_draws, transparent_draws;
    int chunk_count, program_switches, upload_count;
    int layers_mask, last_stage;

    float clear_color[4];
    int post_enabled;
    float post_brightness, post_saturation, post_vignette;

    float time, last_time, dt, total_time;
    int64_t frame_count;
} slr_pipeline;

static slr_pipeline s_pipes[SLR_MAX_PIPES];

static slr_pipeline* pipe_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_PIPES || !s_pipes[i].used) return NULL;
    return &s_pipes[i];
}

static slr_object* obj_from_handle(slr_pipeline* p, int64_t oh, int* idx_out)
{
    int i = (int)(oh - 1);
    if (oh <= 0 || i >= SLR_MAX_OBJECTS || !p->objects[i].used) return NULL;
    if (idx_out) *idx_out = i;
    return &p->objects[i];
}

static void pipeline_release_targets(slr_pipeline* p)
{
    p_glDeleteFramebuffers(1, &p->fbo_scene);
    p_glDeleteTextures(1, &p->tex_scene);
    if (p->rb_scene) p_glDeleteRenderbuffers(1, &p->rb_scene);
    p_glDeleteFramebuffers(1, &p->fbo_post);
    p_glDeleteTextures(1, &p->tex_post);
    if (p->rb_post) p_glDeleteRenderbuffers(1, &p->rb_post);
    p_glDeleteFramebuffers(1, &p->fbo_final);
    p_glDeleteTextures(1, &p->tex_final);
    if (p->rb_final) p_glDeleteRenderbuffers(1, &p->rb_final);
    p->fbo_scene = p->tex_scene = p->rb_scene = 0;
    p->fbo_post = p->tex_post = p->rb_post = 0;
    p->fbo_final = p->tex_final = p->rb_final = 0;
}

static int pipeline_make_targets(slr_pipeline* p, int w, int h)
{
    if (!make_render_target(w, h, &p->fbo_scene, &p->tex_scene, &p->rb_scene, 1)) return 0;
    if (!make_render_target(w, h, &p->fbo_post,  &p->tex_post,  &p->rb_post,  0)) return 0;
    if (!make_render_target(w, h, &p->fbo_final, &p->tex_final, &p->rb_final, 0)) return 0;
    return 1;
}

int64_t slr_pipeline_create(int w, int h)
{
    int i;
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!enter_gl()) return 0;
    for (i = 0; i < SLR_MAX_PIPES; i++)
    {
        if (!s_pipes[i].used)
        {
            slr_pipeline* p = &s_pipes[i];
            memset(p, 0, sizeof(slr_pipeline));
            p->used = 1; p->w = w; p->h = h;
            /* 默认相机（槽 0）：正交 [-1,1]²，全 layer 可见，全视口清屏 */
            p->cameras[0].used = 1;
            p->cameras[0].enabled = 1;
            p->cameras[0].cull_mask = -1;
            p->cameras[0].cam_l = -1.0f; p->cameras[0].cam_r = 1.0f;
            p->cameras[0].cam_b = -1.0f; p->cameras[0].cam_t = 1.0f;
            p->cameras[0].clear_flags = SLR_CLEAR_COLOR | SLR_CLEAR_DEPTH;
            p->cameras[0].clear_color[0] = 0.06f; p->cameras[0].clear_color[1] = 0.06f;
            p->cameras[0].clear_color[2] = 0.10f; p->cameras[0].clear_color[3] = 1.0f;
            p->cameras[0].vp_x = 0; p->cameras[0].vp_y = 0;
            p->cameras[0].vp_w = w; p->cameras[0].vp_h = h;
            p->camera_count = 1;
            p->clear_color[0] = 0.06f; p->clear_color[1] = 0.06f;
            p->clear_color[2] = 0.10f; p->clear_color[3] = 1.0f;
            p->post_brightness = 1.0f; p->post_saturation = 1.0f; p->post_vignette = 0.0f;
            if (!pipeline_make_targets(p, w, h))
            {
                pipeline_release_targets(p);
                memset(p, 0, sizeof(slr_pipeline));
                exit_gl();
                return 0;
            }
            exit_gl();
            return (int64_t)(i + 1);
        }
    }
    set_error(SLR_E_LIMIT);
    exit_gl();
    return 0;
}

int slr_pipeline_destroy(int64_t h)
{
    slr_pipeline* p;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    pipeline_release_targets(p);
    memset(p, 0, sizeof(slr_pipeline));
    exit_gl();
    return 1;
}

int slr_pipeline_resize(int64_t h, int w, int hh)
{
    slr_pipeline* p;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    if (w <= 0 || hh <= 0) { set_error(SLR_E_BAD_PARAM); exit_gl(); return 0; }
    pipeline_release_targets(p);
    if (!pipeline_make_targets(p, w, hh))
    {
        pipeline_release_targets(p);
        set_error(SLR_E_FBO);
        exit_gl();
        return 0;
    }
    p->w = w; p->h = hh;
    exit_gl();
    return 1;
}

int64_t slr_pipeline_frame_count(int64_t h)
{
    slr_pipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    return p->frame_count;
}

int slr_pipeline_set_camera(int64_t h, int cull_mask, float l, float r, float b, float t)
{
    slr_pipeline* p = pipe_from_handle(h);
    slr_camera* c;
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    /* 兼容 v2：写默认相机（槽 0） */
    c = &p->cameras[0];
    c->cull_mask = cull_mask;
    c->cam_l = l; c->cam_r = r; c->cam_b = b; c->cam_t = t;
    return 1;
}

int slr_pipeline_set_clear_color(int64_t h, float r, float g, float b, float a)
{
    slr_pipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    p->clear_color[0] = r; p->clear_color[1] = g; p->clear_color[2] = b; p->clear_color[3] = a;
    /* 同步默认相机清屏色（槽 0 清屏色 = 管线清屏色） */
    p->cameras[0].clear_color[0] = r;
    p->cameras[0].clear_color[1] = g;
    p->cameras[0].clear_color[2] = b;
    p->cameras[0].clear_color[3] = a;
    return 1;
}

int slr_pipeline_set_post(int64_t h, int enable, float brightness, float saturation, float vignette)
{
    slr_pipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    p->post_enabled = enable ? 1 : 0;
    p->post_brightness = brightness;
    p->post_saturation = saturation;
    p->post_vignette = vignette;
    return 1;
}

/* ---- 多相机（槽 0 为默认相机，不可销毁）---- */
static slr_camera* cam_from_handle(slr_pipeline* p, int64_t ch)
{
    int i = (int)(ch - 1);
    if (ch <= 0 || i >= SLR_MAX_CAMERAS || !p->cameras[i].used) return NULL;
    return &p->cameras[i];
}

int64_t slr_camera_create(int64_t h, int depth)
{
    slr_pipeline* p;
    int i;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    for (i = 0; i < SLR_MAX_CAMERAS; i++)
    {
        slr_camera* c;
        if (p->cameras[i].used) continue;
        c = &p->cameras[i];
        memset(c, 0, sizeof(slr_camera));
        c->used = 1;
        c->enabled = 1;
        c->depth = depth;
        c->cull_mask = -1;
        c->cam_l = -1.0f; c->cam_r = 1.0f; c->cam_b = -1.0f; c->cam_t = 1.0f;
        c->clear_flags = 0;   /* 叠加相机默认不清屏（透写上一相机画面）*/
        c->clear_color[0] = 0.0f; c->clear_color[1] = 0.0f;
        c->clear_color[2] = 0.0f; c->clear_color[3] = 1.0f;
        c->vp_x = 0; c->vp_y = 0; c->vp_w = p->w; c->vp_h = p->h;
        p->camera_count++;
        return (int64_t)(i + 1);
    }
    set_error(SLR_E_LIMIT);
    return 0;
}

int slr_camera_destroy(int64_t h, int64_t ch)
{
    slr_pipeline* p;
    slr_camera* c;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    if (ch == 1) { set_error(SLR_E_BAD_PARAM); return 0; }  /* 默认相机不可销毁 */
    c = cam_from_handle(p, ch);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    memset(c, 0, sizeof(slr_camera));
    p->camera_count--;
    return 1;
}

static int cam_set_common(int64_t h, int64_t ch, slr_pipeline** pp, slr_camera** cc)
{
    *pp = pipe_from_handle(h);
    if (!*pp) { set_error(SLR_E_PIPELINE); return 0; }
    *cc = cam_from_handle(*pp, ch);
    if (!*cc) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return 1;
}

int slr_camera_set_enabled(int64_t h, int64_t ch, int enabled)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->enabled = enabled ? 1 : 0;
    return 1;
}

int slr_camera_set_depth(int64_t h, int64_t ch, int depth)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->depth = depth;
    return 1;
}

int slr_camera_set_cull_mask(int64_t h, int64_t ch, int mask)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->cull_mask = mask;
    return 1;
}

int slr_camera_set_extents(int64_t h, int64_t ch, float l, float r, float b, float t)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->cam_l = l; c->cam_r = r; c->cam_b = b; c->cam_t = t;
    return 1;
}

int slr_camera_set_viewport(int64_t h, int64_t ch, int x, int y, int w, int hh)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    if (x < 0 || y < 0 || w <= 0 || hh <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    c->vp_x = x; c->vp_y = y; c->vp_w = w; c->vp_h = hh;
    return 1;
}

int slr_camera_set_clear_color(int64_t h, int64_t ch, float r, float g, float b, float a)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->clear_color[0] = r; c->clear_color[1] = g;
    c->clear_color[2] = b; c->clear_color[3] = a;
    return 1;
}

int slr_camera_set_clear_flags(int64_t h, int64_t ch, int flags)
{
    slr_pipeline* p; slr_camera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->clear_flags = flags & (SLR_CLEAR_COLOR | SLR_CLEAR_DEPTH);
    return 1;
}

int slr_camera_count(int64_t h)
{
    slr_pipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    return p->camera_count;
}

/* ---- 场景对象 ---- */
int64_t slr_object_create(int64_t h, int mesh_kind)
{
    slr_pipeline* p;
    int i;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    if (mesh_kind != SLR_MESH_TRIANGLE && mesh_kind != SLR_MESH_QUAD)
    {
        set_error(SLR_E_BAD_PARAM);
        exit_gl();
        return 0;
    }
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        slr_object* o;
        if (p->objects[i].used) continue;
        o = &p->objects[i];
        memset(o, 0, sizeof(slr_object));
        o->used = 1;
        o->mesh = mesh_kind;
        o->visible = 1;
        o->layer = 0;
        /* 对齐 Unity 渲染队列：三角默认不透明，四边形默认透明 */
        o->queue = (mesh_kind == SLR_MESH_TRIANGLE) ? 2000 : 3000;
        o->scale[0] = 1.0f; o->scale[1] = 1.0f;
        o->color[0] = 1.0f; o->color[1] = 1.0f; o->color[2] = 1.0f; o->color[3] = 1.0f;
        o->texture = 0;
        exit_gl();
        return (int64_t)(i + 1);
    }
    set_error(SLR_E_LIMIT);
    exit_gl();
    return 0;
}

int slr_object_destroy(int64_t h, int64_t obj)
{
    slr_pipeline* p;
    int idx = 0;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    if (!obj_from_handle(p, obj, &idx)) { set_error(SLR_E_OBJECT); exit_gl(); return 0; }
    memset(&p->objects[idx], 0, sizeof(slr_object));
    exit_gl();
    return 1;
}

static int obj_set_common(int64_t h, int64_t obj, slr_pipeline** pp, slr_object** oo, int* idx)
{
    if (!enter_gl()) return 0;
    *pp = pipe_from_handle(h);
    if (!*pp) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    *oo = obj_from_handle(*pp, obj, idx);
    if (!*oo) { set_error(SLR_E_OBJECT); exit_gl(); return 0; }
    return 1;
}

int slr_object_set_visible(int64_t h, int64_t obj, int visible)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->visible = visible ? 1 : 0;
    exit_gl();
    return 1;
}

int slr_object_set_layer(int64_t h, int64_t obj, int layer)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (layer < 0 || layer > 31) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->layer = layer;
    exit_gl();
    return 1;
}

int slr_object_set_queue(int64_t h, int64_t obj, int queue)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->queue = queue;
    exit_gl();
    return 1;
}

int slr_object_set_position(int64_t h, int64_t obj, float x, float y, float z)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->pos[0] = x; o->pos[1] = y; o->pos[2] = z;
    exit_gl();
    return 1;
}

int slr_object_set_rotation_z(int64_t h, int64_t obj, float rz)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->rot_z = rz;
    exit_gl();
    return 1;
}

int slr_object_set_scale(int64_t h, int64_t obj, float sx, float sy)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->scale[0] = sx; o->scale[1] = sy;
    exit_gl();
    return 1;
}

int slr_object_set_color(int64_t h, int64_t obj, float r, float g, float b, float a)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->color[0] = r; o->color[1] = g; o->color[2] = b; o->color[3] = a;
    exit_gl();
    return 1;
}

int slr_object_set_texture(int64_t h, int64_t obj, int64_t tex)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    if (tex != 0 && !tex_from_handle(tex)) { set_error(SLR_E_TEXTURE); exit_gl(); return 0; }
    o->texture = tex;
    exit_gl();
    return 1;
}

int slr_object_set_animated(int64_t h, int64_t obj, int mode, float speed)
{
    slr_pipeline* p; slr_object* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->anim_mode = (mode == SLR_ANIM_HUE_CYCLE) ? SLR_ANIM_HUE_CYCLE : SLR_ANIM_NONE;
    o->anim_speed = speed;
    exit_gl();
    return 1;
}

int slr_object_count(int64_t h)
{
    slr_pipeline* p = pipe_from_handle(h);
    int i, n = 0;
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    for (i = 0; i < SLR_MAX_OBJECTS; i++) if (p->objects[i].used) n++;
    return n;
}

/* ===================================================================== */
/* 13 阶段实现（内部函数：调用方已持有 GL 锁与上下文）                      */
/* ===================================================================== */

/* 1 渲染开始 */
static int stage_begin_frame(slr_pipeline* p, float time)
{
    p->time = time;
    p->frame_count++;
    p->last_stage = 1;
    p->visible_count = 0; p->culled_count = 0;
    p->draw_calls = 0; p->opaque_draws = 0; p->transparent_draws = 0;
    p->chunk_count = 0; p->program_switches = 0; p->upload_count = 0;
    p->layers_mask = 0; p->item_count = 0; p->opaque_count = 0;
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_scene);
    p_glViewport(0, 0, p->w, p->h);
    p_glClearColor(p->clear_color[0], p->clear_color[1], p->clear_color[2], p->clear_color[3]);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    p_glDisable(GL_BLEND);
    p_glEnable(GL_DEPTH_TEST);
    p_glDepthFunc(GL_LESS);
    p_glDepthMask(GL_TRUE);
    return 1;
}

/* 2 准备物料 */
static int stage_prepare_materials(slr_pipeline* p)
{
    p->last_stage = 2;
    /* 着色器程序/UBO 在 slr_init 已就绪；此处确保场景纹理参数合法 */
    return 1;
}

/* 3 提前更新（动画） */
static int stage_early_update(slr_pipeline* p)
{
    int i;
    p->last_stage = 3;
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        slr_object* o = &p->objects[i];
        if (!o->used || !o->visible) continue;
        if (o->anim_mode == SLR_ANIM_HUE_CYCLE)
        {
            float hue = o->anim_speed * p->time;
            hsv_to_rgb(hue, &o->color[0], &o->color[1], &o->color[2]);
        }
    }
    return 1;
}

/* 按深度升序收集本帧活动相机（稳定插入排序：depth 相同按槽位序） */
static int pipeline_order_cameras(slr_pipeline* p, int* order)
{
    int i, j, n = 0;
    for (i = 0; i < SLR_MAX_CAMERAS; i++)
    {
        if (!p->cameras[i].used || !p->cameras[i].enabled) continue;
        order[n++] = i;
    }
    for (i = 1; i < n; i++)
    {
        int key = order[i], d = p->cameras[key].depth;
        j = i - 1;
        while (j >= 0 && p->cameras[order[j]].depth > d)
        {
            order[j + 1] = order[j];
            j--;
        }
        order[j + 1] = key;
    }
    return n;
}

/* 4 渲染层分层（剔除）：逐相机独立剔除，对象记录可见相机位掩码 */
static int stage_cull_layers(slr_pipeline* p)
{
    int i, ci, cam_count;
    int order[SLR_MAX_CAMERAS];
    p->last_stage = 4;
    p->visible_count = 0; p->culled_count = 0;
    cam_count = pipeline_order_cameras(p, order);
    for (ci = 0; ci < cam_count; ci++) p->active_cams[ci] = order[ci];
    p->active_cam_count = cam_count;
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        slr_object* o = &p->objects[i];
        int vis_mask = 0;
        if (!o->used) { o->cull_cams = 0; continue; }
        if (o->visible)
        {
            float hx = 0.5f * o->scale[0];
            float hy = 0.5f * o->scale[1];
            float l = o->pos[0] - hx, r = o->pos[0] + hx;
            float b = o->pos[1] - hy, t = o->pos[1] + hy;
            for (ci = 0; ci < cam_count; ci++)
            {
                slr_camera* c = &p->cameras[order[ci]];
                if (!(c->cull_mask & (1 << o->layer))) continue;
                if ((r >= c->cam_l) && (l <= c->cam_r) &&
                    (t >= c->cam_b) && (b <= c->cam_t))
                {
                    vis_mask |= (1 << order[ci]);
                }
            }
        }
        o->cull_cams = vis_mask;
        if (vis_mask) p->visible_count++;
        else p->culled_count++;
    }
    return 1;
}

/* 绘制项排序辅助：不透明 (queue,z) 升序；透明 (queue,z) 降序 */
static void sort_items(slr_draw_item* items, int count, int transparent)
{
    int i, j;
    for (i = 1; i < count; i++)
    {
        slr_draw_item key = items[i];
        j = i - 1;
        while (j >= 0)
        {
            int swap;
            if (transparent)
            {
                /* 队列升序，同队列 z 降序（远→近）*/
                if (items[j].queue > key.queue) swap = 1;
                else if (items[j].queue < key.queue) swap = 0;
                else swap = items[j].z < key.z;
            }
            else
            {
                /* 队列升序，同队列 z 升序（近→远）*/
                if (items[j].queue > key.queue) swap = 1;
                else if (items[j].queue < key.queue) swap = 0;
                else swap = items[j].z > key.z;
            }
            if (!swap) break;
            items[j + 1] = items[j];
            j--;
        }
        items[j + 1] = key;
    }
}

/* 5 渲染层整理数据（真正实现，多相机）：
 *   逐活动相机（depth 升序）收集可见对象：每相机先不透明（queue 升序、
 *   z 升序：近→远），再透明（queue 升序、z 降序：远→近）。
 *   items 布局：[cam0 不透明|cam0 透明|cam1 不透明|cam1 透明|...]
 *   区间记录于 cam_ranges[bit]；slot = 数组下标 = PerDraw UBO 槽位 */
static int stage_assemble_impl(slr_pipeline* p)
{
    int ci, i, slot;
    p->last_stage = 5;
    p->item_count = 0;
    p->opaque_count = 0;
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        slr_camera* c = &p->cameras[bit];
        slr_cam_range* rg = &p->cam_ranges[bit];
        float proj[16], model[16];
        int start, start_t;
        mat4_ortho(proj, c->cam_l, c->cam_r, c->cam_b, c->cam_t, -1.0f, 1.0f);
        /* 先收不透明 */
        start = p->item_count;
        for (i = 0; i < SLR_MAX_OBJECTS && p->item_count < SLR_MAX_OBJECTS; i++)
        {
            slr_object* o = &p->objects[i];
            if (!o->used || o->queue >= 2500) continue;
            if (!(o->cull_cams & (1 << bit))) continue;
            {
                slr_draw_item* it = &p->items[p->item_count];
                memset(it, 0, sizeof(slr_draw_item));
                it->obj = i;
                it->queue = o->queue; it->layer = o->layer; it->z = o->pos[2];
                it->cam = bit;
                it->prog = (o->texture != 0) ? SLR_PROG_PTEX : SLR_PROG_PFLAT;
                mat4_model2d(model, o->pos[0], o->pos[1], o->rot_z, o->scale[0], o->scale[1]);
                mat4_mul(it->mvp, proj, model);
                p->item_count++;
            }
        }
        rg->start = start;
        rg->n_opaque = p->item_count - start;
        sort_items(p->items + start, rg->n_opaque, 0);
        /* 再收透明 */
        start_t = p->item_count;
        for (i = 0; i < SLR_MAX_OBJECTS && p->item_count < SLR_MAX_OBJECTS; i++)
        {
            slr_object* o = &p->objects[i];
            if (!o->used || o->queue < 2500) continue;
            if (!(o->cull_cams & (1 << bit))) continue;
            {
                slr_draw_item* it = &p->items[p->item_count];
                memset(it, 0, sizeof(slr_draw_item));
                it->obj = i;
                it->queue = o->queue; it->layer = o->layer; it->z = o->pos[2];
                it->cam = bit;
                it->prog = (o->texture != 0) ? SLR_PROG_PTEX : SLR_PROG_PFLAT;
                mat4_model2d(model, o->pos[0], o->pos[1], o->rot_z, o->scale[0], o->scale[1]);
                mat4_mul(it->mvp, proj, model);
                p->item_count++;
            }
        }
        rg->n_trans = p->item_count - start_t;
        sort_items(p->items + start_t, rg->n_trans, 1);
    }
    /* UBO 槽位 = 数组下标 */
    for (slot = 0; slot < p->item_count; slot++) p->items[slot].slot = slot;
    return 1;
}

/* 6 向 GPU 传入渲染数据（PerDraw CBUFFER 批量上传） */
static int stage_upload_render_data(slr_pipeline* p)
{
    int i;
    p->last_stage = 6;
    memset(&s_perdraw, 0, sizeof(s_perdraw));
    for (i = 0; i < p->item_count; i++)
    {
        slr_object* o = &p->objects[p->items[i].obj];
        memcpy(s_perdraw.mvp[i], p->items[i].mvp, sizeof(p->items[i].mvp));
        memcpy(s_perdraw.color[i], o->color, sizeof(o->color));
        p->upload_count += 2;   /* MVP + 颜色 */
    }
    p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, s_ubo);
    p_glBufferSubData(GL_UNIFORM_BUFFER, 0, (GLsizeiptr)sizeof(slr_perdraw), &s_perdraw);
    p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
    return 1;
}

static void draw_one_item(slr_pipeline* p, slr_draw_item* it)
{
    slr_object* o = &p->objects[it->obj];
    p_glUniform1i(s_uni[it->prog].obj_index, it->slot);
    if (it->prog == SLR_PROG_PTEX)
    {
        slr_texres* t = tex_from_handle(o->texture);
        p_glActiveTexture(GL_TEXTURE1);
        p_glBindTexture(GL_TEXTURE_2D, t ? t->gltex : 0);
    }
    p_glBindVertexArray(s_meshes[o->mesh].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[o->mesh].count);
    p->draw_calls++;
    p->layers_mask |= (1 << it->layer);
}

/* 7 shader 分块渲染（不透明段，多相机：逐相机 视口/清屏 -> 分组合批绘制） */
static int stage_render_shader_chunks(slr_pipeline* p)
{
    int ci;
    p->last_stage = 7;
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_scene);
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        slr_camera* c = &p->cameras[bit];
        slr_cam_range* rg = &p->cam_ranges[bit];
        int i = rg->start, end = rg->start + rg->n_opaque;
        p_glViewport(c->vp_x, c->vp_y, c->vp_w, c->vp_h);
        /* glClear 只受 scissor 限制（不受 viewport 限制）：局部清屏必须
         * 开 scissor box，否则后画相机把整个画面清掉 */
        if (c->clear_flags)
        {
            p_glEnable(GL_SCISSOR_TEST);
            p_glScissor(c->vp_x, c->vp_y, c->vp_w, c->vp_h);
            if (c->clear_flags & SLR_CLEAR_COLOR)
            {
                p_glClearColor(c->clear_color[0], c->clear_color[1],
                               c->clear_color[2], c->clear_color[3]);
                p_glClear(GL_COLOR_BUFFER_BIT);
            }
            if (c->clear_flags & SLR_CLEAR_DEPTH)
            {
                p_glClear(GL_DEPTH_BUFFER_BIT);
            }
            p_glDisable(GL_SCISSOR_TEST);
        }
        p_glDisable(GL_BLEND);
        p_glEnable(GL_DEPTH_TEST);
        p_glDepthFunc(GL_LESS);
        p_glDepthMask(GL_TRUE);
        while (i < end)
        {
            int prog = p->items[i].prog, j = i;
            p_glUseProgram(s_progs[prog]);
            p->program_switches++;
            while (j < end && p->items[j].prog == prog)
            {
                draw_one_item(p, &p->items[j]);
                p->opaque_draws++;
                j++;
            }
            p->chunk_count++;
            i = j;
        }
    }
    return 1;
}

/* 8 核心更新时间 */
static int stage_update_core_time(slr_pipeline* p)
{
    p->last_stage = 8;
    if (p->frame_count <= 1)
    {
        p->dt = 0.0f;
    }
    else
    {
        p->dt = p->time - p->last_time;
        if (p->dt < 0.0f) p->dt = 0.0f;
    }
    p->last_time = p->time;
    p->total_time += p->dt;
    return 1;
}

/* 9 shader 分段渲染（透明段：混合开、深度写关、后→前；多相机逐相机执行） */
static int stage_render_shader_segments(slr_pipeline* p)
{
    int ci;
    p->last_stage = 9;
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_scene);
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        slr_camera* c = &p->cameras[bit];
        slr_cam_range* rg = &p->cam_ranges[bit];
        int i = rg->start + rg->n_opaque, end = rg->start + rg->n_opaque + rg->n_trans;
        p_glViewport(c->vp_x, c->vp_y, c->vp_w, c->vp_h);
        p_glEnable(GL_BLEND);
        p_glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        p_glEnable(GL_DEPTH_TEST);
        p_glDepthFunc(GL_LESS);
        p_glDepthMask(GL_FALSE);
        while (i < end)
        {
            int prog = p->items[i].prog, j = i;
            p_glUseProgram(s_progs[prog]);
            p->program_switches++;
            while (j < end && p->items[j].prog == prog)
            {
                draw_one_item(p, &p->items[j]);
                p->transparent_draws++;
                j++;
            }
            p->chunk_count++;
            i = j;
        }
    }
    return 1;
}

/* 10 整理渲染后的图层 */
static int stage_assemble_rendered_layers(slr_pipeline* p)
{
    p->last_stage = 10;
    p_glDepthMask(GL_TRUE);
    p_glDisable(GL_BLEND);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
    return 1;
}

/* 11 后处理 */
static int stage_post_process(slr_pipeline* p)
{
    p->last_stage = 11;
    p_glDisable(GL_DEPTH_TEST);
    p_glDisable(GL_BLEND);
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_post);
    p_glViewport(0, 0, p->w, p->h);
    if (p->post_enabled)
    {
        p_glUseProgram(s_progs[SLR_PROG_POST]);
        p->program_switches++;
        p_glUniform1f(s_uni[SLR_PROG_POST].bright, p->post_brightness);
        p_glUniform1f(s_uni[SLR_PROG_POST].sat,     p->post_saturation);
        p_glUniform1f(s_uni[SLR_PROG_POST].vig,     p->post_vignette);
    }
    else
    {
        p_glUseProgram(s_progs[SLR_PROG_BLIT]);
        p->program_switches++;
    }
    p_glActiveTexture(GL_TEXTURE0);
    p_glBindTexture(GL_TEXTURE_2D, p->tex_scene);
    p_glBindVertexArray(s_meshes[2].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[2].count);
    p->draw_calls++;
    return 1;
}

/* 12 层级的逻辑整合（后处理结果 → 最终 renderTexture） */
static int stage_integrate_layers(slr_pipeline* p)
{
    p->last_stage = 12;
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_final);
    p_glViewport(0, 0, p->w, p->h);
    p_glUseProgram(s_progs[SLR_PROG_BLIT]);
    p->program_switches++;
    p_glActiveTexture(GL_TEXTURE0);
    p_glBindTexture(GL_TEXTURE_2D, p->tex_post);
    p_glBindVertexArray(s_meshes[2].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[2].count);
    p->draw_calls++;
    return 1;
}

/* 13 输出最终渲染 renderTexture */
static int stage_output_render_texture(slr_pipeline* p, int64_t dst_ptr)
{
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); return 0; }
    p->last_stage = 13;
    p_glBindFramebuffer(GL_FRAMEBUFFER, p->fbo_final);
    p_glViewport(0, 0, p->w, p->h);
    read_pixels_flip(p->w, p->h, dst_ptr);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return 1;
}

/* ---- 阶段导出 ---- */
#define SLR_STAGE_EXPORT(fname, stager)                      \
    SLR_API int fname(int64_t h)                                \
    {                                                          \
        slr_pipeline* p;                                       \
        int ok;                                                \
        if (!enter_gl()) return 0;                             \
        p = pipe_from_handle(h);                               \
        if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; } \
        ok = stager(p);                                        \
        exit_gl();                                             \
        return ok;                                             \
    }

SLR_STAGE_EXPORT(slr_pipeline_prepare_materials,       stage_prepare_materials)
SLR_STAGE_EXPORT(slr_pipeline_early_update,            stage_early_update)
SLR_STAGE_EXPORT(slr_pipeline_cull_layers,             stage_cull_layers)
SLR_STAGE_EXPORT(slr_pipeline_assemble_layer_data,    stage_assemble_impl)
SLR_STAGE_EXPORT(slr_pipeline_upload_render_data,     stage_upload_render_data)
SLR_STAGE_EXPORT(slr_pipeline_render_shader_chunks,    stage_render_shader_chunks)
SLR_STAGE_EXPORT(slr_pipeline_update_core_time,        stage_update_core_time)
SLR_STAGE_EXPORT(slr_pipeline_render_shader_segments,  stage_render_shader_segments)
SLR_STAGE_EXPORT(slr_pipeline_assemble_rendered_layers, stage_assemble_rendered_layers)
SLR_STAGE_EXPORT(slr_pipeline_post_process,            stage_post_process)
SLR_STAGE_EXPORT(slr_pipeline_integrate_layers,        stage_integrate_layers)

int slr_pipeline_begin_frame(int64_t h, float time)
{
    slr_pipeline* p;
    int ok;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    ok = stage_begin_frame(p, time);
    exit_gl();
    return ok;
}

int slr_pipeline_output_render_texture(int64_t h, int64_t dst_ptr)
{
    slr_pipeline* p;
    int ok;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    ok = stage_output_render_texture(p, dst_ptr);
    exit_gl();
    return ok;
}

int slr_pipeline_render_frame(int64_t h, float time, int64_t dst_ptr)
{
    slr_pipeline* p;
    int ok;
    if (!enter_gl()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); exit_gl(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); exit_gl(); return 0; }
    ok = stage_begin_frame(p, time)
      && stage_prepare_materials(p)
      && stage_early_update(p)
      && stage_cull_layers(p)
      && stage_assemble_impl(p)
      && stage_upload_render_data(p)
      && stage_render_shader_chunks(p)
      && stage_update_core_time(p)
      && stage_render_shader_segments(p)
      && stage_assemble_rendered_layers(p)
      && stage_post_process(p)
      && stage_integrate_layers(p)
      && stage_output_render_texture(p, dst_ptr);
    exit_gl();
    return ok;
}

int slr_pipeline_stat(int64_t h, int stat_id)
{
    slr_pipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    switch (stat_id)
    {
    case SLR_STAT_FRAME:             return (int)p->frame_count;
    case SLR_STAT_VISIBLE:           return p->visible_count;
    case SLR_STAT_CULLED:            return p->culled_count;
    case SLR_STAT_DRAW_CALLS:        return p->draw_calls;
    case SLR_STAT_OPAQUE_DRAWS:      return p->opaque_draws;
    case SLR_STAT_TRANSPARENT_DRAWS: return p->transparent_draws;
    case SLR_STAT_POST_ENABLED:      return p->post_enabled;
    case SLR_STAT_LAST_STAGE:        return p->last_stage;
    case SLR_STAT_OBJECT_COUNT:
    {
        int i, n = 0;
        for (i = 0; i < SLR_MAX_OBJECTS; i++) if (p->objects[i].used) n++;
        return n;
    }
    case SLR_STAT_CHUNK_COUNT:       return p->chunk_count;
    case SLR_STAT_LAYERS_MASK:       return p->layers_mask;
    case SLR_STAT_UPLOAD_COUNT:      return p->upload_count;
    case SLR_STAT_TIME_MS:           return (int)(p->time * 1000.0f);
    case SLR_STAT_DT_MS:             return (int)(p->dt * 1000.0f);
    case SLR_STAT_TEXTURE_COUNT:     return slr_texture_count();
    case SLR_STAT_PROGRAM_SWITCHES:  return p->program_switches;
    case SLR_STAT_CAMERA_COUNT:      return p->active_cam_count;
    default: set_error(SLR_E_BAD_PARAM); return 0;
    }
}

/* ===================================================================== */
/* 初始化 / 反初始化                                                       */
/* ===================================================================== */
static FARPROC resolve_gl(const char* name)
{
    FARPROC f = pwglGetProcAddress(name);
    if (!f || f == (FARPROC)1 || f == (FARPROC)2 || f == (FARPROC)3 || f == (FARPROC)(intptr_t)-1)
        f = GetProcAddress(s_hgl, name);
    return f;
}

static int load_all_gl_procs(void)
{
    int missing = 0;
#define LOAD_GL(name) \
    do { \
        p_##name = (PFN_##name)resolve_gl(#name); \
        if (!p_##name) missing = 1; \
    } while (0)

    LOAD_GL(glGetError);
    LOAD_GL(glEnable);
    LOAD_GL(glDisable);
    LOAD_GL(glClearColor);
    LOAD_GL(glClear);
    LOAD_GL(glViewport);
    LOAD_GL(glScissor);
    LOAD_GL(glDepthMask);
    LOAD_GL(glDepthFunc);
    LOAD_GL(glBlendFunc);
    LOAD_GL(glGenVertexArrays);
    LOAD_GL(glBindVertexArray);
    LOAD_GL(glDeleteVertexArrays);
    LOAD_GL(glGenBuffers);
    LOAD_GL(glBindBuffer);
    LOAD_GL(glBufferData);
    LOAD_GL(glBufferSubData);
    LOAD_GL(glDeleteBuffers);
    LOAD_GL(glBindBufferBase);
    LOAD_GL(glEnableVertexAttribArray);
    LOAD_GL(glVertexAttribPointer);
    LOAD_GL(glCreateShader);
    LOAD_GL(glShaderSource);
    LOAD_GL(glCompileShader);
    LOAD_GL(glGetShaderiv);
    LOAD_GL(glGetShaderInfoLog);
    LOAD_GL(glDeleteShader);
    LOAD_GL(glCreateProgram);
    LOAD_GL(glAttachShader);
    LOAD_GL(glLinkProgram);
    LOAD_GL(glGetProgramiv);
    LOAD_GL(glGetProgramInfoLog);
    LOAD_GL(glDeleteProgram);
    LOAD_GL(glUseProgram);
    LOAD_GL(glGetUniformLocation);
    LOAD_GL(glUniform1f);
    LOAD_GL(glUniform1i);
    LOAD_GL(glUniform4f);
    LOAD_GL(glUniformMatrix4fv);
    LOAD_GL(glGetUniformBlockIndex);
    LOAD_GL(glUniformBlockBinding);
    LOAD_GL(glGenTextures);
    LOAD_GL(glDeleteTextures);
    LOAD_GL(glBindTexture);
    LOAD_GL(glTexImage2D);
    LOAD_GL(glTexParameteri);
    LOAD_GL(glActiveTexture);
    LOAD_GL(glGenFramebuffers);
    LOAD_GL(glDeleteFramebuffers);
    LOAD_GL(glBindFramebuffer);
    LOAD_GL(glFramebufferTexture2D);
    LOAD_GL(glCheckFramebufferStatus);
    LOAD_GL(glGenRenderbuffers);
    LOAD_GL(glDeleteRenderbuffers);
    LOAD_GL(glBindRenderbuffer);
    LOAD_GL(glRenderbufferStorage);
    LOAD_GL(glFramebufferRenderbuffer);
    LOAD_GL(glReadPixels);
    LOAD_GL(glPixelStorei);
    LOAD_GL(glGetString);
    LOAD_GL(glDrawArrays);
#undef LOAD_GL
    if (missing)
    {
        set_error_detail(SLR_E_GL_SYMBOL, "GL 3.3 core symbol missing");
        return 0;
    }
    return 1;
}

#define WGL_CONTEXT_MAJOR_VERSION_ARB  0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB  0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB   0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001
#define PFD_DRAW_TO_WINDOW 0x00000004
#define PFD_SUPPORT_OPENGL 0x00000020
#define PFD_DOUBLEBUFFER    0x00000001

static int init_wgl(void)
{
    WNDCLASSA wc;
    PIXELFORMATDESCRIPTOR pfd;
    int pf;
    HGLRC dummy;
    int attribs[9];
    const char* s;
    int guard;

    /* 1) opengl32.dll */
    s_hgl = LoadLibraryA("opengl32.dll");
    if (!s_hgl) { set_error(SLR_E_OPENGL_MISSING); return 0; }
    pwglCreateContext    = (PFN_wglCreateContext)GetProcAddress(s_hgl, "wglCreateContext");
    pwglMakeCurrent      = (PFN_wglMakeCurrent)GetProcAddress(s_hgl, "wglMakeCurrent");
    pwglDeleteContext    = (PFN_wglDeleteContext)GetProcAddress(s_hgl, "wglDeleteContext");
    pwglGetProcAddress   = (PFN_wglGetProcAddress)GetProcAddress(s_hgl, "wglGetProcAddress");
    if (!pwglCreateContext || !pwglMakeCurrent || !pwglDeleteContext || !pwglGetProcAddress)
    {
        set_error(SLR_E_OPENGL_MISSING);
        return 0;
    }

    /* 上次 init 半途失败的残留清理（保证可重入）*/
    if (s_hrc)
    {
        pwglMakeCurrent(NULL, NULL);
        pwglDeleteContext(s_hrc);
        s_hrc = NULL;
    }
    if (s_hwnd)
    {
        if (s_hdc) ReleaseDC(s_hwnd, s_hdc);
        DestroyWindow(s_hwnd);
        s_hwnd = NULL;
        s_hdc = NULL;
    }

    /* 2) 隐藏窗口 */
    memset(&wc, 0, sizeof(wc));
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "SLR_HIDDEN_WND";
    if (!RegisterClassA(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        set_error(SLR_E_WINDOW);
        return 0;
    }
    s_hwnd = CreateWindowExA(0, "SLR_HIDDEN_WND", "sl_render", WS_OVERLAPPEDWINDOW,
                              CW_USEDEFAULT, CW_USEDEFAULT, 100, 100,
                              NULL, NULL, wc.hInstance, NULL);
    if (!s_hwnd) { set_error(SLR_E_WINDOW); return 0; }
    s_hdc = GetDC(s_hwnd);
    if (!s_hdc) { set_error(SLR_E_WINDOW); return 0; }

    /* 3) 像素格式 */
    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    pf = ChoosePixelFormat(s_hdc, &pfd);
    if (pf == 0 || !SetPixelFormat(s_hdc, pf, &pfd))
    {
        set_error(SLR_E_PIXEL_FORMAT);
        return 0;
    }

    /* 4) 传统上下文 → 取 ARB 扩展符号 */
    dummy = pwglCreateContext(s_hdc);
    if (!dummy || !pwglMakeCurrent(s_hdc, dummy))
    {
        set_error(SLR_E_CONTEXT);
        return 0;
    }
    pwglCreateContextAttribsARB =
        (PFN_wglCreateContextAttribsARB)pwglGetProcAddress("wglCreateContextAttribsARB");
    if (!pwglCreateContextAttribsARB ||
        pwglCreateContextAttribsARB == (void*)1 || pwglCreateContextAttribsARB == (void*)2 ||
        pwglCreateContextAttribsARB == (void*)3 || pwglCreateContextAttribsARB == (void*)(intptr_t)-1)
    {
        pwglCreateContextAttribsARB = NULL;
    }
    if (pwglCreateContextAttribsARB)
    {
        attribs[0] = WGL_CONTEXT_MAJOR_VERSION_ARB; attribs[1] = 3;
        attribs[2] = WGL_CONTEXT_MINOR_VERSION_ARB; attribs[3] = 3;
        attribs[4] = WGL_CONTEXT_PROFILE_MASK_ARB;
        attribs[5] = WGL_CONTEXT_CORE_PROFILE_BIT_ARB;
        attribs[6] = 0;
        s_hrc = pwglCreateContextAttribsARB(s_hdc, NULL, attribs);
    }
    if (!s_hrc)
    {
        /* 回退：使用传统上下文（老 ICD 也常暴露所需符号）*/
        s_hrc = dummy;
        dummy = NULL;
    }
    if (!pwglMakeCurrent(s_hdc, s_hrc))
    {
        set_error(SLR_E_CONTEXT);
        return 0;
    }
    if (dummy) { pwglDeleteContext(dummy); dummy = NULL; }

    /* 5) GL 符号解析 */
    if (!load_all_gl_procs()) return 0;

    /* 6) 冲刷粘性 GL 错误 + 像素对齐 */
    guard = 0;
    while (p_glGetError() != GL_NO_ERROR && guard++ < 32) {}
    p_glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    p_glPixelStorei(GL_PACK_ALIGNMENT, 1);

    /* 7) 设备信息缓存 */
    s = (const char*)p_glGetString(GL_RENDERER);
    _snprintf(s_renderer_str, sizeof(s_renderer_str) - 1, "%s", (s && s[0]) ? s : "unknown");
    s = (const char*)p_glGetString(GL_VERSION);
    _snprintf(s_version_str, sizeof(s_version_str) - 1, "%s", (s && s[0]) ? s : "unknown");

    if (!s_lock_init)
    {
        InitializeCriticalSection(&s_lock);
        s_lock_init = 1;
    }
    return 1;
}

int slr_init(void)
{
    s_last_error = SLR_OK;
    if (s_ready) return 1;
    if (!init_wgl()) return 0;
    if (!ensure_programs())
    {
        return 0;   /* 着色器/UBO 就绪失败，保持未初始化态 */
    }
    if (!ensure_meshes())
    {
        set_error(SLR_E_GL_SYMBOL);
        return 0;
    }
    s_ready = 1;
    return 1;
}

int slr_uninit(void)
{
    int i;
    s_last_error = SLR_OK;
    if (!s_ready) return 1;
    EnterCriticalSection(&s_lock);
    if (pwglMakeCurrent(s_hdc, s_hrc))
    {
        /* 管线 / 纹理 / v1 ctx 资源回收 */
        for (i = 0; i < SLR_MAX_PIPES; i++)
            if (s_pipes[i].used) pipeline_release_targets(&s_pipes[i]);
        memset(s_pipes, 0, sizeof(s_pipes));
        for (i = 0; i < SLR_MAX_TEX; i++)
            if (s_textures[i].used) p_glDeleteTextures(1, &s_textures[i].gltex);
        memset(s_textures, 0, sizeof(s_textures));
        for (i = 0; i < SLR_MAX_CTX; i++)
            if (s_ctxs[i].used)
            {
                p_glDeleteFramebuffers(1, &s_ctxs[i].fbo);
                p_glDeleteTextures(1, &s_ctxs[i].tex);
                if (s_ctxs[i].rb) p_glDeleteRenderbuffers(1, &s_ctxs[i].rb);
            }
        memset(s_ctxs, 0, sizeof(s_ctxs));
        for (i = 0; i < SLR_PROG_COUNT; i++)
            if (s_progs[i]) p_glDeleteProgram(s_progs[i]);
        memset(s_progs, 0, sizeof(s_progs));
        for (i = 0; i < 4; i++)
        {
            if (s_meshes[i].vao) p_glDeleteVertexArrays(1, &s_meshes[i].vao);
            if (s_meshes[i].vbo) p_glDeleteBuffers(1, &s_meshes[i].vbo);
        }
        memset(s_meshes, 0, sizeof(s_meshes));
        if (s_ubo) p_glDeleteBuffers(1, &s_ubo);
        s_ubo = 0;
    }
    pwglMakeCurrent(NULL, NULL);
    if (s_hrc) { pwglDeleteContext(s_hrc); s_hrc = NULL; }
    if (s_hwnd) { DestroyWindow(s_hwnd); s_hwnd = NULL; }
    if (s_hgl) { FreeLibrary(s_hgl); s_hgl = NULL; }
    LeaveCriticalSection(&s_lock);
    if (s_lock_init) { DeleteCriticalSection(&s_lock); s_lock_init = 0; }
    s_ready = 0;
    return 1;
}

/* ---- 诊断导出 ---- */
int slr_last_error(void) { return s_last_error; }

const char* slr_error_string(int err)
{
    switch (err)
    {
    case SLR_OK:                return "ok";
    case SLR_E_OPENGL_MISSING:  return "opengl32.dll load failed";
    case SLR_E_WINDOW:          return "hidden window creation failed";
    case SLR_E_PIXEL_FORMAT:    return "pixel format unavailable";
    case SLR_E_CONTEXT:         return "GL context creation failed";
    case SLR_E_NO_ARB:          return "WGL_ARB_create_context unavailable";
    case SLR_E_GL_SYMBOL:
        return (s_err_detail[0]) ? s_err_detail : "GL symbol resolution failed";
    case SLR_E_NOT_INITIALIZED: return "not initialized (call slr_init)";
    case SLR_E_BAD_HANDLE:      return "invalid handle";
    case SLR_E_BAD_PARAM:       return "invalid parameter";
    case SLR_E_FBO:             return "framebuffer incomplete";
    case SLR_E_SHADER:
        return (s_err_detail[0]) ? s_err_detail : "shader compile/link failed";
    case SLR_E_MEMORY:          return "memory allocation failed";
    case SLR_E_CONTEXT_CURRENT: return "wglMakeCurrent failed";
    case SLR_E_OBJECT:          return "invalid scene object";
    case SLR_E_TEXTURE:         return "invalid texture";
    case SLR_E_PIPELINE:        return "invalid pipeline";
    case SLR_E_STATE:          return "invalid pipeline stage state";
    case SLR_E_LIMIT:           return "resource limit reached";
    case SLR_E_IMAGE:           return "image file decode failed";
    default:                    return "unknown error";
    }
}

const char* slr_error_detail(void) { return s_err_detail; }

const char* slr_renderer_string(void) { return s_renderer_str; }
const char* slr_version_string(void)  { return s_version_str; }
