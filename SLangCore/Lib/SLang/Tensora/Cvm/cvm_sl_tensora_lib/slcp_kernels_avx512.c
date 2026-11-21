/*
 * slcp_kernels_avx512.c —— Tier-1 kernel 的 AVX-512 版（运行期检测启用）
 * ==========================================================================
 * 本文件按 /arch:AVX512 编译（cvm_sl_tensora_lib.vcxproj per-file
 * EnableEnhancedInstructionSet=AdvancedVectorExtensions512），仅当运行期
 * 检测确认 AVX-512F/VL/DQ 三位齐全 + OS 使能 opmask/ZMM 后可达
 * （Comet Lake 等消费级禁用档自然不满足，回落 AVX2）。
 *
 * 位级一致要点与 slcp_kernels_sse2.c 相同（见该文件头）。
 * 尾部处理差异（§6.1.2）：输出段不足 V 时用 **mask 寄存器**
 * （_mm512_maskz_loadu_ps 只触碰有效 lane 的内存，越界 lane 置 0；
 * _mm512_mask_storeu_ps 只写有效 lane）——SSE2/AVX2 档为标量余段。
 * ========================================================================== */

#include <immintrin.h>
#include <math.h>     /* expf：softmax 复刻 L0 的 exp 链路（CRT 同函数） */
#include <stdint.h>

#define SLCP_AVX512_V 16   /* f32 通道数 */

/* ------------------------------------------------------------------ */
/* matmul：a[m,k] * b[k,n] -> o[m,n]，行主序                          */
/* ------------------------------------------------------------------ */

int32_t slcp_matmul_avx512(const float* a, const float* b,
                           float* o, const int32_t* cfg)
{
    const int     m = cfg[0];
    const int     n = cfg[1];
    const int     k = cfg[2];
    const int32_t V = SLCP_AVX512_V;

    for (int i = 0; i < m; i++)
    {
        const float* arow = a + (size_t)i * (size_t)k;
        float*       orow = o + (size_t)i * (size_t)n;

        int j = 0;
        for (; j + V <= n; j += V)
        {
            __m512 acc = _mm512_setzero_ps();
            for (int p = 0; p < k; p++)
            {
                const __m512 av = _mm512_set1_ps(arow[p]);
                const __m512 bv = _mm512_loadu_ps(&b[(size_t)p * (size_t)n + (size_t)j]);
                acc = _mm512_add_ps(acc, _mm512_mul_ps(av, bv));
            }
            _mm512_storeu_ps(&orow[j], acc);
        }
        /* 尾段：mask 寄存器（不足 V 的部分，越界 lane 不触碰内存）。 */
        for (; j < n; j += V)
        {
            const __mmask16 mask = (__mmask16)((1u << (n - j)) - 1);
            __m512 acc = _mm512_setzero_ps();
            for (int p = 0; p < k; p++)
            {
                const __m512 av = _mm512_set1_ps(arow[p]);
                const __m512 bv = _mm512_maskz_loadu_ps(mask, &b[(size_t)p * (size_t)n + (size_t)j]);
                acc = _mm512_add_ps(acc, _mm512_mul_ps(av, bv));
            }
            _mm512_mask_storeu_ps(&orow[j], mask, acc);
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* sum：标量顺序累加（位级同 L0；三 ISA 档实现相同）                  */
/* ------------------------------------------------------------------ */

int32_t slcp_sum_avx512(const float* x, const float* unused, float* o, const int32_t* cfg)
{
    const int n = cfg[0];
    float s = 0.0f;
    for (int i = 0; i < n; i++)
    {
        s = s + x[i];
    }
    o[0] = s;
    return 1;
}

/* ------------------------------------------------------------------ */
/* softmax：逐行复刻 L0 Tensor.softmax（标量序 + CRT expf）           */
/* ------------------------------------------------------------------ */

int32_t slcp_softmax_avx512(const float* x, const float* unused, float* o, const int32_t* cfg)
{
    const int rows = cfg[0];
    const int cols = cfg[1];

    for (int i = 0; i < rows; i++)
    {
        const float* xr   = x + (size_t)i * (size_t)cols;
        float*       orow = o + (size_t)i * (size_t)cols;

        float mx = xr[0];
        for (int j = 1; j < cols; j++)
        {
            if (xr[j] > mx)
            {
                mx = xr[j];
            }
        }
        float denom = 0.0f;
        for (int j = 0; j < cols; j++)
        {
            denom = denom + expf(xr[j] - mx);
        }
        for (int j = 0; j < cols; j++)
        {
            orow[j] = expf(xr[j] - mx) / denom;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* conv2d：in[C,H,W] * wt[C,k,k] -> o[1,outH,outW]                    */
/*   stride==1 时 ox 分段 SIMD（输出尾段 mask；输入边缘段 buf 补 0）；*/
/*   (ch,ky,kx) 累加顺序与 L0 一致；stride != 1 时标量 L0 顺序。      */
/* ------------------------------------------------------------------ */

int32_t slcp_conv2d_avx512(const float* in, const float* wt,
                           float* o, const int32_t* cfg)
{
    const int C = cfg[0], H = cfg[1], W = cfg[2];
    const int K = cfg[3], S = cfg[4], P = cfg[5];
    const int oH = cfg[6], oW = cfg[7];
    const int32_t V = SLCP_AVX512_V;

    if (S == 1)
    {
        for (int oy = 0; oy < oH; oy++)
        {
            float* orow = o + (size_t)oy * (size_t)oW;
            int ox = 0;
            for (; ox + V <= oW; ox += V)
            {
                __m512 acc = _mm512_setzero_ps();
                for (int ch = 0; ch < C; ch++)
                {
                    for (int ky = 0; ky < K; ky++)
                    {
                        const int iy = oy - P + ky;
                        if (iy < 0 || iy >= H)
                        {
                            continue;
                        }
                        const float* irow = in + ((size_t)ch * (size_t)H + (size_t)iy) * (size_t)W;
                        const float* wrow = wt + ((size_t)ch * (size_t)K + (size_t)ky) * (size_t)K;
                        for (int kx = 0; kx < K; kx++)
                        {
                            const __m512 wvb = _mm512_set1_ps(wrow[kx]);
                            const int ix0 = ox - P + kx;
                            if (ix0 >= 0 && ix0 + V <= W)
                            {
                                const __m512 bv = _mm512_loadu_ps(&irow[ix0]);
                                acc = _mm512_add_ps(acc, _mm512_mul_ps(wvb, bv));
                            }
                            else
                            {
                                /* 输入边缘段：逐 lane 判界补 0。 */
                                float buf[SLCP_AVX512_V];
                                for (int l = 0; l < V; l++)
                                {
                                    const int ix = ix0 + l;
                                    buf[l] = (ix >= 0 && ix < W) ? irow[ix] : 0.0f;
                                }
                                const __m512 bv = _mm512_loadu_ps(buf);
                                acc = _mm512_add_ps(acc, _mm512_mul_ps(wvb, bv));
                            }
                        }
                    }
                }
                _mm512_storeu_ps(&orow[ox], acc);
            }
            /* 输出尾段：mask 寄存器。 */
            for (; ox < oW; ox += V)
            {
                const __mmask16 mask = (__mmask16)((1u << (oW - ox)) - 1);
                __m512 acc = _mm512_setzero_ps();
                for (int ch = 0; ch < C; ch++)
                {
                    for (int ky = 0; ky < K; ky++)
                    {
                        const int iy = oy - P + ky;
                        if (iy < 0 || iy >= H)
                        {
                            continue;
                        }
                        const float* irow = in + ((size_t)ch * (size_t)H + (size_t)iy) * (size_t)W;
                        const float* wrow = wt + ((size_t)ch * (size_t)K + (size_t)ky) * (size_t)K;
                        for (int kx = 0; kx < K; kx++)
                        {
                            const __m512 wvb = _mm512_set1_ps(wrow[kx]);
                            const int ix0 = ox - P + kx;
                            if (ix0 >= 0 && ix0 + V <= W)
                            {
                                const __m512 bv = _mm512_loadu_ps(&irow[ix0]);
                                acc = _mm512_add_ps(acc, _mm512_mul_ps(wvb, bv));
                            }
                            else
                            {
                                float buf[SLCP_AVX512_V];
                                for (int l = 0; l < V; l++)
                                {
                                    const int ix = ix0 + l;
                                    buf[l] = (ix >= 0 && ix < W) ? irow[ix] : 0.0f;
                                }
                                const __m512 bv = _mm512_loadu_ps(buf);
                                acc = _mm512_add_ps(acc, _mm512_mul_ps(wvb, bv));
                            }
                        }
                    }
                }
                _mm512_mask_storeu_ps(&orow[ox], mask, acc);
            }
        }
        return 1;
    }

    for (int oy = 0; oy < oH; oy++)
    {
        float* orow = o + (size_t)oy * (size_t)oW;
        for (int ox = 0; ox < oW; ox++)
        {
            float acc = 0.0f;
            for (int ch = 0; ch < C; ch++)
            {
                for (int ky = 0; ky < K; ky++)
                {
                    const int iy = oy * S - P + ky;
                    if (iy < 0 || iy >= H) { continue; }
                    const float* irow = in + ((size_t)ch * (size_t)H + (size_t)iy) * (size_t)W;
                    const float* wrow = wt + ((size_t)ch * (size_t)K + (size_t)ky) * (size_t)K;
                    for (int kx = 0; kx < K; kx++)
                    {
                        const int ix = ox * S - P + kx;
                        if (ix >= 0 && ix < W)
                        {
                            acc = acc + irow[ix] * wrow[kx];
                        }
                    }
                }
            }
            orow[ox] = acc;
        }
    }
    return 1;
}
