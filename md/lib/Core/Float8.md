# Float8.sl

> 源文件：`Float8.sl`

## class `Float8`

- **说明**：8 位浮点数（低精度变体），用于高吞吐/低存储需求的数值批量计算。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Float8 _value = 0.0fe4` | 字段 _value（类型见签名）。 |
| 方法 | `void _init_(Float8 f)` | 执行 _init_(f)，行为详见源实现。 |
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `bool isNaN(Float8 f)` | 判断状态是否（isNaN）。 |
| 方法 | `bool isInfinite(Float8 f)` | 判断状态是否（isInfinite）。 |
| 方法 | `bool isFinite(Float8 f)` | 判断状态是否（isFinite）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `String toString(string format)` | 转换为 Stringundefined 类型（toString）。 |

## class `Float8_E5M2`

- **说明**：SLang 标准库类型 Float8_E5M2（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Float8_E5M2 _value = 0.0fe5` | 字段 _value（类型见签名）。 |
| 方法 | `void _init_(Float8_E5M2 f)` | 执行 _init_(f)，行为详见源实现。 |
| 属性 | `get int size()` | 获取 size 的值。 |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `bool isNaN(Float8_E5M2 f)` | 判断状态是否（isNaN）。 |
| 方法 | `bool isInfinite(Float8_E5M2 f)` | 判断状态是否（isInfinite）。 |
| 方法 | `bool isFinite(Float8_E5M2 f)` | 判断状态是否（isFinite）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `String toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `String toString(string format)` | 转换为 Stringundefined 类型（toString）。 |
