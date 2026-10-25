import Std

# MatrixMul - 矩阵乘法基准：三重循环 + 扁平数组（行主序）
# c = a * b，n x n 方阵，下标手工展开为 i*n+j
MatrixMul
{
    static fun()
    {
        Console.println("========== MatrixMul (start) ==========")

        n = 100
        rounds = 3
        Int32[] a = Array<Int32>.create(n * n)
        Int32[] b = Array<Int32>.create(n * n)
        Int32[] c = Array<Int32>.create(n * n)

        # 数据填充不计入计时
        for i = 0, i < n, i++
        {
            for j = 0, j < n, j++
            {
                a[i * n + j] = (i + j) % 100
                b[i * n + j] = (i * 7 + j * 3) % 100
            }
        }

        nowMs = Environment.sys.nowMillis()
        for r = 0, r < rounds, r++
        {
            MatrixMul.mul(a, b, c, n)
        }
        nowMs = Environment.sys.nowMillis() - nowMs

        # 校验和
        checksum = 0L
        for i = 0, i < n * n, i++
        {
            checksum += c[i]
        }
        Console.println("matmul 100x100 x3  [$nowMs.toString() ms]  checksum = " + checksum.toString())

        Console.println("========== MatrixMul (end) ==========")
    }

    # 朴素三重循环矩阵乘法
    static mul(Int32[] a, Int32[] b, Int32[] c, int n)
    {
        for i = 0, i < n, i++
        {
            for j = 0, j < n, j++
            {
                sum = 0
                for k = 0, k < n, k++
                {
                    sum += a[i * n + k] * b[k * n + j]
                }
                c[i * n + j] = sum
            }
        }
    }
}
