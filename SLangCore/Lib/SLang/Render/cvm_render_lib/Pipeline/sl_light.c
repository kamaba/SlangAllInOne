/* =========================================================================
 * sl_light.c —— 管线光照槽表（对应 SL 侧 Camera/Light.sl）
 *
 * 光照状态为管线级（SlrPipeline.lights[SLR_MAX_LIGHTS] + ambient）：
 *   - SL 侧 Light.applyTo 经 slr_light_set 写入槽（参数经 Memory 块传递，
 *     布局见 vm_sl_render.h v3.3 注释）；
 *   - 阶段 6（sl_pipeline.c）调用 light_build_block 组装帧级光照块
 *     （环境光 + 首个启用的平行光 + 首个启用的聚光），经 RHI
 *     upload_lights 上传（GL/GLES UBO 绑定点 1 / D3D11 寄存器 b4）；
 *   - 着色器侧 PFLAT/PTEX 逐像素消费：平行光按物体朝向 ndl、聚光按
 *     世界坐标锥角 + 距离衰减（世界坐标经 PerDraw.wmat 重建）。
 * 默认态（无光照 + ambient=1.0）输出与无光照版逐字节一致——跨后端
 * 同效果测试不受影响。
 * ========================================================================= */
#include "sl_render_internal.h"

/* params 布局（vm_sl_render.h v3.7 注释为准）：
 *   平行光 type=0：[dirX, dirY, r, g, b, intensity, shadowQuality,
 *                   shadowBias, shadowStrength, shadowCascades]        10 float
 *     （shadowQuality：0=旧 2D 投影黑斑；1=shadow map——N2a，仅平行光；
 *       shadowBias/Strength/Cascades：N2b 覆盖（0 = 管线默认
 *       0.002 / 0.35 / 单级；cascades 支持 1 与 4——4 = CSM）
 *   聚光   type=2：[posX, posY, dirX, dirY, angleDeg, range, r, g, b, intensity] 10 float */
int slr_light_set(int64_t h, int slot, int type, int64_t params_ptr)
{
    SlrPipeline* p;
    const float* q;
    SlrLight* L;
    float len;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (slot < 0 || slot >= SLR_MAX_LIGHTS || !params_ptr)
    { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    if (type != SLR_LIGHT_DIRECTIONAL && type != SLR_LIGHT_SPOT)
    { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }

    q = (const float*)(intptr_t)params_ptr;
    L = &p->lights[slot];
    memset(L, 0, sizeof(SlrLight));
    L->used = 1;
    L->type = type;

    if (type == SLR_LIGHT_DIRECTIONAL)
    {
        len = sqrtf(q[0] * q[0] + q[1] * q[1]);
        if (len < 1e-5f) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
        L->dir[0] = q[0] / len;
        L->dir[1] = q[1] / len;
        L->color[0] = q[2]; L->color[1] = q[3]; L->color[2] = q[4];
        L->intensity = q[5];
        /* N2a：shadow map 质量（仅平行光有意义；1=启用）*/
        if (q[6] >= 1.0f) L->shadow_quality = 1;
        /* N2b：bias / 强度 / 级联数覆盖（0 = 管线默认）*/
        L->shadow_bias_ovr = q[7];
        L->shadow_str_ovr = q[8];
        L->shadow_cascades = (q[9] >= 3.5f) ? 4 : 1;
    }
    else
    {
        float ang = q[4];
        L->pos[0] = q[0]; L->pos[1] = q[1];
        len = sqrtf(q[2] * q[2] + q[3] * q[3]);
        if (len < 1e-5f) { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
        L->dir[0] = q[2] / len;
        L->dir[1] = q[3] / len;
        /* 锥半角夹取 [1°, 89°]：着色器 smoothstep 锥边平滑需要
         * cos(edge) 与 1 之间留出余量，0°/90° 退化为除零/全开 */
        if (ang < 1.0f) ang = 1.0f;
        if (ang > 89.0f) ang = 89.0f;
        L->cos_angle = cosf(ang * 0.01745329251994329577f);
        L->range = q[5];
        if (L->range < 0.01f) L->range = 0.01f;
        L->color[0] = q[6]; L->color[1] = q[7]; L->color[2] = q[8];
        L->intensity = q[9];
    }
    if (L->intensity < 0.0f) L->intensity = 0.0f;
    rhi_exit();
    return 1;
}

int slr_light_clear(int64_t h, int slot)
{
    SlrPipeline* p;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (slot < 0 || slot >= SLR_MAX_LIGHTS)
    { set_error(SLR_E_BAD_PARAM); rhi_exit(); return 0; }
    memset(&p->lights[slot], 0, sizeof(SlrLight));
    rhi_exit();
    return 1;
}

int slr_light_count(int64_t h)
{
    SlrPipeline* p;
    int i, n = 0;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    for (i = 0; i < SLR_MAX_LIGHTS; i++) if (p->lights[i].used) n++;
    rhi_exit();
    return n;
}

int slr_light_set_ambient(int64_t h, float ambient)
{
    SlrPipeline* p;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (ambient < 0.0f) ambient = 0.0f;
    if (ambient > 1.0f) ambient = 1.0f;
    p->ambient = ambient;
    rhi_exit();
    return 1;
}

/* 帧级光照块组装：环境光 + 首个启用的平行光 + 首个启用的聚光
 * （颜色预乘强度；a 分量 1.0 = 启用）。阶段 6 每帧调用。 */
void light_build_block(SlrPipeline* p, SlrLightBlock* out)
{
    int i;
    memset(out, 0, sizeof(*out));
    out->ambient[0] = p->ambient;
    for (i = 0; i < SLR_MAX_LIGHTS; i++)
    {
        SlrLight* L = &p->lights[i];
        if (!L->used) continue;
        if (L->type == SLR_LIGHT_DIRECTIONAL && out->dir_color[3] < 0.5f)
        {
            out->dir_color[0] = L->color[0] * L->intensity;
            out->dir_color[1] = L->color[1] * L->intensity;
            out->dir_color[2] = L->color[2] * L->intensity;
            out->dir_color[3] = 1.0f;
            out->dir_dir[0] = L->dir[0];
            out->dir_dir[1] = L->dir[1];
        }
        if (L->type == SLR_LIGHT_SPOT && out->spot_color[3] < 0.5f)
        {
            out->spot_color[0] = L->color[0] * L->intensity;
            out->spot_color[1] = L->color[1] * L->intensity;
            out->spot_color[2] = L->color[2] * L->intensity;
            out->spot_color[3] = 1.0f;
            out->spot_pos_range[0] = L->pos[0];
            out->spot_pos_range[1] = L->pos[1];
            out->spot_pos_range[2] = L->range;
            out->spot_dir_cos[0] = L->dir[0];
            out->spot_dir_cos[1] = L->dir[1];
            out->spot_dir_cos[2] = L->cos_angle;
        }
    }
    /* N2a/N2b shadow 参数：stage_shadow_pass 已执行（阶段 4.5，先于本
     * 函数）时填 —— 光空间 VP（级联 0..3，列主）+ 开关/偏移/强度/纹素
     * + 跨后端深度值域还原（GL/GLES 硬件深度 *2-1）+ 级联 v 分段表 */
    if (p->shadow_on)
    {
        int d3d = (g_rhi && strcmp(g_rhi->name, "d3d11") == 0);
        int lv;
        memcpy(out->light_vp, p->shadow_light_vp[0], sizeof(float) * 16);
        memcpy(out->shadow_vp1, p->shadow_light_vp[1], sizeof(float) * 16);
        memcpy(out->shadow_vp2, p->shadow_light_vp[2], sizeof(float) * 16);
        memcpy(out->shadow_vp3, p->shadow_light_vp[3], sizeof(float) * 16);
        out->shadow_param[0] = 1.0f;                          /* enable */
        out->shadow_param[1] = p->shadow_bias;                /* bias   */
        out->shadow_param[2] = p->shadow_strength;            /* 强度    */
        out->shadow_param[3] = 1.0f / (float)p->shadow_map_size; /* texel */
        out->shadow_zxform[0] = d3d ? 1.0f : 2.0f;    /* 深度还原 scale  */
        out->shadow_zxform[1] = d3d ? 0.0f : -1.0f;   /* 深度还原 bias   */
        out->shadow_zxform[2] = d3d ? -1.0f : 1.0f;   /* 行 v scale（D3D11 RT 行序镜像）*/
        out->shadow_zxform[3] = d3d ? 1.0f : 0.0f;   /* 行 v bias        */
        /* N2b：级联 v 分段（级联 i 覆盖 [split[i], split[i+1]]；
         * 单级 = [vmin, vmax] 全段，split[1..3] 填 vmax 让 shader 级联
         * 选择天然落 0 级——N2a 语义零变化）*/
        for (lv = 0; lv < 4; lv++)
            out->shadow_split[lv] = p->shadow_split[lv];
        out->shadow_info[0] = (float)p->shadow_cascades;
        out->shadow_info[1] = p->shadow_split[4];   /* 末级右端 v */
    }
}

/* 阴影投射光源查询（阶段 5）：首个平行光优先 —— 平行光 dir 为
 * 表面 -> 光源方向，阴影偏移方向 = -dir（背离光源）；无平行光时
 * 取首个聚光（has_pos=1，方向 = normalize(物体位置 - 光源位置)，
 * 由调用方逐物体计算）。无任何光源返回 0（不生成阴影）。 */
int light_pick_shadow(SlrPipeline* p, float* dir_out, int* has_pos_out,
                      float* pos_out)
{
    int i;
    *has_pos_out = 0;
    dir_out[0] = -1.0f; dir_out[1] = 0.0f;
    pos_out[0] = 0.0f; pos_out[1] = 0.0f;
    for (i = 0; i < SLR_MAX_LIGHTS; i++)
    {
        SlrLight* L = &p->lights[i];
        if (!L->used) continue;
        if (L->type == SLR_LIGHT_DIRECTIONAL)
        {
            dir_out[0] = -L->dir[0];
            dir_out[1] = -L->dir[1];
            return 1;
        }
    }
    for (i = 0; i < SLR_MAX_LIGHTS; i++)
    {
        SlrLight* L = &p->lights[i];
        if (!L->used) continue;
        if (L->type == SLR_LIGHT_SPOT)
        {
            pos_out[0] = L->pos[0];
            pos_out[1] = L->pos[1];
            *has_pos_out = 1;
            return 1;
        }
    }
    return 0;
}

/* N2a shadow map 光源查询（阶段 4.5 / 阶段 5）：返回首个
 * shadow_quality>=1 的平行光索引（dir_out 输出其方向，表面->光源）；
 *无则返回 -1（阶段 5 照常生成 2D 投影黑斑回退）。 */
int light_pick_shadowmap(SlrPipeline* p, float* dir_out)
{
    int i;
    for (i = 0; i < SLR_MAX_LIGHTS; i++)
    {
        SlrLight* L = &p->lights[i];
        if (L->used && L->type == SLR_LIGHT_DIRECTIONAL && L->shadow_quality >= 1)
        {
            dir_out[0] = L->dir[0];
            dir_out[1] = L->dir[1];
            return i;
        }
    }
    return -1;
}
