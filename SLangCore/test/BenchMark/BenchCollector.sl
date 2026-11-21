import Std

# ============================================================================
# BenchCollector.sl -- benchmark 数据采集 + Markdown 对比报告生成
#
# 数据模型：
#   data BenchEntry -- 单条计时记录（语言类型 / 语言使用说明 / 优化选项 /
#                      测试类型 / 测试参数 / 运行时间 us）
#   BenchCollector  -- 静态 List<BenchEntry> 采集器：九个语言的 record
#                      便捷入口（SL 原生逐段计时；其余语言均为块内自身
#                      计时经出通道回传，不含引擎装载/编译部署开销）。
#
# 报告生成：
#   BenchCollector.generateReport() 在 BenchMark.sp 结尾调用一次：
#   按（测试类型, 测试参数）归并四语言横向对比表 + 全量原始条目表，
#   以 OS.DateTime.now() 拼时间戳文件名 BenchmarkReport_yyyyMMdd_HHmmss.md，
#   经 File.writeAllText 写入进程工作目录（相对路径）。
#
# 实现注意：data 类型经 for-in + as 转型在运行时得到 null（MetaCore
# 仅提示不阻断），因此遍历统一用 List._getItem_(i) 索引访问（元素静态
# 类型即 BenchEntry，免 as）。
# ============================================================================

# 单条基准数据条目
data BenchEntry
{
    language = ""
    languageDesc = ""
    optDesc = ""
    testType = ""
    testParam = ""
    timeUs = 0L
}

BenchCollector
{
    # 采集列表（懒初始化：静态字段无 new 初始化先例，首次 record 时创建）
    static List<BenchEntry> _entries = null

    # SL 系列语言标签（JIT 轮 = "SL"；非 JIT 轮 = "SL-NoJIT"）。
    # 由 BenchMark._main_ 启动时按 VM 传参 SL_JIT 判定后 setSlLanguage 注入，
    # recordSL 按此标签落列——一份报告经 sidecar 缓存合并即可同时呈现
    # JIT / 非 JIT 两列对比（见 saveSlSidecar / mergeOtherSlSidecar）。
    static string _slLang = null

    # 当前 SL 系语言标签（懒兜底 "SL"：静态 string 字段初始化器不可依赖）
    static string slLang()
    {
        if BenchCollector._slLang == null
        {
            ret "SL"
        }
        ret BenchCollector._slLang
    }

    # 注入本轮 SL 系语言标签（BenchMark._main_ 启动传参判定后调用）
    static setSlLanguage( string lang )
    {
        BenchCollector._slLang = lang
    }

    # ---------- 统一采集入口（时间存储单位一律 us） ----------
    # 存储单位用微秒而非纳秒：SL 侧整块计时为毫秒（×1000 换算），若 ×1e6
    # 换 ns，超 2147ms 的 SL 大项（NQueens/Mandelbrot 等）会在 Int32×字面量
    # 乘法里按 32 位语义溢出成负值（实测 -2147483648ns）。C/C++ 的 ns 精确
    # 值在 recordC/recordCpp 入口 /1000 折算（亚微秒项在报表显示为 0us，
    # 块内 printf 细节输出保留原始 ns）。

    static record( string language, string languageDesc, string optDesc, string testType, string testParam, long timeUs )
    {
        if BenchCollector._entries == null
        {
            BenchCollector._entries = List<BenchEntry>()
        }
        BenchEntry e = BenchEntry()
        e.language = language
        e.languageDesc = languageDesc
        e.optDesc = optDesc
        e.testType = testType
        e.testParam = testParam
        e.timeUs = timeUs
        BenchCollector._entries.add( e )
    }

    # ---------- 各语言便捷入口 ----------
    # SL：参数为毫秒（SL 侧 nowMillis 计时粒度所限），内部 ×1000 换 us；
    # CSharp/Java/JS/TS：参数为块内自身计时回传的微秒（Stopwatch /
    # nanoTime / Date.now / performance.now，经出通道回传，不含引擎
    # 装载/编译部署开销）直存；C/C++：参数为块内 QPC/steady_clock 纳秒
    # 精确值（经出通道回传），入口 /1000 折算 us。

    # SL：参数为毫秒（SL 侧 nowMillis 计时粒度所限），内部 ×1000 换 us。
    # 语言标签取 slLang()：JIT 轮落 "SL" 列、非 JIT 轮（SL_JIT=0）落
    # "SL-NoJIT" 列，双轮数据经 sidecar 合并进同一份报告对比。
    static recordSL( string testType, string testParam, long timeMs )
    {
        string opt = "VM JIT 默认开启（--no-jit 关闭）"
        if BenchCollector.slLang() == "SL-NoJIT"
        {
            opt = "VM 字节码解释执行，JIT 关闭（启动传参 SL_JIT=0）"
        }
        BenchCollector.record( BenchCollector.slLang(), "SLang 自研语言，SL VM 字节码执行", opt, testType, testParam, timeMs * 1000L )
    }

    static recordCSharp( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "CSharp", "C# / mono 运行时（csharp_mono 插件内嵌）", "Mono JIT 默认优化，块内 Stopwatch us 计时", testType, testParam, timeUs )
    }

    static recordJava( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "Java", "Java 17 / Hotspot 运行时（java_hotspot 插件内嵌）", "HotSpot 分层 JIT，块内 nanoTime us 计时", testType, testParam, timeUs )
    }

    static recordJs( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "JavaScript", "JavaScript / QuickJS 2024-01-13（javascript_quickjs 插件内嵌）", "QuickJS 解释器（无 JIT），块内 Date.now ms 计时（×1000 存 us）", testType, testParam, timeUs )
    }

    # TypeScript（语言列 JavaScriptV8，与 QuickJS 对照）：与 recordCSharp 同口径
    # （块内 us 直存）。引擎为 Node.js V8（typescript_nodev8 插件外接 node.exe
    # keep-alive 子进程，TypeScript 原生类型擦除执行）——V8 有 JIT，块内
    # performance.now 亚毫秒精度计时，与 QuickJS 解释执行形成对照。
    static recordTs( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "TypeScript", "TypeScript / Node.js V8（typescript_nodev8 插件外接 node.exe 子进程）", "V8 JIT 默认优化，TS 原生类型擦除，块内 performance.now us 计时", testType, testParam, timeUs )
    }

    # Python：参数为微秒（CPython 块内 perf_counter_ns 纳秒精确计时——ns 粒度
    # 超 int32 出通道上限（>2.1s 子项在解释执行下普遍超限，参照 C++
    # RegExpBench 先例），块内统一 //1000 折算 us 回传；模块导入在 run() 外
    # 不计入，与 C/C++ 块内 ns 口径同为"净算法耗时"）。
    static recordPython( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "Python", "Python / CPython 3.14 内嵌（python_cpython 插件）", "CPython 字节码解释器（无 JIT），块内 perf_counter_ns 计时（us 回传）", testType, testParam, timeUs )
    }

    # PHP：参数为微秒（2026-11-20 修订：php 出通道 $us <- (...) 回传在 AOT
    # 发布包（BenchMark.exe）实测失效——块内 echo 正常、毒化 long 回传致报告
    # PHP 列全空；源码树 slang.exe 运行正常。参照 MasmBench asm 出通道失效
    # 先例，统计值改用 SL 侧 nowMillis 整块计时兜底（ms×1000 存 us，含块
    # trampoline 调用开销）；块内 hrtime(true) printf 原始 us 见运行日志）。
    static recordPhp( string testType, string testParam, long timeUs )
    {
        BenchCollector.record( "PHP", "PHP 8.4 / embed SAPI 内嵌（php_embed 插件，vendored php8ts.dll TS x64）", "PHP Zend 字节码解释器（无 JIT），SL 侧 nowMillis 整块计时（php 出通道回传在 AOT 发布包失效兜底，块内 hrtime 原始 us 见运行日志）", testType, testParam, timeUs )
    }

    static recordC( string testType, string testParam, long timeNs )
    {
        BenchCollector.record( "C", "C 惯用法（@cplus_clang 块，malloc/裸指针/函数指针）", "MSVC cl /O2 原生编译，块内 ns 精确计时（cplus_clang 插件）", testType, testParam, timeNs / 1000L )
    }

    static recordCpp( string testType, string testParam, long timeNs )
    {
        BenchCollector.record( "C++", "C++ 惯用法（@cplus_clang 块，对象/STL/RAII）", "MSVC cl /O2 原生编译，块内 ns 精确计时（cplus_clang 插件）", testType, testParam, timeNs / 1000L )
    }

    # ASM（x86-64 MASM）：参数为 SL 侧 nowMillis 包住整个 masm 块调用的耗时
    #（纳秒，SL ms×1e6）——asm 出通道 $ns<-rax 回传本机实测拿到 0（报告 ASM 列
    # 空），按约定改用 SL 计时。入口 /1000 折算 us；块内 QPC printf 原始 ns
    # 仍见运行日志（精确算法耗时参考）。含 trampoline 调用开销，口径略异于
    # C/C++ 净算法耗时。
    static recordMasm( string testType, string testParam, long timeNs )
    {
        BenchCollector.record( "ASM", "x86-64 MASM 汇编（@masm_x64 块，手写指令）", "ml64 原生汇编（含 AVX2 SIMD 专列），SL 侧 nowMillis 整块计时（asm 出通道回传失效兜底）", testType, testParam, timeNs / 1000L )
    }

    # ---------- 报告生成 ----------

    static generateReport()
    {
        if BenchCollector._entries == null || BenchCollector._entries.length == 0
        {
            Console.println( "[BenchCollector] no entries collected, skip report" )
            ret
        }

        # SL 双轮 sidecar：先落本轮 SL 系条目缓存（供另一轮次运行合并），
        # 再合并另一轮次的缓存条目（JIT 轮合入 SL-NoJIT，反之亦然）
        BenchCollector.saveSlSidecar()
        BenchCollector.mergeOtherSlSidecar()

        var dt = OS.DateTime.now()
        string stamp = BenchCollector.pad2( dt.year ) + BenchCollector.pad2( dt.month ) + BenchCollector.pad2( dt.day )
        stamp = stamp + "_" + BenchCollector.pad2( dt.hour ) + BenchCollector.pad2( dt.minute ) + BenchCollector.pad2( dt.second )
        string fileName = "BenchmarkReport_" + stamp + ".md"
        # 报告统一存入 report 子目录（先建目录：File.writeAllText 底层 fopen 不自动建父目录）
        # 不用 IO.Path.combine：params 可变参数数组跨模块传递为 null，实测返回空串
        if !IO.Directory.exists( "report" )
        {
            IO.Directory.createDirectory( "report" )
        }
        fileName = "report/" + fileName

        string md = BenchCollector.buildReport( dt )
        bool ok = File.writeAllText( fileName, md )
        if ok
        {
            Console.println( "[BenchCollector] report written: " + fileName + "  (" + BenchCollector._entries.length.toString() + " entries)" )
        }
        else
        {
            Console.println( "[BenchCollector] report write FAILED: " + fileName )
        }
    }

    # 报告正文：标题 + 语言说明表 + 四语言对比总表 + 全量原始条目附录
    static string buildReport( OS.DateTime dt )
    {
        string nl = "\n"
        string md = "# SLang 多语言 Benchmark 对比报告" + nl + nl
        md = md + "- 生成时间: " + dt.year.toString() + "-" + BenchCollector.pad2( dt.month ) + "-" + BenchCollector.pad2( dt.day )
        md = md + " " + BenchCollector.pad2( dt.hour ) + ":" + BenchCollector.pad2( dt.minute ) + ":" + BenchCollector.pad2( dt.second ) + nl
        md = md + "- 数据条目: " + BenchCollector._entries.length.toString() + " 条" + nl
        md = md + "- 计时口径: 时间存储单位一律微秒；SL 为 SL 侧 nowMillis 毫秒计时（×1000 存 us）；C/C++/CSharp/Java/JS/TS/Python 为块内自身计时经出通道回传（不含引擎装载/编译部署开销）——C/C++ QPC/steady_clock ns（/1000 存 us，原始 ns 见运行日志）、CSharp Stopwatch（us）、Java System.nanoTime（ns /1000 折 us）、JS QuickJS Date.now（ms ×1000 存 us，粒度毫秒）、TS performance.now（亚毫秒 ms ×1000 折 us）、Python perf_counter_ns（块内 //1000 回传 us，原始 ns 见运行日志）；PHP/ASM 因出通道回传失效改用 SL 侧 nowMillis 整块计时（含块 trampoline 调用开销，ms×1000 存 us，块内 hrtime/QPC printf 原始值见运行日志）" + nl
        md = md + "- 单元格显示自适应单位（us 值过大时折算 ms），附录保留原始微秒值" + nl
        md = md + "- C/C++/CSharp/Java/JavaScript/TypeScript/Python 均为块内自身计时，PHP/ASM 为 SL 侧整块计时；CSharp/Java/TypeScript 首轮块内另含运行时 JIT/解释预热" + nl
        md = md + "- SL 与 SL-NoJIT 为 JIT/非 JIT 双轮对比：SL = JIT 轮（VM JIT 默认开启），SL-NoJIT = 非 JIT 轮（VM 字节码解释执行，启动传参 SL_JIT=0）；缺轮数据自动合并自 report/entries_<语言>.txt 上轮缓存" + nl + nl

        # 语言与优化说明表（取各语言首条记录的说明）
        md = md + "## 语言与优化说明" + nl + nl
        md = md + "| 语言 | 使用说明 | 优化选项 |" + nl
        md = md + "|------|----------|----------|" + nl
        md = md + BenchCollector.langRow( "SL" )
        md = md + BenchCollector.langRow( "SL-NoJIT" )
        md = md + BenchCollector.langRow( "C" )
        md = md + BenchCollector.langRow( "C++" )
        md = md + BenchCollector.langRow( "ASM" )
        md = md + BenchCollector.langRow( "CSharp" )
        md = md + BenchCollector.langRow( "Java" )
        md = md + BenchCollector.langRow( "JavaScript" )
        md = md + BenchCollector.langRow( "TypeScript" )
        md = md + BenchCollector.langRow( "Python" )
        md = md + BenchCollector.langRow( "PHP" )
        md = md + nl

        # 多语言对比总表：按测试类型归并（一行一个测试，各语言该测试全部子项耗时求和，us 域）
        md = md + "## 耗时对比总表（自适应单位，越小越快，单元格为该测试全部子项耗时合计）" + nl + nl
        md = md + "| 测试类型 | 参数 | SL | SL-NoJIT | C | C++ | ASM | CSharp | Java | JavaScript | JavaScriptV8 | Python | PHP |" + nl
        md = md + "|----------|------|----|----------|---|-----|-----|--------|------|------------|--------------|--------|-----|" + nl
        List<BenchEntry> rows = BenchCollector.collectRows()
        for i = 0, i < rows.length, i++
        {
            BenchEntry row = rows._getItem_( i )
            int cnt = BenchCollector.countOf( row.testType, "SL" )
            string param = row.testParam
            if cnt > 1
            {
                param = param + " 等 " + cnt.toString() + " 子项"
            }
            md = md + "| " + row.testType + " | " + param + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "SL" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "SL-NoJIT" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "C" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "C++" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "ASM" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "CSharp" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "Java" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "JavaScript" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "TypeScript" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "Python" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "PHP" ) + " |" + nl
        }
        md = md + nl

        # 附录：全量原始条目（采集顺序，时间列保留原始微秒值）
        md = md + "## 附录: 全部原始条目" + nl + nl
        md = md + "| 序号 | 语言 | 测试类型 | 参数 | 运行时间(us) |" + nl
        md = md + "|------|------|----------|------|--------------|" + nl
        int seq = 0
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            seq = seq + 1
            md = md + "| " + seq.toString() + " | " + e.language + " | " + e.testType + " | " + e.testParam + " | " + e.timeUs.toString() + " |" + nl
        }
        ret md
    }

    # 单语言说明行（无该语言记录返回空串，不出现在表中）
    static string langRow( string language )
    {
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.language == language
            {
                ret "| " + e.language + " | " + e.languageDesc + " | " + e.optDesc + " |" + "\n"
            }
        }
        ret ""
    }

    # 归并行集合：按 testType 去重，保持首次出现顺序（行代表值取该测试首条记录）
    static List<BenchEntry> collectRows()
    {
        List<BenchEntry> rows = List<BenchEntry>()
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if BenchCollector.findRow( rows, e.testType ) == null
            {
                rows.add( e )
            }
        }
        ret rows
    }

    static BenchEntry findRow( List<BenchEntry> rows, string testType )
    {
        for i = 0, i < rows.length, i++
        {
            BenchEntry r = rows._getItem_( i )
            if r.testType == testType
            {
                ret r
            }
        }
        ret null
    }

    # 某测试类型下指定语言的记录条数
    static int countOf( string testType, string language )
    {
        int cnt = 0
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.testType == testType && e.language == language
            {
                cnt = cnt + 1
            }
        }
        ret cnt
    }

    # 指定（测试类型, 语言）全部子项耗时求和（us 域）；无记录返回 "-"
    static string timeCell( string testType, string language )
    {
        long total = 0L
        bool found = false
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.testType == testType && e.language == language
            {
                total = total + e.timeUs
                found = true
            }
        }
        if !found
        {
            ret "-"
        }
        ret BenchCollector.fmtUs( total )
    }

    # 微秒自适应单位：<1000 → us；否则折算 ms（总表统一）
    static string fmtUs( long us )
    {
        if us < 1000
        {
            ret us.toString() + "us"
        }
        ret ( us / 1000 ).toString() + "ms"
    }

    # 两位数补零
    static string pad2( int v )
    {
        if v < 10
        {
            ret "0" + v.toString()
        }
        ret v.toString()
    }

    # ---------- SL 双轮 sidecar（JIT / 非 JIT 缓存合并） ----------

    # 本轮 SL 系条目耗时逐行落盘 report/entries_<slLang>.txt（每行一个 us 值，
    # 顺序 = 采集顺序；首行 # 注释）。另一轮次运行生成报告时读它合并出
    # 双列对比；同轮覆盖写（latest wins）。
    static saveSlSidecar()
    {
        string lang = BenchCollector.slLang()
        int n = 0
        string content = "# SL bench sidecar lang=" + lang + " (one timeUs per line, collect order)\n"
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.language == lang
            {
                content = content + e.timeUs.toString() + "\n"
                n = n + 1
            }
        }
        if n == 0
        {
            ret
        }
        if !IO.Directory.exists( "report" )
        {
            IO.Directory.createDirectory( "report" )
        }
        string path = "report/entries_" + lang + ".txt"
        bool ok = File.writeAllText( path, content )
        if ok
        {
            Console.println( "[BenchCollector] SL sidecar saved: " + path + " (" + n.toString() + " entries)" )
        }
        else
        {
            Console.println( "[BenchCollector] SL sidecar write FAILED: " + path )
        }
    }

    # 合并另一轮次的 sidecar 缓存为本语言系条目：JIT 轮合入 SL-NoJIT，
    # 非 JIT 轮合入 SL。条目的 testType/testParam 直接取本轮 SL 系条目
    #（同一套件同序），耗时取缓存行值；条数不齐（套件变化/缓存过期）整批跳过。
    static mergeOtherSlSidecar()
    {
        string other = "SL-NoJIT"
        if BenchCollector.slLang() == "SL-NoJIT"
        {
            other = "SL"
        }
        if BenchCollector.countLang( other ) > 0
        {
            ret
        }
        string path = "report/entries_" + other + ".txt"
        if !File.exists( path )
        {
            ret
        }
        string text = File.readAllText( path )
        if text == null
        {
            ret
        }
        List<long> nums = BenchCollector.parseNumberLines( text )
        int n = BenchCollector.countLang( BenchCollector.slLang() )
        if n == 0 || nums.length != n
        {
            Console.println( "[BenchCollector] sidecar merge skipped: " + path + " lines=" + nums.length.toString() + " current=" + n.toString() + " (suite changed or stale cache)" )
            ret
        }
        string opt = "VM JIT 默认开启（--no-jit 关闭）"
        if other == "SL-NoJIT"
        {
            opt = "VM 字节码解释执行，JIT 关闭（启动传参 SL_JIT=0）"
        }
        opt = opt + "（合并自缓存 " + path + "）"
        int idx = 0
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.language == BenchCollector.slLang()
            {
                long v = nums._getItem_( idx )
                idx = idx + 1
                BenchCollector.record( other, "SLang 自研语言，SL VM 字节码执行", opt, e.testType, e.testParam, v )
            }
        }
        Console.println( "[BenchCollector] sidecar merged: " + path + " (" + nums.length.toString() + " entries -> " + other + ")" )
    }

    # 逐行解析数字文本（\n 分行，容 \r，# 开头行忽略）；无 split/charCodeAt
    # 依赖——按字节 slice + 单字符 == 比对（UTF-8 下 ASCII 分隔符单字节安全）
    static List<long> parseNumberLines( string text )
    {
        List<long> nums = List<long>()
        int len = text.length
        int start = 0
        for i = 0, i <= len, i++
        {
            bool atEnd = i == len
            string ch = ""
            if !atEnd
            {
                ch = text.slice( i, i + 1 )
            }
            if atEnd || ch == "\n"
            {
                string line = text.slice( start, i )
                int ll = line.length
                if ll > 0 && line.slice( ll - 1, ll ) == "\r"
                {
                    line = line.slice( 0, ll - 1 )
                }
                if line.length > 0 && line.slice( 0, 1 ) != "#"
                {
                    nums.add( BenchCollector.parseLong( line ) )
                }
                start = i + 1
            }
        }
        ret nums
    }

    # 纯数字串 → long（容尾空白；非数字字节跳过）
    static long parseLong( string s )
    {
        long v = 0L
        int len = s.length
        for i = 0, i < len, i++
        {
            long c = SystemStringCharCodeAt( s, i )
            if c >= 48 && c <= 57
            {
                v = v * 10L + c - 48L
            }
        }
        ret v
    }

    # 指定语言条目数
    static int countLang( string language )
    {
        int cnt = 0
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.language == language
            {
                cnt = cnt + 1
            }
        }
        ret cnt
    }
}
