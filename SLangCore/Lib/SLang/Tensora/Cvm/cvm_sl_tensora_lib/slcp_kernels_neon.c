/*
 * slcp_kernels_neon.c —— Tier-1 kernel 的 NEON 版（ARM64 基线预留）
 * ==========================================================================
 * 本文件为 ARM64 平台预留：NEON 是 AArch64 基线指令集，免运行期检测
 * （sl_cpu_lib.c 在 ARM64 下恒选 SLCP_ISA_NEON）。
 * 当前 cvm_sl_tensora_lib.vcxproj 仅配置 x64（与 CUDA 部分同工程），
 * **不编译本文件**；ARM64 平台启用时在 vcxproj 追加 ARM64
 * 平台配置并将本文件纳入 ClCompile 即可（符号名与 SSE2/AVX2/AVX-512
 * 版完全对齐，sl_cpu_lib.c 的函数指针表已预留 NEON 列）。
 *
 * 位级一致要点与 slcp_kernels_sse2.c 相同（见该文件头）：
 * lane 并行的是不同输出元素、k 方向标量顺序累加（vadd/vmul 均为
 * 逐 lane 独立舍入）、尾部标量余段、不假设对齐（vld1q_f32 对非对齐
 * 地址安全）、禁用 VFMA（vfmaq_laneq_f32 单次舍入，与参考实现
 * mul 后 add 两次舍入不同）。
 * ========================================================================== */

#if defined(_M_ARM64) || defined(__aarch64__)

#include <arm_neon.h>
#include <math.h>     /* expf：softmax 复刻 L0 的 exp 链路（CRT 同函数） */
#include <stdint.h>

#define SLCP_NEON_V 4   /* f32 通道数 */

/* ------------------------------------------------------------------ */
/* matmul：a[m,k] * b[k,n] -> o[m,n]，行主序                          */
/* ------------------------------------------------------------------ */

int32_t slcp_matmul_neon(const float* a, const float* b,
                         float* o, const int32_t* cfg)
{
    const int     m = cfg[0];
    const int     n = cfg[1];
    const int     k = cfg[2];
    const int32_t V = SLCP_NEON_V;

    for (int i = 0; i < m; i++)
    {
        const float* arow = a + (size_t)i * (size_t)k;
        float*       orow = o + (size_t)i * (size_t)n;

        int j = 0;
        for (; j + V <= n; j += V)
        {
            float32x4_t acc = vdupq_n_f32(0.0f);
            for (int p = 0; p < k; p++)
            {
                const float32x4_t av = vld1q_dup_f32(&arow[p]);
                const float32x4_t bv = vld1q_f32(&b[(size_t)p * (size_t)n + (size_t)j]);
                /* 不用 vfmaq_f32（单次舍入 FMA，位级契约禁用）。 */
                acc = vaddq_f32(acc, vmulq_f32(av, bv));
            }
            vst1q_f32(&orow[j], acc);
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
/* sum：标量顺序累加（位级同 L0；各 ISA 档实现相同）                  */
/* ------------------------------------------------------------------ */

int32_t slcp_sum_neon(const float* x, const float* unused, float* o, const int32_t* cfg)
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

int32_t slcp_softmax_neon(const float* x, const float* unused, float* o, const int32_t* cfg)
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

int32_t slcp_conv2d_neon(const float* in, const float* wt,
                         float* o, const int32_t* cfg)
{
    const int C = cfg[0], H = cfg[1], W = cfg[2];
    const int K = cfg[3], S = cfg[4], P = cfg[5];
    const int oH = cfg[6], oW = cfg[7];
    const int32_t V = SLCP_NEON_V;

    if (S == 1)
    {
        for (int oy = 0; oy < oH; oy++)
        {
            float* orow = o + (size_t)oy * (size_t)oW;
            int ox = 0;
            for (; ox + V <= oW; ox += V)
            {
                float32x4_t acc = vdupq_n_f32(0.0f);
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
                            const float32x4_t wvb = vld1q_dup_f32(&wrow[kx]);
                            const int ix0 = ox - P + kx;
                            if (ix0 >= 0 && ix0 + V <= W)
                            {
                                const float32x4_t bv = vld1q_f32(&irow[ix0]);
                                acc = vaddq_f32(acc, vmulq_f32(wvb, bv));
                            }
                            else
                            {
                                float buf[SLCP_NEON_V];
                                for (int l = 0; l < V; l++)
                                {
                                    const int ix = ix0 + l;
                                    buf[l] = (ix >= 0 && ix < W) ? irow[ix] : 0.0f;
                                }
                                const float32x4_t bv = vld1q_f32(buf);
                                acc = vaddq_f32(acc, vmulq_f32(wvb, bv));
                            }
                        }
                    }
                }
                vst1q_f32(&orow[ox], acc);
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

#endif /* _M_ARM64 / __aarch64__ */
