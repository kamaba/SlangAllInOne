using System.Diagnostics;

namespace SlangAllInOne.Pack;

/// <summary>
/// pack-modules：编译标准库三件套（Core → Math → Std）并把产物打进发布目录，
/// 制作过程全部内置在工程里 —— dotnet publish 时由 csproj 的 PackStdModules
/// target 调起刚发布的 exe 执行本命令，无需任何手工脚本。
///
/// 编译模型：每模块一个干净子进程（本 exe 自举 compile），与 scripts\compile-
/// stdlib.ps1 及 CompileStdlib 驱动（core/math/std 预设）完全同构；导出参数
/// --format binary --export-json（R15：slb 主产物 + json 调试副本）；成功判据
/// 对齐 compile-stdlib.ps1 —— exit 0 且 slb mtime fresh（Front 编译失败时
/// 退出码仍可能为 0，mtime 才是硬证据）。
///
/// 包内布局为平铺单目录 &lt;dest&gt;\lib\（slb / json / math_lib.dll 直排，
/// 不再镜像仓库 out\export\ 多层结构；2026-10-18 目录更名 module\ → lib\，
/// 设计记录 md/project/package-layout.md——lib\ = 系统自带标准库，
/// modules\ 留给未来 spm.exe 包管理器，plugins\ 存插件）。模块内嵌的深层
/// 相对路径由 C VM 装载器回退兼容：moduleReferences（"../Core"）回退
/// &lt;dir&gt;\Core.module.json
/// （json 或 slb 任一存在即尝试，SLB 优先重定向自动改指同名 .slb）；FFI
/// dllImports（"../../out/export/Math/math_lib.dll"）第三重回退按文件名在
/// pkg_dir 内直查（lib\math_lib.dll）。
///
/// 包内容（config 决定）：
///   Debug   = &lt;M&gt;.module.slb + &lt;M&gt;.module.json（json 调试副本：C VM
///             --debug/--force-json 排障 + Front 编译用户工程时的引用装载）
///   Release = 仅必须的 &lt;M&gt;.module.slb + math_lib.dll（运行包；Math 的
///             FFI 原生库，vmDllImports 预载与静态绑定都需要）
/// </summary>
internal static class PackModulesCommand
{
    /// <summary>标准库三件套；顺序即编译顺序（Math/Std 引用 Core，Front 的引用
    /// 装载 Strategy 1/2 读磁盘上的 Core 产物，故 Core 必须先行）。
    /// 2026-10-17 仓库重组：库源码自 simple_language\source\Front\Lib\ 迁至
    /// SlangAllInOne\SLangCore\Lib\（export.outputDir → SlangAllInOne\out\export）。</summary>
    private static readonly (string Name, string Project)[] StdlibProjects =
    {
        ("Core", @"SlangAllInOne\SLangCore\Lib\Core\Core"),
        ("Math", @"SlangAllInOne\SLangCore\Lib\Math\Math"),
        ("Std",  @"SlangAllInOne\SLangCore\Lib\Std\Std"),
    };

    /// <param name="destDir">包根目录；空 = exe 所在目录（publish 集成默认，
    /// 发布产物就在 exe 旁边）。</param>
    /// <param name="config">Debug = slb + json 调试副本；Release = 仅必须的 slb。</param>
    public static int Run(string? destDir, string config)
    {
        string? repoRoot = Program.GetRepoRoot();
        if (repoRoot == null)
        {
            Console.WriteLine("pack-modules must run inside the repo (standard library sources not found).");
            return 1;
        }

        string destRoot = string.IsNullOrWhiteSpace(destDir)
            ? AppContext.BaseDirectory
            : Path.GetFullPath(destDir);
        bool includeJson = string.Equals(config, "Debug", StringComparison.OrdinalIgnoreCase);

        Console.WriteLine($"=== pack-modules (config: {config}) ===");
        Console.WriteLine($"Repo:    {repoRoot}");
        Console.WriteLine($"Package: {destRoot}");

        string exportRoot = Path.Combine(repoRoot, "SlangAllInOne", "out", "export");
        string selfExe = Environment.ProcessPath
            ?? Path.Combine(AppContext.BaseDirectory, "slang.exe");

        foreach (var (name, projectRel) in StdlibProjects)
        {
            string projectPath = Path.Combine(repoRoot, projectRel);
            // 工程路径是 Front 语义（会补 .sp/.jsonc 解析），裸条目不一定存在
            if (!Directory.Exists(projectPath) && !File.Exists(projectPath)
                && !File.Exists(projectPath + ".sp") && !File.Exists(projectPath + ".jsonc"))
            {
                Console.WriteLine($"[FAIL] {name}: standard library project not found: {projectPath}");
                return 1;
            }

            // 子进程编译；CWD 与 compile-stdlib.ps1 一致（SlangAllInOne\，库源树根）。
            string slbPath = Path.Combine(exportRoot, name, $"{name}.module.slb");
            var start = DateTime.Now;
            Console.WriteLine($"--- {name}: compile {projectRel} -O3 --format binary --export-json");
            int exit = RunChild(selfExe,
                $"compile \"{projectPath}\" -O3 --format binary --export-json --no-banner",
                Path.Combine(repoRoot, "SlangAllInOne"));
            bool fresh = File.Exists(slbPath) && File.GetLastWriteTime(slbPath) >= start.AddSeconds(-5);
            if (exit != 0 || !fresh)
            {
                Console.WriteLine($"[FAIL] {name}: compile failed (exit={exit}, slb rewritten={fresh})");
                return 1;
            }

            // 打包：slb 必带；Debug 附加 json 调试副本；Math 附加 math_lib.dll。
            var sources = new List<string> { slbPath };
            if (includeJson)
                sources.Add(Path.Combine(exportRoot, name, $"{name}.module.json"));
            if (name == "Math")
                sources.Add(Path.Combine(exportRoot, name, "math_lib.dll"));

            // 平铺单目录：所有模块产物直排 <dest>\lib\（2026-10-18 更名），
            // 无按模块子目录。lib\ = 系统自带标准库（官方库直查目录）。
            string destModuleDir = Path.Combine(destRoot, "lib");
            Directory.CreateDirectory(destModuleDir);
            foreach (var src in sources)
            {
                if (!File.Exists(src))
                {
                    Console.WriteLine($"[FAIL] {name}: expected artifact missing: {src}");
                    return 1;
                }
                File.Copy(src, Path.Combine(destModuleDir, Path.GetFileName(src)), overwrite: true);
            }
            Console.WriteLine($"[OK]   {name} -> lib\\: {string.Join(", ", sources.Select(Path.GetFileName))}");
        }

        Console.WriteLine($"Standard library packed into {Path.Combine(destRoot, "lib")}");
        Console.WriteLine(includeJson
            ? "Debug package: .module.slb + .module.json (debug copies) per module."
            : "Release package: mandatory .module.slb (+ math_lib.dll) only.");
        return 0;
    }

    static int RunChild(string exe, string arguments, string workingDir)
    {
        var psi = new ProcessStartInfo(exe, arguments) { WorkingDirectory = workingDir };
        using var p = Process.Start(psi);
        if (p == null)
        {
            Console.WriteLine($"[FAIL] failed to start child process: {exe}");
            return -1;
        }
        p.WaitForExit();
        return p.ExitCode;
    }
}
