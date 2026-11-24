/* =========================================================================
 * sl_librosa.h —— librosa 1.0.1 音频分析算法的纯 C 移植（third_party）
 *
 * 上游：librosa/librosa（https://github.com/librosa/librosa），ISC 许可
 *       （等效于 MIT 的宽松许可，允许闭源内部实现）。
 * 本文件为按 librosa 1.0.1 源码逐算法移植的衍生作品，遵循同一 ISC 许可：
 *
 *   ISC License
 *   Copyright (c) 2013--2023 librosa development team.
 *   Copyright (C) 2026 SLangAudio "sl_librosa" port contributors.
 *
 *   Permission to use, copy, modify, and/or distribute this software for any
 *   purpose with or without fee is hereby granted, provided that the above
 *   copyright notice and this permission notice appear in all copies.
 *   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * 移植覆盖（默认参数与 librosa 1.0.1 对齐，逐项见 sl_librosa.c 注释）：
 *   stft / istft          center=True，periodic hann，pad_mode="constant"，
 *                          窗与 FFT 均 double 精度后落 float32（librosa 语义）
 *   mel 滤波器组           Slaney 尺度（htk 可选），norm="slaney"
 *   chroma 滤波器组        base_c=True，octwidth=2，norm=2（列 L2）
 *   estimate_tuning       piptrack（fmin=150/fmax=4000/threshold=0.1）+
 *                          median 门限 + pitch_tuning 直方图（resolution=0.01）
 *   melspectrogram / mfcc  power=2 / DCT-II ortho / power_to_db(top_db=80)
 *   spectral_centroid / bandwidth(p=2) / rolloff(0.85) / flatness
 *   rms / zero_crossing_rate / tempo（onset_strength + 自相关 tempogram +
 *                          log2 正态先验 start_bpm=120/std=1.0/max_tempo=320）
 *   hz<->mel / midi<->hz / hz_to_note / dB 换算
 *
 * 约束：
 *   - n_fft 仅支持 2 的幂，范围 [8, 32768]（内部 radix-2 FFT）；
 *   - 输入为 mono float32（[-1,1] 归一化建议），多维声道由上层抽取；
 *   - 所有输出矩阵 row-major（行=频率/系数轴，列=时间帧轴）；
 *   - stft 复数矩阵存储为 re/im 交错的 float32（元素数 = rows*cols*2）。
 *   - 无外部依赖（仅 libc math），线程安全性：非线程安全（调用方串行）。
 * ========================================================================= */
#ifndef SL_LIBROSA_H
#define SL_LIBROSA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define LR_API
#else
#  define LR_API
#endif

/* ---- 错误码（与 vm_sl_audio.h SLA_E_* 语义对齐，正值=本层新增） ---- */
#define LR_OK            0
#define LR_E_PARAM      -2   /* 参数非法（空指针/尺寸越界/非 2 的幂）    */
#define LR_E_MEMORY     -4   /* 分配失败                                */
#define LR_E_LIMIT      -5   /* 结果规模超上限                          */
#define LR_E_DECODE     -7   /* 内部计算失败（FFT/空数据）              */

/* ---- 容量上限 ---- */
#define LR_MAX_NFFT      32768   /* n_fft 上限（2 的幂）               */
#define LR_MIN_NFFT      8       /* n_fft 下限                          */
#define LR_MAX_NMELS     512     /* mel 通道数上限                      */
#define LR_MAX_ELEMS     (1 << 26) /* 单矩阵 float 元素总数上限           */

/* ---- 生命周期诊断 ---- */
const char* lr_version(void);

/* ---- 单位换算（Slaney 尺度 htk=0 / HTK 尺度 htk=1） ---- */
double lr_hz_to_mel(double hz, int htk);
double lr_mel_to_hz(double mel, int htk);
double lr_hz_to_midi(double hz);
double lr_midi_to_hz(double midi);
/* 写 ASCII 音名（"C#4" 风格，unicode=False）；out_cap >= 8 */
void   lr_hz_to_note(double hz, char* out, int out_cap);
/* dB 换算（amin：power=1e-10 / amplitude=1e-5；标量无 top_db 收敛） */
double lr_power_to_db(double x, double ref);
double lr_db_to_power(double db, double ref);
double lr_amplitude_to_db(double x, double ref);
double lr_db_to_amplitude(double db, double ref);

/* ---- STFT / ISTFT -------------------------------------------------------
 * stft：mono f32 -> 复数矩阵（re/im 交错 f32，rows=1+n_fft/2，cols=1+n/hop）。
 *       center=True：左右各补 n_fft/2 个 0；窗 = periodic hann（double）。
 * istft：复数矩阵 -> 时域 f32。length>0 时输出 length 个样本（librosa
 *       length 语义）；length<=0 时输出 n_fft+hop*(cols-1)-n_fft 个。
 *       窗平方和归一化，除法守卫 tiny(float32)。
 * ------------------------------------------------------------------------ */
int lr_stft(const float* y, int64_t n, int n_fft, int hop,
            float** out_reim, int64_t* out_rows, int64_t* out_cols);
int lr_istft(const float* reim, int64_t rows, int64_t cols,
             int n_fft, int hop, int64_t length,
             float* dst, int64_t cap, int64_t* out_n);

/* ---- 特征（stft 复数矩阵 -> 结果矩阵/向量） ----------------------------
 * 输入 reim 为 lr_stft 输出（rows=1+n_fft/2，cols=帧数），n_fft=2*(rows-1)。
 * 输出矩阵 row-major f32（行数见各函数），内存由 malloc 分配、调用方释放。
 * ------------------------------------------------------------------------ */
int lr_melspectrogram(const float* reim, int64_t rows, int64_t cols,
                      int sr, int n_mels, float** out, int64_t* out_rows);
int lr_mfcc(const float* mel, int64_t mel_rows, int64_t cols, int n_mfcc,
            float** out, int64_t* out_rows);
int lr_chroma(const float* reim, int64_t rows, int64_t cols, int sr,
              float** out, int64_t* out_rows);

/* estimate_tuning（core/pitch.py）：piptrack + median 门限 + 直方图，
 * 返回 [-0.5, 0.5) 的调音偏差（无有效峰值返回 0.0） */
int lr_tuning(const float* reim, int64_t rows, int64_t cols, int sr,
              double* out_tuning);

/* 逐帧向量特征（写入 dst，返回帧数；dst 容量 >= cols） */
int lr_centroid(const float* reim, int64_t rows, int64_t cols, int sr,
                float* dst, int64_t* out_n);
int lr_bandwidth(const float* reim, int64_t rows, int64_t cols, int sr,
                 float* dst, int64_t* out_n);
int lr_rolloff(const float* reim, int64_t rows, int64_t cols, int sr,
               float* dst, int64_t* out_n);
int lr_flatness(const float* reim, int64_t rows, int64_t cols,
                float* dst, int64_t* out_n);

/* ---- 特征（时域 mono -> 向量/BPM） -------------------------------------- */
int lr_rms(const float* y, int64_t n, int frame_len, int hop,
           float* dst, int64_t cap, int64_t* out_n);
int lr_zcr(const float* y, int64_t n, int frame_len, int hop,
           float* dst, int64_t cap, int64_t* out_n);
/* librosa.feature.tempo 等价管线（start_bpm=120/std=1.0/ac_size=8s/
 * max_tempo=320，先验 log2 正态；返回 BPM，失败返回 <0 错误码） */
int lr_tempo(const float* y, int64_t n, int sr, int hop, double* out_bpm);

#ifdef __cplusplus
}
#endif

#endif /* SL_LIBROSA_H */
