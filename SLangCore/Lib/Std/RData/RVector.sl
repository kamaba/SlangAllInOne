# =========================================================================
# Std/RData/RVector.sl —— R 风格数值向量（统计数据结构地基）
#
# 定位：给统计数据/预测数据提供统一的数值序列载体，带名称与 NA（缺失）
# 语义；供 RTable / RTimeSeries / RForecast 复用，供 GameEngine 映射成图表。
# 纯 SL，零原生依赖。约定：NA 位置的值读出来为 0，但 isNA() 可判别。
# =========================================================================

public class RData.RVector
{
    List<Float32> _values = null
    List<string> _names = null
    List<Int32> _na = null

    public static RVector create( List<Float32> values )
    {
        RVector r = new()
        r._values = values
        r._na = List<Int32>()
        Int32 i = 0
        while i < values.length
        {
            r._na.add( 0 )
            i = i + 1
        }
        ret r
    }

    public static RVector createNamed( List<Float32> values, List<string> names )
    {
        RVector r = RVector.create( values )
        r._names = names
        ret r
    }

    public static RVector fromCsvColumn( string csvText, string columnName )
    {
        BaseCsv csv = BaseCsv.parse( csvText )
        Int32 col = csv.table.getColumnIndex( columnName )
        List<Float32> vals = List<Float32>()
        List<string> names = List<string>()
        Int32 row = 0
        while row < csv.rowCount
        {
            vals.add( SystemConvertFloat32( csv.table.getFloatByName( row, columnName, 0.0f ) ) )
            names.add( csv.table.getStr( row, col ) )
            row = row + 1
        }
        ret RVector.createNamed( vals, names )
    }

    public Int32 length()
    {
        if this._values == null { ret 0 }
        ret this._values.length
    }

    public Float32 at( Int32 index )
    {
        if this._values == null { ret 0.0f }
        if index < 0 || index >= this._values.length { ret 0.0f }
        if this.isNA( index ) { ret 0.0f }
        ret this._values._getItem_( index )
    }

    public bool isNA( Int32 index )
    {
        if this._na == null { ret false }
        if index < 0 || index >= this._na.length { ret true }
        ret this._na._getItem_( index ) != 0
    }

    public void setNA( Int32 index, bool on )
    {
        if this._na == null { ret }
        if index < 0 || index >= this._na.length { ret }
        if on { this._na._setItem_( index, 1 ) }
        else { this._na._setItem_( index, 0 ) }
    }

    public Int32 countNA()
    {
        Int32 n = 0
        Int32 i = 0
        while i < this.length()
        {
            if this.isNA( i ) { n = n + 1 }
            i = i + 1
        }
        ret n
    }

    public string nameAt( Int32 index )
    {
        if this._names == null { ret "" }
        if index < 0 || index >= this._names.length { ret "" }
        ret this._names._getItem_( index )
    }

    public bool hasNames()
    {
        ret this._names != null
    }

    public get inline List<Float32> values()
    {
       ret this._values
    }

    public RVector slice( Int32 from, Int32 count )
    {
        List<Float32> res = List<Float32>()
        Int32 i = from
        Int32 end = from + count
        if end > this.length() { end = this.length() }
        while i < end
        {
            res.add( this.at( i ) )
            i = i + 1
        }
        ret RVector.create( res )
    }

    public RVector diff()
    {
        List<Float32> res = List<Float32>()
        Int32 i = 1
        while i < this.length()
        {
            res.add( this.at( i ) - this.at( i - 1 ) )
            i = i + 1
        }
        ret RVector.create( res )
    }

    public Float32 sum()
    {
        Float32 r = 0.0f
        Int32 i = 0
        while i < this.length()
        {
            if !this.isNA( i ) { r = r + this.at( i ) }
            i = i + 1
        }
        ret r
    }

    public Float32 mean()
    {
        Int32 n = this.length() - this.countNA()
        if n <= 0 { ret 0.0f }
        ret this.sum() / SystemConvertFloat32( n )
    }

    public Float32 minValue()
    {
        Int32 n = this.length()
        if n <= 0 { ret 0.0f }
        Float32 r = this.at( 0 )
        Int32 i = 1
        while i < n
        {
            if !this.isNA( i )
            {
                Float32 v = this.at( i )
                if v < r { r = v }
            }
            i = i + 1
        }
        ret r
    }

    public Float32 maxValue()
    {
        Int32 n = this.length()
        if n <= 0 { ret 0.0f }
        Float32 r = this.at( 0 )
        Int32 i = 1
        while i < n
        {
            if !this.isNA( i )
            {
                Float32 v = this.at( i )
                if v > r { r = v }
            }
            i = i + 1
        }
        ret r
    }
}
