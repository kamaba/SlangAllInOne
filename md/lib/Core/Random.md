# Random.sl

> 源文件：`Random.sl`

## class `Random`

- **说明**：伪随机数生成器：基于线性同余算法（LCG，a=1103515245 c=12345 m=2^31-1）按种子生成确定性随机序列，支持整型 / 浮点 / 区间取样。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _seed = 0` | 字段 _seed（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 构造 | `_init_(Int32 initialSeed)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int32 advance()` | Advance the linear congruential generator and return the new state. |
| 方法 | `Int32 nextInt(Int32 max)` | Generate random int in range [0, max) |
| 方法 | `Int32 nextInt(Int32 min, Int32 max)` | Generate random int in range [min, max) |
| 方法 | `Num nextFloat()` | Generate random Num in range [0.0, 1.0) |
| 方法 | `Num nextFloat(Num min, Num max)` | Generate random Num in range [min, max) |
| 方法 | `bool nextBool()` | Generate random bool |
| 方法 | `Int32 randomInt(Int32 max)` | Static convenience methods |
| 方法 | `Num randomFloat()` | 执行 randomFloat()。 |
| 方法 | `Num randomFloat(Num min, Num max)` | 执行 randomFloat(min, max)，行为详见源实现。 |
