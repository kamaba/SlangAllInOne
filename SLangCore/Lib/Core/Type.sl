# 元类：承载类型的命名空间与类名等元信息，供反射读取类型标识。
public class MetaClass
{
    string _namespaceName = "";
    string _className = "";

    get string className(){ ret this._className; }
}

# 类型对象：运行时类型的统一表示，封装底层类型枚举（eType）与元类（MetaClass），用于反射判断与类型信息读取。
public class Type extends Object
{
    byte _eType = 0
    MetaClass _metaClass = null
    public Type[] typelist = null
 
    #runtime accessors filled by RuntimeTypeManager.CreateTypeObject    
    get MetaClass metaClass() { ret this._metaClass; }
    get int eType() { ret this._eType.toInt32(); }

    override string toString()
    {
        if( this._metaClass == null )
        {
            ret "no_meta_class"
        }
        string str = this._metaClass.className;
        if this.typelist != null 
        {
            str = str + "<"
            for i = 0, i < this.typelist.length, i++ 
            {
                str = str + this.typelist[i].toString()
            }
            str = str + ">"
        }
        ret str
    }
}