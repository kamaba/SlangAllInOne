# Float16_3.sl

> 源文件：`Float16_3.sl`

## class `Float16_3`

- **说明**：SLang 标准库类型 Float16_3（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float16 x = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 y = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 z = 0.0h` | 字段 Float16（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float16 _x, Float16 _y, Float16 _z)` | 执行 _init_(_x, _y, _z)，行为详见源实现。 |
| 方法 | `void _init_(Float16 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float16_2 v, Float16 _z)` | 执行 _init_(v, _z)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3 v)` | 由 Float32_3 降精度 |
| 方法 | `Float16 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float16 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float16_3 _add_(Float16_3 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float16_3 _sub_(Float16_3 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float16_3 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float16_3 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float16_3 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float16_3 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float16 dot(Float16_3 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float16 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float16 length()` | 执行 length()。 |
| 方法 | `Float16_3 normalize()` | 执行 normalize()。 |
| 方法 | `Float16 distance(Float16_3 other)` | 执行 distance(other)，行为详见源实现。 |
| 方法 | `Float16_3 cross(Float16_3 other)` | 执行 cross(other)，行为详见源实现。 |
| 方法 | `Float16_3 lerp(Float16_3 other, Float16 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float16_3 scale(Float16 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float16_3 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float16_3 reflect(Float16_3 normal)` | 绕法线反射（normal 需已归一化） |
| 方法 | `Float16_3 setValue(Float16 _x, Float16 _y, Float16 _z)` | 执行 setValue(_x, _y, _z)，行为详见源实现。 |
| 方法 | `Float16_3 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_3 toFloat32_3()` | ── 精度转换 ───────────────────────────────────────── |
| 方法 | `Float64_3 toFloat64_3()` | 转换 / 序列化 / 格式化（toFloat64_3）。 |
| 属性 | `get Float16_3 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float16_3 one()` | 获取 one 的值。 |
| 属性 | `get Float16_3 forward()` | 获取 forward 的值。 |
| 属性 | `get Float16_3 back()` | 获取 back 的值。 |
| 属性 | `get Float16_3 up()` | 获取 up 的值。 |
| 属性 | `get Float16_3 down()` | 获取 down 的值。 |
| 属性 | `get Float16_3 left()` | 获取 left 的值。 |
| 属性 | `get Float16_3 right()` | 获取 right 的值。 |
| 方法 | `Float16 dot(Float16_3 a, Float16_3 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float16_3 cross(Float16_3 a, Float16_3 b)` | 执行 cross(a, b)，行为详见源实现。 |
| 方法 | `Float16 distance(Float16_3 a, Float16_3 b)` | 执行 distance(a, b)，行为详见源实现。 |
| 方法 | `Float16_3 lerp(Float16_3 a, Float16_3 b, Float16 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
