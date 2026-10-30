# Quaternion.sl

> 源文件：`Quaternion.sl`

## class `Quaternion`

- **说明**：SLang 标准库类型 Quaternion（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Float32 x = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 y = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 z = 0.0f` | 字段 Float32（类型见签名）。 |
| 字段 | `public Float32 w = 1.0f` | 字段 Float32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Float32 _x, Float32 _y, Float32 _z, Float32 _w)` | 执行 _init_(_x, _y, _z, _w)，行为详见源实现。 |
| 方法 | `void _init_(Float32_3 axis, Float32 radians)` | 由轴角构造（axis 需已归一化） |
| 方法 | `Float32 _getItem_(int index)` | ── 索引访问 ───────────────────────────────────────── |
| 方法 | `void _setItem_(int index, Float32 value)` | 执行 _setItem_(index, value)，行为详见源实现。 |
| 方法 | `Object _mul_(Object obj1)` | ── 运算符重载 ─────────────────────────────────────── 说明：Quaternion * Quaternion 返回 Quaternion；Quaternion * Float32_3 返回 Float32_3。 运算符重载是动态分派，返回类型统一声明为 Object； 需要静态类型的场景请直接使用 multiply() / rotate()。 |
| 方法 | `bool _eq_(Quaternion q)` | 执行 _eq_(q)，行为详见源实现。 |
| 方法 | `bool _ne_(Quaternion q)` | 执行 _ne_(q)，行为详见源实现。 |
| 方法 | `Quaternion multiply(Quaternion q)` | ── 四元数运算 ─────────────────────────────────────── Hamilton 积：this * q（先应用 q，再应用 this） |
| 方法 | `Float32_3 rotate(Float32_3 v)` | 用四元数旋转向量 v |
| 方法 | `Float32 dot(Quaternion q)` | 执行 dot(q)，行为详见源实现。 |
| 方法 | `Float32 lengthSquared()` | 执行 lengthSquared()。 |
| 方法 | `Float32 length()` | 执行 length()。 |
| 方法 | `Quaternion normalize()` | 执行 normalize()。 |
| 方法 | `Quaternion conjugate()` | 执行 conjugate()。 |
| 方法 | `Quaternion inverse()` | 执行 inverse()。 |
| 方法 | `Quaternion lerp(Quaternion q, Float32 t)` | 线性插值（结果需归一化） |
| 方法 | `Quaternion slerp(Quaternion q, Float32 t)` | 球面插值 |
| 方法 | `Quaternion set(Float32 _x, Float32 _y, Float32 _z, Float32 _w)` | 设置 / 保存（set）。 |
| 方法 | `Quaternion setIdentity()` | 执行 setIdentity()。 |
| 方法 | `Quaternion clone()` | 克隆 / 复制（clone）。 |
| 方法 | `Float32_4x4 toFloat32_4x4()` | 转为 4x4 旋转矩阵 |
| 方法 | `Float32_3 toEuler()` | 转为欧拉角（弧度，YXZ 顺序） |
| 属性 | `get Quaternion identity()` | ── 静态常量与工厂 ──────────────────────────────────── |
| 方法 | `Quaternion axisAngle(Float32_3 axis, Float32 radians)` | 绕归一化轴 axis 旋转 radians |
| 方法 | `Quaternion euler(Float32 pitch, Float32 yaw, Float32 roll)` | 欧拉角（弧度）转四元数，YXZ 顺序 |
| 方法 | `Quaternion euler(Float32_3 e)` | 执行 euler(e)，行为详见源实现。 |
| 方法 | `Quaternion lookRotation(Float32_3 forward, Float32_3 upHint)` | 由 forward / up 构造朝向 |
| 方法 | `Float32 angle(Quaternion a, Quaternion b)` | 两个四元数之间的夹角（弧度） |
| 方法 | `Quaternion slerp(Quaternion a, Quaternion b, Float32 t)` | 执行 slerp(a, b, t)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
