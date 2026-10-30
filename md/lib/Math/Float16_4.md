# Float16_4.sl

> 源文件：`Float16_4.sl`

## class `Float16_4`

- **说明**：SLang 标准库类型 Float16_4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float16 x = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 y = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 z = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 w = 0.0h` | 字段 Float16（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float16 _x, Float16 _y, Float16 _z, Float16 _w)` | 执行 _init_(_x, _y, _z, _w)，行为详见源实现。 |
| 方法 | `void _init_(Float16 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float16_3 v, Float16 _w)` | 执行 _init_(v, _w)，行为详见源实现。 |
| 方法 | `void _init_(Float32_4 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `Float16 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float16 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float16_4 _add_(Float16_4 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float16_4 _sub_(Float16_4 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float16_4 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float16_4 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float16_4 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float16_4 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float16 dot(Float16_4 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float16 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float16 length()` | 执行 length()。 |
| 方法 | `Float16_4 normalize()` | 执行 normalize()。 |
| 方法 | `Float16_4 lerp(Float16_4 other, Float16 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float16_4 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float16_4 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_4 toFloat32_4()` | ── 精度转换 ───────────────────────────────────────── |
| 方法 | `Float64_4 toFloat64_4()` | 转换 / 序列化 / 格式化（toFloat64_4）。 |
| 属性 | `get Float16_4 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float16_4 one()` | 获取 one 的值。 |
| 方法 | `Float16 dot(Float16_4 a, Float16_4 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float16_4 lerp(Float16_4 a, Float16_4 b, Float16 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
