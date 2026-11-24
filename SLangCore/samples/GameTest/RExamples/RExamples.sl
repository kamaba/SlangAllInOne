import Std;
import Core;
import Math;
import SimGameEngine;

# RExamples —— 仿菜鸟教程 R 绘图/回归页的 12 个示例，每格都是真图表。
# 数据来源：runoob r-func-plot / hist / barplot / boxplot / pie / plot-type /
# par / legend / abline / r-linear-regression；随机数与统计用新增 MathR 类。
public class RExamples
{
    static Int32 pass = 0
    static Int32 fail = 0

    static PlotParams makePar( string title, string xlab, string ylab )
    {
        PlotParams p = DrawChart.par()
        p.setSize( 360, 240 )
        p.setMargins( 42, 24, 12, 26 )
        p.setGrid( true, 4 )
        p.setLabels( title, xlab, ylab )
        ret p
    }

    static List<Float32> toF32( List<Float64> v )
    {
        List<Float32> r = List<Float32>()
        Int32 i = 0
        while i < v.length
        {
            r.add( v._getItem_( i ).toFloat32() )
            i = i + 1
        }
        ret r
    }

    static List<Float64> toF64( List<Float32> v )
    {
        List<Float64> r = List<Float64>()
        Int32 i = 0
        while i < v.length
        {
            r.add( v._getItem_( i ).toFloat64() )
            i = i + 1
        }
        ret r
    }

    static List<Float64> dvals( Float64 a, Float64 b, Float64 c, Float64 d, Float64 e )
    {
        List<Float64> v = List<Float64>()
        v.add( a )
        v.add( b )
        v.add( c )
        v.add( d )
        v.add( e )
        ret v
    }

    static List<Float64> dvals6( Float64 a, Float64 b, Float64 c, Float64 d, Float64 e, Float64 f )
    {
        List<Float64> v = List<Float64>()
        v.add( a ); v.add( b ); v.add( c ); v.add( d ); v.add( e ); v.add( f )
        ret v
    }

    static void show( Int32 idx, string caption, DrawCanvas c )
    {
        RExamplesHost.setCaption( idx, caption )
        RExamplesHost.setPixmap( idx, c.pixelPtr(), c.width(), c.height() )
        c.free()
    }

    static void vline( DrawCanvas c, Float64 x, Int32 color, Int32 style )
    {
        Float32 span = c.xhi() - c.xlo()
        if span == 0.0f
        {
            ret
        }
        Float32 frac = ( x.toFloat32() - c.xlo() ) / span
        Int32 off = ( frac * c.plotWidth().toFloat32() ) as Int32
        Int32 px = c.plotLeft() + off
        Int32 y0 = c.plotTop()
        c.lineEx( px, y0, px, y0 + c.plotHeight(), color, style, 2 )
    }

    static void hline( DrawCanvas c, Float64 y, Int32 color, Int32 style )
    {
        Float32 span = c.yhi() - c.ylo()
        if span == 0.0f
        {
            ret
        }
        Float32 frac = ( y.toFloat32() - c.ylo() ) / span
        Int32 off = ( frac * c.plotHeight().toFloat32() ) as Int32
        Int32 py = c.plotTop() + c.plotHeight() - off
        c.lineEx( c.plotLeft(), py, c.plotLeft() + c.plotWidth(), py, color, style, 2 )
    }

    static void miniFrame( DrawCanvas c, Int32 x, Int32 y, Int32 w, Int32 hh, string title )
    {
        c.rect( x, y, w, hh, DrawTypes.black() )
        c.line( x + 24, y + hh - 20, x + w - 6, y + hh - 20, DrawTypes.gray() )
        c.line( x + 24, y + 16, x + 24, y + hh - 20, DrawTypes.gray() )
        c.text( x + 4, y + 2, title, DrawTypes.blue() )
    }

    # [0] plot(): height vs weight scatter + lm fit（r-func-plot / plot page）
    static DrawCanvas exPlot()
    {
        List<Float64> h = List<Float64>()
        h.add( 160.0d ); h.add( 165.0d ); h.add( 170.0d ); h.add( 175.0d ); h.add( 180.0d )
        h.add( 158.0d ); h.add( 172.0d ); h.add( 168.0d ); h.add( 178.0d ); h.add( 182.0d )
        List<Float64> w = List<Float64>()
        w.add( 55.0d ); w.add( 60.0d ); w.add( 65.0d ); w.add( 70.0d ); w.add( 80.0d )
        w.add( 52.0d ); w.add( 68.0d ); w.add( 62.0d ); w.add( 75.0d ); w.add( 85.0d )
        PlotParams p = RExamples.makePar( "Height vs Weight (blue=points red=lm)", "height cm", "weight kg" )
        DrawCanvas c = DrawChart.scatter( RExamples.toF32( h ), RExamples.toF32( w ), p )
        Float64 slope = MathStats.lmSlope( h, w )
        Float64 inter = MathStats.lmIntercept( h, w )
        DrawChart.abline( c, slope.toFloat32(), inter.toFloat32(), p )
        ret c
    }

    # [1] hist(): 200 normal scores + mean/median lines + legend（r-func-hist）
    static DrawCanvas exHist()
    {
        MathDist.setSeed( 123 )
        List<Float64> scores = List<Float64>()
        Int32 i = 0
        while i < 200
        {
            scores.add( MathDist.rnorm( 70.0d, 10.0d ) )
            i = i + 1
        }
        PlotParams p = RExamples.makePar( "Exam scores histogram (15 bins)", "score", "count" )
        DrawCanvas c = DrawChart.hist( RExamples.toF32( scores ), 15, p )
        RExamples.vline( c, MathStats.mean( scores ), DrawTypes.red(), DrawTypes.LTY_DASHED )
        RExamples.vline( c, MathStats.median( scores ), DrawTypes.blue(), DrawTypes.LTY_DOTTED )
        List<string> labs = List<string>()
        labs.add( "mean" )
        labs.add( "median" )
        List<Int32> cols = List<Int32>()
        cols.add( DrawTypes.red() )
        cols.add( DrawTypes.blue() )
        DrawChart.legend( c, labs, cols, p )
        ret c
    }

    # [2] barplot(): 5 colored product bars（r-func-barplot example 1）
    static DrawCanvas exBar()
    {
        List<Float64> sales = RExamples.dvals( 120.0d, 85.0d, 150.0d, 90.0d, 110.0d )
        List<string> names = List<string>()
        names.add( "A" ); names.add( "B" ); names.add( "C" ); names.add( "D" ); names.add( "E" )
        DrawCanvas c = DrawCanvas.create( 360, 240 )
        c.fill( DrawTypes.white() )
        c.text( 8, 8, "Product sales (barplot)", DrawTypes.blue() )
        c.line( 32, 210, 350, 210, DrawTypes.black() )
        Int32 i = 0
        while i < 5
        {
            Float64 v = sales._getItem_( i )
            Int32 bh = ( v / 150.0d * 160.0d ) as Int32
            Int32 bx = 44 + i * 60
            c.fillRect( bx, 210 - bh, 40, bh, DrawTypes.palette( i + 1 ) )
            string lb = names._getItem_( i )
            c.text( bx + 14, 214, lb, DrawTypes.black() )
            i = i + 1
        }
        ret c
    }

    # [3] barplot(beside=TRUE): Q1 vs Q2 grouped bars（r-func-barplot example 2）
    static DrawCanvas exBarGroup()
    {
        List<Float64> q1 = RExamples.dvals( 120.0d, 85.0d, 150.0d, 90.0d, 110.0d )
        List<Float64> q2 = RExamples.dvals( 130.0d, 90.0d, 140.0d, 95.0d, 125.0d )
        DrawCanvas c = DrawCanvas.create( 360, 240 )
        c.fill( DrawTypes.white() )
        c.text( 8, 8, "Quarter sales (beside=TRUE)", DrawTypes.blue() )
        c.line( 32, 210, 350, 210, DrawTypes.black() )
        Int32 i = 0
        while i < 5
        {
            Float64 a = q1._getItem_( i )
            Float64 b = q2._getItem_( i )
            Int32 ha = ( a / 150.0d * 150.0d ) as Int32
            Int32 hb = ( b / 150.0d * 150.0d ) as Int32
            Int32 bx = 36 + i * 62
            c.fillRect( bx, 210 - ha, 26, ha, DrawTypes.palette( 1 ) )
            c.fillRect( bx + 27, 210 - hb, 26, hb, DrawTypes.palette( 2 ) )
            i = i + 1
        }
        c.fillRect( 270, 20, 12, 10, DrawTypes.palette( 1 ) )
        c.text( 286, 20, "Q1", DrawTypes.black() )
        c.fillRect( 270, 36, 12, 10, DrawTypes.palette( 2 ) )
        c.text( 286, 36, "Q2", DrawTypes.black() )
        ret c
    }

    # [4] boxplot(): three classes（r-func-boxplot example 1）
    static DrawCanvas exBox()
    {
        List<Float64> flat = List<Float64>()
        Array<Float64> groups = [ 78.0d, 82.0d, 85.0d, 88.0d, 90.0d, 75.0d, 80.0d, 86.0d, 92.0d, 84.0d,
            72.0d, 75.0d, 78.0d, 76.0d, 80.0d, 70.0d, 74.0d, 77.0d, 79.0d, 73.0d,
            85.0d, 88.0d, 90.0d, 92.0d, 95.0d, 80.0d, 87.0d, 89.0d, 91.0d, 86.0d ]
        Int32 i = 0
        while i < 30
        {
            flat.add( groups[i] )
            i = i + 1
        }
        List<Int32> sizes = List<Int32>()
        sizes.add( 10 ); sizes.add( 10 ); sizes.add( 10 )
        List<string> labs = List<string>()
        labs.add( "A" ); labs.add( "B" ); labs.add( "C" )
        PlotParams p = RExamples.makePar( "Class score boxplot (A/B/C)", "class", "score" )
        ret DrawChart.boxplot( RExamples.toF32( flat ), sizes, labs, p )
    }

    # [5] pie(): market share with percent labels（r-func-pie）
    static DrawCanvas exPie()
    {
        List<Float64> share = RExamples.dvals( 35.0d, 28.0d, 20.0d, 12.0d, 5.0d )
        Float64 total = MathRBasic.sum( share )
        List<string> labs = List<string>()
        labs.add( "A " + MathRBasic.roundDigits( share._getItem_( 0 ) / total * 100.0d, 1 ).toString() + "%" )
        labs.add( "B " + MathRBasic.roundDigits( share._getItem_( 1 ) / total * 100.0d, 1 ).toString() + "%" )
        labs.add( "C " + MathRBasic.roundDigits( share._getItem_( 2 ) / total * 100.0d, 1 ).toString() + "%" )
        labs.add( "D " + MathRBasic.roundDigits( share._getItem_( 3 ) / total * 100.0d, 1 ).toString() + "%" )
        labs.add( "Other " + MathRBasic.roundDigits( share._getItem_( 4 ) / total * 100.0d, 1 ).toString() + "%" )
        PlotParams p = RExamples.makePar( "Market share pie", "", "" )
        ret DrawChart.pie( RExamples.toF32( share ), labs, p )
    }

    # [6] plot(type="n"+"h"+"o"): temperature overlays（r-func-plot-type）
    static DrawCanvas exTypes()
    {
        Array<Float32> temp = [ 5.0f, 7.0f, 10.0f, 14.0f, 18.0f, 22.0f, 25.0f, 28.0f, 26.0f, 20.0f,
            15.0f, 10.0f, 8.0f, 6.0f, 9.0f, 13.0f, 17.0f, 21.0f, 24.0f, 27.0f,
            25.0f, 19.0f, 14.0f, 9.0f, 7.0f, 5.0f, 8.0f, 12.0f, 16.0f, 20.0f ]
        DrawCanvas c = DrawCanvas.create( 360, 240 )
        c.fill( DrawTypes.white() )
        c.text( 8, 8, "Temperature: type=n + h + o", DrawTypes.blue() )
        c.line( 34, 210, 350, 210, DrawTypes.black() )
        c.line( 34, 16, 34, 210, DrawTypes.black() )
        Int32 i = 0
        while i < 30
        {
            Int32 px = 36 + i * 10
            Int32 hh = ( temp[i] * 6.0f ) as Int32
            c.line( px, 210 - hh, px, 210, DrawTypes.palette( 5 ) )
            i = i + 1
        }
        List<Float32> xs = List<Float32>()
        List<Float32> ys = List<Float32>()
        i = 0
        while i < 30
        {
            xs.add( ( 36 + i * 10 ).toFloat32() )
            ys.add( 210.0f - temp[i] * 6.0f )
            i = i + 1
        }
        c.polyline( xs, ys, DrawTypes.palette( 2 ) )
        i = 0
        while i < 30
        {
            Int32 px = 36 + i * 10
            Int32 py = ( 210.0f - temp[i] * 6.0f ) as Int32
            c.fillCircle( px, py, 2, DrawTypes.palette( 2 ) )
            i = i + 1
        }
        ret c
    }

    # [7] par(mfrow=c(2,2)): four mini charts in one canvas（r-func-par）
    static DrawCanvas exPar()
    {
        DrawCanvas c = DrawCanvas.create( 360, 240 )
        c.fill( DrawTypes.white() )
        RExamples.miniFrame( c, 6, 16, 170, 100, "scatter x^2" )
        RExamples.miniFrame( c, 184, 16, 170, 100, "hist" )
        RExamples.miniFrame( c, 6, 128, 170, 100, "bar" )
        RExamples.miniFrame( c, 184, 128, 170, 100, "box" )
        Int32 i = 0
        while i < 10
        {
            Int32 xv = 30 + i * 14
            Float32 ff = i.toFloat32()
            Float32 fy = 100.0f - ff * ff * 0.8f
            Int32 yv = fy as Int32
            Int32 bx = 208 + i * 14
            Int32 bh = i * 5 + 10
            Int32 by = 100 - bh
            c.fillCircle( xv, yv, 2, DrawTypes.palette( 1 ) )
            c.fillRect( bx, by, 9, bh, DrawTypes.palette( 2 ) )
            i = i + 1
        }
        c.rect( 48, 168, 80, 36, DrawTypes.palette( 3 ) )
        c.line( 88, 168, 88, 204, DrawTypes.black() )
        c.line( 50, 178, 126, 178, DrawTypes.black() )
        ret c
    }

    # [8] legend(): three product trend lines（r-func-legend）
    static DrawCanvas exLegend()
    {
        List<Float64> month = List<Float64>()
        month.add( 1.0d ); month.add( 2.0d ); month.add( 3.0d )
        month.add( 4.0d ); month.add( 5.0d ); month.add( 6.0d )
        List<Float64> a = RExamples.dvals6( 100.0d, 120.0d, 115.0d, 135.0d, 145.0d, 160.0d )
        List<Float64> b = RExamples.dvals6( 85.0d, 90.0d, 95.0d, 100.0d, 105.0d, 110.0d )
        List<Float64> cc = RExamples.dvals6( 60.0d, 70.0d, 80.0d, 75.0d, 90.0d, 88.0d )
        PlotParams p = RExamples.makePar( "Product monthly sales + legend", "month", "sales" )
        p.setYlim( 50.0f, 170.0f )
        p.setPlotType( DrawTypes.PLOT_BOTH )
        DrawCanvas c = DrawChart.plot( RExamples.toF32( month ), RExamples.toF32( a ), p )
        List<Float32> ysB = RExamples.toF32( b )
        List<Float32> ysC = RExamples.toF32( cc )
        c.polyline( RExamples.toF32( month ), ysB, DrawTypes.palette( 2 ) )
        c.polyline( RExamples.toF32( month ), ysC, DrawTypes.palette( 3 ) )
        List<string> labs = List<string>()
        labs.add( "A" ); labs.add( "B" ); labs.add( "C" )
        List<Int32> cols = List<Int32>()
        cols.add( DrawTypes.palette( 1 ) ); cols.add( DrawTypes.palette( 2 ) ); cols.add( DrawTypes.palette( 3 ) )
        DrawChart.legend( c, labs, cols, p )
        ret c
    }

    # [9] abline(): regression + h=mean + v=10（r-func-abline）
    static DrawCanvas exAbline()
    {
        MathDist.setSeed( 2024 )
        List<Float64> xs = List<Float64>()
        List<Float64> ys = List<Float64>()
        Int32 i = 1
        while i <= 20
        {
            Float64 x = i.toFloat64()
            xs.add( x )
            ys.add( 3.0d * x + MathDist.rnorm( 0.0d, 5.0d ) )
            i = i + 1
        }
        PlotParams p = RExamples.makePar( "abline: fit / mean / x=10", "X", "Y" )
        DrawCanvas c = DrawChart.scatter( RExamples.toF32( xs ), RExamples.toF32( ys ), p )
        Float64 slope = MathStats.lmSlope( xs, ys )
        Float64 inter = MathStats.lmIntercept( xs, ys )
        DrawChart.abline( c, slope.toFloat32(), inter.toFloat32(), p )
        RExamples.hline( c, MathStats.mean( ys ), DrawTypes.green(), DrawTypes.LTY_DASHED )
        RExamples.vline( c, 10.0d, DrawTypes.palette( 5 ), DrawTypes.LTY_DOTTED )
        List<string> labs = List<string>()
        labs.add( "fit" ); labs.add( "mean" ); labs.add( "x=10" )
        List<Int32> cols = List<Int32>()
        cols.add( DrawTypes.red() ); cols.add( DrawTypes.green() ); cols.add( DrawTypes.palette( 5 ) )
        DrawChart.legend( c, labs, cols, p )
        ret c
    }

    # [10] lm(): runoob linear-regression dataset + prediction at 170
    static DrawCanvas exRegression()
    {
        List<Float64> h = List<Float64>()
        h.add( 151.0d ); h.add( 174.0d ); h.add( 138.0d ); h.add( 186.0d ); h.add( 128.0d )
        h.add( 136.0d ); h.add( 179.0d ); h.add( 163.0d ); h.add( 152.0d ); h.add( 131.0d )
        List<Float64> w = List<Float64>()
        w.add( 63.0d ); w.add( 81.0d ); w.add( 56.0d ); w.add( 91.0d ); w.add( 47.0d )
        w.add( 57.0d ); w.add( 76.0d ); w.add( 72.0d ); w.add( 62.0d ); w.add( 48.0d )
        PlotParams p = RExamples.makePar( "lm(y~x): predict weight at 170cm", "height", "weight" )
        DrawCanvas c = DrawChart.scatter( RExamples.toF32( h ), RExamples.toF32( w ), p )
        Float64 slope = MathStats.lmSlope( h, w )
        Float64 inter = MathStats.lmIntercept( h, w )
        DrawChart.abline( c, slope.toFloat32(), inter.toFloat32(), p )
        Float64 pred = inter + slope * 170.0d
        Float64 ri = MathRBasic.roundDigits( inter, 2 )
        Float64 rs = MathRBasic.roundDigits( slope, 4 )
        Float64 rp = MathRBasic.roundDigits( pred, 2 )
        string si = ri.toString()
        string ss = rs.toString()
        string sp = rp.toString()
        string txt = "y=" + si + "+" + ss + "x  pred(170)=" + sp
        c.text( 12, 228, txt, DrawTypes.black() )
        ret c
    }

    # [11] MathR 新增函数联动：dnorm 密度曲线 + rnorm 经验直方图
    static DrawCanvas exMathR()
    {
        MathDist.setSeed( 77 )
        List<Float64> samples = List<Float64>()
        Int32 i = 0
        while i < 300
        {
            samples.add( MathDist.rnorm( 0.0d, 1.0d ) )
            i = i + 1
        }
        PlotParams p = RExamples.makePar( "MathDist.dnorm + rnorm histogram", "x", "density/count" )
        DrawCanvas c = DrawChart.hist( RExamples.toF32( samples ), 14, p )
        List<Float32> cx = List<Float32>()
        List<Float32> cy = List<Float32>()
        Float32 span = c.xhi() - c.xlo()
        Float32 pw = c.plotWidth().toFloat32()
        Float32 ph = c.plotHeight().toFloat32()
        Float32 top = c.plotTop().toFloat32()
        Float64 x = 0.0d - 3.0d
        i = 0
        while i < 61
        {
            Int32 off = ( ( x.toFloat32() - c.xlo() ) / span * pw ) as Int32
            Int32 px = c.plotLeft() + off
            Float32 dens = MathDist.dnorm( x, 0.0d, 1.0d ).toFloat32()
            Float32 py = top + ph - dens / 0.4f * ph * 0.85f
            cx.add( px.toFloat32() )
            cy.add( py )
            x = x + 0.1d
            i = i + 1
        }
        c.polyline( cx, cy, DrawTypes.red() )
        List<string> labs = List<string>()
        labs.add( "hist" ); labs.add( "dnorm" )
        List<Int32> cols = List<Int32>()
        cols.add( DrawTypes.palette( 1 ) ); cols.add( DrawTypes.red() )
        DrawChart.legend( c, labs, cols, p )
        ret c
    }

    static void check( Int32 idx, string name, DrawCanvas c )
    {
        Int32 n = c.nonWhiteCount( 0, 0, c.width() - 1, c.height() - 1 )
        if n > 100
        {
            Console.println( "  [PASS] " + name + " pixels=" + n.toString() )
            RExamples.pass = RExamples.pass + 1
        }
        else
        {
            Console.println( "  [FAIL] " + name + " pixels=" + n.toString() )
            RExamples.fail = RExamples.fail + 1
        }
        c.free()
    }

    public static void smoke()
    {
        Console.println( "===== RExamples smoke: 12 chart views =====" )
        RExamples.check( 0, "plot+lm", RExamples.exPlot() )
        RExamples.check( 1, "hist", RExamples.exHist() )
        RExamples.check( 2, "bar", RExamples.exBar() )
        RExamples.check( 3, "bar-group", RExamples.exBarGroup() )
        RExamples.check( 4, "boxplot", RExamples.exBox() )
        RExamples.check( 5, "pie", RExamples.exPie() )
        RExamples.check( 6, "plot-types", RExamples.exTypes() )
        RExamples.check( 7, "par-2x2", RExamples.exPar() )
        RExamples.check( 8, "legend", RExamples.exLegend() )
        RExamples.check( 9, "abline", RExamples.exAbline() )
        RExamples.check( 10, "lm-regression", RExamples.exRegression() )
        RExamples.check( 11, "mathr-dnorm", RExamples.exMathR() )
        string s = "===== RExamples smoke PASS=" + RExamples.pass.toString() + " FAIL=" + RExamples.fail.toString() + " ====="
        Console.println( s )
    }

    public static void run()
    {
        RExamplesHost.build()
        RExamples.show( 0, "[0] plot: height/weight + lm", RExamples.exPlot() )
        RExamples.show( 1, "[1] hist: exam scores + mean/median", RExamples.exHist() )
        RExamples.show( 2, "[2] barplot: product sales", RExamples.exBar() )
        RExamples.show( 3, "[3] barplot: Q1 vs Q2 grouped", RExamples.exBarGroup() )
        RExamples.show( 4, "[4] boxplot: class A/B/C", RExamples.exBox() )
        RExamples.show( 5, "[5] pie: market share", RExamples.exPie() )
        RExamples.show( 6, "[6] plot types: n + h + o", RExamples.exTypes() )
        RExamples.show( 7, "[7] par: 2x2 layout", RExamples.exPar() )
        RExamples.show( 8, "[8] legend: three products", RExamples.exLegend() )
        RExamples.show( 9, "[9] abline: fit/mean/x=10", RExamples.exAbline() )
        RExamples.show( 10, "[10] lm: predict weight at 170cm", RExamples.exRegression() )
        RExamples.show( 11, "[11] MathR: dnorm + rnorm", RExamples.exMathR() )
        RExamplesHost.setTitle( "12 R-style examples | MathRBasic/MathStats/MathDist/MathVec | close to exit" )
        Console.println( "RExamples: 12 chart views rendered; entering Qt event loop" )
        RExamplesHost.exec()
    }
}
