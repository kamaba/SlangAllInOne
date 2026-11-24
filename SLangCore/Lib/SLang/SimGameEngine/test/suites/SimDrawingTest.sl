import SimGameEngine;
import Std;
import Math;

# ============================================================================
# SimDrawingTest — 基础绘图 + R 风格图表验证（第 23 套，doc/24）
# ----------------------------------------------------------------------------
# 覆盖：DrawTypes 颜色/调色板、DrawCanvas 画布与全部图元（直线/虚线/点线/
# 矩形/圆/椭圆/弧/扇形/多边形/文字）、PlotParams 的 par() 参数、DrawChart
# 的统计辅助与 plot/scatter/curve/hist/barplot/boxplot/pie/abline/legend。
# 断言走像素统计与关键点颜色，全部离屏、无窗口、无 C 依赖。
# ============================================================================

public class SimDrawingTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static Int32 passCount()
    {
        ret _pass
    }

    static Int32 failCount()
    {
        ret _fail
    }

    static List<Float32> seq( Int32 n )
    {
        List<Float32> v = List<Float32>()
        Int32 i = 0
        while i < n
        {
            v.add( SystemConvertFloat32( i ) )
            i = i + 1
        }
        ret v
    }

    static void run()
    {
        Console.println( "  [Draw] types + canvas basics" )
        Int32 red = DrawTypes.rgb( 255, 0, 0 )
        check( red == DrawTypes.red(), "rgb(red) packs 0xRRGGBB" )
        check( DrawTypes.redOf( red ) == 255 && DrawTypes.greenOf( red ) == 0, "red/green channel decode" )
        check( DrawTypes.rgb( 300, -2, 7 ) == DrawTypes.rgb( 255, 0, 7 ), "rgb clamps to 0..255" )
        check( DrawTypes.palette( 1 ) == DrawTypes.red(), "palette(1)=red" )
        check( DrawTypes.palette( 9 ) == DrawTypes.palette( 1 ), "palette wraps modulo 8" )
        check( DrawTypes.LTY_DASHED != DrawTypes.LTY_SOLID, "line style constants distinct" )

        DrawCanvas c = DrawCanvas.create( 120, 90 )
        check( c.isReady(), "canvas allocated" )
        check( c.width() == 120 && c.height() == 90, "canvas dimensions" )
        check( c.pixelPtr() != 0, "pixelPtr non-null" )
        check( c.pixelAt( 5, 5 ) == DrawTypes.white(), "canvas initialized white" )
        c.setPixel( 5, 6, red )
        check( c.pixelIs( 5, 6, red ), "setPixel writes packed rgb" )
        check( c.pixelAt( -1, 0 ) == -1, "out-of-range pixelAt returns -1" )
        c.fill( DrawTypes.black() )
        check( c.pixelIs( 5, 6, DrawTypes.black() ), "fill overwrites whole canvas" )
        c.free()
        check( !c.isReady(), "free clears buffer" )

        Console.println( "  [Draw] primitives: line / dash / rect / circle" )
        DrawCanvas p = DrawCanvas.create( 160, 120 )
        p.line( 10, 10, 60, 10, red )
        check( p.pixelIs( 30, 10, red ), "horizontal line midpoint" )
        check( p.pixelIs( 10, 10, red ) && p.pixelIs( 60, 10, red ), "line includes both ends" )
        p.line( 10, 20, 60, 70, DrawTypes.blue() )
        check( p.pixelIs( 35, 45, DrawTypes.blue() ), "diagonal Bresenham passes midpoint" )
        p.dashedLine( 10, 90, 120, 90, DrawTypes.black(), 10, 10 )
        Int32 dashHits = p.nonWhiteCount( 10, 90, 121, 91 )
        check( dashHits > 10 && dashHits < 111, "dashed line leaves gaps (got " + dashHits + ")" )
        p.lineEx( 10, 100, 120, 100, DrawTypes.palette( 2 ), DrawTypes.LTY_DOTTED, 1 )
        Int32 dotHits = p.nonWhiteCount( 10, 100, 121, 101 )
        check( dotHits > 0 && dotHits < 111, "dotted lineEx sparse (got " + dotHits + ")" )
        p.rect( 130, 10, 20, 20, red )
        check( p.pixelIs( 140, 10, red ) && p.pixelAt( 140, 20 ) == DrawTypes.white(), "rect outline only" )
        p.fillRect( 130, 40, 20, 20, DrawTypes.blue() )
        check( p.pixelIs( 140, 50, DrawTypes.blue() ), "fillRect fills interior" )
        p.circle( 70, 60, 20, DrawTypes.black() )
        check( p.pixelAt( 70, 60 ) == DrawTypes.white(), "circle outline keeps center empty" )
        check( p.nonWhiteCount( 48, 38, 93, 83 ) > 20, "circle draws ring" )
        p.fillCircle( 120, 60, 12, DrawTypes.palette( 3 ) )
        check( p.pixelIs( 120, 60, DrawTypes.palette( 3 ) ), "fillCircle fills center" )
        p.free()

        Console.println( "  [Draw] primitives: ellipse / arc / pie / polygon / text" )
        DrawCanvas s = DrawCanvas.create( 200, 160 )
        s.ellipse( 50, 40, 30, 20, red )
        check( s.nonWhiteCount( 18, 18, 83, 63 ) > 10, "ellipse outline" )
        s.fillEllipse( 50, 100, 25, 15, DrawTypes.blue() )
        check( s.pixelIs( 50, 100, DrawTypes.blue() ), "fillEllipse interior" )
        s.arc( 140, 80, 30, 0.0f, 1.5707963f, DrawTypes.black() )
        Int32 arcHits = s.nonWhiteCount( 108, 48, 172, 112 )
        check( arcHits > 5, "arc draws quarter ring" )
        s.pieSlice( 140, 80, 25, 0.0f, -1.5707963f, DrawTypes.palette( 4 ) )
        check( s.nonWhiteCount( 114, 54, 166, 106 ) > 100, "pieSlice fills quadrant" )
        List<Float32> vx = List<Float32>()
        List<Float32> vy = List<Float32>()
        vx.add( 10.0f )
        vx.add( 60.0f )
        vx.add( 35.0f )
        vy.add( 140.0f )
        vy.add( 140.0f )
        vy.add( 110.0f )
        s.fillPolygon( vx, vy, DrawTypes.palette( 5 ) )
        check( s.pixelIs( 35, 135, DrawTypes.palette( 5 ) ), "fillPolygon interior" )
        s.text( 100, 140, "ABC", DrawTypes.black() )
        check( s.nonWhiteCount( 100, 140, 112, 145 ) > 5, "3x5 bitmap text renders" )
        s.free()

        Console.println( "  [Draw] par() parameters + statistics" )
        PlotParams par = DrawChart.par()
        check( par.width == 720 && par.height == 480, "par() default size" )
        check( par.foreground == DrawTypes.black() && par.background == DrawTypes.white(), "par() default colors" )
        par.setSize( 400, 300 )
        par.setColors( DrawTypes.black(), DrawTypes.white(), DrawTypes.lightGray(), DrawTypes.palette( 2 ) )
        par.setLine( DrawTypes.LTY_DASHED, 2 )
        par.setPoint( DrawTypes.PCH_SQUARE, 2 )
        par.setPlotType( DrawTypes.PLOT_LINES )
        par.setLabels( "TITLE", "X", "Y" )
        par.setGrid( true, 4 )
        par.setLegendPos( DrawTypes.LEGEND_BOTTOMLEFT )
        check( par.width == 400 && par.height == 300, "setSize applied" )
        check( par.lineType == DrawTypes.LTY_DASHED && par.lineWidth == 2, "setLine applied" )
        check( par.plotType == DrawTypes.PLOT_LINES, "setPlotType applied" )
        check( par.grid && par.ticks == 4, "setGrid applied" )
        check( par.legendPos == DrawTypes.LEGEND_BOTTOMLEFT, "setLegendPos applied" )
        par.setXlim( 5.0f, 1.0f )
        check( par.lastError.length > 0 && par.autoX, "invalid xlim rejected" )
        par.setXlim( 1.0f, 5.0f )
        check( !par.autoX && par.xlimHigh == 5.0f, "valid xlim applied" )

        List<Float32> stats = List<Float32>()
        stats.add( 1.0f )
        stats.add( 2.0f )
        stats.add( 3.0f )
        stats.add( 4.0f )
        check( DrawChart.sum( stats ) == 10.0f, "sum" )
        check( DrawChart.minValue( stats ) == 1.0f && DrawChart.maxValue( stats ) == 4.0f, "min/max" )
        check( DrawChart.mean( stats ) == 2.5f, "mean" )
        check( DrawChart.median( stats ) == 2.5f, "median (type-7)" )
        check( DrawChart.quantile( stats, 0.25f ) == 1.75f, "quantile 25%" )
        List<Float32> breaks = DrawChart.histBreaks( stats, 2 )
        check( breaks.length == 3, "histBreaks count = bins+1" )
        List<Int32> counts = DrawChart.histCounts( stats, 2 )
        check( counts.length == 2, "histCounts count = bins" )
        Int32 totalCounts = counts._getItem_( 0 ) + counts._getItem_( 1 )
        check( totalCounts == 4, "histCounts covers all samples" )

        Console.println( "  [Draw] charts: plot / scatter / curve / hist / barplot" )
        List<Float32> xs = SimDrawingTest.seq( 6 )
        List<Float32> ys = List<Float32>()
        ys.add( 1.0f )
        ys.add( 4.0f )
        ys.add( 2.0f )
        ys.add( 8.0f )
        ys.add( 5.0f )
        ys.add( 7.0f )
        PlotParams small = PlotParams.create()
        small.setSize( 320, 240 )
        DrawCanvas pl = DrawChart.plot( xs, ys, small )
        check( pl.isReady() && pl.nonWhiteCount( 0, 0, 320, 240 ) > 100, "plot draws axes + points" )
        check( pl.plotWidth() > 0 && pl.plotHeight() > 0, "plot records plot frame" )
        DrawCanvas sc = DrawChart.scatter( xs, ys, small )
        check( sc.nonWhiteCount( 0, 0, 320, 240 ) > 50, "scatter draws points" )
        DrawCanvas cv = DrawChart.curve( xs, ys, small )
        check( cv.nonWhiteCount( 0, 0, 320, 240 ) > 50, "curve draws function polyline" )
        check( DrawChart.abline( cv, 1.0f, 0.0f, small ), "abline overlay succeeds" )
        DrawCanvas hg = DrawChart.hist( ys, 3, small )
        check( hg.nonWhiteCount( 0, 0, 320, 240 ) > 50, "hist draws bars" )
        List<string> labs = List<string>()
        labs.add( "A" )
        labs.add( "B" )
        labs.add( "C" )
        List<Float32> vals = List<Float32>()
        vals.add( 3.0f )
        vals.add( 7.0f )
        vals.add( 5.0f )
        DrawCanvas bp = DrawChart.barplot( vals, labs, small )
        check( bp.nonWhiteCount( 0, 0, 320, 240 ) > 100, "barplot draws bars + labels" )
        DrawCanvas emptyChart = DrawChart.plot( null, null, small )
        check( emptyChart.isReady(), "plot with null data returns blank canvas" )

        Console.println( "  [Draw] charts: boxplot / pie / legend" )
        List<Float32> flat = List<Float32>()
        flat.add( 1.0f )
        flat.add( 2.0f )
        flat.add( 3.0f )
        flat.add( 4.0f )
        flat.add( 5.0f )
        flat.add( 6.0f )
        flat.add( 8.0f )
        flat.add( 10.0f )
        List<Int32> sizes = List<Int32>()
        sizes.add( 5 )
        sizes.add( 3 )
        DrawCanvas bx = DrawChart.boxplot( flat, sizes, labs, small )
        check( bx.nonWhiteCount( 0, 0, 320, 240 ) > 50, "boxplot draws two boxes" )
        DrawCanvas pc = DrawChart.pie( vals, labs, small )
        check( pc.nonWhiteCount( 0, 0, 320, 240 ) > 300, "pie fills slices + legend" )
        List<Int32> cols = List<Int32>()
        cols.add( DrawTypes.red() )
        cols.add( DrawTypes.blue() )
        check( DrawChart.legend( bp, labs, cols, small ), "legend overlay succeeds" )
        check( !DrawChart.abline( null, 1.0f, 0.0f, small ), "abline rejects null canvas" )
        pl.free()
        sc.free()
        cv.free()
        hg.free()
        bp.free()
        bx.free()
        pc.free()
        emptyChart.free()

        Console.println( "SimDrawingTest PASS=" + passCount() + " FAIL=" + failCount() )
    }
}
