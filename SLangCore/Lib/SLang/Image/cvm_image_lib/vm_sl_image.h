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

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_IMAGE_H */
