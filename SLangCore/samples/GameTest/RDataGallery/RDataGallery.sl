import Std;
import SimGameEngine;

# RDataGallery —— 6 视图：Std.RData 五类结构经由 RDataChart 生成图表，
# 最后一格演示同一 DrawCanvas 同时产出 RenderTexture（GPU）与像素指针（QT）。
public class RDataGallery
{
    static void blit( Int32 idx, string caption, DrawCanvas c )
    {
        RDataHost.show( idx, caption, c.pixelPtr(), c.width(), c.height() )
        c.free()
    }

    static List<Float32> nums()
    {
        List<Float32> v = List<Float32>()
        v.add( 2.0f )
        v.add( 5.0f )
        v.add( 3.0f )
        v.add( 8.0f )
        v.add( 6.0f )
        v.add( 9.0f )
        ret v
    }

    public static void run()
    {
        SLang.Render.initialize()
        RDataHost.build()

        # [0] RVector → 折线/点图
        RData.RVector vec = RData.RVector.create( RDataGallery.nums() )
        List<Float32> vv = vec.values()
        DrawCanvas c0 = RDataChart.plotVector( vv, "RVector (named)" )
        RDataGallery.blit( 0, "[0] Std.RData.RVector -> plotVector", c0 )

        # [1] RFactor → 条形图（CSV 分类列）
        string csv = "city,sales,profit\n1,10,2.5\n2,20,3.0\n1,15,4.5\n2,12,3.6\n1,18,4.0\n2,22,5.1\n"
        RData.RTable table = RData.RTable.fromCsvText( csv )
        RData.RFactor fac = table.factorByName( "city" )
        List<Float32> cnt = List<Float32>()
        List<Int32> raw = fac.counts()
        Int32 ci = 0
        while ci < raw.length
        {
            cnt.add( SystemConvertFloat32( raw._getItem_( ci ) ) )
            ci = ci + 1
        }
        DrawCanvas c1 = RDataChart.barFactor( cnt, fac.levels(), "city factor" )
        RDataGallery.blit( 1, "[1] Std.RData.RFactor -> barFactor", c1 )

        # [2] RTimeSeries → 折线图
        RData.RTimeSeries ts = RData.RTimeSeries.fromList( RDataGallery.nums(), 2024.0f, 4.0f )
        List<Float32> tsv = ts.values()
        DrawCanvas c2 = RDataChart.plotSeries( tsv, ts.start(), ts.frequency(), "quarterly series" )
        RDataGallery.blit( 2, "[2] Std.RData.RTimeSeries -> plotSeries", c2 )

        # [3] RTable 数值列 → 图表
        RData.RVector sales = table.columnByName( "sales" )
        List<Float32> salesVals = sales.values()
        DrawCanvas c3 = RDataChart.plotCsvColumn( salesVals, "sales", "csv column" )
        RDataGallery.blit( 3, "[3] Std.RData.RTable -> plotCsvColumn", c3 )

        # [4] RForecast → 置信带预测图
        List<Float32> mu = RDataGallery.nums()
        List<Float32> lo = List<Float32>()
        List<Float32> hi = List<Float32>()
        Int32 i = 0
        while i < mu.length
        {
            Float32 m = mu._getItem_( i )
            lo.add( m - 1.5f )
            hi.add( m + 1.5f )
            i = i + 1
        }
        RData.RForecast fc = RData.RForecast.fromLists( mu, lo, hi )
        List<Float32> fm = fc.meanValues()
        List<Float32> fl = fc.lowerValues()
        List<Float32> fu = fc.upperValues()
        DrawCanvas c4 = RDataChart.plotForecast( fm, fl, fu, "forecast with 80% band" )
        RDataGallery.blit( 4, "[4] Std.RData.RForecast -> plotForecast", c4 )

        # [5] 同一画布 → RenderTexture（GPU）+ 同一像素块 → QLabel（QT 回绘）
        DrawCanvas c5 = RDataChart.plotForecast( fm, fl, fu, "same canvas: texture + QLabel" )
        var tex = c5.toTexture()
        string rtState = "RenderTexture: unavailable in this backend"
        if tex != null
        {
            rtState = "RenderTexture: created (GPU handle ready); pixels blitted to QLabel below"
        }
        RDataGallery.blit( 5, "[5] DrawCanvas.toTexture() + QLabel blit", c5 )
        RDataHost.setTitle( rtState + " | close window to exit" )
        Console.println( "RDataGallery: 6 views rendered. " + rtState )
        RDataHost.exec()
    }
}
