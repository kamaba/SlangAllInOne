# MathDist —— R base 风格概率分布与随机数（Float64，纯 SL）
# 对应菜鸟教程 R 实例「概率分布」一栏：set.seed/runif/rnorm/dnorm/pnorm/
# qnorm/rbinom/rpois/rexp/sample。
# RNG 用 Park-Miller LCG（Float64 精确整除范围，跨模块零原生依赖）；
# 正态用 Box-Muller；pnorm 用 Abramowitz-Stegun 7.1.26  erf 近似，
# qnorm 用 80 次二分反解，精度约 1e-9。
public class MathDist
{
    static Float64 stateValue = 12345.0d

    public static void setSeed( Int32 seed )
    {
        Float64 s = seed.toFloat64()
        if s <= 0.0d
        {
            s = 1.0d
        }
        MathDist.stateValue = s
    }

    public static Float64 uniform01()
    {
        Float64 x = MathDist.stateValue * 16807.0d
        Float64 m = 2147483647.0d
        Float64 q = Mathd.floor( x / m )
        MathDist.stateValue = x - q * m
        ret MathDist.stateValue / m
    }

    public static Float64 runif( Float64 lo, Float64 hi )
    {
        ret lo + ( hi - lo ) * MathDist.uniform01()
    }

    public static Float64 rnorm( Float64 mu, Float64 sd )
    {
        Float64 u1 = MathDist.uniform01()
        if u1 <= 0.0d
        {
            u1 = 0.0000001d
        }
        Float64 u2 = MathDist.uniform01()
        Float64 r = Mathd.sqrt( 0.0d - 2.0d * Mathd.log( u1 ) )
        ret mu + sd * r * Mathd.cos( 2.0d * Mathd.Pi * u2 )
    }

    public static Float64 dnorm( Float64 x, Float64 mu, Float64 sd )
    {
        if sd <= 0.0d
        {
            ret 0.0d
        }
        Float64 z = ( x - mu ) / sd
        Float64 e = Mathd.exp( 0.0d - 0.5d * z * z )
        ret e / ( sd * Mathd.sqrt( 2.0d * Mathd.Pi ) )
    }

    static Float64 erf( Float64 x )
    {
        Float64 z = x
        Float64 sign = 1.0d
        if z < 0.0d
        {
            z = 0.0d - z
            sign = 0.0d - 1.0d
        }
        Float64 t = 1.0d / ( 1.0d + 0.3275911d * z )
        Float64 poly = ( ( ( 1.061405429d * t - 1.453152027d ) * t + 1.421413741d ) * t - 0.284496736d ) * t + 0.254829592d
        Float64 decay = Mathd.exp( 0.0d - z * z )
        Float64 y = 1.0d - poly * t * decay
        ret sign * y
    }

    public static Float64 pnorm( Float64 x, Float64 mu, Float64 sd )
    {
        if sd <= 0.0d
        {
            ret 0.0d
        }
        Float64 z = ( x - mu ) / ( sd * Mathd.sqrt( 2.0d ) )
        ret 0.5d * ( 1.0d + MathDist.erf( z ) )
    }

    public static Float64 qnorm( Float64 p, Float64 mu, Float64 sd )
    {
        if p <= 0.0d
        {
            ret 0.0d - 100.0d
        }
        if p >= 1.0d
        {
            ret 100.0d
        }
        Float64 lo = 0.0d - 12.0d
        Float64 hi = 12.0d
        Int32 i = 0
        while i < 80
        {
            Float64 mid = ( lo + hi ) / 2.0d
            if MathDist.pnorm( mid, 0.0d, 1.0d ) < p
            {
                lo = mid
            }
            else
            {
                hi = mid
            }
            i = i + 1
        }
        ret mu + sd * ( lo + hi ) / 2.0d
    }

    public static Float64 rbinom( Int32 n, Int32 size, Float64 p )
    {
        Float64 total = 0.0d
        Int32 i = 0
        while i < n
        {
            Int32 k = 0
            while k < size
            {
                if MathDist.uniform01() < p
                {
                    total = total + 1.0d
                }
                k = k + 1
            }
            i = i + 1
        }
        ret total
    }

    public static Float64 rpois( Float64 meanValue )
    {
        if meanValue <= 0.0d
        {
            ret 0.0d
        }
        Float64 limit = Mathd.exp( 0.0d - meanValue )
        Float64 p = 1.0d
        Float64 k = 0.0d
        while true
        {
            p = p * MathDist.uniform01()
            if p <= limit
            {
                ret k
            }
            k = k + 1.0d
        }
    }

    public static Float64 rexp( Float64 rate )
    {
        if rate <= 0.0d
        {
            ret 0.0d
        }
        Float64 u = MathDist.uniform01()
        if u <= 0.0d
        {
            u = 0.0000001d
        }
        ret 0.0d - Mathd.log( u ) / rate
    }

    public static List<Float64> sample( List<Float64> v, Int32 k )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Int32 count = k
        if count > n
        {
            count = n
        }
        List<Float64> pool = List<Float64>()
        Int32 i = 0
        while i < n
        {
            pool.add( v._getItem_( i ) )
            i = i + 1
        }
        i = 0
        while i < count
        {
            Int32 idx = ( MathDist.uniform01() * ( n - i ).toFloat64() ) as Int32
            Float64 picked = pool._getItem_( idx )
            Int32 last = n - i - 1
            Float64 swapped = pool._getItem_( last )
            r.add( picked )
            pool._setItem_( idx, swapped )
            i = i + 1
        }
        ret r
    }
}
