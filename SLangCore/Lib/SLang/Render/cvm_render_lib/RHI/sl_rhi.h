/* =========================================================================
 * sl_rhi.h —— 渲染硬件抽象层（RHI，Render Hardware Interface）
 *
 * SLangRender 定位是"渲染中间层"：13 阶段管线逻辑在管线层（Pipeline/）
 * 走下来，经本抽象层落到不同操作系统的不同驱动后端，渲染出一致效果：
 *
 *   Pipeline 层（平台无关）           RHI 后端（平台/驱动相关）
 *   --------------------------        --------------------------------
 *   sl_pipeline.c / sl_render.c  -->  RHI/sl_rhi_gl.c     Windows WGL + GL 3.3
 *   （13 阶段 + v1 + 纹理注册）       RHI/sl_rhi_d3d11.cpp Windows D3D11
 *                                     RHI/sl_rhi_vk.cpp   Vulkan（SPIR-V 固化）
 *                                     RHI/sl_rhi_gles.c   EGL + GLES 3.0
 *
 * 设计约定：
 *   - 后端 = 一张 slr_rhi 函数表（vtable）；sl_render.c 持注册表
 *     { "gl", "d3d11", ... }，slr_init_backend() 选择后端，slr_init()
 *     默认 gl（向后兼容）；
 *   - 渲染目标 / 纹理均为后端私有不透明指针（slr_rhi_target* / void*），
 *     管线层只持有与传递，不解引用；
 *   - 像素契约（跨后端一致，是"同效果"的验收标准）：
 *       * 纹理上传：RGBA8 行主序，首行 = 图像底部（GL 行序；上传前
 *         由 sl_texture.c 统一翻转，后端原样入显存）；
 *       * 回读输出：RGBA8 行主序，首行 = 图像顶部（top-down，行序
 *         翻转由各后端自理：GL glReadPixels 产出 bottom-up 需翻，
 *         D3D11 staging Map 天然 top-down）；
 *   - 相机视口坐标沿用 GL 约定（原点左下，y 向上），D3D11 后端内部
 *     换算 TopLeftY = target_h - (y + h)；
 *   - NDC 语义各后端一致（y=+1 为视口顶，z 语义由后端各自映射）。
 * ========================================================================= */
#ifndef SL_RHI_H
#define SL_RHI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 后端渲染目标（颜色 + 可选深度；后端私有结构）*/
typedef struct slr_rhi_target slr_rhi_target;

/* 后端纹理（后端私有结构，管线层以 void* 传递）*/

/* ===================================================================== */
/* RHI 操作集（vtable）                                                    */
/* ===================================================================== */
typedef struct slr_rhi
{
    const char* name;          /* 后端注册名（slr_backend_list / init_backend）*/

    /* ---- 生命周期 ---- */
    int  (*init)(void);        /* 设备/上下文创建（不含共享资源）*/
    void (*shutdown)(void);    /* 设备/上下文销毁（free_shared 之后调用）*/
    void (*info)(char* renderer, int rcap, char* version, int vcap);

    /* ---- 帧级进出（sl_render.c 的 rhi_enter/rhi_exit 转发）----
     * 后端 enter 只做：加锁 + 上下文/设备就绪化（GL: wglMakeCurrent；
     * D3D11: 立即上下文加锁）。s_ready 检查与错误清零由外层负责。*/
    int  (*enter)(void);
    void (*exit)(void);

    /* ---- 进程级共享资源（init 成功后构建一次）----
     * 着色器程序集（SLR_PROG_* 槽位）+ 4 张静态网格 + PerDraw 常量缓冲 */
    int  (*make_shared)(void);
    void (*free_shared)(void);

    /* ---- 渲染目标 ---- */
    slr_rhi_target* (*target_create)(int w, int h, int with_depth);
    void (*target_destroy)(slr_rhi_target* t);

    /* ---- 纹理（rgba 首行 = 图像底部，行主序 RGBA8）---- */
    void* (*texture_create)(int w, int h, const unsigned char* rgba);
    void (*texture_destroy)(void* tex);

    /* ---- 管线 pass（调用方已 enter）---- */
    /* 阶段 1：绑定场景目标 + 全视口 + 整幅清（色 + 深）+ 不透明初始状态 */
    void (*begin_scene)(slr_rhi_target* t, int w, int h, const float* clear_rgba);
    /* 阶段 7/9 逐相机：重新绑定场景目标 + 相机视口 + 可选局部清屏
     * （GL: scissor + glClear；D3D11: 清屏 quad 模拟整目标清屏限制）
     * 坐标为 GL 约定（原点左下，y 向上），target_h 用于 D3D11 翻转 */
    void (*camera_begin)(slr_rhi_target* t, int x, int y, int w, int h,
                         int target_h, int clear_flags, const float* clear_rgba);
    /* 渲染状态：0 = 不透明（深度测+写、无混合）1 = 透明（后->前混合、深度不写）*/
    void (*set_state)(int transparent);
    /* 阶段 6：PerDraw 常量缓冲整块上传（mat4[64] + vec4[64]）*/
    void (*upload_perdraw)(const void* data, int bytes);
    /* 单绘制项：prog = SLR_PROG_PFLAT/PTEX（v1 为 FLAT/TEX），slot =
     * PerDraw 槽位，mesh = 0..3 静态网格，tex = NULL 表示纯色 */
    void (*draw_item)(int prog, int slot, int mesh, void* tex);

    /* 阶段 11：后处理（enabled=0 走纯拷贝）scene -> post */
    void (*post_process)(slr_rhi_target* dst, slr_rhi_target* src, int w, int h,
                         int enabled, float brightness, float saturation, float vignette);
    /* 阶段 12：全屏拷贝 post -> final */
    void (*blit)(slr_rhi_target* dst, slr_rhi_target* src, int w, int h);
    /* 阶段 13：回读（top-down RGBA8 写入 dst_ptr 指向的 w*h*4 块）*/
    void (*readback)(slr_rhi_target* t, int w, int h, int64_t dst_ptr);

    /* ---- v1 直连层 ---- */
    /* 绑定目标 + 视口 + 整幅清（色 + 深）*/
    void (*v1_clear)(slr_rhi_target* t, int w, int h, const float* clear_rgba);
    /* 居中大三角：prog = SLR_PROG_FLAT/TEX，单位矩阵 MVP + 纯色/纹理 */
    void (*v1_draw)(slr_rhi_target* t, int w, int h,
                    int prog, const float* mvp, const float* color_rgba, void* tex);
} slr_rhi;

/* 当前后端（slr_init / slr_init_backend 设置；未初始化为 NULL）*/
extern const slr_rhi* g_rhi;

/* ---- 各后端实现（返回 NULL = 编入但当前环境不可用）---- */
const slr_rhi* slr_rhi_gl(void);      /* RHI/sl_rhi_gl.c     */
const slr_rhi* slr_rhi_d3d11(void);   /* RHI/sl_rhi_d3d11.cpp*/
const slr_rhi* slr_rhi_vk(void);      /* RHI/sl_rhi_vk.cpp   */
const slr_rhi* slr_rhi_gles(void);    /* RHI/sl_rhi_gles.c   */

#ifdef __cplusplus
}
#endif

#endif /* SL_RHI_H */
