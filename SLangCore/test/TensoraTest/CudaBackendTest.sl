import Tensora

# CudaBackendTest —— P2A 验证：cvm GPU 算子执行层（TensoraBackend.md §6.2 / §5 / §8）
#
# 覆盖：
#   1. 门控          开关默认关 → setCudaEnabled 后 available(GPU)；无卡跳过
#   2. 状态机 I1-I4  to()→S0 / 算子出口 S2 / 读迫同步→S0 / CPU 写→S1
#                   →补传后值正确；Device.bytesUsed 记账开/合
#   3. 一致性        算术类（add/sub/mul/div/scale/relu/mmat/sum/原地/D2D）
#                   构造性逐位一致；超越类（exp/sigmoid/tanh/softmax）容差
#                   1e-6（GPU 无 CRT expf，§6.2 位级策略）；列向量广播走
#                   CPU 合并回落（值正确 + S1 挂设备）
#   4. bench         独立入口（不进 _main_）：matmul 1024² GPU 全链
#                   （staging+kernel+download）+ §5.7 分段基准
#                   （P1/P2/P4/memset），[PROBE] 行落盘 out\probe\h2d_bench.txt
#
# 本机环境：NVIDIA GeForce RTX 2080（sm_75）/ 驱动 13.3

CudaBackendTest
{
    static Int32 s_pass = 0
    static Int32 s_fail = 0

    static check( string name, bool cond )
    {
        if cond
        {
            CudaBackendTest.s_pass += 1
            global.println( "[CudaBackendTest] " + name + " : OK" )
        }
        else
        {
            CudaBackendTest.s_fail += 1
            global.println( "[CudaBackendTest] " + name + " : FAIL" )
        }
    }

    # ── 确定性填充（与 CpuSimdTest 同 hash，整数值域 [-9,9]/8）──
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
            arr[i] = CudaBackendTest.hashLin( i )
            i += 1
        }
        Tensor t = Tensor()
        t._shape = Shape.matrix( rows, cols )
        t._strides = t._shape.strides()
        t._data = arr
        ret t
    }

    # 全元素逐位断言
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
                global.println( "  [mismatch] idx " + i.toString() + " " + x._data[i].toString() + " vs " + y._data[i].toString() )
                ret false
            }
            i += 1
        }
        ret true
    }

    # 全元素最大绝对差（容差类用）
    static Float32 maxDiff( Tensor x, Tensor y )
    {
        Float32 md = 0.0f
        Int32 i = 0
        while i < x._data.length
        {
            Float32 d = x._data[i] - y._data[i]
            if d < 0.0f
            {
                d = -d
            }
            if d > md
            {
                md = d
            }
            i += 1
        }
        ret md
    }

    # 读一次触发读迫同步（S2→S0），此后 _data 可直接比
    static void syncRead( Tensor t )
    {
        t.at( 0 )
    }

    # ================================================================
    # 状态机段（§5.1 I1-I4 + §5.3 记账）
    # ================================================================

    static Device s_dev = null

    static void stateMachineRun()
    {
        Tensor src = CudaBackendTest.makeMatrix( 5, 7 )
        Tensor srcb = CudaBackendTest.makeMatrix( 5, 7 )
        Tensor ref = src.add( srcb )

        # ── to()：§5.3 立即分配 + OQ-1 零复制上传（源数组 data 直传）→
        #    出口 S2（dev 权威，_data 零填充占位）；源不动 ──
        Int64 baseUsed = CudaBackendTest.s_dev.bytesUsed
        Tensor ga = src.to( CudaBackendTest.s_dev )
        Tensor gb = srcb.to( CudaBackendTest.s_dev )
        CudaBackendTest.check( "I0 to() S2 (dev authoritative)", ga.isDevDirty && !ga.isHostDirty && ga.hasDeviceBuffer )
        CudaBackendTest.check( "I0 to() source untouched (cpu)", !src.onGpu() && src.isHostDirty )
        CudaBackendTest.check( "I0 to() device tag", ga.device.sameDevice( CudaBackendTest.s_dev ) )
        CudaBackendTest.check( "I0 accounting +2 blocks", CudaBackendTest.s_dev.bytesUsed == baseUsed + 280 )

        # ── I1/I2：设备算子出口 S2；读迫同步 → S0，值位级正确 ──
        Tensor c = ga.add( gb )
        CudaBackendTest.check( "I2 op exit S2 (dev authoritative)", c.isDevDirty && !c.isHostDirty && c.hasDeviceBuffer )
        CudaBackendTest.syncRead( c )
        CudaBackendTest.check( "I2 read-pull to S0", !c.isDevDirty && !c.isHostDirty )
        CudaBackendTest.check( "I2 add bitwise vs cpu ref", CudaBackendTest.sameAll( c, ref ) )

        # ── OQ-1 to() 零复制验证：S2 占位 _data 读迫同步后位级正确 ──
        Tensor gcheck = src.to( CudaBackendTest.s_dev )
        CudaBackendTest.syncRead( gcheck )
        CudaBackendTest.check( "OQ1 to() lazy fill bitwise", CudaBackendTest.sameAll( gcheck, src ) )
        gcheck.freeDevice()

        # ── I4：CPU 原地写 → S1；下个设备算子 stageOut 补传后值正确 ──
        ga.setAt( 0, 0, 1.5f )
        CudaBackendTest.check( "I4 host write -> S1", ga.isHostDirty && !ga.isDevDirty )
        Tensor ref2 = src.add( srcb )
        ref2.setAt( 0, 0, 1.5f + srcb.at( 0, 0 ) )
        Tensor c2 = ga.add( gb )
        CudaBackendTest.check( "I4 op after S1 staged (S2)", c2.isDevDirty && !c2.isHostDirty )
        CudaBackendTest.syncRead( c2 )
        CudaBackendTest.check( "I4 stageOut re-upload correct", CudaBackendTest.sameAll( c2, ref2 ) )

        # ── to(cpu)：新 CPU 张量，源影子不动 ──
        Tensor back = c.cpu()
        CudaBackendTest.check( "to(cpu) new tensor clean cpu", !back.hasDeviceBuffer && !back.isDevDirty && !back.onGpu() )
        CudaBackendTest.check( "to(cpu) values copied", CudaBackendTest.sameAll( back, ref ) )
        CudaBackendTest.check( "to(cpu) source stays on gpu", c.hasDeviceBuffer )

        # ── 释放协议：记账开/合（全部显式 freeDevice 后回基线）──
        ga.freeDevice()
        gb.freeDevice()
        c.freeDevice()
        c2.freeDevice()
        back.freeDevice()
        CudaBackendTest.check( "freeDevice accounting closed", CudaBackendTest.s_dev.bytesUsed == baseUsed )
    }

    # ================================================================
    # 一致性段（§6.2 首批 12 opId + 2 库级原语）
    # ================================================================

    static void consistencyRun()
    {
        Device dev = CudaBackendTest.s_dev

        # ── 逐元素二元：同形 add/sub/mul/div（构造性逐位）──
        Tensor ca = CudaBackendTest.makeMatrix( 7, 11 )
        Tensor cb = CudaBackendTest.makeMatrix( 11, 7 )
        cb = cb.transpose()
        Tensor ga = ca.to( dev )
        Tensor gb = cb.to( dev )
        Tensor rAdd = ga.add( gb )
        Tensor rSub = ga.sub( gb )
        Tensor rMul = ga.mul( gb )
        Tensor rDiv = ga.div( gb )
        CudaBackendTest.syncRead( rAdd )
        CudaBackendTest.syncRead( rSub )
        CudaBackendTest.syncRead( rMul )
        CudaBackendTest.syncRead( rDiv )
        CudaBackendTest.check( "EADD same-shape bitwise", CudaBackendTest.sameAll( rAdd, ca.add( cb ) ) )
        CudaBackendTest.check( "ESUB same-shape bitwise", CudaBackendTest.sameAll( rSub, ca.sub( cb ) ) )
        CudaBackendTest.check( "EMUL same-shape bitwise", CudaBackendTest.sameAll( rMul, ca.mul( cb ) ) )
        CudaBackendTest.check( "EDIV same-shape bitwise", CudaBackendTest.sameAll( rDiv, ca.div( cb ) ) )

        # ── 广播：行向量 / 标量（kernel gid%blen 映射）──
        Tensor cRow = CudaBackendTest.makeMatrix( 1, 11 )
        Tensor gRow = cRow.to( dev )
        Tensor rRow = ga.add( gRow )
        CudaBackendTest.syncRead( rRow )
        CudaBackendTest.check( "EADD row-vector broadcast bitwise", CudaBackendTest.sameAll( rRow, ca.add( cRow ) ) )

        Tensor cScalar = Tensor()
        cScalar.setAt( 0, 0.5f )
        Tensor gScalar = cScalar.to( dev )
        Tensor rScalar = ga.add( gScalar )
        CudaBackendTest.syncRead( rScalar )
        CudaBackendTest.check( "EADD scalar broadcast bitwise", CudaBackendTest.sameAll( rScalar, ca.add( cScalar ) ) )

        # ── 列向量广播：v1 不支持 → CPU 合并回落（值正确 + 挂设备 S1）──
        Tensor cCol = CudaBackendTest.makeMatrix( 7, 1 )
        Tensor gCol = cCol.to( dev )
        Tensor rCol = ga.add( gCol )
        CudaBackendTest.check( "column broadcast fallback to cpu path", CudaBackendTest.sameAll( rCol, ca.add( cCol ) ) )
        CudaBackendTest.check( "fallback tagged device S1 (lazy)", rCol.onGpu() && rCol.isHostDirty && !rCol.hasDeviceBuffer )

        # ── scale / relu（构造性逐位）──
        Tensor rScale = ga.scale( 0.375f )
        CudaBackendTest.syncRead( rScale )
        CudaBackendTest.check( "ESCALE bitwise", CudaBackendTest.sameAll( rScale, ca.scale( 0.375f ) ) )
        Tensor rRelu = ga.relu()
        CudaBackendTest.syncRead( rRelu )
        CudaBackendTest.check( "ERELU bitwise", CudaBackendTest.sameAll( rRelu, ca.relu() ) )

        # ── 超越类：exp/sigmoid/tanh（f64 变换 + ex2.approx，容差 1e-6）──
        Tensor rExp = ga.exp()
        Tensor rSig = ga.sigmoid()
        Tensor rTan = ga.tanh()
        CudaBackendTest.syncRead( rExp )
        CudaBackendTest.syncRead( rSig )
        CudaBackendTest.syncRead( rTan )
        CudaBackendTest.check( "EEXP tolerance 1e-6", CudaBackendTest.maxDiff( rExp, ca.exp() ) <= 0.000001f )
        CudaBackendTest.check( "ESIGMOID tolerance 1e-6", CudaBackendTest.maxDiff( rSig, ca.sigmoid() ) <= 0.000001f )
        CudaBackendTest.check( "ETANH tolerance 1e-6", CudaBackendTest.maxDiff( rTan, ca.tanh() ) <= 0.000001f )

        # ── matmul（p 序标量累加 → 逐位）+ sum（单线程标量序 → 逐位）──
        Tensor cm1 = CudaBackendTest.makeMatrix( 13, 17 )
        Tensor cm2 = CudaBackendTest.makeMatrix( 17, 9 )
        Tensor gm1 = cm1.to( dev )
        Tensor gm2 = cm2.to( dev )
        Tensor rMM = gm1.matmul( gm2 )
        CudaBackendTest.syncRead( rMM )
        CudaBackendTest.check( "MMUL 13x17x9 bitwise", CudaBackendTest.sameAll( rMM, cm1.matmul( cm2 ) ) )

        Tensor cm3 = CudaBackendTest.makeMatrix( 64, 64 )
        Tensor cm4 = CudaBackendTest.makeMatrix( 64, 64 )
        Tensor gm3 = cm3.to( dev )
        Tensor gm4 = cm4.to( dev )
        Tensor rMM64 = gm3.matmul( gm4 )
        CudaBackendTest.syncRead( rMM64 )
        CudaBackendTest.check( "MMUL 64x64x64 bitwise", CudaBackendTest.sameAll( rMM64, cm3.matmul( cm4 ) ) )

        Tensor cvec = CudaBackendTest.makeMatrix( 7, 139 )
        Tensor gvec = cvec.to( dev )
        CudaBackendTest.check( "RSUM bitwise", gvec.sum() == cvec.sum() )

        # ── softmax（exp 容差）──
        Tensor csm = CudaBackendTest.makeMatrix( 13, 29 )
        Tensor gsm = csm.to( dev )
        Tensor rSmx = gsm.softmax()
        CudaBackendTest.syncRead( rSmx )
        CudaBackendTest.check( "SMAX tolerance 1e-6", CudaBackendTest.maxDiff( rSmx, csm.softmax() ) <= 0.000001f )

        # ── 设备原地：zero（memset8）/ fillValue（TFILL）/ scaleInPlace（ESCALE dst==src）──
        Tensor gz = cm3.to( dev )
        gz.zero()
        Tensor zref = cm3.clone()
        zref.zero()
        CudaBackendTest.check( "zero (memset8) S2 exit", gz.isDevDirty && !gz.isHostDirty )
        CudaBackendTest.syncRead( gz )
        CudaBackendTest.check( "zero bitwise", CudaBackendTest.sameAll( gz, zref ) )

        gz.fillValue( 2.5f )
        CudaBackendTest.check( "TFILL S2 exit", gz.isDevDirty && !gz.isHostDirty )
        CudaBackendTest.syncRead( gz )
        bool fillOk = true
        Int32 fi = 0
        while fi < gz._data.length
        {
            if gz._data[fi] != 2.5f
            {
                fillOk = false
            }
            fi += 1
        }
        CudaBackendTest.check( "TFILL values", fillOk )

        Tensor gsip = cvec.to( dev )
        gsip.scaleInPlace( 3.0f )
        Tensor sipRef = cvec.clone()
        sipRef.scaleInPlace( 3.0f )
        CudaBackendTest.check( "ESCALE in-place S2 exit", gsip.isDevDirty && !gsip.isHostDirty )
        CudaBackendTest.syncRead( gsip )
        CudaBackendTest.check( "scaleInPlace bitwise", CudaBackendTest.sameAll( gsip, sipRef ) )

        # ── D2D：clone / copyFrom（P5 不过主机）──
        Tensor gcl = gsm.clone()
        CudaBackendTest.check( "clone D2D S2 exit", gcl.isDevDirty && !gcl.isHostDirty && gcl.hasDeviceBuffer )
        CudaBackendTest.syncRead( gcl )
        CudaBackendTest.check( "clone D2D bitwise", CudaBackendTest.sameAll( gcl, csm ) )

        Tensor gdst = cm3.to( dev )
        gdst.copyFrom( gm3 )
        CudaBackendTest.check( "copyFrom D2D S2 exit", gdst.isDevDirty && !gdst.isHostDirty )
        CudaBackendTest.syncRead( gdst )
        CudaBackendTest.check( "copyFrom D2D bitwise", CudaBackendTest.sameAll( gdst, cm3 ) )

        # ── 清理（显式释放，进程长驻规约）──
        ga.freeDevice()
        gb.freeDevice()
        gRow.freeDevice()
        gScalar.freeDevice()
        gCol.freeDevice()
        rRow.freeDevice()
        rScalar.freeDevice()
        rCol.freeDevice()
        rScale.freeDevice()
        rRelu.freeDevice()
        rExp.freeDevice()
        rSig.freeDevice()
        rTan.freeDevice()
        gm1.freeDevice()
        gm2.freeDevice()
        rMM.freeDevice()
        gm3.freeDevice()
        gm4.freeDevice()
        rMM64.freeDevice()
        gvec.freeDevice()
        gsm.freeDevice()
        rSmx.freeDevice()
        gz.freeDevice()
        gsip.freeDevice()
        gcl.freeDevice()
        gdst.freeDevice()
        rAdd.freeDevice()
        rSub.freeDevice()
        rMul.freeDevice()
        rDiv.freeDevice()
    }

    # ================================================================
    # 入口
    # ================================================================

    static fun()
    {
        global.println( "" )
        global.println( "===== CudaBackendTest start =====" )

        # 门控：开关默认关 → available(GPU) false；显式开启后探测真实设备
        bool gateBefore = Backends.available( EDeviceKind.GPU )
        CudaBackendTest.check( "gate off by default", gateBefore == false )
        Backends.setCudaEnabled( true )
        if !Backends.available( EDeviceKind.GPU )
        {
            global.println( "  (no CUDA device, skip rest of CudaBackendTest)" )
            global.println( "===== CudaBackendTest end PASS=" + CudaBackendTest.s_pass.toString() + " FAIL=" + CudaBackendTest.s_fail.toString() + " =====" )
            ret
        }
        CudaBackendTest.check( "available(GPU) after enable", true )
        CudaBackendTest.check( "driver resolved", Cuda.driverVersion() > 0 )
        CudaBackendTest.s_dev = Device.gpu( 0 )

        # ── OQ-1 布局防漂移断言（固化）：VMArray data@48 / length@32 ──
        # csimple_lang 的 vm_array.h 布局一旦变更（VMObject/VMArray 字段
        # 增删），此断言先于一切搬运路径变红（CudaBackend.arrayDataPtr
        # 的 48 偏移即失配）。位模式对照：1.5f=0x3FC00000=1069547520、
        # 100f=0x42C80000=1120403456、0.5f=0x3F000000=1056964608。
        Array<Float32> pa = Array<Float32>( 4 )
        pa[0] = 1.5f
        pa[1] = 100.0f
        pa[2] = 0.5f
        pa[3] = 2.0f
        Int64 paAddr = SystemPtrFromObject( pa )
        Int64 paData = SystemPtrReadInt64( paAddr, 48 )
        CudaBackendTest.check( "OQ1 VMArray length@32", SystemPtrReadInt32( paAddr, 32 ) == 4 )
        CudaBackendTest.check( "OQ1 VMArray data@48 nonzero", paData != 0 )
        CudaBackendTest.check( "OQ1 pin element bits", SystemPtrReadInt32( paData, 0 ) == 1069547520 && SystemPtrReadInt32( paData, 4 ) == 1120403456 && SystemPtrReadInt32( paData, 8 ) == 1056964608 && SystemPtrReadInt32( paData, 12 ) == 1073741824 )

        CudaBackendTest.stateMachineRun()
        CudaBackendTest.consistencyRun()

        global.println( "bytesUsed after all frees: " + CudaBackendTest.s_dev.bytesUsed.toString() )
        global.println( "" )
        global.println( "===== CudaBackendTest end PASS=" + CudaBackendTest.s_pass.toString() + " FAIL=" + CudaBackendTest.s_fail.toString() + " =====" )
    }

    # ================================================================
    # bench（独立入口，不进 _main_）：§5.7 分段基准 + matmul GPU vs CPU
    # 产 [PROBE] 行，落盘 out\probe\h2d_bench.txt（TensoraBackend.md §5.7）
    # ================================================================

    # 分段计时一段：n 元素 f32 的 P1 / P2 / P4 / memset 各段毫秒
    static void benchStagingOnce( Int32 n )
    {
        Device dev = CudaBackendTest.s_dev
        Array<Float32> arr = Array<Float32>( n )
        Int32 i = 0
        while i < n
        {
            arr[i] = SystemConvertFloat32( i % 100 ) / 100.0f
            i += 1
        }
        Int32 bytes = n * 4

        # 设备块
        Int64 db = CudaBackend.allocDevRaw( bytes, dev )
        if db == 0
        {
            global.println( "[PROBE] staging alloc failed, n=" + n.toString() )
            ret
        }

        # P1：A→B 循环写（B 块组包）
        Int64 t0 = SystemTimerClock()
        Int64 blk = Memory.alloc( bytes )
        Int32 j = 0
        while j < n
        {
            Memory.writeF32( blk, j * 4, arr[j] )
            j += 1
        }
        Int64 t1 = SystemTimerClock()

        # P2：B→C DMA 上传
        Cuda.libMemcpyH2D( db, blk, bytes )
        Cuda.libCtxSync()
        Int64 t2 = SystemTimerClock()

        # P3：C→B DMA 下载（P3 与 P2 对称，一并记录）
        Cuda.libMemcpyD2H( blk, db, bytes )
        Cuda.libCtxSync()
        Int64 t3 = SystemTimerClock()

        # P4：B→A 循环读
        Int32 k = 0
        while k < n
        {
            arr[k] = Memory.readFloat32( blk, k * 4 )
            k += 1
        }
        Int64 t4 = SystemTimerClock()

        # memset8（设备侧整块清零）
        Cuda.libMemset8( db, 0, bytes )
        Cuda.libCtxSync()
        Int64 t5 = SystemTimerClock()

        Memory.free( blk )
        CudaBackend.freeDevRaw( db, bytes, dev )

        Int64 p1 = t1 - t0
        Int64 p2 = t2 - t1
        Int64 p3 = t3 - t2
        Int64 p4 = t4 - t3
        Int64 ms = t5 - t4
        global.println( "[PROBE] staging,n=" + n.toString() + ",p1_write_ms=" + p1.toString() + ",p2_h2d_ms=" + p2.toString() + ",p3_d2h_ms=" + p3.toString() + ",p4_read_ms=" + p4.toString() + ",memset_ms=" + ms.toString() )
    }

    # matmul n² 对比：GPU 全链（to×2 + kernel + download）vs CPU SIMD
    # （CPU 侧启用 SIMD + 阈值 -1 强制分派，代表 CPU 最佳状态）
    static void benchMatmulOnce( Int32 n )
    {
        Device dev = CudaBackendTest.s_dev
        Tensor ca = CudaBackendTest.makeMatrix( n, n )
        Tensor cb = CudaBackendTest.makeMatrix( n, n )

        # GPU 全链（分段计时：to×2 / kernel / download）
        Backends.setCudaEnabled( true )
        Int64 g0 = SystemTimerClock()
        Tensor ga = ca.to( dev )
        Int64 g1 = SystemTimerClock()
        Tensor gb = cb.to( dev )
        Int64 g2 = SystemTimerClock()
        Tensor gr = ga.matmul( gb )
        Int64 g3 = SystemTimerClock()
        CudaBackendTest.syncRead( gr )
        Int64 g4 = SystemTimerClock()

        # CPU SIMD（P1+kernel+P4 全链）
        Backends.setSimdEnabled( true )
        Int64 savedT = Backends.T_MMUL
        Backends.T_MMUL = -1
        Int64 c0 = SystemTimerClock()
        Tensor cr = ca.matmul( cb )
        Int64 c1 = SystemTimerClock()
        Backends.T_MMUL = savedT
        Backends.setSimdEnabled( false )

        # 一致性旁证
        bool ok = CudaBackendTest.sameAll( gr, cr )

        ga.freeDevice()
        gb.freeDevice()
        gr.freeDevice()

        Int64 gms = g4 - g0
        Int64 cms = c1 - c0
        Float32 sp = SystemConvertFloat32( cms ) / SystemConvertFloat32( gms )
        global.println( "[PROBE] matmul,n=" + n.toString() + ",gpu_total_ms=" + gms.toString() + ",cpu_simd_ms=" + cms.toString() + ",speedup=" + sp.toString() + ",bitwise=" + SystemConvertString( ok ) + ",upload_a_ms=" + ( g1 - g0 ).toString() + ",upload_b_ms=" + ( g2 - g1 ).toString() + ",kernel_ms=" + ( g3 - g2 ).toString() + ",download_ms=" + ( g4 - g3 ).toString() )
    }

    static bench()
    {
        global.println( "" )
        global.println( "===== CudaBackendTest.bench (out\\probe\\h2d_bench.txt) =====" )
        Backends.setCudaEnabled( true )
        if !Backends.available( EDeviceKind.GPU )
        {
            global.println( "no CUDA device, bench skipped" )
            ret
        }
        CudaBackendTest.s_dev = Device.gpu( 0 )
        CudaBackendTest.benchStagingOnce( 16 * 1024 )
        CudaBackendTest.benchStagingOnce( 256 * 1024 )
        CudaBackendTest.benchStagingOnce( 1024 * 1024 )
        CudaBackendTest.benchStagingOnce( 4 * 1024 * 1024 )
        CudaBackendTest.benchStagingOnce( 16 * 1024 * 1024 )
        CudaBackendTest.benchMatmulOnce( 512 )
        CudaBackendTest.benchMatmulOnce( 1024 )
    }
}
