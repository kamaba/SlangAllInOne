# BigDecimal.sl

> 源文件：`BigDecimal.sl`

## class `BigDecimal`

- **说明**：SLang 标准库类型 BigDecimal（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `BigNumber _unscaled = null` | ── 内部表示 ───────────────────────────────────────── 值 = _unscaled / 10^_scale 例：_unscaled = 12345, _scale = 3  →  12.345 |
| 字段 | `public Int32 scale = 0` | 字段 Int32（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Int32 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(BigNumber unscaled, Int32 _scale)` | 执行 _init_(unscaled, _scale)，行为详见源实现。 |
| 方法 | `void _init_(Int32 value, Int32 _scale)` | 由整数 + 小数位数构造：value / 10^scale |
| 方法 | `void _init_(string text)` | 执行 _init_(text)，行为详见源实现。 |
| 方法 | `BigNumber _unscaledAtScale(Int32 targetScale)` | ── 内部工具 ───────────────────────────────────────── |
| 方法 | `Int32 _align(BigDecimal other, BigNumber outA, BigNumber outB)` | 对齐两个操作数的 scale，返回公共 scale（写入 outA / outB） |
| 方法 | `BigDecimal add(BigDecimal other)` | ── 算术 ───────────────────────────────────────────── |
| 方法 | `BigDecimal sub(BigDecimal other)` | 算术：返回 a - b 之差（sub）。 |
| 方法 | `BigDecimal multiply(BigDecimal other)` | 算术：返回两数之积（multiply）。 |
| 方法 | `BigDecimal div(BigDecimal other, Int32 extraScale = 8)` | 除法：结果保留 dividend.scale + extraScale 位小数（默认补足到 8 位） |
| 方法 | `BigDecimal negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `BigDecimal clone()` | 克隆 / 复制（clone）。 |
| 方法 | `BigDecimal rescale(Int32 targetScale)` | 调整小数位数（截断） |
| 方法 | `BigDecimal roundTo(Int32 targetScale)` | 四舍五入到指定小数位 |
| 方法 | `int compare(BigDecimal other)` | 比较 / 排序 / 相等判定（compare）。 |
| 方法 | `BigDecimal _add_(Object obj1)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `BigDecimal _sub_(Object obj1)` | 执行 _sub_(obj1)，行为详见源实现。 |
| 方法 | `BigDecimal _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `BigDecimal _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `bool _lt_(Object obj1)` | 执行 _lt_(obj1)，行为详见源实现。 |
| 方法 | `bool _le_(Object obj1)` | 执行 _le_(obj1)，行为详见源实现。 |
| 方法 | `bool _gt_(Object obj1)` | 执行 _gt_(obj1)，行为详见源实现。 |
| 方法 | `bool _ge_(Object obj1)` | 执行 _ge_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Object obj1)` | 执行 _eq_(obj1)，行为详见源实现。 |
| 方法 | `bool _ne_(Object obj1)` | 执行 _ne_(obj1)，行为详见源实现。 |
| 方法 | `int _compareBoxed(Object obj1)` | 执行 _compareBoxed(obj1)，行为详见源实现。 |
| 属性 | `get int size()` | ── Num 接口实现 ───────────────────────────────────── |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 向下取整（去掉小数部分） |
| 方法 | `Num ceil()` | 向上取整 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `Int32 toInt32()` | 取整数部分（截断小数） |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 属性 | `get BigDecimal zero()` | ── 静态工具 ───────────────────────────────────────── |
| 属性 | `get BigDecimal one()` | 获取 one 的值。 |
| 方法 | `BigDecimal fromInt32(Int32 v)` | 执行 fromInt32(v)，行为详见源实现。 |
| 方法 | `BigDecimal fromUnscaled(BigNumber unscaled, Int32 scale)` | 由未缩放整数 + 小数位构造 |
| 方法 | `BigDecimal parse(string text)` | 解析十进制字符串：支持 "12.345" / "-0.5" / "100" 说明：依赖运行时的字符串长度与字符访问能力；若运行时未提供字符索引， 请改用 fromUnscaled(BigNumber.parse(intPart), fracLen) 组合构造。 |
| 方法 | `Int32 _countFractionDigits(string text)` | 统计小数点后的位数（无小数点返回 0） |
| 方法 | `int _charCodeAt(string s, int index)` | 执行 _charCodeAt(s, index)，行为详见源实现。 |
| 方法 | `BigDecimal maxValue(BigDecimal a, BigDecimal b)` | 执行 maxValue(a, b)，行为详见源实现。 |
| 方法 | `BigDecimal minValue(BigDecimal a, BigDecimal b)` | 执行 minValue(a, b)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
