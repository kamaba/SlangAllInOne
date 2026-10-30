# Container/IList.sl

> 源文件：`Container/IList.sl`

## interface `IList<T>`

- **接口**：IList&lt;T&gt;
- **说明**：列表（有序集合）契约：支持按索引增删、容量管理与转数组。 标准库 List<T> 等顺序容器均实现此接口，供泛型算法与遍历统一处理。

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_(int capacity)` | 构造：指定初始容量。 |
| 属性 | `get int capacity()` | 获取当前容量（内部数组长度）。 |
| 属性 | `set void capacity(int value)` | 设置容量（小于元素数时以元素数为准）。 |
| 方法 | `void ensureCapacity(int min)` | 确保容量至少达到 min，不足则扩容。 |
| 方法 | `void add(T item)` | 向末尾追加元素。 |
| 方法 | `void remove(T item)` | 移除首个匹配的元素（按值比较）。 |
| 方法 | `void removeAt(int index)` | 按下标移除元素。 |
| 方法 | `void clear()` | 清空所有元素。 |
| 方法 | `Array&lt;T&gt; toArray()` | 将列表内容物化为 Array&lt;T&gt;（复制一份快照）。 |
