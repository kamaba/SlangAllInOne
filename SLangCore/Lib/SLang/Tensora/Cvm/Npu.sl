# =========================================================================
# Npu —— cvm 的 NPU / 神经网络处理器平台 FFI 中间接口（预留骨架）
#
# 平台定位：NPU 类神经网络加速器（昇腾 Ascend ACL / 高通 QNN /
# Apple ANE / 厂商 NPU SDK）。按 TensoraBackend.md §6.4 插件规约接入：
#   - 原生层：cvm_sl_tensora_lib.vcxproj 内追加平台源文件（前缀建议
#     sln_*），运行期解析厂商运行库（昇腾为 Linux 侧 libascendcl；
#     构建期零 SDK 依赖，与 CUDA 部分 slc_* 的 LoadLibrary 手法一致）；
#   - SL 绑定：本文件（Npu.sl）承载 @DllStaticImport 绑定 + 门面，
#     形态对齐 Cpu_x64.sl / Cuda.sl；
#   - 算子层：Backends\NpuBackend.sl（kernel/算子图封装 + §5 staging
#     协议），Backends.available(EDeviceKind.NPU) 接入分派。
#
# 目标能力（平台向 Tensora 提供）：Tier-1 算子 kernel + 大模型计算
# （厂商算子图执行 / 端侧量化推理——对标 PyTorch NPU 后端的心智：
# 平台接口承载算子图编译与设备内存，Tensora 只做张量语义）。
#
# 接入状态：**预留骨架**——available() 恒 false，jsonc 开关
# tensoraNpuEnabled（默认关）待平台落地时接线。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

public class Npu
{
    # NPU 平台是否可用（骨架：恒 false；原生层落地后改为开关 + 探测）
    public static bool available()
    {
        ret false
    }

    override string toString()
    {
        ret "Npu(reserved)"
    }
}
