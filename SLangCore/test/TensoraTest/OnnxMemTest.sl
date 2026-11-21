import Tensora
import Math;

# OnnxMemTest —— ONNX 读取 + 跨平台内存管理验证（cvm，Onnx.sl / Mem.sl）
#
# 覆盖：
#   1. ONNX      生成测试模型（slo_make_test_model：w0[2,3] float_data
#                路径 + w1[5] raw_data 路径）→ open/count/name/rank/dim/
#                elemCount/dataType；**指针直读**（dataPtr + hostRead
#                逐元素，位级对照生成值）
#   2. loadTensor 快路径（pin + 一次 memcpy 物化 Tensor，位级对照；
#                .to(gpu) 上设备 + 读迫同步回读位级对照）
#   3. Mem       copyHost（数组↔数组批量拷）；copyToDevice/copyToHost
#                （A↔C DMA 往返位级对照 + 记账开合）；copyDevice（D2D）；
#                moveFromDevice（转移语义：源回 CPU 态、块句柄接管）；
#                free（删除 + 记账回收）；inspect（查看输出形态）
#   4. 无卡环境：第 3 节 GPU 部分跳过（仅 CPU 侧 copyHost 断言）

OnnxMemTest
{
    static Int32 s_pass = 0
    static Int32 s_fail = 0

    static check( string name, bool cond )
    {
        if cond
        {
            OnnxMemTest.s_pass += 1
            global.println( "[OnnxMemTest] " + name + " : OK" )
        }
        else
        {
            OnnxMemTest.s_fail += 1
            global.println( "[OnnxMemTest] " + name + " : FAIL" )
        }
    }

    static fun()
    {
        global.println( "" )
        global.println( "===== OnnxMemTest start =====" )

        # ── 1. 生成测试模型 + 打开解析 ──────────────────────
        string path = "onnx_mem_test.onnx"
        OnnxMemTest.check( "makeTestModel", Onnx.makeTestModel( path ) )
        Onnx m = Onnx.open( path )
        OnnxMemTest.check( "open ok", m.ok() )
        OnnxMemTest.check( "count == 2", m.count() == 2 )

        OnnxMemTest.check( "name[0] == w0", m.name( 0 ) == "w0" )
        OnnxMemTest.check( "rank[0] == 2", m.rank( 0 ) == 2 )
        OnnxMemTest.check( "dim[0] 2x3", m.dim( 0, 0 ) == 2 && m.dim( 0, 1 ) == 3 )
        OnnxMemTest.check( "elemCount[0] == 6", m.elemCount( 0 ) == 6 )
        OnnxMemTest.check( "dataType[0] == FLOAT(1)", m.dataType( 0 ) == 1 )
        OnnxMemTest.check( "name[1] == w1", m.name( 1 ) == "w1" )
        OnnxMemTest.check( "rank[1] == 1 / dim == 5", m.rank( 1 ) == 1 && m.dim( 1, 0 ) == 5 )

        # ── 2. 指针直读（"上层拿指针读数据"通路）─────────────
        Int64 p0 = m.dataPtr( 0 )
        OnnxMemTest.check( "dataPtr[0] != 0", p0 != 0 )
        OnnxMemTest.check( "ptr read w0[0] == 1.5", Mem.hostRead( p0, 0 ) == 1.5f )
        OnnxMemTest.check( "ptr read w0[1] == -2.25", Mem.hostRead( p0, 1 ) == -2.25f )
        OnnxMemTest.check( "ptr read w0[2] == 3", Mem.hostRead( p0, 2 ) == 3.0f )
        OnnxMemTest.check( "ptr read w0[3] == 0.5", Mem.hostRead( p0, 3 ) == 0.5f )
        OnnxMemTest.check( "ptr read w0[4] == 100", Mem.hostRead( p0, 4 ) == 100.0f )
        OnnxMemTest.check( "ptr read w0[5] == 2", Mem.hostRead( p0, 5 ) == 2.0f )
        Int64 p1 = m.dataPtr( 1 )
        OnnxMemTest.check( "ptr read w1[4] == 50", Mem.hostRead( p1, 4 ) == 50.0f )

        # ── 3. loadTensor 快路径（pin + memcpy 物化）────────
        Tensor t0 = m.loadTensor( 0 )
        OnnxMemTest.check( "loadTensor t0 not null", t0 != null )
        OnnxMemTest.check( "t0 shape (2,3)", t0.rank() == 2 && t0._shape.dims[0] == 2 && t0._shape.dims[1] == 3 )
        bool t0ok = t0.at( 0, 0 ) == 1.5f && t0.at( 0, 1 ) == -2.25f && t0.at( 0, 2 ) == 3.0f && t0.at( 1, 0 ) == 0.5f && t0.at( 1, 1 ) == 100.0f && t0.at( 1, 2 ) == 2.0f
        OnnxMemTest.check( "t0 values bitwise", t0ok )
        Mem.inspect( t0, "w0" )

        # ── 4. Mem：CPU 侧（copyHost / copyArray）───────────
        Array<Float32> a1 = Array<Float32>( 5 )
        Array<Float32> a2 = Array<Float32>( 5 )
        a1[0] = 1.25f
        a1[1] = 2.5f
        a1[2] = -3.75f
        a1[3] = 4.0f
        a1[4] = 100.5f
        OnnxMemTest.check( "copyArray", Mem.copyArray( a2, a1 ) )
        bool arrOk = a2[0] == 1.25f && a2[1] == 2.5f && a2[2] == -3.75f && a2[3] == 4.0f && a2[4] == 100.5f
        OnnxMemTest.check( "copyArray values", arrOk )
        OnnxMemTest.check( "copyHost bad args rejected", !Mem.copyHost( 0, 0, 16 ) )

        # ── 5. Mem：GPU 侧（A↔C / C→C / move / free）───────
        Backends.setCudaEnabled( true )
        if Backends.available( EDeviceKind.GPU )
        {
            Device dev = Device.gpu( 0 )
            Int64 baseUsed = dev.bytesUsed

            # A → C → A 往返位级对照
            Int64 dblk = Mem.copyToDevice( a1, dev )
            OnnxMemTest.check( "copyToDevice ok", dblk != 0 )
            OnnxMemTest.check( "accounting +20 bytes", dev.bytesUsed == baseUsed + 20 )
            Array<Float32> back = Array<Float32>( 5 )
            OnnxMemTest.check( "copyToHost ok", Mem.copyToHost( dblk, back, dev ) )
            bool rtOk = back[0] == 1.25f && back[1] == 2.5f && back[2] == -3.75f && back[3] == 4.0f && back[4] == 100.5f
            OnnxMemTest.check( "A<->C roundtrip bitwise", rtOk )
            Mem.inspectDevice( dblk, 5, dev, "dev block" )

            # C → C（D2D）
            Int64 dblk2 = Mem.copyToDevice( a2, dev )
            OnnxMemTest.check( "copyDevice (D2D)", Mem.copyDevice( dblk2, dblk, 20, dev ) )
            Array<Float32> back2 = Array<Float32>( 5 )
            Mem.copyToHost( dblk2, back2, dev )
            bool d2dOk = back2[0] == 1.25f && back2[2] == -3.75f && back2[4] == 100.5f
            OnnxMemTest.check( "D2D values", d2dOk )

            # move：张量设备块所有权转出
            Tensor tg = t0.to( dev )
            Int64 moved = Mem.moveFromDevice( tg )
            OnnxMemTest.check( "moveFromDevice nonzero", moved != 0 )
            OnnxMemTest.check( "source back to cpu state", !tg.hasDeviceBuffer && tg.isHostDirty && !tg.onGpu() )
            Mem.free( moved, 6 * 4, dev )
            Mem.free( dblk, 20, dev )
            Mem.free( dblk2, 20, dev )
            OnnxMemTest.check( "accounting closed", dev.bytesUsed == baseUsed )
        }
        else
        {
            global.println( "  (no CUDA device, GPU section skipped)" )
        }

        # ── 6. loadTensor → GPU 全链（OQ-1 直传）────────────
        if Backends.available( EDeviceKind.GPU )
        {
            Device dev = Device.gpu( 0 )
            Tensor tg = m.loadTensor( 1 ).to( dev )
            OnnxMemTest.check( "onnx->gpu ok", tg.onGpu() && tg.hasDeviceBuffer )
            Tensor tb = tg.cpu()
            bool gok = tb.at( 0 ) == 10.0f && tb.at( 2 ) == 30.0f && tb.at( 4 ) == 50.0f
            OnnxMemTest.check( "onnx->gpu->cpu bitwise", gok )
            tg.freeDevice()
        }

        # ── 7. 关闭（dataPtr 失效约定 + 错误路径）───────────
        OnnxMemTest.check( "close ok", m.close() )
        OnnxMemTest.check( "close idempotent", m.close() )
        Onnx bad = Onnx.open( "no_such_file.onnx" )
        OnnxMemTest.check( "bad open reports error", !bad.ok() )
        OnnxMemTest.check( "errorString non-empty", Onnx.errorString() != "" )
        global.println( "  onnx error = [" + Onnx.errorString() + "]" )

        global.println( "" )
        global.println( "===== OnnxMemTest end PASS=" + OnnxMemTest.s_pass.toString() + " FAIL=" + OnnxMemTest.s_fail.toString() + " =====" )
    }
}
