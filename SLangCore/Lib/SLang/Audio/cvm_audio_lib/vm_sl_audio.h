/* =========================================================================
 * vm_sl_audio.h —— SLangAudio 原生音频库对外契约（v1）
 *
 * sl_audio_lib.dll：音频解码 / 流式 / 播放中间层，本体由三组后端承担：
 *   "wav"   内建 RIFF/PCM 解析（sl_audio_wav.c，纯 C 零依赖）
 *   "mp3"   minimp3 r1.0.3（CC0 公有领域，third_party/minimp3/ 整文件内置，
 *           Codec/sl_audio_mp3.c 单点编译）
 *   "mp4"   minimp4（CC0 公有领域，third_party/minimp4/ 整文件内置，
 *           Codec/sl_audio_mp4.c 单点编译）：解封装 MP4 音轨
 *           （sowt/lpcm PCM 直读、MP3 帧喂 minimp3、AAC 喂 MF）
 *   "mf"    Windows Media Foundation AAC 解码 MFT（系统组件 mfplat，
 *           Codec/sl_audio_mf.c 纯 C lpVtbl，与 Image 模块 WIC 兜底同款）
 *   "wave"  waveOut 播放（系统 winmm，Codec/sl_audio_wave.c 内部线程
 *           + 环形缓冲，零外部依赖）
 *
 * 约定（与 vm_sl_render.h / vm_sl_image.h 一致）：
 *   - 句柄均为 1 起始非 0 值（0 = 无效）；
 *   - 返回 int 的状态函数：1 = 成功，0 = 失败（SL 侧 sig 用 ->bool 直取）；
 *   - 失败原因经 sla_last_error()（粘性：每次原生入口先清零）+
 *     sla_error_string() / sla_error_detail() 取得；
 *   - PCM 契约：恒 interleaved S16LE（playback / stream / decode 输出统一），
 *     采样率 / 声道数保持源值；
 *   - FFI 参数上限 6（SL_FFI_MAX_ARGS），新增函数签名均不超过 6 参。
 *
 * 播放线程安全：所有 sla_player_* 可在任意线程调用（内部锁保护环形
 * 缓冲）；播放线程由库自持（每 player 1 条 waveOut 服务线程）。
 * ========================================================================= */
#ifndef VM_SL_AUDIO_H
#define VM_SL_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLA_API __declspec(dllexport)
#else
#  define SLA_API
#endif

/* ---- 错误码（Audio.AudioErrorCode 语义对齐，负值与 slr_/sli_ 风格一致）---- */
enum
{
    SLA_OK                = 0,
    SLA_E_NOT_INITIALIZED = -1,  /* 库未初始化                    */
    SLA_E_BAD_PARAM       = -2,  /* 参数非法（空指针/尺寸<=0）    */
    SLA_E_BAD_HANDLE      = -3,  /* 无效句柄                      */
    SLA_E_MEMORY          = -4,  /* 分配失败                      */
    SLA_E_LIMIT           = -5,  /* 句柄槽位耗尽                  */
    SLA_E_UNSUPPORTED     = -6,  /* 格式本库不支持                */
    SLA_E_DECODE          = -7,  /* 解码失败（数据损坏/截断）     */
    SLA_E_IO              = -8,  /* 文件读写失败                  */
    SLA_E_NO_DEVICE       = -9,  /* 无音频输出设备                */
    SLA_E_NO_DATA         = -10  /* 流内数据不足（非错误，重试）  */
};

/* ---- 音频源格式 id（sla_*_source_format 出参；勿与 EAudioFormat 混用）---- */
enum
{
    SLA_FMT_UNKNOWN  = 0,
    SLA_FMT_WAV      = 1,   /* RIFF/PCM 或 IEEE float WAV            */
    SLA_FMT_PCM_S16  = 2,   /* 裸 PCM：interleaved S16LE             */
    SLA_FMT_PCM_U8   = 3,   /* 裸 PCM：无符号 8 位，零点 128         */
    SLA_FMT_PCM_F32  = 4,   /* 裸 PCM：interleaved IEEE Float32      */
    SLA_FMT_MP3      = 5,   /* 裸 MP3 帧流（含 ID3 头）              */
    SLA_FMT_AAC_ADTS = 6,   /* AAC ADTS 裸流                         */
    SLA_FMT_MP4_PCM  = 7,   /* MP4 容器 PCM 音轨（sowt/lpcm）         */
    SLA_FMT_MP4_MP3  = 8,   /* MP4 容器 MP3 音轨                      */
    SLA_FMT_MP4_AAC  = 9,   /* MP4 容器 AAC 音轨（经 MF 解码）        */
    SLA_FMT_MP4      = 10   /* MP4 容器（仅嗅探/hint 中间值，src 出参
                                 用 MP4_PCM/MP4_MP3/MP4_AAC 细分）   */
};

/* fmt_hint（sla_decode_* / sla_stream_create 入参）：
 * 0 = 自动嗅探（RIFF/ID3/MPEG 同步字/ftyp）；
 * SLA_FMT_PCM_S16 / SLA_FMT_PCM_U8 / SLA_FMT_PCM_F32 / SLA_FMT_MP3 /
 * SLA_FMT_AAC_ADTS 强制裸流格式；容器格式（WAV/MP4）仅自动嗅探。 */
#define SLA_HINT_AUTO 0

/* ---- 探测出参块（sla_probe_* 的 out_ptr，6 x int32 = 24 字节） ----
 * [0] srcFormat(SLA_FMT_*)  [1] sampleRate  [2] channels  [3] bitsPerSample
 * [4] frameCountLo          [5] frameCountHi（帧数 = lo + hi*2^32；未知 = 0）
 */
#define SLA_PROBE_OUT_BYTES 24

/* ================= 生命周期 / 诊断 ================= */
SLA_API int         sla_init(void);            /* 幂等；返回 1=已就绪   */
SLA_API int         sla_uninit(void);
SLA_API int         sla_last_error(void);
SLA_API const char* sla_error_string(int err);
SLA_API const char* sla_error_detail(void);
SLA_API const char* sla_version_string(void);
SLA_API const char* sla_backend_list(void);    /* 如 "wav,mp3,mp4,mf,wave" */

/* ================= 探测（不解码 PCM） ================= */
/* 读文件头写探测块。返回 1=成功。path 为 UTF-8。 */
SLA_API int         sla_probe_file(const char* path_utf8, int64_t out_ptr);
SLA_API int         sla_probe_mem(int64_t data_ptr, int64_t size, int64_t out_ptr);

/* ================= 整段解码（dec 句柄，C 侧持有 PCM） ================= */
/* 解码整段 -> interleaved S16（源采样率/声道）。fmt_hint 见 SLA_HINT_*。
 * 返回 dec 句柄（0=失败）。 */
SLA_API int64_t     sla_decode_file(const char* path_utf8, int fmt_hint);
SLA_API int64_t     sla_decode_mem(int64_t data_ptr, int64_t size, int fmt_hint);

SLA_API int         sla_dec_sample_rate(int64_t dec);
SLA_API int         sla_dec_channels(int64_t dec);
SLA_API int         sla_dec_source_format(int64_t dec);   /* SLA_FMT_*     */
SLA_API int64_t     sla_dec_frame_count(int64_t dec);     /* 总帧数        */
/* 拷贝 S16LE PCM 到 dst（cap_frames 为帧数，帧 = channels 个 int16）。
 * 返回实际拷贝帧数（0=cap 为 0 或失败）。 */
SLA_API int64_t     sla_dec_copy_i16(int64_t dec, int64_t dst_ptr, int64_t cap_frames);
SLA_API int         sla_dec_free(int64_t dec);

/* ================= 流式解码（stm 句柄：喂压缩比特流，拉 PCM） =================
 * 用法：create(fmt_hint, sr, ch) -> feed(ptr, size)* -> read_i16(dst, cap)*
 *       -> free。裸 PCM 家族 fmt_hint 必填（无法从数据本身判定位深）；
 *       0 = 自动嗅探（wav / mp3 / adts-aac）。
 * feed 后格式参数才定型（如 MP3 首帧）：sample_rate/channels 在
 * 确定前返回 0。返回 int 的函数：1=成功，0=失败（SLA_E_NO_DATA 属
 * feed 不足，按 0 返回并可用 sla_last_error 区分）。 */
SLA_API int64_t     sla_stream_create(int fmt_hint, int sample_rate, int channels);
SLA_API int64_t     sla_stream_feed(int64_t stm, int64_t data_ptr, int64_t size);  /* 返回消费字节数（0=全缓存未消费或失败） */
SLA_API int64_t     sla_stream_read_i16(int64_t stm, int64_t dst_ptr, int64_t cap_frames); /* 返回产出帧数 */
SLA_API int         sla_stream_sample_rate(int64_t stm);
SLA_API int         sla_stream_channels(int64_t stm);
SLA_API int         sla_stream_source_format(int64_t stm);
SLA_API int64_t     sla_stream_frames_out(int64_t stm);  /* 累计产出帧数   */
SLA_API int         sla_stream_free(int64_t stm);

/* ================= 播放（ply 句柄，waveOut + 库自持线程） =================
 * 队列语义：enqueue 的 S16 块进环形缓冲，waveOut 依序消耗；
 * position = 已通过扬声器输出的帧数；stop 清空队列并复位。 */
SLA_API int         sla_device_available(void);           /* 1=有声卡      */
SLA_API int64_t     sla_player_create(int sample_rate, int channels);
SLA_API int64_t     sla_player_enqueue(int64_t ply, int64_t pcm_ptr, int64_t frames); /* 返回入队帧数 */
SLA_API int         sla_player_pause(int64_t ply, int paused);   /* paused: 1=暂停 0=恢复 */
SLA_API int         sla_player_stop(int64_t ply);
SLA_API int64_t     sla_player_position(int64_t ply);     /* 已播帧数      */
SLA_API int         sla_player_volume(int64_t ply, int vol0100);  /* 0..100 */
SLA_API int64_t     sla_player_buffered(int64_t ply);     /* 队列剩余帧数  */
SLA_API int         sla_player_free(int64_t ply);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_AUDIO_H */
