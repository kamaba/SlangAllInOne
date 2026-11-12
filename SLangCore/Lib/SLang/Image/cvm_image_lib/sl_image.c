/* =========================================================================
 * sl_image.c —— 生命周期 / 诊断 / 槽表 / 嗅探 / 解码编码分派
 *
 * 对应 SL 侧 ImageFfi.sl（@DllStaticImport 静态绑定，sl_image_lib 注册名）。
 * 编解码本体：
 *   stb  Codec/sl_image_stb.c（third_party/stb 单头实现，公有领域/MIT-0）
 *   wic  Codec/sl_image_wic.c（Windows 系统组件，COM/vtbl C 风格）
 * 分派策略：嗅探格式 -> stb 主路（PNG/JPEG/BMP/GIF/TGA/PSD/PNM/HDR/PIC）
 *           -> WIC 兜底（TIFF/ICO/WebP 装了系统编解码器时）；
 *           stb 失败再试 WIC（渐进 JPEG/12bpc 等长尾由 WIC 接住）。
 * ========================================================================= */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>

#include "sl_image_internal.h"

#if defined(_WIN32)
#include <windows.h>
#endif

/* ================= 内部状态 ================= */

static int s_ready = 0;
static int s_last_error = SLI_OK;
static char s_detail[256];

SliImage s_images[SLI_MAX_IMAGES];
SliBlob  s_blobs[SLI_MAX_BLOBS];

void sli_set_error(int err)
{
    s_last_error = err;
    s_detail[0] = '\0';
}

void sli_set_error_detail(int err, const char* fmt, ...)
{
    va_list ap;
    s_last_error = err;
    va_start(ap, fmt);
    vsnprintf(s_detail, sizeof(s_detail), fmt, ap);
    va_end(ap);
}

static SliImage* image_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLI_MAX_IMAGES || !s_images[i].used) return NULL;
    return &s_images[i];
}

static SliBlob* blob_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLI_MAX_BLOBS || !s_blobs[i].used) return NULL;
    return &s_blobs[i];
}

int64_t sli_blob_register(unsigned char* data, int64_t size)
{
    int i;
    if (!data || size <= 0) { sli_set_error(SLI_E_MEMORY); return 0; }
    for (i = 0; i < SLI_MAX_BLOBS; i++)
    {
        if (s_blobs[i].used) continue;
        s_blobs[i].used = 1;
        s_blobs[i].data = data;
        s_blobs[i].size = size;
        return (int64_t)(i + 1);
    }
    free(data);
    sli_set_error(SLI_E_LIMIT);
    return 0;
}

/* ================= 生命周期 / 诊断 ================= */

int sli_init(void)
{
    if (s_ready) return 1;
    memset(s_images, 0, sizeof(s_images));
    memset(s_blobs, 0, sizeof(s_blobs));
    s_ready = 1;
    sli_set_error(SLI_OK);
    return 1;
}

int sli_uninit(void)
{
    int i;
    for (i = 0; i < SLI_MAX_IMAGES; i++)
    {
        if (s_images[i].used)
        {
            free(s_images[i].pixels);
            memset(&s_images[i], 0, sizeof(SliImage));
        }
    }
    for (i = 0; i < SLI_MAX_BLOBS; i++)
    {
        if (s_blobs[i].used)
        {
            free(s_blobs[i].data);
            memset(&s_blobs[i], 0, sizeof(SliBlob));
        }
    }
    s_ready = 0;
    return 1;
}

int sli_last_error(void)
{
    return s_last_error;
}

const char* sli_error_string(int err)
{
    switch (err)
    {
    case SLI_OK:                return "ok";
    case SLI_E_NOT_INITIALIZED: return "not initialized";
    case SLI_E_BAD_PARAM:       return "bad parameter";
    case SLI_E_BAD_HANDLE:      return "bad handle";
    case SLI_E_MEMORY:          return "out of memory";
    case SLI_E_LIMIT:           return "handle slots exhausted";
    case SLI_E_UNSUPPORTED:     return "unsupported format";
    case SLI_E_DECODE:          return "decode failed";
    case SLI_E_ENCODE:          return "encode failed";
    case SLI_E_IO:              return "file io failed";
    case SLI_E_TOO_LARGE:       return "image too large";
    default:                    return "unknown error";
    }
}

const char* sli_error_detail(void)
{
    return s_detail[0] ? s_detail : sli_error_string(s_last_error);
}

const char* sli_version_string(void)
{
    return "sl_image_lib 1.0 (stb_image 2.31 + stb_image_write 1.17 + WIC)";
}

const char* sli_codec_list(void)
{
    return "stb,wic";
}

/* ================= 嗅探 / 头部探测 ================= */

static unsigned char u8at(const unsigned char* p, int64_t n, int64_t i)
{
    if (i < 0 || i >= n) return 0;
    return p[i];
}

static int64_t be32at(const unsigned char* p, int64_t n, int64_t i)
{
    return ((int64_t)u8at(p, n, i) << 24) | ((int64_t)u8at(p, n, i + 1) << 16) |
           ((int64_t)u8at(p, n, i + 2) << 8) | (int64_t)u8at(p, n, i + 3);
}

static int64_t le32at(const unsigned char* p, int64_t n, int64_t i)
{
    return (int64_t)u8at(p, n, i) | ((int64_t)u8at(p, n, i + 1) << 8) |
           ((int64_t)u8at(p, n, i + 2) << 16) | ((int64_t)u8at(p, n, i + 3) << 24);
}

static int64_t le16at(const unsigned char* p, int64_t n, int64_t i)
{
    return (int64_t)u8at(p, n, i) | ((int64_t)u8at(p, n, i + 1) << 8);
}

static int fourcc(const unsigned char* p, int64_t n, int64_t i, const char* cc)
{
    int k;
    for (k = 0; k < 4; k++)
    {
        if (u8at(p, n, i + k) != (unsigned char)cc[k]) return 0;
    }
    return 1;
}

int sli_sniff_format(const unsigned char* p, int64_t n)
{
    if (!p || n < 8) return SLI_FMT_UNKNOWN;

    /* PNG：完整 8 字节 magic 89 'P' 'N' 'G' 0D 0A 1A 0A（fourcc 是定长 4 字节
     * 比较，"PNG" 字面量第 4 字节为 NUL，与 magic 第 5 字节 0x0D 不匹配，
     * 旧写法 fourcc(p,n,1,"PNG") 永不命中 → PNG 被嗅探为 UNKNOWN） */
    if (u8at(p, n, 0) == 0x89 && u8at(p, n, 1) == 'P' && u8at(p, n, 2) == 'N' &&
        u8at(p, n, 3) == 'G' && u8at(p, n, 4) == 0x0D && u8at(p, n, 5) == 0x0A &&
        u8at(p, n, 6) == 0x1A && u8at(p, n, 7) == 0x0A) return SLI_FMT_PNG;
    /* JPEG */
    if (u8at(p, n, 0) == 0xFF && u8at(p, n, 1) == 0xD8 && u8at(p, n, 2) == 0xFF)
        return SLI_FMT_JPEG;
    /* GIF */
    if (fourcc(p, n, 0, "GIF8")) return SLI_FMT_GIF;
    /* BMP */
    if (u8at(p, n, 0) == 'B' && u8at(p, n, 1) == 'M') return SLI_FMT_BMP;
    /* WebP: RIFF....WEBP */
    if (fourcc(p, n, 0, "RIFF") && fourcc(p, n, 8, "WEBP")) return SLI_FMT_WEBP;
    /* TIFF */
    if (fourcc(p, n, 0, "II*\0") || fourcc(p, n, 0, "MM\0*")) return SLI_FMT_TIFF;
    /* ICO */
    if (u8at(p, n, 0) == 0 && u8at(p, n, 1) == 0 &&
        u8at(p, n, 2) == 1 && u8at(p, n, 3) == 0) return SLI_FMT_ICO;
    /* PPM 家族 */
    if (u8at(p, n, 0) == 'P')
    {
        int d = u8at(p, n, 1);
        if (d >= '1' && d <= '6') return SLI_FMT_PPM;
    }
    /* AVIF / HEIC: ....ftyp avif/heic/heix/mif1/msf1 */
    if (fourcc(p, n, 4, "ftyp"))
    {
        if (fourcc(p, n, 8, "avif")) return SLI_FMT_AVIF;
        return SLI_FMT_HEIC;
    }
    /* PSD */
    if (fourcc(p, n, 0, "8BPS")) return SLI_FMT_UNKNOWN; /* stb 能解，但枚举无位 */
    /* SVG（UTF-8 文本）*/
    {
        int64_t s = 0;
        if (u8at(p, n, 0) == 0xEF && u8at(p, n, 1) == 0xBB && u8at(p, n, 2) == 0xBF)
            s = 3;
        if (u8at(p, n, s) == '<' && (u8at(p, n, s + 1) == '?' || u8at(p, n, s + 1) == 's'))
            return SLI_FMT_SVG;
    }
    /* TGA：无 magic，退化为 18 字节头启发（Type 2/3/10 + bpp 8/16/24/32）*/
    if (n >= 18)
    {
        int type = u8at(p, n, 2);
        int bpp  = u8at(p, n, 16);
        if ((type == 2 || type == 3 || type == 10) &&
            (bpp == 8 || bpp == 16 || bpp == 24 || bpp == 32))
        {
            return SLI_FMT_TGA;
        }
    }
    return SLI_FMT_UNKNOWN;
}

/* JPEG SOF 扫描：取第一个 SOF0/1/2/9/14 帧头里的高宽（大端） */
static int jpeg_sof_dims(const unsigned char* p, int64_t n, int* w, int* h)
{
    int64_t i = 2;
    while (i + 9 < n)
    {
        if (u8at(p, n, i) != 0xFF) { i++; continue; }
        {
            int m = u8at(p, n, i + 1);
            if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7))
            {
                i += 2; continue;          /* 无长度段 */
            }
            if (m == 0xDA) return 0;       /* 到扫描数据，未遇 SOF */
            {
                int64_t len = (u8at(p, n, i + 2) << 8) | u8at(p, n, i + 3);
                if ((m >= 0xC0 && m <= 0xC3) || (m >= 0xC5 && m <= 0xC7) ||
                    (m >= 0xC9 && m <= 0xCB) || (m >= 0xCD && m <= 0xCF))
                {
                    if (i + 9 <= n)
                    {
                        *h = ((int)u8at(p, n, i + 5) << 8) | u8at(p, n, i + 6);
                        *w = ((int)u8at(p, n, i + 7) << 8) | u8at(p, n, i + 8);
                        return 1;
                    }
                    return 0;
                }
                if (len <= 0) return 0;
                i += 2 + len;
            }
        }
    }
    return 0;
}

/* TIFF：解析 IFD0 的 ImageWidth(256)/ImageLength(257) */
static int tiff_dims(const unsigned char* p, int64_t n, int* w, int* h)
{
    int64_t ifd;
    int64_t i, k, count;
    int little = (u8at(p, n, 0) == 'I' && u8at(p, n, 1) == 'I');
    if (n < 8) return 0;
    ifd = little ? le32at(p, n, 4) : be32at(p, n, 4);
    if (ifd + 2 > n || ifd < 0) return 0;
    count = little ? le16at(p, n, ifd) : ((u8at(p, n, ifd) << 8) | u8at(p, n, ifd + 1));
    if (count <= 0 || count > 512) return 0;
    i = ifd + 2;
    for (k = 0; k < count; k++)
    {
        int64_t e = i + (int64_t)k * 12;
        int tag = little ? (int)le16at(p, n, e) : ((int)u8at(p, n, e) << 8 | u8at(p, n, e + 1));
        int type = little ? (int)le16at(p, n, e + 2) : ((int)u8at(p, n, e + 2) << 8 | u8at(p, n, e + 3));
        int64_t val = 0;
        if (e + 12 > n) break;
        if (type == 3) /* SHORT */
        {
            val = little ? le16at(p, n, e + 8) : ((u8at(p, n, e + 8) << 8) | u8at(p, n, e + 9));
        }
        else if (type == 4) /* LONG */
        {
            val = little ? le32at(p, n, e + 8) : be32at(p, n, e + 8);
        }
        if (tag == 256) *w = (val > 0x7FFFFFFF) ? 0 : (int)val;
        if (tag == 257) *h = (val > 0x7FFFFFFF) ? 0 : (int)val;
        if (*w && *h) return 1;
    }
    return (*w && *h) ? 1 : 0;
}

int sli_probe_header(const unsigned char* p, int64_t n,
                     int* w, int* h, int* src_fmt, int* has_alpha)
{
    int fmt;
    *w = 0; *h = 0; *has_alpha = 0;
    if (!p || n <= 0) return 0;
    fmt = sli_sniff_format(p, n);
    *src_fmt = fmt;

    switch (fmt)
    {
    case SLI_FMT_PNG:
        if (n >= 26)
        {
            int64_t ww = be32at(p, n, 16), hh = be32at(p, n, 20);
            int ct = u8at(p, n, 25);
            *w = (ww > 0 && ww <= SLI_MAX_DIM) ? (int)ww : 0;
            *h = (hh > 0 && hh <= SLI_MAX_DIM) ? (int)hh : 0;
            *has_alpha = (ct == 4 || ct == 6) ? 1 : 0;
        }
        return 1;
    case SLI_FMT_BMP:
        if (n >= 30)
        {
            int64_t ww = le32at(p, n, 18), hh = le32at(p, n, 22);
            int bpp = (int)le16at(p, n, 28);
            *w = (ww > 0 && ww <= SLI_MAX_DIM) ? (int)ww : 0;
            *h = (hh < 0 && hh >= -(int64_t)SLI_MAX_DIM) ? (int)(-hh) : (hh > 0 ? (int)hh : 0);
            *has_alpha = (bpp == 32) ? 1 : 0;
        }
        return 1;
    case SLI_FMT_GIF:
        if (n >= 10)
        {
            *w = (int)le16at(p, n, 6);
            *h = (int)le16at(p, n, 8);
            *has_alpha = 1;
        }
        return 1;
    case SLI_FMT_JPEG:
        jpeg_sof_dims(p, n, w, h);
        return 1;
    case SLI_FMT_WEBP:
        if (n >= 30 && fourcc(p, n, 12, "VP8X"))
        {
            int64_t ww = le32at(p, n, 24) & 0xFFFFFF;
            int64_t hh = le32at(p, n, 27) & 0xFFFFFF;
            *w = (int)(ww + 1); *h = (int)(hh + 1);
            *has_alpha = (u8at(p, n, 20) & 0x10) ? 1 : 0;
        }
        else if (n >= 30 && fourcc(p, n, 12, "VP8L"))
        {
            int64_t b0 = u8at(p, n, 21), b1 = u8at(p, n, 22), b2 = u8at(p, n, 23), b3 = u8at(p, n, 24);
            int64_t bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
            *w = (int)((bits & 0x3FFF) + 1);
            *h = (int)(((bits >> 14) & 0x3FFF) + 1);
            *has_alpha = 1;
        }
        else if (n >= 30 && fourcc(p, n, 12, "VP8 "))
        {
            /* keyframe: 3 字节帧标签 + 0x9D 0x01 0x2A + 14bit 宽高（LE） */
            if (u8at(p, n, 23) == 0x9D && u8at(p, n, 24) == 0x01 && u8at(p, n, 25) == 0x2A)
            {
                *w = (int)(le16at(p, n, 26) & 0x3FFF);
                *h = (int)(((int)le16at(p, n, 28) & 0x3FFF) | (((int)u8at(p, n, 30) & 0x3) << 12) );
            }
        }
        return 1;
    case SLI_FMT_TIFF:
        tiff_dims(p, n, w, h);
        return 1;
    case SLI_FMT_ICO:
        if (n >= 8)
        {
            int cnt = (int)le16at(p, n, 4);
            int bw = u8at(p, n, 6);
            int bh = u8at(p, n, 7);
            *w = (bw == 0) ? 256 : bw;
            *h = (bh == 0) ? 256 : bh;
            *has_alpha = 1;
            if (cnt > 1) { /* 多帧（动画语义弱） */ }
        }
        return 1;
    case SLI_FMT_PPM:
    {
        /* 跳 magic 后按空白/注释解析两个十进制整数 */
        int64_t i = 2;
        int vals[2] = {0, 0};
        int vi = 0;
        while (i < n && vi < 2)
        {
            int c = u8at(p, n, i);
            if (c == '#')
            {
                while (i < n && u8at(p, n, i) != '\n') i++;
                continue;
            }
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
            {
                int64_t v = 0;
                while (i < n && u8at(p, n, i) >= '0' && u8at(p, n, i) <= '9')
                {
                    v = v * 10 + (u8at(p, n, i) - '0');
                    if (v > SLI_MAX_DIM) return 1;
                    i++;
                }
                vals[vi++] = (int)v;
            }
        }
        *w = vals[0]; *h = vals[1];
        return 1;
    }
    case SLI_FMT_SVG:
    case SLI_FMT_AVIF:
    case SLI_FMT_HEIC:
        return 1;     /* 仅识别格式，尺寸留给上层（v1 不解析） */
    default:
        return 0;
    }
}

/* ================= 探测导出 ================= */

int sli_probe_file(const char* path_utf8, int64_t out_ptr)
{
#if defined(_WIN32)
    unsigned char head[256];
    FILE* f = NULL;
    size_t got = 0;
    int32_t* out;
    int w = 0, h = 0, fmt = 0, alpha = 0;
    wchar_t wpath[1024];

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!path_utf8 || !out_ptr) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    out = (int32_t*)(intptr_t)out_ptr;

    if (!MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1))
    {
        sli_set_error_detail(SLI_E_IO, "bad path encoding");
        return 0;
    }
    if (_wfopen_s(&f, wpath, L"rb") != 0 || !f)
    {
        sli_set_error_detail(SLI_E_IO, "open file");
        return 0;
    }
    got = fread(head, 1, sizeof(head), f);
    fclose(f);
    if (got < 8) { sli_set_error_detail(SLI_E_DECODE, "short file"); return 0; }

    sli_probe_header(head, (int64_t)got, &w, &h, &fmt, &alpha);
    if (fmt == SLI_FMT_UNKNOWN) { sli_set_error_detail(SLI_E_DECODE, "unknown format"); return 0; }

    out[0] = w;
    out[1] = h;
    out[2] = fmt;
    out[3] = (w && h) ? 4 : 0;      /* 探测期通道未知，非零尺寸给保守 4 */
    out[4] = alpha;
    out[5] = 0;                     /* 帧动画标记（v1 恒 0） */
    return 1;
#else
    (void)path_utf8; (void)out_ptr;
    sli_set_error(SLI_E_UNSUPPORTED);
    return 0;
#endif
}

int sli_probe_mem(int64_t data_ptr, int64_t size, int64_t out_ptr)
{
    const unsigned char* p;
    int32_t* out;
    int w = 0, h = 0, fmt = 0, alpha = 0;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!data_ptr || size <= 0 || !out_ptr) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    p = (const unsigned char*)(intptr_t)data_ptr;
    out = (int32_t*)(intptr_t)out_ptr;

    sli_probe_header(p, size, &w, &h, &fmt, &alpha);
    if (fmt == SLI_FMT_UNKNOWN) { sli_set_error_detail(SLI_E_DECODE, "unknown format"); return 0; }

    out[0] = w;
    out[1] = h;
    out[2] = fmt;
    out[3] = (w && h) ? 4 : 0;
    out[4] = alpha;
    out[5] = 0;
    return 1;
}

/* ================= 解码 ================= */

static int64_t image_register(unsigned char* pixels, int w, int h,
                               int channels, int src_fmt)
{
    int i;
    if (!pixels) return 0;
    for (i = 0; i < SLI_MAX_IMAGES; i++)
    {
        if (s_images[i].used) continue;
        s_images[i].used = 1;
        s_images[i].w = w;
        s_images[i].h = h;
        s_images[i].channels = channels;
        s_images[i].src_format = src_fmt;
        s_images[i].pixels = pixels;
        return (int64_t)(i + 1);
    }
    free(pixels);
    sli_set_error(SLI_E_LIMIT);
    return 0;
}

/* 尺寸上限校验（防异常头把进程 OOM） */
static int dims_ok(int w, int h)
{
    if (w <= 0 || h <= 0) { sli_set_error_detail(SLI_E_BAD_PARAM, "bad dims %dx%d", w, h); return 0; }
    if (w > SLI_MAX_DIM || h > SLI_MAX_DIM ||
        (int64_t)w * (int64_t)h > (int64_t)SLI_MAX_PIXELS)
    {
        sli_set_error_detail(SLI_E_TOO_LARGE, "dims %dx%d", w, h);
        return 0;
    }
    return 1;
}

static int64_t decode_mem_common(const unsigned char* data, int64_t size, int req_channels)
{
    unsigned char* pixels = NULL;
    int w = 0, h = 0, src_fmt = 0, alpha = 0;

    (void)req_channels; /* v1 像素契约恒 RGBA8：stb/wic 均按 4 通道产出 */

    if (!data || size <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    sli_probe_header(data, size, &w, &h, &src_fmt, &alpha);

    /* 主路：stb（PNG/JPEG/BMP/GIF/TGA/PSD/HDR/PIC/PNM + 未知嗅探） */
    if (src_fmt != SLI_FMT_TIFF && src_fmt != SLI_FMT_ICO &&
        src_fmt != SLI_FMT_WEBP && src_fmt != SLI_FMT_SVG &&
        src_fmt != SLI_FMT_AVIF && src_fmt != SLI_FMT_HEIC)
    {
        pixels = sli_stb_decode_mem(data, size, 4, &w, &h);
    }
    /* WIC 路：TIFF/ICO/WebP（系统装了编解码器时） */
    if (!pixels &&
        (src_fmt == SLI_FMT_TIFF || src_fmt == SLI_FMT_ICO ||
         src_fmt == SLI_FMT_WEBP || src_fmt == SLI_FMT_JPEG /* 长尾兜底 */))
    {
        pixels = sli_wic_decode_mem(data, size, &w, &h, &src_fmt);
    }
    if (!pixels)
    {
        if (s_last_error == SLI_OK) sli_set_error_detail(SLI_E_DECODE, "no codec handled data");
        return 0;
    }
    if (!dims_ok(w, h)) { free(pixels); return 0; }

    return image_register(pixels, w, h, 4, src_fmt);
}

int64_t sli_decode_file(const char* path_utf8, int req_channels)
{
#if defined(_WIN32)
    FILE* f = NULL;
    long sz;
    unsigned char* buf;
    int64_t img;
    wchar_t wpath[1024];

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!path_utf8 || !path_utf8[0]) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    if (!MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1))
    {
        sli_set_error_detail(SLI_E_IO, "bad path encoding");
        return 0;
    }
    if (_wfopen_s(&f, wpath, L"rb") != 0 || !f)
    {
        sli_set_error_detail(SLI_E_IO, "open file");
        return 0;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); sli_set_error(SLI_E_IO); return 0; }
    sz = ftell(f);
    if (sz <= 0 || sz > (long)(512 * 1024 * 1024))
    {
        fclose(f);
        sli_set_error_detail(SLI_E_TOO_LARGE, "file %ld bytes", sz);
        return 0;
    }
    rewind(f);
    buf = (unsigned char*)malloc((size_t)sz);
    if (!buf) { fclose(f); sli_set_error(SLI_E_MEMORY); return 0; }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz)
    {
        fclose(f);
        free(buf);
        sli_set_error_detail(SLI_E_IO, "short read");
        return 0;
    }
    fclose(f);

    img = decode_mem_common(buf, (int64_t)sz, req_channels);
    free(buf);
    return img;
#else
    (void)path_utf8; (void)req_channels;
    sli_set_error(SLI_E_UNSUPPORTED);
    return 0;
#endif
}

int64_t sli_decode_mem(int64_t data_ptr, int64_t size, int req_channels)
{
    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!data_ptr || size <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    return decode_mem_common((const unsigned char*)(intptr_t)data_ptr, size, req_channels);
}

int sli_image_width(int64_t img)
{
    SliImage* m = image_from_handle(img);
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return m->w;
}

int sli_image_height(int64_t img)
{
    SliImage* m = image_from_handle(img);
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return m->h;
}

int sli_image_channels(int64_t img)
{
    SliImage* m = image_from_handle(img);
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return m->channels;
}

int sli_image_src_format(int64_t img)
{
    SliImage* m = image_from_handle(img);
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return m->src_format;
}

int sli_image_copy_pixels(int64_t img, int64_t dst_ptr, int64_t cap)
{
    SliImage* m = image_from_handle(img);
    int64_t need;
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (!dst_ptr || cap <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    need = (int64_t)m->w * (int64_t)m->h * 4;
    if (cap < need) { sli_set_error_detail(SLI_E_TOO_LARGE, "cap %lld < %lld", (long long)cap, (long long)need); return 0; }
    memcpy((void*)(intptr_t)dst_ptr, m->pixels, (size_t)need);
    return 1;
}

int sli_image_free(int64_t img)
{
    SliImage* m = image_from_handle(img);
    if (!m) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    free(m->pixels);
    memset(m, 0, sizeof(SliImage));
    return 1;
}

/* ================= 编码 + blob ================= */

int64_t sli_encode_mem(int fmt, int quality, int w, int h, int64_t pixels_ptr)
{
    const unsigned char* rgba;
    unsigned char* out = NULL;
    int64_t out_size = 0;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!pixels_ptr || w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (!dims_ok(w, h)) return 0;
    rgba = (const unsigned char*)(intptr_t)pixels_ptr;

    if (quality < 0) quality = 0;
    if (quality > 100) quality = 100;

    switch (fmt)
    {
    case SLI_FMT_PNG:
    case SLI_FMT_JPEG:
    case SLI_FMT_BMP:
    case SLI_FMT_TGA:
    case SLI_FMT_PPM:
        out = sli_stb_encode_mem(fmt, quality, w, h, rgba, &out_size);
        break;
    case SLI_FMT_TIFF:
        out = sli_wic_encode_tiff(rgba, w, h, &out_size);
        break;
    default:
        sli_set_error_detail(SLI_E_UNSUPPORTED, "fmt %d encode", fmt);
        return 0;
    }
    if (!out) return 0;
    return sli_blob_register(out, out_size);
}

int64_t sli_blob_size(int64_t blob)
{
    SliBlob* b = blob_from_handle(blob);
    if (!b) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return b->size;
}

int sli_blob_copy(int64_t blob, int64_t dst_ptr, int64_t cap)
{
    SliBlob* b = blob_from_handle(blob);
    if (!b) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (!dst_ptr || cap <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (cap < b->size)
    {
        sli_set_error_detail(SLI_E_TOO_LARGE, "cap %lld < %lld", (long long)cap, (long long)b->size);
        return 0;
    }
    memcpy((void*)(intptr_t)dst_ptr, b->data, (size_t)b->size);
    return 1;
}

int sli_blob_save(int64_t blob, const char* path_utf8)
{
#if defined(_WIN32)
    SliBlob* b = blob_from_handle(blob);
    FILE* f = NULL;
    wchar_t wpath[1024];

    if (!b) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (!path_utf8 || !path_utf8[0]) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (!MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1))
    {
        sli_set_error_detail(SLI_E_IO, "bad path encoding");
        return 0;
    }
    if (_wfopen_s(&f, wpath, L"wb") != 0 || !f)
    {
        sli_set_error_detail(SLI_E_IO, "open file");
        return 0;
    }
    if (fwrite(b->data, 1, (size_t)b->size, f) != (size_t)b->size)
    {
        fclose(f);
        sli_set_error_detail(SLI_E_IO, "short write");
        return 0;
    }
    fclose(f);
    return 1;
#else
    (void)blob; (void)path_utf8;
    sli_set_error(SLI_E_UNSUPPORTED);
    return 0;
#endif
}

int sli_blob_free(int64_t blob)
{
    SliBlob* b = blob_from_handle(blob);
    if (!b) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    free(b->data);
    memset(b, 0, sizeof(SliBlob));
    return 1;
}
