# UInt32.sl

> 源文件：`UInt32.sl`

## class `UInt32`

- **说明**：32 位无符号整数，取值范围 0 ~ 4294967295，对应 C# uint。

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 构造 | `_init_(UInt32 _val)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
