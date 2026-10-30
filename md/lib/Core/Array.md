# Array.sl

> 源文件：`Array.sl`

## class `Array<T>`

- **接口**：IIterable&lt;T&gt;, IIterator&lt;T&gt;
- **说明**：SLang 标准库类型 Array<T>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `int _length = 0` | 字段 _length（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `Array&lt;T&gt; create(int length)` | 初始化 / 创建（create）。 |
| 构造 | `_init_(int __len)` | 构造方法，初始化本类型实例。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `void fill(T value, int startIndex = 0, int count = -1)` | 执行 fill(value, 0, -1)，行为详见源实现。 |
| 方法 | `void reset()` | 接口层 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `set void current(T val)` | 设置 current 的值。 |
| 属性 | `get IIterator&lt;T&gt; iterator()` | 获取 iterator 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 属性 | `set void index(int ind)` | 设置 index 的值。 |
| 方法 | `void _setItem_(int __index, T val)` | 执行 _setItem_(__index, val)，行为详见源实现。 |
| 方法 | `T _getItem_(int __index)` | 执行 _getItem_(__index)，行为详见源实现。 |
| 方法 | `void forEach(Function callback)` | 迭代器 / 订阅控制（forEach）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
