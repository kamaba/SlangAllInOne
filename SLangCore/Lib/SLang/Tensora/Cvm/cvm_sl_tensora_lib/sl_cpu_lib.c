/*
 * sl_cpu_lib.c —— Tensora cvm 原生实现 CPU 部分（合入 sl_tensora_lib.dll）
 * ==========================================================================
 * Tensora CPU 后端 L1 SIMD 加速层的入口 / 检测 / 分派层。
 *
 * 与 sl_cuda_lib.c 的分工差异：CUDA 库这层做 LoadLibrary 符号解析，
 * 本库这层做 **ISA 运行期检测 + 函数指针表分派**——
 *
 *   1) 本文件按 x64 基线（SSE2）编译，只使用 __cpuid/__cpuidex/_xgetbv
 *      探测指令，不含任何 AVX/AVX-512 intrinsic；
 *   2) 各 ISA 的 kernel 实现在 slcp_kernels_{sse2,avx2,avx512}.c，
 *      MSVC **按文件**设编译开关（/arch:AVX2、/arch:AVX512，
 *      见 cvm_sl_tensora_lib.vcxproj 的 per-file EnableEnhancedInstructionSet）；
 *      NEON 版 slcp_kernels_neon.c 为 ARM64 预留（x64 工程不编译）；
 *   3) 首次调用（或显式 slcp_init）惰性检测一次，按结果填
 *      s_table[op][isa] 函数指针表，此后每次调用直达目标实现
 *      （每调用零检测开销）。
 *
 * x64 检测规则（§6.1.2，仅 CPUID 置位不充分，必须校验 XCR0）：
 *   - SSE2：x64 架构保证，恒可用（保底路径）；
 *   - AVX2：leaf1 ECX OSXSAVE(bit27) + AVX(bit28)，且 XCR0 的
 *     XMM(bit1)+YMM(bit2) 使能，再 leaf7 EBX AVX2(bit5)；
 *   - AVX-512：AVX2 成立基础上，leaf7 EBX 的 F(bit16) + DQ(bit17) +
 *     VL(bit31) 三位齐全，且 XCR0 的 opmask(bit5) + ZMM_Hi256(bit6) +
 *     Hi16_ZMM(bit7) 使能（Comet Lake 等消费级禁用档自然不满足）；
 *   - FMA3：leaf1 ECX bit12（仅记录供 slcp_has_fma 查询；Tier-1
 *     kernel 恒不用 FMA，位级一致契约见 vm_sl_cpu.h 文件头）。
 *
 * 线程安全：检测一次性完成（Interlocked 抢占 + 自旋等待），
 * 完成后 s_table / s_isa 只读；错误消息用线程局部缓冲。
 * ========================================================================== */

#include "vm_sl_cpu.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>

#include <string.h>

/* ========================================================================
 * ISA kernel 实现（slcp_kernels_*.c 提供，普通外部链接、不导出）
 * 四参统一形态（vm_sl_cpu.h），一个函数指针类型即可覆盖全部算子。
 * ======================================================================== */

typedef int32_t (*slcp_fn_t)(const float*, const float*, float*, const int32_t*);

extern int32_t slcp_matmul_sse2 (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_sum_sse2    (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_softmax_sse2(const float*, const float*, float*, const int32_t*);
extern int32_t slcp_conv2d_sse2 (const float*, const float*, float*, const int32_t*);

extern int32_t slcp_matmul_avx2 (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_sum_avx2    (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_softmax_avx2(const float*, const float*, float*, const int32_t*);
extern int32_t slcp_conv2d_avx2 (const float*, const float*, float*, const int32_t*);

extern int32_t slcp_matmul_avx512 (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_sum_avx512    (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_softmax_avx512(const float*, const float*, float*, const int32_t*);
extern int32_t slcp_conv2d_avx512 (const float*, const float*, float*, const int32_t*);

#if defined(_M_ARM64) || defined(__aarch64__)
extern int32_t slcp_matmul_neon (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_sum_neon    (const float*, const float*, float*, const int32_t*);
extern int32_t slcp_softmax_neon(const float*, const float*, float*, const int32_t*);
extern int32_t slcp_conv2d_neon (const float*, const float*, float*, const int32_t*);
#endif

/* ========================================================================
 * 全局状态
 * ======================================================================== */

/* 函数指针表：[opId][isa]，检测完成后只读。 */
static slcp_fn_t s_table[SLCP_OP_COUNT][SLCP_ISA_COUNT];

/* 检测状态：0=未跑 1=某线程执行中 2=完成（此后只读）。 */
static volatile LONG s_init_state = 0;

/* 检测结果（s_init_state==2 后只读）。s_isa_hw 为硬件检测档
   （slcp_force_isa 恢复用）；s_isa 为当前生效档（force 可改写）。 */
static int32_t s_isa     = SLCP_ISA_SSE2;
static int32_t s_isa_hw  = SLCP_ISA_SSE2;
static int32_t s_has_fma = 0;

/* 粘性错误码：每个入口先清零；0 = 无错。 */
static __declspec(thread) int t_last = 0;

/* 错误文本线程局部缓冲（返回瞬间有效语义，见 vm_sl_cpu.h）。 */
static __declspec(thread) char t_msg[128];

/* ========================================================================
 * ISA 检测（x64）
 * ======================================================================== */

#if defined(_M_X64) || defined(_M_AMD64) || defined(__x86_64__)

static int32_t slcp_detect_x64(void)
{
    int32_t isa = SLCP_ISA_SSE2;   /* x64 基线恒可用 */

    int cpu[4];
    __cpuid(cpu, 1);

    s_has_fma = (cpu[2] & (1 << 12)) ? 1 : 0;   /* FMA3 位，仅记录 */

    const int osxsave = (cpu[2] & (1 << 27)) != 0;
    const int avx     = (cpu[2] & (1 << 28)) != 0;
    if (osxsave && avx)
    {
        /* OS 必须已使能 YMM 上下文保存，仅 CPUID 置位不充分。 */
        const unsigned long long xcr0 = (unsigned long long)_xgetbv(0);
        if ((xcr0 & 0x6ULL) == 0x6ULL)   /* bit1 XMM + bit2 YMM */
        {
            __cpuidex(cpu, 7, 0);
            if (cpu[1] & (1 << 5))       /* EBX bit5 = AVX2 */
            {
                isa = SLCP_ISA_AVX2;

                /* AVX-512：F(16) + DQ(17) + VL(31) 三位齐全，
                   且 OS 使能 opmask(bit5)/ZMM_Hi256(bit6)/Hi16_ZMM(bit7)。 */
                const unsigned int f_vl_dq = (1u << 16) | (1u << 17) | (1u << 31);
                if ((cpu[1] & f_vl_dq) == f_vl_dq &&
                    (xcr0 & 0xe6ULL) == 0xe6ULL)
                {
                    isa = SLCP_ISA_AVX512;
                }
            }
        }
    }
    return isa;
}

#elif defined(_M_ARM64) || defined(__aarch64__)

static int32_t slcp_detect_x64(void)   /* 命名沿用，ARM64 下 NEON 基线免检 */
{
    return SLCP_ISA_NEON;
}

#endif

/* ========================================================================
 * 惰性初始化：检测 + 填表（一次性，幂等，线程安全）
 * ======================================================================== */

static void slcp_fill_table(void)
{
    /* 全列先清零（未提供实现的组合 = NULL = SLCP_E_UNSUPPORTED）。 */
    memset(s_table, 0, sizeof(s_table));

    s_table[SLCP_OP_MMUL][SLCP_ISA_SSE2]   = slcp_matmul_sse2;
    s_table[SLCP_OP_SUM ][SLCP_ISA_SSE2]   = slcp_sum_sse2;
    s_table[SLCP_OP_SMAX][SLCP_ISA_SSE2]   = slcp_softmax_sse2;
    s_table[SLCP_OP_CONV][SLCP_ISA_SSE2]   = slcp_conv2d_sse2;

    s_table[SLCP_OP_MMUL][SLCP_ISA_AVX2]   = slcp_matmul_avx2;
    s_table[SLCP_OP_SUM ][SLCP_ISA_AVX2]   = slcp_sum_avx2;
    s_table[SLCP_OP_SMAX][SLCP_ISA_AVX2]   = slcp_softmax_avx2;
    s_table[SLCP_OP_CONV][SLCP_ISA_AVX2]   = slcp_conv2d_avx2;

    s_table[SLCP_OP_MMUL][SLCP_ISA_AVX512] = slcp_matmul_avx512;
    s_table[SLCP_OP_SUM ][SLCP_ISA_AVX512] = slcp_sum_avx512;
    s_table[SLCP_OP_SMAX][SLCP_ISA_AVX512] = slcp_softmax_avx512;
    s_table[SLCP_OP_CONV][SLCP_ISA_AVX512] = slcp_conv2d_avx512;

#if defined(_M_ARM64) || defined(__aarch64__)
    s_table[SLCP_OP_MMUL][SLCP_ISA_NEON]   = slcp_matmul_neon;
    s_table[SLCP_OP_SUM ][SLCP_ISA_NEON]   = slcp_sum_neon;
    s_table[SLCP_OP_SMAX][SLCP_ISA_NEON]   = slcp_softmax_neon;
    s_table[SLCP_OP_CONV][SLCP_ISA_NEON]   = slcp_conv2d_neon;
#endif
}

static void slcp_ensure_ready(void)
{
    if (s_init_state == 2)
    {
        return;
    }
    /* 抢占执行权：抢到者检测 + 填表 + 置 2；没抢到者自旋等 2。 */
    if (InterlockedCompareExchange(&s_init_state, 1, 0) == 0)
    {
        s_isa_hw = slcp_detect_x64();
        s_isa = s_isa_hw;
        slcp_fill_table();
        InterlockedExchange(&s_init_state, 2);
    }
    else
    {
        while (s_init_state != 2)
        {
            Sleep(0);
        }
    }
}

/* ========================================================================
 * 错误 / 版本 / 检测入口
 * ======================================================================== */

SLCP_API int32_t slcp_last_error(void)
{
    return t_last;
}

SLCP_API const char* slcp_error_string(int32_t err)
{
    if (err == 0)
    {
        err = t_last;
    }
    switch (err)
    {
    case 0:
        return "ok";
    case SLCP_E_BAD_PARAM:
        return "bad parameter (null pointer or non-positive dimension)";
    case SLCP_E_UNSUPPORTED:
        return "no kernel implementation for the active ISA";
    default:
    {
        /* 未知码：格式化进线程局部缓冲（不覆盖 t_last）。 */
        char* p = t_msg;
        const char* s = "unknown slcp error ";
        while (*s) { *p++ = *s++; }
        /* 十进制直写，避免依赖 sprintf。 */
        int32_t v = err < 0 ? -err : err;
        char digits[12];
        int n = 0;
        do { digits[n++] = (char)('0' + (v % 10)); v /= 10; } while (v > 0);
        if (err < 0) { *p++ = '-'; }
        while (n > 0) { *p++ = digits[--n]; }
        *p = '\0';
        return t_msg;
    }
    }
}

SLCP_API int32_t slcp_init(void)
{
    slcp_ensure_ready();
    return 1;
}

SLCP_API int32_t slcp_isa_id(void)
{
    slcp_ensure_ready();
    return s_isa;
}

SLCP_API const char* slcp_isa_name(void)
{
    static const char* names[SLCP_ISA_COUNT] =
    {
        "SSE2", "AVX2", "AVX512", "NEON"
    };
    slcp_ensure_ready();
    return names[s_isa];
}

/* 测试钩子（vm_sl_cpu.h 注释）：目标档四个 kernel 表项全非 NULL 才
   切换；isa < 0 恢复硬件检测档。非线程安全，仅一致性测试调用。 */
SLCP_API int32_t slcp_force_isa(int32_t isa)
{
    slcp_ensure_ready();
    if (isa < 0)
    {
        s_isa = s_isa_hw;
    }
    else if (isa < SLCP_ISA_COUNT)
    {
        if (s_table[SLCP_OP_MMUL][isa] && s_table[SLCP_OP_SUM][isa] &&
            s_table[SLCP_OP_SMAX][isa] && s_table[SLCP_OP_CONV][isa])
        {
            s_isa = isa;
        }
    }
    return s_isa;
}

SLCP_API int32_t slcp_has_fma(void)
{
    slcp_ensure_ready();
    return s_has_fma;
}

SLCP_API int32_t slcp_version(void)
{
    return 0x00000001;   /* 0.1 */
}

/* ========================================================================
 * Tier-1 kernel 入口（分派 + 参数校验）
 * ----------------------------------------------------------------------
 * 校验只做系统边界检查（空指针 / 维度非正）；块大小无法得知（SL 侧
 * Memory 块不携带长度），布局正确性由调用方（Tensora 桥）保证——
 * 与 slc_kernel_launch 对 params 布局"不感知"的契约一致。
 * ======================================================================== */

static int32_t slcp_dispatch(int32_t op, const float* p0, const float* p1,
                             float* p2, const int32_t* cfg)
{
    t_last = 0;
    slcp_ensure_ready();
    if (!p0 || !p1 || !p2 || !cfg)
    {
        t_last = SLCP_E_BAD_PARAM;
        return 0;
    }
    slcp_fn_t fn = s_table[op][s_isa];
    if (!fn)
    {
        t_last = SLCP_E_UNSUPPORTED;
        return 0;
    }
    if (!fn(p0, p1, p2, cfg))
    {
        if (t_last == 0)
        {
            t_last = SLCP_E_BAD_PARAM;
        }
        return 0;
    }
    return 1;
}

SLCP_API int32_t slcp_matmul_f32(const float* a, const float* b,
                                 float* out, const int32_t* cfg)
{
    /* cfg = { m, n, k }，维度必须为正。 */
    if (cfg && (cfg[0] <= 0 || cfg[1] <= 0 || cfg[2] <= 0))
    {
        t_last = SLCP_E_BAD_PARAM;
        return 0;
    }
    return slcp_dispatch(SLCP_OP_MMUL, a, b, out, cfg);
}

SLCP_API int32_t slcp_sum_f32(const float* x, float* out,
                              const int32_t* cfg)
{
    /* cfg = { n }，n >= 0（n == 0 时 out[0] = 0，与 L0 空和一致）。 */
    if (cfg && cfg[0] < 0)
    {
        t_last = SLCP_E_BAD_PARAM;
        return 0;
    }
    return slcp_dispatch(SLCP_OP_SUM, x, x, out, cfg);
}

SLCP_API int32_t slcp_softmax_f32(const float* x, float* out,
                                  const int32_t* cfg)
{
    /* cfg = { rows, cols }。 */
    if (cfg && (cfg[0] <= 0 || cfg[1] <= 0))
    {
        t_last = SLCP_E_BAD_PARAM;
        return 0;
    }
    return slcp_dispatch(SLCP_OP_SMAX, x, x, out, cfg);
}

SLCP_API int32_t slcp_conv2d_f32(const float* in, const float* wt,
                                 float* out, const int32_t* cfg)
{
    /* cfg = { C, H, W, k, stride, padding, outH, outW }。 */
    if (cfg && (cfg[0] <= 0 || cfg[1] <= 0 || cfg[2] <= 0 ||
                cfg[3] <= 0 || cfg[4] <= 0 || cfg[6] <= 0 || cfg[7] <= 0))
    {
        t_last = SLCP_E_BAD_PARAM;
        return 0;
    }
    return slcp_dispatch(SLCP_OP_CONV, in, wt, out, cfg);
}
