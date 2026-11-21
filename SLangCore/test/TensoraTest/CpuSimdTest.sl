import Tensora
import Math;

# CpuSimdTest —— P2B 验证：cvm CPU L1 SIMD 分派（TensoraBackend.md §6.1）
#
# 覆盖：
#   1. dllProbe       cvm DLL 绑定 / ISA 检测（本机硬件档）
#   2. consistencyRun 四 kernel（matmul/sum/softmax/conv2d）位级一致：
#                     L0 基准（SIMD 关）vs SIMD 端到端（Tensor.matmul 等
#                     dispatch 全链），阈值临时调 -1 保证小规模也分派，
#                     维度刻意取非向量宽倍数覆盖尾 lane
#   3. 两档断言       硬件档 + force SSE2 档各跑一遍（slcp_force_isa）
#   4. bench          matmul 512/1024 端到端（计入 staging 上载/下载
#                     成本）vs L0，[PROBE] 行供落盘 out\probe（§6.1.7）

CpuSimdTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            global.println( "[CpuSimdTest] " + name + " : OK" )
        }
        else
        {
            global.println( "[CpuSimdTest] " + name + " : FAIL" )
        }
    }

    # ── 确定性填充：整数值域 [-9,9] 的 hash / 8 ─────────────
    # 同一 _data 喂 L0 / SIMD 两条路径，生成方式不影响一致性比较
    static Float32 hashLin( Int32 idx )
    {
        Int32 v = ( idx * 7 + idx / 3 + idx % 11 ) % 19 - 9
        ret SystemConvertFloat32( v ) / 8.0f
    }

    # 直挂 _data 构造张量（绕开逐元素 setAt 开销；同 Ops dispatch 出口）
    static Tensor makeMatrix( Int32 rows, Int32 cols )
    {
        Array<Float32> arr = Array<Float32>( rows * cols )
        Int32 i = 0
        while i < rows * cols
        {
            arr[i] = CpuSimdTest.hashLin( i )
            i += 1
        }
        Tensor t = Tensor()
        t._shape = Shape.matrix( rows, cols )
        t._strides = t._shape.strides()
        t._data = arr
        ret t
    }

    static Tensor makeCube( Int32 c, Int32 h, Int32 w )
    {
        Array<Float32> arr = Array<Float32>( c * h * w )
        Int32 i = 0
        while i < c * h * w
        {
            arr[i] = CpuSimdTest.hashLin( i + 5 )
            i += 1
        }
        Tensor t = Tensor()
        t._shape = Shape( c, h, w )
        t._strides = t._shape.strides()
        t._data = arr
        ret t
    }

    # 全元素逐位断言（== 即位级一致；值域设计避开 ±0 / NaN 歧义）
    static bool sameAll( Tensor x, Tensor y )
    {
        if x._data.length != y._data.length
        {
            global.println( "  [mismatch] size " + x._data.length.toString() + " vs " + y._data.length.toString() )
            ret false
        }
        Int32 i = 0
        while i < x._data.length
        {
            if x._data[i] != y._data[i]
            {
                global.println( "  [mismatch] idx=" + i.toString() + " l0=" + SystemConvertString( x._data[i] ) + " simd=" + SystemConvertString( y._data[i] ) )
                ret false
            }
            i += 1
        }
        ret true
    }

    # ── 1. DLL 绑定 / ISA 检测 ──────────────────────────────
    static dllProbe()
    {
        global.println( "===== CpuSimdTest.dllProbe =====" )
        check( "cvm dll bound (isaId >= 0)", Cpu_x64.isaId() >= 0 )
        check( "isa name known", Cpu_x64.isaName() == "SSE2" || Cpu_x64.isaName() == "AVX2" || Cpu_x64.isaName() == "AVX512" )
        check( "version > 0", Cpu_x64.version() > 0 )
        global.println( "  isa=" + Cpu_x64.isaName() + " hasFma=" + Cpu_x64.hasFma().toString() )
    }

    # ── 2. 一致性：四 kernel 位级断言 ──────────────────────
    # 前置：阈值已被调用方调 -1（全部规模走 dispatch）
    static consistencyRun( string tag )
    {
        global.println( "===== CpuSimdTest.consistencyRun [" + tag + "] =====" )

        # matmul a[7,11]*b[11,5]：m/n/k 均非向量宽倍数（尾 lane）
        Tensor a = CpuSimdTest.makeMatrix( 7, 11 )
        Tensor b = CpuSimdTest.makeMatrix( 11, 5 )
        Backends.setSimdEnabled( false )
        Tensor rL0 = a.matmul( b )
        Backends.setSimdEnabled( true )
        check( tag + " matmul executor ok", Backends.simdMatmulArray( a._data, b._data, 7, 5, 11 ) != null )
        check( tag + " matmul bitwise", CpuSimdTest.sameAll( rL0, a.matmul( b ) ) )

        # matmul 整宽主流路径 64x64
        Tensor a2 = CpuSimdTest.makeMatrix( 64, 64 )
        Tensor b2 = CpuSimdTest.makeMatrix( 64, 64 )
        Backends.setSimdEnabled( false )
        Tensor r2L0 = a2.matmul( b2 )
        Backends.setSimdEnabled( true )
        check( tag + " matmul64 bitwise", CpuSimdTest.sameAll( r2L0, a2.matmul( b2 ) ) )

        # sum x[973]：973 % 8 = 5（尾 lane）；正负相消对累加序敏感
        Tensor x = CpuSimdTest.makeMatrix( 1, 973 )
        Backends.setSimdEnabled( false )
        Float32 sL0 = x.sum()
        Backends.setSimdEnabled( true )
        check( tag + " sum executor ok", Backends.simdSumArray( x._data ) != null )
        Float32 sS = x.sum()
        check( tag + " sum bitwise", sL0 == sS )
        if sL0 != sS
        {
            global.println( "  [mismatch] l0=" + SystemConvertString( sL0 ) + " simd=" + SystemConvertString( sS ) )
        }

        # softmax x[13,29]：行内 29 尾 lane，exp 走 CRT expf 同函数
        Tensor sm = CpuSimdTest.makeMatrix( 13, 29 )
        Backends.setSimdEnabled( false )
        Tensor smL0 = sm.softmax()
        Backends.setSimdEnabled( true )
        check( tag + " softmax executor ok", Backends.simdSoftmaxArray( sm._data, 13, 29 ) != null )
        check( tag + " softmax bitwise", CpuSimdTest.sameAll( smL0, sm.softmax() ) )

        # conv2d in[3,7,9]*wt[3,2,2] stride=1 pad=1 -> [1,8,10]
        Tensor ci = CpuSimdTest.makeCube( 3, 7, 9 )
        Tensor cw = CpuSimdTest.makeCube( 3, 2, 2 )
        Backends.setSimdEnabled( false )
        Tensor cL0 = Ops.conv2d( ci, cw, 1, 1 )
        Backends.setSimdEnabled( true )
        check( tag + " conv2d executor ok", Backends.simdConv2dArray( ci._data, cw._data, 3, 7, 9, 2, 1, 1, 8, 10 ) != null )
        check( tag + " conv2d bitwise", CpuSimdTest.sameAll( cL0, Ops.conv2d( ci, cw, 1, 1 ) ) )
    }

    # ── 4. 基准：matmul 端到端（含 staging）vs L0（§6.1.7）──
    static benchOnce( Int32 n )
    {
        global.println( "===== CpuSimdTest.benchOnce n=" + n.toString() + " =====" )
        Tensor a = CpuSimdTest.makeMatrix( n, n )
        Tensor b = CpuSimdTest.makeMatrix( n, n )

        # L0（SIMD 关）：1 次
        Backends.setSimdEnabled( false )
        Int64 t0 = SystemTimerClock()
        Tensor rL0 = a.matmul( b )
        Int64 l0Ms = SystemTimerClock() - t0

        # SIMD（硬件档，含 staging 上载/下载 + 结果张量构造）：3 次取最小
        Backends.setSimdEnabled( true )
        Tensor rS = null
        Int64 best = 0
        Int32 r = 0
        while r < 3
        {
            Int64 s0 = SystemTimerClock()
            rS = a.matmul( b )
            Int64 d = SystemTimerClock() - s0
            if best == 0 || d < best
            {
                best = d
            }
            r += 1
        }

        # 大矩阵位级一致顺带断言
        check( "bench n=" + n.toString() + " bitwise", CpuSimdTest.sameAll( rL0, rS ) )

        Int32 l0v = SystemConvertInt32( l0Ms )
        Int32 sv = SystemConvertInt32( best )
        Float32 sp = SystemConvertFloat32( l0v ) / SystemConvertFloat32( sv )
        global.println( "[PROBE] bench,matmul,n=" + n.toString() + ",isa=" + Cpu_x64.isaName() + ",l0_ms=" + l0v.toString() + ",simd_ms=" + sv.toString() + ",speedup=" + SystemConvertString( sp ) )
    }

    static fun()
    {
        CpuSimdTest.dllProbe()

        # 阈值全调 -1（一致性小规模也走 dispatch），测完恢复
        Int64 oMM = Backends.T_MMUL
        Int64 oSUM = Backends.T_SUM
        Int64 oSMAX = Backends.T_SMAX
        Int64 oCONV = Backends.T_CONV
        Backends.T_MMUL = -1
        Backends.T_SUM = -1
        Backends.T_SMAX = -1
        Backends.T_CONV = -1

        # 硬件档（本机检测，i9-10850K 上为 AVX2）
        CpuSimdTest.consistencyRun( "hw:" + Cpu_x64.isaName() )

        # force SSE2 档（x64 基线恒可用），跑完恢复硬件档
        Int32 hw = Cpu_x64.isaId()
        if hw != Cpu_x64.ISA_SSE2
        {
            check( "force SSE2 applied", Cpu_x64.forceIsa( Cpu_x64.ISA_SSE2 ) == Cpu_x64.ISA_SSE2 )
            CpuSimdTest.consistencyRun( "force:SSE2" )
            check( "force restore", Cpu_x64.forceIsa( -1 ) == hw )
        }

        # 恢复阈值与总开关（关——与全局默认一致）
        Backends.T_MMUL = oMM
        Backends.T_SUM = oSUM
        Backends.T_SMAX = oSMAX
        Backends.T_CONV = oCONV
        Backends.setSimdEnabled( false )
    }

    # 基准（§6.1.7，单跑入口；真实阈值表下 512/1024 天然超阈值，
    # [PROBE] 行由外部提取落盘 out\probe\；L0 1024 约 40+ 分钟）
    static bench()
    {
        CpuSimdTest.benchOnce( 512 )
        CpuSimdTest.benchOnce( 1024 )
        Backends.setSimdEnabled( false )
    }
}
