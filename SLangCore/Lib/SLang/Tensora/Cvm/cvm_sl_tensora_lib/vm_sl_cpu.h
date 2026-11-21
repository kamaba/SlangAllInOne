#ifndef VM_SL_CPU_H
#define VM_SL_CPU_H

/* ==========================================================================
 * vm_sl_cpu.h —— Tensora cvm 原生层导出声明（sl_tensora_lib.dll 的 CPU 部分）
 * --------------------------------------------------------------------------
 * 本库是 Tensora CPU 后端的 L1 **原生 SIMD 加速层**，与前缀 slc_ 的 CUDA
 * 部分（sl_cuda_lib.c）同处合一工程 cvm_sl_tensora_lib.vcxproj（产物
 * sl_tensora_lib.dll，jsonc vmDlls + @DllStaticImport 静态直调），差异仅
 * 一点：CUDA 部分运行期 LoadLibrary 解析 nvcuda.dll，
 * 而本库**自身就是实现**——x64 下按 SSE2 基线编译入口/检测层，各 ISA
 * kernel 分文件按 MSVC 编译开关（/arch:AVX2、/arch:AVX512）编译，
 * 首次调用时惰性 cpuid + XCR0 检测并填函数指针表，此后直达目标实现。
 *
 * x64 ISA 矩阵（设计文档 TensoraBackend.md §6.1.2）：
 *   SSE2（xmm，4 通道）  —— x64 基线，编译保底路径，恒可用
 *   AVX2（ymm，8 通道）  —— 运行期检测启用（leaf7 EBX bit5 + XCR0 YMM）
 *   AVX-512F/VL/DQ（zmm，16 通道）—— 三位齐全 + XCR0 opmask/ZMM 才启用
 *   NEON（128-bit，4 通道）—— ARM64 基线免检（slcp_kernels_neon.c 预留，
 *                             x64 工程配置不编译该文件）
 *
 * 位级一致契约（Tier-1，§6.1.4）——本库全部 kernel 与 Tensora L0 SL
 * 参考实现**逐位相同**：
 *   1) 仅用 IEEE 单舍入指令（add/mul/div/sub，每条指令独立舍入）；
 *      **禁用 FMA**（_mm*_fmadd_* 单次舍入，与参考实现 mul 后 add 两次
 *      舍入不同 → 位级偏差；融合版独立函数 slcp_*_fma 留待后续）；
 *   2) matmul / conv2d 的内积按"输出元素分组、k 标量顺序累加"组织
 *      （SIMD lane 并行的是**不同输出元素**，不是同一元素的不同 k 分量），
 *      每条 lane 的舍入序列与 L0 的 acc = acc + a*b 完全同序；
 *   3) sum / softmax 为标量顺序循环复刻 L0（softmax 的 exp 走 CRT expf，
 *      与 SL 侧 TensorMath.exp → Mathf.exp → math_lib!mathf_exp 是同一
 *      个函数，位级相同；div 同为 IEEE 单舍入）；
 *   4) 对齐与尾部：不假设 SL Memory 块对齐，SIMD 一律 unaligned
 *      load/store；尾部 AVX-512 用 mask 寄存器（越界 lane 不触碰内存），
 *      SSE2/AVX2 用标量余段。
 *
 * 导出命名约定：统一前缀 slcp_（SimpleLanguage CPU）。
 * 调用约定：x64 cdecl。参数个数上限 6（SL_FFI_MAX_ARGS）。
 *
 * 数据通路（§5.2 staging 协议的 CPU 同构版）：
 *   - SL 托管 Array<Float32> 无裸指针出口，上 kernel 前必须经 Core 的
 *     Memory.allocArray(n, "f32") + writeF32 系列组原生块（P1 staging），
 *     kernel 完成后 readF32 逐元素取回（P4）；
 *   - 主机大块数据不走 FFI 传值：块地址以 ptr（Int64 承载）传入；
 *   - 整数参数超过直接形参时打包为 cfg 描述块（Memory.allocArray 组装
 *     i32 数组，布局见各 kernel 注释，参照 slc_kernel_launch 的 40 字节
 *     启动描述块模式）。
 *
 * 错误约定（与 slc_* 的 bool 语义对齐）：
 *   - "成功与否"类导出（四个 kernel）：int32_t 1 = 成功，0 = 失败，
 *     失败原因写入粘性 last_error；
 *   - 查询类（isa_id / has_fma / version）：恒有定义值，失败不可能发生
 *     （检测失败即回落 SSE2 基线，不会失败）；
 *   - 粘性码：每个入口调用先清零再执行，调用后立刻查询即可分辨。
 *
 * 返回字符串内存约定：const char* 一律指向本库线程局部缓冲，调用方
 * 不得 free；SL 侧在返回瞬间即拷走内容。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLCP_API __declspec(dllexport)
#else
#  define SLCP_API
#endif

/* ------------------------------------------------------------------ */
/* 本库合成错误码（负值）                                              */
/* ------------------------------------------------------------------ */

#define SLCP_E_BAD_PARAM   (-2)   /* 参数非法（空指针 / 维度非正等） */
#define SLCP_E_UNSUPPORTED (-4)   /* 当前 ISA 无该算子实现          */

/* ------------------------------------------------------------------ */
/* ISA 与算子标识（函数指针表下标）                                    */
/* ------------------------------------------------------------------ */

/* x64 检测后实际生效档；ARM64 恒 NEON。值同时是 isa_name 的索引。 */
#define SLCP_ISA_SSE2    0
#define SLCP_ISA_AVX2    1
#define SLCP_ISA_AVX512  2
#define SLCP_ISA_NEON    3
#define SLCP_ISA_COUNT   4

/* Tier-1 首批算子（§6.1.3：只覆盖计算密集算子，elementwise 不做）。 */
#define SLCP_OP_MMUL 0        /* matmul  (m,k)x(k,n)          */
#define SLCP_OP_SUM  1        /* 全量 sum                     */
#define SLCP_OP_SMAX 2        /* 逐行 softmax（最后一维）      */
#define SLCP_OP_CONV 3        /* conv2d 单输出通道            */
#define SLCP_OP_COUNT 4

/* ------------------------------------------------------------------ */
/* 错误 / 版本 / 检测                                                  */
/* ------------------------------------------------------------------ */

/* 粘性最近错误码：0 = 无错。每个 slcp_ 入口调用都会先清零再执行。 */
SLCP_API int32_t     slcp_last_error(void);
/* 错误码转文本；err == 0 时取 last_error。永不返回 NULL。 */
SLCP_API const char* slcp_error_string(int32_t err);

/* 触发 ISA 检测 + 填函数指针表。幂等：重复调用安全；实际无需显式调用
   ——全部 kernel 入口会自动惰性检测（首次调用零额外开销由后续直达保证）。 */
SLCP_API int32_t     slcp_init(void);

/* 当前生效 ISA（SLCP_ISA_* ；未检测前调用会先触发检测）。 */
SLCP_API int32_t     slcp_isa_id(void);

/* 当前生效 ISA 名（"SSE2" / "AVX2" / "AVX512" / "NEON"，线程局部缓冲）。 */
SLCP_API const char* slcp_isa_name(void);

/* 测试钩子：强制切换生效 ISA（一致性测试做 SSE2/AVX2 两档位级断言用，
   非线程安全、勿在业务路径调用）。isa 取 SLCP_ISA_*；仅当目标档全部
   四个 kernel 表项非 NULL 时切换（x64 上 NEON 档为 NULL 会拒绝）。
   isa < 0 恢复硬件检测档。返回切换后的生效 ISA id。 */
SLCP_API int32_t     slcp_force_isa(int32_t isa);

/* CPU 是否具备 FMA3（leaf1 ECX bit12 + XCR0）。Tier-1 kernel 恒不使用
   FMA（位级一致契约，§6.1.4）；本查询仅供上层决定是否启用后续的
   slcp_*_fma 融合旁路（jsonc tensoraFmaEnabled，默认关）。 */
SLCP_API int32_t     slcp_has_fma(void);

/* 库版本：(major << 16) | minor，当前 0x00000001 = 0.1。 */
SLCP_API int32_t     slcp_version(void);

/* ------------------------------------------------------------------ */
/* Tier-1 kernel（四参统一形态：数据块 ptr x3 + cfg 描述块 ptr）        */
/*                                                                      */
/* 形参均为 SL 侧 Memory 原生块地址（Int64 位模式承载）；cfg 为 i32     */
/* 数组块。全部返回 int32_t：1 = 成功，0 = 失败（见 last_error）。      */
/*                                                                      */
/* 位级一致：同输入下，本 DLL 任一 ISA 档与 L0 SL 参考实现输出逐位     */
/* 相同（见文件头"位级一致契约"）。                                    */
/* ------------------------------------------------------------------ */

/* 矩阵乘：a[m,k] * b[k,n] -> out[m,n]（全部行主序 f32）。
   cfg = { m, n, k }（3 个 i32）。对应 Tensor.matmul（Tensor.sl L0：
   acc=0 按 k 标量序累加 acc + a[i][p]*b[p][j]）。 */
SLCP_API int32_t slcp_matmul_f32(const float* a, const float* b,
                                 float* out, const int32_t* cfg);

/* 全量求和：out[0] = sum(x[0..n))。cfg = { n }（1 个 i32）。
   标量顺序累加（与 L0 Tensor.sum 逐位相同）。 */
SLCP_API int32_t slcp_sum_f32(const float* x, float* out,
                              const int32_t* cfg);

/* 逐行 softmax（最后一维）：x[rows,cols] -> out[rows,cols]。
   cfg = { rows, cols }（2 个 i32）。位级复刻 L0 Tensor.softmax：
   行 max（严格 > 首值优先）→ denom = sum expf(x-mx)（标量序）→
   expf(x-mx)/denom。 */
SLCP_API int32_t slcp_softmax_f32(const float* x, float* out,
                                  const int32_t* cfg);

/* 单通道卷积：in[C,H,W] * wt[C,k,k] -> out[1,outH,outW]（行主序 f32）。
   cfg = { C, H, W, k, stride, padding, outH, outW }（8 个 i32，调用方
   按 L0 Ops.conv2d 同公式预算 outH/outW）。stride==1 时 ox 分段 SIMD
   （(ch,ky,kx) 累加顺序与 L0 一致），其余情形标量 L0 顺序。 */
SLCP_API int32_t slcp_conv2d_f32(const float* in, const float* wt,
                                 float* out, const int32_t* cfg);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_CPU_H */
