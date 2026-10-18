//****************************************************************************
//  SimpleLanguageTest : BaseTest 用例集宿主（轻量入口，等价 CSimpleVMCoreTest）。
//  2026-10-18 复活改造：原 VM 段引用已删除的 C# VM 工程（SimpleLanuageVM），
//  改走 C VM —— Debug 走 P/Invoke（csimple_lang_dll.dll 进程内，C#/C 可同进程
//  断点调试），Release/子进程模式走 csimple_lang.exe，与 CSimpleVM* 宿主同款。
//****************************************************************************

using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using SimpleLanguage.Logging;
using SimpleLanguage.Project;

namespace SimpleLanguageTest;

internal static class Program
{
    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        string repoRoot = GetRepoRoot();

        // Usage:
        //   dotnet run --project Project/Test/SimpleLanguageTest.csproj -- <projectPath> [-test] [-start=false]
        // Default: BaseTest suite.
        string defaultProjectPath = Path.Combine(repoRoot, "SLangCore", "test", "BaseTest", "ProjectTest");
        string projectPath = args.Length == 0 ? defaultProjectPath : args[0];
        bool runTestEntry = args.Any(a => string.Equals(a, "-test", StringComparison.OrdinalIgnoreCase));
        // Default to in-process mode for easier single-process debugging.
        bool start = TryGetBoolArg(args, "start", defaultValue: true);

        if (args.Length == 0)
        {
            Console.WriteLine("No args provided, using defaults:");
            Console.WriteLine($"  projectPath = {projectPath}");
        }

        // Step 1: Compile with Front (in-process or via dotnet run)
        int frontExit = start
            ? RunFrontInProcess(projectPath)
            : RunDotnet(new List<string>
            {
                "run", "--project",
                Quote(Path.Combine(repoRoot, "..", "simple_language", "source", "SimpleLanguageFront.csproj")), "--",
                "compile", "-e", "ir", "-p", projectPath, "--no-banner"
            }, "Front compile", repoRoot);
        if (frontExit != 0)
        {
            Console.WriteLine($"Front compile failed, exit code: {frontExit}");
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

        // Step 3: Run C VM (csimple_lang) — P/Invoke in-process or external exe
        int vmExit = RunCVM(packagePath, runTestEntry, repoRoot);
        if (vmExit != 0)
        {
            Console.WriteLine($"C VM run failed, exit code: {vmExit}");
            return vmExit;
        }

        Console.WriteLine("Front compile + C VM run completed.");
        return 0;
    }

    static int RunCVM(string packagePath, bool runTestEntry, string repoRoot)
    {
        // Resolve csimple_lang exe/dll path (VS output: csimple_lang\build\<Config>\bin)
        string cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Debug", "bin"));
        string cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");

        if (!File.Exists(cvmExe))
        {
            cvmDir = Path.GetFullPath(Path.Combine(repoRoot, "..", "csimple_lang", "build", "Release", "bin"));
            cvmExe = Path.Combine(cvmDir, "csimple_lang.exe");
        }

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

    static int RunDotnet(List<string> args, string stepName, string? workingDirectory = null)
    {
        return RunProcess("dotnet", args, stepName, workingDirectory);
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

    static int RunFrontInProcess(string projectPath)
    {
        try
        {
            Console.WriteLine("=== Front compile (in-process) ===");
            var frontArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath, "--no-banner" };
#if DEBUG
            // Debug：改走二进制导出（.module.slb 必产物），并附带导出 module.json 调试副本
            frontArgs.Add("--format");
            frontArgs.Add("binary");
            frontArgs.Add("--export-json");
#endif
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

    static string GetRepoRoot()
    {
        // Project/Test -> SlangAllInOne root
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
