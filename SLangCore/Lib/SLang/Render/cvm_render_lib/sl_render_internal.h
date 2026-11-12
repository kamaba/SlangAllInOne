/* =========================================================================
 * sl_render_internal.h —— sl_render_lib 内部共享头（仅库内编译单元使用）
 *
 * 文件划分（与 SLangRender 侧 SL 文件一一对应）：
 *
 *   sl_render.c            <-> Render.sl            生命周期/诊断/v1 直连层
 *                                                      + RHI 后端注册表
 *   Pipeline/sl_pipeline.c <-> Pipeline/UnityPipeline.sl  13 阶段管线 + 相机调度
 *   Pipeline/sl_object.c   <-> UnityRenderObject         场景对象
 *   Pipeline/sl_texture.c  <-> UnityRenderTexture        纹理注册表 + WIC 加载
 *   Pipeline/sl_camera.c   <-> UnityRenderCamera         多相机槽表
 *
 * RHI 层（渲染硬件抽象，一表多后端同效果）：
 *   RHI/sl_rhi.h           接口契约（vtable + 像素/坐标约定）
 *   RHI/sl_rhi_gl.c        Windows WGL + GL 3.3 后端
 *   RHI/sl_rhi_d3d11.cpp   Windows D3D11 后端
 *   RHI/sl_rhi_vk.cpp      Vulkan 后端（SPIR-V 固化于 RHI/sl_rhi_vk_shaders.h）
 *   RHI/sl_rhi_gles.c      EGL + GLES 3.0 后端（缺失运行库时优雅降级）
 *
 * 共享约定：
 *   - 渲染目标为后端私有 slr_rhi_target*，管线层只持有与传递；
 *   - 纹理为后端私有 void*（存于 s_textures 注册表）；
 *   - 全局资源表：s_pipes（pipeline）/ s_textures（texture）定义在
 *     各自归属 .c，s_perdraw（PerDraw CPU 暂存）定义在 sl_render.c；
 *   - 跨文件内部函数统一非 static（原型见底部），仅单文件使用的保持 static。
 * ========================================================================= */
#ifndef SL_RENDER_INTERNAL_H
#define SL_RENDER_INTERNAL_H

#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include "vm_sl_render.h"
#include "RHI/sl_rhi.h"

/* C++ 编译单元（RHI/sl_rhi_d3d11.cpp 等）引用 C 层符号时保持 C 链接 */
#ifdef __cplusplus
extern "C" {
#endif

/* ===================================================================== */
/* 容量常量 / 位定义                                                       */
/* ===================================================================== */
#define SLR_MAX_OBJECTS 64
#define SLR_MAX_CTX     16
#define SLR_MAX_PIPES   32
#define SLR_MAX_TEX     64
#define SLR_MAX_CAMERAS 8
#define SLR_CUSTOM_MESHES 4   /* 动态网格槽（对象 mesh = 4 + slot 路由）*/
#define SLR_CUSTOM_MAX_VERTS 4096

/* clear_flags 位定义（相机清屏选项） */
#define SLR_CLEAR_COLOR 1
#define SLR_CLEAR_DEPTH 2

/* ===================================================================== */
/* 着色器程序槽位（各 RHI 后端按同一槽位实现六组程序）                      */
/* ===================================================================== */
enum
{
    SLR_PROG_FLAT = 0,   /* v1：MVP/Color uniform             */
    SLR_PROG_TEX,        /* v1：MVP/Color + 纹理              */
    SLR_PROG_PFLAT,      /* 管线：PerDraw 缓冲 + 纯色          */
    SLR_PROG_PTEX,       /* 管线：PerDraw 缓冲 + 纹理          */
    SLR_PROG_BLIT,       /* 全屏拷贝                          */
    SLR_PROG_POST,       /* 后处理                            */
    SLR_PROG_COUNT
};

/* PerDraw 常量缓冲 CPU 暂存（列主序，与 GL std140 / HLSL cbuffer 布局一致）*/
typedef struct
{
    float mvp[SLR_MAX_OBJECTS][16];
    float color[SLR_MAX_OBJECTS][4];
} slr_perdraw;

/* ===================================================================== */
/* 资源结构                                                                */
/* ===================================================================== */
typedef struct { int used, w, h; void* rhi_tex; } slr_texres;

typedef struct
{
    int used, mesh, layer, queue, visible, anim_mode, cull_cams;
    float pos[3], rot_z, scale[2], color[4], anim_speed;
    int64_t texture;
} slr_object;

typedef struct
{
    int obj;        /* objects 下标          */
    int slot;       /* PerDraw 槽位      */
    int prog;        /* SLR_PROG_PFLAT/PTEX   */
    int queue, layer;
    int cam;        /* 所属相机位号（0..SLR_MAX_CAMERAS-1）*/
    float z;
    float mvp[16];
} slr_draw_item;

/* 相机：独立剔除掩码/正交视域/视口/清屏参数，depth 决定绘制次序 */
typedef struct
{
    int used, enabled, depth, cull_mask, clear_flags;
    float cam_l, cam_r, cam_b, cam_t;
    float clear_color[4];
    int vp_x, vp_y, vp_w, vp_h;
} slr_camera;

/* 每帧逐相机绘制项区间（items 内 [start, start+n_opaque+n_trans) ）*/
typedef struct
{
    int start, n_opaque, n_trans;
} slr_cam_range;

typedef struct
{
    int used, w, h;
    slr_rhi_target* rt_scene;    /* 场景渲染目标（带深度）    */
    slr_rhi_target* rt_post;     /* 后处理中间目标           */
    slr_rhi_target* rt_final;    /* 最终输出目标（回读源）    */

    slr_object objects[SLR_MAX_OBJECTS];
    int object_count;

    slr_draw_item items[SLR_MAX_OBJECTS];
    int item_count, opaque_count;

    slr_camera   cameras[SLR_MAX_CAMERAS];
    int          active_cams[SLR_MAX_CAMERAS];   /* 本帧相机位号（depth 升序）*/
    int          active_cam_count;
    slr_cam_range cam_ranges[SLR_MAX_CAMERAS];
    int camera_count;                            /* 已启用相机数（stat）*/

    int visible_count, culled_count;
    int draw_calls, opaque_draws, transparent_draws;
    int chunk_count, program_switches, upload_count;
    int layers_mask, last_stage;

    float clear_color[4];
    int post_enabled;
    float post_brightness, post_saturation, post_vignette;

    float time, last_time, dt, total_time;
    int64_t frame_count;
} slr_pipeline;

/* ===================================================================== */
/* 共享全局（定义归属：s_pipes -> sl_pipeline.c，s_textures -> sl_texture.c，
 * s_ready/s_perdraw -> sl_render.c）                                       */
/* ===================================================================== */
extern int          s_ready;
extern slr_perdraw  s_perdraw;
extern slr_pipeline s_pipes[SLR_MAX_PIPES];
extern slr_texres   s_textures[SLR_MAX_TEX];

/* ===================================================================== */
/* 跨文件内部函数原型（统一非 static）                                      */
/* ===================================================================== */
/* sl_render.c：错误处理 + RHI 进出锁 + 后端生命周期 */
void set_error(int e);
void set_error_detail(int e, const char* detail);
void clear_error(void);
int  rhi_enter(void);
void rhi_exit(void);

/* sl_texture.c：纹理注册表（管线/对象跨文件取用） */
slr_texres* tex_from_handle(int64_t h);

/* sl_pipeline.c：管线句柄解析与渲染目标回收（slr_uninit 也调用） */
slr_pipeline* pipe_from_handle(int64_t h);
void pipeline_release_targets(slr_pipeline* p);

#ifdef __cplusplus
}
#endif

#endif /* SL_RENDER_INTERNAL_H */
