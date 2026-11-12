/* =========================================================================
 * sl_image_stb.c —— Codec：stb_image v2.31 / stb_image_write v1.17
 *
 * third_party/stb/ 整文件内置（public domain / MIT-0，见同目录 LICENSE.md）。
 * 本文件是 stb 实现的唯一编译点（IMPLEMENTATION 宏只在此定义一次）：
 *   - 解码：stbi_load_from_memory（JPEG/PNG/BMP/GIF/TGA/PSD/HDR/PIC/PNM）
 *           输出恒 4 通道 RGBA8 top-down（SL 像素契约）
 *   - 编码：PNG 走 stbi_write_png_to_mem（堆块直出）；
 *           JPEG/BMP/TGA 走 *_to_func + 增长缓冲回调；
 *           PPM(P6) 无 stb 写路，本文件手写 15 行头 + 3 通道像素拷贝。
 * stb 自带 assert 关闭（STBI_ASSERT/STBIW_ASSERT 空实现，坏数据走
 * NULL 返回 + sli_set_error_detail(stbi 失败原因字符串)）。
 * ========================================================================= */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>

#include "../sl_image_internal.h"

/* ---- 关闭 stb 的 assert（异常输入不崩进程，走 NULL 失败路径）---- */
#define STBI_ASSERT(x)   ((void)0)
#define STBIW_ASSERT(x)  ((void)0)

#define STB_IMAGE_IMPLEMENTATION
#include "../third_party/stb/stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../third_party/stb/stb_image_write.h"

/* ================= 解码 ================= */

unsigned char* sli_stb_decode_mem(const unsigned char* data, int64_t size,
                                   int req_channels, int* w, int* h)
{
    int cw = 0, ch = 0, cc = 0;
    unsigned char* pixels;
    const char* why = NULL;

    if (size > (int64_t)INT_MAX)
    {
        sli_set_error_detail(SLI_E_TOO_LARGE, "input %lld bytes", (long long)size);
        return NULL;
    }
    pixels = stbi_load_from_memory(data, (int)size, &cw, &ch, &cc,
                                    (req_channels == 3) ? 3 : 4);
    if (!pixels)
    {
        why = stbi_failure_reason();
        sli_set_error_detail(SLI_E_DECODE, "stb: %s",
                              why ? why : "unknown reason");
        return NULL;
    }
    *w = cw;
    *h = ch;
    /* 契约恒 RGBA8：req=3 的调用方由上层规避（v1 统一 4 通道） */
    if (req_channels == 3)
    {
        int64_t n3 = (int64_t)cw * (int64_t)ch * 3;
        int64_t i;
        unsigned char* rgba = (unsigned char*)malloc((size_t)(n3 / 3 * 4));
        if (!rgba) { free(pixels); sli_set_error(SLI_E_MEMORY); return NULL; }
        for (i = 0; i < cw * ch; i++)
        {
            rgba[i * 4 + 0] = pixels[i * 3 + 0];
            rgba[i * 4 + 1] = pixels[i * 3 + 1];
            rgba[i * 4 + 2] = pixels[i * 3 + 2];
            rgba[i * 4 + 3] = 255;
        }
        free(pixels);
        return rgba;
    }
    return pixels;
}

/* ================= 编码 ================= */

/* 增长缓冲（_to_func 回调的落点） */
typedef struct SliGrowBuf
{
    unsigned char* data;
    int64_t         len;
    int64_t         cap;
    int             oom;
} SliGrowBuf;

static void grow_reset(SliGrowBuf* g)
{
    g->data = NULL;
    g->len = 0;
    g->cap = 0;
    g->oom = 0;
}

static void grow_append(void* ctx, void* d, int size)
{
    SliGrowBuf* g = (SliGrowBuf*)ctx;
    if (size <= 0 || g->oom) return;
    if (g->len + (int64_t)size > g->cap)
    {
        int64_t want = g->len + (int64_t)size;
        int64_t cap = (g->cap > 0) ? g->cap * 2 : 4096;
        unsigned char* nd;
        while (cap < want) cap *= 2;
        nd = (unsigned char*)realloc(g->data, (size_t)cap);
        if (!nd) { g->oom = 1; free(g->data); g->data = NULL; g->cap = 0; return; }
        g->data = nd;
        g->cap = cap;
    }
    memcpy(g->data + g->len, d, (size_t)size);
    g->len += (int64_t)size;
}

static unsigned char* grow_take(SliGrowBuf* g, int64_t* out_size)
{
    if (g->oom) { free(g->data); g->data = NULL; g->len = 0; }
    if (!g->data || g->len <= 0) { free(g->data); g->data = NULL; return NULL; }
    *out_size = g->len;
    return g->data;
}

/* PPM(P6) 手写：15 字节头 + RGB8 紧密像素 */
static unsigned char* ppm_write(int w, int h, const unsigned char* rgba, int64_t* out_size)
{
    char head[64];
    int head_len;
    int64_t body = (int64_t)w * (int64_t)h * 3;
    unsigned char* out;
    int64_t i;
    head_len = snprintf(head, sizeof(head), "P6\n%d %d\n255\n", w, h);
    if (head_len <= 0) return NULL;
    out = (unsigned char*)malloc((size_t)head_len + (size_t)body);
    if (!out) { sli_set_error(SLI_E_MEMORY); return NULL; }
    memcpy(out, head, (size_t)head_len);
    for (i = 0; i < (int64_t)w * h; i++)
    {
        out[head_len + i * 3 + 0] = rgba[i * 4 + 0];
        out[head_len + i * 3 + 1] = rgba[i * 4 + 1];
        out[head_len + i * 3 + 2] = rgba[i * 4 + 2];
    }
    *out_size = (int64_t)head_len + body;
    return out;
}

unsigned char* sli_stb_encode_mem(int fmt, int quality,
                                   int w, int h, const unsigned char* rgba,
                                   int64_t* out_size)
{
    SliGrowBuf g;
    unsigned char* out = NULL;
    int ok = 0;

    *out_size = 0;
    if (!rgba) { sli_set_error(SLI_E_BAD_PARAM); return NULL; }

    switch (fmt)
    {
    case SLI_FMT_PNG:
    {
        int len = 0;
        unsigned char* png = stbi_write_png_to_mem(rgba, 0, w, h, 4, &len);
        if (!png) { sli_set_error_detail(SLI_E_ENCODE, "stb png"); return NULL; }
        *out_size = len;
        return png;
    }
    case SLI_FMT_JPEG:
        grow_reset(&g);
        ok = stbi_write_jpg_to_func(grow_append, &g, w, h, 4, rgba,
                                    (quality > 0 && quality < 100) ? quality : 90);
        out = ok ? grow_take(&g, out_size) : NULL;
        if (!ok || !out)
        {
            free(g.data); g.data = NULL;
            sli_set_error_detail(SLI_E_ENCODE, "stb jpeg");
            return NULL;
        }
        return out;
    case SLI_FMT_BMP:
        grow_reset(&g);
        ok = stbi_write_bmp_to_func(grow_append, &g, w, h, 4, rgba);
        out = ok ? grow_take(&g, out_size) : NULL;
        if (!ok || !out)
        {
            free(g.data); g.data = NULL;
            sli_set_error_detail(SLI_E_ENCODE, "stb bmp");
            return NULL;
        }
        return out;
    case SLI_FMT_TGA:
        grow_reset(&g);
        ok = stbi_write_tga_to_func(grow_append, &g, w, h, 4, rgba);
        out = ok ? grow_take(&g, out_size) : NULL;
        if (!ok || !out)
        {
            free(g.data); g.data = NULL;
            sli_set_error_detail(SLI_E_ENCODE, "stb tga");
            return NULL;
        }
        return out;
    case SLI_FMT_PPM:
        out = ppm_write(w, h, rgba, out_size);
        if (!out) { sli_set_error_detail(SLI_E_ENCODE, "ppm write"); return NULL; }
        return out;
    default:
        sli_set_error_detail(SLI_E_UNSUPPORTED, "stb encode fmt %d", fmt);
        return NULL;
    }
}
