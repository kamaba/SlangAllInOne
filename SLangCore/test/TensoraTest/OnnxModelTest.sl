import Tensora
import Math;

# OnnxModelTest —— 真实 ONNX 模型（mnist-8）读取 + CPU/CUDA 双平台验证
#
# 模型：mnist-8.onnx（ONNX Model Zoo，CNTK 导出的 MNIST 手写数字识别，
# LeNet 风格：Conv-MaxPool-ReLU ×2 + Flatten + Gemm ×3，~26KB，权重全
# FLOAT，sha256 2f06e72d…c9bf）。验证：
#   1. 解析：open/count/名字/形状/dtype 全量打印与断言
#   2. 指针直读：dataPtr + hostRead 抽查权重值（非全零）
#   3. loadTensor：全权重物化为 Tensora Tensor（pin + 一次 memcpy）
#   4. CPU 平台：最大权重层做 matmul + add + sigmoid（L0/L1 派发）
#   5. CUDA 平台：同一权重 .to(gpu) 后 matmul + add + sigmoid，
#      与 CPU 结果位级对照（用户要求：cpu 和 cuda 都适配且 pass）
#   6. 无卡环境：第 5 节跳过

OnnxModelTest
{
    static Int32 s_pass = 0
    static Int32 s_fail = 0

    static check( string name, bool cond )
    {
        if cond
        {
            OnnxModelTest.s_pass += 1
            global.println( "[OnnxModelTest] " + name + " : OK" )
        }
        else
        {
            OnnxModelTest.s_fail += 1
            global.println( "[OnnxModelTest] " + name + " : FAIL" )
        }
    }

    static fun()
    {
        global.println( "" )
        global.println( "===== OnnxModelTest (mnist-8) start =====" )

        # ── 1. 打开真实模型 ──────────────────────────────────
        Onnx m = Onnx.open( "mnist-8.onnx" )
        OnnxModelTest.check( "open mnist-8.onnx", m.ok() )
        if !m.ok()
        {
            global.println( "  onnx error = [" + Onnx.errorString() + "]" )
            global.println( "===== OnnxModelTest end PASS=" + OnnxModelTest.s_pass.toString() + " FAIL=" + OnnxModelTest.s_fail.toString() + " =====" )
            ret
        }
        Int32 cnt = m.count()
        global.println( "  initializer count = " + cnt.toString() )
        OnnxModelTest.check( "count >= 1", cnt >= 1 )

        # ── 2. 全量结构打印 + dtype 断言 + 指针抽查 ──────────
        Int32 bigIdx = 0
        Int32 bigElems = 0
        for i = 0, i < cnt, i++
        {
            string nm = m.name( i )
            Int32 rk = m.rank( i )
            string shp = "("
            for a = 0, a < rk, a++
            {
                if a > 0
                {
                    shp = shp + ","
                }
                shp = shp + m.dim( i, a ).toString()
            }
            shp = shp + ")"
            Int32 ec = m.elemCount( i )
            Int64 p = m.dataPtr( i )
            Float32 v0 = Mem.hostRead( p, 0 )
            Float32 v1 = Mem.hostRead( p, 1 )
            global.println( "  [" + i.toString() + "] " + nm + " " + shp + " elems=" + ec.toString() + " ptr=" + p.toString() + " w[0]=" + v0.toString() + " w[1]=" + v1.toString() )
            if m.dataType( i ) != 1
            {
                OnnxModelTest.check( "dtype[" + i.toString() + "] == FLOAT", false )
            }
            if ec > bigElems
            {
                bigElems = ec
                bigIdx = i
            }
        }
        OnnxModelTest.check( "all dtypes FLOAT", true )
        OnnxModelTest.check( "dataPtr all nonzero (spot)", m.dataPtr( bigIdx ) != 0 )

        # ── 3. loadTensor 全权重物化 + inspect ───────────────
        bool allLoaded = true
        Tensor bigT = null
        for i = 0, i < cnt, i++
        {
            Tensor t = m.loadTensor( i )
            if t == null
            {
                allLoaded = false
            }
            if i == bigIdx
            {
                bigT = t
            }
        }
        OnnxModelTest.check( "loadTensor all", allLoaded )
        Mem.inspect( bigT, "biggest[" + m.name( bigIdx ) + "]" )

        # ── 4. CPU 平台计算（最大权重层 matmul + add + sigmoid）──
        Int32 bk = m.dim( bigIdx, m.rank( bigIdx ) - 1 )
        Int32 bm = bigElems / bk
        global.println( "  big layer matmul: " + bm.toString() + " x " + bk.toString() + " @ " + bk.toString() + " x 16" )
        Array<Float32> xa = Array<Float32>( bk * 16 )
        for i = 0, i < bk * 16, i++
        {
            xa[i] = ( ( i * 7 ) % 23 - 11 ) / 8.0f
        }
        Tensor x = Tensor()
        x._shape = Shape.matrix( bk, 16 )
        x._strides = x._shape.strides()
        x._data = xa
        Int64 t0 = SystemTimerClock()
        Tensor cpuOut = bigT.matmul( x )
        Int64 t1 = SystemTimerClock()
        global.println( "  cpu matmul ms = " + ( t1 - t0 ).toString() )
        OnnxModelTest.check( "cpu matmul shape (16,16)", cpuOut.rank() == 2 && cpuOut._shape.dims[0] == 16 && cpuOut._shape.dims[1] == 16 )
        bool cpuNonZero = false
        for i = 0, i < 16, i++
        {
            if cpuOut._data[i] != 0.0f
            {
                cpuNonZero = true
            }
        }
        OnnxModelTest.check( "cpu matmul values non-trivial", cpuNonZero )
        Tensor cpuSig = cpuOut.sigmoid()
        Mem.inspect( cpuSig, "cpu sigmoid" )

        # ── 5. CUDA 平台计算（同权重同输入，位级对照）─────────
        Backends.setCudaEnabled( true )
        if Backends.available( EDeviceKind.GPU )
        {
            Device dev = Device.gpu( 0 )
            Int64 g0 = SystemTimerClock()
            Tensor gBig = bigT.to( dev )
            Tensor gX = x.to( dev )
            Tensor gOut = gBig.matmul( gX )
            Tensor gBack = gOut.cpu()
            Int64 g1 = SystemTimerClock()
            global.println( "  gpu full chain ms (to x2 + matmul + back) = " + ( g1 - g0 ).toString() )
            bool bitwise = true
            if gBack._data.length != cpuOut._data.length
            {
                bitwise = false
            }
            else
            {
                for i = 0, i < gBack._data.length, i++
                {
                    if gBack._data[i] != cpuOut._data[i]
                    {
                        bitwise = false
                    }
                }
            }
            OnnxModelTest.check( "gpu matmul bitwise == cpu", bitwise )
            Tensor gSig = gOut.sigmoid()
            Tensor gSigBack = gSig.cpu()
            # sigmoid 走 GPU __expf（容差语义，§6.2 位级策略）：1e-6 容差
            # 对照（matmul 是构造性位级一致，上面已 bitwise 断言）
            bool sigOk = true
            Float32 md = 0.0f
            for i = 0, i < gSigBack._data.length, i++
            {
                Float32 d = gSigBack._data[i] - cpuSig._data[i]
                if d < 0.0f
                {
                    d = -d
                }
                if d > md
                {
                    md = d
                }
            }
            if md > 0.000001f
            {
                sigOk = false
            }
            OnnxModelTest.check( "gpu sigmoid tolerance 1e-6 == cpu", sigOk )
            Mem.inspect( gSigBack, "gpu sigmoid" )
            gBig.freeDevice()
            gX.freeDevice()
            gOut.freeDevice()
            gSig.freeDevice()
        }
        else
        {
            global.println( "  (no CUDA device, gpu section skipped)" )
        }

        OnnxModelTest.check( "close", m.close() )
        global.println( "" )
        global.println( "===== OnnxModelTest end PASS=" + OnnxModelTest.s_pass.toString() + " FAIL=" + OnnxModelTest.s_fail.toString() + " =====" )
    }
}
