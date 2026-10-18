using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using SimpleLanguage.Logging;
using SimpleLanguage.Project;

namespace CSimpleVMTest;

/// <summary>
/// 联合测试宿主（2026-10-18 由 CSimpleVMCore/Std/Math/Special/BenchMark/RenderTest
/// 与 Test/Test2 八个宿主工程合一）：
/// Front 进程内编译（-start=false 走 dotnet 子进程）→ 解析 module 包 → C VM 执行
/// （Debug = P/Invoke csimple_lang_dll.dll 进程内、C#/C 可同进程断点调试；
///   Release = csimple_lang.exe 独立进程）。
///
/// 用例选择（第一个非 - 开头参数；IDE 里对应 Properties\launchSettings.json 各 profile）：
///   BaseTest | ExpendTest（缺省） | MathTest | SpecialTest | BenchMark | RenderTest
///       —— 六大用例集预设（合并自八个旧宿主的默认入口）；
///   NullFast | JsonTest | … | GameTank —— 原 CSimpleVMTest 的命名用例（Other/ 探针、
///       负例与 samples 等，全表见 Presets）；
///   其他 —— 视为显式工程路径（相对/绝对均可）。
/// 其余选项：-test（跑 _test_ 入口）、-start true/false（false 走 dotnet 子进程编译）、
/// -debug（Release 进程模式下启动前暂停挂调试器）、-O0..-O3（转发 Front）、
/// "--" 之后的 token 原样透传给 C VM 作 Project._inputArgs 程序参数。
/// </summary>
internal static class Program
{
    /// <summary>用例预设：名称 → 工程路径（相对 SlangAllInOne 根）；缺省 = ExpendTest。</summary>
    static readonly (string Name, string Path)[] Presets =
    {
        // 六大用例集（合并自八个旧宿主）
        ("BaseTest",    Path.Combine("SLangCore", "test", "BaseTest", "ProjectTest")),
        ("ExpendTest",  Path.Combine("SLangCore", "test", "ExpendTest", "ProjectTest")),
        ("MathTest",    Path.Combine("SLangCore", "test", "MathTest", "ProjectTest")),
        ("SpecialTest", Path.Combine("SLangCore", "test", "SpecialTest", "ProjectTest")),
        ("BenchMark",   Path.Combine("SLangCore", "test", "BenchMark", "BenchMark")),
        ("RenderTest",  Path.Combine("SLangCore", "test", "RenderTest", "ProjectTest")),
        // 命名用例（原 CSimpleVMTest）
        ("NullFast",                   Path.Combine("SLangCore", "test", "Other", "NullFastTest", "ProjectTest")),
        ("JsonTest",                   Path.Combine("SLangCore", "test", "Other", "JsonTest", "JsonTest")),
        ("PlatformAotNegTest",         Path.Combine("SLangCore", "test", "Other", "PlatformAotNegTest", "PlatformAotNegTest")),
        ("PlatformNegTest",            Path.Combine("SLangCore", "test", "Other", "PlatformNegTest", "PlatformNegTest")),
        ("PlatformOverrideNegTest",    Path.Combine("SLangCore", "test", "Other", "PlatformOverrideNegTest", "PlatformOverrideNegTest")),
        ("PlatformVariantNegTest",     Path.Combine("SLangCore", "test", "Other", "PlatformVariantNegTest", "PlatformVariantNegTest")),
        ("PlatformVariantTest",        Path.Combine("SLangCore", "test", "Other", "PlatformVariantTest", "PlatformVariantTest")),
        ("InlineLambdaTest",           Path.Combine("SLangCore", "test", "Other", "InlineLambdaTest", "ProjectTest")),
        ("InlineLambdaForbiddenTest",  Path.Combine("SLangCore", "test", "Other", "InlineLambdaForbiddenTest", "ProjectTest")),
        ("AutoInlineTest",             Path.Combine("SLangCore", "test", "Other", "AutoInlineTest", "ProjectTest")),
        ("InlineMethodTest",           Path.Combine("SLangCore", "test", "Other", "InlineMethodTest", "ProjectTest")),
        ("ARCTest",                    Path.Combine("SLangCore", "test", "Other", "ARCTest", "ArcProbe")),
        ("CoroGCProbe",                Path.Combine("SLangCore", "test", "Other", "CoroGCProbe", "CoroGCProbe")),
        ("MiProbe",                    Path.Combine("SLangCore", "test", "Other", "MiProbe", "MiProbe")),
        ("NestedGCProbe",              Path.Combine("SLangCore", "test", "Other", "NestedGCProbe", "NestedGCProbe")),
        ("OOMProbe",                   Path.Combine("SLangCore", "test", "Other", "OOMProbe", "OOMProbe")),
        ("SBAProbe",                   Path.Combine("SLangCore", "test", "Other", "SBAProbe", "SBAProbe")),
        ("SFRepro",                    Path.Combine("SLangCore", "test", "Other", "SFRepro", "SFRepro")),
        ("TLSFProbe",                  Path.Combine("SLangCore", "test", "Other", "TLSFProbe", "TLSFProbe")),
        ("AtSignLabel",                Path.Combine("SLangCore", "test", "Other", "AtSignLabel", "AtSignNegativeTest")),
        ("NetTest",                    Path.Combine("SLangCore", "test", "Other", "NetTest", "ProjectTest")),
        ("HttpWebTest",                Path.Combine("SLangCore", "test", "Other", "HttpWebTest", "HttpWebTest")),
        ("MyTest",                     Path.Combine("SLangCore", "test", "Other", "MyTest", "MyTest")),
        ("GameTank",                   Path.Combine("SLangCore", "samples", "Game", "TankGame", "TankGame")),
    };

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        string repoRoot = GetRepoRoot();

        if (args.Length >= 1 && (args[0] == "-h" || args[0] == "--help" || args[0] == "/?"))
        {
            PrintUsage();
            return 0;
        }

        // 用例选择：第一个非 - 开头参数（"--" 之后的 token 是程序参数，不参与解析）。
        string? selector = GetProjectPathArg(args);
        string projectPath = ResolvePreset(selector, repoRoot)
            ?? selector
            ?? Path.Combine(repoRoot, "SLangCore", "test", "ExpendTest", "ProjectTest");

        bool runTestEntry = args.Any(a => string.Equals(a, "-test", StringComparison.OrdinalIgnoreCase));
        bool start = TryGetBoolArg(args, "start", defaultValue: true);
        bool debug = args.Any(a => string.Equals(a, "-debug", StringComparison.OrdinalIgnoreCase));
        // -O0..-O3 / -o0..-o3 forwarded to the Front compile step (absent = compiler default level)
        string? optLevelArg = GetOptimizeLevelArg(args);
        // 程序参数（Project._inputArgs）："--" 之后所有 token 原样透传给 C VM
        // 例：dotnet run --project ... -- BenchMark -- -- w3   ->   C VM 收到 "-- w3"
        List<string> programArgs = GetProgramArgs(args);

        if (selector == null)
        {
            Console.WriteLine("No args provided, using defaults:");
            Console.WriteLine($"  projectPath = {projectPath}");
        }

        // Step 1: Compile with Front (in-process or via dotnet run)
        var dotnetFrontArgs = new List<string>
        {
            "run", "--project", Quote(Path.Combine(repoRoot, "..", "simple_language", "source", "SimpleLanguageFront.csproj")), "--",
            "compile", "-e", "ir", "-p", projectPath
        };
        if (optLevelArg != null)
            dotnetFrontArgs.Add(optLevelArg);
        dotnetFrontArgs.Add("--no-banner");
#if DEBUG
        // Debug：改走二进制导出（.module.slb 必产物），并附带导出 module.json 调试副本
        dotnetFrontArgs.Add("--format");
        dotnetFrontArgs.Add("binary");
        dotnetFrontArgs.Add("--export-json");
#endif

        int frontExit = start
            ? RunFrontInProcess(projectPath, optLevelArg)
            : RunDotnet(dotnetFrontArgs, "Front compile", repoRoot);
        if (frontExit != 0)
        {
            Console.WriteLine($"Front compile failed, exit code: {frontExit}");
            // 负例工程: 前端编译失败是预期结果, 校验预期拦截 LID 全部命中则视为通过 (exit 0)
            var neg = TryGetNegativeFrontCase(args);
            if (neg != null)
                return VerifyNegativeFrontCase(neg, repoRoot, frontExit);
            return frontExit;
        }

        // Step 2: Resolve compiled module package path
        string packagePath = ResolveModulePackagePath(repoRoot, projectPath);
        if (!File.Exists(packagePath))
        {
            Console.WriteLine("Compile succeeded but module package not found:");
            Console.WriteLine(packagePath);
            return 3;
        }

        Console.WriteLine($"Package: {packagePath}");

        // Step 3: Run C VM (csimple_lang.exe) as external process
        // C VM 测试用例使用相对路径（如 Sqlite3Test 的 Resources/ttest），
        // VS 启动时 CWD 是 bin\Debug\net8.0，需切到测试工程目录，与命令行运行环境一致
        string? projectDir = Path.GetDirectoryName(Path.GetFullPath(projectPath));
        if (Directory.Exists(projectDir))
        {
            Environment.CurrentDirectory = projectDir;
        }
        int cvmExit = RunCVM(packagePath, runTestEntry, repoRoot, debug, programArgs);
        if (cvmExit != 0)
        {
            Console.WriteLine($"C VM run failed, exit code: {cvmExit}");
            return cvmExit;
        }

        Console.WriteLine("Front compile + C VM run completed.");
        return 0;
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  dotnet run --project Project/CSimpleVMTest/CSimpleVMTest.csproj -- [suite|case|projectPath] [options] [-- programArgs]");
        Console.WriteLine("Suites    : " + string.Join(", ", Presets.Take(6).Select(p => p.Name)));
        Console.WriteLine("Named     : " + string.Join(", ", Presets.Skip(6).Select(p => p.Name)));
        Console.WriteLine("Options   : -test | -start true/false | -debug | -O0..-O3");
        Console.WriteLine("Default   : ExpendTest");
        Console.WriteLine("Example:");
        Console.WriteLine("  ... -- MathTest -test          (compile MathTest and run _test_ entry)");
        Console.WriteLine("  ... -- BenchMark -- -- w3      (pass program args to Project._inputArgs)");
    }

    /// <summary>预设名 → 绝对路径；未命中返回 null（selector 本身作为工程路径）。</summary>
    static string? ResolvePreset(string? selector, string repoRoot)
    {
        if (string.IsNullOrEmpty(selector))
            return null;
        foreach (var p in Presets)
        {
            if (selector.Equals(p.Name, StringComparison.OrdinalIgnoreCase))
                return Path.Combine(repoRoot, p.Path);
        }
        return null;
    }

    static int RunCVM(string packagePath, bool runTestEntry, string repoRoot, bool debug = false, List<string>? programArgs = null)
    {
        // Resolve csimple_lang exe/dll path (VS output: csimple_lang\build\<Config>\bin).
        // Match the C# build configuration to the VM build configuration:
        // Debug  -> build\Debug\bin   (P/Invoke DLL, can attach C debugger)
        // Release-> build\Release\bin (optimized /O2 + RELEASE=1 exe)
        // 找不到时回退另一配置。
#if DEBUG
        string cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Debug", "bin"));
        string cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");

        if (!File.Exists(cvmExe))
        {
            cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Release", "bin"));
            cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");
        }
#else
        string cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Release", "bin"));
        string cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");

        if (!File.Exists(cvmExe))
        {
            // vcxproj Release|x64 (Application) outputs csimple_lang_lib.exe into the same bin dir
            string libExe = Path.Combine(cvmDir, "csimple_lang_lib.exe");
            if (File.Exists(libExe))
                cvmExe = libExe;
        }

        if (!File.Exists(cvmExe))
        {
            cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Debug", "bin"));
            cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");
        }
#endif

        if (!File.Exists(cvmExe))
        {
            Console.WriteLine("csimple_lang.exe not found. Build the C VM first:");
            Console.WriteLine("  .\\scripts\\build-vm-win.ps1 -Configuration Debug");
            return 4;
        }

        var cvmArgs = new List<string> { "run", Quote(packagePath) };
        if (runTestEntry)
        {
            cvmArgs.Add("-test");
        }
        // 程序参数（Project._inputArgs）：仅透传宿主命令行 "--" 之后的 token，
        // 无 "--" 时不注入（_inputArgs 为空数组，全量回归不受影响）。
        // InputArgsTest 三参数路径：dotnet run --project ... -- -- hello 42 world
        if (programArgs != null && programArgs.Count > 0)
        {
            cvmArgs.Add("--");
            cvmArgs.AddRange(programArgs);
        }

#if DEBUG
        // Debug: P/Invoke into csimple_lang_dll.dll (in-process, can attach C debugger)
        string dllPath = Path.Combine(cvmDir, "csimple_lang_dll.dll");
        if (!File.Exists(dllPath))
        {
            Console.WriteLine($"csimple_lang_dll.dll not found at {dllPath}, falling back to process mode.");
            return RunProcess(cvmExe, cvmArgs, "C VM run (csimple_lang)");
        }

        Console.WriteLine("=== C VM run (P/Invoke) ===");
        Console.WriteLine($"DLL: {dllPath}");

        // Add DLL directory to search path so DllImport can find it
        if (OperatingSystem.IsWindows())
            SetDllDirectory(cvmDir);

        // Build argv: ["csimple_lang", "run", packagePath, ...]
        var argv = new List<string> { "csimple_lang" };
        argv.AddRange(cvmArgs);
        return CallCliMain(argv.ToArray());
#else
        // Release: process invocation
        if (debug)
        {
            Console.WriteLine("=== C VM debug mode (csimple_lang) ===");
            Console.WriteLine($"{cvmExe} {string.Join(" ", cvmArgs)}");
            Console.WriteLine("Press Enter to start C VM...");
            Console.ReadLine();
            return RunProcessDirect(cvmExe, cvmArgs, Environment.CurrentDirectory);
        }
        return RunProcess(cvmExe, cvmArgs, "C VM run (csimple_lang)");
#endif
    }

#if DEBUG
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetDllDirectory(string lpPathName);

    [DllImport("csimple_lang_dll.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int cli_main(int argc, IntPtr argv);

    static int CallCliMain(string[] args)
    {
        int argc = args.Length;
        var argvPtrs = new IntPtr[argc];
        try
        {
            for (int i = 0; i < argc; i++)
            {
                byte[] bytes = Encoding.UTF8.GetBytes(args[i] + "\0");
                argvPtrs[i] = Marshal.AllocHGlobal(bytes.Length);
                Marshal.Copy(bytes, 0, argvPtrs[i], bytes.Length);
            }
            IntPtr nativeArgv = Marshal.AllocHGlobal(IntPtr.Size * argc);
            Marshal.Copy(argvPtrs, 0, nativeArgv, argc);
            int ret = cli_main(argc, nativeArgv);
            Marshal.FreeHGlobal(nativeArgv);
            return ret;
        }
        finally
        {
            for (int i = 0; i < argc; i++)
            {
                if (argvPtrs[i] != IntPtr.Zero)
                    Marshal.FreeHGlobal(argvPtrs[i]);
            }
        }
    }
#endif

    static int RunProcessDirect(string fileName, List<string> args, string workingDirectory)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = string.Join(" ", args),
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            CreateNoWindow = false
        };
        using var p = new Process { StartInfo = psi };
        p.Start();
        p.WaitForExit();
        return p.ExitCode;
    }

    static int RunProcess(string fileName, List<string> args, string stepName, string? workingDirectory = null)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = string.Join(" ", args),
            WorkingDirectory = string.IsNullOrWhiteSpace(workingDirectory) ? Environment.CurrentDirectory : workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            CreateNoWindow = true
        };

        using var p = new Process { StartInfo = psi };

        p.OutputDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            Console.WriteLine(e.Data);
        };
        p.ErrorDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            Console.Error.WriteLine(e.Data);
        };

        Console.WriteLine($"=== {stepName} ===");
        Console.WriteLine($"{psi.FileName} {psi.Arguments}");

        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        p.WaitForExit();

        return p.ExitCode;
    }

    static int RunDotnet(List<string> args, string stepName, string? workingDirectory = null)
    {
        return RunProcess("dotnet", args, stepName, workingDirectory);
    }

    static int RunFrontInProcess(string projectPath, string? optLevelArg = null)
    {
        try
        {
            Console.WriteLine("=== Front compile (in-process) ===");
            var frontArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath };
            if (optLevelArg != null)
                frontArgs.Add(optLevelArg);
            frontArgs.Add("--no-banner");
#if DEBUG
            // Debug：改走二进制导出（.module.slb 必产物），并附带导出 module.json 调试副本
            frontArgs.Add("--format");
            frontArgs.Add("binary");
            frontArgs.Add("--export-json");
#endif
            Console.WriteLine("Front: " + string.Join(' ', frontArgs));
            var inputArgs = new CommandInputArgs(frontArgs.ToArray());
            bool ok = CommandExecutor.Execute(inputArgs);
            if (!ok || Log.errorCount > 0)
            {
                Console.WriteLine($"Front compile failed, error count: {Log.errorCount}");
                return 1;
            }
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return 1;
        }
    }

    // ==== 负例工程支持: 前端编译「预期失败 = 成功」====
    // 负例工程的拦截命中会让 Front 以非零码退出, 这里读 Front.txt 校验
    // 预期拦截 LID 是否全部命中: 全命中 = 负例通过 (exit 0, 跳过 C VM 运行),
    // 有缺命中 = 真失败。只看预期 LID 命中数, 不计连锁产生的其他日志。

    private sealed class NegativeFrontCase
    {
        public string ArgName = "";          // 命令行启动项名 (args[0])
        public string ExportModuleName = ""; // 导出模块名: out/export/<名>/Logs/Front.txt
        public (string Lid, int Count)[] ExpectedLids = Array.Empty<(string, int)>();
    }

    private static readonly NegativeFrontCase[] s_negativeFrontCases = new[]
    {
        new NegativeFrontCase
        {
            ArgName = "InlineLambdaForbiddenTest",
            ExportModuleName = "InlineLambdaForbiddenTest",
            // 6 个负例: 协程拦截 3 (spawn/await/isolate) + 自引用/互递归 2 + try? 1
            ExpectedLids = new[]
            {
                ("MetaCoreInlineLambdaBodyForbiddenCoroutine", 3),
                ("MetaCoreInlineLambdaBodyForbiddenSelfReference", 2),
                ("MetaCoreInlineLambdaBodyForbiddenExceptionFrame", 1),
            }
        },
    };

    static NegativeFrontCase? TryGetNegativeFrontCase(string[] args)
    {
        if (args.Length == 0)
            return null;
        return s_negativeFrontCases.FirstOrDefault(c => c.ArgName == args[0]);
    }

    // 校验负例: 按行统计 Front.txt 中 "[LID]" 出现次数, 预期全部达标 = 通过
    static int VerifyNegativeFrontCase(NegativeFrontCase neg, string repoRoot, int frontExit)
    {
        // 优先用 Front 写入的日志路径 (in-process 模式下最准确), 回退到按模块名推导
        string? logPath = Log.FrontLogFilePath;
        if (string.IsNullOrWhiteSpace(logPath) || !File.Exists(logPath))
            logPath = Path.Combine(repoRoot, "out", "export", neg.ExportModuleName, "Logs", "Front.txt");
        if (!File.Exists(logPath))
        {
            Console.WriteLine($"Negative case '{neg.ArgName}': Front log not found: {logPath}");
            return frontExit;
        }

        var lines = File.ReadAllLines(logPath);
        bool allHit = true;
        Console.WriteLine($"=== Negative front case '{neg.ArgName}': verify expected LID hits ===");
        foreach (var (lid, expected) in neg.ExpectedLids)
        {
            int actual = lines.Count(l => l.Contains("[" + lid + "]"));
            bool hit = actual >= expected;
            Console.WriteLine($"  [{(hit ? "OK" : "MISS")}] {lid}: expect >= {expected}, actual {actual}");
            if (!hit)
                allHit = false;
        }
        if (allHit)
        {
            Console.WriteLine($"Negative test passed: all expected LID interceptions hit, skip C VM run.");
            return 0;
        }
        Console.WriteLine("Negative test FAILED: some expected LID interceptions missing.");
        return frontExit;
    }

    static string ResolveModulePackagePath(string repoRoot, string projectPath)
    {
        /* 编译同进程完成后从 jsonc 派生的进程内状态取导出目录
         *（SIMPLELANG_EXPORT_OUTDIR 仅保留为外部手动覆盖入口）。 */
        var exportDir = ProjectOutputEnvironment.GetEffectiveExportOutDir();
        if (!string.IsNullOrWhiteSpace(exportDir))
        {
            var d = Path.GetFullPath(exportDir.Trim());
            if (Directory.Exists(d))
            {
                var found = Directory.GetFiles(d, "*.module.json");
                if (found.Length == 1)
                    return found[0];
                if (found.Length > 1)
                    return found.OrderByDescending(File.GetLastWriteTimeUtc).First();
            }
        }

        // Derive module name from project path
        var moduleName = !string.IsNullOrWhiteSpace(projectPath)
            ? Path.GetFileName(projectPath.TrimEnd('\\', '/'))
            : "Core";
        var fallback = Path.Combine(repoRoot, "out", "export", moduleName, moduleName + ".module.json");
        if (File.Exists(fallback))
            return fallback;

        // Final fallback: search export dir for any module.json
        var exportRoot = Path.Combine(repoRoot, "out", "export");
        if (Directory.Exists(exportRoot))
        {
            var found = Directory.GetFiles(exportRoot, "*.module.json", SearchOption.AllDirectories);
            if (found.Length >= 1)
                return found.OrderByDescending(File.GetLastWriteTimeUtc).First();
        }

        return Path.Combine(repoRoot, "out", "export", "Core", "Core.module.json");
    }

    static string? GetProjectPathArg(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            // "--" 之后的 token 属于程序参数（透传给 C VM），不参与本宿主选项解析
            if (a == "--")
                break;
            if (string.IsNullOrEmpty(a) || a.StartsWith('-'))
                continue;
            // "-start true/false" takes the next token as its value, not a project path
            if (i > 0 && string.Equals(args[i - 1], "-start", StringComparison.OrdinalIgnoreCase))
                continue;
            return a;
        }
        return null;
    }

    static List<string> GetProgramArgs(string[] args)
    {
        var result = new List<string>();
        int idx = Array.IndexOf(args, "--");
        if (idx >= 0)
        {
            for (int i = idx + 1; i < args.Length; i++)
                result.Add(args[i]);
        }
        return result;
    }

    static string? GetOptimizeLevelArg(string[] args)
    {
        // Same -O0..-O3 / -o0..-o3 pattern as CommandInputArgs
        foreach (var a in args)
        {
            if (a.Length == 3 && a[0] == '-'
                && (a[1] == 'O' || a[1] == 'o')
                && a[2] >= '0' && a[2] <= '3')
                return a;
        }
        return null;
    }

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

    static string Quote(string s)
    {
        if (string.IsNullOrEmpty(s)) return "\"\"";
        if (s.Contains(' ') || s.Contains('\t') || s.Contains('"'))
            return "\"" + s.Replace("\"", "\\\"") + "\"";
        return s;
    }

    static bool TryGetBoolArg(string[] args, string key, bool defaultValue)
    {
        if (args == null || args.Length == 0)
        {
            return defaultValue;
        }

        string keyLower = key.ToLowerInvariant();
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (string.IsNullOrWhiteSpace(a))
            {
                continue;
            }

            var low = a.ToLowerInvariant();
            if (low == $"--{keyLower}" || low == $"-{keyLower}")
            {
                if (i + 1 < args.Length && bool.TryParse(args[i + 1], out var parsed))
                {
                    return parsed;
                }
                return true;
            }

            if (low.StartsWith($"--{keyLower}=", StringComparison.Ordinal))
            {
                var raw = a.Substring(key.Length + 3);
                if (bool.TryParse(raw, out var parsed))
                {
                    return parsed;
                }
            }
        }

        return defaultValue;
    }
}
