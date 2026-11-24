# =========================================================================
# Std/RData/RFactor.sl —— R factor（分类变量：levels + 整数编码）
#
# 用于把 CSV 里的分类列映射成可统计、可画柱状图的离散数据结构。
# 纯 SL，零原生依赖。
# =========================================================================

public class RData.RFactor
{
    List<Int32> _codes = null
    List<string> _levels = null

    public static RFactor fromStrings( List<string> labels )
    {
        RFactor f = new()
        f._codes = List<Int32>()
        f._levels = List<string>()
        Int32 i = 0
        while i < labels.length
        {
            string lab = labels._getItem_( i )
            Int32 code = RFactor.indexOf( f._levels, lab )
            if code < 0
            {
                f._levels.add( lab )
                code = f._levels.length - 1
            }
            f._codes.add( code )
            i = i + 1
        }
        ret f
    }

    public static RFactor fromCodes( List<Int32> codes, List<string> levels )
    {
        RFactor f = new()
        f._codes = codes
        f._levels = levels
        ret f
    }

    static Int32 indexOf( List<string> list, string text )
    {
        Int32 i = 0
        while i < list.length
        {
            if list._getItem_( i ) == text { ret i }
            i = i + 1
        }
        ret -1
    }

    public Int32 length()
    {
        if this._codes == null { ret 0 }
        ret this._codes.length
    }

    public Int32 levelCount()
    {
        if this._levels == null { ret 0 }
        ret this._levels.length
    }

    public Int32 codeAt( Int32 index )
    {
        if this._codes == null { ret -1 }
        if index < 0 || index >= this._codes.length { ret -1 }
        ret this._codes._getItem_( index )
    }

    public string levelAt( Int32 index )
    {
        if this._levels == null { ret "" }
        if index < 0 || index >= this._levels.length { ret "" }
        ret this._levels._getItem_( index )
    }

    public string labelAt( Int32 index )
    {
        ret this.levelAt( this.codeAt( index ) )
    }

    public Int32 countOf( Int32 level )
    {
        Int32 n = 0
        Int32 i = 0
        while i < this.length()
        {
            if this.codeAt( i ) == level { n = n + 1 }
            i = i + 1
        }
        ret n
    }

    public List<Int32> counts()
    {
        List<Int32> res = List<Int32>()
        Int32 i = 0
        while i < this.levelCount()
        {
            res.add( this.countOf( i ) )
            i = i + 1
        }
        ret res
    }

    public List<string> levels()
    {
        List<string> res = List<string>()
        Int32 i = 0
        while i < this.levelCount()
        {
            res.add( this.levelAt( i ) )
            i = i + 1
        }
        ret res
    }
}
