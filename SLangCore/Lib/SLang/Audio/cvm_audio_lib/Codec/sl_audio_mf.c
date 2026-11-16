/* =========================================================================
 * sl_audio_mf.c —— Codec：Media Foundation AAC 解码 MFT（Windows 系统组件）
 *
 * CMSAACDecMFT：ADTS（payload=0）与 raw（payload=1 + AudioSpecificConfig）
 * 两种输入；输出恒 IEEE Float32 -> 本文件就地转 S16 追加 pending。
 * 纯 C + lpVtbl 调用（.c 单元内 COM 必须 lpVtbl，sl_image_wic.c 同款）；
 * 依赖系统自带：mfplat.lib / mfuuid.lib / ole32.lib（pragma 注入）。
 * COM 走 MTA；RPC_E_CHANGED_MODE（线程已 STA）直接继续，仅 SUCCEEDED 时配对 Uninit。
 * ========================================================================= */
#include <windows.h>
#include <objbase.h>
#include <mfapi.h>
#include <mfobjects.h>
#include <mftransform.h>
#include <mferror.h>
#include <wmcodecdsp.h>          /* CLSID_CMSAACDecMFT（本 SDK mftransform.h 不含）*/
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")   /* CLSID_CMSAACDecMFT 实例   */
#pragma comment(lib, "ole32.lib")

#include "../sl_audio_internal.h"

typedef struct
{
    IMFTransform* xform;
    int sr, ch, payload_adts;
    int com_init;                 /* open 时 CoInit 保持到 close       */
    int mf_started;
    int    self_out_samples;      /* MFT 自供输出样本                  */
    int64_t next_hns;             /* 输入样本时间戳（100ns）           */
    DWORD  out_buf_cap;           /* 预分配输出 buffer 字节数          */
    short*  pend;                 /* pending interleaved S16           */
    int64_t pend_len;             /* 帧数                               */
    int64_t pend_cap;
    int64_t pend_head;            /* 已 take 起点（懒收缩）            */
} SlaMft;

int sla_mf_available(void)
{
    IMFTransform* x = NULL;
    HRESULT hr;
    int ok = 0;
    int com_init = 0;
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;
    hr = CoCreateInstance(&CLSID_CMSAACDecMFT, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IMFTransform, (void**)&x);
    if (SUCCEEDED(hr) && x)
    {
        ok = 1;
        x->lpVtbl->Release(x);
    }
    if (com_init) CoUninitialize();
    return ok;
}

/* float32 块 -> S16 追加 pending */
static int pend_append(SlaMft* m, const float* f, int64_t frames)
{
    if (m->pend_head > 4096)                       /* 懒收缩已消费前段 */
    {
        memmove(m->pend, m->pend + m->pend_head * m->ch,
                (size_t)((m->pend_len - m->pend_head) * m->ch) * sizeof(short));
        m->pend_len -= m->pend_head;
        m->pend_head = 0;
    }
    if (m->pend_len + frames > m->pend_cap)
    {
        int64_t new_cap = (m->pend_len + frames) * 2 + 4096;
        short* np = (short*)realloc(m->pend, (size_t)(new_cap * m->ch) * sizeof(short));
        if (!np) return 0;
        m->pend = np;
        m->pend_cap = new_cap;
    }
    {
        int64_t i;
        for (i = 0; i < frames * m->ch; i++)
        {
            float v = f[i];
            if (v > 1.0f) v = 1.0f;
            if (v < -1.0f) v = -1.0f;
            m->pend[m->pend_len * m->ch + i] = (short)(v * 32767.0f);
        }
    }
    m->pend_len += frames;
    return 1;
}

/* AAC 采样率表（ISO 14496-3） -> sampling_frequency_index */
static int aac_sr_index(int sr)
{
    static const int tab[13][2] = {
        {96000, 0}, {88200, 1}, {64000, 2}, {48000, 3},
        {44100, 4}, {32000, 5}, {24000, 6}, {22050, 7},
        {16000, 8}, {12000, 9}, {11025, 10}, {8000, 11}, {7350, 12}
    };
    int i;
    for (i = 0; i < 13; i++) if (tab[i][0] == sr) return tab[i][1];
    return -1;
}

/* 由 (objectType=2 AAC-LC, sr, ch) 构造 2 字节 AudioSpecificConfig */
static void aac_make_asc(unsigned char out[2], int sr, int ch)
{
    int sridx = aac_sr_index(sr);
    if (sridx < 0) sridx = 4;                     /* 缺省 44100           */
    out[0] = (unsigned char)((2u << 3) | ((unsigned)sridx >> 1));
    out[1] = (unsigned char)((((unsigned)sridx & 1) << 7) | ((unsigned)ch << 3));
}

void* sla_mf_aac_open(int sample_rate, int channels,
                      const unsigned char* asc, int asc_bytes,
                      int payload_adts)
{
    SlaMft* m = NULL;
    IMFTransform* x = NULL;
    IMFMediaType* in_mt = NULL, * out_mt = NULL;
    unsigned char asc_adts[2];
    const unsigned char* asc_use;
    int asc_len;
    HRESULT hr;
    int com_init = 0, mf_started = 0;

    if (sample_rate <= 0 || sample_rate > SLA_MAX_SR ||
        channels <= 0 || channels > SLA_MAX_CH)
    {
        sla_set_error_detail(SLA_E_BAD_PARAM, "mf-aac: sr=%d ch=%d", sample_rate, channels);
        return NULL;
    }
    /* 实验结论：CMSAACDecMFT 输入类型必须带 MF_MT_USER_DATA(ASC)。
     * ADTS 模式下由帧头参数自构（AAC-LC/sr/ch）                    */
    if (payload_adts)
    {
        aac_make_asc(asc_adts, sample_rate, channels);
        asc_use = asc_adts;
        asc_len = 2;
    }
    else
    {
        if (!asc || asc_bytes < 2)
        {
            sla_set_error_detail(SLA_E_BAD_PARAM, "mf-aac: raw mode needs asc");
            return NULL;
        }
        asc_use = asc;
        asc_len = asc_bytes;
    }

    /* COM/MF 平台状态在实例生命周期内保持（open->close 配对）；
     * 逐次 CoUninitialize 后继续 vtable 调用是未定义行为          */
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) com_init = 1;
    hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (SUCCEEDED(hr)) mf_started = 1;
    hr = CoCreateInstance(&CLSID_CMSAACDecMFT, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IMFTransform, (void**)&x);
    if (FAILED(hr) || !x)
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mf-aac: CoCreateInstance hr=0x%08lx", (unsigned long)hr);
        if (mf_started) MFShutdown();
        if (com_init) CoUninitialize();
        return NULL;
    }

    m = (SlaMft*)calloc(1, sizeof(SlaMft));
    if (!m) goto fail;
    m->xform = x;
    m->sr = sample_rate;
    m->ch = channels;
    m->payload_adts = payload_adts ? 1 : 0;
    m->com_init = com_init;
    m->mf_started = mf_started;
    /* 输入类型协商：CMSAACDecMFT 只接受自报候选作基底（手搓类型一律
     * MF_E_INVALIDMEDIATYPE）。候选固定为 48k/6ch/32bit 占位：
     *   cand[*]: subtype=AAC 的有 pay=0(raw)/pay=1(ADTS)/pay=3
     * 选 payload 匹配的候选，覆盖 sr/ch 与 ASC 后提交              */
    {
        int i2;
        IMFMediaType* base = NULL;
        for (i2 = 0; i2 < 16; i2++)
        {
            IMFMediaType* cand = NULL;
            GUID sub = { 0 };
            UINT32 cpay = 0xFFFFFFFFu;
            if (FAILED(x->lpVtbl->GetInputAvailableType(x, 0, i2, &cand)) || !cand)
                break;
            cand->lpVtbl->GetGUID(cand, &MF_MT_SUBTYPE, &sub);
            cand->lpVtbl->GetUINT32(cand, &MF_MT_AAC_PAYLOAD_TYPE, &cpay);
            if (IsEqualGUID(&sub, &MFAudioFormat_AAC) &&
                cpay == (UINT32)m->payload_adts)
            {
                base = cand;                     /* 持引用，break 后提交 */
                break;
            }
            cand->lpVtbl->Release(cand);
        }
        if (!base)
        {
            hr = MF_E_NO_MORE_TYPES;
            goto fail;
        }
        base->lpVtbl->SetUINT32(base, &MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                (UINT32)sample_rate);
        base->lpVtbl->SetUINT32(base, &MF_MT_AUDIO_NUM_CHANNELS,
                                (UINT32)channels);
        /* USER_DATA（基底默认 ASC）不可改动（改/删即拒）；本机 MFT
         * 实际从流内容自学习（ADTS 头/raw 首帧），忽略该字段        */
        hr = x->lpVtbl->SetInputType(x, 0, base, 0);
        base->lpVtbl->Release(base);
    }
    in_mt = NULL;                                 /* 未用手搓（防误释放）*/
    if (FAILED(hr))
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mf-aac: SetInputType hr=0x%08lx", (unsigned long)hr);
        goto fail;
    }

    /* 输出类型：手搓 Float 类型同样被拒，取解码器推荐基底          */
    {
        IMFMediaType* omt = NULL;
        hr = x->lpVtbl->GetOutputAvailableType(x, 0, 0, &omt);
        if (SUCCEEDED(hr) && omt)
        {
            hr = x->lpVtbl->SetOutputType(x, 0, omt, 0);
            omt->lpVtbl->Release(omt);
        }
        else if (SUCCEEDED(hr)) hr = E_FAIL;
    }
    out_mt = NULL;                                 /* 已不用（防误释放）  */
    if (FAILED(hr))
    {
        sla_set_error_detail(SLA_E_UNSUPPORTED, "mf-aac: SetOutputType hr=0x%08lx", (unsigned long)hr);
        goto fail;
    }

    hr = x->lpVtbl->ProcessMessage(x, MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    if (FAILED(hr)) { /* 非致命 */ }

    /* 输出样本分配模式：多数 AAC MFT 不自供 -> 调用者预分配          */
    {
        MFT_OUTPUT_STREAM_INFO oi;
        memset(&oi, 0, sizeof(oi));
        m->self_out_samples =
            (SUCCEEDED(x->lpVtbl->GetOutputStreamInfo(x, 0, &oi)) &&
             (oi.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES)) ? 1 : 0;
        m->out_buf_cap = oi.cbSize ? oi.cbSize : 16384;
    }

    return m;                                     /* COM/MF 保持到 close */

fail:
    if (in_mt) in_mt->lpVtbl->Release(in_mt);
    if (out_mt) out_mt->lpVtbl->Release(out_mt);
    if (x) x->lpVtbl->Release(x);
    if (m) free(m);
    if (!sla_last_error_is_set())
        sla_set_error_detail(SLA_E_MEMORY, "mf-aac: open failed hr=0x%08lx", (unsigned long)hr);
    if (mf_started) MFShutdown();
    if (com_init) CoUninitialize();
    return NULL;
}

/* 把 MFT 当前输出全部收进 pending；返回 1 成功 */
static int pump_output(SlaMft* m)
{
    for (;;)
    {
        MFT_OUTPUT_DATA_BUFFER ob;
        IMFSample* sample;
        IMFMediaBuffer* buf;
        HRESULT hr;
        BYTE* data = NULL;
        DWORD max_len = 0, cur_len = 0;
        DWORD status = 0;

        memset(&ob, 0, sizeof(ob));
        if (!m->self_out_samples)
        {
            /* 调用者预分配输出样本（MFT 不自供时必须）               */
            IMFMediaBuffer* nb = NULL;
            if (FAILED(MFCreateMemoryBuffer(m->out_buf_cap, &nb)) || !nb)
            {
                sla_set_error(SLA_E_MEMORY);
                return 0;
            }
            if (FAILED(MFCreateSample(&ob.pSample)) || !ob.pSample)
            {
                nb->lpVtbl->Release(nb);
                sla_set_error(SLA_E_MEMORY);
                return 0;
            }
            ob.pSample->lpVtbl->AddBuffer(ob.pSample, nb);
            nb->lpVtbl->Release(nb);
        }
        hr = m->xform->lpVtbl->ProcessOutput(m->xform, 0, 1, &ob, &status);
        if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT)
        {
            if (ob.pSample) ob.pSample->lpVtbl->Release(ob.pSample);
            return 1;                                  /* 正常：需要更多输入 */
        }
        if (hr == MF_E_TRANSFORM_STREAM_CHANGE)
        {
            if (ob.pSample) ob.pSample->lpVtbl->Release(ob.pSample);
            /* 类型变化：重新取解码器推荐输出类型                     */
            {
                IMFMediaType* omt = NULL;
                if (SUCCEEDED(m->xform->lpVtbl->GetOutputAvailableType(m->xform, 0, 0, &omt)) && omt)
                {
                    m->xform->lpVtbl->SetOutputType(m->xform, 0, omt, 0);
                    omt->lpVtbl->Release(omt);
                }
            }
            continue;
        }
        if (FAILED(hr))
        {
            if (ob.pSample) ob.pSample->lpVtbl->Release(ob.pSample);
            return 0;
        }
        sample = ob.pSample;
        if (!sample) return 1;

        hr = sample->lpVtbl->GetBufferByIndex(sample, 0, &buf);
        if (FAILED(hr) || !buf) { sample->lpVtbl->Release(sample); return 1; }
        hr = buf->lpVtbl->Lock(buf, &data, &max_len, &cur_len);
        if (SUCCEEDED(hr) && data)
        {
            int64_t frames = cur_len / (sizeof(float) * m->ch);
            if (frames > 0 && !pend_append(m, (const float*)data, frames))
            {
                buf->lpVtbl->Unlock(buf);
                buf->lpVtbl->Release(buf);
                sample->lpVtbl->Release(sample);
                sla_set_error(SLA_E_MEMORY);
                return 0;
            }
        }
        if (SUCCEEDED(hr)) buf->lpVtbl->Unlock(buf);
        buf->lpVtbl->Release(buf);
        sample->lpVtbl->Release(sample);
    }
}

int sla_mf_aac_push(void* h, const unsigned char* frame, int frame_bytes)
{
    SlaMft* m = (SlaMft*)h;
    IMFMediaBuffer* buf = NULL;
    IMFSample* sample = NULL;
    BYTE* data = NULL;
    HRESULT hr;
    int ok = 0;

    if (!m || !frame || frame_bytes <= 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }

    hr = MFCreateMemoryBuffer((DWORD)frame_bytes, &buf);
    if (FAILED(hr) || !buf) goto done;
    hr = buf->lpVtbl->Lock(buf, &data, NULL, NULL);
    if (FAILED(hr) || !data) goto done;
    memcpy(data, frame, (size_t)frame_bytes);
    buf->lpVtbl->Unlock(buf);
    buf->lpVtbl->SetCurrentLength(buf, (DWORD)frame_bytes);

    hr = MFCreateSample(&sample);
    if (FAILED(hr) || !sample) goto done;
    hr = sample->lpVtbl->AddBuffer(sample, buf);
    if (FAILED(hr)) goto done;
    /* AAC MFT 要求样本带时间戳（否则 MF_E_NO_SAMPLE_TIMESTAMP）     */
    sample->lpVtbl->SetSampleTime(sample, m->next_hns);
    m->next_hns += ((int64_t)frame_bytes * 10000000) / 1000;  /* 近似递增 */

    hr = m->xform->lpVtbl->ProcessInput(m->xform, 0, sample, 0);
    if (SUCCEEDED(hr))
    {
        if (pump_output(m)) ok = 1;
    }
    else
    {
        sla_set_error_detail(SLA_E_DECODE, "mf-aac: ProcessInput hr=0x%08lx", (unsigned long)hr);
    }

done:
    if (sample) sample->lpVtbl->Release(sample);
    if (buf) buf->lpVtbl->Release(buf);
    return ok;
}

int64_t sla_mf_aac_take(void* h, short* dst, int64_t cap_frames)
{
    SlaMft* m = (SlaMft*)h;
    int64_t avail, take;
    if (!m || !dst || cap_frames <= 0) return 0;
    avail = m->pend_len - m->pend_head;
    take = avail < cap_frames ? avail : cap_frames;
    if (take <= 0) return 0;
    memcpy(dst, m->pend + m->pend_head * m->ch, (size_t)(take * m->ch) * sizeof(short));
    m->pend_head += take;
    if (m->pend_head == m->pend_len) { m->pend_head = 0; m->pend_len = 0; }
    return take;
}

int sla_mf_aac_drain(void* h)
{
    SlaMft* m = (SlaMft*)h;
    if (!m) return 0;
    m->xform->lpVtbl->ProcessMessage(m->xform, MFT_MESSAGE_COMMAND_DRAIN, 0);
    pump_output(m);
    m->xform->lpVtbl->ProcessMessage(m->xform, MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    return 1;
}

void sla_mf_aac_close(void* h)
{
    SlaMft* m = (SlaMft*)h;
    if (!m) return;
    if (m->xform) m->xform->lpVtbl->Release(m->xform);
    free(m->pend);
    if (m->mf_started) MFShutdown();
    if (m->com_init) CoUninitialize();
    free(m);
}
