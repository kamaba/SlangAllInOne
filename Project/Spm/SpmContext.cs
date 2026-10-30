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

    /// <summary>全局配置 &lt;lang&gt;\spm.json（registry）。</summary>
    public static string GlobalConfigPath => Path.Combine(LangDir, "spm.json");

    // ==== 全局配置（spm.json）====

    public sealed class GlobalConfig
    {
        public string Registry { get; set; } = "";
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
