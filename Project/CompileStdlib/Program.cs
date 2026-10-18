using System.Diagnostics;
using System.Text;
using SimpleLanguage.Project;

namespace SimpleLanguageCompileStdlib;

/// <summary>
/// 标准库编译驱动（2026-10-18 由 CompileCore / CompileMath / CompileStd 三工程合一）。
/// 第一个非 - 开头参数作为选择器：
///   core | math | std —— 单编对应标准库（进程内编译，与旧三驱动行为一致）；
///   all（缺省）      —— Core → Math → Std 依序全编，每模块自举一个干净子进程
///                        （与 Pack/PackModulesCommand 同模型，隔离 Front 静态状态）；
///   其他             —— 视为显式工程路径（如某测试工程的 .sp）。
/// 其余参数原样转发 Front CLI（显式 -O0 等可覆盖内置 -o3）。
/// IDE 经 Properties\launchSettings.json 的 All/Core/Math/Std 配置分流
/// （All 为默认 profile 且不带 commandLineArgs：dotnet run 会把 profile 参数与
/// -- 后参数拼接，默认 profile 留空才能保证 `-- core` 之类不被污染）。
/// </summary>
internal static class Program
{
    /// <summary>标准库预设：名称 → 工程路径（相对 SlangAllInOne 根）；数组顺序即 all 的编译顺序。</summary>
    static readonly (string Name, string Path)[] Presets =
    {
        ("core", Path.Combine("SLangCore", "Lib", "Core", "Core")),
        ("math", Path.Combine("SLangCore", "Lib", "Math", "Math")),
        ("std",  Path.Combine("SLangCore", "Lib", "Std", "Std")),
    };

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        string repoRoot = GetRepoRoot();

        // 第一个非 - 开头参数是选择器（预设名或工程路径），不再转发 Front；其余参数原样转发。
        string? selector = null;
        var forwardArgs = new List<string>();
        foreach (var a in args)
        {
            if (selector == null && !string.IsNullOrEmpty(a) && !a.StartsWith('-'))
            {
                selector = a;
                continue;
            }
            forwardArgs.Add(a);
        }

        // Disable Debug.Assert crashes on compiler errors
        SimpleLanguage.Logging.LogManager.Options.EnableAssertFeature = false;

        if (selector == null || selector.Equals("all", StringComparison.OrdinalIgnoreCase))
            return CompileAll(repoRoot, forwardArgs);

        string projectPath = ResolvePreset(selector, repoRoot) ?? selector;
        return CompileOne(projectPath, forwardArgs);
    }

    /// <summary>全编：每模块自举一个干净子进程（apphost 与 dotnet+dll 两种启动形态都兼容）。</summary>
    static int CompileAll(string repoRoot, List<string> forwardArgs)
    {
        string? selfExe = Environment.ProcessPath;
        if (selfExe == null)
        {
            Console.WriteLine("Cannot locate the current executable for child processes.");
            return 1;
        }

        /* 经 dotnet 宿主启动时 ProcessPath 是 dotnet.exe，子进程需要改带 dll 路径 */
        bool viaDotnet = Path.GetFileName(selfExe).StartsWith("dotnet", StringComparison.OrdinalIgnoreCase);
        string dllPath = Path.Combine(AppContext.BaseDirectory, "SimpleLanguageCompileStdlib.dll");

        int failures = 0;
        foreach (var p in Presets)
        {
            Console.WriteLine($"--- CompileStdlib [{p.Name}] (clean child process)");
            var parts = new List<string>();
            if (viaDotnet)
                parts.Add(dllPath);
            parts.Add(p.Name);
            parts.AddRange(forwardArgs);
            var psi = new ProcessStartInfo(selfExe, string.Join(' ', parts.Select(Quote)))
            {
                WorkingDirectory = repoRoot
            };
            using var child = Process.Start(psi);
            if (child == null)
            {
                failures++;
                continue;
            }
            child.WaitForExit();
            if (child.ExitCode != 0)
                failures++;
        }
        return failures == 0 ? 0 : 1;
    }

    /// <summary>单编（进程内）：compile -e ir -p <路径> -o3 --no-banner + 转发参数。</summary>
    static int CompileOne(string projectPath, List<string> forwardArgs)
    {
        var cliArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath, "-o3", "--no-banner" };
        cliArgs.AddRange(forwardArgs);

        Console.WriteLine($"CompileStdlib: project = {projectPath}");

        try
        {
            var inputArgs = new CommandInputArgs(cliArgs.ToArray());
            _ = CommandExecutor.Execute(inputArgs);
            Console.Out.Flush();
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return 1;
        }
    }

    static string? ResolvePreset(string selector, string repoRoot)
    {
        foreach (var p in Presets)
        {
            if (selector.Equals(p.Name, StringComparison.OrdinalIgnoreCase))
                return Path.Combine(repoRoot, p.Path);
        }
        return null;
    }

    static string Quote(string arg) =>
        arg.Contains(' ') ? "\"" + arg + "\"" : arg;

    static string GetRepoRoot()
    {
        string dir = AppContext.BaseDirectory;
        var d = new DirectoryInfo(dir);
        while (d != null && !File.Exists(Path.Combine(d.FullName, "SlangAllInOne.csproj")))
        {
            d = d.Parent;
        }
        if (d == null)
            throw new DirectoryNotFoundException("Cannot locate repo root (SlangAllInOne.csproj).");
        return d.FullName;
    }
}
