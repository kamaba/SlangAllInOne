# SLang 多语言 Benchmark 对比报告

- 生成时间: 2026-11-20 10:48:56
- 数据条目: 147 条
- 计时口径: 时间存储单位一律微秒；SL 为 SL 侧 nowMillis 毫秒计时（×1000 存 us）；C/C++/CSharp/Java/JS/TS/Python/PHP 为块内自身计时经出通道回传（不含引擎装载/编译部署开销）——C/C++ QPC/steady_clock ns（/1000 存 us，原始 ns 见运行日志）、CSharp Stopwatch（us）、Java System.nanoTime（ns /1000 折 us）、JS QuickJS Date.now（ms ×1000 存 us，粒度毫秒）、TS performance.now（亚毫秒 ms ×1000 折 us）、Python perf_counter_ns（块内 //1000 回传 us，原始 ns 见运行日志）、PHP hrtime(true)（块内 intdiv(...,1000) 回传 us，原始 ns 见运行日志）；ASM 因出通道回传失效改用 SL 侧 nowMillis 整块计时（含 trampoline 开销，ms×1000 存 us，块内 QPC printf 原始 ns 见运行日志）
- 单元格显示自适应单位（us 值过大时折算 ms），附录保留原始微秒值
- C/C++/CSharp/Java/JavaScript/TypeScript/Python/PHP 均为块内自身计时；CSharp/Java/TypeScript 首轮块内另含运行时 JIT/解释预热

## 语言与优化说明

| 语言 | 使用说明 | 优化选项 |
|------|----------|----------|
| SL | SLang 自研语言，SL VM 字节码执行 | VM JIT 默认开启（--no-jit 关闭） |
| C | C 惯用法（@cplus_clang 块，malloc/裸指针/函数指针） | MSVC cl /O2 原生编译，块内 ns 精确计时（cplus_clang 插件） |
| C++ | C++ 惯用法（@cplus_clang 块，对象/STL/RAII） | MSVC cl /O2 原生编译，块内 ns 精确计时（cplus_clang 插件） |
| ASM | x86-64 MASM 汇编（@masm_x64 块，手写指令） | ml64 原生汇编（含 AVX2 SIMD 专列），SL 侧 nowMillis 整块计时（asm 出通道回传失效兜底） |
| CSharp | C# / mono 运行时（csharp_mono 插件内嵌） | Mono JIT 默认优化，块内 Stopwatch us 计时 |
| Java | Java 17 / Hotspot 运行时（java_hotspot 插件内嵌） | HotSpot 分层 JIT，块内 nanoTime us 计时 |
| JavaScript | JavaScript / QuickJS 2024-01-13（javascript_quickjs 插件内嵌） | QuickJS 解释器（无 JIT），块内 Date.now ms 计时（×1000 存 us） |
| TypeScript | TypeScript / Node.js V8（typescript_nodev8 插件外接 node.exe 子进程） | V8 JIT 默认优化，TS 原生类型擦除，块内 performance.now us 计时 |
| Python | Python / CPython 3.14 内嵌（python_cpython 插件） | CPython 字节码解释器（无 JIT），块内 perf_counter_ns 计时（us 回传） |
| PHP | PHP 8.4 / embed SAPI 内嵌（php_embed 插件，vendored php8ts.dll TS x64） | PHP Zend 字节码解释器（无 JIT），块内 hrtime(true) 计时（us 回传） |

## 耗时对比总表（自适应单位，越小越快，单元格为该测试全部子项耗时合计）

| 测试类型 | 参数 | SL | C | C++ | ASM | CSharp | Java | JavaScript | JavaScriptV8 | Python | PHP |
|----------|------|----|---|-----|-----|--------|------|------------|--------------|--------|-----|
| Fibonacci | fib(0..21) 递归求和 | 32ms | 100us | 100us | 9ms | 366us | 374us | 6ms | 534us | 4ms | 4ms |
| EqBench | i32 != 2e6 等 4 子项 | 765ms | 2ms | 2ms | 3ms | 8ms | 13ms | 449ms | 14ms | 316ms | 121ms |
| Loop | array sum x3000 等 5 子项 | 1674ms | 1ms | 2ms | 18ms | 11ms | 10ms | 523ms | 11ms | 334ms | 122ms |
| Levenshtein | levenshtein x5000 | 282ms | 162us | 206us | - | 1ms | 2ms | 62ms | 3ms | 36ms | 24ms |
| DataTypes | Int32 sum 2e6 等 5 子项 | 932ms | 5ms | 5ms | - | 15ms | 24ms | 542ms | 23ms | 336ms | 137ms |
| StringBench | concat 1e4 等 4 子项 | 64ms | 1ms | 9ms | - | 100ms | 85ms | 21ms | 1ms | 6ms | 5ms |
| RegExpBench | compile x2000 等 8 子项 | 187ms | 22ms | 22ms | - | 290ms | 46ms | 266ms | 14ms | 26ms | 6ms |
| NQueens | nqueens(11) 单轮 等 2 子项 | 3643ms | 18ms | 20ms | - | 29ms | 24ms | 1308ms | 29ms | 939ms | 626ms |
| Sieve | sieve 1e6 单轮 等 2 子项 | 1041ms | 11ms | 9ms | - | 13ms | 25ms | 703ms | 39ms | 438ms | 254ms |
| QuickSort | quicksort 3e4 x5 | 844ms | 11ms | 6ms | - | 8ms | 11ms | 261ms | 13ms | 26ms | 24ms |
| MatrixMul | matmul 100x100 x3 | 680ms | 406us | 431us | - | 3ms | 7ms | 307ms | 10ms | 147ms | 67ms |
| BinaryTree | tree depth12 x10 等 2 子项 | 543ms | 1ms | 10ms | - | 20ms | 4ms | 114ms | 4ms | 83ms | 68ms |
| Mandelbrot | mandelbrot 240x180 x3 | 1094ms | 6ms | 5ms | - | 11ms | 8ms | 343ms | 11ms | 338ms | 127ms |
| ListWalk | malloc 链表 build+指针遍历 1e5 x10（C 专列，块内 ns） | - | 56ms | 439us | - | - | - | - | - | - | - |
| SimdAVX2 | vpaddd 4 车道向量累加 5e6 次（ASM 专列，块内 QPC ns） | - | - | - | 1ms | - | - | - | - | - | - |

## 附录: 全部原始条目

| 序号 | 语言 | 测试类型 | 参数 | 运行时间(us) |
|------|------|----------|------|--------------|
| 1 | SL | Fibonacci | fib(0..21) 递归求和 | 32000 |
| 2 | SL | EqBench | i32 != 2e6 | 126000 |
| 3 | SL | EqBench | i64 != 2e6 | 256000 |
| 4 | SL | EqBench | f64 != 2e6 | 226000 |
| 5 | SL | EqBench | bool == 1e6 | 157000 |
| 6 | SL | Loop | array sum x3000 | 411000 |
| 7 | SL | Loop | while sum 5e6 | 537000 |
| 8 | SL | Loop | for step +7 1e6 | 15000 |
| 9 | SL | Loop | for sum 1e6 | 107000 |
| 10 | SL | Loop | for-in range sum 1e6 | 604000 |
| 11 | SL | Levenshtein | levenshtein x5000 | 282000 |
| 12 | SL | DataTypes | Int32 sum 2e6 | 127000 |
| 13 | SL | DataTypes | Int64 sum 2e6 | 223000 |
| 14 | SL | DataTypes | Num sum 2e6 | 238000 |
| 15 | SL | DataTypes | Mixed ops 1e6 | 175000 |
| 16 | SL | DataTypes | bool mod 1e6 | 169000 |
| 17 | SL | StringBench | concat 1e4 | 36000 |
| 18 | SL | StringBench | interp 1e4 | 12000 |
| 19 | SL | StringBench | format 1e4 | 1000 |
| 20 | SL | StringBench | compare 1e5 | 15000 |
| 21 | SL | RegExpBench | compile x2000 | 97000 |
| 22 | SL | RegExpBench | search hit x500 | 14000 |
| 23 | SL | RegExpBench | search miss x20 | 2000 |
| 24 | SL | RegExpBench | matchAll x5 | 35000 |
| 25 | SL | RegExpBench | replace x5 | 3000 |
| 26 | SL | RegExpBench | group search x200 | 8000 |
| 27 | SL | RegExpBench | backref matchAll x10 | 26000 |
| 28 | SL | RegExpBench | utf8 search x100 | 2000 |
| 29 | SL | NQueens | nqueens(11) 单轮 | 2668000 |
| 30 | SL | NQueens | nqueens(9) x10 | 975000 |
| 31 | SL | Sieve | sieve 1e6 单轮 | 300000 |
| 32 | SL | Sieve | sieve 5e5 x5 | 741000 |
| 33 | SL | QuickSort | quicksort 3e4 x5 | 844000 |
| 34 | SL | MatrixMul | matmul 100x100 x3 | 680000 |
| 35 | SL | BinaryTree | tree depth12 x10 | 131000 |
| 36 | SL | BinaryTree | tree depth16 x2 | 412000 |
| 37 | SL | Mandelbrot | mandelbrot 240x180 x3 | 1094000 |
| 38 | CSharp | Fibonacci | fib(0..21) 递归求和（块内 Stopwatch us） | 366 |
| 39 | CSharp | EqBench | 4子项（块内 Stopwatch us） | 8038 |
| 40 | CSharp | Loop | 3子项（块内 Stopwatch us） | 11037 |
| 41 | CSharp | Levenshtein | levenshtein x5000（块内 Stopwatch us） | 1118 |
| 42 | CSharp | DataTypes | 5子项（块内 Stopwatch us） | 15007 |
| 43 | CSharp | StringBench | 4子项（块内 Stopwatch us） | 100704 |
| 44 | CSharp | RegExpBench | 8子项（块内 Stopwatch us） | 290925 |
| 45 | CSharp | NQueens | n=11 单轮 + n=9 x10（块内 Stopwatch us） | 29605 |
| 46 | CSharp | Sieve | 1e6 单轮 + 5e5 x5（块内 Stopwatch us） | 13467 |
| 47 | CSharp | QuickSort | quicksort 3e4 x5（块内 Stopwatch us） | 8837 |
| 48 | CSharp | MatrixMul | matmul 100x100 x3（块内 Stopwatch us） | 3390 |
| 49 | CSharp | BinaryTree | depth12 x10 + depth16 x2（块内 Stopwatch us） | 20876 |
| 50 | CSharp | Mandelbrot | mandelbrot 240x180 x3（块内 Stopwatch us） | 11955 |
| 51 | Java | Fibonacci | fib(0..21) 递归求和（块内 nanoTime us） | 374 |
| 52 | Java | EqBench | 4子项（块内 nanoTime us） | 13134 |
| 53 | Java | Loop | 3子项（块内 nanoTime us） | 10228 |
| 54 | Java | Levenshtein | levenshtein x5000（块内 nanoTime us） | 2029 |
| 55 | Java | DataTypes | 5子项（块内 nanoTime us） | 24428 |
| 56 | Java | StringBench | 4子项（块内 nanoTime us） | 85053 |
| 57 | Java | RegExpBench | 8子项（块内 nanoTime us） | 46937 |
| 58 | Java | NQueens | n=11 单轮 + n=9 x10（块内 nanoTime us） | 24149 |
| 59 | Java | Sieve | 1e6 单轮 + 5e5 x5（块内 nanoTime us） | 25803 |
| 60 | Java | QuickSort | quicksort 3e4 x5（块内 nanoTime us） | 11745 |
| 61 | Java | MatrixMul | matmul 100x100 x3（块内 nanoTime us） | 7016 |
| 62 | Java | BinaryTree | depth12 x10 + depth16 x2（块内 nanoTime us） | 4235 |
| 63 | Java | Mandelbrot | mandelbrot 240x180 x3（块内 nanoTime us） | 8882 |
| 64 | JavaScript | Fibonacci | fib(0..21) 递归求和（块内 Date.now ms） | 6000 |
| 65 | JavaScript | EqBench | 4子项（块内 Date.now ms） | 449000 |
| 66 | JavaScript | Loop | 3子项（块内 Date.now ms） | 523000 |
| 67 | JavaScript | Levenshtein | levenshtein x5000（块内 Date.now ms） | 62000 |
| 68 | JavaScript | DataTypes | 5子项（块内 Date.now ms） | 542000 |
| 69 | JavaScript | StringBench | 4子项（块内 Date.now ms） | 21000 |
| 70 | JavaScript | RegExpBench | 8子项（块内 Date.now ms） | 266000 |
| 71 | JavaScript | NQueens | n=11 单轮 + n=9 x10（块内 Date.now ms） | 1308000 |
| 72 | JavaScript | Sieve | 1e6 单轮 + 5e5 x5（块内 Date.now ms） | 703000 |
| 73 | JavaScript | QuickSort | quicksort 3e4 x5（块内 Date.now ms） | 261000 |
| 74 | JavaScript | MatrixMul | matmul 100x100 x3（块内 Date.now ms） | 307000 |
| 75 | JavaScript | BinaryTree | depth12 x10 + depth16 x2（块内 Date.now ms） | 114000 |
| 76 | JavaScript | Mandelbrot | mandelbrot 240x180 x3（块内 Date.now ms） | 343000 |
| 77 | TypeScript | Fibonacci | fib(0..21) 递归求和（块内 performance.now us） | 534 |
| 78 | TypeScript | EqBench | 4子项（块内 performance.now us） | 14856 |
| 79 | TypeScript | Loop | 3子项（块内 performance.now us） | 11641 |
| 80 | TypeScript | Levenshtein | levenshtein x5000（块内 performance.now us） | 3115 |
| 81 | TypeScript | DataTypes | 5子项（块内 performance.now us） | 23003 |
| 82 | TypeScript | StringBench | 4子项（块内 performance.now us） | 1939 |
| 83 | TypeScript | RegExpBench | 8子项（块内 performance.now us） | 14227 |
| 84 | TypeScript | NQueens | n=11 单轮 + n=9 x10（块内 performance.now us） | 29947 |
| 85 | TypeScript | Sieve | 1e6 单轮 + 5e5 x5（块内 performance.now us） | 39982 |
| 86 | TypeScript | QuickSort | quicksort 3e4 x5（块内 performance.now us） | 13453 |
| 87 | TypeScript | MatrixMul | matmul 100x100 x3（块内 performance.now us） | 10634 |
| 88 | TypeScript | BinaryTree | depth12 x10 + depth16 x2（块内 performance.now us） | 4535 |
| 89 | TypeScript | Mandelbrot | mandelbrot 240x180 x3（块内 performance.now us） | 11175 |
| 90 | C | Fibonacci | fib(0..21) 递归求和（块内 ns） | 100 |
| 91 | C | EqBench | i32/i64/f64/bool 4 子项（块内 ns） | 2714 |
| 92 | C | Loop | 指针游走求和 x3000/while 5e6/step 1e6 3 子项（块内 ns） | 1364 |
| 93 | C | Levenshtein | 滚动缓冲 DP x5000（块内 ns） | 162 |
| 94 | C | DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns） | 5089 |
| 95 | C | StringBench | 手写 char* 拼接/sprintf/指针比较 4 子项（块内 ns） | 1624 |
| 96 | C | RegExpBench | std::regex 8 子项（块内 us，超 int32 出通道上限） | 22223 |
| 97 | C | NQueens | n=11 单轮 + n=9 x10（块内 ns） | 18815 |
| 98 | C | Sieve | malloc 筛 1e6 单轮 + 5e5 x5（块内 ns） | 11012 |
| 99 | C | QuickSort | qsort 3e4 x5（块内 ns） | 11275 |
| 100 | C | MatrixMul | 行指针矩阵乘 100x100 x3（块内 ns） | 406 |
| 101 | C | BinaryTree | malloc 池树显式栈 DFS depth12 x10 + depth16 x2（块内 ns） | 1173 |
| 102 | C | Mandelbrot | 240x180 x3（块内 ns） | 6064 |
| 103 | C | ListWalk | malloc 链表 build+指针遍历 1e5 x10（C 专列，块内 ns） | 56900 |
| 104 | C++ | Fibonacci | fib(0..21) 递归求和（块内 ns） | 100 |
| 105 | C++ | EqBench | i32/i64/f64/bool 4 子项（块内 ns） | 2681 |
| 106 | C++ | Loop | 迭代器求和 x3000/while 5e6/step 1e6 3 子项（块内 ns） | 2041 |
| 107 | C++ | Levenshtein | vector 滚动 DP x5000（块内 ns） | 206 |
| 108 | C++ | DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns） | 5043 |
| 109 | C++ | StringBench | std::string 拼接/to_string/stringstream/比较 4 子项（块内 ns） | 9264 |
| 110 | C++ | RegExpBench | std::regex 8 子项（块内 us，超 int32 出通道上限） | 22371 |
| 111 | C++ | NQueens | n=11 单轮 + n=9 x10（块内 ns） | 20044 |
| 112 | C++ | Sieve | vector 筛 1e6 单轮 + 5e5 x5（块内 ns） | 9699 |
| 113 | C++ | QuickSort | std::sort 3e4 x5（块内 ns） | 6395 |
| 114 | C++ | MatrixMul | vector<vector> 矩阵乘 100x100 x3（块内 ns） | 431 |
| 115 | C++ | BinaryTree | unique_ptr 树递归 lambda depth12 x10 + depth16 x2（块内 ns） | 10573 |
| 116 | C++ | Mandelbrot | 240x180 x3（块内 ns） | 5926 |
| 117 | C++ | ListWalk | vector 对象成员方法遍历 1e5 x10（C++ 专列，块内 ns） | 439 |
| 118 | ASM | Loop | for sum 1e6 x10 / while 5e6 / step 1e6 3 子项（块内 QPC ns） | 18000 |
| 119 | ASM | EqBench | i32/i64/f64/bool 4 子项（块内 QPC ns） | 3000 |
| 120 | ASM | Fibonacci | fib(0..21) 递归求和 x100 轮（块内 QPC ns） | 9000 |
| 121 | ASM | SimdAVX2 | vpaddd 4 车道向量累加 5e6 次（ASM 专列，块内 QPC ns） | 1000 |
| 122 | Python | Fibonacci | fib(0..21) 递归求和（块内 ns→us） | 4433 |
| 123 | Python | EqBench | i32/i64/f64/bool 4 子项（块内 ns→us） | 316251 |
| 124 | Python | Loop | list 迭代求和 x3000/while 5e6/step 1e6 3 子项（块内 ns→us） | 334008 |
| 125 | Python | Levenshtein | 滚动列表 DP x5000（块内 ns→us） | 36785 |
| 126 | Python | DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us） | 336382 |
| 127 | Python | StringBench | str 拼接/f-string 插值/format/比较 4 子项（块内 ns→us） | 6713 |
| 128 | Python | RegExpBench | re 模块 8 子项（块内 ns→us） | 26421 |
| 129 | Python | NQueens | n=11 单轮 + n=9 x10（块内 ns→us） | 939682 |
| 130 | Python | Sieve | bytearray 筛 1e6 单轮 + 5e5 x5（块内 ns→us） | 438097 |
| 131 | Python | QuickSort | list.sort 3e4 x5（块内 ns→us） | 26385 |
| 132 | Python | MatrixMul | 嵌套 list 矩阵乘 100x100 x3（块内 ns→us） | 147493 |
| 133 | Python | BinaryTree | class 树递归 depth12 x10 + depth16 x2（块内 ns→us） | 83989 |
| 134 | Python | Mandelbrot | 240x180 x3（块内 ns→us） | 338500 |
| 135 | PHP | Fibonacci | fib(0..21) 递归求和（块内 ns→us） | 4310 |
| 136 | PHP | EqBench | i32/i64/f64/bool 4 子项（块内 ns→us） | 121296 |
| 137 | PHP | Loop | 数组迭代求和 x3000/while 5e6/step 1e6 3 子项（块内 ns→us） | 122991 |
| 138 | PHP | Levenshtein | 滚动数组 DP x5000（块内 ns→us） | 24007 |
| 139 | PHP | DataTypes | Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us） | 137941 |
| 140 | PHP | StringBench | 字符串拼接/插值/sprintf/比较 4 子项（块内 ns→us） | 5465 |
| 141 | PHP | RegExpBench | preg_* 8 子项（块内 ns→us） | 6598 |
| 142 | PHP | NQueens | n=11 单轮 + n=9 x10（块内 ns→us） | 626766 |
| 143 | PHP | Sieve | 数组筛 1e6 单轮 + 5e5 x5（块内 ns→us） | 254870 |
| 144 | PHP | QuickSort | 原生 sort 3e4 x5（块内 ns→us） | 24116 |
| 145 | PHP | MatrixMul | 嵌套数组矩阵乘 100x100 x3（块内 ns→us） | 67736 |
| 146 | PHP | BinaryTree | 匿名类树递归 depth12 x10 + depth16 x2（块内 ns→us） | 68137 |
| 147 | PHP | Mandelbrot | 240x180 x3（块内 ns→us） | 127646 |
