# Complex32 —— Float32（单精度）复数。
# 底层：math_lib.dll 的 mathc_f_* 复数算子经 FFI @DllStaticImport 静态绑定；
# 绑定失败自动回退函数体（委托 Complex64 转精度，同 Mathf.sl 模式）。
# 复数按 (real, imag) 两个标量字段表示，运算符返回类型均为 Complex32 自身。
@Nickname("C32")
public class Complex32
{
    public Float32 real = 0.0f
    public Float32 imag = 0.0f

    # ── 构造 ─────────────────────────────────────────────
    override void _init_()
    {
        this.real = 0.0f
        this.imag = 0.0f
    }

    public void _init_( Float32 _real, Float32 _imag )
    {
        this.real = _real
        this.imag = _imag
    }

    public void _init_( Float32 _real )
    {
        this.real = _real
        this.imag = 0.0f
    }

    # ── 索引访问：0=real, 1=imag ─────────────────────────
    override Float32 _getItem_( int index )
    {
        if index == 0
        {
            ret this.real
        }
        ret this.imag
    }

    override void _setItem_( int index, Float32 value )
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
    override Complex32 _add_( Complex32 v )
    {
        ret Complex32( this.real + v.real, this.imag + v.imag )
    }

    override Complex32 _sub_( Complex32 v )
    {
        ret Complex32( this.real - v.real, this.imag - v.imag )
    }

    override Complex32 _mul_( Object obj1 )
    {
        if obj1 is Complex32 v
        {
            Float32 re = this.real * v.real - this.imag * v.imag
            Float32 im = this.real * v.imag + this.imag * v.real
            ret Complex32( re, im )
        }
        if obj1 is Float32 s
        {
            ret Complex32( this.real * s, this.imag * s )
        }
        if obj1 is Int32 si
        {
            Float32 s = si.toFloat32()
            ret Complex32( this.real * s, this.imag * s )
        }
        ret this
    }

    override Complex32 _truediv_( Object obj1 ) throws
    {
        if obj1 is Complex32 v
        {
            Float32 d = v.real * v.real + v.imag * v.imag
            Float32 re = ( this.real * v.real + this.imag * v.imag ) / d
            Float32 im = ( this.imag * v.real - this.real * v.imag ) / d
            ret Complex32( re, im )
        }
        if obj1 is Float32 s
        {
            ret Complex32( this.real / s, this.imag / s )
        }
        if obj1 is Int32 si
        {
            Float32 s = si.toFloat32()
            ret Complex32( this.real / s, this.imag / s )
        }
        ret this
    }

    override bool _eq_( Complex32 v )
    {
        ret this.real == v.real && this.imag == v.imag
    }

    override bool _ne_( Complex32 v )
    {
        ret !this._eq_( v )
    }

    # ── 实例方法（FFI + 转精度 fallback）──────────────────
    @DllStaticImport( "math_lib", "mathc_f_abs" )
    public Float32 abs()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).abs().toFloat32()
    }

    @DllStaticImport( "math_lib", "mathc_f_arg" )
    public Float32 arg()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).arg().toFloat32()
    }

    public Complex32 conjugate()
    {
        ret Complex32( this.real, 0.0f - this.imag )
    }

    public Complex32 negate()
    {
        ret Complex32( 0.0f - this.real, 0.0f - this.imag )
    }

    public Complex32 scale( Float32 s )
    {
        ret Complex32( this.real * s, this.imag * s )
    }

    public Complex32 clone()
    {
        ret Complex32( this.real, this.imag )
    }

    @DllStaticImport( "math_lib", "mathc_f_exp_re" )
    public Float32 expReal()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).expReal().toFloat32()
    }

    @DllStaticImport( "math_lib", "mathc_f_exp_im" )
    public Float32 expImag()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).expImag().toFloat32()
    }

    public Complex32 exp()
    {
        ret Complex32( this.expReal(), this.expImag() )
    }

    @DllStaticImport( "math_lib", "mathc_f_sqrt_re" )
    public Float32 sqrtReal()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).sqrtRealF64().toFloat32()
    }

    @DllStaticImport( "math_lib", "mathc_f_sqrt_im" )
    public Float32 sqrtImag()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).sqrtImagF64().toFloat32()
    }

    public Complex32 sqrt()
    {
        ret Complex32( this.sqrtReal(), this.sqrtImag() )
    }

    @DllStaticImport( "math_lib", "mathc_f_log_re" )
    public Float32 logReal()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).logReal().toFloat32()
    }

    @DllStaticImport( "math_lib", "mathc_f_log_im" )
    public Float32 logImag()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() ).logImag().toFloat32()
    }

    public Complex32 log()
    {
        ret Complex32( this.logReal(), this.logImag() )
    }

    # ── 静态常量 ─────────────────────────────────────────
    public static get Complex32 zero()
    {
        ret Complex32( 0.0f, 0.0f )
    }

    public static get Complex32 one()
    {
        ret Complex32( 1.0f, 0.0f )
    }

    public static get Complex32 i()
    {
        ret Complex32( 0.0f, 1.0f )
    }

    # ── 静态工具 ─────────────────────────────────────────
    @DllStaticImport( "math_lib", "mathc_f_from_polar_re" )
    public static Float32 fromPolarReal( Float32 r, Float32 theta )
    {
        ret r * Mathf.cos( theta )
    }

    @DllStaticImport( "math_lib", "mathc_f_from_polar_im" )
    public static Float32 fromPolarImag( Float32 r, Float32 theta )
    {
        ret r * Mathf.sin( theta )
    }

    public static Complex32 fromPolar( Float32 r, Float32 theta )
    {
        ret Complex32( Complex32.fromPolarReal( r, theta ), Complex32.fromPolarImag( r, theta ) )
    }

    public static Complex32 expi( Float32 theta )
    {
        ret Complex32( Mathf.cos( theta ), Mathf.sin( theta ) )
    }

    # ── 精度转换 ─────────────────────────────────────────
    public Complex64 toComplex64()
    {
        ret Complex64( this.real.toFloat64(), this.imag.toFloat64() )
    }

    override string toString()
    {
        ret String.toFormat( "({0} + {1}i)", this.real, this.imag )
    }
}
