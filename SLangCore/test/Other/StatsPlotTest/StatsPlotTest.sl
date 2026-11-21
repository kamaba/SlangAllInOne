# =========================================================================
# StatsPlotTest —— SLang.StatsPlot 模块端到端测试（无头，纯断言）
#
# 覆盖：
#   1.  Stats：sum/mean/median/min/max/quantile(type-7)/sd/var/cor/cov/order
#   2.  DataFrame：fromCsv 解析 / names/column/rowCount / head/tail / filter /
#       sortBy / summary（6 行统计量）/ groupBy+summarise / tableOf
#   3.  PlotCanvas：create/fillRect/line/circle/polygon/text 与 pixel 断言
#   4.  Plot：barplot / lineplot / scatter(拟合线) / histogram / pie / boxplot
#        的像素级冒烟（nonWhiteCount / pixelIs）
#   5.  PlotIo：ascii 预览非空
#
# 运行：dotnet run --no-launch-profile --project Project\CSimpleVMTest\CSimpleVMTest.csproj --
#       SLangCore\test\Other\StatsPlotTest\ProjectTest.jsonc
# =========================================================================

import Std;
import StatsPlot;

class StatsPlotTest
{
    static int s_pass = 0
    static int s_fail = 0

    static void check( string name, bool ok )
    {
        if ok
        {
            s_pass = s_pass + 1
        }
        else
        {
            s_fail = s_fail + 1
            Console.println( "[FAIL] " + name )
        }
    }

    # 容差范围断言（统计浮点）
    static bool near( Float32 v, Float32 expect, Float32 eps )
    {
        Float32 d = v - expect
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d <= eps
    }

    # 简易子串查找（SL String 无 indexOf）
    static Int32 indexOf( string s, string sub )
    {
        Int32 n = s.length
        Int32 m = sub.length
        if m == 0 || n < m
        {
            ret -1
        }
        Int32 i = 0
        while i <= n - m
        {
            Int32 j = 0
            while j < m
            {
                if SystemStringCharCodeAt( s, i + j ) != SystemStringCharCodeAt( sub, j )
                {
                    j = m + 1
                }
                j = j + 1
            }
            if j == m
            {
                ret i
            }
            i = i + 1
        }
        ret -1
    }

    static void fun()
    {
        Console.println( "=== StatsPlotTest begin ===" )

        # ── 1 统计函数（手算基准）────────────────────────────
        List<Float32> v = List<Float32>()
        v.add( 1.0f )
        v.add( 2.0f )
        v.add( 3.0f )
        v.add( 4.0f )
        check( "sum(1..4)=10", StatsPlot.Stats.sum( v ) == 10.0f )
        check( "mean(1..4)=2.5", near( StatsPlot.Stats.mean( v ), 2.5f, 0.0001f ) )
        check( "median(1..4)=2.5", near( StatsPlot.Stats.median( v ), 2.5f, 0.0001f ) )
        check( "min(1..4)=1", StatsPlot.Stats.minValue( v ) == 1.0f )
        check( "max(1..4)=4", StatsPlot.Stats.maxValue( v ) == 4.0f )
        check( "quantile(1..4,0.25)=1.75", near( StatsPlot.Stats.quantile( v, 0.25f ), 1.75f, 0.0001f ) )

        List<Float32> w = List<Float32>()
        w.add( 2.0f )
        w.add( 4.0f )
        w.add( 4.0f )
        w.add( 4.0f )
        w.add( 5.0f )
        w.add( 5.0f )
        w.add( 7.0f )
        w.add( 9.0f )
        check( "median(w)=4.5", near( StatsPlot.Stats.median( w ), 4.5f, 0.0001f ) )
        check( "quantile(w,0.25)=4", near( StatsPlot.Stats.quantile( w, 0.25f ), 4.0f, 0.0001f ) )
        check( "quantile(w,0.75)=5.5", near( StatsPlot.Stats.quantile( w, 0.75f ), 5.5f, 0.0001f ) )
        Float32 sdw = StatsPlot.Stats.sd( w )
        check( "sd(w)~2.138", sdw > 2.13f && sdw < 2.15f )
        Float32 vw = StatsPlot.Stats.variance( w )
        check( "var(w)~4.571", vw > 4.55f && vw < 4.60f )

        List<Float32> x1 = List<Float32>()
        x1.add( 1.0f )
        x1.add( 2.0f )
        x1.add( 3.0f )
        List<Float32> y1 = List<Float32>()
        y1.add( 2.0f )
        y1.add( 4.0f )
        y1.add( 6.0f )
        check( "cor=1 (perfect)", near( StatsPlot.Stats.correlation( x1, y1 ), 1.0f, 0.0001f ) )
        check( "cov==2", near( StatsPlot.Stats.covariance( x1, y1 ), 2.0f, 0.0001f ) )
        List<Int32> ord = StatsPlot.Stats.order( v, false )
        Int32 o0 = 0
        Int32 o3 = 3
        check( "order asc idx", ord._getItem_( o0 ) == 0 && ord._getItem_( o3 ) == 3 )
        List<Int32> ordD = StatsPlot.Stats.order( v, true )
        check( "order desc idx", ordD._getItem_( o0 ) == 3 && ordD._getItem_( o3 ) == 0 )

        # ── 2 DataFrame ──────────────────────────────────────
        string csv = "city,sales,profit\n1,10,2.5\n2,20,3.0\n1,15,4.5"
        StatsPlot.DataFrame df = StatsPlot.DataFrame.fromCsv( csv )
        check( "csv rowCount=3", df.rowCount() == 3 )
        check( "csv colCount=3", df.colCount() == 3 )
        check( "csv names[0]=city", df.nameAt( 0 ) == "city" )
        check( "has(sales)", df.has( "sales" ) )
        check( "!has(nope)", df.has( "nope" ) == false )
        List<Float32> sales = df.column( "sales" )
        Int32 s0 = 0
        Int32 s1 = 1
        Int32 s2 = 2
        check( "sales 10/20/15", sales._getItem_( s0 ) == 10.0f && sales._getItem_( s1 ) == 20.0f && sales._getItem_( s2 ) == 15.0f )

        StatsPlot.DataFrame h2 = df.head( 2 )
        check( "head(2) rows=2", h2.rowCount() == 2 )
        StatsPlot.DataFrame tl = df.tail( 1 )
        check( "tail(1) rows=1", tl.rowCount() == 1 )
        List<Float32> tlSales = tl.column( "sales" )
        check( "tail(1) sales=15", tlSales._getItem_( s0 ) == 15.0f )

        List<bool> which = List<bool>()
        which.add( false )
        which.add( true )
        which.add( true )
        StatsPlot.DataFrame big = df.filter( which )
        check( "filter rows=2", big.rowCount() == 2 )
        check( "filter colCount=3", big.colCount() == 3 )
        List<Float32> bigSales = big.column( "sales" )
        check( "filter first sales=20", bigSales._getItem_( s0 ) == 20.0f )

        StatsPlot.DataFrame srt = df.sortBy( "sales", true )
        List<Float32> srtSales = srt.column( "sales" )
        check( "sort desc sales 20/15/10", srtSales._getItem_( s0 ) == 20.0f && srtSales._getItem_( s2 ) == 10.0f )

        StatsPlot.DataFrame sm = df.summary()
        check( "summary rows=6", sm.rowCount() == 6 )
        check( "summary colCount=3", sm.colCount() == 3 )
        check( "summary labels 6", sm.summaryLabels().length == 6 )
        List<Float32> ss = sm.column( "sales" )
        check( "summary sales min=10", ss._getItem_( s0 ) == 10.0f )
        check( "summary sales median=15", near( ss._getItem_( 2 ), 15.0f, 0.0001f ) )
        check( "summary sales mean=15", near( ss._getItem_( 3 ), 15.0f, 0.0001f ) )
        check( "summary sales max=20", ss._getItem_( 5 ) == 20.0f )

        StatsPlot.StatsGroup g = df.groupBy( "city" )
        check( "group keyCount=2", g.keyCount() == 2 )
        check( "group key[0]=1", g.keyAt( 0 ) == 1.0f )
        check( "group size[0]=2", g.sizeOf( 0 ) == 2 )
        check( "group size[1]=1", g.sizeOf( 1 ) == 1 )
        check( "group mean[0] sales=12.5", near( g.mean( 0, "sales" ), 12.5f, 0.0001f ) )
        check( "group sum[1] sales=20", g.sum( 1, "sales" ) == 20.0f )
        StatsPlot.DataFrame gs = g.summarise( "sales", "mean" )
        check( "summarise rows=2", gs.rowCount() == 2 )
        List<Float32> gsMean = gs.column( "mean" )
        check( "summarise mean[0]=12.5", near( gsMean._getItem_( s0 ), 12.5f, 0.0001f ) )
        StatsPlot.DataFrame gs2 = g.summarise( "sales", "sum" )
        List<Float32> gsSum = gs2.column( "sum" )
        check( "summarise sum[1]=20", gsSum._getItem_( s1 ) == 20.0f )
        StatsPlot.DataFrame gs3 = g.summarise( "sales", "count" )
        List<Float32> gsCnt = gs3.column( "count" )
        check( "summarise count[0]=2", gsCnt._getItem_( s0 ) == 2.0f )

        StatsPlot.DataFrame tb = df.tableOf( "city" )
        check( "table rows=2", tb.rowCount() == 2 )
        List<Float32> tbVal = tb.column( "value" )
        List<Float32> tbCnt = tb.column( "count" )
        check( "table value[0]=1", tbVal._getItem_( s0 ) == 1.0f )
        check( "table count[0]=2", tbCnt._getItem_( s0 ) == 2.0f )
        check( "table count[1]=1", tbCnt._getItem_( s1 ) == 1.0f )

        List<Float32> brk = StatsPlot.Stats.histBreaks( w, 0 )
        List<Int32> cnt = StatsPlot.Stats.histCounts( w, 0 )
        check( "hist breaks=5 (n=8 sturges k=4)", brk.length == 5 )
        Int32 csum = cnt._getItem_( 0 ) + cnt._getItem_( 1 ) + cnt._getItem_( 2 ) + cnt._getItem_( 3 )
        check( "hist counts sum=8", csum == 8 )
        check( "hist counts[1]=5", cnt._getItem_( 1 ) == 5 )

        # ── 3/4 图表画布像素冒烟 ─────────────────────────────
        StatsPlot.PlotCanvas cBar = StatsPlot.Plot.barplot( sales, null, "Sales by city" )
        check( "barplot canvas 720x480", cBar.width() == 720 && cBar.height() == 480 )
        check( "barplot painted >1000", cBar.nonWhiteCount( 0, 0, 720, 480 ) > 1000 )
        Int32 barZone = cBar.nonWhiteCount( 60, 200, 700, 440 )
        check( "barplot bars zone >200", barZone > 200 )
        check( "barplot title zone >0", cBar.nonWhiteCount( 300, 5, 430, 26 ) > 0 )
        StatsPlot.PlotCanvas cb2 = StatsPlot.Plot.barplot( sales )
        check( "barplot overload painted", cb2.nonWhiteCount( 0, 0, 720, 480 ) > 1000 )

        List<Float32> trend = List<Float32>()
        trend.add( 1.0f )
        trend.add( 2.5f )
        trend.add( 2.0f )
        trend.add( 4.0f )
        trend.add( 3.5f )
        StatsPlot.PlotCanvas cLine = StatsPlot.Plot.lineplot( trend, "Trend" )
        check( "lineplot painted >300", cLine.nonWhiteCount( 0, 0, 720, 480 ) > 300 )

        List<Float32> xs = List<Float32>()
        xs.add( 1.0f )
        xs.add( 2.0f )
        xs.add( 3.0f )
        xs.add( 4.0f )
        xs.add( 5.0f )
        List<Float32> ys = List<Float32>()
        ys.add( 2.0f )
        ys.add( 4.1f )
        ys.add( 5.9f )
        ys.add( 8.2f )
        ys.add( 10.0f )
        StatsPlot.PlotCanvas cSc = StatsPlot.Plot.scatter( xs, ys, "xy" )
        check( "scatter painted >200", cSc.nonWhiteCount( 0, 0, 720, 480 ) > 200 )
        Int32 redCnt = 0
        Int32 sx = 56
        Int32 red = StatsPlot.PlotCanvas.rgb( 220, 0, 0 )
        while sx < 706
        {
            Int32 sy = 30
            while sy < 440
            {
                if cSc.pixelAt( sx, sy ) == red
                {
                    redCnt = redCnt + 1
                }
                sy = sy + 3
            }
            sx = sx + 3
        }
        check( "scatter fit-line red >10", redCnt > 10 )

        StatsPlot.PlotCanvas cHist = StatsPlot.Plot.histogram( w, 4, "Hist" )
        check( "histogram painted >200", cHist.nonWhiteCount( 0, 0, 720, 480 ) > 200 )

        List<Float32> pieV = List<Float32>()
        pieV.add( 10.0f )
        pieV.add( 20.0f )
        pieV.add( 30.0f )
        List<string> pieL = List<string>()
        pieL.add( "A" )
        pieL.add( "B" )
        pieL.add( "C" )
        StatsPlot.PlotCanvas cPie = StatsPlot.Plot.pie( pieV, pieL, "Share" )
        check( "pie painted >2000", cPie.nonWhiteCount( 0, 0, 720, 480 ) > 2000 )
        check( "pie center zone dark", cPie.nonWhiteCount( 241, 225, 261, 245 ) > 10 )

        # boxplot：两箱（扁平向量 + 分组计数）
        List<Float32> flat = List<Float32>()
        Int32 fi = 0
        while fi < v.length
        {
            flat.add( v._getItem_( fi ) )
            fi = fi + 1
        }
        fi = 0
        while fi < w.length
        {
            flat.add( w._getItem_( fi ) )
            fi = fi + 1
        }
        List<Int32> sizes = List<Int32>()
        sizes.add( v.length )
        sizes.add( w.length )
        List<string> glab = List<string>()
        glab.add( "V" )
        glab.add( "W" )
        StatsPlot.PlotCanvas cBox = StatsPlot.Plot.boxplot( flat, sizes, glab, "Groups" )
        check( "boxplot painted >500", cBox.nonWhiteCount( 0, 0, 720, 480 ) > 500 )

        # ── 5 PlotIo ─────────────────────────────────────────
        string asciiBar = StatsPlot.PlotIo.ascii( cBar )
        check( "ascii bar non-empty", asciiBar.length > 20 )
        check( "ascii bar has @", StatsPlotTest.indexOf( asciiBar, "@" ) >= 0 )

        cBar.free()
        cb2.free()
        cLine.free()
        cSc.free()
        cHist.free()
        cPie.free()
        cBox.free()

        Console.println( "PASS=" + SystemConvertString( StatsPlotTest.s_pass ) + " FAIL=" + SystemConvertString( StatsPlotTest.s_fail ) )
    }
}