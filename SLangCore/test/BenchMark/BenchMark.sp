import Std

Project
{
    _main_()
    {
        Console.println("===== BenchMark _main_ start =====")

        # ── SL JIT / 非 JIT 双轮开关（启动传参 SL_JIT） ──
        # VM 既有开关：SL_JIT=0/false → 本轮非 JIT（VM 字节码解释执行），
        # SL 条目记入报告 SL-NoJIT 列；未设/SL_JIT=1 → JIT 轮（Release VM
        # 默认开），记入 SL 列。两轮各跑一次，报告经 report/entries_*.txt
        # sidecar 缓存互相合并，单份报告即有 SL 与 SL-NoJIT 双列对比。
        # 说明：--no-jit 仅 CLI 通道、SL 脚本不可感知，本基准统一用 SL_JIT；
        # PowerShell 非 JIT 轮：$env:SL_JIT = "0"（跑完 Remove-Item Env:SL_JIT）。
        string jitEnv = Environment.env.getValue("SL_JIT")
        if jitEnv == "0" || jitEnv == "false"
        {
            BenchCollector.setSlLanguage("SL-NoJIT")
            Console.println("[BenchMark] SL_JIT=" + jitEnv + " -> non-JIT round (VM interpreter), SL entries -> SL-NoJIT column")
        }
        else
        {
            Console.println("[BenchMark] JIT round (SL_JIT unset/1), SL entries -> SL column (set SL_JIT=0 for non-JIT round)")
        }

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
