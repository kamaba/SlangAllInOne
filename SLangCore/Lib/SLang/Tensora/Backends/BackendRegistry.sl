# Backends —— 后端注册与能力探测（分发层骨架）
#
# 设计文档：TensoraBackend.md §4.4 / §5
# P1 范围：
#   - CPU 路径直通（黄金基准，Tensor 方法内直接实现）
#   - 非 CPU 后端 available() 恒 false（P2 起 CUDA 查询 SLangCuda 桥模块）
#   - 影子缓冲状态机在 CPU 路径下 I1-I4 恒成立（无设备侧影子）
#   - 传值原语（uploadFlow/downloadFlow，§5.2.1/5.2.2）P2 随桥模块实现
#
# 错误通道：BackendError（enum extends Error），D4 显式失败不静默回落

public enum BackendError extends Error
{
    Unavailable = { code = 1, message = "backend not available" }
    UnsupportedOp = { code = 2, message = "op not implemented on this backend" }
    DeviceMismatch = { code = 3, message = "tensors on different devices" }
    ShapeBroadcast = { code = 4, message = "shapes not broadcastable" }
}

public class Backends
{
    # ── 开关（工程规约：新增开关默认关闭，显式开启才生效）──
    # P1 为静态字段；jsonc data.* 注入通道在 P2 接桥模块时一并接线
    static bool _cudaEnabled = false
    static bool _rocmEnabled = false
    static bool _npuEnabled = false
    static bool _tpuEnabled = false
    static bool _fallbackToCpu = false

    public static void setCudaEnabled( bool v )
    {
        Backends._cudaEnabled = v
    }

    public static void setRocmEnabled( bool v )
    {
        Backends._rocmEnabled = v
    }

    public static void setNpuEnabled( bool v )
    {
        Backends._npuEnabled = v
    }

    public static void setTpuEnabled( bool v )
    {
        Backends._tpuEnabled = v
    }

    # D4：跨设备运算回落 CPU 的逃生门（默认关；开启即偏离黄金基准路径）
    public static void setFallbackToCpu( bool v )
    {
        Backends._fallbackToCpu = v
    }

    public static bool isFallbackToCpu()
    {
        ret Backends._fallbackToCpu
    }

    # ── 能力探测（§4.4）──────────────────────────────────
    # kind 为 EDeviceKind 值；CPU 恒可用；其余待桥模块接入
    public static bool available( Int32 kind )
    {
        if kind == EDeviceKind.CPU
        {
            ret true
        }
        # P2 起：GPU -> Backends._cudaEnabled && Cuda.initialize() && Cuda.deviceCount() > 0
        # P3 起：ROCM -> 同构查询 SLangRocm 桥模块
        # P4/P5：NPU / TPU -> 插件规约（§6.4/§6.5）
        ret false
    }

    # ── 运算前设备检查（§5.2.5 跨设备矩阵）───────────────
    # a / b 为参与二元运算的两个张量设备（null ≡ cpu）：
    #   cpu × cpu        -> 放行（黄金基准路径）
    #   同类同号设备      -> 放行（P2 起设备 kernel 路径）
    #   其余（含跨设备）  -> BackendError.DeviceMismatch（fallback 开启时放行）
    public static void checkPair( Device a, Device b ) throws
    {
        if Device.bothCpu( a, b )
        {
            ret
        }
        Device da = a
        if da == null
        {
            da = Device.cpu()
        }
        Device db = b
        if db == null
        {
            db = Device.cpu()
        }
        if da.sameDevice( db )
        {
            ret
        }
        if Backends._fallbackToCpu
        {
            ret
        }
        throw BackendError.DeviceMismatch
    }

    override string toString()
    {
        ret "Backends(cpu)"
    }
}
