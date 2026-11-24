# =========================================================================
# SimGameEngine/r/RDataChart.sl —— Std.RData 数据结构 → 图表 → RenderTexture
#
# 映射契约：Std.RData 各结构自身提供取值器（values()/counts()/levels()/
# start()/frequency()/meanValues()/lowerValues()/upperValues()/columnByName()），
# 本类接收这些基础列表生成画布图表。原因：Front 不支持跨模块带点命名空间的
# 类作为方法形参类型（实测 RData.RVector 解析失败），故用列表作为稳定边界。
# 同一画布既可读 CPU 像素（回绘 QT），也可经 toTexture() 得到 GPU 纹理。
# 纯 SL，零 C 改动。
# =========================================================================

import Core;
import Std;

public class RDataChart
{
    static PlotParams makeParams( Int32 w, Int32 h, string title )
    {
        PlotParams p = DrawChart.par()
        p.setSize( w, h )
        p.setMargins( 48, 28, 14, 32 )
        p.setGrid( true, 4 )
        p.setLabels( title, "index", "value" )
        ret p
    }

    static Int32 mapX( Float32 v, Float32 lo, Float32 hi, Int32 left, Int32 pw )
    {
        if hi <= lo { hi = lo + 1.0f }
        Float32 f = ( v - lo ) / ( hi - lo )
        Float32 xf = SystemConvertFloat32( left ) + f * SystemConvertFloat32( pw )
        ret xf as Int32
    }

    static Int32 mapY( Float32 v, Float32 lo, Float32 hi, Int32 top, Int32 ph )
    {
        if hi <= lo { hi = lo + 1.0f }
        Float32 f = ( v - lo ) / ( hi - lo )
        Float32 yf = SystemConvertFloat32( top + ph ) - f * SystemConvertFloat32( ph )
        ret yf as Int32
    }

    static string fmt( Float32 v )
    {
        ret StatsPlot.Plot.fmtNum( v )
    }

    # ── RVector.values() → 折线/点图 ──
    public static DrawCanvas plotVector( List<Float32> values, string title )
    {
        PlotParams p = RDataChart.makeParams( 480, 320, title )
        ret DrawChart.plotY( values, p )
    }

    # ── RFactor.counts()/levels() → 条形图 ──
    public static DrawCanvas barFactor( List<Float32> counts, List<string> levels, string title )
    {
        PlotParams p = RDataChart.makeParams( 480, 320, title )
        ret DrawChart.barplot( counts, levels, p )
    }

    # ── RTimeSeries.values()/start()/frequency() → 折线图 ──
    public static DrawCanvas plotSeries( List<Float32> values, Float32 start, Float32 frequency, string title )
    {
        string lab = title + " (start=" + RDataChart.fmt( start ) + " freq=" + RDataChart.fmt( frequency ) + ")"
        ret RDataChart.plotVector( values, lab )
    }

    # ── RTable.columnByName() → 指定列图表 ──
    public static DrawCanvas plotCsvColumn( List<Float32> values, string columnName, string title )
    {
        if values == null
        {
            DrawCanvas blank = DrawCanvas.create( 480, 320 )
            blank.fill( DrawTypes.white() )
            blank.text( 12, 12, "COLUMN NOT FOUND", DrawTypes.red() )
            ret blank
        }
        ret RDataChart.plotVector( values, title + " [" + columnName + "]" )
    }

    # ── RForecast.meanValues()/lowerValues()/upperValues() → 置信带预测图 ──
    public static DrawCanvas plotForecast( List<Float32> mean, List<Float32> lower, List<Float32> upper, string title )
    {
        DrawCanvas c = DrawCanvas.create( 560, 360 )
        c.fill( DrawTypes.white() )
        Int32 left = 50
        Int32 top = 28
        Int32 pw = 496
        Int32 ph = 292
        Float32 lo = DrawChart.minValue( lower )
        Float32 hi = DrawChart.maxValue( upper )
        if hi <= lo { hi = lo + 1.0f }
        Float32 pad = ( hi - lo ) * 0.08f
        lo = lo - pad
        hi = hi + pad

        Int32 g = 0
        while g <= 4
        {
            Float32 tv = lo + ( hi - lo ) * SystemConvertFloat32( g ) / 4.0f
            Int32 gy = RDataChart.mapY( tv, lo, hi, top, ph )
            c.line( left, gy, left + pw, gy, DrawTypes.lightGray() )
            string gl = RDataChart.fmt( tv )
            c.text( left - 4 - gl.length * 4, gy - 2, gl, DrawTypes.gray() )
            g = g + 1
        }
        c.line( left, top, left, top + ph, DrawTypes.black() )
        c.line( left, top + ph, left + pw, top + ph, DrawTypes.black() )
        c.text( 12, 8, title, DrawTypes.black() )

        Int32 n = mean.length
        if n < 2 { ret c }
        Int32 x = 0
        while x < pw
        {
            Float32 frac = SystemConvertFloat32( x ) / SystemConvertFloat32( pw )
            Float32 idx = frac * SystemConvertFloat32( n - 1 )
            Int32 i0 = idx as Int32
            if i0 >= n - 1 { i0 = n - 2 }
            if i0 < 0 { i0 = 0 }
            Float32 f = idx - SystemConvertFloat32( i0 )
            Float32 lu = lower._getItem_( i0 ) + ( lower._getItem_( i0 + 1 ) - lower._getItem_( i0 ) ) * f
            Float32 up = upper._getItem_( i0 ) + ( upper._getItem_( i0 + 1 ) - upper._getItem_( i0 ) ) * f
            Int32 yu = RDataChart.mapY( up, lo, hi, top, ph )
            Int32 yl = RDataChart.mapY( lu, lo, hi, top, ph )
            if yl > yu { c.fillRect( left + x, yu, 2, yl - yu + 1, DrawTypes.lightGray() ) }
            x = x + 2
        }

        Int32 i = 0
        while i < n - 1
        {
            Int32 x0 = RDataChart.mapX( SystemConvertFloat32( i ), 0.0f, SystemConvertFloat32( n - 1 ), left, pw )
            Int32 x1 = RDataChart.mapX( SystemConvertFloat32( i + 1 ), 0.0f, SystemConvertFloat32( n - 1 ), left, pw )
            Int32 my0 = RDataChart.mapY( mean._getItem_( i ), lo, hi, top, ph )
            Int32 my1 = RDataChart.mapY( mean._getItem_( i + 1 ), lo, hi, top, ph )
            c.line( x0, my0, x1, my1, DrawTypes.palette( 1 ) )
            Int32 ul0 = RDataChart.mapY( upper._getItem_( i ), lo, hi, top, ph )
            Int32 ul1 = RDataChart.mapY( upper._getItem_( i + 1 ), lo, hi, top, ph )
            c.dashedLine( x0, ul0, x1, ul1, DrawTypes.palette( 2 ), 6, 4 )
            Int32 ll0 = RDataChart.mapY( lower._getItem_( i ), lo, hi, top, ph )
            Int32 ll1 = RDataChart.mapY( lower._getItem_( i + 1 ), lo, hi, top, ph )
            c.dashedLine( x0, ll0, x1, ll1, DrawTypes.palette( 2 ), 6, 4 )
            i = i + 1
        }
        c.text( left + 12, top + 12, "MEAN", DrawTypes.palette( 1 ) )
        c.text( left + 12, top + 26, "LOWER/UPPER 80%", DrawTypes.palette( 2 ) )
        ret c
    }
}
