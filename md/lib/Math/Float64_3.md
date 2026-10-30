# Float64_3.sl

> 源文件：`Float64_3.sl`

## class `Float64_3`

- **说明**：SLang 标准库类型 Float64_3（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float64 x = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 y = 0.0d` | 字段 Float64（类型见签名）。 |
| 字段 | `public Float64 z = 0.0d` | 字段 Float64（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float64 _x, Float64 _y, Float64 _z)` | 执行 _init_(_x, _y, _z)，行为详见源实现。 |
| 方法 | `void _init_(Float64 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float64_2 v, Float64 _z)` | 执行 _init_(v, _z)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3 v)` | 由 Float32_3 提升 |
| 方法 | `Float64 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float64 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float64_3 _add_(Float64_3 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float64_3 _sub_(Float64_3 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float64_3 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float64_3 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float64_3 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float64_3 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float64 dot(Float64_3 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float64 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float64 length()` | 执行 length()。 |
| 方法 | `Float64_3 normalize()` | 执行 normalize()。 |
| 方法 | `Float64 distance(Float64_3 other)` | 执行 distance(other)，行为详见源实现。 |
| 方法 | `Float64_3 cross(Float64_3 other)` | 执行 cross(other)，行为详见源实现。 |
| 方法 | `Float64_3 lerp(Float64_3 other, Float64 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float64_3 scale(Float64 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float64_3 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float64_3 reflect(Float64_3 normal)` | 绕法线反射（normal 需已归一化） |
| 方法 | `Float64_3 setValue(Float64 _x, Float64 _y, Float64 _z)` | 执行 setValue(_x, _y, _z)，行为详见源实现。 |
| 方法 | `Float64_3 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_3 toFloat32_3()` | ── 精度转换 ───────────────────────────────────────── |
| 属性 | `get Float64_3 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float64_3 one()` | 获取 one 的值。 |
| 属性 | `get Float64_3 forward()` | 获取 forward 的值。 |
| 属性 | `get Float64_3 back()` | 获取 back 的值。 |
| 属性 | `get Float64_3 up()` | 获取 up 的值。 |
| 属性 | `get Float64_3 down()` | 获取 down 的值。 |
| 属性 | `get Float64_3 left()` | 获取 left 的值。 |
| 属性 | `get Float64_3 right()` | 获取 right 的值。 |
| 方法 | `Float64 dot(Float64_3 a, Float64_3 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float64_3 cross(Float64_3 a, Float64_3 b)` | 执行 cross(a, b)，行为详见源实现。 |
| 方法 | `Float64 distance(Float64_3 a, Float64_3 b)` | 执行 distance(a, b)，行为详见源实现。 |
| 方法 | `Float64_3 lerp(Float64_3 a, Float64_3 b, Float64 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
