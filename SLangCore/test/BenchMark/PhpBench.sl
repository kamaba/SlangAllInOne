import Std

# ============================================================================
# PhpBench — PHP 惯用法基准（@php_embed(){} 内联块，php_embed 插件内嵌
# PHP embed SAPI 解释执行，vendored php8ts.dll PHP 8.4 TS x64）
#
# 13 项与 SL/C/C++/CSharp/Java/JS/TS/Python 共享基准逐项同算法/同参数
#（对齐 PythonBench/CppBench，校验和可跨语言对拍）。惯用法：递归闭包
#（use(&$fn) 自引用，避免全局函数重声明）、原生 sort、preg_* 正则、
# str_repeat/sprintf、匿名类树、数组 DP。
#
# 计时（2026-11-20 修订）：php 出通道 $us <- (...) 回传在 AOT 发布包
#（BenchMark.exe）实测失效——块内 echo 正常输出、报告 PHP 列却全空
#（毒化 long：toString 为空；源码树 slang.exe 运行则正常）。参照
# MasmBench asm 出通道失效先例，统计值统一改 SL 侧 Environment.sys.nowMillis()
# 整块计时兜底（ms×1000 存 us，含块 trampoline 调用开销）；块内
# hrtime(true) 的 printf 原始 us 保留在 stdout 运行日志作精确算法耗时参考。
#
# 块内代码约束：出通道表达式加小括号（Front 出通道不可以 $ 开头铁律，
# PHP 表达式天然 $ 起首）；不用 # 行注释（SL 词法层块捕获约束）；递归
# 助手用闭包而非全局 function（驻留解释器全局作用域共享，全局 function
# 跨块/热更会 Cannot redeclare 致命）；类树用匿名类（同理避重声明）。
#
# 共享部署位：块产物 Entry_N.php 部署 <插件>\package\windows\phpsrc\
#（与 pysrc / SLCpp.dll / java classes 同款"后编译覆盖"约定）——运行
# BenchMark 前须最后编译本工程。
# ============================================================================

PhpBench
{
    static fun()
    {
        # SL 侧整块计时兜底（php 出通道回传在 AOT 发布包失效，见头注释）
        long slT0 = Environment.sys.nowMillis()
        PhpBench.fibonacci()
        long slMs = Environment.sys.nowMillis() - slT0
        long us = slMs * 1000L
        BenchCollector.recordPhp("Fibonacci", "fib(0..21) 递归求和（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.eqBench()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("EqBench", "i32/i64/f64/bool 4 子项（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.loopBench()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("Loop", "数组迭代求和 x3000/while 5e6/step 1e6 3 子项（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.levenshtein()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("Levenshtein", "滚动数组 DP x5000（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.dataTypes()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("DataTypes", "Int32/Int64/Num/混合/bool mod 5 子项（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.stringBench()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("StringBench", "字符串拼接/插值/sprintf/比较 4 子项（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.regExpBench()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("RegExpBench", "preg_* 8 子项（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.nQueens()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("NQueens", "n=11 单轮 + n=9 x10（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.sieve()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("Sieve", "数组筛 1e6 单轮 + 5e5 x5（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.quickSort()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("QuickSort", "原生 sort 3e4 x5（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.matrixMul()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("MatrixMul", "嵌套数组矩阵乘 100x100 x3（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.binaryTree()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("BinaryTree", "匿名类树递归 depth12 x10 + depth16 x2（SL 侧整块计时）", us)

        slT0 = Environment.sys.nowMillis()
        PhpBench.mandelbrot()
        slMs = Environment.sys.nowMillis() - slT0
        us = slMs * 1000L
        BenchCollector.recordPhp("Mandelbrot", "240x180 x3（SL 侧整块计时）", us)
    }

    # 1. Fibonacci：递归闭包求和（sum = 17711，对齐 CppBench 校验和）
    static long fibonacci()
    {
        Console.println("========== Fibonacci (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $fib = function($n) use (&$fib) {
                if ($n <= 1) { return $n; }
                return $fib($n - 1) + $fib($n - 2);
            };
            $total = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 22; $i++) { $total += $fib($i); }
            $t1 = hrtime(true);
            echo "fib(0..21) sum = " . $total . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($t1 - $t0, 1000));
        }
        Console.println("========== Fibonacci (PHP) (end) ==========")
        ret us
    }

    # 2. EqBench：四种类型相等比较循环（对齐 CppBench 4 子项）
    static long eqBench()
    {
        Console.println("========== EqBench (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $acc = 0;
            $k = 0; $s = 0;
            $t0 = hrtime(true);
            while ($k != 2000000) { $s += $k; $k += 1; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "i32 != 2e6 = " . $s . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $k64 = 0; $s64 = 0;
            $t0 = hrtime(true);
            while ($k64 != 2000000) { $s64 += $k64; $k64 += 1; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "i64 != 2e6 = " . $s64 . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $kd = 0.0; $sd = 0.0;
            $t0 = hrtime(true);
            while ($kd != 2000000.0) { $sd += $kd; $kd += 1.0; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "f64 != 2e6 = " . $sd . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $cnt = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 1000000; $i++) { if (true) { $cnt += 1; } }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "bool == 1e6 = " . $cnt . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== EqBench (PHP) (end) ==========")
        ret us
    }

    # 3. Loop：数组迭代求和 x3000 / while 5e6 / step 1e6 三段
    static long loopBench()
    {
        Console.println("========== Loop (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $n = 1000;
            $arr = [];
            for ($i = 0; $i < $n; $i++) { $arr[] = $i * $i; }
            $acc = 0; $total = 0;
            $t0 = hrtime(true);
            for ($j = 0; $j < 3000; $j++) {
                $s = 0;
                foreach ($arr as $v) { $s += $v; }
                $total += $s;
            }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "iterator sum x3000 = " . $total . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $wsum = 0; $k = 0;
            $t0 = hrtime(true);
            while ($k < 5000000) { $wsum += $k; $k += 1; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "while sum 5e6 = " . $wsum . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $stepSum = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 1000000; $i += 7) { $stepSum += $i; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "for step +7 1e6 = " . $stepSum . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== Loop (PHP) (end) ==========")
        ret us
    }

    # 4. Levenshtein：两行滚动 DP，先单次再 x5000
    static long levenshtein()
    {
        Console.println("========== Levenshtein (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $a = [10, 20, 30, 40, 50, 60];
            $b = [10, 25, 30, 35, 40, 50, 65];
            $m = 6; $n = 7;
            $prev = range(0, $n);
            $curr = array_fill(0, $n + 1, 0);
            for ($i = 1; $i <= $m; $i++) {
                $curr[0] = $i;
                for ($j = 1; $j <= $n; $j++) {
                    $cost = ($a[$i - 1] == $b[$j - 1]) ? 0 : 1;
                    $d1 = $prev[$j] + 1;
                    $d2 = $curr[$j - 1] + 1;
                    $d3 = $prev[$j - 1] + $cost;
                    $curr[$j] = min($d1, $d2, $d3);
                }
                $tmp = $prev; $prev = $curr; $curr = $tmp;
            }
            echo "levenshtein(a,b) = " . $prev[$n] . "\n";
            $total = 0;
            $t0 = hrtime(true);
            for ($r = 0; $r < 5000; $r++) {
                for ($j = 0; $j <= $n; $j++) { $prev[$j] = $j; }
                for ($i = 1; $i <= $m; $i++) {
                    $curr[0] = $i;
                    for ($j = 1; $j <= $n; $j++) {
                        $cost = ($a[$i - 1] == $b[$j - 1]) ? 0 : 1;
                        $d1 = $prev[$j] + 1;
                        $d2 = $curr[$j - 1] + 1;
                        $d3 = $prev[$j - 1] + $cost;
                        $curr[$j] = min($d1, $d2, $d3);
                    }
                    $tmp = $prev; $prev = $curr; $curr = $tmp;
                }
                $total += $prev[$n];
            }
            $t1 = hrtime(true);
            echo "levenshtein x5000 = " . $total . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($t1 - $t0, 1000));
        }
        Console.println("========== Levenshtein (PHP) (end) ==========")
        ret us
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段（对齐 CppBench）
    static long dataTypes()
    {
        Console.println("========== DataTypes (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $acc = 0;
            $s32 = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 2000000; $i++) { $s32 += $i; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "Int32 sum 2e6 = " . $s32 . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $s64 = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 2000000; $i++) { $s64 += $i; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "Int64 sum 2e6 = " . $s64 . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $sf = 0.0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 2000000; $i++) { $sf += $i * 1.5; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "Num sum 2e6 = " . $sf . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $mix = 0.0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 1000000; $i++) { $mix = $mix + $i / 3.0 + $i % 7; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "Mixed ops 1e6 = " . $mix . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $count = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 1000000; $i++) { if ($i % 3 == 0 && $i % 5 == 0) { $count += 1; } }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "bool mod 1e6 = " . $count . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== DataTypes (PHP) (end) ==========")
        ret us
    }

    # 6. StringBench：字符串拼接 / 插值 / sprintf 格式化 / == 比较
    static long stringBench()
    {
        Console.println("========== StringBench (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $acc = 0;
            $s = "";
            $t0 = hrtime(true);
            for ($i = 0; $i < 10000; $i++) { $s = $s . "ab"; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "concat 1e4 (str) = " . strlen($s) . " chars  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $t = "";
            $t0 = hrtime(true);
            for ($i = 0; $i < 10000; $i++) { $t = "v=$i s=" . ($i * 2); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "interp 1e4 = " . $t . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $u = "";
            $t0 = hrtime(true);
            for ($i = 0; $i < 10000; $i++) { $u = sprintf("%d-%d", $i, $i + 1); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "format 1e4 = " . $u . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $c = 0;
            $t0 = hrtime(true);
            for ($i = 0; $i < 100000; $i++) { if ($s == $t) { $c += 1; } }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "compare 1e5 count = " . $c . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== StringBench (PHP) (end) ==========")
        ret us
    }

    # 7. RegExpBench：preg_* 8 子项（对齐 CppBench；文本构造不计时）
    static long regExpBench()
    {
        Console.println("========== RegExpBench (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $chunk = "abc123 def456 ghi789 ";
            $text = str_repeat($chunk, 4000);
            echo "text bytes = " . strlen($text) . "\n";
            $acc = 0;
            $m = [];
            $t0 = hrtime(true);
            for ($i = 0; $i < 2000; $i++) { preg_match("/([a-z]+)([0-9]+)/", $chunk, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "compile x2000  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $t0 = hrtime(true);
            for ($i = 0; $i < 500; $i++) { preg_match("/def456/", $text, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "search hit x500  [" . intdiv($t1 - $t0, 1000) . " us]  value=" . $m[0] . "\n";
            $t0 = hrtime(true);
            for ($i = 0; $i < 20; $i++) { $hit = preg_match("/zzz999/", $text, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "search miss x20  [" . intdiv($t1 - $t0, 1000) . " us]  miss=" . ($hit === 0 ? "true" : "false") . "\n";
            $t0 = hrtime(true);
            for ($i = 0; $i < 5; $i++) { $words = preg_match_all("/[a-z]+/", $text, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "matchAll x5  [" . intdiv($t1 - $t0, 1000) . " us]  count=" . $words . "\n";
            $t0 = hrtime(true);
            for ($i = 0; $i < 5; $i++) { $rep = preg_replace("/[0-9]+/", "#", $text); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "replace x5  [" . intdiv($t1 - $t0, 1000) . " us]  len=" . strlen($rep) . "\n";
            $t0 = hrtime(true);
            for ($i = 0; $i < 200; $i++) { preg_match("/([a-z]+)([0-9]+)/", $text, $m); $g1 = $m[1]; $g2 = $m[2]; }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "group search x200  [" . intdiv($t1 - $t0, 1000) . " us]  g1=" . $g1 . " g2=" . $g2 . "\n";
            $text2 = str_repeat("abc abc def def ", 2000);
            $t0 = hrtime(true);
            for ($i = 0; $i < 10; $i++) { $pairs = preg_match_all("/(\w+) \1/", $text2, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "backref matchAll x10  [" . intdiv($t1 - $t0, 1000) . " us]  count=" . $pairs . "\n";
            $text3 = str_repeat("中文测试123 ", 2000);
            $t0 = hrtime(true);
            for ($i = 0; $i < 100; $i++) { preg_match("/测试[0-9]+/u", $text3, $m); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "utf8 search x100  [" . intdiv($t1 - $t0, 1000) . " us]  value=" . $m[0] . "\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== RegExpBench (PHP) (end) ==========")
        ret us
    }

    # 8. NQueens：递归闭包回溯（n=11 单轮 + n=9 x10）
    static long nQueens()
    {
        Console.println("========== NQueens (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $place = function(&$queens, $row, $n) use (&$place) {
                if ($row == $n) { return 1; }
                $count = 0;
                for ($col = 0; $col < $n; $col++) {
                    $ok = 1;
                    for ($i = 0; $i < $row; $i++) {
                        if ($queens[$i] == $col || $queens[$i] - $i == $col - $row || $queens[$i] + $i == $col + $row) {
                            $ok = 0;
                            break;
                        }
                    }
                    if ($ok == 1) {
                        $queens[$row] = $col;
                        $count += $place($queens, $row + 1, $n);
                    }
                }
                return $count;
            };
            $queens = array_fill(0, 16, 0);
            $acc = 0;
            $t0 = hrtime(true);
            $solutions = $place($queens, 0, 11);
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "nqueens(11) solutions = " . $solutions . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $total = 0;
            $t0 = hrtime(true);
            for ($r = 0; $r < 10; $r++) { $total += $place($queens, 0, 9); }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "nqueens(9) x10 = " . $total . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== NQueens (PHP) (end) ==========")
        ret us
    }

    # 9. Sieve：数组素数筛（1e6 单轮 78498 + 5e5 x5 207690）
    static long sieve()
    {
        Console.println("========== Sieve (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $acc = 0;
            $lim = 1000000;
            $comp = array_fill(0, $lim + 1, 0);
            $t0 = hrtime(true);
            $count = 0;
            for ($i = 2; $i <= $lim; $i++) {
                if ($comp[$i] == 0) {
                    $count += 1;
                    if ($i <= intdiv($lim, $i)) {
                        $j = $i * $i;
                        while ($j <= $lim) { $comp[$j] = 1; $j += $i; }
                    }
                }
            }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "sieve 1e6 primes = " . $count . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $total = 0;
            $t0 = hrtime(true);
            for ($r = 0; $r < 5; $r++) {
                $comp5 = array_fill(0, 500001, 0);
                for ($i = 2; $i <= 500000; $i++) {
                    if ($comp5[$i] == 0) {
                        $total += 1;
                        if ($i <= intdiv(500000, $i)) {
                            $j = $i * $i;
                            while ($j <= 500000) { $comp5[$j] = 1; $j += $i; }
                        }
                    }
                }
            }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "sieve 5e5 x5 = " . $total . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== Sieve (PHP) (end) ==========")
        ret us
    }

    # 10. QuickSort：原生 sort（3e4 x5，数据生成不计时）
    static long quickSort()
    {
        Console.println("========== QuickSort (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $n = 30000;
            $arr = array_fill(0, $n, 0);
            $acc = 0;
            $checksum = 0;
            for ($r = 0; $r < 5; $r++) {
                $seed = 42 + $r;
                for ($i = 0; $i < $n; $i++) {
                    $seed = ($seed * 16807) % 2147483647;
                    $arr[$i] = $seed;
                }
                $t0 = hrtime(true);
                sort($arr);
                $t1 = hrtime(true);
                $acc += $t1 - $t0;
                for ($i = 0; $i < $n; $i++) {
                    $checksum += $arr[$i];
                    if ($i > 0 && $arr[$i - 1] > $arr[$i]) { echo "SORTED CHECK FAILED at " . $i . "\n"; }
                }
            }
            echo "sort 3e4 x5  [" . intdiv($acc, 1000) . " us]  checksum = " . $checksum . "\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== QuickSort (PHP) (end) ==========")
        ret us
    }

    # 11. MatrixMul：嵌套数组矩阵乘（每轮清零，checksum 与他语言对齐）
    static long matrixMul()
    {
        Console.println("========== MatrixMul (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $n = 100;
            $a = []; $b = [];
            for ($i = 0; $i < $n; $i++) {
                $ai = []; $bi = [];
                for ($j = 0; $j < $n; $j++) {
                    $ai[] = ($i + $j) % 100;
                    $bi[] = ($i * 7 + $j * 3) % 100;
                }
                $a[] = $ai; $b[] = $bi;
            }
            $t0 = hrtime(true);
            for ($r = 0; $r < 3; $r++) {
                $c = [];
                for ($i = 0; $i < $n; $i++) { $c[] = array_fill(0, $n, 0); }
                for ($i = 0; $i < $n; $i++) {
                    $ci = &$c[$i];
                    $ai = $a[$i];
                    for ($k = 0; $k < $n; $k++) {
                        $av = $ai[$k];
                        $bk = $b[$k];
                        for ($j = 0; $j < $n; $j++) { $ci[$j] += $av * $bk[$j]; }
                    }
                    unset($ci);
                }
            }
            $t1 = hrtime(true);
            $checksum = 0;
            for ($i = 0; $i < $n; $i++) { for ($j = 0; $j < $n; $j++) { $checksum += $c[$i][$j]; } }
            echo "matmul 100x100 x3  [" . intdiv($t1 - $t0, 1000) . " us]  checksum = " . $checksum . "\n";
            $us <- (intdiv($t1 - $t0, 1000));
        }
        Console.println("========== MatrixMul (PHP) (end) ==========")
        ret us
    }

    # 12. BinaryTree：匿名类树递归（depth12 x10 + depth16 x2，校验和对齐）
    static long binaryTree()
    {
        Console.println("========== BinaryTree (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $build = function($depth, $v) use (&$build) {
                if ($depth <= 0) { return null; }
                $node = new class($v) {
                    public $l = null;
                    public $r = null;
                    public $v;
                    function __construct($v) { $this->v = $v; }
                };
                $node->l = $build($depth - 1, $v * 2);
                $node->r = $build($depth - 1, $v * 2 + 1);
                return $node;
            };
            $tsum = function($node) use (&$tsum) {
                if ($node === null) { return 0; }
                return $node->v + $tsum($node->l) + $tsum($node->r);
            };
            $acc = 0;
            $t0 = hrtime(true);
            $total12 = 0;
            for ($r = 0; $r < 10; $r++) {
                $root = $build(12, $r + 1);
                $total12 += $tsum($root);
            }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "tree depth12 x10 recursive sum = " . $total12 . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $t0 = hrtime(true);
            $total16 = 0;
            for ($r = 0; $r < 2; $r++) {
                $root = $build(16, $r + 1);
                $total16 += $tsum($root);
            }
            $t1 = hrtime(true);
            $acc += $t1 - $t0;
            echo "tree depth16 x2 recursive sum = " . $total16 . "  [" . intdiv($t1 - $t0, 1000) . " us]\n";
            $us <- (intdiv($acc, 1000));
        }
        Console.println("========== BinaryTree (PHP) (end) ==========")
        ret us
    }

    # 13. Mandelbrot：标准映射（对齐 CppBench Render，240x180 x3）
    static long mandelbrot()
    {
        Console.println("========== Mandelbrot (PHP) (start) ==========")
        long us = 0L
        @php_embed()
        {
            $w = 240; $h = 180; $maxIter = 150;
            $iterSum = 0; $inside = 0;
            $t0 = hrtime(true);
            for ($r = 0; $r < 3; $r++) {
                for ($py = 0; $py < $h; $py++) {
                    $y0 = $py * 4.0 / $h - 2.0;
                    for ($px = 0; $px < $w; $px++) {
                        $x0 = $px * 4.0 / $w - 2.0;
                        $x = 0.0; $y = 0.0; $it = 0;
                        while ($it < $maxIter && $x * $x + $y * $y <= 4.0) {
                            $xt = $x * $x - $y * $y + $x0;
                            $y = 2.0 * $x * $y + $y0;
                            $x = $xt;
                            $it += 1;
                        }
                        $iterSum += $it;
                        if ($it == $maxIter) { $inside += 1; }
                    }
                }
            }
            $t1 = hrtime(true);
            echo "mandelbrot 240x180 x3  [" . intdiv($t1 - $t0, 1000) . " us]  iterSum = " . $iterSum . " inside = " . $inside . "\n";
            $us <- (intdiv($t1 - $t0, 1000));
        }
        Console.println("========== Mandelbrot (PHP) (end) ==========")
        ret us
    }
}