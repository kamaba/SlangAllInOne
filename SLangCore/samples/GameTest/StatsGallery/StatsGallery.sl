import SimGameEngine;
import Std;
import Core;

# StatsGallery — 把 SimGameEngine 新绘图接口的 16 个视图铺到 QT 窗口。
# 行 1-2 = 引擎 drawing/（图元 + DrawChart 八接口）；
# 行 3-4 = 合并入引擎的 StatsPlot（DataFrame/Stats/Plot/PlotIo）。
#
# 2026-11-24 重构：16 个视图块抽成 public static DrawCanvas view0()..view15()
# （自含数据构造，可独立调用），run() 按序消费 —— 桌面 QT 行为不变；
# web wasm 版（GameTest/web/StatsGalleryWeb）按 idx 惰性重渲染单视图。
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

    static List<Int32> groups()
    {
        List<Int32> g = List<Int32>()
        g.add( 5 )
        g.add( 4 )
        ret g
    }

    static PlotParams parParams()
    {
        PlotParams p = DrawChart.par()
        p.setSize( 360, 240 )
        p.setMargins( 42, 24, 12, 26 )
        p.setGrid( true, 4 )
        ret p
    }

    # ── 视图构造（public：web wasm 版按 idx 复用）──────────────────

    # 0: DrawCanvas 基础图元（线 / 虚线 / 点线 / 圆 / 椭圆 / 弧 / 文字）
    public static DrawCanvas view0()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
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
        ret prim
    }

    # 1: plot + abline + legend 叠加
    public static DrawCanvas view1()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        PlotParams p = StatsGallery.parParams()
        DrawCanvas c1 = DrawChart.plot( xs, ys, p )
        DrawChart.abline( c1, 0.8f, 1.0f, p )
        List<Int32> legendColors = List<Int32>()
        legendColors.add( DrawTypes.palette( 1 ) )
        legendColors.add( DrawTypes.palette( 2 ) )
        List<string> legendLabels = List<string>()
        legendLabels.add( "data" )
        legendLabels.add( "fit" )
        DrawChart.legend( c1, legendLabels, legendColors, p )
        ret c1
    }

    public static DrawCanvas view2()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.curve( xs, ys, p )
    }

    public static DrawCanvas view3()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.scatter( xs, ys, p )
    }

    public static DrawCanvas view4()
    {
        List<Float32> ys = StatsGallery.seqY()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.hist( ys, 4, p )
    }

    public static DrawCanvas view5()
    {
        List<Float32> v = StatsGallery.values()
        List<string> lab = StatsGallery.labels()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.barplot( v, lab, p )
    }

    public static DrawCanvas view6()
    {
        List<Float32> ys = StatsGallery.seqY()
        List<Int32> groupSizes = StatsGallery.groups()
        List<string> lab = StatsGallery.labels()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.boxplot( ys, groupSizes, lab, p )
    }

    public static DrawCanvas view7()
    {
        List<Float32> v = StatsGallery.values()
        List<string> lab = StatsGallery.labels()
        PlotParams p = StatsGallery.parParams()
        ret DrawChart.pie( v, lab, p )
    }

    # 8-14: 合并入引擎的 StatsPlot 图表（原模块 API 不变）
    public static StatsPlot.PlotCanvas view8()
    {
        List<Float32> v = StatsGallery.values()
        List<string> lab = StatsGallery.labels()
        ret StatsPlot.Plot.barplot( v, lab, "R barplot" )
    }

    public static StatsPlot.PlotCanvas view9()
    {
        List<Float32> ys = StatsGallery.seqY()
        ret StatsPlot.Plot.lineplot( ys, "R plot(type=l)" )
    }

    public static StatsPlot.PlotCanvas view10()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        ret StatsPlot.Plot.lineplotXY( xs, ys, "R plot(x,y)" )
    }

    public static StatsPlot.PlotCanvas view11()
    {
        List<Float32> xs = StatsGallery.seqX()
        List<Float32> ys = StatsGallery.seqY()
        ret StatsPlot.Plot.scatter( xs, ys, "scatter + fit" )
    }

    public static StatsPlot.PlotCanvas view12()
    {
        List<Float32> ys = StatsGallery.seqY()
        ret StatsPlot.Plot.histogram( ys, 4, "R hist" )
    }

    public static StatsPlot.PlotCanvas view13()
    {
        List<Float32> v = StatsGallery.values()
        List<string> lab = StatsGallery.labels()
        ret StatsPlot.Plot.pie( v, lab, "R pie" )
    }

    public static StatsPlot.PlotCanvas view14()
    {
        List<Float32> ys = StatsGallery.seqY()
        List<Float32> v = StatsGallery.values()
        List<Int32> groupSizes = StatsGallery.groups()
        List<Float32> flat = List<Float32>()
        Int32 fi = 0
        while fi < ys.length
        {
            Float32 fy = ys._getItem_( fi )
            flat.add( fy )
            fi = fi + 1
        }
        fi = 0
        while fi < v.length
        {
            Float32 fv = v._getItem_( fi )
            flat.add( fv )
            fi = fi + 1
        }
        List<string> boxLabels = List<string>()
        boxLabels.add( "YS" )
        boxLabels.add( "V" )
        ret StatsPlot.Plot.boxplot( flat, groupSizes, boxLabels, "R boxplot" )
    }

    # 15: DataFrame + Stats + PlotIo（数据整合链路，无头也有 ASCII 输出）
    public static DrawCanvas view15()
    {
        List<Float32> v = StatsGallery.values()
        StatsPlot.DataFrame df = StatsPlot.DataFrame.fromCsv( "g,v\n1,3\n2,7\n1,5\n2,9\n1,4\n" )
        StatsPlot.DataFrame summary = df.groupBy( "g" ).summarise( "v", "mean" )
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
        ret c15
    }

    # 视图标题（与 run() 的 showDraw/showStats caption 一致；web 版信息条用）
    public static string caption( Int32 idx )
    {
        if idx == 0
        {
            ret "[0] DrawCanvas primitives"
        }
        if idx == 1
        {
            ret "[1] plot + abline + legend"
        }
        if idx == 2
        {
            ret "[2] curve (function line)"
        }
        if idx == 3
        {
            ret "[3] scatter"
        }
        if idx == 4
        {
            ret "[4] hist"
        }
        if idx == 5
        {
            ret "[5] barplot"
        }
        if idx == 6
        {
            ret "[6] boxplot"
        }
        if idx == 7
        {
            ret "[7] pie + legend"
        }
        if idx == 8
        {
            ret "[8] StatsPlot.barplot"
        }
        if idx == 9
        {
            ret "[9] StatsPlot.lineplot"
        }
        if idx == 10
        {
            ret "[10] StatsPlot.lineplotXY"
        }
        if idx == 11
        {
            ret "[11] StatsPlot.scatter"
        }
        if idx == 12
        {
            ret "[12] StatsPlot.histogram"
        }
        if idx == 13
        {
            ret "[13] StatsPlot.pie"
        }
        if idx == 14
        {
            ret "[14] StatsPlot.boxplot"
        }
        ret "[15] DataFrame + Stats + PlotIo"
    }

    public static void run()
    {
        GalleryHost.build()

        StatsGallery.showDraw( 0, "[0] DrawCanvas primitives", StatsGallery.view0() )
        StatsGallery.showDraw( 1, "[1] plot + abline + legend", StatsGallery.view1() )
        StatsGallery.showDraw( 2, "[2] curve (function line)", StatsGallery.view2() )
        StatsGallery.showDraw( 3, "[3] scatter", StatsGallery.view3() )
        StatsGallery.showDraw( 4, "[4] hist", StatsGallery.view4() )
        StatsGallery.showDraw( 5, "[5] barplot", StatsGallery.view5() )
        StatsGallery.showDraw( 6, "[6] boxplot", StatsGallery.view6() )
        StatsGallery.showDraw( 7, "[7] pie + legend", StatsGallery.view7() )
        StatsGallery.showStats( 8, "[8] StatsPlot.barplot", StatsGallery.view8() )
        StatsGallery.showStats( 9, "[9] StatsPlot.lineplot", StatsGallery.view9() )
        StatsGallery.showStats( 10, "[10] StatsPlot.lineplotXY", StatsGallery.view10() )
        StatsGallery.showStats( 11, "[11] StatsPlot.scatter", StatsGallery.view11() )
        StatsGallery.showStats( 12, "[12] StatsPlot.histogram", StatsGallery.view12() )
        StatsGallery.showStats( 13, "[13] StatsPlot.pie", StatsGallery.view13() )
        StatsGallery.showStats( 14, "[14] StatsPlot.boxplot", StatsGallery.view14() )
        StatsGallery.showDraw( 15, "[15] DataFrame + Stats + PlotIo", StatsGallery.view15() )

        Float32 sdv = StatsPlot.Stats.sd( StatsGallery.values() )
        GalleryHost.setTitle( "16 views ready | rows 1-2: engine drawing/ | rows 3-4: merged StatsPlot | sd(v)=" + StatsPlot.Plot.fmtNum( sdv ) )
        Console.println( "StatsGallery: 16 chart views rendered; entering Qt event loop" )
        GalleryHost.exec()
    }
}
