# UInt64.sl

> 源文件：`UInt64.sl`

## class `UInt64`

- **说明**：64 位无符号整数，对应 C# ulong，用于大计数、容量与句柄等场景。

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 构造 | `_init_(UInt64 _val)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
