/* =========================================================================
 * sl_image_internal.h —— sl_image_lib.dll 内部共享契约（跨编译单元）
 *
 * 自有结构体命名遵守用户规则：PascalCase（Slr* 同款约定，函数名保持
 * snake_case）。公开导出面全部集中在 vm_sl_image.h（带 SLI_API）。
 * ========================================================================= */
#ifndef SL_IMAGE_INTERNAL_H
#define SL_IMAGE_INTERNAL_H

#include "vm_sl_image.h"

/* ---- 上限（槽表规模） ---- */
#define SLI_MAX_IMAGES  64      /* 同时存活的解码图像句柄        */
#define SLI_MAX_BLOBS   64      /* 同时存活的编码字节块句柄      */
#define SLI_MAX_DIM     16384   /* 单边像素上限（防异常头 OOM）  */
#define SLI_MAX_PIXELS  (256 * 1024 * 1024)  /* 1G 像素位上限     */

#ifdef __cplusplus
extern "C" {
#endif

/* ---- 解码图像槽（句柄 = 槽号 + 1，0 无效） ---- */
typedef struct SliImage
{
    int              used;          /* 槽占用                     */
    int              w;
    int              h;
    int              channels;      /* 输出通道数（3/4）          */
    int              src_format;    /* SLI_FMT_* 探测出的源格式   */
    unsigned char*   pixels;        /* RGBA8 top-down（4 通道）   */
} SliImage;

/* ---- 编码 blob 槽 ---- */
typedef struct SliBlob
{
    int              used;
    unsigned char*   data;          /* 堆上压缩字节               */
    int64_t          size;
} SliBlob;

/* ---- 错误状态（sl_image.c 定义，全库共享；粘性：入口清零） ---- */
void    sli_set_error(int err);
void    sli_set_error_detail(int err, const char* fmt, ...);

/* ---- 槽表（sl_image.c 定义） ---- */
extern SliImage s_images[SLI_MAX_IMAGES];
extern SliBlob  s_blobs[SLI_MAX_BLOBS];

/* ---- blob 注册（encode 产物入槽；size 所有权移交） ---- */
int64_t sli_blob_register(unsigned char* data, int64_t size);

/* ---- 嗅探：字节流 -> SLI_FMT_*（0=未知）。sl_image.c 实现。 ---- */
int     sli_sniff_format(const unsigned char* p, int64_t n);

/* ---- 头部探测：字节流 -> w/h/通道/alpha（不解码像素）。---- */
int     sli_probe_header(const unsigned char* p, int64_t n,
                         int* w, int* h, int* src_fmt, int* has_alpha);

/* ================= Codec: stb（Codec/sl_image_stb.c） ================= */
/* 解码内存字节 -> RGBA8 堆块（所有权移交调用方，free 释放）。
 * req_channels 3/4。失败返回 NULL（错误已 set）。 */
unsigned char* sli_stb_decode_mem(const unsigned char* data, int64_t size,
                                   int req_channels, int* w, int* h);
/* 编码 RGBA8 -> 压缩字节堆块（所有权移交）。fmt = SLI_FMT_*。 */
unsigned char* sli_stb_encode_mem(int fmt, int quality,
                                   int w, int h, const unsigned char* rgba,
                                   int64_t* out_size);

/* ================= Codec: WIC（Codec/sl_image_wic.c） ================= */
/* WIC 文件解码 -> RGBA8 堆块。 */
unsigned char* sli_wic_decode_file(const wchar_t* wpath,
                                    int* w, int* h, int* src_fmt);
/* WIC 内存流解码 -> RGBA8 堆块。 */
unsigned char* sli_wic_decode_mem(const unsigned char* data, int64_t size,
                                   int* w, int* h, int* src_fmt);
/* WIC 编码 TIFF。 */
unsigned char* sli_wic_encode_tiff(const unsigned char* rgba,
                                   int w, int h, int64_t* out_size);
/* 探测 WIC 是否可用（COM 工厂可建）——供诊断。 */
int     sli_wic_available(void);

#ifdef __cplusplus
}
#endif

#endif /* SL_IMAGE_INTERNAL_H */
