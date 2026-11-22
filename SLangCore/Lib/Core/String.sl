public class String extends Object
{
    private String _value = null
    private Int32 _length = -1

    _init_( Int8 aa )
    {
        this._value = SystemConvertString( aa )
    }
    _init_( Int32 aa )
    {
        this._value = SystemConvertString( aa )
    }
    _init_( String aa )
    {
        this._value = aa
    }
    public string format( params object[] _parmas )
    {
        ret SystemStringFormat(this, _parmas)
    }

    public get int length()
    {
        # 直接走系统调用：字符串值在 VM 上是 scalar wrapper（无类字段布局），
        # 不能通过 this._length 字段访问缓存，否则字段读取失败返回空。
        ret SystemStringLength(this)
    }
    override String toString()
    {
        ret this;
    }
    public static string toFormat( string _format, params object[] _parmas )
    {
        ret SystemStringFormat(_format, _parmas)
    }

    # 截取前 index 个字符；index<=0 为空串；大于长度则整串
    string front( int index )
    {
        ret SystemStringFront( this, index )
    }

    # 截取末尾 index 个字符（从后往前数）
    string end( int index )
    {
        ret SystemStringEnd( this, index )
    }

    # 半开区间 [start, end)，等价 Substring(start, end - start)
    # 方法名 slice：range 是小写容器构造糖（range() => Range），类成员名须避让
    string slice( int start, int end )
    {
        ret SystemStringRange( this, start, end )
    }

    # UTF-8 字节序列，Array<Byte>（ByteArray）
    UInt8Array toUInt8Array()
    {
        ret SystemStringToUInt8Array( this )
    }

    # 按分隔符 sep 切割为 Array<string>（C99 层 strstr 实现，UTF-8 字节语义）。
    # 相邻分隔符产生空串元素；sep 为空串时返回 [整串] 单元素数组。
    # 典型用法：按行切割 "a\nb\n".split( "\n" ) → ["a","b",""]（尾空串）。
    Array<string> split( string sep )
    {
        ret SystemStringSplit( this, sep )
    }

    # 按行切割（\n 或 \r\n），尾行可为空串。split( "\n" ) 后逐元素剥掉
    # 尾部 \r（兼容 Windows 换行）。行数 = split 结果中的非尾行数。
    Array<string> splitLines()
    {
        Array<string> rows = SystemStringSplit( this, "\n" )
        Int32 n = rows.length
        Int32 last = n - 1
        Int32 i = 0
        while i < n
        {
            Int32 el = SystemStringLength( rows[i] )
            if i < last && el > 0 && SystemStringCharCodeAt( rows[i], el - 1 ) == 13
            {
                rows[i] = SystemStringRange( rows[i], 0, el - 1 )
            }
            i += 1
        }
        ret rows
    }

    # 下标读协议：返回第 index 个字符码（UTF-8 字节 0-255；越界 -1）。
    # 支持 s[i] 下标语法糖与显式 s._getItem_( i ) 两种调用。
    override Int32 _getItem_( int index )
    {
        ret SystemStringCharCodeAt( this, index )
    }

    # 下标写协议（编译器强制 void 签名）。注意：VM 字符串不可变（heap
    # block 多处共享）且 string 值是 scalar wrapper，协议调用无法把新串
    # 写回 this——因此 s[i] = code 语法对 string **不会生效**。真正的
    # 字符替换请用 setChar（返回新串）：s = s.setChar( index, code )。
    override void _setItem_( int index, int code )
    {
        SystemStringSetChar( this, index, code )
        ret
    }

    # 显式字符替换：返回把第 index 个字节替换为 code（0-255）后的**新串**，
    # 原串不变（C99 层 vm_sys_string_set_char 拷贝实现）。index/code 越界
    # 时原样返回。用法：s = s.setChar( 0, 65 )
    string setChar( int index, int code )
    {
        ret SystemStringSetChar( this, index, code )
    }
}