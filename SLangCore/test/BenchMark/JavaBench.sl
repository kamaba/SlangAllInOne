import Std

# ============================================================================
# JavaBench — Java 版基准（@java_hotspot(){} 内联块，Hotspot 运行时）
# 13 项基准与 SL 版逐项对齐：相同算法 / 迭代次数 / 运算序列 / 输出行格式。
# 计时：块内 System.nanoTime() 自身计时（ns 累计，出通道 /1000 折 us 回传
# SL 侧 recordJava——不含引擎调用/装载/部署开销，与 C/C++/Python 口径一致）。
# java_hotspot 插件不支持 jsonc sources 段，递归类算法以块内局部类承载
#（块体经 javac --release 17 编译部署到插件 classes 目录后加载执行）。
# 注意：SL 层禁行内 # 注释（只整行使用）；块内字符串禁字面 # 字符
#（replaceAll 目标字符写作 \u0023）；Java 域块体头区只吸收 import 指令行；
# 同一作用域不能重复声明局部变量（多段计时的 t0 用重赋值续用）。
# 嵌入式 JVM 的 System.out 默认跟随宿主 ANSI 代码页（非 UTF-8），中文输出
# 会变 ?；regExpBench 块内 System.setOut 显式切 UTF-8 对齐 SL/C# 输出通路。
# ============================================================================

JavaBench
{
    static fun()
    {
        # 各子项块内 nanoTime 自身计时（出通道 /1000 折 us 回传），方法内直接记录进 BenchCollector
        JavaBench.fibonacci()
        JavaBench.eqBench()
        JavaBench.loopBench()
        JavaBench.levenshtein()
        JavaBench.dataTypes()
        JavaBench.stringBench()
        JavaBench.regExpBench()
        JavaBench.nQueens()
        JavaBench.sieve()
        JavaBench.quickSort()
        JavaBench.matrixMul()
        JavaBench.binaryTree()
        JavaBench.mandelbrot()
    }

    # 1. Fibonacci：fib(0..21) 递归求和（= 17711）
    static fibonacci()
    {
        Console.println("========== Fibonacci (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            class FibB
            {
                int fib(int n)
                {
                    return n <= 1 ? n : fib(n - 1) + fib(n - 2);
                }
            }
            FibB fb = new FibB();
            long t0 = System.nanoTime();
            long sum = 0L;
            for (int i = 0; i < 22; i++)
            {
                sum += fb.fib(i);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("fib(0..21) sum = " + sum + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== Fibonacci (Java) (end) ==========")
        BenchCollector.recordJava("Fibonacci", "fib(0..21) 递归求和（块内 nanoTime us）", us)
    }

    # 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool）
    static eqBench()
    {
        Console.println("========== EqBench (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            int k = 0;
            int s = 0;
            long t0 = System.nanoTime();
            while (k != 2000000)
            {
                s += k;
                k++;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("i32 != 2e6 = " + s + "  [" + dt / 1000000L + " ms]");
            long k64 = 0L;
            long s64 = 0L;
            t0 = System.nanoTime();
            while (k64 != 2000000L)
            {
                s64 += k64;
                k64++;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("i64 != 2e6 = " + s64 + "  [" + dt / 1000000L + " ms]");
            double kd = 0.0;
            double sd = 0.0;
            t0 = System.nanoTime();
            while (kd != 2000000.0)
            {
                sd += kd;
                kd += 1.0;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("f64 != 2e6 = " + sd + "  [" + dt / 1000000L + " ms]");
            boolean b = true;
            int cnt = 0;
            t0 = System.nanoTime();
            for (int i = 0; i < 1000000; i++)
            {
                if (b == true)
                {
                    cnt++;
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("bool == 1e6 = " + cnt + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== EqBench (Java) (end) ==========")
        BenchCollector.recordJava("EqBench", "4子项（块内 nanoTime us）", us)
    }

    # 3. Loop：数组求和 / while / 步进 for 三段
    static loopBench()
    {
        Console.println("========== Loop (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            int n = 1000;
            int[] arr = new int[n];
            for (int i = 0; i < n; i++)
            {
                arr[i] = i * i;
            }
            long total = 0L;
            long t0 = System.nanoTime();
            for (int j = 0; j < 3000; j++)
            {
                long s = 0L;
                for (int i = 0; i < n; i++)
                {
                    s += arr[i];
                }
                total += s;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("array sum x3000 = " + total + "  [" + dt / 1000000L + " ms]");
            long wsum = 0L;
            int k = 0;
            t0 = System.nanoTime();
            while (k < 5000000)
            {
                wsum += k;
                k++;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("while sum 5e6 = " + wsum + "  [" + dt / 1000000L + " ms]");
            long stepSum = 0L;
            t0 = System.nanoTime();
            for (int i = 0; i < 1000000; i += 7)
            {
                stepSum += i;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("for step +7 1e6 = " + stepSum + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== Loop (Java) (end) ==========")
        BenchCollector.recordJava("Loop", "3子项（块内 nanoTime us）", us)
    }

    # 4. Levenshtein：编辑距离 DP（a,b 固定序列，先单次再 x5000）
    static levenshtein()
    {
        Console.println("========== Levenshtein (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            class LevB
            {
                int distance(int[] a, int[] b)
                {
                    int m = a.length;
                    int n = b.length;
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
                            int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                            int del = prev[j] + 1;
                            int ins = curr[j - 1] + 1;
                            int sub = prev[j - 1] + cost;
                            curr[j] = min3(del, ins, sub);
                        }
                        int[] tmp = prev;
                        prev = curr;
                        curr = tmp;
                    }
                    return prev[n];
                }
                int min3(int x, int y, int z)
                {
                    if (x < y && x < z)
                    {
                        return x;
                    }
                    if (y < z)
                    {
                        return y;
                    }
                    return z;
                }
            }
            LevB lb = new LevB();
            int[] a = { 10, 20, 30, 40, 50, 60 };
            int[] b = { 10, 25, 30, 35, 40, 50, 65 };
            int dist = lb.distance(a, b);
            System.out.println("levenshtein(a,b) = " + dist);
            long total = 0L;
            long t0 = System.nanoTime();
            for (int r = 0; r < 5000; r++)
            {
                total += lb.distance(a, b);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("levenshtein x5000 = " + total + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== Levenshtein (Java) (end) ==========")
        BenchCollector.recordJava("Levenshtein", "levenshtein x5000（块内 nanoTime us）", us)
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段
    static dataTypes()
    {
        Console.println("========== DataTypes (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            int s32 = 0;
            long t0 = System.nanoTime();
            for (int i = 0; i < 2000000; i++)
            {
                s32 += i;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("Int32 sum 2e6 = " + s32 + "  [" + dt / 1000000L + " ms]");
            long s64 = 0L;
            t0 = System.nanoTime();
            for (int i = 0; i < 2000000; i++)
            {
                s64 += i;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("Int64 sum 2e6 = " + s64 + "  [" + dt / 1000000L + " ms]");
            double sf = 0.0;
            t0 = System.nanoTime();
            for (int i = 0; i < 2000000; i++)
            {
                sf += i * 1.5;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("Num sum 2e6 = " + sf + "  [" + dt / 1000000L + " ms]");
            double mix = 0.0;
            t0 = System.nanoTime();
            for (int i = 0; i < 1000000; i++)
            {
                mix = mix + i / 3.0 + i % 7;
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("Mixed ops 1e6 = " + mix + "  [" + dt / 1000000L + " ms]");
            int count = 0;
            t0 = System.nanoTime();
            for (int i = 0; i < 1000000; i++)
            {
                if (i % 3 == 0 && i % 5 == 0)
                {
                    count++;
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("bool mod 1e6 = " + count + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== DataTypes (Java) (end) ==========")
        BenchCollector.recordJava("DataTypes", "5子项（块内 nanoTime us）", us)
    }

    # 6. StringBench：拼接 / 插值构建 / format / 比较 / 结尾校验
    static stringBench()
    {
        Console.println("========== StringBench (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            String s = "";
            long t0 = System.nanoTime();
            for (int i = 0; i < 10000; i++)
            {
                s = s + "ab";
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("concat 1e4  [" + dt / 1000000L + " ms]");
            String t = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 10000; i++)
            {
                t = "v=" + i + " s=" + (i * 2);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("interp 1e4  [" + dt / 1000000L + " ms]");
            String u = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 10000; i++)
            {
                u = String.format("%d-%d", i, i + 1);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("format 1e4  [" + dt / 1000000L + " ms]");
            int c = 0;
            t0 = System.nanoTime();
            for (int i = 0; i < 100000; i++)
            {
                if (s.equals(t))
                {
                    c++;
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("compare 1e5  count=" + c + "  [" + dt / 1000000L + " ms]");
            System.out.println("concat endswith ab = " + s.equals(u));
            $us <- acc / 1000L;
        }
        Console.println("========== StringBench (Java) (end) ==========")
        BenchCollector.recordJava("StringBench", "4子项（块内 nanoTime us）", us)
    }

    # 7. RegExpBench：编译 / 命中 / 未命中 / 全量 / 替换 / 分组 / 反向引用 / UTF8
    static regExpBench()
    {
        Console.println("========== RegExpBench (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            import java.util.regex.Matcher;
            import java.util.regex.Pattern;
            long acc = 0L;
            long dt = 0L;
            System.setOut(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), true, java.nio.charset.StandardCharsets.UTF_8));
            String chunk = "abc123 def456 ghi789 ";
            String text = "";
            for (int i = 0; i < 4000; i++)
            {
                text = text + chunk;
            }
            System.out.println("text bytes = " + text.length());
            long t0 = System.nanoTime();
            for (int i = 0; i < 2000; i++)
            {
                Pattern.compile("([a-z]+)([0-9]+)");
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("compile x2000  [" + dt / 1000000L + " ms]");
            Pattern re1 = Pattern.compile("def456");
            String hit = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 500; i++)
            {
                Matcher m1 = re1.matcher(text);
                hit = m1.find() ? m1.group() : "";
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("search hit x500  [" + dt / 1000000L + " ms]  value=" + hit);
            Pattern re2 = Pattern.compile("zzz999");
            boolean miss = true;
            t0 = System.nanoTime();
            for (int i = 0; i < 20; i++)
            {
                miss = !re2.matcher(text).find();
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("search miss x20  [" + dt / 1000000L + " ms]  miss=" + miss);
            Pattern re3 = Pattern.compile("[a-z]+");
            int words = 0;
            t0 = System.nanoTime();
            for (int i = 0; i < 5; i++)
            {
                Matcher m3 = re3.matcher(text);
                words = 0;
                while (m3.find())
                {
                    words++;
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("matchAll x5  [" + dt / 1000000L + " ms]  count=" + words);
            Pattern re4 = Pattern.compile("[0-9]+");
            String rep = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 5; i++)
            {
                rep = re4.matcher(text).replaceAll("\u0023");
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("replace x5  [" + dt / 1000000L + " ms]  len=" + rep.length());
            Pattern re5 = Pattern.compile("([a-z]+)([0-9]+)");
            String g1 = "";
            String g2 = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 200; i++)
            {
                Matcher m5 = re5.matcher(text);
                if (m5.find())
                {
                    g1 = m5.group(1);
                    g2 = m5.group(2);
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("group search x200  [" + dt / 1000000L + " ms]  g1=" + g1 + " g2=" + g2);
            String chunk2 = "abc abc def def ";
            String text2 = "";
            for (int i = 0; i < 2000; i++)
            {
                text2 = text2 + chunk2;
            }
            Pattern re6 = Pattern.compile("(\\w+) \\1");
            int pairs = 0;
            t0 = System.nanoTime();
            for (int i = 0; i < 10; i++)
            {
                Matcher m6 = re6.matcher(text2);
                pairs = 0;
                while (m6.find())
                {
                    pairs++;
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("backref matchAll x10  [" + dt / 1000000L + " ms]  count=" + pairs);
            String chunk3 = "中文测试123 ";
            String text3 = "";
            for (int i = 0; i < 2000; i++)
            {
                text3 = text3 + chunk3;
            }
            Pattern re7 = Pattern.compile("测试[0-9]+");
            String zh = "";
            t0 = System.nanoTime();
            for (int i = 0; i < 100; i++)
            {
                Matcher m7 = re7.matcher(text3);
                zh = m7.find() ? m7.group() : "";
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("utf8 search x100  [" + dt / 1000000L + " ms]  value=" + zh);
            $us <- acc / 1000L;
        }
        Console.println("========== RegExpBench (Java) (end) ==========")
        BenchCollector.recordJava("RegExpBench", "8子项（块内 nanoTime us）", us)
    }

    # 8. NQueens：n=11 单轮（2680）+ n=9 x10 轮（3520）
    static nQueens()
    {
        Console.println("========== NQueens (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            class NQB
            {
                int solve(int n)
                {
                    int[] queens = new int[n];
                    return place(queens, 0, n);
                }
                int place(int[] queens, int row, int n)
                {
                    if (row == n)
                    {
                        return 1;
                    }
                    int count = 0;
                    for (int col = 0; col < n; col++)
                    {
                        int ok = 1;
                        for (int i = 0; i < row; i++)
                        {
                            if (queens[i] == col || queens[i] - i == col - row || queens[i] + i == col + row)
                            {
                                ok = 0;
                                break;
                            }
                        }
                        if (ok == 1)
                        {
                            queens[row] = col;
                            count += place(queens, row + 1, n);
                        }
                    }
                    return count;
                }
            }
            NQB nqb = new NQB();
            long t0 = System.nanoTime();
            int solutions = nqb.solve(11);
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("nqueens(11) solutions = " + solutions + "  [" + dt / 1000000L + " ms]");
            int total = 0;
            t0 = System.nanoTime();
            for (int r = 0; r < 10; r++)
            {
                total += nqb.solve(9);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("nqueens(9) x10 = " + total + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== NQueens (Java) (end) ==========")
        BenchCollector.recordJava("NQueens", "n=11 单轮 + n=9 x10（块内 nanoTime us）", us)
    }

    # 9. Sieve：1e6 单轮（78498）+ 5e5 x5 轮（207690）
    static sieve()
    {
        Console.println("========== Sieve (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            int primes = 0;
            long t0 = System.nanoTime();
            int[] comp1 = new int[1000001];
            for (int i = 2; i <= 1000000; i++)
            {
                if (comp1[i] == 0)
                {
                    primes++;
                    if (i <= 1000000 / i)
                    {
                        int j = i * i;
                        while (j <= 1000000)
                        {
                            comp1[j] = 1;
                            j += i;
                        }
                    }
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("sieve 1e6 primes = " + primes + "  [" + dt / 1000000L + " ms]");
            int total = 0;
            t0 = System.nanoTime();
            for (int r = 0; r < 5; r++)
            {
                int[] comp2 = new int[500001];
                int cnt = 0;
                for (int i = 2; i <= 500000; i++)
                {
                    if (comp2[i] == 0)
                    {
                        cnt++;
                        if (i <= 500000 / i)
                        {
                            int j = i * i;
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
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("sieve 5e5 x5 = " + total + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== Sieve (Java) (end) ==========")
        BenchCollector.recordJava("Sieve", "1e6 单轮 + 5e5 x5（块内 nanoTime us）", us)
    }

    # 10. QuickSort：3e4 元素 x5 轮（LCG 数据生成不计时，逐轮计时累计）
    static quickSort()
    {
        Console.println("========== QuickSort (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            class QSB
            {
                void sort(long[] a, int lo, int hi)
                {
                    if (lo >= hi)
                    {
                        return;
                    }
                    int i = lo;
                    int j = hi;
                    long p = a[(lo + hi) / 2];
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
                            long tmp = a[i];
                            a[i] = a[j];
                            a[j] = tmp;
                            i++;
                            j--;
                        }
                    }
                    sort(a, lo, j);
                    sort(a, i, hi);
                }
            }
            QSB qsb = new QSB();
            int n = 30000;
            int rounds = 5;
            long[] arr = new long[n];
            long totalUs = 0L;
            long checksum = 0L;
            for (int r = 0; r < rounds; r++)
            {
                long seed = 42L + r;
                for (int i = 0; i < n; i++)
                {
                    seed = (seed * 16807) % 2147483647;
                    arr[i] = seed;
                }
                long t0 = System.nanoTime();
                qsb.sort(arr, 0, n - 1);
                totalUs += (System.nanoTime() - t0) / 1000L;
                for (int i = 0; i < n; i++)
                {
                    checksum += arr[i];
                    if (i > 0)
                    {
                        if (arr[i - 1] > arr[i])
                        {
                            System.out.println("SORTED CHECK FAILED at " + i);
                        }
                    }
                }
            }
            System.out.println("quicksort 3e4 x5  [" + totalUs + " us]  checksum = " + checksum);
            $us <- totalUs;
        }
        Console.println("========== QuickSort (Java) (end) ==========")
        BenchCollector.recordJava("QuickSort", "quicksort 3e4 x5（块内 nanoTime us）", us)
    }

    # 11. MatrixMul：100x100 x3 轮（填充不计时，Int64 校验和）
    static matrixMul()
    {
        Console.println("========== MatrixMul (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
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
            long t0 = System.nanoTime();
            for (int r = 0; r < rounds; r++)
            {
                for (int i = 0; i < n; i++)
                {
                    for (int j = 0; j < n; j++)
                    {
                        int sum = 0;
                        for (int k = 0; k < n; k++)
                        {
                            sum += a[i * n + k] * b[k * n + j];
                        }
                        c[i * n + j] = sum;
                    }
                }
            }
            long elapsed = (System.nanoTime() - t0) / 1000L;
            acc += elapsed;
            long checksum = 0L;
            for (int i = 0; i < n * n; i++)
            {
                checksum += c[i];
            }
            System.out.println("matmul 100x100 x3  [" + elapsed + " us]  checksum = " + checksum);
            $us <- acc;
        }
        Console.println("========== MatrixMul (Java) (end) ==========")
        BenchCollector.recordJava("MatrixMul", "matmul 100x100 x3（块内 nanoTime us）", us)
    }

    # 12. BinaryTree：depth12 x10 轮 + depth16 x2 轮（构建 + 求和）
    static binaryTree()
    {
        Console.println("========== BinaryTree (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            class BN
            {
                long value;
                BN left;
                BN right;
                BN(long v)
                {
                    value = v;
                }
            }
            class BTB
            {
                BN build(int depth, int value)
                {
                    if (depth <= 0)
                    {
                        return null;
                    }
                    BN node = new BN(value);
                    node.left = build(depth - 1, value * 2);
                    node.right = build(depth - 1, value * 2 + 1);
                    return node;
                }
                long checksum(BN node)
                {
                    if (node == null)
                    {
                        return 0L;
                    }
                    return node.value + checksum(node.left) + checksum(node.right);
                }
            }
            BTB btb = new BTB();
            long total = 0L;
            long t0 = System.nanoTime();
            for (int r = 0; r < 10; r++)
            {
                BN root = btb.build(12, r + 1);
                total += btb.checksum(root);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("tree depth12 x10 checksum = " + total + "  [" + dt / 1000000L + " ms]");
            long total2 = 0L;
            t0 = System.nanoTime();
            for (int r = 0; r < 2; r++)
            {
                BN root = btb.build(16, r + 1);
                total2 += btb.checksum(root);
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("tree depth16 x2 checksum = " + total2 + "  [" + dt / 1000000L + " ms]");
            $us <- acc / 1000L;
        }
        Console.println("========== BinaryTree (Java) (end) ==========")
        BenchCollector.recordJava("BinaryTree", "depth12 x10 + depth16 x2（块内 nanoTime us）", us)
    }

    # 13. Mandelbrot：240x180 x3 轮（iterSum/inside 跨轮累加）
    static mandelbrot()
    {
        Console.println("========== Mandelbrot (Java) (start) ==========")
        long us = 0L
        @java_hotspot()
        {
            long acc = 0L;
            long dt = 0L;
            int w = 240;
            int h = 180;
            int maxIter = 150;
            int rounds = 3;
            long iterSum = 0L;
            int insideCount = 0;
            long t0 = System.nanoTime();
            for (int r = 0; r < rounds; r++)
            {
                for (int py = 0; py < h; py++)
                {
                    double y0 = py * 4.0 / h - 2.0;
                    for (int px = 0; px < w; px++)
                    {
                        double x0 = px * 4.0 / w - 2.0;
                        double x = 0.0;
                        double y = 0.0;
                        int iter = 0;
                        while (iter < maxIter && x * x + y * y <= 4.0)
                        {
                            double xtemp = x * x - y * y + x0;
                            y = 2.0 * x * y + y0;
                            x = xtemp;
                            iter++;
                        }
                        iterSum += iter;
                        if (iter == maxIter)
                        {
                            insideCount++;
                        }
                    }
                }
            }
            dt = System.nanoTime() - t0;
            acc += dt;
            System.out.println("mandelbrot 240x180 x3  [" + dt / 1000000L + " ms]  iterSum = " + iterSum + "  inside = " + insideCount);
            $us <- acc / 1000L;
        }
        Console.println("========== Mandelbrot (Java) (end) ==========")
        BenchCollector.recordJava("Mandelbrot", "mandelbrot 240x180 x3（块内 nanoTime us）", us)
    }
}
