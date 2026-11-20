# SLang 多语言 Benchmark 对比报告

- 生成时间: 2026-11-20 10:46:40
- 数据条目: 13 条
- 计时口径: 时间存储单位一律微秒；SL 为 SL 侧 nowMillis 毫秒计时（×1000 存 us）；C/C++/CSharp/Java/JS/TS/Python/PHP 为块内自身计时经出通道回传（不含引擎装载/编译部署开销）——C/C++ QPC/steady_clock ns（/1000 存 us，原始 ns 见运行日志）、CSharp Stopwatch（us）、Java System.nanoTime（ns /1000 折 us）、JS QuickJS Date.now（ms ×1000 存 us，粒度毫秒）、TS performance.now（亚毫秒 ms ×1000 折 us）、Python perf_counter_ns（块内 //1000 回传 us，原始 ns 见运行日志）、PHP hrtime(true)（块内 intdiv(...,1000) 回传 us，原始 ns 见运行日志）；ASM 因出通道回传失效改用 SL 侧 nowMillis 整块计时（含 trampoline 开销，ms×1000 存 us，块内 QPC printf 原始 ns 见运行日志）
- 单元格显示自适应单位（us 值过大时折算 ms），附录保留原始微秒值
- C/C++/CSharp/Java/JavaScript/TypeScript/Python/PHP 均为块内自身计时；CSharp/Java/TypeScript 首轮块内另含运行时 JIT/解释预热

## 语言与优化说明

| 语言 | 使用说明 | 优化选项 |
|------|----------|----------|
| PHP | PHP 8.4 / embed SAPI 内嵌（php_embed 插件，vendored php8ts.dll TS x64） | PHP Zend 字节码解释器（无 JIT），块内 hrtime(true) 计时（us 回传） |

## 耗时对比总表（自适应单位，越小越快，单元格为该测试全部子项耗时合计）

| 测试类型 | 参数 | SL | C | C++ | ASM | CSharp | Java | JavaScript | JavaScriptV8 | Python | PHP |
|----------|------|----|---|-----|-----|--------|------|------------|--------------|--------|-----|
| Fibonacci | fib(0..21) 递归求和（块内 ns→us） | - | - | - | - | - | - | - | - | - | 4ms |
| EqBench | i32/i64/f64/bool 4 子项（块内 ns→us） | - | - | - | - | - | - | - | - | - | 123ms |
| Loop | 数组迭代求和 x3000/while 5e6/step 1e6 3 子项（块内 ns→us） | - | - | - | - | - | - | - | - | - | 123ms |
| Levenshtein | 滚动数组 DP x5000（块内 ns→us） | - | - | - | - | - | - | - | - | - | 24ms |
| DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us） | - | - | - | - | - | - | - | - | - | 139ms |
| StringBench | 字符串拼接/插值/sprintf/比较 4 子项（块内 ns→us） | - | - | - | - | - | - | - | - | - | 5ms |
| RegExpBench | preg_* 8 子项（块内 ns→us） | - | - | - | - | - | - | - | - | - | 6ms |
| NQueens | n=11 单轮 + n=9 x10（块内 ns→us） | - | - | - | - | - | - | - | - | - | 631ms |
| Sieve | 数组筛 1e6 单轮 + 5e5 x5（块内 ns→us） | - | - | - | - | - | - | - | - | - | 286ms |
| QuickSort | 原生 sort 3e4 x5（块内 ns→us） | - | - | - | - | - | - | - | - | - | 24ms |
| MatrixMul | 嵌套数组矩阵乘 100x100 x3（块内 ns→us） | - | - | - | - | - | - | - | - | - | 69ms |
| BinaryTree | 匿名类树递归 depth12 x10 + depth16 x2（块内 ns→us） | - | - | - | - | - | - | - | - | - | 68ms |
| Mandelbrot | 240x180 x3（块内 ns→us） | - | - | - | - | - | - | - | - | - | 127ms |

## 附录: 全部原始条目

| 序号 | 语言 | 测试类型 | 参数 | 运行时间(us) |
|------|------|----------|------|--------------|
| 1 | PHP | Fibonacci | fib(0..21) 递归求和（块内 ns→us） | 4520 |
| 2 | PHP | EqBench | i32/i64/f64/bool 4 子项（块内 ns→us） | 123146 |
| 3 | PHP | Loop | 数组迭代求和 x3000/while 5e6/step 1e6 3 子项（块内 ns→us） | 123302 |
| 4 | PHP | Levenshtein | 滚动数组 DP x5000（块内 ns→us） | 24358 |
| 5 | PHP | DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us） | 139343 |
| 6 | PHP | StringBench | 字符串拼接/插值/sprintf/比较 4 子项（块内 ns→us） | 5657 |
| 7 | PHP | RegExpBench | preg_* 8 子项（块内 ns→us） | 6930 |
| 8 | PHP | NQueens | n=11 单轮 + n=9 x10（块内 ns→us） | 631801 |
| 9 | PHP | Sieve | 数组筛 1e6 单轮 + 5e5 x5（块内 ns→us） | 286350 |
| 10 | PHP | QuickSort | 原生 sort 3e4 x5（块内 ns→us） | 24837 |
| 11 | PHP | MatrixMul | 嵌套数组矩阵乘 100x100 x3（块内 ns→us） | 69181 |
| 12 | PHP | BinaryTree | 匿名类树递归 depth12 x10 + depth16 x2（块内 ns→us） | 68830 |
| 13 | PHP | Mandelbrot | 240x180 x3（块内 ns→us） | 127808 |
