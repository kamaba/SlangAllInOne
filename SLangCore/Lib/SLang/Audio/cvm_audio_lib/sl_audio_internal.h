/* =========================================================================
 * sl_audio_internal.h —— SLangAudio 原生库内部共享头
 *
 * 对应 SL 侧 AudioFfi.sl（@DllStaticImport 静态绑定，sl_audio_lib 注册名）。
 * 槽表 / 粘性错误与 sl_image_internal.h 同款；句柄 = 槽位下标 + 1。
 * 解码输出统一 interleaved S16LE。
 * ========================================================================= */
#ifndef SL_AUDIO_INTERNAL_H
#define SL_AUDIO_INTERNAL_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "vm_sl_audio.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- 容量常量（SL 层测试断言依赖，勿随意缩水） ---- */
#define SLA_MAX_DEC     32      /* 整段解码句柄槽         */
#define SLA_MAX_STREAM  16      /* 流式句柄槽             */
#define SLA_MAX_PLAYER  8       /* 播放器句柄槽           */

#define SLA_MAX_SR      768000  /* 采样率上限             */
#define SLA_MAX_CH      8       /* 声道数上限             */
#define SLA_MAX_FRAMES  (1 << 28) /* 单 dec 帧数上限 ~2.68亿 */
#define SLA_RING_INIT   (1 << 14) /* 流式输入环初始 16 KiB */

/* ---- 共享诊断（sl_audio.c 定义） ---- */
void sla_set_error(int err);
void sla_set_error_detail(int err, const char* fmt, ...);
int  sla_last_error_is_set(void);   /* 粘性错误非零时 1（SLA_OK=0 未设） */

/* =========================================================================
 *                      Codec 后端内部接口
 * =========================================================================
 * 每个"打开源"函数从字节块解出全部 PCM；流式后端逐段消费。
 * PCM 输出 = short* interleaved（帧 = channels 个 int16）。
 */

/* ---- Codec/sl_audio_wav.c ---- */
/* RIFF 头嗅探：WAV 返回 1。 */
int  sla_wav_is_wav(const unsigned char* p, int64_t size);
/* 解析 RIFF 头（容许 fmt 在 data 之后）；成功返回 1 并填 sr/ch/bits/data_off/data_size。 */
int  sla_wav_parse_header(const unsigned char* p, int64_t size,
                           int* sr, int* ch, int* bits, int* is_float,
                           int64_t* data_off, int64_t* data_size);
/* WAV 字节块 -> S16 堆块（调用方 free）。返回帧数（<=0 失败）。 */
int64_t sla_wav_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, short** out_pcm);
/* 裸 PCM 块 -> S16（u8/f32/s16 转换；零拷贝语义=新块）。返回帧数。 */
int64_t sla_wav_pcm_to_i16(const unsigned char* p, int64_t size, int src_fmt,
                            int* sr_hint, int* ch_hint, short** out_pcm);

/* ---- Codec/sl_audio_mp3.c（minimp3 唯一 IMPLEMENTATION 编译点） ---- */
/* MP3/ID3 嗅探：返回 1。 */
int  sla_mp3_is_mp3(const unsigned char* p, int64_t size);
/* 整段 MP3 -> S16 堆块。返回帧数。 */
int64_t sla_mp3_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, short** out_pcm);
/* 流式状态：new 建实例；feed 追加输入；read 解出帧；free 释放。 */
void* sla_mp3_stream_new(void);
int64_t sla_mp3_stream_feed(void** st, const unsigned char* p, int64_t size);
int64_t sla_mp3_stream_read(void* st, short* dst, int64_t cap_frames,
                             int* sr, int* ch, int* fmt);
void   sla_mp3_stream_free(void* st);

/* ---- Codec/sl_audio_mp4.c（minimp4 唯一 IMPLEMENTATION 编译点） ---- */
/* ftyp/moov 嗅探：返回 1。 */
int  sla_mp4_is_mp4(const unsigned char* p, int64_t size);
/* 整段 MP4 音轨 -> S16 堆块（音轨按 handler=='soun' 选择）。
 * src_fmt 出参 SLA_FMT_MP4_PCM/MP4_MP3/MP4_AAC。返回帧数。 */
int64_t sla_mp4_decode_all(const unsigned char* p, int64_t size,
                            int* sr, int* ch, int* src_fmt, short** out_pcm);
/* 仅解析头信息（probe）。返回 1 成功。 */
int  sla_mp4_probe(const unsigned char* p, int64_t size,
                   int* sr, int* ch, int* bits, int64_t* frames, int* src_fmt);

/* ---- Codec/sl_audio_mf.c（Media Foundation AAC MFT，系统组件） ---- */
/* MFT 句柄 = void*。raw 模式：asc 指向 AudioSpecificConfig（可 NULL=用
 * adts 模式，payload_adts=1）。失败返回 NULL。
 * 消费型接口：push 解码追加内部 pending（S16），take 取走前段。 */
void* sla_mf_aac_open(int sample_rate, int channels,
                      const unsigned char* asc, int asc_bytes,
                      int payload_adts);
/* 送入一帧（ADTS 模式含完整 ADTS 帧；raw 模式纯 AAC 裸帧）。
 * 返回 1 成功（0=失败，原因见 last_error）。 */
int   sla_mf_aac_push(void* mft, const unsigned char* frame, int frame_bytes);
/* 从 pending 取走前 cap_frames 帧拷到 dst（interleaved S16）。
 * 返回实际帧数。 */
int64_t sla_mf_aac_take(void* mft, short* dst, int64_t cap_frames);
/* 冲刷尾部（PCE/CPE 排空 -> pending）。返回 1。 */
int   sla_mf_aac_drain(void* mft);
void  sla_mf_aac_close(void* mft);
int   sla_mf_available(void);       /* 系统有 AAC MFT：1=有            */

/* ---- Codec/sl_audio_wave.c（waveOut 播放内核） ---- */
typedef struct SlaWaveOut SlaWaveOut;
/* 打开设备并启动服务线程。sr/ch 固定；失败返回 NULL（原因见 last_error）。 */
SlaWaveOut* sla_wave_open(int sample_rate, int channels);
int64_t sla_wave_enqueue(SlaWaveOut* w, const short* pcm, int64_t frames);
int   sla_wave_pause(SlaWaveOut* w, int paused);
int   sla_wave_stop(SlaWaveOut* w);
int64_t sla_wave_position(SlaWaveOut* w);
int   sla_wave_volume(SlaWaveOut* w, int vol0100);
int64_t sla_wave_buffered(SlaWaveOut* w);
void  sla_wave_close(SlaWaveOut* w);    /* stop + 关设备 + 停线程 + 释放 */
int   sla_wave_device_available(void);

#ifdef __cplusplus
}
#endif

#endif /* SL_AUDIO_INTERNAL_H */
