/* =========================================================================
 * sl_audio_mp4.c —— Codec：minimp4 唯一 IMPLEMENTATION 编译点 + 音轨解码
 *
 * minimp4（CC0 公有领域，third_party/minimp4/ 整文件内置）。本单元是
 * minimp4.h 的唯一 #define MINIMP4_IMPLEMENTATION 编译点。
 *
 * 音轨选择：handler_type == 'soun' 的第一条轨道。按编码分派：
 *   - sample_entry 'sowt' / 'lpcm'（MP4E e_audio_pcm 产物）→ PCM S16 直读
 *   - object_type_indication 0x69/0x6B（MPEG-1/2 Audio Layer III）
 *       → 每帧经 sla_mp3_stream_*（sl_audio_mp3.c 的唯一 minimp3 实现）
 *   - object_type_indication 0x40/0x66-0x68（MPEG-4 Audio = AAC）
 *       → 每帧喂 Media Foundation AAC MFT（raw 模式，ASC = track->dsi）
 * ========================================================================= */
#define MINIMP4_IMPLEMENTATION
/* MSVC：minimp4 内部 strdup 为 POSIX 名（SDL 检查下 C4996 升级为错误），
 * 本翻译单元用 ISO 等价 _strdup 替换 */
#define strdup _strdup
#include "../third_party/minimp4/minimp4.h"

#include "../sl_audio_internal.h"

#define MP4_OTI_AAC_MPEG4   0x40
#define MP4_OTI_AAC_MAIN    0x66
#define MP4_OTI_AAC_LC      0x67
#define MP4_OTI_AAC_SSR     0x68
#define MP4_OTI_MP3_MPEG1L3 0x69
#define MP4_OTI_MP3_MPEG2L3 0x6B

/* 单帧读出缓冲（AAC/MP3 帧最大 ~2.4KB；PCM 轨走直读不经此缓冲） */
#define SLA_MP4_FBUF  16384

int sla_mp4_is_mp4(const unsigned char* p, int64_t size)
{
    if (!p || size < 12) return 0;
    /* ftyp @ offset 4（box size @0..3） */
    if (p[4] == 'f' && p[5] == 't' && p[6] == 'y' && p[7] == 'p') return 1;
    return 0;
}

/* 读回调：内存块视作文件 */
typedef struct { const unsigned char* base; } MemFile;
static int mem_read(int64_t offset, void* buffer, size_t size, void* token)
{
    MemFile* mf = (MemFile*)token;
    memcpy(buffer, mf->base + offset, size);
    return 0;
}

static int pick_audio_track(const MP4D_demux_t* mp4, int* track_idx)
{
    unsigned i;
    for (i = 0; i < mp4->track_count; i++)
    {
        if (mp4->track[i].handler_type == MP4D_HANDLER_TYPE_SOUN)
        {
            *track_idx = (int)i;
            return 1;
        }
    }
    return 0;
}

static int oti_is_aac(unsigned oti)
{
    return oti == MP4_OTI_AAC_MPEG4 || oti == MP4_OTI_AAC_MAIN ||
           oti == MP4_OTI_AAC_LC   || oti == MP4_OTI_AAC_SSR;
}
static int oti_is_mp3(unsigned oti)
{
    return oti == MP4_OTI_MP3_MPEG1L3 || oti == MP4_OTI_MP3_MPEG2L3;
}
static int entry_is_pcm(unsigned sample_entry)
{
    return sample_entry == 0x736f7774u /* 'sowt'（MP4E e_audio_pcm） */ ||
           sample_entry == 0x6c70636du; /* 'lpcm'                       */
}

/* ---- stsd 音频 entry 自扫描（MP4D 只认 'mp4a'；'sowt'/'lpcm' 无 OTI，
 *      sr/ch/entry 全缺 -> 逐 trak 找 stsd 第一个 entry 自行解析） ---- */
typedef struct
{
    unsigned entry;     /* entry 四字符（0=无）                    */
    int      ch, sr, bits;
} SlaTrakSd;

static int64_t box_size(const unsigned char* p, int64_t left)
{
    int64_t sz = (int64_t)((uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 |
                           (uint32_t)p[2] << 8 | (uint32_t)p[3]);
    if (sz == 1 && left >= 16)
        sz = (int64_t)((uint64_t)p[8] << 56 | (uint64_t)p[9] << 48 |
                       (uint64_t)p[10] << 40 | (uint64_t)p[11] << 32 |
                       (uint64_t)p[12] << 24 | (uint64_t)p[13] << 16 |
                       (uint64_t)p[14] << 8 | (uint64_t)p[15]);
    return sz;                                  /* 0 = 到容器尾           */
}

/* SoundSampleEntry payload（type 偏移 4 后）解析 ch/sr/bits */
static void parse_sound_entry(const unsigned char* q, unsigned type, int* ch, int* sr, int* bits)
{
    if (type == 0x736f7774u || type == 0x6c70636du)
    {
        /* QuickTime v1：ch @+16 bits @+18 sr16.16 @+24               */
        *ch   = (q[16] << 8) | q[17];
        *bits = (q[18] << 8) | q[19];
        *sr   = (int)(((uint32_t)q[24] << 24 | (uint32_t)q[25] << 16 |
                       (uint32_t)q[26] << 8 | (uint32_t)q[27]) >> 16);
    }
    else if (type == 0x6d703461u) /* 'mp4a' v0：ch @+8 bits @+10 sr @+16 */
    {
        *ch   = (q[8]  << 8) | q[9];
        *bits = (q[10] << 8) | q[11];
        *sr   = (int)(((uint32_t)q[16] << 24 | (uint32_t)q[17] << 16 |
                       (uint32_t)q[18] << 8 | (uint32_t)q[19]) >> 16);
    }
}

/* 在容器 [start, end) 内找 fourcc 直接子 box；命中返回其起始偏移并写
 * 其尺寸（0=未找到）。box_size==0 表示"到容器尾"（仅顶层允许）。      */
static int64_t find_child(const unsigned char* p, int64_t start, int64_t end,
                          const char* fourcc, int64_t* out_size)
{
    int64_t pos = start;
    while (pos + 8 <= end)
    {
        int64_t sz = box_size(p + pos, end - pos);
        if (sz < 8) break;
        if (memcmp(p + pos + 4, fourcc, 4) == 0)
        {
            *out_size = (sz == 0 ? end - pos : sz);
            return pos;
        }
        if (sz == 0) break;
        pos += sz;
    }
    return -1;
}

/* 遍历 moov 下 trak*，各trak 经 mdia/minf/stbl 下钻取 stsd 第一个 entry
 *（stsd 是 stbl 的子 box，不在 trak 直接子级）                        */
static int scan_trak_stsd(const unsigned char* p, int64_t size,
                          SlaTrakSd* out, int max_traks)
{
    int64_t moov_sz = 0, moov, moov_end, q;
    int ntrak = 0;

    moov = find_child(p, 0, size, "moov", &moov_sz);
    if (moov < 0) return 0;
    moov_end = moov + moov_sz;

    q = moov + 8;
    while (q + 8 <= moov_end && ntrak < max_traks)
    {
        int64_t trak_sz = 0, mdia_sz = 0, minf_sz = 0, stbl_sz = 0, stsd_sz = 0;
        int64_t trak, mdia, minf, stbl, stsd;
        trak = find_child(p, q, moov_end, "trak", &trak_sz);
        if (trak < 0) break;
        if ((mdia = find_child(p, trak + 8, trak + trak_sz, "mdia", &mdia_sz)) >= 0 &&
            (minf = find_child(p, mdia + 8, mdia + mdia_sz, "minf", &minf_sz)) >= 0 &&
            (stbl = find_child(p, minf + 8, minf + minf_sz, "stbl", &stbl_sz)) >= 0 &&
            (stsd = find_child(p, stbl + 8, stbl + stbl_sz, "stsd", &stsd_sz)) >= 0)
        {
            /* stsd: ver/flags(4) count(4) -> entry box                 */
            int64_t e = stsd + 8 + 8;
            if (e + 8 <= stsd + stsd_sz)
            {
                unsigned type = (unsigned)p[e+4] << 24 | (unsigned)p[e+5] << 16 |
                                (unsigned)p[e+6] << 8 | (unsigned)p[e+7];
                out[ntrak].entry = type;
                out[ntrak].ch = 0; out[ntrak].sr = 0; out[ntrak].bits = 0;
                if (e + 28 <= stsd + stsd_sz)
                    parse_sound_entry(p + e + 8, type, &out[ntrak].ch,
                                      &out[ntrak].sr, &out[ntrak].bits);
                ntrak++;
            }
        }
        if (trak_sz <= 0) break;
        q = trak + trak_sz;
    }
    return ntrak;
}

/* ---------- probe ---------- */
int sla_mp4_probe(const unsigned char* p, int64_t size,
                   int* sr, int* ch, int* bits, int64_t* frames, int* src_fmt)
{
    MP4D_demux_t mp4;
    MemFile mf;
    int ti = -1;
    unsigned n;
    unsigned track_ota, track_entry;
    SlaTrakSd sd[16];

    if (!sla_mp4_is_mp4(p, size))
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: not ftyp");
        return 0;
    }
    memset(sd, 0, sizeof(sd));
    scan_trak_stsd(p, size, sd, 16);           /* 自扫描 entry（sowt 兜底）*/
    mf.base = p;
    if (MP4D_open(&mp4, mem_read, &mf, size) != 1)
    {
        sla_set_error_detail(SLA_E_DECODE, "mp4: MP4D_open");
        return 0;
    }
    if (!pick_audio_track(&mp4, &ti))
    {
        MP4D_close(&mp4);
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: no 'soun' track");
        return 0;
    }
    *sr = (int)mp4.track[ti].SampleDescription.audio.samplerate_hz;
    *ch = (int)mp4.track[ti].SampleDescription.audio.channelcount;
    track_ota = mp4.track[ti].object_type_indication;
    track_entry = mp4.track[ti].sample_entry ? mp4.track[ti].sample_entry
                : (ti < 16 ? sd[ti].entry : 0);
    /* sowt/lpcm：MP4D 不解析 entry -> 用自扫描结果补 sr/ch          */
    if (entry_is_pcm(track_entry) && ti < 16 && sd[ti].sr > 0 && sd[ti].ch > 0)
    {
        *sr = sd[ti].sr;
        *ch = sd[ti].ch;
    }
    n = mp4.track[ti].sample_count;

    if (entry_is_pcm(track_entry))
    {
        /* sowt：1 sample = 一块 PCM（多帧）-> 按字节精确累计        */
        int64_t total_bytes = 0;
        unsigned ns;
        for (ns = 0; ns < n; ns++)
        {
            unsigned fb = 0, dts = 0, pts = 0, dur = 0;
            int sync = 0;
            int64_t off = MP4D_frame_offset(&mp4, (unsigned)ti, ns,
                                            &fb, &dts, &pts, &dur, &sync);
            if (off < 0) break;
            total_bytes += fb;
        }
        *bits = 16;
        *frames = total_bytes / ((int64_t)2 * *ch);
        *src_fmt = SLA_FMT_MP4_PCM;
    }
    else if (oti_is_mp3(track_ota))
    {
        *bits = 16;
        *frames = (int64_t)n * 1152;           /* 1152/576，近似            */
        *src_fmt = SLA_FMT_MP4_MP3;
    }
    else if (oti_is_aac(track_ota))
    {
        *bits = 16;
        *frames = (int64_t)n * 1024;           /* AAC-LC 每帧 1024          */
        *src_fmt = SLA_FMT_MP4_AAC;
    }
    else
    {
        MP4D_close(&mp4);
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: oti=0x%02x entry=%08x",
                             track_ota, track_entry);
        return 0;
    }
    if (*sr <= 0 || *sr > SLA_MAX_SR || *ch <= 0 || *ch > SLA_MAX_CH)
    {
        MP4D_close(&mp4);
        sla_set_error_detail(SLA_E_DECODE, "mp4: sr=%d ch=%d", *sr, *ch);
        return 0;
    }
    MP4D_close(&mp4);
    return 1;
}

/* ---------- 整段解码 ---------- */

typedef struct
{
    short* data;
    int64_t len;      /* 采样数（含声道交织）*/
    int64_t cap;
} PcmAcc;

static int acc_append(PcmAcc* a, const void* src, int64_t samples)
{
    if (samples <= 0) return 1;
    if (a->len + samples > a->cap)
    {
        int64_t new_cap = (a->len + samples) * 2 + 65536;
        short* np = (short*)realloc(a->data, (size_t)new_cap * sizeof(short));
        if (!np) { sla_set_error(SLA_E_MEMORY); return 0; }
        a->data = np;
        a->cap = new_cap;
    }
    memcpy(a->data + a->len, src, (size_t)samples * sizeof(short));
    a->len += samples;
    return 1;
}

/* 取一帧样值（大小/越界校验后返回字节长度；0=取不到） */
static int fetch_sample(const unsigned char* base, int64_t size,
                        MP4D_demux_t* mp4, int ti, unsigned ns,
                        unsigned char* dst, int64_t cap)
{
    unsigned frame_bytes = 0, dts = 0, pts = 0, dur = 0;
    int sync = 0;
    int64_t off;
    if (ns >= mp4->track[ti].sample_count) return 0;
    off = MP4D_frame_offset(mp4, (unsigned)ti, ns, &frame_bytes, &dts, &pts, &dur, &sync);
    if (off < 0 || frame_bytes == 0) return 0;
    if (off + frame_bytes > size) return 0;
    if (frame_bytes > (unsigned)cap) return 0;
    memcpy(dst, base + off, frame_bytes);
    return (int)frame_bytes;
}

int64_t sla_mp4_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, int* src_fmt, short** out_pcm)
{
    MP4D_demux_t mp4;
    MemFile mf;
    int ti = -1;
    PcmAcc acc;
    unsigned n, ns;
    unsigned char* fbuf = NULL;
    void* mp3st = NULL;
    void* mft = NULL;
    unsigned oti, track_entry;
    SlaTrakSd sd[16];
    int ok = 0;

    memset(&acc, 0, sizeof(acc));
    memset(sd, 0, sizeof(sd));
    if (!sla_mp4_is_mp4(p, size))
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: not ftyp");
        return -1;
    }
    scan_trak_stsd(p, size, sd, 16);
    mf.base = p;
    if (MP4D_open(&mp4, mem_read, &mf, size) != 1)
    {
        sla_set_error_detail(SLA_E_DECODE, "mp4: MP4D_open");
        return -1;
    }
    if (!pick_audio_track(&mp4, &ti))
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: no 'soun' track");
        goto fail;
    }
    *sr = (int)mp4.track[ti].SampleDescription.audio.samplerate_hz;
    *ch = (int)mp4.track[ti].SampleDescription.audio.channelcount;
    oti = mp4.track[ti].object_type_indication;
    track_entry = mp4.track[ti].sample_entry ? mp4.track[ti].sample_entry
                : (ti < 16 ? sd[ti].entry : 0);
    if (entry_is_pcm(track_entry) && ti < 16 && sd[ti].sr > 0 && sd[ti].ch > 0)
    {
        *sr = sd[ti].sr;                        /* sowt/lpcm 的 MP4D 缺参补全 */
        *ch = sd[ti].ch;
    }
    n = mp4.track[ti].sample_count;

    if (*sr <= 0 || *sr > SLA_MAX_SR || *ch <= 0 || *ch > SLA_MAX_CH || n == 0)
    {
        sla_set_error_detail(SLA_E_DECODE, "mp4: sr=%d ch=%d n=%u", *sr, *ch, n);
        goto fail;
    }

    /* ---- 分支 1：PCM 音轨（sowt/lpcm，S16LE 直读 mdat，不经帧缓冲） ---- */
    if (entry_is_pcm(track_entry))
    {
        *src_fmt = SLA_FMT_MP4_PCM;
        for (ns = 0; ns < n; ns++)
        {
            unsigned frame_bytes = 0, dts = 0, pts = 0, dur = 0;
            int sync = 0;
            int64_t off;
            if (ns >= mp4.track[ti].sample_count) break;
            off = MP4D_frame_offset(&mp4, (unsigned)ti, ns,
                                    &frame_bytes, &dts, &pts, &dur, &sync);
            if (off < 0 || frame_bytes == 0) break;
            if (off + frame_bytes > size) break;
            if (acc.len + frame_bytes / 2 > SLA_MAX_FRAMES * (int64_t)*ch) break;
            if (!acc_append(&acc, p + off, frame_bytes / 2)) goto fail;
        }
        if (acc.len == 0)
        {
            sla_set_error_detail(SLA_E_DECODE, "mp4-pcm: no data");
            goto fail;
        }
    }
    /* ---- 分支 2：MP3 音轨（帧喂 minimp3 流实例，收集全部产出） ---- */
    else if (oti_is_mp3(oti))
    {
        int msr = 0, mch = 0, mfmt = 0;
        short tmp[2304];   /* >= 1152 帧 x 2ch                        */
        *src_fmt = SLA_FMT_MP4_MP3;
        fbuf = (unsigned char*)malloc(SLA_MP4_FBUF);
        if (!fbuf) { sla_set_error(SLA_E_MEMORY); goto fail; }
        mp3st = sla_mp3_stream_new();
        if (!mp3st) { sla_set_error(SLA_E_MEMORY); goto fail; }
        for (ns = 0; ns < n; ns++)
        {
            int got = fetch_sample(p, size, &mp4, ti, ns, fbuf, SLA_MP4_FBUF);
            int64_t produced;
            if (got <= 0) break;
            if (sla_mp3_stream_feed(&mp3st, fbuf, got) == 0) continue;
            for (;;)
            {
                produced = sla_mp3_stream_read(mp3st, tmp, 1152, &msr, &mch, &mfmt);
                if (produced <= 0) break;
                if (msr > 0 && mch > 0) { *sr = msr; *ch = mch; }
                if (!acc_append(&acc, tmp, produced * (mch > 0 ? mch : *ch))) goto fail;
            }
        }
        if (acc.len == 0)
        {
            sla_set_error_detail(SLA_E_DECODE, "mp4-mp3: no pcm");
            goto fail;
        }
    }
    /* ---- 分支 3：AAC 音轨（帧喂 MF MFT，raw 模式 + dsi 作 ASC） ---- */
    else if (oti_is_aac(oti))
    {
        *src_fmt = SLA_FMT_MP4_AAC;
        fbuf = (unsigned char*)malloc(SLA_MP4_FBUF);
        if (!fbuf) { sla_set_error(SLA_E_MEMORY); goto fail; }
        mft = sla_mf_aac_open(*sr, *ch,
                              (const unsigned char*)mp4.track[ti].dsi,
                              (int)mp4.track[ti].dsi_bytes, 0);
        if (!mft) goto fail;                    /* 错误已设（mf-aac: ...）*/
        for (ns = 0; ns < n; ns++)
        {
            int got = fetch_sample(p, size, &mp4, ti, ns, fbuf, SLA_MP4_FBUF);
            int64_t take;
            if (got <= 0) break;
            if (!sla_mf_aac_push(mft, fbuf, got)) goto fail;
            for (;;)
            {
                take = sla_mf_aac_take(mft, (short*)fbuf, SLA_MP4_FBUF / 2 / *ch);
                if (take <= 0) break;
                if (!acc_append(&acc, fbuf, take * *ch)) goto fail;
            }
        }
        sla_mf_aac_drain(mft);
        for (;;)
        {
            int64_t take = sla_mf_aac_take(mft, (short*)fbuf, SLA_MP4_FBUF / 2 / *ch);
            if (take <= 0) break;
            if (!acc_append(&acc, fbuf, take * *ch)) goto fail;
        }
        if (acc.len == 0)
        {
            sla_set_error_detail(SLA_E_DECODE, "mp4-aac: no pcm");
            goto fail;
        }
    }
    else
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mp4: oti=0x%02x", oti);
        goto fail;
    }

    free(fbuf);
    if (mp3st) sla_mp3_stream_free(mp3st);
    if (mft) sla_mf_aac_close(mft);
    MP4D_close(&mp4);
    *out_pcm = acc.data;
    ok = 1;
    return acc.len / *ch;

fail:
    free(fbuf);
    if (mp3st) sla_mp3_stream_free(mp3st);
    if (mft) sla_mf_aac_close(mft);
    free(acc.data);
    MP4D_close(&mp4);
    (void)ok;
    return -1;
}
