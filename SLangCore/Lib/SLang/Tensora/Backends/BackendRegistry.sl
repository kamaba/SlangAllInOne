 Backends —— 后端注册与能力探测（分发层骨架）
#
# 设计文档：TensoraBackend.md §4.4 / §5
# P1 范围：
#   - CPU 路径直通（黄金基准，Tensor 方法内直接实现）
#   - 非 CPU 后端 available() 恒 false（CUDA 随 cvm 平台整合接入，不依赖外部 SLangCuda 模块）
#   - 影子缓冲状态机在 CPU 路径下 I1-I4 恒成立（无设备侧影子）
#   - 传值原语（uploadFlow/downloadFlow，§5.2.1/5.2.2）P2 随桥模块实现
# P2B（CPU L1 SIMD 分派，§6.1.1/§6.1.3）：
#   - 总开关 tensoraSimdEnabled（默认 false，运行期 setSimdEnabled() 开启）+ 阈值表
#   - simd*On gate（算子×规模）+ simd*Array executor（P1 上载 →
#     sl_cpu_lib kernel → P4 下载，失败 ret null 回落 L0）
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
        # P2A：GPU → cvm CUDA 平台（驱动 API 运行期解析 nvcuda.dll）
        if kind == EDeviceKind.GPU
        {
            ret Backends._cudaEnabled && CudaBackend.cudaOk()
        }
        # P3 起：ROCM -> 同构查询（cvm 平台接入时在此追加）
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

    # ================================================================
    # CPU L1 SIMD 分派（§6.1.1 / §6.1.3，P2B）
    #
    # Tensor / Ops 侧只做前置检查（rank / dtype / 稠密）+ 调用：
    #   gate（simd*On）      ：总开关 + DLL 绑定就绪 + 算子×规模阈值表
    #   executor（simd*Array）：P1 上载 → sl_cpu_lib kernel → P4 下载，
    #                          任一步失败 ret null，调用方无脑回落 L0
    # 阈值不预估（§6.1.3-2）：以下为基准落盘前的保守初值，
    # 由 §6.1.7 验收基准（out\probe）校准后写回。
    # ================================================================

    # SIMD 总开关默认 false（jsonc data.tensoraSimdEnabled 仅声明性文档：
    # 库工程无 Project 类，data.* 注入通道不生效）
    static bool _simdEnabled = false

    # -2 未探测 / -1 DLL 兜底（cvm DLL 绑定失败）/ >=0 生效 ISA id
    static Int32 _simdIsa = -2

    # 阈值表（Int64 防乘加体积溢出）
    static Int64 T_MMUL = 262144    # matmul：m*k*n 乘加体积（= 64³）
    static Int64 T_SUM  = 65536     # sum：元素数
    static Int64 T_SMAX = 65536     # softmax：rows*cols
    static Int64 T_CONV = 262144    # conv2d：c*c*outH*outW*k*k 乘加体积

    public static void setSimdEnabled( bool v )
    {
        Backends._simdEnabled = v
    }

    public static bool isSimdEnabled()
    {
        ret Backends._simdEnabled
    }

    # 当前生效 ISA 名（测试 / 基准用）；未就绪时空串
    public static string simdIsaName()
    {
        if !Backends.simdReady()
        {
            ret ""
        }
        ret Cpu_x64.isaName()
    }

    # 内部：总开关 + cvm DLL 绑定就绪（isaId() >= 0；结果缓存）
    static bool simdReady()
    {
        if !Backends._simdEnabled
        {
            ret false
        }
        if Backends._simdIsa == -2
        {
            Backends._simdIsa = Cpu_x64.isaId()
            if Backends._simdIsa >= 0
            {
                Cpu_x64.initialize()
            }
        }
        ret Backends._simdIsa >= 0
    }

    # ── gate：算子 × 规模是否分派 L1 ─────────────────────

    public static bool simdMatmulOn( Int32 m, Int32 k, Int32 n )
    {
        if !Backends.simdReady()
        {
            ret false
        }
        Int64 mm = m
        Int64 kk = k
        Int64 nn = n
        ret mm * kk * nn > Backends.T_MMUL
    }

    public static bool simdSumOn( Int32 n )
    {
        if !Backends.simdReady()
        {
            ret false
        }
        Int64 nn = n
        ret nn > Backends.T_SUM
    }

    public static bool simdSoftmaxOn( Int32 rows, Int32 cols )
    {
        if !Backends.simdReady()
        {
            ret false
        }
        Int64 rr = rows
        Int64 cc = cols
        ret rr * cc > Backends.T_SMAX
    }

    public static bool simdConv2dOn( Int32 c, Int32 outH, Int32 outW, Int32 k )
    {
        if !Backends.simdReady()
        {
            ret false
        }
        Int64 cc = c
        Int64 oh = outH
        Int64 ow = outW
        Int64 kk = k
        ret cc * cc * oh * ow * kk * kk > Backends.T_CONV
    }

    # ── executor：OQ-1 零拷贝（数组 data 指针直接喂 kernel；输出预分配
    #    数组直写；无独立块无 free）；null = 回落 L0 ──

    # a[m,k] * b[k,n] -> r[m,n]（行主序稠密 f32）
    public static Array<Float32> simdMatmulArray( Array<Float32> a, Array<Float32> b,
                                                  Int32 m, Int32 n, Int32 k )
    {
        Array<Float32> r = Array<Float32>( m * n )
        Int64 aBlk = Cpu_x64.pinF32( a )
        Int64 bBlk = Cpu_x64.pinF32( b )
        Int64 oBlk = Cpu_x64.pinF32( r )
        if aBlk == 0 || bBlk == 0 || oBlk == 0
        {
            ret null
        }
        if !Cpu_x64.matmul( aBlk, bBlk, oBlk, m, n, k )
        {
            ret null
        }
        ret r
    }

    # r[0] = sum(x)；1 元素数组承载（SL 无可空值类型）
    public static Array<Float32> simdSumArray( Array<Float32> x )
    {
        Array<Float32> r = Array<Float32>( 1 )
        Int64 xBlk = Cpu_x64.pinF32( x )
        Int64 oBlk = Cpu_x64.pinF32( r )
        if xBlk == 0 || oBlk == 0
        {
            ret null
        }
        if !Cpu_x64.sum( xBlk, oBlk, x.length )
        {
            ret null
        }
        ret r
    }

    # x[rows,cols] -> r[rows,cols]（逐行最后维 softmax）
    public static Array<Float32> simdSoftmaxArray( Array<Float32> x,
                                                   Int32 rows, Int32 cols )
    {
        Array<Float32> r = Array<Float32>( rows * cols )
        Int64 xBlk = Cpu_x64.pinF32( x )
        Int64 oBlk = Cpu_x64.pinF32( r )
        if xBlk == 0 || oBlk == 0
        {
            ret null
        }
        if !Cpu_x64.softmax( xBlk, oBlk, rows, cols )
        {
            ret null
        }
        ret r
    }

    # in[c,h,w] * wt[c,k,k] -> r[1,outH,outW]（与 Ops.conv2d L0 同形）
    public static Array<Float32> simdConv2dArray( Array<Float32> input, Array<Float32> kernel,
                                                  Int32 c, Int32 h, Int32 w,
                                                  Int32 k, Int32 stride, Int32 padding,
                                                  Int32 outH, Int32 outW )
    {
        Array<Float32> r = Array<Float32>( outH * outW )
        Int64 iBlk = Cpu_x64.pinF32( input )
        Int64 wBlk = Cpu_x64.pinF32( kernel )
        Int64 oBlk = Cpu_x64.pinF32( r )
        if iBlk == 0 || wBlk == 0 || oBlk == 0
        {
            ret null
        }
        if !Cpu_x64.conv2d( iBlk, wBlk, oBlk,
                                               c, h, w, k, stride, padding, outH, outW )
        {
            ret null
        }
        ret r
    }
}
