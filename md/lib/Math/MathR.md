# Math 库的 R 风格扩展函数

Math 模块在 `Mathd`/`Mathf` 之外，另提供四组 `Float64` 静态工具类，用法与 R base
常见函数对齐。所有函数都是纯 SL 实现，不需要额外原生库；向量统一用
`List<Float64>`，下标统一 `Int32`。

```slang
import Math;

List<Float64> x = List<Float64>()
x.add( 1.0d )
x.add( 2.0d )
x.add( 3.0d )
Console.println( MathStats.mean( x ).toString() )   # 2
```

## 1. 基础数学 / 聚合（MathRBasic）

| 方法 | 签名 | 说明 |
|------|------|------|
| `sum` | `Float64 sum(List<Float64> v)` | 求和，空表返回 0 |
| `prod` | `Float64 prod(List<Float64> v)` | 连乘，空表返回 1 |
| `minOf` / `maxOf` | `Float64 minOf(List<Float64> v)` | 最小 / 最大，空表返回 0 |
| `rangeOf` | `Float64 rangeOf(List<Float64> v)` | `maxOf - minOf` |
| `cumsum` | `List<Float64> cumsum(List<Float64> v)` | 累加序列 |
| `diff` | `List<Float64> diff(List<Float64> v)` | 相邻差分，长度 n-1 |
| `factorial` | `Float64 factorial(Int32 n)` | n!，负数返回 0 |
| `choose` | `Float64 choose(Int32 n, Int32 k)` | 组合数 C(n,k)，越界返回 0 |
| `abs` | `Float64 abs(Float64 x)` | 绝对值（委托 Mathd.abs） |
| `roundDigits` | `Float64 roundDigits(Float64 x, Int32 digits)` | 按小数位四舍五入 |
| `ceiling` / `floor` | `Float64 ceiling(Float64 x)` | 向上 / 向下取整 |

三角、指数、对数、平方根等标量函数仍用 `Mathd` / `Mathf` / `Mathh`。

## 2. 统计函数（MathStats）

| 方法 | 签名 | 说明 |
|------|------|------|
| `sum` / `mean` | `Float64 mean(List<Float64> v)` | 求和 / 平均值 |
| `median` | `Float64 median(List<Float64> v)` | 中位数 = `quantile(v, 0.5)` |
| `variance` / `sd` | `Float64 variance(List<Float64> v)` | 样本方差（n-1 分母）、样本标准差 |
| `quantile` | `Float64 quantile(List<Float64> v, Float64 p)` | R type-7 线性插值分位数 |
| `covariance` | `Float64 covariance(List<Float64> x, List<Float64> y)` | 样本协方差 |
| `correlation` | `Float64 correlation(List<Float64> x, List<Float64> y)` | Pearson 相关系数 |
| `scale` | `List<Float64> scale(List<Float64> v)` | 标准化（减均值除标准差，标准差为 0 时返回全 0） |
| `summary` | `string summary(List<Float64> v)` | n/min/q1/median/q3/max/mean/sd 文本摘要 |
| `tTest` | `Float64 tTest(List<Float64> v, Float64 mu)` | 单样本 t 统计量 `(mean-mu)/(sd/sqrt(n))` |
| `chisqTest` | `Float64 chisqTest(List<Float64> obs, List<Float64> exp)` | Pearson 卡方统计量 |
| `aov` | `Float64 aov(List<Float64> a, List<Float64> b)` | 两组单因子方差分析 F 统计量 |
| `lmSlope` / `lmIntercept` | `Float64 lmSlope(List<Float64> x, List<Float64> y)` | 最小二乘斜率 / 截距 |

检验类函数只返回统计量，不返回 p 值；显著性判断需要自行对照分布表。

## 3. 概率分布（MathDist）

| 方法 | 签名 | 说明 |
|------|------|------|
| `setSeed` | `void setSeed(Int32 seed)` | 设置随机种子（对应 R 的 `set.seed`） |
| `uniform01` | `Float64 uniform01()` | (0,1) 均匀随机数 |
| `runif` | `Float64 runif(Float64 lo, Float64 hi)` | 区间均匀随机数 |
| `rnorm` | `Float64 rnorm(Float64 mu, Float64 sd)` | 正态随机数（Box-Muller） |
| `dnorm` | `Float64 dnorm(Float64 x, Float64 mu, Float64 sd)` | 正态密度 |
| `pnorm` | `Float64 pnorm(Float64 x, Float64 mu, Float64 sd)` | 正态分布函数（erf 近似） |
| `qnorm` | `Float64 qnorm(Float64 p, Float64 mu, Float64 sd)` | 正态分位数（二分反解） |
| `rbinom` | `Float64 rbinom(Int32 n, Int32 size, Float64 p)` | n 个二项样本之和 |
| `rpois` | `Float64 rpois(Float64 meanValue)` | 泊松随机数 |
| `rexp` | `Float64 rexp(Float64 rate)` | 指数随机数 |
| `sample` | `List<Float64> sample(List<Float64> v, Int32 k)` | 无放回抽样，返回 k 个元素 |

同一种子下随机数序列可复现。R 的例子用点号命名（`set.seed`），SL 里统一用
`setSeed`。

## 4. 向量操作（MathVec）

| 方法 | 签名 | 说明 |
|------|------|------|
| `seq` | `List<Float64> seq(Float64 from, Float64 to, Float64 by)` | 等差序列，`by=0` 返回空表 |
| `rep` | `List<Float64> rep(Float64 value, Int32 times)` | 重复值 |
| `sort` | `List<Float64> sort(List<Float64> v)` | 升序副本 |
| `order` | `List<Int32> order(List<Float64> v)` | 升序排序后的原始下标 |
| `rev` | `List<Float64> rev(List<Float64> v)` | 反转副本 |
| `unique` | `List<Float64> unique(List<Float64> v)` | 按首次出现顺序去重 |
| `whichEqual` / `whichGreater` | `List<Int32> whichEqual(List<Float64> v, Float64 value)` | 满足条件的下标（等于 / 大于） |
| `matchIndex` | `Int32 matchIndex(Float64 value, List<Float64> table)` | 首次出现下标，找不到返回 -1 |
| `append` | `List<Float64> append(List<Float64> v, Float64 value)` | 追加元素后的副本 |
| `cutIndex` | `Int32 cutIndex(Float64 value, List<Float64> breaks)` | 落入哪个区间 `[breaks[i], breaks[i+1])`，否则 -1 |
| `ifelse` | `List<Float64> ifelse(List<Int32> cond, Float64 yes, Float64 no)` | 掩码非零取 `yes`，否则取 `no` |
| `tableCounts` | `List<Int32> tableCounts(List<Float64> v)` | 频数，与 `sort(unique(v))` 顺序对齐 |
| `modeValue` | `Float64 modeValue(List<Float64> v)` | 出现次数最多的元素，并列取最小 |

`range`、`lambda` 等是 SL 保留字，因此对应入口分别命名为 `rangeOf`、
`rpois(meanValue)`；`table` 的频数结果叫 `tableCounts`。

## 注意事项

- 所有统计函数遇到空表返回 0，`variance`/`sd` 在样本数小于 2 时返回 0。
- `correlation`、`lmSlope` 在方差为 0 时返回 0，避免除零。
- `sample` 与随机数函数共享全局种子状态；需要复现实验时先调用 `setSeed`。
- 这些工具类是 `Float64` 版本；`Float32` 场景可先 `.toFloat64()`、结果再
  `.toFloat32()`。
