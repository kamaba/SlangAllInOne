import Std

# ============================================================================
# CSharpBench — C# 版基准（@csharp_mono(){} 内联块，mono 运行时）
# 13 项基准与 SL 版逐项对齐：相同算法 / 迭代次数 / 运算序列 / 输出行格式，
# 计时用 Stopwatch（毫秒口径同 Environment.sys.nowMillis）。
# 递归类算法（fib/levenshtein/nqueens/quicksort/binarytree/mandelbrot 的
# 算法主体）在 CsExtra/SlBenchLib.cs（jsonc plugins.csharp_mono.sources
# 合并编译进 SLAtSign.dll），块内头区 using SlBench; 即可调用。
# 注意：SL 层禁用行内 # 注释（只整行使用）；块内字符串禁字面 # 字符。
# ============================================================================

CSharpBench
{
    static fun()
    {
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
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            Stopwatch sw = Stopwatch.StartNew();
            long sum = 0L;
            for (int i = 0; i < 22; i++)
            {
                sum += Bench.Fib(i);
            }
            long ms = sw.ElapsedMilliseconds;
            Console.WriteLine("fib(0..21) sum = " + sum + "  [" + ms + " ms]");
        }
        Console.println("========== Fibonacci (CSharp) (end) ==========")
    }

    # 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool）
    static eqBench()
    {
        Console.println("========== EqBench (CSharp) (start) ==========")
        @csharp_mono()
        {
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            int k = 0;
            int s = 0;
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
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                if (b == true)
                {
                    cnt++;
                }
            }
            sw.Stop();
            Console.WriteLine("bool == 1e6 = " + cnt + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== EqBench (CSharp) (end) ==========")
    }

    # 3. Loop：数组求和 / while / 步进 for 三段
    static loopBench()
    {
        Console.println("========== Loop (CSharp) (start) ==========")
        @csharp_mono()
        {
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            int n = 1000;
            int[] arr = new int[n];
            for (int i = 0; i < n; i++)
            {
                arr[i] = i * i;
            }
            long total = 0L;
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
            sw.Restart();
            while (k < 5000000)
            {
                wsum += k;
                k++;
            }
            sw.Stop();
            Console.WriteLine("while sum 5e6 = " + wsum + "  [" + sw.ElapsedMilliseconds + " ms]");
            long stepSum = 0L;
            sw.Restart();
            for (int i = 0; i < 1000000; i += 7)
            {
                stepSum += i;
            }
            sw.Stop();
            Console.WriteLine("for step +7 1e6 = " + stepSum + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== Loop (CSharp) (end) ==========")
    }

    # 4. Levenshtein：编辑距离 DP（a,b 固定序列，先单次再 x5000）
    static levenshtein()
    {
        Console.println("========== Levenshtein (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            int[] a = new int[] { 10, 20, 30, 40, 50, 60 };
            int[] b = new int[] { 10, 25, 30, 35, 40, 50, 65 };
            int dist = Bench.Distance(a, b);
            Console.WriteLine("levenshtein(a,b) = " + dist);
            Stopwatch sw = new Stopwatch();
            long total = 0L;
            sw.Restart();
            for (int r = 0; r < 5000; r++)
            {
                total += Bench.Distance(a, b);
            }
            sw.Stop();
            Console.WriteLine("levenshtein x5000 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== Levenshtein (CSharp) (end) ==========")
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段
    static dataTypes()
    {
        Console.println("========== DataTypes (CSharp) (start) ==========")
        @csharp_mono()
        {
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            int s32 = 0;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                s32 += i;
            }
            sw.Stop();
            Console.WriteLine("Int32 sum 2e6 = " + s32 + "  [" + sw.ElapsedMilliseconds + " ms]");
            long s64 = 0L;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                s64 += i;
            }
            sw.Stop();
            Console.WriteLine("Int64 sum 2e6 = " + s64 + "  [" + sw.ElapsedMilliseconds + " ms]");
            double sf = 0.0;
            sw.Restart();
            for (int i = 0; i < 2000000; i++)
            {
                sf += i * 1.5;
            }
            sw.Stop();
            Console.WriteLine("Num sum 2e6 = " + sf + "  [" + sw.ElapsedMilliseconds + " ms]");
            double mix = 0.0;
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                mix = mix + i / 3.0 + i % 7;
            }
            sw.Stop();
            Console.WriteLine("Mixed ops 1e6 = " + mix + "  [" + sw.ElapsedMilliseconds + " ms]");
            int count = 0;
            sw.Restart();
            for (int i = 0; i < 1000000; i++)
            {
                if (i % 3 == 0 && i % 5 == 0)
                {
                    count++;
                }
            }
            sw.Stop();
            Console.WriteLine("bool mod 1e6 = " + count + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== DataTypes (CSharp) (end) ==========")
    }

    # 6. StringBench：拼接 / 插值构建 / format / 比较 / 结尾校验
    static stringBench()
    {
        Console.println("========== StringBench (CSharp) (start) ==========")
        @csharp_mono()
        {
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            string s = "";
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                s = s + "ab";
            }
            sw.Stop();
            Console.WriteLine("concat 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            string t = "";
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                t = "v=" + i + " s=" + (i * 2);
            }
            sw.Stop();
            Console.WriteLine("interp 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            string u = "";
            sw.Restart();
            for (int i = 0; i < 10000; i++)
            {
                u = string.Format("{0}-{1}", i, i + 1);
            }
            sw.Stop();
            Console.WriteLine("format 1e4  [" + sw.ElapsedMilliseconds + " ms]");
            int c = 0;
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
            Console.WriteLine("concat endswith ab = " + (s == u ? "true" : "false"));
        }
        Console.println("========== StringBench (CSharp) (end) ==========")
    }

    # 7. RegExpBench：编译 / 早命中 / 不命中 / matchAll / replace / 分组 /
    #    backref / UTF-8 中文 共 8 项（文本构建不计时）
    static regExpBench()
    {
        Console.println("========== RegExpBench (CSharp) (start) ==========")
        @csharp_mono()
        {
            using System.Diagnostics;
            using System.Text.RegularExpressions;
            string chunk = "abc123 def456 ghi789 ";
            string text = "";
            for (int i = 0; i < 4000; i++)
            {
                text = text + chunk;
            }
            Console.WriteLine("text bytes = " + text.Length);
            Stopwatch sw = new Stopwatch();
            sw.Restart();
            for (int i = 0; i < 2000; i++)
            {
                new Regex("([a-z]+)([0-9]+)");
            }
            sw.Stop();
            Console.WriteLine("compile x2000  [" + sw.ElapsedMilliseconds + " ms]");
            Regex re1 = new Regex("def456");
            string hit = "";
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
            sw.Restart();
            for (int i = 0; i < 20; i++)
            {
                miss = !re2.IsMatch(text);
            }
            sw.Stop();
            Console.WriteLine("search miss x20  [" + sw.ElapsedMilliseconds + " ms]  miss=" + (miss ? "true" : "false"));
            Regex re3 = new Regex("[a-z]+");
            int words = 0;
            sw.Restart();
            for (int i = 0; i < 5; i++)
            {
                words = re3.Matches(text).Count;
            }
            sw.Stop();
            Console.WriteLine("matchAll x5  [" + sw.ElapsedMilliseconds + " ms]  count=" + words);
            Regex re4 = new Regex("[0-9]+");
            string rep = "";
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
            sw.Restart();
            for (int i = 0; i < 100; i++)
            {
                Match m7 = re7.Match(text3);
                zh = m7.Success ? m7.Value : "";
            }
            sw.Stop();
            Console.WriteLine("utf8 search x100  [" + sw.ElapsedMilliseconds + " ms]  value=" + zh);
        }
        Console.println("========== RegExpBench (CSharp) (end) ==========")
    }

    # 8. NQueens：n=11 单轮（2680）+ n=9 x10 轮（3520）
    static nQueens()
    {
        Console.println("========== NQueens (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            sw.Restart();
            int solutions = Bench.Solve(11);
            sw.Stop();
            Console.WriteLine("nqueens(11) solutions = " + solutions + "  [" + sw.ElapsedMilliseconds + " ms]");
            int total = 0;
            sw.Restart();
            for (int r = 0; r < 10; r++)
            {
                total += Bench.Solve(9);
            }
            sw.Stop();
            Console.WriteLine("nqueens(9) x10 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== NQueens (CSharp) (end) ==========")
    }

    # 9. Sieve：1e6 单轮（78498）+ 5e5 x5 轮（207690）
    static sieve()
    {
        Console.println("========== Sieve (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            sw.Restart();
            int primes = Bench.CountPrimes(1000000);
            sw.Stop();
            Console.WriteLine("sieve 1e6 primes = " + primes + "  [" + sw.ElapsedMilliseconds + " ms]");
            int total = 0;
            sw.Restart();
            for (int r = 0; r < 5; r++)
            {
                total += Bench.CountPrimes(500000);
            }
            sw.Stop();
            Console.WriteLine("sieve 5e5 x5 = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== Sieve (CSharp) (end) ==========")
    }

    # 10. QuickSort：3e4 元素 x5 轮（LCG 数据生成不计时，逐轮计时累计）
    static quickSort()
    {
        Console.println("========== QuickSort (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            int n = 30000;
            int rounds = 5;
            long[] arr = new long[n];
            long totalMs = 0L;
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
                Bench.Sort(arr, 0, n - 1);
                sw.Stop();
                totalMs += sw.ElapsedMilliseconds;
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
            Console.WriteLine("quicksort 3e4 x5  [" + totalMs + " ms]  checksum = " + checksum);
        }
        Console.println("========== QuickSort (CSharp) (end) ==========")
    }

    # 11. MatrixMul：100x100 x3 轮（填充不计时，Int64 校验和）
    static matrixMul()
    {
        Console.println("========== MatrixMul (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
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
            Stopwatch sw = new Stopwatch();
            sw.Restart();
            for (int r = 0; r < rounds; r++)
            {
                Bench.Mul(a, b, c, n);
            }
            sw.Stop();
            long checksum = 0L;
            for (int i = 0; i < n * n; i++)
            {
                checksum += c[i];
            }
            Console.WriteLine("matmul 100x100 x3  [" + sw.ElapsedMilliseconds + " ms]  checksum = " + checksum);
        }
        Console.println("========== MatrixMul (CSharp) (end) ==========")
    }

    # 12. BinaryTree：depth12 x10 轮 + depth16 x2 轮（构建 + 求和）
    static binaryTree()
    {
        Console.println("========== BinaryTree (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            Stopwatch sw = new Stopwatch();
            long total = 0L;
            sw.Restart();
            for (int r = 0; r < 10; r++)
            {
                BenchNode root = Bench.Build(12, r + 1);
                total += Bench.Checksum(root);
            }
            sw.Stop();
            Console.WriteLine("tree depth12 x10 checksum = " + total + "  [" + sw.ElapsedMilliseconds + " ms]");
            long total2 = 0L;
            sw.Restart();
            for (int r = 0; r < 2; r++)
            {
                BenchNode root = Bench.Build(16, r + 1);
                total2 += Bench.Checksum(root);
            }
            sw.Stop();
            Console.WriteLine("tree depth16 x2 checksum = " + total2 + "  [" + sw.ElapsedMilliseconds + " ms]");
        }
        Console.println("========== BinaryTree (CSharp) (end) ==========")
    }

    # 13. Mandelbrot：240x180 x3 轮（iterSum/inside 跨轮累加）
    static mandelbrot()
    {
        Console.println("========== Mandelbrot (CSharp) (start) ==========")
        @csharp_mono()
        {
            using SlBench;
            using System.Diagnostics;
            int w = 240;
            int h = 180;
            int maxIter = 150;
            int rounds = 3;
            long iterSum = 0L;
            int insideCount = 0;
            Stopwatch sw = new Stopwatch();
            sw.Restart();
            for (int r = 0; r < rounds; r++)
            {
                iterSum += Bench.Render(w, h, maxIter, ref insideCount);
            }
            sw.Stop();
            Console.WriteLine("mandelbrot 240x180 x3  [" + sw.ElapsedMilliseconds + " ms]  iterSum = " + iterSum + "  inside = " + insideCount);
        }
        Console.println("========== Mandelbrot (CSharp) (end) ==========")
    }
}
