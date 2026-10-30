# 数据聚合抽象基类：将一组命名字段聚合成结构化 data 对象（类似 JSON 对象），可序列化为 JSON（toJson / toJsonPretty），是 SLang 结构化数据的根类型。
public abstract class Data extends object
{
    override String toString()
    { 
        ret SystemBuildDataString( this )
    }

    #将 data 实例序列化为紧凑 JSON 文本：data 成员内置递归展开为对象，
    #class 成员虚调其 toJson() 嫁接子树，enum 成员取底层值，
    #array/list/set/tuple 转数组、map 转对象（规则详见 md/syntax/data.md）。
    public String toJson()
    {
        TreeNode<string> proto = TreeNode<string>()
        ret SystemDataToJson( this, proto, false )
    }

    #toJson 的 2 空格缩进格式化版本。
    public String toJsonPretty()
    {
        TreeNode<string> proto = TreeNode<string>()
        ret SystemDataToJson( this, proto, true )
    }
}