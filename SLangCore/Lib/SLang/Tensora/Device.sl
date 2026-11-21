# Device —— 计算设备抽象（跨硬件算子计算框架的设备层入口）
#
# 设计文档：TensoraBackend.md §4.2 / §5.3
# 职责：
#   1. 描述张量所在设备（kind + id）
#   2. 设备内存/显存记账（bytesUsed，供训练脚本查询占用）
#   3. 为 Backends.available(kind) 提供探测目标
#
# 注意：枚举成员逐成员显式赋值——旧版 GPU/NPU 未赋值导致全部为 0，
#       与 CPU 混淆（SL 未赋值枚举成员默认全为 0 的实证 bug，已修复）

enum EDeviceKind
{
    CPU = 0
    GPU = 1
    NPU = 2
    ROCM = 3
    TPU = 4
}

@Nickname("Device")
public class Device
{
    public Int32 kind = 0
    public Int32 id = 0
    public string name = "cpu"
    public bool available = true

    # 统计用：本设备当前分配的字节数（仅记录，不做真实内存管理）
    public Int64 bytesUsed = 0

    public void _init_()
    {
        this.kind = EDeviceKind.CPU
        this.id = 0
        this.name = "cpu"
        this.available = true
        this.bytesUsed = 0
    }

    public void _init_( Int32 kind, Int32 id )
    {
        this.kind = kind
        this.id = id
        this.available = true
        this.bytesUsed = 0
        if kind == EDeviceKind.CPU
        {
            this.name = "cpu"
        }
        else
        {
            this.name = Device.kindName( kind ) + ":" + SystemConvertString( id )
        }
    }

    # ── 判定 ─────────────────────────────────────────────
    public bool isCpu()
    {
        ret this.kind == EDeviceKind.CPU
    }

    public bool isGpu()
    {
        ret this.kind == EDeviceKind.GPU
    }

    public bool isNpu()
    {
        ret this.kind == EDeviceKind.NPU
    }

    public bool isRocm()
    {
        ret this.kind == EDeviceKind.ROCM
    }

    public bool isTpu()
    {
        ret this.kind == EDeviceKind.TPU
    }

    # 两设备同类同号才可参与同一运算（§5.2.5 跨设备矩阵）
    public bool sameDevice( Device other )
    {
        if other == null
        {
            ret this.isCpu()
        }
        ret this.kind == other.kind && this.id == other.id
    }

    # null 视为 cpu（Tensor._device 缺省 null 的约定，§4.2）
    public static bool bothCpu( Device a, Device b )
    {
        bool aCpu = a == null
        if !aCpu
        {
            aCpu = a.isCpu()
        }
        bool bCpu = b == null
        if !bCpu
        {
            bCpu = b.isCpu()
        }
        if aCpu
        {
            if bCpu
            {
                ret true
            }
        }
        ret false
    }

    # ── 工厂 ─────────────────────────────────────────────
    public static Device cpu()
    {
        ret Device( EDeviceKind.CPU, 0 )
    }

    public static Device gpu( Int32 id )
    {
        ret Device( EDeviceKind.GPU, id )
    }

    public static Device npu( Int32 id )
    {
        ret Device( EDeviceKind.NPU, id )
    }

    public static Device rocm( Int32 id )
    {
        ret Device( EDeviceKind.ROCM, id )
    }

    public static Device tpu( Int32 id )
    {
        ret Device( EDeviceKind.TPU, id )
    }

    public static string kindName( Int32 kind )
    {
        if kind == EDeviceKind.CPU
        {
            ret "cpu"
        }
        if kind == EDeviceKind.GPU
        {
            ret "cuda"
        }
        if kind == EDeviceKind.NPU
        {
            ret "npu"
        }
        if kind == EDeviceKind.ROCM
        {
            ret "rocm"
        }
        if kind == EDeviceKind.TPU
        {
            ret "tpu"
        }
        ret "unknown"
    }

    # ── 记账（§5.3：分配/释放时调用，bytesUsed 即时可见）──
    public void alloc( Int64 bytes )
    {
        this.bytesUsed = this.bytesUsed + bytes
    }

    public void free( Int64 bytes )
    {
        this.bytesUsed = this.bytesUsed - bytes
    }

    override string toString()
    {
        ret "Device(" + this.name + ")"
    }
}
