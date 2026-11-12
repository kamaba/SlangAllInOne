/* =========================================================================
 * sl_camera.c —— 多相机槽表（对应 SL 侧 UnityRenderCamera）
 *
 * 每管线 8 个相机槽（SLR_MAX_CAMERAS），槽 0 为默认相机（兼容 v2 的
 * slr_pipeline_set_camera / set_clear_color 写槽 0，不可销毁）。
 * 渲染次序由 depth 升序决定（排序与逐相机绘制见 Pipeline/sl_pipeline.c）。
 * ========================================================================= */
#include "sl_render_internal.h"

static SlrCamera* cam_from_handle(SlrPipeline* p, int64_t ch)
{
    int i = (int)(ch - 1);
    if (ch <= 0 || i >= SLR_MAX_CAMERAS || !p->cameras[i].used) return NULL;
    return &p->cameras[i];
}

int64_t slr_camera_create(int64_t h, int depth)
{
    SlrPipeline* p;
    int i;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    for (i = 0; i < SLR_MAX_CAMERAS; i++)
    {
        SlrCamera* c;
        if (p->cameras[i].used) continue;
        c = &p->cameras[i];
        memset(c, 0, sizeof(SlrCamera));
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
    SlrPipeline* p;
    SlrCamera* c;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    if (ch == 1) { set_error(SLR_E_BAD_PARAM); return 0; }  /* 默认相机不可销毁 */
    c = cam_from_handle(p, ch);
    if (!c) { set_error(SLR_E_BAD_HANDLE); return 0; }
    memset(c, 0, sizeof(SlrCamera));
    p->camera_count--;
    return 1;
}

static int cam_set_common(int64_t h, int64_t ch, SlrPipeline** pp, SlrCamera** cc)
{
    *pp = pipe_from_handle(h);
    if (!*pp) { set_error(SLR_E_PIPELINE); return 0; }
    *cc = cam_from_handle(*pp, ch);
    if (!*cc) { set_error(SLR_E_BAD_HANDLE); return 0; }
    return 1;
}

int slr_camera_set_enabled(int64_t h, int64_t ch, int enabled)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->enabled = enabled ? 1 : 0;
    return 1;
}

int slr_camera_set_depth(int64_t h, int64_t ch, int depth)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->depth = depth;
    return 1;
}

int slr_camera_set_cull_mask(int64_t h, int64_t ch, int mask)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->cull_mask = mask;
    return 1;
}

int slr_camera_set_extents(int64_t h, int64_t ch, float l, float r, float b, float t)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->cam_l = l; c->cam_r = r; c->cam_b = b; c->cam_t = t;
    return 1;
}

int slr_camera_set_viewport(int64_t h, int64_t ch, int x, int y, int w, int hh)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    if (x < 0 || y < 0 || w <= 0 || hh <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    c->vp_x = x; c->vp_y = y; c->vp_w = w; c->vp_h = hh;
    return 1;
}

int slr_camera_set_clear_color(int64_t h, int64_t ch, float r, float g, float b, float a)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->clear_color[0] = r; c->clear_color[1] = g;
    c->clear_color[2] = b; c->clear_color[3] = a;
    return 1;
}

int slr_camera_set_clear_flags(int64_t h, int64_t ch, int flags)
{
    SlrPipeline* p; SlrCamera* c;
    if (!cam_set_common(h, ch, &p, &c)) return 0;
    c->clear_flags = flags & (SLR_CLEAR_COLOR | SLR_CLEAR_DEPTH);
    return 1;
}

int slr_camera_count(int64_t h)
{
    SlrPipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    return p->camera_count;
}
