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
#define SLR_CUSTOM_MESHES 10  /* 动态网格槽（对象 mesh = 4 + slot 路由）；
                                 2026-11-19 4→8：棋盘 4 烘焙组 + FairyGUI UI 槽；
                                 8→10：FairyGUI v2 多纹理组（UI 槽 7..13 =
                                 图集 + loader/graph/go3d 独立纹理组）*/
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
    SLR_PROG_SKY,        /* P6：渐变天空背景（全屏 quad，无深度写入）*/
    /* v3.6 MotionVectors：速度 pass（VS 出 cur/prev 双 NDC，FS 编码
     * RG = vel*0.5+0.5；PerDrawPrev UBO 绑定点 2 消费；插入在 GEN_BASE
     * 之前——GEN_BASE/SKY_CUBE/COUNT 相应平移，全部消费点走宏/枚举名）*/
    SLR_PROG_MOTION,
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
    /* doc/13 §2.1 第二步：cubemap 天空（全屏 quad 按视线方向采样 cube；
     * 尾部追加不动既有槽序——gen 固化槽检查宏同步 +1）*/
    SLR_PROG_SKY_CUBE,
    SLR_PROG_COUNT = SLR_PROG_GEN_BASE + 10   /* 10 = SLR_GEN_EFFECT_COUNT*2；SKY_CUBE 懒创建不占内建槽 */
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

/* v3.6 MotionVectors：PerDrawPrev 帧级块（std140，GL/GLES UBO 绑定点 2，
 * SLR_PROG_MOTION 顶点着色器消费 uPrevMVP[obj]）。槽位 = 当前帧绘制项
 * 数组下标（与 SlrPerDraw.mvp 同布局同槽序），CPU 侧在阶段 6 由
 * 上帧对象变换快照 × 上帧相机视域投影现场组算。 */
typedef struct
{
    float prev_mvp[SLR_MAX_OBJECTS][16];
} SlrPerDrawPrev;

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
    int shadow_quality;   /* N2a：0 = 旧 2D 投影黑斑回退；1 = shadow map
                             （仅平行光生效；聚光 1 时仍走黑斑）。VK 无
                             深度采样支持时管线层强制按 0 处理 */
    float shadow_bias_ovr;    /* N2b：bias 覆盖（0 = 管线默认 0.002）*/
    float shadow_str_ovr;     /* N2b：强度覆盖（0 = 管线默认 0.35）*/
    int   shadow_cascades;    /* N2b：级联数（0/1 = 单级 N2a；4 = CSM）*/
} SlrLight;

/* 帧级光照块（std140；GL/GLES 绑定点 1，D3D11 b4）
 * 组装规则：环境光 + 首个启用的平行光 + 首个启用的聚光（light_build_block）；
 * 颜色均为 颜色*强度 预乘；a 分量 1.0=启用。全零 + ambient=1 时输出与
 * 无光照版逐字节一致（向后兼容：跨后端同效果测试不受影响）。
 * 基础段（96B）：6 vec4 光照。
 * N2a 段（+96B = 192B）：uLightVP（级联 0）/ uShadowParam / uShadowZx
 *   ——偏移恒定（尾部追加原则），旧布局零破坏。
 * N2b 追加（+224B = 416B）：uShadowSplit（4 级联 v 左端边界）/
 *   uShadowInfo（x=级联数 y=末级右端 v）/ uLightVP1..3（级联 1..3 VP；
 *   级联 0 复用 N2a 的 uLightVP 位）*/
typedef struct
{
    float ambient[4];      /* x = 环境光强度（管线默认 1.0 = 无光照效果）*/
    float dir_color[4];    /* rgb = 颜色*强度, a = 启用 */
    float dir_dir[4];      /* xy = 平行光方向（表面 -> 光源）*/
    float spot_color[4];   /* rgb = 颜色*强度, a = 启用 */
    float spot_pos_range[4]; /* xy = 聚光位置, z = 有效半径 */
    float spot_dir_cos[4]; /* xy = 光轴方向（光源 -> 外）, z = cos(锥半角)*/
    float light_vp[16];    /* N2a：级联 0 光空间 VP（column_major 4x4）*/
    float shadow_param[4]; /* N2a：enable / bias / strength / texel */
    float shadow_zxform[4]; /* N2a：深度还原 xy + 行 v 适配 zw */
    float shadow_split[4]; /* N2b：4 级联 v 左端边界（split[i+1]=右端）*/
    float shadow_info[4];  /* N2b：x = 级联数（1/4），y = 末级右端 v */
    float shadow_vp1[16];  /* N2b：级联 1 VP */
    float shadow_vp2[16];  /* N2b：级联 2 VP */
    float shadow_vp3[16];  /* N2b：级联 3 VP */
} SlrLightBlock;

/* ── N4a 软光追场景（Pipeline/sl_ray.c <-> SL 侧 Ray.sl）──
 * 固定容量场景（≤16 球 + y=0 地面平面）+ whitted 2 弹射（主射线 +
 * 阴影射线 + 1 次反射）。状态挂 SlrPipeline（跨命令流持久：RaySet*
 * 命令累积覆写，RayRender 命令消费渲染）。着色模型（C/SL 两侧逐字
 * 一致，RenderTest Phase RAY 手算断言依据）：
 *   local = albedo * (AMBIENT + (inShadow ? 0 : intensity * max(0, n·l)))
 *   color = (depth < 1 && reflect > 0)
 *             ? local * (1 - reflect) + trace(reflected) * reflect : local
 *   AMBIENT = 0.25；字节 = clamp01(c) * 255 + 0.5
 * 相机（正交固定基：forward +z / up +y / right +x，fov 为垂直视场角）：
 *   ndc_x = (px+0.5)/w*2-1   ndc_y = 1-(py+0.5)/h*2
 *   half_h = tan(fov_y/2)    half_w = half_h * (w/h)
 *   dir = normalize(ndc_x*half_w, ndc_y*half_h, 1) */
#define SLR_RAY_MAX_SPHERES 16
#define SLR_RAY_AMBIENT 0.25f

typedef struct
{
    int used;
    float cx, cy, cz, r;     /* 球心 + 半径            */
    float cr, cg, cb;        /* albedo                 */
    float reflect;           /* 反射率 0..1            */
} SlrRaySphere;

typedef struct
{
    SlrRaySphere spheres[SLR_RAY_MAX_SPHERES];
    int sphere_count;
    int ground_on;           /* 1 = y=0 地面平面参与求交 */
    float ground[4];         /* r g b reflect           */
    float light_dir[3];      /* 表面 -> 光源（消费时归一）*/
    float light_intensity;
    float eye[3];
    float fov_y;             /* 垂直视场角（度）        */
    float bg[3];             /* 未命中背景色            */
} SlrRayScene;

/* ===================================================================== */
/* 资源结构                                                                */
/* ===================================================================== */
typedef struct { int used, w, h; int is_cube; void* rhi_tex; } SlrTexRes;

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

/* ── N3 异步提交队列（深度 2 环形；SL 语言无线程原语，并发全封装 C 侧）──
 * async_mode=1 时 execute_stream 把 SLMC 块拷入空槽即返（等空槽阻塞在
 * cv_done），worker 线程取槽回放；completed==submitted 即 drain 完成。
 * 块内存归队列持有（容量按需扩，shutdown 释放）；context 线程亲和随
 * 模式启停整体移交（g_rhi->thread_acquire/release，见 cmd_async_switch）。*/
typedef struct
{
    CRITICAL_SECTION     lock;
    CONDITION_VARIABLE   cv_submit, cv_done;
    HANDLE               thread;          /* worker（async 模式期存活）*/
    unsigned char*       buf[2];          /* 槽块（malloc/realloc，NULL = 空）*/
    int                  cap[2];          /* 槽容量（字节，只增）*/
    int                  head, tail, count;   /* 环形游标 (x+1)&1 */
    int                  running, inited;
    int64_t              submitted, completed;
} SlrAsyncQueue;

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
    int instance_total;                         /* N1：本帧实例总数（合批后）*/
    int chunk_count, program_switches, upload_count;
    int layers_mask, last_stage;

    SlrDescTable descs;                /* 帧级描述符表（阶段 6 写入/绘制绑定）*/

    SlrLight lights[SLR_MAX_LIGHTS];   /* 光照槽表（SL 侧 Light.applyTo 写入）*/
    float ambient;                     /* 环境光强度（默认 1.0 = 无光照效果）*/

    /* N2a shadow map：深度专用目标（懒创建 512x512，仅平行光 quality>=1
     * 且后端支持时激活；destroy 走 pipeline_release_targets）
     * N2b CSM：4 级联 v 分段（图集 1x4 分区），级联 0 复用单级语义 */
    SlrRhiTarget* rt_shadow;
    int   shadow_on;                    /* 本帧 shadow pass 已执行（绑定+VP 就绪）*/
    int   shadow_map_size;              /* 深度图边长（正方形，默认 512）*/
    int   shadow_cascades;              /* N2b：级联数（1 = 单级 N2a；4 = CSM）*/
    float shadow_light_vp[4][16];       /* N2b：每级光空间 VP（[0] = N2a 单级位）*/
    float shadow_split[5];              /* N2b：级联 v 边界（split[i]..split[i+1]）*/
    float shadow_bias, shadow_strength;/* 防 acne 偏移 / 阴影强度（0..1）*/

    float clear_color[4];
    /* 后处理参数（v2 Unity Color Adjustments 风：doc/14 v1.1）——中性值 =
     * 旧行为（contrast=1 / filter=(1,1,1) / hue=0 / grain=0 / vigSmooth=1
     * 时逐位等价旧三参公式）；set_post / set_post_params 写入 */
    int post_enabled;
    float post_brightness, post_saturation, post_vignette;
    float post_contrast;                /* 对比度（0..2+，1 = 不变）        */
    float post_vig_smooth;              /* 暗角柔度（0..1，1 = 旧标准曲线） */
    float post_hue;                     /* 色相偏移（角度制，0 = 不变）     */
    float post_grain;                   /* 胶片颗粒强度（0 = 关）           */
    float post_grain_seed;              /* 颗粒随机种子（时间驱动）         */
    int   post_tonemap;                 /* 0 = 关 / 1 = Reinhard（LDR 近似）*/
    float post_filter[3];               /* 颜色滤片（乘法 tint，1,1,1 = 不变）*/

    /* P6 渐变天空背景：sky_on=1 时每个相机的清屏（COLOR 位）之后画全屏
     * 渐变 quad（顶->底线性插值，无深度写入，物体随后正常覆盖）；
     * set_sky_color / set_sky_on 写入 */
    int   sky_on;
    float sky_top[3];
    float sky_bottom[3];
    /* doc/13 §2.1 第二步：cubemap 天空纹理句柄（0 = 走渐变路径；
     * set_sky_cube 写入，stage 7 天空绘制按它分派 draw_sky_cube）*/
    int64_t sky_cube;
    /* doc/13 §2.1 透视相机专项：cube 天空采样基向量（11 float：
     * fwd3/right3/up3/tanX/tanY；默认 fwd=(0,0,-1) right=(1,0,0)
     * up=(0,1,0) tan=(1,1) —— 与旧固定公式 normalize(vUv*2-1, -1)
     * 逐位同效，向后兼容）；set_sky_cube_cam 写入 */
    float sky_cam[11];

    /* N4a 软光追：场景状态（RaySet* 命令累积写）+ 输出纹理（RayRender
     * 命令产出并写入描述符槽；纹理归管线持有，pipeline_release_targets
     * 统一销毁，尺寸变化时销毁重建） */
    SlrRayScene ray;
    int64_t ray_tex;
    int ray_tex_w, ray_tex_h;

    float time, last_time, dt, total_time;
    int64_t frame_count;

    /* N3 异步渲染：async_mode=1 时命令流入队即返、worker 线程回放；
     * 0 = 同步直接回放（默认）。模式经流内 AsyncMode 控制命令切换。*/
    SlrAsyncQueue async;
    int async_mode;

    /* ── v3.6 AA + MotionVectors（尾部追加，set_aa/set_motion 写入）── */
    /* AA：请求值与实际生效值分离——后端无 target_create_ms（VK）或
     * 创建失败时 msaa_active=0 回退单采样（stat MSAA_SAMPLES 读实际值）。
     * msaa 变化触发 targets 重建（set_aa 内部）。
     * FXAA：FS_POST 内嵌前段（GL/GLES/D3D11 运行期 HLSL 消费；
     * VK SPIR-V 冻结忽略），fxaa_span = 采样延伸上限（默认 8）。 */
    int   aa_msaa;          /* 请求采样数（0/1 = 关）*/
    int   aa_msaa_active;   /* 实际生效采样数（0 = 单采样）*/
    int   fxaa_on;          /* FXAA 开关（0 = 关，输出逐位 = 旧版）*/
    float fxaa_span;        /* FXAA spanMax（默认 8.0）*/
    SlrRhiTarget* rt_resolve;   /* MSAA resolve 中转（单采样；仅 msaa_active 时存在）*/
    /* MotionVectors：rt_motion（无深度，懒创建）+ 上帧变换快照。
     * RG 通道编码 = 速度*0.5+0.5（0.5 = 静止），B=0 A=1；
     * 快照在阶段 10 落盘（阶段 6 组算 prev 块消费）：
     *   obj_prev_*  = 上帧对象 pos/rot/scale（valid=0 首帧/新建 -> prev=cur）；
     *   cam_prev_*  = 上帧相机视域 (l,r,b,t)（相机运动随 MVP 进速度）。 */
    int   mv_on;
    SlrRhiTarget* rt_motion;
    float obj_prev_pos[SLR_MAX_OBJECTS][3];
    float obj_prev_rot[SLR_MAX_OBJECTS];
    float obj_prev_scale[SLR_MAX_OBJECTS][2];
    int   obj_prev_valid[SLR_MAX_OBJECTS];
    float cam_prev_ext[SLR_MAX_CAMERAS][4];
    int   cam_prev_valid[SLR_MAX_CAMERAS];

    /* ── v3.7 TAA（尾部追加，set_taa 写入）──
     * taa_on=0 时零开销（post 输入 = 原场景色）；taa_on=1 且后端支持
     * taa_resolve 时：阶段 11 前以 history ping-pong（rt_taa_hist[2]，
     * taa_hist_idx 读旧写新）做时域累积；依赖 motion pass 的速度图
     * （mv_on=0 时 set_taa 自动开启 motion——TAA 必须有速度输入）。
     * taa_reset=1 时本帧强制忽略历史（首帧/尺寸变化/开关切换）。 */
    int   taa_on;
    float taa_blend;            /* 当前帧权重（0..1，默认 0.1）*/
    int   taa_reset;            /* 本帧忽略历史 */
    int   taa_hist_idx;         /* 下帧读的 history 槽（0/1）*/
    SlrRhiTarget* rt_taa_hist[2];
    SlrRhiTarget* rt_taa_cur;   /* TAA 输出（post 的输入，替代 src）*/

    /* ── v3.8 Motion Blur（尾部追加）──
     * mb_on=1 且后端有 motion_blur + 速度图时：阶段 10.6 以 rt_motion
     * 为速度输入，把 src（场景/TAA 输出）模糊到 rt_mb；阶段 11 post
     * 从 rt_mb 读（再走 FXAA/调色）。mb_on=0 零开销。 */
    int   mb_on;
    float mb_scale;             /* 速度倍率（默认 1.0）*/
    int   mb_samples;           /* 采样数（默认 8）*/
    SlrRhiTarget* rt_mb;
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
void rhi_set_thread_handoff(int on);   /* N3：async 常态下主线程 exit 顺带
                                        * 解绑 context（见 sl_render.c）*/

/* sl_texture.c：纹理注册表（管线/对象跨文件取用） */
SlrTexRes* tex_from_handle(int64_t h);
/* sl_texture.c：top-down RGBA8 像素块 -> 翻行(bottom-up) -> RHI 上传 ->
 * 注册表占位（调用方须已 rhi_enter；返回句柄 0 = 失败）。
 * N4a 起非 static：sl_ray.c 的 RayRender 输出纹理复用本通路。 */
int64_t texture_register(int w, int h, const unsigned char* topdown);

/* sl_pipeline.c：管线句柄解析与渲染目标回收（slr_uninit 也调用） */
SlrPipeline* pipe_from_handle(int64_t h);
void pipeline_release_targets(SlrPipeline* p);

/* Pipeline/sl_ray.c：软光追场景写入口（SLMC RaySet* 命令回放调用；
 * f8 = [cx cy cz r cr cg cb reflect]，f4/f3 同序）+ 渲染入口（RayRender
 * 命令；逐像素 whitted 求交 -> top-down RGBA8 -> texture_register ->
 * 写描述符槽 tex_slot，与 SLR_CMD_SET_TEXTURE 同路径） */
void ray_scene_reset(SlrRayScene* s);
void ray_set_sphere(SlrRayScene* s, int idx, const float* f8);
void ray_set_light(SlrRayScene* s, const float* f4);
void ray_set_ground(SlrRayScene* s, const float* f4);
void ray_set_camera(SlrRayScene* s, const float* f4);
void ray_set_background(SlrRayScene* s, const float* f3);
int  ray_render(SlrPipeline* p, int tex_slot, int w, int h);

/* sl_light.c：帧级光照块组装（阶段 6 调用；环境光 + 首个平行光 + 首个聚光）*/
void light_build_block(SlrPipeline* p, SlrLightBlock* out);

/* sl_light.c：阴影投射光源查询（阶段 5 调用）：首个启用的平行光方向优先
 * （dir_out = 阴影偏移方向，已含"背离光源"语义），否则首个聚光
 * （返回其槽位；has_pos_out=1 表示带位置，方向需逐物体归一化）。
 * 返回 0 = 无可用光源 -> 不生成阴影。 */
int light_pick_shadow(SlrPipeline* p, float* dir_out, int* has_pos_out,
                      float* pos_out);

/* sl_light.c：N2a shadow map 光源查询（阶段 4.5/5）：首个 shadow_quality>=1
 * 的平行光（dir_out = 表面->光源方向）；返回 -1 = 无（走黑斑回退）。 */
int light_pick_shadowmap(SlrPipeline* p, float* dir_out);

/* Pipeline/sl_cmd.c：N3 异步提交队列（execute_stream 内部分流）。
 *   cmd_async_switch(p, mode)  0->1 惰性启 worker（主线程解绑 context 移交
 *                              worker）；1->0 drain 后停 worker 并绑回主线程。
 *                              内部自带 drain，仅在锁外（rhi_exit 之后）调用。
 *   cmd_async_drain(p)         等待全部已入队流回放完成（completed ==
 *                              submitted；无 RHI 锁，可在任意时刻调用）。
 *   cmd_async_shutdown(p)      管线销毁前的安全停机（drain + 停 worker +
 *                              释放槽块/同步原语）。必须在实际持有 RHI 锁
 *                              之前调用——worker 回放需要 rhi_enter。*/
void cmd_async_switch(SlrPipeline* p, int mode);
void cmd_async_drain(SlrPipeline* p);
void cmd_async_shutdown(SlrPipeline* p);

#ifdef __cplusplus
}
#endif

#endif /* SL_RENDER_INTERNAL_H */
