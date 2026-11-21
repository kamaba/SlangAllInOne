/*
 * slcp_kernels_avx2.c —— Tier-1 kernel 的 AVX2 版（运行期检测启用）
 * ==========================================================================
 * 本文件按 /arch:AVX2 编译（cvm_sl_tensora_lib.vcxproj per-file
 * EnableEnhancedInstructionSet=AdvancedVectorExtensions2），仅当运行期
 * 检测（cpuid + XCR0，见 sl_cpu_lib.c）确认 AVX2 + OS 使能后才可达。
 *
 * 位级一致要点与 slcp_kernels_sse2.c 相同（见该文件头）：
 * lane 并行的是不同输出元素、k 方向标量顺序累加、尾部标量余段、
 * unaligned 访问、禁 FMA——因此与 SSE2 档 / L0 逐位相同。
 * ========================================================================== */

#include <immintrin.h>
#include <math.h>     /* expf：softmax 复刻 L0 的 exp 链路（CRT 同函数） */
#include <stdint.h>

#define SLCP_AVX2_V 8   /* f32 通道数 */

/* ------------------------------------------------------------------ */
/* matmul：a[m,k] * b[k,n] -> o[m,n]，行主序                          */
/* ------------------------------------------------------------------ */

int32_t slcp_matmul_avx2(const float* a, const float* b,
                         float* o, const int32_t* cfg)
{
    const int     m = cfg[0];
    const int     n = cfg[1];
    const int     k = cfg[2];
    const int32_t V = SLCP_AVX2_V;

    for (int i = 0; i < m; i++)
    {
        const float* arow = a + (size_t)i * (size_t)k;
        float*       orow = o + (size_t)i * (size_t)n;

        int j = 0;
        for (; j + V <= n; j += V)
        {
            __m256 acc = _mm256_setzero_ps();
            for (int p = 0; p < k; p++)
            {
                const __m256 av = _mm256_set1_ps(arow[p]);
                const __m256 bv = _mm256_loadu_ps(&b[(size_t)p * (size_t)n + (size_t)j]);
                acc = _mm256_add_ps(acc, _mm256_mul_ps(av, bv));
            }
            _mm256_storeu_ps(&orow[j], acc);
        }
        for (; j < n; j++)
        {
            float acc = 0.0f;
            for (int p = 0; p < k; p++)
            {
                acc = acc + arow[p] * b[(size_t)p * (size_t)n + (size_t)j];
            }
            orow[j] = acc;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* sum：标量顺序累加（位级同 L0；三 ISA 档实现相同）                  */
/* ------------------------------------------------------------------ */

int32_t slcp_sum_avx2(const float* x, const float* unused, float* o, const int32_t* cfg)
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

int32_t slcp_softmax_avx2(const float* x, const float* unused, float* o, const int32_t* cfg)
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
/*   stride==1 时 ox 分段 SIMD（(ch,ky,kx) 顺序同 L0）；否则标量 L0。 */
/* ------------------------------------------------------------------ */

int32_t slcp_conv2d_avx2(const float* in, const float* wt,
                         float* o, const int32_t* cfg)
{
    const int C = cfg[0], H = cfg[1], W = cfg[2];
    const int K = cfg[3], S = cfg[4], P = cfg[5];
    const int oH = cfg[6], oW = cfg[7];
    const int32_t V = SLCP_AVX2_V;

    if (S == 1)
    {
        for (int oy = 0; oy < oH; oy++)
        {
            float* orow = o + (size_t)oy * (size_t)oW;
            int ox = 0;
            for (; ox + V <= oW; ox += V)
            {
                __m256 acc = _mm256_setzero_ps();
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
                            const __m256 wvb = _mm256_set1_ps(wrow[kx]);
                            const int ix0 = ox - P + kx;
                            if (ix0 >= 0 && ix0 + V <= W)
                            {
                                const __m256 bv = _mm256_loadu_ps(&irow[ix0]);
                                acc = _mm256_add_ps(acc, _mm256_mul_ps(wvb, bv));
                            }
                            else
                            {
                                float buf[SLCP_AVX2_V];
                                for (int l = 0; l < V; l++)
                                {
                                    const int ix = ix0 + l;
                                    buf[l] = (ix >= 0 && ix < W) ? irow[ix] : 0.0f;
                                }
                                const __m256 bv = _mm256_loadu_ps(buf);
                                acc = _mm256_add_ps(acc, _mm256_mul_ps(wvb, bv));
                            }
                        }
                    }
                }
                _mm256_storeu_ps(&orow[ox], acc);
            }
            for (; ox < oW; ox++)
            {
                float acc = 0.0f;
                for (int ch = 0; ch < C; ch++)
                {
                    for (int ky = 0; ky < K; ky++)
                    {
                        const int iy = oy - P + ky;
                        if (iy < 0 || iy >= H) { continue; }
                        const float* irow = in + ((size_t)ch * (size_t)H + (size_t)iy) * (size_t)W;
                        const float* wrow = wt + ((size_t)ch * (size_t)K + (size_t)ky) * (size_t)K;
                        for (int kx = 0; kx < K; kx++)
                        {
                            const int ix = ox - P + kx;
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
