import Std

# Sieve - 埃拉托斯特尼素数筛基准：数组标记 + 步进内层循环 + 整除判断
Sieve
{
    static fun()
    {
        Console.println("========== Sieve (start) ==========")

        # 1. 1e6 单轮（78498 个素数）
        nowMs = Environment.sys.nowMillis()
        primes = Sieve.countPrimes(1000000)
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("sieve 1e6 primes = " + primes.toString() + "  [$nowMs.toString() ms]")

        # 2. 5e5 x5 轮（每轮 41538，合计 207690）
        nowMs = Environment.sys.nowMillis()
        total = 0
        for r = 0, r < 5, r++
        {
            total += Sieve.countPrimes(500000)
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("sieve 5e5 x5 = " + total.toString() + "  [$nowMs.toString() ms]")

        Console.println("========== Sieve (end) ==========")
    }

    # 统计 [2, n] 内素数个数（isComposite 为 0 视为素数）
    static int countPrimes(int n)
    {
        Int32[] isComposite = Array<Int32>.create(n + 1)
        count = 0
        for i = 2, i <= n, i++
        {
            if (isComposite[i] == 0)
            {
                count++
                # i*i <= n 时才需要划掉合数（用 i <= n/i 判断避免 i*i 溢出）
                if (i <= n / i)
                {
                    j = i * i
                    while (j <= n)
                    {
                        isComposite[j] = 1
                        j += i
                    }
                }
            }
        }
        ret count
    }
}
