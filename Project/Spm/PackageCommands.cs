namespace Spm;

/// <summary>
/// 包命令（module 编译产物 → modules\&lt;名&gt;\）：
/// install / search / list / outdated / remove / config registry。
/// </summary>
internal static class PackageCommands
{
    // ==== install ====

    public static int RunInstall(string[] args)
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
                return Program.PrintUsage();
            }
        }
        if (target.Length == 0)
        {
            return Program.PrintUsage();
        }

        string langModules = SpmContext.LangModulesDir;
        string projectDir = global ? "" : (SpmContext.FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory);
        string modulesDir = global ? langModules : Path.Combine(projectDir, "modules");

        // 形态一：URL 直接下载 zip
        if (target.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            var r = ZipInstall.InstallPackageZip(target, modulesDir, expectedName: null, version: "", source: "url");
            if (r == null)
            {
                return 1;
            }
            if (!r.AlreadyInstalled)
            {
                Console.WriteLine($"[OK]  {r.Name}: installed -> {r.DestDir}");
            }
            PromptAddReference(r.Name);
            return 0;
        }

        // 形态二：按名安装（工程已装 → lang 移动 → 服务器查询下载）
        if (!ZipInstall.IsValidName(target))
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

        // ② 语言目录命中 → 移动到工程（仅项目模式；全局模式落空走服务器）
        if (!global && Directory.Exists(Path.Combine(langModules, target)))
        {
            Directory.CreateDirectory(modulesDir);
            string dest = Path.Combine(modulesDir, target);
            ZipInstall.TryMoveOrCopy(Path.Combine(langModules, target), dest);
            Console.WriteLine($"[OK]  {target}: moved <lang>\\modules\\{target} -> {dest}");
            PromptAddReference(target);
            return 0;
        }

        // ③ 服务器：registry 查元数据（API → 静态回落），下载产物链接或缺省 zip
        string? registry = SpmContext.ResolveRegistry(registryOpt, projectDir.Length > 0 ? projectDir : null);
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine($"[FAIL] 包 \"{target}\" 未找到（工程 modules\\ 与 <lang>\\modules\\ 均无），且未配置 registry。");
            Console.WriteLine("       配置方式: spm config registry <url>  或工程 jsonc 加 \"spm\": { \"registry\": \"...\" }");
            return 1;
        }

        var meta = RegistryClient.QueryPackage(registry, target);
        if (meta != null)
        {
            Console.WriteLine($"server: {meta.Name} {meta.Version}  ({meta.Source})");
            if (meta.Description.Length > 0)
            {
                Console.WriteLine($"        {meta.Description}");
            }
            string url = RegistryClient.ResolvePackageUrl(registry, meta, target);
            var r = ZipInstall.InstallPackageZip(url, modulesDir, expectedName: target, version: meta.Version, source: registry);
            if (r == null)
            {
                return 1;
            }
            if (!r.AlreadyInstalled)
            {
                Console.WriteLine($"[OK]  {r.Name}: installed -> {r.DestDir}");
            }
            PromptAddReference(r.Name);
            return 0;
        }

        // 静态兜底：registry 直接拼 <名>.zip（旧约定，服务器无元数据时）
        string fallbackUrl = registry.TrimEnd('/') + "/" + target + ".zip";
        Console.WriteLine($"server: no metadata for \"{target}\"; trying {fallbackUrl}");
        var r2 = ZipInstall.InstallPackageZip(fallbackUrl, modulesDir, expectedName: target, version: "", source: registry);
        if (r2 == null)
        {
            return 1;
        }
        if (!r2.AlreadyInstalled)
        {
            Console.WriteLine($"[OK]  {r2.Name}: installed -> {r2.DestDir}");
        }
        PromptAddReference(r2.Name);
        return 0;
    }

    // ==== search：通过名称查具体的包 ====

    public static int RunSearch(string[] args)
    {
        string? keyword = null;
        string? registryOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--registry") && i + 1 < args.Length)
                registryOpt = args[++i];
            else if (keyword == null)
                keyword = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return Program.PrintUsage();
            }
        }
        if (string.IsNullOrWhiteSpace(keyword))
        {
            return Program.PrintUsage();
        }

        string? registry = SpmContext.ResolveRegistry(registryOpt, null);
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine("[FAIL] 未配置 registry（spm search 需要服务器）。");
            Console.WriteLine("       配置方式: spm config registry <url>  或工程 jsonc 加 \"spm\": { \"registry\": \"...\" }");
            return 1;
        }

        // ① 精确命中优先
        var exact = RegistryClient.QueryPackage(registry, keyword);
        if (exact != null)
        {
            PrintPackage(exact);
            return 0;
        }

        // ② 全量索引过滤（名称/描述包含关键字）
        var hits = RegistryClient.SearchPackages(registry, keyword);
        if (hits == null)
        {
            Console.WriteLine($"[FAIL] 服务器无此包且索引不可达: {registry}");
            return 1;
        }
        if (hits.Count == 0)
        {
            Console.WriteLine($"no packages matched \"{keyword}\" (registry: {registry})");
            return 0;
        }
        Console.WriteLine($"{hits.Count} package(s) matched \"{keyword}\":");
        foreach (var p in hits.Take(30))
        {
            PrintPackage(p, indent: true);
        }
        return 0;
    }

    static void PrintPackage(RegistryClient.PackageMeta p, bool indent = false)
    {
        var pad = indent ? "  " : "";
        Console.WriteLine($"{pad}{p.Name}  {p.Version}");
        if (p.Description.Length > 0)
        {
            Console.WriteLine($"{pad}  {p.Description}");
        }
        Console.WriteLine($"{pad}  install: spm install {p.Name}");
    }

    // ==== list ====

    public static int RunList(string[] args)
    {
        if (args.Length > 0)
        {
            return Program.PrintUsage();
        }
        string projectDir = SpmContext.FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory;
        ListPackages("project", Path.Combine(projectDir, "modules"));
        ListPackages("lang", SpmContext.LangModulesDir);
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
            .Select(n => n!)
            .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (pkgs.Count == 0)
        {
            Console.WriteLine("  (empty)");
            return;
        }
        foreach (var p in pkgs)
        {
            var manifest = ZipInstall.ReadLocalManifest(Path.Combine(modulesDir, p));
            var ver = manifest != null && manifest.Version.Length > 0 ? manifest.Version : "?";
            Console.WriteLine($"  {p}  ({ver})");
        }
    }

    // ==== outdated：与服务器版本对比 ====

    public static int RunOutdated(string[] args)
    {
        string? registryOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--registry" && i + 1 < args.Length)
            {
                registryOpt = args[++i];
            }
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {args[i]}");
                return Program.PrintUsage();
            }
        }

        string projectDir = SpmContext.FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory;
        string? registry = SpmContext.ResolveRegistry(registryOpt, projectDir);
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine("[FAIL] 未配置 registry（spm outdated 需要服务器做版本对比）。");
            Console.WriteLine("       配置方式: spm config registry <url>  或工程 jsonc 加 \"spm\": { \"registry\": \"...\" }");
            return 1;
        }
        Console.WriteLine($"registry: {registry}");

        int rows = 0;
        int updatable = 0;
        foreach (var (label, modulesDir) in new[] { ("project", Path.Combine(projectDir, "modules")), ("lang", SpmContext.LangModulesDir) })
        {
            if (!Directory.Exists(modulesDir))
            {
                continue;
            }
            foreach (var dir in Directory.GetDirectories(modulesDir).OrderBy(d => d, StringComparer.OrdinalIgnoreCase))
            {
                var name = Path.GetFileName(dir);
                var manifest = ZipInstall.ReadLocalManifest(dir);
                string local = manifest?.Version.Length > 0 ? manifest.Version : "(unknown)";

                var meta = RegistryClient.QueryPackage(registry, name);
                string server = meta != null && meta.Version.Length > 0 ? meta.Version : "(not on server)";
                string status;
                if (meta == null || meta.Version.Length == 0)
                {
                    status = "-";
                }
                else if (CompareVersions(local, meta.Version) < 0)
                {
                    status = "可升级 -> spm install " + name;
                    updatable++;
                }
                else
                {
                    status = "up to date";
                }
                Console.WriteLine($"  [{label,-7}] {name,-24} local {local,-12} server {server,-12} {status}");
                rows++;
            }
        }
        if (rows == 0)
        {
            Console.WriteLine("  (no installed packages)");
            return 0;
        }
        Console.WriteLine(updatable > 0
            ? $"{updatable} package(s) can be updated (spm install <name> 重装即升级)"
            : "all packages up to date.");
        return 0;
    }

    /// <summary>语义化版本比较（a.b.c 数字逐段）；解析失败按字符串序（仅判不等）。</summary>
    static int CompareVersions(string a, string b)
    {
        if (TryParseVersion(a, out var va) && TryParseVersion(b, out var vb))
        {
            int c = va[0].CompareTo(vb[0]);
            if (c != 0) return c;
            c = va[1].CompareTo(vb[1]);
            if (c != 0) return c;
            return va[2].CompareTo(vb[2]);
        }
        return string.CompareOrdinal(a, b);
    }

    static bool TryParseVersion(string s, out int[] v)
    {
        v = new[] { 0, 0, 0 };
        if (string.IsNullOrWhiteSpace(s))
        {
            return false;
        }
        var parts = s.TrimStart('v', 'V').Split('-', '+')[0].Split('.');
        if (parts.Length == 0 || parts.Length > 3)
        {
            return false;
        }
        for (int i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i], out v[i]))
            {
                return false;
            }
        }
        return true;
    }

    // ==== remove ====

    public static int RunRemove(string[] args)
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
                return Program.PrintUsage();
            }
        }
        if (name.Length == 0)
        {
            return Program.PrintUsage();
        }

        string projectDir = SpmContext.FindProjectDir(Environment.CurrentDirectory) ?? Environment.CurrentDirectory;
        string modulesDir = global ? SpmContext.LangModulesDir : Path.Combine(projectDir, "modules");
        string target = Path.Combine(modulesDir, name);
        if (!Directory.Exists(target))
        {
            Console.WriteLine($"[FAIL] 未安装: {target}");
            Console.WriteLine(global ? "       （spm list 查看全部包）" : "       （-g 可删语言目录侧的全局包；spm list 查看全部）");
            return 1;
        }
        Directory.Delete(target, recursive: true);
        Console.WriteLine($"[OK]  removed: {target}");
        return 0;
    }

    // ==== config ====

    public static int RunConfig(string[] args)
    {
        if (args.Length == 0 || !args[0].Equals("registry", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("Usage: spm config registry [<url>]");
            return 2;
        }
        if (args.Length == 1)
        {
            var reg = SpmContext.GlobalRegistry();
            Console.WriteLine(string.IsNullOrWhiteSpace(reg)
                ? $"registry: (not set)  ->  {SpmContext.GlobalConfigPath}"
                : $"registry: {reg}");
            return 0;
        }
        if (args.Length > 2)
        {
            Console.WriteLine("Usage: spm config registry [<url>]");
            return 2;
        }
        var cfg = SpmContext.LoadGlobalConfig();
        cfg.Registry = args[1].Trim();
        SpmContext.SaveGlobalConfig(cfg);
        Console.WriteLine($"[OK]  registry saved -> {SpmContext.GlobalConfigPath}");
        Console.WriteLine($"      {cfg.Registry}");
        return 0;
    }

    // ==== helpers ====

    /// <summary>装完提示：把包加进 jsonc references（不自动改写工程文件）。</summary>
    static void PromptAddReference(string pkgName)
    {
        Console.WriteLine($"      提示: 在工程 jsonc 的 references 里登记后即可 import {pkgName}: 使用，");
        Console.WriteLine($"            \"references\": [ {{ \"path\": \"./modules/{pkgName}\" }} ]");
    }
}
