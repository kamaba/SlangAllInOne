# Dtype —— 张量元素类型（枚举 + 宽度/命名表）
#
# 设计文档：TensoraBackend.md §4.1
# 阶段支持：P1 仅 F32（现状不动）+ I32（索引/label 张量）；
#           F16/BF16 待 Float16 算术语义验证后排期（OQ-3）
#
# 约束：枚举成员逐成员显式赋值（SL 未赋值成员默认全为 0，
#       历史上 EDeviceKind 曾因此让 GPU/NPU 与 CPU 混淆为 0）

enum EDtype
{
    F32 = 0
    F16 = 1
    BF16 = 2
    I32 = 3
    I64 = 4
    BOOL = 5
}

public class Dtype
{
    # 元素宽度（字节）。对齐 Core.Memory.sizeOf 宽度表
    # （Memory.sl：bool/i8/u8=1，i16/u16/f16=2，i32/u32/f32=4，i64/u64/f64=8）
    public static Int32 bytesOf( Int32 dtype )
    {
        if dtype == EDtype.F32
        {
            ret 4
        }
        if dtype == EDtype.F16
        {
            ret 2
        }
        if dtype == EDtype.BF16
        {
            ret 2
        }
        if dtype == EDtype.I32
        {
            ret 4
        }
        if dtype == EDtype.I64
        {
            ret 8
        }
        if dtype == EDtype.BOOL
        {
            ret 1
        }
        ret 0
    }

    public static string nameOf( Int32 dtype )
    {
        if dtype == EDtype.F32
        {
            ret "f32"
        }
        if dtype == EDtype.F16
        {
            ret "f16"
        }
        if dtype == EDtype.BF16
        {
            ret "bf16"
        }
        if dtype == EDtype.I32
        {
            ret "i32"
        }
        if dtype == EDtype.I64
        {
            ret "i64"
        }
        if dtype == EDtype.BOOL
        {
            ret "bool"
        }
        ret "unknown"
    }

    # 库默认类型：F32（与现有 Tensor 存储一致）
    public static Int32 defaultDtype()
    {
        ret EDtype.F32
    }

    override string toString()
    {
        ret "Dtype"
    }
}
