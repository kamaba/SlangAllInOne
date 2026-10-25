using System.Diagnostics;
using System.Text;
using SimpleLanguage.Project;

namespace SimpleLanguageCompileStdlib;

/// <summary>
/// 标准库编译驱动（2026-10-18 由 CompileCore / CompileMath / CompileStd 三工程合一）。
/// 第一个非 - 开头参数作为选择器：
///   core | math | std —— 单编对应标准库（进程内编译，与旧三驱动行为一致）；
///   all（缺省）      —— Core → Std → Math 依序全编，每模块自举一个干净子进程
///                        （与 Pack/PackModulesCommand 同模型，隔离 Front 静态状态；
///                         Std 只引用 Core、Math 引用 Core+Std，改序后清空 out\export
///                         首编完全自举，2026-10-18 由 Core→Math→Std 改序）；
///   其他             —— 视为显式工程路径（如某测试工程的 .sp）。
/// 其余参数原样转发 Front CLI（显式 --format 等可覆盖内置旗标）。
/// 预设模块编译成功后自动把产物（R15：slb 主产物 + json 调试副本，--format binary+json 内置）
/// 同步到 package\{win32|linux}-{debug|release}\lib 四目录
/// （2026-10-18 用户指令，与 publish 的 pack-modules 同一落位；显式工程路径不同步）。
/// IDE 经 Properties\launchSettings.json 的 All/Core/Math/Std 配置分流
/// （All 为默认 profile 且不带 commandLineArgs：dotnet run 会把 profile 参数与
/// -- 后参数拼接，默认 profile 留空才能保证 `-- core` 之类不被污染）。
/// </summary>
internal static class Program
{
    /// <summary>标准库预设：名称 → 工程路径（相对 SlangAllInOne 根）；数组顺序即 all 的编译顺序
    /// （Core → Std → Math：Std 只引用 Core，Math 引用 Core+Std，清空产物后首编完全自举）。</summary>
    static readonly (string Name, string Path)[] Presets =
    {
        ("core", Path.Combine("SLangCore", "Lib", "Core", "Core")),
        ("std",  Path.Combine("SLangCore", "Lib", "Std", "Std")),
        ("math", Path.Combine("SLangCore", "Lib", "Math", "Math")),
    };

    /// <summary>Main 里赋值（GetRepoRoot 结果），供 CompileOne/SyncToPackageLibs
    /// 计算 out\export 与 package 目录；避免逐层传参。</summary>
    static string? repoRootHolder;

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        string repoRoot = GetRepoRoot();
        repoRootHolder = repoRoot;

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

        /* 预设命中：presetName = 工程路径尾段（Core/Math/Std，产物目录名），
         * 用于编译成功后同步产物进四个包目录 lib\；显式工程路径不同步。 */
        string? presetName = null;
        string projectPath;
        var preset = Presets.FirstOrDefault(p => selector.Equals(p.Name, StringComparison.OrdinalIgnoreCase));
        if (preset.Name != null)
        {
            projectPath = Path.Combine(repoRoot, preset.Path);
            presetName = Path.GetFileName(preset.Path);
        }
        else
        {
            projectPath = selector;
        }
        return CompileOne(projectPath, forwardArgs, presetName);
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

    /// <summary>单编（进程内）：compile -e ir -p <路径> -o3 --format binary+json
    /// --no-banner + 转发参数；成功（slb mtime fresh，Front 失败时退出码仍 0，
    /// mtime 才是硬证据）后把产物同步进四个包目录的 lib\（2026-10-18 用户指令：
    /// 标准库编译产物按 debug/release 分别落 package\{win32|linux}-{debug|release}\lib，
    /// 与 publish 的 pack-modules 同一落位；显式工程路径 selector 不属于标准库，
    /// 不同步）。</summary>
    static int CompileOne(string projectPath, List<string> forwardArgs, string? presetName = null)
    {
        var cliArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath, "-o3",
            "--format", "binary+json", "--no-banner" };
        cliArgs.AddRange(forwardArgs);

        Console.WriteLine($"CompileStdlib: project = {projectPath}");

        var start = DateTime.Now;
        try
        {
            var inputArgs = new CommandInputArgs(cliArgs.ToArray());
            _ = CommandExecutor.Execute(inputArgs);
            Console.Out.Flush();

            /* 产物落位 = {export.outputDir}/{moduleName}/；R15 双产物：
             * slb 主产物恒导出 + json 调试副本（--format binary+json）。 */
            if (presetName == null)
                return 0;

            string moduleDir = Path.Combine(repoRootHolder ?? ".", "out", "export", presetName);
            string slbPath = Path.Combine(moduleDir, presetName + ".module.slb");
            bool fresh = File.Exists(slbPath) && File.GetLastWriteTime(slbPath) >= start.AddSeconds(-5);
            if (!fresh)
            {
                Console.WriteLine($"[FAIL] {presetName}: compile failed (slb not rewritten: {slbPath})");
                return 1;
            }
            SyncToPackageLibs(moduleDir, presetName);
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return 1;
        }
    }

    /// <summary>把刚编译的标准库产物同步到四个包目录的 lib\（与 publish 的
    /// PackStdModules 落位一致）：
    ///   *.module.slb → 四目录恒同步；*.module.json → 仅 *-debug 两目录
    /// （调试副本）；math_lib.dll（Math 的 FFI 原生库，Windows 产物）→ 仅
    /// win32-* 两目录的 lib\windows\ 平台位（布局标准 2026-10-25）。包目录
    /// 不存在时创建 lib\（publish 尚未跑过也能先见产物）。
    /// 文件锁等失败仅告警（下次 publish/pack-modules 会重打，不必阻断）。</summary>
    static void SyncToPackageLibs(string moduleDir, string name)
    {
        string pkgRoot = Path.Combine(repoRootHolder ?? ".", "package");
        foreach (var pkg in new[] { "win32-debug", "win32-release", "linux-debug", "linux-release" })
        {
            string libDir = Path.Combine(pkgRoot, pkg, "lib");
            try
            {
                Directory.CreateDirectory(libDir);

                string slbSrc = Path.Combine(moduleDir, name + ".module.slb");
                File.Copy(slbSrc, Path.Combine(libDir, name + ".module.slb"), overwrite: true);

                /* json 调试副本只进 debug 包（release 包按包卫生不带）。 */
                string jsonSrc = Path.Combine(moduleDir, name + ".module.json");
                if (pkg.EndsWith("-debug") && File.Exists(jsonSrc))
                    File.Copy(jsonSrc, Path.Combine(libDir, name + ".module.json"), overwrite: true);

                /* math_lib.dll 是 Windows PE：落 win32 包 lib\windows\ 平台位
                 * （布局标准 2026-10-25，与 publish 的 pack-modules 同落位）；
                 * linux 包不携带（既有发布约定）。 */
                if (name == "Math" && pkg.StartsWith("win32-"))
                {
                    string mathSrc = Path.Combine(moduleDir, "math_lib.dll");
                    if (File.Exists(mathSrc))
                    {
                        string platDir = Path.Combine(libDir, "windows");
                        Directory.CreateDirectory(platDir);
                        File.Copy(mathSrc, Path.Combine(platDir, "math_lib.dll"), overwrite: true);
                    }
                }
                Console.WriteLine($"[SYNC] {name} -> package\\{pkg}\\lib\\");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WARN] sync {name} -> package\\{pkg}\\lib failed: {ex.Message}");
            }
        }
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
