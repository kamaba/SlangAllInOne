# SLang C VM vs CPython 基准对比报告（传统算法用例新增批次）

| 项 | 值 |
|---|---|
| 报告时间 | 2026-10-23 03:50 |
| C VM | SimpleLanguage VM **0.0.01** (C Runtime) · Release 模板（JIT 编入且默认开） |
| 用例批次 | **新增 6 个传统语言基准**：NQueens（八皇后）/ Sieve（素数筛）/ QuickSort（快排）/ MatrixMul（矩阵乘法）/ BinaryTree（二叉树）/ Mandelbrot（曼德博集） |
| 对比对象 | CPython **3.14.7**（同机同线程串行实测） |
| 运行方式 | SL = publish 产物 `publish\release\BenchMark.exe` 默认运行；Python = `BenchMarkPython.py`（逐项镜像：同算法、同数据、同计时口径）；两侧各 3 轮取中位数 |
| 新增段总耗时 | **SL 14749ms vs CPython 2083ms → 整体 7.1×**（剔除二叉树后 4.9×） |
| 全套件总耗时 | SL 18471ms vs CPython 2868ms → 6.4× |

## 一、新增用例逐项对比（3 轮中位数）

| 基准项 | 考察维度 | SL (ms) | Python (ms) | SL/Py | 结果值（两侧一致） |
|---|---|---:|---:|---:|---|
| **NQueens** n=11（2680 解） | 递归回溯 + 剪枝 | 3936 | 696 | 5.7× | 2680 |
| **NQueens** n=9 ×10 | 同上（多轮） | 1357 | 241 | 5.6× | 3520 |
| **Sieve** 1e6 | 数组标记 + 步进循环 | 452 | 100 | 4.5× | 78498 |
| **Sieve** 5e5 ×5 | 同上（多轮） | 1115 | 236 | 4.7× | 207690 |
| **QuickSort** 3e4 ×5（Hoare 分区） | 递归 + 分区交换 + LCG 数据 | 960 | 169 | 5.7× | checksum 161115501280132 |
| **MatrixMul** 100×100 ×3（扁平数组） | 三重循环 + 下标算术 | 928 | 268 | 3.5× | checksum 2450250000 |
| **BinaryTree** depth12 ×10 | 对象分配 + GC + 递归 | 1194 | 17 | **~70×** | 335523825 |
| **BinaryTree** depth16 ×2 | 同上（大树） | 3793 | 55 | **~69×** | 5726557525 |
| **Mandelbrot** 240×180 ×3（Float64） | 浮点迭代 + 逃逸判断 | 1014 | 301 | 3.4× | iterSum 2256993 / inside 12480 |
| **新增段合计** | | **14749** | **2083** | **7.1×** | |
| （剔除 BinaryTree） | | 9762 | 2011 | 4.9× | |

## 二、数值校验

所有结果值逐一核对**完全一致**（含浮点逐位一致）：

- NQueens 2680 / 3520（公开已知解数）；Sieve 78498 / 207690（已知素数计数）；
- QuickSort：两侧用同一 Park-Miller LCG（`seed*16807 % 2147483647`，Int64）生成数据，排序后校验和与有序性检查均通过；
- MatrixMul / BinaryTree 校验和一致；Mandelbrot 的 iterSum 与 inside 计数**逐位一致**——
  SL 侧浮点字面量统一带 `d` 后缀（`0.0d`/`4.0d`）走 Float64 管线，与 CPython double 同口径，
  边界逃逸判定完全相同（对照：`DataTypes.sl` 无后缀字面量仍走 Float32，见旧报告发现 1）。

## 三、发现

### 1. 对象分配/GC/字段访问是最大短板（BinaryTree ~69×）

depth16 每树 65535 节点：SL 单节点"构建+求和"约 **29µs**，CPython 约 **0.42µs**（CPython 池化分配 +
自适应解释器字段特化）。同为递归密集型的 NQueens（5.7×）/ QuickSort（5.7×）没有如此悬殊，说明差距主因
不在调用开销，而在**节点对象分配 + GC 压力 + 字段读写**链路。这是当前最值得投入的单点优化方向
（对象内联分配 / 分代收集 / 字段槽直接寻址）。

### 2. 紧凑数值循环最接近 CPython（3.4×–4.7×）

Mandelbrot（Float64，3.4×）、MatrixMul（3.5×）、Sieve（4.5–4.7×）——无函数调用、无对象分配的
纯数值/数组循环是 SL 相对最强的形态；`d` 后缀的 Float64 管线表现好于预期。

### 3. 递归调用形态稳定落后 ~5.6–5.7×

NQueens/QuickSort 与旧用例 Fibonacci（7.3×）、Levenshtein（7.5×→O3 后 5.0×）一致，
解释器调用帧构建成本约为 CPython 3.14（调用内联化）的 5 倍以上。

### 4. JIT 对新增用例贡献仍为零

`--no-jit` 全套件 18322ms ≈ 默认（JIT 开）18471ms（±1%）。与旧报告结论一致：
大循环所在方法因 BAILOUT 指令类无法编入，JIT 命中不了热点。

### 5. 开发中发现：Int32 + Int64 混算链被截断回绕（疑似 VM/前端语义缺陷）

BinaryTree 首版 `int value` 字段参与 `node.value + checksum(left) + checksum(right)`（Int64）加法链，
depth16 求和 5726557525 被回绕为 1431590229（= 5726557525 mod 2^32），即混合加法实际按 32 位截断，
与 `md/syntax/number.md`"整数运算提升为有符号 long"的规范不符。规避方式：节点字段直接声明为
`Int64`（本次已采用）。建议单独立项核查运算提升路径。

## 四、公平性注记

- Python 侧 `BenchNode` 使用 `__slots__`（贴近 SL 固定字段对象，且是 Python 较快形态）；
- 两侧计时均排除数据准备（LCG 生成 / 矩阵填充 / 文本构建），只计核心计算段；
- CPython 3.14 为自适应特化解释器，基线较强；SL 为 Release 模板（JIT 默认开）；
- 旧段（Fibonacci~RegExpBench）本次同机复测与 2026-10-22 基线一致（±10% 内，机器状态差异），
  本报告表格仅列新增段，全套件端到端见文首。

## 五、复现命令

```powershell
# SL 侧（publish 产物，Release 模板）
out\host\slang.exe publish SlangAllInOne\SLangCore\test\BenchMark --no-banner
cd SlangAllInOne\SLangCore\test\BenchMark\publish\release
.\BenchMark.exe                # 默认（JIT 开）
.\BenchMark.exe --no-jit       # 关 JIT 对照

# Python 侧（等价镜像脚本）
cd SlangAllInOne\SLangCore\test\BenchMark
python BenchMarkPython.py
```

新增用例文件：`NQueens.sl` / `Sieve.sl` / `QuickSort.sl` / `MatrixMul.sl` / `BinaryTree.sl` / `Mandelbrot.sl`
（已在 `BenchMark.jsonc` 注册、`BenchMark.sp::_main_` 接入，Python 镜像在 `BenchMarkPython.py` 同名段落）。
