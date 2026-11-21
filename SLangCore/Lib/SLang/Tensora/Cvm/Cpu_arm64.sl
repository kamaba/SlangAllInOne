# =========================================================================
# Cpu_arm64 —— cvm 的 ARM64（AArch64）CPU 平台 FFI 中间接口
#
# 平台定位：ARM64 构建的 sl_tensora_lib.dll 之 slcp_* kernel（NEON 为
# AArch64 基线指令集，免运行期检测——sl_cpu_lib.c 在 ARM64 下恒选
# SLCP_ISA_NEON；实现见 cvm_sl_tensora_lib\slcp_kernels_neon.c，符号名
# 与 SSE2/AVX2/AVX-512 版完全对齐，slcp_* 为平台中立符号面）。
#
# 接入状态：**预留骨架**。当前 Tensora 仅配置 x64 构建（vcxproj 无
# ARM64 平台配置，NEON kernel 不编译）；ARM64 构建启用时：
#   1) cvm_sl_tensora_lib.vcxproj 追加 ARM64 平台并将 slcp_kernels_neon.c
#      纳入 ClCompile（见该文件头注释）；
#   2) 本接口即与 Cpu_x64 同符号面（slcp_* 绑定写法一致，可按需从
#      Cpu_x64.sl 镜像绑定段）；
#   3) Backends 的 SIMD executor 调用点由 Cpu_x64.* 切换为 Cpu_arm64.*
#      （或届时引入编译期平台选择）。
#
# available() 判定：slcp_isa_id() == ISA_NEON（ARM64 构建下恒真；
# x64 构建下恒 false——本类在 x64 构建中仅为占位，不参与分派）。
#
# 目标能力（平台向 Tensora 提供）：Tier-1 算子 kernel（位级一致契约
# 同 §6.1.4）+ 后续大模型计算 kernel（ARM NEON/ SME 路径）。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

public class Cpu_arm64
{
    # ARM64 平台是否可用（= 当前生效 ISA 为 NEON；经 Cpu_x64 的
    # slcp_isa_id 探测——符号面同源，无需重复绑定）
    public static bool available()
    {
        ret Cpu_x64.isaId() == Cpu_x64.ISA_NEON
    }

    override string toString()
    {
        ret "Cpu_arm64(" + ( Cpu_arm64.available() ? "available" : "not built" ) + ")"
    }
}
