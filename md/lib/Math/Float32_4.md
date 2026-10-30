# Float32_4.sl

> 源文件：`Float32_4.sl`

## class `Float32_4`

- **说明**：SLang 标准库类型 Float32_4（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float32 x = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 y = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 z = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 w = 0.0f` | 字段 Float32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float32 _x, Float32 _y, Float32 _z, Float32 _w)` | 执行 _init_(_x, _y, _z, _w)，行为详见源实现。 |
| 方法 | `void _init_(Float32 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3 v, Float32 _w)` | vec3 + w |
| 方法 | `Float32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float32_4 _add_(Float32_4 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float32_4 _sub_(Float32_4 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float32_4 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float32_4 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float32_4 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float32_4 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float32 dot(Float32_4 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float32 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float32 length()` | 执行 length()。 |
| 方法 | `Float32_4 normalize()` | 执行 normalize()。 |
| 方法 | `Float32_4 lerp(Float32_4 other, Float32 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float32_4 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float32_4 clone()` | 克隆 / 复制（clone）。 |
| 属性 | `get Float32_4 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float32_4 one()` | 获取 one 的值。 |
| 方法 | `Float32 dot(Float32_4 a, Float32_4 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float32_4 lerp(Float32_4 a, Float32_4 b, Float32 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
