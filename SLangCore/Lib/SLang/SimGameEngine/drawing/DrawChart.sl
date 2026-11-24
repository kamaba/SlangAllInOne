# ============================================================================
# DrawChart — R 基元风格图表工厂（SimGameEngine 基础绘图 / doc/24）
# ----------------------------------------------------------------------------
# 静态工厂，每个函数产一张 DrawCanvas：
#   plot(xs,ys,p) 散点/折线/阶梯（p.plotType）· scatter · curve（函数曲线采样）
#   hist(values,bins,p) 直方图 · barplot(values,labels,p) 条形图
#   boxplot(flat,sizes,labels,p) 箱线图 · pie(values,labels,p) 饼图
# 叠加：abline(canvas,slope,intercept,p) 参考线 · legend(canvas,labels,colors,p) 图例
# 参数：par() / PlotParams；统计辅助 min/max/mean/median/quantile 随类提供。
# 图元全部委托 DrawCanvas → SLangRender.BasicDraw（GDI 原生 / RHI 三角化双后端）；
# 画布可直接上屏（QLabel）或转纹理（toTexture）。
# ============================================================================

import Core;
import Std;
import Math;

public class DrawChart
{
    static Float32 _PI = 3.14159265f

    # ── par() 别名 ──
    public static PlotParams par()
    {
        ret PlotParams.par()
    }

    # ── 描述统计（R 同名函数语义）──
    public static Float32 sum( List<Float32> v )
    {
        if v == null { ret 0.0f }
        Float32 s = 0.0f
        Int32 i = 0
        while i < v.length
        {
            s = s + v._getItem_( i )
            i = i + 1
        }
        ret s
    }

    public static Float32 minValue( List<Float32> v )
    {
        if v == null || v.length == 0 { ret 0.0f }
        Float32 m = v._getItem_( 0 )
        Int32 i = 1
        while i < v.length
        {
            Float32 x = v._getItem_( i )
            if x < m { m = x }
            i = i + 1
        }
        ret m
    }

    public static Float32 maxValue( List<Float32> v )
    {
        if v == null || v.length == 0 { ret 0.0f }
        Float32 m = v._getItem_( 0 )
        Int32 i = 1
        while i < v.length
        {
            Float32 x = v._getItem_( i )
            if x > m { m = x }
            i = i + 1
        }
        ret m
    }

    public static Float32 mean( List<Float32> v )
    {
        if v == null || v.length == 0 { ret 0.0f }
        ret DrawChart.sum( v ) / SystemConvertFloat32( v.length )
    }

    public static List<Float32> sorted( List<Float32> v )
    {
        List<Float32> r = List<Float32>()
        if v == null { ret r }
        Int32 i = 0
        while i < v.length
        {
            r.add( v._getItem_( i ) )
            i = i + 1
        }
        Int32 n = r.length
        i = 0
        while i < n
        {
            Int32 j = 0
            while j < n - i - 1
            {
                Float32 a = r._getItem_( j )
                Float32 b = r._getItem_( j + 1 )
                if a > b
                {
                    r._setItem_( j, b )
                    r._setItem_( j + 1, a )
                }
                j = j + 1
            }
            i = i + 1
        }
        ret r
    }

    public static Float32 quantile( List<Float32> v, Float32 p )
    {
        List<Float32> s = DrawChart.sorted( v )
        Int32 n = s.length
        if n == 0 { ret 0.0f }
        if n == 1 { ret s._getItem_( 0 ) }
        Float32 q = p
        if q < 0.0f { q = 0.0f }
        if q > 1.0f { q = 1.0f }
        Float32 h = SystemConvertFloat32( n - 1 ) * q
        Int32 lo = h as Int32
        Float32 frac = h - SystemConvertFloat32( lo )
        Int32 hi = lo + 1
        if hi >= n { hi = n - 1 }
        Float32 a = s._getItem_( lo )
        Float32 b = s._getItem_( hi )
        ret a + ( b - a ) * frac
    }

    public static Float32 median( List<Float32> v )
    {
        ret DrawChart.quantile( v, 0.5f )
    }

    # ── 内部工具 ──
    static PlotParams eff( PlotParams p )
    {
        if p == null
        {
            ret PlotParams.create()
        }
        ret p
    }

    static string fmt( Float32 v )
    {
        if v == 0.0f { ret "0" }
        Int32 vi = v as Int32
        Float32 vf = SystemConvertFloat32( vi )
        if v == vf { ret SystemConvertString( vi ) }
        bool neg = v < 0.0f
        Float32 a = v
        if neg { a = 0.0f - a }
        Int32 hundred = ( ( a * 100.0f ) + 0.5f ) as Int32
        string s = ""
        if neg { s = "-" }
        s = s + SystemConvertString( hundred / 100 )
        s = s + "."
        Int32 frac = hundred % 100
        if frac < 10 { s = s + "0" }
        s = s + SystemConvertString( frac )
        ret s
    }

    static Float32 sx( Float32 v, Float32 lo, Float32 hi, Int32 left, Int32 pw )
    {
        if hi <= lo { hi = lo + 1.0f }
        ret SystemConvertFloat32( left ) + ( v - lo ) / ( hi - lo ) * SystemConvertFloat32( pw )
    }

    static Float32 sy( Float32 v, Float32 lo, Float32 hi, Int32 top, Int32 ph )
    {
        if hi <= lo { hi = lo + 1.0f }
        ret SystemConvertFloat32( top + ph ) - ( v - lo ) / ( hi - lo ) * SystemConvertFloat32( ph )
    }

    static void point( DrawCanvas c, Int32 px, Int32 py, Int32 symbol, Int32 scale, Int32 color )
    {
        Int32 r = scale
        if r < 1 { r = 1 }
        if r > 6 { r = 6 }
        if symbol == DrawTypes.PCH_NONE { ret }
        if symbol == DrawTypes.PCH_SQUARE
        {
            c.fillRect( px - r, py - r, r * 2 + 1, r * 2 + 1, color )
            ret
        }
        if symbol == DrawTypes.PCH_PIXEL
        {
            c.setPixel( px, py, color )
            ret
        }
        c.circle( px, py, r, color )
        c.setPixel( px, py, color )
    }

    # 画坐标轴 / 网格 / 刻度 / 标题，并记录绘图区与数据范围供叠加层使用
    static void frame( DrawCanvas c, PlotParams p, Float32 xlo, Float32 xhi, Float32 ylo, Float32 yhi, bool xTicks )
    {
        Int32 left = p.marginLeft
        Int32 top = p.marginTop
        Int32 pw = p.width - p.marginLeft - p.marginRight
        Int32 ph = p.height - p.marginTop - p.marginBottom
        if pw < 16 { pw = 16 }
        if ph < 16 { ph = 16 }
        Int32 fg = p.foreground
        Int32 baseY = top + ph
        if p.grid
        {
            Int32 k = 0
            while k <= p.ticks
            {
                Float32 t = ylo + ( yhi - ylo ) * ( SystemConvertFloat32( k ) / SystemConvertFloat32( p.ticks ) )
                Int32 gy = DrawChart.sy( t, ylo, yhi, top, ph ) as Int32
                c.line( left, gy, left + pw, gy, p.gridColor )
                if xTicks
                {
                    Float32 xv = xlo + ( xhi - xlo ) * ( SystemConvertFloat32( k ) / SystemConvertFloat32( p.ticks ) )
                    Int32 gx = DrawChart.sx( xv, xlo, xhi, left, pw ) as Int32
                    c.line( gx, top, gx, baseY, p.gridColor )
                }
                k = k + 1
            }
        }
        c.line( left, baseY, left + pw, baseY, fg )
        c.line( left, top, left, baseY, fg )
        Int32 i = 0
        while i <= p.ticks
        {
            Float32 t = ylo + ( yhi - ylo ) * ( SystemConvertFloat32( i ) / SystemConvertFloat32( p.ticks ) )
            Int32 iy = DrawChart.sy( t, ylo, yhi, top, ph ) as Int32
            c.line( left, iy, left + 4, iy, fg )
            string lab = DrawChart.fmt( t )
            c.text( left - 6 - lab.length * DrawTypes.GLYPH_ADVANCE, iy - 2, lab, fg )
            if xTicks
            {
                Float32 xv = xlo + ( xhi - xlo ) * ( SystemConvertFloat32( i ) / SystemConvertFloat32( p.ticks ) )
                Int32 ix = DrawChart.sx( xv, xlo, xhi, left, pw ) as Int32
                c.line( ix, baseY, ix, baseY + 4, fg )
                string xl = DrawChart.fmt( xv )
                c.text( ix - xl.length * 2, baseY + 7, xl, fg )
            }
            i = i + 1
        }
        if p.main != null && p.main.length > 0
        {
            c.text( left + ( pw / 2 ) - p.main.length * 2, 6, p.main, fg )
        }
        if p.ylab != null && p.ylab.length > 0
        {
            c.text( 4, top - 18, p.ylab, fg )
        }
        if p.xlab != null && p.xlab.length > 0
        {
            c.text( left + ( pw / 2 ) - p.xlab.length * 2, p.height - 14, p.xlab, fg )
        }
        c.setPlotFrame( left, top, pw, ph, xlo, xhi, ylo, yhi )
    }

    static DrawCanvas blank( PlotParams p )
    {
        DrawCanvas c = DrawCanvas.create( p.width, p.height )
        c.fill( p.background )
        ret c
    }

    # ── plot()：散点 / 折线 / 点线同绘 / 阶梯（R plot type=）──
    public static DrawCanvas plot( List<Float32> xs, List<Float32> ys, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        Int32 n = 0
        if xs != null && ys != null
        {
            n = xs.length
            if ys.length < n { n = ys.length }
        }
        DrawCanvas c = DrawChart.blank( pp )
        if n == 0 { ret c }
        Float32 xlo = DrawChart.minValue( xs )
        Float32 xhi = DrawChart.maxValue( xs )
        Float32 ylo = DrawChart.minValue( ys )
        Float32 yhi = DrawChart.maxValue( ys )
        Float32 xr = xhi - xlo
        Float32 yr = yhi - ylo
        if xr <= 0.0f { xr = 1.0f }
        if yr <= 0.0f { yr = 1.0f }
        xlo = xlo - xr * 0.05f
        xhi = xhi + xr * 0.05f
        ylo = ylo - yr * 0.05f
        yhi = yhi + yr * 0.05f
        if !pp.autoX { xlo = pp.xlimLow ; xhi = pp.xlimHigh }
        if !pp.autoY { ylo = pp.ylimLow ; yhi = pp.ylimHigh }
        DrawChart.frame( c, pp, xlo, xhi, ylo, yhi, true )
        Int32 pw = pp.width - pp.marginLeft - pp.marginRight
        Int32 ph = pp.height - pp.marginTop - pp.marginBottom
        Int32 left = pp.marginLeft
        Int32 top = pp.marginTop
        Int32 color = pp.seriesColor
        Int32 i = 0
        for i = 0, i < n - 1, i = i + 1
        {
            Float32 x0 = xs._getItem_( i )
            Float32 x1 = xs._getItem_( i + 1 )
            Float32 y0 = ys._getItem_( i )
            Float32 y1 = ys._getItem_( i + 1 )
            Int32 ax = DrawChart.sx( x0, xlo, xhi, left, pw ) as Int32
            Int32 ay = DrawChart.sy( y0, ylo, yhi, top, ph ) as Int32
            Int32 bx = DrawChart.sx( x1, xlo, xhi, left, pw ) as Int32
            Int32 by = DrawChart.sy( y1, ylo, yhi, top, ph ) as Int32
            if pp.plotType == DrawTypes.PLOT_LINES || pp.plotType == DrawTypes.PLOT_BOTH
            {
                c.lineEx( ax, ay, bx, by, color, pp.lineType, pp.lineWidth )
            }
            if pp.plotType == DrawTypes.PLOT_STEPS
            {
                c.lineEx( ax, ay, bx, ay, color, pp.lineType, pp.lineWidth )
                c.lineEx( bx, ay, bx, by, color, pp.lineType, pp.lineWidth )
            }
        }
        if pp.plotType == DrawTypes.PLOT_POINTS || pp.plotType == DrawTypes.PLOT_BOTH || pp.plotType == DrawTypes.PLOT_STEPS
        {
            i = 0
            while i < n
            {
                Int32 px = DrawChart.sx( xs._getItem_( i ), xlo, xhi, left, pw ) as Int32
                Int32 py = DrawChart.sy( ys._getItem_( i ), ylo, yhi, top, ph ) as Int32
                DrawChart.point( c, px, py, pp.pointSymbol, pp.charScale, color )
                i = i + 1
            }
        }
        ret c
    }

    public static DrawCanvas plotY( List<Float32> ys, PlotParams p )
    {
        List<Float32> xs = List<Float32>()
        if ys != null
        {
            Int32 i = 0
            while i < ys.length
            {
                xs.add( SystemConvertFloat32( i ) )
                i = i + 1
            }
        }
        ret DrawChart.plot( xs, ys, p )
    }

    public static DrawCanvas scatter( List<Float32> xs, List<Float32> ys, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        pp.plotType = DrawTypes.PLOT_POINTS
        ret DrawChart.plot( xs, ys, pp )
    }

    # 函数曲线：传入采样点（y=f(x) 的离散采样），强制折线
    public static DrawCanvas curve( List<Float32> xs, List<Float32> ys, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        pp.plotType = DrawTypes.PLOT_LINES
        ret DrawChart.plot( xs, ys, pp )
    }

    # ── hist()：直方图（bins<=0 自动 Sturges）──
    public static List<Float32> histBreaks( List<Float32> v, Int32 bins )
    {
        List<Float32> br = List<Float32>()
        if v == null || v.length == 0 { ret br }
        Float32 lo = DrawChart.minValue( v )
        Float32 hi = DrawChart.maxValue( v )
        if hi <= lo { hi = lo + 1.0f }
        Int32 k = bins
        if k <= 0
        {
            k = 2 + DrawTypes.log2Floor( v.length )
        }
        if k < 1 { k = 1 }
        if k > 64 { k = 64 }
        Float32 step = ( hi - lo ) / SystemConvertFloat32( k )
        Int32 i = 0
        while i <= k
        {
            br.add( lo + step * SystemConvertFloat32( i ) )
            i = i + 1
        }
        ret br
    }

    public static List<Int32> histCounts( List<Float32> v, Int32 bins )
    {
        List<Float32> br = DrawChart.histBreaks( v, bins )
        List<Int32> cnt = List<Int32>()
        Int32 k = br.length - 1
        Int32 j = 0
        while j < k
        {
            cnt.add( 0 )
            j = j + 1
        }
        if v == null || k <= 0 { ret cnt }
        Int32 i = 0
        while i < v.length
        {
            Float32 x = v._getItem_( i )
            Int32 b = 0
            while b < k
            {
                Float32 a = br._getItem_( b )
                Float32 z = br._getItem_( b + 1 )
                if x >= a && ( x < z || ( b == k - 1 && x <= z ) )
                {
                    Int32 old = cnt._getItem_( b )
                    cnt._setItem_( b, old + 1 )
                    break
                }
                b = b + 1
            }
            i = i + 1
        }
        ret cnt
    }

    public static DrawCanvas hist( List<Float32> values, Int32 bins, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        List<Int32> counts = DrawChart.histCounts( values, bins )
        List<Float32> bars = List<Float32>()
        Int32 i = 0
        while i < counts.length
        {
            bars.add( SystemConvertFloat32( counts._getItem_( i ) ) )
            i = i + 1
        }
        ret DrawChart.barplot( bars, null, pp )
    }

    # ── barplot()：条形图 ──
    public static DrawCanvas barplot( List<Float32> values, List<string> labels, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        DrawCanvas c = DrawChart.blank( pp )
        Int32 n = 0
        if values != null { n = values.length }
        if n == 0 { ret c }
        Int32 left = pp.marginLeft
        Int32 top = pp.marginTop
        Int32 pw = pp.width - pp.marginLeft - pp.marginRight
        Int32 ph = pp.height - pp.marginTop - pp.marginBottom
        if pw < 16 { pw = 16 }
        if ph < 16 { ph = 16 }
        Float32 hi = DrawChart.maxValue( values )
        if hi <= 0.0f { hi = 1.0f }
        hi = hi * 1.05f
        DrawChart.frame( c, pp, 0.0f, SystemConvertFloat32( n ), 0.0f, hi, false )
        Float32 slot = SystemConvertFloat32( pw ) / SystemConvertFloat32( n )
        Float32 bw = slot * 0.62f
        if bw < 2.0f { bw = 2.0f }
        Int32 k = 0
        while k < n
        {
            Float32 v = values._getItem_( k )
            Float32 bh = v / hi * SystemConvertFloat32( ph - 4 )
            if bh < 1.0f { bh = 1.0f }
            Int32 bx = ( SystemConvertFloat32( left ) + SystemConvertFloat32( k ) * slot + ( slot - bw ) * 0.5f ) as Int32
            Int32 by = ( SystemConvertFloat32( top + ph ) - bh ) as Int32
            Int32 col = DrawTypes.palette( k )
            c.fillRect( bx, by, bw as Int32, ( bh + 1.0f ) as Int32, col )
            if labels != null && k < labels.length
            {
                string lab = labels._getItem_( k )
                c.text( bx - lab.length * 2, top + ph + 7, lab, pp.foreground )
            }
            k = k + 1
        }
        ret c
    }

    # ── boxplot()：扁平向量 + 每组长度，等价 R boxplot(list) ──
    public static DrawCanvas boxplot( List<Float32> flat, List<Int32> sizes, List<string> labels, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        DrawCanvas c = DrawChart.blank( pp )
        Int32 groups = 0
        if sizes != null { groups = sizes.length }
        if groups == 0 || flat == null { ret c }
        Int32 left = pp.marginLeft
        Int32 top = pp.marginTop
        Int32 pw = pp.width - pp.marginLeft - pp.marginRight
        Int32 ph = pp.height - pp.marginTop - pp.marginBottom
        if pw < 16 { pw = 16 }
        if ph < 16 { ph = 16 }
        Float32 lo = 999999.0f
        Float32 hi = -999999.0f
        Int32 i = 0
        while i < flat.length
        {
            Float32 v = flat._getItem_( i )
            if v < lo { lo = v }
            if v > hi { hi = v }
            i = i + 1
        }
        if hi <= lo { hi = lo + 1.0f }
        Float32 pad = ( hi - lo ) * 0.05f
        lo = lo - pad
        hi = hi + pad
        DrawChart.frame( c, pp, 0.0f, SystemConvertFloat32( groups ), lo, hi, false )
        Float32 slot = SystemConvertFloat32( pw ) / SystemConvertFloat32( groups )
        Float32 bw = slot * 0.5f
        if bw < 4.0f { bw = 4.0f }
        Int32 off = 0
        Int32 g = 0
        while g < groups
        {
            Int32 sz = sizes._getItem_( g )
            List<Float32> vals = List<Float32>()
            Int32 j = 0
            while j < sz && off + j < flat.length
            {
                vals.add( flat._getItem_( off + j ) )
                j = j + 1
            }
            off = off + sz
            if vals.length > 0
            {
                Int32 cx = ( SystemConvertFloat32( left ) + SystemConvertFloat32( g ) * slot + slot * 0.5f ) as Int32
                Int32 halfW = ( bw * 0.5f ) as Int32
                Int32 yMin = DrawChart.sy( DrawChart.minValue( vals ), lo, hi, top, ph ) as Int32
                Int32 yMax = DrawChart.sy( DrawChart.maxValue( vals ), lo, hi, top, ph ) as Int32
                Int32 yQ1 = DrawChart.sy( DrawChart.quantile( vals, 0.25f ), lo, hi, top, ph ) as Int32
                Int32 yQ3 = DrawChart.sy( DrawChart.quantile( vals, 0.75f ), lo, hi, top, ph ) as Int32
                Int32 yMd = DrawChart.sy( DrawChart.median( vals ), lo, hi, top, ph ) as Int32
                Int32 fg = pp.foreground
                c.line( cx, yMin, cx, yMax, fg )
                c.line( cx - 4, yMin, cx + 4, yMin, fg )
                c.line( cx - 4, yMax, cx + 4, yMax, fg )
                Int32 bh = yQ1 - yQ3
                if bh < 1 { bh = 1 }
                c.fillRect( cx - halfW, yQ3, halfW * 2 + 1, bh, DrawTypes.palette( g ) )
                c.rect( cx - halfW, yQ3, halfW * 2 + 1, bh, fg )
                c.line( cx - halfW, yMd, cx + halfW, yMd, DrawTypes.palette( 1 ) )
                if labels != null && g < labels.length
                {
                    string lab = labels._getItem_( g )
                    c.text( cx - lab.length * 2, top + ph + 7, lab, fg )
                }
            }
            g = g + 1
        }
        ret c
    }

    # ── pie()：饼图（自 12 点方向顺时针；右侧图例）──
    public static DrawCanvas pie( List<Float32> values, List<string> labels, PlotParams p )
    {
        PlotParams pp = DrawChart.eff( p )
        DrawCanvas c = DrawChart.blank( pp )
        Int32 n = 0
        if values != null { n = values.length }
        if n == 0 { ret c }
        Float32 total = DrawChart.sum( values )
        if total <= 0.0f { ret c }
        Int32 left = pp.marginLeft
        Int32 top = pp.marginTop
        Int32 pw = pp.width - pp.marginLeft - pp.marginRight
        Int32 ph = pp.height - pp.marginTop - pp.marginBottom
        Int32 cx = left + pw * 32 / 100
        Int32 cy = top + ph * 50 / 100
        Int32 r = ph * 40 / 100
        if r > cx - left - 4 { r = cx - left - 4 }
        if r < 4 { r = 4 }
        Float32 a = -0.5f * DrawChart._PI
        Int32 i = 0
        while i < n
        {
            Float32 frac = values._getItem_( i ) / total
            if frac > 0.0005f
            {
                Float32 end = a - frac * 2.0f * DrawChart._PI
                Int32 col = DrawTypes.palette( i )
                c.pieSlice( cx, cy, r, a, end, col )
                Float32 rf = SystemConvertFloat32( r )
                Float32 cxf = SystemConvertFloat32( cx )
                Float32 cyf = SystemConvertFloat32( cy )
                Float32 x1f = cxf + rf * DrawTypes.cos( a )
                Float32 y1f = cyf + rf * DrawTypes.sin( a )
                Float32 x2f = cxf + rf * DrawTypes.cos( end )
                Float32 y2f = cyf + rf * DrawTypes.sin( end )
                c.line( cx, cy, x1f as Int32, y1f as Int32, pp.foreground )
                c.line( cx, cy, x2f as Int32, y2f as Int32, pp.foreground )
                a = end
            }
            i = i + 1
        }
        c.circle( cx, cy, r, pp.foreground )
        # 图例
        Int32 lx = left + pw * 66 / 100
        Int32 ly = top + 16
        i = 0
        while i < n
        {
            Int32 col = DrawTypes.palette( i )
            c.fillRect( lx, ly, 10, 10, col )
            string txt = ""
            if labels != null && i < labels.length { txt = labels._getItem_( i ) }
            Float32 pct = values._getItem_( i ) / total * 100.0f
            txt = txt + " " + DrawChart.fmt( pct ) + "%"
            c.text( lx + 14, ly - 2, txt, pp.foreground )
            ly = ly + 16
            i = i + 1
        }
        if pp.main != null && pp.main.length > 0
        {
            c.text( left + ( pw / 2 ) - pp.main.length * 2, 6, pp.main, pp.foreground )
        }
        c.setPlotFrame( left, top, pw, ph, 0.0f, 1.0f, 0.0f, 1.0f )
        ret c
    }

    # ── abline()：在已有图上叠加参考线 y = slope*x + intercept ──
    public static bool abline( DrawCanvas c, Float32 slope, Float32 intercept, PlotParams p )
    {
        if c == null || !c.isReady() { ret false }
        PlotParams pp = DrawChart.eff( p )
        Float32 xlo = c.xlo()
        Float32 xhi = c.xhi()
        Float32 ylo = c.ylo()
        Float32 yhi = c.yhi()
        Int32 left = c.plotLeft()
        Int32 top = c.plotTop()
        Int32 pw = c.plotWidth()
        Int32 ph = c.plotHeight()
        Int32 ay = DrawChart.sy( slope * xlo + intercept, ylo, yhi, top, ph ) as Int32
        Int32 by = DrawChart.sy( slope * xhi + intercept, ylo, yhi, top, ph ) as Int32
        c.lineEx( left, ay, left + pw, by, pp.seriesColor, pp.lineType, pp.lineWidth )
        ret true
    }

    # ── legend()：在已有图上叠加图例（色块 + 标签）──
    public static bool legend( DrawCanvas c, List<string> labels, List<Int32> colors, PlotParams p )
    {
        if c == null || !c.isReady() || labels == null { ret false }
        PlotParams pp = DrawChart.eff( p )
        Int32 left = c.plotLeft()
        Int32 top = c.plotTop()
        Int32 pw = c.plotWidth()
        Int32 ph = c.plotHeight()
        Int32 lx = left + 10
        Int32 ly = top + 10
        if pp.legendPos == DrawTypes.LEGEND_TOPRIGHT || pp.legendPos == DrawTypes.LEGEND_BOTTOMRIGHT
        {
            Int32 widest = 0
            Int32 iw = 0
            while iw < labels.length
            {
                string s = labels._getItem_( iw )
                Int32 w = 16 + s.length * DrawTypes.GLYPH_ADVANCE
                if w > widest { widest = w }
                iw = iw + 1
            }
            lx = left + pw - widest - 8
        }
        if pp.legendPos == DrawTypes.LEGEND_BOTTOMLEFT || pp.legendPos == DrawTypes.LEGEND_BOTTOMRIGHT
        {
            ly = top + ph - labels.length * 16 - 8
        }
        if ly < top { ly = top }
        Int32 i = 0
        while i < labels.length
        {
            Int32 col = pp.seriesColor
            if colors != null && i < colors.length { col = colors._getItem_( i ) }
            c.fillRect( lx, ly + 2, 9, 9, col )
            string lab = labels._getItem_( i )
            c.text( lx + 14, ly, lab, pp.foreground )
            ly = ly + 16
            i = i + 1
        }
        ret true
    }
}
