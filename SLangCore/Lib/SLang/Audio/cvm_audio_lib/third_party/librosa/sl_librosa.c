/* =========================================================================
 * sl_librosa.c —— librosa 1.0.1 音频分析算法的纯 C 移植（third_party）
 *
 * 逐函数对齐 librosa 1.0.1：
 *   core/spectrum.py    stft / istft / power_to_db
 *   core/convert.py     hz_to_mel / mel_to_hz / midi / octs / fft_frequencies
 *   core/pitch.py       piptrack / estimate_tuning / pitch_tuning
 *   filters.py          mel / chroma / get_window(hann periodic)
 *   feature/spectral.py melspectrogram / mfcc / chroma_stft /
 *                       centroid / bandwidth / rolloff / flatness / rms / zcr
 *   feature/rhythm.py   tempo（onset_strength + tempogram + log2 正态先验）
 * 许可与出处声明见 sl_librosa.h 头部（上游 ISC，衍生作品同许可）。
 *
 * 数值语义（对齐 librosa numpy/numba）：
 *   - stft：periodic hann（double）× 帧（f32→double）→ double FFT → 落 f32；
 *   - 特征累积 double、结果落 f32（librosa f32 BLAS 累积与本实现差异
 *     在 1e-6 相对量级，黄金对照容差 2e-4 覆盖）；
 *   - np.round = banker's rounding；np.median = 偶数个取中间两均值。
 * ========================================================================= */
#include "sl_librosa.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define LR_PI 3.14159265358979323846
#define LR_TINY32  1.1754944e-38     /* np.finfo(f32).tiny   */
#define LR_TINY64  2.2250738585072014e-308 /* np.finfo(f64).tiny */

#if defined(_MSC_VER)
#  define LR_INLINE static
#else
#  define LR_INLINE static inline
#endif

const char* lr_version(void)
{
    return "sl_librosa 1.0.1-port (librosa ISC)";
}

LR_INLINE int lr_is_pow2(int n)
{
    return n > 0 && (n & (n - 1)) == 0;
}

/* np.round：half-to-even */
LR_INLINE double lr_round(double x)
{
    double f = floor(x);
    double diff = x - f;
    if (diff > 0.5) return f + 1.0;
    if (diff < 0.5) return f;
    return ((long long)f % 2 == 0) ? f : f + 1.0;
}

/* periodic hann（scipy get_window("hann", M, fftbins=True)）：
 * w[n] = 0.5 - 0.5*cos(2*pi*n/M)；M<=1 时恒 1 */
static void lr_hann(double* w, int m)
{
    int i;
    if (m <= 1)
    {
        if (m == 1) w[0] = 1.0;
        return;
    }
    for (i = 0; i < m; i++)
    {
        w[i] = 0.5 - 0.5 * cos(2.0 * LR_PI * (double)i / (double)m);
    }
}

/* 原地 radix-2 FFT（n 为 2 的幂；inverse=1 为逆变换，已除以 n） */
static void lr_fft(double* re, double* im, int n, int inverse)
{
    int i, j, len;
    double t;
    for (i = 1, j = 0; i < n; i++)
    {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j)
        {
            t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }
    for (len = 2; len <= n; len <<= 1)
    {
        double ang = (inverse ? 2.0 : -2.0) * LR_PI / (double)len;
        double wr = cos(ang), wi = sin(ang);
        for (i = 0; i < n; i += len)
        {
            double cr = 1.0, ci = 0.0;
            int step = len >> 1;
            for (j = 0; j < step; j++)
            {
                int a = i + j, b = i + j + step;
                double tr = re[b] * cr - im[b] * ci;
                double ti = re[b] * ci + im[b] * cr;
                re[b] = re[a] - tr; im[b] = im[a] - ti;
                re[a] += tr;        im[a] += ti;
                t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
            }
        }
    }
    if (inverse)
    {
        double inv = 1.0 / (double)n;
        for (i = 0; i < n; i++) { re[i] *= inv; im[i] *= inv; }
    }
}

LR_INLINE int lr_next_pow2(int n)
{
    int p = 1;
    while (p < n) p <<= 1;
    return p;
}

/* ================= 单位换算（core/convert.py） ================= */

/* Slaney：f_sp=200/3，min_log_hz=1000，min_log_mel=15，logstep=ln(6.4)/27 */
double lr_hz_to_mel(double hz, int htk)
{
    if (htk) return 2595.0 * log10(1.0 + hz / 700.0);
    if (hz < 1000.0) return hz / (200.0 / 3.0);
    return 15.0 + log(hz / 1000.0) / (log(6.4) / 27.0);
}

double lr_mel_to_hz(double mel, int htk)
{
    if (htk) return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
    if (mel < 15.0) return (200.0 / 3.0) * mel;
    return 1000.0 * exp((log(6.4) / 27.0) * (mel - 15.0));
}

double lr_hz_to_midi(double hz)
{
    return 12.0 * (log2(hz) - log2(440.0)) + 69.0;
}

double lr_midi_to_hz(double midi)
{
    return 440.0 * pow(2.0, (midi - 69.0) / 12.0);
}

/* midi_to_note(unicode=False, octave=True)：names[round-half-even(midi)%12]
 * + (int(note_num/12)-1)；非有限值返回空串 */
void lr_hz_to_note(double hz, char* out, int out_cap)
{
    static const char* names[12] = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" };
    double midi;
    long long note_num, octave;
    if (!out || out_cap < 8) return;
    if (!(hz > 0.0) || !(hz < 1e12))
    {
        out[0] = '\0';
        return;
    }
    midi = lr_hz_to_midi(hz);
    note_num = (long long)lr_round(midi);
    octave = note_num / 12 - 1;    /* C 向 0 截断 */
    snprintf(out, (size_t)out_cap, "%s%lld",
             names[((int)(note_num % 12) + 12) % 12], octave);
}

double lr_power_to_db(double x, double ref)
{
    return 10.0 * log10(fmax(1e-10, fabs(x)))
         - 10.0 * log10(fmax(1e-10, fabs(ref)));
}

double lr_db_to_power(double db, double ref)
{
    return ref * pow(10.0, db * 0.1);
}

double lr_amplitude_to_db(double x, double ref)
{
    return 20.0 * log10(fmax(1e-5, fabs(x)))
         - 20.0 * log10(fmax(1e-5, fabs(ref)));
}

double lr_db_to_amplitude(double db, double ref)
{
    return ref * pow(10.0, db / 20.0);
}

/* fft_frequencies：arange(0,1+n_fft/2)*(sr/n_fft)（商先算，f64 值域） */
LR_INLINE double lr_fft_freq(int k, int sr, int n_fft)
{
    return (double)k * ((double)sr / (double)n_fft);
}

/* hz_to_octs：octs = log2(f / (440*2^(tuning/bpo)/16)) */
LR_INLINE double lr_hz_to_octs(double f, double tuning, int bins_per_octave)
{
    double a440 = 440.0 * pow(2.0, tuning / (double)bins_per_octave);
    return log2(f / (a440 / 16.0));
}

/* ================= mel 滤波器组（filters.mel） ================= */

/* out：n_mels x (1+n_fft/2) row-major f32；norm="slaney" */
static int lr_mel_filterbank(int sr, int n_fft, int n_mels, int htk, float* out)
{
    int bins = 1 + n_fft / 2;
    double* mel_f;
    double min_mel, max_mel, span;
    int i, k;
    if (!out || n_mels < 2 || n_mels > LR_MAX_NMELS) return LR_E_PARAM;
    mel_f = (double*)malloc(sizeof(double) * (size_t)(n_mels + 2));
    if (!mel_f) return LR_E_MEMORY;

    min_mel = lr_hz_to_mel(0.0, htk);
    max_mel = lr_hz_to_mel(0.5 * (double)sr, htk);
    span = max_mel - min_mel;
    for (i = 0; i < n_mels + 2; i++)
    {
        mel_f[i] = lr_mel_to_hz(min_mel + span * (double)i / (double)(n_mels + 1), htk);
    }

    for (i = 0; i < n_mels; i++)
    {
        double fd0 = mel_f[i + 1] - mel_f[i];
        double fd1 = mel_f[i + 2] - mel_f[i + 1];
        double enorm = 2.0 / (mel_f[i + 2] - mel_f[i]);
        for (k = 0; k < bins; k++)
        {
            double f = lr_fft_freq(k, sr, n_fft);
            double lower = (f - mel_f[i]) / fd0;
            double upper = (mel_f[i + 2] - f) / fd1;
            double v = lower < upper ? lower : upper;
            if (v < 0.0) v = 0.0;
            out[(int64_t)i * bins + k] = (float)(v * enorm);
        }
    }
    free(mel_f);
    return LR_OK;
}

/* ================= chroma 滤波器组（filters.chroma） ================= */

/* out：n_chroma x (1+n_fft/2) row-major f32。
 * 构造顺序（librosa filters.py:327-365）：
 *   frqbins[0]=占位（frqbins[1]-1.5*n_chroma），frqbins[i>=1]=
 *     n_chroma*hz_to_octs(i*sr/n_fft)
 *   binwidthbins[i]=max(frqbins[i+1]-frqbins[i],1)
 *   wts = exp(-0.5*(2*D/binwidth)^2)，D=(frqbins[i]-c 折回 [-n/2,n/2))
 *   → 列 L2 归一化（axis=0，f64 tiny 守卫）
 *   → 列乘 octave 高斯权重（ctroct=5, octwidth=2）
 *   → base_c：行 roll(-3*(n_chroma//12)) */
static int lr_chroma_filterbank(int sr, int n_fft, int n_chroma, double tuning,
                                double ctroct, double octwidth, int base_c, float* out)
{
    int bins = 1 + n_fft / 2;
    double* frqbins;
    int i, c, roll;
    float* tmp;
    double n_chroma2;
    if (!out || n_chroma < 2 || n_chroma > 36) return LR_E_PARAM;
    frqbins = (double*)malloc(sizeof(double) * (size_t)(bins + 1));
    if (!frqbins) return LR_E_MEMORY;

    for (i = 0; i <= bins; i++)
    {
        double f = (double)i * (double)sr / (double)n_fft;   /* bin i 频率 */
        frqbins[i] = (double)n_chroma * lr_hz_to_octs(f, tuning, n_chroma);
    }
    frqbins[0] = frqbins[1] - 1.5 * (double)n_chroma;        /* 0Hz 占位 */

    n_chroma2 = lr_round((double)n_chroma / 2.0);

    for (i = 0; i < bins; i++)
    {
        double bw = (i < bins - 1) ? (frqbins[i + 1] - frqbins[i]) : 0.0;
        if (bw < 1.0) bw = 1.0;
        for (c = 0; c < n_chroma; c++)
        {
            double D = frqbins[i] - (double)c;
            double w;
            D = fmod(D + n_chroma2 + 10.0 * (double)n_chroma, (double)n_chroma);
            if (D < 0.0) D += (double)n_chroma;   /* np.remainder 非负 */
            D -= n_chroma2;
            w = exp(-0.5 * pow(2.0 * D / bw, 2.0));
            out[(int64_t)c * bins + i] = (float)w;
        }
    }

    /* 列 L2 归一化（先于 octave 权重；f64 tiny 守卫：小于则保持原值） */
    for (i = 0; i < bins; i++)
    {
        double s = 0.0;
        for (c = 0; c < n_chroma; c++)
        {
            double v = (double)out[(int64_t)c * bins + i];
            s += v * v;
        }
        s = sqrt(s);
        if (s < LR_TINY64) continue;
        for (c = 0; c < n_chroma; c++)
        {
            out[(int64_t)c * bins + i] =
                (float)((double)out[(int64_t)c * bins + i] / s);
        }
    }

    /* octave 高斯权重（norm 之后乘） */
    if (octwidth > 0.0)
    {
        for (i = 0; i < bins; i++)
        {
            double w = exp(-0.5 * pow((frqbins[i] / (double)n_chroma - ctroct)
                                     / octwidth, 2.0));
            for (c = 0; c < n_chroma; c++)
            {
                out[(int64_t)c * bins + i] =
                    (float)((double)out[(int64_t)c * bins + i] * w);
            }
        }
    }

    /* base_c：new[c] = old[(c+3*(n_chroma//12)) % n_chroma] */
    if (base_c && n_chroma >= 12)
    {
        roll = 3 * (n_chroma / 12);
        tmp = (float*)malloc(sizeof(float) * (size_t)n_chroma);
        if (!tmp) { free(frqbins); return LR_E_MEMORY; }
        for (i = 0; i < bins; i++)
        {
            for (c = 0; c < n_chroma; c++) tmp[c] = out[(int64_t)c * bins + i];
            for (c = 0; c < n_chroma; c++)
            {
                out[(int64_t)c * bins + i] = tmp[(c + roll) % n_chroma];
            }
        }
        free(tmp);
    }

    free(frqbins);
    return LR_OK;
}

/* ================= STFT / ISTFT（core/spectrum.py） ================= */

/* center=True：帧 t 覆盖原信号 [t*hop-half, t*hop-half+n_fft)，
 * 帧数 = 1 + n/hop；pad_mode="constant"（补 0） */
int lr_stft(const float* y, int64_t n, int n_fft, int hop,
            float** out_reim, int64_t* out_rows, int64_t* out_cols)
{
    int64_t rows, cols, t, k, idx;
    int half;
    double* win;
    double* re;
    double* im;
    float* out;
    if (!y || n <= 0 || !out_reim || !out_rows || !out_cols) return LR_E_PARAM;
    if (!lr_is_pow2(n_fft) || n_fft < LR_MIN_NFFT || n_fft > LR_MAX_NFFT) return LR_E_PARAM;
    if (hop < 1 || hop > n_fft) return LR_E_PARAM;
    if (n > LR_MAX_ELEMS) return LR_E_LIMIT;

    rows = 1 + n_fft / 2;
    cols = 1 + n / hop;
    if (rows * cols * 2 > LR_MAX_ELEMS) return LR_E_LIMIT;

    out = (float*)malloc(sizeof(float) * (size_t)(rows * cols * 2));
    win = (double*)malloc(sizeof(double) * (size_t)n_fft);
    re = (double*)malloc(sizeof(double) * (size_t)n_fft);
    im = (double*)malloc(sizeof(double) * (size_t)n_fft);
    if (!out || !win || !re || !im)
    {
        free(out); free(win); free(re); free(im);
        return LR_E_MEMORY;
    }
    lr_hann(win, n_fft);

    half = n_fft / 2;
    for (t = 0; t < cols; t++)
    {
        int64_t base = t * (int64_t)hop;
        for (k = 0; k < n_fft; k++)
        {
            int64_t src = base - half + k;
            double v = (src >= 0 && src < n) ? (double)y[src] : 0.0;
            re[k] = v * win[k];
            im[k] = 0.0;
        }
        lr_fft(re, im, n_fft, 0);
        for (k = 0; k < rows; k++)
        {
            idx = (k * cols + t) * 2;
            out[idx] = (float)re[k];
            out[idx + 1] = (float)im[k];
        }
    }

    free(win); free(re); free(im);
    *out_reim = out;
    *out_rows = rows;
    *out_cols = cols;
    return LR_OK;
}

/* istft：OLA 于 padded（帧位 0,hop,...），输出 y[i]=padded[half+i]/sumsq；
 * length>0：n_frames=min(cols, ceil((length+n_fft)/hop))，输出 length 样本 */
int lr_istft(const float* reim, int64_t rows, int64_t cols,
             int n_fft, int hop, int64_t length,
             float* dst, int64_t cap, int64_t* out_n)
{
    int64_t n_frames, padded_len, n_out, f, k, i, j;
    int half;
    double* win;
    double* win_sq;
    double* re;
    double* im;
    double* y_pad;
    double* sumsq;
    if (!reim || rows < 2 || cols <= 0 || !dst || !out_n) return LR_E_PARAM;
    if (!lr_is_pow2(n_fft) || n_fft < LR_MIN_NFFT || n_fft > LR_MAX_NFFT) return LR_E_PARAM;
    if (rows != 1 + n_fft / 2) return LR_E_PARAM;
    if (hop < 1 || hop > n_fft) return LR_E_PARAM;

    if (length > 0)
    {
        int64_t need = (length + (int64_t)n_fft + hop - 1) / hop;
        n_frames = cols < need ? cols : need;
    }
    else
    {
        n_frames = cols;
    }
    padded_len = (int64_t)n_fft + (int64_t)hop * (n_frames - 1);
    n_out = (length > 0) ? length : (padded_len - (int64_t)n_fft);
    if (n_out > cap) n_out = cap;
    if (n_out < 0) n_out = 0;

    win = (double*)malloc(sizeof(double) * (size_t)n_fft);
    win_sq = (double*)malloc(sizeof(double) * (size_t)n_fft);
    re = (double*)malloc(sizeof(double) * (size_t)n_fft);
    im = (double*)malloc(sizeof(double) * (size_t)n_fft);
    y_pad = (double*)calloc((size_t)(padded_len > 0 ? padded_len : 1), sizeof(double));
    sumsq = (double*)calloc((size_t)(padded_len > 0 ? padded_len : 1), sizeof(double));
    if (!win || !win_sq || !re || !im || !y_pad || !sumsq)
    {
        free(win); free(win_sq); free(re); free(im); free(y_pad); free(sumsq);
        return LR_E_MEMORY;
    }
    lr_hann(win, n_fft);
    for (k = 0; k < n_fft; k++) win_sq[k] = win[k] * win[k];

    half = n_fft / 2;
    for (f = 0; f < n_frames; f++)
    {
        int64_t dst0 = (int64_t)hop * f;
        int64_t lim = (padded_len - dst0 < n_fft) ? padded_len - dst0 : n_fft;
        for (k = 0; k < n_fft; k++)
        {
            int64_t kk = (k <= half) ? k : n_fft - k;
            int64_t idx = (kk * cols + f) * 2;
            re[k] = (double)reim[idx];
            im[k] = (k <= half) ? (double)reim[idx + 1]
                                : -(double)reim[idx + 1];
        }
        lr_fft(re, im, n_fft, 1);
        for (k = 0; k < lim; k++)
        {
            y_pad[dst0 + k] += re[k] * win[k];
            sumsq[dst0 + k] += win_sq[k];
        }
    }

    for (i = 0; i < n_out; i++)
    {
        j = i + half;
        dst[i] = (j < padded_len && sumsq[j] > LR_TINY32)
            ? (float)(y_pad[j] / sumsq[j]) : 0.0f;
    }

    free(win); free(win_sq); free(re); free(im); free(y_pad); free(sumsq);
    *out_n = n_out;
    return LR_OK;
}

/* ================= 内部：|S|^2 功率谱（f32 矩阵） ================= */

static float* lr_power_spec(const float* reim, int64_t rows, int64_t cols)
{
    int64_t k, t;
    float* S = (float*)malloc(sizeof(float) * (size_t)(rows * cols));
    if (!S) return NULL;
    for (t = 0; t < cols; t++)
    {
        for (k = 0; k < rows; k++)
        {
            double re = (double)reim[(k * cols + t) * 2];
            double im = (double)reim[(k * cols + t) * 2 + 1];
            S[k * cols + t] = (float)(re * re + im * im);
        }
    }
    return S;
}

/* ================= melspectrogram（feature/spectral.py） ================= */

int lr_melspectrogram(const float* reim, int64_t rows, int64_t cols,
                      int sr, int n_mels, float** out, int64_t* out_rows)
{
    int n_fft, k;
    int64_t m, t;
    float* W;
    float* S;
    float* M;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0) return LR_E_PARAM;
    if (n_mels < 2 || n_mels > LR_MAX_NMELS) return LR_E_PARAM;
    n_fft = (int)(2 * (rows - 1));
    if (rows * cols > LR_MAX_ELEMS || (int64_t)n_mels * cols > LR_MAX_ELEMS) return LR_E_LIMIT;

    W = (float*)malloc(sizeof(float) * (size_t)((int64_t)n_mels * rows));
    if (!W) return LR_E_MEMORY;
    if (lr_mel_filterbank(sr, n_fft, n_mels, 0, W) != LR_OK)
    {
        free(W);
        return LR_E_PARAM;
    }

    S = lr_power_spec(reim, rows, cols);
    M = (float*)malloc(sizeof(float) * (size_t)((int64_t)n_mels * cols));
    if (!S || !M)
    {
        free(W); free(S); free(M);
        return LR_E_MEMORY;
    }

    for (t = 0; t < cols; t++)
    {
        for (m = 0; m < n_mels; m++)
        {
            double acc = 0.0;
            const float* wrow = W + m * rows;
            for (k = 0; k < rows; k++)
            {
                acc += (double)wrow[k] * (double)S[(int64_t)k * cols + t];
            }
            M[m * cols + t] = (float)acc;
        }
    }

    free(W); free(S);
    *out = M;
    *out_rows = n_mels;
    return LR_OK;
}

/* ================= mfcc（DCT-II ortho + power_to_db top_db=80） ================= */

int lr_mfcc(const float* mel, int64_t mel_rows, int64_t cols, int n_mfcc,
            float** out, int64_t* out_rows)
{
    double* D;
    float* Y;
    int64_t m, t, k;
    double dmax;
    if (!mel || mel_rows < 2 || cols <= 0) return LR_E_PARAM;
    if (n_mfcc < 1 || n_mfcc > 128 || n_mfcc > mel_rows) return LR_E_PARAM;
    if (mel_rows * cols > LR_MAX_ELEMS) return LR_E_LIMIT;

    D = (double*)malloc(sizeof(double) * (size_t)(mel_rows * cols));
    Y = (float*)malloc(sizeof(float) * (size_t)((int64_t)n_mfcc * cols));
    if (!D || !Y) { free(D); free(Y); return LR_E_MEMORY; }

    dmax = -1e300;
    for (m = 0; m < mel_rows * cols; m++)
    {
        D[m] = 10.0 * log10(fmax(1e-10, (double)mel[m]));
        if (D[m] > dmax) dmax = D[m];
    }
    for (m = 0; m < mel_rows * cols; m++)
    {
        if (D[m] < dmax - 80.0) D[m] = dmax - 80.0;
    }

    for (t = 0; t < cols; t++)
    {
        for (k = 0; k < n_mfcc; k++)
        {
            double acc = 0.0;
            for (m = 0; m < mel_rows; m++)
            {
                acc += D[m * cols + t]
                     * cos(LR_PI * (double)k * (2.0 * (double)m + 1.0)
                           / (2.0 * (double)mel_rows));
            }
            if (k == 0) acc *= sqrt(1.0 / (double)mel_rows);
            else        acc *= sqrt(2.0 / (double)mel_rows);
            Y[k * cols + t] = (float)acc;
        }
    }

    free(D);
    *out = Y;
    *out_rows = n_mfcc;
    return LR_OK;
}

/* ================= estimate_tuning（core/pitch.py） ================= */

static int lr_cmp_double(const void* a, const void* b)
{
    double x = *(const double*)a, y = *(const double*)b;
    return (x < y) ? -1 : (x > y) ? 1 : 0;
}

/* np.median：排序后奇取中、偶取中间两均值 */
static double lr_median(double* v, int64_t cnt)
{
    qsort(v, (size_t)cnt, sizeof(double), lr_cmp_double);
    if (cnt % 2 == 1) return v[cnt / 2];
    return 0.5 * (v[cnt / 2 - 1] + v[cnt / 2]);
}

/* piptrack + median 门限 + pitch_tuning 直方图；S 为功率谱 */
static double lr_estimate_tuning(const float* S, int64_t rows, int64_t cols,
                                 int sr, int n_fft)
{
    double* pitches;
    double* mags;
    double* resid;
    int* counts;
    int64_t cap = rows * cols;
    int64_t cnt = 0, i, k, t, rc = 0;
    double fmin = 150.0;
    double fmax = (4000.0 < 0.5 * (double)sr) ? 4000.0 : 0.5 * (double)sr;
    double thr_med = 0.0, tuning = 0.0;
    int best = 0, bin;

    if (cap <= 0) return 0.0;
    pitches = (double*)malloc(sizeof(double) * (size_t)cap);
    mags = (double*)malloc(sizeof(double) * (size_t)cap);
    if (!pitches || !mags) { free(pitches); free(mags); return 0.0; }

    /* piptrack：频段 [fmin,fmax)，localmax + 0.1*逐帧最大值，抛物线插值 */
    for (t = 0; t < cols; t++)
    {
        double frame_max = -1e300;
        const float* sc = S + t;
        for (k = 0; k < rows; k++)
        {
            if ((double)sc[k * cols] > frame_max) frame_max = (double)sc[k * cols];
        }
        for (k = 0; k < rows; k++)
        {
            double fk = lr_fft_freq((int)k, sr, n_fft);
            double s0, sp, sm, a, b, shift;
            if (fk < fmin || fk >= fmax) continue;
            s0 = (double)sc[k * cols];
            {
                double prev = (k > 0) ? (double)sc[(k - 1) * cols] : s0;
                double next = (k + 1 < rows) ? (double)sc[(k + 1) * cols] : s0;
                if (!(s0 > prev && s0 >= next)) continue;   /* localmax（边界钳位） */
            }
            if (!(s0 > 0.1 * frame_max)) continue;
            sp = (k + 1 < rows) ? (double)sc[(k + 1) * cols] : s0;
            sm = (k > 0) ? (double)sc[(k - 1) * cols] : s0;
            a = sp + sm - 2.0 * s0;
            b = 0.5 * (sp - sm);
            shift = (fabs(b) < fabs(a)) ? (-b / a) : 0.0;
            if (cnt >= cap) break;
            pitches[cnt] = ((double)k + shift) * (double)sr / (double)n_fft;
            mags[cnt] = s0 + 0.5 * b * shift;
            cnt++;
        }
    }

    if (cnt > 0)
    {
        /* np.median 不改输入：排序在副本上做，保持 pitches/mags 配对 */
        double* mags_sorted = (double*)malloc(sizeof(double) * (size_t)cnt);
        if (mags_sorted)
        {
            memcpy(mags_sorted, mags, sizeof(double) * (size_t)cnt);
            thr_med = lr_median(mags_sorted, cnt);
            free(mags_sorted);
        }
        resid = (double*)malloc(sizeof(double) * (size_t)cnt);
        if (resid)
        {
            for (i = 0; i < cnt; i++)
            {
                if (pitches[i] > 0.0 && mags[i] >= thr_med)
                {
                    double r = fmod(12.0 * lr_hz_to_octs(pitches[i], 0.0, 12), 1.0);
                    if (r >= 0.5) r -= 1.0;
                    resid[rc++] = r;
                }
            }
            /* pitch_tuning：bins=linspace(-0.5,0.5,101)，取 argmax 左沿 */
            if (rc > 0)
            {
                counts = (int*)calloc(101, sizeof(int));
                if (counts)
                {
                    for (i = 0; i < rc; i++)
                    {
                        if (resid[i] < -0.5 || resid[i] > 0.5) continue;
                        bin = (int)((resid[i] + 0.5) / 0.01);
                        if (bin > 100) bin = 100;
                        counts[bin]++;
                    }
                    for (i = 1; i < 101; i++)
                    {
                        if (counts[i] > counts[best]) best = (int)i;
                    }
                    tuning = -0.5 + 0.01 * (double)best;
                    free(counts);
                }
            }
            free(resid);
        }
    }

    free(pitches); free(mags);
    return tuning;
}

/* ================= chroma_stft（feature/spectral.py） ================= */

int lr_chroma(const float* reim, int64_t rows, int64_t cols, int sr,
              float** out, int64_t* out_rows)
{
    int n_fft, k;
    int64_t c, t;
    float* S;
    float* W;
    float* C;
    double tuning;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0) return LR_E_PARAM;
    n_fft = (int)(2 * (rows - 1));
    if (rows * cols > LR_MAX_ELEMS || 12 * cols > LR_MAX_ELEMS) return LR_E_LIMIT;

    S = lr_power_spec(reim, rows, cols);
    W = (float*)malloc(sizeof(float) * (size_t)(12 * rows));
    C = (float*)malloc(sizeof(float) * (size_t)(12 * cols));
    if (!S || !W || !C) { free(S); free(W); free(C); return LR_E_MEMORY; }

    tuning = lr_estimate_tuning(S, rows, cols, sr, n_fft);
    if (lr_chroma_filterbank(sr, n_fft, 12, tuning, 5.0, 2.0, 1, W) != LR_OK)
    {
        free(S); free(W); free(C);
        return LR_E_PARAM;
    }

    for (t = 0; t < cols; t++)
    {
        double mx = 0.0;
        for (c = 0; c < 12; c++)
        {
            double acc = 0.0;
            for (k = 0; k < rows; k++)
            {
                acc += (double)W[c * rows + k] * (double)S[k * cols + t];
            }
            C[c * cols + t] = (float)acc;
        }
        /* normalize(norm=inf, axis=-2)：逐帧除以列最大值（<tiny 保持） */
        for (c = 0; c < 12; c++)
        {
            double v = fabs((double)C[c * cols + t]);
            if (v > mx) mx = v;
        }
        if (mx >= LR_TINY32)
        {
            for (c = 0; c < 12; c++)
            {
                C[c * cols + t] = (float)((double)C[c * cols + t] / mx);
            }
        }
    }

    free(S); free(W);
    *out = C;
    *out_rows = 12;
    return LR_OK;
}

/* ================= 调音估计（公开包装） ================= */

int lr_tuning(const float* reim, int64_t rows, int64_t cols, int sr,
              double* out_tuning)
{
    float* S;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0 || !out_tuning) return LR_E_PARAM;
    S = lr_power_spec(reim, rows, cols);
    if (!S) return LR_E_MEMORY;
    *out_tuning = lr_estimate_tuning(S, rows, cols, sr, (int)(2 * (rows - 1)));
    free(S);
    return LR_OK;
}

/* ================= 谱特征向量（feature/spectral.py） ================= */

static void lr_mag_spec(const float* reim, int64_t rows, int64_t cols, double* M)
{
    int64_t k, t;
    for (t = 0; t < cols; t++)
    {
        for (k = 0; k < rows; k++)
        {
            double re = (double)reim[(k * cols + t) * 2];
            double im = (double)reim[(k * cols + t) * 2 + 1];
            M[k * cols + t] = sqrt(re * re + im * im);
        }
    }
}

int lr_centroid(const float* reim, int64_t rows, int64_t cols, int sr,
                float* dst, int64_t* out_n)
{
    int n_fft;
    double* M;
    int64_t k, t;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0 || !dst || !out_n) return LR_E_PARAM;
    n_fft = (int)(2 * (rows - 1));
    if (cols > LR_MAX_ELEMS) return LR_E_LIMIT;
    M = (double*)malloc(sizeof(double) * (size_t)(rows * cols));
    if (!M) return LR_E_MEMORY;
    lr_mag_spec(reim, rows, cols, M);
    for (t = 0; t < cols; t++)
    {
        double num = 0.0, den = 0.0;
        for (k = 0; k < rows; k++)
        {
            num += lr_fft_freq((int)k, sr, n_fft) * M[k * cols + t];
            den += M[k * cols + t];
        }
        dst[t] = (float)(num / (den > 0.0 ? den : 1.0));
    }
    free(M);
    *out_n = cols;
    return LR_OK;
}

int lr_bandwidth(const float* reim, int64_t rows, int64_t cols, int sr,
                 float* dst, int64_t* out_n)
{
    int n_fft;
    double* M;
    int64_t k, t;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0 || !dst || !out_n) return LR_E_PARAM;
    n_fft = (int)(2 * (rows - 1));
    if (cols > LR_MAX_ELEMS) return LR_E_LIMIT;
    M = (double*)malloc(sizeof(double) * (size_t)(rows * cols));
    if (!M) return LR_E_MEMORY;
    lr_mag_spec(reim, rows, cols, M);
    for (t = 0; t < cols; t++)
    {
        double den = 0.0, cen = 0.0, acc = 0.0;
        for (k = 0; k < rows; k++) den += M[k * cols + t];
        den = (den > 0.0) ? den : 1.0;
        for (k = 0; k < rows; k++)
        {
            cen += lr_fft_freq((int)k, sr, n_fft) * M[k * cols + t];
        }
        cen /= den;
        for (k = 0; k < rows; k++)
        {
            double d = lr_fft_freq((int)k, sr, n_fft) - cen;
            if (d < 0.0) d = -d;
            acc += (M[k * cols + t] / den) * d * d;   /* p=2 */
        }
        dst[t] = (float)sqrt(acc);
    }
    free(M);
    *out_n = cols;
    return LR_OK;
}

int lr_rolloff(const float* reim, int64_t rows, int64_t cols, int sr,
               float* dst, int64_t* out_n)
{
    int n_fft;
    double* M;
    int64_t k, t, kk;
    if (!reim || rows < 2 || cols <= 0 || sr <= 0 || !dst || !out_n) return LR_E_PARAM;
    n_fft = (int)(2 * (rows - 1));
    if (cols > LR_MAX_ELEMS) return LR_E_LIMIT;
    M = (double*)malloc(sizeof(double) * (size_t)(rows * cols));
    if (!M) return LR_E_MEMORY;
    lr_mag_spec(reim, rows, cols, M);
    for (t = 0; t < cols; t++)
    {
        double cum = 0.0, total = 0.0;
        kk = rows - 1;
        for (k = 0; k < rows; k++) total += M[k * cols + t];
        for (k = 0; k < rows; k++)
        {
            cum += M[k * cols + t];
            if (cum >= 0.85 * total)   /* 首个 >= 0.85*总能量 bin */
            {
                kk = k;
                break;
            }
        }
        dst[t] = (float)lr_fft_freq((int)kk, sr, n_fft);
    }
    free(M);
    *out_n = cols;
    return LR_OK;
}

int lr_flatness(const float* reim, int64_t rows, int64_t cols,
                float* dst, int64_t* out_n)
{
    double* M;
    int64_t k, t;
    if (!reim || rows < 2 || cols <= 0 || !dst || !out_n) return LR_E_PARAM;
    if (cols > LR_MAX_ELEMS) return LR_E_LIMIT;
    M = (double*)malloc(sizeof(double) * (size_t)(rows * cols));
    if (!M) return LR_E_MEMORY;
    lr_mag_spec(reim, rows, cols, M);
    for (t = 0; t < cols; t++)
    {
        double lg = 0.0, am = 0.0;
        for (k = 0; k < rows; k++)
        {
            double st = M[k * cols + t] * M[k * cols + t];  /* max(amin, S**2) */
            if (st < 1e-10) st = 1e-10;
            lg += log(st);
            am += st;
        }
        lg /= (double)rows;
        am /= (double)rows;
        dst[t] = (float)(exp(lg) / am);
    }
    free(M);
    *out_n = cols;
    return LR_OK;
}

/* ================= rms / zcr（feature/spectral.py） ================= */

int lr_rms(const float* y, int64_t n, int frame_len, int hop,
           float* dst, int64_t cap, int64_t* out_n)
{
    int64_t cols, t, base;
    int half, i;
    if (!y || n <= 0 || !dst || !out_n) return LR_E_PARAM;
    if (frame_len < 8 || frame_len > (1 << 16)) return LR_E_PARAM;
    if (hop < 1 || hop > frame_len) return LR_E_PARAM;
    cols = 1 + n / hop;                       /* center=True（补 0） */
    if (cols > cap) return LR_E_PARAM;
    half = frame_len / 2;
    for (t = 0; t < cols; t++)
    {
        double acc = 0.0;
        base = t * (int64_t)hop - half;
        for (i = 0; i < frame_len; i++)
        {
            int64_t src = base + i;
            double v = (src >= 0 && src < n) ? (double)y[src] : 0.0;
            acc += v * v;
        }
        dst[t] = (float)sqrt(acc / (double)frame_len);
    }
    *out_n = cols;
    return LR_OK;
}

/* zcr：center=edge 复制补；帧内位置 0 恒不计（pad=False）；
 * threshold=1e-10，signbit 比较 */
int lr_zcr(const float* y, int64_t n, int frame_len, int hop,
           float* dst, int64_t cap, int64_t* out_n)
{
    int64_t cols, t, base, cross;
    int half, i;
    if (!y || n <= 0 || !dst || !out_n) return LR_E_PARAM;
    if (frame_len < 8 || frame_len > (1 << 16)) return LR_E_PARAM;
    if (hop < 1 || hop > frame_len) return LR_E_PARAM;
    cols = 1 + n / hop;
    if (cols > cap) return LR_E_PARAM;
    half = frame_len / 2;
    for (t = 0; t < cols; t++)
    {
        cross = 0;
        base = t * (int64_t)hop - half;
        for (i = 1; i < frame_len; i++)
        {
            int64_t s0i = base + i, s1i = base + i - 1;
            double x0 = (s0i >= 0 && s0i < n) ? (double)y[s0i]
                      : (double)y[(s0i < 0) ? 0 : (n - 1)];
            double x1 = (s1i >= 0 && s1i < n) ? (double)y[s1i]
                      : (double)y[(s1i < 0) ? 0 : (n - 1)];
            if (x0 >= -1e-10 && x0 <= 1e-10) x0 = 0.0;
            if (x1 >= -1e-10 && x1 <= 1e-10) x1 = 0.0;
            if ((x0 < 0.0) != (x1 < 0.0)) cross++;
        }
        dst[t] = (float)((double)cross / (double)frame_len);
    }
    *out_n = cols;
    return LR_OK;
}

/* ================= tempo（feature/rhythm.py） ================= */

int lr_tempo(const float* y, int64_t n, int sr, int hop, double* out_bpm)
{
    const int n_fft = 2048, n_mels = 128;
    int64_t rows = 0, cols = 0, t, i, lag;
    int win, fft_n, best = -1;
    float* S = NULL;
    float* M = NULL;
    double* db = NULL;
    double* onset = NULL;
    double* shifted = NULL;
    double* padded_on = NULL;
    double* acc = NULL;
    double* hann = NULL;
    double* re = NULL;
    double* im = NULL;
    double best_score = -1e300, bpm = 0.0;
    int rc;

    if (!y || n <= 0 || sr <= 0 || !out_bpm) return LR_E_PARAM;
    if (hop < 1 || hop > n_fft) return LR_E_PARAM;
    if (n > LR_MAX_ELEMS) return LR_E_LIMIT;

    /* 1) onset_strength：mel 功率谱 -> dB(top_db=80) -> 一阶差分半波整流
     *    -> 频率轴均值 -> 前补 3 个 0 -> 截到 cols 帧 */
    rc = lr_stft(y, n, n_fft, hop, &S, &rows, &cols);
    if (rc != LR_OK) return rc;
    rc = lr_melspectrogram(S, rows, cols, sr, n_mels, &M, &rows);
    free(S);
    if (rc != LR_OK) return rc;

    db = (double*)malloc(sizeof(double) * (size_t)((int64_t)n_mels * cols));
    onset = (double*)calloc((size_t)cols, sizeof(double));
    shifted = (double*)calloc((size_t)cols, sizeof(double));
    if (!db || !onset || !shifted)
    {
        free(M); free(db); free(onset); free(shifted);
        return LR_E_MEMORY;
    }
    {
        double dmax = -1e300;
        for (i = 0; i < (int64_t)n_mels * cols; i++)
        {
            db[i] = 10.0 * log10(fmax(1e-10, (double)M[i]));
            if (db[i] > dmax) dmax = db[i];
        }
        for (i = 0; i < (int64_t)n_mels * cols; i++)
        {
            if (db[i] < dmax - 80.0) db[i] = dmax - 80.0;
        }
    }
    for (t = 1; t < cols; t++)
    {
        double a = 0.0;
        for (i = 0; i < n_mels; i++)
        {
            double d = db[i * cols + t] - db[i * cols + t - 1];
            if (d < 0.0) d = 0.0;
            a += d;
        }
        onset[t - 1] = a / (double)n_mels;
    }
    for (t = 3; t < cols; t++) shifted[t] = onset[t - 3];
    free(onset);
    onset = shifted;

    /* 2) tempogram：win=floor(8s*sr/hop)；linear_ramp 两侧 win/2 + hann
     *    + 自相关 + 列 inf 归一，帧数截到 cols 后求时间均值 */
    win = (int)((8.0 * (double)sr) / (double)hop);
    if (win < 4 || win > (1 << 16))
    {
        free(M); free(db); free(onset);
        return LR_E_PARAM;
    }
    acc = (double*)calloc((size_t)win, sizeof(double));
    hann = (double*)malloc(sizeof(double) * (size_t)win);
    fft_n = lr_next_pow2(2 * win - 1);
    re = (double*)malloc(sizeof(double) * (size_t)fft_n);
    im = (double*)calloc((size_t)fft_n, sizeof(double));
    if (!acc || !hann || !re || !im)
    {
        free(M); free(db); free(onset); free(acc); free(hann); free(re); free(im);
        return LR_E_MEMORY;
    }
    lr_hann(hann, win);
    {
        int64_t pad = win / 2;
        int64_t padded = cols + 2 * pad;
        padded_on = (double*)malloc(sizeof(double) * (size_t)padded);
        if (!padded_on)
        {
            free(M); free(db); free(onset); free(acc); free(hann); free(re); free(im);
            return LR_E_MEMORY;
        }
        for (i = 0; i < pad; i++)   /* linear_ramp 0 -> onset[0] */
        {
            padded_on[i] = onset[0] * (double)(i + 1) / (double)(pad + 1);
        }
        for (t = 0; t < cols; t++) padded_on[pad + t] = onset[t];
        for (i = 0; i < pad; i++)   /* onset[cols-1] -> 0 */
        {
            padded_on[pad + cols + i] =
                onset[cols - 1] * (double)(pad - i) / (double)(pad + 1);
        }

        for (t = 0; t < cols; t++)
        {
            double mx = 0.0;
            for (lag = 0; lag < win; lag++)
            {
                re[lag] = padded_on[t + lag] * hann[lag];
                im[lag] = 0.0;
            }
            for (lag = win; lag < fft_n; lag++) { re[lag] = 0.0; im[lag] = 0.0; }
            lr_fft(re, im, fft_n, 0);
            for (lag = 0; lag < fft_n; lag++)
            {
                double p = re[lag] * re[lag] + im[lag] * im[lag];
                re[lag] = p;
                im[lag] = 0.0;
            }
            lr_fft(re, im, fft_n, 1);
            for (lag = 0; lag < win; lag++)
            {
                double v = fabs(re[lag]);
                if (v > mx) mx = v;
            }
            if (mx < LR_TINY64) mx = 1.0;   /* normalize inf 守卫 */
            for (lag = 0; lag < win; lag++) acc[lag] += re[lag] / mx;
        }
        for (lag = 0; lag < win; lag++) acc[lag] /= (double)cols;
        free(padded_on);
    }

    /* 3) 先验：log2 正态（center=log2(120)，std=1.0）+ max_tempo=320 屏蔽；
     *    score = log1p(1e6*tg) + logprior，argmax 取 bin BPM */
    {
        double log2_start = log2(120.0);
        int64_t max_idx = 0;
        for (lag = 1; lag < win; lag++)
        {
            if (60.0 * (double)sr / ((double)hop * (double)lag) < 320.0)
            {
                max_idx = lag;
                break;
            }
        }
        for (lag = 1; lag < win; lag++)
        {
            double bpmv = 60.0 * (double)sr / ((double)hop * (double)lag);
            double score;
            if (lag < max_idx) continue;   /* BPM >= max_tempo（含 lag 0） */
            score = log1p(1e6 * acc[lag])
                  + (-0.5 * pow((log2(bpmv) - log2_start) / 1.0, 2.0));
            if (score > best_score)
            {
                best_score = score;
                best = (int)lag;
            }
        }
    }
    if (best > 0)
    {
        bpm = 60.0 * (double)sr / ((double)hop * (double)best);
        *out_bpm = bpm;
        rc = LR_OK;
    }
    else
    {
        rc = LR_E_DECODE;
    }

    free(M); free(db); free(onset); free(acc); free(hann); free(re); free(im);
    return rc;
}
