
# 配置格式基类（模板方法骨架）：以 JSON 字符串为输入构造，提供空实现的初始化 / 序列化方法，
# 供具体配置格式（如 TOML / YAML 等）派生并重写其解析与 toString 逻辑。
public class ConfitFormat
{
    override _init_()
    {
        
    }    
    void _init_( string jsonstr )
    {
        
    }

    
    override string toString()
    {
        
    }
}