/* =========================================================================
 * sl_image_gif.c —— GIF89a 动画编码（自有实现，无外部依赖）
 *
 * 对应 SL 侧 Gif.sl；解码动画走 stb（sl_image_stb.c 的 sli_stb_decode_gif），
 * 本文件只负责"普通图 -> GIF 动画"的合成方向：
 *   1) 全局调色板量化：唯一色 <= 255 时精确直配；否则中位切分（median cut）
 *      到 255 桶；唯一色超限时退化到 4:4:4 RGB 直方图取桶均色。
 *   2) 半透明处理：alpha < 128 视为透明，占独立索引（GCE 透明色标记）。
 *   3) LZW 压缩（9..12 位变宽码，12 位满表发 CLEAR 复位）。
 *   4) 容器写入：GIF89a 头 / LSD / GCT / NETSCAPE 循环扩展 /
 *      每帧 GCE（延迟 + 透明 + disposal=1）/ 图像描述符 / 子块化 LZW 流。
 *
 * 自有结构体命名遵守用户规则：PascalCase（函数名保持 snake_case）。
 * ========================================================================= */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>

#include "sl_image_internal.h"

/* ================= 内部：统一错误直通 ================= */
static void gif_fail(int err, const char* fmt, ...)
{
    char buf[192];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    sli_set_error_detail(err, "gif: %s", buf);
}

/* ================= NETSCAPE2.0 循环扩展扫描 ================= */
/* 找 21 FF 0B "NETSCAPE2.0" 后首个 03 01 <u16LE>；返回原值（-1 无扩展）。
 * 扫描直接穿透子块长度字段（应用扩展体短小，错配概率极低且只读安全）。 */
int sli_gif_scan_loop(const unsigned char* data, int64_t size)
{
    static const char tag[] = { 'N','E','T','S','C','A','P','E','2','.','0' };
    int64_t i, n = size;
    if (!data || n < 32) return -1;
    for (i = 0; i + 14 < n; i++)
    {
        int k;
        if (data[i] != 0x21 || data[i + 1] != 0xFF || data[i + 2] != 0x0B) continue;
        for (k = 0; k < 11; k++)
            if ((char)data[i + 3 + k] != tag[k]) break;
        if (k == 11 && i + 17 < n &&
            data[i + 14] == 0x03 && data[i + 15] == 0x01)
            return (int)data[i + 16] | ((int)data[i + 17] << 8);
    }
    return -1;
}

/* ================= 调色板量化 ================= */
/* 唯一色收集：开放定址哈希（键 = RGB24）。上限 GIF_MAX_UNIQUE；超限置
 * *overflow = 1，调用方退化为 4:4:4 桶量化。带频次，供中位切分加权。 */
#define GIF_UNIQUE_CAP 65536
#define GIF_UNIQUE_SIZE (GIF_UNIQUE_CAP * 2)  /* 装填 < 0.5 */
#define GIF_UNIQUE_KEY(c) (69069u * (c))

typedef struct SliGifColors
{
    unsigned int* rgb;      /* 0 = 空；否则 RGB24            */
    int*          cnt;      /* 出现次数                      */
    int           used;     /* 唯一色数（<= GIF_UNIQUE_CAP） */
    int           overflow; /* 1 = 唯一色超限                */
} SliGifColors;

static SliGifColors g_colors;

static void colors_reset(void)
{
    memset(g_colors.rgb, 0, sizeof(unsigned int) * GIF_UNIQUE_SIZE);
    memset(g_colors.cnt, 0, sizeof(int) * GIF_UNIQUE_SIZE);
    g_colors.used = 0;
    g_colors.overflow = 0;
}

static int colors_init(void)
{
    if (g_colors.rgb) return 1;
    g_colors.rgb = (unsigned int*)calloc(GIF_UNIQUE_SIZE, sizeof(unsigned int));
    g_colors.cnt = (int*)calloc(GIF_UNIQUE_SIZE, sizeof(int));
    if (!g_colors.rgb || !g_colors.cnt)
    {
        free(g_colors.rgb); free(g_colors.cnt);
        g_colors.rgb = NULL; g_colors.cnt = NULL;
        return 0;
    }
    return 1;
}

/* 登记一个不透明像素颜色；返回 0 = 表满（overflow 置位）。
 * 存储键 = rgb24 | 0x1000000（bit24 恒置位），0 保留为空槽哨兵。 */
static int colors_add(unsigned int rgb24)
{
    unsigned int k = rgb24 | 0x1000000u;
    unsigned int key = GIF_UNIQUE_KEY(k) & (GIF_UNIQUE_SIZE - 1);
    for (;;)
    {
        if (g_colors.rgb[key] == 0)
        {
            if (g_colors.used >= GIF_UNIQUE_CAP) { g_colors.overflow = 1; return 0; }
            g_colors.rgb[key] = k;
            g_colors.cnt[key] = 1;
            g_colors.used++;
            return 1;
        }
        if (g_colors.rgb[key] == k) { g_colors.cnt[key]++; return 1; }
        key = (key + 1) & (GIF_UNIQUE_SIZE - 1);
    }
}

/* ================= 中位切分（median cut） ================= */
#define GIF_PAL_MAX 256
typedef struct SliGifPal
{
    unsigned char rgb[GIF_PAL_MAX * 3];
    int           n;                 /* 不含透明槽                         */
    int           transparent;       /* 1 = 尾部有透明槽（索引 n）         */
    /* 唯一色 -> 调色板索引（与 g_colors 槽位对齐；overflow 路不建） */
    int*          slot_index;
} SliGifPal;

static SliGifPal g_pal;

static int pal_reset(void)
{
    if (!colors_init()) return 0;
    colors_reset();
    if (!g_pal.slot_index)
        g_pal.slot_index = (int*)malloc(sizeof(int) * GIF_UNIQUE_SIZE);
    if (!g_pal.slot_index) return 0;
    g_pal.n = 0;
    g_pal.transparent = 0;
    return 1;
}

/* 唯一色收集（全部帧一遍；alpha<128 计入 has_transparent） */
static int pal_collect(unsigned char** frame_pix, int frame_count,
                       int64_t frame_len, int* has_transparent)
{
    int f, i;
    *has_transparent = 0;
    for (f = 0; f < frame_count; f++)
    {
        const unsigned char* p = frame_pix[f];
        for (i = 0; i + 3 < frame_len; i += 4)
        {
            if (p[i + 3] < 128) { *has_transparent = 1; continue; }
            if (!colors_add(((unsigned int)p[i] << 16) |
                            ((unsigned int)p[i + 1] << 8) | p[i + 2]))
                return 0;  /* 已置 overflow，调用方走桶退化 */
        }
    }
    return 1;
}

static int sq3(int dr, int dg, int db)
{
    return dr * dr + dg * dg + db * db;
}

/* 最近调色板项（线性扫描；<= 256 项，唯一色粒度足够） */
static int pal_nearest(const unsigned char* rgb, int n)
{
    int i, best = 0, bd = 0x7fffffff;
    for (i = 0; i < n; i++)
    {
        int d = sq3(rgb[0] - g_pal.rgb[i * 3],
                    rgb[1] - g_pal.rgb[i * 3 + 1],
                    rgb[2] - g_pal.rgb[i * 3 + 2]);
        if (d < bd) { bd = d; best = i; }
    }
    return best;
}

/* ---- 中位切分本体 ---- */
/* 唯一色先抽到连续数组（值/频次），在数组区间上反复切"最宽通道桶"。
 * boxes 区间 (lo,hi)；每轮选通道跨度最大的桶，排序后按频次加权中位切开。 */
typedef struct { unsigned int rgb; int cnt; } SliGifItem;

static int blo[GIF_PAL_MAX], bhi[GIF_PAL_MAX];

/* rgb24 拆出通道 c（0=R 1=G 2=B） */
static int chan(unsigned int rgb, int c)
{
    return (int)((rgb >> (16 - 8 * c)) & 255);
}

static void item_sort(SliGifItem* a, int lo, int hi, int c)
{
    int i, j;
    for (i = lo + 1; i <= hi; i++)
    {
        SliGifItem t = a[i];
        int v = chan(t.rgb, c);
        for (j = i - 1; j >= lo && chan(a[j].rgb, c) > v; j--) a[j + 1] = a[j];
        a[j + 1] = t;
    }
}

/* 求桶 (lo,hi) 的最宽通道；返回跨度，sel 带回通道号 */
static int box_widest(const SliGifItem* a, int lo, int hi, int* sel)
{
    int mn[3] = { 256, 256, 256 }, mx[3] = { -1, -1, -1 };
    int c, span = -1;
    int j;
    for (j = lo; j <= hi; j++)
    {
        for (c = 0; c < 3; c++)
        {
            int v = chan(a[j].rgb, c);
            if (v < mn[c]) mn[c] = v;
            if (v > mx[c]) mx[c] = v;
        }
    }
    for (c = 0; c < 3; c++)
        if (mx[c] - mn[c] > span) { span = mx[c] - mn[c]; *sel = c; }
    return span;
}

static int median_cut(SliGifItem* items, int n, int want)
{
    int nbox = 1, pal_n = 0, i;
    blo[0] = 0; bhi[0] = n - 1;
    while (nbox < want)
    {
        int bi = -1, bw = -1, bsel = 0, j;
        for (i = 0; i < nbox; i++)
        {
            int sel = 0, span;
            if (blo[i] >= bhi[i]) continue;
            span = box_widest(items, blo[i], bhi[i], &sel);
            if (span > bw) { bw = span; bi = i; bsel = sel; }
        }
        if (bi < 0 || bw <= 0) break;  /* 无可切桶 */
        {
            int lo = blo[bi], hi = bhi[bi];
            int64_t total = 0, acc = 0;
            item_sort(items, lo, hi, bsel);
            for (j = lo; j <= hi; j++) total += items[j].cnt;
            for (j = lo; j < hi; j++)
            {
                acc += items[j].cnt;
                if (acc * 2 >= total) break;
            }
            if (j >= hi) j = hi - 1;   /* 防空区间 */
            if (j < lo) j = lo;
            bhi[nbox] = hi;             /* [lo..j] | [j+1..hi] */
            blo[nbox] = j + 1;
            bhi[bi] = j;
            nbox++;
        }
    }
    /* 桶均值（频次加权）-> 调色板 */
    for (i = 0; i < nbox; i++)
    {
        int64_t sr = 0, sg = 0, sb = 0, sc = 0;
        int j, p;
        for (j = blo[i]; j <= bhi[i]; j++)
        {
            sr += (int64_t)chan(items[j].rgb, 0) * items[j].cnt;
            sg += (int64_t)chan(items[j].rgb, 1) * items[j].cnt;
            sb += (int64_t)chan(items[j].rgb, 2) * items[j].cnt;
            sc += items[j].cnt;
        }
        p = pal_n * 3;
        if (sc > 0)
        {
            g_pal.rgb[p]     = (unsigned char)((sr + sc / 2) / sc);
            g_pal.rgb[p + 1] = (unsigned char)((sg + sc / 2) / sc);
            g_pal.rgb[p + 2] = (unsigned char)((sb + sc / 2) / sc);
            pal_n++;
        }
    }
    g_pal.n = pal_n;
    return pal_n;
}

/* ================= 调色板构建（三档策略） ================= */
/* 返回 1 成功：g_pal.n 生效（<= 255，透明槽单独占 g_pal.n）。
 * 1) 唯一色 <= 255：精确调色板，像素无损；
 * 2) 唯一色 <= 65536：中位切分到 255 桶；
 * 3) 唯一色溢出：4:4:4 RGB 4096 桶直方图，取桶均色 top 255。 */
static int palette_build(unsigned char** frame_pix, int frame_count,
                         int w, int h, int* has_transparent)
{
    int64_t frame_len = (int64_t)w * h * 4;
    int i, used;
    if (!pal_reset()) { gif_fail(SLI_E_BAD_PARAM, "palette oom"); return 0; }
    if (!pal_collect(frame_pix, frame_count, frame_len, has_transparent))
    {
        /* overflow 已置位 -> 走 4:4:4 退化（下文），无需中止 */
    }
    used = g_colors.used;
    if (g_colors.overflow)
    {
        /* ---- 桶退化：4096 桶直方图 ---- */
        static int64_t br[4096], bg[4096], bb[4096];
        static int64_t bc[4096];
        int f, k, bins = 0;
        memset(br, 0, sizeof(int64_t) * 4096);
        memset(bg, 0, sizeof(int64_t) * 4096);
        memset(bb, 0, sizeof(int64_t) * 4096);
        memset(bc, 0, sizeof(int64_t) * 4096);
        colors_reset();   /* 像素查找退化到最近匹配（哈希不再命中） */
        for (f = 0; f < frame_count; f++)
        {
            const unsigned char* p = frame_pix[f];
            for (k = 0; k + 3 < frame_len; k += 4)
            {
                int b = ((p[k] >> 4) << 8) | ((p[k + 1] >> 4) << 4) | (p[k + 2] >> 4);
                br[b] += p[k]; bg[b] += p[k + 1]; bb[b] += p[k + 2];
                bc[b]++;
            }
        }
        for (k = 0; k < 4096; k++) if (bc[k]) bins++;
        if (bins <= 255)
        {
            for (k = 0; k < 4096; k++)
                if (bc[k])
                {
                    g_pal.rgb[g_pal.n * 3]     = (unsigned char)(br[k] / bc[k]);
                    g_pal.rgb[g_pal.n * 3 + 1] = (unsigned char)(bg[k] / bc[k]);
                    g_pal.rgb[g_pal.n * 3 + 2] = (unsigned char)(bb[k] / bc[k]);
                    g_pal.n++;
                }
        }
        else
        {
            /* 取频次 top 255 桶；不足次频桶丢给最近匹配 */
            static int order[4096];
            int j, t, m = 0;
            for (k = 0; k < 4096; k++) if (bc[k]) order[m++] = k;
            for (i = 1; i < m; i++)          /* 插入排序按频次降序 */
            {
                t = order[i];
                for (j = i - 1; j >= 0 && bc[order[j]] < bc[t]; j--) order[j + 1] = order[j];
                order[j + 1] = t;
            }
            for (i = 0; i < 255 && i < m; i++)
            {
                k = order[i];
                g_pal.rgb[g_pal.n * 3]     = (unsigned char)(br[k] / bc[k]);
                g_pal.rgb[g_pal.n * 3 + 1] = (unsigned char)(bg[k] / bc[k]);
                g_pal.rgb[g_pal.n * 3 + 2] = (unsigned char)(bb[k] / bc[k]);
                g_pal.n++;
            }
        }
        if (g_pal.n < 1) { gif_fail(SLI_E_BAD_PARAM, "palette empty"); return 0; }
        return 1;
    }
    if (used <= 255)
    {
        /* ---- 精确调色板：像素值即索引 ---- */
        int slot;
        for (slot = 0; slot < GIF_UNIQUE_SIZE; slot++)
        {
            unsigned int k = g_colors.rgb[slot];
            if (k)
            {
                g_pal.rgb[g_pal.n * 3]     = (unsigned char)((k >> 16) & 255);
                g_pal.rgb[g_pal.n * 3 + 1] = (unsigned char)((k >> 8) & 255);
                g_pal.rgb[g_pal.n * 3 + 2] = (unsigned char)(k & 255);
                g_pal.slot_index[slot] = g_pal.n;
                g_pal.n++;
            }
        }
        return 1;
    }
    /* ---- 中位切分 ---- */
    {
        SliGifItem* items = (SliGifItem*)malloc(sizeof(SliGifItem) * used);
        int slot, m = 0;
        if (!items) { gif_fail(SLI_E_BAD_PARAM, "median oom"); return 0; }
        for (slot = 0; slot < GIF_UNIQUE_SIZE; slot++)
        {
            unsigned int k = g_colors.rgb[slot];
            if (k)
            {
                items[m].rgb = k & 0xFFFFFFu;
                items[m].cnt = g_colors.cnt[slot];
                g_pal.slot_index[slot] = -1;  /* 待回填 */
                m++;
            }
        }
        if (!median_cut(items, m, 255))
        {
            free(items);
            gif_fail(SLI_E_BAD_PARAM, "median cut empty");
            return 0;
        }
        /* 每个唯一色 -> 最近调色板项；回填 slot_index */
        for (slot = 0; slot < GIF_UNIQUE_SIZE; slot++)
        {
            unsigned int k = g_colors.rgb[slot];
            if (k)
            {
                unsigned char rgb[3];
                rgb[0] = (unsigned char)((k >> 16) & 255);
                rgb[1] = (unsigned char)((k >> 8) & 255);
                rgb[2] = (unsigned char)(k & 255);
                g_pal.slot_index[slot] = pal_nearest(rgb, g_pal.n);
            }
        }
        free(items);
        return 1;
    }
}

/* 像素 -> 调色板索引（透明返回 g_pal.n；查哈希槽） */
static int pixel_index(unsigned int rgb24)
{
    unsigned int k = rgb24 | 0x1000000u;
    unsigned int key = GIF_UNIQUE_KEY(k) & (GIF_UNIQUE_SIZE - 1);
    for (;;)
    {
        if (g_colors.rgb[key] == 0) break;  /* 未登记（溢出退化路径） */
        if (g_colors.rgb[key] == k) return g_pal.slot_index[key];
        key = (key + 1) & (GIF_UNIQUE_SIZE - 1);
    }
    /* 退化路径 / 极端未命中：最近匹配 */
    {
        unsigned char rgb[3];
        rgb[0] = (unsigned char)((rgb24 >> 16) & 255);
        rgb[1] = (unsigned char)((rgb24 >> 8) & 255);
        rgb[2] = (unsigned char)(rgb24 & 255);
        return pal_nearest(rgb, g_pal.n);
    }
}

/* ================= 输出缓冲 ================= */
typedef struct SliGifOut
{
    unsigned char* buf;
    int64_t        len, cap;
} SliGifOut;

static SliGifOut g_out;
static int       g_out_failed;   /* out_reserve 失败置位（静默截断防线） */

static int out_reserve(int64_t extra)
{
    int64_t need = g_out.len + extra;
    if (need <= g_out.cap) return 1;
    while (g_out.cap < need) g_out.cap = g_out.cap ? g_out.cap * 2 : 4096;
    {
        unsigned char* p = (unsigned char*)realloc(g_out.buf, (size_t)g_out.cap);
        if (!p) { g_out_failed = 1; return 0; }
        g_out.buf = p;
    }
    return 1;
}

static void out_byte(int b)
{
    if (!out_reserve(1)) return;
    g_out.buf[g_out.len++] = (unsigned char)b;
}

static void out_raw(const void* p, int64_t n)
{
    if (n <= 0) return;
    if (!out_reserve(n)) return;
    memcpy(g_out.buf + g_out.len, p, (size_t)n);
    g_out.len += n;
}

static void out_le16(int v)
{
    out_byte(v & 255); out_byte((v >> 8) & 255);
}

/* ================= LZW 压缩 ================= */
/* 宽度对齐约定（与 stb 解码器逐码对齐验证过）：
 * 解码方读第 m 个数据码后添加第 (m+256) 号词条（首码不加），avail 超过
 * (1<<cs)-1 时升位；编码方在第 j 个数据码后插入第 (257+j) 号词条，
 * 因此 next_code 达到 (1<<code_size)+1 时升位 —— 两侧对同一码位换宽。 */
#define LZW_HT_BITS 13
#define LZW_HT_SIZE (1 << LZW_HT_BITS)   /* 8192 槽开放定址 */
#define LZW_MAX_CODE 4096                 /* 12 位码上限（词典满） */

typedef struct SliGifLzw
{
    unsigned int acc;        /* LSB 位累积器      */
    int          nbits;      /* acc 中有效位数    */
    unsigned char blk[256];  /* 当前子块         */
    int          blen;
    int          mcs;         /* 本帧最小码宽（2..8）            */
    int          code_size;
    int          next_code;
    int          clear_code, eoi_code;
    int*         hkey;       /* -1 = 空          */
    int*         hcode;
} SliGifLzw;

static int lzw_hash(int key)
{
    unsigned int k = (unsigned int)key * 2654435761u;
    return (int)(k >> (32 - LZW_HT_BITS));
}

static int lzw_lookup(SliGifLzw* z, int key)
{
    int i = lzw_hash(key);
    for (;;)
    {
        if (z->hkey[i] < 0) return -1;
        if (z->hkey[i] == key) return z->hcode[i];
        i = (i + 1) & (LZW_HT_SIZE - 1);
    }
}

static void lzw_emit(SliGifLzw* z, int code)
{
    z->acc |= ((unsigned int)code) << z->nbits;
    z->nbits += z->code_size;
    while (z->nbits >= 8)
    {
        if (z->blen >= 255)
        {
            out_byte(255); out_raw(z->blk, 255); z->blen = 0;
        }
        z->blk[z->blen++] = (unsigned char)(z->acc & 255);
        z->acc >>= 8;
        z->nbits -= 8;
    }
}

static void lzw_flush(SliGifLzw* z)
{
    if (z->nbits > 0)
    {
        if (z->blen >= 255) { out_byte(255); out_raw(z->blk, 255); z->blen = 0; }
        z->blk[z->blen++] = (unsigned char)(z->acc & 255);
        z->acc = 0; z->nbits = 0;
    }
    if (z->blen > 0) { out_byte(z->blen); out_raw(z->blk, z->blen); z->blen = 0; }
    out_byte(0);   /* 子块终止符 */
}

static void lzw_reset(SliGifLzw* z, int mcs)
{
    memset(z->hkey, -1, sizeof(int) * LZW_HT_SIZE);
    z->mcs = mcs;
    z->clear_code = 1 << mcs;
    z->eoi_code = z->clear_code + 1;
    z->next_code = z->eoi_code + 1;   /* = clear + 2        */
    z->code_size = mcs + 1;            /* 重置后码宽 = mcs+1 */
}

/* 插入新词条并处理升位（词条号 == (1<<cs) 时 next 达 (1<<cs)+1） */
static void lzw_insert(SliGifLzw* z, int key)
{
    int i = lzw_hash(key);
    while (z->hkey[i] >= 0) i = (i + 1) & (LZW_HT_SIZE - 1);
    z->hkey[i] = key;
    z->hcode[i] = z->next_code;
    z->next_code++;
    if (z->next_code == (1 << z->code_size) + 1 && z->code_size < 12)
        z->code_size++;
}

/* LZW 哈希表惰性分配（跨帧复用） */
static int lzw_halloc(SliGifLzw* z)
{
    if (z->hkey) return 1;
    z->hkey = (int*)malloc(sizeof(int) * LZW_HT_SIZE);
    z->hcode = (int*)malloc(sizeof(int) * LZW_HT_SIZE);
    if (!z->hkey || !z->hcode)
    {
        free(z->hkey); free(z->hcode);
        z->hkey = NULL; z->hcode = NULL;
        return 0;
    }
    return 1;
}

static SliGifLzw g_lzw;

/* 一帧索引流 -> 子块化 LZW 码流（clear 起，eoi 止）。
 * 满表（next_code==4096）时 miss 路径发 CLEAR 复位——stb 解码端词典满
 * 后仅写哨兵槽、码宽恒 12，clear 后回 mcs+1，两侧对齐。 */
static int lzw_write_frame(const int* idx, int64_t n, int mcs)
{
    SliGifLzw* z = &g_lzw;
    int64_t i;
    int prefix;
    z->acc = 0; z->nbits = 0; z->blen = 0;
    lzw_reset(z, mcs);
    lzw_emit(z, z->clear_code);        /* 帧首 clear（解码器同步重置） */
    prefix = idx[0];
    for (i = 1; i < n; i++)
    {
        int k = idx[i];
        int key = (prefix << 12) | k;
        int hit = lzw_lookup(z, key);
        if (hit >= 0) { prefix = hit; continue; }
        lzw_emit(z, prefix);           /* miss：发 prefix            */
        if (z->next_code < LZW_MAX_CODE)
            lzw_insert(z, key);        /* 插 (prefix,k)，按规则升位   */
        else
        {
            lzw_emit(z, z->clear_code);  /* 满表：延迟 clear 复位    */
            lzw_reset(z, mcs);
        }
        prefix = k;
    }
    lzw_emit(z, prefix);
    lzw_emit(z, z->eoi_code);
    lzw_flush(z);
    return g_out_failed ? 0 : 1;
}

/* ================= GIF89a 容器组装 ================= */
static int pow2_at_least(int v)   /* 不小于 v 的 2 的幂（>= 4，<= 256） */
{
    int p = 4;
    while (p < v && p < 256) p <<= 1;
    return p;
}

static int log2i(int v)           /* v 为 2 的幂（>= 4） */
{
    int n = 2;
    while ((1 << n) < v) n++;
    return n;
}

/* 输出失败统一清理（g_out 所有权回收） */
static unsigned char* gif_out_fail(void)
{
    free(g_out.buf);
    g_out.buf = NULL; g_out.len = 0; g_out.cap = 0;
    gif_fail(SLI_E_MEMORY, "output buffer oom");
    return NULL;
}

unsigned char* sli_gif_encode_animated(int w, int h, int frame_count,
                                        unsigned char** frame_pix,
                                        const int* delays_ms, int loop,
                                        int64_t* out_size)
{
    int has_transparent = 0, entries, padded, mcs, gct_bits, f, i;
    int64_t npix, fi;
    int* idx = NULL;
    unsigned char* result;

    if (out_size) *out_size = 0;
    if (!frame_pix || !delays_ms || w <= 0 || h <= 0 ||
        w > SLI_MAX_DIM || h > SLI_MAX_DIM ||
        frame_count <= 0 || frame_count > 100000)
    {
        gif_fail(SLI_E_BAD_PARAM, "bad encode params");
        return NULL;
    }
    if ((int64_t)w * h > SLI_MAX_PIXELS)
    {
        gif_fail(SLI_E_TOO_LARGE, "canvas too large");
        return NULL;
    }
    for (f = 0; f < frame_count; f++)
        if (!frame_pix[f])
        { gif_fail(SLI_E_BAD_PARAM, "null frame %d", f); return NULL; }

    g_out_failed = 0;
    g_out.len = 0;
    if (!lzw_halloc(&g_lzw))
    { gif_fail(SLI_E_MEMORY, "lzw table oom"); return NULL; }
    npix = (int64_t)w * h;
    idx = (int*)malloc(sizeof(int) * (size_t)npix);
    if (!idx) { gif_fail(SLI_E_MEMORY, "index buffer oom"); return NULL; }

    if (!palette_build(frame_pix, frame_count, w, h, &has_transparent))
    {
        free(idx);   /* 错误已在 palette_build 内 set */
        return NULL;
    }

    entries = g_pal.n + (has_transparent ? 1 : 0);
    padded = pow2_at_least(entries);
    mcs = log2i(padded);
    gct_bits = mcs - 1;

    /* ---- 头 / LSD / GCT ---- */
    out_raw("GIF89a", 6);
    out_le16(w); out_le16(h);
    out_byte(0x80 | 0x70 | gct_bits);   /* GCT 开，8 位色分辨率 */
    out_byte(0);                          /* 背景色索引 0         */
    out_byte(0);                          /* 像素宽高比 0         */
    for (i = 0; i < g_pal.n; i++)
    {
        out_byte(g_pal.rgb[i * 3]);
        out_byte(g_pal.rgb[i * 3 + 1]);
        out_byte(g_pal.rgb[i * 3 + 2]);
    }
    for (; i < padded; i++)               /* 透明槽 + 0 填充至 2 幂 */
        out_raw("\0\0\0", 3);

    /* ---- NETSCAPE2.0 循环扩展（loop != -1 时写） ---- */
    if (loop != -1)
    {
        static const char ns[] = "NETSCAPE2.0";
        out_byte(0x21); out_byte(0xFF); out_byte(0x0B);
        out_raw(ns, 11);
        out_byte(0x03); out_byte(0x01);
        out_le16(loop & 0xFFFF);
        out_byte(0x00);
    }

    /* ---- 每帧：GCE + 图像描述符 + LZW ---- */
    for (f = 0; f < frame_count; f++)
    {
        const unsigned char* p = frame_pix[f];
        /* 延迟四舍五入到厘秒，clamp [0, 65535] */
        int delay_cs = (delays_ms[f] + 5) / 10;
        /* 有透明 → disposal=2（restore to bg，stb 清透明）；全不透明 → 1 */
        int gce = has_transparent ? (0x08 | 0x01) : 0x04;
        if (delay_cs < 0) delay_cs = 0;
        if (delay_cs > 65535) delay_cs = 65535;

        for (fi = 0; fi < npix; fi++)
        {
            const unsigned char* q = p + fi * 4;
            if (q[3] < 128)
                idx[fi] = g_pal.n;       /* 透明索引（调色板尾部） */
            else
                idx[fi] = pixel_index(((unsigned int)q[0] << 16) |
                                      ((unsigned int)q[1] << 8) | q[2]);
        }

        out_byte(0x21); out_byte(0xF9); out_byte(0x04);   /* GCE     */
        out_byte(gce);
        out_le16(delay_cs);
        out_byte(g_pal.n);                                 /* 透明索引 */
        out_byte(0x00);

        out_byte(0x2C);                                    /* 描述符  */
        out_le16(0); out_le16(0);                          /* 整画布  */
        out_le16(w); out_le16(h);
        out_byte(0x00);                                    /* 无局表  */
        out_byte(mcs);
        if (!lzw_write_frame(idx, npix, mcs))
        { free(idx); return gif_out_fail(); }
    }
    out_byte(0x3B);                                        /* trailer */

    free(idx);
    if (g_out_failed || !g_out.buf || g_out.len <= 0)
        return gif_out_fail();
    if (out_size) *out_size = g_out.len;
    result = g_out.buf;          /* 所有权移交调用方（free 释放） */
    g_out.buf = NULL; g_out.len = 0; g_out.cap = 0;
    return result;
}







