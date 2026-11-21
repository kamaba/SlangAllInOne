# =========================================================================
# Cpu_x64 —— cvm 的 x86-64 CPU 平台 FFI 中间接口
#
# 平台定位：x64 构建的 sl_tensora_lib.dll 之 slcp_* kernel（SSE2 基线 /
# AVX2 / AVX-512 运行期检测分派；自有 C 实现，零外部依赖）。Tensora
# （Backends / Tensor 算子层）直接调用本接口；Cvm.sl 为兼容聚合门面。
# 姊妹接口：Cpu_arm64.sl（ARM64/NEON）、Cuda.sl（NVIDIA GPU）、
# Tpu.sl / Npu.sl（预留）。
#
# 目标能力（平台向 Tensora 提供）：Tier-1 算子 kernel（matmul/sum/
# softmax/conv2d，位级一致）+ 后续大模型计算 kernel（量化矩阵乘 /
# flash-attention 等，随平台接口扩展）。
#
# 用法：
#   Cpu_x64.initialize()      # 惰性 cpuid+XCR0 检测，幂等
#   Cpu_x64.isaName()         # "SSE2" / "AVX2" / "AVX512"
#
#   # Tensora staging 协议（§5.2 的 CPU 同构版，OQ-1 零拷贝）：
#   Array<Float32> ro = Array<Float32>( m * n )
#   Int64 a = Cpu_x64.pinF32( ta._data )   # 数组裸 data 指针（勿 free）
#   Int64 o = Cpu_x64.pinF32( ro )
#   Cpu_x64.matmul( a, b, o, m, n, k )     # L1 kernel 直写 ro
#
# 底层链路：
#   Cpu_x64.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_tensora_lib.dll（slcp_*）
#     首次调用惰性检测 ISA（SSE2 基线 → AVX2 → AVX-512F/VL/DQ，CPUID+
#     XCR0 双校验）并填函数指针表，此后直达目标实现（每调用零检测开销）。
#
# 位级一致契约（Tier-1，TensoraBackend.md §6.1.4）：全部 kernel 与
# Tensora L0 SL 参考实现逐位相同——仅 IEEE 单舍入指令（add/mul/div）、
# 禁 FMA（单次舍入）、SIMD lane 并行不同输出元素而 k 方向标量顺序累加、
# softmax 的 exp 走 CRT expf（与 Mathf.exp → math_lib!mathf_exp 同函数）。
#
# 错误处理以返回值表达（false / 0 / 空串），原因经 lastError() /
# errorString() 取得（粘性：每次原生入口调用先清零）。DLL 不可用时
# 兜底（lib* 函数体生效）：libIsaId() 返回 -1 即兜底征兆。
#
# 注意：所有类型必须是 namespace 下的顶级类型（不能嵌套在类内）。
# =========================================================================

# ===================================================================
# Cpu_x64 —— x64 平台入口类 + 低层绑定
#
# lib* 系列是 sl_tensora_lib.dll（slcp_*）的直接映射（函数体 = DLL 不可用时的
# 兜底返回值），通常不必直接使用；initialize() / matmul() 等门面
# 供业务使用。含 ptr 形参的绑定必须手写 sig（FFI 短名）。
# ===================================================================
public class Cpu_x64
{
    # ── ISA 标识（slcp_isa_id 返回值，与 vm_sl_cpu.h 对齐）──

    public static Int32 ISA_SSE2 = 0
    public static Int32 ISA_AVX2 = 1
    public static Int32 ISA_AVX512 = 2
    public static Int32 ISA_NEON = 3

    # ── 低层：错误 / 版本 / 检测 ───────────────────────────

    @DllStaticImport( "sl_tensora_lib", "slcp_last_error", "->i32" )
    public static Int32 libLastError()
    {
        ret 0
    }

    @DllStaticImport( "sl_tensora_lib", "slcp_error_string", "i32->utf8" )
    public static string libErrorString( Int32 err )
    {
        ret ""
    }

    # 触发 ISA 检测 + 填函数指针表。幂等；实际无需显式调用
    # （全部 kernel 入口自动惰性检测）。
    @DllStaticImport( "sl_tensora_lib", "slcp_init", "->bool" )
    public static bool libInit()
    {
        ret false
    }

    @DllStaticImport( "sl_tensora_lib", "slcp_isa_id", "->i32" )
    public static Int32 libIsaId()
    {
        ret -1
    }

    @DllStaticImport( "sl_tensora_lib", "slcp_isa_name", "->utf8" )
    public static string libIsaName()
    {
        ret ""
    }

    # 测试钩子：强制切换生效 ISA（仅当目标档 kernel 表齐备；isa < 0
    # 恢复硬件检测档）。返回切换后生效 ISA id。非线程安全，仅一致性
    # 测试做 SSE2/AVX2 两档位级断言用，业务路径勿调。
    @DllStaticImport( "sl_tensora_lib", "slcp_force_isa", "i32->i32" )
    public static Int32 libForceIsa( Int32 isa )
    {
        ret -1
    }

    # CPU 是否具备 FMA3。Tier-1 kernel 恒不用 FMA（位级一致契约）；
    # 仅供上层决定是否启用后续融合旁路（tensoraFmaEnabled，默认关）。
    @DllStaticImport( "sl_tensora_lib", "slcp_has_fma", "->bool" )
    public static bool libHasFma()
    {
        ret false
    }

    @DllStaticImport( "sl_tensora_lib", "slcp_version", "->i32" )
    public static Int32 libVersion()
    {
        ret 0
    }

    # ── 低层：Tier-1 kernel 直调 ──────────────────────────
    # ptr 形参一律为 Memory 原生块地址（Int64 位模式承载）；
    # cfg 为 i32 数组块（布局见门面方法注释）。

    # cfg = { m, n, k }：a[m,k] * b[k,n] -> out[m,n]（行主序）。
    @DllStaticImport( "sl_tensora_lib", "slcp_matmul_f32", "ptr,ptr,ptr,ptr->bool" )
    public static bool libMatmul( Int64 aBlk, Int64 bBlk, Int64 oBlk, Int64 cfgBlk )
    {
        ret false
    }

    # cfg = { n }：out[0] = sum(x[0..n))（标量序，位级同 L0）。
    @DllStaticImport( "sl_tensora_lib", "slcp_sum_f32", "ptr,ptr,ptr->bool" )
    public static bool libSum( Int64 xBlk, Int64 oBlk, Int64 cfgBlk )
    {
        ret false
    }

    # cfg = { rows, cols }：逐行 softmax（最后一维），位级复刻 L0。
    @DllStaticImport( "sl_tensora_lib", "slcp_softmax_f32", "ptr,ptr,ptr->bool" )
    public static bool libSoftmax( Int64 xBlk, Int64 oBlk, Int64 cfgBlk )
    {
        ret false
    }

    # cfg = { C,H,W,k,stride,pad,outH,outW }：
    # in[C,H,W] * wt[C,k,k] -> out[1,outH,outW]（行主序）。
    @DllStaticImport( "sl_tensora_lib", "slcp_conv2d_f32", "ptr,ptr,ptr,ptr->bool" )
    public static bool libConv2D( Int64 inBlk, Int64 wtBlk, Int64 oBlk, Int64 cfgBlk )
    {
        ret false
    }

    # ── 门面：检测 / 查询 ──────────────────────────────────

    # 惰性检测（幂等）。返回 false 仅当 DLL 缺失（兜底生效）。
    public static bool initialize()
    {
        ret Cpu_x64.libInit()
    }

    # 当前生效 ISA（ISA_* 常量；DLL 缺失时 -1）。
    public static Int32 isaId()
    {
        ret Cpu_x64.libIsaId()
    }

    # 当前生效 ISA 名（"SSE2" / "AVX2" / "AVX512" / "NEON"；DLL
    # 缺失时空串）。
    public static string isaName()
    {
        ret Cpu_x64.libIsaName()
    }

    # 强制切换生效 ISA（ISA_* 常量；isa < 0 恢复硬件检测档）。
    # 测试专用（见 libForceIsa 注释）。DLL 缺失时恒返回 -1。
    public static Int32 forceIsa( Int32 isa )
    {
        ret Cpu_x64.libForceIsa( isa )
    }

    public static bool hasFma()
    {
        ret Cpu_x64.libHasFma()
    }

    # 库版本：(major << 16) | minor。
    public static Int32 version()
    {
        ret Cpu_x64.libVersion()
    }

    public static Int32 lastError()
    {
        ret Cpu_x64.libLastError()
    }

    # 错误码转文本；err == 0 时取粘性 last_error。
    public static string errorString()
    {
        ret Cpu_x64.libErrorString( Cpu_x64.libLastError() )
    }

    # ── 门面：Tier-1 kernel（整数参数组 cfg 块，用后即释） ──
    # 全部返回 bool：true = 成功；false 时查 errorString()。
    # 数据块布局正确性由调用方（Tensora BackendRegistry）保证。

    # a[m,k] * b[k,n] -> o[m,n]（行主序 f32）。
    public static bool matmul( Int64 aBlk, Int64 bBlk, Int64 oBlk,
                               Int32 m, Int32 n, Int32 k )
    {
        Int64 cfgBlk = Memory.allocArray( 3, "i32" )
        Memory.writeI32( cfgBlk, 0, m )
        Memory.writeI32( cfgBlk, 4, n )
        Memory.writeI32( cfgBlk, 8, k )
        bool ok = Cpu_x64.libMatmul( aBlk, bBlk, oBlk, cfgBlk )
        Memory.free( cfgBlk )
        ret ok
    }

    # out[0] = sum(x[0..n))。
    public static bool sum( Int64 xBlk, Int64 oBlk, Int32 n )
    {
        Int64 cfgBlk = Memory.allocArray( 1, "i32" )
        Memory.writeI32( cfgBlk, 0, n )
        bool ok = Cpu_x64.libSum( xBlk, oBlk, cfgBlk )
        Memory.free( cfgBlk )
        ret ok
    }

    # x[rows,cols] -> o[rows,cols]（逐行，最后一维）。
    public static bool softmax( Int64 xBlk, Int64 oBlk,
                                Int32 rows, Int32 cols )
    {
        Int64 cfgBlk = Memory.allocArray( 2, "i32" )
        Memory.writeI32( cfgBlk, 0, rows )
        Memory.writeI32( cfgBlk, 4, cols )
        bool ok = Cpu_x64.libSoftmax( xBlk, oBlk, cfgBlk )
        Memory.free( cfgBlk )
        ret ok
    }

    # in[C,H,W] * wt[C,k,k] -> o[1,outH,outW]（outH/outW 由调用方
    # 按 L0 Ops.conv2d 同公式预算）。
    public static bool conv2d( Int64 inBlk, Int64 wtBlk, Int64 oBlk,
                               Int32 c, Int32 h, Int32 w,
                               Int32 k, Int32 stride, Int32 padding,
                               Int32 outH, Int32 outW )
    {
        Int64 cfgBlk = Memory.allocArray( 8, "i32" )
        Memory.writeI32( cfgBlk, 0, c )
        Memory.writeI32( cfgBlk, 4, h )
        Memory.writeI32( cfgBlk, 8, w )
        Memory.writeI32( cfgBlk, 12, k )
        Memory.writeI32( cfgBlk, 16, stride )
        Memory.writeI32( cfgBlk, 20, padding )
        Memory.writeI32( cfgBlk, 24, outH )
        Memory.writeI32( cfgBlk, 28, outW )
        bool ok = Cpu_x64.libConv2D( inBlk, wtBlk, oBlk, cfgBlk )
        Memory.free( cfgBlk )
        ret ok
    }

    # ── staging 辅助：SL Array<Float32> ↔ Memory 原生块 ────
    # Tensora 侧的 P1 上载 / P4 下载（§5.2 staging 协议 CPU 同构版）。

    # 组 f32 原生块并逐元素写入（P1 旧路径，对照保留）。返回块地址
    #（0 = 失败；用毕 freeBlock 显式释放）。
    public static Int64 uploadF32( Array<Float32> values )
    {
        Int64 addr = Memory.allocArray( values.length, "f32" )
        Int32 i = 0
        while i < values.length
        {
            Memory.writeF32( addr, i * 4, values[i] )
            i += 1
        }
        ret addr
    }

    # OQ-1（§5.7 立项落地）：数组裸数据指针（VMArray.data，偏移 48；
    # VMObject 32B 头 + length@32 + unit_length@36 + elem_rt@40 + data@48，
    # csimple_lang vm_array.h）。kernel 直接消费 SL 数组紧凑元素缓冲，
    # P1/P4 逐元素循环全消。布局防漂移：CudaBackendTest 固化断言此偏移。
    # 生命周期：指针随数组（勿 free，勿在数组回收后使用）；v1 全同步
    # 语义下无并发 GC 竞争，v2 异步前须扩展真 pin。
    public static Int64 pinF32( Array<Float32> values )
    {
        if values == null
        {
            ret 0
        }
        ret SystemPtrReadInt64( SystemPtrFromObject( values ), 48 )
    }

    # 从 f32 原生块逐元素取回（P4 旧路径，对照保留）。count 与上载元素数一致。
    public static Array<Float32> downloadF32( Int64 addr, Int32 count )
    {
        Array<Float32> values = Array<Float32>( count )
        Int32 i = 0
        while i < count
        {
            values[i] = Memory.readFloat32( addr, i * 4 )
            i += 1
        }
        ret values
    }

    # 释放原生块（显式释放协议：SL 无析构钩子，调用方负责）。
    # 仅用于 uploadF32 / Memory.allocArray 的独立块——pinF32 指针勿调。
    public static void freeBlock( Int64 addr )
    {
        Memory.free( addr )
    }
}
