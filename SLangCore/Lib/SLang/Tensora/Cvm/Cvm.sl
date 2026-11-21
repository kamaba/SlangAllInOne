# =========================================================================
# Cvm —— Tensora 统一硬件算子计算平台（cvm）：平台聚合 / 兼容门面
#
# cvm 目标：兼容所有硬件平台，平台提供算子与大模型计算。全部原生
# 实现收在 Tensora\Cvm\ 下（单一 cvm_sl_tensora_lib.vcxproj 合一工程，
# 产物 sl_tensora_lib.dll），不依赖外部 SLangCpu/SLangCuda 模块。
# 每平台一个 FFI 中间接口文件，Tensora 直接调用：
#
#   Cvm\Cpu_x64.sl    x86-64 CPU（slcp_*：SSE2 基线 / AVX2 / AVX-512
#                     运行期检测分派）——实体接口
#   Cvm\Cpu_arm64.sl  ARM64 CPU（slcp_* 符号面同源，NEON 基线）——
#                     预留骨架（ARM64 构建启用）
#   Cvm\Cuda.sl       NVIDIA GPU（slc_*：驱动 API 运行期解析 nvcuda.dll，
#                     P2A 算子层 Backends\CudaBackend.sl 已接入）——实体接口
#   Cvm\Tpu.sl        TPU / 专用张量加速器（§6.5 规约）——预留骨架
#   Cvm\Npu.sl        NPU / 神经网络处理器（昇腾 ACL 等，§6.4 规约）——
#                     预留骨架
#
# 本类（Cvm）为 **CPU 侧聚合兼容门面**：全部方法一对一委托当前构建
# 平台的 CPU 接口（x64 构建委托 Cpu_x64）。新代码直接调平台接口
# （Cpu_x64.* / Cuda.* / ...）；本门面保留 Backends / 测试的既有引用
# 与"当前 CPU 平台"的统一查询入口。
#
# 命名空间由 Tensora.jsonc struct 树定义（namespace Tensora / class Cvm），
# 文件内不声明 namespace 块（同工程其余文件约定一致）。
#
# 位级一致契约（Tier-1，TensoraBackend.md §6.1.4）与错误约定见
# Cpu_x64.sl 头注释。
# =========================================================================

public class Cvm
{
    # ── ISA 标识（透传 Cpu_x64，与 vm_sl_cpu.h 对齐）──

    public static Int32 ISA_SSE2 = 0
    public static Int32 ISA_AVX2 = 1
    public static Int32 ISA_AVX512 = 2
    public static Int32 ISA_NEON = 3

    # ── 检测 / 查询（委托当前构建平台的 CPU 接口）─────────

    public static bool initialize()
    {
        ret Cpu_x64.initialize()
    }

    public static Int32 isaId()
    {
        ret Cpu_x64.isaId()
    }

    public static string isaName()
    {
        ret Cpu_x64.isaName()
    }

    public static Int32 forceIsa( Int32 isa )
    {
        ret Cpu_x64.forceIsa( isa )
    }

    public static bool hasFma()
    {
        ret Cpu_x64.hasFma()
    }

    public static Int32 version()
    {
        ret Cpu_x64.version()
    }

    public static Int32 lastError()
    {
        ret Cpu_x64.lastError()
    }

    public static string errorString()
    {
        ret Cpu_x64.errorString()
    }

    # ── Tier-1 kernel（委托）────────────────────────────────

    public static bool matmul( Int64 aBlk, Int64 bBlk, Int64 oBlk,
                               Int32 m, Int32 n, Int32 k )
    {
        ret Cpu_x64.matmul( aBlk, bBlk, oBlk, m, n, k )
    }

    public static bool sum( Int64 xBlk, Int64 oBlk, Int32 n )
    {
        ret Cpu_x64.sum( xBlk, oBlk, n )
    }

    public static bool softmax( Int64 xBlk, Int64 oBlk,
                                Int32 rows, Int32 cols )
    {
        ret Cpu_x64.softmax( xBlk, oBlk, rows, cols )
    }

    public static bool conv2d( Int64 inBlk, Int64 wtBlk, Int64 oBlk,
                               Int32 c, Int32 h, Int32 w,
                               Int32 k, Int32 stride, Int32 padding,
                               Int32 outH, Int32 outW )
    {
        ret Cpu_x64.conv2d( inBlk, wtBlk, oBlk,
                            c, h, w, k, stride, padding, outH, outW )
    }

    # ── staging 辅助（委托）─────────────────────────────────

    public static Int64 uploadF32( Array<Float32> values )
    {
        ret Cpu_x64.uploadF32( values )
    }

    public static Int64 pinF32( Array<Float32> values )
    {
        ret Cpu_x64.pinF32( values )
    }

    public static Array<Float32> downloadF32( Int64 addr, Int32 count )
    {
        ret Cpu_x64.downloadF32( addr, count )
    }

    public static void freeBlock( Int64 addr )
    {
        Cpu_x64.freeBlock( addr )
    }

    override string toString()
    {
        ret "Cvm(cpu=" + Cpu_x64.isaName() + ", cuda=" + ( CudaBackend.cudaOk() ? "on" : "off" ) + ")"
    }
}
