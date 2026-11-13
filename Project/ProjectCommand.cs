using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SlangAllInOne.Project;

/// <summary>
/// slang project：工程配置与目录扫描的 CLI 真源（2026-11-13，总纲 §0.2 CLI 先行）。
///   slang project info &lt;path&gt; [--json]                    工程信息 + 配置节点树 + 原始片段
///   slang project scan &lt;dir&gt; [--json] [--depth N]           递归扫描工程 .jsonc
///   slang project get &lt;path&gt; --key &lt;json.path&gt;           读一个键（结构化）
///   slang project copy &lt;path&gt; --name &lt;New&gt; [--dest &lt;dir&gt;]  复制工程目录为新名副本（改名锚点 + 同步模块语义键）
///   slang project rename &lt;path&gt; --name &lt;New&gt;               重命名工程（改名 jsonc/sp + 同步模块语义键）
///   slang project delete &lt;path&gt;                             递归永久删除工程目录（危险，无回收）
///   slang project raw &lt;path&gt; --key &lt;json.path&gt;           读一个节点的原始片段
/// 约定：
///   · 节点路径用 / 拼接，数组索引写作 [i]；根路径由 IDE 自行加 root/&lt;文件&gt;。
///   · set 只替换目标值区间，绝不整份序列化（// 注释、缩进、键顺序、BOM 原样保留）。
///   · stdout 的 --json 为单行 / 缩进 JSON，便于 IDE 用 Text.Json 消费；日志走 stderr。
/// </summary>
internal static class ProjectCommand
{
    private sealed class NodeEntry
    {
        public string Path = "";
        public string Key = "";
        public string Type = "";
        public string Value = "";
        public int ChildCount;
        public string Raw = "";
        public int StartLine;
        public int EndLine;
        public int ValueStart;
        public int ValueEnd;
        public string Note = "";
        public string Source = "explicit";
    }

    private sealed class Parser
    {
        private readonly string _text;
        private int _pos;
        public readonly List<NodeEntry> Nodes = new();
        public readonly Dictionary<string, NodeEntry> ByPath = new(StringComparer.Ordinal);
        public string Error = "";

        public Parser(string text) { _text = text; }

        public bool Parse()
        {
            SkipSpace();
            if (_pos >= _text.Length || _text[_pos] != '{')
            {
                Error = "根节点不是 object";
                return false;
            }
            ParseObjectBody("");
            return Error.Length == 0;
        }

        private void SkipSpace()
        {
            while (_pos < _text.Length)
            {
                char c = _text[_pos];
                if (char.IsWhiteSpace(c)) { _pos++; continue; }
                if (c == '/' && _pos + 1 < _text.Length && _text[_pos + 1] == '/')
                {
                    _pos += 2;
                    while (_pos < _text.Length && _text[_pos] != '\n') _pos++;
                    continue;
                }
                if (c == '/' && _pos + 1 < _text.Length && _text[_pos + 1] == '*')
                {
                    _pos += 2;
                    while (_pos + 1 < _text.Length && !(_text[_pos] == '*' && _text[_pos + 1] == '/')) _pos++;
                    if (_pos + 1 < _text.Length) _pos += 2;
                    continue;
                }
                break;
            }
        }

        private int LineAt(int index)
        {
            int line = 1;
            for (int i = 0; i < index && i < _text.Length; i++)
                if (_text[i] == '\n') line++;
            return line;
        }

        public string Text => _text;

        private static string Join(string parent, string key) =>
            parent.Length == 0 ? key : parent + "/" + key;

        private bool Expect(char c)
        {
            SkipSpace();
            if (_pos < _text.Length && _text[_pos] == c) { _pos++; return true; }
            Error = $"第 {LineAt(_pos)} 行期望 '{c}'，实际 '{(_pos < _text.Length ? _text[_pos] : '?')}'";
            return false;
        }

        private string ReadStringRaw()
        {
            int start = _pos;
            if (_pos >= _text.Length || _text[_pos] != '"') return "";
            _pos++;
            while (_pos < _text.Length)
            {
                char c = _text[_pos];
                if (c == '\\') { _pos += 2; continue; }
                _pos++;
                if (c == '"') break;
            }
            return _text.Substring(start, Math.Min(_pos, _text.Length) - start);
        }

        private void ParseObjectBody(string parent)
        {
            Expect('{');
            int childCount = 0;
            while (true)
            {
                SkipSpace();
                if (_pos >= _text.Length) { Error = "object 未闭合"; return; }
                if (_text[_pos] == '}')
                {
                    _pos++;
                    if (parent.Length > 0 && ByPath.TryGetValue(parent, out var self))
                        self.ChildCount = childCount;
                    return;
                }
                int keyStart = _pos;
                string keyRaw = ReadStringRaw();
                if (keyRaw.Length < 2) { Error = $"第 {LineAt(keyStart)} 行键名解析失败"; return; }
                string key = Unquote(keyRaw);
                if (!Expect(':')) return;
                ParseValue(Join(parent, key), key, keyStart);
                childCount++;
                if (Error.Length > 0) return;
                SkipSpace();
                if (_pos < _text.Length && _text[_pos] == ',') { _pos++; continue; }
                SkipSpace();
                if (_pos < _text.Length && _text[_pos] == '}')
                {
                    _pos++;
                    if (parent.Length > 0 && ByPath.TryGetValue(parent, out var self2))
                        self2.ChildCount = childCount;
                    return;
                }
                Error = $"第 {LineAt(_pos)} 行 object 成员后缺少 ',' 或 '}}'";
                return;
            }
        }

        private void ParseArrayBody(string parent)
        {
            Expect('[');
            int index = 0;
            int childCount = 0;
            while (true)
            {
                SkipSpace();
                if (_pos >= _text.Length) { Error = "array 未闭合"; return; }
                if (_text[_pos] == ']')
                {
                    _pos++;
                    if (ByPath.TryGetValue(parent, out var self)) self.ChildCount = childCount;
                    return;
                }
                string key = "[" + index + "]";
                ParseValue(Join(parent, key), key, _pos);
                childCount++;
                index++;
                if (Error.Length > 0) return;
                SkipSpace();
                if (_pos < _text.Length && _text[_pos] == ',') { _pos++; continue; }
                SkipSpace();
                if (_pos < _text.Length && _text[_pos] == ']')
                {
                    _pos++;
                    if (ByPath.TryGetValue(parent, out var self2)) self2.ChildCount = childCount;
                    return;
                }
                Error = $"第 {LineAt(_pos)} 行 array 元素后缺少 ',' 或 ']'";
                return;
            }
        }

        private void ParseValue(string path, string key, int keyStart)
        {
            SkipSpace();
            int valueStart = _pos;
            var node = new NodeEntry
            {
                Path = path,
                Key = key,
                StartLine = LineAt(keyStart),
                ValueStart = valueStart,
            };
            Nodes.Add(node);
            ByPath[path] = node;

            if (_pos < _text.Length && _text[_pos] == '{')
            {
                node.Type = "object";
                ParseObjectBody(path);
            }
            else if (_pos < _text.Length && _text[_pos] == '[')
            {
                node.Type = "array";
                ParseArrayBody(path);
            }
            else if (_pos < _text.Length && _text[_pos] == '"')
            {
                node.Type = "string";
                string raw = ReadStringRaw();
                node.Value = Unquote(raw);
                _pos = valueStart + raw.Length;
            }
            else
            {
                int start = _pos;
                while (_pos < _text.Length)
                {
                    char c = _text[_pos];
                    if (c == ',' || c == '}' || c == ']' || c == '/' || char.IsWhiteSpace(c)) break;
                    _pos++;
                }
                string raw = _text.Substring(start, _pos - start);
                node.Value = raw;
                if (raw == "true" || raw == "false") node.Type = "bool";
                else if (raw == "null") node.Type = "null";
                else if (raw.Contains('.') || raw.Contains('e') || raw.Contains('E')) node.Type = "float";
                else node.Type = "int";
            }
            if (Error.Length > 0) return;

            node.ValueEnd = _pos;
            node.EndLine = LineAt(_pos);
            node.Raw = _text.Substring(keyStart, Math.Min(_pos, _text.Length) - keyStart);
            if (node.Type == "object") node.Value = "{…} (" + node.ChildCount + " 项)";
            if (node.Type == "array") node.Value = "[…] (" + node.ChildCount + " 项)";
            node.Note = NoteFor(path);
            if (path == "export/format" || path == "compile/optimize")
                node.Source = "CLI 可覆盖";
        }

        private static string Unquote(string raw)
        {
            if (raw.Length < 2) return raw;
            try
            {
                var n = JsonNode.Parse(raw);
                return n?.GetValue<string>() ?? raw;
            }
            catch (JsonException) { return raw.Substring(1, raw.Length - 2); }
        }

        private static string NoteFor(string path)
        {
            if (path == "project/buildSubVersion") return "无效键（Front 不解析）";
            if (path == "source/root" || path == "source/entryFile") return "已解析未消费";
            if (path == "export/debugText/outputDir") return "兼容保留（已失效）";
            if (path.EndsWith("/isVariadic", StringComparison.Ordinal)) return "缺省 true";
            string top = path.Split('/')[0];
            if (!KnownTopKeys.Contains(top)) return "未知键（Front 静默忽略）";
            if (path.StartsWith("compileFiles/files/[", StringComparison.Ordinal) && path.EndsWith("/path", StringComparison.Ordinal))
                return "必填";
            return "";
        }

        private static readonly HashSet<string> KnownTopKeys = new(StringComparer.Ordinal)
        {
            "project", "source", "compile", "compileFiles", "compileFilter", "global",
            "struct", "references", "dllImports", "lib", "vmDlls", "systemCalls",
            "plugins", "export", "platform", "publish", "spm",
        };
    }

    private sealed class InfoResult
    {
        public string Path = "";
        public string Dir = "";
        public string Name = "";
        public string Anchor = "";
        public string AnchorKind = "";
        public string Kind = "";
        public string ModuleName = "";
        public string Format = "";
        public bool HasSp;
        public string State = "ok";
        public string ParseError = "";
        public int SourceCount;
        public int MissingCount;
        public readonly List<JsonObject> CompileFiles = new();
        public readonly List<string> References = new();
        public readonly List<NodeEntry> Nodes = new();
    }

    public static int Run(string[] args)
    {
        if (args.Length == 0) { PrintUsage(); return 2; }
        string verb = args[0];
        string target = "";
        string key = "";
        string value = "";
        int depth = 8;
        bool json = false;
        bool add = false;
        string name = "";
        string dest = "";

        for (int i = 1; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "--json") json = true;
            else if (a == "--add") add = true;
            else if ((a == "--depth") && i + 1 < args.Length && int.TryParse(args[++i], out int d)) depth = d;
            else if ((a == "--key" || a == "-k") && i + 1 < args.Length) key = args[++i];
            else if ((a == "--value" || a == "-v") && i + 1 < args.Length) value = args[++i];
            else if ((a == "--name") && i + 1 < args.Length) name = args[++i];
            else if ((a == "--dest") && i + 1 < args.Length) dest = args[++i];
            else if (!a.StartsWith("--", StringComparison.Ordinal) && target.Length == 0) target = a;
            else { Console.Error.WriteLine("未知参数: " + a); PrintUsage(); return 2; }
        }

        if (target.Length == 0) { PrintUsage(); return 2; }

        if (verb.Equals("scan", StringComparison.OrdinalIgnoreCase))
            return Scan(target, depth, json);

        string jsoncPath = ResolveJsonc(target);
        if (jsoncPath.Length == 0)
        {
            Console.Error.WriteLine("[FAIL] 未找到工程 .jsonc: " + target);
            return 1;
        }

        switch (verb.ToLowerInvariant())
        {
            case "info": return Info(jsoncPath, json);
            case "get": return Get(jsoncPath, key, json);
            case "raw": return Raw(jsoncPath, key);
            case "set": return Set(jsoncPath, key, value, add);
            case "copy": return Copy(jsoncPath, name, dest);
            case "rename": return Rename(jsoncPath, name);
            case "delete": return DeleteProject(jsoncPath);
            default: PrintUsage(); return 2;
        }
    }

    private static string ResolveJsonc(string target)
    {
        string full = Path.GetFullPath(target);
        if (File.Exists(full))
        {
            if (full.EndsWith(".jsonc", StringComparison.OrdinalIgnoreCase)) return full;
            string sibling = Path.ChangeExtension(full, ".jsonc");
            if (File.Exists(sibling)) return sibling;
            string sameName = Path.Combine(full, Path.GetFileName(full) + ".jsonc");
            if (File.Exists(sameName)) return sameName;
            return "";
        }
        if (Directory.Exists(full))
        {
            var candidates = Directory.GetFiles(full, "*.jsonc", SearchOption.TopDirectoryOnly)
                .Where(p => !p.EndsWith("plugin.jsonc", StringComparison.OrdinalIgnoreCase))
                .OrderBy(p => p, StringComparer.Ordinal).ToArray();
            return candidates.Length > 0 ? Path.GetFullPath(candidates[0]) : "";
        }
        return "";
    }

    private static string ReadText(string path) => File.ReadAllText(path, Encoding.UTF8);

    // ---- test（2026-11-13 第十八轮，总纲 §0.2 CLI 先行：IDE 测试动作的 CLI 真源）----
    // 约定：工程下 tests/ 目录存在时，其下每个含 .jsonc 的 <Name>/ 目录工程为一个
    // 测试用例（入口 = 同名 .sp，缺省回落该目录 .jsonc）。注意：无 sibling jsonc 的
    // .sp 会被 Front 向上吸附到外层工程（实测），故散落 .sp 不作用例；每个用例按
    // 裸工程语义编译（memory 内存交接，零落盘）+ 运行，退出码 0 = PASS。收集在本
    // 文件，循环复用宿主裸工程链路（Program.RunTests → RunProject）。

    internal static string ResolveJsoncPath(string target) => ResolveJsonc(target);

    /// <summary>收集 tests/ 用例（名称升序；无 tests/ 目录或空目录返回空表）。</summary>
    internal static List<(string Name, string Anchor)> CollectTestCases(string jsoncPath)
    {
        var cases = new List<(string Name, string Anchor)>();
        string dir = Path.GetDirectoryName(Path.GetFullPath(jsoncPath))!;
        string testsDir = Path.Combine(dir, "tests");
        if (!Directory.Exists(testsDir)) return cases;
        foreach (string d in Directory.EnumerateDirectories(testsDir).OrderBy(p => p, StringComparer.Ordinal))
        {
            string jsonc = ResolveJsonc(d);
            if (jsonc.Length == 0) continue;
            string leaf = Path.GetFileName(d);
            string sp = Directory.GetFiles(d, leaf + ".sp", SearchOption.TopDirectoryOnly).FirstOrDefault()
                ?? Directory.GetFiles(d, "*.sp", SearchOption.TopDirectoryOnly).FirstOrDefault();
            cases.Add((leaf, sp ?? jsonc));
        }
        return cases;
    }

    // ---- copy / rename / delete（2026-11-13，总纲 §0.2 CLI 先行：IDE 的工程
    // 复制 / 重命名 / 删除只组装参数调这三条命令，不做本地目录语义） ----

    private static bool ValidProjectName(string name)
    {
        if (name.Length == 0) return false;
        if (name == "." || name == "..") return false;
        foreach (char c in name)
        {
            if (c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' ||
                c == '"' || c == '<' || c == '>' || c == '|') return false;
        }
        return true;
    }

    private static void CopyDirectory(string src, string dst)
    {
        Directory.CreateDirectory(dst);
        foreach (string f in Directory.EnumerateFiles(src))
            File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), overwrite: false);
        foreach (string d in Directory.EnumerateDirectories(src))
            CopyDirectory(d, Path.Combine(dst, Path.GetFileName(d)));
    }

    /// <summary>副本内改写模块语义键（存在才改，缺失跳过；不改其它内容）。</summary>
    private static void ReplaceKey(string jsoncPath, string key, string literal)
    {
        string text = File.ReadAllText(jsoncPath, Encoding.UTF8);
        var parser = new Parser(text);
        if (!parser.Parse() || !parser.ByPath.TryGetValue(key, out NodeEntry? n) || n == null) return;
        string updated = text.Substring(0, n.ValueStart) + JsonSerializer.Serialize(literal) + text.Substring(n.ValueEnd);
        WritePreservingBom(jsoncPath, updated);
    }

    private static int Copy(string jsoncPath, string name, string dest)
    {
        if (!ValidProjectName(name))
        {
            Console.Error.WriteLine("[FAIL] --name 非法: \"" + name + "\"");
            return 2;
        }
        string dir = Path.GetDirectoryName(Path.GetFullPath(jsoncPath))!;
        string destDir = dest.Length > 0 ? Path.GetFullPath(dest) : Path.GetDirectoryName(dir)!;
        string targetDir = Path.Combine(destDir, name);
        if (Directory.Exists(targetDir))
        {
            Console.Error.WriteLine("[FAIL] 目标目录已存在: " + targetDir);
            return 1;
        }
        try
        {
            CopyDirectory(dir, targetDir);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[FAIL] 复制失败: " + ex.Message);
            try { Directory.Delete(targetDir, true); } catch { }
            return 1;
        }
        // 副本内锚点文件改名为 <name>.jsonc / <name>.sp
        string oldJsoncName = Path.GetFileName(jsoncPath);
        string newJsonc = Path.Combine(targetDir, name + ".jsonc");
        if (!string.Equals(oldJsoncName, name + ".jsonc", StringComparison.Ordinal))
        {
            string copiedJsonc = Path.Combine(targetDir, oldJsoncName);
            if (File.Exists(copiedJsonc)) File.Move(copiedJsonc, newJsonc);
        }
        string newSp = Path.Combine(targetDir, name + ".sp");
        string oldSp = Path.Combine(targetDir, Path.GetFileNameWithoutExtension(jsoncPath) + ".sp");
        if (File.Exists(oldSp) && !string.Equals(oldSp, newSp, StringComparison.Ordinal))
        {
            File.Move(oldSp, newSp);
        }
        if (!File.Exists(newJsonc))
        {
            Console.Error.WriteLine("[FAIL] 副本缺 .jsonc: " + newJsonc);
            return 1;
        }
        ReplaceKey(newJsonc, "project/name", name);
        ReplaceKey(newJsonc, "export/moduleName", name);
        Console.WriteLine("Copied: " + jsoncPath + " -> " + newJsonc);
        return 0;
    }

    private static int Rename(string jsoncPath, string name)
    {
        if (!ValidProjectName(name))
        {
            Console.Error.WriteLine("[FAIL] --name 非法: \"" + name + "\"");
            return 2;
        }
        string dir = Path.GetDirectoryName(Path.GetFullPath(jsoncPath))!;
        string newJsonc = Path.Combine(dir, name + ".jsonc");
        if (File.Exists(newJsonc))
        {
            Console.Error.WriteLine("[FAIL] 目标已存在: " + newJsonc);
            return 1;
        }
        string newSp = Path.Combine(dir, name + ".sp");
        if (File.Exists(newSp))
        {
            Console.Error.WriteLine("[FAIL] 目标已存在: " + newSp);
            return 1;
        }
        string oldSp = Path.ChangeExtension(jsoncPath, ".sp");
        File.Move(jsoncPath, newJsonc);
        if (File.Exists(oldSp)) File.Move(oldSp, newSp);
        ReplaceKey(newJsonc, "project/name", name);
        ReplaceKey(newJsonc, "export/moduleName", name);
        Console.WriteLine("Renamed: " + jsoncPath + " -> " + newJsonc);
        return 0;
    }

    private static int DeleteProject(string jsoncPath)
    {
        string dir = Path.GetDirectoryName(Path.GetFullPath(jsoncPath))!;
        if (dir.Length < 4 || dir.EndsWith(":/", StringComparison.Ordinal) || dir.EndsWith(":\\", StringComparison.Ordinal))
        {
            Console.Error.WriteLine("[FAIL] 目录异常，拒绝删除: " + dir);
            return 1;
        }
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[FAIL] 删除失败: " + ex.Message);
            return 1;
        }
        Console.WriteLine("Deleted: " + dir);
        return 0;
    }

    private static InfoResult BuildInfo(string jsoncPath, bool withNodes)
    {
        string full = Path.GetFullPath(jsoncPath);
        string dir = Path.GetDirectoryName(full) ?? "";
        string name = Path.GetFileNameWithoutExtension(full);
        var info = new InfoResult
        {
            Path = full,
            Dir = dir,
            Name = name,
            Anchor = full,
            AnchorKind = "jsonc",
            Kind = "module",
            State = "parseError",
        };

        string sp = Path.Combine(dir, name + ".sp");
        if (File.Exists(sp))
        {
            info.HasSp = true;
            info.Anchor = sp;
            info.AnchorKind = "sp";
            info.Kind = "app";
        }

        string text;
        try { text = ReadText(full); }
        catch (IOException ex)
        {
            info.ParseError = ex.Message;
            return info;
        }

        var parser = new Parser(text);
        bool parsed = parser.Parse();
        info.State = parsed ? "ok" : "parseError";
        info.ParseError = parser.Error;
        if (withNodes) info.Nodes.AddRange(parser.Nodes);

        bool hasFeature = parser.ByPath.ContainsKey("project/name") ||
                          parser.ByPath.ContainsKey("compileFiles/files") ||
                          parser.ByPath.ContainsKey("export/moduleName");
        if (!hasFeature && !info.HasSp) info.State = "unconfirmed";

        info.ModuleName = ValueOf(parser, "export/moduleName");
        if (info.ModuleName.Length == 0) info.ModuleName = ValueOf(parser, "project/name");
        if (info.ModuleName.Length == 0) info.ModuleName = name;
        info.Format = ValueOf(parser, "export/format");

        // compileFiles.files[] 逐个核对存在 / ignore / 必填 path
        if (parser.ByPath.TryGetValue("compileFiles/files", out var filesNode))
        {
            foreach (var n in parser.Nodes)
            {
                if (!n.Path.StartsWith("compileFiles/files/[", StringComparison.Ordinal)) continue;
                if (!n.Path.Contains("]")) continue;
                int close = n.Path.IndexOf(']');
                int open = n.Path.IndexOf('[', StringComparison.Ordinal);
                string indexPart = n.Path.Substring(open + 1, close - open - 1);
                string prefix = "compileFiles/files/[" + indexPart + "]";
                if (n.Path != prefix) continue;
                string rel = ValueOf(parser, prefix + "/path");
                string group = ValueOf(parser, prefix + "/group");
                string tag = ValueOf(parser, prefix + "/tag");
                string ignoreRaw = ValueOf(parser, prefix + "/ignore");
                string priorityRaw = ValueOf(parser, prefix + "/priority");
                bool ignore = ignoreRaw == "true";
                bool exists = rel.Length > 0 && File.Exists(Path.GetFullPath(Path.Combine(dir, rel)));
                if (!exists) info.MissingCount++;
                info.SourceCount++;
                var item = new JsonObject
                {
                    ["path"] = rel,
                    ["group"] = group,
                    ["tag"] = tag,
                    ["ignore"] = ignore,
                    ["priority"] = int.TryParse(priorityRaw, out int pri) ? pri : 0,
                    ["exists"] = exists,
                    ["absPath"] = rel.Length > 0 ? Path.GetFullPath(Path.Combine(dir, rel)) : "",
                    ["valid"] = rel.Length > 0,
                };
                info.CompileFiles.Add(item);
            }
        }
        if (info.MissingCount > 0 && info.State == "ok") info.State = "missing";

        foreach (var n in parser.Nodes)
        {
            if (n.Path.StartsWith("references/[", StringComparison.Ordinal) && !n.Path.Contains("/"))
                continue;
            if (n.Path.StartsWith("references/[", StringComparison.Ordinal) && n.Path.EndsWith("/path", StringComparison.Ordinal))
                info.References.Add(n.Value);
        }
        return info;
    }

    private static string ValueOf(Parser parser, string path) =>
        parser.ByPath.TryGetValue(path, out var n) ? n.Value : "";

    private static JsonObject InfoToJson(InfoResult info, bool withNodes)
    {
        var root = new JsonObject
        {
            ["ok"] = info.State != "parseError",
            ["path"] = info.Path,
            ["dir"] = info.Dir,
            ["name"] = info.Name,
            ["anchor"] = info.Anchor,
            ["anchorKind"] = info.AnchorKind,
            ["kind"] = info.Kind,
            ["moduleName"] = info.ModuleName,
            ["format"] = info.Format,
            ["hasSp"] = info.HasSp,
            ["state"] = info.State,
            ["parseError"] = info.ParseError,
            ["sourceCount"] = info.SourceCount,
            ["missingCount"] = info.MissingCount,
            // 显式计数：SL 侧 BaseJson 没有数组长度 API，IDE 按 count + 索引遍历
            ["fileCount"] = info.CompileFiles.Count,
            ["referenceCount"] = info.References.Count,
            ["nodeCount"] = info.Nodes.Count,
        };
        var files = new JsonArray();
        // 必须走非泛型 Add(JsonNode?)：泛型 Add<T> 会生成 JsonValueCustomized<T>，
        // Native AOT 下 ToJsonString 需要 TypeInfoResolver（实测崩溃）
        foreach (var f in info.CompileFiles) files.Add((JsonNode)f.DeepClone());
        root["compileFiles"] = files;
        var refs = new JsonArray();
        foreach (var r in info.References) refs.Add(JsonValue.Create(r));
        root["references"] = refs;
        if (withNodes)
        {
            var nodes = new JsonArray();
            foreach (var n in info.Nodes)
            {
                nodes.Add(new JsonObject
                {
                    ["path"] = n.Path,
                    ["key"] = n.Key,
                    ["type"] = n.Type,
                    ["value"] = n.Value,
                    ["childCount"] = n.ChildCount,
                    ["raw"] = n.Raw,
                    ["startLine"] = n.StartLine,
                    ["endLine"] = n.EndLine,
                    ["note"] = n.Note,
                    ["source"] = n.Source,
                });
            }
            root["nodes"] = nodes;
        }
        return root;
    }

    private static int Info(string path, bool json)
    {
        var info = BuildInfo(path, withNodes: true);
        if (json)
        {
            Console.WriteLine(InfoToJson(info, true).ToJsonString());
            return info.State == "parseError" ? 1 : 0;
        }
        Console.WriteLine($"Project: {info.Name} [{info.Kind}] state={info.State}");
        Console.WriteLine($"Anchor: {info.Anchor} ({(info.HasSp ? "有 .sp" : "无 .sp（库模块）")})");
        Console.WriteLine($"Module: {info.ModuleName}  Format: {info.Format}");
        Console.WriteLine($"Files: {info.SourceCount}  Missing: {info.MissingCount}  Nodes: {info.Nodes.Count}");
        foreach (var f in info.CompileFiles)
            Console.WriteLine($"  {(f["exists"]?.GetValue<bool>() == true ? "OK " : "MISS")} {f["path"]?.GetValue<string>()}");
        if (info.ParseError.Length > 0) Console.WriteLine("ParseError: " + info.ParseError);
        return info.State == "parseError" ? 1 : 0;
    }

    private static int Scan(string dir, int depth, bool json)
    {
        string full = Path.GetFullPath(dir);
        if (!Directory.Exists(full))
        {
            Console.Error.WriteLine("[FAIL] 目录不存在: " + full);
            return 1;
        }
        var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".git", "node_modules", "out", "publish", "build", "bin", "obj", ".codebuddy",
        };
        var list = new JsonArray();
        int seen = 0;
        int projects = 0;
        foreach (string file in Directory.EnumerateFiles(full, "*.jsonc", SearchOption.AllDirectories))
        {
            if (++seen > 2000) { Console.Error.WriteLine("[WARN] 超过 2000 个文件，已截断"); break; }
            string rel = Path.GetRelativePath(full, file);
            int segments = rel.Split(Path.DirectorySeparatorChar).Length;
            if (segments > depth) continue;
            if (Path.GetFileName(file).Equals("plugin.jsonc", StringComparison.OrdinalIgnoreCase)) continue;
            bool skip = rel.Split(Path.DirectorySeparatorChar, '/')
                .Any(seg => excluded.Contains(seg));
            if (skip) continue;
            if (projects >= 200) { Console.Error.WriteLine("[WARN] 超过 200 个工程，已截断"); break; }
            var info = BuildInfo(file, withNodes: false);
            var item = InfoToJson(info, false);
            item["relPath"] = rel.Replace('\\', '/');
            list.Add(item);
            projects++;
        }
        if (json)
        {
            var wrapper = new JsonObject
            {
                ["ok"] = true,
                ["scanRoot"] = full.Replace('\\', '/'),
                ["count"] = projects,
                ["projects"] = list,
            };
            Console.WriteLine(wrapper.ToJsonString());
            return 0;
        }
        Console.WriteLine($"ScanRoot: {full}  Projects: {projects}");
        foreach (var node in list)
        {
            var o = node!.AsObject();
            Console.WriteLine($"  {o["relPath"]?.GetValue<string>()}  kind={o["kind"]?.GetValue<string>()} state={o["state"]?.GetValue<string>()} files={o["sourceCount"]?.GetValue<int>()} missing={o["missingCount"]?.GetValue<int>()}");
        }
        return 0;
    }

    private static (Parser Parser, string Text, int Code) Load(string path, string key)
    {
        if (key.Length == 0)
        {
            Console.Error.WriteLine("[FAIL] 缺少 --key");
            return (new Parser("{}"), "", 2);
        }
        string text = ReadText(path);
        var parser = new Parser(text);
        if (!parser.Parse())
        {
            Console.Error.WriteLine("[FAIL] jsonc 解析失败: " + parser.Error);
            return (parser, text, 1);
        }
        if (!parser.ByPath.ContainsKey(key))
        {
            Console.Error.WriteLine("[FAIL] 未找到键路径: " + key);
            return (parser, text, 1);
        }
        return (parser, text, 0);
    }

    private static int Get(string path, string key, bool json)
    {
        var (parser, _, code) = Load(path, key);
        if (code != 0) return code;
        var n = parser.ByPath[key];
        if (json)
        {
            Console.WriteLine(new JsonObject
            {
                ["ok"] = true,
                ["path"] = key,
                ["type"] = n.Type,
                ["value"] = n.Value,
                ["raw"] = n.Raw,
                ["note"] = n.Note,
            }.ToJsonString());
            return 0;
        }
        Console.WriteLine($"{key} = {n.Value}  ({n.Type})");
        return 0;
    }

    private static int Raw(string path, string key)
    {
        var (parser, _, code) = Load(path, key);
        if (code != 0) return code;
        Console.Write(parser.ByPath[key].Raw);
        Console.WriteLine();
        return 0;
    }

    private static int Set(string path, string key, string value, bool add)
    {
        if (key.Length == 0) { Console.Error.WriteLine("[FAIL] 缺少 --key"); return 2; }
        if (value.Length == 0) { Console.Error.WriteLine("[FAIL] 缺少 --value"); return 2; }
        if (key.Split('/').Any(s => s.Length == 0))
        {
            Console.Error.WriteLine("[FAIL] 键路径含空段: " + key);
            return 2;
        }
        string text = ReadText(path);
        var parser = new Parser(text);
        if (!parser.Parse())
        {
            Console.Error.WriteLine("[FAIL] jsonc 解析失败: " + parser.Error);
            return 1;
        }
        string literal = ToLiteral(value);
        if (literal.Length == 0) return 2;

        if (parser.ByPath.ContainsKey(key))
        {
            if (add)
            {
                Console.Error.WriteLine("[FAIL] 键已存在，--add 只用于新增缺失键: " + key);
                return 1;
            }
            var n = parser.ByPath[key];
            string updated = text.Substring(0, n.ValueStart) + literal + text.Substring(n.ValueEnd);
            WritePreservingBom(path, updated);
            Console.WriteLine($"Updated: {path}#{key} = {literal}");
            return 0;
        }
        if (!add)
        {
            Console.Error.WriteLine("[FAIL] 未找到键路径: " + key + "（新增请加 --add）");
            return 1;
        }

        string inserted = InsertNewKey(parser, text, key, literal);
        if (inserted.Length == 0) return 1;
        WritePreservingBom(path, inserted);
        Console.WriteLine($"Added: {path}#{key} = {literal}");
        return 0;
    }

    /// <summary>--value 转 JSON 字面量：裸文本自动加引号；非法 JSON 报错返回空串。</summary>
    private static string ToLiteral(string value)
    {
        string literal = value;
        char first = value[0];
        if (!(first == '"' || first == '{' || first == '[' || first == '-' ||
              char.IsDigit(first) || value == "true" || value == "false" || value == "null"))
        {
            literal = JsonSerializer.Serialize(value);
        }
        try { JsonNode.Parse(literal); }
        catch (JsonException ex)
        {
            Console.Error.WriteLine("[FAIL] --value 不是合法 JSON 值: " + ex.Message);
            return "";
        }
        return literal;
    }

    /// <summary>
    /// 新增缺失键：找到最长已存在祖先（object 内插入成员 / array 末尾追加元素），
    /// 中间缺失的段构造嵌套 object；绝不动既有区间，注释/BOM/缩进保留。
    /// 返回改写后的全文；失败（含数组中间插入）打印 [FAIL] 并返回空串。
    /// </summary>
    private static string InsertNewKey(Parser parser, string text, string key, string literal)
    {
        string[] segs = key.Split('/');
        int match = 0;
        while (match < segs.Length)
        {
            string prefix = string.Join("/", segs, 0, match + 1);
            if (!parser.ByPath.ContainsKey(prefix)) break;
            match++;
        }
        string parentPath = match > 0 ? string.Join("/", segs, 0, match) : "";
        NodeEntry parentNode = parentPath.Length > 0 ? parser.ByPath[parentPath] : null;

        if (parentNode != null && parentNode.Type == "array")
        {
            string tailSeg = segs[match];
            if (tailSeg != "[" + parentNode.ChildCount + "]")
            {
                Console.Error.WriteLine($"[FAIL] 数组只支持末尾追加元素 [{parentNode.ChildCount}]，不能写: " + key);
                return "";
            }
            // 元素本身，或元素内嵌套键（[i]/a/b → 元素为嵌套 object）
            string element = literal;
            for (int i = segs.Length - 1; i > match; i--)
                element = "{ " + JsonSerializer.Serialize(segs[i]) + ": " + element + " }";
            return InsertIntoContainer(parser, text, parentNode, element);
        }
        if (parentNode != null && parentNode.Type != "object")
        {
            Console.Error.WriteLine("[FAIL] 父节点是 " + parentNode.Type + "，只能新增 object 子键或向 array 追加元素");
            return "";
        }
        // object / 根：缺失的中间段构造嵌套容器；直接子键 = segs[match]。
        // 段为 "[i]"（新建数组）→ 构造数组字面量（i>0 用 null 占位）；
        // 其余段 → 构造嵌套 object。
        string member = literal;
        for (int i = segs.Length - 1; i > match; i--)
        {
            int arrIdx = ArrayIndexOf(segs[i]);
            if (arrIdx >= 0)
            {
                string pad = "";
                for (int k = 0; k < arrIdx; k++) pad += "null, ";
                member = "[ " + pad + member + " ]";
            }
            else
            {
                member = "{ " + JsonSerializer.Serialize(segs[i]) + ": " + member + " }";
            }
        }
        member = JsonSerializer.Serialize(segs[match]) + ": " + member;
        return InsertIntoContainer(parser, text, parentNode, member);
    }

    /// <summary>"[3]" → 3；非数组段 → -1。</summary>
    private static int ArrayIndexOf(string seg)
    {
        if (!seg.StartsWith("[", StringComparison.Ordinal) || !seg.EndsWith("]", StringComparison.Ordinal))
            return -1;
        return int.TryParse(seg.Substring(1, seg.Length - 2), out int v) ? v : -1;
    }

    /// <summary>向 object（node=null 表示根）的闭括号前插入一个成员，或向 array 追加一个元素。</summary>
    private static string InsertIntoContainer(Parser parser, string text, NodeEntry node, string member)
    {
        bool atRoot = node == null;
        char closeChar = (node != null && node.Type == "array") ? ']' : '}';
        int braceIdx;
        int openIdx;
        if (atRoot)
        {
            braceIdx = text.LastIndexOf('}');
            if (braceIdx < 0) { Console.Error.WriteLine("[FAIL] 全文缺少根 '}'"); return ""; }
            openIdx = 0;
        }
        else
        {
            braceIdx = node.ValueEnd - 1;
            openIdx = node.ValueStart;
            if (braceIdx < 0 || braceIdx >= text.Length || text[braceIdx] != closeChar)
            {
                Console.Error.WriteLine("[FAIL] 容器区间解析异常: " + node.Path);
                return "";
            }
        }
        // 成员缩进：容器已有成员 → 直接取其行缩进；否则空容器按「闭括号缩进 + 基准缩进」、根按基准缩进
        NodeEntry firstChild = atRoot ? FirstNode(parser) : FirstDirectChild(parser, node);
        string closeIndent = LeadingWhitespace(text, braceIdx);
        string memberIndent;
        if (firstChild != null)
        {
            memberIndent = LeadingWhitespaceOfLine(text, firstChild.StartLine);
        }
        else
        {
            memberIndent = atRoot ? DetectBaseIndent(text) : closeIndent + DetectBaseIndent(text);
        }

        // 插入点 = 闭括号前最后一个内容字符（跳过空白与注释）；
        // 前面是开括号/尾逗号/冒号时只换行，否则补逗号（避免产生 ",,"）
        int insertAt = LastContentIndex(text, braceIdx - 1, openIdx);
        if (insertAt < openIdx) insertAt = openIdx;
        char last = text[insertAt];
        string sep = (last == '{' || last == '[' || last == ',' || last == ':') ? "\n" : ",\n";
        return text.Substring(0, insertAt + 1) + sep + memberIndent + member
            + "\n" + closeIndent + text.Substring(braceIdx);
    }

    /// <summary>从 from 向前找最后一个内容字符：跳过空白、// 行注释与 /* */ 块注释。</summary>
    private static int LastContentIndex(string text, int from, int floor)
    {
        int i = from;
        while (i > floor)
        {
            char c = text[i];
            if (char.IsWhiteSpace(c)) { i--; continue; }
            if (c == '/')
            {
                int lineStart = i;
                while (lineStart > floor && text[lineStart - 1] != '\n') lineStart--;
                int ls = lineStart;
                while (ls < i && (text[ls] == ' ' || text[ls] == '\t')) ls++;
                if (ls + 1 <= i && text[ls] == '/' && text[ls + 1] == '/')
                {
                    i = lineStart - 1;
                    continue;
                }
                if (i > floor && text[i - 1] == '*')
                {
                    int start = text.LastIndexOf("/*", i, StringComparison.Ordinal);
                    if (start > floor) { i = start - 1; continue; }
                }
            }
            return i;
        }
        return floor;
    }

    private static NodeEntry FirstNode(Parser parser) =>
        parser.Nodes.Count > 0 ? parser.Nodes[0] : null;

    private static NodeEntry FirstDirectChild(Parser parser, NodeEntry node)
    {
        string prefix = node.Path + "/";
        foreach (var n in parser.Nodes)
        {
            if (!n.Path.StartsWith(prefix, StringComparison.Ordinal)) continue;
            if (n.Path.IndexOf('/', prefix.Length) < 0) return n;
        }
        return null;
    }

    private static string LeadingWhitespace(string text, int index)
    {
        int lineStart = text.LastIndexOf('\n', Math.Max(0, index - 1)) + 1;
        int i = lineStart;
        while (i < text.Length && (text[i] == ' ' || text[i] == '\t')) i++;
        return text.Substring(lineStart, i - lineStart);
    }

    /// <summary>按 1-based 行号取该行行首缩进（NodeEntry.StartLine 是行号不是字符下标）。</summary>
    private static string LeadingWhitespaceOfLine(string text, int line)
    {
        int idx = 0;
        int cur = 1;
        while (cur < line && idx < text.Length)
        {
            if (text[idx] == '\n') cur++;
            idx++;
        }
        int i = idx;
        while (i < text.Length && (text[i] == ' ' || text[i] == '\t')) i++;
        return text.Substring(idx, i - idx);
    }

    private static string DetectBaseIndent(string text)
    {
        int i = 0;
        while (i < text.Length)
        {
            int j = i;
            while (j < text.Length && (text[j] == ' ' || text[j] == '\t')) j++;
            if (j > i && j < text.Length && text[j] == '"') return text.Substring(i, j - i);
            while (j < text.Length && text[j] != '\n') j++;
            if (j >= text.Length) break;
            i = j + 1;
        }
        return "    ";
    }

    /// <summary>改写既有 jsonc 保持原 BOM 形态（R16，与 NewCommand 同口径）。</summary>
    private static void WritePreservingBom(string path, string content)
    {
        bool hasBom = false;
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            hasBom = fs.ReadByte() == 0xEF && fs.ReadByte() == 0xBB && fs.ReadByte() == 0xBF;
        }
        catch (IOException) { hasBom = true; }
        File.WriteAllText(path, content, new UTF8Encoding(hasBom));
    }

    private static void PrintUsage()
    {
        Console.WriteLine(@"用法:
  slang project info <path> [--json]                     工程信息 + 配置节点树 + 原始片段
  slang project scan <dir> [--json] [--depth N]          递归扫描工程 .jsonc（默认深度 8）
  slang project get <path> --key <json.path> [--json]    读一个键
  slang project set <path> --key <json.path> --value <text> [--add]
                                                        改一个键；--add 新增缺失键/段（支持嵌套段与数组末尾追加）
  slang project copy <path> --name <New> [--dest <dir>]  复制工程为新名副本（锚点改名 + 同步 project.name/export.moduleName）
  slang project rename <path> --name <New>               重命名工程（jsonc/sp 改名 + 语义键同步）
  slang project delete <path>                            递归永久删除工程目录（无回收站）
  slang project raw <path> --key <json.path>             读一个节点的原始片段

<path> 可为 .jsonc / .sp / 工程目录；节点路径用 / 拼接，数组索引写 [i]，
例：export/moduleName、compileFiles/files/[0]/path");
    }
}
