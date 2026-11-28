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
#include <math.h>

#include "sl_image_internal.h"

#if defined(_WIN32)
#include <windows.h>
#else
/* 非 Windows（wasm）：sl_image_wic.c 不编入（COM/WIC 专属），但解码/
 * 编码主路的 WIC 兜底调用点仍在（sl_image_internal.h 声明）——提供
 * 恒失败存根，链接可解析，运行期自然落到 stb 主路。 */
unsigned char* sli_wic_decode_file(const wchar_t* wpath, int* w, int* h, int* src_fmt)
{ (void)wpath; (void)w; (void)h; (void)src_fmt; return 0; }
unsigned char* sli_wic_decode_mem(const unsigned char* data, int64_t size,
                                  int* w, int* h, int* src_fmt)
{ (void)data; (void)size; (void)w; (void)h; (void)src_fmt; return 0; }
unsigned char* sli_wic_encode_tiff(const unsigned char* rgba,
                                   int w, int h, int64_t* out_size)
{ (void)rgba; (void)w; (void)h; (void)out_size; return 0; }
int sli_wic_available(void) { return 0; }
#endif

/* ================= 内部状态 ================= */

static int s_ready = 0;
static int s_last_error = SLI_OK;
static char s_detail[256];

SliImage  s_images[SLI_MAX_IMAGES];
SliBlob   s_blobs[SLI_MAX_BLOBS];
SliGif    s_gifs[SLI_MAX_GIFS];
SliGifEnc s_gif_encs[SLI_MAX_GIF_ENCODERS];

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
    memset(s_gifs, 0, sizeof(s_gifs));
    memset(s_gif_encs, 0, sizeof(s_gif_encs));
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
    for (i = 0; i < SLI_MAX_GIFS; i++)
    {
        if (s_gifs[i].used)
        {
            free(s_gifs[i].pixels);
            free(s_gifs[i].delays_ms);
            memset(&s_gifs[i], 0, sizeof(SliGif));
        }
    }
    for (i = 0; i < SLI_MAX_GIF_ENCODERS; i++)
    {
        if (s_gif_encs[i].used)
        {
            int f;
            for (f = 0; f < s_gif_encs[i].count; f++)
                free(s_gif_encs[i].frame_pix[f]);
            free(s_gif_encs[i].frame_pix);
            free(s_gif_encs[i].delays_ms);
            memset(&s_gif_encs[i], 0, sizeof(SliGifEnc));
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
    case SLI_FMT_GIF:
        /* 单帧静态 GIF：延迟 0、不写 NETSCAPE（loop=-1） */
        {
            unsigned char* frames[1];
            int delays[1];
            frames[0] = (unsigned char*)rgba;
            delays[0] = 0;
            out = sli_gif_encode_animated(w, h, 1, frames, delays, -1, &out_size);
        }
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

/* ================= GIF 动画（拆解 / 合成） ================= */

static SliGif* gif_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLI_MAX_GIFS || !s_gifs[i].used) return NULL;
    return &s_gifs[i];
}

static SliGifEnc* gif_enc_from_handle(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLI_MAX_GIF_ENCODERS || !s_gif_encs[i].used) return NULL;
    return &s_gif_encs[i];
}

/* GIF 解码产物入槽（所有权：pixels / delays_ms 移交；满槽时释放并报 LIMIT） */
static int64_t gif_register(unsigned char* pixels, int w, int h,
                            int frames, int* delays_ms, int loop)
{
    int i;
    for (i = 0; i < SLI_MAX_GIFS; i++)
    {
        if (s_gifs[i].used) continue;
        s_gifs[i].used = 1;
        s_gifs[i].w = w;
        s_gifs[i].h = h;
        s_gifs[i].frames = frames;
        s_gifs[i].loop = loop;
        s_gifs[i].delays_ms = delays_ms;
        s_gifs[i].pixels = pixels;
        return (int64_t)(i + 1);
    }
    free(pixels);
    free(delays_ms);
    sli_set_error(SLI_E_LIMIT);
    return 0;
}

/* 读整个文件到堆块（UTF-8 路径 -> wchar 打开；512MB 上限） */
static unsigned char* read_file_all(const char* path_utf8, int64_t* out_size)
{
#if defined(_WIN32)
    FILE* f = NULL;
    long sz;
    unsigned char* buf;
    wchar_t wpath[1024];

    if (!path_utf8 || !path_utf8[0]) { sli_set_error(SLI_E_BAD_PARAM); return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, (int)(sizeof(wpath) / sizeof(wchar_t)) - 1))
    {
        sli_set_error_detail(SLI_E_IO, "bad path encoding");
        return NULL;
    }
    if (_wfopen_s(&f, wpath, L"rb") != 0 || !f)
    {
        sli_set_error_detail(SLI_E_IO, "open file");
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); sli_set_error(SLI_E_IO); return NULL; }
    sz = ftell(f);
    if (sz <= 0 || sz > (long)(512 * 1024 * 1024))
    {
        fclose(f);
        sli_set_error_detail(SLI_E_TOO_LARGE, "file %ld bytes", sz);
        return NULL;
    }
    rewind(f);
    buf = (unsigned char*)malloc((size_t)sz);
    if (!buf) { fclose(f); sli_set_error(SLI_E_MEMORY); return NULL; }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz)
    {
        fclose(f);
        free(buf);
        sli_set_error_detail(SLI_E_IO, "short read");
        return NULL;
    }
    fclose(f);
    *out_size = (int64_t)sz;
    return buf;
#else
    (void)path_utf8; (void)out_size;
    sli_set_error(SLI_E_UNSUPPORTED);
    return NULL;
#endif
}

static int64_t gif_decode_common(const unsigned char* data, int64_t size)
{
    int w = 0, h = 0, frames = 0, loop = -1;
    int* delays_ms = NULL;
    unsigned char* pixels;

    if (!data || size <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    pixels = sli_stb_decode_gif(data, size, &w, &h, &frames, &delays_ms, &loop);
    if (!pixels) return 0;                      /* 错误已由 codec set */

    if (frames <= 0)
    {
        free(pixels);
        free(delays_ms);
        sli_set_error_detail(SLI_E_DECODE, "gif frames %d", frames);
        return 0;
    }
    if (!dims_ok(w, h)) { free(pixels); free(delays_ms); return 0; }

    if (!delays_ms)                              /* stb 正常必产出；兜底全 0 */
    {
        delays_ms = (int*)calloc((size_t)frames, sizeof(int));
        if (!delays_ms) { free(pixels); sli_set_error(SLI_E_MEMORY); return 0; }
    }
    return gif_register(pixels, w, h, frames, delays_ms, loop);
}

int64_t sli_gif_decode_file(const char* path_utf8)
{
#if defined(_WIN32)
    int64_t size = 0;
    unsigned char* buf;
    int64_t gif;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    buf = read_file_all(path_utf8, &size);
    if (!buf) return 0;
    gif = gif_decode_common(buf, size);
    free(buf);
    return gif;
#else
    (void)path_utf8;
    sli_set_error(SLI_E_UNSUPPORTED);
    return 0;
#endif
}

int64_t sli_gif_decode_mem(int64_t data_ptr, int64_t size)
{
    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!data_ptr || size <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    return gif_decode_common((const unsigned char*)(intptr_t)data_ptr, size);
}

int sli_gif_width(int64_t gif)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return g->w;
}

int sli_gif_height(int64_t gif)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return g->h;
}

int sli_gif_frame_count(int64_t gif)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    return g->frames;
}

int sli_gif_loop_count(int64_t gif)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return -1; }
    return g->loop;
}

int sli_gif_frame_delay(int64_t gif, int frame)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return -1; }
    if (frame < 0 || frame >= g->frames)
    {
        sli_set_error_detail(SLI_E_BAD_PARAM, "frame %d of %d", frame, g->frames);
        return -1;
    }
    return g->delays_ms ? g->delays_ms[frame] : 0;
}

int sli_gif_frame_pixels(int64_t gif, int frame, int64_t dst_ptr, int64_t cap)
{
    SliGif* g = gif_from_handle(gif);
    int64_t need;
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (frame < 0 || frame >= g->frames)
    {
        sli_set_error_detail(SLI_E_BAD_PARAM, "frame %d of %d", frame, g->frames);
        return 0;
    }
    if (!dst_ptr || cap <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    need = (int64_t)g->w * (int64_t)g->h * 4;
    if (cap < need)
    {
        sli_set_error_detail(SLI_E_TOO_LARGE, "cap %lld < %lld", (long long)cap, (long long)need);
        return 0;
    }
    memcpy((void*)(intptr_t)dst_ptr, g->pixels + (size_t)((int64_t)frame * need), (size_t)need);
    return 1;
}

int sli_gif_free(int64_t gif)
{
    SliGif* g = gif_from_handle(gif);
    if (!g) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    free(g->pixels);
    free(g->delays_ms);
    memset(g, 0, sizeof(SliGif));
    return 1;
}

int64_t sli_gif_encode_new(int w, int h, int loop)
{
    int i;
    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dims_ok(w, h)) return 0;
    if (loop < -1) loop = -1;
    for (i = 0; i < SLI_MAX_GIF_ENCODERS; i++)
    {
        if (s_gif_encs[i].used) continue;
        memset(&s_gif_encs[i], 0, sizeof(SliGifEnc));
        s_gif_encs[i].used = 1;
        s_gif_encs[i].w = w;
        s_gif_encs[i].h = h;
        s_gif_encs[i].loop = loop;
        return (int64_t)(i + 1);
    }
    sli_set_error(SLI_E_LIMIT);
    return 0;
}

int sli_gif_encode_add_frame(int64_t enc, int64_t pixels_ptr, int delay_ms)
{
    SliGifEnc* e = gif_enc_from_handle(enc);
    unsigned char* copy;
    int64_t frame_bytes;

    if (!e) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (!pixels_ptr) { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (delay_ms < 0) delay_ms = 0;
    if (delay_ms > 655350) delay_ms = 655350;    /* GCE u16 厘秒上限 */

    frame_bytes = (int64_t)e->w * (int64_t)e->h * 4;
    if (e->count >= e->cap)
    {
        int newcap = e->cap ? e->cap * 2 : 8;
        unsigned char** fp;
        int* dp;
        fp = (unsigned char**)realloc(e->frame_pix, sizeof(unsigned char*) * (size_t)newcap);
        if (!fp) { sli_set_error(SLI_E_MEMORY); return 0; }
        e->frame_pix = fp;
        dp = (int*)realloc(e->delays_ms, sizeof(int) * (size_t)newcap);
        if (!dp) { sli_set_error(SLI_E_MEMORY); return 0; }
        e->delays_ms = dp;
        e->cap = newcap;
    }

    copy = (unsigned char*)malloc((size_t)frame_bytes);
    if (!copy) { sli_set_error(SLI_E_MEMORY); return 0; }
    memcpy(copy, (const void*)(intptr_t)pixels_ptr, (size_t)frame_bytes);
    e->frame_pix[e->count] = copy;
    e->delays_ms[e->count] = delay_ms;
    e->count++;
    return 1;
}

int64_t sli_gif_encode_finish(int64_t enc)
{
    SliGifEnc* e = gif_enc_from_handle(enc);
    unsigned char* out = NULL;
    int64_t out_size = 0;

    if (!e) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    if (e->count == 0) sli_set_error_detail(SLI_E_BAD_PARAM, "no frames added");
    else
        out = sli_gif_encode_animated(e->w, e->h, e->count, e->frame_pix,
                                      e->delays_ms, e->loop, &out_size);
    /* 无论成败：帧数组释放、槽失效（finish 是一次性终点；空帧同样终结，
     * SL 侧 build 失败后不再持有句柄 -> 零泄漏） */
    {
        int f;
        for (f = 0; f < e->count; f++) free(e->frame_pix[f]);
        free(e->frame_pix);
        free(e->delays_ms);
        memset(e, 0, sizeof(SliGifEnc));
    }
    if (!out) return 0;                          /* 错误已 set */
    return sli_blob_register(out, out_size);    /* 失败时 blob_register 释放 out */
}

int sli_gif_encode_free(int64_t enc)
{
    SliGifEnc* e = gif_enc_from_handle(enc);
    if (!e) { sli_set_error(SLI_E_BAD_HANDLE); return 0; }
    {
        int f;
        for (f = 0; f < e->count; f++) free(e->frame_pix[f]);
        free(e->frame_pix);
        free(e->delays_ms);
        memset(e, 0, sizeof(SliGifEnc));
    }
    return 1;
}

/* =========================================================================
 * 像素批量运算（sli_op_*，v2，2026-11-28）
 *
 * 纯 SL 每像素重循环下沉：convolve / rotate / resize / alpha 合成与混合 /
 * 通道拆合 / 格式转换 / 贴入 / 填充 / 翻转 / 预乘。裸指针运算（无句柄槽），
 * 语义与 SL 侧 ImageBuffer/ImageFilter 实现逐位对齐：
 *   - 整数除法截断（C 与 SL int 语义一致）；
 *   - toInt = clamp8((int)(v + 0.5f))（Std ColorInt.toInt 同式）；
 *   - 灰度 BT.601：(299r + 587g + 114b + 500) / 1000；
 *   - blendOver：src.a>=255 直通 src / <=0 直通 dst / 否则浮点 over。
 * 失败返回 0（粘性错误），SL 侧据此回落纯 SL 循环兜底。
 * ========================================================================= */

/* SL 侧 ColorInt 数值语义 */
static int op_clamp8(int v)
{
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
}

static int op_toint(float v)      /* clamp8((int)(v + 0.5f)) */
{
    int i = (int)(v + 0.5f);
    return op_clamp8(i);
}

static int op_gray(int r, int g, int b)   /* BT.601（SL grayscale 同式） */
{
    return (299 * r + 587 * g + 114 * b + 500) / 1000;
}

/* ---- convolve3x3：RGBA8 边界复制，RGB 卷积 + offset，alpha 保留中心 ---- */
int sli_op_convolve3x3(int64_t src, int64_t dst, int w, int h, int64_t ctl)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const int* k = (const int*)(intptr_t)ctl;
    int x, y;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !dp || !k || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (k[9] <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    for (y = 0; y < h; ++y)
    {
        for (x = 0; x < w; ++x)
        {
            int sr = 0, sg = 0, sb = 0, dy, dx;
            const unsigned char* c = sp + (size_t)(y * w + x) * 4;
            unsigned char* d = dp + (size_t)(y * w + x) * 4;
            for (dy = -1; dy <= 1; ++dy)
            {
                for (dx = -1; dx <= 1; ++dx)
                {
                    int nx = x + dx, ny = y + dy;
                    int ki = (dy + 1) * 3 + (dx + 1);
                    const unsigned char* p;
                    if (nx < 0) nx = 0;
                    if (nx >= w) nx = w - 1;
                    if (ny < 0) ny = 0;
                    if (ny >= h) ny = h - 1;
                    p = sp + (size_t)(ny * w + nx) * 4;
                    sr += k[ki] * (int)p[0];
                    sg += k[ki] * (int)p[1];
                    sb += k[ki] * (int)p[2];
                }
            }
            d[0] = (unsigned char)op_clamp8(sr / k[9] + k[10]);
            d[1] = (unsigned char)op_clamp8(sg / k[9] + k[10]);
            d[2] = (unsigned char)op_clamp8(sb / k[9] + k[10]);
            d[3] = c[3];
        }
    }
    return 1;
}

/* ---- rotate：逆时针为正；dst 预分配，圈外透明；nearest / bilinear ----
 * angle_milli_deg = 度数×1000（i32 规避 VM f32 fast path 封送 bug——坑 9） */
int sli_op_rotate(int64_t src, int64_t dst, int64_t ctl, int angle_milli_deg)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const int* c = (const int*)(intptr_t)ctl;
    int sw, sh, dw, dh, mode, x, y;
    float cs, sn, cx, cy, ncx, ncy, angle_rad;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !dp || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    sw = c[0]; sh = c[1]; dw = c[2]; dh = c[3]; mode = c[4];
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 || (mode != 0 && mode != 1))
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    angle_rad = (float)angle_milli_deg * (float)(3.14159265358979323846 / 180.0) / 1000.0f;
    cs = (float)cos((double)angle_rad);
    sn = (float)sin((double)angle_rad);
    cx = 0.5f * (float)(sw - 1);
    cy = 0.5f * (float)(sh - 1);
    ncx = 0.5f * (float)(dw - 1);
    ncy = 0.5f * (float)(dh - 1);
    memset(dp, 0, (size_t)dw * (size_t)dh * 4);

    for (y = 0; y < dh; ++y)
    {
        for (x = 0; x < dw; ++x)
        {
            float fx = (float)x - ncx;
            float fy = (float)y - ncy;
            float sx = cx + fx * cs - fy * sn;
            float sy = cy + fx * sn + fy * cs;
            int inside = (sx >= -0.5f) && (sx <= (float)sw - 0.5f) &&
                        (sy >= -0.5f) && (sy <= (float)sh - 0.5f);
            unsigned char* d = dp + (size_t)(y * dw + x) * 4;
            if (!inside) continue;
            if (mode == 0)
            {
                int ix = (int)(sx + 0.5f), iy = (int)(sy + 0.5f);
                const unsigned char* p;
                if (ix < 0) ix = 0;
                if (ix >= sw) ix = sw - 1;
                if (iy < 0) iy = 0;
                if (iy >= sh) iy = sh - 1;
                p = sp + (size_t)(iy * sw + ix) * 4;
                d[0] = p[0]; d[1] = p[1]; d[2] = p[2]; d[3] = p[3];
            }
            else
            {
                int x0, x1, y0, y1;
                float wx, wy;
                const unsigned char *p00, *p10, *p01, *p11;
                float w00, w10, w01, w11;
                if (sx < 0.0f) sx = 0.0f;
                if (sx > (float)(sw - 1)) sx = (float)(sw - 1);
                if (sy < 0.0f) sy = 0.0f;
                if (sy > (float)(sh - 1)) sy = (float)(sh - 1);
                x0 = (int)sx; x1 = x0 + 1;
                wx = sx - (float)x0;
                y0 = (int)sy; y1 = y0 + 1;
                wy = sy - (float)y0;
                if (x1 >= sw) x1 = sw - 1;
                if (y1 >= sh) y1 = sh - 1;
                p00 = sp + (size_t)(y0 * sw + x0) * 4;
                p10 = sp + (size_t)(y0 * sw + x1) * 4;
                p01 = sp + (size_t)(y1 * sw + x0) * 4;
                p11 = sp + (size_t)(y1 * sw + x1) * 4;
                w00 = (1.0f - wx) * (1.0f - wy);
                w10 = wx * (1.0f - wy);
                w01 = (1.0f - wx) * wy;
                w11 = wx * wy;
                d[0] = (unsigned char)op_toint((float)p00[0] * w00 + (float)p10[0] * w10 +
                                               (float)p01[0] * w01 + (float)p11[0] * w11);
                d[1] = (unsigned char)op_toint((float)p00[1] * w00 + (float)p10[1] * w10 +
                                               (float)p01[1] * w01 + (float)p11[1] * w11);
                d[2] = (unsigned char)op_toint((float)p00[2] * w00 + (float)p10[2] * w10 +
                                               (float)p01[2] * w01 + (float)p11[2] * w11);
                d[3] = (unsigned char)op_toint((float)p00[3] * w00 + (float)p10[3] * w10 +
                                               (float)p01[3] * w01 + (float)p11[3] * w11);
            }
        }
    }
    return 1;
}

/* ---- resize：nearest / bilinear（公式与 SL resizeNearest/Bilinear 一致） ---- */
int sli_op_resize(int64_t src, int64_t dst, int64_t ctl)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const int* c = (const int*)(intptr_t)ctl;
    int sw, sh, dw, dh, mode, x, y;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !dp || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    sw = c[0]; sh = c[1]; dw = c[2]; dh = c[3]; mode = c[4];
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 || (mode != 0 && mode != 1))
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    for (y = 0; y < dh; ++y)
    {
        for (x = 0; x < dw; ++x)
        {
            unsigned char* d = dp + (size_t)(y * dw + x) * 4;
            if (mode == 0)
            {
                int sy = (int)(1.0f * (float)y * (float)sh / (float)dh);
                int sx = (int)(1.0f * (float)x * (float)sw / (float)dw);
                const unsigned char* p;
                if (sy >= sh) sy = sh - 1;
                if (sx >= sw) sx = sw - 1;
                p = sp + (size_t)(sy * sw + sx) * 4;
                d[0] = p[0]; d[1] = p[1]; d[2] = p[2]; d[3] = p[3];
            }
            else
            {
                float fy = 1.0f * (float)(y + 0.5f) * (float)sh / (float)dh - 0.5f;
                float fx = 1.0f * (float)(x + 0.5f) * (float)sw / (float)dw - 0.5f;
                int x0, x1, y0, y1;
                float wx, wy;
                const unsigned char *p00, *p10, *p01, *p11;
                float w00, w10, w01, w11;
                if (fy < 0.0f) fy = 0.0f;
                if (fx < 0.0f) fx = 0.0f;
                y0 = (int)fy; y1 = y0 + 1;
                wy = fy - (float)y0;
                x0 = (int)fx; x1 = x0 + 1;
                wx = fx - (float)x0;
                if (y0 < 0) y0 = 0;
                if (y1 < 0) y1 = 0;
                if (y0 >= sh) y0 = sh - 1;
                if (y1 >= sh) y1 = sh - 1;
                if (x0 < 0) x0 = 0;
                if (x1 < 0) x1 = 0;
                if (x0 >= sw) x0 = sw - 1;
                if (x1 >= sw) x1 = sw - 1;
                p00 = sp + (size_t)(y0 * sw + x0) * 4;
                p10 = sp + (size_t)(y0 * sw + x1) * 4;
                p01 = sp + (size_t)(y1 * sw + x0) * 4;
                p11 = sp + (size_t)(y1 * sw + x1) * 4;
                w00 = (1.0f - wx) * (1.0f - wy);
                w10 = wx * (1.0f - wy);
                w01 = (1.0f - wx) * wy;
                w11 = wx * wy;
                d[0] = (unsigned char)op_toint((float)p00[0] * w00 + (float)p10[0] * w10 +
                                               (float)p01[0] * w01 + (float)p11[0] * w11);
                d[1] = (unsigned char)op_toint((float)p00[1] * w00 + (float)p10[1] * w10 +
                                               (float)p01[1] * w01 + (float)p11[1] * w11);
                d[2] = (unsigned char)op_toint((float)p00[2] * w00 + (float)p10[2] * w10 +
                                               (float)p01[2] * w01 + (float)p11[2] * w11);
                d[3] = (unsigned char)op_toint((float)p00[3] * w00 + (float)p10[3] * w10 +
                                               (float)p01[3] * w01 + (float)p11[3] * w11);
            }
        }
    }
    return 1;
}

/* ---- alpha 合成：src over dst（Std ColorInt.blendOver 逐位镜像） ---- */
int sli_op_alpha_composite(int64_t dst, int64_t src, int64_t out, int w, int h)
{
    const unsigned char* d = (const unsigned char*)(intptr_t)dst;
    const unsigned char* s = (const unsigned char*)(intptr_t)src;
    unsigned char* o = (unsigned char*)(intptr_t)out;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!d || !s || !o || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* dp = d + (size_t)i * 4;
        const unsigned char* sp = s + (size_t)i * 4;
        unsigned char* op = o + (size_t)i * 4;
        if (sp[3] >= 255)
        {
            op[0] = sp[0]; op[1] = sp[1]; op[2] = sp[2]; op[3] = sp[3];
        }
        else if (sp[3] <= 0)
        {
            op[0] = dp[0]; op[1] = dp[1]; op[2] = dp[2]; op[3] = dp[3];
        }
        else
        {
            float sa = 1.0f * (float)sp[3] / 255.0f;
            float da = 1.0f * (float)dp[3] / 255.0f;
            float oa = sa + da * (1.0f - sa);
            if (oa <= 0.0f)
            {
                op[0] = 0; op[1] = 0; op[2] = 0; op[3] = 0;
            }
            else
            {
                float rr = (1.0f * (float)sp[0] * sa + 1.0f * (float)dp[0] * da * (1.0f - sa)) / oa;
                float gg = (1.0f * (float)sp[1] * sa + 1.0f * (float)dp[1] * da * (1.0f - sa)) / oa;
                float bb = (1.0f * (float)sp[2] * sa + 1.0f * (float)dp[2] * da * (1.0f - sa)) / oa;
                int a;
                if (oa > 1.0f) a = 255;
                else a = (int)(oa * 255.0f + 0.5f);
                op[0] = (unsigned char)op_toint(rr);
                op[1] = (unsigned char)op_toint(gg);
                op[2] = (unsigned char)op_toint(bb);
                op[3] = (unsigned char)op_clamp8(a);
            }
        }
    }
    return 1;
}

/* ---- 线性混合：out = a*(1-alpha) + b*alpha（ImageBuffer.blend 同式；
 * alpha_x1000 = alpha×1000，i32 规避 VM f32 封送 bug——坑 9） ---- */
int sli_op_blend(int64_t a, int64_t b, int64_t out, int w, int h, int alpha_x1000)
{
    const unsigned char* pa = (const unsigned char*)(intptr_t)a;
    const unsigned char* pb = (const unsigned char*)(intptr_t)b;
    unsigned char* po = (unsigned char*)(intptr_t)out;
    float alpha, fa;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!pa || !pb || !po || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (alpha_x1000 < 0) alpha_x1000 = 0;
    if (alpha_x1000 > 1000) alpha_x1000 = 1000;
    alpha = (float)alpha_x1000 / 1000.0f;
    fa = 1.0f - alpha;

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* qa = pa + (size_t)i * 4;
        const unsigned char* qb = pb + (size_t)i * 4;
        unsigned char* qo = po + (size_t)i * 4;
        qo[0] = (unsigned char)op_toint(1.0f * (float)qa[0] * fa + 1.0f * (float)qb[0] * alpha);
        qo[1] = (unsigned char)op_toint(1.0f * (float)qa[1] * fa + 1.0f * (float)qb[1] * alpha);
        qo[2] = (unsigned char)op_toint(1.0f * (float)qa[2] * fa + 1.0f * (float)qb[2] * alpha);
        qo[3] = (unsigned char)op_toint(1.0f * (float)qa[3] * fa + 1.0f * (float)qb[3] * alpha);
    }
    return 1;
}

/* ---- 拆通道：RGBA8 -> 4 张 Gray8 平面 ---- */
int sli_op_split_rgba(int64_t src, int64_t r, int64_t g, int64_t b, int64_t a, int64_t ctl)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* rp = (unsigned char*)(intptr_t)r;
    unsigned char* gp = (unsigned char*)(intptr_t)g;
    unsigned char* bp = (unsigned char*)(intptr_t)b;
    unsigned char* ap = (unsigned char*)(intptr_t)a;
    const int* c = (const int*)(intptr_t)ctl;
    int w, h, i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !rp || !gp || !bp || !ap || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    w = c[0]; h = c[1];
    if (w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* p = sp + (size_t)i * 4;
        rp[i] = p[0];
        gp[i] = p[1];
        bp[i] = p[2];
        ap[i] = p[3];
    }
    return 1;
}

/* ---- 合通道：3 张 Gray8 -> 不透明 Rgba8 ---- */
int sli_op_merge_rgb(int64_t r, int64_t g, int64_t b, int64_t dst, int w, int h)
{
    const unsigned char* rp = (const unsigned char*)(intptr_t)r;
    const unsigned char* gp = (const unsigned char*)(intptr_t)g;
    const unsigned char* bp = (const unsigned char*)(intptr_t)b;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!rp || !gp || !bp || !dp || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        unsigned char* d = dp + (size_t)i * 4;
        d[0] = rp[i]; d[1] = gp[i]; d[2] = bp[i]; d[3] = 255;
    }
    return 1;
}

/* ---- 合通道：4 张 Gray8 -> Rgba8 ---- */
int sli_op_merge_rgba(int64_t r, int64_t g, int64_t b, int64_t a, int64_t dst, int64_t ctl)
{
    const unsigned char* rp = (const unsigned char*)(intptr_t)r;
    const unsigned char* gp = (const unsigned char*)(intptr_t)g;
    const unsigned char* bp = (const unsigned char*)(intptr_t)b;
    const unsigned char* ap = (const unsigned char*)(intptr_t)a;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const int* c = (const int*)(intptr_t)ctl;
    int w, h, i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!rp || !gp || !bp || !ap || !dp || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    w = c[0]; h = c[1];
    if (w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        unsigned char* d = dp + (size_t)i * 4;
        d[0] = rp[i]; d[1] = gp[i]; d[2] = bp[i]; d[3] = ap[i];
    }
    return 1;
}

/* ---- 像素格式转换（EPixelFormat 值；读写语义镜像 SL getPixel/setPixel） ---- */
static int op_read_pixel(const unsigned char* p, int fmt, int* pr, int* pg, int* pb, int* pa)
{
    switch (fmt)
    {
    case 1: /* Gray8 */   { int v = p[0]; *pr = v; *pg = v; *pb = v; *pa = 255; return 1; }
    case 2: /* Gray16 */  { int v = p[1]; *pr = v; *pg = v; *pb = v; *pa = 255; return 1; }
    case 3: /* Rgb8 */    { *pr = p[0]; *pg = p[1]; *pb = p[2]; *pa = 255; return 1; }
    case 4: /* Rgba8 */   { *pr = p[0]; *pg = p[1]; *pb = p[2]; *pa = p[3]; return 1; }
    case 5: /* Bgr8 */    { *pr = p[2]; *pg = p[1]; *pb = p[0]; *pa = 255; return 1; }
    case 6: /* Bgra8 */   { *pr = p[2]; *pg = p[1]; *pb = p[0]; *pa = p[3]; return 1; }
    case 7: /* Rgb16 */   { *pr = p[1]; *pg = p[3]; *pb = p[5]; *pa = 255; return 1; }
    case 8: /* Rgba16 */  { *pr = p[1]; *pg = p[3]; *pb = p[5]; *pa = p[7]; return 1; }
    default: return 0;    /* 浮点格式 9/10 由 SL 兜底 */
    }
}

static int op_write_pixel(unsigned char* p, int fmt, int r, int g, int b, int a)
{
    switch (fmt)
    {
    case 1: /* Gray8 */   { p[0] = (unsigned char)op_gray(r, g, b); return 1; }
    case 2: /* Gray16 */ { int v = op_gray(r, g, b); p[0] = 0; p[1] = (unsigned char)v; return 1; }
    case 3: /* Rgb8 */   { p[0] = (unsigned char)r; p[1] = (unsigned char)g; p[2] = (unsigned char)b; return 1; }
    case 4: /* Rgba8 */  { p[0] = (unsigned char)r; p[1] = (unsigned char)g; p[2] = (unsigned char)b; p[3] = (unsigned char)a; return 1; }
    case 5: /* Bgr8 */   { p[0] = (unsigned char)b; p[1] = (unsigned char)g; p[2] = (unsigned char)r; return 1; }
    case 6: /* Bgra8 */  { p[0] = (unsigned char)b; p[1] = (unsigned char)g; p[2] = (unsigned char)r; p[3] = (unsigned char)a; return 1; }
    case 7: /* Rgb16 */  { p[0] = 0; p[1] = (unsigned char)r; p[2] = 0; p[3] = (unsigned char)g; p[4] = 0; p[5] = (unsigned char)b; return 1; }
    case 8: /* Rgba16 */ { p[0] = 0; p[1] = (unsigned char)r; p[2] = 0; p[3] = (unsigned char)g; p[4] = 0; p[5] = (unsigned char)b; p[6] = 0; p[7] = (unsigned char)a; return 1; }
    default: return 0;
    }
}

static int op_bpp(int fmt)
{
    switch (fmt)
    {
    case 1: return 1;
    case 2: return 2;
    case 3: case 5: return 3;
    case 4: case 6: return 4;
    case 7: return 6;
    case 8: return 8;
    default: return 0;
    }
}

int sli_op_convert(int64_t src, int64_t dst, int w, int h, int src_fmt, int dst_fmt)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    int sbpp, dbpp, i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !dp || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    sbpp = op_bpp(src_fmt);
    dbpp = op_bpp(dst_fmt);
    if (sbpp <= 0 || dbpp <= 0)
    { sli_set_error_detail(SLI_E_UNSUPPORTED, "fmt %d -> %d", src_fmt, dst_fmt); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        int r, g, b, a;
        if (!op_read_pixel(sp + (size_t)i * sbpp, src_fmt, &r, &g, &b, &a))
        { sli_set_error_detail(SLI_E_UNSUPPORTED, "fmt %d", src_fmt); return 0; }
        if (!op_write_pixel(dp + (size_t)i * dbpp, dst_fmt, r, g, b, a))
        { sli_set_error_detail(SLI_E_UNSUPPORTED, "fmt %d", dst_fmt); return 0; }
    }
    return 1;
}

/* ---- 区域贴入：整块覆盖，越界裁剪（ImageBuffer.paste 同域） ---- */
int sli_op_paste(int64_t dst, int64_t src, int64_t ctl)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    const int* c = (const int*)(intptr_t)ctl;
    int dw, dh, sw, sh, x, y, x0, y0, x1, y1, dy;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || !sp || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    dw = c[0]; dh = c[1]; sw = c[2]; sh = c[3]; x = c[4]; y = c[5];
    if (dw <= 0 || dh <= 0 || sw <= 0 || sh <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    x0 = x < 0 ? 0 : x;
    y0 = y < 0 ? 0 : y;
    x1 = x + sw; if (x1 > dw) x1 = dw;
    y1 = y + sh; if (y1 > dh) y1 = dh;
    if (x1 <= x0 || y1 <= y0) return 1;    /* 空区域 = 成功（同 SL 语义） */

    for (dy = y0; dy < y1; ++dy)
    {
        memcpy(dp + (size_t)(((size_t)dy * (size_t)dw) + (size_t)x0) * 4,
               sp + (size_t)(((size_t)(dy - y) * (size_t)sw) + (size_t)(x0 - x)) * 4,
               (size_t)(x1 - x0) * 4);
    }
    return 1;
}

/* ---- 纯色填充：rgba = 0xRRGGBBAA（Std toPackedRgba 布局） ---- */
int sli_op_fill(int64_t dst, int w, int h, int rgba)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    unsigned char r = (unsigned char)((rgba >> 24) & 0xFF);
    unsigned char g = (unsigned char)((rgba >> 16) & 0xFF);
    unsigned char b = (unsigned char)((rgba >> 8) & 0xFF);
    unsigned char a = (unsigned char)(rgba & 0xFF);
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        unsigned char* p = dp + (size_t)i * 4;
        p[0] = r; p[1] = g; p[2] = b; p[3] = a;
    }
    return 1;
}

/* ---- 上下翻转：行交换（w*4 字节行） ---- */
int sli_op_flip_y(int64_t dst, int w, int h)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    unsigned char* row;
    int stride, top, bottom;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    stride = w * 4;
    row = (unsigned char*)malloc((size_t)stride);
    if (!row) { sli_set_error(SLI_E_MEMORY); return 0; }
    top = 0;
    bottom = h - 1;
    while (top < bottom)
    {
        unsigned char* a = dp + (size_t)top * (size_t)stride;
        unsigned char* b = dp + (size_t)bottom * (size_t)stride;
        memcpy(row, a, (size_t)stride);
        memcpy(a, b, (size_t)stride);
        memcpy(b, row, (size_t)stride);
        ++top;
        --bottom;
    }
    free(row);
    return 1;
}

/* ---- 左右翻转：行内像素交换 ---- */
int sli_op_flip_x(int64_t dst, int w, int h)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    int y;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    for (y = 0; y < h; ++y)
    {
        unsigned char* row = dp + (size_t)y * (size_t)w * 4;
        int left = 0, right = w - 1;
        while (left < right)
        {
            unsigned char* a = row + (size_t)left * 4;
            unsigned char* b = row + (size_t)right * 4;
            unsigned char t0 = a[0], t1 = a[1], t2 = a[2], t3 = a[3];
            a[0] = b[0]; a[1] = b[1]; a[2] = b[2]; a[3] = b[3];
            b[0] = t0; b[1] = t1; b[2] = t2; b[3] = t3;
            ++left;
            --right;
        }
    }
    return 1;
}

/* ---- alpha 预乘 / 反预乘（Std ColorInt.premultiply/unpremultiply 同式） ---- */
int sli_op_premultiply(int64_t dst, int w, int h, int unpre)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (unpre != 0 && unpre != 1) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        unsigned char* p = dp + (size_t)i * 4;
        int r = p[0], g = p[1], b = p[2], a = p[3];
        if (unpre == 0)
        {
            p[0] = (unsigned char)((r * a + 127) / 255);
            p[1] = (unsigned char)((g * a + 127) / 255);
            p[2] = (unsigned char)((b * a + 127) / 255);
        }
        else
        {
            if (a <= 0) { p[0] = 0; p[1] = 0; p[2] = 0; }
            else if (a >= 255) { /* 原样 */ }
            else
            {
                p[0] = (unsigned char)op_clamp8(r * 255 / a);
                p[1] = (unsigned char)op_clamp8(g * 255 / a);
                p[2] = (unsigned char)op_clamp8(b * 255 / a);
            }
        }
    }
    return 1;
}

/* =========================================================================
 * 高级合成家族（v2.1，2026-11-28）
 * 仿 Pillow ImageChops / ImageEnhance / 蒙版合成（runoob pillow-advanced）。
 * 语义与 SL 兜底逐位对齐：整数除法截断、clamp8、BT.601。
 * ========================================================================= */

/* ---- 灰度化（BT.601 写回 RGB，alpha 保留） ---- */
int sli_op_grayscale(int64_t src, int64_t dst, int w, int h)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || !dp || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* p = sp + (size_t)i * 4;
        unsigned char* d = dp + (size_t)i * 4;
        int v = (unsigned char)op_gray(p[0], p[1], p[2]);
        d[0] = (unsigned char)v;
        d[1] = (unsigned char)v;
        d[2] = (unsigned char)v;
        d[3] = p[3];
    }
    return 1;
}

/* ---- BT.601 灰度均值（四舍五入 0..255；0 = 失败） ---- */
int sli_op_luma_mean(int64_t src, int w, int h)
{
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    int64_t sum = 0;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!sp || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* p = sp + (size_t)i * 4;
        sum += op_gray(p[0], p[1], p[2]);
    }
    return (int)((sum + n / 2) / n);
}

/* ---- 通道运算（11 模式，4 通道同步） ---- */
static int op_chop_channel(int op, int a, int b)
{
    switch (op)
    {
    case 0:  return op_clamp8(a + b);                        /* add        */
    case 1:  return a - b > 0 ? a - b : 0;                    /* subtract   */
    case 2:  return a * b / 255;                             /* multiply   */
    case 3:  return 255 - (255 - a) * (255 - b) / 255;       /* screen     */
    case 4:  { int d = a - b; return d < 0 ? -d : d; }       /* difference */
    case 5:  return a > b ? a : b;                           /* lighter    */
    case 6:  return a < b ? a : b;                           /* darker     */
    case 7:  return 255 - a;                                 /* invert     */
    case 8:  return (a * (255 - b) + b * b / 255) / 255;     /* soft_light */
    case 9:  return b < 128                                  /* hard_light */
             ? 2 * a * b / 255
             : 255 - 2 * (255 - a) * (255 - b) / 255;
    case 10: return a < 128                                  /* overlay    */
             ? 2 * a * b / 255
             : 255 - 2 * (255 - a) * (255 - b) / 255;
    default: return a;
    }
}

int sli_op_chops(int op, int64_t a, int64_t b, int64_t out, int w, int h)
{
    const unsigned char* pa = (const unsigned char*)(intptr_t)a;
    const unsigned char* pb = (const unsigned char*)(intptr_t)b;
    unsigned char* po = (unsigned char*)(intptr_t)out;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (op < 0 || op > 10)
    { sli_set_error_detail(SLI_E_BAD_PARAM, "chops op %d", op); return 0; }
    if (!pa || !po || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    if (op != 7 && !pb) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* qa = pa + (size_t)i * 4;
        const unsigned char* qb = pb + (size_t)i * 4;
        unsigned char* qo = po + (size_t)i * 4;
        int k;
        for (k = 0; k < 4; ++k)
        {
            qo[k] = (unsigned char)op_clamp8(op_chop_channel(op, qa[k], qb[k]));
        }
    }
    return 1;
}

/* ---- 蒙版混合：out = a*(1-m/255) + b*(m/255)（4 通道） ---- */
int sli_op_mask_blend(int64_t a, int64_t b, int64_t mask, int64_t out, int64_t ctl)
{
    const unsigned char* pa = (const unsigned char*)(intptr_t)a;
    const unsigned char* pb = (const unsigned char*)(intptr_t)b;
    const unsigned char* pm = (const unsigned char*)(intptr_t)mask;
    unsigned char* po = (unsigned char*)(intptr_t)out;
    const int* c = (const int*)(intptr_t)ctl;
    int w, h, i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!pa || !pb || !pm || !po || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    w = c[0]; h = c[1];
    if (w <= 0 || h <= 0) { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* qa = pa + (size_t)i * 4;
        const unsigned char* qb = pb + (size_t)i * 4;
        unsigned char* qo = po + (size_t)i * 4;
        int m = pm[i];
        int k;
        for (k = 0; k < 4; ++k)
        {
            qo[k] = (unsigned char)op_clamp8(qa[k] + (qb[k] - qa[k]) * m / 255);
        }
    }
    return 1;
}

/* ---- 带蒙版贴入：f = mask/255，dst = src*f + dst*(1-f)（覆盖域内） ---- */
int sli_op_paste_masked(int64_t dst, int64_t src, int64_t mask, int64_t ctl)
{
    unsigned char* dp = (unsigned char*)(intptr_t)dst;
    const unsigned char* sp = (const unsigned char*)(intptr_t)src;
    const unsigned char* mp = (const unsigned char*)(intptr_t)mask;
    const int* c = (const int*)(intptr_t)ctl;
    int dw, dh, sw, sh, x, y, x0, y0, x1, y1, dy;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!dp || !sp || !mp || !c)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    dw = c[0]; dh = c[1]; sw = c[2]; sh = c[3]; x = c[4]; y = c[5];
    if (dw <= 0 || dh <= 0 || sw <= 0 || sh <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }

    x0 = x < 0 ? 0 : x;
    y0 = y < 0 ? 0 : y;
    x1 = x + sw; if (x1 > dw) x1 = dw;
    y1 = y + sh; if (y1 > dh) y1 = dh;
    if (x1 <= x0 || y1 <= y0) return 1;    /* 空区域 = 成功（同 paste 语义） */

    for (dy = y0; dy < y1; ++dy)
    {
        int sy = dy - y;
        int dx;
        for (dx = x0; dx < x1; ++dx)
        {
            int sx = dx - x;
            unsigned char* d = dp + (size_t)((size_t)dy * (size_t)dw + (size_t)dx) * 4;
            const unsigned char* s = sp + (size_t)((size_t)sy * (size_t)sw + (size_t)sx) * 4;
            int m = mp[(size_t)sy * (size_t)sw + (size_t)sx];
            int k;
            for (k = 0; k < 4; ++k)
            {
                d[k] = (unsigned char)op_clamp8(d[k] + (s[k] - d[k]) * m / 255);
            }
        }
    }
    return 1;
}

/* ---- 线性插值（不钳 factor；factor_x1000 = factor×1000，i32 规避
 * VM f32 封送 bug——坑 9；ImageEnhance 外插用） ---- */
int sli_op_blend_factor(int64_t a, int64_t b, int64_t out, int w, int h, int factor_x1000)
{
    const unsigned char* pa = (const unsigned char*)(intptr_t)a;
    const unsigned char* pb = (const unsigned char*)(intptr_t)b;
    unsigned char* po = (unsigned char*)(intptr_t)out;
    float factor;
    int i, n;

    if (!s_ready) { sli_set_error(SLI_E_NOT_INITIALIZED); return 0; }
    if (!pa || !pb || !po || w <= 0 || h <= 0)
    { sli_set_error(SLI_E_BAD_PARAM); return 0; }
    factor = (float)factor_x1000 / 1000.0f;

    n = w * h;
    for (i = 0; i < n; ++i)
    {
        const unsigned char* qa = pa + (size_t)i * 4;
        const unsigned char* qb = pb + (size_t)i * 4;
        unsigned char* qo = po + (size_t)i * 4;
        int k;
        for (k = 0; k < 4; ++k)
        {
            float v = (float)qa[k] * (1.0f - factor) + (float)qb[k] * factor;
            qo[k] = (unsigned char)op_toint(v);
        }
    }
    return 1;
}
