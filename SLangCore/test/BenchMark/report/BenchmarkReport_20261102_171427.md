# SLang 多语言 Benchmark 对比报告

- 生成时间: 2026-11-02 17:14:27
- 数据条目: 74 条
- 计时口径: 全部为毫秒（Environment.sys.nowMillis / Stopwatch / System.nanoTime / Date.now）
- CSharp/Java/JavaScript 为插件块整块计时，含引擎调用开销，首轮另含编译部署

## 语言与优化说明

| 语言 | 使用说明 | 优化选项 |
|------|----------|----------|
| SL | SLang 自研语言，SL VM 字节码解释执行 | VM 默认（无 JIT） |
| CSharp | C# / mono 运行时（csharp_mono 插件内嵌） | Mono JIT 默认优化 |
| Java | Java 17 / Hotspot 运行时（java_hotspot 插件内嵌） | HotSpot 分层 JIT |
| JavaScript | JavaScript / QuickJS 2024-01-13（javascript_quickjs 插件内嵌） | QuickJS 解释器（无 JIT） |

## 耗时对比总表（毫秒，越小越快，单元格为该测试全部子项耗时合计）

| 测试类型 | 参数 | SL | CSharp | Java | JavaScript |
|----------|------|----|--------|------|------------|
| Fibonacci | fib(0..21) 递归求和 | 36 | 93 | 61 | 5 |
| EqBench | i32 != 2e6 等 4 子项 | 1204 | 21 | 22 | 447 |
| Loop | array sum x3000 等 3 子项 | 1631 | 12 | 11 | 519 |
| Levenshtein | levenshtein x5000 | 389 | 2 | 5 | 61 |
| DataTypes | Int32 sum 2e6 等 5 子项 | 1734 | 16 | 26 | 541 |
| StringBench | concat 1e4 等 4 子项 | 77 | 94 | 80 | 21 |
| RegExpBench | compile x2000 等 8 子项 | 185 | 459 | 112 | 266 |
| NQueens | nqueens(11) 单轮 等 2 子项 | 6712 | 31 | 26 | 1305 |
| Sieve | sieve 1e6 单轮 等 2 子项 | 1971 | 18 | 25 | 695 |
| QuickSort | quicksort 3e4 x5 | 1118 | 11 | 20 | 295 |
| MatrixMul | matmul 100x100 x3 | 1217 | 5 | 8 | 311 |
| BinaryTree | tree depth12 x10 等 2 子项 | 596 | 21 | 6 | 119 |
| Mandelbrot | mandelbrot 240x180 x3 | 1261 | 13 | 12 | 341 |

## 附录: 全部原始条目

| 序号 | 语言 | 测试类型 | 参数 | 运行时间(ms) |
|------|------|----------|------|--------------|
| 1 | SL | Fibonacci | fib(0..21) 递归求和 | 36 |
| 2 | SL | EqBench | i32 != 2e6 | 321 |
| 3 | SL | EqBench | i64 != 2e6 | 321 |
| 4 | SL | EqBench | f64 != 2e6 | 288 |
| 5 | SL | EqBench | bool == 1e6 | 274 |
| 6 | SL | Loop | array sum x3000 | 675 |
| 7 | SL | Loop | while sum 5e6 | 930 |
| 8 | SL | Loop | for step +7 1e6 | 26 |
| 9 | SL | Levenshtein | levenshtein x5000 | 389 |
| 10 | SL | DataTypes | Int32 sum 2e6 | 344 |
| 11 | SL | DataTypes | Int64 sum 2e6 | 373 |
| 12 | SL | DataTypes | Num sum 2e6 | 408 |
| 13 | SL | DataTypes | Mixed ops 1e6 | 291 |
| 14 | SL | DataTypes | bool mod 1e6 | 318 |
| 15 | SL | StringBench | concat 1e4 | 39 |
| 16 | SL | StringBench | interp 1e4 | 14 |
| 17 | SL | StringBench | format 1e4 | 2 |
| 18 | SL | StringBench | compare 1e5 | 22 |
| 19 | SL | RegExpBench | compile x2000 | 95 |
| 20 | SL | RegExpBench | search hit x500 | 15 |
| 21 | SL | RegExpBench | search miss x20 | 1 |
| 22 | SL | RegExpBench | matchAll x5 | 35 |
| 23 | SL | RegExpBench | replace x5 | 4 |
| 24 | SL | RegExpBench | group search x200 | 8 |
| 25 | SL | RegExpBench | backref matchAll x10 | 25 |
| 26 | SL | RegExpBench | utf8 search x100 | 2 |
| 27 | SL | NQueens | nqueens(11) 单轮 | 4978 |
| 28 | SL | NQueens | nqueens(9) x10 | 1734 |
| 29 | SL | Sieve | sieve 1e6 单轮 | 572 |
| 30 | SL | Sieve | sieve 5e5 x5 | 1399 |
| 31 | SL | QuickSort | quicksort 3e4 x5 | 1118 |
| 32 | SL | MatrixMul | matmul 100x100 x3 | 1217 |
| 33 | SL | BinaryTree | tree depth12 x10 | 143 |
| 34 | SL | BinaryTree | tree depth16 x2 | 453 |
| 35 | SL | Mandelbrot | mandelbrot 240x180 x3 | 1261 |
| 36 | CSharp | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 93 |
| 37 | CSharp | EqBench | 4子项整块（含引擎开销） | 21 |
| 38 | CSharp | Loop | 3子项整块（含引擎开销） | 12 |
| 39 | CSharp | Levenshtein | levenshtein x5000（整块含引擎开销） | 2 |
| 40 | CSharp | DataTypes | 5子项整块（含引擎开销） | 16 |
| 41 | CSharp | StringBench | 4子项整块（含引擎开销） | 94 |
| 42 | CSharp | RegExpBench | 8子项整块（含引擎开销） | 459 |
| 43 | CSharp | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 31 |
| 44 | CSharp | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 18 |
| 45 | CSharp | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 11 |
| 46 | CSharp | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 5 |
| 47 | CSharp | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 21 |
| 48 | CSharp | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 13 |
| 49 | Java | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 61 |
| 50 | Java | EqBench | 4子项整块（含引擎开销） | 22 |
| 51 | Java | Loop | 3子项整块（含引擎开销） | 11 |
| 52 | Java | Levenshtein | levenshtein x5000（整块含引擎开销） | 5 |
| 53 | Java | DataTypes | 5子项整块（含引擎开销） | 26 |
| 54 | Java | StringBench | 4子项整块（含引擎开销） | 80 |
| 55 | Java | RegExpBench | 8子项整块（含引擎开销） | 112 |
| 56 | Java | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 26 |
| 57 | Java | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 25 |
| 58 | Java | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 20 |
| 59 | Java | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 8 |
| 60 | Java | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 6 |
| 61 | Java | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 12 |
| 62 | JavaScript | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 5 |
| 63 | JavaScript | EqBench | 4子项整块（含引擎开销） | 447 |
| 64 | JavaScript | Loop | 3子项整块（含引擎开销） | 519 |
| 65 | JavaScript | Levenshtein | levenshtein x5000（整块含引擎开销） | 61 |
| 66 | JavaScript | DataTypes | 5子项整块（含引擎开销） | 541 |
| 67 | JavaScript | StringBench | 4子项整块（含引擎开销） | 21 |
| 68 | JavaScript | RegExpBench | 8子项整块（含引擎开销） | 266 |
| 69 | JavaScript | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 1305 |
| 70 | JavaScript | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 695 |
| 71 | JavaScript | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 295 |
| 72 | JavaScript | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 311 |
| 73 | JavaScript | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 119 |
| 74 | JavaScript | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 341 |
