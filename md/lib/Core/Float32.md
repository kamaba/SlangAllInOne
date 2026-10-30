# Float32.sl

> 源文件：`Float32.sl`

## class `Float32`

- **说明**：历史遗留的 import CSharp.System; 所指命名空间并不存在（曾静默失败），随 import 错误严格化已移除。 32 位单精度浮点数，对应 C# float，用于通用浮点运算与对外数值交换。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Float32 _value = 0.0f` | 字段 _value（类型见签名）。 |
| 方法 | `void _init_(Float32 f)` | 执行 _init_(f)，行为详见源实现。 |
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `bool isNaN(Float32 f)` | 判断状态是否（isNaN）。 |
| 方法 | `bool isInfinite(Float32 f)` | 判断状态是否（isInfinite）。 |
| 方法 | `bool isFinite(Float32 f)` | 判断状态是否（isFinite）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `String toString(string format)` | 转换为 Stringundefined 类型（toString）。 |
