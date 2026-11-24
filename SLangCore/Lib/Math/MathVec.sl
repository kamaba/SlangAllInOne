# MathVec —— R base 风格向量操作（Float64，纯 SL）
# 对应菜鸟教程 R 实例「向量操作」一栏：seq/rep/sort/order/rev/unique/
# which/match/append/cut/ifelse/table/计算最多次元素。
# 下标统一用 Int32；所有函数返回新 List，不修改入参。
public class MathVec
{
    public static List<Float64> seq( Float64 from, Float64 to, Float64 by )
    {
        List<Float64> r = List<Float64>()
        if by == 0.0d
        {
            ret r
        }
        Float64 x = from
        Int32 guard = 0
        if by > 0.0d
        {
            while x <= to && guard < 100000
            {
                r.add( x )
                x = x + by
                guard = guard + 1
            }
        }
        else
        {
            while x >= to && guard < 100000
            {
                r.add( x )
                x = x + by
                guard = guard + 1
            }
        }
        ret r
    }

    public static List<Float64> rep( Float64 value, Int32 times )
    {
        List<Float64> r = List<Float64>()
        Int32 i = 0
        while i < times
        {
            r.add( value )
            i = i + 1
        }
        ret r
    }

    public static List<Float64> sort( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Int32 i = 0
        while i < n
        {
            r.add( v._getItem_( i ) )
            i = i + 1
        }
        i = 0
        while i < n
        {
            Int32 j = 0
            while j < n - i - 1
            {
                Int32 nj = j + 1
                Float64 a = r._getItem_( j )
                Float64 b = r._getItem_( nj )
                if a > b
                {
                    r._setItem_( j, b )
                    r._setItem_( j + 1, a )
                }
                j = j + 1
            }
            i = i + 1
        }
        ret r
    }

    public static List<Int32> order( List<Float64> v )
    {
        List<Int32> r = List<Int32>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Int32 i = 0
        while i < n
        {
            r.add( i )
            i = i + 1
        }
        i = 0
        while i < n
        {
            Int32 j = 0
            while j < n - i - 1
            {
                Int32 nj = j + 1
                Int32 ia = r._getItem_( j )
                Int32 ib = r._getItem_( nj )
                if v._getItem_( ia ) > v._getItem_( ib )
                {
                    r._setItem_( j, ib )
                    r._setItem_( j + 1, ia )
                }
                j = j + 1
            }
            i = i + 1
        }
        ret r
    }

    public static List<Float64> rev( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 i = v.length - 1
        while i >= 0
        {
            r.add( v._getItem_( i ) )
            i = i - 1
        }
        ret r
    }

    public static List<Float64> unique( List<Float64> v )
    {
        List<Float64> r = List<Float64>()
        if v == null
        {
            ret r
        }
        Int32 n = v.length
        Int32 i = 0
        while i < n
        {
            Float64 x = v._getItem_( i )
            bool seen = false
            Int32 j = 0
            while j < r.length
            {
                if r._getItem_( j ) == x
                {
                    seen = true
                }
                j = j + 1
            }
            if !seen
            {
                r.add( x )
            }
            i = i + 1
        }
        ret r
    }

    public static List<Int32> whichEqual( List<Float64> v, Float64 value )
    {
        List<Int32> r = List<Int32>()
        if v == null
        {
            ret r
        }
        Int32 i = 0
        while i < v.length
        {
            if v._getItem_( i ) == value
            {
                r.add( i )
            }
            i = i + 1
        }
        ret r
    }

    public static List<Int32> whichGreater( List<Float64> v, Float64 value )
    {
        List<Int32> r = List<Int32>()
        if v == null
        {
            ret r
        }
        Int32 i = 0
        while i < v.length
        {
            if v._getItem_( i ) > value
            {
                r.add( i )
            }
            i = i + 1
        }
        ret r
    }

    public static Int32 matchIndex( Float64 value, List<Float64> table )
    {
        if table == null
        {
            ret 0 - 1
        }
        Int32 i = 0
        while i < table.length
        {
            if table._getItem_( i ) == value
            {
                ret i
            }
            i = i + 1
        }
        ret 0 - 1
    }

    public static List<Float64> append( List<Float64> v, Float64 value )
    {
        List<Float64> r = List<Float64>()
        if v != null
        {
            Int32 i = 0
            while i < v.length
            {
                r.add( v._getItem_( i ) )
                i = i + 1
            }
        }
        r.add( value )
        ret r
    }

    public static Int32 cutIndex( Float64 value, List<Float64> breaks )
    {
        if breaks == null || breaks.length < 2
        {
            ret 0 - 1
        }
        Int32 i = 0
        Int32 n = breaks.length
        while i < n - 1
        {
            Int32 ni = i + 1
            if value >= breaks._getItem_( i ) && value < breaks._getItem_( ni )
            {
                ret i
            }
            i = i + 1
        }
        ret 0 - 1
    }

    public static List<Float64> ifelse( List<Int32> cond, Float64 yes, Float64 no )
    {
        List<Float64> r = List<Float64>()
        if cond == null
        {
            ret r
        }
        Int32 i = 0
        while i < cond.length
        {
            if cond._getItem_( i ) != 0
            {
                r.add( yes )
            }
            else
            {
                r.add( no )
            }
            i = i + 1
        }
        ret r
    }

    # table(v)：按升序唯一值给出频数（与 sort(unique(v)) 对齐）
    public static List<Int32> tableCounts( List<Float64> v )
    {
        List<Int32> r = List<Int32>()
        List<Float64> uniq = MathVec.unique( v )
        List<Float64> keys = MathVec.sort( uniq )
        if keys == null
        {
            ret r
        }
        Int32 k = 0
        while k < keys.length
        {
            r.add( 0 )
            k = k + 1
        }
        if v == null
        {
            ret r
        }
        Int32 i = 0
        while i < v.length
        {
            Float64 x = v._getItem_( i )
            k = 0
            while k < keys.length
            {
                if keys._getItem_( k ) == x
                {
                    Int32 c = r._getItem_( k )
                    r._setItem_( k, c + 1 )
                }
                k = k + 1
            }
            i = i + 1
        }
        ret r
    }

    # 计算出现次数最多的元素；并列时取最小
    public static Float64 modeValue( List<Float64> v )
    {
        List<Float64> uniq = MathVec.unique( v )
        List<Float64> keys = MathVec.sort( uniq )
        if keys == null || keys.length == 0
        {
            ret 0.0d
        }
        List<Int32> counts = MathVec.tableCounts( v )
        Int32 best = 0
        Int32 i = 1
        while i < counts.length
        {
            if counts._getItem_( i ) > counts._getItem_( best )
            {
                best = i
            }
            i = i + 1
        }
        ret keys._getItem_( best )
    }
}
