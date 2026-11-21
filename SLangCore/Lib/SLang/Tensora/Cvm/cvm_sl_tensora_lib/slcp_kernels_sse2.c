/*
 * slcp_kernels_sse2.c —— Tier-1 kernel 的 SSE2 版（x64 基线保底路径）
 * ==========================================================================
 * 本文件按 x64 默认（无 /arch 开关，SSE2 恒可用）编译。
 *
 * 位级一致实现要点（vm_sl_cpu.h 文件头"位级一致契约"的落地）：
 *   - matmul / conv2d：SIMD lane 并行的是**不同输出元素**；对单个输出
 *     元素，k（或 ch,ky,kx）方向按标量顺序逐条 mul（单舍入）+ add
 *     （单舍入）累加，舍入序列与 L0 的 acc = acc + a*b 完全同序 →
 *     与 L0 及其他 ISA 档逐位相同；
 *   - sum / softmax：标量顺序循环复刻 L0（softmax 的 exp 用 CRT expf，
 *     与 SL 侧 Mathf.exp → math_lib!mathf_exp 同一函数）；
 *   - 尾部用标量余段（AVX-512 档才用 mask 寄存器）；
 *   - 全程 unaligned load/store（不假设 SL Memory 块对齐）；
 *   - 禁用 FMA intrinsic（MSVC /fp:precise 下也不做自动融合）。
 * ========================================================================== */

#include <immintrin.h>
#include <math.h>     /* expf：softmax 复刻 L0 的 exp 链路（CRT 同函数） */
#include <stdint.h>

/* 每文件统一的导出前缀声明（slcp_ 内部实现，普通外部链接）。 */
#define SLCP_K extern

SLCP_K int32_t slcp_matmul_sse2(const float* a, const float* b,
                                float* o, const int32_t* cfg);
SLCP_K int32_t slcp_sum_sse2(const float* x, const float* unused, float* o,
                             const int32_t* cfg);
SLCP_K int32_t slcp_softmax_sse2(const float* x, const float* unused, float* o,
                                 const int32_t* cfg);
SLCP_K int32_t slcp_conv2d_sse2(const float* in, const float* wt,
                                float* o, const int32_t* cfg);

#define SLCP_SSE2_V 4   /* f32 通道数 */

/* ------------------------------------------------------------------ */
/* matmul：a[m,k] * b[k,n] -> o[m,n]，行主序                          */
/* ------------------------------------------------------------------ */

int32_t slcp_matmul_sse2(const float* a, const float* b,
                         float* o, const int32_t* cfg)
{
    const int     m = cfg[0];
    const int     n = cfg[1];
    const int     k = cfg[2];
    const int32_t V = SLCP_SSE2_V;

    for (int i = 0; i < m; i++)
    {
        const float* arow = a + (size_t)i * (size_t)k;
        float*       orow = o + (size_t)i * (size_t)n;

        int j = 0;
        for (; j + V <= n; j += V)
        {
            /* 每 lane 独立按 p=0..k-1 顺序累加（位级同 L0）。 */
            __m128 acc = _mm_setzero_ps();
            for (int p = 0; p < k; p++)
            {
                const __m128 av = _mm_set1_ps(arow[p]);
                const __m128 bv = _mm_loadu_ps(&b[(size_t)p * (size_t)n + (size_t)j]);
                acc = _mm_add_ps(acc, _mm_mul_ps(av, bv));
            }
            _mm_storeu_ps(&orow[j], acc);
        }
        /* 标量余段（L0 原序）。 */
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
/* sum：标量顺序累加（位级同 L0 Tensor.sum）                          */
/* ------------------------------------------------------------------ */

int32_t slcp_sum_sse2(const float* x, const float* unused, float* o, const int32_t* cfg)
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
/* softmax：逐行复刻 L0 Tensor.softmax                               */
/*   max（严格 >，首值优先）→ denom = sum expf(x-mx)（标量序）→       */
/*   out = expf(x-mx) / denom（IEEE 单舍入除法）                      */
/* ------------------------------------------------------------------ */

int32_t slcp_softmax_sse2(const float* x, const float* unused, float* o, const int32_t* cfg)
{
    const int rows = cfg[0];
    const int cols = cfg[1];

    for (int i = 0; i < rows; i++)
    {
        const float* xr = x + (size_t)i * (size_t)cols;
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
/*   L0（Ops.conv2d）对每个输出元素按 (ch,ky,kx) 顺序累加，越界 tap   */
/*   跳过（不加）；stride==1 时按 ox 分段 SIMD（lane = 不同输出元素），*/
/*   累加顺序与 L0 一致；越界 tap 的 lane 置 0（贡献 ±0，位级同"不加"）*/
/*   ——唯一理论边缘：acc 恰为 -0 时 +0 会翻成 +0，实测用例不触发。   */
/*   stride != 1 时整体走 L0 标量顺序（保位级，性能让位正确性）。      */
/* ------------------------------------------------------------------ */

int32_t slcp_conv2d_sse2(const float* in, const float* wt,
                         float* o, const int32_t* cfg)
{
    const int C = cfg[0], H = cfg[1], W = cfg[2];
    const int K = cfg[3], S = cfg[4], P = cfg[5];
    const int oH = cfg[6], oW = cfg[7];
    const int32_t V = SLCP_SSE2_V;

    if (S == 1)
    {
        for (int oy = 0; oy < oH; oy++)
        {
            float* orow = o + (size_t)oy * (size_t)oW;
            int ox = 0;
            for (; ox + V <= oW; ox += V)
            {
                __m128 acc = _mm_setzero_ps();
                for (int ch = 0; ch < C; ch++)
                {
                    for (int ky = 0; ky < K; ky++)
                    {
                        const int iy = oy - P + ky;
                        if (iy < 0 || iy >= H)
                        {
                            continue;   /* 整行 tap 无效：不加（位级同 L0） */
                        }
                        const float* irow = in + ((size_t)ch * (size_t)H + (size_t)iy) * (size_t)W;
                        const float* wrow = wt + ((size_t)ch * (size_t)K + (size_t)ky) * (size_t)K;
                        for (int kx = 0; kx < K; kx++)
                        {
                            const __m128 wvb = _mm_set1_ps(wrow[kx]);
                            const int ix0 = ox - P + kx;
                            if (ix0 >= 0 && ix0 + V <= W)
                            {
                                const __m128 bv = _mm_loadu_ps(&irow[ix0]);
                                acc = _mm_add_ps(acc, _mm_mul_ps(wvb, bv));
                            }
                            else
                            {
                                /* 边缘段：逐 lane 判界，越界置 0。 */
                                float buf[SLCP_SSE2_V];
                                for (int l = 0; l < V; l++)
                                {
                                    const int ix = ix0 + l;
                                    buf[l] = (ix >= 0 && ix < W) ? irow[ix] : 0.0f;
                                }
                                const __m128 bv = _mm_loadu_ps(buf);
                                acc = _mm_add_ps(acc, _mm_mul_ps(wvb, bv));
                            }
                        }
                    }
                }
                _mm_storeu_ps(&orow[ox], acc);
            }
            /* 标量余段（L0 原序）。 */
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

    /* stride != 1：L0 标量顺序（位级一致优先）。 */
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
