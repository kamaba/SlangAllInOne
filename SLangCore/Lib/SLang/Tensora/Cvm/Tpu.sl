# =========================================================================
# Tpu —— cvm 的 TPU / 专用张量加速器平台 FFI 中间接口（预留骨架）
#
# 平台定位：TPU 类专用张量处理器（Google TPU / TPU-like 脉动阵列 /
# 厂商张量加速卡）。按 TensoraBackend.md §6.5 规约接入：
#   - 原生层：cvm_sl_tensora_lib.vcxproj 内追加平台源文件（前缀建议
#     slt_*），运行期解析厂商 SDK / 驱动（对齐 CUDA 部分 slc_* 的
#     LoadLibrary 手法，构建期零 SDK 依赖）；
#   - SL 绑定：本文件（Tpu.sl）承载 @DllStaticImport 绑定 + 门面，
#     形态对齐 Cpu_x64.sl / Cuda.sl；
#   - 算子层：Backends\TpuBackend.sl（kernel 封装 + §5 staging 协议），
#     Backends.available(EDeviceKind.TPU) 接入分派。
#
# 目标能力（平台向 Tensora 提供）：Tier-1 算子 kernel + 大模型计算
# （脉动阵列矩阵乘 / bfloat16 / TPU 编译器图执行——对标 PyTorch XLA
# 的心智：平台接口承载编译器入口与设备内存，Tensora 只做张量语义）。
#
# 接入状态：**预留骨架**——available() 恒 false，jsonc 开关
# tensoraTpuEnabled（默认关）待平台落地时接线。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

public class Tpu
{
    # TPU 平台是否可用（骨架：恒 false；原生层落地后改为开关 + 探测）
    public static bool available()
    {
        ret false
    }

    override string toString()
    {
        ret "Tpu(reserved)"
    }
}
