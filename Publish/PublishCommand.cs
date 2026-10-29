using System.Text;
using System.Text.Json;
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
///    cli_app_payload.h）。
///
/// 发布目录（布局规则 2026-10-22 定稿）：&lt;outputDir&gt;\&lt;debug|release&gt;\
/// 两型并存（配置子目录每次发布清空重建，publish 根保留其它配置）；子目录内：
/// exe + slb + lib\ + plugins\——lib\ 平铺平台无关的 *.module.slb，原生库按
/// 平台细分落 lib\&lt;windows|linux|macos|android|ios&gt;\（.dll/.so/.dylib/.a），
/// 一个发布目录可承载多平台运行体，运行时按当前平台查找连接库
/// （C VM sl_platform_dir_name / sl_preload_associated_dlls / FFI 候选链，
/// 平铺 lib\ 为兼容位）。
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
        /// <summary>CLI --gui 覆盖（null = 走 jsonc publish.gui；--gui 仅强制开）。</summary>
        public bool? Gui = null;
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
        bool gui = opts.Gui ?? pub.Gui;

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

        /* 配置子目录（2026-10-22 发布规则）：publish 根下分 debug\ / release\
         * 两型并存——同一工程可同时保有 Debug（可调试）/ Release（发布）两套
         * 产物；仅本配置子目录清空重建，publish 根与另一配置不动。 */
        publishDir = Path.Combine(publishDir, cvmConfig.ToLowerInvariant());

        string moduleName = ResolveModuleName();

        if (Directory.Exists(publishDir))
        {
            Directory.Delete(publishDir, recursive: true);
        }
        Directory.CreateDirectory(publishDir);

        Console.WriteLine($"=== slang publish (mode: {mode}, config: {cvmConfig.ToLowerInvariant()}) ===");
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
                    if (gui)
                    {
                        PatchSubsystemWindows(appExe);
                        Console.WriteLine($"[OK]  gui:  PE subsystem Console -> Windows (no cmd window; see publish-guide.md §5)");
                    }

                    /* C VM exe 唯一动态依赖（delay-load）：按布局规则落
                     * lib\<平台>\（2026-10-22 平台细分）——运行期 exe 经
                     * sl_preload_associated_dlls 按 <exe>\lib\<平台>\ 预装载
                     * 绑定（平铺 lib\ 为兼容位）。 */
                    string? binDir = Path.GetDirectoryName(cvmExe);
                    string sqlite = Path.Combine(binDir ?? "", "sqlite3.dll");
                    if (File.Exists(sqlite))
                    {
                        string destPlat = Path.Combine(publishDir, "lib", HostPlatformDir());
                        Directory.CreateDirectory(destPlat);
                        File.Copy(sqlite, Path.Combine(destPlat, "sqlite3.dll"), overwrite: true);
                        Console.WriteLine($"[OK]  lib:  {HostPlatformDir()}\\sqlite3.dll");
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

        /* Step 6: 引用模块 stage（2026-10-22 发布规则）：主模块的
         * moduleReferences 里非系统库引用（如 ExpendTest -> SLangServer）
         * 原样相对路径在发布目录必然错位——装载期静默跳过会让引用方
         * 全线失效（ServerP1Test 实录）。按 CSimpleVMTest 同款把导出
         * 产物 stage 进发布目录，C VM 装载器回退链 <pkg>\<name>.module.json
         * basename 直查即命中（slb 优先重定向）。 */
        if (result.ModuleJsonPath != null && File.Exists(result.ModuleJsonPath))
        {
            StageReferencedModules(result.ModuleJsonPath, publishDir, repoRoot);
        }

        /* Step 7: 插件产物（Front 导出已按 plugin\<id>\ 布局落到模块
         * export 目录；整目录拷贝，应用 exe 相对自身目录解析）。 */
        if (!string.IsNullOrEmpty(result.ExportDir))
        {
            string pluginsSrc = Path.Combine(result.ExportDir, "plugin");
            if (Directory.Exists(pluginsSrc) && Directory.EnumerateFileSystemEntries(pluginsSrc).Any())
            {
                CopyDirectory(pluginsSrc, Path.Combine(publishDir, "plugin"));
                Console.WriteLine("[OK]  plugin:   copied from module export (plugin\\)");
            }
        }

        /* Step 8: 工程 modules\ 整目录拷贝（2026-10-29 spm 规则）：工程
         * 经 slang spm install 装的包（modules\<名>\<名>.module.slb|json）
         * 随发布包携带，C VM 装载器 ④ 回退链 <dir>/modules 直查命中
         * （Front 导出的引用相对路径也按同布局解析）。 */
        {
            string modulesSrc = Path.Combine(projectDir, "modules");
            if (Directory.Exists(modulesSrc) && Directory.EnumerateFileSystemEntries(modulesSrc).Any())
            {
                CopyDirectory(modulesSrc, Path.Combine(publishDir, "modules"));
                Console.WriteLine("[OK]  modules:  copied from project (modules\\)");
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

    /// <summary>publish gui:true：把应用 exe 的 PE Subsystem 字段从
    /// Console(IMAGE_SUBSYSTEM_WINDOWS_CUI=3) 补丁为 Windows(GUI=2)——发布时
    /// 一次写入，C VM 模板不动。入口 RVA 不变：Windows 加载器只跳
    /// AddressOfEntryPoint（_mainCRTStartup→main），子系统字段只决定进程创建
    /// 时是否自动分配控制台——双击/启动即无 cmd 窗口。C 侧 app 模式配套见
    /// cli_app_payload.c（无控制台跳过收尾 pause；从终端启动 AttachConsole
    /// 挂回父控制台看日志）。非 3（已 GUI / 异常值）不动。</summary>
    static void PatchSubsystemWindows(string exePath)
    {
        using var fs = new FileStream(exePath, FileMode.Open, FileAccess.ReadWrite);
        using var br = new BinaryReader(fs);
        /* DOS header e_lfanew @0x3C -> PE 头；Subsystem @PE+0x5C（u16 LE） */
        fs.Seek(0x3C, SeekOrigin.Begin);
        int peOff = br.ReadInt32();
        if (peOff <= 0 || peOff + 0x5C + 2 > fs.Length)
        {
            return;
        }
        fs.Seek(peOff + 0x5C, SeekOrigin.Begin);
        if (br.ReadUInt16() != 3)
        {
            return;
        }
        fs.Seek(peOff + 0x5C, SeekOrigin.Begin); /* ReadUInt16 已前移 2 字节，写回前重定位 */
        fs.WriteByte(2);
    }

    /// <summary>拷官方标准库到 &lt;publish&gt;\lib\（slb 平铺）+ 原生库到
    /// lib\&lt;平台&gt;\（2026-10-22 平台细分）。模块产物来源链：
    /// ① 包布局 &lt;app dir&gt;\lib\&lt;n&gt;.module.slb（官方库直查目录）
    /// ② dev 树 SlangAllInOne\out\export\&lt;n&gt;\&lt;n&gt;.module.slb。
    /// libs 空 = Core/Std/Math 全量；含 Math 附带 math_lib.dll（平台位）。
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
                    string destPlat = Path.Combine(destLib, HostPlatformDir());
                    Directory.CreateDirectory(destPlat);
                    File.Copy(mathDll, Path.Combine(destPlat, "math_lib.dll"), overwrite: true);
                    Console.WriteLine($"[OK]  lib:  {HostPlatformDir()}\\math_lib.dll");
                }
                else
                {
                    Console.WriteLine("[WARN] lib: math_lib.dll not found (needed when the app uses Math native functions)");
                }
            }
        }
        return 0;
    }

    /// <summary>宿主平台目录名（布局规则 2026-10-22 平台细分）：原生库按平台
    /// 分目录落 lib\&lt;平台&gt;\，与 C VM sl_platform_dir_name 同名约定
    /// （windows / linux / macos / android / ios）。发布命令在哪个平台宿主
    /// 上运行就落哪个平台位（跨平台产物可后续手动补位，查找链按运行平台
    /// 取对应子目录）。</summary>
    static string HostPlatformDir()
    {
        if (OperatingSystem.IsWindows()) return "windows";
        if (OperatingSystem.IsAndroid()) return "android";
        if (OperatingSystem.IsIOS() || OperatingSystem.IsMacCatalyst()) return "ios";
        if (OperatingSystem.IsMacOS()) return "macos";
        if (OperatingSystem.IsLinux()) return "linux";
        return "windows"; /* 兜底：exe 模式当前仅 Windows */
    }

    /// <summary>官方库集合：发布产物 lib\ 平铺直查（官方库直查链），无需 stage。</summary>
    static readonly HashSet<string> SystemModuleNames = new(StringComparer.OrdinalIgnoreCase)
    { "Core", "Std", "Math" };

    /// <summary>解析主模块 moduleReferences，把非系统库引用（如 ExpendTest ->
    /// SLangServer、WebUITest -&gt; SLangWebUI）的导出产物 stage 成
    /// &lt;publish&gt;\&lt;名&gt;.module.{slb,json} **平铺**——发布目录深度与开发
    /// 导出树不同，内嵌相对路径必然错位（装载期静默跳过 → 引用方全线失效）；
    /// C VM 引用回退链（sl_load_references ② basename 直查）恰好按
    /// &lt;主包目录&gt;\&lt;名&gt;.module.json 平铺命中（SLB 优先重定向自动改指同名
    /// .slb）；载荷 exe 的主包目录 = exe 目录（cli_app_payload base_dir）。
    /// 导出目录解析序：标准导出树两处候选（须实含 *.module.* 产物，陈旧空
    /// 目录不再静默命中）→ moduleReferences.path 字段（相对主 module.json
    /// 目录解析，Front 导出时即被引用模块导出产物的权威指针）。被引用模块
    /// 导出目录里的原生库（webui_lib.dll 等）按布局规则落 lib\&lt;平台&gt;\
    /// ——C VM 两条链均命中：FFI sl_ffi_lib_load 发布布局回退
    /// （&lt;exe&gt;\lib\&lt;平台&gt;\）与 vm_sys_ffi_static_lib_register 的
    /// pkg_dir/&lt;平台&gt;/basename。未找到仅提示不阻断。</summary>
    static void StageReferencedModules(string moduleJsonPath, string publishDir, string? repoRoot)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(moduleJsonPath));
            if (!doc.RootElement.TryGetProperty("moduleReferences", out var refsEl))
                return;
            string baseDir = Path.GetDirectoryName(Path.GetFullPath(moduleJsonPath)) ?? ".";
            foreach (var r in refsEl.EnumerateArray())
            {
                if (!r.TryGetProperty("name", out var nameEl))
                    continue;
                string name = nameEl.GetString() ?? "";
                if (name.Length == 0 || SystemModuleNames.Contains(name) || repoRoot == null)
                    continue;
                string[] exportRoots =
                {
                    Path.Combine(repoRoot, "SlangAllInOne", "out", "export", name),
                    Path.Combine(repoRoot, "SlangAllInOne", "SLangCore", "out", "export", name),
                };
                /* 候选目录须实含 *.module.* 产物：out\export\ 下的陈旧空壳目录
                 * （仅剩 Logs\ 残留）命中即静默零拷贝，是发布缺件事故根源。 */
                string? srcDir = exportRoots.FirstOrDefault(d =>
                    Directory.Exists(d) && Directory.GetFiles(d, "*.module.*").Length > 0);
                /* 回退：引用 path 字段（相对主 module.json 目录）指向的权威导出树。 */
                if (srcDir == null && r.TryGetProperty("path", out var pathEl))
                {
                    string? rp = pathEl.GetString();
                    if (!string.IsNullOrWhiteSpace(rp))
                    {
                        string full = Path.GetFullPath(Path.Combine(baseDir, rp));
                        string? d = Path.GetDirectoryName(full);
                        if (d != null && Directory.Exists(d)
                            && Directory.GetFiles(d, "*.module.*").Length > 0)
                        {
                            srcDir = d;
                        }
                    }
                }
                if (srcDir == null)
                {
                    Console.WriteLine($"[WARN] reference: module '{name}' export artifacts not found, skipped (the app needs it if it is referenced)");
                    continue;
                }
                /* 平铺 stage：主包目录直下 <名>.module.slb / .module.json——
                 * 对齐 C VM 引用回退链的 basename 直查形态。 */
                bool any = false;
                foreach (string f in Directory.GetFiles(srcDir, "*.module.*"))
                {
                    File.Copy(f, Path.Combine(publishDir, Path.GetFileName(f)), overwrite: true);
                    any = true;
                }
                /* 原生库 stage（布局规则平台细分）：webui_lib.dll 等按宿主平台
                 * 落 lib\<平台>\，C VM FFI 查找链（sl_ffi_lib_load 发布布局
                 * 回退）按 basename 命中。 */
                string platDir = Path.Combine(publishDir, "lib", HostPlatformDir());
                foreach (string ext in new[] { "*.dll", "*.so", "*.dylib" })
                {
                    foreach (string f in Directory.GetFiles(srcDir, ext))
                    {
                        Directory.CreateDirectory(platDir);
                        File.Copy(f, Path.Combine(platDir, Path.GetFileName(f)), overwrite: true);
                        Console.WriteLine($"[OK]  reference: lib\\{HostPlatformDir()}\\{Path.GetFileName(f)}");
                    }
                }
                string refPlugins = Path.Combine(srcDir, "plugin");
                if (Directory.Exists(refPlugins))
                    CopyDirectory(refPlugins, Path.Combine(publishDir, "plugin"));
                if (any)
                    Console.WriteLine($"[OK]  reference: {name}.module.* (staged flat into publish)");
                else
                    Console.WriteLine($"[WARN] reference: module '{name}' has no *.module.* artifacts in {srcDir}");
            }
        }
        catch (Exception ex)
        {
            /* stage 失败不阻断主流程（C VM 装载期按回退链解析，可诊断） */
            Console.WriteLine("[WARN] reference staging failed: " + ex.Message);
        }
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

    /// <summary>Math 原生库来源链（包布局 lib\windows\ 平台位（布局标准
    /// 2026-10-25）优先 → 平铺 lib\ 兼容位 → dev out\export\Math\）。</summary>
    static string? FindMathNativeDll(string? repoRoot)
    {
        string packaged = Path.Combine(AppContext.BaseDirectory, "lib", HostPlatformDir(), "math_lib.dll");
        if (File.Exists(packaged))
        {
            return packaged;
        }
        packaged = Path.Combine(AppContext.BaseDirectory, "lib", "math_lib.dll");
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
