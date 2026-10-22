# SLang C VM vs CPython 基准对比报告（-O3 + JIT 全优化）

| 项 | 值 |
|---|---|
| 报告时间 | 2026-10-22 09:41 |
| C VM | SimpleLanguage VM **0.0.01** (C Runtime) · Release · MSVC |
| 优化配置 | Front **`-O3`**；jsonc `publish.config = "Release"`（JIT 编入 + LTO/加固树模板，显式声明）；运行时 **`--jit --jit-warmup --jit-methods=*`**（eager 全量预热编译）+ `--jit-stats` |
| 对比对象 | CPython **3.14.7**（同机复跑，737ms） |
| 对照基线 | `CVM0.0.01_20261022_0935_vs_Python.md`（SL 3371ms / Python 734ms，默认配置） |
| 优化后总耗时 | **SL 3263ms vs CPython 737ms → 差距 4.4×（基线 4.6×）** |

## 一、逐项对比（基线 → 优化）

| 基准项 | 基线 SL | 优化 SL | 变化 | Python | 优化 SL/Py |
|---|---:|---:|---:|---:|---:|
| Fibonacci fib(0..21) | 29 | 30 | ±0 | 4 | 7.5× |
| 数组求和×3000 | 529 | 528 | ±0 | 91 | 5.8× |
| while 累加 5e6 | 725 | 726 | ±0 | 245 | 3.0× |
| for 步进 1e6 | 18 | 18 | ±0 | 5 | 3.6× |
| Levenshtein ×5000 | 309 | **203** | **-34%** | 41 | 5.0× |
| Int32 2e6 | 234 | 235 | ±0 | 66 | 3.6× |
| Int64 2e6 | 291 | 291 | ±0 | 66 | 4.4× |
| 浮点累加 2e6 ¹ | 276 | 276 | ±0 | 74 | 3.7× |
| 混合运算 1e6 ¹ | 199 | 198 | ±0 | 67 | 3.0× |
| bool 取模 1e6 | 246 | 245 | ±0 | 44 | 5.6× |
| 字符串拼接 1e4 | 31 | 33 | ±0 | 1 | ~33× ² |
| 插值 1e4 | 12 | 11 | ±0 | 2 | 5.5× |
| format 1e4 | 1 | 1 | = | 2 | **0.5×，SL 胜** |
| 比较 1e5 | 19 | 19 | ±0 | 2 | ~9× |
| 正则编译×2000 ³ | 246 | 251 | ±0 | 1 | ~250× |
| matchAll×5 | 35 | 35 | ±0 | 10 | 3.5× |
| 正则替换×5 | 3 | 3 | = | 9 | **0.3×，SL 胜** |
| backref×10 | 26 | 25 | ±0 | 7 | 3.6× |
| **总计** | **3371** | **3263** | **-3.2%** | **737** | **4.4×** |

省略的 <10ms 正则子项（早命中 28/<1、全扫 2/<1、分组 12/<1、utf8 5/<1）与基线持平。
数值校验：所有结果值与基线完全一致（-O3 未改变语义；浮点两行仍为 Float32 路径，见基线报告发现 1）。

## 二、优化归因

### 1. 提升全部来自 -O3（Levenshtein -34%）

隔离实验：`-O3 + --no-jit` = **3264ms** ≈ `-O3 + JIT 全开` = **3263ms**。
唯一显著变化是 Levenshtein 309→203ms，推测为 -O3 高优化级下方法内联类优化生效
（编译阶段含 AutoInlineMark，min3 这类每 DP 格调用的leaf函数被内联后调用开销消失）；
其余 17 项全部持平。

### 2. JIT 贡献为零——瓶颈在 opcode 覆盖，不在触发策略

eager 预热（`--jit-methods=* --jit-warmup`，装配期不等热度直接编译）后 JIT 统计：

```
compiled=1  bailout=7  failed=0  runs(done)=91213  runs(yield)=91198
```

- 8 个尝试编译的方法 **7 个 bail out**：大循环所在的 `*.fun` 方法含 JIT 尚未支持的
  opcode（BAILOUT 类），编译即退场、回退解释执行——这正是基线"热度阈值永远达不到"
  之外的第二层原因，且 eager 也绕不过；
- 唯一编入的方法（fib）91198 次运行几乎**全部 yield 回解释器**
  （runs(yield) ≈ fib 调用总数 9.3 万），fib 耗时 30ms 与基线 29ms 无差；
- 结论：调阈值 / 加 warmup 均无效，**收窄 BAILOUT 指令类、扩大 JIT 可编译范围是当前
  最大单点优化机会**——while 5e6（726ms，占总时长 22%）与数组求和（528ms，16%）
  两项合计近 4 成耗时，均因 bail 而全程解释执行。

### 3. 与 Python 差距：4.6× → 4.4×

SL 两项获胜保持：format（1ms vs 2ms）、正则替换（3ms vs 9ms，C 回溯引擎快于 CPython sre）。

## 三、沿用基线报告的发现

Float32 标注问题、GBK 控制台乱码、公平性注记（¹ ² ³）均不变，
详见 `CVM0.0.01_20261022_0935_vs_Python.md` 第三节、第四节。

## 四、复现命令

```powershell
# ① 发布（-O3 + Release 模板；publish 段 config 已显式 Release）
SlangAllInOne\out\host\slang.exe publish SlangAllInOne\SLangCore\test\BenchMark -O3

# ② 全优化运行（JIT eager 预热全量编译）
cd SlangAllInOne\SLangCore\test\BenchMark\publish
.\BenchMark.exe --jit --jit-warmup --jit-methods=* --jit-stats

# ③ 隔离 -O3 单独贡献（关 JIT）
.\BenchMark.exe --no-jit

# ④ Python 对照
python ..\BenchMarkPython.py
```
