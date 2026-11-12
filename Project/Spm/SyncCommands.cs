using System.IO.Compression;
using System.Text.Json;

namespace Spm;

/// <summary>
/// 后管平台同步命令（spm sync，doc/spm-registry.md §3）：
/// 对后管平台发布的四类产物做「md5 比对 + 按需重下载 + 解压落位」：
///   本体包(core)   resolve?type=本体包                 → 解压合并进 &lt;lang&gt;\（spm.exe 所在目录）
///   vscode        resolve?type=vscode                  → 解压进 %USERPROFILE%\.vscode\extensions\
///   插件(plugin)  GET /api/plugins 列 id → resolve     → &lt;lang&gt;\plugin\&lt;id&gt;\
///   包(package)   GET /api/packages 列 id → resolve    → &lt;lang&gt;\modules\&lt;名&gt;\
///
/// 多服务器（&lt;lang&gt;\spm.json "servers" 列表）：解析/列表/下载均按序逐个尝试，
/// 无回复、404、连接失败都换下一个；全部服务器都失败时在返回结果中逐条说明
/// 每个服务器的失败原因。列表解析：--server 参数（单值）&gt; spm config server
/// 写入的 servers &gt; 内置缺省（官网远程服务 + 127.0.0.1）。
///
/// 单条目流程（§3）：解析 GET /api/registry/resolve 得 {md5,url} → 与本地缓存
/// zip 的 md5 比对（一致跳过下载）→ 不一致/缺失按 url 重下载 → 下载后 md5 二次
/// 校验（不一致删缓存报错退出）→ 解压落位 → 记录 &lt;lang&gt;\spm-cache.json，
/// zip 存 &lt;lang&gt;\spm-cache\&lt;type&gt;__&lt;name&gt;.zip。
/// </summary>
internal static class SyncCommands
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(10) };    // 下载（大文件）
    static readonly HttpClient HttpApi = new() { Timeout = TimeSpan.FromSeconds(15) }; // 解析/列表（快速失败换下一台）

    // 类型令牌：英文 / 中文别名 → 内部 key
    static string? NormalizeTypeToken(string s)
    {
        var t = s.Trim().ToLowerInvariant();
        return t switch
        {
            "all" or "全部" or "*" => "all",
            "core" or "本体包" or "本体" or "slang" or "lang" => "core",
            "vscode" or "vsix" => "vscode",
            "plugin" or "plugins" or "插件" => "plugin",
            "package" or "packages" or "pkg" or "包" => "package",
            _ => null,
        };
    }

    public static int Run(string[] args)
    {
        var types = new List<string>();
        string? nameFilter = null;
        string? serverOpt = null;
        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--server" && i + 1 < args.Length)
            {
                serverOpt = args[++i];
                continue;
            }
            var t = NormalizeTypeToken(a);
            if (t != null)
            {
                types.Add(t);
                continue;
            }
            // plugin/package 类型后的非类型词 = 名称过滤（spm sync plugin echo）
            if (types.Count > 0 && nameFilter == null
                && (types[^1] == "plugin" || types[^1] == "package")
                && ZipInstall.IsValidName(a))
            {
                nameFilter = a;
                continue;
            }
            Console.WriteLine($"[FAIL] 未知参数: {a}");
            return Program.PrintUsage();
        }
        if (types.Count == 0)
        {
            types.Add("all");
        }
        if (nameFilter != null && !types.Any(t => t is "plugin" or "package"))
        {
            Console.WriteLine("[FAIL] 名称过滤只适用于 plugin / package 类型。");
            return 2;
        }

        List<string> servers;
        if (serverOpt != null)
        {
            var n = SpmContext.NormalizeServerUrl(serverOpt);
            if (n == null)
            {
                Console.WriteLine("[FAIL] --server 地址为空。示例: spm sync --server 192.168.1.10:35221");
                return 2;
            }
            servers = new List<string> { n };
        }
        else
        {
            servers = SpmContext.EffectiveServers(); // 配置 > 内置缺省（官网远程 + 本机）
        }
        Console.WriteLine($"servers ({servers.Count}):");
        foreach (var s in servers)
        {
            Console.WriteLine($"  - {s}");
        }

        var selected = types.Contains("all")
            ? new[] { "core", "vscode", "plugin", "package" }
            : types.Distinct().ToArray();
        var cache = SyncCache.Load();
        var st = new Stats();

        foreach (var t in selected)
        {
            switch (t)
            {
                case "core":
                    Console.WriteLine("== 本体包 -> <lang>\\ ==");
                    SyncOne(cache, servers, st, "core", "本体包", "slang");
                    break;
                case "vscode":
                    Console.WriteLine("== VSCode 插件 -> .vscode\\extensions\\ ==");
                    SyncOne(cache, servers, st, "vscode", "vscode", "vscode");
                    break;
                case "plugin":
                {
                    Console.WriteLine($"== slang 插件 -> {SpmContext.LangPluginsDir}\\<id> ==");
                    var (hit, ids, listErrors) = ListIdsMulti(servers, "plugins");
                    if (ids == null)
                    {
                        Console.WriteLine($"[FAIL] 无法获取插件列表（所有服务器均无响应，尝试 {servers.Count} 个）:");
                        foreach (var e in listErrors)
                        {
                            Console.WriteLine($"        {e}");
                        }
                        st.Failed++;
                        break;
                    }
                    var ordered = Prefer(servers, hit);
                    if (nameFilter != null)
                    {
                        ids = ids.Where(x => x.Equals(nameFilter, StringComparison.OrdinalIgnoreCase)).ToList();
                    }
                    if (ids.Count == 0)
                    {
                        Console.WriteLine(nameFilter == null ? "  (服务器无已发布插件)" : $"  (服务器无此插件: {nameFilter})");
                        break;
                    }
                    foreach (var id in ids)
                    {
                        SyncOne(cache, ordered, st, "plugin", "插件", id);
                    }
                    break;
                }
                case "package":
                {
                    Console.WriteLine($"== slang 包 -> {SpmContext.LangModulesDir}\\<名> ==");
                    var (hit, ids, listErrors) = ListIdsMulti(servers, "packages");
                    if (ids == null)
                    {
                        Console.WriteLine($"[FAIL] 无法获取包列表（所有服务器均无响应，尝试 {servers.Count} 个）:");
                        foreach (var e in listErrors)
                        {
                            Console.WriteLine($"        {e}");
                        }
                        st.Failed++;
                        break;
                    }
                    var ordered = Prefer(servers, hit);
                    if (nameFilter != null)
                    {
                        ids = ids.Where(x => x.Equals(nameFilter, StringComparison.OrdinalIgnoreCase)).ToList();
                    }
                    if (ids.Count == 0)
                    {
                        Console.WriteLine(nameFilter == null ? "  (服务器无已发布包)" : $"  (服务器无此包: {nameFilter})");
                        break;
                    }
                    foreach (var id in ids)
                    {
                        SyncOne(cache, ordered, st, "package", "包", id);
                    }
                    break;
                }
            }
        }

        cache.Save();
        Console.WriteLine($"sync 完成: 更新 {st.Updated}，已最新 {st.Skipped}，失败 {st.Failed}");
        return st.Failed > 0 ? 1 : 0;
    }

    sealed class Stats
    {
        public int Updated;
        public int Skipped;
        public int Failed;
    }

    // ==== 单条目同步 ====

    static void SyncOne(SyncCache cache, List<string> servers, Stats st, string typeKey, string typeName, string name)
    {
        var (hit, r, resolveErrors) = ResolveMulti(servers, typeName, name);
        if (r == null)
        {
            Console.WriteLine($"[FAIL] {name}: 所有服务器均无有效响应（尝试 {servers.Count} 个）:");
            foreach (var e in resolveErrors)
            {
                Console.WriteLine($"        {e}");
            }
            st.Failed++;
            return;
        }
        if (r.Url.Length == 0)
        {
            Console.WriteLine($"[SKIP] {name}: 服务器未提供下载地址（v{r.Version}，{hit}）");
            st.Skipped++;
            return;
        }
        var hitServer = hit!; // ResolveMulti 命中时 server 必非空

        string key = typeKey is "core" or "vscode" ? typeKey : typeKey + "/" + name;
        string zipPath = Path.Combine(SpmContext.CacheDir, SanitizeFile(typeKey + "__" + name) + ".zip");

        // ① 本地缓存 md5 比对（§3.2）：缓存 zip 在且 md5 一致 → 不重下载
        byte[] zipBytes;
        bool downloaded = false;
        if (File.Exists(zipPath) && r.Md5.Length > 0
            && ZipInstall.Md5File(zipPath).Equals(r.Md5, StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                zipBytes = File.ReadAllBytes(zipPath);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[FAIL] {name}: 读缓存失败: {ex.Message}");
                st.Failed++;
                return;
            }
        }
        else
        {
            var (bytes, dlErrors) = DownloadMulti(servers, hitServer, r.Url);
            if (bytes == null)
            {
                Console.WriteLine($"[FAIL] {name}: 下载失败（所有服务器均不可达，尝试 {dlErrors.Count} 次）:");
                foreach (var e in dlErrors)
                {
                    Console.WriteLine($"        {e}");
                }
                st.Failed++;
                return;
            }
            zipBytes = bytes;
            downloaded = true;
            // ② 下载后 md5 二次校验（§3.4）：不一致判损坏，删缓存报错退出
            if (r.Md5.Length > 0 && !ZipInstall.Md5Bytes(zipBytes).Equals(r.Md5, StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"[FAIL] {name}: md5 校验失败（服务器 {r.Md5} != 下载 {ZipInstall.Md5Bytes(zipBytes)}），已放弃安装");
                try { File.Delete(zipPath); } catch { }
                st.Failed++;
                return;
            }
            try
            {
                Directory.CreateDirectory(SpmContext.CacheDir);
                File.WriteAllBytes(zipPath, zipBytes);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WARN] {name}: 缓存 zip 写入失败: {ex.Message}（不影响本次安装）");
            }
        }

        // ③ 安装完好 + 记录 md5 与服务器一致 → 跳过解压（省时）
        var rec = cache.Get(key);
        if (rec != null && r.Md5.Length > 0
            && rec.Md5.Equals(r.Md5, StringComparison.OrdinalIgnoreCase)
            && InstallIntact(rec))
        {
            Console.WriteLine($"[OK]  {name} {r.Version}: 已是最新（md5 {Short(r.Md5)}）");
            st.Skipped++;
            return;
        }

        // ④ 解压落位
        string? installPath = null;
        switch (typeKey)
        {
            case "core":
                installPath = ExtractCore(zipBytes);
                break;
            case "vscode":
                installPath = ExtractVscode(zipBytes, name);
                break;
            case "plugin":
            {
                var pr = ZipInstall.InstallPluginZip(zipBytes, SpmContext.LangPluginsDir, name, replaceExisting: true);
                if (pr != null && pr.AlreadyInstalled)
                {
                    Console.WriteLine($"[FAIL] {name}: 无法替换已安装插件目录（文件被占用？）");
                    pr = null;
                }
                installPath = pr?.DestDir;
                break;
            }
            case "package":
            {
                // md5 / zip 路径随包清单 spm.json 记录（2026-11-12 与本地 zip 装包统一）
                var pr = ZipInstall.InstallPackageZip(zipBytes, SpmContext.LangModulesDir, name, r.Version, hitServer,
                    replaceExisting: true, md5: r.Md5, zipPath: zipPath);
                if (pr != null && pr.AlreadyInstalled)
                {
                    Console.WriteLine($"[FAIL] {name}: 无法替换已安装包目录（文件被占用？）");
                    pr = null;
                }
                installPath = pr?.DestDir;
                break;
            }
        }
        if (installPath == null)
        {
            st.Failed++;
            return;
        }

        cache.Set(key, new SyncCache.Record
        {
            Type = typeKey,
            Name = name,
            Version = r.Version,
            Md5 = r.Md5,
            Url = r.Url,
            Zip = zipPath,
            InstallPath = installPath,
            UpdatedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
        });
        Console.WriteLine($"[OK]  {name} {r.Version}: {(downloaded ? "下载并" : "缓存")}安装 -> {installPath}");
        st.Updated++;
    }

    /// <summary>安装位完好性：插件/包/扩展看安装目录在不在；本体包目录恒在，靠记录 md5 把关。</summary>
    static bool InstallIntact(SyncCache.Record rec)
    {
        return Directory.Exists(rec.InstallPath);
    }

    // ==== 本体包：解压合并进语言目录 ====

    /// <summary>
    /// 本体包落位：zip 内容合并进 &lt;lang&gt;\（覆盖同名文件，不删除多余文件）。
    /// 单一顶层目录 → 取其内容为源根（发布包常带一层 win32-release\）。
    /// 有文件被占用（如运行中的 spm.exe/slang.exe）→ 列出并返回 null（不写记录，下次重试）。
    /// </summary>
    static string? ExtractCore(byte[] zipBytes)
    {
        var langDir = SpmContext.LangDir;
        var locked = new List<string>();
        string tempRoot = Path.Combine(Path.GetTempPath(), "slang-spm-core-" + Guid.NewGuid().ToString("N"));
        string tempZip = tempRoot + ".zip";
        try
        {
            File.WriteAllBytes(tempZip, zipBytes);
            ZipFile.ExtractToDirectory(tempZip, tempRoot, overwriteFiles: true);
            var dirs = Directory.GetDirectories(tempRoot);
            var files = Directory.GetFiles(tempRoot);
            string srcRoot = dirs.Length == 1 && files.Length == 0 ? dirs[0] : tempRoot;
            foreach (var src in Directory.GetFiles(srcRoot, "*", SearchOption.AllDirectories))
            {
                var rel = Path.GetRelativePath(srcRoot, src);
                var dest = Path.Combine(langDir, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                try
                {
                    File.Copy(src, dest, overwrite: true);
                }
                catch (Exception)
                {
                    locked.Add(rel);
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] 本体包解压失败: {ex.Message}");
            return null;
        }
        finally
        {
            try { Directory.Delete(tempRoot, true); } catch { }
            try { File.Delete(tempZip); } catch { }
        }
        if (locked.Count > 0)
        {
            Console.WriteLine($"[WARN] {locked.Count} 个文件被占用未能替换（关闭 slang 相关程序后重跑 spm sync core）:");
            foreach (var f in locked.Take(10))
            {
                Console.WriteLine($"        {f}");
            }
            if (locked.Count > 10)
            {
                Console.WriteLine($"        ... 共 {locked.Count} 个");
            }
            return null; // 未完全落位：不写记录，下次重试
        }
        return langDir;
    }

    // ==== vscode：解压进 VSCode 扩展目录 ====

    /// <summary>
    /// vscode 插件落位：解压 → 定位扩展根（根/package.json、extension\package.json
    /// （vsix 布局）、任一顶层目录\package.json）→ 读 package.json 的 name/version/
    /// publisher 拼 VSCode 约定目录名 → 装 %USERPROFILE%\.vscode\extensions\。
    /// </summary>
    static string? ExtractVscode(byte[] zipBytes, string fallbackName)
    {
        string extRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".vscode", "extensions");
        string tempRoot = Path.Combine(Path.GetTempPath(), "slang-spm-vscode-" + Guid.NewGuid().ToString("N"));
        string tempZip = tempRoot + ".zip";
        try
        {
            File.WriteAllBytes(tempZip, zipBytes);
            ZipFile.ExtractToDirectory(tempZip, tempRoot, overwriteFiles: true);
            var dir = FindExtensionRoot(tempRoot);
            if (dir == null)
            {
                Console.WriteLine("[FAIL] vscode 产物中未找到 package.json（无法定位扩展根）");
                return null;
            }
            var (name, version, publisher) = ReadExtensionManifest(Path.Combine(dir, "package.json"));
            var dest = Path.Combine(extRoot, BuildExtensionDirName(name, version, publisher, fallbackName));
            if (Directory.Exists(dest))
            {
                try
                {
                    Directory.Delete(dest, recursive: true);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[FAIL] 无法替换 {dest}: {ex.Message}（VSCode 正在使用？）");
                    return null;
                }
            }
            Directory.CreateDirectory(extRoot);
            ZipInstall.TryMoveOrCopy(dir, dest);
            return dest;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] vscode 插件解压失败: {ex.Message}");
            return null;
        }
        finally
        {
            try { Directory.Delete(tempRoot, true); } catch { }
            try { File.Delete(tempZip); } catch { }
        }
    }

    static string? FindExtensionRoot(string extractRoot)
    {
        if (File.Exists(Path.Combine(extractRoot, "package.json")))
        {
            return extractRoot;
        }
        var extDir = Path.Combine(extractRoot, "extension"); // vsix 布局
        if (File.Exists(Path.Combine(extDir, "package.json")))
        {
            return extDir;
        }
        foreach (var d in Directory.GetDirectories(extractRoot))
        {
            if (File.Exists(Path.Combine(d, "package.json")))
            {
                return d;
            }
        }
        return null;
    }

    static (string name, string version, string publisher) ReadExtensionManifest(string manifestPath)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(manifestPath), SpmContext.JsonDocOptions);
            string S(string k) => doc.RootElement.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String
                ? (v.GetString() ?? "") : "";
            return (S("name"), S("version"), S("publisher"));
        }
        catch
        {
            return ("", "", "");
        }
    }

    static string BuildExtensionDirName(string name, string version, string publisher, string fallback)
    {
        var n = string.IsNullOrWhiteSpace(name) ? fallback : name;
        var v = string.IsNullOrWhiteSpace(version) ? "" : "-" + version;
        return string.IsNullOrWhiteSpace(publisher) ? $"{n}{v}" : $"{publisher}.{n}{v}";
    }

    // ==== 服务器接口（多服务器逐个尝试，失败汇总说明）====

    /// <summary>把 preferred 提到列表最前（其余保持原序；null 原样返回）。</summary>
    static List<string> Prefer(List<string> servers, string? preferred)
    {
        if (preferred == null)
        {
            return servers;
        }
        var ordered = new List<string> { preferred };
        ordered.AddRange(servers.Where(s => s != preferred));
        return ordered;
    }

    /// <summary>下载产物：优先 hit 服务器，失败换下一个；绝对 url 只试一次。</summary>
    static (byte[]? bytes, List<string> errors) DownloadMulti(List<string> servers, string hit, string url)
    {
        var errors = new List<string>();
        var isAbsolute = url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                      || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
        var targets = isAbsolute ? new List<string> { hit } : Prefer(servers, hit);
        foreach (var s in targets)
        {
            var abs = AbsoluteUrl(s, url);
            try
            {
                return (Http.GetByteArrayAsync(abs).GetAwaiter().GetResult(), errors);
            }
            catch (Exception ex)
            {
                errors.Add($"{abs} -> {ex.Message}");
            }
        }
        return (null, errors);
    }

    /// <summary>逐服务器解析：按序尝试，第一个「在线且 code 200」的服务器命中。</summary>
    static (string? server, ResolveResult? result, List<string> errors) ResolveMulti(
        List<string> servers, string typeName, string name)
    {
        var errors = new List<string>();
        foreach (var s in servers)
        {
            var r = Resolve(s, typeName, name, out var error);
            if (r != null)
            {
                return (s, r, errors);
            }
            errors.Add($"{s} -> {error}");
        }
        return (null, null, errors);
    }

    sealed class ResolveResult
    {
        public string Type = "";
        public string Name = "";
        public string Version = "";
        public string Md5 = "";
        public string Url = "";
    }

    /// <summary>
    /// GET /api/registry/resolve（version=latest）：{ code, data:{type,name,version,md5,url} }。
    /// 失败经 out error 返回原因（连接失败 / HTTP 状态 / 服务器业务 msg）。
    /// </summary>
    static ResolveResult? Resolve(string server, string typeName, string name, out string error)
    {
        error = "";
        var url = $"{server}/api/registry/resolve?type={Uri.EscapeDataString(typeName)}"
                + $"&name={Uri.EscapeDataString(name)}&version=latest";
        string json;
        try
        {
            using var resp = HttpApi.GetAsync(url).GetAwaiter().GetResult();
            if (!resp.IsSuccessStatusCode)
            {
                error = $"HTTP {(int)resp.StatusCode}";
                return null;
            }
            json = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            error = "连接失败: " + ex.Message;
            return null;
        }
        try
        {
            using var doc = JsonDocument.Parse(json, SpmContext.JsonDocOptions);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                error = "响应格式异常";
                return null;
            }
            if (root.TryGetProperty("code", out var code)
                && (code.ValueKind == JsonValueKind.Number && code.GetInt32() != 200
                    || code.ValueKind == JsonValueKind.String && code.GetString() != "200"))
            {
                error = root.TryGetProperty("msg", out var msg) && msg.ValueKind == JsonValueKind.String
                    ? (msg.GetString() ?? "业务失败")
                    : "业务失败";
                return null;
            }
            if (!root.TryGetProperty("data", out var d) || d.ValueKind != JsonValueKind.Object)
            {
                error = "响应缺少 data";
                return null;
            }
            return new ResolveResult
            {
                Type = GetStr(d, "type"),
                Name = GetStr(d, "name"),
                Version = GetStr(d, "version"),
                Md5 = GetStr(d, "md5").Trim().ToLowerInvariant(),
                Url = GetStr(d, "url").Trim(),
            };
        }
        catch
        {
            error = "响应解析失败";
            return null;
        }
    }

    /// <summary>GET /api/{plugins|packages}（逐服务器尝试）：取对外可见条目 id 列表。</summary>
    static (string? server, List<string>? ids, List<string> errors) ListIdsMulti(List<string> servers, string kind)
    {
        var errors = new List<string>();
        foreach (var s in servers)
        {
            var ids = ListIds(s, kind, out var error);
            if (ids != null)
            {
                return (s, ids, errors);
            }
            errors.Add($"{s} -> {error}");
        }
        return (null, null, errors);
    }

    /// <summary>
    /// GET /api/{plugins|packages}：解析对外可见条目 id 列表（id/name/pluginName/
    /// packageName 任一字段）；服务器在线返回空表 = 有效回复（不换服务器），
    /// 网络失败/HTTP 非 2xx/解析失败返回 null + 原因。
    /// </summary>
    static List<string>? ListIds(string server, string kind, out string error)
    {
        error = "";
        try
        {
            using var resp = HttpApi.GetAsync($"{server}/api/{kind}").GetAwaiter().GetResult();
            if (!resp.IsSuccessStatusCode)
            {
                error = $"HTTP {(int)resp.StatusCode}";
                return null;
            }
            var json = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(json, SpmContext.JsonDocOptions);
            var root = doc.RootElement;
            JsonElement arr;
            if (root.ValueKind == JsonValueKind.Array)
            {
                arr = root;
            }
            else if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var d))
            {
                if (d.ValueKind == JsonValueKind.Array)
                {
                    arr = d;
                }
                else if (d.ValueKind == JsonValueKind.Object && d.TryGetProperty(kind, out var pk) && pk.ValueKind == JsonValueKind.Array)
                {
                    arr = pk; // { packages:[...] } 形态
                }
                else
                {
                    error = "响应格式异常";
                    return null;
                }
            }
            else
            {
                error = "响应格式异常";
                return null;
            }
            var ids = new List<string>();
            foreach (var item in arr.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }
                var id = GetStr(item, "id");
                if (id.Length == 0) id = GetStr(item, "name");
                if (id.Length == 0) id = GetStr(item, "pluginName");
                if (id.Length == 0) id = GetStr(item, "packageName");
                if (id.Length > 0 && !ids.Contains(id))
                {
                    ids.Add(id);
                }
            }
            return ids;
        }
        catch (Exception ex)
        {
            error = "连接失败: " + ex.Message;
            return null;
        }
    }

    // ==== 同步记录（<lang>\spm-cache.json）====

    sealed class SyncCache
    {
        public sealed class Record
        {
            public string Type { get; set; } = "";
            public string Name { get; set; } = "";
            public string Version { get; set; } = "";
            public string Md5 { get; set; } = "";
            public string Url { get; set; } = "";
            public string Zip { get; set; } = "";
            public string InstallPath { get; set; } = "";
            public string UpdatedAt { get; set; } = "";
        }

        public Dictionary<string, Record> Artifacts { get; set; } = new();

        public Record? Get(string key) => Artifacts.TryGetValue(key, out var r) ? r : null;

        public void Set(string key, Record r) => Artifacts[key] = r;

        public static SyncCache Load()
        {
            try
            {
                if (File.Exists(SpmContext.SyncCachePath))
                {
                    return JsonSerializer.Deserialize<SyncCache>(File.ReadAllText(SpmContext.SyncCachePath)) ?? new SyncCache();
                }
            }
            catch { }
            return new SyncCache();
        }

        public void Save()
        {
            try
            {
                File.WriteAllText(SpmContext.SyncCachePath,
                    JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WARN] 同步记录写入失败: {ex.Message}");
            }
        }
    }

    // ==== 工具 ====

    static string AbsoluteUrl(string server, string url)
    {
        if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return url;
        }
        return server.TrimEnd('/') + (url.StartsWith('/') ? "" : "/") + url;
    }

    static string SanitizeFile(string name)
    {
        foreach (var c in Path.GetInvalidFileNameChars())
        {
            name = name.Replace(c, '_');
        }
        return name;
    }

    static string Short(string md5) => md5.Length <= 8 ? md5 : md5[..8] + "..";

    static string GetStr(JsonElement el, string key)
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
