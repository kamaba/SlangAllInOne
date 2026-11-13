/* =========================================================================
 * sl_render_internal.h —— sl_render_lib 内部共享头（仅库内编译单元使用）
 *
 * 文件划分（与 SLangRender 侧 SL 文件一一对应）：
 *
 *   sl_render.c            <-> Render.sl            生命周期/诊断/v1 直连层
 *                                                      + RHI 后端注册表
 *   Pipeline/sl_pipeline.c <-> Pipeline/Pipeline.sl  13 阶段管线 + 相机调度
 *   Pipeline/sl_object.c   <-> RenderObject         场景对象
 *   Pipeline/sl_texture.c  <-> RenderTexture        纹理注册表 + WIC 加载
 *   Pipeline/sl_camera.c   <-> RenderCamera         多相机槽表
 *   Pipeline/sl_light.c    <-> Camera/Light.sl      光照槽表 + 帧级光照块
 *   Pipeline/sl_cmd.c      <-> Pipeline/CommandBuffer.sl
 *                                                   命令流执行器（D1 真录制）
 *
 * RHI 层（渲染硬件抽象，一表多后端同效果）：
 *   RHI/sl_rhi.h           接口契约（vtable + 像素/坐标约定）
 *   RHI/sl_rhi_gl.c        Windows WGL + GL 3.3 后端
 *   RHI/sl_rhi_d3d11.cpp   Windows D3D11 后端
 *   RHI/sl_rhi_vk.cpp      Vulkan 后端（SPIR-V 固化于 RHI/sl_rhi_vk_shaders.h）
 *   RHI/sl_rhi_gles.c      EGL + GLES 3.0 后端（缺失运行库时优雅降级）
 *
 * 共享约定：
 *   - 渲染目标为后端私有 SlrRhiTarget*，管线层只持有与传递；
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
#define SLR_MAX_LIGHTS  8    /* 管线光照槽（着色器消费首个平行光 + 首个聚光）*/
#define SLR_CUSTOM_MESHES 4   /* 动态网格槽（对象 mesh = 4 + slot 路由）*/
#define SLR_CUSTOM_MAX_VERTS 4096

/* clear_flags 位定义（相机清屏选项） */
#define SLR_CLEAR_COLOR 1
#define SLR_CLEAR_DEPTH 2

/* 纹理描述符槽容量（帧级描述符表；DX11 SRV 槽表 / VK descriptor set 池的
 * 管线侧镜像，四后端经 RHI desc_write_tex / desc_bind_tex 统一消费）*/
#define SLR_DESC_TEX_SLOTS 16

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
    /* v3.4 Phong：v3.3 光照 + Blinn-Phong 伪 3D 高光（uSpec[64] 消费）。
     * 尾部追加不动既有槽序（VK 固化表依赖顺序；VK 将新槽降级映射到
     * PFLAT/PTEX —— SPIR-V 未含光照/高光，绘制不报错仅无 Phong 效果）*/
    SLR_PROG_PHONG_FLAT,
    SLR_PROG_PHONG_TEX,
    /* v3.5 固化编译槽（RHI/sl_rhi_shaders_gen.h 产物；本头不 include 该
     * 446KB 头——避免所有包含者编译巨量字符串，后端经下方宏寻址 +
     * 编译期 typedef 检查对齐）：5 效果（Lambert/Phong/BlinnPhong/
     * BlinnPhongNormalMap/Toon）× 2 变体（TEX=0 / FLAT=1）。
     * 管线全材质（material 0..4）路由至此（v3.5 起内建 PFLAT/PTEX/
     * PHONG_* 仅作 VK 降级目标与阴影项专用）。GL/GLES 运行期编固化
     * GLSL330/ESSL300 源；D3D11 直吃 DXBC blob（fxc SM5 预编译，运行期
     * 零编译）；VK 降级映射 PFLAT/PTEX（SPIR-V 未含光照，绘制不报错
     * 仅无该效果）。*/
    SLR_PROG_GEN_BASE,
    SLR_PROG_COUNT = SLR_PROG_GEN_BASE + 10   /* 10 = SLR_GEN_EFFECT_COUNT*2 */
};

/* v3.5 固化槽位寻址：效果 0..4 × 变体 0=TEX / 1=FLAT，
 * 与固化头 SLR_GEN_SETS[effect*2+variant] 表同构 */
#define SLR_PROG_GEN_SLOT(effect, variant) \
    (SLR_PROG_GEN_BASE + (effect) * 2 + (variant))

/* PerDraw 常量缓冲 CPU 暂存（列主序，与 GL std140 / HLSL cbuffer 布局一致）：
 *   mvp   —— 顶点变换矩阵（proj * model2d）
 *   color —— 逐项颜色（rgba）
 *   wmat  —— 2D 世界仿射（光照用，每项 2 个 vec4 打包）：
 *     [0]=c*sx  [1]=-s*sy  [2]=s*sx  [3]=c*sy  （2x2 旋转缩放，c/s=cos/sin rot_z）
 *     [4]=tx    [5]=ty     [6]=c     [7]=s     （平移 + 物体朝向法线 (c,s)）
 *     着色器：world = vec2(dot(pos,w0.xy), dot(pos,w0.zw)) + w1.xy; nrm = w1.zw
 *   spec  —— Phong 高光参数（v3.4，每项 1 个 vec4）：
 *     [0]=高光强度 strength  [1]=shininess 光泽度  [2..3] 预留 */
typedef struct
{
    float mvp[SLR_MAX_OBJECTS][16];
    float color[SLR_MAX_OBJECTS][4];
    float wmat[SLR_MAX_OBJECTS][8];
    float spec[SLR_MAX_OBJECTS][4];
} SlrPerDraw;

/* ── 光照槽（管线级，SL 侧 Light.applyTo 经 slr_light_set 写入）──
 * 直射光存归一化方向；聚光存位置 + 归一化光轴 + cos(锥半角) + 范围。 */
typedef struct
{
    int used;             /* 1 = 启用（参与帧级光照块组装）*/
    int type;             /* SLR_LIGHT_DIRECTIONAL / SLR_LIGHT_SPOT */
    float dir[2];         /* 平行光：表面 -> 光源方向（归一化）
                             聚光：光轴方向 光源 -> 外（归一化）*/
    float pos[2];         /* 聚光：世界位置 */
    float range;          /* 聚光：有效半径 */
    float cos_angle;      /* 聚光：cos(锥半角) */
    float color[3];
    float intensity;
} SlrLight;

/* 帧级光照块（std140，6 vec4 = 96B；GL/GLES 绑定点 1，D3D11 寄存器 b4）
 * 组装规则：环境光 + 首个启用的平行光 + 首个启用的聚光（light_build_block）；
 * 颜色均为 颜色*强度 预乘；a 分量 1.0=启用。全零 + ambient=1 时输出与
 * 无光照版逐字节一致（向后兼容：跨后端同效果测试不受影响）。 */
typedef struct
{
    float ambient[4];      /* x = 环境光强度（管线默认 1.0 = 无光照效果）*/
    float dir_color[4];    /* rgb = 颜色*强度, a = 启用 */
    float dir_dir[4];      /* xy = 平行光方向（表面 -> 光源）*/
    float spot_color[4];   /* rgb = 颜色*强度, a = 启用 */
    float spot_pos_range[4]; /* xy = 聚光位置, z = 有效半径 */
    float spot_dir_cos[4]; /* xy = 光轴方向（光源 -> 外）, z = cos(锥半角)*/
} SlrLightBlock;

/* ===================================================================== */
/* 资源结构                                                                */
/* ===================================================================== */
typedef struct { int used, w, h; void* rhi_tex; } SlrTexRes;

typedef struct
{
    int used, mesh, layer, queue, visible, anim_mode, cull_cams;
    float pos[3], rot_z, scale[2], color[4], anim_speed;
    int64_t texture;
    /* v3.4/v3.5 材质/阴影（阶段 5 消费）：
     * material    0=Lambert 1=Phong 2=BlinnPhong 3=BlinnPhongNormalMap 4=Toon
     *             （0/1 走内建槽；2..4 走 v3.5 gen 固化槽，纹理→TEX/无→FLAT）
     * spec_str    Phong 高光强度（0 = 无高光）
     * spec_shin   Phong 光泽度（pow 指数）
     * cast_shadow 1 = 生成 2D 投影阴影绘制项（透明段，黑 0.35 alpha）*/
    int material, cast_shadow;
    float spec_str, spec_shin;
} SlrObject;

typedef struct
{
    int obj;        /* objects 下标          */
    int slot;       /* PerDraw 槽位      */
    int prog;        /* PFLAT/PTEX/PHONG_* 或 v3.5 gen 固化槽 */
    int queue, layer;
    int cam;        /* 所属相机位号（0..SLR_MAX_CAMERAS-1）*/
    int tex_desc;   /* 纹理描述符槽号（-1 = 无纹理；阶段 6 分配）*/
    int is_shadow;  /* 1 = 投影阴影项（阶段 6 写阴影色/变换）*/
    float z;
    float mvp[16];
} SlrDrawItem;

/* ── 描述符表（DX11 SRV 槽表 / VK descriptor set 的管线侧数据结构）──
 * 帧级生命周期：阶段 6 写入（纹理资源 -> 槽，同纹理查重复用），阶段
 * 7/9 绘制项按 tex_desc 槽号绑定（desc_bind_tex），draw_item 只携带
 * 整数索引不碰资源指针——"绑定与绘制分离"，与 DX11
 * PSSetShaderResources / VK vkCmdBindDescriptorSets 机制对齐。 */
typedef struct
{
    void* res;      /* 源资源指针（查重复用用，不参与绑定）*/
    int   used;
} SlrTexDesc;

typedef struct
{
    SlrTexDesc tex[SLR_DESC_TEX_SLOTS];
    int tex_count;              /* 本帧已写入的纹理描述符槽数 */
} SlrDescTable;

/* 相机：独立剔除掩码/正交视域/视口/清屏参数，depth 决定绘制次序 */
typedef struct
{
    int used, enabled, depth, cull_mask, clear_flags;
    float cam_l, cam_r, cam_b, cam_t;
    float clear_color[4];
    int vp_x, vp_y, vp_w, vp_h;
} SlrCamera;

/* 每帧逐相机绘制项区间（items 内 [start, start+n_opaque+n_trans) ）*/
typedef struct
{
    int start, n_opaque, n_trans;
} SlrCamRange;

typedef struct
{
    int used, w, h;
    SlrRhiTarget* rt_scene;    /* 场景渲染目标（带深度）    */
    SlrRhiTarget* rt_post;     /* 后处理中间目标           */
    SlrRhiTarget* rt_final;    /* 最终输出目标（回读源）    */

    SlrObject objects[SLR_MAX_OBJECTS];
    int object_count;

    SlrDrawItem items[SLR_MAX_OBJECTS];
    int item_count, opaque_count;

    SlrCamera   cameras[SLR_MAX_CAMERAS];
    int          active_cams[SLR_MAX_CAMERAS];   /* 本帧相机位号（depth 升序）*/
    int          active_cam_count;
    SlrCamRange cam_ranges[SLR_MAX_CAMERAS];
    int camera_count;                            /* 已启用相机数（stat）*/

    int visible_count, culled_count;
    int draw_calls, opaque_draws, transparent_draws;
    int chunk_count, program_switches, upload_count;
    int layers_mask, last_stage;

    SlrDescTable descs;                /* 帧级描述符表（阶段 6 写入/绘制绑定）*/

    SlrLight lights[SLR_MAX_LIGHTS];   /* 光照槽表（SL 侧 Light.applyTo 写入）*/
    float ambient;                     /* 环境光强度（默认 1.0 = 无光照效果）*/

    float clear_color[4];
    int post_enabled;
    float post_brightness, post_saturation, post_vignette;

    float time, last_time, dt, total_time;
    int64_t frame_count;
} SlrPipeline;

/* ===================================================================== */
/* 共享全局（定义归属：s_pipes -> sl_pipeline.c，s_textures -> sl_texture.c，
 * s_ready/s_perdraw -> sl_render.c）                                       */
/* ===================================================================== */
extern int          s_ready;
extern SlrPerDraw  s_perdraw;
extern SlrPipeline s_pipes[SLR_MAX_PIPES];
extern SlrTexRes   s_textures[SLR_MAX_TEX];

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
SlrTexRes* tex_from_handle(int64_t h);

/* sl_pipeline.c：管线句柄解析与渲染目标回收（slr_uninit 也调用） */
SlrPipeline* pipe_from_handle(int64_t h);
void pipeline_release_targets(SlrPipeline* p);

/* sl_light.c：帧级光照块组装（阶段 6 调用；环境光 + 首个平行光 + 首个聚光）*/
void light_build_block(SlrPipeline* p, SlrLightBlock* out);

/* sl_light.c：阴影投射光源查询（阶段 5 调用）：首个启用的平行光方向优先
 * （dir_out = 阴影偏移方向，已含"背离光源"语义），否则首个聚光
 * （返回其槽位；has_pos_out=1 表示带位置，方向需逐物体归一化）。
 * 返回 0 = 无可用光源 -> 不生成阴影。 */
int light_pick_shadow(SlrPipeline* p, float* dir_out, int* has_pos_out,
                      float* pos_out);

#ifdef __cplusplus
}
#endif

#endif /* SL_RENDER_INTERNAL_H */
