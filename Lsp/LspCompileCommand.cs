//****************************************************************************
//  File:      LspCompileCommand.cs
// ------------------------------------------------
//  slang lsp-compile —— LSP 专用诊断编译子命令：新进程编译一次（进程内静态
//  状态天然干净，规避 Front CommandExecutor 不可重入的残留问题，2026-10-19
//  LSP 实测：同进程第二轮 Compile 会因 isLoaded/fileParseList/ProcessManager
//  残留而空跑/假失败），并把结构化结果打到 stdout（纯 JSON，一行协议）：
//
//   { "success": bool,
//     "exportDir": string?,
//     "packageJson": string?,          // 成功时的 SLIR 内存包 json（符号源）
//     "diagnostics": [ { "severity": 1|2,   // 1=Error 2=Warning（pass/Info 不含）
//         "code": "LIDEventName", "file": "相对路径|null",
//         "line": int(1-based), "char": int(0-based),
//         "endLine": int, "endChar": int,
//         "message": string, "extend": string, "tips": string } ] }
//
//  Front 的全部日志镜像/宿主提示走 stderr（Console.SetOut(stderr)），stdout
//  只有这一行 JSON——与 slang lsp 同款 stdout 卫生纪律。
//****************************************************************************
using System.Text;
using System.Text.Json;
using SimpleLanguage.ExportLanguage;
using SimpleLanguage.Logging;
using SlangAllInOne.FrontEnd;

namespace SlangAllInOne.Lsp;

internal static class LspCompileCommand
{
    public static int Run(string[] args)
    {
        if (args.Length == 0 || args[0].StartsWith('-'))
        {
            Console.Error.WriteLine("用法: slang lsp-compile <project.sp> [--cwd <dir>]");
            return 2;
        }
        string spPath = Path.GetFullPath(args[0]);
        if (!File.Exists(spPath))
        {
            Console.Error.WriteLine("lsp-compile: 工程入口不存在: " + spPath);
            return 2;
        }
        string? cwd = null;
        for (int i = 1; i < args.Length - 1; i++)
        {
            if (args[i] == "--cwd")
            {
                cwd = args[i + 1];
            }
        }
        if (cwd != null)
        {
            Environment.CurrentDirectory = cwd; // Front 相对路径（Resources/ 等）以工程目录为基，与宿主 run 行为一致
        }

        // stdout 专用于结果 JSON；Front 日志镜像全部改走 stderr
        var stdout = Console.OpenStandardOutput();
        Console.SetOut(Console.Error);

        // 导出三态之三（memory）：诊断编译零磁盘产物；SLB 字节不压缩留内存
        //（本命令不消费），format=json 使内存 JSON 文本一并产出（符号源）。
        var result = FrontendService.Compile(spPath, EExportMode.Memory, -1, "json");
        var diags = Log.SnapshotLogs()
            .Where(ld => (ld.logType == LogType.Error || ld.logType == LogType.Warning) && !ld.pass)
            .Select(ld => new
            {
                severity = ld.logType == LogType.Error ? 1 : 2,
                code = ld.error.ToString(),
                file = ld.filePath,
                line = ld.sourceBeginLine,
                @char = ld.sourceBeginChar,
                endLine = ld.sourceEndLine,
                endChar = ld.sourceEndChar,
                message = ld.message ?? "",
                extend = ld.extendMessage ?? "",
                tips = ld.advan ?? "",
            })
            .ToArray();

        var payload = new
        {
            success = result.Success,
            exportDir = result.ExportDir,
            packageJson = result.PackageJson,
            diagnostics = diags,
            // 方法调用点 → 目标方法精确关联（IR 指令流导出，definition 精确跳转数据源）
            callSites = result.Success ? LspCallSiteExporter.Export() : new List<object>(),
        };
        // 匿名 payload 经 JsonDom（纯反射→JsonNode）序列化：STJ 反射路径在
        // Native AOT 下对匿名类型走 SmallObjectWithParameterizedConverter（运行时
        // 构造泛型，无预生成代码 → 崩溃），详见 JsonDom.cs 头注（2026-10-19）
        var json = JsonDom.ToNode(payload)?.ToJsonString() ?? "null";
        var body = Encoding.UTF8.GetBytes(json);
        stdout.Write(body, 0, body.Length);
        stdout.Flush();
        return result.Success ? 0 : 1;
    }
}
