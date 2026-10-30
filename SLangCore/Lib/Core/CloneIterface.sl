# 克隆契约：实现该接口的类型可通过 clone() 返回自身的一个独立副本（深/浅拷贝语义由实现决定）。
public interface IClone
{
    # 返回当前对象的副本。
    public Object clone()    
}
# 泛型克隆契约：强类型 clone()，返回 T 的副本。
public interface IClone<T>
{
    public T clone()    
}

#!
public class Level<T> interface Core.IClone
{
    T _value = null
    public Level<T> clone()
    {
        Level<T> newclone = Level<T>()
        newclone._value = this._value
        ret newclone
    }
}
!#