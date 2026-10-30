# 映射（键值对集合）契约：支持容量管理、增删与下标访问。
# 标准库 Map<TKey,TValue> 等字典容器实现此接口，m[key] 读写通过 _getItem_/_setItem_ 实现。
public interface IMap<T1, T2>
{
    # 构造：指定初始容量。
    _init_( int capacity );
    # 获取当前容量（内部数组长度）。
    get int capacity();
    # 设置容量。
    set void capacity( int value );
    # 确保容量至少达到 min，不足则扩容。
    void ensureCapacity( int min );
    # 添加键值对；key 已存在返回 false，否则插入并返回 true。
    public bool add( T1 key, T2 value );
    # 按键移除并返回其旧值；不存在返回 null。
    public T2 remove( T1 key );
    # 按下标移除实体（下标非法忽略）。
    public void removeAt( int index );
    # 清空所有键值对。
    public void clear();
    # m[key] 读取语义：不存在返回 null（Dart Map 语义）。
    T2 _getItem_( T1 key );
    # m[key] = value 写入语义：存在则更新 value，不存在则插入。
    void _setItem_( T1 key, T2 value );
}
