# Mathf.sl

> 源文件：`Mathf.sl`

## class `Mathf`

- **说明**：Mathf —— Float32（single）精度数学库。 底层能力：由 math_lib.dll（C ABI，见 source\Front\Lib\Math\cvm_math_lib\math_lib.c） 经 FFI @DllStaticImport 二参形式（静态注册名, 符号名）静态绑定：cvm 加载期按 Math.jsonc dllImports 的 "static" 字段预载注册，静态调用点由 cvm 装配期 attribute 注册表改写为 CallFFIStatic(77) 直调绑定表（sig 从函数签名自动推导），无 wrapper 委托转发开销；绑定失败（库未注册 / 符号缺失 / sig 非法）时回退执行函数本体 （fallback 委托 Mathd 双精度实现后回转 Float32，链路同 Mathh 的中转模式）。 纯算术能力（abs / min / max / clamp / sign ...）在 SL 层实现。 精度分组约定： Mathd -> Float64（见 Mathd.sl） Mathf -> Float32（本文件） Mathh -> Float16（见 Mathh.sl）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public const static Float32 Pi = 3.141592653589793f` | 字段 const（类型见签名）。 |
| 字段 | `public const static Float32 E = 2.718281828459045f` | 字段 const（类型见签名）。 |
| 方法 | `Float32 sin(Float32 value)` | 数学函数（sin）。 |
| 方法 | `Float32 cos(Float32 value)` | 数学函数（cos）。 |
| 方法 | `Float32 tan(Float32 value)` | 数学函数（tan）。 |
| 方法 | `Float32 asin(Float32 value)` | 转换 / 序列化 / 格式化（asin）。 |
| 方法 | `Float32 acos(Float32 value)` | 数学函数（acos）。 |
| 方法 | `Float32 atan(Float32 value)` | 查找 / 取值（atan）。 |
| 方法 | `Float32 atan2(Float32 y, Float32 x)` | 查找 / 取值（atan2）。 |
| 方法 | `Float32 sinh(Float32 value)` | 执行 sinh(value)，行为详见源实现。 |
| 方法 | `Float32 cosh(Float32 value)` | 执行 cosh(value)，行为详见源实现。 |
| 方法 | `Float32 tanh(Float32 value)` | 执行 tanh(value)，行为详见源实现。 |
| 方法 | `Float32 pow(Float32 baseValue, Float32 exponent)` | 算术：返回幂（pow）。 |
| 方法 | `Float32 sqrt(Float32 value)` | 算术：返回平方根 / 立方根（sqrt）。 |
| 方法 | `Float32 exp(Float32 value)` | 数学函数（exp）。 |
| 方法 | `Float32 log(Float32 value)` | 数学函数（log）。 |
| 方法 | `Float32 log10(Float32 value)` | 数学函数（log10）。 |
| 方法 | `Float32 ceil(Float32 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Float32 floor(Float32 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Float32 round(Float32 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（round）。 |
| 方法 | `Int32 truncate(Float32 value)` | 执行 truncate(value)，行为详见源实现。 |
| 方法 | `Float32 dot3(Float32 a0, Float32 a1, Float32 a2, Float32 b0, Float32 b1, Float32 b2)` | 执行 dot3(a0, a1, a2, b0, b1, b2)，行为详见源实现。 |
| 方法 | `Int32 abs(Int32 value)` | ── 绝对值 ─────────────────────────────────────────── |
| 方法 | `Float32 abs(Float32 value)` | 算术：返回绝对值（abs）。 |
| 方法 | `Int32 min(Int32 a, Int32 b)` | ── 最小 / 最大 ────────────────────────────────────── |
| 方法 | `Float32 min(Float32 a, Float32 b)` | 比较：返回较小 / 较大值（min）。 |
| 方法 | `Int32 max(Int32 a, Int32 b)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Float32 max(Float32 a, Float32 b)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Int32 clamp(Int32 value, Int32 minValue, Int32 maxValue)` | ── 区间限定 ───────────────────────────────────────── |
| 方法 | `Float32 clamp(Float32 value, Float32 minValue, Float32 maxValue)` | 执行 clamp(value, minValue, maxValue)，行为详见源实现。 |
| 方法 | `Int32 sign(Int32 value)` | ── 符号 ───────────────────────────────────────────── |
| 方法 | `Int32 sign(Float32 value)` | 执行 sign(value)，行为详见源实现。 |
| 方法 | `Float32 distance(Float32 x1, Float32 y1, Float32 x2, Float32 y2)` | ── 距离 ───────────────────────────────────────────── |
| 方法 | `Float32 distance3D(Float32 x1, Float32 y1, Float32 z1, Float32 x2, Float32 y2, Float32 z2)` | 执行 distance3D(x1, y1, z1, x2, y2, z2)，行为详见源实现。 |
| 方法 | `Float32 lerp(Float32 a, Float32 b, Float32 t)` | ── 插值 ───────────────────────────────────────────── |
| 方法 | `Float32 lerpClamped(Float32 a, Float32 b, Float32 t)` | 执行 lerpClamped(a, b, t)，行为详见源实现。 |
| 方法 | `Float32 degrees(Float32 radians)` | ── 角度转换 ───────────────────────────────────────── |
| 方法 | `Float32 radians(Float32 degrees)` | 执行 radians(degrees)，行为详见源实现。 |
| 方法 | `bool approximately(Float32 a, Float32 b, Float32 epsilon = 0.000001f)` | ── 扩展工具 ───────────────────────────────────────── |
| 方法 | `Int32 mod(Int32 value, Int32 m)` | 取模（结果恒为非负） |
| 方法 | `Int32 powInt(Int32 baseValue, Int32 exponent)` | 整数快速幂（result 是 Result 返回函数注入变量的上下文名，避免遮蔽歧义，此处改名 r） |
