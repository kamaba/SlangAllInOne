/* =========================================================================
 * sl_render.c —— SLangRender 原生渲染库核心（对应 SL 侧 Render.sl）
 *
 * 职责（渲染中间层的"调度层"，平台无关）：
 *   - RHI 后端注册表：slr_init 默认 gl（向后兼容），slr_init_backend
 *     可选 d3d11 / vk / gles；slr_backend_list 列出可用后端；
 *   - 错误处理（粘性）与诊断导出；
 *   - v1 直连层：RenderContext（渲染目标 清屏/三角/回读，经 RHI）；
 *   - 资源全局表回收（管线目标 / 纹理 / v1 ctx，经 RHI）。
 *
 * 渲染逻辑全部在：
 *   Pipeline/sl_pipeline.c <-> Pipeline/UnityPipeline.sl（13 阶段管线）
 *   Pipeline/sl_object.c   <-> UnityRenderObject
 *   Pipeline/sl_texture.c  <-> UnityRenderTexture
 *   Pipeline/sl_camera.c   <-> UnityRenderCamera
 *   RHI/sl_rhi_*.c         <-> 平台驱动后端（GL / D3D11 / VK / GLES）
 * ========================================================================= */
#include "sl_render_internal.h"

/* ===================================================================== */
/* 全局状态                                                               */
/* ===================================================================== */
int         s_ready = 0;
SlrPerDraw s_perdraw;

static int  s_last_error = SLR_OK;
static char s_err_detail[256] = { 0 };
static char s_renderer_str[160] = "unknown";
static char s_version_str[160] = "unknown";
static char s_backend_str[32] = "none";

/* v1 RenderContext 表（slr_uninit 回收时访问，先于使用定义）*/
typedef struct
{
    int used, w, h;
    SlrRhiTarget* rt;
    int64_t frame_count;
} SlrCtx;
static SlrCtx s_ctxs[SLR_MAX_CTX];

/* ===================================================================== */
/* 错误处理（粘性）                                                       */
/* ===================================================================== */
void set_error(int e) { s_last_error = e; }

void set_error_detail(int e, const char* detail)
{
    s_last_error = e;
    if (detail) { _snprintf(s_err_detail, sizeof(s_err_detail) - 1, "%s", detail); s_err_detail[sizeof(s_err_detail) - 1] = 0; }
    else { s_err_detail[0] = 0; }
}

void clear_error(void)
{
    s_last_error = SLR_OK;
    s_err_detail[0] = 0;
}

/* ===================================================================== */
/* RHI 进出（外层统一：清错误 + s_ready 检查 + 后端锁/上下文）              */
/* ===================================================================== */
int rhi_enter(void)
{
    clear_error();
    if (!s_ready || !g_rhi) { set_error(SLR_E_NOT_INITIALIZED); return 0; }
    if (!g_rhi->enter()) return 0;
    return 1;
}

void rhi_exit(void)
{
    if (g_rhi) g_rhi->exit();
}

/* ===================================================================== */
/* 数学辅助（v1 直连层使用；管线侧矩阵见 Pipeline/sl_pipeline.c）           */
/* ===================================================================== */
static void mat4_identity(float* m)
{
    int i;
    for (i = 0; i < 16; i++) m[i] = 0.0f;
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

/* ===================================================================== */
/* RHI 后端注册表                                                          */
/* ===================================================================== */
typedef struct
{
    const char* name;
    const SlrRhi* (*get)(void);
} SlrBackendEntry;

/* 全部后端静态注册（初始化失败 = 当前环境不可用，init 返回 0 降级）*/
static const SlrBackendEntry s_backends[] =
{
    { "gl",    slr_rhi_gl    },
    { "d3d11", slr_rhi_d3d11 },
    { "vk",    slr_rhi_vk    },
    { "gles",  slr_rhi_gles  },
};

#define SLR_BACKEND_COUNT (sizeof(s_backends) / sizeof(s_backends[0]))

const SlrRhi* g_rhi = NULL;

static const SlrBackendEntry* backend_find(const char* name)
{
    size_t i;
    if (!name || !name[0]) return NULL;
    for (i = 0; i < SLR_BACKEND_COUNT; i++)
        if (strcmp(s_backends[i].name, name) == 0) return &s_backends[i];
    return NULL;
}

/* 统一初始化路径：设备就绪 -> 共享资源 -> 状态置位 */
static int backend_startup(const SlrBackendEntry* e)
{
    if (!e->get())
    {
        set_error_detail(SLR_E_BACKEND, "backend unavailable in this environment");
        return 0;
    }
    g_rhi = e->get();
    if (!g_rhi->init()) return 0;
    if (!g_rhi->make_shared())
    {
        g_rhi->shutdown();
        g_rhi = NULL;
        return 0;   /* 着色器/网格/常量缓冲就绪失败，保持未初始化态 */
    }
    g_rhi->info(s_renderer_str, (int)sizeof(s_renderer_str),
                s_version_str, (int)sizeof(s_version_str));
    _snprintf(s_backend_str, sizeof(s_backend_str) - 1, "%s", e->name);
    s_backend_str[sizeof(s_backend_str) - 1] = 0;
    s_ready = 1;
    return 1;
}

/* ===================================================================== */
/* 初始化 / 反初始化 / 后端选择                                            */
/* ===================================================================== */
int slr_init(void)
{
    s_last_error = SLR_OK;
    if (s_ready) return 1;
    /* 默认后端 = gl（v1/v2 向后兼容）*/
    return backend_startup(&s_backends[0]);
}

int slr_init_backend(const char* backend_utf8)
{
    const SlrBackendEntry* e;
    s_last_error = SLR_OK;
    e = backend_find(backend_utf8);
    if (!e)
    {
        set_error_detail(SLR_E_BACKEND, "unknown backend name (see slr_backend_list)");
        return 0;
    }
    if (s_ready)
    {
        if (strcmp(s_backend_str, e->name) == 0) return 1;   /* 已是该后端 */
        if (!slr_uninit()) return 0;
    }
    return backend_startup(e);
}

int slr_uninit(void)
{
    int i;
    s_last_error = SLR_OK;
    if (!s_ready) return 1;
    if (g_rhi && g_rhi->enter())
    {
        /* 管线 / 纹理 / v1 ctx 资源回收（经 RHI）*/
        for (i = 0; i < SLR_MAX_PIPES; i++)
            if (s_pipes[i].used) pipeline_release_targets(&s_pipes[i]);
        memset(s_pipes, 0, sizeof(s_pipes));
        for (i = 0; i < SLR_MAX_TEX; i++)
            if (s_textures[i].used && s_textures[i].rhi_tex)
                g_rhi->texture_destroy(s_textures[i].rhi_tex);
        memset(s_textures, 0, sizeof(s_textures));
        for (i = 0; i < SLR_MAX_CTX; i++)
            if (s_ctxs[i].used && s_ctxs[i].rt)
                g_rhi->target_destroy(s_ctxs[i].rt);
        memset(s_ctxs, 0, sizeof(s_ctxs));
        g_rhi->free_shared();
        g_rhi->exit();
    }
    if (g_rhi) g_rhi->shutdown();
    g_rhi = NULL;
    s_ready = 0;
    _snprintf(s_renderer_str, sizeof(s_renderer_str) - 1, "%s", "unknown");
    _snprintf(s_version_str, sizeof(s_version_str) - 1, "%s", "unknown");
    _snprintf(s_backend_str, sizeof(s_backend_str) - 1, "%s", "none");
    return 1;
}

const char* slr_backend_list(void)
{
    static char list[64];
    size_t i;
    size_t off = 0;
    list[0] = 0;
    for (i = 0; i < SLR_BACKEND_COUNT; i++)
    {
        size_t len = strlen(s_backends[i].name);
        if (off + len + 2 >= sizeof(list)) break;
        if (off) list[off++] = ',';
        memcpy(list + off, s_backends[i].name, len);
        off += len;
        list[off] = 0;
    }
    return list;
}

/* ===================================================================== */
/* v1：RenderContext（直连渲染目标，对应 Render.sl 的 RenderContext 门面）  */
/* ===================================================================== */

static SlrCtx* ctx_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_CTX || !s_ctxs[i].used) return NULL;
    return &s_ctxs[i];
}

int64_t slr_context_create(int w, int h)
{
    int i;
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!rhi_enter()) return 0;
    for (i = 0; i < SLR_MAX_CTX; i++)
    {
        if (!s_ctxs[i].used)
        {
            SlrRhiTarget* rt = g_rhi->target_create(w, h, 1);
            if (!rt) { rhi_exit(); return 0; }
            memset(&s_ctxs[i], 0, sizeof(SlrCtx));
            s_ctxs[i].used = 1; s_ctxs[i].w = w; s_ctxs[i].h = h;
            s_ctxs[i].rt = rt;
            rhi_exit();
            return (int64_t)(i + 1);
        }
    }
    set_error(SLR_E_LIMIT);
    rhi_exit();
    return 0;
}

int slr_context_destroy(int64_t ctx)
{
    SlrCtx* c;
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    g_rhi->target_destroy(c->rt);
    memset(c, 0, sizeof(SlrCtx));
    rhi_exit();
    return 1;
}

int slr_context_resize(int64_t ctx, int w, int h)
{
    SlrCtx* c;
    SlrRhiTarget* rt;
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    rt = g_rhi->target_create(w, h, 1);
    if (!rt) { rhi_exit(); return 0; }
    g_rhi->target_destroy(c->rt);
    c->rt = rt; c->w = w; c->h = h;
    rhi_exit();
    return 1;
}

int slr_context_width(int64_t ctx)
{
    SlrCtx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->w;
}

int slr_context_height(int64_t ctx)
{
    SlrCtx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->h;
}

int64_t slr_frame_count(int64_t ctx)
{
    SlrCtx* c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return c->frame_count;
}

int slr_clear(int64_t ctx, float r, float g, float b, float a)
{
    SlrCtx* c;
    float clear[4];
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    clear[0] = r; clear[1] = g; clear[2] = b; clear[3] = a;
    g_rhi->v1_clear(c->rt, c->w, c->h, clear);
    rhi_exit();
    return 1;
}

int slr_draw_triangle(int64_t ctx, float r, float g, float b)
{
    SlrCtx* c;
    float ident[16], color[4];
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    mat4_identity(ident);
    color[0] = r; color[1] = g; color[2] = b; color[3] = 1.0f;
    g_rhi->v1_draw(c->rt, c->w, c->h, SLR_PROG_FLAT, ident, color, NULL);
    rhi_exit();
    return 1;
}

int slr_read_pixels(int64_t ctx, int64_t dst_ptr)
{
    SlrCtx* c;
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    g_rhi->readback(c->rt, c->w, c->h, dst_ptr);
    rhi_exit();
    return 1;
}

int slr_render_frame(int64_t ctx, float r, float g, float b, int64_t dst_ptr)
{
    SlrCtx* c;
    float ident[16], color[4], clear[4];
    if (!rhi_enter()) return 0;
    c = ctx_from_handle(ctx);
    if (!c) { set_error(SLR_E_BAD_HANDLE); rhi_exit(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    mat4_identity(ident);
    color[0] = r; color[1] = g; color[2] = b; color[3] = 1.0f;
    clear[0] = 0.06f; clear[1] = 0.06f; clear[2] = 0.10f; clear[3] = 1.0f;
    g_rhi->v1_clear(c->rt, c->w, c->h, clear);
    g_rhi->v1_draw(c->rt, c->w, c->h, SLR_PROG_FLAT, ident, color, NULL);
    g_rhi->readback(c->rt, c->w, c->h, dst_ptr);
    c->frame_count++;
    rhi_exit();
    return 1;
}

/* ===================================================================== */
/* 诊断导出                                                               */
/* ===================================================================== */
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
    case SLR_E_BACKEND:
        return (s_err_detail[0]) ? s_err_detail : "backend unavailable";
    default:                    return "unknown error";
    }
}

const char* slr_error_detail(void) { return s_err_detail; }

const char* slr_renderer_string(void) { return s_renderer_str; }

const char* slr_version_string(void) { return s_version_str; }

const char* slr_current_backend(void) { return s_backend_str; }
