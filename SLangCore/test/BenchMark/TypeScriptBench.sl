import Std

# ============================================================================
# TypeScriptBench — TypeScript 版基准（@typescript_nodev8(){} 内联块，Node.js V8 引擎）
# 13 项基准与 SL/C#/Java/JS(QuickJS) 版逐项对齐：相同算法 / 迭代次数 /
# 运算序列 / 输出行格式。计时：块内 performance.now() 自身计时（亚毫秒
# 精度 ms 累计，出通道 ×1000 折 us 回传 SL 侧 recordTs——不含引擎调用/
# node 子进程拉起/部署开销，与 C/C++/Python 口径一致）。
# 引擎为外接 node.exe keep-alive 子进程（V8 JIT），与 QuickJS 解释执行对照；
# 块体为 TypeScript（形参带类型标注，Node >= 22.6 原生类型擦除，零 tsc）：
# 块体被包裹进 export async function run(...): Promise<void>（ESM .mts），
# 块内直接声明 function / let / interface 均可；输出走 console.log（stdout
# 通路，插件 console 包装转发）。
# 注意：SL 层禁用行内 # 注释（只整行使用）；块内禁 # 注释行（会原样进
# .mts 导致 Node 语法错误）；块内字符串禁字面 # 字符（replace 目标字符
# 写作 \x23）；块内勿写含 <- 的正则字面量（用 new RegExp("...") 形态）。
# ============================================================================

TypeScriptBench
{
    static fun()
    {
        # 各子项块内 performance.now 自身计时（出通道 ×1000 折 us 回传），方法内直接记录进 BenchCollector
        TypeScriptBench.fibonacci()
        TypeScriptBench.eqBench()
        TypeScriptBench.loopBench()
        TypeScriptBench.levenshtein()
        TypeScriptBench.dataTypes()
        TypeScriptBench.stringBench()
        TypeScriptBench.regExpBench()
        TypeScriptBench.nQueens()
        TypeScriptBench.sieve()
        TypeScriptBench.quickSort()
        TypeScriptBench.matrixMul()
        TypeScriptBench.binaryTree()
        TypeScriptBench.mandelbrot()
    }

    # 1. Fibonacci：fib(0..21) 递归求和（= 17711），TS 形参类型标注
    static fibonacci()
    {
        Console.println("========== Fibonacci (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            function fib(n: number): number
            {
                return n <= 1 ? n : fib(n - 1) + fib(n - 2);
            }
            let t0: number = performance.now();
            let sum: number = 0;
            for (let i: number = 0; i < 22; i++)
            {
                sum += fib(i);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("fib(0..21) sum = " + sum + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== Fibonacci (TS/V8) (end) ==========")
        BenchCollector.recordTs("Fibonacci", "fib(0..21) 递归求和（块内 performance.now us）", us)
    }

    # 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool）
    static eqBench()
    {
        Console.println("========== EqBench (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let k: number = 0;
            let s: number = 0;
            let t0: number = performance.now();
            while (k !== 2000000)
            {
                s += k;
                k++;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("i32 != 2e6 = " + s + "  [" + dt.toFixed(3) + " ms]");
            let k64: number = 0;
            let s64: number = 0;
            t0 = performance.now();
            while (k64 !== 2000000)
            {
                s64 += k64;
                k64++;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("i64 != 2e6 = " + s64 + "  [" + dt.toFixed(3) + " ms]");
            let kd: number = 0.0;
            let sd: number = 0.0;
            t0 = performance.now();
            while (kd !== 2000000.0)
            {
                sd += kd;
                kd += 1.0;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("f64 != 2e6 = " + sd + "  [" + dt.toFixed(3) + " ms]");
            let b: boolean = true;
            let cnt: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 1000000; i++)
            {
                if (b === true)
                {
                    cnt++;
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("bool == 1e6 = " + cnt + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== EqBench (TS/V8) (end) ==========")
        BenchCollector.recordTs("EqBench", "4子项（块内 performance.now us）", us)
    }

    # 3. Loop：数组求和 / while / 步进 for 三段
    static loopBench()
    {
        Console.println("========== Loop (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let n: number = 1000;
            let arr: number[] = new Array(n);
            for (let i: number = 0; i < n; i++)
            {
                arr[i] = i * i;
            }
            let total: number = 0;
            let t0: number = performance.now();
            for (let j: number = 0; j < 3000; j++)
            {
                let s: number = 0;
                for (let i: number = 0; i < n; i++)
                {
                    s += arr[i];
                }
                total += s;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("array sum x3000 = " + total + "  [" + dt.toFixed(3) + " ms]");
            let wsum: number = 0;
            let k: number = 0;
            t0 = performance.now();
            while (k < 5000000)
            {
                wsum += k;
                k++;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("while sum 5e6 = " + wsum + "  [" + dt.toFixed(3) + " ms]");
            let stepSum: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 1000000; i += 7)
            {
                stepSum += i;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("for step +7 1e6 = " + stepSum + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== Loop (TS/V8) (end) ==========")
        BenchCollector.recordTs("Loop", "3子项（块内 performance.now us）", us)
    }

    # 4. Levenshtein：编辑距离 DP（a,b 固定序列，先单次再 x5000）
    static levenshtein()
    {
        Console.println("========== Levenshtein (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            function distance(a: number[], b: number[]): number
            {
                let m: number = a.length;
                let n: number = b.length;
                let prev: number[] = new Array(n + 1);
                let curr: number[] = new Array(n + 1);
                for (let j: number = 0; j <= n; j++)
                {
                    prev[j] = j;
                }
                for (let i: number = 1; i <= m; i++)
                {
                    curr[0] = i;
                    for (let j: number = 1; j <= n; j++)
                    {
                        let cost: number = a[i - 1] === b[j - 1] ? 0 : 1;
                        curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
                    }
                    let tmp: number[] = prev;
                    prev = curr;
                    curr = tmp;
                }
                return prev[n];
            }
            let a: number[] = [10, 20, 30, 40, 50, 60];
            let b: number[] = [10, 25, 30, 35, 40, 50, 65];
            let dist: number = distance(a, b);
            console.log("levenshtein(a,b) = " + dist);
            let total: number = 0;
            let t0: number = performance.now();
            for (let r: number = 0; r < 5000; r++)
            {
                total += distance(a, b);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("levenshtein x5000 = " + total + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== Levenshtein (TS/V8) (end) ==========")
        BenchCollector.recordTs("Levenshtein", "levenshtein x5000（块内 performance.now us）", us)
    }

    # 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段
    static dataTypes()
    {
        Console.println("========== DataTypes (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let s32: number = 0;
            let t0: number = performance.now();
            for (let i: number = 0; i < 2000000; i++)
            {
                s32 += i;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("Int32 sum 2e6 = " + s32 + "  [" + dt.toFixed(3) + " ms]");
            let s64: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 2000000; i++)
            {
                s64 += i;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("Int64 sum 2e6 = " + s64 + "  [" + dt.toFixed(3) + " ms]");
            let sf: number = 0.0;
            t0 = performance.now();
            for (let i: number = 0; i < 2000000; i++)
            {
                sf += i * 1.5;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("Num sum 2e6 = " + sf + "  [" + dt.toFixed(3) + " ms]");
            let mix: number = 0.0;
            t0 = performance.now();
            for (let i: number = 0; i < 1000000; i++)
            {
                mix = mix + i / 3.0 + i % 7;
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("Mixed ops 1e6 = " + mix + "  [" + dt.toFixed(3) + " ms]");
            let count: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 1000000; i++)
            {
                if (i % 3 === 0 && i % 5 === 0)
                {
                    count++;
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("bool mod 1e6 = " + count + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== DataTypes (TS/V8) (end) ==========")
        BenchCollector.recordTs("DataTypes", "5子项（块内 performance.now us）", us)
    }

    # 6. StringBench：拼接 / 插值构建 / format / 比较 / 结尾校验
    static stringBench()
    {
        Console.println("========== StringBench (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let s: string = "";
            let t0: number = performance.now();
            for (let i: number = 0; i < 10000; i++)
            {
                s = s + "ab";
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("concat 1e4  [" + dt.toFixed(3) + " ms]");
            let t: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 10000; i++)
            {
                t = "v=" + i + " s=" + (i * 2);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("interp 1e4  [" + dt.toFixed(3) + " ms]");
            let u: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 10000; i++)
            {
                u = i + "-" + (i + 1);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("format 1e4  [" + dt.toFixed(3) + " ms]");
            let c: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 100000; i++)
            {
                if (s === t)
                {
                    c++;
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("compare 1e5  count=" + c + "  [" + dt.toFixed(3) + " ms]");
            console.log("concat endswith ab = " + (s.endsWith("ab") && u === u));
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== StringBench (TS/V8) (end) ==========")
        BenchCollector.recordTs("StringBench", "4子项（块内 performance.now us）", us)
    }

    # 7. RegExpBench：编译 / 早命中 / 不命中 / matchAll / replace / 分组 /
    #    backref / UTF-8 中文 共 8 项（文本构建不计时）
    static regExpBench()
    {
        Console.println("========== RegExpBench (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let chunk: string = "abc123 def456 ghi789 ";
            let text: string = "";
            for (let i: number = 0; i < 4000; i++)
            {
                text = text + chunk;
            }
            console.log("text bytes = " + text.length);
            let t0: number = performance.now();
            for (let i: number = 0; i < 2000; i++)
            {
                new RegExp("([a-z]+)([0-9]+)");
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("compile x2000  [" + dt.toFixed(3) + " ms]");
            let re1: RegExp = new RegExp("def456");
            let hit: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 500; i++)
            {
                let m1: RegExpExecArray | null = re1.exec(text);
                hit = m1 !== null ? m1[0] : "";
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("search hit x500  [" + dt.toFixed(3) + " ms]  value=" + hit);
            let re2: RegExp = new RegExp("zzz999");
            let miss: boolean = true;
            t0 = performance.now();
            for (let i: number = 0; i < 20; i++)
            {
                miss = !re2.test(text);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("search miss x20  [" + dt.toFixed(3) + " ms]  miss=" + miss);
            let re3: RegExp = new RegExp("[a-z]+", "g");
            let words: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 5; i++)
            {
                words = 0;
                re3.lastIndex = 0;
                let m3: RegExpExecArray | null;
                while ((m3 = re3.exec(text)) !== null)
                {
                    words++;
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("matchAll x5  [" + dt.toFixed(3) + " ms]  count=" + words);
            let re4: RegExp = new RegExp("[0-9]+", "g");
            let rep: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 5; i++)
            {
                rep = text.replace(re4, "\x23");
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("replace x5  [" + dt.toFixed(3) + " ms]  len=" + rep.length);
            let re5: RegExp = new RegExp("([a-z]+)([0-9]+)");
            let g1: string = "";
            let g2: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 200; i++)
            {
                let m5: RegExpExecArray | null = re5.exec(text);
                if (m5 !== null)
                {
                    g1 = m5[1];
                    g2 = m5[2];
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("group search x200  [" + dt.toFixed(3) + " ms]  g1=" + g1 + " g2=" + g2);
            let chunk2: string = "abc abc def def ";
            let text2: string = "";
            for (let i: number = 0; i < 2000; i++)
            {
                text2 = text2 + chunk2;
            }
            let re6: RegExp = new RegExp("(\\w+) \\1", "g");
            let pairs: number = 0;
            t0 = performance.now();
            for (let i: number = 0; i < 10; i++)
            {
                pairs = 0;
                re6.lastIndex = 0;
                let m6: RegExpExecArray | null;
                while ((m6 = re6.exec(text2)) !== null)
                {
                    pairs++;
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("backref matchAll x10  [" + dt.toFixed(3) + " ms]  count=" + pairs);
            let chunk3: string = "中文测试123 ";
            let text3: string = "";
            for (let i: number = 0; i < 2000; i++)
            {
                text3 = text3 + chunk3;
            }
            let re7: RegExp = new RegExp("测试[0-9]+");
            let zh: string = "";
            t0 = performance.now();
            for (let i: number = 0; i < 100; i++)
            {
                let m7: RegExpExecArray | null = re7.exec(text3);
                zh = m7 !== null ? m7[0] : "";
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("utf8 search x100  [" + dt.toFixed(3) + " ms]  value=" + zh);
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== RegExpBench (TS/V8) (end) ==========")
        BenchCollector.recordTs("RegExpBench", "8子项（块内 performance.now us）", us)
    }

    # 8. NQueens：n=11 单轮（2680）+ n=9 x10 轮（3520）
    static nQueens()
    {
        Console.println("========== NQueens (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            function place(queens: number[], row: number, n: number): number
            {
                if (row === n)
                {
                    return 1;
                }
                let count: number = 0;
                for (let col: number = 0; col < n; col++)
                {
                    let ok: number = 1;
                    for (let i: number = 0; i < row; i++)
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
            function solve(n: number): number
            {
                let queens: number[] = new Array(n);
                return place(queens, 0, n);
            }
            let t0: number = performance.now();
            let solutions: number = solve(11);
            dt = performance.now() - t0;
            acc += dt;
            console.log("nqueens(11) solutions = " + solutions + "  [" + dt.toFixed(3) + " ms]");
            let total: number = 0;
            t0 = performance.now();
            for (let r: number = 0; r < 10; r++)
            {
                total += solve(9);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("nqueens(9) x10 = " + total + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== NQueens (TS/V8) (end) ==========")
        BenchCollector.recordTs("NQueens", "n=11 单轮 + n=9 x10（块内 performance.now us）", us)
    }

    # 9. Sieve：1e6 单轮（78498）+ 5e5 x5 轮（207690）
    static sieve()
    {
        Console.println("========== Sieve (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let primes: number = 0;
            let t0: number = performance.now();
            let comp1: number[] = new Array(1000001).fill(0);
            for (let i: number = 2; i <= 1000000; i++)
            {
                if (comp1[i] === 0)
                {
                    primes++;
                    if (i <= 1000000 / i)
                    {
                        let j: number = i * i;
                        while (j <= 1000000)
                        {
                            comp1[j] = 1;
                            j += i;
                        }
                    }
                }
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("sieve 1e6 primes = " + primes + "  [" + dt.toFixed(3) + " ms]");
            let total: number = 0;
            t0 = performance.now();
            for (let r: number = 0; r < 5; r++)
            {
                let comp2: number[] = new Array(500001).fill(0);
                let cnt: number = 0;
                for (let i: number = 2; i <= 500000; i++)
                {
                    if (comp2[i] === 0)
                    {
                        cnt++;
                        if (i <= 500000 / i)
                        {
                            let j: number = i * i;
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
            dt = performance.now() - t0;
            acc += dt;
            console.log("sieve 5e5 x5 = " + total + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== Sieve (TS/V8) (end) ==========")
        BenchCollector.recordTs("Sieve", "1e6 单轮 + 5e5 x5（块内 performance.now us）", us)
    }

    # 10. QuickSort：3e4 元素 x5 轮（LCG 数据生成不计时，逐轮计时累计）
    static quickSort()
    {
        Console.println("========== QuickSort (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            function sort(a: number[], lo: number, hi: number): void
            {
                if (lo >= hi)
                {
                    return;
                }
                let i: number = lo;
                let j: number = hi;
                let p: number = a[(lo + hi) / 2 | 0];
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
                        let tmp: number = a[i];
                        a[i] = a[j];
                        a[j] = tmp;
                        i++;
                        j--;
                    }
                }
                sort(a, lo, j);
                sort(a, i, hi);
            }
            let n: number = 30000;
            let rounds: number = 5;
            let arr: number[] = new Array(n);
            let checksum: number = 0;
            for (let r: number = 0; r < rounds; r++)
            {
                let seed: number = 42 + r;
                for (let i: number = 0; i < n; i++)
                {
                    seed = (seed * 16807) % 2147483647;
                    arr[i] = seed;
                }
                let t0: number = performance.now();
                sort(arr, 0, n - 1);
                acc += performance.now() - t0;
                for (let i: number = 0; i < n; i++)
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
            console.log("quicksort 3e4 x5  [" + acc.toFixed(3) + " ms]  checksum = " + checksum);
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== QuickSort (TS/V8) (end) ==========")
        BenchCollector.recordTs("QuickSort", "quicksort 3e4 x5（块内 performance.now us）", us)
    }

    # 11. MatrixMul：100x100 x3 轮（填充不计时，校验和）
    static matrixMul()
    {
        Console.println("========== MatrixMul (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let n: number = 100;
            let rounds: number = 3;
            let a: number[] = new Array(n * n).fill(0);
            let b: number[] = new Array(n * n).fill(0);
            let c: number[] = new Array(n * n).fill(0);
            for (let i: number = 0; i < n; i++)
            {
                for (let j: number = 0; j < n; j++)
                {
                    a[i * n + j] = (i + j) % 100;
                    b[i * n + j] = (i * 7 + j * 3) % 100;
                }
            }
            let t0: number = performance.now();
            for (let r: number = 0; r < rounds; r++)
            {
                for (let i: number = 0; i < n; i++)
                {
                    for (let j: number = 0; j < n; j++)
                    {
                        let sum: number = 0;
                        for (let k: number = 0; k < n; k++)
                        {
                            sum += a[i * n + k] * b[k * n + j];
                        }
                        c[i * n + j] = sum;
                    }
                }
            }
            let elapsed: number = performance.now() - t0;
            acc += elapsed;
            let checksum: number = 0;
            for (let i: number = 0; i < n * n; i++)
            {
                checksum += c[i];
            }
            console.log("matmul 100x100 x3  [" + elapsed + " ms]  checksum = " + checksum);
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== MatrixMul (TS/V8) (end) ==========")
        BenchCollector.recordTs("MatrixMul", "matmul 100x100 x3（块内 performance.now us）", us)
    }

    # 12. BinaryTree：depth12 x10 轮 + depth16 x2 轮（构建 + 求和）
    static binaryTree()
    {
        Console.println("========== BinaryTree (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            interface TreeNode { value: number; left: TreeNode | null; right: TreeNode | null }
            function build(depth: number, value: number): TreeNode | null
            {
                if (depth <= 0)
                {
                    return null;
                }
                let node: TreeNode = { value: value, left: null, right: null };
                node.left = build(depth - 1, value * 2);
                node.right = build(depth - 1, value * 2 + 1);
                return node;
            }
            function checksum(node: TreeNode | null): number
            {
                if (node === null)
                {
                    return 0;
                }
                return node.value + checksum(node.left) + checksum(node.right);
            }
            let total: number = 0;
            let t0: number = performance.now();
            for (let r: number = 0; r < 10; r++)
            {
                let root: TreeNode | null = build(12, r + 1);
                total += checksum(root);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("tree depth12 x10 checksum = " + total + "  [" + dt.toFixed(3) + " ms]");
            let total2: number = 0;
            t0 = performance.now();
            for (let r: number = 0; r < 2; r++)
            {
                let root: TreeNode | null = build(16, r + 1);
                total2 += checksum(root);
            }
            dt = performance.now() - t0;
            acc += dt;
            console.log("tree depth16 x2 checksum = " + total2 + "  [" + dt.toFixed(3) + " ms]");
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== BinaryTree (TS/V8) (end) ==========")
        BenchCollector.recordTs("BinaryTree", "depth12 x10 + depth16 x2（块内 performance.now us）", us)
    }

    # 13. Mandelbrot：240x180 x3 轮（iterSum/inside 跨轮累加）
    static mandelbrot()
    {
        Console.println("========== Mandelbrot (TS/V8) (start) ==========")
        long us = 0L
        @typescript_nodev8()
        {
            let acc: number = 0;
            let dt: number = 0;
            let w: number = 240;
            let h: number = 180;
            let maxIter: number = 150;
            let rounds: number = 3;
            let iterSum: number = 0;
            let insideCount: number = 0;
            let t0: number = performance.now();
            for (let r: number = 0; r < rounds; r++)
            {
                for (let py: number = 0; py < h; py++)
                {
                    let y0: number = py * 4.0 / h - 2.0;
                    for (let px: number = 0; px < w; px++)
                    {
                        let x0: number = px * 4.0 / w - 2.0;
                        let x: number = 0.0;
                        let y: number = 0.0;
                        let iter: number = 0;
                        while (iter < maxIter && x * x + y * y <= 4.0)
                        {
                            let xtemp: number = x * x - y * y + x0;
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
            dt = performance.now() - t0;
            acc += dt;
            console.log("mandelbrot 240x180 x3  [" + dt.toFixed(3) + " ms]  iterSum = " + iterSum + "  inside = " + insideCount);
            $us <- Math.round(acc * 1000);
        }
        Console.println("========== Mandelbrot (TS/V8) (end) ==========")
        BenchCollector.recordTs("Mandelbrot", "mandelbrot 240x180 x3（块内 performance.now us）", us)
    }
}
