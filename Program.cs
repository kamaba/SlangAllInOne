using System.Text;
using SlangAllInOne.Backend;
using SlangAllInOne.FrontEnd;

namespace SlangAllInOne;

/// <summary>
/// SlangAllInOne: unified FrontEnd (SimpleLanguage compiler) + Backend (C VM)
/// host CLI. The headline feature is `run`: compile a project in-process, keep
/// the exported SLIR package JSON in memory, and hand it straight to the C VM
/// memory entry -- no module.json write/read round trip.
/// </summary>
internal static class Program
{
    private sealed class Options
    {
        public string Command = "";
        public string ProjectPath = "";
        public string ModuleJsonPath = "";
        public bool Test = false;
        public bool InMemory = false;
        public bool NoBanner = false;
        public bool ForceRun = false;
        public bool DebugVm = false;
        public bool StrictPlugins = false;
        public bool Help = false;
        public string CvmConfig = "Debug";
        public int OptimizeLevel = -1;
        public List<string> ProgramArgs = new();
    }

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;

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
            "run" => RunInMemory(opts),
            "run-disk" => RunDisk(opts),
            "info" => RunInfo(opts),
            "version" => RunVersion(opts),
            _ => PrintHelp(),
        };
    }

    // ==== commands ====

    // compile: Front in-process compile (disk export unless --in-memory)
    static int RunCompile(Options opts)
    {
        var result = FrontendService.Compile(opts.ProjectPath, opts.InMemory, opts.OptimizeLevel);
        if (!result.Success)
            return 1;
        if (opts.InMemory)
            Console.WriteLine($"Package JSON built in memory ({result.PackageJson!.Length} chars), baseDir: {result.ExportDir}");
        Console.WriteLine("Compile completed.");
        return 0;
    }

    // run: Front in-memory compile -> C VM memory entry (no module.json IO)
    static int RunInMemory(Options opts)
    {
        string repoRoot = GetRepoRoot();

        // Step 1: compile with the Front, keeping the package JSON in memory
        var result = FrontendService.Compile(opts.ProjectPath, inMemory: true, opts.OptimizeLevel);
        if (!result.Success)
            return 1;

        Console.WriteLine($"=== C VM run (in-memory) ===");
        Console.WriteLine($"BaseDir: {result.ExportDir}");

        // Step 2: locate the C VM DLL
        var cvm = CvmBackend.Locate(repoRoot, opts.CvmConfig);
        if (cvm == null)
        {
            Console.WriteLine($"csimple_lang_dll.dll not found under {repoRoot}\\csimple_lang\\build\\{{{opts.CvmConfig}}}\\bin.");
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

        // Step 4: hand the package JSON straight to the VM
        int flags = 0;
        if (opts.NoBanner) flags |= CvmInterop.FlagNoBanner;
        if (opts.DebugVm) flags |= CvmInterop.FlagDebug;
        if (opts.ForceRun) flags |= CvmInterop.FlagForceRun;
        if (opts.StrictPlugins) flags |= CvmInterop.FlagStrictPlugins;
        if (opts.Test) flags |= CvmInterop.FlagTest;

        int exitCode = cvm.RunInMemory(result.PackageJson!, result.ExportDir, flags, opts.ProgramArgs);
        if (exitCode != 0)
            Console.WriteLine($"C VM run failed, exit code: {exitCode}");
        else
            Console.WriteLine("Compile (in-memory) + C VM run completed.");
        return exitCode;
    }

    // run-disk: classic path, run an already exported module.json via cli_main
    static int RunDisk(Options opts)
    {
        string repoRoot = GetRepoRoot();
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
        string repoRoot = GetRepoRoot();
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
        string repoRoot = GetRepoRoot();
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
            else if (a == "--in-memory")
            {
                opts.InMemory = true;
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
            else if (a == "--cvm" && i + 1 < args.Length)
            {
                opts.CvmConfig = args[++i];
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

    static string GetRepoRoot()
    {
        // SlangAllInOne lives directly under the workspace root; walk up from
        // the output dir until we see the csimple_lang source tree.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "csimple_lang", "CMakeLists.txt")))
                return dir.FullName;
            dir = dir.Parent!;
        }
        throw new DirectoryNotFoundException("Cannot locate the workspace root (csimple_lang/CMakeLists.txt).");
    }

    static int PrintHelp()
    {
        Console.WriteLine(@"
Usage: slang <command> [options]

Commands:
  compile <project>         Compile a project with the Front (in-process).
                             Disk export by default; --in-memory keeps the
                             package JSON in RAM.
  run <project>             Compile in memory + run on the C VM directly
                             (Front IR -> memory hand-off -> VM, no module.json).
  run-disk <module.json>    Run an exported module.json via the C VM (classic).
  info <module.json>        Show module metadata via the C VM.
  version                   Show Front/Backend versions.
  help                      Show this help.

Options:
  -p, --project <path>      Project path (directory or .sp file)
  -t, --test                Pass -test to the C VM (placeholder in the C VM
                             today: the entry switch is not implemented yet,
                             both disk and memory paths run the _main_ entry)
  -O0..-O3                  Front optimize level
  --in-memory               compile: keep the package JSON in memory
  --no-banner               Suppress banners
  --force-run               Skip C VM hard platform checks
  --debug                   C VM debug mode (verbose tracing)
  --strict-plugins          Treat plugin disable as a C VM error
  --cvm <Debug|Release>     C VM build tree to use (default Debug)
  -- [args...]              Everything after -- goes to Project._inputArgs

Examples:
  slang run simple_language\test\BaseTest\ProjectTest
  slang run simple_language\test\ExpendTest\ProjectTest -t
  slang run MyProject -- arg1 arg2
  slang compile MyProject
  slang compile MyProject --in-memory
  slang run-disk simple_language\out\export\ProjectTest\ProjectTest.module.json
  slang info simple_language\out\export\ProjectTest\ProjectTest.module.json");
        return 0;
    }
}
