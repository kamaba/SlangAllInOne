# Complex64 —— Float64（双精度）复数。
# 底层：math_lib.dll 的 mathc_d_* 复数算子经 FFI @DllStaticImport 静态绑定
# （同 Mathd.sl 模式）；绑定失败自动回退函数体（纯 SL 兜底）。
# 复数按 (real, imag) 两个标量字段表示，运算符返回类型均为 Complex64 自身
# （对齐 Float32_2 / Quaternion 的运算符重载约定）。
@Nickname("Complex")
@Nickname("Complex128")
public class Complex64
{
    public Float64 real = 0.0d
    public Float64 imag = 0.0d

    # ── 构造 ─────────────────────────────────────────────
    override void _init_()
    {
        this.real = 0.0d
        this.imag = 0.0d
    }

    public void _init_( Float64 _real, Float64 _imag )
    {
        this.real = _real
        this.imag = _imag
    }

    public void _init_( Float64 _real )
    {
        this.real = _real
        this.imag = 0.0d
    }

    # ── 索引访问：0=real, 1=imag ─────────────────────────
    override Float64 _getItem_( int index )
    {
        if index == 0
        {
            ret this.real
        }
        ret this.imag
    }

    override void _setItem_( int index, Float64 value )
    {
        if index == 0
        {
            this.real = value
        }
        else
        {
            this.imag = value
        }
    }

    # ── 运算符重载（返回本类类型）─────────────────────────
    override Complex64 _add_( Complex64 v )
    {
        ret Complex64( this.real + v.real, this.imag + v.imag )
    }

    override Complex64 _sub_( Complex64 v )
    {
        ret Complex64( this.real - v.real, this.imag - v.imag )
    }

    override Complex64 _mul_( Object obj1 )
    {
        if obj1 is Complex64 v
        {
            Float64 re = this.real * v.real - this.imag * v.imag
            Float64 im = this.real * v.imag + this.imag * v.real
            ret Complex64( re, im )
        }
        if obj1 is Float64 s
        {
            ret Complex64( this.real * s, this.imag * s )
        }
        if obj1 is Int32 si
        {
            Float64 s = si.toFloat64()
            ret Complex64( this.real * s, this.imag * s )
        }
        ret this
    }

    override Complex64 _truediv_( Object obj1 ) throws
    {
        if obj1 is Complex64 v
        {
            Float64 d = v.real * v.real + v.imag * v.imag
            Float64 re = ( this.real * v.real + this.imag * v.imag ) / d
            Float64 im = ( this.imag * v.real - this.real * v.imag ) / d
            ret Complex64( re, im )
        }
        if obj1 is Float64 s
        {
            ret Complex64( this.real / s, this.imag / s )
        }
        if obj1 is Int32 si
        {
            Float64 s = si.toFloat64()
            ret Complex64( this.real / s, this.imag / s )
        }
        ret this
    }

    override bool _eq_( Complex64 v )
    {
        ret this.real == v.real && this.imag == v.imag
    }

    override bool _ne_( Complex64 v )
    {
        ret !this._eq_( v )
    }

    # ── 实例方法 ─────────────────────────────────────────
    @DllStaticImport( "math_lib", "mathc_d_abs" )
    public Float64 abs()
    {
        ret Mathd.sqrt( this.real * this.real + this.imag * this.imag )
    }

    @DllStaticImport( "math_lib", "mathc_d_arg" )
    public Float64 arg()
    {
        ret Mathd.atan2( this.imag, this.real )
    }

    public Complex64 conjugate()
    {
        ret Complex64( this.real, 0.0d - this.imag )
    }

    public Complex64 negate()
    {
        ret Complex64( 0.0d - this.real, 0.0d - this.imag )
    }

    public Complex64 scale( Float64 s )
    {
        ret Complex64( this.real * s, this.imag * s )
    }

    public Complex64 clone()
    {
        ret Complex64( this.real, this.imag )
    }

    @DllStaticImport( "math_lib", "mathc_d_exp_re" )
    public Float64 expReal()
    {
        ret Mathd.exp( this.real ) * Mathd.cos( this.imag )
    }

    @DllStaticImport( "math_lib", "mathc_d_exp_im" )
    public Float64 expImag()
    {
        ret Mathd.exp( this.real ) * Mathd.sin( this.imag )
    }

    public Complex64 exp()
    {
        ret Complex64( this.expReal(), this.expImag() )
    }

    @DllStaticImport( "math_lib", "mathc_d_sqrt_re" )
    public Float64 sqrtRealF64()
    {
        Float64 r = this.abs()
        ret Mathd.sqrt( ( r + this.real ) / 2.0d )
    }

    @DllStaticImport( "math_lib", "mathc_d_sqrt_im" )
    public Float64 sqrtImagF64()
    {
        Float64 r = this.abs()
        Float64 re = Mathd.sqrt( ( r + this.real ) / 2.0d )
        if re == 0.0d
        {
            ret 0.0d
        }
        ret this.imag / ( 2.0d * re )
    }

    public Complex64 sqrt()
    {
        ret Complex64( this.sqrtRealF64(), this.sqrtImagF64() )
    }

    @DllStaticImport( "math_lib", "mathc_d_log_re" )
    public Float64 logReal()
    {
        ret Mathd.log( this.abs() )
    }

    @DllStaticImport( "math_lib", "mathc_d_log_im" )
    public Float64 logImag()
    {
        ret this.arg()
    }

    public Complex64 log()
    {
        ret Complex64( this.logReal(), this.logImag() )
    }

    # ── 静态常量 ─────────────────────────────────────────
    public static get Complex64 zero()
    {
        ret Complex64( 0.0d, 0.0d )
    }

    public static get Complex64 one()
    {
        ret Complex64( 1.0d, 0.0d )
    }

    public static get Complex64 i()
    {
        ret Complex64( 0.0d, 1.0d )
    }

    # ── 静态工具 ─────────────────────────────────────────
    @DllStaticImport( "math_lib", "mathc_d_from_polar_re" )
    public static Float64 fromPolarReal( Float64 r, Float64 theta )
    {
        ret r * Mathd.cos( theta )
    }

    @DllStaticImport( "math_lib", "mathc_d_from_polar_im" )
    public static Float64 fromPolarImag( Float64 r, Float64 theta )
    {
        ret r * Mathd.sin( theta )
    }

    public static Complex64 fromPolar( Float64 r, Float64 theta )
    {
        ret Complex64( Complex64.fromPolarReal( r, theta ), Complex64.fromPolarImag( r, theta ) )
    }

    public static Complex64 expi( Float64 theta )
    {
        ret Complex64( Mathd.cos( theta ), Mathd.sin( theta ) )
    }

    override string toString()
    {
        ret String.toFormat( "({0} + {1}i)", this.real, this.imag )
    }
}
