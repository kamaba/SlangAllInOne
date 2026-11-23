/* =========================================================================
 * sl_audio_mf_stub_web.c —— Media Foundation AAC MFT 的 wasm 占位实现
 * （2026-11-22）。sl_audio.c 无条件引用 sla_mf_* 符号，但 MF 是 Windows
 * 系统组件（sl_audio_mf.c 不可编入 wasm）——这里提供"恒不可用"语义的
 * 占位：open 返回 NULL / probe 返回 0，AAC 解码路径按既有错误链优雅
 * 降级（SL 侧 lastErrorText 可见），wav/mp3 解码不受影响。
 * ========================================================================= */
#include <stdint.h>

void* sla_mf_aac_open(int sample_rate, int channels,
                      const unsigned char* asc, int asc_bytes,
                      int payload_adts)
{
    (void)sample_rate; (void)channels; (void)asc; (void)asc_bytes; (void)payload_adts;
    return (void*)0;
}

int   sla_mf_aac_push(void* mft, const unsigned char* frame, int frame_bytes)
{
    (void)mft; (void)frame; (void)frame_bytes;
    return 0;
}

int64_t sla_mf_aac_take(void* mft, short* dst, int64_t cap_frames)
{
    (void)mft; (void)dst; (void)cap_frames;
    return 0;
}

int   sla_mf_aac_drain(void* mft)
{
    (void)mft;
    return 0;
}

void  sla_mf_aac_close(void* mft)
{
    (void)mft;
}

int   sla_mf_available(void)
{
    return 0;
}
