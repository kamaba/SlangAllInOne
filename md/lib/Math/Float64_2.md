# Float64_2.sl

> 源文件：`Float64_2.sl`

## class `Float64_2`

- **说明**：SLang 标准库类型 Float64_2（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float64 x = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 y = 0.0d` | 字段 Float64（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float64 _x, Float64 _y)` | 执行 _init_(_x, _y)，行为详见源实现。 |
| 方法 | `void _init_(Float64 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float32_2 v)` | 由 Float32_2 提升 |
| 方法 | `Float64 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float64 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float64_2 _add_(Float64_2 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float64_2 _sub_(Float64_2 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float64_2 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float64_2 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float64_2 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float64_2 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float64 dot(Float64_2 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float64 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float64 length()` | 执行 length()。 |
| 方法 | `Float64_2 normalize()` | 执行 normalize()。 |
| 方法 | `Float64 distance(Float64_2 other)` | 执行 distance(other)，行为详见源实现。 |
| 方法 | `Float64 cross(Float64_2 other)` | 2D 叉积（标量） |
| 方法 | `Float64_2 lerp(Float64_2 other, Float64 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float64_2 scale(Float64 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float64_2 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float64_2 setValue(Float64 _x, Float64 _y)` | 执行 setValue(_x, _y)，行为详见源实现。 |
| 方法 | `Float64_2 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_2 toFloat32_2()` | ── 精度转换 ───────────────────────────────────────── |
| 属性 | `get Float64_2 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float64_2 one()` | 获取 one 的值。 |
| 属性 | `get Float64_2 up()` | 获取 up 的值。 |
| 属性 | `get Float64_2 down()` | 获取 down 的值。 |
| 属性 | `get Float64_2 left()` | 获取 left 的值。 |
| 属性 | `get Float64_2 right()` | 获取 right 的值。 |
| 方法 | `Float64 dot(Float64_2 a, Float64_2 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float64 distance(Float64_2 a, Float64_2 b)` | 执行 distance(a, b)，行为详见源实现。 |
| 方法 | `Float64_2 lerp(Float64_2 a, Float64_2 b, Float64 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
