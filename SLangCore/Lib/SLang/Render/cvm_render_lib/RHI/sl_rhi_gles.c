/* =========================================================================
 * sl_rhi_gles.c —— RHI 后端：EGL + OpenGL ES 3.0（Windows / 嵌入式 / Web 载体）
 *
 * 与 GL 桌面后端（sl_rhi_gl.c）渲染完全一致效果的 GLES 3.0 实现：
 *   - 零构建依赖：libEGL.dll / libGLESv2.dll 运行期 LoadLibrary 探测，
 *     EGL 函数经 GetProcAddress 解析、GLES 函数经 eglGetProcAddress
 *     解析（回退 GetProcAddress），无 SDK 头与 .lib；
 *   - 缺失 GLES 运行库的机器：init 返回 0 置 SLR_E_BACKEND 优雅降级
 *     （slr_init_backend("gles") 返回 false，GLRenderTest 报 SKIP）；
 *   - 着色器为 GLSL ES 3.00 版（与 GL 330 六组逐组对应，片段一律
 *     precision highp 保证与 GL/D3D11 逐字节同像素）；
 *   - 上下文：EGL_DEFAULT_DISPLAY + eglInitialize + eglBindAPI(ES) +
 *     eglCreateContext(client version 3)；优先 EGL_KHR_surfaceless_context
 *     无表面绑定（纯离屏），不支持则回退 1x1 pbuffer；
 *   - 函数指针清单复用 RHI/sl_gl_procs.h（清单内函数全部是 ES 3.0 core）。
 *
 * 管线 pass / 网格 / PerDraw UBO / 回读行翻与 GL 后端逐行同构
 * （GL 语义即 GLES 语义：视口左下原点、glReadPixels 产出 bottom-up、
 *  清屏受 scissor / DepthMask 限制的坑一致处理）。
 * ========================================================================= */
#include "sl_render_internal.h"   /* vm_sl_render.h + RHI/sl_rhi.h + 共享结构 */
#include "sl_rhi_shaders_gen.h"   /* v3.5 固化着色器（GLSL330 + ESSL300 + DXBC blob）*/

/* 固化头槽位一致性编译期检查：枚举 gen 段长度必须正好覆盖 SLR_GEN_SETS
 * 全表（不匹配 = 枚举与固化头版本脱节，编译期即爆）*/
typedef char slr_gen_slot_check[
    (SLR_GEN_EFFECT_COUNT * 2 == SLR_PROG_COUNT - SLR_PROG_GEN_BASE) ? 1 : -1];

/* ===================================================================== */
/* GL 类型 / 常量（与 sl_rhi_gl.c 相同；ES 3.0 core 值一致）               */
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
#define GL_FLOAT                  0x1406
#define GL_RGBA                   0x1908
#define GL_RGBA8                  0x8058
#define GL_DEPTH_COMPONENT24      0x81A6
#define GL_DEPTH_COMPONENT16      0x81A5
#define GL_COLOR_BUFFER_BIT        0x00004000
#define GL_DEPTH_BUFFER_BIT        0x00000100
#define GL_BLEND                  0x0BE2
#define GL_SRC_ALPHA              0x0302
#define GL_ONE_MINUS_SRC_ALPHA    0x0303
#define GL_DEPTH_TEST             0x0B71
#define GL_DEPTH_FUNC             0x0B74
#define GL_SCISSOR_TEST           0x0C11
#define GL_LESS                   0x0201
#define GL_ARRAY_BUFFER           0x8892
#define GL_STATIC_DRAW            0x88E4
#define GL_DYNAMIC_DRAW           0x88E8
#define GL_UNIFORM_BUFFER         0x8A11
#define GL_TEXTURE_2D             0x0DE1
#define GL_TEXTURE0               0x84C0
#define GL_TEXTURE1               0x84C1
#define GL_TEXTURE2               0x84C2   /* N2a：shadow depth 采样单元 */
#define GL_TEXTURE_MIN_FILTER     0x2801
#define GL_TEXTURE_MAG_FILTER     0x2800
#define GL_TEXTURE_WRAP_S         0x2802
#define GL_TEXTURE_WRAP_T         0x2803
#define GL_LINEAR                 0x2601
#define GL_NEAREST                0x2600  /* N2a：深度纹理 NEAREST */
#define GL_CLAMP_TO_EDGE          0x812F
#define GL_NONE                   0
#define GL_DEPTH_COMPONENT        0x1902
#define GL_UNSIGNED_INT           0x1405
#define GL_FRAMEBUFFER            0x8D40
#define GL_RENDERBUFFER           0x8D41
#define GL_COLOR_ATTACHMENT0      0x8CE0
#define GL_DEPTH_ATTACHMENT       0x8D00
#define GL_FRAMEBUFFER_COMPLETE   0x8CD5
#define GL_VERTEX_SHADER          0x8B31
#define GL_FRAGMENT_SHADER        0x8B30
#define GL_COMPILE_STATUS         0x8B81
#define GL_LINK_STATUS             0x8B82
#define GL_INFO_LOG_LENGTH        0x8B84
#define GL_PACK_ALIGNMENT         0x0D05
#define GL_UNPACK_ALIGNMENT       0x0CF5
#define GL_VENDOR                 0x1F00
#define GL_RENDERER               0x1F01
#define GL_VERSION                0x1F02

#ifndef APIENTRY
#define APIENTRY
#endif

/* ---- GLES 函数指针：两遍展开（清单与 GL 后端共用）----
 * 定义带 static：与 sl_rhi_gl.c 的同名指针（外部链接）隔离，
 * 两后端各持一份解析结果，互不干扰。*/
#define GLDECL(name, ret, params) typedef ret (APIENTRY *PFN_##name) params;
#include "RHI/sl_gl_procs.h"
#undef GLDECL
#define GLDECL(name, ret, params) static PFN_##name p_##name = NULL;
#include "RHI/sl_gl_procs.h"
#undef GLDECL

/* ===================================================================== */
/* EGL 类型 / 常量（手写，零 SDK 依赖）                                    */
/* ===================================================================== */
typedef void* EGLDisplay;
typedef void* EGLContext;
typedef void* EGLSurface;
typedef void* EGLConfig;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;

#define EGL_DEFAULT_DISPLAY       ((void*)0)
#define EGL_NO_DISPLAY            ((void*)0)
#define EGL_NO_CONTEXT            ((void*)0)
#define EGL_NO_SURFACE            ((void*)0)
#define EGL_FALSE                 0
#define EGL_TRUE                  1
#define EGL_SUCCESS               0x3000
#define EGL_BAD_DISPLAY           0x3008
#define EGL_NOT_INITIALIZED       0x3009
#define EGL_BAD_ATTRIBUTE         0x3004

#define EGL_ALPHA_SIZE            0x3021
#define EGL_BLUE_SIZE             0x3022
#define EGL_GREEN_SIZE            0x3023
#define EGL_RED_SIZE              0x3024
#define EGL_DEPTH_SIZE            0x3025
#define EGL_STENCIL_SIZE          0x3026
#define EGL_SURFACE_TYPE          0x3033
#define EGL_NONE                  0x3038
#define EGL_WIDTH                 0x3057
#define EGL_HEIGHT                0x3056
#define EGL_VENDOR                0x3053
#define EGL_VERSION               0x3054
#define EGL_EXTENSIONS            0x3055
#define EGL_RENDERABLE_TYPE       0x3040
#define EGL_PBUFFER_BIT           0x0001
#define EGL_OPENGL_ES3_BIT        0x0040
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_OPENGL_ES_API         0x30A2

typedef EGLDisplay (WINAPI *PFN_eglGetDisplay)(void*);
typedef EGLBoolean (WINAPI *PFN_eglInitialize)(EGLDisplay, EGLint*, EGLint*);
typedef EGLBoolean (WINAPI *PFN_eglBindAPI)(EGLenum);
typedef EGLBoolean (WINAPI *PFN_eglChooseConfig)(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*);
typedef EGLContext (WINAPI *PFN_eglCreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint*);
typedef EGLSurface (WINAPI *PFN_eglCreatePbufferSurface)(EGLDisplay, EGLConfig, const EGLint*);
typedef EGLBoolean (WINAPI *PFN_eglMakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
typedef EGLBoolean (WINAPI *PFN_eglDestroyContext)(EGLDisplay, EGLContext);
typedef EGLBoolean (WINAPI *PFN_eglDestroySurface)(EGLDisplay, EGLSurface);
typedef EGLBoolean (WINAPI *PFN_eglTerminate)(EGLDisplay);
typedef void*      (WINAPI *PFN_eglGetProcAddress)(const char*);
typedef EGLint     (WINAPI *PFN_eglGetError)(void);
typedef const char*(WINAPI *PFN_eglQueryString)(EGLDisplay, EGLint);

static PFN_eglGetDisplay           p_eglGetDisplay;
static PFN_eglInitialize           p_eglInitialize;
static PFN_eglBindAPI              p_eglBindAPI;
static PFN_eglChooseConfig         p_eglChooseConfig;
static PFN_eglCreateContext        p_eglCreateContext;
static PFN_eglCreatePbufferSurface p_eglCreatePbufferSurface;
static PFN_eglMakeCurrent          p_eglMakeCurrent;
static PFN_eglDestroyContext        p_eglDestroyContext;
static PFN_eglDestroySurface       p_eglDestroySurface;
static PFN_eglTerminate            p_eglTerminate;
static PFN_eglGetProcAddress       p_eglGetProcAddress;
static PFN_eglGetError             p_eglGetError;
static PFN_eglQueryString          p_eglQueryString;

/* ===================================================================== */
/* 后端私有状态                                                           */
/* ===================================================================== */
struct SlrRhiTarget            /* GLES 渲染目标 = FBO + 颜色纹理 + 可选深度 RB */
{
    int w, h;
    GLuint fbo, tex, rb;
    GLuint depth_tex;   /* N2a shadow：可采样深度纹理（仅 shadow 目标非 0）*/
};

typedef struct { int mvp, color, tex, shadow_tex; int obj_index; int src, bright, sat, vig; } GlProgUni;
typedef struct { GLuint vao, vbo; int count; } GlMesh;

/* ES 3.0 深度清屏是 glClearDepthf（float），共享清单里的 glClearDepth
 * (GLdouble) 在 ES 无符号——本地声明 + load（N2a shadow 用）*/
typedef void (APIENTRY *PFN_glClearDepthfES)(GLfloat);
static PFN_glClearDepthfES p_glClearDepthfES = NULL;

static GLuint       s_progs[SLR_PROG_COUNT];
static GlProgUni  s_uni[SLR_PROG_COUNT];
static GLuint       s_ubo = 0;
static GLuint       s_ubo_light = 0;   /* LightBlock UBO（绑定点 1）*/
static GlMesh      s_meshes[4];
static GlMesh      s_custom[SLR_CUSTOM_MESHES];   /* 动态网格（mesh id = 4+slot）*/
static GLuint       s_desc_tex[SLR_DESC_TEX_SLOTS];   /* 描述符槽表（free_shared 前向引用）*/

static HMODULE  s_hegl = NULL;
static HMODULE  s_hgles = NULL;
static EGLDisplay s_dpy = NULL;
static EGLContext s_ctx = NULL;
static EGLSurface  s_surf = NULL;
static CRITICAL_SECTION s_lock;
static int      s_lock_init = 0;

/* ===================================================================== */
/* 着色器（GLSL ES 3.00，六组与 GL330/D3D11/VK 逐组对应；片段 highp）       */
/* ===================================================================== */
static const char* VS_SCENE =
    "#version 300 es\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "uniform mat4 uMVP;\n"
    "out vec2 vUv;\n"
    "void main(){ vUv = aUv; gl_Position = uMVP * vec4(aPos, 0.0, 1.0); }\n";

static const char* FS_FLAT =
    "#version 300 es\n"
    "precision highp float;\n"
    "out vec4 oCol;\n"
    "uniform vec4 uColor;\n"
    "void main(){ oCol = uColor; }\n";

static const char* FS_TEX =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "uniform vec4 uColor;\n"
    "uniform sampler2D uTex;\n"
    "void main(){ oCol = uColor * texture(uTex, vUv); }\n";

static const char* VS_PSCENE =
    "#version 300 es\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "uniform highp int uObjIndex;\n"
    "out vec2 vUv;\n"
    "out vec2 vWorld;\n"
    "out vec2 vNrm;\n"
    "flat out highp int vObj;\n"
    "void main(){\n"
    "  vUv = aUv;\n"
    "  int obj = uObjIndex + gl_InstanceID;\n"
    "  int k = obj * 2;\n"
    "  vWorld = vec2(dot(aPos, uWMat[k].xy), dot(aPos, uWMat[k].zw)) + uWMat[k + 1].xy;\n"
    "  vNrm = uWMat[k + 1].zw;\n"
    "  vObj = obj;\n"
    "  gl_Position = uMVP[obj] * vec4(aPos, 0.0, 1.0); }\n";

/* 管线片元光照（与 GL/D3D11 后端公式逐字一致，跨后端同效果）*/
static const char* FS_PFLAT =
    "#version 300 es\n"
    "precision highp float;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "flat in highp int vObj;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[vObj];\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  if (uDirColor.a > 0.5) light += uDirColor.rgb * max(dot(vNrm, uDirDir.xy), 0.0);\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    vec2 toF = vWorld - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    light += uSpotColor.rgb * att * smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "  }\n"
    "  oCol = vec4(base.rgb * light, base.a); }\n";

static const char* FS_PTEX =
    "#version 300 es\n"
    "precision highp float;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "flat in highp int vObj;\n"
    "uniform sampler2D uTex;\n"
    "in vec2 vUv;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[vObj] * texture(uTex, vUv);\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  if (uDirColor.a > 0.5) light += uDirColor.rgb * max(dot(vNrm, uDirDir.xy), 0.0);\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    vec2 toF = vWorld - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    light += uSpotColor.rgb * att * smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "  }\n"
    "  oCol = vec4(base.rgb * light, base.a); }\n";

/* v3.4 Phong 光照模型（与 GL/D3D11 后端公式逐字一致）：
 * v3.3 光照 + 伪 3D 高光（N=normalize(vec3(vNrm,0.75))，V=(0,0,1)，
 * R=reflect(-L,N)，spec=pow(max(dot(R,V),0),shin)*strength）*/
static const char* FS_PHONG_FLAT =
    "#version 300 es\n"
    "precision highp float;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "flat in highp int vObj;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[vObj];\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  vec3 N = normalize(vec3(vNrm, 0.75));\n"
    "  vec3 V = vec3(0.0, 0.0, 1.0);\n"
    "  vec2 sp = uSpec[vObj].xy;\n"
    "  float shin = max(sp.y, 0.001);\n"
    "  if (uDirColor.a > 0.5) {\n"
    "    light += uDirColor.rgb * max(dot(vNrm, uDirDir.xy), 0.0);\n"
    "    vec3 L = normalize(vec3(uDirDir.xy, 0.6));\n"
    "    vec3 R = reflect(-L, N);\n"
    "    light += uDirColor.rgb * pow(max(dot(R, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    vec2 toF = vWorld - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    float cone = smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "    light += uSpotColor.rgb * att * cone;\n"
    "    vec3 L2 = normalize(vec3(-toF / max(d, 1e-4), 0.6));\n"
    "    vec3 R2 = reflect(-L2, N);\n"
    "    light += uSpotColor.rgb * att * cone * pow(max(dot(R2, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  oCol = vec4(base.rgb * light, base.a); }\n";

static const char* FS_PHONG_TEX =
    "#version 300 es\n"
    "precision highp float;\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "flat in highp int vObj;\n"
    "uniform sampler2D uTex;\n"
    "in vec2 vUv;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[vObj] * texture(uTex, vUv);\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  vec3 N = normalize(vec3(vNrm, 0.75));\n"
    "  vec3 V = vec3(0.0, 0.0, 1.0);\n"
    "  vec2 sp = uSpec[vObj].xy;\n"
    "  float shin = max(sp.y, 0.001);\n"
    "  if (uDirColor.a > 0.5) {\n"
    "    light += uDirColor.rgb * max(dot(vNrm, uDirDir.xy), 0.0);\n"
    "    vec3 L = normalize(vec3(uDirDir.xy, 0.6));\n"
    "    vec3 R = reflect(-L, N);\n"
    "    light += uDirColor.rgb * pow(max(dot(R, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  if (uSpotColor.a > 0.5) {\n"
    "    vec2 toF = vWorld - uSpotPosRange.xy;\n"
    "    float d = length(toF);\n"
    "    float att = clamp(1.0 - d / max(uSpotPosRange.z, 1e-4), 0.0, 1.0);\n"
    "    att *= att;\n"
    "    float ca = dot(toF, uSpotDirCos.xy) / max(d, 1e-4);\n"
    "    float ce = uSpotDirCos.z;\n"
    "    float cone = smoothstep(ce, ce + (1.0 - ce) * 0.5, ca);\n"
    "    light += uSpotColor.rgb * att * cone;\n"
    "    vec3 L2 = normalize(vec3(-toF / max(d, 1e-4), 0.6));\n"
    "    vec3 R2 = reflect(-L2, N);\n"
    "    light += uSpotColor.rgb * att * cone * pow(max(dot(R2, V), 0.0), shin) * sp.x;\n"
    "  }\n"
    "  oCol = vec4(base.rgb * light, base.a); }\n";

static const char* VS_FULL =
    "#version 300 es\n"
    "layout(location=0) in vec2 aPos;\n"
    "layout(location=1) in vec2 aUv;\n"
    "out vec2 vUv;\n"
    "void main(){ vUv = aUv; gl_Position = vec4(aPos, 0.0, 1.0); }\n";

static const char* FS_BLIT =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 vUv;\n"
    "out vec4 oCol;\n"
    "uniform sampler2D uSrc;\n"
    "void main(){ oCol = texture(uSrc, vUv); }\n";

static const char* FS_POST =
    "#version 300 es\n"
    "precision highp float;\n"
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

/* ---- 共享资源构建（程序 + 网格 + PerDraw UBO）---- */
static int gl_make_shared(void)
{
    int i;
    for (i = 0; i < SLR_PROG_COUNT; i++) s_progs[i] = 0;

    if (!make_program(SLR_PROG_FLAT, VS_SCENE, FS_FLAT)) return 0;
    if (!make_program(SLR_PROG_TEX,  VS_SCENE, FS_TEX))  return 0;
    if (!make_program(SLR_PROG_PFLAT, VS_PSCENE, FS_PFLAT)) return 0;
    if (!make_program(SLR_PROG_PTEX,  VS_PSCENE, FS_PTEX))  return 0;
    if (!make_program(SLR_PROG_PHONG_FLAT, VS_PSCENE, FS_PHONG_FLAT)) return 0;
    if (!make_program(SLR_PROG_PHONG_TEX,  VS_PSCENE, FS_PHONG_TEX))  return 0;
    if (!make_program(SLR_PROG_BLIT, VS_FULL,  FS_BLIT))  return 0;
    if (!make_program(SLR_PROG_POST, VS_FULL,  FS_POST))  return 0;

    /* v3.5 固化效果槽：5 效果 × 2 变体（固化 ESSL300 源运行期编译，
     * 与内建程序同一 make_program 路径——编译/链接失败同样致命）*/
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
    {
        const SlrGenShaderSet* gs = &SLR_GEN_SETS[i];
        if (!make_program(SLR_PROG_GEN_BASE + i, gs->essl_vs, gs->essl_fs)) return 0;
    }

    s_uni[SLR_PROG_FLAT].mvp   = p_glGetUniformLocation(s_progs[SLR_PROG_FLAT], "uMVP");
    s_uni[SLR_PROG_FLAT].color = p_glGetUniformLocation(s_progs[SLR_PROG_FLAT], "uColor");

    s_uni[SLR_PROG_TEX].mvp   = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uMVP");
    s_uni[SLR_PROG_TEX].color = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uColor");
    s_uni[SLR_PROG_TEX].tex   = p_glGetUniformLocation(s_progs[SLR_PROG_TEX], "uTex");

    s_uni[SLR_PROG_PFLAT].obj_index = p_glGetUniformLocation(s_progs[SLR_PROG_PFLAT], "uObjIndex");
    s_uni[SLR_PROG_PTEX].obj_index  = p_glGetUniformLocation(s_progs[SLR_PROG_PTEX], "uObjIndex");
    s_uni[SLR_PROG_PTEX].tex        = p_glGetUniformLocation(s_progs[SLR_PROG_PTEX], "uTex");
    s_uni[SLR_PROG_PHONG_FLAT].obj_index = p_glGetUniformLocation(s_progs[SLR_PROG_PHONG_FLAT], "uObjIndex");
    s_uni[SLR_PROG_PHONG_TEX].obj_index  = p_glGetUniformLocation(s_progs[SLR_PROG_PHONG_TEX], "uObjIndex");
    s_uni[SLR_PROG_PHONG_TEX].tex        = p_glGetUniformLocation(s_progs[SLR_PROG_PHONG_TEX], "uTex");

    /* v3.5 固化槽 uniform：全槽取 uObjIndex；偶数下标（TEX 变体）取 uTex；
     * N2a：全 gen 槽取 uShadowTex 绑 TEXTURE2（flat/tex 变体都有 shadow 采样）*/
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
    {
        int gslot = SLR_PROG_GEN_BASE + i;
        s_uni[gslot].obj_index = p_glGetUniformLocation(s_progs[gslot], "uObjIndex");
        s_uni[gslot].shadow_tex = p_glGetUniformLocation(s_progs[gslot], "uShadowTex");
        if (!(i & 1))
            s_uni[gslot].tex = p_glGetUniformLocation(s_progs[gslot], "uTex");
    }

    s_uni[SLR_PROG_BLIT].src  = p_glGetUniformLocation(s_progs[SLR_PROG_BLIT], "uSrc");
    s_uni[SLR_PROG_POST].src  = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uSrc");
    s_uni[SLR_PROG_POST].bright = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uBrightness");
    s_uni[SLR_PROG_POST].sat    = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uSaturation");
    s_uni[SLR_PROG_POST].vig    = p_glGetUniformLocation(s_progs[SLR_PROG_POST], "uVignette");

    /* 采样器常量：管线纹理走 unit 1，全屏拷贝走 unit 0 */
    p_glUseProgram(s_progs[SLR_PROG_TEX]);
    p_glUniform1i(s_uni[SLR_PROG_TEX].tex, 1);
    p_glUseProgram(s_progs[SLR_PROG_PTEX]);
    p_glUniform1i(s_uni[SLR_PROG_PTEX].tex, 1);
    p_glUseProgram(s_progs[SLR_PROG_PHONG_TEX]);
    p_glUniform1i(s_uni[SLR_PROG_PHONG_TEX].tex, 1);
    /* v3.5 固化槽 + N2a shadow：偶数下标（TEX 变体）管线纹理走 unit 1；
     * 全槽 uShadowTex 走 unit 2——glUniform1i 只作用于当前绑定 program，
     * 必须逐槽 useProgram 后设置（gen 全槽含 shadow 采样，同 GL 后端）*/
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
    {
        int gslot = SLR_PROG_GEN_BASE + i;
        p_glUseProgram(s_progs[gslot]);
        if (!(i & 1))
            p_glUniform1i(s_uni[gslot].tex, 1);
        if (s_uni[gslot].shadow_tex >= 0)
            p_glUniform1i(s_uni[gslot].shadow_tex, 2);
    }
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
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PHONG_FLAT], "PerDraw");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PHONG_FLAT], blk, 0);
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PHONG_TEX], "PerDraw");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PHONG_TEX], blk, 0);
        /* v3.5 固化槽：PerDraw 块绑定 0（与内建同 UBO 直接共享）*/
        for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
        {
            int gslot = SLR_PROG_GEN_BASE + i;
            blk = p_glGetUniformBlockIndex(s_progs[gslot], "PerDraw");
            if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[gslot], blk, 0);
        }
        p_glGenBuffers(1, &s_ubo);
        p_glBindBuffer(GL_UNIFORM_BUFFER, s_ubo);
        p_glBufferData(GL_UNIFORM_BUFFER, (GLsizeiptr)sizeof(SlrPerDraw), &s_perdraw, GL_DYNAMIC_DRAW);
        p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, s_ubo);
        p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }

    /* LightBlock UBO：块绑定 1（PFLAT/PTEX/PHONG_* 消费；帧级 upload_lights 更新）*/
    {
        GLuint blk;
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PFLAT], "LightBlock");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PFLAT], blk, 1);
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PTEX], "LightBlock");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PTEX], blk, 1);
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PHONG_FLAT], "LightBlock");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PHONG_FLAT], blk, 1);
        blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_PHONG_TEX], "LightBlock");
        if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[SLR_PROG_PHONG_TEX], blk, 1);
        /* v3.5 固化槽：LightBlock 块绑定 1（与内建同 UBO 直接共享）*/
        for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
        {
            int gslot = SLR_PROG_GEN_BASE + i;
            blk = p_glGetUniformBlockIndex(s_progs[gslot], "LightBlock");
            if (blk != 0xFFFFFFFFu) p_glUniformBlockBinding(s_progs[gslot], blk, 1);
        }
        p_glGenBuffers(1, &s_ubo_light);
        p_glBindBuffer(GL_UNIFORM_BUFFER, s_ubo_light);
        p_glBufferData(GL_UNIFORM_BUFFER, (GLsizeiptr)sizeof(SlrLightBlock), NULL, GL_DYNAMIC_DRAW);
        p_glBindBufferBase(GL_UNIFORM_BUFFER, 1, s_ubo_light);
        p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }

    /* 静态网格（pos2 + uv2，stride 16B；GLES 无 D3D 行序差异 -> GL 原版）*/
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
        const float* datas[4] = { tri, quad, fs_tri, ctx_tri };
        const int   counts[4] = { 3, 6, 3, 3 };
        for (i = 0; i < 4; i++)
        {
            p_glGenVertexArrays(1, &s_meshes[i].vao);
            p_glGenBuffers(1, &s_meshes[i].vbo);
            p_glBindVertexArray(s_meshes[i].vao);
            p_glBindBuffer(GL_ARRAY_BUFFER, s_meshes[i].vbo);
            p_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(counts[i] * 16), datas[i], GL_STATIC_DRAW);
            p_glEnableVertexAttribArray(0);
            p_glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (const void*)0);
            p_glEnableVertexAttribArray(1);
            p_glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (const void*)8);
            p_glBindVertexArray(0);
            s_meshes[i].count = counts[i];
        }
    }
    return 1;
}

static void gl_free_shared(void)
{
    int i;
    for (i = 0; i < SLR_PROG_COUNT; i++)
        if (s_progs[i]) p_glDeleteProgram(s_progs[i]);
    memset(s_progs, 0, sizeof(s_progs));
    for (i = 0; i < 4; i++)
    {
        if (s_meshes[i].vao) p_glDeleteVertexArrays(1, &s_meshes[i].vao);
        if (s_meshes[i].vbo) p_glDeleteBuffers(1, &s_meshes[i].vbo);
    }
    memset(s_meshes, 0, sizeof(s_meshes));
    for (i = 0; i < SLR_CUSTOM_MESHES; i++)
    {
        if (s_custom[i].vao) p_glDeleteVertexArrays(1, &s_custom[i].vao);
        if (s_custom[i].vbo) p_glDeleteBuffers(1, &s_custom[i].vbo);
    }
    memset(s_custom, 0, sizeof(s_custom));
    /* 描述符槽表清空（纹理已先销毁，防悬空纹理名）*/
    memset(s_desc_tex, 0, sizeof(s_desc_tex));
    if (s_ubo) p_glDeleteBuffers(1, &s_ubo);
    s_ubo = 0;
    if (s_ubo_light) p_glDeleteBuffers(1, &s_ubo_light);
    s_ubo_light = 0;
}

/* ===================================================================== */
/* 渲染目标 / 纹理（与 GL 后端同构）                                        */
/* ===================================================================== */
static SlrRhiTarget* gl_target_create(int w, int h, int with_depth)
{
    SlrRhiTarget* t = (SlrRhiTarget*)malloc(sizeof(SlrRhiTarget));
    GLenum st;
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    t->w = w; t->h = h; t->fbo = 0; t->tex = 0; t->rb = 0; t->depth_tex = 0;
    p_glGenFramebuffers(1, &t->fbo);
    p_glGenTextures(1, &t->tex);
    p_glBindTexture(GL_TEXTURE_2D, t->tex);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, 0x1401, NULL);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLint)GL_CLAMP_TO_EDGE);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLint)GL_CLAMP_TO_EDGE);
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->tex, 0);
    if (with_depth)
    {
        p_glGenRenderbuffers(1, &t->rb);
        p_glBindRenderbuffer(GL_RENDERBUFFER, t->rb);
        /* ES 3.0 必须带内部格式常量（GL_RENDERBUFFER 内部格式枚举）*/
        p_glRenderbufferStorage(GL_RENDERBUFFER, (GLenum)GL_DEPTH_COMPONENT24, w, h);
        p_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, t->rb);
    }
    st = p_glCheckFramebufferStatus(GL_FRAMEBUFFER);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (st != GL_FRAMEBUFFER_COMPLETE)
    {
        p_glDeleteFramebuffers(1, &t->fbo);
        p_glDeleteTextures(1, &t->tex);
        if (t->rb) p_glDeleteRenderbuffers(1, &t->rb);
        free(t);
        set_error(SLR_E_FBO);
        return NULL;
    }
    return t;
}

static void gl_target_destroy(SlrRhiTarget* t)
{
    if (!t) return;
    p_glDeleteFramebuffers(1, &t->fbo);
    p_glDeleteTextures(1, &t->tex);
    if (t->rb) p_glDeleteRenderbuffers(1, &t->rb);
    if (t->depth_tex) p_glDeleteTextures(1, &t->depth_tex);
    free(t);
}

/* ---- N2a shadow map（与 GL 后端同构；ES 3.0 depth texture 原生支持）----
 * depth-only FBO（glDrawBuffers(GL_NONE)）+ GL_DEPTH_COMPONENT24 纹理
 *（NEAREST，无 compare mode —— shader 手动 PCF）。 */
static SlrRhiTarget* gl_shadow_target_create(int w, int h)
{
    SlrRhiTarget* t = (SlrRhiTarget*)malloc(sizeof(SlrRhiTarget));
    GLenum st, none = (GLenum)GL_NONE;
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    t->w = w; t->h = h; t->fbo = 0; t->tex = 0; t->rb = 0; t->depth_tex = 0;
    p_glGenFramebuffers(1, &t->fbo);
    p_glGenTextures(1, &t->depth_tex);
    p_glBindTexture(GL_TEXTURE_2D, t->depth_tex);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_DEPTH_COMPONENT24, w, h, 0,
                   GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, NULL);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, (GLint)GL_NEAREST);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (GLint)GL_NEAREST);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLint)GL_CLAMP_TO_EDGE);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLint)GL_CLAMP_TO_EDGE);
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D,
                             t->depth_tex, 0);
    p_glDrawBuffers(1, &none);   /* 无颜色输出：片元只写深度 */
    st = p_glCheckFramebufferStatus(GL_FRAMEBUFFER);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (st != GL_FRAMEBUFFER_COMPLETE)
    {
        p_glDeleteFramebuffers(1, &t->fbo);
        p_glDeleteTextures(1, &t->depth_tex);
        free(t);
        set_error(SLR_E_FBO);
        return NULL;
    }
    return t;
}

static void gl_shadow_target_destroy(SlrRhiTarget* t)
{
    gl_target_destroy(t);
}

/* shadow pass 开始：绑深度 FBO + 清深度（ES glClearDepthf）+ 关颜色写。 */
static void gl_shadow_begin(SlrRhiTarget* t, int w, int h)
{
    (void)t;
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    p_glDepthMask(GL_TRUE);
    p_glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
    if (p_glClearDepthfES) p_glClearDepthfES(1.0f);
    p_glClear(GL_DEPTH_BUFFER_BIT);
    p_glDisable(GL_BLEND);
    p_glEnable(GL_DEPTH_TEST);
    p_glDepthFunc(GL_LESS);
    p_glDisable(GL_SCISSOR_TEST);
}

/* 深度纹理绑 TEXTURE2（gen 着色器 uShadowTex 单元 2），帧一次。 */
static void gl_shadow_bind_depth(SlrRhiTarget* t)
{
    p_glActiveTexture(GL_TEXTURE2);
    p_glBindTexture(GL_TEXTURE_2D, t ? t->depth_tex : 0);
}

/* rgba 首行 = 图像底部（sl_texture.c 已统一翻转），GLES 原样入显存 */
static void* gl_texture_create(int w, int h, const unsigned char* rgba)
{
    GLuint t = 0;
    p_glGenTextures(1, &t);
    p_glBindTexture(GL_TEXTURE_2D, t);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, 0x1401, rgba);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, (GLint)GL_LINEAR);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLint)GL_CLAMP_TO_EDGE);
    p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLint)GL_CLAMP_TO_EDGE);
    p_glBindTexture(GL_TEXTURE_2D, 0);
    return (void*)(intptr_t)t;
}

static void gl_texture_destroy(void* tex)
{
    GLuint t = (GLuint)(intptr_t)tex;
    if (t) p_glDeleteTextures(1, &t);
}

/* ===================================================================== */
/* 管线 pass（与 GL 后端逐行同构：GL 语义即 GLES 语义）                     */
/* ===================================================================== */
static void gl_begin_scene(SlrRhiTarget* t, int w, int h, const float* clear)
{
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    /* DepthMask 必须先于清屏打开：glClear(DEPTH) 受深度写掩码限制 */
    p_glDepthMask(GL_TRUE);
    /* N2a：shadow pass 关掉的 ColorMask 在此恢复（主渲染入口统一重置）*/
    p_glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    p_glClearColor(clear[0], clear[1], clear[2], clear[3]);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    p_glDisable(GL_BLEND);
    p_glEnable(GL_DEPTH_TEST);
    p_glDepthFunc(GL_LESS);
    p_glDisable(GL_SCISSOR_TEST);
}

static void gl_camera_begin(SlrRhiTarget* t, int x, int y, int w, int h,
                            int target_h, int clear_flags, const float* clear)
{
    (void)target_h;   /* GLES 视口原点即左下，与 GL 一致 */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    /* N2a：shadow pass（阶段 4.5）关掉的 ColorMask 在此恢复（同 GL）*/
    p_glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    p_glViewport(x, y, w, h);
    /* scissor box = 相机矩形，整段保持开启（局部清屏 + 相机段裁剪）*/
    p_glEnable(GL_SCISSOR_TEST);
    p_glScissor(x, y, w, h);
    if (clear_flags & SLR_CLEAR_COLOR)
    {
        p_glClearColor(clear[0], clear[1], clear[2], clear[3]);
        p_glClear(GL_COLOR_BUFFER_BIT);
    }
    if (clear_flags & SLR_CLEAR_DEPTH)
    {
        p_glDepthMask(GL_TRUE);
        p_glClear(GL_DEPTH_BUFFER_BIT);
    }
}

static void gl_set_state(int transparent)
{
    if (transparent)
    {
        p_glEnable(GL_BLEND);
        p_glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        p_glEnable(GL_DEPTH_TEST);
        p_glDepthFunc(GL_LESS);
        p_glDepthMask(GL_FALSE);
    }
    else
    {
        p_glDisable(GL_BLEND);
        p_glEnable(GL_DEPTH_TEST);
        p_glDepthFunc(GL_LESS);
        p_glDepthMask(GL_TRUE);
    }
}

static void gl_upload_perdraw(const void* data, int bytes)
{
    p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, s_ubo);
    p_glBufferSubData(GL_UNIFORM_BUFFER, 0, (GLsizeiptr)bytes, data);
    p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

/* 帧级光照块上传（LightBlock，绑定点 1；PFLAT/PTEX 消费）*/
static void gl_upload_lights(const void* data, int bytes)
{
    p_glBindBufferBase(GL_UNIFORM_BUFFER, 1, s_ubo_light);
    p_glBufferSubData(GL_UNIFORM_BUFFER, 0, (GLsizeiptr)bytes, data);
    p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

/* ── 描述符表（纹理名槽表；GLES 采样单元 t1 固定的镜像形态）────────────
 * 绑定与绘制分离，与 DX11 PSSetShaderResources / VK vkCmdBindDescriptorSets
 * 的描述符机制语义对齐（详细注释见 sl_rhi_gl.c 同名段；
 * 槽表声明于静态状态区——free_shared 前向引用）。 */
static int gl_desc_write_tex(int slot, void* tex)
{
    if (slot < 0 || slot >= SLR_DESC_TEX_SLOTS) return 0;
    s_desc_tex[slot] = (GLuint)(intptr_t)tex;
    return 1;
}

static void gl_desc_bind_tex(int slot)
{
    GLuint name = (slot >= 0 && slot < SLR_DESC_TEX_SLOTS) ? s_desc_tex[slot] : 0;
    p_glActiveTexture(GL_TEXTURE1);
    p_glBindTexture(GL_TEXTURE_2D, name);
}

static void gl_draw_item(int prog, int slot, int mesh, int instance_count)
{
    GlMesh* m;
    if (mesh >= 4 + SLR_CUSTOM_MESHES)
    {
        set_error(SLR_E_BAD_PARAM);
        return;
    }
    m = (mesh >= 4) ? &s_custom[mesh - 4] : &s_meshes[mesh];
    if (!m->vao || m->count <= 0)
    {
        set_error_detail(SLR_E_BAD_PARAM, "mesh not uploaded");
        return;
    }
    if (instance_count < 1) instance_count = 1;
    if (slot < 0 || slot + instance_count > 64)
    {
        set_error_detail(SLR_E_BAD_PARAM, "instance slots exceed PerDraw bounds");
        return;
    }
    p_glUseProgram(s_progs[prog]);
    if (prog == SLR_PROG_PFLAT || prog == SLR_PROG_PTEX ||
        prog == SLR_PROG_PHONG_FLAT || prog == SLR_PROG_PHONG_TEX ||
        prog >= SLR_PROG_GEN_BASE)
        p_glUniform1i(s_uni[prog].obj_index, slot);
    /* 纹理已由 desc_bind_tex 绑定到 t1（描述符槽），此处不碰资源 */
    p_glBindVertexArray(m->vao);
    if (instance_count > 1)
        p_glDrawArraysInstanced(GL_TRIANGLES, 0, m->count, instance_count);
    else
        p_glDrawArrays(GL_TRIANGLES, 0, m->count);
    p_glBindVertexArray(0);
}

/* 动态网格上传（三角形列表 pos2+uv2，stride 16B）*/
static int gl_mesh_upload(int slot, const float* verts, int vert_count)
{
    GlMesh* m;
    if (slot < 0 || slot >= SLR_CUSTOM_MESHES || !verts ||
        vert_count <= 0 || vert_count > SLR_CUSTOM_MAX_VERTS)
    {
        set_error(SLR_E_BAD_PARAM);
        return 0;
    }
    m = &s_custom[slot];
    if (!m->vao)
    {
        p_glGenVertexArrays(1, &m->vao);
        p_glGenBuffers(1, &m->vbo);
        p_glBindVertexArray(m->vao);
        p_glBindBuffer(GL_ARRAY_BUFFER, m->vbo);
        p_glEnableVertexAttribArray(0);
        p_glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (const void*)0);
        p_glEnableVertexAttribArray(1);
        p_glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (const void*)8);
        p_glBindVertexArray(0);
    }
    p_glBindBuffer(GL_ARRAY_BUFFER, m->vbo);
    p_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(vert_count * 16), verts, GL_DYNAMIC_DRAW);
    p_glBindBuffer(GL_ARRAY_BUFFER, 0);
    m->count = vert_count;
    return 1;
}

static void gl_post_process(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h,
                            int enabled, float bright, float sat, float vig)
{
    p_glDisable(GL_SCISSOR_TEST);   /* 全屏 pass 不受相机 scissor 限制 */
    p_glDisable(GL_DEPTH_TEST);
    p_glDisable(GL_BLEND);
    p_glBindFramebuffer(GL_FRAMEBUFFER, dst->fbo);
    p_glViewport(0, 0, w, h);
    if (enabled)
    {
        p_glUseProgram(s_progs[SLR_PROG_POST]);
        p_glUniform1f(s_uni[SLR_PROG_POST].bright, bright);
        p_glUniform1f(s_uni[SLR_PROG_POST].sat, sat);
        p_glUniform1f(s_uni[SLR_PROG_POST].vig, vig);
    }
    else
    {
        p_glUseProgram(s_progs[SLR_PROG_BLIT]);
    }
    p_glActiveTexture(GL_TEXTURE0);
    p_glBindTexture(GL_TEXTURE_2D, src->tex);
    p_glBindVertexArray(s_meshes[2].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[2].count);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
}

static void gl_blit(SlrRhiTarget* dst, SlrRhiTarget* src, int w, int h)
{
    p_glDisable(GL_SCISSOR_TEST);
    p_glDisable(GL_DEPTH_TEST);
    p_glDisable(GL_BLEND);
    p_glBindFramebuffer(GL_FRAMEBUFFER, dst->fbo);
    p_glViewport(0, 0, w, h);
    p_glUseProgram(s_progs[SLR_PROG_BLIT]);
    p_glActiveTexture(GL_TEXTURE0);
    p_glBindTexture(GL_TEXTURE_2D, src->tex);
    p_glBindVertexArray(s_meshes[2].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[2].count);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
}

/* 回读 + 行翻 top-down（glReadPixels 产出 bottom-up，原地交换行序）*/
static void gl_readback(SlrRhiTarget* t, int w, int h, int64_t dst_ptr)
{
    unsigned char* buf = (unsigned char*)(intptr_t)dst_ptr;
    int stride = w * 4, rows = h / 2, y;
    unsigned char* tmp;
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    p_glReadPixels(0, 0, w, h, GL_RGBA, 0x1401, buf);
    tmp = (unsigned char*)malloc((size_t)stride);
    if (!tmp) return;
    for (y = 0; y < rows; y++)
    {
        int y2 = h - 1 - y;
        memcpy(tmp, buf + (size_t)y * stride, (size_t)stride);
        memcpy(buf + (size_t)y * stride, buf + (size_t)y2 * stride, (size_t)stride);
        memcpy(buf + (size_t)y2 * stride, tmp, (size_t)stride);
    }
    free(tmp);
    p_glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

/* ===================================================================== */
/* v1 直连 pass（与 GL 后端同构）                                          */
/* ===================================================================== */
static void gl_v1_clear(SlrRhiTarget* t, int w, int h, const float* clear)
{
    p_glDisable(GL_SCISSOR_TEST);
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    p_glClearColor(clear[0], clear[1], clear[2], clear[3]);
    p_glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

static void gl_v1_draw(SlrRhiTarget* t, int w, int h,
                       int prog, const float* mvp, const float* color, void* tex)
{
    p_glDisable(GL_SCISSOR_TEST);
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    p_glDisable(GL_BLEND);
    p_glDisable(GL_DEPTH_TEST);
    p_glDepthMask(GL_TRUE);
    p_glUseProgram(s_progs[prog]);
    if (prog == SLR_PROG_FLAT || prog == SLR_PROG_TEX)
    {
        p_glUniformMatrix4fv(s_uni[prog].mvp, 1, GL_FALSE, mvp);
        p_glUniform4f(s_uni[prog].color, color[0], color[1], color[2], color[3]);
    }
    if (tex)
    {
        p_glActiveTexture(GL_TEXTURE1);
        p_glBindTexture(GL_TEXTURE_2D, (GLuint)(intptr_t)tex);
    }
    p_glBindVertexArray(s_meshes[3].vao);
    p_glDrawArrays(GL_TRIANGLES, 0, s_meshes[3].count);
    p_glBindVertexArray(0);
    p_glUseProgram(0);
}

/* ===================================================================== */
/* EGL 初始化 / GLES 符号解析                                              */
/* ===================================================================== */
static FARPROC resolve_gles(const char* name)
{
    FARPROC f = NULL;
    if (p_eglGetProcAddress)
    {
        f = (FARPROC)p_eglGetProcAddress(name);
        /* eglGetProcAddress 约定只失败返回 NULL，防御异常值 */
        if (f == (FARPROC)1 || f == (FARPROC)2 || f == (FARPROC)3 ||
            f == (FARPROC)(intptr_t)-1)
            f = NULL;
    }
    if (!f && s_hgles)
        f = GetProcAddress(s_hgles, name);
    return f;
}

static int load_all_gles_procs(void)
{
    int missing = 0;
#define LOAD_GL(name) \
    do { \
        p_##name = (PFN_##name)resolve_gles(#name); \
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
    LOAD_GL(glDrawArraysInstanced);
    /* N2a shadow map（glClearDepth 是 GL 的 GLdouble 版，ES 无符号不加载；
     * ES 侧深度清屏走本地声明的 glClearDepthf）*/
    LOAD_GL(glColorMask);
    LOAD_GL(glDrawBuffers);
#undef LOAD_GL
    p_glClearDepthfES = (PFN_glClearDepthfES)resolve_gles("glClearDepthf");
    if (missing)
    {
        set_error_detail(SLR_E_GL_SYMBOL, "GLES 3.0 core symbol missing");
        return 0;
    }
    return 1;
}

static int gl_init(void)
{
    EGLint major = 0, minor = 0;
    EGLConfig cfg = NULL;
    EGLint ncfg = 0;
    const char* exts;
    int guard;

    /* 1) libEGL.dll（探测失败 = 环境无 GLES -> 优雅降级）*/
    s_hegl = LoadLibraryA("libEGL.dll");
    if (!s_hegl) s_hegl = LoadLibraryA("egl.dll");
    if (!s_hegl)
    {
        set_error_detail(SLR_E_BACKEND, "libEGL.dll load failed (no GLES runtime)");
        return 0;
    }
    p_eglGetDisplay           = (PFN_eglGetDisplay)GetProcAddress(s_hegl, "eglGetDisplay");
    p_eglInitialize           = (PFN_eglInitialize)GetProcAddress(s_hegl, "eglInitialize");
    p_eglBindAPI              = (PFN_eglBindAPI)GetProcAddress(s_hegl, "eglBindAPI");
    p_eglChooseConfig         = (PFN_eglChooseConfig)GetProcAddress(s_hegl, "eglChooseConfig");
    p_eglCreateContext        = (PFN_eglCreateContext)GetProcAddress(s_hegl, "eglCreateContext");
    p_eglCreatePbufferSurface = (PFN_eglCreatePbufferSurface)GetProcAddress(s_hegl, "eglCreatePbufferSurface");
    p_eglMakeCurrent          = (PFN_eglMakeCurrent)GetProcAddress(s_hegl, "eglMakeCurrent");
    p_eglDestroyContext       = (PFN_eglDestroyContext)GetProcAddress(s_hegl, "eglDestroyContext");
    p_eglDestroySurface       = (PFN_eglDestroySurface)GetProcAddress(s_hegl, "eglDestroySurface");
    p_eglTerminate            = (PFN_eglTerminate)GetProcAddress(s_hegl, "eglTerminate");
    p_eglGetProcAddress       = (PFN_eglGetProcAddress)GetProcAddress(s_hegl, "eglGetProcAddress");
    p_eglGetError             = (PFN_eglGetError)GetProcAddress(s_hegl, "eglGetError");
    p_eglQueryString          = (PFN_eglQueryString)GetProcAddress(s_hegl, "eglQueryString");
    if (!p_eglGetDisplay || !p_eglInitialize || !p_eglCreateContext ||
        !p_eglMakeCurrent || !p_eglGetProcAddress || !p_eglBindAPI ||
        !p_eglChooseConfig || !p_eglDestroyContext || !p_eglTerminate)
    {
        set_error_detail(SLR_E_BACKEND, "libEGL.dll entry points missing");
        return 0;
    }

    /* libGLESv2.dll（eglGetProcAddress 可解析核心函数，但直出回退更稳）*/
    s_hgles = LoadLibraryA("libGLESv2.dll");
    if (!s_hgles) s_hgles = LoadLibraryA("libGLESv2.dll");
    /* 缺失不致命：eglGetProcAddress 仍可能解析到全部核心函数 */

    /* 2) display + initialize */
    s_dpy = p_eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (!s_dpy)
    {
        set_error_detail(SLR_E_BACKEND, "eglGetDisplay(EGL_DEFAULT_DISPLAY) failed");
        return 0;
    }
    if (!p_eglInitialize(s_dpy, &major, &minor))
    {
        set_error_detail(SLR_E_BACKEND, "eglInitialize failed (no EGL device)");
        return 0;
    }

    /* 3) ES 绑定 + 选配置（pbuffer 兼容，全用离屏 FBO）*/
    p_eglBindAPI(EGL_OPENGL_ES_API);
    {
        EGLint attribs[16];
        int i = 0;
        attribs[i++] = EGL_RED_SIZE;   attribs[i++] = 8;
        attribs[i++] = EGL_GREEN_SIZE; attribs[i++] = 8;
        attribs[i++] = EGL_BLUE_SIZE;  attribs[i++] = 8;
        attribs[i++] = EGL_ALPHA_SIZE; attribs[i++] = 8;
        attribs[i++] = EGL_DEPTH_SIZE; attribs[i++] = 24;
        attribs[i++] = EGL_SURFACE_TYPE; attribs[i++] = EGL_PBUFFER_BIT;
        attribs[i++] = EGL_RENDERABLE_TYPE; attribs[i++] = EGL_OPENGL_ES3_BIT;
        attribs[i++] = EGL_NONE;
        if (!p_eglChooseConfig(s_dpy, attribs, &cfg, 1, &ncfg) || ncfg < 1)
        {
            set_error_detail(SLR_E_BACKEND, "eglChooseConfig found no GLES3 config");
            return 0;
        }
    }

    /* 4) ES 3.0 上下文 */
    {
        EGLint cattribs[3];
        cattribs[0] = EGL_CONTEXT_CLIENT_VERSION;
        cattribs[1] = 3;
        cattribs[2] = EGL_NONE;
        s_ctx = p_eglCreateContext(s_dpy, cfg, EGL_NO_CONTEXT, cattribs);
        if (!s_ctx)
        {
            set_error_detail(SLR_E_CONTEXT, "eglCreateContext(GLES3) failed");
            return 0;
        }
    }

    /* 5) 绑定：优先无表面（EGL_KHR_surfaceless_context），回退 1x1 pbuffer */
    exts = p_eglQueryString ? p_eglQueryString(s_dpy, EGL_EXTENSIONS) : NULL;
    if (exts && strstr(exts, "EGL_KHR_surfaceless_context"))
    {
        if (p_eglMakeCurrent(s_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, s_ctx))
            goto bound;
    }
    {
        EGLint pattribs[5];
        pattribs[0] = EGL_WIDTH;  pattribs[1] = 1;
        pattribs[2] = EGL_HEIGHT; pattribs[3] = 1;
        pattribs[4] = EGL_NONE;
        s_surf = p_eglCreatePbufferSurface(s_dpy, cfg, pattribs);
        if (!s_surf || !p_eglMakeCurrent(s_dpy, s_surf, s_surf, s_ctx))
        {
            set_error_detail(SLR_E_CONTEXT_CURRENT, "eglMakeCurrent failed (surfaceless unsupported)");
            return 0;
        }
    }
bound:
    /* 6) GLES 符号解析 */
    if (!load_all_gles_procs()) return 0;

    /* 7) 冲刷粘性错误 + 像素对齐 */
    guard = 0;
    while (p_glGetError() != GL_NO_ERROR && guard++ < 32) {}
    p_glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    p_glPixelStorei(GL_PACK_ALIGNMENT, 1);

    if (!s_lock_init)
    {
        InitializeCriticalSection(&s_lock);
        s_lock_init = 1;
    }
    return 1;
}

static void gl_shutdown(void)
{
    if (s_ctx || s_surf)
    {
        if (p_eglMakeCurrent)
            p_eglMakeCurrent(s_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (s_surf && p_eglDestroySurface) { p_eglDestroySurface(s_dpy, s_surf); s_surf = NULL; }
    if (s_ctx && p_eglDestroyContext) { p_eglDestroyContext(s_dpy, s_ctx); s_ctx = NULL; }
    if (s_dpy && p_eglTerminate) { p_eglTerminate(s_dpy); s_dpy = NULL; }
    if (s_hgles) { FreeLibrary(s_hgles); s_hgles = NULL; }
    if (s_hegl) { FreeLibrary(s_hegl); s_hegl = NULL; }
    p_eglGetDisplay = NULL; p_eglInitialize = NULL; p_eglBindAPI = NULL;
    p_eglChooseConfig = NULL; p_eglCreateContext = NULL;
    p_eglCreatePbufferSurface = NULL; p_eglMakeCurrent = NULL;
    p_eglDestroyContext = NULL; p_eglDestroySurface = NULL;
    p_eglTerminate = NULL; p_eglGetProcAddress = NULL;
    p_eglGetError = NULL; p_eglQueryString = NULL;
    if (s_lock_init) { DeleteCriticalSection(&s_lock); s_lock_init = 0; }
}

static void gl_info(char* renderer, int rcap, char* version, int vcap)
{
    const char* s = (const char*)p_glGetString(GL_RENDERER);
    _snprintf(renderer, (size_t)rcap - 1, "%s", (s && s[0]) ? s : "unknown");
    renderer[rcap - 1] = 0;
    s = (const char*)p_glGetString(GL_VERSION);
    _snprintf(version, (size_t)vcap - 1, "%s", (s && s[0]) ? s : "unknown");
    version[vcap - 1] = 0;
}

static int gl_enter(void)
{
    EnterCriticalSection(&s_lock);
    /* 上下文已在线程绑定（init 时 MakeCurrent）；EGL 重复绑定幂等，
     * 但 surfaceless 模式下重复 MakeCurrent 某些驱动报 BAD_SURFACE——
     * 仅当未绑定时绑定：eglGetCurrentContext 检查。*/
    if (!s_ctx)
    {
        LeaveCriticalSection(&s_lock);
        set_error(SLR_E_CONTEXT_CURRENT);
        return 0;
    }
    return 1;
}

static void gl_exit(void) { LeaveCriticalSection(&s_lock); }

/* ===================================================================== */
/* vtable                                                                 */
/* ===================================================================== */
static const SlrRhi s_rhi_gles =
{
    "gles",
    gl_init,
    gl_shutdown,
    gl_info,
    gl_enter,
    gl_exit,
    gl_make_shared,
    gl_free_shared,
    gl_target_create,
    gl_target_destroy,
    gl_texture_create,
    gl_texture_destroy,
    gl_mesh_upload,
    gl_begin_scene,
    gl_camera_begin,
    gl_set_state,
    gl_upload_perdraw,
    gl_draw_item,
    gl_post_process,
    gl_blit,
    gl_readback,
    gl_v1_clear,
    gl_v1_draw,
    gl_desc_write_tex,
    gl_desc_bind_tex,
    gl_upload_lights,
    /* N2a shadow map（深度专用目标）*/
    gl_shadow_target_create,
    gl_shadow_target_destroy,
    gl_shadow_begin,
    gl_shadow_bind_depth,
};

const SlrRhi* slr_rhi_gles(void) { return &s_rhi_gles; }
