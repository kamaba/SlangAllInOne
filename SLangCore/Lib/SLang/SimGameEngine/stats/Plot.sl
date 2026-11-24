# =========================================================================
# Stats/Plot.sl —— 六种图表工厂（R base 图形族，纯静态函数）
#
# 用法见 doc/02-Usage.md §4；实现说明见 doc/01-Design.md §5.5/D4/D5。
# 图表：barplot（柱状）/ lineplot / lineplotXY（折线）/ scatter（散点+拟合线）
#       / histogram（直方图）/ pie（饼图+图例）/ boxplot（箱线图）
# 布局常量集中：边距 left=56 right=14 top=30 bottom=34，刻度 5 档，
# 调色板对齐 R palette()（PlotCanvas.palette）。
# 依赖：Mathf.cos/sin（饼图切片弧），import Math。
# =========================================================================

import Core;
import Std;
import Math;

namespace StatsPlot
{
    public class Plot
    {
        # ── 布局常量 ───────────────────────────────────────
        static Int32 ML = 56
        static Int32 MR = 14
        static Int32 MT = 30
        static Int32 MB = 34

        static Float32 _PI = 3.14159265f

        # ── 数值标签格式（整形不补小数；非整 2 位小数）────────
        public static string fmtNum( Float32 v )
        {
            if v == 0.0f
            {
                ret "0"
            }
            Int32 vi = v as Int32
            Float32 iv = vi as Float32
            if v == iv
            {
                ret SystemConvertString( vi )
            }
            bool neg = v < 0.0f
            Float32 a = v
            if neg
            {
                a = 0.0f - a
            }
            Int32 t = ( ( a * 100.0f ) + 0.5f ) as Int32
            Int32 ip = t / 100
            Int32 fp = t % 100
            string s = ""
            if neg
            {
                s = "-"
            }
            s = s + SystemConvertString( ip )
            s = s + "."
            if fp < 10
            {
                s = s + "0"
            }
            s = s + SystemConvertString( fp )
            ret s
        }

        # ── 坐标轴 + 刻度（v0.1：底轴 + 左轴 + 5 档刻度标签）──
        static void _drawTicks( PlotCanvas c, Float32 lo, Float32 hi, Int32 k, Int32 ml, Int32 mt, Int32 pw, Int32 ph )
        {
            Int32 black = PlotCanvas.rgb( 0, 0, 0 )
            Int32 x0 = ml
            Int32 y1 = mt + ph
            c.line( x0, y1, x0 + pw, y1, black )
            c.line( x0, mt - 4, x0, y1, black )
            Int32 i = 0
            while i <= k
            {
                Float32 t = lo + ( hi - lo ) * ( SystemConvertFloat32( i ) / SystemConvertFloat32( k ) )
                Float32 ty = SystemConvertFloat32( y1 ) - ( t - lo ) / ( hi - lo ) * SystemConvertFloat32( ph )
                Int32 iy = ty as Int32
                c.line( x0, iy, x0 + 4, iy, black )
                string lab = Plot.fmtNum( t )
                c.text( x0 - 6 - lab.length * 4, iy - 2, lab, black )
                i = i + 1
            }
        }

        # x/y 值 → 屏幕坐标
        static Float32 _sx( Float32 v, Float32 lo, Float32 hi, Int32 ml, Int32 pw )
        {
            ret SystemConvertFloat32( ml ) + ( v - lo ) / ( hi - lo ) * SystemConvertFloat32( pw )
        }

        static Float32 _sy( Float32 v, Float32 lo, Float32 hi, Int32 mt, Int32 ph )
        {
            ret SystemConvertFloat32( mt + ph ) - ( v - lo ) / ( hi - lo ) * SystemConvertFloat32( ph )
        }

        # 标题（顶部居中）
        static void _title( PlotCanvas c, string title )
        {
            if title != null && title.length > 0
            {
                c.text( c.width() / 2 - title.length * 2 - 2, 10, title, PlotCanvas.rgb( 0, 0, 0 ) )
            }
        }

        # ── 柱状图（R barplot）──────────────────────────────
        public static PlotCanvas barplot( List<Float32> values )
        {
            ret Plot.barplot( values, null, "" )
        }

        public static PlotCanvas barplot( List<Float32> values, List<string> labels, string title )
        {
            Int32 w = 720
            Int32 h = 480
            PlotCanvas c = PlotCanvas.create( w, h )
            Int32 n = 0
            if values != null
            {
                n = values.length
            }
            if n == 0
            {
                ret c
            }
            Int32 pw = w - Plot.ML - Plot.MR
            Int32 ph = h - Plot.MT - Plot.MB
            Float32 lo = 0.0f
            Float32 hi = Stats.maxValue( values )
            if hi <= lo
            {
                hi = 1.0f
            }
            hi = hi + ( hi - lo ) * 0.05f
            Float32 slot = SystemConvertFloat32( pw ) / SystemConvertFloat32( n )
            Float32 bw = slot * 0.6f
            if bw < 2.0f
            {
                bw = 2.0f
            }
            Plot._drawTicks( c, lo, hi, 5, Plot.ML, Plot.MT, pw, ph )
            Int32 i = 0
            while i < n
            {
                Float32 v = values._getItem_( i )
                Float32 bh = ( v - lo ) / ( hi - lo ) * SystemConvertFloat32( ph - 6 )
                if bh < 1.0f
                {
                    bh = 1.0f
                }
                Float32 x0 = SystemConvertFloat32( Plot.ML ) + SystemConvertFloat32( i ) * slot + ( slot - bw ) * 0.5f
                Float32 y0 = SystemConvertFloat32( Plot.MT + ph ) - bh
                c.fillRect( x0 as Int32, y0 as Int32, bw as Int32, ( bh + 1.0f ) as Int32, PlotCanvas.palette( i ) )
                string lab = Plot.fmtNum( v )
                c.text( ( x0 + bw * 0.5f ) as Int32 - lab.length * 2, ( y0 - 13.0f ) as Int32, lab, PlotCanvas.rgb( 0, 0, 0 ) )
                if labels != null && i < labels.length
                {
                    string xl = labels._getItem_( i )
                    c.text( ( x0 + bw * 0.5f ) as Int32 - xl.length * 2, Plot.MT + ph + 6, xl, PlotCanvas.rgb( 0, 0, 0 ) )
                }
                i = i + 1
            }
            Plot._title( c, title )
            ret c
        }

        # ── 折线图（R plot type="l"）────────────────────────
        public static PlotCanvas lineplot( List<Float32> values, string title )
        {
            Int32 n = 0
            if values != null
            {
                n = values.length
            }
            List<Float32> xs = List<Float32>()
            Int32 i = 0
            while i < n
            {
                xs.add( SystemConvertFloat32( i ) )
                i = i + 1
            }
            ret Plot.lineplotXY( xs, values, title )
        }

        public static PlotCanvas lineplotXY( List<Float32> xs, List<Float32> ys, string title )
        {
            Int32 w = 720
            Int32 h = 480
            PlotCanvas c = PlotCanvas.create( w, h )
            Int32 n = xs.length
            if n == 0 || ys.length != n
            {
                ret c
            }
            Int32 pw = w - Plot.ML - Plot.MR
            Int32 ph = h - Plot.MT - Plot.MB
            Float32 xLo = Stats.minValue( xs )
            Float32 xHi = Stats.maxValue( xs )
            Float32 yLo = Stats.minValue( ys )
            Float32 yHi = Stats.maxValue( ys )
            Float32 xr = xHi - xLo
            Float32 yr = yHi - yLo
            if xr <= 0.0f
            {
                xr = 1.0f
            }
            if yr <= 0.0f
            {
                yr = 1.0f
            }
            xLo = xLo - xr * 0.05f
            xHi = xHi + xr * 0.05f
            yLo = yLo - yr * 0.05f
            yHi = yHi + yr * 0.05f
            if yLo >= yHi
            {
                yHi = yLo + 1.0f
            }
            Plot._drawTicks( c, yLo, yHi, 5, Plot.ML, Plot.MT, pw, ph )
            List<Float32> pxs = List<Float32>()
            List<Float32> pys = List<Float32>()
            Int32 i = 0
            while i < n
            {
                pxs.add( Plot._sx( xs._getItem_( i ), xLo, xHi, Plot.ML, pw ) )
                pys.add( Plot._sy( ys._getItem_( i ), yLo, yHi, Plot.MT, ph ) )
                i = i + 1
            }
            c.polyline( pxs, pys, PlotCanvas.rgb( 0, 0, 0 ) )
            # 折线点光斑（半径 2）
            i = 0
            while i < n
            {
                c.circleFilled( pxs._getItem_( i ) as Int32, pys._getItem_( i ) as Int32, 2, PlotCanvas.palette( 1 ) )
                i = i + 1
            }
            Plot._title( c, title )
            ret c
        }

        # ── 散点图 + 最小二乘拟合线（R plot + abline(lm(y~x))）──
        public static PlotCanvas scatter( List<Float32> xs, List<Float32> ys, string title )
        {
            Int32 w = 720
            Int32 h = 480
            PlotCanvas c = PlotCanvas.create( w, h )
            Int32 n = xs.length
            if n == 0 || ys.length != n
            {
                ret c
            }
            Int32 pw = w - Plot.ML - Plot.MR
            Int32 ph = h - Plot.MT - Plot.MB
            Float32 xLo = Stats.minValue( xs )
            Float32 xHi = Stats.maxValue( xs )
            Float32 yLo = Stats.minValue( ys )
            Float32 yHi = Stats.maxValue( ys )
            Float32 xr = xHi - xLo
            Float32 yr = yHi - yLo
            if xr <= 0.0f { xr = 1.0f }
            if yr <= 0.0f { yr = 1.0f }
            xLo = xLo - xr * 0.05f
            xHi = xHi + xr * 0.05f
            yLo = yLo - yr * 0.05f
            yHi = yHi + yr * 0.05f
            if yLo >= yHi { yHi = yLo + 1.0f }
            Plot._drawTicks( c, yLo, yHi, 5, Plot.ML, Plot.MT, pw, ph )
            Int32 i = 0
            while i < n
            {
                Int32 px = Plot._sx( xs._getItem_( i ), xLo, xHi, Plot.ML, pw ) as Int32
                Int32 py = Plot._sy( ys._getItem_( i ), yLo, yHi, Plot.MT, ph ) as Int32
                c.fillRect( px - 1, py - 1, 3, 3, PlotCanvas.rgb( 0, 0, 0 ) )
                i = i + 1
            }
            # 最小二乘拟合线：y = mx + b
            Float32 vx = Stats.variance( xs )
            Float32 m = 0.0f
            if vx > 0.0f
            {
                m = Stats.covariance( xs, ys ) / vx
            }
            Float32 b = Stats.mean( ys ) - m * Stats.mean( xs )
            Int32 ly1 = Plot._sy( m * xLo + b, yLo, yHi, Plot.MT, ph ) as Int32
            Int32 ly2 = Plot._sy( m * xHi + b, yLo, yHi, Plot.MT, ph ) as Int32
            c.line( Plot.ML, ly1, Plot.ML + pw, ly2, PlotCanvas.rgb( 220, 0, 0 ) )
            Plot._title( c, title )
            ret c
        }

        # ── 直方图（R hist；bins<=0 自动 Sturges）────────────
        public static PlotCanvas histogram( List<Float32> values, Int32 bins, string title )
        {
            List<Float32> brk = Stats.histBreaks( values, bins )
            List<Int32> cnt = Stats.histCounts( values, bins )
            List<Float32> bars = List<Float32>()
            Int32 i = 0
            while i < cnt.length
            {
                bars.add( SystemConvertFloat32( cnt._getItem_( i ) ) )
                i = i + 1
            }
            List<string> labels = null
            if bins > 0 && bins <= 6
            {
                labels = List<string>()
                Int32 j = 0
                while j < brk.length - 1
                {
                    labels.add( Plot.fmtNum( brk._getItem_( j ) ) )
                    j = j + 1
                }
            }
            ret Plot.barplot( bars, labels, title )
        }

        # ── 饼图（R pie；切片顺时针自 12 点方向，右侧图例）───
        public static PlotCanvas pie( List<Float32> values, List<string> labels, string title )
        {
            Int32 w = 720
            Int32 h = 480
            PlotCanvas c = PlotCanvas.create( w, h )
            Int32 n = 0
            if values != null
            {
                n = values.length
            }
            if n == 0
            {
                ret c
            }
            Float32 total = Stats.sum( values )
            if total <= 0.0f
            {
                ret c
            }
            Int32 pw = w - Plot.ML - Plot.MR
            Int32 ph = h - Plot.MT - Plot.MB
            Int32 cx = Plot.ML + ( pw * 30 / 100 )
            Int32 cy = Plot.MT + ( ph * 50 / 100 )
            Int32 r = ph * 32 / 100
            if r > cx - Plot.ML
            {
                r = cx - Plot.ML
            }
            Float32 aStart = 0.0f - Plot._PI * 0.5f
            Int32 i = 0
            Int32 black = PlotCanvas.rgb( 0, 0, 0 )
            Float32 cum = 0.0f
            while i < n
            {
                Float32 frac = values._getItem_( i ) / total
                if frac > 0.0005f
                {
                    Float32 aEnd = aStart - frac * 2.0f * Plot._PI
                    List<Float32> pxs = List<Float32>()
                    List<Float32> pys = List<Float32>()
                    pxs.add( SystemConvertFloat32( cx ) )
                    pys.add( SystemConvertFloat32( cy ) )
                    Float32 a = aStart
                    while a > aEnd
                    {
                        pxs.add( SystemConvertFloat32( cx ) + SystemConvertFloat32( r ) * Mathf.cos( a ) )
                        pys.add( SystemConvertFloat32( cy ) + SystemConvertFloat32( r ) * Mathf.sin( a ) )
                        a = a - 0.10f
                    }
                    pxs.add( SystemConvertFloat32( cx ) + SystemConvertFloat32( r ) * Mathf.cos( aEnd ) )
                    pys.add( SystemConvertFloat32( cy ) + SystemConvertFloat32( r ) * Mathf.sin( aEnd ) )
                    c.polygonFilled( pxs, pys, PlotCanvas.palette( i ) )
                    # 描边：中心幅射线 + 弧
                    Int32 lastIdx = pxs.length - 1
                    c.line( cx, cy, pxs._getItem_( 1 ) as Int32, pys._getItem_( 1 ) as Int32, black )
                    c.line( cx, cy, pxs._getItem_( lastIdx ) as Int32, pys._getItem_( lastIdx ) as Int32, black )
                    Int32 ai = 1
                    while ai < pxs.length
                    {
                        c.line( pxs._getItem_( ai - 1 ) as Int32, pys._getItem_( ai - 1 ) as Int32, pxs._getItem_( ai ) as Int32, pys._getItem_( ai ) as Int32, black )
                        ai = ai + 1
                    }
                    aStart = aEnd
                    cum = cum + frac
                }
                i = i + 1
            }
            # 图例（右列：色块 + 标签 + 百分比）
            Int32 lx = Plot.ML + ( pw * 62 / 100 )
            Int32 ly = Plot.MT + 20
            i = 0
            while i < n
            {
                Float32 frac2 = values._getItem_( i ) / total
                c.fillRect( lx, ly, 10, 10, PlotCanvas.palette( i ) )
                string txt = ""
                if labels != null && i < labels.length
                {
                    txt = labels._getItem_( i )
                }
                txt = txt + " " + Plot.fmtNum( frac2 * 100.0f ) + "%"
                c.text( lx + 14, ly - 2, txt, black )
                ly = ly + 16
                i = i + 1
            }
            Plot._title( c, title )
            ret c
        }

        # ── 箱线图（R boxplot；每组一箱：须线 min~max + 箱 Q1~Q3 + 中位线）──
        # 跨模块调用限制（嵌套泛型不可作为模块引用边界参数）：组数据以
        # 扁平向量 + 分组计数传入（flat = 各组数据顺序拼接，sizes[i] = 第 i 组长度）
        public static PlotCanvas boxplot( List<Float32> flat, List<Int32> sizes, List<string> labels, string title )
        {
            Int32 w = 720
            Int32 h = 480
            PlotCanvas c = PlotCanvas.create( w, h )
            Int32 ng = 0
            if sizes != null
            {
                ng = sizes.length
            }
            if ng == 0
            {
                ret c
            }
            Int32 pw = w - Plot.ML - Plot.MR
            Int32 ph = h - Plot.MT - Plot.MB
            # 全局 y 范围（跨组扫描扁平向量）
            Int32 off = 0
            Int32 g = 0
            Float32 lo = 999999.0f
            Float32 hi = -999999.0f
            while g < ng
            {
                Int32 sz = sizes._getItem_( g )
                Int32 k = 0
                while k < sz
                {
                    Float32 val = flat._getItem_( off + k )
                    if val < lo { lo = val }
                    if val > hi { hi = val }
                    k = k + 1
                }
                off = off + sz
                g = g + 1
            }
            Float32 rng = hi - lo
            if rng <= 0.0f { rng = 1.0f }
            lo = lo - rng * 0.05f
            hi = hi + rng * 0.05f
            Plot._drawTicks( c, lo, hi, 5, Plot.ML, Plot.MT, pw, ph )
            Float32 slot = SystemConvertFloat32( pw ) / SystemConvertFloat32( ng )
            Float32 bwx = slot * 0.5f
            if bwx < 4.0f { bwx = 4.0f }
            Int32 black = PlotCanvas.rgb( 0, 0, 0 )
            Int32 red = PlotCanvas.rgb( 200, 0, 0 )
            off = 0
            g = 0
            while g < ng
            {
                Int32 sz = sizes._getItem_( g )
                List<Float32> v = List<Float32>()
                Int32 k = 0
                while k < sz
                {
                    v.add( flat._getItem_( off + k ) )
                    k = k + 1
                }
                off = off + sz
                Float32 cx = SystemConvertFloat32( Plot.ML ) + SystemConvertFloat32( g ) * slot + slot * 0.5f
                if v.length > 0
                {
                    Float32 mn = Stats.minValue( v )
                    Float32 q1 = Stats.quantile( v, 0.25f )
                    Float32 md = Stats.median( v )
                    Float32 q3 = Stats.quantile( v, 0.75f )
                    Float32 mx = Stats.maxValue( v )
                    Int32 yMn = Plot._sy( mn, lo, hi, Plot.MT, ph ) as Int32
                    Int32 yQ1 = Plot._sy( q1, lo, hi, Plot.MT, ph ) as Int32
                    Int32 yMd = Plot._sy( md, lo, hi, Plot.MT, ph ) as Int32
                    Int32 yQ3 = Plot._sy( q3, lo, hi, Plot.MT, ph ) as Int32
                    Int32 yMx = Plot._sy( mx, lo, hi, Plot.MT, ph ) as Int32
                    Int32 cxI = cx as Int32
                    Int32 bwI = bwx as Int32
                    # 须线 + 端帽
                    c.line( cxI, yMn, cxI, yQ1, black )
                    c.line( cxI, yQ3, cxI, yMx, black )
                    c.line( cxI - 4, yMn, cxI + 4, yMn, black )
                    c.line( cxI - 4, yMx, cxI + 4, yMx, black )
                    # 箱体（Q1..Q3 填充 + 描边）+ 中位线
                    Int32 bh = yQ1 - yQ3
                    if bh < 1 { bh = 1 }
                    c.fillRect( cxI - bwI / 2, yQ3, bwI, bh, PlotCanvas.palette( g ) )
                    c.rectBorder( cxI - bwI / 2, yQ3, bwI, bh, black )
                    c.line( cxI - bwI / 2, yMd, cxI + bwI / 2, yMd, red )
                    if labels != null && g < labels.length
                    {
                        string xl = labels._getItem_( g )
                        c.text( cxI - xl.length * 2, Plot.MT + ph + 6, xl, black )
                    }
                }
                g = g + 1
            }
            Plot._title( c, title )
            ret c
        }
    }
}