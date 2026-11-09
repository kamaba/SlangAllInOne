import Std;
import SLangCuda;

# =========================================================================
# CudaTest —— SLangCuda 端到端测试（本机 NVIDIA GPU，驱动 API 直连）
#
# 覆盖：
#   1) 原生层可用性（driverVersion —— 非 fallback 说明 sl_cuda_lib.dll
#      已静态预载，@DllStaticImport 直调生效，且 nvcuda.dll 解析成功）
#   2) 设备枚举与属性（deviceCount / device(0) / cc / SM 数 / warp）
#   3) 设备内存（alloc / memset8 / upload / download / free / 余量）
#   4) 流与事件（stream create/sync/destroy、事件计时 elapsedMs）
#   5) PTX 内核（fromPtx JIT 加载 + launch1D 启动 vec_add / vec_scale，
#      含 i32 参数与 f32 参数两条路径）
#   6) 错误路径（坏 PTX 返回 null + errorString 非空）
#
# SLangCuda 的类都在 namespace SLang 下，故统一用 SLang.xxx 全名访问。
# 语义对照 Python：Cuda.initialize() ~= cuda.cudart.cudaInit；
# CudaBuffer.alloc/upload/download ~ cudaMalloc/cudaMemcpy(H2D/D2H)。
# =========================================================================
class CudaTest
{
    static int s_pass = 0
    static int s_fail = 0

    static void check( string name, bool ok )
    {
        if ok
        {
            s_pass++
            Console.println( "  [PASS] " + name )
        }
        else
        {
            s_fail++
            Console.println( "  [FAIL] " + name )
        }
    }

    # vec_add PTX（.target sm_75 覆盖 Turing 及以上，驱动向下 JIT 兼容）
    static string vecAddPtx()
    {
        string ptx = ""
        ptx = ptx + ".version 8.0\n"
        ptx = ptx + ".target sm_75\n"
        ptx = ptx + ".address_size 64\n"
        ptx = ptx + "\n"
        ptx = ptx + ".visible .entry vec_add(\n"
        ptx = ptx + "    .param .u64 a_ptr,\n"
        ptx = ptx + "    .param .u64 b_ptr,\n"
        ptx = ptx + "    .param .u64 out_ptr,\n"
        ptx = ptx + "    .param .u32 count\n"
        ptx = ptx + ")\n"
        ptx = ptx + "{\n"
        ptx = ptx + "    .reg .b32 %r<5>;\n"
        ptx = ptx + "    .reg .b64 %rd<7>;\n"
        ptx = ptx + "    .reg .f32 %f<4>;\n"
        ptx = ptx + "    .reg .pred %p;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    ld.param.u64 %rd1, [a_ptr];\n"
        ptx = ptx + "    ld.param.u64 %rd2, [b_ptr];\n"
        ptx = ptx + "    ld.param.u64 %rd3, [out_ptr];\n"
        ptx = ptx + "    ld.param.u32 %r1, [count];\n"
        ptx = ptx + "\n"
        # 全局线程号：gid = blockIdx * blockDim + tid（多 block 必需）
        ptx = ptx + "    mov.u32 %r0, %tid.x;\n"
        ptx = ptx + "    mov.u32 %r2, %ctaid.x;\n"
        ptx = ptx + "    mov.u32 %r3, %ntid.x;\n"
        ptx = ptx + "    mad.lo.u32 %r4, %r2, %r3, %r0;\n"
        ptx = ptx + "    setp.ge.u32 %p, %r4, %r1;\n"
        ptx = ptx + "    @%p bra EXIT;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    mad.wide.u32 %rd4, %r4, 4, %rd1;\n"
        ptx = ptx + "    mad.wide.u32 %rd5, %r4, 4, %rd2;\n"
        ptx = ptx + "    mad.wide.u32 %rd6, %r4, 4, %rd3;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    ld.global.f32 %f1, [%rd4];\n"
        ptx = ptx + "    ld.global.f32 %f2, [%rd5];\n"
        ptx = ptx + "    add.f32 %f3, %f1, %f2;\n"
        ptx = ptx + "    st.global.f32 [%rd6], %f3;\n"
        ptx = ptx + "\n"
        ptx = ptx + "EXIT:\n"
        ptx = ptx + "    ret;\n"
        ptx = ptx + "}\n"
        ret ptx
    }

    # vec_scale PTX（out[i] = in[i] * scale）：验证 f32 标量参数路径
    static string vecScalePtx()
    {
        string ptx = ""
        ptx = ptx + ".version 8.0\n"
        ptx = ptx + ".target sm_75\n"
        ptx = ptx + ".address_size 64\n"
        ptx = ptx + "\n"
        ptx = ptx + ".visible .entry vec_scale(\n"
        ptx = ptx + "    .param .u64 in_ptr,\n"
        ptx = ptx + "    .param .u64 out_ptr,\n"
        ptx = ptx + "    .param .u32 count,\n"
        ptx = ptx + "    .param .f32 scale\n"
        ptx = ptx + ")\n"
        ptx = ptx + "{\n"
        ptx = ptx + "    .reg .b32 %r<5>;\n"
        ptx = ptx + "    .reg .b64 %rd<5>;\n"
        ptx = ptx + "    .reg .f32 %f<4>;\n"
        ptx = ptx + "    .reg .pred %p;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    ld.param.u64 %rd1, [in_ptr];\n"
        ptx = ptx + "    ld.param.u64 %rd2, [out_ptr];\n"
        ptx = ptx + "    ld.param.u32 %r1, [count];\n"
        ptx = ptx + "    ld.param.f32 %f1, [scale];\n"
        ptx = ptx + "\n"
        # 全局线程号：gid = blockIdx * blockDim + tid（多 block 必需）
        ptx = ptx + "    mov.u32 %r0, %tid.x;\n"
        ptx = ptx + "    mov.u32 %r2, %ctaid.x;\n"
        ptx = ptx + "    mov.u32 %r3, %ntid.x;\n"
        ptx = ptx + "    mad.lo.u32 %r4, %r2, %r3, %r0;\n"
        ptx = ptx + "    setp.ge.u32 %p, %r4, %r1;\n"
        ptx = ptx + "    @%p bra EXIT;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    mad.wide.u32 %rd3, %r4, 4, %rd1;\n"
        ptx = ptx + "    mad.wide.u32 %rd4, %r4, 4, %rd2;\n"
        ptx = ptx + "\n"
        ptx = ptx + "    ld.global.f32 %f2, [%rd3];\n"
        ptx = ptx + "    mul.f32 %f3, %f2, %f1;\n"
        ptx = ptx + "    st.global.f32 [%rd4], %f3;\n"
        ptx = ptx + "\n"
        ptx = ptx + "EXIT:\n"
        ptx = ptx + "    ret;\n"
        ptx = ptx + "}\n"
        ret ptx
    }

    static fun()
    {
        Console.println( "" )
        Console.println( "===== CudaTest start =====" )

        # ── 1. 原生层可用性 ──────────────────────────────────────
        check( "T01 initialize() ok", SLang.Cuda.initialize() )
        Int32 ver = SLang.Cuda.driverVersion()
        Console.println( "driverVersion = " + ver.toString() + " (" + SLang.Cuda.driverVersionText() + ")" )
        check( "T02 driverVersion > 0 (DLL loaded, nvcuda resolved, not SL fallback)", ver > 0 )
        check( "T03 driverVersionText not unknown", SLang.Cuda.driverVersionText() != "unknown" )

        # ── 2. 设备枚举与属性 ────────────────────────────────────
        Int32 ndev = SLang.Cuda.deviceCount()
        Console.println( "deviceCount = " + ndev.toString() )
        check( "T04 deviceCount >= 1", ndev >= 1 )
        if ndev < 1
        {
            Console.println( "no CUDA device, skip rest of CudaTest" )
            Console.println( "===== CudaTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
            ret
        }

        SLang.CudaDevice dev = SLang.Cuda.device( 0 )
        check( "T05 device(0) not null", dev != null )
        Console.println( "device[0] = " + dev.toString() )
        check( "T06 device name not empty", dev.name != "" )
        check( "T07 compute capability major > 0", dev.ccMajor > 0 )
        check( "T08 smCount > 0", dev.smCount > 0 )
        check( "T09 warpSize == 32", dev.warpSize == 32 )
        check( "T10 maxThreadsPerBlock >= 1024", dev.maxThreadsPerBlock >= 1024 )
        check( "T11 totalMemory > 1GB", dev.totalMemory > 1073741824 )

        check( "T12 makeCurrent ok", dev.makeCurrent() )
        check( "T13 currentDevice == 0", SLang.Cuda.currentDevice() == 0 )

        Int64 memTotal = SLang.Cuda.memTotalBytes()
        Int64 memFree = SLang.Cuda.memFreeBytes()
        Console.println( "memTotal = " + memTotal.toString() + " memFree = " + memFree.toString() )
        check( "T14 memTotalBytes > 0", memTotal > 0 )
        check( "T15 memFreeBytes > 0", memFree > 0 )
        check( "T16 memFree <= memTotal", memFree <= memTotal )

        # ── 3. 设备内存：alloc / upload / download ───────────────
        int n = 4096
        SLang.CudaBuffer buf = SLang.CudaBuffer.alloc( n * 4 )
        check( "T17 buffer alloc ok", buf != null )
        check( "T18 buffer sizeBytes == n*4", buf.sizeBytes == n * 4 )

        Int64 host = Memory.allocArray( n, "f32" )
        for i = 0, i < n, i++
        {
            Memory.writeF32( host, i * 4, SystemConvertFloat32( i ) )
        }
        check( "T19 upload ok", buf.upload( host ) )

        Int64 back = Memory.allocArray( n, "f32" )
        check( "T20 download ok", buf.download( back ) )
        Float32 v0 = Memory.readFloat32( back, 0 )
        Float32 v1 = Memory.readFloat32( back, 4 )
        Float32 vlast = Memory.readFloat32( back, ( n - 1 ) * 4 )
        check( "T21 roundtrip f32 [0] == 0", v0 == 0.0f )
        check( "T22 roundtrip f32 [1] == 1", v1 == 1.0f )
        check( "T23 roundtrip f32 [n-1] == n-1", vlast == SystemConvertFloat32( n - 1 ) )

        # memset8：整块填 0x05 -> i32 读回应为 0x05050505
        check( "T24 memset8 ok", buf.memset8( 0x05 ) )
        buf.download( back )
        Int32 filled = Memory.readInt32( back, 0 )
        check( "T25 memset8 pattern 0x05050505", filled == 0x05050505 )

        # ── 4. 流与事件 ──────────────────────────────────────────
        SLang.CudaStream stream = SLang.CudaStream.create()
        check( "T26 stream create ok", stream != null )
        check( "T27 stream uploadAsync ok", buf.uploadAsync( host, n * 4, stream ) )
        check( "T28 stream downloadAsync ok", buf.downloadAsync( back, n * 4, stream ) )
        check( "T29 stream sync ok", stream.synchronize() )
        Float32 av0 = Memory.readFloat32( back, 0 )
        check( "T30 async roundtrip [0] == 0", av0 == 0.0f )

        SLang.CudaEvent evStart = SLang.CudaEvent.createTiming()
        SLang.CudaEvent evEnd = SLang.CudaEvent.createTiming()
        check( "T31 timing events created", evStart != null && evEnd != null )
        check( "T32 event record ok", evStart.record( stream ) )
        buf.uploadAsync( host, n * 4, stream )
        check( "T33 event record end ok", evEnd.record( stream ) )
        check( "T34 event sync ok", evEnd.synchronize() )
        Float64 ms = SLang.CudaEvent.elapsedMs( evStart, evEnd )
        Console.println( "elapsedMs = " + SystemConvertString( ms ) )
        check( "T35 elapsedMs >= 0", ms >= 0.0 )

        # ── 5. PTX 内核：vec_add（u64 x3 + u32 参数）─────────────
        SLang.CudaKernel kAdd = SLang.CudaKernel.fromPtx( CudaTest.vecAddPtx(), "vec_add" )
        if kAdd == null
        {
            Console.println( "fromPtx(vec_add) failed: " + SLang.Cuda.errorString() )
        }
        check( "T36 fromPtx(vec_add) not null", kAdd != null )

        SLang.CudaBuffer a = SLang.CudaBuffer.alloc( n * 4 )
        SLang.CudaBuffer b = SLang.CudaBuffer.alloc( n * 4 )
        SLang.CudaBuffer outBuf = SLang.CudaBuffer.alloc( n * 4 )
        Int64 hb = Memory.allocArray( n, "f32" )
        for i = 0, i < n, i++
        {
            Memory.writeF32( host, i * 4, SystemConvertFloat32( i ) )
            Memory.writeF32( hb, i * 4, SystemConvertFloat32( i ) * 2.0f )
        }
        a.upload( host )
        b.upload( hb )

        SLang.CudaKernelArgs args = SLang.CudaKernelArgs( 4 )
        args.addPtr( a.devicePointer )
        args.addPtr( b.devicePointer )
        args.addPtr( outBuf.devicePointer )
        args.addI32( n )
        check( "T37 args count == 4", args.count == 4 )
        check( "T38 launch1D ok", kAdd.launch1D( n, 256, null, args ) )
        check( "T39 ctx synchronize ok", SLang.Cuda.synchronize() )
        outBuf.download( back )

        # 抽查 [0] [1] [123] [n-1]：out[i] == i + 2i == 3i
        bool addOk = true
        Float32 o0 = Memory.readFloat32( back, 0 )
        Float32 o1 = Memory.readFloat32( back, 4 )
        Float32 o123 = Memory.readFloat32( back, 123 * 4 )
        Float32 oLast = Memory.readFloat32( back, ( n - 1 ) * 4 )
        if o0 != 0.0f || o1 != 3.0f || o123 != 369.0f || oLast != SystemConvertFloat32( ( n - 1 ) * 3 )
        {
            addOk = false
        }
        Console.println( "vec_add out[0]=" + SystemConvertString( o0 ) + " out[1]=" + SystemConvertString( o1 ) + " out[123]=" + SystemConvertString( o123 ) + " out[4095]=" + SystemConvertString( oLast ) )
        check( "T40 vec_add results == 3*i", addOk )

        # ── 6. PTX 内核：vec_scale（u64 x2 + u32 + f32 参数）─────
        SLang.CudaKernel kScale = SLang.CudaKernel.fromPtx( CudaTest.vecScalePtx(), "vec_scale" )
        check( "T41 fromPtx(vec_scale) not null", kScale != null )

        SLang.CudaKernelArgs args2 = SLang.CudaKernelArgs( 4 )
        args2.addPtr( a.devicePointer )
        args2.addPtr( outBuf.devicePointer )
        args2.addI32( n )
        args2.addF32( 10.0f )
        check( "T42 vec_scale launch ok", kScale.launch1D( n, 256, stream, args2 ) )
        stream.synchronize()
        outBuf.download( back )
        Float32 s1 = Memory.readFloat32( back, 4 )
        Float32 s100 = Memory.readFloat32( back, 100 * 4 )
        Float32 sTail = Memory.readFloat32( back, ( n - 1 ) * 4 )
        check( "T43 vec_scale out[1] == 10", s1 == 10.0f )
        check( "T44 vec_scale out[100] == 1000 and tail == 40950", s100 == 1000.0f && sTail == 40950.0f )

        # ── 7. 错误路径：坏 PTX ──────────────────────────────────
        SLang.CudaKernel kBad = SLang.CudaKernel.fromPtx( ".version 8.0\n.this is not valid ptx\n", "nope" )
        check( "T45 bad ptx returns null", kBad == null )
        check( "T46 errorString not empty after failure", SLang.Cuda.errorString() != "" )
        Console.println( "bad ptx error = [" + SLang.Cuda.errorString() + "]" )

        # ── 8. 清理 ──────────────────────────────────────────────
        args.free()
        args2.free()
        kAdd.destroy()
        kScale.destroy()
        evStart.destroy()
        evEnd.destroy()
        stream.destroy()
        a.free()
        b.free()
        outBuf.free()
        buf.free()
        check( "T47 buffer isValid == false after free", buf.isValid == false )
        Memory.free( host )
        Memory.free( hb )
        Memory.free( back )

        Console.println( "" )
        Console.println( "===== CudaTest end PASS=" + s_pass.toString() + " FAIL=" + s_fail.toString() + " =====" )
    }
}
