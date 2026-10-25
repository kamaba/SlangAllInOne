import Std

# QuickSort - 快速排序基准：递归分区 + Hoare 双向扫描 + 交换
# 数据用 Park-Miller LCG（Int64 运算）生成，SL 与 Python 两侧数据完全一致
QuickSort
{
    static fun()
    {
        Console.println("========== QuickSort (start) ==========")

        n = 30000
        rounds = 5
        Int64[] arr = Array<Int64>.create(n)

        # 每轮：LCG 重新生成数据（不计入计时）→ 计时排序 → 累计
        totalMs = 0L
        checksum = 0L
        for r = 0, r < rounds, r++
        {
            seed = 42L + r
            for i = 0, i < n, i++
            {
                seed = (seed * 16807) % 2147483647
                arr[i] = seed
            }
            t0 = Environment.sys.nowMillis()
            QuickSort.sort(arr, 0, n - 1)
            totalMs += Environment.sys.nowMillis() - t0
            # 排序结果校验：求和 + 有序性
            for i = 0, i < n, i++
            {
                checksum += arr[i]
                if (i > 0)
                {
                    if (arr[i - 1] > arr[i])
                    {
                        Console.println("SORTED CHECK FAILED at " + i.toString())
                    }
                }
            }
        }
        Console.println("quicksort 3e4 x5  [" + totalMs.toString() + " ms]  checksum = " + checksum.toString())

        Console.println("========== QuickSort (end) ==========")
    }

    # Hoare 分区快排，p 取中位元素（[lo, hi] 闭区间）
    static sort(Int64[] a, int lo, int hi)
    {
        if (lo >= hi)
        {
            ret
        }
        i = lo
        j = hi
        p = a[(lo + hi) / 2]
        while (i <= j)
        {
            while (a[i] < p)
            {
                i++
            }
            while (a[j] > p)
            {
                j--
            }
            if (i <= j)
            {
                tmp = a[i]
                a[i] = a[j]
                a[j] = tmp
                i++
                j--
            }
        }
        QuickSort.sort(a, lo, j)
        QuickSort.sort(a, i, hi)
    }
}
