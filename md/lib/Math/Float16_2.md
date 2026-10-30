# Float16_2.sl

> 源文件：`Float16_2.sl`

## class `Float16_2`

- **说明**：SLang 标准库类型 Float16_2（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float16 x = 0.0h` | 字段 Float16（类型见签名）。 |
| 字段 | `public Float16 y = 0.0h` | 字段 Float16（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float16 _x, Float16 _y)` | 执行 _init_(_x, _y)，行为详见源实现。 |
| 方法 | `void _init_(Float16 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(Float32_2 v)` | 由 Float32_2 降精度 |
| 方法 | `Float16 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float16 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float16_2 _add_(Float16_2 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float16_2 _sub_(Float16_2 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float16_2 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float16_2 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float16_2 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float16_2 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float16 dot(Float16_2 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float16 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float16 length()` | 执行 length()。 |
| 方法 | `Float16_2 normalize()` | 执行 normalize()。 |
| 方法 | `Float16 distance(Float16_2 other)` | 执行 distance(other)，行为详见源实现。 |
| 方法 | `Float16 cross(Float16_2 other)` | 2D 叉积（标量） |
| 方法 | `Float16_2 lerp(Float16_2 other, Float16 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float16_2 scale(Float16 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float16_2 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float16_2 setValue(Float16 _x, Float16 _y)` | 执行 setValue(_x, _y)，行为详见源实现。 |
| 方法 | `Float16_2 clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_2 toFloat32_2()` | ── 精度转换 ───────────────────────────────────────── |
| 方法 | `Float64_2 toFloat64_2()` | 转换 / 序列化 / 格式化（toFloat64_2）。 |
| 属性 | `get Float16_2 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float16_2 one()` | 获取 one 的值。 |
| 属性 | `get Float16_2 up()` | 获取 up 的值。 |
| 属性 | `get Float16_2 down()` | 获取 down 的值。 |
| 属性 | `get Float16_2 left()` | 获取 left 的值。 |
| 属性 | `get Float16_2 right()` | 获取 right 的值。 |
| 方法 | `Float16 dot(Float16_2 a, Float16_2 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float16 distance(Float16_2 a, Float16_2 b)` | 执行 distance(a, b)，行为详见源实现。 |
| 方法 | `Float16_2 lerp(Float16_2 a, Float16_2 b, Float16 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
