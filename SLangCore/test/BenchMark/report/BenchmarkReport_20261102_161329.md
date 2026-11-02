# SLang 多语言 Benchmark 对比报告

- 生成时间: 2026-11-02 16:13:29
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

## 耗时对比总表（毫秒，越小越快）

| 测试类型 | 参数 | SL | CSharp | Java | JavaScript |
|----------|------|----|--------|------|------------|
| Fibonacci | fib(0..21) 递归求和 | 37 | - | - | - |
| EqBench | i32 != 2e6 | 321 | - | - | - |
| EqBench | i64 != 2e6 | 336 | - | - | - |
| EqBench | f64 != 2e6 | 290 | - | - | - |
| EqBench | bool == 1e6 | 274 | - | - | - |
| Loop | array sum x3000 | 672 | - | - | - |
| Loop | while sum 5e6 | 932 | - | - | - |
| Loop | for step +7 1e6 | 26 | - | - | - |
| Levenshtein | levenshtein x5000 | 390 | - | - | - |
| DataTypes | Int32 sum 2e6 | 343 | - | - | - |
| DataTypes | Int64 sum 2e6 | 372 | - | - | - |
| DataTypes | Num sum 2e6 | 406 | - | - | - |
| DataTypes | Mixed ops 1e6 | 288 | - | - | - |
| DataTypes | bool mod 1e6 | 318 | - | - | - |
| StringBench | concat 1e4 | 40 | - | - | - |
| StringBench | interp 1e4 | 14 | - | - | - |
| StringBench | format 1e4 | 2 | - | - | - |
| StringBench | compare 1e5 | 22 | - | - | - |
| RegExpBench | compile x2000 | 101 | - | - | - |
| RegExpBench | search hit x500 | 15 | - | - | - |
| RegExpBench | search miss x20 | 1 | - | - | - |
| RegExpBench | matchAll x5 | 36 | - | - | - |
| RegExpBench | replace x5 | 4 | - | - | - |
| RegExpBench | group search x200 | 7 | - | - | - |
| RegExpBench | backref matchAll x10 | 26 | - | - | - |
| RegExpBench | utf8 search x100 | 3 | - | - | - |
| NQueens | nqueens(11) 单轮 | 4974 | - | - | - |
| NQueens | nqueens(9) x10 | 1712 | - | - | - |
| Sieve | sieve 1e6 单轮 | 565 | - | - | - |
| Sieve | sieve 5e5 x5 | 1392 | - | - | - |
| QuickSort | quicksort 3e4 x5 | 1121 | - | - | - |
| MatrixMul | matmul 100x100 x3 | 1211 | - | - | - |
| BinaryTree | tree depth12 x10 | 146 | - | - | - |
| BinaryTree | tree depth16 x2 | 459 | - | - | - |
| Mandelbrot | mandelbrot 240x180 x3 | 1254 | - | - | - |
| Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | - | 69 | 62 | 5 |
| EqBench | 4子项整块（含引擎开销） | - | 20 | 22 | 449 |
| Loop | 3子项整块（含引擎开销） | - | 12 | 11 | 518 |
| Levenshtein | levenshtein x5000（整块含引擎开销） | - | 2 | 5 | 63 |
| DataTypes | 5子项整块（含引擎开销） | - | 16 | 27 | 540 |
| StringBench | 4子项整块（含引擎开销） | - | 106 | 91 | 21 |
| RegExpBench | 8子项整块（含引擎开销） | - | 480 | 125 | 270 |
| NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | - | 32 | 25 | 1308 |
| Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | - | 16 | 26 | 706 |
| QuickSort | quicksort 3e4 x5（整块含引擎开销） | - | 11 | 19 | 296 |
| MatrixMul | matmul 100x100 x3（整块含引擎开销） | - | 4 | 9 | 323 |
| BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | - | 21 | 6 | 126 |
| Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | - | 12 | 13 | 341 |

## 附录: 全部原始条目

| 序号 | 语言 | 测试类型 | 参数 | 运行时间(ms) |
|------|------|----------|------|--------------|
| 1 | SL | Fibonacci | fib(0..21) 递归求和 | 37 |
| 2 | SL | EqBench | i32 != 2e6 | 321 |
| 3 | SL | EqBench | i64 != 2e6 | 336 |
| 4 | SL | EqBench | f64 != 2e6 | 290 |
| 5 | SL | EqBench | bool == 1e6 | 274 |
| 6 | SL | Loop | array sum x3000 | 672 |
| 7 | SL | Loop | while sum 5e6 | 932 |
| 8 | SL | Loop | for step +7 1e6 | 26 |
| 9 | SL | Levenshtein | levenshtein x5000 | 390 |
| 10 | SL | DataTypes | Int32 sum 2e6 | 343 |
| 11 | SL | DataTypes | Int64 sum 2e6 | 372 |
| 12 | SL | DataTypes | Num sum 2e6 | 406 |
| 13 | SL | DataTypes | Mixed ops 1e6 | 288 |
| 14 | SL | DataTypes | bool mod 1e6 | 318 |
| 15 | SL | StringBench | concat 1e4 | 40 |
| 16 | SL | StringBench | interp 1e4 | 14 |
| 17 | SL | StringBench | format 1e4 | 2 |
| 18 | SL | StringBench | compare 1e5 | 22 |
| 19 | SL | RegExpBench | compile x2000 | 101 |
| 20 | SL | RegExpBench | search hit x500 | 15 |
| 21 | SL | RegExpBench | search miss x20 | 1 |
| 22 | SL | RegExpBench | matchAll x5 | 36 |
| 23 | SL | RegExpBench | replace x5 | 4 |
| 24 | SL | RegExpBench | group search x200 | 7 |
| 25 | SL | RegExpBench | backref matchAll x10 | 26 |
| 26 | SL | RegExpBench | utf8 search x100 | 3 |
| 27 | SL | NQueens | nqueens(11) 单轮 | 4974 |
| 28 | SL | NQueens | nqueens(9) x10 | 1712 |
| 29 | SL | Sieve | sieve 1e6 单轮 | 565 |
| 30 | SL | Sieve | sieve 5e5 x5 | 1392 |
| 31 | SL | QuickSort | quicksort 3e4 x5 | 1121 |
| 32 | SL | MatrixMul | matmul 100x100 x3 | 1211 |
| 33 | SL | BinaryTree | tree depth12 x10 | 146 |
| 34 | SL | BinaryTree | tree depth16 x2 | 459 |
| 35 | SL | Mandelbrot | mandelbrot 240x180 x3 | 1254 |
| 36 | CSharp | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 69 |
| 37 | CSharp | EqBench | 4子项整块（含引擎开销） | 20 |
| 38 | CSharp | Loop | 3子项整块（含引擎开销） | 12 |
| 39 | CSharp | Levenshtein | levenshtein x5000（整块含引擎开销） | 2 |
| 40 | CSharp | DataTypes | 5子项整块（含引擎开销） | 16 |
| 41 | CSharp | StringBench | 4子项整块（含引擎开销） | 106 |
| 42 | CSharp | RegExpBench | 8子项整块（含引擎开销） | 480 |
| 43 | CSharp | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 32 |
| 44 | CSharp | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 16 |
| 45 | CSharp | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 11 |
| 46 | CSharp | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 4 |
| 47 | CSharp | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 21 |
| 48 | CSharp | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 12 |
| 49 | Java | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 62 |
| 50 | Java | EqBench | 4子项整块（含引擎开销） | 22 |
| 51 | Java | Loop | 3子项整块（含引擎开销） | 11 |
| 52 | Java | Levenshtein | levenshtein x5000（整块含引擎开销） | 5 |
| 53 | Java | DataTypes | 5子项整块（含引擎开销） | 27 |
| 54 | Java | StringBench | 4子项整块（含引擎开销） | 91 |
| 55 | Java | RegExpBench | 8子项整块（含引擎开销） | 125 |
| 56 | Java | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 25 |
| 57 | Java | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 26 |
| 58 | Java | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 19 |
| 59 | Java | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 9 |
| 60 | Java | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 6 |
| 61 | Java | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 13 |
| 62 | JavaScript | Fibonacci | fib(0..21) 递归求和（整块含引擎开销） | 5 |
| 63 | JavaScript | EqBench | 4子项整块（含引擎开销） | 449 |
| 64 | JavaScript | Loop | 3子项整块（含引擎开销） | 518 |
| 65 | JavaScript | Levenshtein | levenshtein x5000（整块含引擎开销） | 63 |
| 66 | JavaScript | DataTypes | 5子项整块（含引擎开销） | 540 |
| 67 | JavaScript | StringBench | 4子项整块（含引擎开销） | 21 |
| 68 | JavaScript | RegExpBench | 8子项整块（含引擎开销） | 270 |
| 69 | JavaScript | NQueens | n=11 单轮 + n=9 x10（整块含引擎开销） | 1308 |
| 70 | JavaScript | Sieve | 1e6 单轮 + 5e5 x5（整块含引擎开销） | 706 |
| 71 | JavaScript | QuickSort | quicksort 3e4 x5（整块含引擎开销） | 296 |
| 72 | JavaScript | MatrixMul | matmul 100x100 x3（整块含引擎开销） | 323 |
| 73 | JavaScript | BinaryTree | depth12 x10 + depth16 x2（整块含引擎开销） | 126 |
| 74 | JavaScript | Mandelbrot | mandelbrot 240x180 x3（整块含引擎开销） | 341 |
