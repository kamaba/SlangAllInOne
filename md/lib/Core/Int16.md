# Int16.sl

> 源文件：`Int16.sl`

## class `Int16`

- **说明**：16 位有符号整数，取值范围 -32768 ~ 32767，对应 C# short。

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_(Int16 _val)` | 构造方法，初始化本类型实例。 |
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `Int16 parse(string s)` | 转换 / 序列化 / 格式化（parse）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `bool toBool()` | 转换为 Boolundefined 类型（toBool）。 |
| 方法 | `Int8 toInt8(UInt8 index = 0)` | 转换为 Int8 类型（toInt8）。 |
| 方法 | `UInt8 toUInt8(UInt8 index = 0)` | 转换为 UInt8 类型（toUInt8）。 |
| 方法 | `Int16 toInt16()` | 转换为 Int16 类型（toInt16）。 |
| 方法 | `UInt16 toUInt16()` | 转换为 UInt16 类型（toUInt16）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `UInt32 toUInt32()` | 转换为 UInt32 类型（toUInt32）。 |
| 方法 | `Int64 toInt64()` | 转换为 Int64 类型（toInt64）。 |
| 方法 | `Int64 toUInt64()` | 转换为 UInt64 类型（toUInt64）。 |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Int32 sign()` | 执行 sign()。 |
| 方法 | `bool isEven()` | 判断状态是否（isEven）。 |
| 方法 | `bool isOdd()` | 判断状态是否（isOdd）。 |
| 方法 | `String toRadixString(int radix)` | 转换 / 序列化 / 格式化（toRadixString）。 |
| 方法 | `String toBinaryString()` | 转换 / 序列化 / 格式化（toBinaryString）。 |
| 方法 | `String toHexString()` | 转换 / 序列化 / 格式化（toHexString）。 |
| 方法 | `String toOctalString()` | 转换 / 序列化 / 格式化（toOctalString）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
