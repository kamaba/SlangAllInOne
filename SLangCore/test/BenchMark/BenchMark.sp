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

        # C/C++ 原生基准（cplus_clang 插件：C 惯用指针版 + C++ 惯用对象版，
        # 逐项同算法同规模对齐；编译产物 SLCpp.dll 共享部署位，运行前本工程
        # 须最后编译）
        CBench.fun()
        CppBench.fun()

        # Python 惯用基准（python_cpython 插件：块内 perf_counter_ns 计时
        # 经出通道 us 回传；pysrc 共享部署位，本工程须最后编译——同上）
        PythonBench.fun()

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
