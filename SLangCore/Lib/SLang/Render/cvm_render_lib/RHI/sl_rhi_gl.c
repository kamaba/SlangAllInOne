/* =========================================================================
 * sl_rhi_gl.c —— RHI 后端：Windows WGL + OpenGL 3.3 core
 *
 * 原 sl_render.c 的全部 GL/WGL 逻辑迁入本文件：
 *   - opengl32.dll 双通道运行期解析（wglGetProcAddress / GetProcAddress，
 *     零 SDK 头与 .lib 依赖）；
 *   - 隐藏窗口 + WGL 3.3 core 上下文（离屏渲染，仅借用窗口做上下文锚点）；
 *   - 6 组 GLSL 着色器程序 / 4 张静态网格 / PerDraw UBO（进程级共享）；
 *   - FBO 渲染目标、纹理、管线 pass、v1 直连 pass、回读行翻。
 *
 * 上层经 sl_rhi.h 的 vtable 调用；错误经 sl_render.c 的
 * set_error / set_error_detail 上抛（共享 s_ready / s_perdraw）。
 * ========================================================================= */
#include "sl_render_internal.h"   /* vm_sl_render.h + RHI/sl_rhi.h + 共享结构 */
#include "sl_rhi_shaders_gen.h"   /* v3.5 固化着色器（GLSL330 + ESSL300 + DXBC blob）*/

/* 固化头槽位一致性编译期检查：枚举 gen 段长度必须正好覆盖 SLR_GEN_SETS
 * 全表（不匹配 = 枚举与固化头版本脱节，编译期即爆）*/
typedef char slr_gen_slot_check[
    (SLR_GEN_EFFECT_COUNT * 2 == SLR_PROG_COUNT - SLR_PROG_GEN_BASE) ? 1 : -1];

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

/* ---- GL 函数指针：两遍展开（先 typedef 后定义）---- */
#define GLDECL(name, ret, params) typedef ret (APIENTRY *PFN_##name) params;
#include "RHI/sl_gl_procs.h"
#undef GLDECL
#define GLDECL(name, ret, params) PFN_##name p_##name = NULL;
#include "RHI/sl_gl_procs.h"
#undef GLDECL

/* ===================================================================== */
/* 后端私有状态                                                           */
/* ===================================================================== */
struct SlrRhiTarget            /* GL 渲染目标 = FBO + 颜色纹理 + 可选深度 RB */
{
    int w, h;
    GLuint fbo, tex, rb;
};

typedef struct { int mvp, color, tex; int obj_index; int src, bright, sat, vig; } GlProgUni;
typedef struct { GLuint vao, vbo; int count; } GlMesh;

static GLuint       s_progs[SLR_PROG_COUNT];
static GlProgUni  s_uni[SLR_PROG_COUNT];
static GLuint       s_ubo = 0;
static GLuint       s_ubo_light = 0;   /* LightBlock UBO（绑定点 1）*/
static GlMesh      s_meshes[4];
static GlMesh      s_custom[SLR_CUSTOM_MESHES];   /* 动态网格（mesh id = 4+slot）*/
static GLuint       s_desc_tex[SLR_DESC_TEX_SLOTS];   /* 描述符槽表（free_shared 前向引用）*/

static HMODULE  s_hgl = NULL;
static HWND     s_hwnd = NULL;
static HDC      s_hdc = NULL;
static HGLRC    s_hrc = NULL;
static CRITICAL_SECTION s_lock;
static int      s_lock_init = 0;

/* ---- WGL 符号（opengl32.dll 直导出）---- */
typedef HGLRC (WINAPI *PFN_wglCreateContext)(HDC);
typedef BOOL  (WINAPI *PFN_wglMakeCurrent)(HDC, HGLRC);
typedef BOOL  (WINAPI *PFN_wglDeleteContext)(HGLRC);
typedef HGLRC (WINAPI *PFN_wglCreateContextAttribsARB)(HDC, HGLRC, const int*);
typedef PROC  (WINAPI *PFN_wglGetProcAddress)(LPCSTR);

static PFN_wglCreateContext           pwglCreateContext;
static PFN_wglMakeCurrent             pwglMakeCurrent;
static PFN_wglDeleteContext           pwglDeleteContext;
static PFN_wglCreateContextAttribsARB pwglCreateContextAttribsARB;
static PFN_wglGetProcAddress          pwglGetProcAddress;

/* ===================================================================== */
/* 着色器（GLSL 330 core，与 D3D11/VK 后端逐组对应）                       */
/* ===================================================================== */
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
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "uniform int uObjIndex;\n"
    "out vec2 vUv;\n"
    "out vec2 vWorld;\n"
    "out vec2 vNrm;\n"
    "void main(){\n"
    "  vUv = aUv;\n"
    "  int k = uObjIndex * 2;\n"
    "  vWorld = vec2(dot(aPos, uWMat[k].xy), dot(aPos, uWMat[k].zw)) + uWMat[k + 1].xy;\n"
    "  vNrm = uWMat[k + 1].zw;\n"
    "  gl_Position = uMVP[uObjIndex] * vec4(aPos, 0.0, 1.0); }\n";

/* 管线片元光照（GL/GLES/D3D11 三方公式逐字一致，跨后端同效果）：
 * 光 = 环境光 + 平行光(ndl 按物体朝向) + 聚光(锥角平滑 + 距离平方衰减)。
 * 默认态（无光源 + ambient=1）输出 = albedo * 1.0，与旧版逐字节一致。 */
static const char* FS_PFLAT =
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "uniform int uObjIndex;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[uObjIndex];\n"
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
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "uniform int uObjIndex;\n"
    "uniform sampler2D uTex;\n"
    "in vec2 vUv;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[uObjIndex] * texture(uTex, vUv);\n"
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

/* v3.4 Phong 光照模型（GL/GLES/D3D11 三方公式逐字一致）：
 * v3.3 光照 + 伪 3D 高光 —— N = normalize(vec3(vNrm, 0.75))，
 * V = (0,0,1)，R = reflect(-L, N)，spec = pow(max(dot(R,V),0), shin) * strength。
 * 直射光 L = normalize(vec3(uDirDir.xy, 0.6))；聚光 L 沿 -toF + 0.6 高度分量，
 * 高光随锥角/距离衰减。sp = uSpec[uObjIndex].xy（x=强度 y=光泽度）。 */
static const char* FS_PHONG_FLAT =
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "uniform int uObjIndex;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[uObjIndex];\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  vec3 N = normalize(vec3(vNrm, 0.75));\n"
    "  vec3 V = vec3(0.0, 0.0, 1.0);\n"
    "  vec2 sp = uSpec[uObjIndex].xy;\n"
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
    "#version 330 core\n"
    "layout(std140) uniform PerDraw { mat4 uMVP[64]; vec4 uColor[64]; vec4 uWMat[128]; vec4 uSpec[64]; };\n"
    "layout(std140) uniform LightBlock {\n"
    "  vec4 uAmbient; vec4 uDirColor; vec4 uDirDir;\n"
    "  vec4 uSpotColor; vec4 uSpotPosRange; vec4 uSpotDirCos; };\n"
    "uniform int uObjIndex;\n"
    "uniform sampler2D uTex;\n"
    "in vec2 vUv;\n"
    "in vec2 vWorld;\n"
    "in vec2 vNrm;\n"
    "out vec4 oCol;\n"
    "void main(){\n"
    "  vec4 base = uColor[uObjIndex] * texture(uTex, vUv);\n"
    "  vec3 light = vec3(uAmbient.x);\n"
    "  vec3 N = normalize(vec3(vNrm, 0.75));\n"
    "  vec3 V = vec3(0.0, 0.0, 1.0);\n"
    "  vec2 sp = uSpec[uObjIndex].xy;\n"
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

    /* v3.5 固化效果槽：5 效果 × 2 变体（固化 GLSL 3.3 源运行期编译，
     * 与内建程序同一 make_program 路径——编译/链接失败同样致命）*/
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
    {
        const SlrGenShaderSet* gs = &SLR_GEN_SETS[i];
        if (!make_program(SLR_PROG_GEN_BASE + i, gs->glsl_vs, gs->glsl_fs)) return 0;
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

    /* v3.5 gen：全槽位取 uObjIndex；TEX 变体（偶数下标）取 uTex */
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
    {
        int gslot = SLR_PROG_GEN_BASE + i;
        s_uni[gslot].obj_index = p_glGetUniformLocation(s_progs[gslot], "uObjIndex");
        if (!(i & 1))
            s_uni[gslot].tex = p_glGetUniformLocation(s_progs[gslot], "uTex");
    }

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
    p_glUseProgram(s_progs[SLR_PROG_PHONG_TEX]);
    p_glUniform1i(s_uni[SLR_PROG_PHONG_TEX].tex, 1);
    for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i += 2)
    {
        p_glUseProgram(s_progs[SLR_PROG_GEN_BASE + i]);
        p_glUniform1i(s_uni[SLR_PROG_GEN_BASE + i].tex, 1);
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
        for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
        {
            blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_GEN_BASE + i], "PerDraw");
            if (blk != 0xFFFFFFFFu)
                p_glUniformBlockBinding(s_progs[SLR_PROG_GEN_BASE + i], blk, 0);
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
        for (i = 0; i < SLR_GEN_EFFECT_COUNT * 2; i++)
        {
            blk = p_glGetUniformBlockIndex(s_progs[SLR_PROG_GEN_BASE + i], "LightBlock");
            if (blk != 0xFFFFFFFFu)
                p_glUniformBlockBinding(s_progs[SLR_PROG_GEN_BASE + i], blk, 1);
        }
        p_glGenBuffers(1, &s_ubo_light);
        p_glBindBuffer(GL_UNIFORM_BUFFER, s_ubo_light);
        p_glBufferData(GL_UNIFORM_BUFFER, (GLsizeiptr)sizeof(SlrLightBlock), NULL, GL_DYNAMIC_DRAW);
        p_glBindBufferBase(GL_UNIFORM_BUFFER, 1, s_ubo_light);
        p_glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }

    /* 静态网格（pos2 + uv2，stride 16B）*/
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
/* 渲染目标 / 纹理                                                         */
/* ===================================================================== */
static SlrRhiTarget* gl_target_create(int w, int h, int with_depth)
{
    SlrRhiTarget* t = (SlrRhiTarget*)malloc(sizeof(SlrRhiTarget));
    GLenum st;
    if (!t) { set_error(SLR_E_MEMORY); return NULL; }
    t->w = w; t->h = h; t->fbo = 0; t->tex = 0; t->rb = 0;
    p_glGenFramebuffers(1, &t->fbo);
    p_glGenTextures(1, &t->tex);
    p_glBindTexture(GL_TEXTURE_2D, t->tex);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
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
        p_glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
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
    free(t);
}

/* rgba 首行 = 图像底部（sl_texture.c 已统一翻转），GL 原样入显存 */
static void* gl_texture_create(int w, int h, const unsigned char* rgba)
{
    GLuint t = 0;
    p_glGenTextures(1, &t);
    p_glBindTexture(GL_TEXTURE_2D, t);
    p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
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
/* 管线 pass                                                              */
/* ===================================================================== */
static void gl_begin_scene(SlrRhiTarget* t, int w, int h, const float* clear)
{
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(0, 0, w, h);
    /* DepthMask 必须先于清屏打开：glClear(DEPTH) 受深度写掩码限制，
     * 上一帧透明段（DepthMask=FALSE）会屏蔽本帧的深度清屏 */
    p_glDepthMask(GL_TRUE);
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
    (void)target_h;   /* GL 视口原点即左下，无需换算 */
    p_glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
    p_glViewport(x, y, w, h);
    /* scissor box = 相机矩形，整段保持开启：
     *   1) 局部清屏靠它（glClear 只受 scissor 限制）；
     *   2) 相机段绘制也裁剪到相机视口——与 D3D11 的 viewport 裁剪
     *      语义对齐（跨后端同效果的必要条件）。 */
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

/* ── 描述符表（纹理名槽表；GL 采样单元 t1 固定的镜像形态）─────────────
 * desc_write_tex 写槽（管线层帧级填充），desc_bind_tex 绑定到采样单元
 * t1——绑定与绘制分离，与 DX11 PSSetShaderResources / VK
 * vkCmdBindDescriptorSets 的描述符机制语义对齐。
 * 槽表声明于静态状态区（free_shared 前向引用）。 */
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

static void gl_draw_item(int prog, int slot, int mesh)
{
    /* 程序绑定是本 pass 的职责（管线层只发 prog 槽位；
     * uniform 设置作用于当前绑定的程序，必须先 UseProgram）*/
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
    p_glUseProgram(s_progs[prog]);
    if (prog == SLR_PROG_PFLAT || prog == SLR_PROG_PTEX ||
        prog == SLR_PROG_PHONG_FLAT || prog == SLR_PROG_PHONG_TEX ||
        prog >= SLR_PROG_GEN_BASE)
        p_glUniform1i(s_uni[prog].obj_index, slot);
    /* 纹理已由 desc_bind_tex 绑定到 t1（描述符槽），此处不碰资源 */
    p_glBindVertexArray(m->vao);
    p_glDrawArrays(GL_TRIANGLES, 0, m->count);
    p_glBindVertexArray(0);
}

/* 动态网格上传（三角形列表 pos2+uv2，stride 16B）：首传建 VAO/VBO，
 * 之后 glBufferData 整块重传（DYNAMIC_DRAW） */
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
    p_glDisable(GL_SCISSOR_TEST);   /* 全屏 pass 不受相机 scissor 限制 */
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
    p_glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
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
/* v1 直连 pass                                                           */
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
    /* v1 直连为确定性行为：显式关混合/深度（与 D3D11 默认状态一致）*/
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
/* WGL 初始化 / 符号解析                                                   */
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

static int gl_init(void)
{
    WNDCLASSA wc;
    PIXELFORMATDESCRIPTOR pfd;
    int pf;
    HGLRC dummy;
    int attribs[9];
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

    /* 4) 传统上下文 → 取 ARB 扩展符号 → 3.3 core */
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

    if (!s_lock_init)
    {
        InitializeCriticalSection(&s_lock);
        s_lock_init = 1;
    }
    return 1;
}

static void gl_shutdown(void)
{
    if (pwglMakeCurrent && s_hdc) pwglMakeCurrent(NULL, NULL);
    if (s_hrc && pwglDeleteContext) { pwglDeleteContext(s_hrc); s_hrc = NULL; }
    if (s_hwnd)
    {
        if (s_hdc) { ReleaseDC(s_hwnd, s_hdc); s_hdc = NULL; }
        DestroyWindow(s_hwnd);
        s_hwnd = NULL;
    }
    if (s_hgl) { FreeLibrary(s_hgl); s_hgl = NULL; }
    pwglCreateContext = NULL;
    pwglMakeCurrent = NULL;
    pwglDeleteContext = NULL;
    pwglCreateContextAttribsARB = NULL;
    pwglGetProcAddress = NULL;
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
    if (!pwglMakeCurrent(s_hdc, s_hrc))
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
static const SlrRhi s_rhi_gl =
{
    "gl",
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
};

const SlrRhi* slr_rhi_gl(void) { return &s_rhi_gl; }
