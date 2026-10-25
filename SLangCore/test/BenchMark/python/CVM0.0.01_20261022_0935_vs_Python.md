# SLang C VM vs CPython 基准对比报告（基线）

| 项 | 值 |
|---|---|
| 报告时间 | 2026-10-22 09:35 |
| C VM | SimpleLanguage VM **0.0.01** (C Runtime) · Release · MSVC · 构建于 Oct 21 2026 21:30:30 |
| exe 模板 | `csimple_lang\build\Release\bin\csimple_lang.exe`（JIT 编入且默认开、LTO/加固） |
| 对比对象 | CPython **3.14.7**（python.org 官方构建，MSC v.1944，64 bit） |
| 运行方式 | 同机同线程串行实测；SL = publish 产物 `BenchMark.exe` 默认运行（无额外旗标）；Python = 逐项对齐 SL 用例语义的等价脚本 `BenchMarkPython.py` |
| 基线总耗时 | **SL 3371ms vs CPython 734ms → Python 整体快约 4.6×** |

## 一、逐项对比

| 基准项 | SL (ms) | Python (ms) | SL/Py |
|---|---:|---:|---:|
| **Fibonacci** fib(0..21) | 29 | 4 | 7.3× |
| **Loop** 数组求和×3000 | 529 | 87 | 6.1× |
| while 累加 5e6 | 725 | 246 | 2.9× |
| for 步进 1e6 | 18 | 5 | 3.6× |
| **Levenshtein** ×5000 | 309 | 41 | 7.5× |
| **DataTypes** Int32 2e6 | 234 | 68 | 3.4× |
| Int64 2e6 | 291 | 67 | 4.3× |
| 浮点累加 2e6 ¹ | 276 | 73 | 3.8× |
| 混合运算 1e6 ¹ | 199 | 66 | 3.0× |
| bool 取模 1e6 | 246 | 43 | 5.7× |
| **String** 拼接 1e4 | 31 | 1 | ~31× ² |
| 插值 1e4 | 12 | 2 | 6× |
| format 1e4 | 1 | 2 | **0.5×，SL 胜** |
| 比较 1e5 | 19 | 2 | ~9× |
| **RegExp** 编译×2000 ³ | 246 | 1 | ~250× |
| 早命中×500 | 28 | <1 | — |
| 全扫不命中×20 | 2 | <1 | — |
| matchAll×5 | 35 | 9 | 3.9× |
| 替换×5 | 3 | 10 | **0.3×，SL 胜** |
| 分组×200 | 14 | <1 | — |
| backref×10 | 26 | 6 | 4.3× |
| utf8×100 | 5 | <1 | — |
| **总计** | **3371** | **734** | **4.6×** |

交叉验证：同一 exe 复跑默认模式 3393ms、`--no-jit` 3403ms、Release 树直跑 3374ms，均在 ±1% 内。

## 二、数值校验

所有结果值逐一核对一致：fib 28656 / array 998500500000 / while 12499997500000 / step 71428928571 /
lev 3·15000 / Int64 1999999000000 / bool 66667 / 正则 count 12000·4000、len 60000、g1=abc g2=123、
utf8=测试123。仅两处语义性差异属预期：

- Int32 求和：SL 回绕得 -1455759936，Python 任意精度得 1999999000000；
- 浮点两行见发现 1（SL 实际 Float32，Python 为 double）。

## 三、发现

### 1. "Num (double)" 行实际测的是 Float32（基准标注问题，非 VM bug）

SL 输出 2995719503872 与 1.6670932992e11 均为 float32 可精确表示的数（f64 精确值应为
2999998500000 / 166669499997，均不可用 float32 表示）。float32 逐步舍入仿真**逐位复现**两个实测值。
根因：`LexerParseToToken.cs` L886/L899——**无后缀小数字面量（含 0.0）默认 Float32**，`sf = 0.0`
推断为 Float32，整条链路单精度。若要真测 double/Num，字面量需写 `0.0d` / `1.5d`，且
`DataTypes.sl` 该行注释应更正。

### 2. JIT 对本套件零收益（基线）

`--jit-stats`：`compiled=2 bailout=8`，JIT 总耗时 3374ms ≈ `--no-jit` 3393ms。
根因：热度阈值按**方法调用次数**计（默认 1500），而大循环所在方法（`Loop.fun`、`DataTypes.fun` 等）
只被调用 1 次，永远达不到阈值；被编译的 2 个方法（fib、min3 等高频小函数）收益不足以体现。
→ 消除方向：`--jit-methods` eager 清单 + `--jit-warmup` 装配期预热，或阈值策略改为按循环回边计数。

### 3. SL 两项获胜

- `format 1e4`：SL 1ms vs Python 2ms（`str.format` 在 CPython 侧较慢）；
- 正则替换×5：SL C 回溯引擎 3ms 完胜 CPython sre 的 10ms。

### 4. 小问题：GBK 控制台下 SL 中文输出乱码

终端输出 `娴嬭瘯123` 实为 `测试123` 的 UTF-8 字节被按 GBK 解码（UTF-8 终端下直跑同一 exe 显示正常）。
可选修复：Windows 侧 `SetConsoleOutputCP(CP_UTF8)`（按 R3 放 `lib/windows/`）。

## 四、公平性注记

- ¹ SL 该两行为 f32 累加，Python 为 f64（解释器内两者单步耗时相当，倍率仍可比）；
- ² CPython 对 `s = s + "ab"` 有原地拼接优化（摊还 O(n)），SL 为真实重复分配；
- ³ CPython 命中 `re` 内部模式缓存（2000 次编译实为缓存命中 + 对象查找）；即便去缓存
  （C 级解析约 40–100ms），SL 的 SL 代码级模式解析仍有数倍差距；
- CPython 3.14 为自适应特化解释器（3.11 起大幅提速），对比基线较强。

## 五、复现命令

```powershell
# SL 侧（publish 产物）
cd d:\project\lang\SlangAllInOne\SLangCore\test\BenchMark
.\publish\BenchMark.exe                       # 默认（Release 树，JIT 默认开）
.\publish\BenchMark.exe --no-jit              # 关 JIT 对照
.\publish\BenchMark.exe --jit-stats           # 带 JIT 统计

# Python 侧（等价脚本，含 float32 精度仿真诊断段）
python BenchMarkPython.py
```
