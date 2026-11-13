/* =========================================================================
 * sl_pipeline.c —— 13 阶段渲染管线（对应 SL 侧 Pipeline/Pipeline.sl）
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

SlrPipeline s_pipes[SLR_MAX_PIPES];

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

/* 2D 模型矩阵：平移(x,y,z) + 绕 Z 旋转 + 缩放（列主序）。
 * v3.4 深度语义（兼顾 v3.3 排序键兼容 + 四后端深度域）：
 *   - z <= 0：真实深度（ndc.z = -z ∈ [0,1]，GL/GLES/D3D11 三方一致，
 *     D3D SV_Position.z 无 [-1,1] 映射必须非负）；
 *   - z > 0：v3.3 语义 z 仅为透明排序键（如 A2 quad z=0.5 表示"最上"），
 *     钳 0 保持 ndc 0 平局行为（后画同深 LESS 剔除）逐字节兼容；
 *   - 投影阴影经 zdepth = 钳(caster z - 0.01) 落在"接收面(z<0)与
 *     本体(z=0)"之间的深度夹层（接收面须 z < 阴影深度才被投影）。 */
static void mat4_model2d(float* m, float x, float y, float z, float rz, float sx, float sy)
{
    float c = cosf(rz), s = sinf(rz);
    if (z > 0.0f) z = 0.0f;
    m[0] = c * sx;  m[1] = s * sx;  m[2] = 0.0f; m[3] = 0.0f;
    m[4] = -s * sy; m[5] = c * sy;  m[6] = 0.0f; m[7] = 0.0f;
    m[8] = 0.0f;    m[9] = 0.0f;    m[10] = 1.0f; m[11] = 0.0f;
    m[12] = x;      m[13] = y;      m[14] = z;   m[15] = 1.0f;
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
SlrPipeline* pipe_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLR_MAX_PIPES || !s_pipes[i].used) return NULL;
    return &s_pipes[i];
}

void pipeline_release_targets(SlrPipeline* p)
{
    if (g_rhi)
    {
        if (p->rt_scene) g_rhi->target_destroy(p->rt_scene);
        if (p->rt_post)  g_rhi->target_destroy(p->rt_post);
        if (p->rt_final) g_rhi->target_destroy(p->rt_final);
        /* N2a：shadow 深度目标（后端无 shadow 能力时 vtable 为 NULL，
         * rt_shadow 恒 NULL，此调用天然跳过）*/
        if (p->rt_shadow && g_rhi->shadow_target_destroy)
            g_rhi->shadow_target_destroy(p->rt_shadow);
    }
    p->rt_scene = NULL;
    p->rt_post = NULL;
    p->rt_final = NULL;
    p->rt_shadow = NULL;
}

static int pipeline_make_targets(SlrPipeline* p, int w, int h)
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
            SlrPipeline* p = &s_pipes[i];
            memset(p, 0, sizeof(SlrPipeline));
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
            /* 光照默认态：无光源 + 环境光 1.0（memset 归零会让全屏变黑，
             * 必须显式置 1——输出与无光照版逐字节一致，向后兼容）*/
            p->ambient = 1.0f;
            /* N2a shadow map 默认参数（shadowQuality=1 的平行光出现时激活）*/
            p->shadow_map_size = 512;
            p->shadow_bias = 0.002f;
            p->shadow_strength = 0.35f;   /* 对齐旧黑斑 alpha 0.35 观感 */
            p->clear_color[0] = 0.06f; p->clear_color[1] = 0.06f;
            p->clear_color[2] = 0.10f; p->clear_color[3] = 1.0f;
            p->post_brightness = 1.0f; p->post_saturation = 1.0f; p->post_vignette = 0.0f;
            if (!pipeline_make_targets(p, w, h))
            {
                pipeline_release_targets(p);
                memset(p, 0, sizeof(SlrPipeline));
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
    SlrPipeline* p;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    pipeline_release_targets(p);
    memset(p, 0, sizeof(SlrPipeline));
    rhi_exit();
    return 1;
}

int slr_pipeline_resize(int64_t h, int w, int hh)
{
    SlrPipeline* p;
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
    SlrPipeline* p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    return p->frame_count;
}

int slr_pipeline_set_camera(int64_t h, int cull_mask, float l, float r, float b, float t)
{
    SlrPipeline* p = pipe_from_handle(h);
    SlrCamera* c;
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    /* 兼容 v2：写默认相机（槽 0） */
    c = &p->cameras[0];
    c->cull_mask = cull_mask;
    c->cam_l = l; c->cam_r = r; c->cam_b = b; c->cam_t = t;
    return 1;
}

int slr_pipeline_set_clear_color(int64_t h, float r, float g, float b, float a)
{
    SlrPipeline* p = pipe_from_handle(h);
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
    SlrPipeline* p = pipe_from_handle(h);
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
static int stage_begin_frame(SlrPipeline* p, float time)
{
    p->time = time;
    p->frame_count++;
    p->last_stage = 1;
    p->visible_count = 0; p->culled_count = 0;
    p->draw_calls = 0; p->opaque_draws = 0; p->transparent_draws = 0;
    p->instance_total = 0;   /* N1：实例总数逐帧清零 */
    p->chunk_count = 0; p->program_switches = 0; p->upload_count = 0;
    p->layers_mask = 0; p->item_count = 0; p->opaque_count = 0;
    /* RHI：绑定场景目标 + 全视口 + 整幅清 + 不透明初始状态 */
    g_rhi->begin_scene(p->rt_scene, p->w, p->h, p->clear_color);
    return 1;
}

/* 2 准备物料 */
static int stage_prepare_materials(SlrPipeline* p)
{
    p->last_stage = 2;
    /* 着色器程序/UBO 在 slr_init 已就绪；此处确保场景纹理参数合法 */
    return 1;
}

/* 3 提前更新（动画） */
static int stage_early_update(SlrPipeline* p)
{
    int i;
    p->last_stage = 3;
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        SlrObject* o = &p->objects[i];
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
static int pipeline_order_cameras(SlrPipeline* p, int* order)
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
static int stage_cull_layers(SlrPipeline* p)
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
        SlrObject* o = &p->objects[i];
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
                SlrCamera* c = &p->cameras[order[ci]];
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
static void sort_items(SlrDrawItem* items, int count, int transparent)
{
    int i, j;
    for (i = 1; i < count; i++)
    {
        SlrDrawItem key = items[i];
        j = i - 1;
        while (j >= 0)
        {
            int swap;
            if (transparent)
            {
                /* 队列升序，同队列 z 降序（远→近）——透明顺序敏感，
                 * 不加材质键（合批不得改变混合次序）*/
                if (items[j].queue > key.queue) swap = 1;
                else if (items[j].queue < key.queue) swap = 0;
                else swap = items[j].z < key.z;
            }
            else
            {
                /* Batching & Sorting（材质排序）：
                 * 队列升序，同队列 z 升序（近→远，Early-Z 方向）；z 同则
                 * 按材质键（prog + 纹理描述符槽）升序——同材质项自然
                 * 相邻成批，阶段 7 一个批 = 一次纹理绑定（深度测试保证
                 * 同深度不透明绘制次序不影响输出，材质排序零像素回归）*/
                if (items[j].queue > key.queue) swap = 1;
                else if (items[j].queue < key.queue) swap = 0;
                else if (items[j].z > key.z) swap = 1;
                else if (items[j].z < key.z) swap = 0;
                else if (items[j].prog > key.prog) swap = 1;
                else if (items[j].prog < key.prog) swap = 0;
                else swap = items[j].tex_desc > key.tex_desc;
            }
            if (!swap) break;
            items[j + 1] = items[j];
            j--;
        }
        items[j + 1] = key;
    }
}

/* 4.5 N2a/N2b shadow 深度 pass：首个 shadowQuality>=1 平行光的光空间
 * 正交深度渲染（castShadow 对象 -> 深度图集；阶段 6 全量 PerDraw 覆盖
 * 重传，临时槽互不干扰）。
 *
 * 2D 光空间扫掠体（shadow volume 正解——平面几何零厚度的光栅化）：
 *   u 轴 = 光方向 d（沿光距离，深度通道）、v 轴 = 垂直光方向；
 *   直接投影 (v→x, u→z) 是 rank-1 退化（屏面零厚度，光栅化丢弃）。
 *   解：把 castShadow 物体沿"背光方向"仿射拉伸成扫掠体
 *   （u ∈ [u_min,u_max] -> [un, u_max]，u 小侧推到视域近端），
 *   深度恒 = (uf-u_max)/range（物体最朝光面）——深度图语义
 *   "柱 v 的最朝光遮挡面"，覆盖物体自身 + 全部背光侧投影区。
 *   采样端：P 重投影 (v_P, u_P) 单点 + 深度比较（与 3D 完全同构）。
 *
 * N2b CSM（cascades=4）：v 轴按固定比例分割（0.05/0.25/0.6/1.0，
 * Unity URP 默认级联分布），每级独立 (vc, W) 视域 + 级内物体的收紧
 * u 窗口（级联精髓——窄 v 段 + 窄深度窗 = 局部高精度）；深度图集单张
 * 1x4 横向分区（每区宽 size/4，级 i 映 [i/4,(i+1)/4]）；shader 端按
 * 片元 v_P 与 uShadowSplit 比较选级联（=1 时全段单级 = N2a 零变化）。
 *
 * 跨后端深度值域：ndc.z ∈ [0,1]（D3D11 直通；GL/GLES 硬件深度
 * z*0.5+0.5，shader 里 zxform (2,-1) 还原后比较）。
 * 前置：阶段 4 剔除后（cull_cams 就绪）；后端无 shadow 能力
 * （VK vtable NULL）或无 shadow 光源时置 shadow_on=0 走黑斑回退。 */
static int stage_shadow_pass(SlrPipeline* p)
{
    float ldir[2];
    float dx, dy;
    float vmin = 0.0f, vmax = 0.0f, umin = 0.0f, ufar = 0.0f;
    float split[5];
    int cascades = 1;
    int lv, i, ci, k, first = 1;
    SlrLight* sl = NULL;

    p->shadow_on = 0;
    /* 后端能力：vtable 四函数任一为 NULL（VK 降级）即回退 */
    if (!g_rhi->shadow_target_create || !g_rhi->shadow_begin ||
        !g_rhi->shadow_target_destroy || !g_rhi->shadow_bind_depth)
        return 1;
    i = light_pick_shadowmap(p, ldir);
    if (i < 0) return 1;
    sl = &p->lights[i];
    dx = ldir[0]; dy = ldir[1];
    /* N2b：光源级覆盖（0 = 管线默认；每帧刷新——灯可动态改参）*/
    p->shadow_bias = sl->shadow_bias_ovr > 0.0f ? sl->shadow_bias_ovr : 0.002f;
    p->shadow_strength = sl->shadow_str_ovr > 0.0f ? sl->shadow_str_ovr : 0.35f;
    cascades = (sl->shadow_cascades >= 4) ? 4 : 1;
    p->shadow_cascades = cascades;

    /* 第一遍：castShadow 物体的 (v,u) 轴向范围（旋转精确——|基系数|
     * 和式）+ 视域包围更新 */
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        SlrObject* o = &p->objects[i];
        float c, s, A, B, Pp, Qq, V0, U0, av, au;
        if (!o->used || !o->cast_shadow) continue;
        c = cosf(o->rot_z); s = sinf(o->rot_z);
        A = o->scale[0] * (-c * dy + s * dx);
        B = o->scale[1] * ( s * dy + c * dx);
        Pp = o->scale[0] * ( c * dx + s * dy);
        Qq = o->scale[1] * (-s * dx + c * dy);
        V0 = -o->pos[0] * dy + o->pos[1] * dx;
        U0 =  o->pos[0] * dx + o->pos[1] * dy;
        av = (A >= 0 ? A : -A) + (B >= 0 ? B : -B);
        au = (Pp >= 0 ? Pp : -Pp) + (Qq >= 0 ? Qq : -Qq);
        if (first || V0 - av * 0.5f < vmin) vmin = V0 - av * 0.5f;
        if (first || V0 + av * 0.5f > vmax) vmax = V0 + av * 0.5f;
        if (first || U0 + au * 0.5f > ufar) ufar = U0 + au * 0.5f;
        first = 0;
    }
    if (first) return 1;   /* 无 castShadow 对象：黑斑路径同样无内容 */
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        SlrCamera* c = &p->cameras[p->active_cams[ci]];
        float corner[4][2] = {
            { c->cam_l, c->cam_b }, { c->cam_r, c->cam_b },
            { c->cam_l, c->cam_t }, { c->cam_r, c->cam_t } };
        for (k = 0; k < 4; k++)
        {
            float v = -corner[k][0] * dy + corner[k][1] * dx;
            float u =  corner[k][0] * dx + corner[k][1] * dy;
            if (v < vmin) vmin = v;
            if (v > vmax) vmax = v;
            if (first || u < umin) umin = u;
            if (u > ufar) ufar = u;
        }
    }

    /* 级联 v 分段：单级 = [vmin, vmax] 全段；4 级 = 固定比例分割
     * （0.05 / 0.25 / 0.6 / 1.0，段宽 5% / 20% / 35% / 40%）*/
    if (cascades == 4)
    {
        float d = vmax - vmin;
        static const float r[5] = { 0.0f, 0.05f, 0.25f, 0.6f, 1.0f };
        for (lv = 0; lv < 5; lv++) split[lv] = vmin + r[lv] * d;
    }
    else
    {
        split[0] = vmin;
        split[1] = split[2] = split[3] = split[4] = vmax;
    }
    for (lv = 0; lv < 5; lv++) p->shadow_split[lv] = split[lv];

    /* 深度图集懒创建（1x4 分区：每区宽 size/4，y 全高）*/
    if (!p->rt_shadow)
        p->rt_shadow = g_rhi->shadow_target_create(p->shadow_map_size,
                                                   p->shadow_map_size);
    if (!p->rt_shadow) return 1;
    g_rhi->shadow_begin(p->rt_shadow, p->shadow_map_size, p->shadow_map_size);

    /* 每级联：独立视域/窗口/扫掠体渲染（单级 = N2a 路径退化）*/
    for (lv = 0; lv < cascades; lv++)
    {
        float seg_lo = split[lv], seg_hi = split[lv + 1];
        float W, vc, un, uf, du, svp[16];
        SlrPerDraw tmp;
        int n = 0, slot = 0;

        W = (seg_hi - seg_lo) * 0.5f;
        vc = (seg_hi + seg_lo) * 0.5f;
        if (W < 1e-3f) W = 1e-3f;
        W *= 1.15f;                       /* 级内 15% pad（跨级重叠正常）*/

        /* 级内 u 窗口：v 投影与 [seg_lo, seg_hi] 相交的物体 u 范围 */
        un = umin; uf = ufar;
        {
            int hit = 0;
            float ul = 0.0f, uh = 0.0f;
            for (i = 0; i < SLR_MAX_OBJECTS; i++)
            {
                SlrObject* o = &p->objects[i];
                float c, s, Pp, Qq, V0, U0, av, au;
                if (!o->used || !o->cast_shadow) continue;
                c = cosf(o->rot_z); s = sinf(o->rot_z);
                Pp = o->scale[0] * ( c * dx + s * dy);
                Qq = o->scale[1] * (-s * dx + c * dy);
                V0 = -o->pos[0] * dy + o->pos[1] * dx;
                U0 =  o->pos[0] * dx + o->pos[1] * dy;
                av = (o->scale[0] * (-c * dy + s * dx));
                av = (av >= 0 ? av : -av) + (o->scale[1] * ( s * dy + c * dx));
                au = (Pp >= 0 ? Pp : -Pp) + (Qq >= 0 ? Qq : -Qq);
                if (V0 + av * 0.5f < seg_lo || V0 - av * 0.5f > seg_hi)
                    continue;               /* v 投影与本级无交集 */
                if (!hit || U0 - au * 0.5f < ul) ul = U0 - au * 0.5f;
                if (!hit || U0 + au * 0.5f > uh) uh = U0 + au * 0.5f;
                hit = 1;
            }
            if (!hit) continue;            /* 空级联：无内容（全 clear）*/
            un = ul; uf = uh;
        }
        if (uf - un < 1e-3f) uf = un + 1e-3f;
        { float pad = (uf - un) * 0.15f + 0.05f; un -= pad; uf += pad; }
        du = 1.0f / (uf - un);

        /* 采样矩阵（列主序；shader mul(uLightVP_lv, world4) 同构）：
         *   sp.x = (v-vc)/W（柱）、sp.y = 2(u-un)*du-1（行 = 片元自身 u）、
         *   sp.z = (uf-u)*du（参考深度——翻转：u 越大越朝光 z 越小）*/
        memset(svp, 0, sizeof(svp));
        svp[0] = -dy / W;   svp[1] = 2.0f * dx * du;  svp[2] = -dx * du;  svp[3] = 0.0f;
        svp[4] =  dx / W;   svp[5] = 2.0f * dy * du;  svp[6] = -dy * du;  svp[7] = 0.0f;
        svp[12] = -vc / W;  svp[13] = -2.0f * un * du - 1.0f; svp[14] = uf * du; svp[15] = 1.0f;
        memcpy(p->shadow_light_vp[lv], svp, sizeof(svp));

        /* 级内扫掠体 mvp（local quad 顶点直映 NDC，深度恒 = 最朝光面）*/
        memset(&tmp, 0, sizeof(tmp));
        n = 0;
        for (i = 0; i < SLR_MAX_OBJECTS; i++)
        {
            SlrObject* o = &p->objects[i];
            float c, s, A, B, Pp, Qq, V0, U0, av, au, umax_i, umin_i, kk, ca, *m;
            if (!o->used || !o->cast_shadow) continue;
            c = cosf(o->rot_z); s = sinf(o->rot_z);
            A = o->scale[0] * (-c * dy + s * dx);
            B = o->scale[1] * ( s * dy + c * dx);
            Pp = o->scale[0] * ( c * dx + s * dy);
            Qq = o->scale[1] * (-s * dx + c * dy);
            V0 = -o->pos[0] * dy + o->pos[1] * dx;
            U0 =  o->pos[0] * dx + o->pos[1] * dy;
            av = (A >= 0 ? A : -A) + (B >= 0 ? B : -B);
            au = (Pp >= 0 ? Pp : -Pp) + (Qq >= 0 ? Qq : -Qq);
            if (V0 + av * 0.5f < seg_lo || V0 - av * 0.5f > seg_hi)
                continue;                   /* 非本级联物体 */
            umin_i = U0 - au * 0.5f;
            umax_i = U0 + au * 0.5f;
            if (umax_i - umin_i < 1e-4f) continue;
            if (umax_i <= un + 1e-3f) continue;
            kk = (umax_i - un) / (umax_i - umin_i);
            ca = un - kk * umin_i;
            m = tmp.mvp[n];
            memset(m, 0, sizeof(float) * 16);
            /* x 列：级内 ndc.x ∈[-1,1] 映图集分区 lv 的 ndc 区
             * [-1+lv·0.5, -1+(lv+1)·0.5]：ndc_atlas = 0.25·ndc + lv·0.5-0.75
             * （单级 lv=0：[-1,-0.5] 即 uv.x∈[0,0.25]——与 shader 采样同区）*/
            m[0]  = A / W * 0.25f;
            m[4]  = B / W * 0.25f;
            m[12] = (V0 - vc) / W * 0.25f + (float)lv * 0.5f - 0.75f;
            m[1]  = 2.0f * du * kk * Pp;
            m[5]  = 2.0f * du * kk * Qq;
            m[13] = 2.0f * du * (kk * U0 + ca) - 2.0f * un * du - 1.0f;
            m[14] = (uf - umax_i) * du;
            m[15] = 1.0f;
            n++;
        }
        if (n == 0) continue;

        g_rhi->upload_perdraw(&tmp, (int)sizeof(tmp));
        g_rhi->set_state(0);
        for (i = 0; i < SLR_MAX_OBJECTS; i++)
        {
            SlrObject* o = &p->objects[i];
            float c, s, A, B, Pp, Qq, V0, U0, av, au, umax_i, umin_i;
            if (!o->used || !o->cast_shadow) continue;
            c = cosf(o->rot_z); s = sinf(o->rot_z);
            A = o->scale[0] * (-c * dy + s * dx);
            B = o->scale[1] * ( s * dy + c * dx);
            Pp = o->scale[0] * ( c * dx + s * dy);
            Qq = o->scale[1] * (-s * dx + c * dy);
            V0 = -o->pos[0] * dy + o->pos[1] * dx;
            U0 =  o->pos[0] * dx + o->pos[1] * dy;
            av = (A >= 0 ? A : -A) + (B >= 0 ? B : -B);
            au = (Pp >= 0 ? Pp : -Pp) + (Qq >= 0 ? Qq : -Qq);
            if (V0 + av * 0.5f < seg_lo || V0 - av * 0.5f > seg_hi)
                continue;
            umin_i = U0 - au * 0.5f;
            umax_i = U0 + au * 0.5f;
            if (umax_i - umin_i < 1e-4f) continue;
            if (umax_i <= un + 1e-3f) continue;
            g_rhi->draw_item(SLR_PROG_PFLAT, slot, o->mesh, 1);
            slot++;
        }
    }
    /* 深度纹理绑采样单元（GL TEXTURE2 / D3D11 t1），帧内持续有效：
     * 后续 desc_bind_tex 只动 TEXTURE1/t0 不冲突 */
    g_rhi->shadow_bind_depth(p->rt_shadow);
    p->shadow_on = 1;
    return 1;
}

/* 5 渲染层整理数据（真正实现，多相机）：
 *   逐活动相机（depth 升序）收集可见对象：每相机先不透明（queue 升序、
 *   z 升序：近→远，z 同按材质键 prog+tex_desc——同材质相邻成批），
 *   再透明（queue 升序、z 降序：远→近，序敏感不加材质键）；
 *   透明段后追加深影绘制项（castShadow 对象 + 有光源时生成，2D 投影：
 *   背离光源偏移 0.10、放大 1.15、黑 0.35 alpha、z = 物体 z + 0.01
 *   排序在物体之前绘制）。items 布局：
 *   [cam0 不透明|cam0 透明|cam1 不透明|cam1 透明|...]
 *   区间记录于 cam_ranges[bit]；slot = 数组下标 = PerDraw UBO 槽位 */
static int stage_assemble_impl(SlrPipeline* p)
{
    int ci, i, slot;
    float sh_dir[2], sh_pos[2];
    int sh_has = 0, sh_has_pos = 0;
    p->last_stage = 5;
    p->item_count = 0;
    p->opaque_count = 0;
    /* 阴影光源（帧级一次）：平行光方向优先，否则聚光位置 */
    sh_has = light_pick_shadow(p, sh_dir, &sh_has_pos, sh_pos);
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        SlrCamera* c = &p->cameras[bit];
        SlrCamRange* rg = &p->cam_ranges[bit];
        float proj[16], model[16];
        int start, start_t;
        mat4_ortho(proj, c->cam_l, c->cam_r, c->cam_b, c->cam_t, -1.0f, 1.0f);
        /* 先收不透明 */
        start = p->item_count;
        for (i = 0; i < SLR_MAX_OBJECTS && p->item_count < SLR_MAX_OBJECTS; i++)
        {
            SlrObject* o = &p->objects[i];
            if (!o->used || o->queue >= 2500) continue;
            if (!(o->cull_cams & (1 << bit))) continue;
            {
                SlrDrawItem* it = &p->items[p->item_count];
                memset(it, 0, sizeof(SlrDrawItem));
                it->obj = i;
                it->queue = o->queue; it->layer = o->layer; it->z = o->pos[2];
                it->cam = bit;
                it->tex_desc = -1;   /* 阶段 6 分配描述符槽；未跑阶段 6 时不误绑槽 0 */
                /* v3.5：全材质路由固化编译槽（HLSL 单源 -> GLSL330/ESSL300/
                 * DXBC，5 效果 × flat/tex 变体）；内建 PFLAT/PTEX/PHONG_*
                 * 保留为 VK 降级目标与阴影项专用（阴影固定 PFLAT）*/
                it->prog = SLR_PROG_GEN_SLOT(o->material, o->texture ? 0 : 1);
                mat4_model2d(model, o->pos[0], o->pos[1], o->pos[2], o->rot_z, o->scale[0], o->scale[1]);
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
            SlrObject* o = &p->objects[i];
            if (!o->used || o->queue < 2500) continue;
            if (!(o->cull_cams & (1 << bit))) continue;
            {
                SlrDrawItem* it = &p->items[p->item_count];
                memset(it, 0, sizeof(SlrDrawItem));
                it->obj = i;
                it->queue = o->queue; it->layer = o->layer; it->z = o->pos[2];
                it->cam = bit;
                it->tex_desc = -1;   /* 阶段 6 分配描述符槽；未跑阶段 6 时不误绑槽 0 */
                /* v3.5：全材质路由固化编译槽（HLSL 单源 -> GLSL330/ESSL300/
                 * DXBC，5 效果 × flat/tex 变体）；内建 PFLAT/PTEX/PHONG_*
                 * 保留为 VK 降级目标与阴影项专用（阴影固定 PFLAT）*/
                it->prog = SLR_PROG_GEN_SLOT(o->material, o->texture ? 0 : 1);
                mat4_model2d(model, o->pos[0], o->pos[1], o->pos[2], o->rot_z, o->scale[0], o->scale[1]);
                mat4_mul(it->mvp, proj, model);
                p->item_count++;
            }
        }
        /* 投影阴影项（v3.4）：castShadow 对象的 2D 投影 quad —— 沿
         * "背离光源"方向偏移 0.10、放大 1.15、黑色 alpha 0.35。
         * z = 物体 z - 0.01（深度夹层）：阴影比本体略远（透明段远→近
         * + queue 2500 都保证先于本体绘制），比 z 更小的接收面（地面）
         * 近（深度测试 LESS 通过）；本体遮挡自己的阴影（阴影深度大于
         * 本体写入深度 -> 在本体像素上被剔除）。聚光（点源）时方向逐
         * 物体归一化（灯摇晃 -> 阴影跟随）；无光源不生成。
         * N2a：shadow map 已启用（阶段 4.5 已渲深度图 + shader 采样
         * PCF）时跳过本黑斑路径（shadowQuality=0 的回退保留）*/
        if (sh_has && !p->shadow_on)
        {
            for (i = 0; i < SLR_MAX_OBJECTS && p->item_count < SLR_MAX_OBJECTS; i++)
            {
                SlrObject* o = &p->objects[i];
                SlrDrawItem* it;
                float dx, dy, len, off, cx, cy, zdepth;
                if (!o->used || !o->visible || !o->cast_shadow) continue;
                if (!(o->cull_cams & (1 << bit))) continue;
                dx = sh_dir[0]; dy = sh_dir[1];
                if (sh_has_pos)
                {
                    dx = o->pos[0] - sh_pos[0];
                    dy = o->pos[1] - sh_pos[1];
                    len = sqrtf(dx * dx + dy * dy);
                    if (len < 1e-5f) continue;   /* 与光源重合：无明确投影方向 */
                    dx /= len; dy /= len;
                }
                off = 0.10f + 0.12f * (o->scale[0] > o->scale[1] ? o->scale[0] : o->scale[1]);
                cx = o->pos[0] + dx * off;
                cy = o->pos[1] + dy * off;
                it = &p->items[p->item_count];
                memset(it, 0, sizeof(SlrDrawItem));
                it->obj = i;
                it->queue = 2500; it->layer = o->layer;
                it->z = o->pos[2] - 0.01f;   /* 透明排序键：略"远"于本体 */
                it->cam = bit;
                it->tex_desc = -1;
                it->is_shadow = 1;
                it->prog = SLR_PROG_PFLAT;   /* 阴影为纯色黑 quad（光照下仍黑）*/
                /* 深度夹层钳取 [-0.99, -0.01]：恒在 z=0 本体之下、
                 * z<-0.01 接收面之上、且 ndc ∈ [0, 0.99] 四后端有效 */
                zdepth = it->z;
                if (zdepth > -0.01f) zdepth = -0.01f;
                if (zdepth < -0.99f) zdepth = -0.99f;
                mat4_model2d(model, cx, cy, zdepth, 0.0f,
                             o->scale[0] * 1.15f, o->scale[1] * 1.15f);
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

/* 6 向 GPU 传入渲染数据（PerDraw 常量缓冲批量上传 + 光照块 + 纹理描述符表写入） */
static int stage_upload_render_data(SlrPipeline* p)
{
    int i;
    p->last_stage = 6;
    memset(&s_perdraw, 0, sizeof(s_perdraw));
    for (i = 0; i < p->item_count; i++)
    {
        SlrObject* o = &p->objects[p->items[i].obj];
        float c, s, *w;
        memcpy(s_perdraw.mvp[i], p->items[i].mvp, sizeof(p->items[i].mvp));
        if (p->items[i].is_shadow)
        {
            /* 阴影项：固定黑色 alpha 0.35（本体色/高光/wmat 不参与）*/
            s_perdraw.color[i][0] = 0.0f;
            s_perdraw.color[i][1] = 0.0f;
            s_perdraw.color[i][2] = 0.0f;
            s_perdraw.color[i][3] = 0.35f;
            continue;
        }
        memcpy(s_perdraw.color[i], o->color, sizeof(o->color));
        p->upload_count += 2;   /* MVP + 颜色 */
        /* 光照用 2D 世界仿射（与 mat4_model2d 同源）：
         * 2x2 旋转缩放 + 平移 + 物体朝向法线 (cos, sin) */
        c = cosf(o->rot_z);
        s = sinf(o->rot_z);
        w = s_perdraw.wmat[i];
        w[0] = c * o->scale[0]; w[1] = -s * o->scale[1];
        w[2] = s * o->scale[0]; w[3] =  c * o->scale[1];
        w[4] = o->pos[0];       w[5] = o->pos[1];
        w[6] = c;               w[7] = s;
        /* Phong 高光参数（v3.4；不计 upload_count —— 整块 PerDraw 一次上传，
         * 保持 A2 uploads 断言字节级兼容）*/
        s_perdraw.spec[i][0] = o->spec_str;
        s_perdraw.spec[i][1] = o->spec_shin;
    }
    g_rhi->upload_perdraw(&s_perdraw, (int)sizeof(SlrPerDraw));
    /* 帧级光照块：环境光 + 首个平行光 + 首个聚光（PFLAT/PTEX 消费）*/
    {
        SlrLightBlock lb;
        light_build_block(p, &lb);
        g_rhi->upload_lights(&lb, (int)sizeof(lb));
    }
    /* 纹理描述符表：PTEX/PHONG_TEX/gen-TEX 绘制项的纹理写入描述符槽
     * （同纹理查重复用），绘制项记录槽号——draw_item 不再携带资源指针。
     * v3.5：固化 gen 槽偶数下标 = TEX 变体（SLR_GEN_VARIANT_TEX=0），
     * 与内建 TEX 槽同一描述符表，VK 降级 PTEX 消费同表 */
    memset(&p->descs, 0, sizeof(p->descs));
    for (i = 0; i < p->item_count; i++)
    {
        SlrDrawItem* it = &p->items[i];
        it->tex_desc = -1;
        if (it->prog == SLR_PROG_PTEX || it->prog == SLR_PROG_PHONG_TEX
            || (it->prog >= SLR_PROG_GEN_BASE && !((it->prog - SLR_PROG_GEN_BASE) & 1)))
        {
            SlrTexRes* t = tex_from_handle(p->objects[it->obj].texture);
            void* res = t ? t->rhi_tex : NULL;
            int d;
            for (d = 0; d < p->descs.tex_count; d++)
                if (p->descs.tex[d].res == res) break;    /* 同纹理复用槽 */
            if (d == p->descs.tex_count)
            {
                if (d >= SLR_DESC_TEX_SLOTS) continue;    /* 槽满：该绘制项降级纯色 */
                p->descs.tex[d].res = res;
                p->descs.tex[d].used = 1;
                p->descs.tex_count++;
                g_rhi->desc_write_tex(d, res);
            }
            it->tex_desc = d;
        }
    }
    return 1;
}

static void draw_one_item(SlrPipeline* p, SlrDrawItem* it)
{
    SlrObject* o = &p->objects[it->obj];
    /* 纹理绑定在批头（desc_bind_tex，见阶段 9 分块循环）——
     * 绑定与绘制分离：批内所有项共享一次纹理绑定。
     * 逐项路径（透明段序敏感，不合批）：单实例 draw */
    g_rhi->draw_item(it->prog, it->slot, o->mesh, 1);
    p->draw_calls++;
    p->instance_total++;
    p->layers_mask |= (1 << it->layer);
}

/* 批分块辅助：从 i 到 end 找出与 items[i] 同材质（prog + 纹理描述符槽）
 * 的连续区间——一个批 = 一次纹理绑定（Batching：状态级合批）。 */
static int batch_end(SlrDrawItem* items, int i, int end)
{
    int prog = items[i].prog, tex = items[i].tex_desc, j = i;
    while (j < end && items[j].prog == prog && items[j].tex_desc == tex) j++;
    return j;
}

/* 7 shader 分块渲染（不透明段，多相机：逐相机 视口/清屏 -> 材质分批绘制） */
static int stage_render_shader_chunks(SlrPipeline* p)
{
    int ci;
    p->last_stage = 7;
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        SlrCamera* c = &p->cameras[bit];
        SlrCamRange* rg = &p->cam_ranges[bit];
        int i = rg->start, end = rg->start + rg->n_opaque;
        /* RHI：相机视口 + 可选局部清屏（GL: scissor / D3D11: 清屏 quad）*/
        g_rhi->camera_begin(p->rt_scene, c->vp_x, c->vp_y, c->vp_w, c->vp_h,
                            p->h, c->clear_flags, c->clear_color);
        g_rhi->set_state(0);
        while (i < end)
        {
            int j = batch_end(p->items, i, end);
            p->program_switches++;
            /* 批头绑定一次纹理描述符（批内同材质共享，SetPass 级合批）*/
            g_rhi->desc_bind_tex(p->items[i].tex_desc);
            /* N1 GPU 实例化：批内按 mesh 相同 + PerDraw 槽连续递增 RLE
             * 分段，每段一次 instanced draw（实例 i = 槽 base+i，VS 槽
             * 索引 = base + InstanceID；段上限 64 槽 = PerDraw 容量）。
             * 阶段 5 排序在前、赋槽在后（slot=数组下标），同材质连续段
             * 槽天然连续，RLE 合批率稳定。段内 layers_mask 逐项照记 */
            for (; i < j; )
            {
                int mesh = p->objects[p->items[i].obj].mesh;
                int base = p->items[i].slot, n = 1, m;
                while (i + n < j
                    && p->objects[p->items[i + n].obj].mesh == mesh
                    && p->items[i + n].slot == base + n
                    && base + n < 64)
                    n++;
                g_rhi->draw_item(p->items[i].prog, base, mesh, n);
                p->draw_calls++;
                p->instance_total += n;
                p->opaque_draws++;
                for (m = 0; m < n; m++)
                    p->layers_mask |= (1 << p->items[i + m].layer);
                i += n;
            }
            p->chunk_count++;    /* 批计数（= 状态切换次数）*/
        }
    }
    return 1;
}

/* 8 核心更新时间 */
static int stage_update_core_time(SlrPipeline* p)
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

/* 9 shader 分段渲染（透明段：混合开、深度写关、后→前；多相机逐相机执行；
 * 绘制次序按深度排序不变（合批不得改变混合次序），材质分块只最小化
 * 绑定次数——块内纹理绑定一次，逐项仍按序绘制） */
static int stage_render_shader_segments(SlrPipeline* p)
{
    int ci;
    p->last_stage = 9;
    for (ci = 0; ci < p->active_cam_count; ci++)
    {
        int bit = p->active_cams[ci];
        SlrCamera* c = &p->cameras[bit];
        SlrCamRange* rg = &p->cam_ranges[bit];
        int i = rg->start + rg->n_opaque, end = rg->start + rg->n_opaque + rg->n_trans;
        g_rhi->camera_begin(p->rt_scene, c->vp_x, c->vp_y, c->vp_w, c->vp_h,
                            p->h, 0, c->clear_color);   /* 透明段不清屏 */
        g_rhi->set_state(1);
        while (i < end)
        {
            int j = batch_end(p->items, i, end);
            p->program_switches++;
            /* 批头绑定一次纹理描述符（绘制次序仍逐项按深度序）*/
            g_rhi->desc_bind_tex(p->items[i].tex_desc);
            for (; i < j; i++)
            {
                draw_one_item(p, &p->items[i]);
                p->transparent_draws++;
            }
            p->chunk_count++;    /* 批计数（= 状态切换次数）*/
        }
    }
    return 1;
}

/* 10 整理渲染后的图层（簿记；渲染状态由后续 pass 自行设定） */
static int stage_assemble_rendered_layers(SlrPipeline* p)
{
    p->last_stage = 10;
    return 1;
}

/* 11 后处理（RHI：scene -> post，enabled=0 纯拷贝） */
static int stage_post_process(SlrPipeline* p)
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
static int stage_integrate_layers(SlrPipeline* p)
{
    p->last_stage = 12;
    g_rhi->blit(p->rt_final, p->rt_post, p->w, p->h);
    p->program_switches++;
    p->draw_calls++;
    return 1;
}

/* 13 输出最终渲染 renderTexture（RHI 回读：top-down RGBA8） */
static int stage_output_render_texture(SlrPipeline* p, int64_t dst_ptr)
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
        SlrPipeline* p;                                       \
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
    SlrPipeline* p;
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
    SlrPipeline* p;
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
    SlrPipeline* p;
    int ok;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (!dst_ptr) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    ok = stage_begin_frame(p, time)
      && stage_prepare_materials(p)
      && stage_early_update(p)
      && stage_cull_layers(p)
      && stage_shadow_pass(p)            /* 4.5 N2a：shadow 深度 pass */
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
    SlrPipeline* p = pipe_from_handle(h);
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
    case SLR_STAT_INSTANCE_COUNT:    return p->instance_total;
    default: set_error(SLR_E_BAD_PARAM); return 0;
    }
}
