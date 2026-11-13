using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SlangAllInOne.Project;

/// <summary>
/// slang project：工程配置与目录扫描的 CLI 真源（2026-11-13，总纲 §0.2 CLI 先行）。
///   slang project info &lt;path&gt; [--json]                    工程信息 + 配置节点树 + 原始片段
///   slang project scan &lt;dir&gt; [--json] [--depth N]           递归扫描工程 .jsonc
///   slang project get &lt;path&gt; --key &lt;json.path&gt;           读一个键（结构化）
///   slang project set &lt;path&gt; --key &lt;json.path&gt; --value &lt;text&gt;  改一个键（保留注释/BOM/缩进）
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

        for (int i = 1; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "--json") json = true;
            else if ((a == "--depth") && i + 1 < args.Length && int.TryParse(args[++i], out int d)) depth = d;
            else if ((a == "--key" || a == "-k") && i + 1 < args.Length) key = args[++i];
            else if ((a == "--value" || a == "-v") && i + 1 < args.Length) value = args[++i];
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
            case "set": return Set(jsoncPath, key, value);
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

    private static int Set(string path, string key, string value)
    {
        var (parser, text, code) = Load(path, key);
        if (code != 0) return code;
        if (value.Length == 0)
        {
            Console.Error.WriteLine("[FAIL] 缺少 --value");
            return 2;
        }
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
            return 2;
        }
        var n = parser.ByPath[key];
        string updated = text.Substring(0, n.ValueStart) + literal + text.Substring(n.ValueEnd);
        WritePreservingBom(path, updated);
        Console.WriteLine($"Updated: {path}#{key} = {literal}");
        return 0;
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
  slang project set <path> --key <json.path> --value <text>
                                                        改一个键（保留注释/BOM/缩进）
  slang project raw <path> --key <json.path>             读一个节点的原始片段

<path> 可为 .jsonc / .sp / 工程目录；节点路径用 / 拼接，数组索引写 [i]，
例：export/moduleName、compileFiles/files/[0]/path");
    }
}
