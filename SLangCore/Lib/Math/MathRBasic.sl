# MathRBasic —— R base 风格基础数学/聚合函数（Float64，纯 SL）
# 对应菜鸟教程 R 实例「基础数学函数」一栏：sum/prod/min/max/range/
# cumsum/diff/abs/round/sqrt/log/exp/sin/factorial/choose/ceiling/floor。
# 标量三角/指数/取整已在 Mathd.sl，这里只补 R 语义的聚合与组合函数。
public class MathRBasic
{
    public static Float64 sum( List<Float64> v )
    {
        if v == null
        {
            ret 0.0d
        }
        Int32 n = v.length
        Float64 acc = 0.0d
        Int32 i = 0
        while i < n
        {
            acc = acc + v._getItem_( i )
            i = i + 1
        }
        ret acc
    }

    public static Float64 prod( List<Float64> v )
    {
        if v == null
        {
            ret 1.0d
        }
        Int32 n = v.length
        Float64 acc = 1.0d
        Int32 i = 0
        while i < n
        {
            acc = acc * v._getItem_( i )
            i = i + 1
        }
        ret acc
    }

    public static Float64 minOf( List<Float64> v )
    {
        if v == null || v.length == 0
        {
            ret 0.0d
        }
        Int32 n = v.length
        Float64 m = v._getItem_( 0 )
        Int32 i = 1
        while i < n
        {
            Float64 x = v._getItem_( i )
            if x < m
            {
                m = x
            }
            i = i + 1
        }
        ret m
    }

    public static Float64 maxOf( List<Float64> v )
    {
        if v == null || v.length == 0
        {
            ret 0.0d
        }
        Int32 n = v.length
        Float64 m = v._getItem_( 0 )
        Int32 i = 1
        while i < n
        {
            Float64 x = v._getItem_( i )
            if x > m
            {
                m = x
            }
            i = i + 1
        }
        ret m
    }

    public static Float64 rangeOf( List<Float64> v )
    {
        ret MathRBasic.maxOf( v ) - MathRBasic.minOf( v )
    }

    public static List<Float64> cumsum( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Float64 acc = 0.0d
        Int32 i = 0
        while i < n
        {
            acc = acc + v._getItem_( i )
            r.add( acc )
            i = i + 1
        }
        ret r
    }

    public static List<Float64> diff( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null || v.length < 2
        {
            ret r
        }
        Int32 n = v.length
        Int32 i = 1
        while i < n
        {
            Int32 prev = i - 1
            r.add( v._getItem_( i ) - v._getItem_( prev ) )
            i = i + 1
        }
        ret r
    }

    public static Float64 factorial( Int32 n )
    {
        if n < 0
        {
            ret 0.0d
        }
        Float64 r = 1.0d
        Int32 i = 2
        while i <= n
        {
            r = r * i.toFloat64()
            i = i + 1
        }
        ret r
    }

    public static Float64 choose( Int32 n, Int32 k )
    {
        if k < 0 || k > n || n < 0
        {
            ret 0.0d
        }
        Int32 kk = k
        if n - kk < kk
        {
            kk = n - kk
        }
        Float64 r = 1.0d
        Int32 i = 1
        while i <= kk
        {
            r = r * ( n - kk + i ).toFloat64() / i.toFloat64()
            i = i + 1
        }
        ret r
    }

    public static Float64 abs( Float64 x )
    {
        ret Mathd.abs( x )
    }

    public static Float64 roundDigits( Float64 x, Int32 digits )
    {
        Float64 p = Mathd.pow( 10.0d, digits.toFloat64() )
        ret Mathd.round( x * p ) / p
    }

    public static Float64 ceiling( Float64 x )
    {
        ret Mathd.ceil( x )
    }

    public static Float64 floor( Float64 x )
    {
        ret Mathd.floor( x )
    }
}
