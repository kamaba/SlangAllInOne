/* =========================================================================
 * sl_audio_wav.c —— Codec：RIFF/WAV 解析 + 裸 PCM 转换（内建，零依赖）
 *
 * 支持：PCM 8/16/24/32bit + IEEE float 32bit（wFormatTag 1/3），
 *       fmt 块容许在 data 之后（部分编码器产物）；奇数块 pad 对齐。
 * 输出统一 interleaved S16LE。
 * ========================================================================= */
#include "../sl_audio_internal.h"

static int rd16le(const unsigned char* p)
{
    return (int)p[0] | ((int)p[1] << 8);
}
static int32_t rd32le(const unsigned char* p)
{
    return (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                    ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}
static int chunk_eq(const unsigned char* p, const char* id)
{
    return p[0] == (unsigned char)id[0] && p[1] == (unsigned char)id[1] &&
           p[2] == (unsigned char)id[2] && p[3] == (unsigned char)id[3];
}

int sla_wav_is_wav(const unsigned char* p, int64_t size)
{
    if (!p || size < 12) return 0;
    return chunk_eq(p, "RIFF") && chunk_eq(p + 8, "WAVE");
}

int sla_wav_parse_header(const unsigned char* p, int64_t size,
                          int* sr, int* ch, int* bits, int* is_float,
                          int64_t* data_off, int64_t* data_size)
{
    int64_t pos = 12;
    int have_fmt = 0;
    if (!sla_wav_is_wav(p, size)) return 0;
    while (pos + 8 <= size)
    {
        int64_t csize = (int64_t)(uint32_t)rd32le(p + pos + 4);
        if (pos + 8 + csize > size) csize = size - pos - 8;
        if (chunk_eq(p + pos, "fmt ") && pos + 8 + 16 <= size)
        {
            int tag = rd16le(p + pos + 8);
            *ch    = rd16le(p + pos + 10);
            *sr    = rd32le(p + pos + 12);
            *bits  = rd16le(p + pos + 22);
            *is_float = (tag == 3);
            have_fmt = 1;
            if (*sr <= 0 || *sr > SLA_MAX_SR || *ch <= 0 || *ch > SLA_MAX_CH)
                return 0;
        }
        else if (chunk_eq(p + pos, "data"))
        {
            if (!have_fmt) return 0;
            *data_off  = pos + 8;
            *data_size = csize;
            return 1;
        }
        pos += 8 + csize + (csize & 1);
    }
    return 0;
}

/* 单采样 -> S16（f = 源值 [-1,1] 域或整型域由 kind 决定） */
static short cvt_to_i16(int kind, int32_t iv, float fv)
{
    int32_t s;
    switch (kind)
    {
    case 8:  s = iv * 256; break;                 /* u8 (zero=128)        */
    case 16: s = iv; break;                       /* s16 直通             */
    case 24: s = iv >> 8; break;                  /* s24 -> s16 高位截断  */
    case 32: s = (int32_t)(fv * 32767.0f); break;  /* float32              */
    default: s = 0; break;
    }
    if (s > 32767)  s = 32767;
    if (s < -32768) s = -32768;
    return (short)s;
}

int64_t sla_wav_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, short** out_pcm)
{
    int bits = 0, is_float = 0;
    int64_t data_off = 0, data_size = 0, frames, i;
    int bps;
    short* pcm;

    if (sla_wav_parse_header(p, size, sr, ch, &bits, &is_float,
                             &data_off, &data_size) != 1)
    {
        sla_set_error_detail(SLA_E_DECODE, "wav: no fmt/data chunk");
        return -1;
    }
    if (bits != 8 && bits != 16 && bits != 24 && bits != 32)
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "wav: bits=%d", bits);
        return -1;
    }
    if (is_float && bits != 32)
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "wav: float bits=%d", bits);
        return -1;
    }
    bps = bits / 8;
    frames = data_size / ((int64_t)bps * *ch);
    if (frames <= 0 || frames > SLA_MAX_FRAMES)
    {
        sla_set_error_detail(SLA_E_DECODE, "wav: frames=%lld", (long long)frames);
        return -1;
    }
    pcm = (short*)malloc((size_t)(frames * *ch) * sizeof(short));
    if (!pcm) { sla_set_error(SLA_E_MEMORY); return -1; }

    for (i = 0; i < frames * *ch; i++)
    {
        const unsigned char* q = p + data_off + i * bps;
        int32_t iv = 0;
        float fv = 0.0f;
        switch (bps)
        {
        case 1: iv = (int32_t)q[0] - 128; break;
        case 2: iv = (int16_t)rd16le(q); break;
        case 3:
            {
                uint32_t u = (uint32_t)q[0] | ((uint32_t)q[1] << 8) | ((uint32_t)q[2] << 16);
                iv = (int32_t)(u < 0x800000u ? u : u - 0x1000000u);
                break;
            }
        case 4:
            if (is_float)
            {
                union { uint32_t u; float f; } cvt;
                cvt.u = (uint32_t)rd32le(q);
                fv = cvt.f;
                if (fv > 1.0f) fv = 1.0f;
                if (fv < -1.0f) fv = -1.0f;
            }
            else iv = rd32le(q) >> 16;
            break;
        }
        pcm[i] = cvt_to_i16(is_float ? 32 : bits, iv, fv);
    }
    *out_pcm = pcm;
    return frames;
}

/* 裸 PCM 块转换（src_fmt = SLA_FMT_PCM_S16 / PCM_U8 / PCM_F32） */
int64_t sla_wav_pcm_to_i16(const unsigned char* p, int64_t size, int src_fmt,
                            int* sr_hint, int* ch_hint, short** out_pcm)
{
    int ch, bps;
    int64_t frames;
    short* pcm;
    if (!p || size <= 0) { sla_set_error(SLA_E_BAD_PARAM); return -1; }

    ch = *ch_hint;
    if (ch <= 0 || ch > SLA_MAX_CH) { sla_set_error_detail(SLA_E_BAD_PARAM, "pcm: ch=%d", ch); return -1; }
    if (*sr_hint < 0 || *sr_hint > SLA_MAX_SR) { sla_set_error_detail(SLA_E_BAD_PARAM, "pcm: sr=%d", *sr_hint); return -1; }

    if (src_fmt == SLA_FMT_PCM_S16)     bps = 2;
    else if (src_fmt == SLA_FMT_PCM_U8) bps = 1;
    else if (src_fmt == SLA_FMT_PCM_F32) bps = 4;
    else { sla_set_error_detail(SLA_E_UNSUPPORTED, "pcm: fmt=%d", src_fmt); return -1; }

    frames = size / ((int64_t)bps * ch);
    if (frames <= 0 || frames > SLA_MAX_FRAMES)
    {
        sla_set_error_detail(SLA_E_DECODE, "pcm: frames=%lld", (long long)frames);
        return -1;
    }
    pcm = (short*)malloc((size_t)(frames * ch) * sizeof(short));
    if (!pcm) { sla_set_error(SLA_E_MEMORY); return -1; }

    if (src_fmt == SLA_FMT_PCM_S16)
    {
        memcpy(pcm, p, (size_t)(frames * ch) * 2);
    }
    else
    {
        int64_t i;
        for (i = 0; i < frames * ch; i++)
        {
            if (src_fmt == SLA_FMT_PCM_U8)
                pcm[i] = cvt_to_i16(8, (int32_t)p[i] - 128, 0.0f);
            else
            {
                union { uint32_t u; float f; } cvt;
                float f = 0.0f;
                cvt.u = (uint32_t)rd32le(p + i * 4);
                f = cvt.f;
                if (f > 1.0f) f = 1.0f;
                if (f < -1.0f) f = -1.0f;
                pcm[i] = cvt_to_i16(32, 0, f);
            }
        }
    }
    *out_pcm = pcm;
    return frames;
}
