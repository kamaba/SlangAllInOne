# =========================================================================
# Stats/Stats.sl —— 描述统计与分布（R base 同语义，纯 SL，零原生依赖）
#
# 用法见 doc/02-Usage.md §3；实现说明见 doc/01-Design.md §5.1。
# 语义对齐 R base：
#   - 标准差/方差 = 样本（n-1 分母）；空列表返回 0
#   - quantile = R type-7 线性插值（quantile(x, probs, type=7)）
#   - correlation = Pearson 积矩相关
#   - order = R order（排序索引）；hist = Sturges 分箱（bins<=0 时 k=⌈log2 n⌉+1）
# =========================================================================

import Core;
import Std;

namespace StatsPlot
{
    public class Stats
    {
        # ── 向量归一 ───────────────────────────────────────
        public static List<Float32> toFloats( List<Int32> v )
        {
            List<Float32> r = List<Float32>()
            Int32 n = v.length
            Int32 i = 0
            while i < n
            {
                r.add( SystemConvertFloat32( v._getItem_( i ) ) )
                i = i + 1
            }
            ret r
        }

        # ── 基础统计 ───────────────────────────────────────
        public static Float32 sum( List<Float32> v )
        {
            Int32 n = v.length
            Float32 acc = 0.0f
            Int32 i = 0
            while i < n
            {
                acc = acc + v._getItem_( i )
                i = i + 1
            }
            ret acc
        }

        public static Float32 mean( List<Float32> v )
        {
            Int32 n = v.length
            if n == 0
            {
                ret 0.0f
            }
            ret Stats.sum( v ) / SystemConvertFloat32( n )
        }

        public static Float32 minValue( List<Float32> v )
        {
            Int32 n = v.length
            if n == 0
            {
                ret 0.0f
            }
            Float32 m = v._getItem_( 0 )
            Int32 i = 1
            while i < n
            {
                if v._getItem_( i ) < m
                {
                    m = v._getItem_( i )
                }
                i = i + 1
            }
            ret m
        }

        public static Float32 maxValue( List<Float32> v )
        {
            Int32 n = v.length
            if n == 0
            {
                ret 0.0f
            }
            Float32 m = v._getItem_( 0 )
            Int32 i = 1
            while i < n
            {
                if v._getItem_( i ) > m
                {
                    m = v._getItem_( i )
                }
                i = i + 1
            }
            ret m
        }

        # ── 排序（副本，升序）────────────────────────────────
        public static List<Float32> sorted( List<Float32> v )
        {
            Int32 n = v.length
            List<Float32> s = List<Float32>()
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
                    if s._getItem_( j ) > s._getItem_( j + 1 )
                    {
                        Float32 t = s._getItem_( j )
                        s._setItem_( j, s._getItem_( j + 1 ) )
                        s._setItem_( j + 1, t )
                    }
                    j = j + 1
                }
                i = i + 1
            }
            ret s
        }

        # ── 分位数 / 中位数（R type-7）──────────────────────
        public static Float32 quantile( List<Float32> v, Float32 p )
        {
            Int32 n = v.length
            if n == 0
            {
                ret 0.0f
            }
            List<Float32> s = Stats.sorted( v )
            if n == 1
            {
                ret s._getItem_( 0 )
            }
            Float32 h = SystemConvertFloat32( n - 1 ) * p
            if h <= 0.0f
            {
                ret s._getItem_( 0 )
            }
            Int32 lo = h as Int32
            if lo >= n - 1
            {
                ret s._getItem_( n - 1 )
            }
            Int32 hi = lo + 1
            Float32 f = h - SystemConvertFloat32( lo )
            ret s._getItem_( lo ) + f * ( s._getItem_( hi ) - s._getItem_( lo ) )
        }

        public static List<Float32> quantiles( List<Float32> v, List<Float32> ps )
        {
            List<Float32> r = List<Float32>()
            Int32 n = ps.length
            Int32 i = 0
            while i < n
            {
                r.add( Stats.quantile( v, ps._getItem_( i ) ) )
                i = i + 1
            }
            ret r
        }

        public static Float32 median( List<Float32> v )
        {
            ret Stats.quantile( v, 0.5f )
        }

        # ── 方差 / 标准差（样本，n-1）────────────────────────
        public static Float32 variance( List<Float32> v )
        {
            Int32 n = v.length
            if n < 2
            {
                ret 0.0f
            }
            Float32 m = Stats.mean( v )
            Float32 acc = 0.0f
            Int32 i = 0
            while i < n
            {
                Float32 d = v._getItem_( i ) - m
                acc = acc + d * d
                i = i + 1
            }
            ret acc / SystemConvertFloat32( n - 1 )
        }

        public static Float32 sd( List<Float32> v )
        {
            ret Stats._sqrt( Stats.variance( v ) )
        }

        # Newton-Raphson 平方根（Float32，避免 Math 依赖）
        static Float32 _sqrt( Float32 x )
        {
            if x <= 0.0f
            {
                ret 0.0f
            }
            Float32 g = x
            Int32 i = 0
            while i < 7
            {
                g = ( g + x / g ) * 0.5f
                i = i + 1
            }
            ret g
        }

        # ── 协方差 / Pearson 相关 ──────────────────────────
        public static Float32 covariance( List<Float32> x, List<Float32> y )
        {
            Int32 n = x.length
            if n < 2 || y.length != n
            {
                ret 0.0f
            }
            Float32 mx = Stats.mean( x )
            Float32 my = Stats.mean( y )
            Float32 acc = 0.0f
            Int32 i = 0
            while i < n
            {
                acc = acc + ( x._getItem_( i ) - mx ) * ( y._getItem_( i ) - my )
                i = i + 1
            }
            ret acc / SystemConvertFloat32( n - 1 )
        }

        public static Float32 correlation( List<Float32> x, List<Float32> y )
        {
            Int32 n = x.length
            if n < 2 || y.length != n
            {
                ret 0.0f
            }
            Float32 mx = Stats.mean( x )
            Float32 my = Stats.mean( y )
            Float32 sxx = 0.0f
            Float32 syy = 0.0f
            Float32 sxy = 0.0f
            Int32 i = 0
            while i < n
            {
                Float32 dx = x._getItem_( i ) - mx
                Float32 dy = y._getItem_( i ) - my
                sxx = sxx + dx * dx
                syy = syy + dy * dy
                sxy = sxy + dx * dy
                i = i + 1
            }
            Float32 den = Stats._sqrt( sxx * syy )
            if den == 0.0f
            {
                ret 0.0f
            }
            ret sxy / den
        }

        # ── 排序索引（R order）─────────────────────────────
        public static List<Int32> order( List<Float32> v, bool desc )
        {
            Int32 n = v.length
            List<Int32> idx = List<Int32>()
            Int32 i = 0
            while i < n
            {
                idx.add( i )
                i = i + 1
            }
            i = 0
            while i < n
            {
                Int32 j = 0
                while j < n - i - 1
                {
                    Float32 a = v._getItem_( idx._getItem_( j ) )
                    Float32 b = v._getItem_( idx._getItem_( j + 1 ) )
                    bool swap = false
                    if desc
                    {
                        if a < b { swap = true }
                    }
                    else
                    {
                        if a > b { swap = true }
                    }
                    if swap
                    {
                        Int32 t = idx._getItem_( j )
                        idx._setItem_( j, idx._getItem_( j + 1 ) )
                        idx._setItem_( j + 1, t )
                    }
                    j = j + 1
                }
                i = i + 1
            }
            ret idx
        }

        # ── 频数表（R table；键升序）────────────────────────
        public static DataFrame table( List<Float32> v )
        {
            Int32 n = v.length
            List<Float32> keys = List<Float32>()
            List<Float32> counts = List<Float32>()
            Int32 i = 0
            while i < n
            {
                Float32 val = v._getItem_( i )
                Int32 hit = -1
                Int32 ki = 0
                while ki < keys.length
                {
                    if keys._getItem_( ki ) == val
                    {
                        hit = ki
                    }
                    ki = ki + 1
                }
                if hit >= 0
                {
                    counts._setItem_( hit, counts._getItem_( hit ) + 1.0f )
                }
                else
                {
                    keys.add( val )
                    counts.add( 1.0f )
                }
                i = i + 1
            }
            # R table 按键升序：简单插入排序（key 列与 count 列同步交换）
            Int32 m = keys.length
            i = 0
            while i < m
            {
                Int32 j = 0
                while j < m - i - 1
                {
                    if keys._getItem_( j ) > keys._getItem_( j + 1 )
                    {
                        Float32 tk = keys._getItem_( j )
                        keys._setItem_( j, keys._getItem_( j + 1 ) )
                        keys._setItem_( j + 1, tk )
                        Float32 tc = counts._getItem_( j )
                        counts._setItem_( j, counts._getItem_( j + 1 ) )
                        counts._setItem_( j + 1, tc )
                    }
                    j = j + 1
                }
                i = i + 1
            }
            List<string> names = List<string>()
            names.add( "value" )
            names.add( "count" )
            List<List<Float32>> cols = List<List<Float32>>()
            cols.add( keys )
            cols.add( counts )
            ret DataFrame.fromColumns( names, cols )
        }

        # ── 直方图分箱（R hist）────────────────────────────
        # bins <= 0 → Sturges 法则 k = ⌈log2(n)⌉ + 1（钳制 1..40）
        public static List<Float32> histBreaks( List<Float32> v, Int32 bins )
        {
            List<Float32> br = List<Float32>()
            Int32 n = v.length
            if n == 0
            {
                ret br
            }
            Int32 k = bins
            if k <= 0
            {
                k = 1
                Int32 hp = n
                while hp > 1
                {
                    hp = hp / 2
                    k = k + 1
                }
                if k < 1 { k = 1 }
                if k > 40 { k = 40 }
            }
            Float32 mn = Stats.minValue( v )
            Float32 mx = Stats.maxValue( v )
            Float32 span = mx - mn
            if span <= 0.0f
            {
                span = 1.0f
            }
            Float32 step = span / SystemConvertFloat32( k )
            Int32 i = 0
            while i < k
            {
                br.add( mn + SystemConvertFloat32( i ) * step )
                i = i + 1
            }
            br.add( mx )
            ret br
        }

        public static List<Int32> histCounts( List<Float32> v, Int32 bins )
        {
            List<Int32> cnt = List<Int32>()
            List<Float32> br = Stats.histBreaks( v, bins )
            Int32 nb = br.length - 1
            if nb < 1
            {
                ret cnt
            }
            Int32 i = 0
            while i < nb
            {
                cnt.add( 0 )
                i = i + 1
            }
            Int32 n = v.length
            i = 0
            while i < n
            {
                Float32 val = v._getItem_( i )
                Int32 bi = 0
                while bi < nb
                {
                    if val >= br._getItem_( bi ) && ( bi == nb - 1 || val < br._getItem_( bi + 1 ) )
                    {
                        cnt._setItem_( bi, cnt._getItem_( bi ) + 1 )
                    }
                    bi = bi + 1
                }
                i = i + 1
            }
            ret cnt
        }
    }
}