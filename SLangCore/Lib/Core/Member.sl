# 反射 / 解构成员描述：携带名称、下标与值的轻量记录结构。
# 用于元组解构、反射取值等场景，把“某个具名/具下标的槽位及其当前值”打包成一个对象。
public class Member extends Object
{
    # 成员名称（无名时为 ""）。
    public string name = "";
    # 成员下标（无下标语义时为 -1）。
    public int index = -1;
    # 成员当前值（无值时为 null）。
    public object value = null;
    # 默认构造。
    override void _init_()
    {
    }
    # 返回 Member{name=..., index=..., value=...} 形式的可读字符串。
    public override string toString()
    {
        string nameText = this.name == null ? "" : this.name
        string indexText = this.index.toString()
        string valueText = this.value == null ? "null" : this.value.toString()
        ret "Member{name=" + nameText + ", index=" + indexText + ", value=" + valueText + "}"
    }
}
