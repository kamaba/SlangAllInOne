import Tensora
import Math

# Tensora 基础算子补全测试（P2 期批量补齐验收）
# 覆盖：构造（arange/linspace/eye）、逐元素补全（reciprocal/rsqrt/
# sqrt/abs/exp2/log2/floor/ceil/round/sign/square/frac/expm1/log1p/
# fmod/三角/双曲/激活补充）、maximum/minimum、归约扩展（argmax/
# argmin/cumprod/countNonZero）、代数（dot/outer）、形状补全
# （squeeze/unsqueeze/flip/cat）。
# GPU 段（有卡时）：位级组（sqrt/abs/floor/ceil/round/sign/square/
# reciprocal/maximum/minimum）与 CPU 逐位对照；近似组（rsqrt/exp2/
# log2/silu/gelu）容差对照。无卡自动跳过。
TensorOpsTest {
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( string name, bool ok )
    {
        if ok
        {
            TensorOpsTest._pass += 1
            global.println( "[TensorOpsTest] " + name + " : OK" )
        }
        else
        {
            TensorOpsTest._fail += 1
            global.println( "[TensorOpsTest] " + name + " : FAIL" )
        }
    }

    static Tensor vec4( Float32 a, Float32 b, Float32 c, Float32 d )
    {
        Tensor t = Tensor( Shape.vector( 4 ) )
        t._data[0] = a
        t._data[1] = b
        t._data[2] = c
        t._data[3] = d
        ret t
    }

    static Tensor vec3( Float32 a, Float32 b, Float32 c )
    {
        Tensor t = Tensor( Shape.vector( 3 ) )
        t._data[0] = a
        t._data[1] = b
        t._data[2] = c
        ret t
    }

    static Tensor vec2( Float32 a, Float32 b )
    {
        Tensor t = Tensor( Shape.vector( 2 ) )
        t._data[0] = a
        t._data[1] = b
        ret t
    }

    static bool sameVec( Tensor a, Tensor want )
    {
        if a._data.length != want._data.length
        {
            ret false
        }
        for i = 0, i < a._data.length, i++
        {
            if a._data[i] != want._data[i]
            {
                ret false
            }
        }
        ret true
    }

    static bool nearVec( Tensor a, Tensor want, Float32 tol )
    {
        if a._data.length != want._data.length
        {
            ret false
        }
        for i = 0, i < a._data.length, i++
        {
            Float32 d = a._data[i] - want._data[i]
            if d < 0.0f
            {
                d = 0.0f - d
            }
            if d > tol
            {
                ret false
            }
        }
        ret true
    }

    # GPU 结果下载后与 CPU 结果逐位对照
    static void gpuSame( string name, Tensor cpuR, Tensor gpuR )
    {
        if cpuR == null || gpuR == null
        {
            TensorOpsTest.check( name + " (null)", false )
            ret
        }
        Tensor back = gpuR.cpu()
        TensorOpsTest.check( name, TensorOpsTest.sameVec( cpuR, back ) )
    }

    # GPU 结果下载后与 CPU 结果容差对照
    static void gpuNear( string name, Tensor cpuR, Tensor gpuR, Float32 tol )
    {
        if cpuR == null || gpuR == null
        {
            TensorOpsTest.check( name + " (null)", false )
            ret
        }
        Tensor back = gpuR.cpu()
        TensorOpsTest.check( name, TensorOpsTest.nearVec( cpuR, back, tol ) )
    }

    static void fun()
    {
        global.println( "===== TensorOpsTest start =====" )

        # ── 1. 构造器 ─────────────────────────────────────
        Tensor a4 = Tensor.arange( 4 )
        TensorOpsTest.check( "arange(4)", TensorOpsTest.sameVec( a4, TensorOpsTest.vec4( 0.0f, 1.0f, 2.0f, 3.0f ) ) )

        Tensor a3 = Tensor.arange( 2, 10, 3 )
        TensorOpsTest.check( "arange(2,10,3)", TensorOpsTest.sameVec( a3, TensorOpsTest.vec3( 2.0f, 5.0f, 8.0f ) ) )

        Tensor ls = Tensor.linspace( 0.0f, 1.0f, 5 )
        TensorOpsTest.check( "linspace(0,1,5)", ls._data.length == 5 && ls._data[0] == 0.0f && ls._data[4] == 1.0f && Mathf.abs( ls._data[2] - 0.5f ) < 0.0001f )

        Tensor e3 = Tensor.eye( 3 )
        bool eyeOk = e3.rows() == 3 && e3.at( 0, 0 ) == 1.0f && e3.at( 1, 1 ) == 1.0f && e3.at( 2, 2 ) == 1.0f && e3.at( 0, 1 ) == 0.0f && e3.at( 1, 2 ) == 0.0f
        TensorOpsTest.check( "eye(3)", eyeOk )

        # ── 2. 逐元素补全（CPU 值断言）────────────────────
        # 位级组（值全为可精确表示数）
        Tensor xq = TensorOpsTest.vec4( 4.0f, 9.0f, 16.0f, 25.0f )
        TensorOpsTest.check( "sqrt", TensorOpsTest.sameVec( xq.sqrt(), TensorOpsTest.vec4( 2.0f, 3.0f, 4.0f, 5.0f ) ) )
        TensorOpsTest.check( "abs", TensorOpsTest.sameVec( xq.abs(), xq ) )

        Tensor xr = TensorOpsTest.vec4( 2.0f, 4.0f, 5.0f, 8.0f )
        TensorOpsTest.check( "reciprocal", TensorOpsTest.sameVec( xr.reciprocal(), TensorOpsTest.vec4( 0.5f, 0.25f, 0.2f, 0.125f ) ) )

        Tensor xe = TensorOpsTest.vec4( 1.0f, 2.0f, 3.0f, 10.0f )
        TensorOpsTest.check( "exp2", TensorOpsTest.sameVec( xe.exp2(), TensorOpsTest.vec4( 2.0f, 4.0f, 8.0f, 1024.0f ) ) )

        Tensor xl = TensorOpsTest.vec4( 2.0f, 8.0f, 1024.0f, 65536.0f )
        TensorOpsTest.check( "log2", TensorOpsTest.sameVec( xl.log2(), TensorOpsTest.vec4( 1.0f, 3.0f, 10.0f, 16.0f ) ) )

        Tensor xrs = TensorOpsTest.vec4( 1.0f, 4.0f, 16.0f, 65536.0f )
        TensorOpsTest.check( "rsqrt", TensorOpsTest.nearVec( xrs.rsqrt(), TensorOpsTest.vec4( 1.0f, 0.5f, 0.25f, 0.00390625f ), 0.000001f ) )

        Tensor xm = TensorOpsTest.vec4( -1.7f, 2.3f, -0.6f, 3.9f )
        TensorOpsTest.check( "floor", TensorOpsTest.sameVec( xm.floor(), TensorOpsTest.vec4( -2.0f, 2.0f, -1.0f, 3.0f ) ) )
        TensorOpsTest.check( "ceil", TensorOpsTest.sameVec( xm.ceil(), TensorOpsTest.vec4( -1.0f, 3.0f, 0.0f, 4.0f ) ) )
        TensorOpsTest.check( "round", TensorOpsTest.sameVec( xm.round(), TensorOpsTest.vec4( -2.0f, 2.0f, -1.0f, 4.0f ) ) )
        TensorOpsTest.check( "sign", TensorOpsTest.sameVec( xm.sign(), TensorOpsTest.vec4( -1.0f, 1.0f, -1.0f, 1.0f ) ) )
        Tensor xsq = TensorOpsTest.vec4( -1.7f * -1.7f, 2.3f * 2.3f, -0.6f * -0.6f, 3.9f * 3.9f )
        TensorOpsTest.check( "square", TensorOpsTest.sameVec( xm.square(), xsq ) )

        Tensor xa = TensorOpsTest.vec4( 1.0f, 4.0f, 16.0f, 25.0f )
        TensorOpsTest.check( "maximum", TensorOpsTest.sameVec( xa.maximum( xr ), TensorOpsTest.vec4( 2.0f, 4.0f, 16.0f, 25.0f ) ) )
        TensorOpsTest.check( "minimum", TensorOpsTest.sameVec( xa.minimum( xr ), TensorOpsTest.vec4( 1.0f, 4.0f, 5.0f, 8.0f ) ) )

        # 近似 / 特殊函数组（容差）
        Tensor xf = TensorOpsTest.vec4( 3.75f, -3.75f, 2.5f, -0.25f )
        TensorOpsTest.check( "frac", TensorOpsTest.sameVec( xf.frac(), TensorOpsTest.vec4( 0.75f, 0.25f, 0.5f, 0.75f ) ) )

        Tensor xm1 = TensorOpsTest.vec2( 0.0f, 1.0f )
        TensorOpsTest.check( "expm1", TensorOpsTest.nearVec( xm1.expm1(), TensorOpsTest.vec2( 0.0f, 1.7182818f ), 0.00001f ) )

        Tensor l1 = TensorOpsTest.vec2( 0.0f, 1.7182818f )
        TensorOpsTest.check( "log1p", TensorOpsTest.nearVec( l1.log1p(), TensorOpsTest.vec2( 0.0f, 1.0f ), 0.00001f ) )

        # fmod：精确可表示值（7%3 / -5%2 / 5.5%2 / b=0 → 0）
        Tensor fd = TensorOpsTest.vec4( 7.0f, -5.0f, 5.5f, 9.0f )
        Tensor fm = fd.fmod( TensorOpsTest.vec4( 3.0f, 2.0f, 2.0f, 0.0f ) )
        TensorOpsTest.check( "fmod", TensorOpsTest.sameVec( fm, TensorOpsTest.vec4( 1.0f, -1.0f, 1.5f, 0.0f ) ) )

        # 三角 / 双曲
        Tensor z1 = TensorOpsTest.vec3( 0.0f, 0.0f, 0.0f )
        TensorOpsTest.check( "sin cos tan at 0", z1.sin()._data[0] == 0.0f && z1.cos()._data[0] == 1.0f && z1.tan()._data[0] == 0.0f )
        TensorOpsTest.check( "sinh cosh at 0", z1.sinh()._data[0] == 0.0f && z1.cosh()._data[0] == 1.0f )
        Tensor t1 = TensorOpsTest.vec2( 1.0f, 1.0f )
        TensorOpsTest.check( "sinh(1) cosh(1)", TensorOpsTest.nearVec( t1.sinh(), TensorOpsTest.vec2( 1.1752012f, 1.1752012f ), 0.000001f ) && TensorOpsTest.nearVec( t1.cosh(), TensorOpsTest.vec2( 1.5430806f, 1.5430806f ), 0.000001f ) )

        # pow / clamp
        Tensor pw = TensorOpsTest.vec4( 2.0f, 3.0f, 5.0f, 10.0f )
        TensorOpsTest.check( "pow(2)", TensorOpsTest.sameVec( pw.pow( 2.0f ), TensorOpsTest.vec4( 4.0f, 9.0f, 25.0f, 100.0f ) ) )
        Tensor cl = TensorOpsTest.vec4( -1.0f, 5.0f, 0.5f, 3.0f )
        TensorOpsTest.check( "clamp(0,3)", TensorOpsTest.sameVec( cl.clamp( 0.0f, 3.0f ), TensorOpsTest.vec4( 0.0f, 3.0f, 0.5f, 3.0f ) ) )

        # ── 3. 激活补充（CPU 值断言，容差）─────────────────
        Tensor act = TensorOpsTest.vec2( -1.0f, 1.0f )
        TensorOpsTest.check( "silu", TensorOpsTest.nearVec( act.silu(), TensorOpsTest.vec2( -0.2689414f, 0.7310586f ), 0.000001f ) )
        TensorOpsTest.check( "gelu", TensorOpsTest.nearVec( act.gelu(), TensorOpsTest.vec2( -0.1587126f, 0.8412874f ), 0.0001f ) )
        TensorOpsTest.check( "softplus", TensorOpsTest.nearVec( act.softplus(), TensorOpsTest.vec2( 0.3132617f, 1.3132617f ), 0.000001f ) )
        TensorOpsTest.check( "leakyRelu(0.1)", TensorOpsTest.sameVec( act.leakyRelu( 0.1f ), TensorOpsTest.vec2( -0.1f, 1.0f ) ) )
        TensorOpsTest.check( "elu(1)", TensorOpsTest.nearVec( act.elu( 1.0f ), TensorOpsTest.vec2( -0.6321206f, 1.0f ), 0.000001f ) )
        Tensor act3 = TensorOpsTest.vec3( -1.0f, 0.0f, 1.0f )
        TensorOpsTest.check( "mish", TensorOpsTest.nearVec( act3.mish(), TensorOpsTest.vec3( -0.3034014f, 0.0f, 0.8650984f ), 0.00001f ) )

        # ── 4. 归约 / 代数扩展 ────────────────────────────
        Tensor rm = TensorOpsTest.vec4( 1.0f, 5.0f, 3.0f, 5.0f )
        TensorOpsTest.check( "argmax", rm.argmax() == 1 )
        TensorOpsTest.check( "argmin", rm.argmin() == 0 )

        Tensor cp = TensorOpsTest.vec4( 1.0f, 2.0f, 3.0f, 4.0f )
        TensorOpsTest.check( "cumprod", TensorOpsTest.sameVec( cp.cumprod(), TensorOpsTest.vec4( 1.0f, 2.0f, 6.0f, 24.0f ) ) )

        Tensor m22 = Tensor( 2, 2 )
        m22.setAt( 0, 0, 1.0f )
        m22.setAt( 0, 1, 2.0f )
        m22.setAt( 1, 0, 3.0f )
        m22.setAt( 1, 1, 4.0f )
        Tensor c1 = m22.cumprodAlong( 1 )
        TensorOpsTest.check( "cumprodAlong axis1", c1.at( 0, 0 ) == 1.0f && c1.at( 0, 1 ) == 2.0f && c1.at( 1, 0 ) == 3.0f && c1.at( 1, 1 ) == 12.0f )
        Tensor c0 = m22.cumprodAlong( 0 )
        TensorOpsTest.check( "cumprodAlong axis0", c0.at( 0, 0 ) == 1.0f && c0.at( 0, 1 ) == 2.0f && c0.at( 1, 0 ) == 3.0f && c0.at( 1, 1 ) == 8.0f )

        TensorOpsTest.check( "countNonZero", TensorOpsTest.vec4( 0.0f, 1.0f, 0.0f, 2.0f ).countNonZero() == 2 )

        Tensor dv = TensorOpsTest.vec3( 1.0f, 2.0f, 3.0f )
        Tensor dw = TensorOpsTest.vec3( 4.0f, 5.0f, 6.0f )
        TensorOpsTest.check( "dot", Mathf.abs( dv.dot( dw ) - 32.0f ) < 0.0001f )

        Tensor ot = TensorOpsTest.vec2( 1.0f, 2.0f ).outer( TensorOpsTest.vec2( 3.0f, 4.0f ) )
        TensorOpsTest.check( "outer", ot.rows() == 2 && ot.cols() == 2 && ot.at( 0, 0 ) == 3.0f && ot.at( 0, 1 ) == 4.0f && ot.at( 1, 0 ) == 6.0f && ot.at( 1, 1 ) == 8.0f )

        # ── 5. 形状操作补全 ───────────────────────────────
        Tensor v3 = TensorOpsTest.vec3( 1.0f, 2.0f, 3.0f )
        Tensor uq = v3.unsqueeze( 0 )
        bool unsqOk = uq.rank() == 2 && uq._shape.dims[0] == 1 && uq._shape.dims[1] == 3 && uq._data.length == 3
        Tensor sq2 = uq.squeeze( 0 )
        bool sqzOk = sq2.rank() == 1 && sq2._shape.dims[0] == 3 && TensorOpsTest.sameVec( sq2, v3 )
        TensorOpsTest.check( "unsqueeze/squeeze", unsqOk && sqzOk )

        Tensor f0 = m22.flip( 0 )
        Tensor f1 = m22.flip( 1 )
        TensorOpsTest.check( "flip(0)", f0.at( 0, 0 ) == 3.0f && f0.at( 0, 1 ) == 4.0f && f0.at( 1, 0 ) == 1.0f && f0.at( 1, 1 ) == 2.0f )
        TensorOpsTest.check( "flip(1)", f1.at( 0, 0 ) == 2.0f && f1.at( 0, 1 ) == 1.0f && f1.at( 1, 0 ) == 4.0f && f1.at( 1, 1 ) == 3.0f )

        Array<Tensor> cts = Array<Tensor>( 2 )
        cts[0] = TensorOpsTest.vec2( 1.0f, 2.0f )
        cts[1] = TensorOpsTest.vec2( 3.0f, 4.0f )
        Tensor cat1 = Tensor.cat( cts, 0 )
        TensorOpsTest.check( "cat 1D", TensorOpsTest.sameVec( cat1, TensorOpsTest.vec4( 1.0f, 2.0f, 3.0f, 4.0f ) ) )

        Tensor r12 = Tensor( 1, 2 )
        r12.setAt( 0, 0, 5.0f )
        r12.setAt( 0, 1, 6.0f )
        Array<Tensor> ct0 = Array<Tensor>( 2 )
        ct0[0] = m22
        ct0[1] = r12
        Tensor catA0 = Tensor.cat( ct0, 0 )
        TensorOpsTest.check( "cat axis0", catA0.rows() == 3 && catA0.cols() == 2 && catA0.at( 2, 0 ) == 5.0f && catA0.at( 2, 1 ) == 6.0f && catA0.at( 0, 0 ) == 1.0f )

        Tensor c21 = Tensor( 2, 1 )
        c21.setAt( 0, 0, 7.0f )
        c21.setAt( 1, 0, 8.0f )
        Array<Tensor> ct1 = Array<Tensor>( 2 )
        ct1[0] = c21
        ct1[1] = m22
        Tensor catA1 = Tensor.cat( ct1, 1 )
        TensorOpsTest.check( "cat axis1", catA1.rows() == 2 && catA1.cols() == 3 && catA1.at( 0, 0 ) == 7.0f && catA1.at( 1, 0 ) == 8.0f && catA1.at( 0, 1 ) == 1.0f && catA1.at( 1, 2 ) == 4.0f )

        # ── 6. GPU 对照（有卡时）──────────────────────────
        Backends.setCudaEnabled( true )
        if Backends.available( EDeviceKind.GPU )
        {
            global.println( "  --- gpu section ---" )
            Device dev = Device.gpu( 0 )

            # 位级组：与 CPU 结果逐位一致
            Tensor gq = xq.to( dev )
            TensorOpsTest.gpuSame( "gpu sqrt bitwise", xq.sqrt(), gq.sqrt() )
            Tensor gm = xm.to( dev )
            TensorOpsTest.gpuSame( "gpu abs bitwise", xm.abs(), gm.abs() )
            TensorOpsTest.gpuSame( "gpu floor bitwise", xm.floor(), gm.floor() )
            TensorOpsTest.gpuSame( "gpu ceil bitwise", xm.ceil(), gm.ceil() )
            TensorOpsTest.gpuSame( "gpu round bitwise", xm.round(), gm.round() )
            TensorOpsTest.gpuSame( "gpu sign bitwise", xm.sign(), gm.sign() )
            TensorOpsTest.gpuSame( "gpu square bitwise", xm.square(), gm.square() )
            Tensor gr = xr.to( dev )
            TensorOpsTest.gpuSame( "gpu reciprocal bitwise", xr.reciprocal(), gr.reciprocal() )

            Tensor ga = xa.to( dev )
            Tensor gb = xr.to( dev )
            TensorOpsTest.gpuSame( "gpu maximum bitwise", xa.maximum( xr ), ga.maximum( gb ) )
            TensorOpsTest.gpuSame( "gpu minimum bitwise", xa.minimum( xr ), ga.minimum( gb ) )

            # 近似组（rsqrt/lg2/ex2 approx；silu/gelu tanh 近似）
            Tensor grs = TensorOpsTest.vec4( 2.0f, 3.0f, 5.0f, 7.0f )
            Tensor grsd = grs.to( dev )
            TensorOpsTest.gpuNear( "gpu rsqrt near", grs.rsqrt(), grsd.rsqrt(), 0.001f )
            Tensor gl = xl.to( dev )
            TensorOpsTest.gpuNear( "gpu log2 near", xl.log2(), gl.log2(), 0.001f )
            Tensor ge = xe.to( dev )
            TensorOpsTest.gpuNear( "gpu exp2 near", xe.exp2(), ge.exp2(), 0.001f )
            Tensor gact = act.to( dev )
            TensorOpsTest.gpuNear( "gpu silu near", act.silu(), gact.silu(), 0.0001f )
            TensorOpsTest.gpuNear( "gpu gelu near", act.gelu(), gact.gelu(), 0.001f )
        }
        else
        {
            global.println( "  gpu not available, gpu section skipped" )
        }

        global.println( "===== TensorOpsTest end pass=" + TensorOpsTest._pass.toString() + " fail=" + TensorOpsTest._fail.toString() + " =====" )
        if TensorOpsTest._fail > 0
        {
            global.println( "[TensorOpsTest] RESULT : FAIL" )
        }
        else
        {
            global.println( "[TensorOpsTest] RESULT : PASS" )
        }
    }
}
