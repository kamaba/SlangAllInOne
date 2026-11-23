import Std;
import Math;

# ============================================================
# ComplexTest - 复数模块测试（Complex64 / Complex32 / MathComplex）
# 断言选复数恒等式：对 FFI 直调（mathc_*）与 SL 兜底两条路径均成立。
# 浮点比较用近似容差，避开末位舍入差异。
# ============================================================
class ComplexTest
{
    static Int32 pass = 0
    static Int32 fail = 0

    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "  [PASS] " + name )
            ComplexTest.pass = ComplexTest.pass + 1
        }
        else
        {
            Console.println( "  [FAIL] " + name )
            ComplexTest.fail = ComplexTest.fail + 1
        }
    }

    static bool near( Float64 a, Float64 b )
    {
        Float64 d = a - b
        if d < 0.0d
        {
            d = 0.0d - d
        }
        ret d < 0.000001d
    }

    static bool near32( Float32 a, Float32 b )
    {
        ret ComplexTest.near( a.toFloat64(), b.toFloat64() )
    }

    static bool nearZ( Complex64 z, Float64 r, Float64 i )
    {
        ret ComplexTest.near( z.real, r ) && ComplexTest.near( z.imag, i )
    }

    static testConstruct64()
    {
        Console.println( "===== ComplexTest.testConstruct64 =====" )
        Complex64 z = Complex64( 3.0d, 4.0d )
        ComplexTest.check( "c64 real", ComplexTest.near( z.real, 3.0d ) )
        ComplexTest.check( "c64 imag", ComplexTest.near( z.imag, 4.0d ) )
        ComplexTest.check( "c64 idx0", ComplexTest.near( z[0], 3.0d ) )
        ComplexTest.check( "c64 idx1", ComplexTest.near( z[1], 4.0d ) )
        ComplexTest.check( "c64 zero", ComplexTest.nearZ( Complex64.zero(), 0.0d, 0.0d ) )
        ComplexTest.check( "c64 one", ComplexTest.nearZ( Complex64.one(), 1.0d, 0.0d ) )
        ComplexTest.check( "c64 i", ComplexTest.nearZ( Complex64.i(), 0.0d, 1.0d ) )
    }

    static testArithmetic64()
    {
        Console.println( "===== ComplexTest.testArithmetic64 =====" )
        Complex64 a = Complex64( 3.0d, 4.0d )
        Complex64 b = Complex64( 1.0d, 2.0d )
        Complex64 add = a + b
        ComplexTest.check( "c64 add", ComplexTest.nearZ( add, 4.0d, 6.0d ) )
        Complex64 sub = a - b
        ComplexTest.check( "c64 sub", ComplexTest.nearZ( sub, 2.0d, 2.0d ) )
        Complex64 mul = a * b
        ComplexTest.check( "c64 mul", ComplexTest.nearZ( mul, -5.0d, 10.0d ) )
        Complex64 div = a / b
        ComplexTest.check( "c64 div", ComplexTest.nearZ( div, 2.2d, -0.4d ) )
        Complex64 scaled = a * 2.0d
        ComplexTest.check( "c64 scalar mul", ComplexTest.nearZ( scaled, 6.0d, 8.0d ) )
        Complex64 halved = a / 2.0d
        ComplexTest.check( "c64 scalar div", ComplexTest.nearZ( halved, 1.5d, 2.0d ) )
        Complex64 same = Complex64( 1.0d, 2.0d )
        Complex64 other = Complex64( 2.0d, 1.0d )
        bool eqr = same == b
        bool ner = other != b
        ComplexTest.check( "c64 eq", eqr )
        ComplexTest.check( "c64 ne", ner )
    }

    static testFunctions64()
    {
        Console.println( "===== ComplexTest.testFunctions64 =====" )
        Complex64 z = Complex64( 3.0d, 4.0d )
        ComplexTest.check( "c64 abs", ComplexTest.near( z.abs(), 5.0d ) )
        ComplexTest.check( "c64 conj", ComplexTest.nearZ( z.conjugate(), 3.0d, -4.0d ) )
        ComplexTest.check( "c64 neg", ComplexTest.nearZ( z.negate(), -3.0d, -4.0d ) )
        Complex64 unit = Complex64( 0.0d, 1.0d )
        ComplexTest.check( "c64 arg i", ComplexTest.near( unit.arg(), Mathd.Pi / 2.0d ) )
        Complex64 euler = Complex64.expi( Mathd.Pi / 2.0d )
        ComplexTest.check( "c64 expi re", ComplexTest.near( euler.real, 0.0d ) )
        ComplexTest.check( "c64 expi im", ComplexTest.near( euler.imag, 1.0d ) )
        # 欧拉公式 exp(i*theta) = cos(theta) + i*sin(theta)
        # theta = pi/2 -> exp(i*pi/2) = i
        Complex64 iTheta = Complex64( 0.0d, Mathd.Pi / 2.0d )
        Complex64 ee = iTheta.exp()
        ComplexTest.check( "c64 exp(i*pi/2) re", ComplexTest.near( ee.real, 0.0d ) )
        ComplexTest.check( "c64 exp(i*pi/2) im", ComplexTest.near( ee.imag, 1.0d ) )
        Complex64 sq = Complex64( 0.0d, 4.0d ).sqrt()
        ComplexTest.check( "c64 sqrt re", ComplexTest.near( sq.real, 1.4142135623730951d ) )
        ComplexTest.check( "c64 sqrt im", ComplexTest.near( sq.imag, 1.4142135623730951d ) )
        Complex64 lg = Complex64.one().log()
        ComplexTest.check( "c64 log(1)", ComplexTest.nearZ( lg, 0.0d, 0.0d ) )
        Complex64 pol = Complex64.fromPolar( 2.0d, 0.0d )
        ComplexTest.check( "c64 fromPolar", ComplexTest.nearZ( pol, 2.0d, 0.0d ) )
    }

    static testFacade()
    {
        Console.println( "===== ComplexTest.testFacade =====" )
        Complex64 a = Complex64( 3.0d, 4.0d )
        Complex64 b = Complex64( 1.0d, 2.0d )
        ComplexTest.check( "facade abs", ComplexTest.near( MathComplex.abs( a ), 5.0d ) )
        ComplexTest.check( "facade norm", ComplexTest.near( MathComplex.norm( a ), 25.0d ) )
        ComplexTest.check( "facade mul", ComplexTest.nearZ( MathComplex.mul( a, b ), -5.0d, 10.0d ) )
        ComplexTest.check( "facade add", ComplexTest.nearZ( MathComplex.add( a, b ), 4.0d, 6.0d ) )
        ComplexTest.check( "facade conj", ComplexTest.nearZ( MathComplex.conjugate( a ), 3.0d, -4.0d ) )
        ComplexTest.check( "facade powInt0", ComplexTest.nearZ( MathComplex.powInt( a, 0 ), 1.0d, 0.0d ) )
        Complex64 i2 = MathComplex.expi( Mathd.Pi )
        ComplexTest.check( "facade expi(pi) im", ComplexTest.near( i2.imag, 0.0d ) )
        Complex64 s = MathComplex.sin( Complex64( 0.0d, 0.0d ) )
        ComplexTest.check( "facade sin(0)", ComplexTest.nearZ( s, 0.0d, 0.0d ) )
    }

    static testComplex32()
    {
        Console.println( "===== ComplexTest.testComplex32 =====" )
        Complex32 a = Complex32( 3.0f, 4.0f )
        Complex32 b = Complex32( 1.0f, 2.0f )
        Complex32 add = a + b
        ComplexTest.check( "c32 add", ComplexTest.near32( add.real, 4.0f ) && ComplexTest.near32( add.imag, 6.0f ) )
        Complex32 mul = a * b
        ComplexTest.check( "c32 mul", ComplexTest.near32( mul.real, -5.0f ) && ComplexTest.near32( mul.imag, 10.0f ) )
        ComplexTest.check( "c32 abs", ComplexTest.near32( a.abs(), 5.0f ) )
        ComplexTest.check( "c32 conj", ComplexTest.near32( a.conjugate().imag, -4.0f ) )
        Complex32 euler = Complex32.expi( Mathf.Pi / 2.0f )
        ComplexTest.check( "c32 expi", ComplexTest.near32( euler.imag, 1.0f ) )
        ComplexTest.check( "c32 toComplex64", ComplexTest.near( a.toComplex64().abs(), 5.0d ) )
    }

    static fun()
    {
        Console.println( "===== ComplexTest START =====" )
        ComplexTest.pass = 0
        ComplexTest.fail = 0
        ComplexTest.testConstruct64()
        ComplexTest.testArithmetic64()
        ComplexTest.testFunctions64()
        ComplexTest.testFacade()
        ComplexTest.testComplex32()
        Console.println( "===== ComplexTest: PASS=" + ComplexTest.pass.toString() + " FAIL=" + ComplexTest.fail.toString() + " =====" )
    }
}
