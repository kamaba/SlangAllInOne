import Std

Project
{
    _main_()
    {
        Console.println("===== BenchMark _main_ start =====")
        nowMs = Environment.sys.nowMillis()

        #HelloWorld.fun()
        Fibonacci.fun()
        EqBench.fun()
        Loop.fun()
        Levenshtein.fun()
        DataTypes.fun()
        StringBench.fun()
        RegExpBench.fun()

        NQueens.fun()
        Sieve.fun()
        QuickSort.fun()
        MatrixMul.fun()
        BinaryTreeBench.fun()
        Mandelbrot.fun()

        CSharpBench.fun()
        JavaBench.fun()
        JsBench.fun()

        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("===== BenchMark _main_ end [$nowMs.toString() ms] =====")

        # 汇总采集数据，生成 .md 对比报告（以时间戳命名，写入工作目录）
        BenchCollector.generateReport()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
