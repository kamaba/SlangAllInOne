# =========================================================================
# Std/RData/RTable.sl —— R data.frame 风格的列式数据表（CSV 入口）
#
# 复用 Core.BaseCsv / Std.IO.File 做解析与文件读取，本类只负责 R 风格
# 列式视图：数值列 → RVector，分类列 → RFactor。
# 注意：不保存嵌套泛型（List<List<string>> 会触发 Front 解析错误）；
# 原始 CSV 文本单独持有，分类列按需重新解析。
# 纯 SL，零新增原生依赖。
# =========================================================================

public class RData.RTable
{
    List<string> _names = null
    List<RVector> _cols = null
    string _text = ""

    public static RTable create( List<string> names )
    {
        RTable t = new()
        t._names = names
        t._cols = List<RVector>()
        Int32 i = 0
        while i < names.length
        {
            t._cols.add( RVector.create( List<Float32>() ) )
            i = i + 1
        }
        ret t
    }

    public static RTable fromCsvText( string text )
    {
        BaseCsv csv = BaseCsv.parse( text )
        Array<string> names = csv.table.columnNames()
        List<string> ns = List<string>()
        Int32 c = 0
        while c < names.length
        {
            ns.add( names._getItem_( c ) )
            c = c + 1
        }
        RTable t = RTable.create( ns )
        t._text = text
        t._cols = List<RVector>()
        c = 0
        while c < ns.length
        {
            List<Float32> nums = List<Float32>()
            Int32 r = 0
            while r < csv.rowCount
            {
                nums.add( SystemConvertFloat32( csv.table.getFloat( r, c, 0.0f ) ) )
                r = r + 1
            }
            t._cols.add( RVector.create( nums ) )
            c = c + 1
        }
        ret t
    }

    public static RTable fromCsvFile( string path )
    {
        string text = SystemFileReadAllText( path )
        ret RTable.fromCsvText( text )
    }

    public Int32 columnCount()
    {
        if this._names == null { ret 0 }
        ret this._names.length
    }

    public Int32 rowCount()
    {
        if this._cols == null || this._cols.length == 0 { ret 0 }
        RVector first = this._cols._getItem_( 0 )
        ret first.length()
    }

    public string nameAt( Int32 index )
    {
        if this._names == null { ret "" }
        if index < 0 || index >= this._names.length { ret "" }
        ret this._names._getItem_( index )
    }

    public Int32 columnIndex( string name )
    {
        Int32 i = 0
        while i < this.columnCount()
        {
            if this.nameAt( i ) == name { ret i }
            i = i + 1
        }
        ret -1
    }

    public bool has( string name )
    {
        ret this.columnIndex( name ) >= 0
    }

    public RVector column( Int32 index )
    {
        if this._cols == null { ret null }
        if index < 0 || index >= this._cols.length { ret null }
        ret this._cols._getItem_( index )
    }

    public RVector columnByName( string name )
    {
        ret this.column( this.columnIndex( name ) )
    }

    public string stringAt( Int32 col, Int32 row )
    {
        BaseCsv csv = BaseCsv.parse( this._text )
        if col < 0 || col >= csv.columnCount { ret "" }
        if row < 0 || row >= csv.rowCount { ret "" }
        ret csv.table.getStr( row, col, "" )
    }

    public List<string> stringsOf( Int32 col )
    {
        List<string> res = List<string>()
        BaseCsv csv = BaseCsv.parse( this._text )
        if col < 0 || col >= csv.columnCount { ret res }
        Int32 r = 0
        while r < csv.rowCount
        {
            res.add( csv.table.getStr( r, col, "" ) )
            r = r + 1
        }
        ret res
    }

    public RFactor factor( Int32 index )
    {
        ret RFactor.fromStrings( this.stringsOf( index ) )
    }

    public RFactor factorByName( string name )
    {
        ret this.factor( this.columnIndex( name ) )
    }

    public void setNumericColumn( Int32 index, RVector values )
    {
        if this._cols == null { ret }
        if index < 0 || index >= this._cols.length { ret }
        this._cols._setItem_( index, values )
    }

    public RTable head( Int32 count )
    {
        RTable res = RTable.create( this._names )
        res._text = this._text
        res._cols = List<RVector>()
        Int32 c = 0
        while c < this.columnCount()
        {
            RVector col = this.column( c )
            res._cols.add( col.slice( 0, count ) )
            c = c + 1
        }
        ret res
    }
}
