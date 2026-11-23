# BenchmarkTest —— Tensora 算子计算基准（L0 标量 / CPU SIMD / AVX-512 / CUDA）

# 目标：对 Tier-1 算子做端到端计时统计（含 staging 上载/下载、读迫同步），
# 输出 [BENCH] 明细行 + 末尾汇总对比表（μs/ms + 相对 L0 加速比），[PROBE]
# 行供外部提取落盘 out\probe\。
#
# 四条路径：
#   cpu-l0    Backends.setSimdEnabled(false)  纯 SL 解释循环基准
#   cpu-hw    setSimdEnabled(true) + 真实硬件 ISA（i9-10850K 上为 AVX2）
#   cpu-avx512  仅在本机硬件真实支持（isaName()=="AVX512"）时启用，
#             此时与 hw 档同一 kernel 路径，列值相同
#   cuda      setCudaEnabled(true) + Device.gpu(0)，张量 .to(dev) 后算子走
#             GPU kernel（首跑含 JIT 编译，warmup 1 次后计时）
#
# 计时口径（μs，EngineClock.nowUs）：warmup 1 次（预热 + GPU JIT）后正式
# 3 轮取最小；每轮先自适应 reps（单次 < 3ms 时放大 reps 使轮内总量
# ≥ 3ms，上限 1024），单次均值 = 轮总耗时 / reps，精度可达 0.1μs 级。
# 每次执行含结果张量 at(0) 读迫同步（GPU 为 S2→S0 整块回传），端到端。
#
# 注意（实测教训）：
#   1. forceIsa(ISA_AVX512) 在不支持 AVX-512 的 CPU 上会被 DLL 直接接受
#      （返回 2 且 isaId=2），随后 SIMD kernel 执行 AVX-512 指令触发非法
#      指令崩溃（0xC000001D）——绝不能盲目强制，只认硬件检测档。
#   2. elementwise（add/mul/exp/sigmoid）CPU 侧与 SIMD 开关无关（SIMD
#      kernel 仅 matmul/sum/softmax/conv2d 四个），其 hw / avx512 列记 skip。
#   3. SystemTimerClock 毫秒粒度不足以测 GPU 小算子（<1ms 读 0），故用
#      SimGameEngine 的 EngineClock.nowUs 微秒时钟。
#
# 规模：matmul 256（四档全跑）/ 512（L0 太慢 skip）；elementwise 1M；
# sum 1M；softmax 1024x1024；conv2d in[3,64,64]xwt[3,3,3]。

import Tensora
import SimGameEngine
import Math;

BenchmarkTest
{
    static Int32 s_pass = 0
    static Int32 s_fail = 0

    static Array<string> s_names = null
    static Array<Int64> s_l0 = null
    static Array<Int64> s_hw = null
    static Array<Int64> s_avx = null
    static Array<Int64> s_gpu = null
    static Int32 s_cnt = 0

    static check( string nm, bool cond )
    {
        if cond
        {
            BenchmarkTest.s_pass += 1
            global.println( "[BenchmarkTest] " + nm + " : OK" )
        }
        else
        {
            BenchmarkTest.s_fail += 1
            global.println( "[BenchmarkTest] " + nm + " : FAIL" )
        }
    }

    # ── 确定性填充（同 CpuSimdTest/CudaBackendTest，值域 [-9/8, 9/8]）──
    static Float32 hashLin( Int32 idx )
    {
        Int32 v = ( idx * 7 + idx / 3 + idx % 11 ) % 19 - 9
        ret SystemConvertFloat32( v ) / 8.0f
    }

    static Tensor makeMatrix( Int32 rows, Int32 cols )
    {
        Array<Float32> arr = Array<Float32>( rows * cols )
        Int32 i = 0
        while i < rows * cols
        {
            arr[i] = BenchmarkTest.hashLin( i )
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
            arr[i] = BenchmarkTest.hashLin( i + 5 )
            i += 1
        }
        Tensor t = Tensor()
        t._shape = Shape( c, h, w )
        t._strides = t._shape.strides()
        t._data = arr
        ret t
    }

    # ── 计时核：单轮 reps 自适应 + iters 轮取最小（μs，端到端含读迫同步）──
    # warm：true 时先 warmup 1 次；iters=1（L0 大算子）时探测次即正式结果
    static Int64 timeLoop( Int32 kind, Tensor a, Tensor b, bool warm, Int32 iters )
    {
        if warm
        {
            BenchmarkTest.execOnce( kind, a, b )
        }
        # 探测单次耗时（μs），决定 reps 放大倍数
        Int64 t0 = EngineClock.nowUs()
        BenchmarkTest.execOnce( kind, a, b )
        Int64 d1 = EngineClock.nowUs() - t0
        if d1 < 1
        {
            d1 = 1
        }
        if iters <= 1 && d1 >= 3000
        {
            # 慢算子（L0 大矩阵）：探测次即正式结果，不再重复跑
            ret d1
        }
        Int64 reps = 1
        if d1 < 3000
        {
            reps = 3000000 / d1
            if reps < 8
            {
                reps = 8
            }
            if reps > 1024
            {
                reps = 1024
            }
        }
        Int64 best = 0
        Int32 i = 0
        while i < iters
        {
            Int64 t1 = EngineClock.nowUs()
            Int64 rep = 0
            while rep < reps
            {
                BenchmarkTest.execOnce( kind, a, b )
                rep += 1
            }
            Int64 total = EngineClock.nowUs() - t1
            Int64 avg = total / reps
            if best == 0 || avg < best
            {
                best = avg
            }
            i += 1
        }
        ret best
    }

    # 单次执行（含 at(0) 读迫同步）
    static void execOnce( Int32 kind, Tensor a, Tensor b )
    {
        if kind == 0
        {
            Tensor r = a.matmul( b )
            r.at( 0 )
            ret
        }
        if kind == 1
        {
            Tensor r = a.add( b )
            r.at( 0 )
            ret
        }
        if kind == 2
        {
            Tensor r = a.mul( b )
            r.at( 0 )
            ret
        }
        if kind == 3
        {
            Float32 v = a.sum()
            ret
        }
        if kind == 4
        {
            Tensor r = a.softmax()
            r.at( 0 )
            ret
        }
        if kind == 5
        {
            Tensor r = a.exp()
            r.at( 0 )
            ret
        }
        if kind == 6
        {
            Tensor r = a.sigmoid()
            r.at( 0 )
            ret
        }
        if kind == 7
        {
            Tensor r = Ops.conv2d( a, b, 1, 1 )
            r.at( 0 )
            ret
        }
    }

    # GPU 金丝雀：小张量（16x16）预热 1 次（含 JIT）+ 计时 3 次；
    # 3 次总量 >= 5ms 判定该算子在 GPU 上无 kernel 路径（逐元素回退每
    # 元素全同步往返，代价随元素数线性放大：256 元素 ~50ms → 1M 元素
    # 数百秒/次，实测拖死测试）——skip。真 GPU kernel（含同步回传）
    # 3 次 < 3ms，阈值 5ms 留余量。
    static bool gpuCanary( Int32 kind, Device dev )
    {
        Tensor c1 = BenchmarkTest.makeMatrix( 16, 16 )
        Tensor c2 = BenchmarkTest.makeMatrix( 16, 16 )
        Tensor g1 = c1.to( dev )
        Tensor g2 = c2.to( dev )
        BenchmarkTest.execOnce( kind, g1, g2 )
        Int64 t0 = EngineClock.nowUs()
        Int32 i = 0
        while i < 3
        {
            BenchmarkTest.execOnce( kind, g1, g2 )
            i += 1
        }
        Int64 d = EngineClock.nowUs() - t0
        g1.freeDevice()
        g2.freeDevice()
        if d >= 5000
        {
            global.println( "  [canary] kind=" + kind.toString() + " slow path " + d.toString() + "us (no gpu kernel), skip" )
        }
        ret d < 5000
    }

    # ── 明细记录 + [BENCH]/[PROBE] 行（μs；<=0 = skip/不可用）────────

    static void recordRow( string nm, Int64 l0Us, Int64 hwUs, Int64 avxUs, Int64 gpuUs )
    {
        BenchmarkTest.s_names[BenchmarkTest.s_cnt] = nm
        BenchmarkTest.s_l0[BenchmarkTest.s_cnt] = l0Us
        BenchmarkTest.s_hw[BenchmarkTest.s_cnt] = hwUs
        BenchmarkTest.s_avx[BenchmarkTest.s_cnt] = avxUs
        BenchmarkTest.s_gpu[BenchmarkTest.s_cnt] = gpuUs
        BenchmarkTest.s_cnt += 1

        global.println( "[BENCH] " + nm + " | l0=" + BenchmarkTest.fmtUs( l0Us ) + " | hw=" + BenchmarkTest.fmtUs( hwUs ) + " | avx512=" + BenchmarkTest.fmtUs( avxUs ) + " | cuda=" + BenchmarkTest.fmtUs( gpuUs ) )
        if l0Us > 0 && gpuUs > 0
        {
            Float32 spG = SystemConvertFloat32( SystemConvertInt32( l0Us ) ) / SystemConvertFloat32( SystemConvertInt32( gpuUs ) )
            global.println( "[PROBE] " + nm + ",l0_us=" + l0Us.toString() + ",cuda_us=" + gpuUs.toString() + ",speedup=" + SystemConvertString( spG ) )
        }
        if l0Us > 0 && hwUs > 0
        {
            Float32 spH = SystemConvertFloat32( SystemConvertInt32( l0Us ) ) / SystemConvertFloat32( SystemConvertInt32( hwUs ) )
            global.println( "[PROBE] " + nm + ",l0_us=" + l0Us.toString() + ",hw_us=" + hwUs.toString() + ",speedup=" + SystemConvertString( spH ) )
        }
    }

    # ── 主入口 ──────────────────────────────────────────────

    static fun()
    {
        global.println( "" )
        global.println( "===== BenchmarkTest start =====" )
        global.println( "  cpu isa = " + Cpu_x64.isaName() + " hasFma=" + Cpu_x64.hasFma().toString() )

        BenchmarkTest.s_names = Array<string>( 64 )
        BenchmarkTest.s_l0 = Array<Int64>( 64 )
        BenchmarkTest.s_hw = Array<Int64>( 64 )
        BenchmarkTest.s_avx = Array<Int64>( 64 )
        BenchmarkTest.s_gpu = Array<Int64>( 64 )
        BenchmarkTest.s_cnt = 0

        # dispatch 阈值全调 -1（小规模也强制走 SIMD kernel 路径），测完恢复
        Int64 oMM = Backends.T_MMUL
        Int64 oSUM = Backends.T_SUM
        Int64 oSMAX = Backends.T_SMAX
        Int64 oCONV = Backends.T_CONV
        Backends.T_MMUL = -1
        Backends.T_SUM = -1
        Backends.T_SMAX = -1
        Backends.T_CONV = -1

        # ── GPU 可用性 ──
        Backends.setCudaEnabled( true )
        bool hasGpu = Backends.available( EDeviceKind.GPU )
        Device dev = null
        if hasGpu
        {
            dev = Device.gpu( 0 )
            global.println( "  cuda device ready" )
        }
        else
        {
            global.println( "  (no CUDA device, cuda column = skip)" )
        }

        # ── AVX-512 档：仅本机硬件真实支持时启用（教训见文件头）──
        bool hasAvx512 = Cpu_x64.isaName() == "AVX512"
        if !hasAvx512
        {
            global.println( "  (AVX-512 not available on this cpu, avx512 column = skip)" )
        }

        # ════ 1. matmul 256x256（四档全跑）═══════════════════
        Tensor a256 = BenchmarkTest.makeMatrix( 256, 256 )
        Tensor b256 = BenchmarkTest.makeMatrix( 256, 256 )
        Backends.setSimdEnabled( false )
        Int64 m256l0 = BenchmarkTest.timeLoop( 0, a256, b256, false, 1 )
        Backends.setSimdEnabled( true )
        Int64 m256hw = BenchmarkTest.timeLoop( 0, a256, b256, true, 3 )
        # 硬件档即 AVX512 时 hw 列 == avx512 列（同一 kernel 路径）
        Int64 m256avx = 0
        if hasAvx512
        {
            m256avx = m256hw
        }
        Int64 m256gpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 0, dev )
        {
            Tensor ga = a256.to( dev )
            Tensor gb = b256.to( dev )
            m256gpu = BenchmarkTest.timeLoop( 0, ga, gb, true, 3 )
            # 位级对照（matmul 构造性位级一致契约）：GPU 结果 vs CPU 结果
            Tensor cpuRef = a256.matmul( b256 )
            Tensor gBack = ga.matmul( gb ).cpu()
            bool ok = true
            Int32 i = 0
            while i < gBack._data.length
            {
                if gBack._data[i] != cpuRef._data[i]
                {
                    ok = false
                }
                i += 1
            }
            BenchmarkTest.check( "cuda matmul256 bitwise", ok )
            ga.freeDevice()
            gb.freeDevice()
        }
        BenchmarkTest.recordRow( "matmul_n256", m256l0, m256hw, m256avx, m256gpu )

        # ════ 2. matmul 512x512（L0 太慢 skip）════════════════
        Tensor a512 = BenchmarkTest.makeMatrix( 512, 512 )
        Tensor b512 = BenchmarkTest.makeMatrix( 512, 512 )
        Backends.setSimdEnabled( true )
        Int64 m512hw = BenchmarkTest.timeLoop( 0, a512, b512, true, 3 )
        Int64 m512avx = 0
        if hasAvx512
        {
            m512avx = m512hw
        }
        Int64 m512gpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 0, dev )
        {
            Tensor ga = a512.to( dev )
            Tensor gb = b512.to( dev )
            m512gpu = BenchmarkTest.timeLoop( 0, ga, gb, true, 3 )
            ga.freeDevice()
            gb.freeDevice()
        }
        BenchmarkTest.recordRow( "matmul_n512", 0, m512hw, m512avx, m512gpu )

        # ════ 3. elementwise 256x256（L0 泛型广播路径极慢：1M 元素 >600s
        #        未完成，故用 64K 规模统计，结论按同数量级外推）═══
        Tensor e1 = BenchmarkTest.makeMatrix( 256, 256 )
        Tensor e2 = BenchmarkTest.makeMatrix( 256, 256 )
        Backends.setSimdEnabled( false )
        Int64 addL0 = BenchmarkTest.timeLoop( 1, e1, e2, false, 1 )
        Int64 addGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 1, dev )
        {
            Tensor g1 = e1.to( dev )
            Tensor g2 = e2.to( dev )
            addGpu = BenchmarkTest.timeLoop( 1, g1, g2, true, 3 )
            g1.freeDevice()
            g2.freeDevice()
        }
        BenchmarkTest.recordRow( "add_64K", addL0, 0, 0, addGpu )

        Int64 mulL0 = BenchmarkTest.timeLoop( 2, e1, e2, false, 1 )
        Int64 mulGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 2, dev )
        {
            Tensor g1 = e1.to( dev )
            Tensor g2 = e2.to( dev )
            mulGpu = BenchmarkTest.timeLoop( 2, g1, g2, true, 3 )
            g1.freeDevice()
            g2.freeDevice()
        }
        BenchmarkTest.recordRow( "mul_64K", mulL0, 0, 0, mulGpu )

        Int64 expL0 = BenchmarkTest.timeLoop( 5, e1, null, false, 1 )
        Int64 expGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 5, dev )
        {
            Tensor g1 = e1.to( dev )
            expGpu = BenchmarkTest.timeLoop( 5, g1, null, true, 3 )
            g1.freeDevice()
        }
        BenchmarkTest.recordRow( "exp_64K", expL0, 0, 0, expGpu )

        Int64 sigL0 = BenchmarkTest.timeLoop( 6, e1, null, false, 1 )
        Int64 sigGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 6, dev )
        {
            Tensor g1 = e1.to( dev )
            sigGpu = BenchmarkTest.timeLoop( 6, g1, null, true, 3 )
            g1.freeDevice()
        }
        BenchmarkTest.recordRow( "sigmoid_64K", sigL0, 0, 0, sigGpu )

        # ════ 4. sum 64K（四档）═════════════════════════════
        Int64 sumL0 = BenchmarkTest.timeLoop( 3, e1, null, false, 1 )
        Backends.setSimdEnabled( true )
        Int64 sumHw = BenchmarkTest.timeLoop( 3, e1, null, true, 3 )
        Int64 sumAvx = 0
        if hasAvx512
        {
            sumAvx = sumHw
        }
        Int64 sumGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 3, dev )
        {
            Tensor g1 = e1.to( dev )
            sumGpu = BenchmarkTest.timeLoop( 3, g1, null, true, 3 )
            g1.freeDevice()
        }
        BenchmarkTest.recordRow( "sum_64K", sumL0, sumHw, sumAvx, sumGpu )

        # ════ 5. softmax 256x256（四档）═════════════════════
        Backends.setSimdEnabled( false )
        Int64 smL0 = BenchmarkTest.timeLoop( 4, e1, null, false, 1 )
        Backends.setSimdEnabled( true )
        Int64 smHw = BenchmarkTest.timeLoop( 4, e1, null, true, 3 )
        Int64 smAvx = 0
        if hasAvx512
        {
            smAvx = smHw
        }
        Int64 smGpu = 0
        if hasGpu && BenchmarkTest.gpuCanary( 4, dev )
        {
            Tensor g1 = e1.to( dev )
            smGpu = BenchmarkTest.timeLoop( 4, g1, null, true, 3 )
            g1.freeDevice()
        }
        BenchmarkTest.recordRow( "softmax_256x256", smL0, smHw, smAvx, smGpu )

        # ════ 6. conv2d in[3,64,64] wt[3,3,3]（CPU 三档，cuda skip）═══
        Tensor ci = BenchmarkTest.makeCube( 3, 64, 64 )
        Tensor cw = BenchmarkTest.makeCube( 3, 3, 3 )
        Backends.setSimdEnabled( false )
        Int64 cvL0 = BenchmarkTest.timeLoop( 7, ci, cw, false, 1 )
        Backends.setSimdEnabled( true )
        Int64 cvHw = BenchmarkTest.timeLoop( 7, ci, cw, true, 3 )
        Int64 cvAvx = 0
        if hasAvx512
        {
            cvAvx = cvHw
        }
        BenchmarkTest.recordRow( "conv2d_3x64x64", cvL0, cvHw, cvAvx, 0 )

        # ── 恢复环境 ──
        Backends.T_MMUL = oMM
        Backends.T_SUM = oSUM
        Backends.T_SMAX = oSMAX
        Backends.T_CONV = oCONV
        Backends.setSimdEnabled( false )
        Backends.setCudaEnabled( false )

        # ── 汇总表 ──
        global.println( "" )
        global.println( "==== BenchmarkTest summary (us/ms 自适应, skip = 不可用/太慢) ====" )
        global.println( "  op                 |      l0 |      hw |  avx512 |    cuda" )
        global.println( "  -----------------------------------------------------------" )
        Int32 r = 0
        while r < BenchmarkTest.s_cnt
        {
            string l0s = BenchmarkTest.fmtCol( BenchmarkTest.s_l0[r] )
            string hws = BenchmarkTest.fmtCol( BenchmarkTest.s_hw[r] )
            string axs = BenchmarkTest.fmtCol( BenchmarkTest.s_avx[r] )
            string gps = BenchmarkTest.fmtCol( BenchmarkTest.s_gpu[r] )
            global.println( "  " + BenchmarkTest.pad( BenchmarkTest.s_names[r], 19 ) + "| " + l0s + " | " + hws + " | " + axs + " | " + gps )
            r += 1
        }
        global.println( "" )
        global.println( "===== BenchmarkTest end PASS=" + BenchmarkTest.s_pass.toString() + " FAIL=" + BenchmarkTest.s_fail.toString() + " =====" )
    }

    # [BENCH] 行内值：μs 或 ms 自适应
    static string fmtUs( Int64 us )
    {
        if us <= 0
        {
            ret "skip"
        }
        if us < 10000
        {
            ret us.toString() + "us"
        }
        Int32 ms = SystemConvertInt32( us / 1000 )
        ret ms.toString() + "ms"
    }

    # 汇总表列值：右对齐 7 字符
    static string fmtCol( Int64 us )
    {
        if us <= 0
        {
            ret "   skip"
        }
        string s = ""
        if us < 10000
        {
            s = us.toString() + "us"
        }
        else
        {
            s = ( SystemConvertInt32( us / 1000 ) ).toString() + "ms"
        }
        while s.length() < 7
        {
            s = " " + s
        }
        ret s
    }

    static string pad( string s, Int32 w )
    {
        while s.length() < w
        {
            s = s + " "
        }
        ret s
    }
}
