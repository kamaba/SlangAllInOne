# IterateVariable.sl

> 源文件：`IterateVariable.sl`

## class `Iterater`

- **接口**：IIterator
- **说明**：迭代器适配器：包装任意 IIterable 提供一个带 index / value 的游标式迭代器（foreach 底层常用），支持复位、前进与取值。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public _index = 0` | 字段 _index（类型见签名）。 |
| 字段 | `IIterator _iterator = null` | 字段 _iterator（类型见签名）。 |
| 构造 | `_init_(IIterable __it)` | 构造方法，初始化本类型实例。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 属性 | `get object value()` | 获取 value 的值。 |
| 方法 | `void reset()` | 迭代器 / 订阅控制（reset）。 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get object current()` | 获取 current 的值。 |
| 方法 | `void release()` | 执行 release()。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Iterater<T>`

- **接口**：IIterator&lt;T&gt;
- **说明**：泛型迭代器适配器：强类型版 Iterater，包装 IIterable<T> 提供带 index / value 的游标式迭代。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public _index = 0` | 字段 _index（类型见签名）。 |
| 字段 | `T _value = null` | 字段 _value（类型见签名）。 |
| 字段 | `IIterator&lt;T&gt; _iterator = null` | 字段 _iterator（类型见签名）。 |
| 构造 | `_init_(IIterable&lt;T&gt; __it)` | 构造方法，初始化本类型实例。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 属性 | `get T value()` | 获取 value 的值。 |
| 方法 | `void reset()` | 迭代器 / 订阅控制（reset）。 |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 方法 | `void release()` | 执行 release()。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
