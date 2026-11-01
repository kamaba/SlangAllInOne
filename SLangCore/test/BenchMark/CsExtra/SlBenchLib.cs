// ============================================================================
// CsExtra/SlBenchLib.cs — CSharpBench 的算法库（sources 合并编译进 SLAtSign.dll）
// 算法与 BenchMark 工程的 SL 版逐项对齐（相同迭代次数/运算序列），
// 供 @csharp_mono(){} 块内 using SlBench; 后调用。
// ============================================================================

using System;

namespace SlBench
{
    // 二叉树节点（对齐 BinaryTree.sl 的 BenchNode）
    public class BenchNode
    {
        public long Value;
        public BenchNode Left;
        public BenchNode Right;
        public BenchNode(long v) { Value = v; }
    }

    public static class Bench
    {
        // Fibonacci.sl：fib(0..21) 求和
        public static int Fib(int n)
        {
            return n <= 1 ? n : Fib(n - 1) + Fib(n - 2);
        }

        // Levenshtein.sl：编辑距离 DP（滚动两行）
        public static int Distance(int[] a, int[] b)
        {
            int m = a.Length;
            int n = b.Length;
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
                    curr[j] = Min3(del, ins, sub);
                }
                int[] tmp = prev;
                prev = curr;
                curr = tmp;
            }
            return prev[n];
        }

        private static int Min3(int x, int y, int z)
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

        // NQueens.sl：n 皇后解数（递归回溯）
        public static int Solve(int n)
        {
            int[] queens = new int[n];
            return Place(queens, 0, n);
        }

        private static int Place(int[] queens, int row, int n)
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
                    count += Place(queens, row + 1, n);
                }
            }
            return count;
        }

        // Sieve.sl：埃氏素数筛计数
        public static int CountPrimes(int n)
        {
            int[] isComposite = new int[n + 1];
            int count = 0;
            for (int i = 2; i <= n; i++)
            {
                if (isComposite[i] == 0)
                {
                    count++;
                    if (i <= n / i)
                    {
                        int j = i * i;
                        while (j <= n)
                        {
                            isComposite[j] = 1;
                            j += i;
                        }
                    }
                }
            }
            return count;
        }

        // QuickSort.sl：Hoare 分区快排（p 取中位元素）
        public static void Sort(long[] a, int lo, int hi)
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
            Sort(a, lo, j);
            Sort(a, i, hi);
        }

        // MatrixMul.sl：朴素三重循环矩阵乘（扁平数组行主序）
        public static void Mul(int[] a, int[] b, int[] c, int n)
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

        // BinaryTree.sl：满二叉树构建
        public static BenchNode Build(int depth, int value)
        {
            if (depth <= 0)
            {
                return null;
            }
            BenchNode node = new BenchNode(value);
            node.Left = Build(depth - 1, value * 2);
            node.Right = Build(depth - 1, value * 2 + 1);
            return node;
        }

        // BinaryTree.sl：全树求和
        public static long Checksum(BenchNode node)
        {
            if (node == null)
            {
                return 0L;
            }
            return node.Value + Checksum(node.Left) + Checksum(node.Right);
        }

        // Mandelbrot.sl：渲染一帧，返回迭代总数，insideCount 跨轮累加
        public static long Render(int w, int h, int maxIter, ref int insideCount)
        {
            long iterSum = 0;
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
            return iterSum;
        }
    }
}
