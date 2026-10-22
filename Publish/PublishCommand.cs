using System.Text;
using SimpleLanguage.ExportLanguage;
using SimpleLanguage.Project;
using SlangAllInOne.Backend;
using SlangAllInOne.FrontEnd;

namespace SlangAllInOne.Publish;

/// <summary>
/// slang publish：工程级发布命令（类比 dotnet publish），配置源 = jsonc
/// 顶层 "publish" 段（ProjectConfig.PublishSection，Front 解析承载），
/// CLI 旗标可覆盖。产物两形态（md/project/publish-guide.md）：
///
///  - slb：&lt;Module&gt;.module.slb 模块包，`slang run &lt;path&gt;.slb` 启动；
///  - exe：&lt;Module&gt;.exe 应用（载荷附着式）= csimple_lang.exe 副本 +
///    尾部附着的 SLB 载荷（"SLVMAPP1" trailer，C VM main() 自检执行，
///    cli_app_payload.h）。exe 模式附带 sqlite3.dll + lib\（官方标准库，
///    引用按 &lt;exe&gt;\lib 官方直查解析）。
///
/// 流程：Front 编译（--format binary+json，R15：slb 主产物 + json 调试
/// 副本，json 不进发布产物）→ 按 mode 组装发布目录（清空重建）。
/// </summary>
internal static class PublishCommand
{
    /// <summary>与 C 侧 cli_app_payload.h 的 SLVM_APP_PAYLOAD_MAGIC 一致。</summary>
    private static readonly byte[] AppPayloadMagic = Encoding.ASCII.GetBytes("SLVMAPP1");

    public sealed class Options
    {
        public string ProjectPath = "";
        /// <summary>CLI --mode 覆盖（exe|slb|both；"" = jsonc/缺省 both）。</summary>
        public string Mode = "";
        /// <summary>CLI --dest 覆盖（"" = jsonc publish.outputDir，相对 jsonc 目录）。</summary>
        public string DestPath = "";
        /// <summary>CLI --cvm 覆盖（"" = jsonc publish.config，缺省 Release）。</summary>
        public string CvmConfig = "";
        /// <summary>CLI --no-libs 覆盖（null = 走 jsonc includeLibs）。</summary>
        public bool? IncludeLibs = null;
        public int OptimizeLevel = -1;
    }

    public static int Run(Options opts)
    {
        string? repoRoot = Program.GetRepoRoot();

        /* Step 1: Front 编译（磁盘导出，R15 binary+json；json 副本留在
         * 工程 export 目录作调试对照，不进发布产物）。 */
        var result = FrontendService.Compile(opts.ProjectPath, EExportMode.OutputDir,
            opts.OptimizeLevel, "binary+json");
        if (!result.Success || result.ModuleSlbPath == null)
        {
            return 1;
        }

        /* Step 2: 读取 jsonc publish 段（Front 已在进程内解析）。 */
        var pub = ProjectManager.config?.Publish ?? new ProjectConfig.PublishSection();
        string? mode = NormalizeMode(string.IsNullOrWhiteSpace(opts.Mode) ? pub.Mode : opts.Mode);
        if (mode == null)
        {
            Console.WriteLine($"Unknown publish mode: '{(string.IsNullOrWhiteSpace(opts.Mode) ? pub.Mode : opts.Mode)}' (expected exe|slb|both)");
            return 1;
        }
        string cvmConfig = string.IsNullOrWhiteSpace(opts.CvmConfig) ? pub.Config : opts.CvmConfig;
        if (!string.Equals(cvmConfig, "Debug", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(cvmConfig, "Release", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"Unknown publish config: '{cvmConfig}' (expected Debug|Release)");
            return 1;
        }
        bool includeLibs = opts.IncludeLibs ?? pub.IncludeLibs;

        /* Step 3: 发布目录（jsonc 目录 = sp 所在目录；清空重建避免陈旧文件）。
         * 注意 ProjectManager.projectPath 语义 = 工程目录（ProjectCompile.
         * LoadProject L47），不是 .sp 文件路径——这里做双形态防御。 */
        string projectPathRaw = ProjectManager.projectPath;
        string projectDir = (projectPathRaw.EndsWith(".sp", StringComparison.OrdinalIgnoreCase)
            ? Path.GetDirectoryName(Path.GetFullPath(projectPathRaw))
            : Path.GetFullPath(projectPathRaw))
            ?? Environment.CurrentDirectory;
        string publishDir = string.IsNullOrWhiteSpace(opts.DestPath)
            ? Path.GetFullPath(Path.IsPathRooted(pub.OutputDir) ? pub.OutputDir : Path.Combine(projectDir, pub.OutputDir))
            : Path.GetFullPath(opts.DestPath);

        string moduleName = ResolveModuleName();

        if (Directory.Exists(publishDir))
        {
            Directory.Delete(publishDir, recursive: true);
        }
        Directory.CreateDirectory(publishDir);

        Console.WriteLine($"=== slang publish (mode: {mode}) ===");
        Console.WriteLine($"Project:  {opts.ProjectPath}");
        Console.WriteLine($"Module:   {moduleName}");
        Console.WriteLine($"Output:   {publishDir}");

        int failures = 0;

        /* Step 4: slb 产物（`slang run <path>.slb` 启动）。 */
        if (mode == "slb" || mode == "both")
        {
            string destSlb = Path.Combine(publishDir, moduleName + ".module.slb");
            File.Copy(result.ModuleSlbPath, destSlb, overwrite: true);
            Console.WriteLine($"[OK]  slb:  {moduleName}.module.slb  (start: slang run \"{destSlb}\")");
        }

        /* Step 5: exe 产物（载荷附着式应用）。 */
        if (mode == "exe" || mode == "both")
        {
            if (!OperatingSystem.IsWindows())
            {
                Console.WriteLine("[FAIL] exe mode is Windows-only for now (csimple_lang.exe template; Linux pending).");
                failures++;
            }
            else
            {
                string? cvmExe = LocateCvmExe(repoRoot, cvmConfig);
                if (cvmExe == null)
                {
                    Console.WriteLine("[FAIL] csimple_lang.exe not found (neither <app dir>\\bin\\ nor a csimple_lang build tree).");
                    Console.WriteLine("       Build the C VM first: powershell scripts\\build-vm-win.ps1 -Config " + cvmConfig);
                    failures++;
                }
                else
                {
                    string appExe = Path.Combine(publishDir, moduleName + ".exe");
                    AttachPayload(cvmExe, appExe, File.ReadAllBytes(result.ModuleSlbPath));
                    Console.WriteLine($"[OK]  exe:  {moduleName}.exe  (template: {Path.GetFileName(Path.GetDirectoryName(cvmExe))}\\{Path.GetFileName(cvmExe)}, payload attached)");

                    /* C VM exe 唯一动态依赖：sqlite3.dll（其余静态链）。 */
                    string? binDir = Path.GetDirectoryName(cvmExe);
                    string sqlite = Path.Combine(binDir ?? "", "sqlite3.dll");
                    if (File.Exists(sqlite))
                    {
                        File.Copy(sqlite, Path.Combine(publishDir, "sqlite3.dll"), overwrite: true);
                        Console.WriteLine("[OK]  dep:  sqlite3.dll");
                    }
                    else
                    {
                        Console.WriteLine("[WARN] sqlite3.dll not found next to the C VM exe; the published app needs it at runtime.");
                    }

                    /* 官方标准库 lib\（引用 Core/Std/Math 时必须；
                     * 应用 exe 运行时按 <exe>\lib 官方直查解析引用）。 */
                    if (includeLibs)
                    {
                        failures += CopyLibs(repoRoot, publishDir, pub.Libs);
                    }
                }
            }
        }

        /* Step 6: 插件产物（Front 导出已按 plugins\<id>\ 布局落到模块
         * export 目录；整目录拷贝，应用 exe 相对自身目录解析）。 */
        if (!string.IsNullOrEmpty(result.ExportDir))
        {
            string pluginsSrc = Path.Combine(result.ExportDir, "plugins");
            if (Directory.Exists(pluginsSrc) && Directory.EnumerateFileSystemEntries(pluginsSrc).Any())
            {
                CopyDirectory(pluginsSrc, Path.Combine(publishDir, "plugins"));
                Console.WriteLine("[OK]  plugins:  copied from module export (plugins\\)");
            }
        }

        if (failures == 0)
        {
            Console.WriteLine($"Publish completed -> {publishDir}");
            return 0;
        }
        Console.WriteLine($"Publish finished with {failures} failure(s).");
        return 1;
    }

    // ==== helpers ====

    /// <summary>mode 归一（大小写不敏感）；非法值返回 null（调用方报错）。</summary>
    static string? NormalizeMode(string raw)
    {
        return raw?.Trim().ToLowerInvariant() switch
        {
            "exe" => "exe",
            "slb" => "slb",
            "both" or "" => "both",
            _ => null,
        };
    }

    /// <summary>产物命名：export.moduleName &gt; project.name &gt; sp 文件名。</summary>
    static string ResolveModuleName()
    {
        var cfg = ProjectManager.config;
        string name = cfg?.Export?.ModuleName ?? string.Empty;
        if (string.IsNullOrWhiteSpace(name))
        {
            name = cfg?.Project?.Name ?? string.Empty;
        }
        if (string.IsNullOrWhiteSpace(name))
        {
            name = Path.GetFileNameWithoutExtension(ProjectManager.projectPath);
        }
        return name;
    }

    /// <summary>定位 C VM exe 模板：发布包布局（&lt;app dir&gt;\bin\csimple_lang.exe，
    /// PackCvmRuntime 携带）优先，dev 树（build\{config}\bin，配置不中回落
    /// 另一配置）次之。</summary>
    static string? LocateCvmExe(string? repoRoot, string config)
    {
        string packaged = Path.Combine(AppContext.BaseDirectory, "bin", "csimple_lang.exe");
        if (File.Exists(packaged))
        {
            return packaged;
        }
        if (repoRoot == null)
        {
            return null;
        }

        var candidates = string.Equals(config, "Release", StringComparison.OrdinalIgnoreCase)
            ? new[] { "Release", "Debug" }
            : new[] { "Debug", "Release" };
        foreach (var cfg in candidates)
        {
            string exe = Path.GetFullPath(Path.Combine(repoRoot, "csimple_lang", "build", cfg, "bin", "csimple_lang.exe"));
            if (File.Exists(exe))
            {
                return exe;
            }
        }
        return null;
    }

    /// <summary>载荷附着：csimple_lang.exe 副本 + SLB 字节 + u64 小端长度 +
    /// "SLVMAPP1" magic（与 C 侧 cli_app_payload.c 的 trailer 解析逐字节镜像）。</summary>
    static void AttachPayload(string templateExe, string destExe, byte[] slbBytes)
    {
        using var input = File.OpenRead(templateExe);
        using var output = new FileStream(destExe, FileMode.Create, FileAccess.Write);
        input.CopyTo(output);
        output.Write(slbBytes, 0, slbBytes.Length);
        output.Write(BitConverter.GetBytes((ulong)slbBytes.Length), 0, 8);
        output.Write(AppPayloadMagic, 0, AppPayloadMagic.Length);
    }

    /// <summary>拷官方标准库到 &lt;publish&gt;\lib\。模块产物来源链：
    /// ① 包布局 &lt;app dir&gt;\lib\&lt;n&gt;.module.slb（官方库直查目录）
    /// ② dev 树 SlangAllInOne\out\export\&lt;n&gt;\&lt;n&gt;.module.slb。
    /// libs 空 = Core/Std/Math 全量；含 Math 附带 math_lib.dll。
    /// 返回失败计数（缺产物告警不中断——工程可能不引用该库）。</summary>
    static int CopyLibs(string? repoRoot, string publishDir, List<string> libs)
    {
        var names = (libs != null && libs.Count > 0)
            ? libs.Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n.Trim()).ToArray()
            : new[] { "Core", "Std", "Math" };

        string destLib = Path.Combine(publishDir, "lib");
        int missing = 0;

        foreach (var name in names)
        {
            string? src = FindModuleArtifact(repoRoot, name);
            if (src == null)
            {
                Console.WriteLine($"[WARN] lib: module '{name}' not found (skipped; build/pack it if the app references it)");
                missing++;
                continue;
            }

            Directory.CreateDirectory(destLib);
            File.Copy(src, Path.Combine(destLib, name + ".module.slb"), overwrite: true);
            Console.WriteLine($"[OK]  lib:  {name}.module.slb");

            if (string.Equals(name, "Math", StringComparison.OrdinalIgnoreCase))
            {
                string? mathDll = FindMathNativeDll(repoRoot);
                if (mathDll != null)
                {
                    File.Copy(mathDll, Path.Combine(destLib, "math_lib.dll"), overwrite: true);
                    Console.WriteLine("[OK]  lib:  math_lib.dll");
                }
                else
                {
                    Console.WriteLine("[WARN] lib: math_lib.dll not found (needed when the app uses Math native functions)");
                }
            }
        }
        return 0;
    }

    /// <summary>单模块 slb 产物来源链（包布局优先 → dev out\export）。</summary>
    static string? FindModuleArtifact(string? repoRoot, string name)
    {
        string packaged = Path.Combine(AppContext.BaseDirectory, "lib", name + ".module.slb");
        if (File.Exists(packaged))
        {
            return packaged;
        }
        if (repoRoot != null)
        {
            string dev = Path.GetFullPath(Path.Combine(repoRoot, "SlangAllInOne", "out", "export", name, name + ".module.slb"));
            if (File.Exists(dev))
            {
                return dev;
            }
        }
        return null;
    }

    /// <summary>Math 原生库来源链（包布局 → dev out\export\Math\）。</summary>
    static string? FindMathNativeDll(string? repoRoot)
    {
        string packaged = Path.Combine(AppContext.BaseDirectory, "lib", "math_lib.dll");
        if (File.Exists(packaged))
        {
            return packaged;
        }
        if (repoRoot != null)
        {
            string dev = Path.GetFullPath(Path.Combine(repoRoot, "SlangAllInOne", "out", "export", "Math", "math_lib.dll"));
            if (File.Exists(dev))
            {
                return dev;
            }
        }
        return null;
    }

    static void CopyDirectory(string srcDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (var file in Directory.EnumerateFiles(srcDir))
        {
            File.Copy(file, Path.Combine(destDir, Path.GetFileName(file)), overwrite: true);
        }
        foreach (var dir in Directory.EnumerateDirectories(srcDir))
        {
            CopyDirectory(dir, Path.Combine(destDir, Path.GetFileName(dir)));
        }
    }
}
