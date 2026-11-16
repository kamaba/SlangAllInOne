import Std

Loop
{
    static fun()
    {
        Console.println("========== Loop (start) ==========")

        # 1. 双层 for + 数组读写
        n = 1000
        Int32[] arr = Array<Int32>.create(n)
        for i = 0, i < n, i++
        {
            arr[i] = i * i
        }
        nowMs = Environment.sys.nowMillis()
        total = 0L
        for j = 0, j < 3000, j++
        {
            s = 0L
            for i = 0, i < n, i++
            {
                s += arr[i]
            }
            total += s
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("array sum x3000 = " + total.toString() + "  [$nowMs.toString() ms]")
        BenchCollector.recordSL("Loop", "array sum x3000", nowMs)

        # 2. while 循环
        nowMs = Environment.sys.nowMillis()
        wsum = 0L
        k = 0
        while (k < 5000000)
        {
            wsum += k
            k++
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("while sum 5e6 = " + wsum.toString() + "  [$nowMs.toString() ms]")
        BenchCollector.recordSL("Loop", "while sum 5e6", nowMs)

        # 3. for 步进
        nowMs = Environment.sys.nowMillis()
        stepSum = 0L
        for i = 0, i < 1000000, i += 7
        {
            stepSum += i
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("for step +7 1e6 = " + stepSum.toString() + "  [$nowMs.toString() ms]")
        BenchCollector.recordSL("Loop", "for step +7 1e6", nowMs)

        # 4. 普通 for 对照段（与 #5 同规模、同循环体，用来隔离 for-in 的迭代开销）
        nowMs = Environment.sys.nowMillis()
        cforSum = 0L
        for i = 0, i < 1000000, i++
        {
            cforSum += i
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("for sum 1e6 = " + cforSum.toString() + "  [$nowMs.toString() ms]")
        BenchCollector.recordSL("Loop", "for sum 1e6", nowMs)

        # 5. for-in range 迭代段（问题.txt #2 快速迭代基线）
        nowMs = Environment.sys.nowMillis()
        inSum = 0L
        for fi in range(1000000)
        {
            inSum += fi
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("for-in range sum 1e6 = " + inSum.toString() + "  [$nowMs.toString() ms]")
        BenchCollector.recordSL("Loop", "for-in range sum 1e6", nowMs)

        # 6. for-in range 边界语义哨兵（不计时）：负步长与零步长两条分支
        #    range(10,0,-3) => 10,7,4,1；range(5,5,0) => 不进入循环体
        downSum = 0L
        downCnt = 0
        for d in range(10, 0, -3)
        {
            downSum += d
            downCnt++
        }
        Console.println("for-in range down = " + downSum.toString() + "/" + downCnt.toString())
        zeroCnt = 0
        for z in range(5, 5, 0)
        {
            zeroCnt++
        }
        Console.println("for-in range zero-step count = " + zeroCnt.toString())

        Console.println("========== Loop (end) ==========")
    }
}
