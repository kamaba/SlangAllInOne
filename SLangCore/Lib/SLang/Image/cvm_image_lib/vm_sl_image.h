/* =========================================================================
 * vm_sl_image.h —— SLangImage 原生图像编解码库对外契约（v1）
 *
 * sl_image_lib.dll：图像读写中间层，解码/编码本体由两组开源/系统后端承担：
 *   "stb"  stb_image v2.31 + stb_image_write v1.17（public domain / MIT-0，
 *          third_party/stb/ 目录整文件内置，Codec/sl_image_stb.c 单点编译）
 *          读：JPEG(baseline+progressive) PNG BMP GIF TGA PSD HDR PIC PNM
 *          写：PNG JPEG BMP TGA (HDR)
 *   "wic"  Windows Imaging Component（系统组件 windowscodecs，运行期 COM）
 *          读：BMP GIF ICO JPEG PNG TIFF (+WebP 若系统装了 WebP 编解码器)
 *          写：BMP GIF JPEG PNG TIFF
 *
 * 约定（与 vm_sl_render.h / vm_sl_cuda.h 一致）：
 *   - 句柄均为 1 起始非 0 值（0 = 无效）；
 *   - 返回 int 的状态函数：1 = 成功，0 = 失败（SL 侧 sig 用 ->bool 直取）；
 *   - 失败原因经 sli_last_error()（粘性：每次原生入口先清零）+
 *     sli_error_string() / sli_error_detail() 取得；
 *   - 像素契约：RGBA8、每像素 4 字节、行主序、顶行在前（top-down），
 *     与 QT QLabel.setPixmapRgba / QImage Format_RGBA8888 一致；
 *   - blob = C 侧堆上字节块句柄（编码产物），读回/落盘后须 sli_blob_free；
 *   - FFI 参数上限 6（SL_FFI_MAX_ARGS），新增函数签名均不超过 6 参。
 * ========================================================================= */
#ifndef VM_SL_IMAGE_H
#define VM_SL_IMAGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLI_API __declspec(dllexport)
#else
#  define SLI_API
#endif

/* ---- 错误码（Image.ImageErrorCode 语义对齐，见 ImageFormat.sl）----
 * 负值段为库自身诊断（与 slr_ 错误码风格一致，勿与 EImageFormat 混用）。 */
enum
{
    SLI_OK                 = 0,
    SLI_E_NOT_INITIALIZED  = -1,   /* 库未初始化                    */
    SLI_E_BAD_PARAM        = -2,   /* 参数非法（空指针/尺寸<=0）    */
    SLI_E_BAD_HANDLE       = -3,   /* 无效句柄                      */
    SLI_E_MEMORY           = -4,   /* 分配失败                      */
    SLI_E_LIMIT            = -5,   /* 句柄槽位耗尽                  */
    SLI_E_UNSUPPORTED      = -6,   /* 格式本库不支持（如 SVG）      */
    SLI_E_DECODE           = -7,   /* 解码失败（数据损坏/截断）     */
    SLI_E_ENCODE           = -8,   /* 编码失败                     */
    SLI_E_IO               = -9,  /* 文件读写失败                  */
    SLI_E_TOO_LARGE        = -10  /* 超出尺寸/内存上限             */
};

/* ---- 文件格式 id：与 SL 侧 EImageFormat 枚举逐值一致（勿改动） ---- */
enum
{
    SLI_FMT_UNKNOWN = 0,
    SLI_FMT_BMP     = 1,
    SLI_FMT_PNG     = 2,
    SLI_FMT_JPEG    = 3,
    SLI_FMT_GIF     = 4,
    SLI_FMT_WEBP    = 5,
    SLI_FMT_SVG     = 6,
    SLI_FMT_TIFF    = 7,
    SLI_FMT_ICO     = 8,
    SLI_FMT_TGA     = 9,
    SLI_FMT_PPM     = 10,
    SLI_FMT_AVIF    = 11,
    SLI_FMT_HEIC    = 12
};

/* ---- 解码输出通道数（req_channels，v1 保留参数）----
 * v1 像素契约恒 RGBA8：无论传何值，解码输出统一 4 通道 top-down。 */
enum
{
    SLI_REQ_DEFAULT = 0,
    SLI_REQ_RGB     = 3,
    SLI_REQ_RGBA    = 4    /* v1 恒按此值处理            */
};

/* ---- 探测出参块（sli_probe_* 的 out_ptr，6 x int32 = 24 字节） ----
 * [0] width  [1] height  [2] srcFormat(SLI_FMT_*)  [3] srcChannels(1..4)
 * [4] hasAlpha(0/1)  [5] isAnimated(0/1)
 */
#define SLI_PROBE_OUT_BYTES 24

/* ================= 生命周期 / 诊断 ================= */
SLI_API int         sli_init(void);            /* 幂等；返回 1=已就绪   */
SLI_API int         sli_uninit(void);
SLI_API int         sli_last_error(void);
SLI_API const char* sli_error_string(int err);
SLI_API const char* sli_error_detail(void);    /* 粘性细节（stb/wic 原因）*/
SLI_API const char* sli_version_string(void);
SLI_API const char* sli_codec_list(void);      /* 如 "stb,wic"          */

/* ================= 探测（不解码像素） ================= */
/* 读文件头写探测块；不解码整图。返回 1=成功。path 为 UTF-8。 */
SLI_API int         sli_probe_file(const char* path_utf8, int64_t out_ptr);
/* 内存字节探测：data_ptr/size 指向文件字节（top-down 无关，原样字节）。 */
SLI_API int         sli_probe_mem(int64_t data_ptr, int64_t size, int64_t out_ptr);

/* ================= 解码（img 句柄，C 侧持有像素） ================= */
/* 返回 img 句柄（0=失败）。像素契约 RGBA8 top-down（w*h*4）。
 * stb 解码 JPEG/PNG/BMP/GIF/TGA/PSD/HDR/PIC/PNM；WIC 兜底 TIFF/ICO/WebP。
 * req_channels: SLI_REQ_RGBA(4) 推荐 / SLI_REQ_RGB(3)。 */
SLI_API int64_t     sli_decode_file(const char* path_utf8, int req_channels);
SLI_API int64_t     sli_decode_mem(int64_t data_ptr, int64_t size, int req_channels);

SLI_API int         sli_image_width(int64_t img);
SLI_API int         sli_image_height(int64_t img);
SLI_API int         sli_image_channels(int64_t img);     /* 解码输出通道数   */
SLI_API int         sli_image_src_format(int64_t img);   /* SLI_FMT_* 源格式 */
SLI_API int         sli_image_copy_pixels(int64_t img, int64_t dst_ptr, int64_t cap);
SLI_API int         sli_image_free(int64_t img);

/* ================= 编码（blob 句柄，C 侧持有压缩字节） ================= */
/* pixels_ptr 指向 RGBA8 top-down 像素块（w*h*4）。fmt = SLI_FMT_*；
 * quality 0..100（无损格式忽略）。返回 blob 句柄（0=失败）。
 * stb 写 PNG/JPEG/BMP/TGA；WIC 写 TIFF/GIF。 */
SLI_API int64_t     sli_encode_mem(int fmt, int quality, int w, int h, int64_t pixels_ptr);

SLI_API int64_t     sli_blob_size(int64_t blob);              /* 字节数   */
SLI_API int         sli_blob_copy(int64_t blob, int64_t dst_ptr, int64_t cap);
SLI_API int         sli_blob_save(int64_t blob, const char* path_utf8);
SLI_API int         sli_blob_free(int64_t blob);

/* ======================= GIF 动画（多帧拆解 / 合成） ======================= */
/* 2026-11-26：动画拆解与合成。
 *   解码：stb 动画装载器（stbi_load_gif_from_memory），每帧已按处置语义
 *         合成为整画布 RGBA8；帧延迟毫秒、NETSCAPE 循环数透出。
 *   编码：自有 GIF89a 写入器（全局调色板量化 + LZW），逐帧喂入整画布像素。
 * 对应 SL 侧 Gif.sl（GifFrame/GifDocument/GifEncoder/Gif 门面）。 */

/* 动画解码：返回动画句柄（0 = 失败，原因进粘性错误）。
 * 每帧像素契约同上（w*h*4，帧已含处置合成结果）。 */
SLI_API int64_t     sli_gif_decode_file(const char* path_utf8);
SLI_API int64_t     sli_gif_decode_mem(int64_t data_ptr, int64_t size);

/* 动画元数据（句柄由 decode 获得；无效句柄置粘性错误并返回 0/-1） */
SLI_API int         sli_gif_width(int64_t gif);
SLI_API int         sli_gif_height(int64_t gif);
SLI_API int         sli_gif_frame_count(int64_t gif);
/* NETSCAPE 循环数原值：-1 = 无扩展（播放一次），0 = 无限循环，>0 = 额外重复次数 */
SLI_API int         sli_gif_loop_count(int64_t gif);
/* 第 frame 帧延迟（毫秒；越界返回 -1） */
SLI_API int         sli_gif_frame_delay(int64_t gif, int frame);
/* 第 frame 帧整画布像素拷出（dst_ptr/cap 契约同 sli_blob_copy；成功返回 1） */
SLI_API int         sli_gif_frame_pixels(int64_t gif, int frame,
                                        int64_t dst_ptr, int64_t cap);
SLI_API int         sli_gif_free(int64_t gif);

/* 动画编码：new 建立画布（w/h 必须为正；loop 语义同上，-1 不写 NETSCAPE），
 * add_frame 逐帧喂入整画布 w*h*4 像素 + 毫秒延迟（clamp [0, 655350]），
 * finish 产出 blob（0 = 失败）。finish 后句柄自动失效（可再调 free 兜底，
 * 幂等安全）。 */
SLI_API int64_t     sli_gif_encode_new(int w, int h, int loop);
SLI_API int         sli_gif_encode_add_frame(int64_t enc, int64_t pixels_ptr, int delay_ms);
SLI_API int64_t     sli_gif_encode_finish(int64_t enc);
SLI_API int         sli_gif_encode_free(int64_t enc);

/* ======================= 像素批量运算（sli_op_*，v2） ======================= */
/* 2026-11-28：纯 SL 每像素重循环下沉 C 层（convolve/rotate/resize/合成混合/
 * 通道拆合/格式转换/贴入/填充/翻转/预乘）。与句柄家族不同，这组是裸指针
 * 运算：src/dst/out 指向 SL 侧 Memory.alloc 块（像素契约同上 RGBA8 顶行
 * 在前，Gray8 平面为 w*h 字节），不占句柄槽。
 *   - ctl_ptr 指向 int32 控制块（布局各函数注明，字节序本机 LE）；
 *   - 失败置粘性错误返回 0 —— SL 侧据此回落纯 SL 循环兜底；
 *   - 语义与 SL 侧实现逐位对齐（除法截断 / clamp8 / BT.601 灰度 /
 *     blendOver 浮点合成），测试口径 byte-exact。 */

/* 3x3 卷积（RGBA8，边界复制，RGB 三通道卷积 + offset，alpha 保留中心像素）。
 * ctl = int32[12]：kernel[0..8]（行主序）、scale（>0）、offset。 */
SLI_API int         sli_op_convolve3x3(int64_t src, int64_t dst,
                                       int w, int h, int64_t ctl);
/* 任意角旋转（逆时针为正；dst 预分配 dw*dh*4，圈外透明；mode 0=最近邻
 * 1=双线性）。angle_milli_deg = 度数×1000（i32，规避 VM CallFFIStatic
 * fast path 对 f32 实参的栈封送 bug——坑 9；C 内部换算弧度）。
 * ctl = int32[5]：sw, sh, dw, dh, mode。 */
SLI_API int         sli_op_rotate(int64_t src, int64_t dst,
                                   int64_t ctl, int angle_milli_deg);
/* 缩放（mode 0=最近邻 1=双线性）。ctl = int32[5]：sw, sh, dw, dh, mode。 */
SLI_API int         sli_op_resize(int64_t src, int64_t dst, int64_t ctl);
/* alpha 合成 src over dst（逐像素 blendOver；三块均 w*h*4）。 */
SLI_API int         sli_op_alpha_composite(int64_t dst, int64_t src,
                                           int64_t out, int w, int h);
/* 线性混合 out = a*(1-alpha) + b*alpha（alpha_x1000 = alpha×1000，
 * 0..1000 域外钳制；i32 规避 f32 fast path 封送 bug——坑 9；
 * 三块均 w*h*4）。 */
SLI_API int         sli_op_blend(int64_t a, int64_t b, int64_t out,
                                 int w, int h, int alpha_x1000);
/* 拆通道：RGBA8 -> 4 张 Gray8 平面（各 w*h 字节）。
 * ctl = int32[2]：w, h。 */
SLI_API int         sli_op_split_rgba(int64_t src, int64_t r, int64_t g,
                                     int64_t b, int64_t a, int64_t ctl);
/* 合通道：3 张 Gray8 -> 不透明 Rgba8（三平面 + dst 均 w*h[+*4]）。 */
SLI_API int         sli_op_merge_rgb(int64_t r, int64_t g, int64_t b,
                                     int64_t dst, int w, int h);
/* 合通道：4 张 Gray8 -> Rgba8（alpha 平面生效）。
 * ctl = int32[2]：w, h。 */
SLI_API int         sli_op_merge_rgba(int64_t r, int64_t g, int64_t b,
                                      int64_t a, int64_t dst, int64_t ctl);
/* 像素格式转换（fmt = SL 侧 EPixelFormat 值 1..8；浮点格式 9/10 不支持
 * 返回 0 由 SL 兜底；dst 字节数 = w*h*bytesPerPixel(dst_fmt)）。 */
SLI_API int         sli_op_convert(int64_t src, int64_t dst,
                                    int w, int h, int src_fmt, int dst_fmt);
/* 区域贴入（整块覆盖不混合，越界裁剪）。ctl = int32[6]：dw, dh, sw, sh, x, y。 */
SLI_API int         sli_op_paste(int64_t dst, int64_t src, int64_t ctl);
/* 纯色填充（rgba = 0xRRGGBBAA，与 Std ColorInt.toPackedRgba 布局一致）。 */
SLI_API int         sli_op_fill(int64_t dst, int w, int h, int rgba);
/* 上下翻转（行交换，w*4 字节行）。 */
SLI_API int         sli_op_flip_y(int64_t dst, int w, int h);
/* 左右翻转（行内像素交换，4 字节/像素）。 */
SLI_API int         sli_op_flip_x(int64_t dst, int w, int h);
/* alpha 预乘 / 反预乘（unpre 0=预乘 1=反预乘；直通 alpha 像素）。 */
SLI_API int         sli_op_premultiply(int64_t dst, int w, int h, int unpre);

/* ---- 高级合成家族（v2.1，2026-11-28；仿 Pillow ImageChops/ImageEnhance/
 *      蒙版合成，runoob pillow-advanced 对照）。均为 RGBA8 裸指针块，
 *      语义与 SL 兜底逐位对齐。 */

/* 灰度化（BT.601 加权写回 RGB；alpha 原样保留）。 */
SLI_API int         sli_op_grayscale(int64_t src, int64_t dst, int w, int h);
/* BT.601 灰度均值（0..255 四舍五入；0 = 失败）。Contrast 枢轴用。 */
SLI_API int         sli_op_luma_mean(int64_t src, int w, int h);
/* 通道运算（11 模式；b 在 invert(7) 时忽略）：
 *   0 add: min(255,a+b)          1 subtract: max(0,a-b)
 *   2 multiply: a*b/255          3 screen: 255-(255-a)*(255-b)/255
 *   4 difference: |a-b|          5 lighter: max  6 darker: min
 *   7 invert: 255-a              8 soft_light: (a*(255-b)+b*b/255)/255
 *   9 hard_light: b<128?2ab/255:255-2(255-a)(255-b)/255
 *  10 overlay:    a<128?2ab/255:255-2(255-a)(255-b)/255
 * 作用于全部 4 通道（RGBA 同步，与 PIL ImageChops 一致）。 */
SLI_API int         sli_op_chops(int op, int64_t a, int64_t b,
                                  int64_t out, int w, int h);
/* 蒙版混合：out = a*(1-m/255) + b*(m/255)，4 通道同步；mask 为 w*h 字节
 * Gray8 平面。ctl = int32[2]：w, h。 */
SLI_API int         sli_op_mask_blend(int64_t a, int64_t b, int64_t mask,
                                      int64_t out, int64_t ctl);
/* 带蒙版贴入：f = mask/255（src 覆盖域内逐像素），dst = src*f + dst*(1-f)。
 * ctl = int32[6]：dw, dh, sw, sh, x, y；mask 为 sw*sh 字节。 */
SLI_API int         sli_op_paste_masked(int64_t dst, int64_t src, int64_t mask,
                                       int64_t ctl);
/* 线性插值（不钳 factor，支持外插增强）：out = a*(1-f) + b*f；
 * factor_x1000 = factor×1000（i32 规避 f32 封送 bug——坑 9）；
 * ImageEnhance 用（Pillow blend 钳 0..1，增强器 factor 可 > 1）。 */
SLI_API int         sli_op_blend_factor(int64_t a, int64_t b, int64_t out,
                                       int w, int h, int factor_x1000);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_IMAGE_H */
