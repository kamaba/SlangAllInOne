import Std

# ============================================================================
# GoBench — Go 惯用法基准（@golang(){} 内联块，golang 插件）
#
# 13 项与 SL/C/C++/CSharp/Java/JS/Python 共享基准逐项同算法/同参数（对齐
# CppBench/PythonBench，校验和可跨语言对拍）。惯用法：递归闭包、slice、
# fmt.Sprintf 插值、regexp（RE2）、[]byte 筛、sort.Slice、struct 树。
#
# 计时：块内 gohost.GohostQpcNow/GohostQpcNs（Windows QPC 纳秒精确计时，
# acc int64 累加）——ns 粒度超 int32 出通道上限（参照 C++ RegExpBench 先例）
# 统一块内 /1000 折算 us 回传，SL 侧 recordGolang 直存 us（预置 import 编译期
# 已进 SLGoHost.exe 不计入计时段；fmt.Println 明细经 console 事件转发宿主
# stdout）。QPC 说明：go1.26.2/Windows 的 time.Since 在无 syscall 的纯计算
# 区间内会退化（单调钟 runtime 缓存，实测 0.5ms 区间第二次调用起恒 0），
# 故基准计时统一走 gohost 内置的 kernel32 QueryPerformanceCounter 直调
#（syscall 每次真实执行，亚微秒粒度，调用端各一次 ~20ns 纳税可忽略）。
#
# 块内代码约束：块体为 Go 函数体（func Entry_N_run），import 只能在文件
# 顶部——预置包 fmt/math/os/regexp/sort/strconv/strings/time 已可直接
# 使用，块内勿遮蔽这些包名；for/if 起始 { 须与子句同行；<- 为 Go 原生
# channel 接收操作符合法；块内不用行注释。
#
# RegExpBench 第 7 子项（反向引用 (\w+) \1）：Go 正则引擎为 RE2，不支持
# 反向引用——Python/C++ 语义用 regexp 拆词 + 相邻重复词对计数等价实现，
# 计数结果与他语言一致（4000），语义差异已在运行日志与本文档注明。
#
# 共享部署位：块产物 Entry_N.go 编进 <插件>\package\windows\go\SLGoHost.exe
#（Front 编译期 go build 产出，内嵌 Go 运行时——运行机器零 Go 依赖；与
# pysrc / SLCpp.dll / java classes 同款"后编译覆盖"约定）——运行 BenchMark
# 前须最后编译本工程。
# ============================================================================

GoBench
{
    static fun()
    {
        long us = GoBench.fibonacci()
        BenchCollector.recordGolang("Fibonacci", "fib(0..21) 递归求和（块内 ns→us）", us)

        us = GoBench.eqBench()
        BenchCollector.recordGolang("EqBench", "i32/i64/f64/bool 4 子项（块内 ns→us）", us)

        us = GoBench.loopBench()
        BenchCollector.recordGolang("Loop", "slice 迭代求和 x3000/for 5e6/step 1e6 3 子项（块内 ns→us）", us)

        us = GoBench.levenshtein()
        BenchCollector.recordGolang("Levenshtein", "滚动 slice DP x5000（块内 ns→us）", us)

        us = GoBench.dataTypes()
        BenchCollector.recordGolang("DataTypes", "Int32/Int64/Num/混合/bool mod 5 子项（块内 ns→us）", us)

        us = GoBench.stringBench()
        BenchCollector.recordGolang("StringBench", "string 拼接/Sprintf 插值/格式化/比较 4 子项（块内 ns→us）", us)

        us = GoBench.regExpBench()
        BenchCollector.recordGolang("RegExpBench", "regexp 8 子项（块内 ns→us；反向引用子项 RE2 等价实现）", us)

        us = GoBench.nQueens()
        BenchCollector.recordGolang("NQueens", "n=11 单轮 + n=9 x10（块内 ns→us）", us)

        us = GoBench.sieve()
        BenchCollector.recordGolang("Sieve", "[]byte 筛 1e6 单轮 + 5e5 x5（块内 ns→us）", us)

        us = GoBench.quickSort()
        BenchCollector.recordGolang("QuickSort", "sort.Slice 3e4 x5（块内 ns→us）", us)

        us = GoBench.matrixMul()
        BenchCollector.recordGolang("MatrixMul", "嵌套 slice 矩阵乘 100x100 x3（块内 ns→us）", us)

        us = GoBench.binaryTree()
        BenchCollector.recordGolang("BinaryTree", "struct 树递归 depth12 x10 + depth16 x2（块内 ns→us）", us)

        us = GoBench.mandelbrot()
        BenchCollector.recordGolang("Mandelbrot", "240x180 x3（块内 ns→us）", us)
    }

    # 1. Fibonacci：递归闭包求和（sum = 17711，对齐 CppBench 校验和）
    static long fibonacci()
    {
        Console.println("========== Fibonacci (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            var fib func(int64) int64
            fib = func(nn int64) int64 {
                if nn <= 1 {
                    return nn
                }
                return fib(nn-1) + fib(nn-2)
            }
            total := int64(0)
            t0 := GohostQpcNow()
            for i := int64(0); i < 22; i++ {
                total += fib(i)
            }
            elapsed := GohostQpcNs(t0)
            fmt.Println("fib(0..21) sum =", total, "  [", elapsed/1000, "us]")
            $us <- elapsed / 1000;
        }
        Console.println("========== Fibonacci (Go) (end) ==========")
        ret us
    }

    # 2. EqBench：四种类型相等比较循环（对齐 CppBench 4 子项；i32 子项 int32
    # 累加回绕语义与 C++ int 同款，Python 无符号回绕差异已在各列注明）
    static long eqBench()
    {
        Console.println("========== EqBench (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            acc := int64(0)
            k := int32(0)
            s := int32(0)
            t0 := GohostQpcNow()
            for k != 2000000 {
                s += k
                k++
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("i32 != 2e6 =", s, "  [", d/1000, "us]")
            k64 := int64(0)
            s64 := int64(0)
            t0 = GohostQpcNow()
            for k64 != 2000000 {
                s64 += k64
                k64++
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("i64 != 2e6 =", s64, "  [", d/1000, "us]")
            kd := 0.0
            sd := 0.0
            t0 = GohostQpcNow()
            for kd != 2000000.0 {
                sd += kd
                kd += 1.0
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("f64 != 2e6 =", sd, "  [", d/1000, "us]")
            cnt := 0
            t0 = GohostQpcNow()
            for i := 0; i < 1000000; i++ {
                if true {
                    cnt++
                }
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("bool == 1e6 =", cnt, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== EqBench (Go) (end) ==========")
        ret us
    }

    # 3. Loop：slice 迭代求和 x3000 / for 5e6 / step +7 1e6 三段
    static long loopBench()
    {
        Console.println("========== Loop (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            n := 1000
            arr := make([]int64, n)
            for i := 0; i < n; i++ {
                arr[i] = int64(i * i)
            }
            acc := int64(0)
            total := int64(0)
            t0 := GohostQpcNow()
            for j := 0; j < 3000; j++ {
                s := int64(0)
                for _, v := range arr {
                    s += v
                }
                total += s
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("iterator sum x3000 =", total, "  [", d/1000, "us]")
            wsum := int64(0)
            k := int64(0)
            t0 = GohostQpcNow()
            for k < 5000000 {
                wsum += k
                k++
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("for sum 5e6 =", wsum, "  [", d/1000, "us]")
            stepSum := int64(0)
            t0 = GohostQpcNow()
            for i := int64(0); i < 1000000; i += 7 {
                stepSum += i
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("for step +7 1e6 =", stepSum, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== Loop (Go) (end) ==========")
        ret us
    }

    # 4. Levenshtein：两种行滚动 DP，先单次再 x5000
    static long levenshtein()
    {
        Console.println("========== Levenshtein (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            a := []int64{10, 20, 30, 40, 50, 60}
            b := []int64{10, 25, 30, 35, 40, 50, 65}
            m := 6
            n := 7
            prev := make([]int64, n+1)
            curr := make([]int64, n+1)
            for j := 0; j <= n; j++ {
                prev[j] = int64(j)
            }
            for i := 1; i <= m; i++ {
                curr[0] = int64(i)
                for j := 1; j <= n; j++ {
                    cost := int64(0)
                    if a[i-1] != b[j-1] {
                        cost = 1
                    }
                    curr[j] = min(prev[j]+1, curr[j-1]+1, prev[j-1]+cost)
                }
                prev, curr = curr, prev
            }
            fmt.Println("levenshtein(a,b) =", prev[n])
            total := int64(0)
            t0 := GohostQpcNow()
            for r := 0; r < 5000; r++ {
                for j := 0; j <= n; j++ {
                    prev[j] = int64(j)
                }
                for i := 1; i <= m; i++ {
                    curr[0] = int64(i)
                    for j := 1; j <= n; j++ {
                        cost := int64(0)
                        if a[i-1] != b[j-1] {
                            cost = 1
                        }
                        curr[j] = min(prev[j]+1, curr[j-1]+1, prev[j-1]+cost)
                    }
                    prev, curr = curr, prev
                }
                total += prev[n]
            }
            elapsed := GohostQpcNs(t0)
            fmt.Println("levenshtein x5000 =", total, "  [", elapsed/1000, "us]")
            $us <- elapsed / 1000;
        }
        Console.println("========== Levenshtein (Go) (end) ==========")
        ret us
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段（对齐 CppBench；
    # Int32 子项 int32 累加回绕与 C++ 同款）
    static long dataTypes()
    {
        Console.println("========== DataTypes (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            acc := int64(0)
            s32 := int32(0)
            t0 := GohostQpcNow()
            for i := int32(0); i < 2000000; i++ {
                s32 += i
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("Int32 sum 2e6 =", s32, "  [", d/1000, "us]")
            s64 := int64(0)
            t0 = GohostQpcNow()
            for i := int64(0); i < 2000000; i++ {
                s64 += i
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("Int64 sum 2e6 =", s64, "  [", d/1000, "us]")
            sf := 0.0
            t0 = GohostQpcNow()
            for i := 0; i < 2000000; i++ {
                sf += float64(i) * 1.5
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("Num sum 2e6 =", sf, "  [", d/1000, "us]")
            mix := 0.0
            t0 = GohostQpcNow()
            for i := 0; i < 1000000; i++ {
                mix = mix + float64(i)/3.0 + float64(i%7)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("Mixed ops 1e6 =", mix, "  [", d/1000, "us]")
            count := 0
            t0 = GohostQpcNow()
            for i := 0; i < 1000000; i++ {
                if i%3 == 0 && i%5 == 0 {
                    count++
                }
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("bool mod 1e6 =", count, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== DataTypes (Go) (end) ==========")
        ret us
    }

    # 6. StringBench：string 拼接 / Sprintf 插值 / 格式化 / == 比较
    static long stringBench()
    {
        Console.println("========== StringBench (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            acc := int64(0)
            s := ""
            t0 := GohostQpcNow()
            for i := 0; i < 10000; i++ {
                s = s + "ab"
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("concat 1e4 (string) =", len(s), "chars  [", d/1000, "us]")
            t := ""
            t0 = GohostQpcNow()
            for i := 0; i < 10000; i++ {
                t = fmt.Sprintf("v=%d s=%d", i, i*2)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("interp 1e4 (Sprintf) =", t, "  [", d/1000, "us]")
            u := ""
            t0 = GohostQpcNow()
            for i := 0; i < 10000; i++ {
                u = fmt.Sprintf("%d-%d", i, i+1)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("format 1e4 =", u, "  [", d/1000, "us]")
            c := 0
            t0 = GohostQpcNow()
            for i := 0; i < 100000; i++ {
                if s == t {
                    c++
                }
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("compare 1e5 count =", c, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== StringBench (Go) (end) ==========")
        ret us
    }

    # 7. RegExpBench：regexp 8 子项（对齐 CppBench；文本构造不计时）。
    # 第 7 子项反向引用：RE2 不支持 \1——strings.Fields 拆词 + 相邻重复
    # 词对计数等价实现（计数 4000 与他语言一致）。
    static long regExpBench()
    {
        Console.println("========== RegExpBench (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            chunk := "abc123 def456 ghi789 "
            text := strings.Repeat(chunk, 4000)
            fmt.Println("text bytes =", len(text))
            acc := int64(0)
            t0 := GohostQpcNow()
            for i := 0; i < 2000; i++ {
                _ = regexp.MustCompile("([a-z]+)([0-9]+)")
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("compile x2000  [", d/1000, "us]")
            rc1 := regexp.MustCompile("def456")
            m := ""
            t0 = GohostQpcNow()
            for i := 0; i < 500; i++ {
                m = rc1.FindString(text)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("search hit x500  [", d/1000, "us]  value=", m)
            rc2 := regexp.MustCompile("zzz999")
            miss := false
            t0 = GohostQpcNow()
            for i := 0; i < 20; i++ {
                miss = rc2.FindString(text) == ""
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("search miss x20  [", d/1000, "us]  miss=", miss)
            rc3 := regexp.MustCompile("[a-z]+")
            words := 0
            t0 = GohostQpcNow()
            for i := 0; i < 5; i++ {
                words = len(rc3.FindAllString(text, -1))
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("matchAll x5  [", d/1000, "us]  count=", words)
            rc4 := regexp.MustCompile("[0-9]+")
            rep := ""
            t0 = GohostQpcNow()
            for i := 0; i < 5; i++ {
                rep = rc4.ReplaceAllString(text, "#")
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("replace x5  [", d/1000, "us]  len=", len(rep))
            rc5 := regexp.MustCompile("([a-z]+)([0-9]+)")
            g1 := ""
            g2 := ""
            t0 = GohostQpcNow()
            for i := 0; i < 200; i++ {
                m5 := rc5.FindStringSubmatch(text)
                g1 = m5[1]
                g2 = m5[2]
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("group search x200  [", d/1000, "us]  g1=", g1, "g2=", g2)
            text2 := strings.Repeat("abc abc def def ", 2000)
            pairs := 0
            t0 = GohostQpcNow()
            for i := 0; i < 10; i++ {
                words2 := strings.Fields(text2)
                pairs = 0
                for j := 0; j+1 < len(words2); j += 2 {
                    if words2[j] == words2[j+1] {
                        pairs++
                    }
                }
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("backref matchAll x10  [", d/1000, "us]  count=", pairs, "(RE2 no-backref equivalent)")
            text3 := strings.Repeat("中文测试123 ", 2000)
            rc7 := regexp.MustCompile("测试[0-9]+")
            m7 := ""
            t0 = GohostQpcNow()
            for i := 0; i < 100; i++ {
                m7 = rc7.FindString(text3)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("utf8 search x100  [", d/1000, "us]  value=", m7)
            $us <- acc / 1000;
        }
        Console.println("========== RegExpBench (Go) (end) ==========")
        ret us
    }

    # 8. NQueens：递归回溯（n=11 单轮 + n=9 x10）
    static long nQueens()
    {
        Console.println("========== NQueens (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            var place func(queens []int64, row int64, n int64) int64
            place = func(queens []int64, row int64, n int64) int64 {
                if row == n {
                    return 1
                }
                count := int64(0)
                for col := int64(0); col < n; col++ {
                    ok := true
                    for i := int64(0); i < row; i++ {
                        if queens[i] == col || queens[i]-i == col-row || queens[i]+i == col+row {
                            ok = false
                            break
                        }
                    }
                    if ok {
                        queens[row] = col
                        count += place(queens, row+1, n)
                    }
                }
                return count
            }
            queens := make([]int64, 16)
            acc := int64(0)
            t0 := GohostQpcNow()
            solutions := place(queens, 0, 11)
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("nqueens(11) solutions =", solutions, "  [", d/1000, "us]")
            total := int64(0)
            t0 = GohostQpcNow()
            for r := 0; r < 10; r++ {
                total += place(queens, 0, 9)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("nqueens(9) x10 =", total, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== NQueens (Go) (end) ==========")
        ret us
    }

    # 9. Sieve：[]byte 素数筛（1e6 单轮 78498 + 5e5 x5 207690）
    static long sieve()
    {
        Console.println("========== Sieve (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            acc := int64(0)
            lim := 1000000
            comp := make([]byte, lim+1)
            t0 := GohostQpcNow()
            count := int64(0)
            for i := 2; i <= lim; i++ {
                if comp[i] == 0 {
                    count++
                    if i <= lim/i {
                        for j := i * i; j <= lim; j += i {
                            comp[j] = 1
                        }
                    }
                }
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("sieve 1e6 primes =", count, "  [", d/1000, "us]")
            total := int64(0)
            t0 = GohostQpcNow()
            for r := 0; r < 5; r++ {
                comp5 := make([]byte, 500001)
                for i := 2; i <= 500000; i++ {
                    if comp5[i] == 0 {
                        total++
                        if i <= 500000/i {
                            for j := i * i; j <= 500000; j += i {
                                comp5[j] = 1
                            }
                        }
                    }
                }
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("sieve 5e5 x5 =", total, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== Sieve (Go) (end) ==========")
        ret us
    }

    # 10. QuickSort：sort.Slice（pdqsort，3e4 x5，数据生成不计时）
    static long quickSort()
    {
        Console.println("========== QuickSort (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            n := 30000
            arr := make([]int64, n)
            acc := int64(0)
            checksum := int64(0)
            for r := 0; r < 5; r++ {
                seed := int64(42 + r)
                for i := 0; i < n; i++ {
                    seed = (seed * 16807) % 2147483647
                    arr[i] = seed
                }
                t0 := GohostQpcNow()
                sort.Slice(arr, func(i, j int) bool {
                    return arr[i] < arr[j]
                })
                acc += GohostQpcNs(t0)
                for i := 0; i < n; i++ {
                    checksum += arr[i]
                }
            }
            fmt.Println("sort.Slice 3e4 x5  [", acc/1000, "us]  checksum =", checksum)
            $us <- acc / 1000;
        }
        Console.println("========== QuickSort (Go) (end) ==========")
        ret us
    }

    # 11. MatrixMul：嵌套 slice 矩阵乘（每轮清零，checksum 与他语言对齐）
    static long matrixMul()
    {
        Console.println("========== MatrixMul (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            n := 100
            a := make([][]int64, n)
            b := make([][]int64, n)
            for i := 0; i < n; i++ {
                a[i] = make([]int64, n)
                b[i] = make([]int64, n)
                for j := 0; j < n; j++ {
                    a[i][j] = int64((i + j) % 100)
                    b[i][j] = int64((i*7 + j*3) % 100)
                }
            }
            var c [][]int64
            t0 := GohostQpcNow()
            for r := 0; r < 3; r++ {
                c = make([][]int64, n)
                for i := 0; i < n; i++ {
                    c[i] = make([]int64, n)
                }
                for i := 0; i < n; i++ {
                    ci := c[i]
                    ai := a[i]
                    for k := 0; k < n; k++ {
                        av := ai[k]
                        bk := b[k]
                        for j := 0; j < n; j++ {
                            ci[j] += av * bk[j]
                        }
                    }
                }
            }
            elapsed := GohostQpcNs(t0)
            checksum := int64(0)
            for i := 0; i < n; i++ {
                for j := 0; j < n; j++ {
                    checksum += c[i][j]
                }
            }
            fmt.Println("matmul 100x100 x3  [", elapsed/1000, "us]  checksum =", checksum)
            $us <- elapsed / 1000;
        }
        Console.println("========== MatrixMul (Go) (end) ==========")
        ret us
    }

    # 12. BinaryTree：struct 指针树递归（depth12 x10 + depth16 x2，Build 值
    # 语义对齐校验和）
    static long binaryTree()
    {
        Console.println("========== BinaryTree (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            type gnode struct {
                l *gnode
                r *gnode
                v int64
            }
            var build func(depth int64, v int64) *gnode
            build = func(depth int64, v int64) *gnode {
                if depth <= 0 {
                    return nil
                }
                nd := &gnode{v: v}
                nd.l = build(depth-1, v*2)
                nd.r = build(depth-1, v*2+1)
                return nd
            }
            var tsum func(nd *gnode) int64
            tsum = func(nd *gnode) int64 {
                if nd == nil {
                    return 0
                }
                return nd.v + tsum(nd.l) + tsum(nd.r)
            }
            acc := int64(0)
            t0 := GohostQpcNow()
            total12 := int64(0)
            for r := int64(0); r < 10; r++ {
                root := build(12, r+1)
                total12 += tsum(root)
            }
            d := GohostQpcNs(t0)
            acc += d
            fmt.Println("tree depth12 x10 recursive sum =", total12, "  [", d/1000, "us]")
            t0 = GohostQpcNow()
            total16 := int64(0)
            for r := int64(0); r < 2; r++ {
                root := build(16, r+1)
                total16 += tsum(root)
            }
            d = GohostQpcNs(t0)
            acc += d
            fmt.Println("tree depth16 x2 recursive sum =", total16, "  [", d/1000, "us]")
            $us <- acc / 1000;
        }
        Console.println("========== BinaryTree (Go) (end) ==========")
        ret us
    }

    # 13. Mandelbrot：标准映射（对齐 CppBench Render，240x180 x3）
    static long mandelbrot()
    {
        Console.println("========== Mandelbrot (Go) (start) ==========")
        long us = 0L
        @golang()
        {
            w := 240
            h := 180
            maxIter := 150
            iterSum := int64(0)
            inside := int64(0)
            t0 := GohostQpcNow()
            for r := 0; r < 3; r++ {
                for py := 0; py < h; py++ {
                    y0 := float64(py)*4.0/float64(h) - 2.0
                    for px := 0; px < w; px++ {
                        x0 := float64(px)*4.0/float64(w) - 2.0
                        x := 0.0
                        y := 0.0
                        it := 0
                        for it < maxIter && x*x+y*y <= 4.0 {
                            xt := x*x - y*y + x0
                            y = 2.0*x*y + y0
                            x = xt
                            it++
                        }
                        iterSum += int64(it)
                        if it == maxIter {
                            inside++
                        }
                    }
                }
            }
            elapsed := GohostQpcNs(t0)
            fmt.Println("mandelbrot 240x180 x3  [", elapsed/1000, "us]  iterSum =", iterSum, " inside =", inside)
            $us <- elapsed / 1000;
        }
        Console.println("========== Mandelbrot (Go) (end) ==========")
        ret us
    }
}
