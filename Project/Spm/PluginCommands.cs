using System.Runtime.InteropServices;
using System.Text.Json;

namespace Spm;

/// <summary>
/// 插件命令（多层运行时扩展 → &lt;lang&gt;\plugin\&lt;id&gt;\，全局共享）：
/// plugin list / search / probe（环境探测）/ install / remove。
/// 插件版本与清单权威 = plugin.jsonc（plugin.id/name/version；环境能力 =
/// entry.lib 平台键）；服务器元数据（/api/plugins/&lt;id&gt;）提供版本与
/// 支持平台 platforms[]。
/// </summary>
internal static class PluginCommands
{
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
            "list" or "ls" => RunList(rest),
            "search" or "find" or "info" => RunSearch(rest),
            "probe" => RunProbe(rest),
            "install" or "add" => RunInstall(rest),
            "remove" or "uninstall" => RunRemove(rest),
            _ => PrintUsage(),
        };
    }

    static int PrintUsage()
    {
        Console.WriteLine(@"
Usage:
  spm plugin list
  spm plugin search <id>            query plugin info from server
  spm plugin probe <id>             environment probe (platforms vs host os/arch)
  spm plugin install <id|url> [--registry <url>]
  spm plugin remove <id>");
        return 2;
    }

    // ==== list ====

    static int RunList(string[] args)
    {
        if (args.Length > 0)
        {
            return PrintUsage();
        }
        string pluginsDir = SpmContext.LangPluginsDir;
        Console.WriteLine($"lang plugins: {pluginsDir}");
        if (!Directory.Exists(pluginsDir))
        {
            Console.WriteLine("  (not created)");
            return 0;
        }
        var ids = Directory.GetDirectories(pluginsDir)
            .Select(Path.GetFileName)
            .Where(n => !string.IsNullOrEmpty(n))
            .Select(n => n!)
            .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (ids.Count == 0)
        {
            Console.WriteLine("  (empty)");
            return 0;
        }
        foreach (var id in ids)
        {
            var (name, version, platforms) = ReadLocalPlugin(Path.Combine(pluginsDir, id));
            if (name == null)
            {
                Console.WriteLine($"  {id}  (no plugin.jsonc)");
                continue;
            }
            var plat = platforms.Count > 0 ? string.Join(",", platforms) : "any";
            Console.WriteLine($"  {id}  {version}  [{plat}]  {name}");
        }
        return 0;
    }

    /// <summary>本地插件信息（plugin.jsonc）：返回 (name, version, entry.lib 平台键)。</summary>
    static (string? name, string version, List<string> platforms) ReadLocalPlugin(string pluginDir)
    {
        try
        {
            var manifest = Path.Combine(pluginDir, "plugin.jsonc");
            if (!File.Exists(manifest))
            {
                return (null, "", new List<string>());
            }
            using var doc = JsonDocument.Parse(File.ReadAllText(manifest), SpmContext.JsonDocOptions);
            string name = "", version = "";
            if (doc.RootElement.TryGetProperty("plugin", out var p) && p.ValueKind == JsonValueKind.Object)
            {
                name = GetString(p, "name");
                version = GetString(p, "version");
            }
            var platforms = new List<string>();
            if (doc.RootElement.TryGetProperty("entry", out var entry)
                && entry.ValueKind == JsonValueKind.Object
                && entry.TryGetProperty("lib", out var lib)
                && lib.ValueKind == JsonValueKind.Object)
            {
                foreach (var kv in lib.EnumerateObject())
                {
                    platforms.Add(kv.Name);
                }
            }
            return (name.Length > 0 ? name : null, version, platforms);
        }
        catch
        {
            return (null, "", new List<string>());
        }
    }

    // ==== search：服务器查插件 ====

    static int RunSearch(string[] args)
    {
        string? id = null;
        string? registryOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--registry") && i + 1 < args.Length)
                registryOpt = args[++i];
            else if (id == null)
                id = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return PrintUsage();
            }
        }
        if (string.IsNullOrWhiteSpace(id))
        {
            return PrintUsage();
        }
        string? registry = SpmContext.ResolveRegistry(registryOpt, null);
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine("[FAIL] 未配置 registry（spm plugin search 需要服务器）。");
            Console.WriteLine("       配置方式: spm config registry <url>");
            return 1;
        }
        var meta = RegistryClient.QueryPlugin(registry, id);
        if (meta == null)
        {
            Console.WriteLine($"[FAIL] 服务器无此插件: {id}  (registry: {registry})");
            return 1;
        }
        PrintPlugin(meta);
        return 0;
    }

    static void PrintPlugin(RegistryClient.PluginMeta m)
    {
        Console.WriteLine($"{m.Id}  {m.Version}  ({m.Source})");
        if (m.Name.Length > 0)
        {
            Console.WriteLine($"  name: {m.Name}");
        }
        if (m.Vendor.Length > 0)
        {
            Console.WriteLine($"  vendor: {m.Vendor}");
        }
        if (m.Description.Length > 0)
        {
            Console.WriteLine($"  {m.Description}");
        }
        Console.WriteLine(m.Platforms.Count > 0
            ? $"  platforms: {string.Join(", ", m.Platforms)}"
            : "  platforms: (undeclared)");
        Console.WriteLine($"  install: spm plugin install {m.Id}");
    }

    // ==== probe：插件环境探测 ====

    static int RunProbe(string[] args)
    {
        string? id = null;
        string? registryOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--registry") && i + 1 < args.Length)
                registryOpt = args[++i];
            else if (id == null)
                id = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return PrintUsage();
            }
        }
        if (string.IsNullOrWhiteSpace(id))
        {
            return PrintUsage();
        }

        string host = HostPlatform();
        Console.WriteLine($"host: {host}");

        // ① 服务器元数据的 platforms 声明
        List<string>? platforms = null;
        string? registry = SpmContext.ResolveRegistry(registryOpt, null);
        if (!string.IsNullOrWhiteSpace(registry))
        {
            var meta = RegistryClient.QueryPlugin(registry, id);
            if (meta != null)
            {
                platforms = meta.Platforms;
                Console.WriteLine($"server: {meta.Id} {meta.Version}");
            }
        }

        // ② 回落：本地已装插件的 plugin.jsonc entry.lib 平台键
        if (platforms == null)
        {
            string localDir = Path.Combine(SpmContext.LangPluginsDir, id);
            if (Directory.Exists(localDir))
            {
                var (_, _, localPlatforms) = ReadLocalPlugin(localDir);
                platforms = localPlatforms;
                Console.WriteLine($"local:  {localDir} (installed)");
            }
        }

        if (platforms == null)
        {
            Console.WriteLine($"[FAIL] 无法探测 \"{id}\"：服务器无此插件且本地未安装。");
            return 1;
        }

        if (platforms.Count == 0)
        {
            Console.WriteLine("result: OK（插件未声明平台限制，视为全平台兼容）");
            return 0;
        }

        Console.WriteLine($"plugin platforms: {string.Join(", ", platforms)}");
        if (PlatformMatches(platforms, host))
        {
            Console.WriteLine($"result: OK（当前环境 {host} 兼容）");
            return 0;
        }
        Console.WriteLine($"result: 不兼容（当前环境 {host} 不在支持列表；仍可 spm plugin install 强制安装）");
        return 1;
    }

    /// <summary>本机平台串："windows-x64" 形态（os-arch）。</summary>
    static string HostPlatform()
    {
        string os = OperatingSystem.IsWindows() ? "windows"
            : OperatingSystem.IsLinux() ? "linux"
            : OperatingSystem.IsMacOS() ? "macos"
            : "unknown";
        string arch = RuntimeInformation.OSArchitecture switch
        {
            Architecture.X64 => "x64",
            Architecture.X86 => "x86",
            Architecture.Arm64 => "arm64",
            Architecture.Arm => "arm",
            _ => "unknown",
        };
        return os + "-" + arch;
    }

    /// <summary>平台匹配：项 "windows-x64" 精确（os+arch）；"windows" 只匹配 os。</summary>
    static bool PlatformMatches(List<string> platforms, string host)
    {
        var os = host.Split('-')[0];
        foreach (var p in platforms)
        {
            var parts = p.Trim().ToLowerInvariant().Split('-');
            if (parts.Length == 1)
            {
                if (parts[0] == os) return true;
            }
            else if (p.Trim().ToLowerInvariant() == host)
            {
                return true;
            }
        }
        return false;
    }

    // ==== install ====

    static int RunInstall(string[] args)
    {
        string target = "";
        string? registryOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--registry") && i + 1 < args.Length)
                registryOpt = args[++i];
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

        string pluginsDir = SpmContext.LangPluginsDir;

        // 形态一：URL 直接下载 zip
        if (target.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            // URL 尾段剥 .zip 作期望 id
            string expected = ZipNameFromUrl(target);
            var r = ZipInstall.InstallPluginZip(target, pluginsDir, expected);
            return r == null ? 1 : 0;
        }

        // 形态二：按 id 服务器安装
        if (!ZipInstall.IsValidName(target))
        {
            Console.WriteLine($"[FAIL] 无效插件 id: \"{target}\"（应为 ^[A-Za-z_][A-Za-z0-9_]*$；或给 http(s):// URL）");
            return 2;
        }
        if (Directory.Exists(Path.Combine(pluginsDir, target)))
        {
            Console.WriteLine($"[OK]  {target} 已安装: {Path.Combine(pluginsDir, target)}（如需重装请先 spm plugin remove {target}）");
            return 0;
        }

        string? registry = SpmContext.ResolveRegistry(registryOpt, null);
        if (string.IsNullOrWhiteSpace(registry))
        {
            Console.WriteLine($"[FAIL] 未配置 registry（按 id 安装插件需要服务器）。");
            Console.WriteLine("       配置方式: spm config registry <url>");
            return 1;
        }

        var meta = RegistryClient.QueryPlugin(registry, target);
        string url;
        if (meta != null)
        {
            Console.WriteLine($"server: {meta.Id} {meta.Version}  ({meta.Source})");
            if (meta.Description.Length > 0)
            {
                Console.WriteLine($"        {meta.Description}");
            }
            // 环境探测（非阻塞警告）：平台不匹配提示但可继续（强制语义）
            if (meta.Platforms.Count > 0)
            {
                string host = HostPlatform();
                Console.WriteLine($"host:   {host}；plugin platforms: {string.Join(", ", meta.Platforms)}");
                if (!PlatformMatches(meta.Platforms, host))
                {
                    Console.WriteLine($"[WARN] 当前环境 {host} 不在插件支持列表，仍继续安装（可先 spm plugin probe {target} 探测）");
                }
            }
            url = RegistryClient.ResolvePluginUrl(registry, meta, target);
        }
        else
        {
            url = registry.TrimEnd('/') + "/plugins/" + target + ".zip";
            Console.WriteLine($"server: no metadata for \"{target}\"; trying {url}");
        }

        var res = ZipInstall.InstallPluginZip(url, pluginsDir, target);
        if (res == null)
        {
            return 1;
        }
        if (!res.AlreadyInstalled)
        {
            Console.WriteLine($"[OK]  {res.Name}: installed -> {res.DestDir}");
        }
        Console.WriteLine("      提示: 插件全局生效（<lang>\\plugin\\），工程 jsonc 的 plugins 段声明后即可 @tag{} 使用：");
        Console.WriteLine($"            \"plugins\": {{ \"{res.Name}\": {{ \"enabled\": true }} }}");
        return 0;
    }

    // ==== remove ====

    static int RunRemove(string[] args)
    {
        string id = "";
        foreach (var a in args)
        {
            if (id.Length == 0)
                id = a;
            else
            {
                Console.WriteLine($"[FAIL] 未知参数: {a}");
                return PrintUsage();
            }
        }
        if (id.Length == 0)
        {
            return PrintUsage();
        }
        string target = Path.Combine(SpmContext.LangPluginsDir, id);
        if (!Directory.Exists(target))
        {
            Console.WriteLine($"[FAIL] 未安装: {target}");
            Console.WriteLine("       （spm plugin list 查看已装插件）");
            return 1;
        }
        Directory.Delete(target, recursive: true);
        Console.WriteLine($"[OK]  removed: {target}");
        return 0;
    }

    // ==== helpers ====

    static string ZipNameFromUrl(string url)
    {
        try
        {
            var name = url.Split('?', '#')[0].TrimEnd('/').Split('/')[^1];
            if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                name = name.Substring(0, name.Length - 4);
            }
            return name.Length > 0 ? name : "plugin";
        }
        catch
        {
            return "plugin";
        }
    }

    static string GetString(JsonElement el, string key)
    {
        if (el.ValueKind == JsonValueKind.Object
            && el.TryGetProperty(key, out var v)
            && v.ValueKind == JsonValueKind.String)
        {
            return v.GetString() ?? "";
        }
        return "";
    }
}
