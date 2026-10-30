# Factor.sl

> 源文件：`Factor.sl`

## class `Factor`

- **说明**：数论 / 因子工具类 说明：本类只提供静态方法，不保存状态（原骨架 _init_ 为 vec4 风格的复制残留，已移除）。 覆盖：质数判定、质因数分解、约数枚举、最大公约数 / 最小公倍数、整数快速幂、阶乘、2 的幂。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool isPrime(Int32 n)` | ── 质数 ───────────────────────────────────────────── 试除法判定（n &lt; 2 一律返回 false） |
| 方法 | `Array&lt;Int32&gt; primeFactors(Int32 n)` | ── 质因数分解 ─────────────────────────────────────── 返回升序质因数数组（含重复），如 12 -&gt; [2, 2, 3]；n &lt; 2 返回空数组 |
| 方法 | `Array&lt;Int32&gt; distinctPrimeFactors(Int32 n)` | 去重后的质因数集合 |
| 方法 | `Array&lt;Int32&gt; divisors(Int32 n)` | ── 约数 ───────────────────────────────────────────── 返回 n 的所有正约数（升序） |
| 方法 | `Int32 divisorCount(Int32 n)` | 约数个数 |
| 方法 | `Int32 divisorSum(Int32 n)` | 约数之和 |
| 方法 | `Int32 gcd(Int32 a, Int32 b)` | ── 公约数 / 公倍数 ─────────────────────────────────── |
| 方法 | `Int32 lcm(Int32 a, Int32 b)` | 执行 lcm(a, b)，行为详见源实现。 |
| 方法 | `Array&lt;Int32&gt; extendedGcd(Int32 a, Int32 b)` | 扩展欧几里得：返回 [gcd, x, y]，满足 a*x + b*y = gcd |
| 方法 | `Int32 powInt(Int32 baseValue, Int32 exponent)` | ── 幂 / 阶乘 ──────────────────────────────────────── 整数快速幂（exponent 需非负；result 是上下文名，此处改名 r） |
| 方法 | `BigNumber factorial(Int32 n)` | 阶乘（大数版本，避免 Int32 溢出） |
| 方法 | `BigNumber permutation(Int32 n, Int32 k)` | 排列数 A(n, k) |
| 方法 | `BigNumber combination(Int32 n, Int32 k)` | 组合数 C(n, k) |
| 方法 | `bool isPowerOfTwo(Int32 n)` | ── 2 的幂 ─────────────────────────────────────────── |
| 方法 | `Int32 nextPowerOfTwo(Int32 n)` | 返回 &gt;= n 的最小 2 的幂 |
| 方法 | `Int32 absInt(Int32 v)` | ── 其他 ───────────────────────────────────────────── |
| 方法 | `Int32 isqrt(Int32 n)` | 整数平方根（向下取整） |
| 方法 | `Int32 eulerPhi(Int32 n)` | 欧拉函数 φ(n)：小于 n 且与 n 互质的正整数个数 |
| 方法 | `void _push(Array&lt;Int32&gt; list, int index, Int32 value)` | ── 内部辅助（Array 容量固定，写入前需保证下标可用）────── |
| 方法 | `Array&lt;Int32&gt; _slice(Array&lt;Int32&gt; list, int count)` | 执行 _slice(list, count)，行为详见源实现。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
