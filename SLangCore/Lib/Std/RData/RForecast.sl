# =========================================================================
# Std/RData/RForecast.sl —— 预测结果容器（点预测 + 上下置信区间）
#
# 对齐 R forecast 包 / 常见 ML 回归输出：mean / lower / upper 三条等长
# 序列，可算残差、可直接被引擎映射成带置信带的 chart。
# 纯 SL，零原生依赖。
# =========================================================================

public class RData.RForecast
{
    RVector _mean = null
    RVector _lower = null
    RVector _upper = null

    public static RForecast create( RVector mean, RVector lower, RVector upper )
    {
        RForecast f = new()
        f._mean = mean
        f._lower = lower
        f._upper = upper
        ret f
    }

    public static RForecast fromLists( List<Float32> mean, List<Float32> lower, List<Float32> upper )
    {
        ret RForecast.create( RVector.create( mean ), RVector.create( lower ), RVector.create( upper ) )
    }

    public Int32 count()
    {
        if this._mean == null { ret 0 }
        ret this._mean.length()
    }

    public Float32 meanAt( Int32 index )
    {
        if this._mean == null { ret 0.0f }
        ret this._mean.at( index )
    }

    public Float32 lowerAt( Int32 index )
    {
        if this._lower == null { ret 0.0f }
        ret this._lower.at( index )
    }

    public Float32 upperAt( Int32 index )
    {
        if this._upper == null { ret 0.0f }
        ret this._upper.at( index )
    }

    public RVector meanValues()
    {
        if this._mean == null { ret RVector.create( List<Float32>() ) }
        ret this._mean
    }

    public RVector lowerValues()
    {
        if this._lower == null { ret RVector.create( List<Float32>() ) }
        ret this._lower
    }

    public RVector upperValues()
    {
        if this._upper == null { ret RVector.create( List<Float32>() ) }
        ret this._upper
    }

    public RVector residuals( RTimeSeries actual )
    {
        List<Float32> res = List<Float32>()
        Int32 n = this.count()
        if actual.length() < n { n = actual.length() }
        Int32 i = 0
        while i < n
        {
            res.add( actual.at( i ) - this.meanAt( i ) )
            i = i + 1
        }
        ret RVector.create( res )
    }

    public Float32 coverageWidth( Int32 index )
    {
        ret this.upperAt( index ) - this.lowerAt( index )
    }
}
