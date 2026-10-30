# 列表（有序集合）契约：支持按索引增删、容量管理与转数组。
# 标准库 List<T> 等顺序容器均实现此接口，供泛型算法与遍历统一处理。
public interface IList<T>
{
    # 构造：指定初始容量。
    _init_( int capacity );
    # 获取当前容量（内部数组长度）。
    get int capacity();
    # 设置容量（小于元素数时以元素数为准）。
    set void capacity( int value );
    # 确保容量至少达到 min，不足则扩容。
    void ensureCapacity( int min );
    # 向末尾追加元素。
    public void add( T item );
    # 移除首个匹配的元素（按值比较）。
    public void remove( T item );
    # 按下标移除元素。
    public void removeAt( int index );
    # 清空所有元素。
    public void clear();
    # 将列表内容物化为 Array<T>（复制一份快照）。
    Array<T> toArray()
}
