import Std

# ============================================================================
# BenchCollector.sl -- benchmark 数据采集 + Markdown 对比报告生成
#
# 数据模型：
#   data BenchEntry -- 单条计时记录（语言类型 / 语言使用说明 / 优化选项 /
#                      测试类型 / 测试参数 / 运行时间 ms）
#   BenchCollector  -- 静态 List<BenchEntry> 采集器：四个语言的 record
#                      便捷入口（SL 原生逐段计时；C#/Java/JS 插件块整块
#                      计时，含引擎调用开销，首轮另含编译部署）。
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
    timeMs = 0L
}

BenchCollector
{
    # 采集列表（懒初始化：静态字段无 new 初始化先例，首次 record 时创建）
    static List<BenchEntry> _entries = null

    # ---------- 统一采集入口 ----------

    static record( string language, string languageDesc, string optDesc, string testType, string testParam, long timeMs )
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
        e.timeMs = timeMs
        BenchCollector._entries.add( e )
    }

    # ---------- 四语言便捷入口 ----------

    static recordSL( string testType, string testParam, long timeMs )
    {
        BenchCollector.record( "SL", "SLang 自研语言，SL VM 字节码解释执行", "VM 默认（无 JIT）", testType, testParam, timeMs )
    }

    static recordCSharp( string testType, string testParam, long timeMs )
    {
        BenchCollector.record( "CSharp", "C# / mono 运行时（csharp_mono 插件内嵌）", "Mono JIT 默认优化", testType, testParam, timeMs )
    }

    static recordJava( string testType, string testParam, long timeMs )
    {
        BenchCollector.record( "Java", "Java 17 / Hotspot 运行时（java_hotspot 插件内嵌）", "HotSpot 分层 JIT", testType, testParam, timeMs )
    }

    static recordJs( string testType, string testParam, long timeMs )
    {
        BenchCollector.record( "JavaScript", "JavaScript / QuickJS 2024-01-13（javascript_quickjs 插件内嵌）", "QuickJS 解释器（无 JIT）", testType, testParam, timeMs )
    }

    # ---------- 报告生成 ----------

    static generateReport()
    {
        if BenchCollector._entries == null || BenchCollector._entries.length == 0
        {
            Console.println( "[BenchCollector] no entries collected, skip report" )
            ret
        }

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
        md = md + "- 计时口径: 全部为毫秒（Environment.sys.nowMillis / Stopwatch / System.nanoTime / Date.now）" + nl
        md = md + "- CSharp/Java/JavaScript 为插件块整块计时，含引擎调用开销，首轮另含编译部署" + nl + nl

        # 语言与优化说明表（取各语言首条记录的说明）
        md = md + "## 语言与优化说明" + nl + nl
        md = md + "| 语言 | 使用说明 | 优化选项 |" + nl
        md = md + "|------|----------|----------|" + nl
        md = md + BenchCollector.langRow( "SL" )
        md = md + BenchCollector.langRow( "CSharp" )
        md = md + BenchCollector.langRow( "Java" )
        md = md + BenchCollector.langRow( "JavaScript" )
        md = md + nl

        # 四语言对比总表：按测试类型归并（一行一个测试，各语言该测试全部子项耗时求和）
        md = md + "## 耗时对比总表（毫秒，越小越快，单元格为该测试全部子项耗时合计）" + nl + nl
        md = md + "| 测试类型 | 参数 | SL | CSharp | Java | JavaScript |" + nl
        md = md + "|----------|------|----|--------|------|------------|" + nl
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
            md = md + " " + BenchCollector.timeCell( row.testType, "CSharp" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "Java" ) + " |"
            md = md + " " + BenchCollector.timeCell( row.testType, "JavaScript" ) + " |" + nl
        }
        md = md + nl

        # 附录：全量原始条目（采集顺序）
        md = md + "## 附录: 全部原始条目" + nl + nl
        md = md + "| 序号 | 语言 | 测试类型 | 参数 | 运行时间(ms) |" + nl
        md = md + "|------|------|----------|------|--------------|" + nl
        int seq = 0
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            seq = seq + 1
            md = md + "| " + seq.toString() + " | " + e.language + " | " + e.testType + " | " + e.testParam + " | " + e.timeMs.toString() + " |" + nl
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

    # 指定（测试类型, 语言）全部子项耗时求和；无记录返回 "-"
    static string timeCell( string testType, string language )
    {
        long total = 0L
        bool found = false
        for i = 0, i < BenchCollector._entries.length, i++
        {
            BenchEntry e = BenchCollector._entries._getItem_( i )
            if e.testType == testType && e.language == language
            {
                total = total + e.timeMs
                found = true
            }
        }
        if !found
        {
            ret "-"
        }
        ret total.toString()
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
}
