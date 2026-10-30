# Container/LinkedList.sl

> 源文件：`Container/LinkedList.sl`

## class `LinkedList<T>`

- **说明**：SLang 标准库类型 LinkedList<T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public class Node` | ── Node 内部类：双向链表节点（参照 C# LinkedListNode&lt;T&gt;）── |
| 字段 | `Node _head = null` | ── 字段 ── |
| 字段 | `Node _tail = null` | 字段 _tail（类型见签名）。 |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 字段 | `int _index = -1` | 迭代器状态 |
| 字段 | `Node _iterNode = null` | 字段 _iterNode（类型见签名）。 |
| 方法 | `override _init_()` | ── 构造函数 ── |
| 属性 | `get int length()` | ── 属性 ── |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get T first()` | 首元素 / 末元素（空列表返回 null） |
| 属性 | `get T last()` | 获取 last 的值。 |
| 方法 | `void add(T item)` | ── 添加操作 ── 说明：SL 层只创建 Node（泛型实例化须在前端完成）， 遍历与 _prev/_next/_head/_tail/_count 指针手术全部在 C 系统调用中完成。 在末尾添加元素（与 List&lt;T&gt;.add 行为一致） |
| 方法 | `void addLast(T item)` | 在末尾添加元素 |
| 方法 | `void addFirst(T item)` | 在头部添加元素 |
| 方法 | `void addBefore(int index, T item)` | 在指定索引处之前插入新元素（越界 no-op；index==0 走头插） |
| 方法 | `void addAfter(int index, T item)` | 在指定索引处之后插入新元素（越界 no-op；index==末位走尾插） |
| 方法 | `void insert(int index, T item)` | 在指定索引处插入元素 |
| 方法 | `void remove(T item)` | ── 删除操作 ── 删除首个匹配元素 |
| 方法 | `void removeFirst()` | 删除首元素 |
| 方法 | `void removeLast()` | 删除末元素 |
| 方法 | `void removeAt(int index)` | 删除指定索引处的元素（就近端遍历定位，越界 no-op） |
| 方法 | `void clear()` | 清空列表 |
| 方法 | `int indexOf(T item)` | ── 查找操作 ── 查找元素首次出现的索引，未找到返回 -1 |
| 方法 | `int lastIndexOf(T item)` | 查找元素最后一次出现的索引，未找到返回 -1 |
| 方法 | `bool contains(T item)` | 是否包含指定元素 |
| 方法 | `T _getItem_(int index)` | ── 索引器 / 随机访问 ── 索引器：获取指定索引处的值（就近端遍历，越界返回 null） |
| 方法 | `void _setItem_(int index, T value)` | 索引器：设置指定索引处的值（就近端遍历，越界 no-op） |
| 方法 | `Array&lt;T&gt; toArray()` | ── 转换 ── 转换为数组（SL 层分配，C 端遍历填充） |
| 方法 | `string toString()` | 字符串表示 |
| 方法 | `void reset()` | ── IIterator / IIterable 接口实现 ── |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
