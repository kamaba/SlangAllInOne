# MathComplex —— 复数静态工具门面（Float64 精度，Complex32 可转精度调用）。
# 与 Mathd/Mathf 的关系：Mathd 管实数标量，MathComplex 管复数；
# 底层 math_lib.dll 的 mathc_d_* 算子经 FFI 绑定，绑定失败走 Complex64 兜底。
public class MathComplex
{
    # ── 由分量构造 ───────────────────────────────────────
    public static Complex64 fromCartesian( Float64 real, Float64 imag )
    {
        ret Complex64( real, imag )
    }

    public static Complex64 fromPolar( Float64 r, Float64 theta )
    {
        ret Complex64.fromPolar( r, theta )
    }

    # 欧拉公式 e^(i*theta)
    public static Complex64 expi( Float64 theta )
    {
        ret Complex64.expi( theta )
    }

    # ── 分量访问 ─────────────────────────────────────────
    public static Float64 real( Complex64 z )
    {
        ret z.real
    }

    public static Float64 imag( Complex64 z )
    {
        ret z.imag
    }

    # ── 模 / 幅角 / 共轭 ──────────────────────────────────
    @DllStaticImport( "math_lib", "mathc_d_abs" )
    public static Float64 abs( Complex64 z )
    {
        ret z.abs()
    }

    @DllStaticImport( "math_lib", "mathc_d_arg" )
    public static Float64 arg( Complex64 z )
    {
        ret z.arg()
    }

    public static Float64 norm( Complex64 z )
    {
        ret z.real * z.real + z.imag * z.imag
    }

    public static Complex64 conjugate( Complex64 z )
    {
        ret z.conjugate()
    }

    # ── 四则（委托运算符）─────────────────────────────────
    public static Complex64 add( Complex64 a, Complex64 b )
    {
        ret a + b
    }

    public static Complex64 sub( Complex64 a, Complex64 b )
    {
        ret a - b
    }

    public static Complex64 mul( Complex64 a, Complex64 b )
    {
        ret a * b
    }

    public static Complex64 div( Complex64 a, Complex64 b )
    {
        ret a / b
    }

    # ── 超越函数（FFI + 兜底）─────────────────────────────
    public static Complex64 exp( Complex64 z )
    {
        ret z.exp()
    }

    public static Complex64 sqrt( Complex64 z )
    {
        ret z.sqrt()
    }

    public static Complex64 log( Complex64 z )
    {
        ret z.log()
    }

    @DllStaticImport( "math_lib", "mathc_d_sin_re" )
    public static Float64 sinReal( Complex64 z )
    {
        ret Mathd.sin( z.real ) * Mathd.cosh( z.imag )
    }

    @DllStaticImport( "math_lib", "mathc_d_sin_im" )
    public static Float64 sinImag( Complex64 z )
    {
        ret Mathd.cos( z.real ) * Mathd.sinh( z.imag )
    }

    public static Complex64 sin( Complex64 z )
    {
        ret Complex64( MathComplex.sinReal( z ), MathComplex.sinImag( z ) )
    }

    @DllStaticImport( "math_lib", "mathc_d_cos_re" )
    public static Float64 cosReal( Complex64 z )
    {
        ret Mathd.cos( z.real ) * Mathd.cosh( z.imag )
    }

    @DllStaticImport( "math_lib", "mathc_d_cos_im" )
    public static Float64 cosImag( Complex64 z )
    {
        ret 0.0d - Mathd.sin( z.real ) * Mathd.sinh( z.imag )
    }

    public static Complex64 cos( Complex64 z )
    {
        ret Complex64( MathComplex.cosReal( z ), MathComplex.cosImag( z ) )
    }

    # 复数幂 z^n（n 为整数，反复乘）
    public static Complex64 powInt( Complex64 z, Int32 n )
    {
        if n == 0
        {
            ret Complex64.one()
        }
        Complex64 result = Complex64.one()
        Int32 k = 0
        while k < n
        {
            result = result * z
            k = k + 1
        }
        ret result
    }
}
