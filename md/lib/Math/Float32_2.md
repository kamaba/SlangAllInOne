# Float32_2.sl

> 源文件：`Float32_2.sl`

## class `Float32_2`

- **说明**：SLang 标准库类型 Float32_2（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float32 x = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 y = 0.0f` | 字段 Float32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float32 _x, Float32 _y)` | 执行 _init_(_x, _y)，行为详见源实现。 |
| 方法 | `void _init_(Float32 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `Float32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Float32_2 _add_(Float32_2 v)` | ── 运算符重载（同类型运算形参收窄为自身类型；标量乘/除保持 Object 动态分派）──────── |
| 方法 | `Float32_2 _sub_(Float32_2 v)` | 执行 _sub_(v)，行为详见源实现。 |
| 方法 | `Float32_2 _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `Float32_2 _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Float32_2 v)` | 执行 _eq_(v)，行为详见源实现。 |
| 方法 | `bool _ne_(Float32_2 v)` | 执行 _ne_(v)，行为详见源实现。 |
| 方法 | `Float32 dot(Float32_2 other)` | ── 向量运算 ───────────────────────────────────────── |
| 方法 | `Float32 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float32 length()` | 执行 length()。 |
| 方法 | `Float32_2 normalize()` | 执行 normalize()。 |
| 方法 | `Float32 distance(Float32_2 other)` | 执行 distance(other)，行为详见源实现。 |
| 方法 | `Float32 cross(Float32_2 other)` | 2D 叉积（标量） |
| 方法 | `Float32_2 lerp(Float32_2 other, Float32 t)` | 执行 lerp(other, t)，行为详见源实现。 |
| 方法 | `Float32_2 scale(Float32 s)` | 执行 scale(s)，行为详见源实现。 |
| 方法 | `Float32_2 negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `Float32_2 setValue(Float32 _x, Float32 _y)` | 执行 setValue(_x, _y)，行为详见源实现。 |
| 方法 | `Float32_2 clone()` | 克隆 / 复制（clone）。 |
| 属性 | `get Float32_2 zero()` | ── 静态常量 ───────────────────────────────────────── |
| 属性 | `get Float32_2 one()` | 获取 one 的值。 |
| 属性 | `get Float32_2 up()` | 获取 up 的值。 |
| 属性 | `get Float32_2 down()` | 获取 down 的值。 |
| 属性 | `get Float32_2 left()` | 获取 left 的值。 |
| 属性 | `get Float32_2 right()` | 获取 right 的值。 |
| 方法 | `Float32 dot(Float32_2 a, Float32_2 b)` | ── 静态工具 ───────────────────────────────────────── |
| 方法 | `Float32 distance(Float32_2 a, Float32_2 b)` | 执行 distance(a, b)，行为详见源实现。 |
| 方法 | `Float32_2 lerp(Float32_2 a, Float32_2 b, Float32 t)` | 执行 lerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
