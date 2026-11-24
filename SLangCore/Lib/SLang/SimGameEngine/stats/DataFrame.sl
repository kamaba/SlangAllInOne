# =========================================================================
# Stats/DataFrame.sl —— 列式数据表（R data.frame 等价物）+ 分组聚合
#
# 用法见 doc/02-Usage.md §2；实现说明见 doc/01-Design.md §5.2/§5.3。
# v0.1 约束：全部数值列（Float32）；分组键必为数值列；
#            CSV 首行表头、分隔符单字符、缺行丢弃。
# =========================================================================

import Core;
import Std;

namespace StatsPlot
{
    public class DataFrame
    {
        List<string> _names = null
        List<List<Float32>> _cols = null

        # ── 构造工厂 ───────────────────────────────────────
        # 跨模块调用限制：嵌套泛型（List<List<Float32>>）参数在模块引用
        # 边界 IR 链接不可解析（IRCallNotFoundIrRuntime），本方法及 fromRows
        # 仅限模块内部使用（table/summary/summarise 等）；消费方列式构造走
        # create + addColumn，或直接 fromCsv。
        public static DataFrame fromColumns( List<string> names, List<List<Float32>> cols )
        {
            DataFrame d = DataFrame()
            d._names = names
            d._cols = cols
            ret d
        }

        # 空表构造（带列名），配合 addColumn（列式构造，跨模块可用）
        public static DataFrame create( List<string> names )
        {
            DataFrame d = DataFrame()
            d._names = names
            Int32 n = names.length
            Int32 i = 0
            while i < n
            {
                d._cols.add( List<Float32>() )
                i = i + 1
            }
            ret d
        }

        public void addColumn( string name, List<Float32> values )
        {
            this._names.add( name )
            this._cols.add( values )
        }

        # 按行构造：rows 每行一条 List<Float32>（长度须等于 names.length）
        public static DataFrame fromRows( List<string> names, List<List<Float32>> rows )
        {
            Int32 nc = names.length
            List<List<Float32>> cols = List<List<Float32>>()
            Int32 c = 0
            while c < nc
            {
                List<Float32> col = List<Float32>()
                Int32 r = 0
                while r < rows.length
                {
                    List<Float32> row = rows._getItem_( r )
                    if c < row.length
                    {
                        col.add( row._getItem_( c ) )
                    }
                    r = r + 1
                }
                cols.add( col )
                c = c + 1
            }
            ret DataFrame.fromColumns( names, cols )
        }

        # CSV 文本构造（R read.csv）：首行表头；分隔符单字符，默认逗号
        public static DataFrame fromCsv( string text )
        {
            ret DataFrame.fromCsv( text, "," )
        }

        public static DataFrame fromCsv( string text, string sep )
        {
            Int32 sepCode = 44
            if sep != null && sep.length > 0
            {
                sepCode = SystemStringCharCodeAt( sep, 0 )
            }
            List<string> names = List<string>()
            List<List<Float32>> cols = List<List<Float32>>()
            List<Float32> cur = null
            Int32 len = 0
            if text != null
            {
                len = text.length
            }
            Int32 fieldStart = 0
            Int32 i = 0
            bool firstLineDone = false
            while i <= len
            {
                Int32 c = -1
                if i < len
                {
                    c = SystemStringCharCodeAt( text, i )
                }
                bool isEnd = ( i >= len )
                bool isNewline = ( c == 10 || c == 13 )   # \n / \r
                Int32 fieldEnd = i
                bool isFieldEnd = isEnd || isNewline || ( c == sepCode )
                if isFieldEnd
                {
                    string field = DataFrame._trimSlice( text, fieldStart, fieldEnd )
                    if !firstLineDone
                    {
                        names.add( field )
                    }
                    else
                    {
                        if cur == null
                        {
                            cur = List<Float32>()
                        }
                        if cur.length < names.length
                        {
                            cur.add( DataFrame._parseFloat( field ) )
                        }
                    }
                    fieldStart = i + 1
                }
                if isNewline && !isEnd
                {
                    if firstLineDone && cur != null && cur.length > 0 && cur.length >= names.length
                    {
                        cols.add( cur )
                    }
                    if c == 13 && i + 1 < len
                    {
                        if SystemStringCharCodeAt( text, i + 1 ) == 10
                        {
                            i = i + 1   # 跳过 \r\n 的 \n
                        }
                    }
                    if !firstLineDone
                    {
                        firstLineDone = true
                    }
                    cur = null
                    fieldStart = i + 1
                }
                i = i + 1
            }
            # 收尾：无换行结尾的最后一行
            if firstLineDone && cur != null && cur.length > 0 && cur.length >= names.length
            {
                cols.add( cur )
            }
            # 上面的 cols 是按行收集的（一行一列），用 fromRows 转置回列式
            ret DataFrame.fromRows( names, cols )
        }

        # 字符串字段裁剪（去首尾空白）
        static string _trimSlice( string text, Int32 start, Int32 end )
        {
            if text == null
            {
                ret ""
            }
            Int32 len = text.length
            Int32 s = start
            Int32 e = end
            if s < 0 { s = 0 }
            if e > len { e = len }
            if e < s { e = s }
            while s < e
            {
                Int32 cc = SystemStringCharCodeAt( text, s )
                if cc > 32 { break }
                s = s + 1
            }
            while e > s
            {
                Int32 cc = SystemStringCharCodeAt( text, e - 1 )
                if cc > 32 { break }
                e = e - 1
            }
            ret text.slice( s, e )
        }

        # ASCII 十进制浮点解析（C 层转换的双保险，本模块自实现）
        static Float32 _parseFloat( string s )
        {
            if s == null
            {
                ret 0.0f
            }
            Int32 len = s.length
            Int32 i = 0
            bool neg = false
            while i < len
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c == 45   # '-'
                {
                    neg = true
                }
                i = i + 1
            }
            Float32 v = 0.0f
            Float32 frac = 0.1f
            bool inFrac = false
            i = 0
            while i < len
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c == 46   # '.'
                {
                    inFrac = true
                }
                if c >= 48 && c <= 57
                {
                    if !inFrac
                    {
                        v = v * 10.0f + SystemConvertFloat32( c - 48 )
                    }
                    else
                    {
                        v = v + SystemConvertFloat32( c - 48 ) * frac
                        frac = frac * 0.1f
                    }
                }
                i = i + 1
            }
            if neg
            {
                v = 0.0f - v
            }
            ret v
        }

        # ── 读取 ───────────────────────────────────────────
        public List<string> names()
        {
            ret this._names
        }

        public string nameAt( Int32 i )
        {
            if this._names != null && i >= 0 && i < this._names.length
            {
                ret this._names._getItem_( i )
            }
            ret ""
        }

        public Int32 rowCount()
        {
            if this._cols == null || this._cols.length == 0
            {
                ret 0
            }
            ret this._cols._getItem_( 0 ).length
        }

        public Int32 colCount()
        {
            if this._cols == null
            {
                ret 0
            }
            ret this._cols.length
        }

        public bool has( string name )
        {
            Int32 n = this._names.length
            Int32 i = 0
            while i < n
            {
                if this._names._getItem_( i ) == name
                {
                    ret true
                }
                i = i + 1
            }
            ret false
        }

        public Int32 columnIndex( string name )
        {
            Int32 n = this._names.length
            Int32 i = 0
            while i < n
            {
                if this._names._getItem_( i ) == name
                {
                    ret i
                }
                i = i + 1
            }
            ret -1
        }

        public List<Float32> column( string name )
        {
            Int32 ci = this.columnIndex( name )
            if ci < 0
            {
                ret null
            }
            ret this._cols._getItem_( ci )
        }

        public List<Float32> columnAt( Int32 i )
        {
            if this._cols != null && i >= 0 && i < this._cols.length
            {
                ret this._cols._getItem_( i )
            }
            ret null
        }

        public List<Float32> rowValues( Int32 r )
        {
            List<Float32> row = List<Float32>()
            Int32 nc = this.colCount()
            Int32 c = 0
            while c < nc
            {
                List<Float32> col = this._cols._getItem_( c )
                if r < col.length
                {
                    row.add( col._getItem_( r ) )
                }
                c = c + 1
            }
            ret row
        }

        # ── 切片：head / tail（R head/tail，默认 6）────────────
        public DataFrame head( Int32 n )
        {
            ret DataFrame._rowsByIndex( this, 0, n, 1 )
        }

        public DataFrame tail( Int32 n )
        {
            Int32 rc = this.rowCount()
            Int32 start = rc - n
            if start < 0
            {
                start = 0
            }
            ret DataFrame._rowsByIndex( this, start, rc, 1 )
        }

        # 按连续行区间取子表（start..end 半开；step 恒 1）
        static DataFrame _rowsByIndex( DataFrame df, Int32 start, Int32 end, Int32 step )
        {
            Int32 rc = df.rowCount()
            if start < 0 { start = 0 }
            if end > rc { end = rc }
            if end < start { end = start }
            List<List<Float32>> cols = List<List<Float32>>()
            Int32 nc = df.colCount()
            Int32 c = 0
            while c < nc
            {
                List<Float32> src = df._cols._getItem_( c )
                List<Float32> col = List<Float32>()
                Int32 r = start
                while r < end
                {
                    col.add( src._getItem_( r ) )
                    r = r + step
                }
                cols.add( col )
                c = c + 1
            }
            DataFrame d = DataFrame()
            d._names = df._names
            d._cols = cols
            ret d
        }

        # ── 筛选 / 排序 ─────────────────────────────────────
        # 逻辑下标筛选（R df._getItem_( which, )）：which 与行数等长
        public DataFrame filter( List<bool> which )
        {
            List<List<Float32>> cols = List<List<Float32>>()
            Int32 nc = this.colCount()
            Int32 c = 0
            while c < nc
            {
                List<Float32> src = this._cols._getItem_( c )
                List<Float32> col = List<Float32>()
                Int32 r = 0
                while r < which.length
                {
                    if which._getItem_( r )
                    {
                        if r < src.length
                        {
                            col.add( src._getItem_( r ) )
                        }
                    }
                    r = r + 1
                }
                cols.add( col )
                c = c + 1
            }
            DataFrame d = DataFrame()
            d._names = this._names
            d._cols = cols
            ret d
        }

        # 按列排序（R df._getItem_( order(df$x), )）
        public DataFrame sortBy( string name, bool desc )
        {
            List<Float32> key = this.column( name )
            if key == null
            {
                ret this
            }
            List<Int32> order = Stats.order( key, desc )
            List<List<Float32>> cols = List<List<Float32>>()
            Int32 nc = this.colCount()
            Int32 c = 0
            while c < nc
            {
                List<Float32> src = this._cols._getItem_( c )
                List<Float32> col = List<Float32>()
                Int32 r = 0
                while r < order.length
                {
                    col.add( src._getItem_( order._getItem_( r ) ) )
                    r = r + 1
                }
                cols.add( col )
                c = c + 1
            }
            DataFrame d = DataFrame()
            d._names = this._names
            d._cols = cols
            ret d
        }

        # ── 描述统计（R summary；行序 min/q1/median/mean/q3/max）──
        public List<string> summaryLabels()
        {
            List<string> ls = List<string>()
            ls.add( "min" )
            ls.add( "q1" )
            ls.add( "median" )
            ls.add( "mean" )
            ls.add( "q3" )
            ls.add( "max" )
            ret ls
        }

        public DataFrame summary()
        {
            List<string> names = List<string>()
            List<List<Float32>> cols = List<List<Float32>>()
            Int32 nc = this.colCount()
            Int32 c = 0
            while c < nc
            {
                List<Float32> v = this._cols._getItem_( c )
                List<Float32> st = List<Float32>()
                st.add( Stats.minValue( v ) )
                st.add( Stats.quantile( v, 0.25f ) )
                st.add( Stats.median( v ) )
                st.add( Stats.mean( v ) )
                st.add( Stats.quantile( v, 0.75f ) )
                st.add( Stats.maxValue( v ) )
                cols.add( st )
                names.add( this._names._getItem_( c ) )
                c = c + 1
            }
            ret DataFrame.fromColumns( names, cols )
        }

        # ── 分组 / 频数 ─────────────────────────────────────
        # 按数值列分组（R split / aggregate；键按出现顺序）
        public StatsGroup groupBy( string name )
        {
            List<Float32> key = this.column( name )
            if key == null
            {
                ret null
            }
            ret StatsGroup._create( this, this.columnIndex( name ), key )
        }

        # 频数表（R table；直接调 Stats.table）
        public DataFrame tableOf( string name )
        {
            List<Float32> v = this.column( name )
            if v == null
            {
                ret null
            }
            ret Stats.table( v )
        }

        # ── 内部 ───────────────────────────────────────────
        _init_()
        {
            this._names = List<string>()
            this._cols = List<List<Float32>>()
        }
    }

    # =====================================================================
    # StatsGroup —— 分组聚合（R aggregate / dplyr group_by %>% summarise）
    # =====================================================================
    public class StatsGroup
    {
        DataFrame _df = null
        Int32 _keyCol = 0
        List<Float32> _keys = null
        List<List<Int32>> _members = null

        # 构造：按 key 列把行索引分组（键按出现顺序去重）
        static StatsGroup _create( DataFrame df, Int32 keyCol, List<Float32> key )
        {
            StatsGroup g = StatsGroup()
            g._df = df
            g._keyCol = keyCol
            g._keys = List<Float32>()
            g._members = List<List<Int32>>()
            Int32 n = key.length
            Int32 i = 0
            while i < n
            {
                Float32 kv = key._getItem_( i )
                Int32 gi = -1
                Int32 k = 0
                while k < g._keys.length
                {
                    if g._keys._getItem_( k ) == kv
                    {
                        gi = k
                    }
                    k = k + 1
                }
                if gi < 0
                {
                    g._keys.add( kv )
                    List<Int32> grp = List<Int32>()
                    grp.add( i )
                    g._members.add( grp )
                }
                else
                {
                    g._members._getItem_( gi ).add( i )
                }
                i = i + 1
            }
            ret g
        }

        public Int32 keyCount()
        {
            if this._keys == null
            {
                ret 0
            }
            ret this._keys.length
        }

        public Float32 keyAt( Int32 ki )
        {
            if ki >= 0 && ki < this._keys.length
            {
                ret this._keys._getItem_( ki )
            }
            ret 0.0f
        }

        public Int32 sizeOf( Int32 ki )
        {
            if ki >= 0 && ki < this._members.length
            {
                ret this._members._getItem_( ki ).length
            }
            ret 0
        }

        # ── 组内聚合原语（R aggregate FUN）──────────────────
        List<Float32> _valuesOf( Int32 ki, string colName )
        {
            List<Float32> vals = List<Float32>()
            Int32 ci = this._df.columnIndex( colName )
            if ci < 0
            {
                ret vals
            }
            List<Float32> src = this._df._cols._getItem_( ci )
            Int32 m = this._members._getItem_( ki ).length
            Int32 j = 0
            while j < m
            {
                Int32 row = this._members._getItem_( ki )._getItem_( j )
                if row < src.length
                {
                    vals.add( src._getItem_( row ) )
                }
                j = j + 1
            }
            ret vals
        }

        public Float32 sum( Int32 ki, string colName )
        {
            ret Stats.sum( this._valuesOf( ki, colName ) )
        }

        public Float32 mean( Int32 ki, string colName )
        {
            ret Stats.mean( this._valuesOf( ki, colName ) )
        }

        public Float32 minValue( Int32 ki, string colName )
        {
            ret Stats.minValue( this._valuesOf( ki, colName ) )
        }

        public Float32 maxValue( Int32 ki, string colName )
        {
            ret Stats.maxValue( this._valuesOf( ki, colName ) )
        }

        public Float32 median( Int32 ki, string colName )
        {
            ret Stats.median( this._valuesOf( ki, colName ) )
        }

        public Float32 sd( Int32 ki, string colName )
        {
            ret Stats.sd( this._valuesOf( ki, colName ) )
        }

        public Int32 countOf( Int32 ki )
        {
            ret this.sizeOf( ki )
        }

        # ── 一键聚合（R aggregate；func ∈ count/sum/mean/min/max/median/sd）
        # 返回 DataFrame：列 "group"（键值）+ "<func>"（结果）
        public DataFrame summarise( string valueCol, string func )
        {
            List<string> names = List<string>()
            names.add( "group" )
            names.add( func )
            List<Float32> ks = List<Float32>()
            List<Float32> rs = List<Float32>()
            Int32 kc = this.keyCount()
            Int32 ki = 0
            while ki < kc
            {
                ks.add( this.keyAt( ki ) )
                Float32 r = 0.0f
                if func == "count"
                {
                    r = SystemConvertFloat32( this.countOf( ki ) )
                }
                if func == "sum"
                {
                    r = this.sum( ki, valueCol )
                }
                if func == "mean"
                {
                    r = this.mean( ki, valueCol )
                }
                if func == "min"
                {
                    r = this.minValue( ki, valueCol )
                }
                if func == "max"
                {
                    r = this.maxValue( ki, valueCol )
                }
                if func == "median"
                {
                    r = this.median( ki, valueCol )
                }
                if func == "sd"
                {
                    r = this.sd( ki, valueCol )
                }
                rs.add( r )
                ki = ki + 1
            }
            List<List<Float32>> cols = List<List<Float32>>()
            cols.add( ks )
            cols.add( rs )
            ret DataFrame.fromColumns( names, cols )
        }
    }
}