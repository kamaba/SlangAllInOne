using System.Text.Json;

namespace Spm;

/// <summary>
/// spm 运行上下文：目录定位 + registry 三级解析 + 全局配置。
/// 自解析工程 jsonc（JSONC 容错：注释 + 尾逗号），不依赖 Front 工程——
/// spm.exe 保持独立轻量（部署 = 拷到 slang.exe 同目录即可）。
/// </summary>
internal static class SpmContext
{
    /// <summary>语言目录（spm.exe 所在目录 = 部署时 slang.exe 同目录）。</summary>
    public static string LangDir => AppContext.BaseDirectory;

    /// <summary>语言目录全局包位 modules\。</summary>
    public static string LangModulesDir => Path.Combine(LangDir, "modules");

    /// <summary>语言目录插件安装位 plugin\（package-layout.md §7.2）。</summary>
    public static string LangPluginsDir => Path.Combine(LangDir, "plugin");

    /// <summary>全局配置 &lt;lang&gt;\spm.json（registry / servers）。</summary>
    public static string GlobalConfigPath => Path.Combine(LangDir, "spm.json");

    /// <summary>sync 产物缓存目录 &lt;lang&gt;\spm-cache\（按 key 存 zip）。</summary>
    public static string CacheDir => Path.Combine(LangDir, "spm-cache");

    /// <summary>sync 记录文件 &lt;lang&gt;\spm-cache.json（key → md5/版本/安装位）。</summary>
    public static string SyncCachePath => Path.Combine(LangDir, "spm-cache.json");

    // ==== 全局配置（spm.json）====

    public sealed class GlobalConfig
    {
        public string Registry { get; set; } = "";

        /// <summary>后管平台地址（旧单值字段；新配置写 Servers，读取时兜底兼容）。</summary>
        public string Server { get; set; } = "";

        /// <summary>后管平台地址列表（spm config server 写入；spm sync 按序逐个尝试）。</summary>
        public List<string> Servers { get; set; } = new();
    }

    public static GlobalConfig LoadGlobalConfig()
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

    public static void SaveGlobalConfig(GlobalConfig cfg)
    {
        File.WriteAllText(GlobalConfigPath, JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = true }));
    }

    public static string? GlobalRegistry()
    {
        var reg = LoadGlobalConfig().Registry;
        return string.IsNullOrWhiteSpace(reg) ? null : reg.Trim();
    }

    // ==== 后管平台地址（spm config server / spm sync）====

    /// <summary>
    /// 内置缺省服务器列表（spm.json 未配置 Servers 时启用）：官网远程服务 → 本机。
    /// </summary>
    public static readonly string[] DefaultServers =
    {
        "http://110.40.210.34:35221", // 官网远程服务（后管平台）
        "http://127.0.0.1:35221",     // 本机后管平台
    };

    /// <summary>已配置的后管平台地址列表（归一化去重）；未配置返回空表。</summary>
    public static List<string> GlobalServers()
    {
        var cfg = LoadGlobalConfig();
        var list = new List<string>();
        foreach (var s in cfg.Servers)
        {
            var n = NormalizeServerUrl(s);
            if (n != null && !list.Contains(n))
            {
                list.Add(n);
            }
        }
        if (list.Count == 0)
        {
            // 旧单值字段兜底（0.3.0 及之前 spm config server 写的 Server）
            var legacy = NormalizeServerUrl(cfg.Server);
            if (legacy != null)
            {
                list.Add(legacy);
            }
        }
        return list;
    }

    /// <summary>sync 实际使用的服务器列表：spm.json 配置 &gt; 内置缺省（官网 + 本机）。</summary>
    public static List<string> EffectiveServers()
    {
        var configured = GlobalServers();
        return configured.Count > 0 ? configured : DefaultServers.ToList();
    }

    /// <summary>
    /// 后管平台地址归一化（spm-registry.md §2：SLANG_API_BASE 形态）：
    ///   裸 IP / 主机名            → http://&lt;host&gt;:35221（后管平台缺省端口）
    ///   host:port                 → http://host:port
    ///   http(s)://...             → 原样（去尾部斜杠）
    /// 非法（空）返回 null。
    /// </summary>
    public static string? NormalizeServerUrl(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return null;
        }
        var s = input.Trim().TrimEnd('/');
        if (s.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return s;
        }
        // 裸地址：补 scheme；无端口补后管平台缺省端口 35221
        return s.Contains(':')
            ? "http://" + s
            : "http://" + s + ":35221";
    }

    // ==== registry 三级解析 ====

    /// <summary>
    /// registry 解析：CLI --registry 参数 > 工程 jsonc "spm"."registry" 段 >
    /// 全局 &lt;lang&gt;\spm.json。全部缺省返回 null（服务器功能不可用，
    /// 纯本地操作 install URL/list/remove 仍可用）。
    /// </summary>
    public static string? ResolveRegistry(string? registryOpt, string? projectDir)
    {
        if (!string.IsNullOrWhiteSpace(registryOpt))
        {
            return registryOpt.Trim();
        }
        var proj = ProjectRegistry(projectDir ?? FindProjectDir(Environment.CurrentDirectory));
        if (proj != null)
        {
            return proj;
        }
        return GlobalRegistry();
    }

    /// <summary>
    /// 工程 jsonc "spm"."registry" 段（JSONC 容错解析，与 Front
    /// ProjectJsoncLoader 同语义，但零依赖：只用 JsonDocument 读一个键）。
    /// </summary>
    public static string? ProjectRegistry(string? projectDir)
    {
        try
        {
            var jsonc = FindProjectJsonc(projectDir);
            if (jsonc == null)
            {
                return null;
            }
            using var doc = JsonDocument.Parse(File.ReadAllText(jsonc), JsonDocOptions);
            if (doc.RootElement.TryGetProperty("spm", out var spm)
                && spm.ValueKind == JsonValueKind.Object
                && spm.TryGetProperty("registry", out var reg)
                && reg.ValueKind == JsonValueKind.String)
            {
                var v = reg.GetString();
                return string.IsNullOrWhiteSpace(v) ? null : v.Trim();
            }
        }
        catch
        {
            // 工程 jsonc 损坏等：静默回落全局配置（spm 只读不改工程文件）
        }
        return null;
    }

    internal static readonly JsonDocumentOptions JsonDocOptions = new()
    {
        AllowTrailingCommas = true,
        CommentHandling = JsonCommentHandling.Skip,
    };

    // ==== 工程定位 ====

    /// <summary>
    /// 工程目录定位：从 startDir 逐级上溯找 .jsonc / .sp 锚点所在目录
    /// （用户语义：装包到"运行的当前工程目录（.jsonc 的目录）"）。
    /// </summary>
    public static string? FindProjectDir(string? startDir)
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

    /// <summary>目录内工程 jsonc（排除 plugin.jsonc 清单；与宿主 NewCommand 同规则）。</summary>
    public static string? FindProjectJsonc(string? dir)
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
}
