using System.IO.Compression;
using System.Text.Json;
using SimpleLanguage.Project;

namespace SlangAllInOne.Spm;

/// <summary>
/// slang spm：包管理器（宿主 CLI 子命令，Main 前置拦截，不进 KnownCommands）。
///
/// 安装布局统一为 modules\&lt;包名&gt;\（包目录名 = 包名；目录内为
/// &lt;包名&gt;.module.slb|json 等产物，装载链 ProjectReferenceModuleLoader
/// Strategy 4 / C VM ④ 回退均支持该目录布局）。
///
/// 子命令：
///   slang spm install &lt;url|包名&gt; [--registry &lt;url&gt;] [-g]
///       - url（http/https）：下载 zip 解压装进目标 modules\；
///       - 包名：① 工程 modules\&lt;名&gt; 已装提示 → ② 语言目录 modules\&lt;名&gt;
///         命中则移动（move）到工程 modules\ → ③ registry 拼 &lt;registry&gt;/&lt;名&gt;.zip
///         下载安装；全部落空报错；
///       - -g/--global：装进语言目录（slang.exe 同级）modules\，全局共享。
///   slang spm list     列出工程 + 语言目录两处 modules\ 的包。
///   slang spm remove &lt;包名&gt; [-g]   删除（-g 删语言目录侧）。
///   slang spm config registry [&lt;url&gt;]   查看/设置全局 registry
///       （落盘 &lt;lang&gt;\spm.json；工程 jsonc "spm"."registry" 段与 --registry
///       参数优先级更高）。
///
/// zip 布局自动探测（解压到临时目录后归一为 modules\&lt;包名&gt;\）：
///   ① 单一顶层目录 → 该目录即包目录（包名 = 目录名）；
///   ② 根含 *.module.slb|json → 根即包内容（包名 = 产物名剥后缀）；
///   ③ 多目录时找 &lt;目录&gt;\&lt;目录名&gt;.module.slb|json 命中者；
///   ④ 兜底：期望包名 / zip 文件名。
///
/// 装完只提示把包名加进 jsonc references（不自动改写工程文件）。
/// </summary>
internal static class SpmCommand
{
    // ==== 入口 ====

    public static int Run(string[] args)
    {
        if (args.Length == 0)
        {
            return PrintUsage();
        }
        var cmd = args[0].ToLowerInvariant();
        var rest = args.Skip(1).ToArray();
        return cmd switch
        {
            "install" or "add" => RunInstall(rest),
            "list" or "ls" => RunList(rest),
            "remove" or "uninstall" => RunRemove(rest),
            "config" => RunConfig(rest),
            _ => PrintUsage(),
        };
    }

    static int PrintUsage()
    {
        Console.WriteLine(@"
spm - SLang package manager

Usage:
  slang spm install <url|package> [--registry <url>] [-g]
      url      : download a .zip and extract into modules\<package>\
      package  : 1) already in project modules\ -> skip
                 2) found in <lang>\modules\     -> moved into project modules\
                 3) download <registry>/<package>.zip
      -g       : install into <lang>\modules\ (global, shared by all projects)
  slang spm list
      List packages in both project modules\ and <lang>\modules\.
  slang spm remove <package> [-g]
      Delete the package directory (-g = language-wide side).
  slang spm config registry [<url>]
      Show / set the global registry (stored in <lang>\spm.json).

Registry resolution (install by name): --registry > project jsonc
""spm"".""registry"" > <lang>\spm.json.");
        return 2;
    }

    // ==== install ====

    static int RunInstall(string[] args)
    {
        string target = "";
        string? registryOpt = null;
        bool global = false;

        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--registry") && i + 1 < args.Length)
                registryOpt = args[++i];
            else if (a == "-g" || a == "--global")
                global = true;
            else if (target.Length == 0)
                target = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return PrintUsage();
            }
        }
        if (target.Length == 0)
        {
            return PrintUsage();
        }

        string langModules = LangModulesDir;
        string projectDir = global ? "" : (FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory);
        string modulesDir = global ? langModules : Path.Combine(projectDir, "modules");

        // 形态一：URL 直接下载 zip
        if (target.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return InstallFromUrl(target, modulesDir, expectedName: null);
        }

        // 形态二：按名安装（工程已装 → lang 移动 → registry 下载）
        if (!IsValidName(target))
        {
            Console.WriteLine($"[FAIL] 无效包名: \"{target}\"（应为 ^[A-Za-z_][A-Za-z0-9_]*$；或给 http(s):// URL）");
            return 2;
        }

        if (global)
        {
            if (Directory.Exists(Path.Combine(langModules, target)))
            {
                Console.WriteLine($"[OK]  {target} 已全局安装: {Path.Combine(langModules, target)}");
                return 0;
            }
        }
        else if (Directory.Exists(Path.Combine(modulesDir, target)))
        {
            Console.WriteLine($"[OK]  {target} 已安装于工程 modules\\: {Path.Combine(modulesDir, target)}");
            PromptAddReference(target);
            return 0;
        }

        // ② 语言目录命中 → 移动到工程（仅项目模式；全局模式落空走 registry）
        if (!global && Directory.Exists(Path.Combine(langModules, target)))
        {
            Directory.CreateDirectory(modulesDir);
            string dest = Path.Combine(modulesDir, target);
            TryMoveOrCopy(Path.Combine(langModules, target), dest);
            Console.WriteLine($"[OK]  {target}: moved <lang>\\modules\\{target} -> {dest}");
            PromptAddReference(target);
            return 0;
        }

        // ③ registry 下载
        string? registry = registryOpt ?? ProjectRegistry(projectDir) ?? GlobalRegistry();
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine($"[FAIL] 包 \"{target}\" 未找到（工程 modules\\ 与 <lang>\\modules\\ 均无），且未配置 registry。");
            Console.WriteLine("       配置方式: slang spm config registry <url>  或工程 jsonc 加 \"spm\": { \"registry\": \"...\" }");
            return 1;
        }
        string url = registry.TrimEnd('/') + "/" + target + ".zip";
        return InstallFromUrl(url, modulesDir, expectedName: target);
    }

    /// <summary>下载 zip → 临时目录解压 → 布局探测 → 归一装进 modules\&lt;包名&gt;\。</summary>
    static int InstallFromUrl(string url, string modulesDir, string? expectedName)
    {
        Console.WriteLine($"Downloading: {url}");
        byte[] zipBytes;
        try
        {
            using var http = new HttpClient();
            http.Timeout = TimeSpan.FromMinutes(5);
            zipBytes = http.GetByteArrayAsync(url).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] 下载失败: {ex.Message}");
            return 1;
        }

        string tempRoot = Path.Combine(Path.GetTempPath(), "slang-spm-" + Guid.NewGuid().ToString("N"));
        string tempZip = tempRoot + ".zip";
        try
        {
            File.WriteAllBytes(tempZip, zipBytes);
            ZipFile.ExtractToDirectory(tempZip, tempRoot, overwriteFiles: true);

            var (pkgName, srcDir) = DetectPackageLayout(tempRoot, expectedName, url);
            if (!IsValidName(pkgName))
            {
                Console.WriteLine($"[FAIL] 推断的包名无效: \"{pkgName}\"（zip 布局异常；包目录/产物名应为 ^[A-Za-z_][A-Za-z0-9_]*$）");
                return 1;
            }
            string dest = Path.Combine(modulesDir, pkgName);
            if (Directory.Exists(dest))
            {
                Console.WriteLine($"[OK]  {pkgName} 已安装: {dest}（如需重装请先 slang spm remove {pkgName}）");
                PromptAddReference(pkgName);
                return 0;
            }
            Directory.CreateDirectory(modulesDir);
            TryMoveOrCopy(srcDir, dest);
            Console.WriteLine($"[OK]  {pkgName}: installed -> {dest}");
            PromptAddReference(pkgName);
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] 安装失败: {ex.Message}");
            return 1;
        }
        finally
        {
            try { Directory.Delete(tempRoot, true); } catch { }
            try { File.Delete(tempZip); } catch { }
        }
    }

    /// <summary>zip 布局探测：见类头注释 ①-④。</summary>
    static (string name, string srcDir) DetectPackageLayout(string extractRoot, string? expectedName, string url)
    {
        var dirs = Directory.GetDirectories(extractRoot);
        var files = Directory.GetFiles(extractRoot);

        // ① 单一顶层目录 → 该目录即包目录
        if (dirs.Length == 1 && files.Length == 0)
        {
            return (Path.GetFileName(dirs[0]), dirs[0]);
        }

        // ② 根含模块产物 → 根即包内容
        var mod = files.FirstOrDefault(f => f.EndsWith(".module.slb", StringComparison.OrdinalIgnoreCase))
                  ?? files.FirstOrDefault(f => f.EndsWith(".module.json", StringComparison.OrdinalIgnoreCase));
        if (mod != null)
        {
            return (ModuleNameFromFile(Path.GetFileName(mod)), extractRoot);
        }

        // ③ 多目录：找 <目录>\<目录名>.module.slb|json 命中者
        foreach (var d in dirs)
        {
            var dn = Path.GetFileName(d);
            if (File.Exists(Path.Combine(d, dn + ".module.slb"))
                || File.Exists(Path.Combine(d, dn + ".module.json")))
            {
                return (dn, d);
            }
        }

        // ④ 兜底：期望包名 / zip 文件名
        var fallback = expectedName ?? ZipNameFromUrl(url);
        return (fallback, extractRoot);
    }

    // ==== list ====

    static int RunList(string[] args)
    {
        if (args.Length > 0)
        {
            return PrintUsage();
        }
        string projectDir = FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory;
        ListPackages("project", Path.Combine(projectDir, "modules"));
        ListPackages("lang", LangModulesDir);
        return 0;
    }

    static void ListPackages(string label, string modulesDir)
    {
        Console.WriteLine($"{label} modules: {modulesDir}");
        if (!Directory.Exists(modulesDir))
        {
            Console.WriteLine("  (not created)");
            return;
        }
        var pkgs = Directory.GetDirectories(modulesDir)
            .Select(Path.GetFileName)
            .Where(n => !string.IsNullOrEmpty(n))
            .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (pkgs.Count == 0)
        {
            Console.WriteLine("  (empty)");
            return;
        }
        foreach (var p in pkgs)
        {
            Console.WriteLine($"  {p}");
        }
    }

    // ==== remove ====

    static int RunRemove(string[] args)
    {
        string name = "";
        bool global = false;
        foreach (var a in args)
        {
            if (a == "-g" || a == "--global")
                global = true;
            else if (name.Length == 0)
                name = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return PrintUsage();
            }
        }
        if (name.Length == 0)
        {
            return PrintUsage();
        }

        string projectDir = FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory;
        string modulesDir = global ? LangModulesDir : Path.Combine(projectDir, "modules");
        string target = Path.Combine(modulesDir, name);
        if (!Directory.Exists(target))
        {
            Console.WriteLine($"[FAIL] 未安装: {target}");
            Console.WriteLine(global ? "       （slang spm list 查看全部包）" : "       （-g 可删语言目录侧的全局包；slang spm list 查看全部）");
            return 1;
        }
        Directory.Delete(target, recursive: true);
        Console.WriteLine($"[OK]  removed: {target}");
        return 0;
    }

    // ==== config ====

    static int RunConfig(string[] args)
    {
        if (args.Length == 0 || !args[0].Equals("registry", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("Usage: slang spm config registry [<url>]");
            return 2;
        }
        if (args.Length == 1)
        {
            var reg = GlobalRegistry();
            Console.WriteLine(string.IsNullOrWhiteSpace(reg)
                ? $"registry: (not set)  ->  {GlobalConfigPath}"
                : $"registry: {reg}");
            return 0;
        }
        if (args.Length > 2)
        {
            Console.WriteLine("Usage: slang spm config registry [<url>]");
            return 2;
        }
        var cfg = LoadGlobalConfig();
        cfg.Registry = args[1].Trim();
        SaveGlobalConfig(cfg);
        Console.WriteLine($"[OK]  registry saved -> {GlobalConfigPath}");
        Console.WriteLine($"      {cfg.Registry}");
        return 0;
    }

    // ==== helpers ====

    /// <summary>语言目录（slang.exe 所在目录）下的 modules\。</summary>
    static string LangModulesDir => Path.Combine(AppContext.BaseDirectory, "modules");

    static string GlobalConfigPath => Path.Combine(AppContext.BaseDirectory, "spm.json");

    sealed class GlobalConfig
    {
        public string Registry { get; set; } = "";
    }

    static GlobalConfig LoadGlobalConfig()
    {
        try
        {
            if (File.Exists(GlobalConfigPath))
            {
                return JsonSerializer.Deserialize<GlobalConfig>(File.ReadAllText(GlobalConfigPath)) ?? new GlobalConfig();
            }
        }
        catch { }
        return new GlobalConfig();
    }

    static void SaveGlobalConfig(GlobalConfig cfg)
    {
        File.WriteAllText(GlobalConfigPath, JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = true }));
    }

    static string? GlobalRegistry()
    {
        var reg = LoadGlobalConfig().Registry;
        return string.IsNullOrWhiteSpace(reg) ? null : reg;
    }

    /// <summary>工程 jsonc "spm"."registry" 段（复用 Front 解析器）。</summary>
    static string? ProjectRegistry(string projectDir)
    {
        try
        {
            var jsonc = FindProjectJsonc(projectDir);
            if (jsonc == null)
            {
                return null;
            }
            var cfg = ProjectJsoncLoader.FromJsonc(File.ReadAllText(jsonc));
            return string.IsNullOrWhiteSpace(cfg?.Spm?.Registry) ? null : cfg.Spm.Registry.Trim();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// 工程目录定位：从 startDir 逐级上溯找 .jsonc / .sp 锚点所在目录
    /// （用户语义：解压到"运行的当前工程目录（.jsonc 的目录）"）。
    /// </summary>
    static string? FindProjectDir(string startDir)
    {
        var dir = startDir;
        while (!string.IsNullOrEmpty(dir))
        {
            if (FindProjectJsonc(dir) != null || Directory.GetFiles(dir, "*.sp").Length > 0)
            {
                return dir;
            }
            dir = Path.GetDirectoryName(dir);
        }
        return null;
    }

    /// <summary>目录内工程 jsonc（排除 plugin.jsonc 清单；与 NewCommand 同规则）。</summary>
    static string? FindProjectJsonc(string dir)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
        {
            return null;
        }
        var jsoncs = Directory.GetFiles(dir, "*.jsonc")
            .Where(p => !string.Equals(Path.GetFileNameWithoutExtension(p), "plugin", StringComparison.OrdinalIgnoreCase))
            .ToList();
        return jsoncs.Count > 0 ? Path.GetFullPath(jsoncs[0]) : null;
    }

    /// <summary>移动目录；跨卷 IO 失败时回落 拷贝+删源。</summary>
    static void TryMoveOrCopy(string srcDir, string destDir)
    {
        try
        {
            Directory.Move(srcDir, destDir);
        }
        catch (IOException)
        {
            CopyDirectory(srcDir, destDir);
            try { Directory.Delete(srcDir, true); } catch { }
        }
    }

    static void CopyDirectory(string srcDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (var f in Directory.GetFiles(srcDir))
        {
            File.Copy(f, Path.Combine(destDir, Path.GetFileName(f)), overwrite: true);
        }
        foreach (var d in Directory.GetDirectories(srcDir))
        {
            CopyDirectory(d, Path.Combine(destDir, Path.GetFileName(d)));
        }
    }

    /// <summary>产物文件名 → 模块名（Foo.module.slb / Foo.module.json → Foo）。</summary>
    static string ModuleNameFromFile(string fileName)
    {
        var name = fileName;
        if (name.EndsWith(".module.json", StringComparison.OrdinalIgnoreCase))
            name = name.Substring(0, name.Length - ".module.json".Length);
        else if (name.EndsWith(".module.slb", StringComparison.OrdinalIgnoreCase))
            name = name.Substring(0, name.Length - ".module.slb".Length);
        return name;
    }

    /// <summary>URL 尾段剥 .zip 作为兜底包名。</summary>
    static string ZipNameFromUrl(string url)
    {
        try
        {
            var name = url.Split('?', '#')[0].TrimEnd('/').Split('/')[^1];
            if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                name = name.Substring(0, name.Length - 4);
            }
            return name.Length > 0 ? name : "package";
        }
        catch
        {
            return "package";
        }
    }

    static bool IsValidName(string name)
    {
        if (string.IsNullOrEmpty(name))
            return false;
        if (!char.IsAsciiLetter(name[0]) && name[0] != '_')
            return false;
        for (int i = 1; i < name.Length; i++)
        {
            char c = name[i];
            if (!char.IsAsciiLetterOrDigit(c) && c != '_')
                return false;
        }
        return true;
    }

    /// <summary>装完提示：把包加进 jsonc references（不自动改写工程文件）。</summary>
    static void PromptAddReference(string pkgName)
    {
        Console.WriteLine($"      提示: 在工程 jsonc 的 references 里登记后即可 import {pkgName}: 使用，");
        Console.WriteLine($"            \"references\": [ {{ \"path\": \"./modules/{pkgName}\" }} ]");
    }
}
