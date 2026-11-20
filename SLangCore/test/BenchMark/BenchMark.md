# BenchMark Project Guide

- Project Entry File: `BenchMark.sp`
- Project Config File: `BenchMark.jsonc`

## Project Entry Conventions

### `_main_`

Primary runtime entry. Normal execution starts here.

### `_test_`

Test entry. Used when test mode is enabled.

### `_before_`

Compile pre-hook entry (Project class). Executed before compilation.

### `_after_`

Compile post-hook entry (Project class). Executed after compilation, before IR export.

## Global Integration

`global.xxx` / `global.func()` is integrated with `Project{}` semantic source.

### JSONC `data` on `Project`

Prefer a root-level `"data": { ... }` block. Legacy `"global"."data"` is still read; root keys override on name clash.

- Primitive values (`int32`/`string`/`float`/`bool`/`null`) are injected as **static members on `Project`** (not on the compiler `global` MetaData shell). Access via `global.<name>`. 
- Array values are supported (primitive and nested arrays), e.g. `global.arr[0]`, `global.arr2[1][0]`. 
- Object values become `MetaData` shape types, still as **fields on `Project`**, e.g. `global.vardata2.a`. 

## Example

```jsonc
"data": {
  "var1": 12,
  "arr": [1,2,3],
  "arr2": [[1,2],[3,4]],
  "vardata2": { "a": 10, "b": 20, "flags": [true,false] }
},
"global": {
  "imports": ["Some.Module"]
}
```

Access:

- `global.var1`
- `global.arr[0]`
- `global.arr2[1][0]`
- `global.vardata2.a`
- `global.vardata2.b`

## 多语言基准套件

13 项共享基准（HelloWorld/Fibonacci/EqBench/Loop/Levenshtein/DataTypes/
StringBench/RegExpBench/NQueens/Sieve/QuickSort/MatrixMul/BinaryTree/
Mandelbrot）逐项同算法同参数，跨语言校验和可对拍。各语言一个 Bench 文件，
经各自插件内嵌/外接运行时执行：

| 语言列 | 文件 | 插件 / 运行时 | 计时口径 |
|--------|------|---------------|----------|
| SL | `Fibonacci.sl` 等 13 个 | SL VM 字节码（JIT 默认开） | SL 侧 nowMillis ms×1000 存 us |
| C / C++ | `CBench.sl` / `CppBench.sl` | cplus_clang（cl /O2 原生） | 块内 QPC/steady_clock ns /1000 |
| ASM | `MasmBench.sl` | masm_x64（ml64，含 SimdAVX2 专列） | SL 侧 nowMillis 整块（asm 出通道兜底） |
| CSharp | `CSharpBench.sl` | csharp_mono（Mono JIT） | 块内 Stopwatch us |
| Java | `JavaBench.sl` | java_hotspot（HotSpot JIT） | 块内 nanoTime ns /1000 |
| JavaScript | `JsBench.sl` | javascript_quickjs（解释器） | 块内 Date.now ms×1000 |
| JavaScriptV8 | `TypeScriptBench.sl` | typescript_nodev8（Node V8 JIT） | 块内 performance.now us |
| Python | `PythonBench.sl` | python_cpython（CPython 解释器） | 块内 perf_counter_ns //1000 |
| **PHP** | **`PhpBench.sl`** | **php_embed（PHP 8.4 embed SAPI，vendored php8ts.dll TS x64，Zend 解释器无 JIT）** | **块内 hrtime(true) intdiv(...,1000) 回传 us** |

- 采集器 = `BenchCollector.sl`：各语言 `record<Lang>` 便捷入口统一存 us；
  `generateReport()` 在 `_main_` 结尾调用一次，按测试类型归并横向对比总表
  （含 PHP 列）+ 语言说明表 + 全量原始条目附录，时间戳命名
  `report/BenchmarkReport_yyyyMMdd_HHmmss.md` 写入进程工作目录。
- PHP 套件（2026-11-20 新增）：递归助手用闭包 `use(&$fn)`、类树用匿名类
  （驻留解释器全局作用域共享，避全局 function/class 跨块重声明致命）；
  出通道表达式加小括号规避 Front「出通道不可以 $ 开头」铁律。块产物
  `Entry_N.php` 部署 `plugin/php_embed/package/windows/phpsrc/`（与 pysrc /
  SLCpp.dll / java classes 同款共享部署位，后编译覆盖）——**运行 BenchMark
  前须最后编译本工程**。PHP 运行时随插件包 vendored，无需本机另装 PHP。
- 隔离冒烟：`test/Other/PhpBenchTest/`（只编译 PhpBench.sl + BenchCollector.sl，
  单独验证 PHP 计时与报告列，不依赖其它语言运行时）。
