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
 *                        draw_item（自包含命令：排序重排安全）；N1 起
 *                        不透明连续项回放端 RLE 合并为 instanced draw
 *                        （prog/mesh/texDesc 同 + 槽连续递增 + ≤64 槽，
 *                        透明项混合序敏感恒逐项）
 *   PostProcess       args[enabled] floats[b s v] -> post_process(post<-scene)
 *   Blit              -> blit(final<-post)
 *   Readback          args[dstPtr] -> readback(final)
 *   RaySetSphere      args[idx] floats[8]（cx cy cz r cr cg cb reflect）
 *                     -> p->ray 场景累积（sl_ray.c，跨命令流持久）
 *   RaySetLight       floats[4]（dx dy dz intensity）-> 同上
 *   RaySetGround      floats[4]（r g b reflect）-> 同上
 *   RaySetCamera      floats[4]（ex ey ez fovY）-> 同上
 *   RaySetBackground  floats[3]（r g b）-> 同上
 *   RayRender         args[texSlot w h] -> CPU whitted 渲 256x256 ->
 *                     texture_register 产纹理 + 写描述符槽（后续 DrawItem
 *                     经 texDesc 绑定上屏；四后端无关的纯离线计算）
 *   AsyncMode         args[0/1]（N3 控制命令）-> 切换执行路径：0 = 同步
 *                     直接回放；1 = 入队即返 + worker 线程回放（GL/GLES
 *                     context 线程亲和随模式启停整体移交，见 RHI
 *                     thread_acquire/thread_release 钩子）
 *   AsyncFlush        （N3 控制命令）-> 屏障：等此前全部已入队流回放完成
 * 其余 opcode（视口/剪刀/PSO/计算/屏障等 M0+ 资源世界命令）：记账跳过，
 * 不报错（前向兼容；args/floats 游标仍按固定表推进，不脱同步）。
 *
 * 帧级前置（回放开始）：s_perdraw / 描述符表清零 + 光照块组装上传
 * （沿用管线光照槽；无光照 + ambient=1.0 时输出与纯色路径逐字节一致）。
 *
 * N3 执行路径（slr_cmd_execute_stream 三分流）：
 *   同步模式   普通流：rhi_enter -> cmd_replay_locked -> rhi_exit。
 *   async 模式 普通流：cmd_async_submit 入队即返（深度 2 环形；队列满则
 *              阻塞等 worker 腾槽 = pack N+1 与执行 N 的同线程流水线）。
 *   控制流（含 AsyncMode/AsyncFlush）：先 cmd_async_drain（屏障）-> 同步
 *              回放（AsyncMode 仅记账 pending_mode）-> rhi_exit 后锁外
 *              cmd_async_switch（内部再 drain + 线程启停 + context 移交）。
 *   worker：每流 thread_acquire -> rhi_enter -> 回放 -> rhi_exit ->
 *              thread_release。主线程在 async 常态下每次 rhi_exit 也顺带
 *              解绑（rhi_set_thread_handoff，sl_render.c）——否则控制流
 *              （AsyncFlush）回放后主线程持绑 context，worker 的
 *              thread_acquire 会 ERROR_BUSY 失败（GL/GLES 单线程独占）。
 * ========================================================================= */
#include "sl_render_internal.h"
#include <stdlib.h>    /* realloc/free（N3 队列槽块）*/

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
    /* ---- N4a 软光追（RaySet* 场景累积 + RayRender 渲产纹理写槽）---- */
    SLR_CMD_RAY_SET_SPHERE = 30,
    SLR_CMD_RAY_SET_LIGHT,
    SLR_CMD_RAY_SET_GROUND,
    SLR_CMD_RAY_SET_CAMERA,
    SLR_CMD_RAY_SET_BACKGROUND,
    SLR_CMD_RAY_RENDER,
    /* ---- N3 异步控制（模式切换 / 排空等待；命中即走同步控制路径）---- */
    SLR_CMD_ASYNC_MODE = 36,
    SLR_CMD_ASYNC_FLUSH,
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
    1,  /* Readback（桥接）      */
    1,  /* RaySetSphere（N4a：球下标）*/
    0,  /* RaySetLight（N4a）    */
    0,  /* RaySetGround（N4a）   */
    0,  /* RaySetCamera（N4a）   */
    0,  /* RaySetBackground（N4a）*/
    3,  /* RayRender（N4a：texSlot w h）*/
    1,  /* AsyncMode（N3：0 同步 / 1 worker）*/
    0   /* AsyncFlush（N3：等在途流排空）*/
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
    0,  /* Readback（桥接）      */
    8,  /* RaySetSphere（N4a：cx cy cz r cr cg cb reflect）*/
    4,  /* RaySetLight（N4a：dx dy dz intensity）*/
    4,  /* RaySetGround（N4a：r g b reflect）*/
    4,  /* RaySetCamera（N4a：ex ey ez fovY）*/
    3,  /* RaySetBackground（N4a：r g b）*/
    0,  /* RayRender（N4a）      */
    0,  /* AsyncMode（N3）       */
    0   /* AsyncFlush（N3）      */
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

/* ---- N3 帧级回放体（execute_stream 同步路径 / worker 共用）----
 * 调用方已 rhi_enter（RHI 锁 + context 就绪）；按帧槽边界重置（PerDraw/
 * 描述符表/统计在函数头清零 = 每条命令流一个帧槽）。base 指向完整 SLMC
 * 块；command_count >= 0 时与头 count 校验（worker 传 -1 跳过）。
 * pending_async_mode 非空且流内出现 AsyncMode 命令时写入目标模式——实际
 * 线程切换由调用方在 rhi_exit 之后锁外执行（switch 内部要 drain + 线程
 * 等待，不能持 RHI 锁）。AsyncFlush 回放为 no-op：屏障语义由控制路径
 * 进入本函数前的 drain 完成（见 execute_stream 控制分支）。*/
static int cmd_replay_locked(SlrPipeline* p, const unsigned char* base,
                             int32_t command_count, int* pending_async_mode)
{
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

    memcpy(&magic,    base + 0,  4);
    memcpy(&version,  base + 4,  4);
    memcpy(&count,    base + 8,  4);
    memcpy(&arg_off,  base + 12, 4);
    memcpy(&float_off, base + 16, 4);
    if (magic != 0x534C4D43 || version != 1 || count < 0)
    {
        set_error_detail(SLR_E_BAD_PARAM, "bad SLMC header");
        return 0;
    }
    if (command_count >= 0 && count != command_count)
    {
        set_error_detail(SLR_E_BAD_PARAM, "command count mismatch");
        return 0;
    }
    if (arg_off < 24 || float_off < arg_off)
    {
        set_error_detail(SLR_E_BAD_PARAM, "bad section offsets");
        return 0;
    }
    opcodes = (const int32_t*)(base + 24);
    args    = (const int64_t*)(base + arg_off);
    floats  = (const float*)(base + float_off);

    /* 纯控制流（仅 Nop/AsyncMode/AsyncFlush）：跳过帧级前置。flush 屏障
     * 每帧末尾都会回放一次，前置里的 stats 清零会抹掉 worker 刚回放完
     * 的统计（读回 0），光照上传也是纯浪费；混渲染命令的流照常前置。*/
    {
        int pure_ctrl = 1;
        for (i = 0; i < count; i++)
        {
            int op = opcodes[i];
            if (op != SLR_CMD_NOP && op != SLR_CMD_ASYNC_MODE &&
                op != SLR_CMD_ASYNC_FLUSH)
            {
                pure_ctrl = 0;
                break;
            }
        }

        /* 帧级前置：PerDraw / 描述符表清零 + 光照块组装上传（沿用管线
         * 光照槽；无光照 + ambient=1.0 时输出与纯色路径逐字节一致）*/
        if (!pure_ctrl)
        {
            memset(&s_perdraw, 0, sizeof(s_perdraw));
            memset(&p->descs, 0, sizeof(p->descs));
            {
                SlrLightBlock lb;
                light_build_block(p, &lb);
                g_rhi->upload_lights(&lb, (int)sizeof(lb));
            }
            p->draw_calls = 0; p->opaque_draws = 0; p->transparent_draws = 0;
            p->instance_total = 0;   /* N1：实例总数逐帧清零（与阶段 1 同口径）*/
            p->program_switches = 0; p->chunk_count = 0; p->upload_count = 0;
            p->layers_mask = 0;
            p->visible_count = 0; p->culled_count = 0;
        }
    }

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
                int n = 1;
                /* N1 GPU 实例化（方案 B：C 侧回放 RLE 合并，SL 录制端零改动）
                 * —— 不透明项 lookahead：连续 DrawItem 且 prog/mesh/texDesc
                 * 相同、槽号连续递增（实例 i = 槽 base+i）、槽不越 64 上限
                 * （PerDraw 容量）。合并候选隐式通过首项验证（prog/mesh/
                 * texd 同已验证值、slot+n ≤ 63）。透明项混合序敏感，恒 1。 */
                if (!transp)
                {
                    while (i + n < count
                        && opcodes[i + n] == SLR_CMD_DRAW_ITEM
                        && slot + n < 64
                        && (int)args[ai + n * CMD_ARGS[SLR_CMD_DRAW_ITEM]] == prog
                        && (int)args[ai + n * CMD_ARGS[SLR_CMD_DRAW_ITEM] + 1] == slot + n
                        && (int)args[ai + n * CMD_ARGS[SLR_CMD_DRAW_ITEM] + 2] == mesh
                        && (int)args[ai + n * CMD_ARGS[SLR_CMD_DRAW_ITEM] + 3] == texd
                        && (int)args[ai + n * CMD_ARGS[SLR_CMD_DRAW_ITEM] + 4] == 0)
                        n++;
                }
                if (perdraw_dirty)
                {
                    g_rhi->upload_perdraw(&s_perdraw, (int)sizeof(SlrPerDraw));
                    perdraw_dirty = 0;
                }
                g_rhi->set_state(transp ? 1 : 0);
                g_rhi->desc_bind_tex(texd);   /* -1 = 清绑定（与批头行为一致）*/
                g_rhi->draw_item(prog, slot, mesh, n);
                p->draw_calls++;
                p->instance_total += n;
                if (transp) p->transparent_draws++;
                else p->opaque_draws++;
                if (prog != last_prog) { p->program_switches++; last_prog = prog; }
                /* 合并 n 条命令：游标推进 = 命令数 x 表定消费（switch 后统一
                 * 推进补最后一条）；首项无效时不合并不推进（保持原行为）*/
                if (n > 1)
                {
                    ai += (n - 1) * CMD_ARGS[op];
                    fi += (n - 1) * CMD_FLOATS[op];
                    i += n - 1;
                }
            }
            break;
        }
        case SLR_CMD_POST_PROCESS:
        {
            /* 命令三参覆盖 pipeline 同名字段；其余（contrast/filter/hue/
             * grain/tonemap/vigSmooth）沿用 set_post_params 写入的管线值
             * （未设置 = 中性 → 与旧三参行为逐位一致） */
            float cb[13];
            cb[0] = (float)(int)args[ai];
            cb[1] = floats[fi];
            cb[2] = p->post_contrast;
            cb[3] = floats[fi + 1];
            cb[4] = floats[fi + 2];
            cb[5] = p->post_vig_smooth;
            cb[6] = p->post_hue;
            cb[7] = p->post_grain;
            cb[8] = p->post_grain_seed;
            cb[9] = (float)p->post_tonemap;
            cb[10] = p->post_filter[0];
            cb[11] = p->post_filter[1];
            cb[12] = p->post_filter[2];
            g_rhi->post_process(p->rt_post, p->rt_scene, p->w, p->h, cb);
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
        /* ---- N4a 软光追：场景累积 + CPU 渲产纹理写描述符槽 ---- */
        case SLR_CMD_RAY_SET_SPHERE:
        {
            int idx = (int)args[ai];
            ray_set_sphere(&p->ray, idx, &floats[fi]);
            break;
        }
        case SLR_CMD_RAY_SET_LIGHT:
            ray_set_light(&p->ray, &floats[fi]);
            break;
        case SLR_CMD_RAY_SET_GROUND:
            ray_set_ground(&p->ray, &floats[fi]);
            break;
        case SLR_CMD_RAY_SET_CAMERA:
            ray_set_camera(&p->ray, &floats[fi]);
            break;
        case SLR_CMD_RAY_SET_BACKGROUND:
            ray_set_background(&p->ray, &floats[fi]);
            break;
        case SLR_CMD_RAY_RENDER:
        {
            int slot = (int)args[ai];
            int rw = (int)args[ai + 1];
            int rh = (int)args[ai + 2];
            ray_render(p, slot, rw, rh);   /* 失败仅置错误码，不中断回放 */
            break;
        }
        /* ---- N3 异步控制（仅同步控制路径到达；回放只记账，实际切换/
         *      排空由 execute_stream 在 rhi_exit 之后锁外执行）---- */
        case SLR_CMD_ASYNC_MODE:
            if (pending_async_mode)
                *pending_async_mode = args[ai] ? 1 : 0;
            break;
        case SLR_CMD_ASYNC_FLUSH:
            break;   /* 屏障已在进入回放前 drain 完成 */
        default:
            /* 未实现 opcode（视口/剪刀/PSO/计算/屏障等）：跳过不报错 */
            break;
        }

        ai += CMD_ARGS[op];
        fi += CMD_FLOATS[op];
    }

    p->last_stage = 13;
    return 1;
}

/* ===================================================================== */
/* N3 异步提交队列（深度 2 环形）+ 渲染 worker 线程                        */
/* ===================================================================== */

/* 队列惰性初始化（cmd_async_switch(p,1) 首次调用）*/
static void cmd_async_init(SlrPipeline* p)
{
    SlrAsyncQueue* q = &p->async;
    if (q->inited) return;
    InitializeCriticalSection(&q->lock);
    InitializeConditionVariable(&q->cv_submit);
    InitializeConditionVariable(&q->cv_done);
    q->head = q->tail = q->count = 0;
    q->submitted = q->completed = 0;
    q->running = 0;
    q->inited = 1;
}

/* 入队：拷贝 SLMC 块到空槽即返（队列满则阻塞等 worker 腾槽；提交侧为
 * SL 主线程，等槽即 pack N+1 与执行 N 的同线程流水线节流点）。
 * 块字节长度自算：float_off + Σ CMD_FLOATS[op]×4（FFI 只传 ptr+count）。*/
static int cmd_async_submit(SlrPipeline* p, const unsigned char* base)
{
    SlrAsyncQueue* q = &p->async;
    const int32_t* opcodes;
    int32_t count, float_off;
    int bytes, total_floats, i;
    unsigned char* dst;

    memcpy(&count, base + 8, 4);
    memcpy(&float_off, base + 16, 4);
    opcodes = (const int32_t*)(base + 24);
    total_floats = 0;
    for (i = 0; i < count; i++)
    {
        int op = opcodes[i];
        if (op >= 0 && op < SLR_CMD_COUNT) total_floats += CMD_FLOATS[op];
    }
    bytes = (int)float_off + total_floats * 4;

    EnterCriticalSection(&q->lock);
    while (q->count == 2)
        SleepConditionVariableCS(&q->cv_done, &q->lock, INFINITE);

    dst = q->buf[q->tail];
    if (q->cap[q->tail] < bytes)
    {
        unsigned char* nb = (unsigned char*)realloc(dst, (size_t)bytes);
        if (!nb)
        {
            LeaveCriticalSection(&q->lock);
            set_error(SLR_E_LIMIT);
            return 0;
        }
        q->buf[q->tail] = nb;
        q->cap[q->tail] = bytes;
        dst = nb;
    }
    memcpy(dst, base, (size_t)bytes);
    q->tail = (q->tail + 1) & 1;
    q->count++;
    q->submitted++;
    LeaveCriticalSection(&q->lock);
    WakeConditionVariable(&q->cv_submit);
    return 1;
}

/* worker：循环取槽回放。每流 acquire -> rhi_enter -> replay -> rhi_exit ->
 * release——idle 时 context 游离，主线程随时可 enter（resize/destroy 等
 * 管线 API 不被饿死）；GL 的 enter 每次 MakeCurrent，acquire 后的重复
 * 绑定幂等无害。free 延迟到槽块复用（容量保留，malloc 只在增长时发生）。*/
static DWORD WINAPI cmd_worker(LPVOID param)
{
    SlrPipeline* p = (SlrPipeline*)param;
    SlrAsyncQueue* q = &p->async;
    for (;;)
    {
        unsigned char* buf;
        EnterCriticalSection(&q->lock);
        while (q->count == 0 && q->running)
            SleepConditionVariableCS(&q->cv_submit, &q->lock, INFINITE);
        if (q->count == 0 && !q->running)
        {
            LeaveCriticalSection(&q->lock);
            break;
        }
        buf = q->buf[q->head];
        q->head = (q->head + 1) & 1;
        q->count--;
        /* 腾出空槽即唤醒等槽的提交方（流水线：pack N+1 与执行 N 并行）*/
        LeaveCriticalSection(&q->lock);
        WakeAllConditionVariable(&q->cv_done);

        /* 线程亲和 + 回放（含失败防线：绑定/enter 失败不裸奔回放——
         * 无 context 的 GL 调用是 UB；且 gl_enter 失败路径已自行出锁，
         * 不能再配对 rhi_exit。completed 照常推进防 drain 死锁。正常
         * 路径下 handoff 机制保证主线程用完即解绑，此处恒成功）。*/
        if ((!g_rhi->thread_acquire || g_rhi->thread_acquire()) &&
            rhi_enter())
        {
            cmd_replay_locked(p, buf, -1, NULL);
            rhi_exit();
        }
        if (g_rhi->thread_release) g_rhi->thread_release();

        EnterCriticalSection(&q->lock);
        q->completed++;
        LeaveCriticalSection(&q->lock);
        WakeAllConditionVariable(&q->cv_done);
    }
    return 0;
}

/* 等待全部已入队流回放完成（completed == submitted；无 RHI 锁，可在
 * 任意时刻调用——异步/同步模式均安全，未初始化时为 no-op）*/
void cmd_async_drain(SlrPipeline* p)
{
    SlrAsyncQueue* q = &p->async;
    if (!q->inited) return;
    EnterCriticalSection(&q->lock);
    while (q->completed != q->submitted)
        SleepConditionVariableCS(&q->cv_done, &q->lock, INFINITE);
    LeaveCriticalSection(&q->lock);
}

/* 模式切换（仅在锁外调用——内部要 drain + 线程创建/等待）。
 *   mode=1：惰性建队列 -> 置 handoff + 主线程解绑 context -> 启 worker
 *           （此后主线程每次 rhi_exit 都顺带解绑——含控制流回放，保证
 *           worker 的 thread_acquire 恒可见游离 context；GL/GLES 的
 *           context 从此归 worker）。
 *   mode=0：drain -> 通知退出并等线程收尾 -> 关 handoff 恢复同步常态
 *           -> context 绑回主线程。*/
void cmd_async_switch(SlrPipeline* p, int mode)
{
    SlrAsyncQueue* q = &p->async;
    if (mode)
    {
        if (p->async_mode) return;
        cmd_async_init(p);
        /* 解绑当前主线程绑定 + 此后主线程 exit 不再持绑（handoff）*/
        rhi_set_thread_handoff(1);
        if (g_rhi->thread_release) g_rhi->thread_release();
        q->running = 1;
        q->thread = CreateThread(NULL, 0, cmd_worker, p, 0, NULL);
        p->async_mode = 1;
    }
    else
    {
        if (!p->async_mode) return;
        cmd_async_drain(p);
        EnterCriticalSection(&q->lock);
        q->running = 0;
        LeaveCriticalSection(&q->lock);
        WakeAllConditionVariable(&q->cv_submit);
        if (q->thread)
        {
            WaitForSingleObject(q->thread, INFINITE);
            CloseHandle(q->thread);
            q->thread = NULL;
        }
        /* worker 末流 exit 已解绑（handoff）：关 handoff 恢复同步常态
         * （exit 不解绑、enter 幂等重绑）+ context 绑回主线程 */
        rhi_set_thread_handoff(0);
        if (g_rhi->thread_acquire) g_rhi->thread_acquire();
        p->async_mode = 0;
    }
}

/* 管线销毁前的安全停机（必须在实际持有 RHI 锁之前调用——worker 回放
 * 需要 rhi_enter，持锁等待会死锁）。停机后 context 游离（worker 末次
 * release），主线程后续 rhi_enter 自行绑定。*/
void cmd_async_shutdown(SlrPipeline* p)
{
    SlrAsyncQueue* q = &p->async;
    if (!q->inited) return;
    cmd_async_drain(p);
    EnterCriticalSection(&q->lock);
    q->running = 0;
    LeaveCriticalSection(&q->lock);
    WakeAllConditionVariable(&q->cv_submit);
    if (q->thread)
    {
        WaitForSingleObject(q->thread, INFINITE);
        CloseHandle(q->thread);
        q->thread = NULL;
    }
    free(q->buf[0]);
    free(q->buf[1]);
    q->buf[0] = q->buf[1] = NULL;
    q->cap[0] = q->cap[1] = 0;
    q->head = q->tail = q->count = 0;
    DeleteCriticalSection(&q->lock);
    q->inited = 0;
    p->async_mode = 0;
    rhi_set_thread_handoff(0);   /* 恢复同步常态（exit 不解绑）*/
}

/* ---- SLMC 整包提交（三路径：同步回放 / 异步入队 / 控制屏障）----
 * 头解析与控制扫描在 RHI 锁外（只读 stream 内存 + 管线槽表）：
 *   控制流（含 AsyncMode/AsyncFlush）：先 drain（屏障：此前全部在途
 *       流回放完成）-> 同步回放 -> 锁外执行模式切换（switch 内部自带
 *       drain，FIFO 次序保证切换点之前的流全部完成）。
 *   async_mode=1 普通流：入队即返（worker 线程回放）。
 *   同步模式普通流：直接回放。*/
SLR_API int slr_cmd_execute_stream(int64_t pipe, int64_t stream_ptr,
                                   int32_t command_count)
{
    SlrPipeline* p;
    const unsigned char* base;
    const int32_t* opcodes;
    int32_t count;
    int i, ctrl;

    p = pipe_from_handle(pipe);
    if (!p) { set_error(SLR_E_PIPELINE); return 0; }
    if (!stream_ptr) { set_error_detail(SLR_E_BAD_PARAM, "null stream"); return 0; }

    base = (const unsigned char*)(intptr_t)stream_ptr;
    memcpy(&count, base + 8, 4);
    if (count < 0) { set_error_detail(SLR_E_BAD_PARAM, "bad SLMC header"); return 0; }
    if (command_count >= 0 && count != command_count)
    { set_error_detail(SLR_E_BAD_PARAM, "command count mismatch"); return 0; }
    opcodes = (const int32_t*)(base + 24);

    /* 控制命令扫描 */
    ctrl = 0;
    for (i = 0; i < count; i++)
    {
        int op = opcodes[i];
        if (op == SLR_CMD_ASYNC_MODE || op == SLR_CMD_ASYNC_FLUSH) { ctrl = 1; break; }
    }
    if (ctrl)
    {
        int pending_mode = -1;
        int ok;
        cmd_async_drain(p);
        if (!rhi_enter()) return 0;
        ok = cmd_replay_locked(p, base, command_count, &pending_mode);
        rhi_exit();
        if (!ok) return 0;
        if (pending_mode >= 0) cmd_async_switch(p, pending_mode);
        return 1;
    }

    /* async 模式：入队即返（等空槽 = 深度 2 流水线节流）*/
    if (p->async_mode)
        return cmd_async_submit(p, base);

    /* 同步路径：直接回放 */
    if (!rhi_enter()) return 0;
    {
        int ok = cmd_replay_locked(p, base, command_count, NULL);
        rhi_exit();
        return ok;
    }
}
