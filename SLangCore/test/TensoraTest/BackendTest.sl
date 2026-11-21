import Tensora
import Math;

# BackendTest —— P1 验证：设备层骨架 + 状态机不变式 + CPU 算子补齐
#
# 设计文档：TensoraBackend.md §8（P1 验收）
# 覆盖：
#   1. stateTest   影子缓冲状态机（CPU 路径 I1-I4）
#   2. deviceTest  Device/Backends/to()/cpu()/freeDevice()/异常通道
#   3. reduceTest  任意轴归约泛化（修复 OQ-7 的 2D 假设）
#   4. compareTest 比较算子（eq/gt/maximum/where 广播）
#   5. indexTest   索引算子（indexSelect/gather/scatter/maskedFill/nonzero）
#   6. shapeTest   形状算子（squeeze/unsqueeze/expand/repeatTile/pad/
#                  catTensors 任意维/stackAxis/flip/narrow/chunk）

BackendTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            global.println( "[BackendTest] " + name + " : OK" )
        }
        else
        {
            global.println( "[BackendTest] " + name + " : FAIL" )
        }
    }

    # ── 1. 状态机（CPU 路径：I3 无影子⇒devDirty 恒 false；写钩子置 hostDirty）──
    static stateTest()
    {
        global.println( "===== BackendTest.stateTest =====" )
        Tensor t = Tensor( Shape.matrix( 2, 2 ) )

        # I3：_devBlock==0 ⇒ _devDirty==false
        check( "I3 fresh: no dev buffer", t.hasDeviceBuffer() == false )
        check( "I3 fresh: devDirty false", t.isDevDirty() == false )

        # S1：构造后 _data 权威（zero() 走 fillValue 写钩子）
        check( "S1 fresh: hostDirty true", t.isHostDirty() == true )

        # 写钩子：setAt 后保持 S1
        t.setAt( 0, 0, 5.0f )
        check( "write hook: hostDirty true", t.isHostDirty() == true )

        # 读钩子不改变状态（CPU 路径无下载）
        Float32 v = t.at( 0, 0 )
        check( "read hook: value intact", v == 5.0f )
        check( "read hook: state unchanged", t.isHostDirty() == true )

        # freeDevice：CPU 张量空操作，回到 S1
        t.freeDevice()
        check( "freeDevice: no dev buffer", t.hasDeviceBuffer() == false )
        check( "freeDevice: hostDirty true", t.isHostDirty() == true )

        # I4：CPU 算子出口 = S1（写类算子产出新张量）
        Tensor s = t.add( Tensor.ones( Shape.matrix( 2, 2 ) ) )
        check( "I4 op output: hostDirty true", s.isHostDirty() == true )
        check( "I4 op output: devDirty false", s.isDevDirty() == false )

        # clone 保留 dtype
        Tensor c = t.clone()
        check( "clone keeps dtype", c.dtype() == EDtype.F32 )
    }

    # ── 2. 设备层（to/cpu no-op 短路、跨设备显式报错、Backends 探测）──
    static deviceTest()
    {
        global.println( "===== BackendTest.deviceTest =====" )

        # Device 工厂与判定
        Device d0 = Device.cpu()
        check( "cpu device kind", d0.isCpu() == true )
        Device d1 = Device.gpu( 0 )
        check( "gpu device kind", d1.isGpu() == true )
        check( "gpu device name", d1.name == "cuda:0" )
        check( "sameDevice gpu0/gpu0", d1.sameDevice( Device.gpu( 0 ) ) == true )
        check( "sameDevice gpu0/gpu1", d1.sameDevice( Device.gpu( 1 ) ) == false )
        check( "bothCpu null/null", Device.bothCpu( null, null ) == true )
        check( "bothCpu cpu/gpu", Device.bothCpu( d0, d1 ) == false )

        # 枚举显式赋值回归（历史 bug：GPU/NPU 未赋值全为 0）
        check( "EDeviceKind.GPU != CPU", EDeviceKind.GPU != EDeviceKind.CPU )
        check( "EDeviceKind.ROCM value", EDeviceKind.ROCM == 3 )
        check( "EDeviceKind.TPU value", EDeviceKind.TPU == 4 )

        # Backends 探测：CPU 恒可用，其余 P1 恒 false
        check( "available(CPU)", Backends.available( EDeviceKind.CPU ) == true )
        check( "available(GPU) false in P1", Backends.available( EDeviceKind.GPU ) == false )
        check( "available(ROCM) false in P1", Backends.available( EDeviceKind.ROCM ) == false )

        # checkPair：cpu×cpu 放行
        bool okPair = false
        label pairOk
        {
            Backends.checkPair( null, null )
            Backends.checkPair( Device.cpu(), null )
            okPair = true
        }
        catch
        {
            okPair = false
        }
        check( "checkPair cpu x cpu pass", okPair == true )

        # checkPair：cpu×cuda 抛 DeviceMismatch（D4 显式失败）
        bool threwMismatch = false
        label pairBad
        {
            Backends.checkPair( Device.cpu(), Device.gpu( 0 ) )
        }
        catch
        {
            threwMismatch = true
        }
        check( "checkPair cpu x cuda throws", threwMismatch == true )

        # to(cpu) 同设备 no-op 短路（返回自身）
        Tensor t = Tensor.matrix( [ 1.0f, 2.0f ], 1, 2 )
        bool noOp = false
        label toCpu
        {
            Tensor t2 = t.to( Device.cpu() )
            if t2 == t
            {
                noOp = true
            }
        }
        catch
        {
            noOp = false
        }
        check( "to(cpu) no-op returns self", noOp == true )

        # to(cuda) P1 后端未接入 → BackendError.Unavailable
        bool threwUnavail = false
        label toGpu
        {
            Tensor t3 = t.to( Device.gpu( 0 ) )
        }
        catch
        {
            threwUnavail = true
        }
        check( "to(cuda) throws Unavailable", threwUnavail == true )

        # Dtype 宽度表（对齐 Core.Memory.sizeOf）
        check( "bytesOf F32", Dtype.bytesOf( EDtype.F32 ) == 4 )
        check( "bytesOf F16", Dtype.bytesOf( EDtype.F16 ) == 2 )
        check( "bytesOf BF16", Dtype.bytesOf( EDtype.BF16 ) == 2 )
        check( "bytesOf I64", Dtype.bytesOf( EDtype.I64 ) == 8 )
        check( "bytesOf BOOL", Dtype.bytesOf( EDtype.BOOL ) == 1 )
        check( "nameOf BF16", Dtype.nameOf( EDtype.BF16 ) == "bf16" )
    }

    # ── 3. 归约泛化（3D 张量任意轴；x[i,j,k] = i*12 + j*4 + k）──
    static reduceTest()
    {
        global.println( "===== BackendTest.reduceTest =====" )
        Tensor x = Tensor( Shape( 2, 3, 4 ) )
        for f = 0, f < 24, f++
        {
            x.setAt( f, SystemConvertFloat32( f ) )
        }

        # sumDim(1)：out[i,k] = 36i + 3k + 12
        Tensor s1 = x.sumDim( 1 )
        Shape s1s = s1.shape()
        check( "sumDim(1) shape (2,4)", s1s.dims[0] == 2 && s1s.dims[1] == 4 )
        check( "sumDim(1)[0,0]==12", s1.at( 0, 0 ) == 12.0f )
        check( "sumDim(1)[0,3]==21", s1.at( 0, 3 ) == 21.0f )
        check( "sumDim(1)[1,3]==57", s1.at( 1, 3 ) == 57.0f )

        # keepdim 兼容入口：sumAlong(1) → [2,1,4]
        Tensor sk = x.sumAlong( 1 )
        Shape sks = sk.shape()
        check( "sumAlong(1) keepdim (2,1,4)", sks.rank() == 3 && sks.dims[1] == 1 )
        check( "sumAlong(1) value", sk.at( 1, 0, 3 ) == 57.0f )

        # 3D 轴 0 归约（旧实现会错读 dims[1] 作行数）
        # out[j,k] = x[0,j,k] + x[1,j,k] = 2*(j*4+k) + 12
        Tensor s0 = x.sumDim( 0 )
        check( "sumDim(0)[2,3]==34", s0.at( 2, 3 ) == 34.0f )

        # meanDim(2)：行均值 = i*12 + j*4 + 1.5
        Tensor m2 = x.meanDim( 2 )
        check( "meanDim(2)[1,2]==21.5", m2.at( 1, 2 ) == 21.5f )

        # argmaxAlong(1)：值随 j 单调增 → 全 2
        Tensor am = x.argmaxAlong( 1 )
        Shape ams = am.shape()
        check( "argmaxAlong(1) shape (2,4)", ams.dims[0] == 2 && ams.dims[1] == 4 )
        check( "argmaxAlong(1)[0,0]==2", am.at( 0, 0 ) == 2.0f )

        # minAlong(0) keepdim
        Tensor mn0 = x.minAlong( 0 )
        check( "minAlong(0)[1,2]==6", mn0.at( 0, 1, 2 ) == 6.0f )

        # cumsumAlong(2)：行内前缀和
        Tensor cs = x.cumsumAlong( 2 )
        check( "cumsum(2)[0,0,*]", cs.at( 0, 0, 0 ) == 0.0f && cs.at( 0, 0, 1 ) == 1.0f && cs.at( 0, 0, 3 ) == 6.0f )

        # varAlong(1)（无偏）：{b, b+4, b+8} 方差 = 16
        Tensor vr = x.varAlong( 1 )
        check( "varAlong(1)[0,0]==16", vr.at( 0, 0, 0 ) == 16.0f )
        Tensor sd = x.stdAlong( 1 )
        check( "stdAlong(1)[0,0]==4", sd.at( 0, 0, 0 ) == 4.0f )

        # 全量归约
        Tensor vec = Tensor.vector( [ 3.0f, 4.0f ] )
        check( "prod()==12", vec.prod() == 12.0f )
        check( "norm()==5", vec.norm() == 5.0f )
        check( "variance()==0.5", vec.variance() == 0.5f )
        check( "std()==sqrt(0.5)", vec.std() == Mathf.sqrt( 0.5f ) )
        check( "anyNonZero", vec.anyNonZero() == true )
        Tensor zv = Tensor.vector( [ 0.0f, 0.0f ] )
        check( "anyNonZero false", zv.anyNonZero() == false )
        check( "allNonZero false", vec.allNonZero() == true )
    }

    # ── 4. 比较算子（广播）─────────────────────────────────
    static compareTest()
    {
        global.println( "===== BackendTest.compareTest =====" )
        Tensor a = Tensor.vector( [ 1.0f, 2.0f, 3.0f ] )
        Tensor b = Tensor.vector( [ 2.0f, 2.0f, 2.0f ] )

        Tensor g = a.gt( b )
        check( "gt", g.at( 0 ) == 0.0f && g.at( 2 ) == 1.0f )
        Tensor e = a.eq( b )
        check( "eq", e.at( 1 ) == 1.0f && e.at( 0 ) == 0.0f )
        Tensor n = a.ne( b )
        check( "ne", n.at( 0 ) == 1.0f && n.at( 1 ) == 0.0f )
        Tensor ge = a.ge( b )
        check( "ge", ge.at( 1 ) == 1.0f && ge.at( 2 ) == 1.0f )
        Tensor lt = a.lt( b )
        check( "lt", lt.at( 0 ) == 1.0f && lt.at( 2 ) == 0.0f )
        Tensor le = a.le( b )
        check( "le", le.at( 0 ) == 1.0f && le.at( 2 ) == 0.0f )

        # 广播：[3] vs [1,3]
        Tensor row = Tensor.matrix( [ 10.0f, 20.0f, 30.0f ], 1, 3 )
        Tensor mx = a.maximum( row )
        check( "maximum broadcast", mx.at( 0, 0 ) == 10.0f && mx.at( 0, 2 ) == 30.0f )
        Tensor mn = a.minimum( row )
        check( "minimum broadcast", mn.at( 0, 0 ) == 1.0f && mn.at( 0, 1 ) == 2.0f )

        # where：cond [1,0,1] → a/b 选择
        Tensor cond = Tensor.vector( [ 1.0f, 0.0f, 1.0f ] )
        Tensor w = Tensor.where( cond, a, b )
        check( "where", w.at( 0 ) == 1.0f && w.at( 1 ) == 2.0f && w.at( 2 ) == 3.0f )
    }

    # ── 5. 索引算子 ────────────────────────────────────────
    static indexTest()
    {
        global.println( "===== BackendTest.indexTest =====" )
        Tensor src = Tensor.matrix( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 )

        # indexSelect(0, [1,0]) → [[3,4],[1,2]]
        Array<Int32> idx1 = [ 1, 0 ]
        Tensor isel = Ops.indexSelect( src, 0, idx1 )
        check( "indexSelect rows", isel.at( 0, 0 ) == 3.0f && isel.at( 1, 0 ) == 1.0f )

        # gather(axis=1, idx=[[1,0],[0,1]])
        Tensor gidx = Tensor.matrix( [ 1.0f, 0.0f, 0.0f, 1.0f ], 2, 2 )
        Tensor gt = Ops.gather( src, 1, gidx )
        check( "gather", gt.at( 0, 0 ) == 2.0f && gt.at( 0, 1 ) == 1.0f && gt.at( 1, 1 ) == 4.0f )

        # scatter(axis=1) value [[10,20],[30,40]]
        Tensor val = Tensor.matrix( [ 10.0f, 20.0f, 30.0f, 40.0f ], 2, 2 )
        Tensor sc = Ops.scatter( Tensor.zeros( Shape.matrix( 2, 2 ) ), 1, gidx, val )
        check( "scatter", sc.at( 0, 1 ) == 10.0f && sc.at( 0, 0 ) == 20.0f && sc.at( 1, 0 ) == 30.0f )

        # maskedFill
        Tensor mask = Tensor.vector( [ 1.0f, 0.0f, 1.0f ] )
        Tensor mf = Ops.maskedFill( Tensor.vector( [ 1.0f, 2.0f, 3.0f ] ), mask, 9.0f )
        check( "maskedFill", mf.at( 0 ) == 9.0f && mf.at( 1 ) == 2.0f && mf.at( 2 ) == 9.0f )

        # nonzero
        Tensor nz = Tensor.vector( [ 0.0f, 1.0f, 0.0f, 3.0f ] )
        Array<Int32> hits = Ops.nonzero( nz )
        check( "nonzero", hits.length == 2 && hits[0] == 1 && hits[1] == 3 )
    }

    # ── 6. 形状算子 ────────────────────────────────────────
    static shapeTest()
    {
        global.println( "===== BackendTest.shapeTest =====" )

        # squeeze / unsqueeze
        Tensor t13 = Tensor( Shape( 1, 3, 1 ) )
        Tensor sq = Ops.squeeze( t13 )
        Shape sqs = sq.shape()
        check( "squeeze -> (3)", sqs.rank() == 1 && sqs.dims[0] == 3 )
        Tensor us = Ops.unsqueeze( Tensor.vector( [ 1.0f, 2.0f, 3.0f ] ), 0 )
        Shape uss = us.shape()
        check( "unsqueeze(0) -> (1,3)", uss.rank() == 2 && uss.dims[0] == 1 && uss.dims[1] == 3 )

        # expand：[1,3] -> [2,3]
        Tensor ex = Ops.expand( us, Shape.matrix( 2, 3 ) )
        check( "expand value", ex.at( 0, 2 ) == 3.0f && ex.at( 1, 0 ) == 1.0f )

        # repeatTile：[2,2] tiles [2,1] -> [4,2]
        Tensor rp = Ops.repeatTile( Tensor.matrix( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 ), [ 2, 1 ] )
        check( "repeatTile", rp.at( 2, 0 ) == 1.0f && rp.at( 3, 1 ) == 4.0f )

        # padLastDim：[2,2] -> [2,4]（左右各补 1）
        Tensor pd = Ops.padLastDim( Tensor.matrix( [ 1.0f, 2.0f, 3.0f, 4.0f ], 2, 2 ), 1, 1, 0.0f )
        Shape pds = pd.shape()
        check( "pad shape (2,4)", pds.dims[0] == 2 && pds.dims[1] == 4 )
        check( "pad value", pd.at( 0, 0 ) == 0.0f && pd.at( 0, 1 ) == 1.0f && pd.at( 0, 2 ) == 2.0f && pd.at( 0, 3 ) == 0.0f )

        # catTensors 任意维：[2,2,2] + [2,1,2] axis=1 -> [2,3,2]
        # seam：axis=1 索引 0-1 来自 c1，索引 2 来自 c2（c2 的 axis=1 仅 0）
        Tensor c1 = Tensor( Shape( 2, 2, 2 ) )
        for f = 0, f < 8, f++
        {
            c1.setAt( f, SystemConvertFloat32( f ) )
        }
        Tensor c2 = Tensor( Shape( 2, 1, 2 ) )
        for f = 0, f < 4, f++
        {
            c2.setAt( f, SystemConvertFloat32( 100 + f ) )
        }
        Array<Tensor> cl = [ c1, c2 ]
        Tensor cat = Ops.catTensors( cl, 1 )
        Shape cats = cat.shape()
        check( "cat3d shape (2,3,2)", cats.dims[0] == 2 && cats.dims[1] == 3 && cats.dims[2] == 2 )
        check( "cat3d seam", cat.at( 0, 1, 0 ) == 100.0f && cat.at( 0, 2, 1 ) == 101.0f && cat.at( 0, 0, 1 ) == 1.0f )

        # stackAxis：3 x [2] -> [3,2]
        Tensor v1 = Tensor.vector( [ 1.0f, 2.0f ] )
        Tensor v2 = Tensor.vector( [ 3.0f, 4.0f ] )
        Tensor v3 = Tensor.vector( [ 5.0f, 6.0f ] )
        Array<Tensor> sl = [ v1, v2, v3 ]
        Tensor st = Ops.stackAxis( sl, 0 )
        Shape sts = st.shape()
        check( "stack shape (3,2)", sts.dims[0] == 3 && sts.dims[1] == 2 )
        check( "stack value", st.at( 0, 0 ) == 1.0f && st.at( 2, 1 ) == 6.0f )

        # flip
        Tensor fl = Ops.flip( Tensor.vector( [ 1.0f, 2.0f, 3.0f ] ), 0 )
        check( "flip", fl.at( 0 ) == 3.0f && fl.at( 2 ) == 1.0f )

        # narrow：[1..6] 取 [2,5)
        Tensor nw = Ops.narrow( Tensor.vector( [ 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f ] ), 0, 2, 3 )
        check( "narrow", nw.size() == 3 && nw.at( 0 ) == 3.0f && nw.at( 2 ) == 5.0f )

        # chunk：5 均分 2 → [3,2]
        Array<Tensor> ch = Ops.chunk( Tensor.vector( [ 1.0f, 2.0f, 3.0f, 4.0f, 5.0f ] ), 2, 0 )
        Tensor ch0 = ch[0]
        Tensor ch1 = ch[1]
        check( "chunk sizes", ch0.size() == 3 && ch1.size() == 2 )
        check( "chunk values", ch0.at( 2 ) == 3.0f && ch1.at( 0 ) == 4.0f )
    }

    static fun()
    {
        BackendTest.stateTest()
        BackendTest.deviceTest()
        BackendTest.reduceTest()
        BackendTest.compareTest()
        BackendTest.indexTest()
        BackendTest.shapeTest()
    }
}
