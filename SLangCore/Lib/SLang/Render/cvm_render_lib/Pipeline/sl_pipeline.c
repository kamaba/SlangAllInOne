/* =========================================================================
 * sl_pipeline.c —— Unity 风格 13 阶段渲染管线（对应 SL 侧 Pipeline/UnityPipeline.sl）
 *
 * 13 阶段与导出函数对照：
 *   1  beginFrame             slr_pipeline_begin_frame            渲染开始
 *   2  prepareMaterials       slr_pipeline_prepare_materials      准备物料
 *   3  earlyUpdate            slr_pipeline_early_update           提前更新
 *   4  cullLayers             slr_pipeline_cull_layers            渲染层分层
 *   5  assembleLayerData      slr_pipeline_assemble_layer_data    层整理数据
 *   6  uploadRenderData       slr_pipeline_upload_render_data     传GPU数据
 *   7  renderShaderChunks     slr_pipeline_render_shader_chunks   分块渲染
 *   8  updateCoreTime         slr_pipeline_update_core_time       核心时间
 *   9  renderShaderSegments   slr_pipeline_render_shader_segments 分段渲染
 *   10 assembleRenderedLayers slr_pipeline_assemble_rendered_layers 整理图层
 *   11 postProcess            slr_pipeline_post_process           后处理
 *   12 integrateLayers        slr_pipeline_integrate_layers       逻辑整合
 *   13 outputRenderTexture    slr_pipeline_output_render_texture  输出
 *
 * 多相机：阶段 4/5/7/9 按相机 depth 升序逐相机执行（视口/清屏 -> 剔除/绘制），
 * 相机槽表管理在 Pipeline/sl_camera.c。
 * ========================================================================= */
#include "sl_render_internal.h"

slr_pipeline s_pipes[SLR_MAX_PIPES];

/* ===================================================================== */
/* 数学辅助（管线专用）                                                    */
/* ===================================================================== */
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
/* 管线句柄 / 渲染目标                                                     */
/* ===================================================================== */
slr_pipeline* pipe_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_PIPES || !s_pipes[i].used) return NULL;
    return &s_pipes[i];
}

void pipeline_release_targets(slr_pipeline* p)
{
    if (g_rhi)
    {
        if (p->rt_scene) g_rhi->target_destroy(p->rt_scene);
        if (p->rt_post)  g_rhi->target_destroy(p->rt_post);
        if (p->rt_final) g_rhi->target_destroy(p->rt_final);
    }
    p->rt_scene = NULL;
    p->rt_post = NULL;
    p->rt_final = NULL;
}

static int pipeline_make_targets(slr_pipeline* p, int w, int h)
{
    return (p->rt_scene = g_rhi->target_create(w, h, 1)) != NULL
        && (p->rt_post = g_rhi->target_create(w, h, 0)) != NULL
        && (p->rt_final = g_rhi->target_create(w, h, 0)) != NULL;
}

int64_t slr_pipeline_create(int w, int h)
{
    int i;
    if (w <= 0 || h <= 0) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!rhi_enter()) return 0;
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
                rhi_exit();
                return 0;
            }
            rhi_exit();
            return (int64_t)(i + 1);
        }
    }
    set_error(SLR_E_LIMIT);
    rhi_exit();
    return 0;
}

int slr_pipeline_destroy(int64_t h)
{
    slr_pipeline* p;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    pipeline_release_targets(p);
    memset(p, 0, sizeof(slr_pipeline));
    rhi_exit();
    return 1;
}

int slr_pipeline_resize(int64_t h, int w, int hh)
{
    slr_pipeline* p;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (w <= 0 || hh <= 0) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    pipeline_release_targets(p);
    if (!pipeline_make_targets(p, w, hh))
    {
        pipeline_release_targets(p);
        set_error(SLR_E_FBO);
        rhi_exit();
        return 0;
    }
    p->w = w; p->h = hh;
    rhi_exit();
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

/* ===================================================================== */
/* 13 阶段实现（内部函数：调用方已 rhi_enter，绘制经 g_rhi 分发后端）        */
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
    /* RHI：绑定场景目标 + 全视口 + 整幅清 + 不透明初始状态 */
    g_rhi->begin_scene(p->rt_scene, p->w, p->h, p->clear_color);
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

/* 6 向 GPU 传入渲染数据（PerDraw 常量缓冲批量上传） */
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
    g_rhi->upload_perdraw(&s_perdraw, (int)sizeof(slr_perdraw));
    return 1;
}

static void draw_one_item(slr_pipeline* p, slr_draw_item* it)
{
    slr_object* o = &p->objects[it->obj];
    void* tex = NULL;
    if (it->prog == SLR_PROG_PTEX)
    {
        slr_texres* t = tex_from_handle(o->texture);
        tex = t ? t->rhi_tex : NULL;
    }
    g_rhi->draw_item(it->prog, it->slot, o->mesh, tex);
    p->draw_calls++;
    p->layers_mask |= (1 << it->layer);
}

/* 7 shader 分块渲染（不透明段，多相机：逐相机 视口/清屏 -> 分组合批绘制） */
static int stage_render_shader_chunks(slr_pipeline* p)
{
    int ci;
    p->last_stage = 7;
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        slr_camera* c = &p->cameras[bit];
        slr_cam_range* rg = &p->cam_ranges[bit];
        int i = rg->start, end = rg->start + rg->n_opaque;
        /* RHI：相机视口 + 可选局部清屏（GL: scissor / D3D11: 清屏 quad）*/
        g_rhi->camera_begin(p->rt_scene, c->vp_x, c->vp_y, c->vp_w, c->vp_h,
                            p->h, c->clear_flags, c->clear_color);
        g_rhi->set_state(0);
        while (i < end)
        {
            int prog = p->items[i].prog, j = i;
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
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        slr_camera* c = &p->cameras[bit];
        slr_cam_range* rg = &p->cam_ranges[bit];
        int i = rg->start + rg->n_opaque, end = rg->start + rg->n_opaque + rg->n_trans;
        g_rhi->camera_begin(p->rt_scene, c->vp_x, c->vp_y, c->vp_w, c->vp_h,
                            p->h, 0, c->clear_color);   /* 透明段不清屏 */
        g_rhi->set_state(1);
        while (i < end)
        {
            int prog = p->items[i].prog, j = i;
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

/* 10 整理渲染后的图层（簿记；渲染状态由后续 pass 自行设定） */
static int stage_assemble_rendered_layers(slr_pipeline* p)
{
    p->last_stage = 10;
    return 1;
}

/* 11 后处理（RHI：scene -> post，enabled=0 纯拷贝） */
static int stage_post_process(slr_pipeline* p)
{
    p->last_stage = 11;
    g_rhi->post_process(p->rt_post, p->rt_scene, p->w, p->h,
                        p->post_enabled, p->post_brightness,
                        p->post_saturation, p->post_vignette);
    p->program_switches++;
    p->draw_calls++;
    return 1;
}

/* 12 层级的逻辑整合（RHI 全屏拷贝：post -> 最终 renderTexture） */
static int stage_integrate_layers(slr_pipeline* p)
{
    p->last_stage = 12;
    g_rhi->blit(p->rt_final, p->rt_post, p->w, p->h);
    p->program_switches++;
    p->draw_calls++;
    return 1;
}

/* 13 输出最终渲染 renderTexture（RHI 回读：top-down RGBA8） */
static int stage_output_render_texture(slr_pipeline* p, int64_t dst_ptr)
{
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); return 0; }
    p->last_stage = 13;
    g_rhi->readback(p->rt_final, p->w, p->h, dst_ptr);
    return 1;
}

/* ---- 阶段导出 ---- */
#define SLR_STAGE_EXPORT(fname, stager)                      \
    SLR_API int fname(int64_t h)                                \
    {                                                          \
        slr_pipeline* p;                                       \
        int ok;                                                \
        if (!rhi_enter()) return 0;                             \
        p = pipe_from_handle(h);                               \
        if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; } \
        ok = stager(p);                                        \
        rhi_exit();                                             \
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
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    ok = stage_begin_frame(p, time);
    rhi_exit();
    return ok;
}

int slr_pipeline_output_render_texture(int64_t h, int64_t dst_ptr)
{
    slr_pipeline* p;
    int ok;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    ok = stage_output_render_texture(p, dst_ptr);
    rhi_exit();
    return ok;
}

int slr_pipeline_render_frame(int64_t h, float time, int64_t dst_ptr)
{
    slr_pipeline* p;
    int ok;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
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
    rhi_exit();
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
