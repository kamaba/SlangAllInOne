# String.sl

> 源文件：`String.sl`

## class `String`

- **说明**：SLang 标准库类型 String（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private String _value = null` | 字段 String（类型见签名）。 |
| 字段 | `private Int32 _length = -1` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(Int8 aa)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(Int32 aa)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(String aa)` | 构造方法，初始化本类型实例。 |
| 方法 | `string format(params object[] _parmas)` | 转换 / 序列化 / 格式化（format）。 |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string toFormat(string _format, params object[] _parmas)` | 转换 / 序列化 / 格式化（toFormat）。 |
| 方法 | `string front(int index)` | 截取前 index 个字符；index&lt;=0 为空串；大于长度则整串 |
| 方法 | `string end(int index)` | 截取末尾 index 个字符（从后往前数） |
| 方法 | `string slice(int start, int end)` | 半开区间 [start, end)，等价 Substring(start, end - start) 方法名 slice：range 是小写容器构造糖（range() =&gt; Range），类成员名须避让 |
| 方法 | `UInt8Array toUInt8Array()` | UTF-8 字节序列，Array&lt;Byte&gt;（ByteArray） |
