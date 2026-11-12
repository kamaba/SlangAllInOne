/* =========================================================================
 * vm_sl_render.h —— SLangRender 原生渲染库对外契约（v3，多后端 RHI）
 *
 * sl_render_lib.dll：渲染中间层。13 阶段管线逻辑平台无关，经 RHI
 * 抽象层落到不同操作系统/驱动后端，渲染效果跨后端一致：
 *   "gl"    Windows WGL + OpenGL 3.3 core（默认，向后兼容）
 *   "d3d11" Windows Direct3D 11（运行期加载，零 .lib 依赖）
 *   （后续接入："vk" Vulkan、"gles" EGL/GLES 3.0）
 *
 * v1 低层 API（RenderContext 直连渲染目标）保留兼容；v2 Unity 风格
 * 13 阶段渲染管线（slr_pipeline_* / slr_object_* / slr_texture_*）。
 *
 * 约定：
 *   - 句柄均为 1 起始非 0 值（0 = 无效）；
 *   - 返回 int 的状态函数：1 = 成功，0 = 失败（SL 侧 sig 用 ->bool 直取）；
 *   - 失败原因经 slr_last_error()（粘性：每次原生入口先清零）+
 *     slr_error_string() 取得；
 *   - 像素块契约：RGBA8、每像素 4 字节、行主序、顶行在前（top-down），
 *     与 QT QLabel.setPixmapRgba / QImage Format_RGBA8888 一致；
 *   - FFI 参数上限 6（SL_FFI_MAX_ARGS），新增函数签名均不超过 6 参。
 * ========================================================================= */
#ifndef VM_SL_RENDER_H
#define VM_SL_RENDER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- 导出宏：FFI 运行期经 GetProcAddress 直取符号；声明缺
 *      __declspec(dllexport) 时 DLL 空导出（LoadLibrary 成功但
 *      GetProcAddress 全 MISS -> SL 兜底 "not available"）。 ---- */
#if defined(_WIN32) && defined(_MSC_VER)
#  define SLR_API __declspec(dllexport)
#else
#  define SLR_API
#endif

/* ---- 错误码（SLang.Render 常量逐值一致，勿改动既有值）---- */
enum
{
    SLR_OK                 = 0,
    SLR_E_OPENGL_MISSING   = -1,   /* opengl32.dll 加载失败            */
    SLR_E_WINDOW           = -2,   /* 隐藏窗口创建失败                  */
    SLR_E_PIXEL_FORMAT     = -3,   /* 像素格式不可用                    */
    SLR_E_CONTEXT          = -4,   /* GL 上下文创建失败                  */
    SLR_E_NO_ARB           = -5,   /* WGL 扩展函数缺失                  */
    SLR_E_GL_SYMBOL        = -6,   /* GL 3.3 符号解析失败               */
    SLR_E_NOT_INITIALIZED  = -7,   /* 未初始化                          */
    SLR_E_BAD_HANDLE       = -8,   /* 无效句柄                          */
    SLR_E_BAD_PARAM        = -9,   /* 参数非法                          */
    SLR_E_FBO              = -10,  /* FBO 不完整                        */
    SLR_E_SHADER           = -11,  /* 着色器编译/链接失败               */
    SLR_E_MEMORY           = -12,  /* 内存分配失败                      */
    SLR_E_CONTEXT_CURRENT  = -13,  /* wglMakeCurrent 失败               */
    /* v2 新增 */
    SLR_E_OBJECT           = -14,  /* 场景对象无效/越界                 */
    SLR_E_TEXTURE          = -15,  /* 纹理无效                          */
    SLR_E_PIPELINE         = -16,  /* 管线无效/未初始化                 */
    SLR_E_STATE            = -17,  /* 阶段状态机非法（阶段序错误等）      */
    SLR_E_LIMIT            = -18,  /* 资源上限（对象/纹理/管线数量）      */
    SLR_E_IMAGE            = -19,  /* 图片文件解码失败（WIC）            */
    /* v3 新增 */
    SLR_E_BACKEND          = -20   /* 后端不可用/未知后端名              */
};

/* ---- 统计项 id（slr_pipeline_stat）---- */
enum
{
    SLR_STAT_FRAME            = 0,   /* 累计帧数（beginFrame 计数）        */
    SLR_STAT_VISIBLE          = 1,   /* 本帧剔除后可见对象数               */
    SLR_STAT_CULLED           = 2,   /* 本帧被剔除对象数                   */
    SLR_STAT_DRAW_CALLS       = 3,   /* 本帧总绘制调用（含后处理全屏 pass） */
    SLR_STAT_OPAQUE_DRAWS     = 4,   /* 不透明段绘制数                     */
    SLR_STAT_TRANSPARENT_DRAWS= 5,   /* 透明段绘制数                       */
    SLR_STAT_POST_ENABLED     = 6,   /* 后处理开关                         */
    SLR_STAT_LAST_STAGE       = 7,   /* 最近执行的管线阶段（1..13）        */
    SLR_STAT_OBJECT_COUNT     = 8,   /* 场景对象总数                       */
    SLR_STAT_CHUNK_COUNT      = 9,   /* 本帧 shader 分块数                 */
    SLR_STAT_LAYERS_MASK      = 10,  /* 本帧实际绘制的 layer 位掩码        */
    SLR_STAT_UPLOAD_COUNT     = 11,  /* 本帧向 GPU 传入的数据块数（UBO）   */
    SLR_STAT_TIME_MS          = 12,  /* 当前帧时间（int 毫秒）             */
    SLR_STAT_DT_MS            = 13,  /* 帧间隔（int 毫秒）                 */
    SLR_STAT_TEXTURE_COUNT    = 14,  /* 全局纹理数                         */
    SLR_STAT_PROGRAM_SWITCHES = 15,  /* 本帧着色器程序切换次数              */
    SLR_STAT_CAMERA_COUNT     = 16   /* 本帧实际参与渲染的相机数            */
};

/* ---- 网格类型 ---- */
enum
{
    SLR_MESH_TRIANGLE = 0,   /* 单位三角形（中心原点）    */
    SLR_MESH_QUAD     = 1     /* 单位四边形（中心原点，uv）*/
};

/* ---- 动画模式 ---- */
enum
{
    SLR_ANIM_NONE      = 0,
    SLR_ANIM_HUE_CYCLE = 1   /* 颜色随时间色相循环        */
};

/* ================= 生命周期 / 诊断 ================= */
SLR_API int         slr_init(void);          /* 默认后端 "gl"（向后兼容）*/
SLR_API int         slr_init_backend(const char* backend_utf8); /* 指定后端初始化 */
SLR_API int         slr_uninit(void);
SLR_API const char* slr_backend_list(void);  /* 可用后端（逗号分隔，如 "gl,d3d11"）*/
SLR_API const char* slr_current_backend(void); /* 当前后端名（未初始化 "none"）*/
SLR_API int         slr_last_error(void);
SLR_API const char* slr_error_string(int err);
SLR_API const char* slr_error_detail(void);
SLR_API const char* slr_renderer_string(void);
SLR_API const char* slr_version_string(void);

/* ================= v1 低层：RenderContext（直连 FBO） ================= */
SLR_API int64_t slr_context_create(int w, int h);
SLR_API int     slr_context_destroy(int64_t ctx);
SLR_API int     slr_context_resize(int64_t ctx, int w, int h);
SLR_API int     slr_context_width(int64_t ctx);
SLR_API int     slr_context_height(int64_t ctx);
SLR_API int64_t slr_frame_count(int64_t ctx);
SLR_API int     slr_clear(int64_t ctx, float r, float g, float b, float a);
SLR_API int     slr_draw_triangle(int64_t ctx, float r, float g, float b);
SLR_API int     slr_read_pixels(int64_t ctx, int64_t dst_ptr);
SLR_API int     slr_render_frame(int64_t ctx, float r, float g, float b, int64_t dst_ptr);

/* ================= v2：纹理（全局注册表） ================= */
/* SL 传入 top-down RGBA8 像素块（内部翻行为 GL bottom-up 上传） */
SLR_API int64_t slr_texture_create_rgba(int w, int h, int64_t data_ptr);
/* 从图片文件（PNG/JPEG/BMP 等，WIC 解码）创建纹理，返回句柄 */
SLR_API int64_t slr_texture_load_file(const char* path_utf8);
SLR_API int     slr_texture_destroy(int64_t tex);
SLR_API int     slr_texture_count(void);

/* ================= v3.1：动态网格（3D/程序化几何通道） =================
 * verts_ptr 指向三角形列表（pos2+uv2 交错，stride 16B；SL 侧经
 * Memory.writeF32 填充，ptr sig 传 Int64）。对象 mesh_kind = 4+slot
 * 引用该槽（slr_object_create 允许 4..4+SLR_CUSTOM_MESHES-1）。
 * 可每帧重复上传（GL/GLES/D3D11 整块重传；VK 持久映射直写）。 */
SLR_API int     slr_mesh_upload(int slot, int64_t verts_ptr, int vert_count);

/* ================= v2.1：多相机（管线内相机槽表） =================
 * 槽 0 为默认相机（slr_pipeline_set_camera 继续写槽 0，保持兼容）。
 * 渲染时按 depth 升序逐相机执行：视口/清屏 -> 剔除 -> 绘制。
 * clear_flags 位：bit0=清颜色，bit1=清深度。 */
SLR_API int64_t slr_camera_create(int64_t p, int depth);
SLR_API int     slr_camera_destroy(int64_t p, int64_t cam);
SLR_API int     slr_camera_set_enabled(int64_t p, int64_t cam, int enabled);
SLR_API int     slr_camera_set_depth(int64_t p, int64_t cam, int depth);
SLR_API int     slr_camera_set_cull_mask(int64_t p, int64_t cam, int mask);
SLR_API int     slr_camera_set_extents(int64_t p, int64_t cam,
                                       float l, float r, float b, float t);
SLR_API int     slr_camera_set_viewport(int64_t p, int64_t cam,
                                        int x, int y, int w, int h);
SLR_API int     slr_camera_set_clear_color(int64_t p, int64_t cam,
                                           float r, float g, float b, float a);
SLR_API int     slr_camera_set_clear_flags(int64_t p, int64_t cam, int flags);
SLR_API int     slr_camera_count(int64_t p);

/* ================= v2：管线（13 阶段 Unity 风格流程） ================= */
SLR_API int64_t slr_pipeline_create(int w, int h);
SLR_API int     slr_pipeline_destroy(int64_t p);
SLR_API int     slr_pipeline_resize(int64_t p, int w, int h);
SLR_API int64_t slr_pipeline_frame_count(int64_t p);

/* 相机：cullingMask + 正交视域（NDC 前的世界系包围盒） */
SLR_API int     slr_pipeline_set_camera(int64_t p, int cull_mask,
                                        float l, float r, float b, float t);
SLR_API int     slr_pipeline_set_clear_color(int64_t p, float r, float g, float b, float a);
/* 后处理：亮度 / 饱和度 / 暗角（enable=0 时纯拷贝） */
SLR_API int     slr_pipeline_set_post(int64_t p, int enable,
                                      float brightness, float saturation, float vignette);

/* ---- 场景对象 ---- */
SLR_API int64_t slr_object_create(int64_t p, int mesh_kind);
SLR_API int     slr_object_destroy(int64_t p, int64_t obj);
SLR_API int     slr_object_set_visible(int64_t p, int64_t obj, int visible);
SLR_API int     slr_object_set_layer(int64_t p, int64_t obj, int layer);
SLR_API int     slr_object_set_queue(int64_t p, int64_t obj, int queue);
SLR_API int     slr_object_set_position(int64_t p, int64_t obj, float x, float y, float z);
SLR_API int     slr_object_set_rotation_z(int64_t p, int64_t obj, float rz);
SLR_API int     slr_object_set_scale(int64_t p, int64_t obj, float sx, float sy);
SLR_API int     slr_object_set_color(int64_t p, int64_t obj, float r, float g, float b, float a);
SLR_API int     slr_object_set_texture(int64_t p, int64_t obj, int64_t tex);
SLR_API int     slr_object_set_animated(int64_t p, int64_t obj, int mode, float speed);
SLR_API int     slr_object_count(int64_t p);

/* ---- 13 阶段（见 sl_render_lib.c 顶部注释的阶段表） ---- */
SLR_API int slr_pipeline_begin_frame(int64_t p, float time);          /* 1 渲染开始   */
SLR_API int slr_pipeline_prepare_materials(int64_t p);                /* 2 准备物料   */
SLR_API int slr_pipeline_early_update(int64_t p);                     /* 3 提前更新   */
SLR_API int slr_pipeline_cull_layers(int64_t p);                      /* 4 渲染层分层 */
SLR_API int slr_pipeline_assemble_layer_data(int64_t p);              /* 5 层整理数据 */
SLR_API int slr_pipeline_upload_render_data(int64_t p);               /* 6 传GPU数据  */
SLR_API int slr_pipeline_render_shader_chunks(int64_t p);             /* 7 分块渲染   */
SLR_API int slr_pipeline_update_core_time(int64_t p);                /* 8 核心时间   */
SLR_API int slr_pipeline_render_shader_segments(int64_t p);           /* 9 分段渲染   */
SLR_API int slr_pipeline_assemble_rendered_layers(int64_t p);        /* 10 整理图层 */
SLR_API int slr_pipeline_post_process(int64_t p);                    /* 11 后处理    */
SLR_API int slr_pipeline_integrate_layers(int64_t p);                /* 12 逻辑整合  */
SLR_API int slr_pipeline_output_render_texture(int64_t p, int64_t dst_ptr); /* 13 输出  */

/* 一键全流程（阶段 1..13 依序） */
SLR_API int slr_pipeline_render_frame(int64_t p, float time, int64_t dst_ptr);

/* 统计（见 SLR_STAT_* 枚举） */
SLR_API int slr_pipeline_stat(int64_t p, int stat_id);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_RENDER_H */
