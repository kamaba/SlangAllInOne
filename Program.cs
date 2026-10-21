using System.Text;
using SimpleLanguage.ExportLanguage;
using SlangAllInOne.Backend;
using SlangAllInOne.FrontEnd;
using SlangAllInOne.Lsp;
using SlangAllInOne.New;
using SlangAllInOne.Pack;

namespace SlangAllInOne;

/// <summary>
/// SlangAllInOne: unified FrontEnd (SimpleLanguage compiler) + Backend (C VM)
/// host CLI. The headline feature is `run`: compile a project in-process and
/// hand the package to the C VM -- where it goes is picked by the three-state
/// front-to-back handoff parameter (--export-mode): export to the configured
/// directory, export to a temporary folder (<cwd>\_temp\), or keep the
/// uncompressed SLB binary in memory (default) with no disk write.
/// </summary>
internal static class Program
{
    private sealed class Options
    {
        public string Command = "";
        public string ProjectPath = "";
        public string ModuleJsonPath = "";
        public bool Test = false;
        /// <summary>导出三态（--export-mode output|temp|memory）；ExportModeSet 区分
        /// "未指定"（compile 缺省 output / run 缺省 memory）与显式指定。</summary>
        public EExportMode ExportMode = EExportMode.OutputDir;
        public bool ExportModeSet = false;
        public bool NoBanner = false;
        public bool ForceRun = false;
        public bool DebugVm = false;
        public bool StrictPlugins = false;
        public bool Help = false;
        public string CvmConfig = "Debug";
        public int OptimizeLevel = -1;
        /// <summary>Export format: "" = compiler default; "json" | "binary" (SLB) |
        /// "binary+json" (SLB main + .module.json debug copy, R15).</summary>
        public string Format = "";
        /// <summary>pack-modules: package root; "" = exe directory.</summary>
        public string DestPath = "";
        /// <summary>pack-modules: package config — Debug = slb + json, Release = slb only.</summary>
        public string PackConfig = "Debug";
        /// <summary>run-disk: SLDP debug server port (0 = off). Passed through to the
        /// C VM as `--debug-server=&lt;port&gt;` (DEBUG_PROTOCOL_DESIGN.md D-P3; consumed by
        /// the VSCode extension's DAP adapter).</summary>
        public int DebugServer = 0;
        public List<string> ProgramArgs = new();
    }

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

        // new: 原生工程/类脚手架（2026-10-18 自 Front CLI 迁入——CLI 三分后
        // Front 只保留 compile/export，`new` 归宿主）。在宿主 Options 解析之前
        // 拦截：`new` 有自己的文法（New\NewCommand.cs）。
        if (args.Length > 0 && args[0].Equals("new", StringComparison.OrdinalIgnoreCase))
            return NewCommand.Run(args.Skip(1).ToArray());

        // lsp: 内嵌 LSP 服务器（stdio JSON-RPC；VSCode 插件 P2 消费，
        // slang_vscode_plugin\07_language_server_lsp.md §2）。同样在 Options
        // 解析前拦截——LSP 模式接管 stdio，不走常规命令面。
        if (args.Length > 0 && args[0].Equals("lsp", StringComparison.OrdinalIgnoreCase))
            return LspServer.Run(args.Skip(1).ToArray());

        // lsp-compile: LSP 专用诊断编译子命令（新进程一次编译 + 结构化 JSON 到
        // stdout；由 slang lsp 每轮 spawn 自身调用，规避 Front 进程内重入残留）。
        if (args.Length > 0 && args[0].Equals("lsp-compile", StringComparison.OrdinalIgnoreCase))
            return LspCompileCommand.Run(args.Skip(1).ToArray());

        var opts = ParseArgs(args);
        if (opts == null)
            return 1;
        if (opts.Help || opts.Command.Length == 0)
        {
            PrintHelp();
            return 0;
        }

        return opts.Command switch
        {
            "compile" => RunCompile(opts),
            "run" => RunProject(opts),
            "run-disk" => RunDisk(opts),
            "info" => RunInfo(opts),
            "version" => RunVersion(opts),
            "pack-modules" => PackModulesCommand.Run(opts.DestPath, opts.PackConfig),
            "pack-docs" => PackDocsCommand.Run(opts.DestPath),
            _ => PrintHelp(),
        };
    }

    // ==== commands ====

    // compile: Front in-process compile. Export three states via --export-mode
    // (default output = disk export to the configured directory).
    static int RunCompile(Options opts)
    {
        var mode = opts.ExportModeSet ? opts.ExportMode : EExportMode.OutputDir;
        var result = FrontendService.Compile(opts.ProjectPath, mode, opts.OptimizeLevel, opts.Format);
        if (!result.Success)
            return 1;
        if (mode == EExportMode.Memory)
        {
            Console.WriteLine($"Package SLB built in memory ({result.PackageBytes!.Length} bytes, uncompressed), baseDir: {result.ExportDir}");
            if (result.PackageJson != null)
                Console.WriteLine($"Package JSON built in memory ({result.PackageJson.Length} chars; json-family format)");
        }
        else
        {
            Console.WriteLine($"Exported SLB: {result.ModuleSlbPath}");
            if (result.ModuleJsonPath != null)
                Console.WriteLine($"Exported JSON debug copy: {result.ModuleJsonPath}");
        }
        Console.WriteLine("Compile completed.");
        return 0;
    }

    // run: Front compile + C VM. Three-state handoff (--export-mode):
    // - memory (default): uncompressed SLB bytes -> C VM memory entry (no disk IO)
    // - output / temp: disk export -> C VM runs the exported module from disk
    //   (slb path preferred; --debug-server and friends apply, same as run-disk)
    static int RunProject(Options opts)
    {
        string? repoRoot = GetRepoRoot();
        var mode = opts.ExportModeSet ? opts.ExportMode : EExportMode.Memory;

        // Step 1: compile with the Front (disk export for output/temp,
        // in-memory SLB bytes for memory)
        var result = FrontendService.Compile(opts.ProjectPath, mode, opts.OptimizeLevel, opts.Format);
        if (!result.Success)
            return 1;

        Console.WriteLine($"=== C VM run ({(mode == EExportMode.Memory ? "in-memory" : mode == EExportMode.TempDir ? "temp-dir" : "output-dir")}) ===");
        Console.WriteLine($"BaseDir: {result.ExportDir}");

        // Step 2: locate the C VM DLL
        var cvm = CvmBackend.Locate(repoRoot, opts.CvmConfig);
        if (cvm == null)
        {
            Console.WriteLine("csimple_lang_dll.dll not found (neither <app dir>\\bin\\ nor a csimple_lang build tree).");
            Console.WriteLine("Build the C VM first: powershell scripts\\build-vm-win.ps1 -Config " + opts.CvmConfig);
            return 4;
        }
        Console.WriteLine($"DLL: {Path.Combine(cvm.BinDir, "csimple_lang_dll.dll")} ({cvm.Config})");

        // Step 3: C VM test cases use relative paths (e.g. Sqlite Resources/),
        // so switch to the project directory before entering the VM,
        // matching the classic CSimpleVMTest host behaviour.
        var projectDir = Path.GetDirectoryName(Path.GetFullPath(opts.ProjectPath));
        if (Directory.Exists(projectDir))
            Environment.CurrentDirectory = projectDir;

        // Step 4: hand the package to the VM
        int exitCode;
        if (mode == EExportMode.Memory)
        {
            // 状态三：SLB 字节（不压缩）直传内存入口
            if (result.PackageBytes == null)
            {
                Console.WriteLine("In-memory package bytes missing (Export phase skipped).");
                return 1;
            }
            int flags = 0;
            if (opts.NoBanner) flags |= CvmInterop.FlagNoBanner;
            if (opts.DebugVm) flags |= CvmInterop.FlagDebug;
            if (opts.ForceRun) flags |= CvmInterop.FlagForceRun;
            if (opts.StrictPlugins) flags |= CvmInterop.FlagStrictPlugins;
            if (opts.Test) flags |= CvmInterop.FlagTest;

            Console.WriteLine($"SLB package: {result.PackageBytes.Length} bytes (binary in-memory chain, uncompressed)");
            exitCode = cvm.RunInMemoryBinary(result.PackageBytes, result.ExportDir, flags, opts.ProgramArgs);
        }
        else
        {
            // 状态一/二：磁盘导出 -> C VM 从落盘产物运行（slb 优先直读；
            // format=binary 无 json 落盘时同样成立），走经典 CLI 路径
            var modulePath = result.ModuleSlbPath ?? result.ModuleJsonPath;
            if (modulePath == null || !File.Exists(modulePath))
            {
                Console.WriteLine($"Exported module package not found: {modulePath}");
                return 1;
            }

            var cliArgs = new List<string> { "run", modulePath };
            if (opts.Test) cliArgs.Add("-test");
            if (opts.NoBanner) cliArgs.Add("--no-banner");
            if (opts.ForceRun) cliArgs.Add("--force-run");
            if (opts.DebugVm) cliArgs.Add("--debug");
            if (opts.StrictPlugins) cliArgs.Add("--strict-plugins");
            if (opts.DebugServer > 0) cliArgs.Add($"--debug-server={opts.DebugServer}");
            if (opts.ProgramArgs.Count > 0)
            {
                cliArgs.Add("--");
                cliArgs.AddRange(opts.ProgramArgs);
            }

            Console.WriteLine("csimple_lang " + string.Join(' ', cliArgs));
            exitCode = cvm.RunCli(cliArgs);
        }
        if (exitCode != 0)
            Console.WriteLine($"C VM run failed, exit code: {exitCode}");
        else
            Console.WriteLine("Compile + C VM run completed.");
        return exitCode;
    }

    // run-disk: classic path, run an already exported module.json via cli_main
    static int RunDisk(Options opts)
    {
        string? repoRoot = GetRepoRoot();
        var cvm = CvmBackend.Locate(repoRoot, opts.CvmConfig);
        if (cvm == null)
        {
            Console.WriteLine("csimple_lang_dll.dll not found. Build the C VM first.");
            return 4;
        }

        var cliArgs = new List<string> { "run", opts.ModuleJsonPath };
        if (opts.Test) cliArgs.Add("-test");
        if (opts.NoBanner) cliArgs.Add("--no-banner");
        if (opts.ForceRun) cliArgs.Add("--force-run");
        if (opts.DebugVm) cliArgs.Add("--debug");
        if (opts.StrictPlugins) cliArgs.Add("--strict-plugins");
        if (opts.DebugServer > 0) cliArgs.Add($"--debug-server={opts.DebugServer}");
        if (opts.ProgramArgs.Count > 0)
        {
            cliArgs.Add("--");
            cliArgs.AddRange(opts.ProgramArgs);
        }

        Console.WriteLine("=== C VM run (disk) ===");
        Console.WriteLine("csimple_lang " + string.Join(' ', cliArgs));
        return cvm.RunCli(cliArgs);
    }

    // info: show module metadata via the C VM info command
    static int RunInfo(Options opts)
    {
        string? repoRoot = GetRepoRoot();
        var cvm = CvmBackend.Locate(repoRoot, opts.CvmConfig);
        if (cvm == null)
        {
            Console.WriteLine("csimple_lang_dll.dll not found. Build the C VM first.");
            return 4;
        }
        var cliArgs = new List<string> { "info", opts.ModuleJsonPath };
        if (opts.NoBanner) cliArgs.Add("--no-banner");
        return cvm.RunCli(cliArgs);
    }

    static int RunVersion(Options opts)
    {
        string? repoRoot = GetRepoRoot();
        var cvm = CvmBackend.Locate(repoRoot, opts.CvmConfig);
        Console.WriteLine("SlangAllInOne (FrontEnd + C VM in one host)");
        Console.WriteLine("  Frontend: SimpleLanguage Front Compiler v" + SimpleLanguage.Project.CommandExecutor.VersionString);
        if (cvm != null)
        {
            Console.WriteLine("  Backend:  csimple_lang ({0}, {1})", cvm.Config, cvm.BinDir);
        }
        else
        {
            Console.WriteLine("  Backend:  csimple_lang DLL not found (build it to enable run commands)");
        }
        return 0;
    }

    // ==== arg parsing ====

    static Options? ParseArgs(string[] args)
    {
        var opts = new Options();
        int i = 0;

        // command
        if (args.Length == 0 || args[0].StartsWith('-'))
        {
            if (args.Length > 0 && (args[0] == "-h" || args[0] == "--help" || args[0] == "/?"))
            {
                opts.Help = true;
                return opts;
            }
            if (args.Length == 0)
            {
                PrintHelp();
                return null;
            }
        }
        else
        {
            opts.Command = args[0].ToLowerInvariant();
            i = 1;
        }

        for (; i < args.Length; i++)
        {
            var a = args[i];

            // "--" and everything after: program args (Project._inputArgs)
            if (a == "--")
            {
                for (i = i + 1; i < args.Length; i++)
                    opts.ProgramArgs.Add(args[i]);
                break;
            }

            if ((a == "-p" || a == "--project") && i + 1 < args.Length)
            {
                opts.ProjectPath = args[++i];
            }
            else if (opts.Command.Length > 0 && opts.ModuleJsonPath.Length == 0 && !a.StartsWith('-'))
            {
                // first bare positional: project path (compile/run) or module.json path (run-disk/info)
                if (opts.Command == "run-disk" || opts.Command == "info")
                    opts.ModuleJsonPath = a;
                else
                    opts.ProjectPath = a;
            }
            else if ((a == "-t" || a == "--test"))
            {
                opts.Test = true;
            }
            else if (a == "--export-mode" && i + 1 < args.Length)
            {
                // 导出三态（前后端联合接口）：output|temp|memory
                //（compile 缺省 output、run 缺省 memory；显式指定后两命令同值）
                var m = ParseExportMode(args[++i]);
                if (m == null)
                    return null;
                opts.ExportMode = m.Value;
                opts.ExportModeSet = true;
            }
            else if (a == "--no-banner")
            {
                opts.NoBanner = true;
            }
            else if (a == "--force-run")
            {
                opts.ForceRun = true;
            }
            else if (a == "--debug")
            {
                opts.DebugVm = true;
            }
            else if (a == "--strict-plugins")
            {
                opts.StrictPlugins = true;
            }
            else if (a.StartsWith("--debug-server=", StringComparison.Ordinal))
            {
                // SLDP debug server port (run-disk only; equal-sign form, mirrors the C VM CLI)
                var ps = a.Substring("--debug-server=".Length);
                if (!int.TryParse(ps, out var port) || port < 1 || port > 65535)
                {
                    Console.WriteLine($"Invalid debug server port: {ps} (expected 1..65535)");
                    return null;
                }
                opts.DebugServer = port;
            }
            else if (a == "--cvm" && i + 1 < args.Length)
            {
                opts.CvmConfig = args[++i];
            }
            else if (a == "--format" && i + 1 < args.Length)
            {
                var f = args[++i];
                // 同义归一：json+binary == binary+json（与 Front ExportLangManager 一致）
                if (string.Equals(f, "json+binary", StringComparison.OrdinalIgnoreCase))
                    f = "binary+json";
                if (!string.Equals(f, "json", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(f, "binary", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(f, "binary+json", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"Unknown format: {f} (expected json|binary|binary+json)");
                    return null;
                }
                opts.Format = f.ToLowerInvariant();
            }
            else if (a == "--dest" && i + 1 < args.Length)
            {
                opts.DestPath = args[++i];
            }
            else if (a == "--config" && i + 1 < args.Length)
            {
                var c = args[++i];
                if (!string.Equals(c, "Debug", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(c, "Release", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"Unknown config: {c} (expected Debug|Release)");
                    return null;
                }
                opts.PackConfig = char.ToUpperInvariant(c[0]) + c.Substring(1).ToLowerInvariant();
            }
            else if (a.Length == 3 && a[0] == '-' && (a[1] == 'O' || a[1] == 'o') && a[2] >= '0' && a[2] <= '3')
            {
                opts.OptimizeLevel = a[2] - '0';
            }
            else if (a == "-h" || a == "--help" || a == "/?")
            {
                opts.Help = true;
                return opts;
            }
            else if (opts.ProgramArgs.Count == 0 && opts.Command != "compile" && opts.Command != "run"
                     && !a.StartsWith('-'))
            {
                // bare positional after the first one on run-disk/info: ignore policy
                if (opts.ModuleJsonPath.Length > 0)
                    opts.ProgramArgs.Add(a);
            }
            else
            {
                Console.WriteLine($"Unknown option: {a}");
                PrintHelp();
                return null;
            }
        }

        if (opts.Command == "compile" || opts.Command == "run")
        {
            if (string.IsNullOrWhiteSpace(opts.ProjectPath))
            {
                Console.WriteLine("Missing project path. Use: slang {0} <projectPath> -p <path>", opts.Command);
                return null;
            }
        }
        else if (opts.Command == "run-disk" || opts.Command == "info")
        {
            if (string.IsNullOrWhiteSpace(opts.ModuleJsonPath))
            {
                Console.WriteLine("Missing module.json path. Use: slang {0} <module.json>", opts.Command);
                return null;
            }
            if (!File.Exists(opts.ModuleJsonPath))
            {
                Console.WriteLine($"Module package not found: {opts.ModuleJsonPath}");
                return null;
            }
        }

        return opts;
    }

    internal static string? GetRepoRoot()
    {
        // SlangAllInOne lives directly under the workspace root; walk up from
        // the output dir until we see the csimple_lang source tree. Returns
        // null when the app runs outside the repo (packaged layout: the C VM
        // runtime then comes from <app dir>\bin\, see CvmBackend.Locate).
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "csimple_lang", "CMakeLists.txt")))
                return dir.FullName;
            dir = dir.Parent!;
        }
        return null;
    }

    /// <summary>--export-mode 取值解析：output|temp|memory（大小写不敏感）；
    /// 非法值返回 null（调用方报错退出）。</summary>
    static EExportMode? ParseExportMode(string value)
    {
        var key = (value ?? string.Empty).Trim().ToLowerInvariant();
        switch (key)
        {
            case "output":
            case "outputdir":
                return EExportMode.OutputDir;
            case "temp":
            case "tempdir":
                return EExportMode.TempDir;
            case "memory":
            case "in-memory":
                return EExportMode.Memory;
            default:
                Console.WriteLine($"Unknown export mode: {value} (expected output|temp|memory)");
                return null;
        }
    }

    static int PrintHelp()
    {
        Console.WriteLine(@"
Usage: slang <command> [options]

Commands:
  compile <project>         Compile a project with the Front (in-process).
                             Export target per --export-mode (default output =
                             the configured export directory).
  run <project>             Compile + run on the C VM. Handoff is picked by
                             --export-mode: memory (default, no disk write,
                             uncompressed SLB straight to the VM), output
                             (export then run from disk) or temp (export to
                             <cwd>\_temp\<module>\ then run from there).
  run-disk <module.json>    Run an exported module.json via the C VM (classic).
  info <module.json>        Show module metadata via the C VM.
  version                   Show Front/Backend versions.
  new <project|class> ...   原生脚手架（2026-10-18 自 Front CLI 迁入，
                             Front 只保留 compile/export）:
                              slang new project MyApp   (Name.sp/.jsonc/.sl/.md
                               成套落盘，UTF-8 BOM，含 guide)
                              slang new project -p <dir> MyApp
                              slang new class MyClass   (.sl + jsonc 登记)
  lsp [--stdio]              Start the embedded LSP 3.17 server over stdio
                             (diagnostics push + symbol completion; consumed
                             by the Slang VSCode extension, engine=lsp).
  pack-modules              Compile the stdlib (Core -> Std -> Math, slb +
   [--dest <dir>]             json debug copy) and pack it into <dest>\out\
   [--config Debug|Release]   export\ mirroring the repo layout so package
                              references resolve unchanged. Debug keeps
                              .module.json + .slb; Release keeps only the
                              mandatory .slb (+ math_lib.dll). Default dest =
                              exe directory. Runs automatically on dotnet
                              publish (official release packaging).
  pack-docs                  Copy the user-facing FrontEnd markdown docs
   [--dest <dir>]             (syntax / lib / project / log / plugins + entry
                              docs + per-library notes) into <dest>\md\.
                              Runs automatically on dotnet publish; skips the
                              internal md\ai\ and md\vm\ trees.
  help                      Show this help.

Options:
  -p, --project <path>      Project path (directory or .sp file)
  -t, --test                Pass -test to the C VM (placeholder in the C VM
                             today: the entry switch is not implemented yet,
                             both disk and memory paths run the _main_ entry)
  -O0..-O3                  Front optimize level
  --export-mode <output|temp|memory>
                             Export target (three states, front-to-back
                             handoff): output = the configured export
                             directory (compile default); temp = <cwd>\_temp\
                             <module>\ temporary folder; memory = no disk
                             write, the uncompressed SLB binary stays in RAM
                             and goes straight to the C VM (run default)
  --format <json|binary|binary+json>
                             Export format: binary = SLB only; json /
                             binary+json = SLB (always written) + .module.json
                             debug copy (R15)
  --no-banner               Suppress banners
  --force-run               Skip C VM hard platform checks
  --debug                   C VM debug mode (verbose tracing)
  --strict-plugins          Treat plugin disable as a C VM error
  --debug-server=<port>     run-disk / run --export-mode output|temp: start
                             the SLDP debug server on 127.0.0.1:<port>
                             (NDJSON over TCP; the VSCode extension's DAP
                             adapter connects to it)
  --cvm <Debug|Release>     C VM build tree to use (default Debug)
  -- [args...]              Everything after -- goes to Project._inputArgs

Examples:
  slang new project MyApp
  slang run SlangAllInOne\SLangCore\test\BaseTest\ProjectTest
  slang run SlangAllInOne\SLangCore\test\ExpendTest\ProjectTest -t
  slang run MyProject --export-mode temp
  slang run MyProject -- arg1 arg2
  slang compile MyProject
  slang compile MyProject --export-mode memory
  slang compile MyProject --format binary+json
  slang pack-modules --config Release
  slang run-disk SlangAllInOne\out\export\ProjectTest\ProjectTest.module.json
  slang info SlangAllInOne\out\export\ProjectTest\ProjectTest.module.json");
        return 0;
    }
}
