# MathStats —— R base 风格统计函数（Float64，纯 SL）
# 对应菜鸟教程 R 实例「统计函数」一栏：mean/median/sum/sd/var/quantile/
# summary/cor/cov/scale/t.test/chisq.test/aov/lm。
# 约定：var/sd 用样本分母 n-1（与 R 一致）；quantile 用 type-7 线性插值；
# 检验类函数返回检验统计量（t / chi-square / F / slope），不返回 p 值。
public class MathStats
{
    static List<Float64> sortedCopy( List<Float64> v )
    {
        List<Float64> s = List<Float64>()
        if v == null
        {
            ret s
        }
        Int32 n = v.length
        Int32 i = 0
        while i < n
        {
            s.add( v._getItem_( i ) )
            i = i + 1
        }
        i = 0
        while i < n
        {
            Int32 j = 0
            while j < n - i - 1
            {
                Int32 nj = j + 1
                Float64 a = s._getItem_( j )
                Float64 b = s._getItem_( nj )
                if a > b
                {
                    s._setItem_( j, b )
                    s._setItem_( j + 1, a )
                }
                j = j + 1
            }
            i = i + 1
        }
        ret s
    }

    public static Float64 sum( List<Float64> v )
    {
        ret MathRBasic.sum( v )
    }

    public static Float64 mean( List<Float64> v )
    {
        if v == null || v.length == 0
        {
            ret 0.0d
        }
        ret MathRBasic.sum( v ) / v.length.toFloat64()
    }

    public static Float64 median( List<Float64> v )
    {
        ret MathStats.quantile( v, 0.5d )
    }

    public static Float64 quantile( List<Float64> v, Float64 p )
    {
        if v == null || v.length == 0
        {
            ret 0.0d
        }
        Int32 n = v.length
        List<Float64> s = MathStats.sortedCopy( v )
        if n == 1
        {
            ret s._getItem_( 0 )
        }
        Float64 h = ( n - 1 ).toFloat64() * p
        if h <= 0.0d
        {
            ret s._getItem_( 0 )
        }
        Int32 lo = h as Int32
        Int32 last = n - 1
        if lo >= last
        {
            ret s._getItem_( last )
        }
        Int32 hi = lo + 1
        Float64 f = h - lo.toFloat64()
        ret s._getItem_( lo ) + f * ( s._getItem_( hi ) - s._getItem_( lo ) )
    }

    public static Float64 variance( List<Float64> v )
    {
        if v == null || v.length < 2
        {
            ret 0.0d
        }
        Int32 n = v.length
        Float64 m = MathStats.mean( v )
        Float64 acc = 0.0d
        Int32 i = 0
        while i < n
        {
            Float64 d = v._getItem_( i ) - m
            acc = acc + d * d
            i = i + 1
        }
        ret acc / ( n - 1 ).toFloat64()
    }

    public static Float64 sd( List<Float64> v )
    {
        ret Mathd.sqrt( MathStats.variance( v ) )
    }

    public static Float64 covariance( List<Float64> x, List<Float64> y )
    {
        if x == null || y == null
        {
            ret 0.0d
        }
        Int32 n = x.length
        if n < 2 || y.length < n
        {
            ret 0.0d
        }
        Float64 mx = MathStats.mean( x )
        Float64 my = MathStats.mean( y )
        Float64 acc = 0.0d
        Int32 i = 0
        while i < n
        {
            acc = acc + ( x._getItem_( i ) - mx ) * ( y._getItem_( i ) - my )
            i = i + 1
        }
        ret acc / ( n - 1 ).toFloat64()
    }

    public static Float64 correlation( List<Float64> x, List<Float64> y )
    {
        Float64 sx = MathStats.sd( x )
        Float64 sy = MathStats.sd( y )
        if sx == 0.0d || sy == 0.0d
        {
            ret 0.0d
        }
        ret MathStats.covariance( x, y ) / ( sx * sy )
    }

    public static List<Float64> scale( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Float64 m = MathStats.mean( v )
        Float64 s = MathStats.sd( v )
        Int32 i = 0
        while i < n
        {
            if s == 0.0d
            {
                r.add( 0.0d )
            }
            else
            {
                r.add( ( v._getItem_( i ) - m ) / s )
            }
            i = i + 1
        }
        ret r
    }

    public static string summary( List<Float64> v )
    {
        string s = "n=" + v.length.toString()
        s = s + " min=" + MathRBasic.minOf( v ).toString()
        s = s + " q1=" + MathStats.quantile( v, 0.25d ).toString()
        s = s + " median=" + MathStats.median( v ).toString()
        s = s + " q3=" + MathStats.quantile( v, 0.75d ).toString()
        s = s + " max=" + MathRBasic.maxOf( v ).toString()
        s = s + " mean=" + MathStats.mean( v ).toString()
        s = s + " sd=" + MathStats.sd( v ).toString()
        ret s
    }

    # t.test：单样本 t 统计量 (mean-mu)/(sd/sqrt(n))
    public static Float64 tTest( List<Float64> v, Float64 mu )
    {
        if v == null || v.length < 2
        {
            ret 0.0d
        }
        Float64 s = MathStats.sd( v )
        if s == 0.0d
        {
            ret 0.0d
        }
        ret ( MathStats.mean( v ) - mu ) / ( s / Mathd.sqrt( v.length.toFloat64() ) )
    }

    # chisq.test：Pearson 卡方统计量 sum((obs-exp)^2/exp)
    public static Float64 chisqTest( List<Float64> obs, List<Float64> exp )
    {
        if obs == null || exp == null
        {
            ret 0.0d
        }
        Int32 n = obs.length
        if exp.length < n
        {
            ret 0.0d
        }
        Float64 acc = 0.0d
        Int32 i = 0
        while i < n
        {
            Float64 e = exp._getItem_( i )
            if e != 0.0d
            {
                Float64 d = obs._getItem_( i ) - e
                acc = acc + d * d / e
            }
            i = i + 1
        }
        ret acc
    }

    # aov：两组单因子方差分析 F = MS_between / MS_within
    public static Float64 aov( List<Float64> a, List<Float64> b )
    {
        if a == null || b == null || a.length < 2 || b.length < 2
        {
            ret 0.0d
        }
        Int32 na = a.length
        Int32 nb = b.length
        Float64 ma = MathStats.mean( a )
        Float64 mb = MathStats.mean( b )
        Float64 totalN = ( na + nb ).toFloat64()
        Float64 grand = ( ma * na.toFloat64() + mb * nb.toFloat64() ) / totalN
        Float64 da = ma - grand
        Float64 db = mb - grand
        Float64 ssb = na.toFloat64() * da * da + nb.toFloat64() * db * db
        Float64 va = MathStats.variance( a )
        Float64 vb = MathStats.variance( b )
        Float64 ssw = ( na - 1 ).toFloat64() * va + ( nb - 1 ).toFloat64() * vb
        if ssw == 0.0d
        {
            ret 0.0d
        }
        ret ssb / ( ssw / ( totalN - 2.0d ) )
    }

    # lm：最小二乘斜率与截距（y = slope*x + intercept）
    public static Float64 lmSlope( List<Float64> x, List<Float64> y )
    {
        Float64 vx = MathStats.variance( x )
        if vx == 0.0d
        {
            ret 0.0d
        }
        ret MathStats.covariance( x, y ) / vx
    }

    public static Float64 lmIntercept( List<Float64> x, List<Float64> y )
    {
        ret MathStats.mean( y ) - MathStats.lmSlope( x, y ) * MathStats.mean( x )
    }
}
