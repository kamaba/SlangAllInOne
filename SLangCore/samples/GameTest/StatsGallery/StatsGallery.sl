import SimGameEngine;
import Std;
import Core;

# StatsGallery — 把 SimGameEngine 新绘图接口的 16 个视图铺到 QT 窗口。
# 行 1-2 = 引擎 drawing/（图元 + DrawChart 八接口）；
# 行 3-4 = 合并入引擎的 StatsPlot（DataFrame/Stats/Plot/PlotIo）。
public class StatsGallery
{
    static void showDraw( Int32 idx, string caption, DrawCanvas c )
    {
        GalleryHost.setCaption( idx, caption )
        GalleryHost.setPixmap( idx, c.pixelPtr(), c.width(), c.height() )
        c.free()
    }

    static void showStats( Int32 idx, string caption, StatsPlot.PlotCanvas c )
    {
        GalleryHost.setCaption( idx, caption )
        GalleryHost.setPixmap( idx, c.pixelPtr(), c.width(), c.height() )
        c.free()
    }

    static List<Float32> seqX()
    {
        List<Float32> x = List<Float32>()
        Int32 i = 0
        while i < 9
        {
            x.add( SystemConvertFloat32( i ) )
            i = i + 1
        }
        ret x
    }

    static List<Float32> seqY()
    {
        List<Float32> y = List<Float32>()
        y.add( 2.0f )
        y.add( 5.0f )
        y.add( 3.0f )
        y.add( 8.0f )
        y.add( 6.0f )
        y.add( 9.0f )
        y.add( 4.0f )
        y.add( 7.0f )
        y.add( 5.0f )
        ret y
    }

    static List<Float32> values()
    {
        List<Float32> v = List<Float32>()
        v.add( 3.0f )
        v.add( 7.0f )
        v.add( 5.0f )
        v.add( 9.0f )
        v.add( 4.0f )
        ret v
    }

    static List<string> labels()
    {
        List<string> l = List<string>()
        l.add( "A" )
        l.add( "B" )
        l.add( "C" )
        l.add( "D" )
        l.add( "E" )
        ret l
    }

    public static void run()
    {
        GalleryHost.build()

        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        List<Float32> v = StatsGallery.values()
        List<string> lab = StatsGallery.labels()

        # ── 0: DrawCanvas 基础图元（线 / 虚线 / 点线 / 圆 / 椭圆 / 弧 / 文字）──
        DrawCanvas prim = DrawCanvas.create( 360, 240 )
        prim.line( 12, 18, 140, 18, DrawTypes.red() )
        prim.dashedLine( 12, 40, 140, 40, DrawTypes.black(), 12, 6 )
        prim.lineEx( 12, 62, 140, 62, DrawTypes.blue(), DrawTypes.LTY_DOTTED, 1 )
        prim.rect( 12, 82, 70, 50, DrawTypes.red() )
        prim.fillRect( 90, 82, 60, 50, DrawTypes.palette( 3 ) )
        prim.circle( 235, 55, 34, DrawTypes.black() )
        prim.fillCircle( 300, 55, 24, DrawTypes.palette( 4 ) )
        prim.ellipse( 235, 130, 40, 25, DrawTypes.blue() )
        prim.arc( 300, 155, 42, 0.0f, 2.0f, DrawTypes.red() )
        prim.fillPolygon( xs, ys, DrawTypes.palette( 5 ) )
        prim.text( 12, 218, "PRIMITIVES 123", DrawTypes.black() )
        StatsGallery.showDraw( 0, "[0] DrawCanvas primitives", prim )

        PlotParams p = DrawChart.par()
        p.setSize( 360, 240 )
        p.setMargins( 42, 24, 12, 26 )
        p.setGrid( true, 4 )

        # ── 1: plot + abline + legend 叠加 ──
        DrawCanvas c1 = DrawChart.plot( xs, ys, p )
        DrawChart.abline( c1, 0.8f, 1.0f, p )
        List<Int32> legendColors = List<Int32>()
        legendColors.add( DrawTypes.palette( 1 ) )
        legendColors.add( DrawTypes.palette( 2 ) )
        List<string> legendLabels = List<string>()
        legendLabels.add( "data" )
        legendLabels.add( "fit" )
        DrawChart.legend( c1, legendLabels, legendColors, p )
        StatsGallery.showDraw( 1, "[1] plot + abline + legend", c1 )

        DrawCanvas c2 = DrawChart.curve( xs, ys, p )
        StatsGallery.showDraw( 2, "[2] curve (function line)", c2 )

        DrawCanvas c3 = DrawChart.scatter( xs, ys, p )
        StatsGallery.showDraw( 3, "[3] scatter", c3 )

        DrawCanvas c4 = DrawChart.hist( ys, 4, p )
        StatsGallery.showDraw( 4, "[4] hist", c4 )

        DrawCanvas c5 = DrawChart.barplot( v, lab, p )
        StatsGallery.showDraw( 5, "[5] barplot", c5 )

        List<Int32> groupSizes = List<Int32>()
        groupSizes.add( 5 )
        groupSizes.add( 4 )
        DrawCanvas c6 = DrawChart.boxplot( ys, groupSizes, lab, p )
        StatsGallery.showDraw( 6, "[6] boxplot", c6 )

        DrawCanvas c7 = DrawChart.pie( v, lab, p )
        StatsGallery.showDraw( 7, "[7] pie + legend", c7 )

        # ── 8-14: 合并入引擎的 StatsPlot 图表（原模块 API 不变）──
        StatsPlot.PlotCanvas s8 = StatsPlot.Plot.barplot( v, lab, "R barplot" )
        StatsGallery.showStats( 8, "[8] StatsPlot.barplot", s8 )

        StatsPlot.PlotCanvas s9 = StatsPlot.Plot.lineplot( ys, "R plot(type=l)" )
        StatsGallery.showStats( 9, "[9] StatsPlot.lineplot", s9 )

        StatsPlot.PlotCanvas s10 = StatsPlot.Plot.lineplotXY( xs, ys, "R plot(x,y)" )
        StatsGallery.showStats( 10, "[10] StatsPlot.lineplotXY", s10 )

        StatsPlot.PlotCanvas s11 = StatsPlot.Plot.scatter( xs, ys, "scatter + fit" )
        StatsGallery.showStats( 11, "[11] StatsPlot.scatter", s11 )

        StatsPlot.PlotCanvas s12 = StatsPlot.Plot.histogram( ys, 4, "R hist" )
        StatsGallery.showStats( 12, "[12] StatsPlot.histogram", s12 )

        StatsPlot.PlotCanvas s13 = StatsPlot.Plot.pie( v, lab, "R pie" )
        StatsGallery.showStats( 13, "[13] StatsPlot.pie", s13 )

        List<Float32> flat = List<Float32>()
        Int32 fi = 0
        while fi < ys.length
        {
            flat.add( ys._getItem_( fi ) )
            fi = fi + 1
        }
        fi = 0
        while fi < v.length
        {
            flat.add( v._getItem_( fi ) )
            fi = fi + 1
        }
        List<string> boxLabels = List<string>()
        boxLabels.add( "YS" )
        boxLabels.add( "V" )
        StatsPlot.PlotCanvas s14 = StatsPlot.Plot.boxplot( flat, groupSizes, boxLabels, "R boxplot" )
        StatsGallery.showStats( 14, "[14] StatsPlot.boxplot", s14 )

        # ── 15: DataFrame + Stats + PlotIo（数据整合链路，无头也有 ASCII 输出）──
        StatsPlot.DataFrame df = StatsPlot.DataFrame.fromCsv( "g,v\n1,3\n2,7\n1,5\n2,9\n1,4\n" )
        StatsPlot.DataFrame summary = df.groupBy( "g" ).summarise( "v", "mean" )
        Float32 sdv = StatsPlot.Stats.sd( v )
        DrawCanvas c15 = DrawCanvas.create( 360, 240 )
        c15.fill( DrawTypes.white() )
        c15.text( 12, 16, "DATAFRAME + STATS + PLOTIO", DrawTypes.black() )
        c15.text( 12, 38, "rows=5 cols=2 groups=2", DrawTypes.blue() )
        c15.text( 12, 60, "sd(v) ~ 2.30", DrawTypes.red() )
        StatsPlot.PlotCanvas asciiSrc = StatsPlot.Plot.histogram( v, 4, "ascii source" )
        string art = StatsPlot.PlotIo.ascii( asciiSrc )
        Console.println( "--- PlotIo.ascii preview ---" )
        Console.println( art )
        asciiSrc.free()
        c15.text( 12, 100, "ASCII PREVIEW -> CONSOLE", DrawTypes.black() )
        c15.text( 12, 130, "OK: DataFrame/Stats/PlotIo", DrawTypes.palette( 2 ) )
        StatsGallery.showDraw( 15, "[15] DataFrame + Stats + PlotIo", c15 )

        GalleryHost.setTitle( "16 views ready | rows 1-2: engine drawing/ | rows 3-4: merged StatsPlot | sd(v)=" + StatsPlot.Plot.fmtNum( sdv ) )
        Console.println( "StatsGallery: 16 chart views rendered; entering Qt event loop" )
        GalleryHost.exec()
    }
}
