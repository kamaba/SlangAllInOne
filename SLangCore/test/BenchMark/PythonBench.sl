import Std

# ============================================================================
# PythonBench — Python 惯用法基准（@python_cpython(){} 内联块，python_cpython
# 插件内嵌 CPython 解释执行）
#
# 13 项与 SL/C/C++/CSharp/Java/JS 共享基准逐项同算法/同参数（对齐 CppBench，
# 校验和可跨语言对拍）。惯用法：递归函数、list 推导、f-string、re 正则、
# bytearray、list.sort、class 树。
#
# 计时：块内 time.perf_counter_ns 纳秒，核心算法段耗时经出通道回传——
# ns 粒度超 int32 出通道上限（>2.1s 子项，Python 解释执行下普遍超限，
# 参照 C++ RegExpBench 先例）统一块内 //1000 折算 us 回传，SL 侧
# recordPython 直存 us（导入/装载开销在 run() 外不计入）。
#
# 块内代码约束：`<-` 序列禁用；不用 # 行注释（print 明细走 flush=True
# 立刷——CPython 嵌入态 stdout 为用户态缓冲，不 flush 进程退出即丢失，
# 与 C++ printf 经 CRT 退出刷盘不同）；''' 三引号禁用（SL 词法层块捕获
# 只认 """）；python 体纯空格缩进（块生成 dedent 后与 return 基线一致，
# 防 Tab/空格混用 TabError）。
#
# 共享部署位：块产物 Entry_N.py 部署 <插件>\package\windows\pysrc\（与
# SLCpp.dll / java classes 同款"后编译覆盖"约定）——运行 BenchMark 前须
# 最后编译本工程。
# ============================================================================

PythonBench
{
    static fun()
    {
        long us = PythonBench.fibonacci()
        BenchCollector.recordPython("Fibonacci", "fib(0..21) 递归求和（块内 ns→us）", us)

        us = PythonBench.eqBench()
        BenchCollector.recordPython("EqBench", "i32/i64/f64/bool 4 子项（块内 ns→us）", us)

        us = PythonBench.loopBench()
        BenchCollector.recordPython("Loop", "list 迭代求和 x3000/while 5e6/step 1e6 3 子项（块内 ns→us）", us)

        us = PythonBench.levenshtein()
        BenchCollector.recordPython("Levenshtein", "滚动列表 DP x5000（块内 ns→us）", us)

        us = PythonBench.dataTypes()
        BenchCollector.recordPython("DataTypes", "Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us）", us)

        us = PythonBench.stringBench()
        BenchCollector.recordPython("StringBench", "str 拼接/f-string 插值/format/比较 4 子项（块内 ns→us）", us)

        us = PythonBench.regExpBench()
        BenchCollector.recordPython("RegExpBench", "re 模块 8 子项（块内 ns→us）", us)

        us = PythonBench.nQueens()
        BenchCollector.recordPython("NQueens", "n=11 单轮 + n=9 x10（块内 ns→us）", us)

        us = PythonBench.sieve()
        BenchCollector.recordPython("Sieve", "bytearray 筛 1e6 单轮 + 5e5 x5（块内 ns→us）", us)

        us = PythonBench.quickSort()
        BenchCollector.recordPython("QuickSort", "list.sort 3e4 x5（块内 ns→us）", us)

        us = PythonBench.matrixMul()
        BenchCollector.recordPython("MatrixMul", "嵌套 list 矩阵乘 100x100 x3（块内 ns→us）", us)

        us = PythonBench.binaryTree()
        BenchCollector.recordPython("BinaryTree", "class 树递归 depth12 x10 + depth16 x2（块内 ns→us）", us)

        us = PythonBench.mandelbrot()
        BenchCollector.recordPython("Mandelbrot", "240x180 x3（块内 ns→us）", us)
    }

    # 1. Fibonacci：递归求和（sum = 17711，对齐 CppBench 校验和）
    static long fibonacci()
    {
        Console.println("========== Fibonacci (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            def fib(n):
                if n <= 1:
                    return n
                return fib(n - 1) + fib(n - 2)
            total = 0
            t0 = time.perf_counter_ns()
            for i in range(22):
                total += fib(i)
            t1 = time.perf_counter_ns()
            print("fib(0..21) sum =", total, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- (t1 - t0) // 1000;
        }
        Console.println("========== Fibonacci (Python) (end) ==========")
        ret us
    }

    # 2. EqBench：四种类型相等比较循环（对齐 CppBench 4 子项）
    static long eqBench()
    {
        Console.println("========== EqBench (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            acc = 0
            k = 0
            s = 0
            t0 = time.perf_counter_ns()
            while k != 2000000:
                s += k
                k += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("i32 != 2e6 =", s, "  [", (t1 - t0) // 1000, "us]", flush=True)
            k64 = 0
            s64 = 0
            t0 = time.perf_counter_ns()
            while k64 != 2000000:
                s64 += k64
                k64 += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("i64 != 2e6 =", s64, "  [", (t1 - t0) // 1000, "us]", flush=True)
            kd = 0.0
            sd = 0.0
            t0 = time.perf_counter_ns()
            while kd != 2000000.0:
                sd += kd
                kd += 1.0
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("f64 != 2e6 =", sd, "  [", (t1 - t0) // 1000, "us]", flush=True)
            cnt = 0
            t0 = time.perf_counter_ns()
            for i in range(1000000):
                if True:
                    cnt += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("bool == 1e6 =", cnt, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== EqBench (Python) (end) ==========")
        ret us
    }

    # 3. Loop：list 迭代求和 x3000 / while 5e6 / step 1e6 三段
    static long loopBench()
    {
        Console.println("========== Loop (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            n = 1000
            arr = [i * i for i in range(n)]
            acc = 0
            total = 0
            t0 = time.perf_counter_ns()
            for j in range(3000):
                s = 0
                for v in arr:
                    s += v
                total += s
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("iterator sum x3000 =", total, "  [", (t1 - t0) // 1000, "us]", flush=True)
            wsum = 0
            k = 0
            t0 = time.perf_counter_ns()
            while k < 5000000:
                wsum += k
                k += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("while sum 5e6 =", wsum, "  [", (t1 - t0) // 1000, "us]", flush=True)
            stepSum = 0
            t0 = time.perf_counter_ns()
            for i in range(0, 1000000, 7):
                stepSum += i
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("for step +7 1e6 =", stepSum, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== Loop (Python) (end) ==========")
        ret us
    }

    # 4. Levenshtein：两种行滚动 DP，先单次再 x5000
    static long levenshtein()
    {
        Console.println("========== Levenshtein (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            a = [10, 20, 30, 40, 50, 60]
            b = [10, 25, 30, 35, 40, 50, 65]
            m = 6
            n = 7
            prev = list(range(n + 1))
            curr = [0] * (n + 1)
            for i in range(1, m + 1):
                curr[0] = i
                for j in range(1, n + 1):
                    cost = 0 if a[i - 1] == b[j - 1] else 1
                    d1 = prev[j] + 1
                    d2 = curr[j - 1] + 1
                    d3 = prev[j - 1] + cost
                    curr[j] = min(d1, d2, d3)
                prev, curr = curr, prev
            print("levenshtein(a,b) =", prev[n], flush=True)
            total = 0
            t0 = time.perf_counter_ns()
            for r in range(5000):
                for j in range(n + 1):
                    prev[j] = j
                for i in range(1, m + 1):
                    curr[0] = i
                    for j in range(1, n + 1):
                        cost = 0 if a[i - 1] == b[j - 1] else 1
                        d1 = prev[j] + 1
                        d2 = curr[j - 1] + 1
                        d3 = prev[j - 1] + cost
                        curr[j] = min(d1, d2, d3)
                    prev, curr = curr, prev
                total += prev[n]
            t1 = time.perf_counter_ns()
            print("levenshtein x5000 =", total, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- (t1 - t0) // 1000;
        }
        Console.println("========== Levenshtein (Python) (end) ==========")
        ret us
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段（对齐 CppBench）
    static long dataTypes()
    {
        Console.println("========== DataTypes (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            acc = 0
            s32 = 0
            t0 = time.perf_counter_ns()
            for i in range(2000000):
                s32 += i
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("Int32 sum 2e6 =", s32, "  [", (t1 - t0) // 1000, "us]", flush=True)
            s64 = 0
            t0 = time.perf_counter_ns()
            for i in range(2000000):
                s64 += i
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("Int64 sum 2e6 =", s64, "  [", (t1 - t0) // 1000, "us]", flush=True)
            sf = 0.0
            t0 = time.perf_counter_ns()
            for i in range(2000000):
                sf += i * 1.5
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("Num sum 2e6 =", sf, "  [", (t1 - t0) // 1000, "us]", flush=True)
            mix = 0.0
            t0 = time.perf_counter_ns()
            for i in range(1000000):
                mix = mix + i / 3.0 + i % 7
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("Mixed ops 1e6 =", mix, "  [", (t1 - t0) // 1000, "us]", flush=True)
            count = 0
            t0 = time.perf_counter_ns()
            for i in range(1000000):
                if i % 3 == 0 and i % 5 == 0:
                    count += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("bool mod 1e6 =", count, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== DataTypes (Python) (end) ==========")
        ret us
    }

    # 6. StringBench：str 拼接 / f-string 插值 / format 格式化 / == 比较
    static long stringBench()
    {
        Console.println("========== StringBench (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            acc = 0
            s = ""
            t0 = time.perf_counter_ns()
            for i in range(10000):
                s = s + "ab"
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("concat 1e4 (str) =", len(s), "chars  [", (t1 - t0) // 1000, "us]", flush=True)
            t = ""
            t0 = time.perf_counter_ns()
            for i in range(10000):
                t = f"v={i} s={i * 2}"
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("interp 1e4 (f-string) =", t, "  [", (t1 - t0) // 1000, "us]", flush=True)
            u = ""
            t0 = time.perf_counter_ns()
            for i in range(10000):
                u = "{}-{}".format(i, i + 1)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("format 1e4 =", u, "  [", (t1 - t0) // 1000, "us]", flush=True)
            c = 0
            t0 = time.perf_counter_ns()
            for i in range(100000):
                if s == t:
                    c += 1
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("compare 1e5 count =", c, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== StringBench (Python) (end) ==========")
        ret us
    }

    # 7. RegExpBench：re 模块 8 子项（对齐 CppBench；文本构造不计时）
    static long regExpBench()
    {
        Console.println("========== RegExpBench (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import re
            import time
            chunk = "abc123 def456 ghi789 "
            text = chunk * 4000
            print("text bytes =", len(text), flush=True)
            acc = 0
            t0 = time.perf_counter_ns()
            for i in range(2000):
                rc = re.compile("([a-z]+)([0-9]+)")
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("compile x2000  [", (t1 - t0) // 1000, "us]", flush=True)
            rc1 = re.compile("def456")
            t0 = time.perf_counter_ns()
            for i in range(500):
                m = rc1.search(text)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("search hit x500  [", (t1 - t0) // 1000, "us]  value=", m.group(0), flush=True)
            rc2 = re.compile("zzz999")
            t0 = time.perf_counter_ns()
            for i in range(20):
                m = rc2.search(text)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("search miss x20  [", (t1 - t0) // 1000, "us]  miss=", m is None, flush=True)
            rc3 = re.compile("[a-z]+")
            t0 = time.perf_counter_ns()
            for i in range(5):
                words = len(rc3.findall(text))
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("matchAll x5  [", (t1 - t0) // 1000, "us]  count=", words, flush=True)
            rc4 = re.compile("[0-9]+")
            t0 = time.perf_counter_ns()
            for i in range(5):
                rep = rc4.sub("#", text)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("replace x5  [", (t1 - t0) // 1000, "us]  len=", len(rep), flush=True)
            rc5 = re.compile("([a-z]+)([0-9]+)")
            t0 = time.perf_counter_ns()
            for i in range(200):
                m5 = rc5.search(text)
                g1 = m5.group(1)
                g2 = m5.group(2)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("group search x200  [", (t1 - t0) // 1000, "us]  g1=", g1, "g2=", g2, flush=True)
            text2 = "abc abc def def " * 2000
            rc6 = re.compile(r"(\w+) \1")
            t0 = time.perf_counter_ns()
            for i in range(10):
                pairs = len(rc6.findall(text2))
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("backref matchAll x10  [", (t1 - t0) // 1000, "us]  count=", pairs, flush=True)
            text3 = "中文测试123 " * 2000
            rc7 = re.compile("测试[0-9]+")
            t0 = time.perf_counter_ns()
            for i in range(100):
                m7 = rc7.search(text3)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("utf8 search x100  [", (t1 - t0) // 1000, "us]  value=", m7.group(0), flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== RegExpBench (Python) (end) ==========")
        ret us
    }

    # 8. NQueens：递归回溯（n=11 单轮 + n=9 x10）
    static long nQueens()
    {
        Console.println("========== NQueens (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            def place(queens, row, n):
                if row == n:
                    return 1
                count = 0
                for col in range(n):
                    ok = 1
                    for i in range(row):
                        if queens[i] == col or queens[i] - i == col - row or queens[i] + i == col + row:
                            ok = 0
                            break
                    if ok == 1:
                        queens[row] = col
                        count += place(queens, row + 1, n)
                return count
            queens = [0] * 16
            acc = 0
            t0 = time.perf_counter_ns()
            solutions = place(queens, 0, 11)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("nqueens(11) solutions =", solutions, "  [", (t1 - t0) // 1000, "us]", flush=True)
            total = 0
            t0 = time.perf_counter_ns()
            for r in range(10):
                total += place(queens, 0, 9)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("nqueens(9) x10 =", total, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== NQueens (Python) (end) ==========")
        ret us
    }

    # 9. Sieve：bytearray 素数筛（1e6 单轮 78498 + 5e5 x5 207690）
    static long sieve()
    {
        Console.println("========== Sieve (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            acc = 0
            lim = 1000000
            comp = bytearray(lim + 1)
            t0 = time.perf_counter_ns()
            count = 0
            for i in range(2, lim + 1):
                if comp[i] == 0:
                    count += 1
                    if i <= lim // i:
                        j = i * i
                        while j <= lim:
                            comp[j] = 1
                            j += i
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("sieve 1e6 primes =", count, "  [", (t1 - t0) // 1000, "us]", flush=True)
            total = 0
            t0 = time.perf_counter_ns()
            for r in range(5):
                comp5 = bytearray(500001)
                for i in range(2, 500001):
                    if comp5[i] == 0:
                        total += 1
                        if i <= 500000 // i:
                            j = i * i
                            while j <= 500000:
                                comp5[j] = 1
                                j += i
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("sieve 5e5 x5 =", total, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== Sieve (Python) (end) ==========")
        ret us
    }

    # 10. QuickSort：list.sort（Timsort，3e4 x5，数据生成不计时）
    static long quickSort()
    {
        Console.println("========== QuickSort (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            n = 30000
            arr = [0] * n
            acc = 0
            checksum = 0
            for r in range(5):
                seed = 42 + r
                for i in range(n):
                    seed = (seed * 16807) % 2147483647
                    arr[i] = seed
                t0 = time.perf_counter_ns()
                arr.sort()
                t1 = time.perf_counter_ns()
                acc += t1 - t0
                for i in range(n):
                    checksum += arr[i]
                    if i > 0 and arr[i - 1] > arr[i]:
                        print("SORTED CHECK FAILED at", i, flush=True)
            print("list.sort 3e4 x5  [", acc // 1000, "us]  checksum =", checksum, flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== QuickSort (Python) (end) ==========")
        ret us
    }

    # 11. MatrixMul：嵌套 list 矩阵乘（每轮清零，checksum 与他语言对齐）
    static long matrixMul()
    {
        Console.println("========== MatrixMul (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            n = 100
            a = [[(i + j) % 100 for j in range(n)] for i in range(n)]
            b = [[(i * 7 + j * 3) % 100 for j in range(n)] for i in range(n)]
            t0 = time.perf_counter_ns()
            for r in range(3):
                c = [[0] * n for _ in range(n)]
                for i in range(n):
                    ci = c[i]
                    ai = a[i]
                    for k in range(n):
                        av = ai[k]
                        bk = b[k]
                        for j in range(n):
                            ci[j] += av * bk[j]
            t1 = time.perf_counter_ns()
            checksum = 0
            for i in range(n):
                for j in range(n):
                    checksum += c[i][j]
            print("matmul 100x100 x3  [", (t1 - t0) // 1000, "us]  checksum =", checksum, flush=True)
            $us <- (t1 - t0) // 1000;
        }
        Console.println("========== MatrixMul (Python) (end) ==========")
        ret us
    }

    # 12. BinaryTree：class 树递归（depth12 x10 + depth16 x2，Build 值语义对齐校验和）
    static long binaryTree()
    {
        Console.println("========== BinaryTree (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            class Node:
                def __init__(self, v):
                    self.l = None
                    self.r = None
                    self.v = v
            def build(depth, v):
                if depth <= 0:
                    return None
                node = Node(v)
                node.l = build(depth - 1, v * 2)
                node.r = build(depth - 1, v * 2 + 1)
                return node
            def tsum(n):
                if n is None:
                    return 0
                return n.v + tsum(n.l) + tsum(n.r)
            acc = 0
            t0 = time.perf_counter_ns()
            total12 = 0
            for r in range(10):
                root = build(12, r + 1)
                total12 += tsum(root)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("tree depth12 x10 recursive sum =", total12, "  [", (t1 - t0) // 1000, "us]", flush=True)
            t0 = time.perf_counter_ns()
            total16 = 0
            for r in range(2):
                root = build(16, r + 1)
                total16 += tsum(root)
            t1 = time.perf_counter_ns()
            acc += t1 - t0
            print("tree depth16 x2 recursive sum =", total16, "  [", (t1 - t0) // 1000, "us]", flush=True)
            $us <- acc // 1000;
        }
        Console.println("========== BinaryTree (Python) (end) ==========")
        ret us
    }

    # 13. Mandelbrot：标准映射（对齐 CppBench Render，240x180 x3）
    static long mandelbrot()
    {
        Console.println("========== Mandelbrot (Python) (start) ==========")
        long us = 0L
        @python_cpython()
        {
            import time
            w = 240
            h = 180
            maxIter = 150
            iterSum = 0
            inside = 0
            t0 = time.perf_counter_ns()
            for r in range(3):
                for py in range(h):
                    y0 = py * 4.0 / h - 2.0
                    for px in range(w):
                        x0 = px * 4.0 / w - 2.0
                        x = 0.0
                        y = 0.0
                        it = 0
                        while it < maxIter and x * x + y * y <= 4.0:
                            xt = x * x - y * y + x0
                            y = 2.0 * x * y + y0
                            x = xt
                            it += 1
                        iterSum += it
                        if it == maxIter:
                            inside += 1
            t1 = time.perf_counter_ns()
            print("mandelbrot 240x180 x3  [", (t1 - t0) // 1000, "us]  iterSum =", iterSum, " inside =", inside, flush=True)
            $us <- (t1 - t0) // 1000;
        }
        Console.println("========== Mandelbrot (Python) (end) ==========")
        ret us
    }
}
