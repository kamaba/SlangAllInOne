/* =========================================================================
 * sl_audio_mp3.c —— Codec：minimp3 唯一 IMPLEMENTATION 编译点 + 适配
 *
 * minimp3 r1.0.3（CC0 公有领域，third_party/minimp3/ 整文件内置）。
 * 本单元是 minimp3.h 的唯一 #define MINIMP3_IMPLEMENTATION 编译点
 * （与 sl_image_stb.c 之于 stb 同款约定，勿在他处重复包含实现）。
 * 默认 S16 输出（mp3d_sample_t = int16_t），与本库 PCM 契约一致。
 * ========================================================================= */
#define MINIMP3_IMPLEMENTATION
#include "../third_party/minimp3/minimp3.h"

#include "../sl_audio_internal.h"

int sla_mp3_is_mp3(const unsigned char* p, int64_t size)
{
    if (!p || size < 4) return 0;
    /* ID3v2 头（"ID3"）或裸帧同步字 FF Ex */
    if (p[0] == 'I' && p[1] == 'D' && p[2] == '3') return 1;
    if (p[0] == 0xFF && (p[1] & 0xE0) == 0xE0) return 1;
    return 0;
}

int64_t sla_mp3_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, short** out_pcm)
{
    mp3dec_t dec;
    mp3dec_frame_info_t info;
    short frame_pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
    short* acc = NULL;
    int64_t acc_cap = 0, acc_len = 0;   /* acc_len = sample 数           */
    int got_meta = 0;

    if (!p || size <= 0) { sla_set_error(SLA_E_BAD_PARAM); return -1; }
    mp3dec_init(&dec);
    memset(&info, 0, sizeof(info));

    while (size > 0)
    {
        int samples = mp3dec_decode_frame(&dec, p, (int)(size > 0x7FFFFFF ? 0x7FFFFFF : size),
                                          frame_pcm, &info);
        if (info.frame_bytes == 0) break;          /* 数据不足/坏流终止  */
        if (info.frame_bytes < 0) break;
        p    += info.frame_bytes;
        size -= info.frame_bytes;

        if (info.channels > 0 && info.hz > 0)
        {
            *sr = info.hz;
            *ch = info.channels;
            got_meta = 1;
        }
        if (samples > 0 && got_meta)
        {
            if (acc_len + samples > acc_cap)
            {
                int64_t new_cap = (acc_len + samples) * 2 + 1152 * 8;
                short* np = (short*)realloc(acc, (size_t)new_cap * sizeof(short));
                if (!np) { free(acc); sla_set_error(SLA_E_MEMORY); return -1; }
                acc = np; acc_cap = new_cap;
            }
            memcpy(acc + acc_len, frame_pcm, (size_t)samples * sizeof(short));
            acc_len += samples;
            if (acc_len > SLA_MAX_FRAMES * (int64_t)(*ch > 0 ? *ch : 2))
            {
                free(acc);
                sla_set_error_detail(SLA_E_DECODE, "mp3: too many samples");
                return -1;
            }
        }
    }
    if (!got_meta || acc_len == 0)
    {
        free(acc);
        sla_set_error_detail(SLA_E_DECODE, "mp3: no frame decoded");
        return -1;
    }
    *out_pcm = acc;
    return acc_len / *ch;   /* 帧数 = 采样总数 / 声道 */
}

/* ---- 流式适配：追加缓冲 + 逐帧解码（consume 后 memmove 收缩） ---- */
typedef struct
{
    mp3dec_t dec;
    unsigned char* buf;
    int len, cap;
    int sr, ch, fmt;          /* fmt/sr/ch：首帧解码后定型 */
    int64_t frames_out;
} SlaMp3Stream;

/* 新建流式状态（调用方 free）。内部使用（sl_audio_mp4.c 同 DLL 共享）。 */
void* sla_mp3_stream_new(void)
{
    SlaMp3Stream* s = (SlaMp3Stream*)calloc(1, sizeof(SlaMp3Stream));
    if (!s) return NULL;
    mp3dec_init(&s->dec);
    return s;
}

int64_t sla_mp3_stream_feed(void** st, const unsigned char* p, int64_t size)
{
    SlaMp3Stream* s = (SlaMp3Stream*)*st;
    if (!s) return 0;
    if (!p || size <= 0) return 0;
    if (s->len + size > s->cap)
    {
        int new_cap = (s->len + (int)size) * 2 + SLA_RING_INIT;
        unsigned char* np = (unsigned char*)realloc(s->buf, (size_t)new_cap);
        if (!np) return 0;
        s->buf = np; s->cap = new_cap;
    }
    memcpy(s->buf + s->len, p, (size_t)size);
    s->len += (int)size;
    return size;                       /* 全量缓存                     */
}

int64_t sla_mp3_stream_read(void* st, short* dst, int64_t cap_frames,
                             int* sr, int* ch, int* fmt)
{
    SlaMp3Stream* s = (SlaMp3Stream*)st;
    int64_t filled = 0;
    mp3dec_frame_info_t info;
    short frame_pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];

    if (!s || !dst || cap_frames <= 0) return 0;
    while (filled < cap_frames && s->len > 0)
    {
        int samples = mp3dec_decode_frame(&s->dec, s->buf, s->len, frame_pcm, &info);
        if (info.frame_bytes <= 0) break;
        memmove(s->buf, s->buf + info.frame_bytes,
                (size_t)(s->len - info.frame_bytes));
        s->len -= info.frame_bytes;
        if (info.channels > 0 && info.hz > 0)
        {
            s->sr = info.hz; s->ch = info.channels; s->fmt = SLA_FMT_MP3;
        }
        if (samples > 0 && s->ch > 0)
        {
            int64_t frames = samples / s->ch;
            int64_t take = frames;
            if (take > cap_frames - filled) take = cap_frames - filled;
            memcpy(dst + filled * s->ch, frame_pcm, (size_t)(take * s->ch) * sizeof(short));
            filled += take;
            s->frames_out += take;
            /* 半帧截断时丢弃余量（流式场景可接受，帧粒度 1152 无感） */
        }
        /* info.frame_bytes==0（长度不足下一帧）则等更多 feed          */
        if (info.frame_bytes == 0) break;
    }
    if (s->ch > 0) { *sr = s->sr; *ch = s->ch; *fmt = s->fmt; }
    return filled;
}

void sla_mp3_stream_free(void* st)
{
    SlaMp3Stream* s = (SlaMp3Stream*)st;
    if (s)
    {
        free(s->buf);
        free(s);
    }
}
