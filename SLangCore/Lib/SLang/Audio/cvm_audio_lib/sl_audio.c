/* =========================================================================
 * sl_audio.c —— 生命周期 / 诊断 / 槽表 / 嗅探 / 解码分派 / 流式 / 播放调度
 *
 * 对应 SL 侧 AudioFfi.sl（@DllStaticImport 静态绑定，sl_audio_lib 注册名）。
 * 解码本体：
 *   wav   Codec/sl_audio_wav.c   （内建 RIFF/PCM）
 *   mp3   Codec/sl_audio_mp3.c   （minimp3，CC0）
 *   mp4   Codec/sl_audio_mp4.c   （minimp4，CC0；AAC 经 mf）
 *   mf    Codec/sl_audio_mf.c    （Media Foundation AAC MFT，系统组件）
 *   wave  Codec/sl_audio_wave.c  （waveOut，系统 winmm）
 * 分派策略：嗅探（RIFF/ID3/MPEG 同步字/ftyp）→ wav / mp3 / mp4 / aac-adts；
 *           裸 PCM 家族须 fmt_hint 显式指定位深。
 * ========================================================================= */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>

#include "sl_audio_internal.h"

#if defined(_WIN32)
#include <windows.h>
#endif

/* ================= 内部状态 ================= */

static int s_ready = 0;
static int s_last_error = SLA_OK;
static char s_detail[256];

/* ---- 整段解码槽 ---- */
typedef struct
{
    int used;
    int sr, ch, src_fmt;
    int64_t frames;
    short* pcm;                 /* interleaved S16（帧*ch）        */
} SlaDec;
static SlaDec s_decs[SLA_MAX_DEC];

/* ---- 流式槽 ---- */
typedef struct
{
    int used;
    int fmt_hint, sr_hint, ch_hint;
    int fmt, sr, ch;            /* fmt 定型后 >0                   */
    int64_t frames_out;

    /* 通用线性缓冲（嗅探/wav 头/adts 帧装配/pcm 直通）           */
    unsigned char* buf;
    int len, cap;
    int64_t data_start;         /* wav：data 块数据起点（相对 buf）*/
    int wav_done;               /* wav 头已解析                    */

    void* mp3;                  /* minimp3 流实例                  */
    void* mft;                  /* MF AAC（adts 模式）             */
} SlaStream;
static SlaStream s_streams[SLA_MAX_STREAM];

/* ---- 播放槽 ---- */
typedef struct
{
    int used;
    SlaWaveOut* wave;
} SlaPlayer;
static SlaPlayer s_players[SLA_MAX_PLAYER];

/* ================= 诊断 ================= */

void sla_set_error(int err)
{
    s_last_error = err;
    s_detail[0] = '\0';
}

void sla_set_error_detail(int err, const char* fmt, ...)
{
    va_list ap;
    s_last_error = err;
    va_start(ap, fmt);
    vsnprintf(s_detail, sizeof(s_detail), fmt, ap);
    va_end(ap);
}

int sla_last_error_is_set(void)
{
    return s_last_error != SLA_OK;
}

int sla_last_error(void)
{
    return s_last_error;
}

const char* sla_error_string(int err)
{
    switch (err)
    {
    case SLA_OK:                return "ok";
    case SLA_E_NOT_INITIALIZED: return "not initialized";
    case SLA_E_BAD_PARAM:       return "bad parameter";
    case SLA_E_BAD_HANDLE:      return "bad handle";
    case SLA_E_MEMORY:          return "out of memory";
    case SLA_E_LIMIT:           return "handle slots exhausted";
    case SLA_E_UNSUPPORTED:     return "unsupported format";
    case SLA_E_DECODE:          return "decode failed";
    case SLA_E_IO:              return "file io failed";
    case SLA_E_NO_DEVICE:       return "no audio output device";
    case SLA_E_NO_DATA:         return "stream needs more data";
    default:                    return "unknown error";
    }
}

const char* sla_error_detail(void)
{
    return s_detail[0] ? s_detail : sla_error_string(s_last_error);
}

/* ================= 生命周期 ================= */

int sla_init(void)
{
    if (s_ready) return 1;
    memset(s_decs, 0, sizeof(s_decs));
    memset(s_streams, 0, sizeof(s_streams));
    memset(s_players, 0, sizeof(s_players));
    s_ready = 1;
    sla_set_error(SLA_OK);
    return 1;
}

int sla_uninit(void)
{
    int i;
    if (!s_ready) return 1;
    for (i = 0; i < SLA_MAX_DEC; i++)
    {
        if (s_decs[i].used)
        {
            free(s_decs[i].pcm);
            memset(&s_decs[i], 0, sizeof(SlaDec));
        }
    }
    for (i = 0; i < SLA_MAX_STREAM; i++)
    {
        if (s_streams[i].used)
        {
            free(s_streams[i].buf);
            if (s_streams[i].mp3) sla_mp3_stream_free(s_streams[i].mp3);
            if (s_streams[i].mft) sla_mf_aac_close(s_streams[i].mft);
            memset(&s_streams[i], 0, sizeof(SlaStream));
        }
    }
    for (i = 0; i < SLA_MAX_PLAYER; i++)
    {
        if (s_players[i].used)
        {
            sla_wave_close(s_players[i].wave);
            memset(&s_players[i], 0, sizeof(SlaPlayer));
        }
    }
    s_ready = 0;
    return 1;
}

const char* sla_version_string(void)
{
    return "sl_audio_lib 1.0 (minimp4 + minimp3 CC0; MF AAC; waveOut)";
}

const char* sla_backend_list(void)
{
    return "wav,pcm,mp3,mp4,mf-aac,wave";
}

/* ================= 嗅探 / ADTS 工具 ================= */

static int sniff_fmt(const unsigned char* p, int64_t size)
{
    if (!p || size < 12) return SLA_FMT_UNKNOWN;
    if (sla_wav_is_wav(p, size)) return SLA_FMT_WAV;
    if (sla_mp4_is_mp4(p, size)) return SLA_FMT_MP4;
    if (sla_mp3_is_mp3(p, size))
    {
        /* FF Fx 且 layer==0 → AAC ADTS（FF F1/F9 常见）；其余 MPEG 帧 → MP3 */
        if ((p[1] & 0x06) == 0x00) return SLA_FMT_AAC_ADTS;
        return SLA_FMT_MP3;
    }
    return SLA_FMT_UNKNOWN;
}

/* ADTS 7 字节头：返回帧长（含头）；0=头无效/不足 */
static int adts_frame_len(const unsigned char* p, int len,
                           int* sr, int* ch, int* profile)
{
    static const int aac_sr_tab[13] =
        { 96000, 88200, 64000, 48000, 44100, 32000, 24000,
          22050, 16000, 12000, 11025, 8000, 7350 };
    int sr_idx, ch_cfg, framelen;
    if (len < 7) return 0;
    if (p[0] != 0xFF || (p[1] & 0xF0) != 0xF0) return 0;
    /* protection_absent(p[1]&1)：1=无 CRC（常见）；0=有 CRC（头 9 字节），
     * 两种均合法帧，帧长解析不受影响，整帧透传给 MFT                    */
    *profile = ((p[2] >> 6) & 0x03) + 1;        /* profile = objectType-1     */
    sr_idx = (p[2] >> 2) & 0x0F;
    ch_cfg = ((p[2] & 0x01) << 2) | ((p[3] >> 6) & 0x03);
    if (sr_idx >= 13 || ch_cfg == 0 || ch_cfg > 6)
    {
        *sr = 0; *ch = 0;
        return 0;
    }
    *sr = aac_sr_tab[sr_idx];
    *ch = (ch_cfg == 7) ? 8 : ch_cfg;
    framelen = ((p[3] & 0x03) << 11) | (p[4] << 3) | (p[5] >> 5);
    if (framelen < 7) return 0;
    return framelen;
}

/* ================= 文件读取（UTF-8 -> UTF-16） ================= */

static unsigned char* read_file_utf8(const char* path_utf8, int64_t* out_size)
{
#if defined(_WIN32)
    wchar_t wpath[1024];
    FILE* f = NULL;
    long fsize;
    unsigned char* data;
    if (!MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath,
                             (int)(sizeof(wpath) / sizeof(wchar_t)) - 1))
    {
        sla_set_error_detail(SLA_E_BAD_PARAM, "path convert failed");
        return NULL;
    }
    if (_wfopen_s(&f, wpath, L"rb") != 0 || !f)
    {
        sla_set_error_detail(SLA_E_IO, "fopen failed");
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); sla_set_error(SLA_E_IO); return NULL; }
    fsize = ftell(f);
    if (fsize <= 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); sla_set_error(SLA_E_IO); return NULL; }
    data = (unsigned char*)malloc((size_t)fsize);
    if (!data) { fclose(f); sla_set_error(SLA_E_MEMORY); return NULL; }
    if (fread(data, 1, (size_t)fsize, f) != (size_t)fsize)
    {
        free(data);
        fclose(f);
        sla_set_error(SLA_E_IO);
        return NULL;
    }
    fclose(f);
    *out_size = fsize;
    return data;
#elif defined(__EMSCRIPTEN__)
    /* wasm：MEMFS 直读（宿主经 FS.writeFile 注入的 UTF-8 路径原样可用）*/
    FILE* f = NULL;
    long fsize;
    unsigned char* data;
    if (!path_utf8 || !path_utf8[0] || !out_size)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return NULL;
    }
    f = fopen(path_utf8, "rb");
    if (!f)
    {
        sla_set_error(SLA_E_IO);
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); sla_set_error(SLA_E_IO); return NULL; }
    fsize = ftell(f);
    if (fsize <= 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); sla_set_error(SLA_E_IO); return NULL; }
    data = (unsigned char*)malloc((size_t)fsize);
    if (!data) { fclose(f); sla_set_error(SLA_E_MEMORY); return NULL; }
    if (fread(data, 1, (size_t)fsize, f) != (size_t)fsize)
    {
        free(data);
        fclose(f);
        sla_set_error(SLA_E_IO);
        return NULL;
    }
    fclose(f);
    *out_size = fsize;
    return data;
#else
    (void)path_utf8; (void)out_size;
    sla_set_error(SLA_E_UNSUPPORTED);
    return NULL;
#endif
}

/* ================= 探测 ================= */

static void probe_out_fill(int64_t out_ptr, int fmt, int sr, int ch,
                           int bits, int64_t frames)
{
    int32_t* o = (int32_t*)(intptr_t)out_ptr;
    o[0] = fmt;
    o[1] = sr;
    o[2] = ch;
    o[3] = bits;
    o[4] = (int32_t)(frames & 0xFFFFFFFFu);
    o[5] = (int32_t)((uint64_t)frames >> 32);
}

static int probe_bytes(const unsigned char* p, int64_t size, int64_t out_ptr)
{
    int fmt = sniff_fmt(p, size);
    int sr = 0, ch = 0, bits = 0, is_float = 0;
    int64_t frames = 0, off = 0, dsize = 0;

    if (fmt == SLA_FMT_WAV)
    {
        if (sla_wav_parse_header(p, size, &sr, &ch, &bits, &is_float, &off, &dsize) == 1)
        {
            frames = dsize / ((int64_t)(bits / 8) * ch);
            probe_out_fill(out_ptr, SLA_FMT_WAV, sr, ch, bits, frames);
            return 1;
        }
        probe_out_fill(out_ptr, SLA_FMT_WAV, 0, 0, 0, 0);
        sla_set_error_detail(SLA_E_DECODE, "wav header");
        return 0;
    }
    if (fmt == SLA_FMT_MP4)
    {
        int src_fmt = 0;
        if (sla_mp4_probe(p, size, &sr, &ch, &bits, &frames, &src_fmt) == 1)
        {
            probe_out_fill(out_ptr, src_fmt, sr, ch, bits, frames);
            return 1;
        }
        probe_out_fill(out_ptr, SLA_FMT_MP4, 0, 0, 0, 0);
        return 0;
    }
    if (fmt == SLA_FMT_MP3)
    {
        /* MP3：sr/ch 需解帧才能确定，probe 只报格式位（0=待定）       */
        probe_out_fill(out_ptr, SLA_FMT_MP3, 0, 0, 0, 0);
        return 1;
    }
    if (fmt == SLA_FMT_AAC_ADTS)
    {
        int profile = 0, flen;
        flen = adts_frame_len(p, (int)(size < 64 ? size : 64), &sr, &ch, &profile);
        if (flen > 0 && sr > 0 && ch > 0)
        {
            probe_out_fill(out_ptr, SLA_FMT_AAC_ADTS, sr, ch, 16, 0);
            return 1;
        }
        probe_out_fill(out_ptr, SLA_FMT_AAC_ADTS, 0, 0, 0, 0);
        sla_set_error_detail(SLA_E_DECODE, "adts: bad header");
        return 0;
    }
    probe_out_fill(out_ptr, SLA_FMT_UNKNOWN, 0, 0, 0, 0);
    sla_set_error_detail(SLA_E_UNSUPPORTED, "probe: unknown format");
    return 0;
}

int sla_probe_file(const char* path_utf8, int64_t out_ptr)
{
    int64_t size = 0, rd = 0;
    unsigned char* data;
    sla_set_error(SLA_OK);                        /* 粘性：入口清零       */
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    if (!path_utf8 || !out_ptr) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    data = read_file_utf8(path_utf8, &size);
    if (!data) return 0;
    rd = probe_bytes(data, size, out_ptr);
    free(data);
    return (int)rd;
}

int sla_probe_mem(int64_t data_ptr, int64_t size, int64_t out_ptr)
{
    sla_set_error(SLA_OK);
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    if (data_ptr == 0 || size <= 0 || !out_ptr) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    return probe_bytes((const unsigned char*)(intptr_t)data_ptr, size, out_ptr);
}

/* ================= 整段解码 ================= */

/* 整段 ADTS -> PCM（帧扫描 + MF adts 模式） */
static int64_t decode_adts_all(const unsigned char* p, int64_t size,
                               int* sr, int* ch, short** out_pcm)
{
    int64_t pos = 0;
    void* mft = NULL;
    int got_meta = 0;
    typedef struct { short* data; int64_t len, cap; int ch; } Acc;
    Acc acc;
    memset(&acc, 0, sizeof(acc));

    while (pos < size)
    {
        int profile = 0, flen;
        int isr = 0, ich = 0;
        if (pos + 7 > size) break;
        flen = adts_frame_len(p + pos, (int)(size - pos), &isr, &ich, &profile);
        if (flen == 0)
        {
            pos++;                                  /* 找同步                */
            continue;
        }
        if (pos + flen > size) break;
        if (!mft && isr > 0 && ich > 0)
        {
            mft = sla_mf_aac_open(isr, ich, NULL, 0, 1 /* adts */);
            if (!mft)
            {
                free(acc.data);
                return -1;                          /* 错误已设             */
            }
            *sr = isr; *ch = ich; acc.ch = ich;
            got_meta = 1;
        }
        if (mft && !sla_mf_aac_push(mft, p + pos, flen))
        {
            pos += flen;
            continue;
        }
        pos += flen;
    }
    if (mft)
    {
        short tmp[8192];
        sla_mf_aac_drain(mft);
        for (;;)
        {
            int64_t take = sla_mf_aac_take(mft, tmp, 8192 / (got_meta ? *ch : 1));
            if (take <= 0) break;
            if (acc.len + take * acc.ch > acc.cap)
            {
                int64_t new_cap = (acc.len + take * acc.ch) * 2 + 8192;
                short* np = (short*)realloc(acc.data, (size_t)new_cap * sizeof(short));
                if (!np) { free(acc.data); sla_mf_aac_close(mft); sla_set_error(SLA_E_MEMORY); return -1; }
                acc.data = np; acc.cap = new_cap;
            }
            memcpy(acc.data + acc.len, tmp, (size_t)(take * acc.ch) * sizeof(short));
            acc.len += take * acc.ch;
        }
        sla_mf_aac_close(mft);
    }
    if (!got_meta || acc.len == 0)
    {
        free(acc.data);
        sla_set_error_detail(SLA_E_DECODE, "adts: no frame decoded");
        return -1;
    }
    *out_pcm = acc.data;
    return acc.len / *ch;
}

static int64_t decode_bytes(const unsigned char* p, int64_t size,
                            int fmt_hint, int* sr, int* ch,
                            int* src_fmt, short** out_pcm)
{
    int fmt = fmt_hint;
    if (fmt == SLA_HINT_AUTO || fmt == SLA_FMT_WAV || fmt == SLA_FMT_MP4)
    {
        int sniffed = sniff_fmt(p, size);
        if (fmt == SLA_HINT_AUTO) fmt = sniffed;
        if (sniffed == SLA_FMT_UNKNOWN && fmt != SLA_FMT_WAV)
        {
            /* PCM 家族无法从数据嗅探（无头）：必须显式 hint + 尺寸     */
            sla_set_error_detail(SLA_E_UNSUPPORTED,
                                 "decode: unknown format (raw pcm needs fmt_hint)");
            return -1;
        }
    }
    switch (fmt)
    {
    case SLA_FMT_WAV:
        {
            int64_t frames = sla_wav_decode_all(p, size, sr, ch, out_pcm);
            if (frames > 0) *src_fmt = SLA_FMT_WAV;
            return frames;
        }
    case SLA_FMT_MP3:
        {
            int64_t frames = sla_mp3_decode_all(p, size, sr, ch, out_pcm);
            if (frames > 0) *src_fmt = SLA_FMT_MP3;
            return frames;
        }
    case SLA_FMT_MP4:
    case SLA_FMT_MP4_PCM:
    case SLA_FMT_MP4_MP3:
    case SLA_FMT_MP4_AAC:
        {
            int64_t frames = sla_mp4_decode_all(p, size, sr, ch, src_fmt, out_pcm);
            return frames;
        }
    case SLA_FMT_AAC_ADTS:
        {
            int64_t frames = decode_adts_all(p, size, sr, ch, out_pcm);
            if (frames > 0) *src_fmt = SLA_FMT_AAC_ADTS;
            return frames;
        }
    case SLA_FMT_PCM_S16:
    case SLA_FMT_PCM_U8:
    case SLA_FMT_PCM_F32:
        {
            /* 裸 PCM 无头：sr/ch 经 decode 侧不可得（0 -> BAD_PARAM），
             * 裸流解码请走 stream（create 时显式 sr/ch）               */
            int64_t frames = sla_wav_pcm_to_i16(p, size, fmt, sr, ch, out_pcm);
            if (frames > 0) *src_fmt = fmt;
            return frames;
        }
    default:
        sla_set_error_detail(SLA_E_UNSUPPORTED, "decode: fmt=%d", fmt);
        return -1;
    }
}

static int64_t dec_register(int sr, int ch, int src_fmt,
                            short* pcm, int64_t frames)
{
    int i;
    for (i = 0; i < SLA_MAX_DEC; i++)
    {
        if (!s_decs[i].used)
        {
            s_decs[i].used = 1;
            s_decs[i].sr = sr;
            s_decs[i].ch = ch;
            s_decs[i].src_fmt = src_fmt;
            s_decs[i].frames = frames;
            s_decs[i].pcm = pcm;
            return (int64_t)(i + 1);
        }
    }
    free(pcm);
    sla_set_error(SLA_E_LIMIT);
    return 0;
}

int64_t sla_decode_file(const char* path_utf8, int fmt_hint)
{
    int64_t size = 0, frames;
    unsigned char* data;
    int sr = 0, ch = 0, src_fmt = SLA_FMT_UNKNOWN;
    short* pcm = NULL;
    sla_set_error(SLA_OK);
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    if (!path_utf8 || !path_utf8[0]) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    data = read_file_utf8(path_utf8, &size);
    if (!data) return 0;
    frames = decode_bytes(data, size, fmt_hint, &sr, &ch, &src_fmt, &pcm);
    free(data);
    if (frames <= 0) return 0;
    return dec_register(sr, ch, src_fmt, pcm, frames);
}

int64_t sla_decode_mem(int64_t data_ptr, int64_t size, int fmt_hint)
{
    int sr = 0, ch = 0, src_fmt = SLA_FMT_UNKNOWN;
    short* pcm = NULL;
    int64_t frames;
    sla_set_error(SLA_OK);
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    if (data_ptr == 0 || size <= 0) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    /* 裸 PCM 家族需要 sr/ch hint 语义由 stream 承担；mem 路径 sr/ch=0
     * 仅对 PCM 报参数错（无头裸流本来无参不可解）                     */
    frames = decode_bytes((const unsigned char*)(intptr_t)data_ptr, size,
                          fmt_hint, &sr, &ch, &src_fmt, &pcm);
    if (frames <= 0) return 0;
    return dec_register(sr, ch, src_fmt, pcm, frames);
}

static SlaDec* dec_from(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLA_MAX_DEC || !s_decs[i].used) return NULL;
    return &s_decs[i];
}

int sla_dec_sample_rate(int64_t dec)
{
    SlaDec* d = dec_from(dec);
    return d ? d->sr : 0;
}
int sla_dec_channels(int64_t dec)
{
    SlaDec* d = dec_from(dec);
    return d ? d->ch : 0;
}
int sla_dec_source_format(int64_t dec)
{
    SlaDec* d = dec_from(dec);
    return d ? d->src_fmt : SLA_FMT_UNKNOWN;
}
int64_t sla_dec_frame_count(int64_t dec)
{
    SlaDec* d = dec_from(dec);
    return d ? d->frames : 0;
}

int64_t sla_dec_copy_i16(int64_t dec, int64_t dst_ptr, int64_t cap_frames)
{
    SlaDec* d = dec_from(dec);
    int64_t copy_frames;
    if (!d) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    if (dst_ptr == 0 || cap_frames <= 0) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    copy_frames = d->frames < cap_frames ? d->frames : cap_frames;
    memcpy((void*)(intptr_t)dst_ptr, d->pcm,
           (size_t)(copy_frames * d->ch) * sizeof(short));
    return copy_frames;
}

int sla_dec_free(int64_t dec)
{
    SlaDec* d = dec_from(dec);
    if (!d) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    free(d->pcm);
    memset(d, 0, sizeof(SlaDec));
    return 1;
}

/* ================= 流式 ================= */

static SlaStream* stm_from(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLA_MAX_STREAM || !s_streams[i].used) return NULL;
    return &s_streams[i];
}

static int stm_buf_append(SlaStream* s, const unsigned char* p, int64_t size)
{
    if (s->len + size > s->cap)
    {
        int new_cap = (s->len + (int)size) * 2 + SLA_RING_INIT;
        unsigned char* np = (unsigned char*)realloc(s->buf, (size_t)new_cap);
        if (!np) return 0;
        s->buf = np;
        s->cap = new_cap;
    }
    memcpy(s->buf + s->len, p, (size_t)size);
    s->len += (int)size;
    return 1;
}
static void stm_buf_consume(SlaStream* s, int bytes)
{
    if (bytes <= 0 || bytes > s->len) return;
    memmove(s->buf, s->buf + bytes, (size_t)(s->len - bytes));
    s->len -= bytes;
}

int64_t sla_stream_create(int fmt_hint, int sample_rate, int channels)
{
    int i;
    sla_set_error(SLA_OK);
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    for (i = 0; i < SLA_MAX_STREAM; i++)
    {
        SlaStream* s = &s_streams[i];
        if (s->used) continue;
        if (fmt_hint != SLA_HINT_AUTO && fmt_hint != SLA_FMT_WAV &&
            fmt_hint != SLA_FMT_MP3 && fmt_hint != SLA_FMT_AAC_ADTS &&
            fmt_hint != SLA_FMT_PCM_S16 && fmt_hint != SLA_FMT_PCM_U8 &&
            fmt_hint != SLA_FMT_PCM_F32)
        {
            sla_set_error_detail(SLA_E_BAD_PARAM, "stream: fmt_hint=%d", fmt_hint);
            return 0;
        }
        memset(s, 0, sizeof(SlaStream));
        s->used = 1;
        s->fmt_hint = fmt_hint;
        s->sr_hint = sample_rate;
        s->ch_hint = channels;
        return (int64_t)(i + 1);
    }
    sla_set_error(SLA_E_LIMIT);
    return 0;
}

int64_t sla_stream_feed(int64_t h, int64_t data_ptr, int64_t size)
{
    SlaStream* s = stm_from(h);
    const unsigned char* p;
    sla_set_error(SLA_OK);
    if (!s) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    if (data_ptr == 0 || size <= 0) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    p = (const unsigned char*)(intptr_t)data_ptr;

    /* MP3：直通后端实例（不经调度层 buf）                           */
    if (s->fmt_hint == SLA_FMT_MP3 || s->fmt == SLA_FMT_MP3)
    {
        if (!s->mp3)
        {
            s->mp3 = sla_mp3_stream_new();
            if (!s->mp3) { sla_set_error(SLA_E_MEMORY); return 0; }
        }
        if (sla_mp3_stream_feed(&s->mp3, p, size) != size)
        {
            sla_set_error_detail(SLA_E_MEMORY, "stream: mp3 feed");
            return 0;
        }
        return size;
    }
    /* 其余（wav 嗅探 / adts 装配 / pcm 直通）进通用 buf             */
    if (!stm_buf_append(s, p, size))
    {
        sla_set_error(SLA_E_MEMORY);
        return 0;
    }
    return size;
}

/* wav 流：头解析后 data_start 起 16bit PCM 直出（调度层 buf）      */
static int64_t stm_read_wav(SlaStream* s, short* dst, int64_t cap_frames)
{
    int sr = 0, ch = 0, bits = 0, is_float = 0;
    int64_t off = 0, dsize = 0;
    if (!s->wav_done)
    {
        if (sla_wav_parse_header(s->buf, s->len, &sr, &ch, &bits, &is_float,
                                 &off, &dsize) != 1)
        {
            if (s->len >= 4 && s->buf[0] == 'R')
            {
                sla_set_error(SLA_E_NO_DATA);  /* 头未凑齐               */
                return 0;
            }
            return 0;
        }
        if (bits != 16 || is_float)
        {
            sla_set_error_detail(SLA_E_UNSUPPORTED, "stream wav: bits=%d float=%d",
                                 bits, is_float);
            return 0;
        }
        s->sr = sr;
        s->ch = ch;
        s->fmt = SLA_FMT_WAV;
        s->wav_done = 1;
        s->data_start = off;
    }
    {
        int64_t avail = s->len - s->data_start;
        int64_t frame_bytes = (int64_t)2 * s->ch;
        int64_t frames = avail / frame_bytes;
        int64_t take = frames < cap_frames ? frames : cap_frames;
        if (take <= 0) return 0;
        memcpy(dst, s->buf + s->data_start, (size_t)(take * frame_bytes));
        stm_buf_consume(s, (int)(take * frame_bytes + s->data_start));
        s->data_start = 0;                    /* 消费含头部             */
        s->frames_out += take;
        return take;
    }
}

/* 裸 PCM：bits 由 fmt_hint 决定；sr/ch 必须显式                      */
static int64_t stm_read_pcm(SlaStream* s, short* dst, int64_t cap_frames)
{
    int fmt = s->fmt_hint;
    int64_t bps, avail, frames, take, i;
    if (s->sr_hint <= 0 || s->ch_hint <= 0)
    {
        sla_set_error_detail(SLA_E_BAD_PARAM, "stream pcm: need sr/ch");
        return 0;
    }
    s->sr = s->sr_hint;
    s->ch = s->ch_hint;
    s->fmt = (fmt == SLA_FMT_PCM_U8 || fmt == SLA_FMT_PCM_F32) ? fmt : SLA_FMT_PCM_S16;

    if (s->fmt == SLA_FMT_PCM_S16)    bps = 2 * s->ch;
    else if (s->fmt == SLA_FMT_PCM_U8) bps = s->ch;
    else                               bps = 4 * s->ch;

    avail = s->len;
    frames = avail / bps;
    take = frames < cap_frames ? frames : cap_frames;
    if (take <= 0) return 0;

    if (s->fmt == SLA_FMT_PCM_S16)
    {
        memcpy(dst, s->buf, (size_t)(take * bps));
    }
    else
    {
        for (i = 0; i < take * s->ch; i++)
        {
            if (s->fmt == SLA_FMT_PCM_U8)
            {
                int v = ((int)s->buf[i] - 128) * 256;
                dst[i] = (short)(v < -32768 ? -32768 : (v > 32767 ? 32767 : v));
            }
            else
            {
                union { uint32_t u; float f; } cvt;
                float f;
                cvt.u = (uint32_t)s->buf[i * 4] | ((uint32_t)s->buf[i * 4 + 1] << 8) |
                        ((uint32_t)s->buf[i * 4 + 2] << 16) | ((uint32_t)s->buf[i * 4 + 3] << 24);
                f = cvt.f;
                if (f > 1.0f) f = 1.0f;
                if (f < -1.0f) f = -1.0f;
                dst[i] = (short)(f * 32767.0f);
            }
        }
    }
    stm_buf_consume(s, (int)(take * bps));
    s->frames_out += take;
    return take;
}

/* ADTS：扫描整帧 -> MF adts 模式 -> take                            */
static int64_t stm_read_adts(SlaStream* s, short* dst, int64_t cap_frames)
{
    int64_t filled = 0;
    while (filled < cap_frames)
    {
        int profile = 0, flen, sr = 0, ch = 0;
        /* 先取 MFT 已积压                                        */
        if (s->mft)
        {
            int64_t take = sla_mf_aac_take(s->mft, dst + filled * s->ch,
                                           cap_frames - filled);
            if (take > 0)
            {
                filled += take;
                s->frames_out += take;
                if (filled >= cap_frames) break;
            }
        }
        /* 凑一个完整 ADTS 帧                                     */
        flen = adts_frame_len(s->buf, s->len, &sr, &ch, &profile);
        if (flen == 0)
        {
            /* 同步字不在 0 位：逐字节滑窗                        */
            int i;
            for (i = 1; i < s->len; i++)
            {
                if (s->buf[i] == 0xFF && (s->buf[i + 1] & 0xF0) == 0xF0)
                {
                    stm_buf_consume(s, i);
                    break;
                }
                if (i + 1 >= s->len) { stm_buf_consume(s, s->len); break; }
            }
            if (s->len < 7) { sla_set_error(SLA_E_NO_DATA); break; }
            continue;
        }
        if (flen > s->len)
        {
            sla_set_error(SLA_E_NO_DATA);      /* 帧未凑齐               */
            break;
        }
        if (!s->mft)
        {
            if (sr <= 0 || ch <= 0)
            {
                sla_set_error_detail(SLA_E_DECODE, "stream adts: bad header");
                break;
            }
            s->mft = sla_mf_aac_open(sr, ch, NULL, 0, 1);
            if (!s->mft) break;               /* 错误已设               */
            s->sr = sr;
            s->ch = ch;
            s->fmt = SLA_FMT_AAC_ADTS;
        }
        if (!sla_mf_aac_push(s->mft, s->buf, flen))
        {
            stm_buf_consume(s, flen);          /* 坏帧跳过               */
            continue;
        }
        stm_buf_consume(s, flen);
        if (s->fmt == 0) { s->fmt = SLA_FMT_AAC_ADTS; s->sr = sr; s->ch = ch; }
    }
    return filled;
}

int64_t sla_stream_read_i16(int64_t h, int64_t dst_ptr, int64_t cap_frames)
{
    SlaStream* s = stm_from(h);
    short* dst;
    int64_t out = 0;
    sla_set_error(SLA_OK);
    if (!s) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    if (dst_ptr == 0 || cap_frames <= 0) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    dst = (short*)(intptr_t)dst_ptr;

    /* fmt 未定型（hint=auto）：嗅探                              */
    if (s->fmt_hint == SLA_HINT_AUTO && s->fmt == 0)
    {
        int sniffed = sniff_fmt(s->buf, s->len);
        if (sniffed == SLA_FMT_UNKNOWN)
        {
            if (s->len < 12) { sla_set_error(SLA_E_NO_DATA); return 0; }
            sla_set_error_detail(SLA_E_UNSUPPORTED, "stream: unknown format");
            return 0;
        }
        s->fmt_hint = sniffed;
    }

    if (s->fmt_hint == SLA_FMT_MP3 || s->fmt == SLA_FMT_MP3)
    {
        int sr = 0, ch = 0, fmt = 0;
        if (!s->mp3) { sla_set_error(SLA_E_NO_DATA); return 0; }
        out = sla_mp3_stream_read(s->mp3, dst, cap_frames, &sr, &ch, &fmt);
        if (sr > 0 && ch > 0) { s->sr = sr; s->ch = ch; s->fmt = SLA_FMT_MP3; }
        s->frames_out += out;
        return out;
    }
    if (s->fmt_hint == SLA_FMT_AAC_ADTS)
    {
        if (s->fmt == 0) s->fmt_hint = SLA_FMT_AAC_ADTS;
        return stm_read_adts(s, dst, cap_frames);
    }
    if (s->fmt_hint == SLA_FMT_WAV)
    {
        return stm_read_wav(s, dst, cap_frames);
    }
    if (s->fmt_hint == SLA_FMT_PCM_S16 || s->fmt_hint == SLA_FMT_PCM_U8 ||
        s->fmt_hint == SLA_FMT_PCM_F32)
    {
        return stm_read_pcm(s, dst, cap_frames);
    }
    sla_set_error_detail(SLA_E_UNSUPPORTED, "stream: fmt=%d", s->fmt_hint);
    return 0;
}

int sla_stream_sample_rate(int64_t h)
{
    SlaStream* s = stm_from(h);
    return s ? s->sr : 0;
}
int sla_stream_channels(int64_t h)
{
    SlaStream* s = stm_from(h);
    return s ? s->ch : 0;
}
int sla_stream_source_format(int64_t h)
{
    SlaStream* s = stm_from(h);
    return s ? (s->fmt ? s->fmt : s->fmt_hint) : SLA_FMT_UNKNOWN;
}
int64_t sla_stream_frames_out(int64_t h)
{
    SlaStream* s = stm_from(h);
    return s ? s->frames_out : 0;
}

int sla_stream_free(int64_t h)
{
    SlaStream* s = stm_from(h);
    if (!s) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    free(s->buf);
    if (s->mp3) sla_mp3_stream_free(s->mp3);
    if (s->mft) sla_mf_aac_close(s->mft);
    memset(s, 0, sizeof(SlaStream));
    return 1;
}

/* ================= 播放 ================= */

int sla_device_available(void)
{
    return sla_wave_device_available();
}

int64_t sla_player_create(int sample_rate, int channels)
{
    int i;
    if (!s_ready) { sla_set_error(SLA_E_NOT_INITIALIZED); return 0; }
    for (i = 0; i < SLA_MAX_PLAYER; i++)
    {
        SlaPlayer* p = &s_players[i];
        SlaWaveOut* w;
        if (p->used) continue;
        w = sla_wave_open(sample_rate, channels);
        if (!w) return 0;                     /* 错误已设               */
        p->used = 1;
        p->wave = w;
        return (int64_t)(i + 1);
    }
    sla_set_error(SLA_E_LIMIT);
    return 0;
}

static SlaPlayer* ply_from(int64_t h)
{
    int i = (int)(h - 1);
    if (h <= 0 || i >= SLA_MAX_PLAYER || !s_players[i].used) return NULL;
    return &s_players[i];
}

int64_t sla_player_enqueue(int64_t h, int64_t pcm_ptr, int64_t frames)
{
    SlaPlayer* p = ply_from(h);
    if (!p) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    if (pcm_ptr == 0 || frames <= 0) { sla_set_error(SLA_E_BAD_PARAM); return 0; }
    return sla_wave_enqueue(p->wave, (const short*)(intptr_t)pcm_ptr, frames);
}

int sla_player_pause(int64_t h, int paused)
{
    SlaPlayer* p = ply_from(h);
    if (!p) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    return sla_wave_pause(p->wave, paused);
}

int sla_player_stop(int64_t h)
{
    SlaPlayer* p = ply_from(h);
    if (!p) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    return sla_wave_stop(p->wave);
}

int64_t sla_player_position(int64_t h)
{
    SlaPlayer* p = ply_from(h);
    return p ? sla_wave_position(p->wave) : 0;
}

int sla_player_volume(int64_t h, int vol)
{
    SlaPlayer* p = ply_from(h);
    if (!p) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    return sla_wave_volume(p->wave, vol);
}

int64_t sla_player_buffered(int64_t h)
{
    SlaPlayer* p = ply_from(h);
    return p ? sla_wave_buffered(p->wave) : 0;
}

int sla_player_free(int64_t h)
{
    SlaPlayer* p = ply_from(h);
    if (!p) { sla_set_error(SLA_E_BAD_HANDLE); return 0; }
    sla_wave_close(p->wave);
    memset(p, 0, sizeof(SlaPlayer));
    return 1;
}
