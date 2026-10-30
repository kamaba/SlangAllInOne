# Mathh.sl

> 源文件：`Mathh.sl`

## class `Mathh`

- **说明**：Mathh —— Float16（half）精度数学库。 实现说明： 运行时目前未注册 half 版外部函数，也没有 SystemConvertFloat16 转换调用， 因此本类以 Float32 作为中间精度计算（half 仅 10 位尾数，Float32 中转不会引入额外误差）， 结果再隐式收敛回 Float16。 若后续在 MathNativeImpl 中注册 "Mathh.xxx"（System.Half 版本）， 可把每个方法替换为：ret SystemCallExternalFunction( "Mathh.sin", value ) as Float16 精度分组约定： Mathd -> Float64（见 Mathd.sl） Mathf -> Float32（见 Mathf.sl） Mathh -> Float16（本文件）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public const static Float16 Pi = 3.141592653589793h` | half 表示下的常量（写入时按 Float16 位宽截断） |
| 字段 | `public const static Float16 E = 2.718281828459045h` | 字段 const（类型见签名）。 |
| 方法 | `Float16 sin(Float16 value)` | ── 三角函数 ───────────────────────────────────────── |
| 方法 | `Float16 cos(Float16 value)` | 数学函数（cos）。 |
| 方法 | `Float16 tan(Float16 value)` | 数学函数（tan）。 |
| 方法 | `Float16 asin(Float16 value)` | 转换 / 序列化 / 格式化（asin）。 |
| 方法 | `Float16 acos(Float16 value)` | 数学函数（acos）。 |
| 方法 | `Float16 atan(Float16 value)` | 查找 / 取值（atan）。 |
| 方法 | `Float16 atan2(Float16 y, Float16 x)` | 查找 / 取值（atan2）。 |
| 方法 | `Float16 sinh(Float16 value)` | ── 双曲函数 ───────────────────────────────────────── |
| 方法 | `Float16 cosh(Float16 value)` | 执行 cosh(value)，行为详见源实现。 |
| 方法 | `Float16 tanh(Float16 value)` | 执行 tanh(value)，行为详见源实现。 |
| 方法 | `Float16 pow(Float16 baseValue, Float16 exponent)` | ── 幂与对数 ───────────────────────────────────────── |
| 方法 | `Float16 sqrt(Float16 value)` | 算术：返回平方根 / 立方根（sqrt）。 |
| 方法 | `Float16 exp(Float16 value)` | 数学函数（exp）。 |
| 方法 | `Float16 log(Float16 value)` | 数学函数（log）。 |
| 方法 | `Float16 log10(Float16 value)` | 数学函数（log10）。 |
| 方法 | `Float16 ceil(Float16 value)` | ── 取整 ───────────────────────────────────────────── |
| 方法 | `Float16 floor(Float16 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Float16 round(Float16 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（round）。 |
| 方法 | `Int32 truncate(Float16 value)` | 执行 truncate(value)，行为详见源实现。 |
| 方法 | `Float16 abs(Float16 value)` | ── 绝对值 ─────────────────────────────────────────── |
| 方法 | `Float16 min(Float16 a, Float16 b)` | ── 最小 / 最大 ────────────────────────────────────── |
| 方法 | `Float16 max(Float16 a, Float16 b)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Float16 clamp(Float16 value, Float16 minValue, Float16 maxValue)` | ── 区间限定 ───────────────────────────────────────── |
| 方法 | `Int32 sign(Float16 value)` | ── 符号 ───────────────────────────────────────────── |
| 方法 | `Float16 distance(Float16 x1, Float16 y1, Float16 x2, Float16 y2)` | ── 距离 ───────────────────────────────────────────── |
| 方法 | `Float16 distance3D(Float16 x1, Float16 y1, Float16 z1, Float16 x2, Float16 y2, Float16 z2)` | 执行 distance3D(x1, y1, z1, x2, y2, z2)，行为详见源实现。 |
| 方法 | `Float16 lerp(Float16 a, Float16 b, Float16 t)` | ── 插值 ───────────────────────────────────────────── |
| 方法 | `Float16 lerpClamped(Float16 a, Float16 b, Float16 t)` | 执行 lerpClamped(a, b, t)，行为详见源实现。 |
| 方法 | `Float16 degrees(Float16 radians)` | ── 角度转换 ───────────────────────────────────────── |
| 方法 | `Float16 radians(Float16 degrees)` | 执行 radians(degrees)，行为详见源实现。 |
| 方法 | `bool approximately(Float16 a, Float16 b, Float16 epsilon = 0.0009765625h)` | ── 扩展工具 ───────────────────────────────────────── half 的机器精度为 2^-10，epsilon 取 0.0009765625 |
