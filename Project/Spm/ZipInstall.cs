using System.IO.Compression;
using System.Text.Json;

namespace Spm;

/// <summary>
/// zip 安装器：下载 → 临时目录解压 → 布局探测归一 → 装进目标目录；
/// 包与插件共用（探测规则不同）。
///
/// 包布局探测（归一为 modules\&lt;名&gt;\）：
///   ① 单一顶层目录 → 该目录即包目录（包名 = 目录名）；
///   ② 根含 *.module.slb|json → 根即包内容（包名 = 产物名剥后缀）；
///   ③ 多目录时找 &lt;目录&gt;\&lt;目录名&gt;.module.slb|json 命中者；
///   ④ 兜底：期望包名 / zip 文件名。
/// 插件布局探测（归一为 plugin\&lt;id&gt;\）：
///   ① 任意层级找 plugin.jsonc 所在目录（插件权威清单 = 插件根）；
///   ② 兜底：单一顶层目录 / 期望 id / zip 文件名。
///
/// 本地清单：包安装成功后写 &lt;目标&gt;\spm.json（name/version/source/
/// installedAt），供 spm outdated 与服务器版本对比；已存在时保留不覆盖
/// （重装前 remove 会整目录删除）。
/// </summary>
internal static class ZipInstall
{
    public sealed class InstallResult
    {
        public string Name = "";
        public string DestDir = "";
        /// <summary>true = 目标已存在（未重装，仅提示）。</summary>
        public bool AlreadyInstalled;
    }

    /// <summary>下载 zip 并按包布局归一装进 modulesDir；version 记入本地清单。</summary>
    public static InstallResult? InstallPackageZip(string url, string modulesDir, string? expectedName, string version, string source)
    {
        return InstallCore(url, dir => DetectPackageLayout(dir, expectedName, url), layout =>
        {
            string dest = Path.Combine(modulesDir, layout.Name);
            bool placed = Place(layout, modulesDir, dest);
            if (placed)
            {
                WriteLocalManifest(dest, layout.Name, version, source);
            }
            return new InstallResult { Name = layout.Name, DestDir = dest, AlreadyInstalled = !placed };
        });
    }

    /// <summary>下载 zip 并按插件布局归一装进 pluginsDir（&lt;lang&gt;\plugin\&lt;id&gt;\）。</summary>
    public static InstallResult? InstallPluginZip(string url, string pluginsDir, string expectedId)
    {
        return InstallCore(url, dir => DetectPluginLayout(dir, expectedId, url), layout =>
        {
            string dest = Path.Combine(pluginsDir, layout.Name);
            bool placed = Place(layout, pluginsDir, dest);
            return new InstallResult { Name = layout.Name, DestDir = dest, AlreadyInstalled = !placed };
        });
    }

    // ==== 核心 ====

    sealed class Layout
    {
        public string Name = "";
        public string SrcDir = "";
    }

    /// <summary>
    /// 下载 → 临时解压 → 探测 → place 回调（移动/拷贝必须在 temp 生命周期内
    /// 完成——finally 清理 tempRoot，故不能把 SrcDir 带出本函数再用）。
    /// </summary>
    static InstallResult? InstallCore(string url, Func<string, Layout> detect, Func<Layout, InstallResult> place)
    {
        byte[] zipBytes;
        try
        {
            zipBytes = RegistryClient.Download(url);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] 下载失败: {ex.Message}");
            return null;
        }

        string tempRoot = Path.Combine(Path.GetTempPath(), "slang-spm-" + Guid.NewGuid().ToString("N"));
        string tempZip = tempRoot + ".zip";
        try
        {
            File.WriteAllBytes(tempZip, zipBytes);
            ZipFile.ExtractToDirectory(tempZip, tempRoot, overwriteFiles: true);
            var layout = detect(tempRoot);
            if (!IsValidName(layout.Name))
            {
                Console.WriteLine($"[FAIL] 推断的包名无效: \"{layout.Name}\"（zip 布局异常；包目录/产物名应为 ^[A-Za-z_][A-Za-z0-9_]*$）");
                return null;
            }
            return place(layout);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] 安装失败: {ex.Message}");
            return null;
        }
        finally
        {
            try { Directory.Delete(tempRoot, true); } catch { }
            try { File.Delete(tempZip); } catch { }
        }
    }

    /// <summary>落位：目标已存在 → false（仅提示）；否则移动/拷贝 → true。</summary>
    static bool Place(Layout layout, string parentDir, string dest)
    {
        if (Directory.Exists(dest))
        {
            Console.WriteLine($"[OK]  {layout.Name} 已安装: {dest}（如需重装请先 spm remove）");
            return false;
        }
        Directory.CreateDirectory(parentDir);
        TryMoveOrCopy(layout.SrcDir, dest);
        return true;
    }

    // ==== 布局探测 ====

    static Layout DetectPackageLayout(string extractRoot, string? expectedName, string url)
    {
        var dirs = Directory.GetDirectories(extractRoot);
        var files = Directory.GetFiles(extractRoot);

        // ① 单一顶层目录 → 该目录即包目录
        if (dirs.Length == 1 && files.Length == 0)
        {
            return new Layout { Name = Path.GetFileName(dirs[0]), SrcDir = dirs[0] };
        }

        // ② 根含模块产物 → 根即包内容
        var mod = files.FirstOrDefault(f => f.EndsWith(".module.slb", StringComparison.OrdinalIgnoreCase))
                  ?? files.FirstOrDefault(f => f.EndsWith(".module.json", StringComparison.OrdinalIgnoreCase));
        if (mod != null)
        {
            return new Layout { Name = ModuleNameFromFile(Path.GetFileName(mod)), SrcDir = extractRoot };
        }

        // ③ 多目录：找 <目录>\<目录名>.module.slb|json 命中者
        foreach (var d in dirs)
        {
            var dn = Path.GetFileName(d);
            if (File.Exists(Path.Combine(d, dn + ".module.slb"))
                || File.Exists(Path.Combine(d, dn + ".module.json")))
            {
                return new Layout { Name = dn, SrcDir = d };
            }
        }

        // ④ 兜底：期望包名 / zip 文件名
        return new Layout { Name = expectedName ?? ZipNameFromUrl(url), SrcDir = extractRoot };
    }

    static Layout DetectPluginLayout(string extractRoot, string expectedId, string url)
    {
        // ① 任意层级找 plugin.jsonc（限三层深度防误扫）：其所在目录 = 插件根
        var manifest = FindPluginManifest(extractRoot, depth: 0);
        if (manifest != null)
        {
            var root = Path.GetDirectoryName(manifest)!;
            // 清单里的 plugin.id 权威；读不到用目录名/期望 id
            var id = ReadPluginId(manifest);
            var name = !string.IsNullOrWhiteSpace(id) ? id : Path.GetFileName(root);
            if (string.IsNullOrWhiteSpace(name))
            {
                name = expectedId;
            }
            return new Layout { Name = name, SrcDir = root };
        }

        // ② 兜底：单一顶层目录 / 期望 id / zip 文件名
        var dirs = Directory.GetDirectories(extractRoot);
        if (dirs.Length == 1 && Directory.GetFiles(extractRoot).Length == 0)
        {
            var dn = Path.GetFileName(dirs[0]);
            return new Layout { Name = dn.Length > 0 ? dn : expectedId, SrcDir = dirs[0] };
        }
        return new Layout { Name = expectedId, SrcDir = extractRoot };
    }

    static string? FindPluginManifest(string dir, int depth)
    {
        if (depth > 3)
        {
            return null;
        }
        var manifest = Path.Combine(dir, "plugin.jsonc");
        if (File.Exists(manifest))
        {
            return manifest;
        }
        foreach (var sub in Directory.GetDirectories(dir))
        {
            var hit = FindPluginManifest(sub, depth + 1);
            if (hit != null)
            {
                return hit;
            }
        }
        return null;
    }

    /// <summary>plugin.jsonc 的 plugin.id（容错；解析失败返回 null）。</summary>
    public static string? ReadPluginId(string manifestPath)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(manifestPath), SpmContext.JsonDocOptions);
            if (doc.RootElement.TryGetProperty("plugin", out var p)
                && p.ValueKind == JsonValueKind.Object
                && p.TryGetProperty("id", out var id)
                && id.ValueKind == JsonValueKind.String)
            {
                var v = id.GetString();
                return string.IsNullOrWhiteSpace(v) ? null : v.Trim();
            }
        }
        catch { }
        return null;
    }

    // ==== 本地清单（版本记录）====

    public sealed class LocalManifest
    {
        public string Name { get; set; } = "";
        public string Version { get; set; } = "";
        public string Source { get; set; } = "";
        public string InstalledAt { get; set; } = "";
    }

    /// <summary>读包目录的本地清单；无清单返回 null（版本视为未知）。</summary>
    public static LocalManifest? ReadLocalManifest(string packageDir)
    {
        try
        {
            var path = Path.Combine(packageDir, "spm.json");
            if (File.Exists(path))
            {
                return JsonSerializer.Deserialize<LocalManifest>(File.ReadAllText(path));
            }
        }
        catch { }
        return null;
    }

    static void WriteLocalManifest(string packageDir, string name, string version, string source)
    {
        try
        {
            var path = Path.Combine(packageDir, "spm.json");
            if (File.Exists(path))
            {
                return; // 保留既有清单（重装语义 = 先 remove）
            }
            var manifest = new LocalManifest
            {
                Name = name,
                Version = version,
                Source = source,
                InstalledAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            };
            File.WriteAllText(path, JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // 清单写失败不阻断安装（outdated 显示 unknown 版本）
        }
    }

    // ==== 通用 ====

    /// <summary>移动目录；跨卷 IO 失败时回落 拷贝+删源。</summary>
    public static void TryMoveOrCopy(string srcDir, string destDir)
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

    public static void CopyDirectory(string srcDir, string destDir)
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

    public static bool IsValidName(string name)
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
}
