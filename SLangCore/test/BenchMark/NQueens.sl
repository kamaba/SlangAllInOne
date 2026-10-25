import Std

# NQueens - 传统 N 皇后基准：递归回溯 + 冲突检测 + 数组读写
# queens[i] = 第 i 行皇后所在列；同列/同对角线冲突即剪枝
NQueens
{
    static fun()
    {
        Console.println("========== NQueens (start) ==========")

        # 1. n=11 单轮（解数 2680）
        nowMs = Environment.sys.nowMillis()
        solutions = NQueens.solve(11)
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("nqueens(11) solutions = " + solutions.toString() + "  [$nowMs.toString() ms]")

        # 2. n=9 x10 轮（解数 352 x10 = 3520）
        nowMs = Environment.sys.nowMillis()
        total = 0
        for r = 0, r < 10, r++
        {
            total += NQueens.solve(9)
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("nqueens(9) x10 = " + total.toString() + "  [$nowMs.toString() ms]")

        Console.println("========== NQueens (end) ==========")
    }

    # 统计 n 皇后解数
    static int solve(int n)
    {
        Int32[] queens = Array<Int32>.create(n)
        ret NQueens.place(queens, 0, n)
    }

    # 在第 row 行逐列尝试放置，递归展开
    static int place(Int32[] queens, int row, int n)
    {
        if (row == n)
        {
            ret 1
        }
        count = 0
        for col = 0, col < n, col++
        {
            ok = 1
            for i = 0, i < row, i++
            {
                # 同列 / 主对角线 / 副对角线
                if (queens[i] == col || queens[i] - i == col - row || queens[i] + i == col + row)
                {
                    ok = 0
                    break
                }
            }
            if (ok == 1)
            {
                queens[row] = col
                count += NQueens.place(queens, row + 1, n)
            }
        }
        ret count
    }
}
