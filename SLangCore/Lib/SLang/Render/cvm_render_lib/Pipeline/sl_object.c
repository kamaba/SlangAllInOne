/* =========================================================================
 * sl_object.c —— 场景对象（对应 SL 侧 UnityRenderObject）
 *
 * 对象属性：网格类型 / 可见性 / layer / 渲染队列 / 位置 / 旋转 / 缩放 /
 * 颜色 / 纹理绑定 / 动画模式。句柄 1 起始，仅持有管线内下标数据，
 * GL 绘制消费见 Pipeline/sl_pipeline.c。
 * ========================================================================= */
#include "sl_render_internal.h"

static SlrObject* obj_from_handle(SlrPipeline* p, int64_t oh, int* idx_out)
{
    int i = (int)(oh - 1);
    if (oh <= 0 || i >= SLR_MAX_OBJECTS || !p->objects[i].used) return NULL;
    if (idx_out) *idx_out = i;
    return &p->objects[i];
}

int64_t slr_object_create(int64_t h, int mesh_kind)
{
    SlrPipeline* p;
    int i;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    /* mesh_kind：0 三角 / 1 四边（静态网格）；4..4+SLR_CUSTOM_MESHES-1
     * 动态网格槽（slr_mesh_upload 上传的三角形列表）*/
    if ((mesh_kind != SLR_MESH_TRIANGLE && mesh_kind != SLR_MESH_QUAD)
        && (mesh_kind < 4 || mesh_kind >= 4 + SLR_CUSTOM_MESHES))
    {
        set_error(SLR_E_BAD_PARAM);
        rhi_exit();
        return 0;
    }
    for (i = 0; i < SLR_MAX_OBJECTS; i++)
    {
        SlrObject* o;
        if (p->objects[i].used) continue;
        o = &p->objects[i];
        memset(o, 0, sizeof(SlrObject));
        o->used = 1;
        o->mesh = mesh_kind;
        o->visible = 1;
        o->layer = 0;
        /* 对齐 Unity 渲染队列：三角默认不透明，四边形/动态网格默认透明 */
        o->queue = (mesh_kind == SLR_MESH_TRIANGLE) ? 2000 : 3000;
        o->scale[0] = 1.0f; o->scale[1] = 1.0f;
        o->color[0] = 1.0f; o->color[1] = 1.0f; o->color[2] = 1.0f; o->color[3] = 1.0f;
        o->texture = 0;
        rhi_exit();
        return (int64_t)(i + 1);
    }
    set_error(SLR_E_LIMIT);
    rhi_exit();
    return 0;
}

/* 动态网格上传（全局资源通道，与纹理同级）：verts_ptr 指向三角形
 * 列表（pos2+uv2 交错，stride 16B，顶行 GL 语义 NDC），对象 mesh_kind
 * = 4 + slot 引用该槽。可每帧重复调用（GL/GLES/D3D11 重传整块，
 * VK 持久映射直写）。返回 1 成功 / 0 失败。 */
int slr_mesh_upload(int slot, int64_t verts_ptr, int vert_count)
{
    int ok;
    if (!rhi_enter()) return 0;
    if (slot < 0 || slot >= SLR_CUSTOM_MESHES || !verts_ptr ||
        vert_count <= 0 || vert_count > SLR_CUSTOM_MAX_VERTS)
    {
        set_error(SLR_E_BAD_PARAM);
        rhi_exit();
        return 0;
    }
    ok = g_rhi->mesh_upload(slot, (const float*)(intptr_t)verts_ptr, vert_count);
    rhi_exit();
    return ok;
}

int slr_object_destroy(int64_t h, int64_t obj)
{
    SlrPipeline* p;
    int idx = 0;
    if (!rhi_enter()) return 0;
    p = pipe_from_handle(h);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (!obj_from_handle(p, obj, &idx)) { set_error(SLR_E_OBJECT); rhi_exit(); return 0; }
    memset(&p->objects[idx], 0, sizeof(SlrObject));
    rhi_exit();
    return 1;
}

static int obj_set_common(int64_t h, int64_t obj, SlrPipeline** pp, SlrObject** oo, int* idx)
{
    if (!rhi_enter()) return 0;
    *pp = pipe_from_handle(h);
    if (!*pp) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    *oo = obj_from_handle(*pp, obj, idx);
    if (!*oo) { set_error(SLR_E_OBJECT); rhi_exit(); return 0; }
    return 1;
}

int slr_object_set_visible(int64_t h, int64_t obj, int visible)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->visible = visible ? 1 : 0;
    rhi_exit();
    return 1;
}

int slr_object_set_layer(int64_t h, int64_t obj, int layer)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (layer < 0 || layer > 31) { set_error(SLR_E_BAD_PARAM); return 0; }
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->layer = layer;
    rhi_exit();
    return 1;
}

int slr_object_set_queue(int64_t h, int64_t obj, int queue)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->queue = queue;
    rhi_exit();
    return 1;
}

int slr_object_set_position(int64_t h, int64_t obj, float x, float y, float z)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->pos[0] = x; o->pos[1] = y; o->pos[2] = z;
    rhi_exit();
    return 1;
}

int slr_object_set_rotation_z(int64_t h, int64_t obj, float rz)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->rot_z = rz;
    rhi_exit();
    return 1;
}

int slr_object_set_scale(int64_t h, int64_t obj, float sx, float sy)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->scale[0] = sx; o->scale[1] = sy;
    rhi_exit();
    return 1;
}

int slr_object_set_color(int64_t h, int64_t obj, float r, float g, float b, float a)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->color[0] = r; o->color[1] = g; o->color[2] = b; o->color[3] = a;
    rhi_exit();
    return 1;
}

int slr_object_set_texture(int64_t h, int64_t obj, int64_t tex)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    if (tex != 0 && !tex_from_handle(tex)) { set_error(SLR_E_TEXTURE); rhi_exit(); return 0; }
    o->texture = tex;
    rhi_exit();
    return 1;
}

int slr_object_set_animated(int64_t h, int64_t obj, int mode, float speed)
{
    SlrPipeline* p; SlrObject* o; int idx;
    if (!obj_set_common(h, obj, &p, &o, &idx)) return 0;
    o->anim_mode = (mode == SLR_ANIM_HUE_CYCLE) ? SLR_ANIM_HUE_CYCLE : SLR_ANIM_NONE;
    o->anim_speed = speed;
    rhi_exit();
    return 1;
}

int slr_object_count(int64_t h)
{
    SlrPipeline* p = pipe_from_handle(h);
    int i, n = 0;
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    for (i = 0; i < SLR_MAX_OBJECTS; i++) if (p->objects[i].used) n++;
    return n;
}
