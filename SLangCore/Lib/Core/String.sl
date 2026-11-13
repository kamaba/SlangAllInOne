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

    # 2026-11-13：Front params 打包修复后（IRCall packN），params 版恢复工作；
    # 1..6 元素定参重载保留（紧邻 params 版，避免虚表序扰动其它方法）。
    public string format( object p1 )
    {
        Array<object> arr = Array<object>( 1 )
        SystemArraySetValueThis( arr, 0, p1 )
        ret SystemStringFormat(this, arr)
    }

    public string format( object p1, object p2 )
    {
        Array<object> arr = Array<object>( 2 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        ret SystemStringFormat(this, arr)
    }

    public string format( object p1, object p2, object p3 )
    {
        Array<object> arr = Array<object>( 3 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        ret SystemStringFormat(this, arr)
    }

    public string format( object p1, object p2, object p3, object p4 )
    {
        Array<object> arr = Array<object>( 4 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        ret SystemStringFormat(this, arr)
    }

    public string format( object p1, object p2, object p3, object p4, object p5 )
    {
        Array<object> arr = Array<object>( 5 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        SystemArraySetValueThis( arr, 4, p5 )
        ret SystemStringFormat(this, arr)
    }

    public string format( object p1, object p2, object p3, object p4, object p5, object p6 )
    {
        Array<object> arr = Array<object>( 6 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        SystemArraySetValueThis( arr, 4, p5 )
        SystemArraySetValueThis( arr, 5, p6 )
        ret SystemStringFormat(this, arr)
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

    public static string toFormat( string _format, object p1 )
    {
        Array<object> arr = Array<object>( 1 )
        SystemArraySetValueThis( arr, 0, p1 )
        ret SystemStringFormat(_format, arr)
    }

    public static string toFormat( string _format, object p1, object p2 )
    {
        Array<object> arr = Array<object>( 2 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        ret SystemStringFormat(_format, arr)
    }

    public static string toFormat( string _format, object p1, object p2, object p3 )
    {
        Array<object> arr = Array<object>( 3 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        ret SystemStringFormat(_format, arr)
    }

    public static string toFormat( string _format, object p1, object p2, object p3, object p4 )
    {
        Array<object> arr = Array<object>( 4 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        ret SystemStringFormat(_format, arr)
    }

    public static string toFormat( string _format, object p1, object p2, object p3, object p4, object p5 )
    {
        Array<object> arr = Array<object>( 5 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        SystemArraySetValueThis( arr, 4, p5 )
        ret SystemStringFormat(_format, arr)
    }

    public static string toFormat( string _format, object p1, object p2, object p3, object p4, object p5, object p6 )
    {
        Array<object> arr = Array<object>( 6 )
        SystemArraySetValueThis( arr, 0, p1 )
        SystemArraySetValueThis( arr, 1, p2 )
        SystemArraySetValueThis( arr, 2, p3 )
        SystemArraySetValueThis( arr, 3, p4 )
        SystemArraySetValueThis( arr, 4, p5 )
        SystemArraySetValueThis( arr, 5, p6 )
        ret SystemStringFormat(_format, arr)
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
}