/* =========================================================================
 * sl_audio_wave.c —— Codec：waveOut 播放内核（系统 winmm，内部实现）
 *
 * 每实例：1 设备 + 1 服务线程 + 1 字节环 + 4 WAVEHDR 轮转（每块 4096 帧）。
 * 队列语义：enqueue 进环，线程依序 waveOutWrite；WHDR_DONE 归还时累加
 * 已播帧数；stop = waveOutReset + 清环 + 复位计数。
 * 线程安全：全部公开接口经 CRITICAL_SECTION 保护（线程内亦然）。
 * 依赖系统自带：winmm.lib（pragma 注入）。
 * ========================================================================= */
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")

#include "../sl_audio_internal.h"

#define SLA_WAVE_HDRS   4
#define SLA_WAVE_CHUNK  4096     /* 每 WAVEHDR 帧数                 */
#define SLA_WAVE_PUMP   5         /* 服务线程轮询毫秒                */

struct SlaWaveOut
{
    HWAVEOUT hwo;
    HANDLE   thread;
    CRITICAL_SECTION lock;
    int      sr, ch;
    int      exiting, paused;

    unsigned char* ring;
    int64_t  ring_cap;            /* 字节容量（2 的幂）              */
    int64_t  ring_head;           /* 写位置（字节）                  */
    int64_t  ring_used;           /* 已用字节                        */

    int64_t  frames_enqueued;
    int64_t  frames_played;
    int64_t  frames_dropped;      /* 环满丢弃                        */

    unsigned char* chunks[SLA_WAVE_HDRS];
    WAVEHDR  hdrs[SLA_WAVE_HDRS];
    int      inflight;            /* 在途 WAVEHDR 数                 */
};

int sla_wave_device_available(void)
{
    return waveOutGetNumDevs() > 0 ? 1 : 0;
}

/* ---- 字节环 ---- */
static void ring_put(SlaWaveOut* w, const unsigned char* p, int64_t bytes)
{
    int64_t head = w->ring_head, cap = w->ring_cap;
    while (bytes > 0)
    {
        int64_t free_space = cap - w->ring_used;
        int64_t copy = free_space < bytes ? free_space : bytes;
        int64_t to_end = cap - head;
        int64_t n1 = copy < to_end ? copy : to_end;
        memcpy(w->ring + head, p, (size_t)n1);
        if (copy > n1) memcpy(w->ring, p + n1, (size_t)(copy - n1));
        head = (head + copy) & (cap - 1);
        p += copy;
        bytes -= copy;
        w->ring_used += copy;
        w->ring_head = head;
        if (copy <= 0) { w->frames_dropped++; break; }   /* 满：防死循环  */
    }
}
static int64_t ring_take(SlaWaveOut* w, unsigned char* p, int64_t bytes)
{
    int64_t tail = (w->ring_head - w->ring_used) & (w->ring_cap - 1);
    int64_t want = bytes < w->ring_used ? bytes : w->ring_used;
    int64_t done = want, to_end = w->ring_cap - tail;
    int64_t n1 = want < to_end ? want : to_end;
    memcpy(p, w->ring + tail, (size_t)n1);
    if (want > n1) memcpy(p + n1, w->ring, (size_t)(want - n1));
    w->ring_used -= want;
    return done;
}
/* 扩容用：整环取出线性化到 dst（容量 >= ring_used），复位游标 */
static void ring_take_all_to_linear(SlaWaveOut* w, unsigned char* dst)
{
    int64_t tail = (w->ring_head - w->ring_used) & (w->ring_cap - 1);
    int64_t n = w->ring_used;
    int64_t to_end = w->ring_cap - tail;
    int64_t n1 = n < to_end ? n : to_end;
    memcpy(dst, w->ring + tail, (size_t)n1);
    if (n > n1) memcpy(dst + n1, w->ring, (size_t)(n - n1));
    w->ring_used = 0;
    w->ring_head = 0;
}

/* ---- 服务线程：归还 done 块 + 填新块 ---- */
static DWORD WINAPI wave_thread(void* arg)
{
    SlaWaveOut* w = (SlaWaveOut*)arg;
    for (;;)
    {
        int i;
        EnterCriticalSection(&w->lock);
        if (w->exiting)
        {
            LeaveCriticalSection(&w->lock);
            break;
        }
        /* 1) 归还已完成块（stop/reset 后队列被清，帧数由 stop 端复位，
         *    这里 inflight 块标 DONE 也照常归还但不计数 */
        for (i = 0; i < SLA_WAVE_HDRS; i++)
        {
            WAVEHDR* h = &w->hdrs[i];
            if ((h->dwFlags & WHDR_DONE) && (h->dwFlags & WHDR_PREPARED))
            {
                waveOutUnprepareHeader(w->hwo, h, sizeof(WAVEHDR));
                memset(h, 0, sizeof(WAVEHDR));
                w->inflight--;
            }
        }
        /* 2) 填充空块 */
        if (!w->paused)
        {
            for (i = 0; i < SLA_WAVE_HDRS; i++)
            {
                WAVEHDR* h = &w->hdrs[i];
                int64_t avail_frames = w->ring_used / (int64_t)(2 * w->ch);
                int64_t take_frames;
                if (h->dwFlags & WHDR_PREPARED) continue;
                if (avail_frames == 0) break;
                take_frames = avail_frames < SLA_WAVE_CHUNK ? avail_frames : SLA_WAVE_CHUNK;
                h->lpData = (LPSTR)w->chunks[i];
                h->dwBufferLength = (DWORD)(take_frames * 2 * w->ch);
                ring_take(w, (unsigned char*)h->lpData, h->dwBufferLength);
                if (waveOutPrepareHeader(w->hwo, h, sizeof(WAVEHDR)) == MMSYSERR_NOERROR)
                {
                    if (waveOutWrite(w->hwo, h, sizeof(WAVEHDR)) == MMSYSERR_NOERROR)
                    {
                        w->inflight++;
                        w->frames_played += take_frames;
                    }
                    else
                    {
                        waveOutUnprepareHeader(w->hwo, h, sizeof(WAVEHDR));
                        memset(h, 0, sizeof(WAVEHDR));
                    }
                }
                else
                {
                    memset(h, 0, sizeof(WAVEHDR));
                }
            }
        }
        LeaveCriticalSection(&w->lock);
        Sleep(SLA_WAVE_PUMP);
    }
    return 0;
}

SlaWaveOut* sla_wave_open(int sample_rate, int channels)
{
    SlaWaveOut* w;
    WAVEFORMATEX wfx;
    MMRESULT mmr;
    int i;

    if (sla_wave_device_available() != 1)
    {
        sla_set_error_detail(SLA_E_NO_DEVICE, "wave: no output device");
        return NULL;
    }
    if (sample_rate <= 0 || sample_rate > SLA_MAX_SR ||
        channels <= 0 || channels > SLA_MAX_CH)
    {
        sla_set_error_detail(SLA_E_BAD_PARAM, "wave: sr=%d ch=%d", sample_rate, channels);
        return NULL;
    }

    w = (SlaWaveOut*)calloc(1, sizeof(SlaWaveOut));
    if (!w) { sla_set_error(SLA_E_MEMORY); return NULL; }
    w->sr = sample_rate;
    w->ch = channels;
    w->ring_cap = (int64_t)SLA_RING_INIT * 2;   /* 32 KiB 初始          */
    w->ring = (unsigned char*)malloc((size_t)w->ring_cap);
    if (!w->ring) { free(w); sla_set_error(SLA_E_MEMORY); return NULL; }
    for (i = 0; i < SLA_WAVE_HDRS; i++)
    {
        w->chunks[i] = (unsigned char*)malloc(SLA_WAVE_CHUNK * 2 * (size_t)channels);
        if (!w->chunks[i])
        {
            int j;
            for (j = 0; j < i; j++) free(w->chunks[j]);
            free(w->ring);
            free(w);
            sla_set_error(SLA_E_MEMORY);
            return NULL;
        }
    }
    InitializeCriticalSection(&w->lock);

    memset(&wfx, 0, sizeof(wfx));
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = (WORD)channels;
    wfx.nSamplesPerSec = (DWORD)sample_rate;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = (WORD)(channels * 2);
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

    mmr = waveOutOpen(&w->hwo, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL);
    if (mmr != MMSYSERR_NOERROR)
    {
        sla_set_error_detail(SLA_E_NO_DEVICE, "wave: open mmr=%u", (unsigned)mmr);
        goto fail;
    }
    w->thread = CreateThread(NULL, 0, wave_thread, w, 0, NULL);
    if (!w->thread)
    {
        sla_set_error_detail(SLA_E_MEMORY, "wave: thread");
        goto fail;
    }
    return w;

fail:
    if (w->hwo) waveOutClose(w->hwo);
    for (i = 0; i < SLA_WAVE_HDRS; i++) free(w->chunks[i]);
    DeleteCriticalSection(&w->lock);
    free(w->ring);
    free(w);
    return NULL;
}

int64_t sla_wave_enqueue(SlaWaveOut* w, const short* pcm, int64_t frames)
{
    int64_t bytes;
    if (!w || !pcm || frames <= 0) return 0;
    bytes = frames * 2 * w->ch;
    /* 环满扩容（上限 64 MiB，防失控） */
    EnterCriticalSection(&w->lock);
    if (w->ring_cap - w->ring_used < bytes)
    {
        int64_t new_cap = w->ring_cap;
        while (new_cap - w->ring_used < bytes)
        {
            new_cap *= 2;
            if (new_cap > (int64_t)64 * 1024 * 1024) break;
        }
        if (new_cap <= (int64_t)64 * 1024 * 1024)
        {
            unsigned char* nr = (unsigned char*)malloc((size_t)new_cap);
            if (nr)
            {
                ring_take_all_to_linear(w, nr);   /* 见下：线性重整 */
                free(w->ring);
                w->ring = nr;
                w->ring_cap = new_cap;
            }
        }
    }
    ring_put(w, (const unsigned char*)pcm, bytes);
    w->frames_enqueued += frames;
    LeaveCriticalSection(&w->lock);
    return frames;
}

int sla_wave_pause(SlaWaveOut* w, int paused)
{
    if (!w) return 0;
    EnterCriticalSection(&w->lock);
    w->paused = paused ? 1 : 0;
    LeaveCriticalSection(&w->lock);
    if (paused) waveOutPause(w->hwo);
    else        waveOutRestart(w->hwo);
    return 1;
}

int sla_wave_stop(SlaWaveOut* w)
{
    int i;
    if (!w) return 0;
    EnterCriticalSection(&w->lock);
    waveOutReset(w->hwo);
    for (i = 0; i < SLA_WAVE_HDRS; i++)
    {
        WAVEHDR* h = &w->hdrs[i];
        if (h->dwFlags & WHDR_PREPARED)
        {
            waveOutUnprepareHeader(w->hwo, h, sizeof(WAVEHDR));
            memset(h, 0, sizeof(WAVEHDR));
        }
    }
    w->inflight = 0;
    w->ring_used = 0;
    w->frames_enqueued = 0;
    w->frames_played = 0;
    w->frames_dropped = 0;
    LeaveCriticalSection(&w->lock);
    return 1;
}

int64_t sla_wave_position(SlaWaveOut* w)
{
    int64_t v;
    if (!w) return 0;
    EnterCriticalSection(&w->lock);
    v = w->frames_played;
    LeaveCriticalSection(&w->lock);
    return v;
}

int sla_wave_volume(SlaWaveOut* w, int vol0100)
{
    DWORD v;
    if (!w) return 0;
    if (vol0100 < 0) vol0100 = 0;
    if (vol0100 > 100) vol0100 = 100;
    v = (DWORD)((vol0100 * 0xFFFF) / 100);
    return waveOutSetVolume(w->hwo, v | (v << 16)) == MMSYSERR_NOERROR ? 1 : 0;
}

int64_t sla_wave_buffered(SlaWaveOut* w)
{
    int64_t v;
    if (!w) return 0;
    EnterCriticalSection(&w->lock);
    v = w->ring_used / (2 * w->ch);
    LeaveCriticalSection(&w->lock);
    return v;
}

void sla_wave_close(SlaWaveOut* w)
{
    int i;
    if (!w) return;
    EnterCriticalSection(&w->lock);
    w->exiting = 1;
    LeaveCriticalSection(&w->lock);
    if (w->thread)
    {
        WaitForSingleObject(w->thread, 3000);
        CloseHandle(w->thread);
    }
    if (w->hwo)
    {
        waveOutReset(w->hwo);
        waveOutClose(w->hwo);
    }
    DeleteCriticalSection(&w->lock);
    for (i = 0; i < SLA_WAVE_HDRS; i++) free(w->chunks[i]);
    free(w->ring);
    free(w);
}
