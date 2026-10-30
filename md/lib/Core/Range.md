# Range.sl

> 源文件：`Range.sl`

## class `Range<T:Num>`

- **接口**：IIterable&lt;T&gt;, IIterator&lt;T&gt;
- **说明**：SLang 标准库类型 Range<T:Num>（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `T _start = null` | 字段 _start（类型见签名）。 |
| 字段 | `T _end = null` | 字段 _end（类型见签名）。 |
| 字段 | `T _step = null` | 字段 _step（类型见签名）。 |
| 字段 | `T _iteratorValue = 0` | 字段 _iteratorValue（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 字段 | `Array&lt;T&gt; _toArrayCache = null` | 字段 _toArrayCache（类型见签名）。 |
| 构造 | `_init_(T _end)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(T _start, T _end)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(T _start, T _end, T _step)` | 构造方法，初始化本类型实例。 |
| 方法 | `void reset()` | 接口层 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 方法 | `bool isContain(T t)` | 判断状态是否（isContain）。 |
| 方法 | `T current()` | 迭代器 / 订阅控制（current）。 |
| 方法 | `IIterator&lt;T&gt; iterator()` | 迭代器 / 订阅控制（iterator）。 |
| 方法 | `Array&lt;T&gt; toArray()` | 将区间内所有值物化为 Array&lt;T&gt;：首次遍历写入缓存并复用，避免重复分配与迭代。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
