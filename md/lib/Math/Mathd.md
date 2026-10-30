# Mathd.sl

> 源文件：`Mathd.sl`

## class `Mathd`

- **说明**：Math —— Float64（double）精度数学库，默认通用入口。 底层能力：由 math_lib.dll（C ABI，见 source\Front\Lib\Math\cvm_math_lib\math_lib.c） 经 FFI @DllStaticImport 二参形式（静态注册名, 符号名）静态绑定：cvm 加载期按 Math.jsonc dllImports 的 "static" 字段预载注册，静态调用点由 cvm 装配期 attribute 注册表改写为 CallFFIStatic(77) 直调绑定表（sig 从函数签名自动推导），无 wrapper 委托转发开销；绑定失败（库未注册 / 符号缺失 / sig 非法）时回退执行函数本体 （SL 纯实现 fallback，见本文件后半的 xxxFallback 私有静态实现）。 纯算术能力（abs / min / max / clamp / sign ...）在 SL 层实现。 精度分组约定： Math  -> Float64（本文件） Mathf -> Float32（见 Mathf.sl） Mathh -> Float16（见 Mathh.sl）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public const static Float64 Pi = 3.141592653589793d` | 字段 const（类型见签名）。 |
| 字段 | `public const static Float64 E = 2.718281828459045d` | 字段 const（类型见签名）。 |
| 方法 | `Float64 sin(Float64 value)` | 数学函数（sin）。 |
| 方法 | `Float64 cos(Float64 value)` | 数学函数（cos）。 |
| 方法 | `Float64 tan(Float64 value)` | 数学函数（tan）。 |
| 方法 | `Float64 asin(Float64 value)` | 转换 / 序列化 / 格式化（asin）。 |
| 方法 | `Float64 acos(Float64 value)` | 数学函数（acos）。 |
| 方法 | `Float64 atan(Float64 value)` | 查找 / 取值（atan）。 |
| 方法 | `Float64 atan2(Float64 y, Float64 x)` | 查找 / 取值（atan2）。 |
| 方法 | `Float64 sinh(Float64 value)` | 执行 sinh(value)，行为详见源实现。 |
| 方法 | `Float64 cosh(Float64 value)` | 执行 cosh(value)，行为详见源实现。 |
| 方法 | `Float64 tanh(Float64 value)` | 执行 tanh(value)，行为详见源实现。 |
| 方法 | `Float64 pow(Float64 baseValue, Float64 exponent)` | 算术：返回幂（pow）。 |
| 方法 | `Float64 sqrt(Float64 value)` | 算术：返回平方根 / 立方根（sqrt）。 |
| 方法 | `Float64 exp(Float64 value)` | 数学函数（exp）。 |
| 方法 | `Float64 log(Float64 value)` | 数学函数（log）。 |
| 方法 | `Float64 log10(Float64 value)` | 数学函数（log10）。 |
| 方法 | `Float64 ceil(Float64 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Float64 floor(Float64 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Float64 round(Float64 value)` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（round）。 |
| 方法 | `Int32 truncate(Float64 value)` | 执行 truncate(value)，行为详见源实现。 |
| 方法 | `Float64 dot3(Float64 a0, Float64 a1, Float64 a2, Float64 b0, Float64 b1, Float64 b2)` | 执行 dot3(a0, a1, a2, b0, b1, b2)，行为详见源实现。 |
| 方法 | `Float64 reducePi(Float64 value)` | ── FFI 不可用时的 SL 纯实现（private fallback） ───── 归约：x mod 2π 折到 [-π, π]（截断式整除，避免 Float64 取模） |
| 方法 | `Float64 sinFallback(Float64 value)` | 执行 sinFallback(value)，行为详见源实现。 |
| 方法 | `Float64 cosFallback(Float64 value)` | 执行 cosFallback(value)，行为详见源实现。 |
| 方法 | `Float64 tanFallback(Float64 value)` | 执行 tanFallback(value)，行为详见源实现。 |
| 方法 | `Float64 asinFallback(Float64 value)` | 转换 / 序列化 / 格式化（asinFallback）。 |
| 方法 | `Float64 acosFallback(Float64 value)` | 执行 acosFallback(value)，行为详见源实现。 |
| 方法 | `Float64 atanFallback(Float64 value)` | 查找 / 取值（atanFallback）。 |
| 方法 | `Float64 atan2Fallback(Float64 y, Float64 x)` | 查找 / 取值（atan2Fallback）。 |
| 方法 | `Float64 sinhFallback(Float64 value)` | 执行 sinhFallback(value)，行为详见源实现。 |
| 方法 | `Float64 coshFallback(Float64 value)` | 执行 coshFallback(value)，行为详见源实现。 |
| 方法 | `Float64 tanhFallback(Float64 value)` | 执行 tanhFallback(value)，行为详见源实现。 |
| 方法 | `Float64 powFallback(Float64 baseValue, Float64 exponent)` | 执行 powFallback(baseValue, exponent)，行为详见源实现。 |
| 方法 | `Float64 sqrtFallback(Float64 value)` | 执行 sqrtFallback(value)，行为详见源实现。 |
| 方法 | `Float64 expFallback(Float64 value)` | 执行 expFallback(value)，行为详见源实现。 |
| 方法 | `Float64 logFallback(Float64 value)` | 执行 logFallback(value)，行为详见源实现。 |
| 方法 | `Float64 floorFallback(Float64 value)` | 执行 floorFallback(value)，行为详见源实现。 |
| 方法 | `Float64 roundFallback(Float64 value)` | 执行 roundFallback(value)，行为详见源实现。 |
| 方法 | `Int32 abs(Int32 value)` | ── 绝对值 ─────────────────────────────────────────── |
| 方法 | `Float64 abs(Float64 value)` | 算术：返回绝对值（abs）。 |
| 方法 | `Int32 min(Int32 a, Int32 b)` | ── 最小 / 最大 ────────────────────────────────────── |
| 方法 | `Float64 min(Float64 a, Float64 b)` | 比较：返回较小 / 较大值（min）。 |
| 方法 | `Int32 max(Int32 a, Int32 b)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Float64 max(Float64 a, Float64 b)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Int32 clamp(Int32 value, Int32 minValue, Int32 maxValue)` | ── 区间限定 ───────────────────────────────────────── |
| 方法 | `Float64 clamp(Float64 value, Float64 minValue, Float64 maxValue)` | 执行 clamp(value, minValue, maxValue)，行为详见源实现。 |
| 方法 | `Int32 sign(Int32 value)` | ── 符号 ───────────────────────────────────────────── |
| 方法 | `Int32 sign(Float64 value)` | 执行 sign(value)，行为详见源实现。 |
| 方法 | `Float64 distance(Float64 x1, Float64 y1, Float64 x2, Float64 y2)` | ── 距离 ───────────────────────────────────────────── |
| 方法 | `Float64 distance3D(Float64 x1, Float64 y1, Float64 z1, Float64 x2, Float64 y2, Float64 z2)` | 执行 distance3D(x1, y1, z1, x2, y2, z2)，行为详见源实现。 |
| 方法 | `Float64 lerp(Float64 a, Float64 b, Float64 t)` | ── 插值 ───────────────────────────────────────────── |
| 方法 | `Float64 lerpClamped(Float64 a, Float64 b, Float64 t)` | 执行 lerpClamped(a, b, t)，行为详见源实现。 |
| 方法 | `Float64 degrees(Float64 radians)` | ── 角度转换 ───────────────────────────────────────── |
| 方法 | `Float64 radians(Float64 degrees)` | 执行 radians(degrees)，行为详见源实现。 |
| 方法 | `bool approximately(Float64 a, Float64 b, Float64 epsilon = 0.0000000001d)` | ── 扩展工具 ───────────────────────────────────────── |
| 方法 | `Int32 mod(Int32 value, Int32 m)` | 取模（结果恒为非负） |
| 方法 | `Int32 powInt(Int32 baseValue, Int32 exponent)` | 整数快速幂（result 是 Result 返回函数注入变量的上下文名，避免遮蔽歧义，此处改名 r） |
