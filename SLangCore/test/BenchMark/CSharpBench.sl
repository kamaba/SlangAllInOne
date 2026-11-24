import Std

# ============================================================================
# CSharpBench — C# 版基准（@csharp_mono(){} 内联块，mono 运行时）
# 13 项基准与 SL 版逐项对齐：相同算法 / 迭代次数 / 运算序列 / 输出行格式。
# 计时：块内 Stopwatch 自身计时（us 粒度，经出通道 $us 回传 SL 侧
# recordCSharp——不含引擎调用/装载/部署开销，与 C/C++/Python 口径一致）。
# 算法全部内联进块体（原 CsExtra/SlBenchLib.cs 已合并删档）：块体是方法
# 体且 csc 为 C#5（Framework64\v4.0.30319），无局部类/局部函数——递归算法
# 用 Func/Action 自引用 lambda（fib/nqueens/quicksort/build/checksum），
# 纯循环算法用单次 lambda 调用；binaryTree 的树节点用本文件顶层 SL
# class BenchNode，binaryTree 块经入通道 `BenchNode mn <- $mn` 触发 Front
# slTypes 布局下发，csharp_mono 插件生成 SLAtSign 命名空间镜像类
#（public 字段 left/right/value）合并编进 SLAtSign.dll——保持与
# SL/C++/Java/Go 逐节点对象堆分配同语义。
# 注意：SL 层禁用行内 # 注释（只整行使用）；块内字符串禁字面 # 字符。
# ============================================================================

# CSharpBench 二叉树节点（供 binaryTree 块镜像生成，见文件头注释）
class BenchNode
{
    BenchNode left = null
    BenchNode right = null
    long value = 0L
}

CSharpBench
{
    static fun()
    {
        # 各子项块内 Stopwatch 自身计时（us 粒度，经出通道回传），方法内直接记录进 BenchCollector
        CSharpBench.fibonacci()
        CSharpBench.eqBench()
        CSharpBench.loopBench()
        CSharpBench.levenshtein()
        CSharpBench.dataTypes()
        CSharpBench.stringBench()
        CSharpBench.regExpBench()
        CSharpBench.nQueens()
        CSharpBench.sieve()
        CSharpBench.quickSort()
        CSharpBench.matrixMul()
        CSharpBench.binaryTree()
        CSharpBench.mandelbrot()
    }

    # 1. Fibonacci：fib(0..21) 递归求和（= 17711）
    static fibonacci()
    {
        Console.println("========== Fibonacci (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = Stopwatch.StartNew();
            Func<int, int> fib = null;
            fib = n => n <= 1 ? n : fib(n - 1) + fib(n - 2);
            long sum = 0L;
            for (int i = 0; i < 22; i++)
            {
                sum += fib(i);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("fib(0..21) sum = " + sum + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== Fibonacci (CSharp) (end) ==========")
        BenchCollector.recordCSharp("Fibonacci", "fib(0..21) 递归求和（块内 Stopwatch us）", us)
    }

    # 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool）
    static eqBench()
    {
        Console.println("========== EqBench (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            int k = 0;
            int s = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            while (k != 2000000)
            {
                s += k;
                k++;
            }
            sw.Stop();
            Console.WriteLine("i32 != 2e6 = " + s + "  [" + sw.ElapsedMilliseconds + " ms]");
            long k64 = 0L;
            long s64 = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            while (k64 != 2000000L)
            {
                s64 += k64;
                k64++;
            }
            sw.Stop();
            Console.WriteLine("i64 != 2e6 = " + s64 + "  [" + sw.ElapsedMilliseconds + " ms]");
            double kd = 0.0;
            double sd = 0.0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            while (kd != 2000000.0)
            {
                sd += kd;
                kd += 1.0;
            }
            sw.Stop();
            Console.WriteLine("f64 != 2e6 = " + sd + "  [" + sw.ElapsedMilliseconds + " ms]");
            bool b = true;
            int cnt = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                if (b == true)
                {
                    cnt++;
                }
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("bool == 1e6 = " + cnt + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== EqBench (CSharp) (end) ==========")
        BenchCollector.recordCSharp("EqBench", "4子项（块内 Stopwatch us）", us)
    }

    # 3. Loop：数组求和 / while / 步进 for 三段
    static loopBench()
    {
        Console.println("========== Loop (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            int n = 1000;
            int[] arr = new int[n];
            for (int i = 0; i < n; i++)
            {
                arr[i] = i * i;
            }
            long total = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int j = 0; j < 3000; j++)
            {
                long s = 0L;
                for (int i = 0; i < n; i++)
                {
                    s += arr[i];
                }
                total += s;
            }
            sw.Stop();
            Console.WriteLine("array sum x3000 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            long wsum = 0L;
            int k = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            while (k < 5000000)
            {
                wsum += k;
                k++;
            }
            sw.Stop();
            Console.WriteLine("while sum 5e6 = " + wsum + "  [" + sw.ElapsedMilliseconds + " ms]");
            long stepSum = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 1000000; i += 7)
            {
                stepSum += i;
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("for step +7 1e6 = " + stepSum + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== Loop (CSharp) (end) ==========")
        BenchCollector.recordCSharp("Loop", "3子项（块内 Stopwatch us）", us)
    }

    # 4. Levenshtein：编辑距离 DP（a,b 固定序列，先单次再 x5000）
    static levenshtein()
    {
        Console.println("========== Levenshtein (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            int[] a = new int[] { 10, 20, 30, 40, 50, 60 };
            int[] b = new int[] { 10, 25, 30, 35, 40, 50, 65 };
            Func<int[], int[], int> distance = null;
            distance = (x, y) =>
            {
                int m = x.Length;
                int n = y.Length;
                int[] prev = new int[n + 1];
                int[] curr = new int[n + 1];
                for (int j = 0; j <= n; j++)
                {
                    prev[j] = j;
                }
                for (int i = 1; i <= m; i++)
                {
                    curr[0] = i;
                    for (int j = 1; j <= n; j++)
                    {
                        int cost = x[i - 1] == y[j - 1] ? 0 : 1;
                        int del = prev[j] + 1;
                        int ins = curr[j - 1] + 1;
                        int sub = prev[j - 1] + cost;
                        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
                    }
                    int[] tmp = prev;
                    prev = curr;
                    curr = tmp;
                }
                return prev[n];
            };
            int dist = distance(a, b);
            Console.WriteLine("levenshtein(a,b) = " + dist);
            Stopwatch sw = new Stopwatch();
            long total = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < 5000; r++)
            {
                total += distance(a, b);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("levenshtein x5000 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== Levenshtein (CSharp) (end) ==========")
        BenchCollector.recordCSharp("Levenshtein", "levenshtein x5000（块内 Stopwatch us）", us)
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段
    static dataTypes()
    {
        Console.println("========== DataTypes (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            int s32 = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                s32 += i;
            }
            sw.Stop();
            Console.WriteLine("Int32 sum 2e6 = " + s32 + "  [" + sw.ElapsedMilliseconds + " ms]");
            long s64 = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                s64 += i;
            }
            sw.Stop();
            Console.WriteLine("Int64 sum 2e6 = " + s64 + "  [" + sw.ElapsedMilliseconds + " ms]");
            double sf = 0.0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                sf += i * 1.5;
            }
            sw.Stop();
            Console.WriteLine("Num sum 2e6 = " + sf + "  [" + sw.ElapsedMilliseconds + " ms]");
            double mix = 0.0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                mix = mix + i / 3.0 + i % 7;
            }
            sw.Stop();
            Console.WriteLine("Mixed ops 1e6 = " + mix + "  [" + sw.ElapsedMilliseconds + " ms]");
            int count = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                if (i % 3 == 0 && i % 5 == 0)
                {
                    count++;
                }
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("bool mod 1e6 = " + count + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== DataTypes (CSharp) (end) ==========")
        BenchCollector.recordCSharp("DataTypes", "5子项（块内 Stopwatch us）", us)
    }

    # 6. StringBench：拼接 / 插值构建 / format / 比较 / 结尾校验
    static stringBench()
    {
        Console.println("========== StringBench (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            string s = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                s = s + "ab";
            }
            sw.Stop();
            Console.WriteLine("concat 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            string t = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                t = "v=" + i + " s=" + (i * 2);
            }
            sw.Stop();
            Console.WriteLine("interp 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            string u = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                u = string.Format("{0}-{1}", i, i + 1);
            }
            sw.Stop();
            Console.WriteLine("format 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            int c = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 100000; i++)
            {
                if (s == t)
                {
                    c++;
                }
            }
            sw.Stop();
            Console.WriteLine("compare 1e5  count=" + c + "  [" + sw.ElapsedMilliseconds + " ms]");
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("concat endswith ab = " + (s == u ? "true" : "false"));
            $us <- (int)acc;
        }
        Console.println("========== StringBench (CSharp) (end) ==========")
        BenchCollector.recordCSharp("StringBench", "4子项（块内 Stopwatch us）", us)
    }

    # 7. RegExpBench：编译 / 早命中 / 不命中 / matchAll / replace / 分组 /
    #    backref / UTF-8 中文 共 8 项（文本构建不计时）
    static regExpBench()
    {
        Console.println("========== RegExpBench (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            using System.Text.RegularExpressions;
            long acc = 0L;
            string chunk = "abc123 def456 ghi789 ";
            string text = "";
            for (int i = 0; i < 4000; i++)
            {
                text = text + chunk;
            }
            Console.WriteLine("text bytes = " + text.Length);
            Stopwatch sw = new Stopwatch();
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 2000; i++)
            {
                new Regex("([a-z]+)([0-9]+)");
            }
            sw.Stop();
            Console.WriteLine("compile x2000  [" + sw.ElapsedMilliseconds + " ms]");
            Regex re1 = new Regex("def456");
            string hit = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 500; i++)
            {
                Match m1 = re1.Match(text);
                hit = m1.Success ? m1.Value : "";
            }
            sw.Stop();
            Console.WriteLine("search hit x500  [" + sw.ElapsedMilliseconds + " ms]  value=" + hit);
            Regex re2 = new Regex("zzz999");
            bool miss = true;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 20; i++)
            {
                miss = !re2.IsMatch(text);
            }
            sw.Stop();
            Console.WriteLine("search miss x20  [" + sw.ElapsedMilliseconds + " ms]  miss=" + (miss ? "true" : "false"));
            Regex re3 = new Regex("[a-z]+");
            int words = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 5; i++)
            {
                words = re3.Matches(text).Count;
            }
            sw.Stop();
            Console.WriteLine("matchAll x5  [" + sw.ElapsedMilliseconds + " ms]  count=" + words);
            Regex re4 = new Regex("[0-9]+");
            string rep = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 5; i++)
            {
                rep = re4.Replace(text, "\x23");
            }
            sw.Stop();
            Console.WriteLine("replace x5  [" + sw.ElapsedMilliseconds + " ms]  len=" + rep.Length);
            Regex re5 = new Regex("([a-z]+)([0-9]+)");
            string g1 = "";
            string g2 = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 200; i++)
            {
                Match m5 = re5.Match(text);
                g1 = m5.Groups[1].Value;
                g2 = m5.Groups[2].Value;
            }
            sw.Stop();
            Console.WriteLine("group search x200  [" + sw.ElapsedMilliseconds + " ms]  g1=" + g1 + " g2=" + g2);
            string chunk2 = "abc abc def def ";
            string text2 = "";
            for (int i = 0; i < 2000; i++)
            {
                text2 = text2 + chunk2;
            }
            Regex re6 = new Regex("(\\w+) \\1");
            int pairs = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 10; i++)
            {
                pairs = re6.Matches(text2).Count;
            }
            sw.Stop();
            Console.WriteLine("backref matchAll x10  [" + sw.ElapsedMilliseconds + " ms]  count=" + pairs);
            string chunk3 = "中文测试123 ";
            string text3 = "";
            for (int i = 0; i < 2000; i++)
            {
                text3 = text3 + chunk3;
            }
            Regex re7 = new Regex("测试[0-9]+");
            string zh = "";
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int i = 0; i < 100; i++)
            {
                Match m7 = re7.Match(text3);
                zh = m7.Success ? m7.Value : "";
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("utf8 search x100  [" + sw.ElapsedMilliseconds + " ms]  value=" + zh);
            $us <- (int)acc;
        }
        Console.println("========== RegExpBench (CSharp) (end) ==========")
        BenchCollector.recordCSharp("RegExpBench", "8子项（块内 Stopwatch us）", us)
    }

    # 8. NQueens：n=11 单轮（2680）+ n=9 x10 轮（3520）
    static nQueens()
    {
        Console.println("========== NQueens (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            Func<int[], int, int, int> place = null;
            place = (qs, row, size) =>
            {
                if (row == size)
                {
                    return 1;
                }
                int count = 0;
                for (int col = 0; col < size; col++)
                {
                    int ok = 1;
                    for (int i = 0; i < row; i++)
                    {
                        if (qs[i] == col || qs[i] - i == col - row || qs[i] + i == col + row)
                        {
                            ok = 0;
                            break;
                        }
                    }
                    if (ok == 1)
                    {
                        qs[row] = col;
                        count += place(qs, row + 1, size);
                    }
                }
                return count;
            };
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            int solutions = place(new int[11], 0, 11);
            sw.Stop();
            Console.WriteLine("nqueens(11) solutions = " + solutions + "  [" + sw.ElapsedMilliseconds + " ms]");
            int total = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < 10; r++)
            {
                total += place(new int[9], 0, 9);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("nqueens(9) x10 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== NQueens (CSharp) (end) ==========")
        BenchCollector.recordCSharp("NQueens", "n=11 单轮 + n=9 x10（块内 Stopwatch us）", us)
    }

    # 9. Sieve：1e6 单轮（78498）+ 5e5 x5 轮（207690）
    static sieve()
    {
        Console.println("========== Sieve (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            Func<int, int> countPrimes = limit =>
            {
                int[] isComposite = new int[limit + 1];
                int count = 0;
                for (int i = 2; i <= limit; i++)
                {
                    if (isComposite[i] == 0)
                    {
                        count++;
                        if (i <= limit / i)
                        {
                            int j = i * i;
                            while (j <= limit)
                            {
                                isComposite[j] = 1;
                                j += i;
                            }
                        }
                    }
                }
                return count;
            };
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            int primes = countPrimes(1000000);
            sw.Stop();
            Console.WriteLine("sieve 1e6 primes = " + primes + "  [" + sw.ElapsedMilliseconds + " ms]");
            int total = 0;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < 5; r++)
            {
                total += countPrimes(500000);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("sieve 5e5 x5 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== Sieve (CSharp) (end) ==========")
        BenchCollector.recordCSharp("Sieve", "1e6 单轮 + 5e5 x5（块内 Stopwatch us）", us)
    }

    # 10. QuickSort：3e4 元素 x5 轮（LCG 数据生成不计时，逐轮计时累计）
    static quickSort()
    {
        Console.println("========== QuickSort (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            Action<long[], int, int> sort = null;
            sort = (sarr, lo, hi) =>
            {
                if (lo >= hi)
                {
                    return;
                }
                int i = lo;
                int j = hi;
                long p = sarr[(lo + hi) / 2];
                while (i <= j)
                {
                    while (sarr[i] < p)
                    {
                        i++;
                    }
                    while (sarr[j] > p)
                    {
                        j--;
                    }
                    if (i <= j)
                    {
                        long tmp = sarr[i];
                        sarr[i] = sarr[j];
                        sarr[j] = tmp;
                        i++;
                        j--;
                    }
                }
                sort(sarr, lo, j);
                sort(sarr, i, hi);
            };
            int n = 30000;
            int rounds = 5;
            long[] arr = new long[n];
            long totalUs = 0L;
            long checksum = 0L;
            Stopwatch sw = new Stopwatch();
            for (int r = 0; r < rounds; r++)
            {
                long seed = 42L + r;
                for (int i = 0; i < n; i++)
                {
                    seed = (seed * 16807) % 2147483647;
                    arr[i] = seed;
                }
                sw.Restart();
                sort(arr, 0, n - 1);
                sw.Stop();
                totalUs += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
                for (int i = 0; i < n; i++)
                {
                    checksum += arr[i];
                    if (i > 0)
                    {
                        if (arr[i - 1] > arr[i])
                        {
                            Console.WriteLine("SORTED CHECK FAILED at " + i);
                        }
                    }
                }
            }
            Console.WriteLine("quicksort 3e4 x5  [" + totalUs + " us]  checksum = " + checksum);
            $us <- (int)totalUs;
        }
        Console.println("========== QuickSort (CSharp) (end) ==========")
        BenchCollector.recordCSharp("QuickSort", "quicksort 3e4 x5（块内 Stopwatch us）", us)
    }

    # 11. MatrixMul：100x100 x3 轮（填充不计时，Int64 校验和）
    static matrixMul()
    {
        Console.println("========== MatrixMul (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            int n = 100;
            int rounds = 3;
            int[] a = new int[n * n];
            int[] b = new int[n * n];
            int[] c = new int[n * n];
            for (int i = 0; i < n; i++)
            {
                for (int j = 0; j < n; j++)
                {
                    a[i * n + j] = (i + j) % 100;
                    b[i * n + j] = (i * 7 + j * 3) % 100;
                }
            }
            Action<int[], int[], int[], int> mul = (ma, mb, mc, size) =>
            {
                for (int i = 0; i < size; i++)
                {
                    for (int j = 0; j < size; j++)
                    {
                        int sum = 0;
                        for (int k = 0; k < size; k++)
                        {
                            sum += ma[i * size + k] * mb[k * size + j];
                        }
                        mc[i * size + j] = sum;
                    }
                }
            };
            Stopwatch sw = new Stopwatch();
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < rounds; r++)
            {
                mul(a, b, c, n);
            }
            sw.Stop();
            long checksum = 0L;
            for (int i = 0; i < n * n; i++)
            {
                checksum += c[i];
            }
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("matmul 100x100 x3  [" + sw.ElapsedMilliseconds + " ms]  checksum = " + checksum);
            $us <- (int)acc;
        }
        Console.println("========== MatrixMul (CSharp) (end) ==========")
        BenchCollector.recordCSharp("MatrixMul", "matmul 100x100 x3（块内 Stopwatch us）", us)
    }

    # 12. BinaryTree：depth12 x10 轮 + depth16 x2 轮（构建 + 求和）
    # 节点 = 本文件顶层 SL class BenchNode 的镜像类（块入通道 `BenchNode mn
    # <- $mn` 触发布局下发，见文件头注释），dummy 节点仅在编译期触发生成、
    # 运行期随哨兵装配一次（零开销级），树构建/求和全在块内镜像类上进行。
    static binaryTree()
    {
        Console.println("========== BinaryTree (CSharp) (start) ==========")
        long us = 0L
        BenchNode mn = BenchNode()
        @csharp_mono()
        {
            BenchNode mn <- $mn
            using System.Diagnostics;
            long acc = 0L;
            Stopwatch sw = new Stopwatch();
            Func<int, int, BenchNode> build = null;
            build = (depth, v) =>
            {
                if (depth <= 0)
                {
                    return null;
                }
                BenchNode node = new BenchNode();
                node.value = v;
                node.left = build(depth - 1, v * 2);
                node.right = build(depth - 1, v * 2 + 1);
                return node;
            };
            Func<BenchNode, long> checksum = null;
            checksum = node => node == null ? 0L : node.value + checksum(node.left) + checksum(node.right);
            long total = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < 10; r++)
            {
                BenchNode root = build(12, r + 1);
                total += checksum(root);
            }
            sw.Stop();
            Console.WriteLine("tree depth12 x10 checksum = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            long total2 = 0L;
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < 2; r++)
            {
                BenchNode root = build(16, r + 1);
                total2 += checksum(root);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("tree depth16 x2 checksum = " + total2 + "  [" + sw.ElapsedMilliseconds + " ms]");
            $us <- (int)acc;
        }
        Console.println("========== BinaryTree (CSharp) (end) ==========")
        BenchCollector.recordCSharp("BinaryTree", "depth12 x10 + depth16 x2（块内 Stopwatch us）", us)
    }

    # 13. Mandelbrot：240x180 x3 轮（iterSum/inside 跨轮累加）
    static mandelbrot()
    {
        Console.println("========== Mandelbrot (CSharp) (start) ==========")
        long us = 0L
        @csharp_mono()
        {
            using System.Diagnostics;
            long acc = 0L;
            int w = 240;
            int h = 180;
            int maxIter = 150;
            int rounds = 3;
            long iterSum = 0L;
            int insideCount = 0;
            Func<int, int, int, long> render = (ww, hh, mi) =>
            {
                long iterTotal = 0L;
                for (int py = 0; py < hh; py++)
                {
                    double y0 = py * 4.0 / hh - 2.0;
                    for (int px = 0; px < ww; px++)
                    {
                        double x0 = px * 4.0 / ww - 2.0;
                        double x = 0.0;
                        double y = 0.0;
                        int iter = 0;
                        while (iter < mi && x * x + y * y <= 4.0)
                        {
                            double xtemp = x * x - y * y + x0;
                            y = 2.0 * x * y + y0;
                            x = xtemp;
                            iter++;
                        }
                        iterTotal += iter;
                        if (iter == mi)
                        {
                            insideCount++;
                        }
                    }
                }
                return iterTotal;
            };
            Stopwatch sw = new Stopwatch();
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            sw.Restart();
            for (int r = 0; r < rounds; r++)
            {
                iterSum += render(w, h, maxIter);
            }
            sw.Stop();
            acc += sw.ElapsedTicks * 1000000L / Stopwatch.Frequency;
            Console.WriteLine("mandelbrot 240x180 x3  [" + sw.ElapsedMilliseconds + " ms]  iterSum = " + iterSum + "  inside = " + insideCount);
            $us <- (int)acc;
        }
        Console.println("========== Mandelbrot (CSharp) (end) ==========")
        BenchCollector.recordCSharp("Mandelbrot", "mandelbrot 240x180 x3（块内 Stopwatch us）", us)
    }
}
