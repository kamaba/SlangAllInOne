# =========================================================================
# Std/RData/RTimeSeries.sl —— R ts（时间序列）风格容器
#
# 值 + 起点 + 采样频率；支持 lag / diff / window，预测数据的时间轴底座。
# 纯 SL，零原生依赖。
# =========================================================================

public class RData.RTimeSeries
{
    RVector _values = null
    Float32 _start = 0.0f
    Float32 _frequency = 1.0f

    public static RTimeSeries create( RVector values, Float32 start, Float32 frequency )
    {
        RTimeSeries t = new()
        t._values = values
        t._start = start
        if frequency > 0.0f { t._frequency = frequency }
        ret t
    }

    public static RTimeSeries fromList( List<Float32> values, Float32 start, Float32 frequency )
    {
        ret RTimeSeries.create( RVector.create( values ), start, frequency )
    }

    public Int32 length()
    {
        if this._values == null { ret 0 }
        ret this._values.length()
    }

    public Float32 at( Int32 index )
    {
        if this._values == null { ret 0.0f }
        ret this._values.at( index )
    }

    public Float32 start()
    {
        ret this._start
    }

    public Float32 frequency()
    {
        ret this._frequency
    }

    public Float32 timeAt( Int32 index )
    {
        ret this._start + SystemConvertFloat32( index ) / this._frequency
    }

    public RVector values()
    {
        if this._values == null { ret RVector.create( List<Float32>() ) }
        ret this._values
    }

    public RTimeSeries lag( Int32 k )
    {
        List<Float32> res = List<Float32>()
        Int32 i = 0
        while i < k && i < this.length()
        {
            res.add( 0.0f )
            i = i + 1
        }
        Int32 j = 0
        while j < this.length() - k
        {
            res.add( this.at( j ) )
            j = j + 1
        }
        ret RTimeSeries.create( RVector.create( res ), this._start, this._frequency )
    }

    public RTimeSeries diff()
    {
        ret RTimeSeries.create( this.values().diff(), this._start, this._frequency )
    }

    public RTimeSeries window( Int32 from, Int32 count )
    {
        RVector v = this.values().slice( from, count )
        Float32 st = this.timeAt( from )
        ret RTimeSeries.create( v, st, this._frequency )
    }
}
