import Std

# ============================================================================
# JsBench — JavaScript 版基准（@javascript_quickjs(){} 内联块，QuickJS 引擎）
# 13 项基准与 SL/C#/Java 版逐项对齐：相同算法 / 迭代次数 / 运算序列 /
# 输出行格式，计时用 Date.now()（毫秒口径同 Environment.sys.nowMillis）。
# JS 域为全局脚本模式：块体被包裹进 function run(){}（"use strict"），
# 块内直接声明 function / let 即可，不支持 import 指令；输出走
# console.log / print（插件注册的控制台绑定，stdout 通路）。
# 注意：SL 层禁用行内 # 注释（只整行使用）；块内字符串禁字面 # 字符
#（replace 目标字符写作 \x23）；块内勿写含 <- 的正则字面量
#（用 new RegExp("...") 字符串形态）。
# ============================================================================

JsBench
{
    static fun()
    {
        # SL 侧整块计时包裹各子项（含引擎调用开销，首轮另含编译部署），逐项记录进 BenchCollector
        t = Environment.sys.nowMillis()
        JsBench.fibonacci()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("Fibonacci", "fib(0..21) 递归求和（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.eqBench()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("EqBench", "4子项整块（含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.loopBench()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("Loop", "3子项整块（含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.levenshtein()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("Levenshtein", "levenshtein x5000（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.dataTypes()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("DataTypes", "5子项整块（含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.stringBench()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("StringBench", "4子项整块（含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.regExpBench()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("RegExpBench", "8子项整块（含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.nQueens()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("NQueens", "n=11 单轮 + n=9 x10（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.sieve()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("Sieve", "1e6 单轮 + 5e5 x5（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.quickSort()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("QuickSort", "quicksort 3e4 x5（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.matrixMul()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("MatrixMul", "matmul 100x100 x3（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.binaryTree()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("BinaryTree", "depth12 x10 + depth16 x2（整块含引擎开销）", t)

        t = Environment.sys.nowMillis()
        JsBench.mandelbrot()
        t = Environment.sys.nowMillis() - t
        BenchCollector.recordJs("Mandelbrot", "mandelbrot 240x180 x3（整块含引擎开销）", t)
    }

    # 1. Fibonacci：fib(0..21) 递归求和（= 17711）
    static fibonacci()
    {
        Console.println("========== Fibonacci (JS) (start) ==========")
        @javascript_quickjs()
        {
            function fib(n)
            {
                return n <= 1 ? n : fib(n - 1) + fib(n - 2);
            }
            let t0 = Date.now();
            let sum = 0;
            for (let i = 0; i < 22; i++)
            {
                sum += fib(i);
            }
            console.log("fib(0..21) sum = " + sum + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== Fibonacci (JS) (end) ==========")
    }

    # 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool）
    static eqBench()
    {
        Console.println("========== EqBench (JS) (start) ==========")
        @javascript_quickjs()
        {
            let k = 0;
            let s = 0;
            let t0 = Date.now();
            while (k !== 2000000)
            {
                s += k;
                k++;
            }
            console.log("i32 != 2e6 = " + s + "  [" + (Date.now() - t0) + " ms]");
            let k64 = 0;
            let s64 = 0;
            t0 = Date.now();
            while (k64 !== 2000000)
            {
                s64 += k64;
                k64++;
            }
            console.log("i64 != 2e6 = " + s64 + "  [" + (Date.now() - t0) + " ms]");
            let kd = 0.0;
            let sd = 0.0;
            t0 = Date.now();
            while (kd !== 2000000.0)
            {
                sd += kd;
                kd += 1.0;
            }
            console.log("f64 != 2e6 = " + sd + "  [" + (Date.now() - t0) + " ms]");
            let b = true;
            let cnt = 0;
            t0 = Date.now();
            for (let i = 0; i < 1000000; i++)
            {
                if (b === true)
                {
                    cnt++;
                }
            }
            console.log("bool == 1e6 = " + cnt + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== EqBench (JS) (end) ==========")
    }

    # 3. Loop：数组求和 / while / 步进 for 三段
    static loopBench()
    {
        Console.println("========== Loop (JS) (start) ==========")
        @javascript_quickjs()
        {
            let n = 1000;
            let arr = new Array(n);
            for (let i = 0; i < n; i++)
            {
                arr[i] = i * i;
            }
            let total = 0;
            let t0 = Date.now();
            for (let j = 0; j < 3000; j++)
            {
                let s = 0;
                for (let i = 0; i < n; i++)
                {
                    s += arr[i];
                }
                total += s;
            }
            console.log("array sum x3000 = " + total + "  [" + (Date.now() - t0) + " ms]");
            let wsum = 0;
            let k = 0;
            t0 = Date.now();
            while (k < 5000000)
            {
                wsum += k;
                k++;
            }
            console.log("while sum 5e6 = " + wsum + "  [" + (Date.now() - t0) + " ms]");
            let stepSum = 0;
            t0 = Date.now();
            for (let i = 0; i < 1000000; i += 7)
            {
                stepSum += i;
            }
            console.log("for step +7 1e6 = " + stepSum + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== Loop (JS) (end) ==========")
    }

    # 4. Levenshtein：编辑距离 DP（a,b 固定序列，先单次再 x5000）
    static levenshtein()
    {
        Console.println("========== Levenshtein (JS) (start) ==========")
        @javascript_quickjs()
        {
            function distance(a, b)
            {
                let m = a.length;
                let n = b.length;
                let prev = new Array(n + 1);
                let curr = new Array(n + 1);
                for (let j = 0; j <= n; j++)
                {
                    prev[j] = j;
                }
                for (let i = 1; i <= m; i++)
                {
                    curr[0] = i;
                    for (let j = 1; j <= n; j++)
                    {
                        let cost = a[i - 1] === b[j - 1] ? 0 : 1;
                        curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
                    }
                    let tmp = prev;
                    prev = curr;
                    curr = tmp;
                }
                return prev[n];
            }
            let a = [10, 20, 30, 40, 50, 60];
            let b = [10, 25, 30, 35, 40, 50, 65];
            let dist = distance(a, b);
            console.log("levenshtein(a,b) = " + dist);
            let total = 0;
            let t0 = Date.now();
            for (let r = 0; r < 5000; r++)
            {
                total += distance(a, b);
            }
            console.log("levenshtein x5000 = " + total + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== Levenshtein (JS) (end) ==========")
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段
    static dataTypes()
    {
        Console.println("========== DataTypes (JS) (start) ==========")
        @javascript_quickjs()
        {
            let s32 = 0;
            let t0 = Date.now();
            for (let i = 0; i < 2000000; i++)
            {
                s32 += i;
            }
            console.log("Int32 sum 2e6 = " + s32 + "  [" + (Date.now() - t0) + " ms]");
            let s64 = 0;
            t0 = Date.now();
            for (let i = 0; i < 2000000; i++)
            {
                s64 += i;
            }
            console.log("Int64 sum 2e6 = " + s64 + "  [" + (Date.now() - t0) + " ms]");
            let sf = 0.0;
            t0 = Date.now();
            for (let i = 0; i < 2000000; i++)
            {
                sf += i * 1.5;
            }
            console.log("Num sum 2e6 = " + sf + "  [" + (Date.now() - t0) + " ms]");
            let mix = 0.0;
            t0 = Date.now();
            for (let i = 0; i < 1000000; i++)
            {
                mix = mix + i / 3.0 + i % 7;
            }
            console.log("Mixed ops 1e6 = " + mix + "  [" + (Date.now() - t0) + " ms]");
            let count = 0;
            t0 = Date.now();
            for (let i = 0; i < 1000000; i++)
            {
                if (i % 3 === 0 && i % 5 === 0)
                {
                    count++;
                }
            }
            console.log("bool mod 1e6 = " + count + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== DataTypes (JS) (end) ==========")
    }

    # 6. StringBench：拼接 / 插值构建 / format / 比较 / 结尾校验
    static stringBench()
    {
        Console.println("========== StringBench (JS) (start) ==========")
        @javascript_quickjs()
        {
            let s = "";
            let t0 = Date.now();
            for (let i = 0; i < 10000; i++)
            {
                s = s + "ab";
            }
            console.log("concat 1e4  [" + (Date.now() - t0) + " ms]");
            let t = "";
            t0 = Date.now();
            for (let i = 0; i < 10000; i++)
            {
                t = "v=" + i + " s=" + (i * 2);
            }
            console.log("interp 1e4  [" + (Date.now() - t0) + " ms]");
            let u = "";
            t0 = Date.now();
            for (let i = 0; i < 10000; i++)
            {
                u = i + "-" + (i + 1);
            }
            console.log("format 1e4  [" + (Date.now() - t0) + " ms]");
            let c = 0;
            t0 = Date.now();
            for (let i = 0; i < 100000; i++)
            {
                if (s === t)
                {
                    c++;
                }
            }
            console.log("compare 1e5  count=" + c + "  [" + (Date.now() - t0) + " ms]");
            console.log("concat endswith ab = " + (s.endsWith("ab") && u === u));
        }
        Console.println("========== StringBench (JS) (end) ==========")
    }

    # 7. RegExpBench：编译 / 早命中 / 不命中 / matchAll / replace / 分组 /
    #    backref / UTF-8 中文 共 8 项（文本构建不计时）
    static regExpBench()
    {
        Console.println("========== RegExpBench (JS) (start) ==========")
        @javascript_quickjs()
        {
            let chunk = "abc123 def456 ghi789 ";
            let text = "";
            for (let i = 0; i < 4000; i++)
            {
                text = text + chunk;
            }
            console.log("text bytes = " + text.length);
            let t0 = Date.now();
            for (let i = 0; i < 2000; i++)
            {
                new RegExp("([a-z]+)([0-9]+)");
            }
            console.log("compile x2000  [" + (Date.now() - t0) + " ms]");
            let re1 = new RegExp("def456");
            let hit = "";
            t0 = Date.now();
            for (let i = 0; i < 500; i++)
            {
                let m1 = re1.exec(text);
                hit = m1 !== null ? m1[0] : "";
            }
            console.log("search hit x500  [" + (Date.now() - t0) + " ms]  value=" + hit);
            let re2 = new RegExp("zzz999");
            let miss = true;
            t0 = Date.now();
            for (let i = 0; i < 20; i++)
            {
                miss = !re2.test(text);
            }
            console.log("search miss x20  [" + (Date.now() - t0) + " ms]  miss=" + miss);
            let re3 = new RegExp("[a-z]+", "g");
            let words = 0;
            t0 = Date.now();
            for (let i = 0; i < 5; i++)
            {
                words = 0;
                re3.lastIndex = 0;
                let m3;
                while ((m3 = re3.exec(text)) !== null)
                {
                    words++;
                }
            }
            console.log("matchAll x5  [" + (Date.now() - t0) + " ms]  count=" + words);
            let re4 = new RegExp("[0-9]+", "g");
            let rep = "";
            t0 = Date.now();
            for (let i = 0; i < 5; i++)
            {
                rep = text.replace(re4, "\x23");
            }
            console.log("replace x5  [" + (Date.now() - t0) + " ms]  len=" + rep.length);
            let re5 = new RegExp("([a-z]+)([0-9]+)");
            let g1 = "";
            let g2 = "";
            t0 = Date.now();
            for (let i = 0; i < 200; i++)
            {
                let m5 = re5.exec(text);
                if (m5 !== null)
                {
                    g1 = m5[1];
                    g2 = m5[2];
                }
            }
            console.log("group search x200  [" + (Date.now() - t0) + " ms]  g1=" + g1 + " g2=" + g2);
            let chunk2 = "abc abc def def ";
            let text2 = "";
            for (let i = 0; i < 2000; i++)
            {
                text2 = text2 + chunk2;
            }
            let re6 = new RegExp("(\\w+) \\1", "g");
            let pairs = 0;
            t0 = Date.now();
            for (let i = 0; i < 10; i++)
            {
                pairs = 0;
                re6.lastIndex = 0;
                let m6;
                while ((m6 = re6.exec(text2)) !== null)
                {
                    pairs++;
                }
            }
            console.log("backref matchAll x10  [" + (Date.now() - t0) + " ms]  count=" + pairs);
            let chunk3 = "中文测试123 ";
            let text3 = "";
            for (let i = 0; i < 2000; i++)
            {
                text3 = text3 + chunk3;
            }
            let re7 = new RegExp("测试[0-9]+");
            let zh = "";
            t0 = Date.now();
            for (let i = 0; i < 100; i++)
            {
                let m7 = re7.exec(text3);
                zh = m7 !== null ? m7[0] : "";
            }
            console.log("utf8 search x100  [" + (Date.now() - t0) + " ms]  value=" + zh);
        }
        Console.println("========== RegExpBench (JS) (end) ==========")
    }

    # 8. NQueens：n=11 单轮（2680）+ n=9 x10 轮（3520）
    static nQueens()
    {
        Console.println("========== NQueens (JS) (start) ==========")
        @javascript_quickjs()
        {
            function place(queens, row, n)
            {
                if (row === n)
                {
                    return 1;
                }
                let count = 0;
                for (let col = 0; col < n; col++)
                {
                    let ok = 1;
                    for (let i = 0; i < row; i++)
                    {
                        if (queens[i] === col || queens[i] - i === col - row || queens[i] + i === col + row)
                        {
                            ok = 0;
                            break;
                        }
                    }
                    if (ok === 1)
                    {
                        queens[row] = col;
                        count += place(queens, row + 1, n);
                    }
                }
                return count;
            }
            function solve(n)
            {
                let queens = new Array(n);
                return place(queens, 0, n);
            }
            let t0 = Date.now();
            let solutions = solve(11);
            console.log("nqueens(11) solutions = " + solutions + "  [" + (Date.now() - t0) + " ms]");
            let total = 0;
            t0 = Date.now();
            for (let r = 0; r < 10; r++)
            {
                total += solve(9);
            }
            console.log("nqueens(9) x10 = " + total + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== NQueens (JS) (end) ==========")
    }

    # 9. Sieve：1e6 单轮（78498）+ 5e5 x5 轮（207690）
    static sieve()
    {
        Console.println("========== Sieve (JS) (start) ==========")
        @javascript_quickjs()
        {
            let primes = 0;
            let t0 = Date.now();
            let comp1 = new Array(1000001).fill(0);
            for (let i = 2; i <= 1000000; i++)
            {
                if (comp1[i] === 0)
                {
                    primes++;
                    if (i <= 1000000 / i)
                    {
                        let j = i * i;
                        while (j <= 1000000)
                        {
                            comp1[j] = 1;
                            j += i;
                        }
                    }
                }
            }
            console.log("sieve 1e6 primes = " + primes + "  [" + (Date.now() - t0) + " ms]");
            let total = 0;
            t0 = Date.now();
            for (let r = 0; r < 5; r++)
            {
                let comp2 = new Array(500001).fill(0);
                let cnt = 0;
                for (let i = 2; i <= 500000; i++)
                {
                    if (comp2[i] === 0)
                    {
                        cnt++;
                        if (i <= 500000 / i)
                        {
                            let j = i * i;
                            while (j <= 500000)
                            {
                                comp2[j] = 1;
                                j += i;
                            }
                        }
                    }
                }
                total += cnt;
            }
            console.log("sieve 5e5 x5 = " + total + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== Sieve (JS) (end) ==========")
    }

    # 10. QuickSort：3e4 元素 x5 轮（LCG 数据生成不计时，逐轮计时累计）
    static quickSort()
    {
        Console.println("========== QuickSort (JS) (start) ==========")
        @javascript_quickjs()
        {
            function sort(a, lo, hi)
            {
                if (lo >= hi)
                {
                    return;
                }
                let i = lo;
                let j = hi;
                let p = a[(lo + hi) / 2 | 0];
                while (i <= j)
                {
                    while (a[i] < p)
                    {
                        i++;
                    }
                    while (a[j] > p)
                    {
                        j--;
                    }
                    if (i <= j)
                    {
                        let tmp = a[i];
                        a[i] = a[j];
                        a[j] = tmp;
                        i++;
                        j--;
                    }
                }
                sort(a, lo, j);
                sort(a, i, hi);
            }
            let n = 30000;
            let rounds = 5;
            let arr = new Array(n);
            let totalMs = 0;
            let checksum = 0;
            for (let r = 0; r < rounds; r++)
            {
                let seed = 42 + r;
                for (let i = 0; i < n; i++)
                {
                    seed = (seed * 16807) % 2147483647;
                    arr[i] = seed;
                }
                let t0 = Date.now();
                sort(arr, 0, n - 1);
                totalMs += Date.now() - t0;
                for (let i = 0; i < n; i++)
                {
                    checksum += arr[i];
                    if (i > 0)
                    {
                        if (arr[i - 1] > arr[i])
                        {
                            console.log("SORTED CHECK FAILED at " + i);
                        }
                    }
                }
            }
            console.log("quicksort 3e4 x5  [" + totalMs + " ms]  checksum = " + checksum);
        }
        Console.println("========== QuickSort (JS) (end) ==========")
    }

    # 11. MatrixMul：100x100 x3 轮（填充不计时，Int64 校验和）
    static matrixMul()
    {
        Console.println("========== MatrixMul (JS) (start) ==========")
        @javascript_quickjs()
        {
            let n = 100;
            let rounds = 3;
            let a = new Array(n * n).fill(0);
            let b = new Array(n * n).fill(0);
            let c = new Array(n * n).fill(0);
            for (let i = 0; i < n; i++)
            {
                for (let j = 0; j < n; j++)
                {
                    a[i * n + j] = (i + j) % 100;
                    b[i * n + j] = (i * 7 + j * 3) % 100;
                }
            }
            let t0 = Date.now();
            for (let r = 0; r < rounds; r++)
            {
                for (let i = 0; i < n; i++)
                {
                    for (let j = 0; j < n; j++)
                    {
                        let sum = 0;
                        for (let k = 0; k < n; k++)
                        {
                            sum += a[i * n + k] * b[k * n + j];
                        }
                        c[i * n + j] = sum;
                    }
                }
            }
            let elapsed = Date.now() - t0;
            let checksum = 0;
            for (let i = 0; i < n * n; i++)
            {
                checksum += c[i];
            }
            console.log("matmul 100x100 x3  [" + elapsed + " ms]  checksum = " + checksum);
        }
        Console.println("========== MatrixMul (JS) (end) ==========")
    }

    # 12. BinaryTree：depth12 x10 轮 + depth16 x2 轮（构建 + 求和）
    static binaryTree()
    {
        Console.println("========== BinaryTree (JS) (start) ==========")
        @javascript_quickjs()
        {
            function build(depth, value)
            {
                if (depth <= 0)
                {
                    return null;
                }
                let node = { value: value };
                node.left = build(depth - 1, value * 2);
                node.right = build(depth - 1, value * 2 + 1);
                return node;
            }
            function checksum(node)
            {
                if (node === null)
                {
                    return 0;
                }
                return node.value + checksum(node.left) + checksum(node.right);
            }
            let total = 0;
            let t0 = Date.now();
            for (let r = 0; r < 10; r++)
            {
                let root = build(12, r + 1);
                total += checksum(root);
            }
            console.log("tree depth12 x10 checksum = " + total + "  [" + (Date.now() - t0) + " ms]");
            let total2 = 0;
            t0 = Date.now();
            for (let r = 0; r < 2; r++)
            {
                let root = build(16, r + 1);
                total2 += checksum(root);
            }
            console.log("tree depth16 x2 checksum = " + total2 + "  [" + (Date.now() - t0) + " ms]");
        }
        Console.println("========== BinaryTree (JS) (end) ==========")
    }

    # 13. Mandelbrot：240x180 x3 轮（iterSum/inside 跨轮累加）
    static mandelbrot()
    {
        Console.println("========== Mandelbrot (JS) (start) ==========")
        @javascript_quickjs()
        {
            let w = 240;
            let h = 180;
            let maxIter = 150;
            let rounds = 3;
            let iterSum = 0;
            let insideCount = 0;
            let t0 = Date.now();
            for (let r = 0; r < rounds; r++)
            {
                for (let py = 0; py < h; py++)
                {
                    let y0 = py * 4.0 / h - 2.0;
                    for (let px = 0; px < w; px++)
                    {
                        let x0 = px * 4.0 / w - 2.0;
                        let x = 0.0;
                        let y = 0.0;
                        let iter = 0;
                        while (iter < maxIter && x * x + y * y <= 4.0)
                        {
                            let xtemp = x * x - y * y + x0;
                            y = 2.0 * x * y + y0;
                            x = xtemp;
                            iter++;
                        }
                        iterSum += iter;
                        if (iter === maxIter)
                        {
                            insideCount++;
                        }
                    }
                }
            }
            console.log("mandelbrot 240x180 x3  [" + (Date.now() - t0) + " ms]  iterSum = " + iterSum + "  inside = " + insideCount);
        }
        Console.println("========== Mandelbrot (JS) (end) ==========")
    }
}
