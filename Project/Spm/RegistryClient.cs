using System.Text.Json;

namespace Spm;

/// <summary>
/// 服务器查询客户端（registry 基 URL）。API 约定 = 官网门户
/// （doc/18-包管理中心spm设计.md §9 / doc/09 §5）：
///   GET &lt;reg&gt;/api/packages/&lt;名&gt;    单包元数据
///   GET &lt;reg&gt;/api/packages           全量索引（{"packages":[...]}）
///   GET &lt;reg&gt;/api/plugins/&lt;id&gt;     单插件元数据
/// 静态回落（简单文件服务器，无门户 API 时）：
///   GET &lt;reg&gt;/&lt;名&gt;.json / &lt;reg&gt;/plugins/&lt;id&gt;.json（同构元数据）
/// 包体下载：元数据 download/file 链接（相对 registry 解析）优先，
/// 缺省 &lt;reg&gt;/&lt;名&gt;.zip、&lt;reg&gt;/plugins/&lt;id&gt;.zip（旧约定）。
/// </summary>
internal static class RegistryClient
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };

    // ==== 元数据模型 ====

    public sealed class PackageMeta
    {
        public string Name = "";
        public string Version = "";
        public string Description = "";
        /// <summary>包体链接（相对 registry 或绝对 URL）；空 = 走缺省 &lt;reg&gt;/&lt;名&gt;.zip。</summary>
        public string Download = "";
        public string Source = ""; // "api" / "static"
    }

    public sealed class PluginMeta
    {
        public string Id = "";
        public string Name = "";
        public string Version = "";
        public string Vendor = "";
        public string Description = "";
        /// <summary>支持平台（"windows" / "windows-x64" / "linux-x64"…；空 = 未声明不限制）。</summary>
        public List<string> Platforms = new();
        public string Download = "";
        public string Source = "";
    }

    // ==== 查询：包 ====

    /// <summary>按名查包：API 端点 → 静态 &lt;reg&gt;/&lt;名&gt;.json 回落；全落空 null。</summary>
    public static PackageMeta? QueryPackage(string registry, string name)
    {
        var json = TryGetString(registry.TrimEnd('/') + "/api/packages/" + Uri.EscapeDataString(name));
        if (json != null)
        {
            var meta = ParsePackage(json);
            if (meta != null)
            {
                meta.Source = "api";
                return meta;
            }
        }
        json = TryGetString(registry.TrimEnd('/') + "/" + Uri.EscapeDataString(name) + ".json");
        if (json != null)
        {
            var meta = ParsePackage(json);
            if (meta != null)
            {
                meta.Source = "static";
                return meta;
            }
        }
        return null;
    }

    /// <summary>全量索引按关键字过滤（search 用）；索引不可达返回 null。</summary>
    public static List<PackageMeta>? SearchPackages(string registry, string keyword)
    {
        var json = TryGetString(registry.TrimEnd('/') + "/api/packages");
        if (json == null)
        {
            return null;
        }
        try
        {
            using var doc = JsonDocument.Parse(json, SpmContext.JsonDocOptions);
            // 两种形态：{"packages":[...]}（官网索引）或直接 [...]
            JsonElement? arr = null;
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("packages", out var pk)
                && pk.ValueKind == JsonValueKind.Array)
            {
                arr = pk;
            }
            else if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                arr = doc.RootElement;
            }
            if (arr == null)
            {
                return null;
            }
            var result = new List<PackageMeta>();
            foreach (var item in arr.Value.EnumerateArray())
            {
                var meta = ParsePackageElement(item);
                if (meta == null)
                {
                    continue;
                }
                if (meta.Name.Contains(keyword, StringComparison.OrdinalIgnoreCase)
                    || meta.Description.Contains(keyword, StringComparison.OrdinalIgnoreCase))
                {
                    result.Add(meta);
                }
            }
            return result;
        }
        catch
        {
            return null;
        }
    }

    // ==== 查询：插件 ====

    /// <summary>按 id 查插件：API 端点 → 静态 &lt;reg&gt;/plugins/&lt;id&gt;.json 回落。</summary>
    public static PluginMeta? QueryPlugin(string registry, string id)
    {
        var json = TryGetString(registry.TrimEnd('/') + "/api/plugins/" + Uri.EscapeDataString(id));
        if (json != null)
        {
            var meta = ParsePlugin(json);
            if (meta != null)
            {
                meta.Source = "api";
                return meta;
            }
        }
        json = TryGetString(registry.TrimEnd('/') + "/plugins/" + Uri.EscapeDataString(id) + ".json");
        if (json != null)
        {
            var meta = ParsePlugin(json);
            if (meta != null)
            {
                meta.Source = "static";
                return meta;
            }
        }
        return null;
    }

    // ==== 下载 ====

    /// <summary>解析包体 URL：元数据 download（相对 registry / 绝对 URL）优先，缺省拼 zip。</summary>
    public static string ResolvePackageUrl(string registry, PackageMeta? meta, string name)
    {
        return ResolveAssetUrl(registry, meta?.Download, name + ".zip");
    }

    public static string ResolvePluginUrl(string registry, PluginMeta? meta, string id)
    {
        return ResolveAssetUrl(registry, meta?.Download, "plugins/" + id + ".zip");
    }

    static string ResolveAssetUrl(string registry, string? download, string defaultRelative)
    {
        if (!string.IsNullOrWhiteSpace(download))
        {
            if (download.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                || download.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return download;
            }
            return registry.TrimEnd('/') + "/" + download.TrimStart('/');
        }
        return registry.TrimEnd('/') + "/" + defaultRelative;
    }

    /// <summary>下载字节数组（5 分钟超时）；失败抛异常由调用方给出友好错误。</summary>
    public static byte[] Download(string url)
    {
        return Http.GetByteArrayAsync(url).GetAwaiter().GetResult();
    }

    // ==== 内部 ====

    static string? TryGetString(string url)
    {
        try
        {
            using var resp = Http.GetAsync(url).GetAwaiter().GetResult();
            if (!resp.IsSuccessStatusCode)
            {
                return null;
            }
            return resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        }
        catch
        {
            return null;
        }
    }

    static PackageMeta? ParsePackage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json, SpmContext.JsonDocOptions);
            return ParsePackageElement(doc.RootElement);
        }
        catch
        {
            return null;
        }
    }

    static PackageMeta? ParsePackageElement(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object)
        {
            return null;
        }
        var meta = new PackageMeta
        {
            Name = GetString(el, "name"),
            Version = GetString(el, "version"),
            Description = GetString(el, "description"),
        };
        // 产物链接键：download（官网索引 versions[].download 平铺约定）/ file（静态元数据）
        meta.Download = GetString(el, "download");
        if (meta.Download.Length == 0)
        {
            meta.Download = GetString(el, "file");
        }
        if (meta.Name.Length == 0)
        {
            return null;
        }
        return meta;
    }

    static PluginMeta? ParsePlugin(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json, SpmContext.JsonDocOptions);
            var el = doc.RootElement;
            if (el.ValueKind != JsonValueKind.Object)
            {
                return null;
            }
            // 兼容 {"plugin":{...}}（plugin.jsonc 风格）与平铺 {"id":...} 两种形态
            if (el.TryGetProperty("plugin", out var inner) && inner.ValueKind == JsonValueKind.Object)
            {
                el = inner;
            }
            var meta = new PluginMeta
            {
                Id = GetString(el, "id"),
                Name = GetString(el, "name"),
                Version = GetString(el, "version"),
                Vendor = GetString(el, "vendor"),
                Description = GetString(el, "description"),
                Download = GetString(el, "download"),
            };
            if (meta.Download.Length == 0)
            {
                meta.Download = GetString(el, "file");
            }
            if (el.TryGetProperty("platforms", out var plats) && plats.ValueKind == JsonValueKind.Array)
            {
                foreach (var p in plats.EnumerateArray())
                {
                    var s = p.ValueKind == JsonValueKind.String ? p.GetString() : null;
                    if (!string.IsNullOrWhiteSpace(s))
                    {
                        meta.Platforms.Add(s.Trim());
                    }
                }
            }
            if (meta.Id.Length == 0)
            {
                return null;
            }
            return meta;
        }
        catch
        {
            return null;
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
