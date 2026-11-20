import Std

Project
{
    _main_()
    {
        Console.println("===== BenchMark _main_ start =====")
        nowMs = Environment.sys.nowMillis()

        HelloWorld.fun()
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

        # TypeScript 基准（typescript_nodev8 插件：外接 node.exe V8 JIT，与
        # QuickJS 解释执行对照；scripts\ 共享部署位，本工程须最后编译）
        TypeScriptBench.fun()

        # C/C++ 原生基准（cplus_clang 插件：C 惯用指针版 + C++ 惯用对象版，
        # 逐项同算法同规模对齐；编译产物 SLCpp.dll 共享部署位，运行前本工程
        # 须最后编译）
        CBench.fun()
        CppBench.fun()

        # x86-64 MASM 汇编基准（masm_x64 插件：Loop/EqBench/Fibonacci 三项
        # 共享基准同口径跨语言对拍 + SimdAVX2 专列；块内 QPC ns 计时经出
        # 通道回传。编译产物 SLMasm.dll 共享部署位，运行前本工程须最后编译）
        MasmBench.fun()

        # Python 惯用基准（python_cpython 插件：块内 perf_counter_ns 计时
        # 经出通道 us 回传；pysrc 共享部署位，本工程须最后编译——同上）
        PythonBench.fun()

        # PHP 惯用基准（php_embed 插件：统计值 SL 侧 nowMillis 整块计时——php
        # 出通道回传在 AOT 发布包失效兜底，参照 MasmBench；phpsrc 共享部署位，
        # 本工程须最后编译——同上。vendored php8ts.dll 随包齐备，无需本机另装 PHP）
        PhpBench.fun()

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
