/* =========================================================================
 * sl_ray.c —— 软光追渲染器（对应 SL 侧 Ray.sl；N4a，AIPrompt.md）
 *
 * 纯 CPU 逐像素 whitted 求交（四后端无关的离线路径）：
 *   - 固定容量场景：≤16 球（SLR_RAY_MAX_SPHERES）+ y=0 地面平面；
 *   - 2 弹射：主射线（depth 0）+ 1 次反射（depth 1），阴影射线每次
 *     漫反射求值各一条；
 *   - 场景状态挂 SlrPipeline.ray（SLMC RaySet* 命令累积覆写，跨命令流
 *     持久）；RayRender 消费渲染：逐像素 trace -> top-down RGBA8 ->
 *     texture_register（翻行 + RHI 上传）-> 写描述符槽（与
 *     SLR_CMD_SET_TEXTURE 同路径，后续 DrawItem 经 texDesc 绑定上屏）。
 *
 * 着色模型与相机模型见 sl_render_internal.h 的 SlrRayScene 注释
 * （C/SL 两侧逐字一致——RenderTest Phase RAY 用 Ray.sl 参考实现 +
 * 手算理论值双重断言）。SL 侧参考实现在 Ray.sl 的 RayScene。
 * ========================================================================= */
#include "sl_render_internal.h"

#define SLR_RAY_EPS 1e-3f   /* 二次射线自交偏移（沿法线偏移起点） */

/* ---- 向量小工具（本文件内联）---- */
static float v3_dot(const float* a, const float* b)
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

static float v3_len(const float* v)
{
    return sqrtf(v3_dot(v, v));
}

static void v3_norm(float* v)
{
    float l = v3_len(v);
    if (l > 1e-8f) { v[0] /= l; v[1] /= l; v[2] /= l; }
}

static float clamp01(float v)
{
    if (v < 0.0f) return 0.0f;
    if (v > 1.0f) return 1.0f;
    return v;
}

/* ---- 场景写入口（SLMC RaySet* 回放）---- */
void ray_scene_reset(SlrRayScene* s)
{
    memset(s, 0, sizeof(*s));
    s->ground_on = 1;
    s->ground[0] = 0.5f; s->ground[1] = 0.5f; s->ground[2] = 0.5f; s->ground[3] = 0.0f;
    s->light_dir[0] = 0.0f; s->light_dir[1] = 1.0f; s->light_dir[2] = 0.0f;
    s->light_intensity = 1.0f;
    s->eye[0] = 0.0f; s->eye[1] = 1.0f; s->eye[2] = -4.0f;
    s->fov_y = 60.0f;
}

void ray_set_sphere(SlrRayScene* s, int idx, const float* f8)
{
    SlrRaySphere* sp;
    if (!s || idx < 0 || idx >= SLR_RAY_MAX_SPHERES || !f8) return;
    sp = &s->spheres[idx];
    sp->used = 1;
    sp->cx = f8[0]; sp->cy = f8[1]; sp->cz = f8[2]; sp->r = f8[3];
    sp->cr = f8[4]; sp->cg = f8[5]; sp->cb = f8[6]; sp->reflect = f8[7];
    if (idx + 1 > s->sphere_count) s->sphere_count = idx + 1;
}

void ray_set_light(SlrRayScene* s, const float* f4)
{
    if (!s || !f4) return;
    s->light_dir[0] = f4[0]; s->light_dir[1] = f4[1]; s->light_dir[2] = f4[2];
    s->light_intensity = f4[3];
}

void ray_set_ground(SlrRayScene* s, const float* f4)
{
    if (!s || !f4) return;
    s->ground_on = 1;
    s->ground[0] = f4[0]; s->ground[1] = f4[1]; s->ground[2] = f4[2]; s->ground[3] = f4[3];
}

void ray_set_camera(SlrRayScene* s, const float* f4)
{
    if (!s || !f4) return;
    s->eye[0] = f4[0]; s->eye[1] = f4[1]; s->eye[2] = f4[2];
    s->fov_y = f4[3];
}

void ray_set_background(SlrRayScene* s, const float* f3)
{
    if (!s || !f3) return;
    s->bg[0] = f3[0]; s->bg[1] = f3[1]; s->bg[2] = f3[2];
}

/* ---- 求交 ---- */

/* 单球求交（d 已归一）：t > eps 时命中，返回 1 并写出 t */
static int ray_hit_sphere(const SlrRaySphere* sp, const float* o, const float* d,
                          float eps, float* t_out)
{
    float oc[3], b, c, disc, t;
    oc[0] = o[0] - sp->cx; oc[1] = o[1] - sp->cy; oc[2] = o[2] - sp->cz;
    b = v3_dot(oc, d);
    c = v3_dot(oc, oc) - sp->r * sp->r;
    disc = b * b - c;
    if (disc < 0.0f) return 0;
    t = -b - sqrtf(disc);
    if (t <= eps) return 0;
    *t_out = t;
    return 1;
}

/* 地面（y=0，法线恒 +y）求交：仅自上方向下的射线可命中 */
static int ray_hit_ground(const SlrRayScene* s, const float* o, const float* d,
                          float eps, float* t_out)
{
    float t;
    if (!s->ground_on || d[1] >= -1e-8f) return 0;
    t = -o[1] / d[1];
    if (t <= eps) return 0;
    *t_out = t;
    return 1;
}

/* 最近命中：球 + 地面。命中返回 1 并写出 t / 命中点 / 法线 / 材质
 * （mat >= 0 球下标 / -1 地面）；未命中返回 0 */
static int ray_nearest(const SlrRayScene* s, const float* o, const float* d,
                       float eps, float* t_out, float* p_out, float* n_out,
                       const float** albedo_out, float* refl_out, int* mat_out)
{
    int i, best_mat = -2;
    float best_t = 0.0f, t;
    const float* best_alb = 0;
    float best_refl = 0.0f;

    for (i = 0; i < s->sphere_count; i++)
    {
        if (!s->spheres[i].used) continue;
        if (ray_hit_sphere(&s->spheres[i], o, d, eps, &t))
        {
            if (best_mat == -2 || t < best_t)
            {
                best_t = t; best_mat = i;
                best_alb = &s->spheres[i].cr;
                best_refl = s->spheres[i].reflect;
            }
        }
    }
    if (ray_hit_ground(s, o, d, eps, &t))
    {
        if (best_mat == -2 || t < best_t)
        {
            best_t = t; best_mat = -1;
            best_alb = s->ground;
            best_refl = s->ground[3];
        }
    }
    if (best_mat == -2) return 0;

    *t_out = best_t;
    p_out[0] = o[0] + d[0] * best_t;
    p_out[1] = o[1] + d[1] * best_t;
    p_out[2] = o[2] + d[2] * best_t;
    if (best_mat >= 0)
    {
        const SlrRaySphere* sp = &s->spheres[best_mat];
        float inv_r = sp->r > 1e-8f ? 1.0f / sp->r : 0.0f;
        n_out[0] = (p_out[0] - sp->cx) * inv_r;
        n_out[1] = (p_out[1] - sp->cy) * inv_r;
        n_out[2] = (p_out[2] - sp->cz) * inv_r;
    }
    else
    {
        n_out[0] = 0.0f; n_out[1] = 1.0f; n_out[2] = 0.0f;
    }
    *albedo_out = best_alb;
    *refl_out = best_refl;
    *mat_out = best_mat;
    return 1;
}

/* 阴影射线遮挡测试：任一球挡住（t > eps）即遮挡（地面是接收面不遮挡） */
static int ray_blocked(const SlrRayScene* s, const float* o, const float* d)
{
    int i;
    float t;
    for (i = 0; i < s->sphere_count; i++)
    {
        if (!s->spheres[i].used) continue;
        if (ray_hit_sphere(&s->spheres[i], o, d, SLR_RAY_EPS, &t)) return 1;
    }
    return 0;
}

/* whitted 递归（depth 0 主射线 / 1 反射；d 已归一） */
static void ray_trace(const SlrRayScene* s, const float* o, const float* d,
                      int depth, float* rgb)
{
    float t, p[3], n[3], refl, L[3], ndl, lit;
    float local[3];
    const float* alb;
    int mat;

    if (!ray_nearest(s, o, d, 1e-4f, &t, p, n, &alb, &refl, &mat))
    {
        rgb[0] = s->bg[0]; rgb[1] = s->bg[1]; rgb[2] = s->bg[2];
        return;
    }

    L[0] = s->light_dir[0]; L[1] = s->light_dir[1]; L[2] = s->light_dir[2];
    v3_norm(L);
    ndl = v3_dot(n, L);
    lit = SLR_RAY_AMBIENT;
    if (ndl > 0.0f && s->light_intensity > 0.0f)
    {
        float so[3];    /* 阴影射线起点：沿法线偏移避免自交 */
        so[0] = p[0] + n[0] * SLR_RAY_EPS;
        so[1] = p[1] + n[1] * SLR_RAY_EPS;
        so[2] = p[2] + n[2] * SLR_RAY_EPS;
        if (!ray_blocked(s, so, L)) lit += s->light_intensity * ndl;
    }
    local[0] = alb[0] * lit;
    local[1] = alb[1] * lit;
    local[2] = alb[2] * lit;

    if (depth < 1 && refl > 0.0f)
    {
        float dd = v3_dot(d, n);
        float rd[3];    /* 反射方向（d/n 单位向量，反射保持长度 1）*/
        float ro[3];
        float rc[3];
        rd[0] = d[0] - 2.0f * dd * n[0];
        rd[1] = d[1] - 2.0f * dd * n[1];
        rd[2] = d[2] - 2.0f * dd * n[2];
        ro[0] = p[0] + n[0] * SLR_RAY_EPS;
        ro[1] = p[1] + n[1] * SLR_RAY_EPS;
        ro[2] = p[2] + n[2] * SLR_RAY_EPS;
        ray_trace(s, ro, rd, depth + 1, rc);
        rgb[0] = local[0] * (1.0f - refl) + rc[0] * refl;
        rgb[1] = local[1] * (1.0f - refl) + rc[1] * refl;
        rgb[2] = local[2] * (1.0f - refl) + rc[2] * refl;
    }
    else
    {
        rgb[0] = local[0]; rgb[1] = local[1]; rgb[2] = local[2];
    }
}

/* ---- 渲染入口（SLMC RayRender 回放；调用方已 rhi_enter）---- */
int ray_render(SlrPipeline* p, int tex_slot, int w, int h)
{
    SlrRayScene* s;
    unsigned char* buf;
    float half_h, half_w, aspect;
    int x, y;

    if (!p || w < 8 || w > 2048 || h < 8 || h > 2048)
    {
        set_error_detail(SLR_E_BAD_PARAM, "ray render size");
        return 0;
    }
    buf = (unsigned char*)malloc((size_t)w * (size_t)h * 4);
    if (!buf) { set_error(SLR_E_MEMORY); return 0; }

    s = &p->ray;
    half_h = tanf(s->fov_y * 3.14159265358979323846f / 360.0f);
    aspect = (float)w / (float)h;
    half_w = half_h * aspect;

    for (y = 0; y < h; y++)
    {
        float ndc_y = 1.0f - ((float)y + 0.5f) * 2.0f / (float)h;
        for (x = 0; x < w; x++)
        {
            float ndc_x = ((float)x + 0.5f) * 2.0f / (float)w - 1.0f;
            float d[3], rgb[3];
            unsigned char* px;
            d[0] = ndc_x * half_w;
            d[1] = ndc_y * half_h;
            d[2] = 1.0f;
            v3_norm(d);
            ray_trace(s, s->eye, d, 0, rgb);
            px = buf + ((size_t)y * (size_t)w + (size_t)x) * 4;
            px[0] = (unsigned char)(clamp01(rgb[0]) * 255.0f + 0.5f);
            px[1] = (unsigned char)(clamp01(rgb[1]) * 255.0f + 0.5f);
            px[2] = (unsigned char)(clamp01(rgb[2]) * 255.0f + 0.5f);
            px[3] = 255;
        }
    }

    /* 输出纹理：销毁旧 -> 注册新（top-down 契约，texture_register 内翻行）*/
    if (p->ray_tex)
    {
        SlrTexRes* old = tex_from_handle(p->ray_tex);
        if (old)
        {
            g_rhi->texture_destroy(old->rhi_tex);
            memset(old, 0, sizeof(SlrTexRes));
        }
        p->ray_tex = 0;
    }
    p->ray_tex = texture_register(w, h, buf);
    free(buf);
    if (!p->ray_tex) return 0;   /* set_error 已由注册路径置位 */
    p->ray_tex_w = w; p->ray_tex_h = h;

    /* 写描述符槽（与 SLR_CMD_SET_TEXTURE 同路径：绑定与绘制分离）*/
    if (tex_slot >= 0 && tex_slot < SLR_DESC_TEX_SLOTS)
    {
        SlrTexRes* t = tex_from_handle(p->ray_tex);
        if (t)
        {
            p->descs.tex[tex_slot].res = t->rhi_tex;
            p->descs.tex[tex_slot].used = 1;
            if (tex_slot + 1 > p->descs.tex_count) p->descs.tex_count = tex_slot + 1;
            g_rhi->desc_write_tex(tex_slot, t->rhi_tex);
        }
    }
    return 1;
}
