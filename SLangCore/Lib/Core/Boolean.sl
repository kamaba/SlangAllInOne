# 布尔包装类型：将原始 bool 封装为对象，便于在需要 Object 的场合（集合、反射等）传递布尔值。
public class Boolean extends Object
{
    # 内部布尔值（true / false）。
    bool _value = false

    # 用给定布尔值构造包装对象。
    _init_( bool b )
    {
        this._value = b
    }
    # 返回 "True" 或 "False" 字符串表示。
    override string toString()
    {
        ret this._value ? "True" : "False"
    }
}
