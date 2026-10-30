# Container/List.sl

> 源文件：`Container/List.sl`

## class `List<T>`

- **说明**：SLang 标准库类型 List<T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `int _length = 0` | 字段 _length（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 字段 | `Array&lt;T&gt; _list = null` | 字段 _list（类型见签名）。 |
| 方法 | `List&lt;T&gt; create(int capacity)` | 初始化 / 创建（create）。 |
| 方法 | `override _init_()` | 默认构造，容量为0，首次添加时扩容为4（与 C# List&lt;T&gt; 一致） |
| 方法 | `void _init_(Array&lt;T&gt; list)` | 从数组构造：SystemArrayCopy 系统级拷贝全部元素（生成新数组，不与源数组共享存储） |
| 方法 | `void _init_(Array&lt;T&gt; list, int startIndex, int length)` | 从数组区间构造：拷贝 [startIndex, startIndex+length) 的元素，越界自动截断 |
| 方法 | `void _init_(Range&lt;T&gt; range)` | 从 Range 构造：Range.toArray() 系统级物化区间为数组，再 SystemArrayCopy 拷贝持有 （不直接持有 Range 内部缓存数组，避免后续 add/insert 污染 Range） |
| 方法 | `void _init_(int capacity)` | 执行 _init_(capacity)，行为详见源实现。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 属性 | `get bool isEmpty()` | 是否为空 / 是否非空 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get T first()` | 首元素 / 末元素（空列表返回 null） |
| 属性 | `get T last()` | 获取 last 的值。 |
| 属性 | `get int capacity()` | 容量（内部存储长度） |
| 属性 | `set void capacity(int value)` | 设置 capacity 的值。 |
| 方法 | `void grow()` | 容量扩展：0-&gt;4，之后倍增 4-&gt;8-&gt;16...（与 C# List&lt;T&gt; 一致） |
| 方法 | `void ensureCapacity(int min)` | 执行 ensureCapacity(min)，行为详见源实现。 |
| 方法 | `void resizeArray(int newCapacity)` | 内部方法：重新分配 _list Array 并拷贝已有元素 |
| 方法 | `void add(T item)` | 添加 / 插入元素（add）。 |
| 方法 | `void insert(int index, T item)` | 添加 / 插入元素（insert）。 |
| 方法 | `void remove(T item)` | 移除 / 删除元素（remove）。 |
| 方法 | `void removeAt(int index)` | 执行 removeAt(index)，行为详见源实现。 |
| 方法 | `void clear()` | 执行 clear()。 |
| 方法 | `int indexOf(T item)` | 查找元素首次出现的位置，未找到返回 -1（== 为值比较：数值/字符串/布尔按值，类按 equals 语义） |
| 方法 | `int lastIndexOf(T item)` | 查找元素最后一次出现的位置，未找到返回 -1 |
| 方法 | `bool contains(T item)` | 是否包含指定元素 |
| 方法 | `void fill(T value, int startIndex = 0, int count = 0)` | count 默认值取 0（类型零值）：跨模块调用时省略参数由 VM 做零值填充（导入函数无默认表达式）， 因此默认值必须与零值一致，否则 ListTest 等外部模块省参调用会得到 0 而非 -1。 |
| 方法 | `void addRange(List&lt;T&gt; other)` | 批量追加另一个列表的全部元素（other 为 null 时忽略） |
| 方法 | `void insertRange(int index, List&lt;T&gt; other)` | 在 index 处批量插入另一个列表的全部元素 |
| 方法 | `void removeRange(int index, int count)` | 移除 [index, index+count) 区间的元素，越界部分自动截断 |
| 方法 | `void reverse()` | 原地反转元素顺序 |
| 方法 | `List&lt;T&gt; getRange(int index, int count)` | 拷贝 [index, index+count) 区间为新列表（越界自动截断；index 非法返回 null） |
| 方法 | `Array&lt;T&gt; toArray()` | 转换 / 序列化 / 格式化（toArray）。 |
| 方法 | `void reset()` | 接口层 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `set void current(T val)` | 设置 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 属性 | `set void index(int ind)` | 设置 index 的值。 |
| 方法 | `void _setItem_(int _index, T _value)` | 执行 _setItem_(_index, _value)，行为详见源实现。 |
| 方法 | `T _getItem_(int _index)` | 执行 _getItem_(_index)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
