# =========================================================================
# SimRDataTest —— Std.RData 统计数据结构 + 引擎映射/chart 接口（第 25 套）
#
# 覆盖：RVector（含 NA）/ RFactor / RTimeSeries / RForecast / RTable（CSV）
# + RDataChart 五个映射接口与画布→RenderTexture 通道。全部离屏断言。
# =========================================================================

import Std;
import SimGameEngine;

public class SimRDataTest
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

    static List<Float32> nums()
    {
        List<Float32> v = List<Float32>()
        v.add( 1.0f )
        v.add( 2.0f )
        v.add( 3.0f )
        v.add( 4.0f )
        ret v
    }

    static List<string> cats()
    {
        List<string> l = List<string>()
        l.add( "A" )
        l.add( "B" )
        l.add( "A" )
        l.add( "C" )
        l.add( "B" )
        ret l
    }

    public static void run()
    {
        Console.println( "  [RData] RVector: NA / statistics / slice / diff" )
        RData.RVector v = RData.RVector.create( SimRDataTest.nums() )
        check( v.length() == 4, "RVector length" )
        check( v.at( 0 ) == 1.0f && v.at( 3 ) == 4.0f, "RVector at" )
        check( v.at( 20 ) == 0.0f, "RVector out-of-range reads 0" )
        check( v.sum() == 10.0f, "RVector sum" )
        check( v.mean() == 2.5f, "RVector mean" )
        check( v.minValue() == 1.0f && v.maxValue() == 4.0f, "RVector min/max" )
        check( v.countNA() == 0 && !v.isNA( 1 ), "RVector no NA initially" )
        v.setNA( 2, true )
        check( v.isNA( 2 ) && v.countNA() == 1, "RVector setNA" )
        check( v.at( 2 ) == 0.0f, "RVector NA reads 0" )
        check( v.sum() == 7.0f, "RVector sum skips NA" )
        v.setNA( 2, false )
        check( v.slice( 1, 2 ).length() == 2, "RVector slice" )
        check( v.diff().at( 0 ) == 1.0f && v.diff().length() == 3, "RVector diff" )
        List<string> names = List<string>()
        names.add( "a" )
        names.add( "b" )
        names.add( "c" )
        names.add( "d" )
        RData.RVector nv = RData.RVector.createNamed( SimRDataTest.nums(), names )
        check( nv.hasNames() && nv.nameAt( 2 ) == "c", "RVector names" )

        Console.println( "  [RData] RFactor: levels / counts / labels" )
        RData.RFactor f = RData.RFactor.fromStrings( SimRDataTest.cats() )
        check( f.length() == 5, "RFactor length" )
        check( f.levelCount() == 3, "RFactor distinct levels" )
        check( f.levelAt( 0 ) == "A" && f.levelAt( 2 ) == "C", "RFactor level order by first appearance" )
        check( f.codeAt( 0 ) == 0 && f.codeAt( 1 ) == 1, "RFactor codes" )
        check( f.labelAt( 4 ) == "B", "RFactor labelAt" )
        check( f.countOf( 0 ) == 2 && f.countOf( 2 ) == 1, "RFactor countOf" )
        check( f.counts().length() == 3, "RFactor counts vector" )
        check( f.levels().length() == 3, "RFactor levels copy" )

        Console.println( "  [RData] RTimeSeries: time / lag / diff / window" )
        RData.RTimeSeries ts = RData.RTimeSeries.fromList( SimRDataTest.nums(), 2020.0f, 4.0f )
        check( ts.length() == 4 && ts.at( 2 ) == 3.0f, "RTimeSeries values" )
        check( ts.start() == 2020.0f && ts.frequency() == 4.0f, "RTimeSeries start/frequency" )
        check( ts.timeAt( 0 ) == 2020.0f && ts.timeAt( 4 ) == 2021.0f, "RTimeSeries timeAt" )
        check( ts.lag( 1 ).length() == 4 && ts.lag( 1 ).at( 1 ) == 1.0f, "RTimeSeries lag" )
        check( ts.diff().length() == 3 && ts.diff().at( 0 ) == 1.0f, "RTimeSeries diff" )
        check( ts.window( 1, 2 ).length() == 2 && ts.window( 1, 2 ).start() == 2020.25f, "RTimeSeries window" )

        Console.println( "  [RData] RForecast: band / residuals" )
        List<Float32> mean = List<Float32>()
        mean.add( 2.0f )
        mean.add( 3.0f )
        mean.add( 4.0f )
        List<Float32> lower = List<Float32>()
        lower.add( 1.0f )
        lower.add( 1.5f )
        lower.add( 2.0f )
        List<Float32> upper = List<Float32>()
        upper.add( 3.0f )
        upper.add( 4.5f )
        upper.add( 6.0f )
        RData.RForecast fc = RData.RForecast.fromLists( mean, lower, upper )
        check( fc.count() == 3, "RForecast count" )
        check( fc.meanAt( 1 ) == 3.0f && fc.lowerAt( 1 ) == 1.5f, "RForecast point values" )
        check( fc.upperAt( 2 ) == 6.0f && fc.coverageWidth( 1 ) == 3.0f, "RForecast band width" )
        check( fc.meanValues().length() == 3 && fc.lowerValues().length() == 3, "RForecast vectors" )
        check( fc.residuals( ts ).length() == 3, "RForecast residuals length" )
        check( fc.residuals( ts ).at( 0 ) == -1.0f, "RForecast residual value" )

        Console.println( "  [RData] RTable: CSV text / columns / factor" )
        string csv = "city,sales,profit\n1,10,2.5\n2,20,3.0\n1,15,4.5\n"
        RData.RTable table = RData.RTable.fromCsvText( csv )
        check( table.rowCount() == 3 && table.columnCount() == 3, "RTable shape" )
        check( table.nameAt( 0 ) == "city" && table.nameAt( 2 ) == "profit", "RTable column names" )
        check( table.has( "sales" ) && !table.has( "missing" ), "RTable has" )
        check( table.columnIndex( "profit" ) == 2, "RTable columnIndex" )
        check( table.columnByName( "sales" ).length() == 3, "RTable numeric column" )
        check( table.columnByName( "sales" ).sum() == 45.0f, "RTable column sum" )
        check( table.stringAt( 0, 1 ) == "2", "RTable stringAt" )
        check( table.stringsOf( 0 ).length() == 3, "RTable stringsOf" )
        check( table.factorByName( "city" ).levelCount() == 2, "RTable factor levels" )
        check( table.factorByName( "city" ).counts().length() == 2, "RTable factor counts" )
        check( table.head( 2 ).rowCount() == 2, "RTable head" )
        check( table.columnByName( "nope" ) == null, "RTable missing column returns null" )

        Console.println( "  [RData] RDataChart: mapping + RenderTexture" )
        DrawCanvas c1 = RDataChart.plotVector( v.values(), "vector" )
        check( c1.nonWhiteCount( 0, 0, 480, 320 ) > 50, "plotVector painted" )
        c1.free()

        List<Float32> countsF = List<Float32>()
        countsF.add( 2.0f )
        countsF.add( 2.0f )
        countsF.add( 1.0f )
        DrawCanvas c2 = RDataChart.barFactor( countsF, f.levels(), "factor" )
        check( c2.nonWhiteCount( 0, 0, 480, 320 ) > 50, "barFactor painted" )
        c2.free()

        DrawCanvas c3 = RDataChart.plotSeries( v.values(), 2020.0f, 4.0f, "series" )
        check( c3.nonWhiteCount( 0, 0, 480, 320 ) > 50, "plotSeries painted" )
        c3.free()

        List<Float32> salesVals = SimRDataTest.nums()
        DrawCanvas c4 = RDataChart.plotCsvColumn( salesVals, "sales", "csv" )
        check( c4.nonWhiteCount( 0, 0, 480, 320 ) > 50, "plotCsvColumn painted" )
        List<Float32> nullVals = null
        DrawCanvas c4b = RDataChart.plotCsvColumn( nullVals, "nope", "blank" )
        check( c4b.nonWhiteCount( 0, 0, 480, 320 ) > 0, "plotCsvColumn null guard paints message" )
        c4.free()
        c4b.free()

        DrawCanvas c5 = RDataChart.plotForecast( mean, lower, upper, "forecast" )
        Int32 fcHits = c5.nonWhiteCount( 0, 0, 560, 360 )
        check( fcHits > 200, "plotForecast band + lines painted (got " + fcHits + ")" )
        var tex = c5.toTexture()
        check( c5.isReady(), "canvas survives toTexture() (GPU texture created)" )
        c5.free()

        Console.println( "SimRDataTest PASS=" + passCount() + " FAIL=" + failCount() )
    }
}
