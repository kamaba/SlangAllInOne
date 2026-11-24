/* =========================================================================
 * sl_audio_librosa.c —— librosa 分析层 FFI 分派（sl_audio_lib 第 2 组导出）
 *
 * 纯算法无句柄、无状态：SL 侧按已知尺寸预分配输出块（Memory.alloc），
 * 本层校验参数 -> 调 third_party/librosa 的 lr_* -> 拷贝到输出块。
 * 错误经 sla_set_error / sla_set_error_detail 走库级粘性错误通道，
 * LR_E_* -> SLA_E_* 映射保持与 vm_sl_audio.h 错误码语义一致。
 * ========================================================================= */
#include "sl_audio_internal.h"
#include "third_party/librosa/sl_librosa.h"

/* ---- 错误映射 ---- */
static int lr_map_err(int rc)
{
    switch (rc)
    {
    case LR_E_PARAM:  return SLA_E_BAD_PARAM;
    case LR_E_MEMORY: return SLA_E_MEMORY;
    case LR_E_LIMIT:  return SLA_E_LIMIT;
    case LR_E_DECODE: return SLA_E_DECODE;
    default:          return SLA_E_UNSUPPORTED;
    }
}

static int lr_fail(int rc, const char* what)
{
    sla_set_error_detail(lr_map_err(rc), "librosa: %s failed (rc=%d)",
                         what, rc);
    return 0;
}

/* ---- 诊断 ---- */

int sla_lr_last_error(void)
{
    return sla_last_error();
}

const char* sla_lr_error_string(int err)
{
    return sla_error_string(err);
}

const char* sla_lr_version_string(void)
{
    return lr_version();
}

/* ---- 标量换算 ---- */

double sla_lr_scalar(int op, double x, double ref)
{
    switch (op)
    {
    case SLA_LRS_HZ_TO_MEL:    return lr_hz_to_mel(x, 0);
    case SLA_LRS_MEL_TO_HZ:    return lr_mel_to_hz(x, 0);
    case SLA_LRS_HZ_TO_MEL_H:  return lr_hz_to_mel(x, 1);
    case SLA_LRS_MEL_TO_HZ_H:  return lr_mel_to_hz(x, 1);
    case SLA_LRS_HZ_TO_MIDI:   return lr_hz_to_midi(x);
    case SLA_LRS_MIDI_TO_HZ:   return lr_midi_to_hz(x);
    case SLA_LRS_POWER_TO_DB:  return lr_power_to_db(x, ref);
    case SLA_LRS_DB_TO_POWER:  return lr_db_to_power(x, ref);
    case SLA_LRS_AMP_TO_DB:    return lr_amplitude_to_db(x, ref);
    case SLA_LRS_DB_TO_AMP:    return lr_db_to_amplitude(x, ref);
    default:
        sla_set_error_detail(SLA_E_BAD_PARAM, "librosa: bad scalar op %d", op);
        return 0.0;
    }
}

const char* sla_lr_hz_to_note(double hz)
{
    static char buf[16];
    lr_hz_to_note(hz, buf, (int)sizeof(buf));
    return buf;
}

/* ---- STFT / ISTFT ---- */

int sla_lr_stft(int64_t y_ptr, int64_t n, int n_fft, int hop, int64_t out_ptr)
{
    float* out = NULL;
    int64_t rows = 0, cols = 0;
    int rc;
    if (y_ptr == 0 || out_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_stft((const float*)(intptr_t)y_ptr, n, n_fft, hop, &out, &rows, &cols);
    if (rc != LR_OK) return lr_fail(rc, "stft");
    memcpy((void*)(intptr_t)out_ptr, out,
           sizeof(float) * (size_t)(rows * cols * 2));
    free(out);
    return 1;
}

int64_t sla_lr_istft(int64_t reim_ptr, int64_t rows, int64_t cols,
                      int hop, int64_t length, int64_t dst_ptr)
{
    int n_fft;
    int64_t n = 0;
    int rc;
    if (reim_ptr == 0 || dst_ptr == 0 || rows < 2)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    n_fft = (int)(2 * (rows - 1));
    rc = lr_istft((const float*)(intptr_t)reim_ptr, rows, cols, n_fft, hop,
                  length, (float*)(intptr_t)dst_ptr,
                  length > 0 ? length : 0x7fffffffLL, &n);
    if (rc != LR_OK) { lr_fail(rc, "istft"); return 0; }
    return n;
}

/* ---- 矩阵特征 ---- */

int sla_lr_melspec(int64_t reim_ptr, int64_t rows, int64_t cols,
                   int sr, int n_mels, int64_t out_ptr)
{
    float* out = NULL;
    int64_t out_rows = 0;
    int rc;
    if (reim_ptr == 0 || out_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_melspectrogram((const float*)(intptr_t)reim_ptr, rows, cols,
                           sr, n_mels, &out, &out_rows);
    if (rc != LR_OK) return lr_fail(rc, "melspectrogram");
    memcpy((void*)(intptr_t)out_ptr, out,
           sizeof(float) * (size_t)(out_rows * cols));
    free(out);
    return 1;
}

int sla_lr_mfcc(int64_t mel_ptr, int64_t mel_rows, int64_t cols,
                int n_mfcc, int64_t out_ptr)
{
    float* out = NULL;
    int64_t out_rows = 0;
    int rc;
    if (mel_ptr == 0 || out_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_mfcc((const float*)(intptr_t)mel_ptr, mel_rows, cols, n_mfcc,
                 &out, &out_rows);
    if (rc != LR_OK) return lr_fail(rc, "mfcc");
    memcpy((void*)(intptr_t)out_ptr, out,
           sizeof(float) * (size_t)(out_rows * cols));
    free(out);
    return 1;
}

int sla_lr_chroma(int64_t reim_ptr, int64_t rows, int64_t cols,
                   int sr, int64_t out_ptr)
{
    float* out = NULL;
    int64_t out_rows = 0;
    int rc;
    if (reim_ptr == 0 || out_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_chroma((const float*)(intptr_t)reim_ptr, rows, cols, sr,
                   &out, &out_rows);
    if (rc != LR_OK) return lr_fail(rc, "chroma_stft");
    memcpy((void*)(intptr_t)out_ptr, out,
           sizeof(float) * (size_t)(out_rows * cols));
    free(out);
    return 1;
}

int sla_lr_tuning(int64_t reim_ptr, int64_t rows, int64_t cols,
                   int sr, int64_t out_f64_ptr)
{
    double tuning = 0.0;
    int rc;
    if (reim_ptr == 0 || out_f64_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_tuning((const float*)(intptr_t)reim_ptr, rows, cols, sr, &tuning);
    if (rc != LR_OK) return lr_fail(rc, "estimate_tuning");
    memcpy((void*)(intptr_t)out_f64_ptr, &tuning, sizeof(double));
    return 1;
}

int64_t sla_lr_vecs(int64_t reim_ptr, int64_t rows, int64_t cols,
                    int sr, int op, int64_t dst_ptr)
{
    int64_t n = 0;
    int rc = LR_OK;
    if (reim_ptr == 0 || dst_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    switch (op)
    {
    case SLA_LRV_CENTROID:
        rc = lr_centroid((const float*)(intptr_t)reim_ptr, rows, cols, sr,
                         (float*)(intptr_t)dst_ptr, &n);
        break;
    case SLA_LRV_BANDWIDTH:
        rc = lr_bandwidth((const float*)(intptr_t)reim_ptr, rows, cols, sr,
                          (float*)(intptr_t)dst_ptr, &n);
        break;
    case SLA_LRV_ROLLOFF:
        rc = lr_rolloff((const float*)(intptr_t)reim_ptr, rows, cols, sr,
                        (float*)(intptr_t)dst_ptr, &n);
        break;
    case SLA_LRV_FLATNESS:
        rc = lr_flatness((const float*)(intptr_t)reim_ptr, rows, cols,
                         (float*)(intptr_t)dst_ptr, &n);
        break;
    default:
        sla_set_error_detail(SLA_E_BAD_PARAM, "librosa: bad vec op %d", op);
        return 0;
    }
    if (rc != LR_OK) { lr_fail(rc, "spectral vec"); return 0; }
    return n;
}

/* ---- 时域向量特征 ---- */

int64_t sla_lr_rms(int64_t y_ptr, int64_t n, int frame_len, int hop,
                   int64_t dst_ptr)
{
    int64_t out_n = 0;
    int rc;
    if (y_ptr == 0 || dst_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_rms((const float*)(intptr_t)y_ptr, n, frame_len, hop,
                (float*)(intptr_t)dst_ptr, 0x7fffffffLL, &out_n);
    if (rc != LR_OK) { lr_fail(rc, "rms"); return 0; }
    return out_n;
}

int64_t sla_lr_zcr(int64_t y_ptr, int64_t n, int frame_len, int hop,
                   int64_t dst_ptr)
{
    int64_t out_n = 0;
    int rc;
    if (y_ptr == 0 || dst_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_zcr((const float*)(intptr_t)y_ptr, n, frame_len, hop,
                (float*)(intptr_t)dst_ptr, 0x7fffffffLL, &out_n);
    if (rc != LR_OK) { lr_fail(rc, "zero_crossing_rate"); return 0; }
    return out_n;
}

int sla_lr_tempo(int64_t y_ptr, int64_t n, int sr, int hop, int64_t out_f64_ptr)
{
    double bpm = 0.0;
    int rc;
    if (y_ptr == 0 || out_f64_ptr == 0)
    {
        sla_set_error(SLA_E_BAD_PARAM);
        return 0;
    }
    rc = lr_tempo((const float*)(intptr_t)y_ptr, n, sr, hop, &bpm);
    if (rc != LR_OK) return lr_fail(rc, "tempo");
    memcpy((void*)(intptr_t)out_f64_ptr, &bpm, sizeof(double));
    return 1;
}
