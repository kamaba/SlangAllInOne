# BigNumber.sl

> 源文件：`BigNumber.sl`

## class `BigNumber`

- **说明**：SLang 标准库类型 BigNumber（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `const static Int32 BASE = 10000` | ── 内部表示 ───────────────────────────────────────── 定点进制：每段存 4 位十进制（BASE = 10^4），低位在前（_digits[0] 是最低段）。 _sign：0 = 零，1 = 正，-1 = 负。 容量固定 CAPACITY 段（默认 64 段 ≈ 256 位十进制），避免动态扩容。 |
| 字段 | `const static Int32 BASE_DIGITS = 4` | 字段 static（类型见签名）。 |
| 字段 | `const static Int32 CAPACITY = 64` | 字段 static（类型见签名）。 |
| 字段 | `Array&lt;Int32&gt; _digits = null` | 字段 _digits（类型见签名）。 |
| 字段 | `Int32 _length = 1` | 字段 _length（类型见签名）。 |
| 字段 | `Int32 _sign = 0` | 字段 _sign（类型见签名）。 |
| 方法 | `void _init_()` | ── 构造 ───────────────────────────────────────────── |
| 方法 | `void _init_(Int32 v)` | 执行 _init_(v)，行为详见源实现。 |
| 方法 | `void _init_(string text)` | 执行 _init_(text)，行为详见源实现。 |
| 方法 | `void _copyFrom(BigNumber other)` | 执行 _copyFrom(other)，行为详见源实现。 |
| 方法 | `void _trim()` | 去除高位无效 0，并维护 _sign |
| 方法 | `bool _isZero()` | 执行 _isZero()。 |
| 方法 | `int _absCompare(BigNumber other)` | 绝对值比较：-1 / 0 / 1 |
| 方法 | `BigNumber _addAbs(BigNumber other)` | 无符号加法（结果写入新对象） |
| 方法 | `BigNumber _subAbs(BigNumber other)` | 无符号减法（要求 this 绝对值 &gt;= other 绝对值） |
| 方法 | `BigNumber _negate()` | 执行 _negate()。 |
| 方法 | `BigNumber add(BigNumber other)` | ── 算术 ───────────────────────────────────────────── |
| 方法 | `BigNumber sub(BigNumber other)` | 算术：返回 a - b 之差（sub）。 |
| 方法 | `BigNumber multiply(BigNumber other)` | 算术：返回两数之积（multiply）。 |
| 方法 | `Array&lt;BigNumber&gt; divMod(BigNumber other)` | 长除法：返回 [商, 余数]（余数符号与被除数一致） |
| 方法 | `BigNumber _shiftLeftOneDigit()` | 左移一段（乘以 BASE） |
| 方法 | `BigNumber div(BigNumber other)` | 算术：返回两数之商（div）。 |
| 方法 | `BigNumber mod(BigNumber other)` | 算术：返回取模余数（mod）。 |
| 方法 | `BigNumber negate()` | 算术：返回取负结果（negate）。 |
| 方法 | `BigNumber clone()` | 克隆 / 复制（clone）。 |
| 方法 | `BigNumber _add_(Object obj1)` | ── 运算符重载 ─────────────────────────────────────── |
| 方法 | `BigNumber _sub_(Object obj1)` | 执行 _sub_(obj1)，行为详见源实现。 |
| 方法 | `BigNumber _mul_(Object obj1)` | 执行 _mul_(obj1)，行为详见源实现。 |
| 方法 | `BigNumber _truediv_(Object obj1)` | 执行 _truediv_(obj1)，行为详见源实现。 |
| 方法 | `BigNumber _mod_(Object obj1)` | 执行 _mod_(obj1)，行为详见源实现。 |
| 方法 | `bool _lt_(Object obj1)` | 执行 _lt_(obj1)，行为详见源实现。 |
| 方法 | `bool _le_(Object obj1)` | 执行 _le_(obj1)，行为详见源实现。 |
| 方法 | `bool _gt_(Object obj1)` | 执行 _gt_(obj1)，行为详见源实现。 |
| 方法 | `bool _ge_(Object obj1)` | 执行 _ge_(obj1)，行为详见源实现。 |
| 方法 | `bool _eq_(Object obj1)` | 执行 _eq_(obj1)，行为详见源实现。 |
| 方法 | `bool _ne_(Object obj1)` | 执行 _ne_(obj1)，行为详见源实现。 |
| 方法 | `int compareToBoxed(Object obj1)` | Object 参数版比较（供运算符重载使用） |
| 方法 | `int compare(BigNumber other)` | 比较 / 排序 / 相等判定（compare）。 |
| 属性 | `get int size()` | ── Num 接口实现 ───────────────────────────────────── |
| 属性 | `get int byteLength()` | 获取 byteLength 的值。 |
| 方法 | `Num abs()` | 算术：返回绝对值（abs）。 |
| 方法 | `Num floor()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（floor）。 |
| 方法 | `Num ceil()` | 算术：取整（向下 / 向上 / 四舍五入 / 截断）（ceil）。 |
| 方法 | `Int8 compareTo(Num other)` | 比较 / 排序 / 相等判定（compareTo）。 |
| 方法 | `Int32 toInt32()` | 转换为 Int32 类型（toInt32）。 |
| 方法 | `Float32 toFloat32()` | 转换为 Float32 类型（toFloat32）。 |
| 方法 | `Float64 toFloat64()` | 转换为 Float64 类型（toFloat64）。 |
| 属性 | `get BigNumber zero()` | ── 静态工具 ───────────────────────────────────────── |
| 属性 | `get BigNumber one()` | 获取 one 的值。 |
| 方法 | `BigNumber parse(string text)` | 从十进制字符串解析（支持可选 +/- 号） |
| 方法 | `int _charToDigit(string s, int index)` | 取字符串指定位置的字符码（无符号字节值），越界/非字符串返回 -1 |
| 方法 | `BigNumber valueOf(Int32 v)` | 执行 valueOf(v)，行为详见源实现。 |
| 方法 | `BigNumber absValue(BigNumber v)` | 执行 absValue(v)，行为详见源实现。 |
| 方法 | `BigNumber maxValue(BigNumber a, BigNumber b)` | 执行 maxValue(a, b)，行为详见源实现。 |
| 方法 | `BigNumber minValue(BigNumber a, BigNumber b)` | 执行 minValue(a, b)，行为详见源实现。 |
| 方法 | `BigNumber pow(BigNumber baseValue, Int32 exponent)` | 幂运算（快速幂，指数为非负 Int32） |
| 方法 | `BigNumber factorial(Int32 n)` | 阶乘 |
| 方法 | `BigNumber gcd(BigNumber a, BigNumber b)` | 最大公约数（欧几里得） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `string _pad4(Int32 v)` | 每段补足 4 位十进制 |
