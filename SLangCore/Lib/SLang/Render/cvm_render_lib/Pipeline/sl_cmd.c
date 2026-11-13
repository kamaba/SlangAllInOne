/* =========================================================================
 * sl_cmd.c —— 命令流执行器（对应 SL 侧 Pipeline/CommandBuffer.sl）
 *
 * D1 真录制（doc/03 §4.7 + doc/04 §3.6）：SL 侧 CommandBuffer 把渲染命令
 * 录进 opcode/args/floats 三段数组（录制期零后端调用），提交时按 SLMC
 * 布局打包成原生内存块，经 slr_cmd_execute_stream 整包传入；本文件解析
 * 命令流并逐 opcode 回放到当前 RHI 后端（g_rhi->* vtable，四后端同效果，
 * 零 vtable 改动）—— Unity 的「整理 -> 提交 -> 渲染」三段式：
 *   SL 录制（乱序也行）-> sortDrawItems 排序整理 -> executeCommandBuffer
 *   打包提交 -> 本执行器回放出像素（readback）。
 *
 * SLMC 命令流布局（stream_ptr 指向的块，小端）：
 *   偏移 0    i32  magic = 0x534C4D43 ('SLMC')
 *   偏移 4    i32  version = 1
 *   偏移 8    i32  commandCount
 *   偏移 12   i32  argOffset（args 段字节偏移，8 对齐）
 *   偏移 16   i32  floatOffset（floats 段字节偏移）
 *   偏移 20   (pad 4)
 *   偏移 24   i32[] opcodes[commandCount]
 *   argOffset   i64[] args（每命令消费个数由 opcode 决定，见 CMD_ARGS）
 *   floatOffset f32[] floats（每命令消费个数见 CMD_FLOATS）
 *
 * 可执行命令集（桥接 13 阶段管线的整数槽位世界；opcode 值与 SL 侧
 * ECommandOpcode 逐值一致）：
 *   SetRenderTargets  args[targetId x y w h clearFlags] floats[rgba]
 *                     -> camera_begin（目标 0=rt_scene 1=rt_post 2=rt_final；
 *                        坐标 GL 约定原点左下，target_h 取管线高）
 *   Clear             args[clearFlags] floats[rgba] -> 当前目标按已存视口再清
 *   SetTexture        args[descSlot texHandle] -> desc_write_tex（帧级写槽；
 *                     绘制项经 DrawItem.texDesc 绑槽，绑定与绘制分离）
 *   SetPerDraw        args[slot] floats[32] -> s_perdraw 槽位（mvp16+color4
 *                     +wmat8+spec4，mvp 列主序），置脏待 DrawItem 前整块上传
 *   DrawItem          args[prog slot mesh texDesc transparent queue]
 *                     floats[z]（z 仅供 SL 侧排序，回放不消费）
 *                     -> 脏则 upload_perdraw；set_state；desc_bind_tex；
 *                        draw_item（自包含命令：排序重排安全）
 *   PostProcess       args[enabled] floats[b s v] -> post_process(post<-scene)
 *   Blit              -> blit(final<-post)
 *   Readback          args[dstPtr] -> readback(final)
 * 其余 opcode（视口/剪刀/PSO/计算/屏障等 M0+ 资源世界命令）：记账跳过，
 * 不报错（前向兼容；args/floats 游标仍按固定表推进，不脱同步）。
 *
 * 帧级前置（回放开始）：s_perdraw / 描述符表清零 + 光照块组装上传
 * （沿用管线光照槽；无光照 + ambient=1.0 时输出与纯色路径逐字节一致）。
 * ========================================================================= */
#include "sl_render_internal.h"

/* ---- opcode 值表（与 SL 侧 ECommandOpcode 逐值一致，勿改动既有值）---- */
enum
{
    SLR_CMD_NOP = 0,
    SLR_CMD_SET_VIEWPORT,
    SLR_CMD_SET_SCISSOR,
    SLR_CMD_SET_RENDER_TARGETS,
    SLR_CMD_CLEAR,
    SLR_CMD_SET_PIPELINE_STATE,
    SLR_CMD_SET_COMPUTE_PIPELINE_STATE,
    SLR_CMD_SET_ROOT_SIGNATURE,
    SLR_CMD_SET_DESCRIPTOR_SET,
    SLR_CMD_SET_VERTEX_BUFFER,
    SLR_CMD_SET_INDEX_BUFFER,
    SLR_CMD_SET_CONSTANT_BUFFER,
    SLR_CMD_SET_TEXTURE,
    SLR_CMD_SET_SAMPLER,
    SLR_CMD_DRAW,
    SLR_CMD_DRAW_INDEXED,
    SLR_CMD_DRAW_PROCEDURAL,
    SLR_CMD_DRAW_MESH,
    SLR_CMD_DISPATCH,
    SLR_CMD_RESOURCE_BARRIER,
    SLR_CMD_COPY_BUFFER,
    SLR_CMD_COPY_TEXTURE,
    SLR_CMD_RESOLVE_TEXTURE,
    SLR_CMD_BEGIN_EVENT,
    SLR_CMD_END_EVENT,
    /* ---- 桥接扩展（13 阶段管线整数槽位世界）---- */
    SLR_CMD_SET_PER_DRAW = 25,
    SLR_CMD_DRAW_ITEM,
    SLR_CMD_POST_PROCESS,
    SLR_CMD_BLIT,
    SLR_CMD_READBACK,
    SLR_CMD_COUNT
};

/* 每 opcode 固定 args / floats 消费数（SL 录制侧与 C 回放侧的硬契约：
 * 录制方法必须恰好压入表定数量的参数，回放游标才能对齐） */
static const int CMD_ARGS[SLR_CMD_COUNT] =
{
    0,  /* Nop                   */
    4,  /* SetViewport           */
    4,  /* SetScissor            */
    6,  /* SetRenderTargets      */
    1,  /* Clear                 */
    1,  /* SetPipelineState      */
    1,  /* SetComputePipelineState */
    1,  /* SetRootSignature      */
    1,  /* SetDescriptorSet      */
    2,  /* SetVertexBuffer       */
    2,  /* SetIndexBuffer        */
    2,  /* SetConstantBuffer     */
    2,  /* SetTexture            */
    2,  /* SetSampler            */
    3,  /* Draw                  */
    4,  /* DrawIndexed           */
    2,  /* DrawProcedural        */
    2,  /* DrawMesh              */
    3,  /* Dispatch              */
    3,  /* ResourceBarrier       */
    2,  /* CopyBuffer            */
    2,  /* CopyTexture           */
    2,  /* ResolveTexture        */
    0,  /* BeginEvent            */
    0,  /* EndEvent              */
    1,  /* SetPerDraw（桥接）    */
    6,  /* DrawItem（桥接）      */
    1,  /* PostProcess（桥接）   */
    0,  /* Blit（桥接）          */
    1   /* Readback（桥接）      */
};

static const int CMD_FLOATS[SLR_CMD_COUNT] =
{
    0,  /* Nop                   */
    0,  /* SetViewport           */
    0,  /* SetScissor            */
    4,  /* SetRenderTargets      */
    4,  /* Clear                 */
    0,  /* SetPipelineState      */
    0,  /* SetComputePipelineState */
    0,  /* SetRootSignature      */
    0,  /* SetDescriptorSet      */
    0,  /* SetVertexBuffer       */
    0,  /* SetIndexBuffer        */
    0,  /* SetConstantBuffer     */
    0,  /* SetTexture            */
    0,  /* SetSampler            */
    0,  /* Draw                  */
    0,  /* DrawIndexed           */
    0,  /* DrawProcedural        */
    36, /* DrawMesh（model16+vp16+color4）*/
    0,  /* Dispatch              */
    0,  /* ResourceBarrier       */
    0,  /* CopyBuffer            */
    0,  /* CopyTexture           */
    0,  /* ResolveTexture        */
    0,  /* BeginEvent            */
    0,  /* EndEvent              */
    32, /* SetPerDraw（桥接）    */
    1,  /* DrawItem（桥接，z）   */
    3,  /* PostProcess（桥接）   */
    0,  /* Blit（桥接）          */
    0   /* Readback（桥接）      */
};

/* 绘制参数边界检查（draw_item 的槽位世界）：
 *   prog  0..SLR_PROG_COUNT-1；slot 0..SLR_MAX_OBJECTS-1（PerDraw 槽）
 *   mesh  0..3 静态网格 / 4..4+SLR_CUSTOM_MESHES-1 动态网格 */
static int cmd_prog_valid(int prog)
{
    return prog >= 0 && prog < SLR_PROG_COUNT;
}

static int cmd_mesh_valid(int mesh)
{
    return mesh >= 0 && mesh < 4 + SLR_CUSTOM_MESHES;
}

SLR_API int slr_cmd_execute_stream(int64_t pipe, int64_t stream_ptr,
                                   int32_t command_count)
{
    SlrPipeline* p;
    const unsigned char* base;
    const int32_t* opcodes;
    const int64_t* args;
    const float* floats;
    int32_t magic, version, count, arg_off, float_off;
    int i, ai, fi;
    /* 回放器帧内状态 */
    SlrRhiTarget* targets[3];
    SlrRhiTarget* cur_target;
    int vp_x, vp_y, vp_w, vp_h;
    int perdraw_dirty = 0;
    int last_prog = -1;

    if (!rhi_enter()) return 0;
    p = pipe_from_handle(pipe);
    if (!p) { set_error(SLR_E_PIPELINE); rhi_exit(); return 0; }
    if (!stream_ptr) { set_error_detail(SLR_E_BAD_PARAM, "null stream"); rhi_exit(); return 0; }

    base = (const unsigned char*)(intptr_t)stream_ptr;
    memcpy(&magic,    base + 0,  4);
    memcpy(&version,  base + 4,  4);
    memcpy(&count,    base + 8,  4);
    memcpy(&arg_off,  base + 12, 4);
    memcpy(&float_off, base + 16, 4);
    if (magic != 0x534C4D43 || version != 1 || count < 0)
    {
        set_error_detail(SLR_E_BAD_PARAM, "bad SLMC header");
        rhi_exit();
        return 0;
    }
    if (command_count >= 0 && count != command_count)
    {
        set_error_detail(SLR_E_BAD_PARAM, "command count mismatch");
        rhi_exit();
        return 0;
    }
    if (arg_off < 24 || float_off < arg_off)
    {
        set_error_detail(SLR_E_BAD_PARAM, "bad section offsets");
        rhi_exit();
        return 0;
    }
    opcodes = (const int32_t*)(base + 24);
    args    = (const int64_t*)(base + arg_off);
    floats  = (const float*)(base + float_off);

    /* 帧级前置：PerDraw / 描述符表清零 + 光照块组装上传（沿用管线光照
     * 槽；无光照 + ambient=1.0 时输出与纯色路径逐字节一致）*/
    memset(&s_perdraw, 0, sizeof(s_perdraw));
    memset(&p->descs, 0, sizeof(p->descs));
    {
        SlrLightBlock lb;
        light_build_block(p, &lb);
        g_rhi->upload_lights(&lb, (int)sizeof(lb));
    }
    p->draw_calls = 0; p->opaque_draws = 0; p->transparent_draws = 0;
    p->program_switches = 0; p->chunk_count = 0; p->upload_count = 0;
    p->layers_mask = 0;
    p->visible_count = 0; p->culled_count = 0;

    targets[0] = p->rt_scene;
    targets[1] = p->rt_post;
    targets[2] = p->rt_final;
    cur_target = p->rt_scene;
    vp_x = 0; vp_y = 0; vp_w = p->w; vp_h = p->h;

    ai = 0; fi = 0;
    for (i = 0; i < count; i++)
    {
        int op = opcodes[i];
        if (op < 0 || op >= SLR_CMD_COUNT) op = SLR_CMD_NOP;  /* 未知按 Nop */

        switch (op)
        {
        case SLR_CMD_SET_RENDER_TARGETS:
        {
            int tid = (int)args[ai];
            int x = (int)args[ai + 1], y = (int)args[ai + 2];
            int w = (int)args[ai + 3], h = (int)args[ai + 4];
            int flags = (int)args[ai + 5];
            float rgba[4];
            int k;
            for (k = 0; k < 4; k++) rgba[k] = floats[fi + k];
            if (tid < 0 || tid > 2) tid = 0;
            cur_target = targets[tid];
            vp_x = x; vp_y = y; vp_w = w; vp_h = h;
            /* 绑定 + 视口 + 可选清屏（与阶段 7/9 的 camera_begin 同源）*/
            g_rhi->camera_begin(cur_target, x, y, w, h, p->h, flags, rgba);
            break;
        }
        case SLR_CMD_CLEAR:
        {
            int flags = (int)args[ai];
            float rgba[4];
            int k;
            for (k = 0; k < 4; k++) rgba[k] = floats[fi + k];
            /* 用已存视口对当前目标再清（flags 0 = 仅重绑不清）*/
            g_rhi->camera_begin(cur_target, vp_x, vp_y, vp_w, vp_h,
                                p->h, flags, rgba);
            break;
        }
        case SLR_CMD_SET_TEXTURE:
        {
            int slot = (int)args[ai];
            int64_t texh = args[ai + 1];
            SlrTexRes* t = tex_from_handle(texh);
            void* res = t ? t->rhi_tex : NULL;
            if (slot >= 0 && slot < SLR_DESC_TEX_SLOTS)
            {
                p->descs.tex[slot].res = res;
                p->descs.tex[slot].used = 1;
                if (slot + 1 > p->descs.tex_count) p->descs.tex_count = slot + 1;
                g_rhi->desc_write_tex(slot, res);
            }
            break;
        }
        case SLR_CMD_SET_PER_DRAW:
        {
            int slot = (int)args[ai];
            if (slot >= 0 && slot < SLR_MAX_OBJECTS)
            {
                int k;
                for (k = 0; k < 16; k++) s_perdraw.mvp[slot][k]  = floats[fi + k];
                for (k = 0; k < 4;  k++) s_perdraw.color[slot][k] = floats[fi + 16 + k];
                for (k = 0; k < 8;  k++) s_perdraw.wmat[slot][k]  = floats[fi + 20 + k];
                for (k = 0; k < 4;  k++) s_perdraw.spec[slot][k]  = floats[fi + 28 + k];
                perdraw_dirty = 1;
                p->upload_count += 2;   /* MVP + 颜色（与阶段 6 记账口径一致）*/
            }
            break;
        }
        case SLR_CMD_DRAW_ITEM:
        {
            int prog = (int)args[ai];
            int slot = (int)args[ai + 1];
            int mesh = (int)args[ai + 2];
            int texd = (int)args[ai + 3];
            int transp = (int)args[ai + 4];
            /* args[ai+5] = queue、floats[fi] = z：排序已在 SL 侧完成，回放不消费 */
            if (cmd_prog_valid(prog) && slot >= 0 && slot < SLR_MAX_OBJECTS
                && cmd_mesh_valid(mesh))
            {
                if (perdraw_dirty)
                {
                    g_rhi->upload_perdraw(&s_perdraw, (int)sizeof(SlrPerDraw));
                    perdraw_dirty = 0;
                }
                g_rhi->set_state(transp ? 1 : 0);
                g_rhi->desc_bind_tex(texd);   /* -1 = 清绑定（与批头行为一致）*/
                g_rhi->draw_item(prog, slot, mesh);
                p->draw_calls++;
                if (transp) p->transparent_draws++;
                else p->opaque_draws++;
                if (prog != last_prog) { p->program_switches++; last_prog = prog; }
            }
            break;
        }
        case SLR_CMD_POST_PROCESS:
        {
            int enabled = (int)args[ai];
            g_rhi->post_process(p->rt_post, p->rt_scene, p->w, p->h, enabled,
                                floats[fi], floats[fi + 1], floats[fi + 2]);
            p->program_switches++;
            p->draw_calls++;
            break;
        }
        case SLR_CMD_BLIT:
            g_rhi->blit(p->rt_final, p->rt_post, p->w, p->h);
            p->program_switches++;
            p->draw_calls++;
            break;
        case SLR_CMD_READBACK:
        {
            int64_t dst = args[ai];
            if (dst) g_rhi->readback(p->rt_final, p->w, p->h, dst);
            break;
        }
        default:
            /* 未实现 opcode（视口/剪刀/PSO/计算/屏障等）：跳过不报错 */
            break;
        }

        ai += CMD_ARGS[op];
        fi += CMD_FLOATS[op];
    }

    p->last_stage = 13;
    rhi_exit();
    return 1;
}
