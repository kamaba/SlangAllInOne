//****************************************************************************
//  File:      LspServer.cs
// ------------------------------------------------
//  slang lsp —— 内嵌于宿主的 LSP 3.17 服务器（stdio JSON-RPC，一工作区一实例）。
//
//  范围（slang_vscode_plugin\07_language_server_lsp.md）：
//   L1（2026-10-19）诊断推送 + 全局符号补全；
//   L2（2026-10-19）成员感知补全（IDENT. → 类成员）+ 悬停 + 定义跳转 + 文档大纲。
//
//  数据模型（module.json / 内存包 json 实测）：
//   - classList：{id, name, fullName, sourcePath, metaClassKind, baseClassId,
//     fieldList[{name,typeDef.className,express[0].debugInfo{path,beginLine,beginChar}}],
//     staticMethodList/nonStaticMethodList[{id,name}]（瘦引用，已含继承成员）}；
//   - 顶层 methodList：胖条目 {id(字符串), name, declaringTypeFullName,
//     returnList[0].typeDef.className, argumentList[{name,typeDef.className}],
//     instructionList[].debugInfo{path,beginLine,beginChar}}——按 id 与类内瘦条目关联；
//   - sourcePath 相对模块源根（工程包=工程目录；引用模块=SLangCore\Lib\<模块>）。
//
//  同步语义：Full（change:1）+ save(includeText)——保存态诊断不变（Front 读磁盘），
//  内存文本仅供补全/悬停/跳转/大纲的即时上下文。
//
//  stdout 专用于协议帧：启动即 Console.SetOut(Console.Error)，Front 日志镜像
//  全部改走 stderr，杜绝污染协议流。
//****************************************************************************
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using SimpleLanguage.Export.SLIR.Binary;

namespace SlangAllInOne.Lsp;

internal sealed class LspServer
{
    // ==== 符号模型 ====
    private sealed class MethodInfo
    {
        public required string Name;
        public string Declaring = "";                       // 声明类名（胖条目 declaringTypeFullName）
        public string ReturnType = "";                      // returnList[0].typeDef.className
        public List<string> Args = new();                   // "Type name" 列表
        public string SourcePath = "";                      // debugInfo 首个有效 path（缺省空）
        public int BeginLine = 0;                           // 1-based；0 = 未知
        public int BeginChar = 0;
        public bool IsStatic;
        public string Signature => (IsStatic ? "static " : "") + (ReturnType.Length > 0 ? ReturnType + " " : "") + Name + "(" + string.Join(", ", Args) + ")";
    }

    private sealed class FieldInfo
    {
        public required string Name;
        public string Type = "";
        public string SourcePath = "";
        public int BeginLine = 0;
        public int BeginChar = 0;
    }

    private sealed class ClassInfo
    {
        public required string Name;
        public required string FullName;
        public string SourcePath = "";
        public int Kind = 7;                                 // CompletionItemKind（Class）
        public List<MethodInfo> StaticMethods = new();
        public List<MethodInfo> InstanceMethods = new();
        public List<FieldInfo> Fields = new();
        public bool IsProject;                               // 工程自身（定义跳转基准=工程目录）
    }

    private sealed class PackageSymbols
    {
        public string ModuleName = "";
        public List<ClassInfo> Classes = new();
        public List<object> SystemCalls = new();   // 系统方法补全项（slb/json 双路兼容）
    }

    private sealed class MergedTable
    {
        public List<ClassInfo> Classes = new();
        public Dictionary<string, ClassInfo> ByName = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, ClassInfo> ByFullName = new(StringComparer.OrdinalIgnoreCase);
    }

    // ==== 协议流 ====
    private readonly Stream _stdin;
    private readonly Stream _stdout;
    private readonly object _writeLock = new();

    // ==== 状态 ====
    private sealed class ProjectInfo
    {
        public required string SpPath;
        public required string Dir;
    }
    private readonly Dictionary<string, ProjectInfo> _docs = new();
    private readonly Dictionary<string, string> _docText = new();               // uri → 最新全文（Full 同步）
    private readonly Dictionary<string, ProjectInfo> _dirCache = new();
    private readonly Dictionary<string, PackageSymbols> _projectPackages = new(); // spPath → 工程符号
    private readonly Dictionary<string, PackageSymbols> _refPackages = new();     // module.json 路径 → 引用符号
    private readonly Dictionary<string, string> _refJsonRoot = new();             // module.json 路径 → 源根（定义跳转解析基准）
    private readonly Dictionary<string, ProjectInfo> _symbolProjects = new();
    private readonly Dictionary<string, HashSet<string>> _publishedFiles = new();
    private int _diagVersion = 0;
    private readonly SemaphoreSlim _diagLock = new(1, 1);
    private bool _shutdown = false;

    private static readonly string[] Keywords =
    {
        // 声明与结构（keywords.md §1.1）
        "typealias", "import", "as", "namespace", "class", "extends", "interface",
        "abstract", "enum", "data", "dynamic", "void", "extern", "bind", "label",
        // 修饰符（§1.2）
        "public", "protected", "private", "const", "mut", "final", "static",
        "inline", "partial", "override", "params",
        // 控制流（§1.3）
        "if", "elif", "else", "while", "dowhile", "for", "in", "out", "switch",
        "case", "default", "next", "continue", "break", "goto", "ret",
        // 异常（§1.4）
        "try", "catch", "finally", "throw", "throws", "checked", "unchecked",
        // 对象/值/协程（§1.5）
        "new", "var", "function", "this", "base", "await", "spawn", "yield",
        "get", "set",
    };

    private LspServer(Stream stdin, Stream stdout)
    {
        _stdin = stdin;
        _stdout = stdout;
    }

    public static int Run(string[] args)
    {
        bool stdio = args.Length == 0 || args[0] == "--stdio";
        if (!stdio)
        {
            Console.Error.WriteLine("slang lsp: 仅支持 --stdio（缺省即 stdio）");
            return 2;
        }
        // stdout 专用于协议帧；Console 全部输出（Front 日志镜像/宿主提示）改走 stderr
        var stdout = Console.OpenStandardOutput();
        Console.SetOut(Console.Error);
        return new LspServer(Console.OpenStandardInput(), stdout).RunLoop();
    }

    // =====================================================================
    // 主循环：Content-Length 分帧 → JSON-RPC 分发
    // =====================================================================
    private int RunLoop()
    {
        while (true)
        {
            string payload;
            try
            {
                payload = ReadPayload(_stdin) ?? "";
            }
            catch
            {
                return _shutdown ? 0 : 1; // stdin 关闭
            }
            if (payload.Length == 0)
            {
                return _shutdown ? 0 : 1;
            }
            JsonDocument doc;
            try
            {
                doc = JsonDocument.Parse(payload);
            }
            catch
            {
                continue; // 坏帧跳过（协议要求容错）
            }
            var root = doc.RootElement;
            string method = root.TryGetProperty("method", out var m) ? m.GetString() ?? "" : "";
            bool hasId = root.TryGetProperty("id", out var idEl);
            try
            {
                if (hasId)
                {
                    if (!HandleRequest(method, idEl.Clone(), root))
                    {
                        return _shutdown ? 0 : 1; // exit（未 shutdown 即退出 = 1，LSP 规范）
                    }
                }
                else
                {
                    if (!HandleNotification(method, root))
                    {
                        return _shutdown ? 0 : 1;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("[lsp] 处理消息异常: " + ex.Message);
                if (hasId)
                {
                    WriteError(idEl.Clone(), -32603, "internal error: " + ex.Message);
                }
            }
        }
    }

    private bool HandleRequest(string method, JsonElement id, JsonElement root)
    {
        switch (method)
        {
            case "initialize":
                Respond(id, new
                {
                    capabilities = new
                    {
                        textDocumentSync = new { openClose = true, change = 1, save = new { includeText = true } },
                        completionProvider = new { triggerCharacters = new[] { "." }, resolveProvider = false },
                        hoverProvider = true,
                        definitionProvider = true,
                        documentSymbolProvider = true,
                        documentFormattingProvider = true,
                        renameProvider = new { prepareProvider = true },
                    },
                    serverInfo = new { name = "slang-lsp", version = "0.3" },
                });
                return true;
            case "shutdown":
                _shutdown = true;
                Respond(id, null);
                return true;
            case "textDocument/completion":
                Respond(id, HandleCompletion(root));
                return true;
            case "textDocument/hover":
                Respond(id, HandleHover(root));
                return true;
            case "textDocument/definition":
                Respond(id, HandleDefinition(root));
                return true;
            case "textDocument/documentSymbol":
                Respond(id, HandleDocumentSymbol(root));
                return true;
            case "textDocument/formatting":
                Respond(id, HandleFormatting(root));
                return true;
            case "textDocument/prepareRename":
                Respond(id, HandlePrepareRename(root));
                return true;
            case "textDocument/rename":
                Respond(id, HandleRename(root));
                return true;
            case "exit":
                return false;
            default:
                WriteError(id, -32601, "method not found: " + method);
                return true;
        }
    }

    private bool HandleNotification(string method, JsonElement root)
    {
        switch (method)
        {
            case "initialized":
            case "$/cancelRequest":
            case "$/setTrace":
                return true;
            case "exit":
                return false;
            case "textDocument/didOpen":
            case "textDocument/didSave":
                OnOpenOrSave(root);
                return true;
            case "textDocument/didChange":
                OnChange(root);   // 仅更新内存文本（保存态诊断语义不变）
                return true;
            case "textDocument/didClose":
                OnClose(root);
                return true;
            default:
                return true; // 未知通知静默（协议要求）
        }
    }

    // =====================================================================
    // 文档跟踪与工程定位
    // =====================================================================
    private void OnOpenOrSave(JsonElement root)
    {
        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td))
        {
            return;
        }
        string uri = td.TryGetProperty("uri", out var uriEl) ? uriEl.GetString() ?? "" : "";
        if (uri.Length == 0)
        {
            return;
        }
        // didOpen: textDocument.text；didSave(includeText): params.text
        string? text = null;
        if (td.TryGetProperty("text", out var t))
        {
            text = t.GetString();
        }
        if (text == null && parms.TryGetProperty("text", out var t2))
        {
            text = t2.GetString();
        }
        if (text != null)
        {
            _docText[uri] = text;
        }

        var project = ResolveProject(uri);
        if (project == null)
        {
            return; // 不在 SLang 工程内：无诊断/补全语义
        }
        _docs[uri] = project;
        ScheduleDiagnostics(project);
    }

    private void OnChange(JsonElement root)
    {
        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td)
            || !td.TryGetProperty("uri", out var uriEl))
        {
            return;
        }
        // Full 同步：contentChanges[0].text 即全文
        if (parms.TryGetProperty("contentChanges", out var changes)
            && changes.GetArrayLength() > 0
            && changes[0].TryGetProperty("text", out var t))
        {
            _docText[uriEl.GetString() ?? ""] = t.GetString() ?? "";
        }
    }

    private void OnClose(JsonElement root)
    {
        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td)
            || !td.TryGetProperty("uri", out var uriEl))
        {
            return;
        }
        string uri = uriEl.GetString() ?? "";
        _docText.Remove(uri);
        if (_docs.Remove(uri))
        {
            Notify("textDocument/publishDiagnostics", new { uri, diagnostics = Array.Empty<object>() });
        }
    }

    private ProjectInfo? ResolveProject(string uri)
    {
        if (!uri.StartsWith("file://", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        string path = UriToPath(uri);
        string? dir = Path.GetDirectoryName(path);
        while (!string.IsNullOrEmpty(dir))
        {
            if (_dirCache.TryGetValue(dir, out var cached))
            {
                return cached;
            }
            var sps = Directory.Exists(dir) ? Directory.GetFiles(dir, "*.sp") : Array.Empty<string>();
            if (sps.Length > 0)
            {
                var info = new ProjectInfo { SpPath = sps[0], Dir = dir };
                _dirCache[dir] = info;
                return info;
            }
            dir = Path.GetDirectoryName(dir);
        }
        return null;
    }

    private string GetDocText(string uri)
    {
        if (_docText.TryGetValue(uri, out var text))
        {
            return text;
        }
        try
        {
            return File.Exists(UriToPath(uri)) ? File.ReadAllText(UriToPath(uri)) : "";
        }
        catch
        {
            return "";
        }
    }

    // =====================================================================
    // 诊断：防抖 400ms → 进程内编译 → LogData 直转 → publish
    // =====================================================================
    private void ScheduleDiagnostics(ProjectInfo project)
    {
        int version = Interlocked.Increment(ref _diagVersion);
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(400);
            }
            catch
            {
                return;
            }
            if (version != Volatile.Read(ref _diagVersion))
            {
                return; // 已有更新的触发，本轮回废
            }
            await _diagLock.WaitAsync();
            try
            {
                if (version == Volatile.Read(ref _diagVersion))
                {
                    DoDiagnostics(project);
                }
            }
            finally
            {
                _diagLock.Release();
            }
        });
    }

    private void DoDiagnostics(ProjectInfo project)
    {
        // 子进程编译（slang lsp-compile）：新进程一次编译，规避 Front 进程内
        // 重入残留（同进程第二轮 Compile 空跑/假失败，2026-10-19 实测；详见
        // LspCompileCommand 头注）。结果为结构化 JSON（诊断数组 + 内存包符号源）。
        string? json = RunLspCompile(project);
        if (string.IsNullOrEmpty(json))
        {
            Console.Error.WriteLine("[lsp] lsp-compile 子进程失败，本轮诊断放弃（下次保存重试）");
            return;
        }
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(json);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[lsp] lsp-compile 结果解析失败: " + ex.Message);
            return;
        }
        var root = doc.RootElement;
        bool success = root.TryGetProperty("success", out var s) && s.ValueKind == JsonValueKind.True;

        var byFile = new Dictionary<string, List<object>>();
        if (root.TryGetProperty("diagnostics", out var diags) && diags.ValueKind == JsonValueKind.Array)
        {
            foreach (var d in diags.EnumerateArray())
            {
                string? file = d.TryGetProperty("file", out var f) && f.ValueKind == JsonValueKind.String ? f.GetString() : null;
                string abs = ResolveLogFilePath(file, project);
                if (!byFile.TryGetValue(abs, out var list))
                {
                    byFile[abs] = list = new List<object>();
                }
                list.Add(ToDiagnostic(d));
            }
        }

        // 逐文件发布；上轮有、本轮无的文件发布空数组（清除）
        var previous = _publishedFiles.TryGetValue(project.SpPath, out var prev) ? prev : new HashSet<string>();
        var current = new HashSet<string>();
        foreach (var kv in byFile)
        {
            string uri = PathToUri(kv.Key);
            Notify("textDocument/publishDiagnostics", new { uri, diagnostics = kv.Value });
            current.Add(uri);
        }
        foreach (var uri in previous)
        {
            if (!current.Contains(uri))
            {
                Notify("textDocument/publishDiagnostics", new { uri, diagnostics = Array.Empty<object>() });
            }
        }
        _publishedFiles[project.SpPath] = current;

        // 成功编译 → 更新工程符号表（补全/悬停/跳转数据源）
        if (success && root.TryGetProperty("packageJson", out var pj) && pj.ValueKind == JsonValueKind.String)
        {
            string? pkgJson = pj.GetString();
            if (!string.IsNullOrEmpty(pkgJson))
            {
                try
                {
                    var pkg = ParsePackage(pkgJson, isProject: true);
                    pkg.ModuleName = Path.GetFileNameWithoutExtension(project.SpPath);
                    _projectPackages[project.SpPath] = pkg;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine("[lsp] 工程符号解析失败: " + ex.Message);
                }
            }
        }
        int errCount = 0;
        if (root.TryGetProperty("diagnostics", out var dgc) && dgc.ValueKind == JsonValueKind.Array)
        {
            errCount = dgc.EnumerateArray().Count(x => x.TryGetProperty("severity", out var sv) && sv.GetInt32() == 1);
        }
        Console.Error.WriteLine($"[lsp] 诊断 {Path.GetFileName(project.SpPath)}: {(success ? "编译通过" : "失败")}，{errCount} 条 Error 级诊断");
    }

    /* spawn 自身执行 lsp-compile：<exe> lsp-compile <sp> --cwd <dir>。
     * dotnet 宿主（dotnet run / dotnet slang.dll）下 Environment.ProcessPath 是
     * dotnet.exe——改传 <slang.dll> 作首参；AOT/打包 exe 直用自身路径。 */
    private static string? RunLspCompile(ProjectInfo project)
    {
        try
        {
            string? host = Environment.ProcessPath;
            if (string.IsNullOrEmpty(host))
            {
                return null;
            }
            string args;
            if (Path.GetFileName(host).StartsWith("dotnet", StringComparison.OrdinalIgnoreCase))
            {
                string dll = typeof(LspServer).Assembly.Location;
                if (string.IsNullOrEmpty(dll))
                {
                    return null;
                }
                args = $"\"{dll}\" lsp-compile \"{project.SpPath}\" --cwd \"{project.Dir}\"";
            }
            else
            {
                args = $"lsp-compile \"{project.SpPath}\" --cwd \"{project.Dir}\"";
            }
            var psi = new ProcessStartInfo(host, args)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = false, // Front 日志镜像直接透传终端，不吞
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p == null)
            {
                return null;
            }
            string stdout = p.StandardOutput.ReadToEnd();
            if (!p.WaitForExit(60_000))
            {
                try { p.Kill(); } catch { /* 已退出 */ }
                Console.Error.WriteLine("[lsp] lsp-compile 超时(60s)被终止");
                return null;
            }
            return stdout.Length > 0 ? stdout : null;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[lsp] spawn lsp-compile 异常: " + ex.Message);
            return null;
        }
    }

    /* lsp-compile 诊断条目（JsonElement）→ LSP diagnostic（行列基准与 LogData 同：
     * line 1-based → 0-based、char 0-based 原样） */
    private static object ToDiagnostic(JsonElement d)
    {
        int line = Math.Max(0, (d.TryGetProperty("line", out var l) && l.GetInt32() > 0 ? l.GetInt32() : 1) - 1);
        int chr = Math.Max(0, d.TryGetProperty("char", out var c) ? c.GetInt32() : 0);
        int endLine = Math.Max(line, (d.TryGetProperty("endLine", out var el) ? el.GetInt32() : 0) - 1);
        int endChr = Math.Max(chr, d.TryGetProperty("endChar", out var ec) ? ec.GetInt32() : 0);
        string message = d.TryGetProperty("message", out var m) ? m.GetString() ?? "" : "";
        string extend = d.TryGetProperty("extend", out var e) ? e.GetString() ?? "" : "";
        string tips = d.TryGetProperty("tips", out var t) ? t.GetString() ?? "" : "";
        if (extend.Length > 0)
        {
            message += " (" + extend + ")";
        }
        if (tips.Length > 0)
        {
            message += "\n建议: " + tips;
        }
        return new
        {
            range = new
            {
                start = new { line, character = chr },
                end = new { line = endLine, character = endChr },
            },
            severity = d.TryGetProperty("severity", out var sv) ? sv.GetInt32() : 1,
            code = d.TryGetProperty("code", out var cd) ? cd.GetString() ?? "" : "",
            source = "slang",
            message,
        };
    }

    private static string ResolveLogFilePath(string? filePath, ProjectInfo project)
    {
        if (string.IsNullOrEmpty(filePath))
        {
            return project.SpPath; // 无定位错误挂工程入口
        }
        if (Path.IsPathRooted(filePath) && File.Exists(filePath))
        {
            return filePath;
        }
        string candidate = Path.Combine(project.Dir, filePath);
        if (File.Exists(candidate))
        {
            return candidate;
        }
        if (File.Exists(filePath))
        {
            return Path.GetFullPath(filePath); // 相对 cwd
        }
        return project.SpPath;
    }

    // =====================================================================
    // 符号表：工程包 + 引用包 → 合并视图
    // =====================================================================
    private MergedTable BuildMergedTable(ProjectInfo project)
    {
        EnsureReferencePackages(project);
        var merged = new MergedTable();
        void AddPackage(PackageSymbols pkg)
        {
            foreach (var c in pkg.Classes)
            {
                merged.Classes.Add(c);
                merged.ByName[c.Name] = c;                       // 后写覆盖：工程包最后加载即优先
                merged.ByFullName[c.FullName] = c;
            }
        }
        foreach (var pkg in _refPackages.Values)
        {
            AddPackage(pkg);
        }
        if (_projectPackages.TryGetValue(project.SpPath, out var own))
        {
            AddPackage(own);
        }
        return merged;
    }

    /* 引用模块：jsonc references[].path → module.json（slb → 同名 .module.json 调试副本） */
    private void EnsureReferencePackages(ProjectInfo project)
    {
        if (_symbolProjects.ContainsKey(project.SpPath))
        {
            return;
        }
        _symbolProjects[project.SpPath] = project;
        try
        {
            string jsonc = Path.ChangeExtension(project.SpPath, ".jsonc");
            if (!File.Exists(jsonc))
            {
                return;
            }
            string text = StripJsoncComments(File.ReadAllText(jsonc));
            using var doc = JsonDocument.Parse(text, new JsonDocumentOptions { AllowTrailingCommas = true });
            if (!doc.RootElement.TryGetProperty("references", out var refs))
            {
                return;
            }
            foreach (var r in refs.EnumerateArray())
            {
                if (!r.TryGetProperty("path", out var p))
                {
                    continue;
                }
                string refPath = p.GetString() ?? "";
                string? moduleJson = ResolveModuleJson(refPath, project, out string? jsonDir, out string? slbPath);
                if (moduleJson == null && slbPath == null)
                {
                    continue; // 引用未命中：符号缺席（编译期报错会经诊断呈现）
                }
                string cacheKey = slbPath ?? moduleJson!;
                if (_refPackages.ContainsKey(cacheKey))
                {
                    continue;
                }
                try
                {
                    // slb 优先（Release 包 lib\ 仅 slb）：Front SLBReader → SLModulePackage
                    // → 序列化回 module.json 形态 → 复用统一解析（Release 包标准库符号不再缺席）。
                    // WhenWritingNull：SLB 不编码的段（express/instructionList 等）在对象上是 null，
                    // 序列化会产出 JSON null——JsonElement.TryGetProperty 对 Null 元素会抛
                    // InvalidOperationException（Try 仅对"属性缺失"安全）；忽略 null 属性
                    // 让其回到"缺失"语义（与 module.json 文本形态一致，2026-10-19 slb 路径实测）。
                    if (slbPath != null)
                    {
                        var pkgObj = SLBReader.Read(slbPath);
                        _refPackages[cacheKey] = ParsePackage(JsonSerializer.Serialize(pkgObj, _slbSerializeOptions), isProject: false);
                    }
                    else
                    {
                        _refPackages[cacheKey] = ParsePackage(File.ReadAllText(moduleJson!), isProject: false);
                    }
                    // 引用模块源根推断：repo 布局 lib\<名>.module.* → 上三级的 SLangCore\Lib\<模块>
                    if (jsonDir != null)
                    {
                        _refJsonRoot[cacheKey] = Path.GetFullPath(Path.Combine(jsonDir, "..", "..", "..", "SLangCore", "Lib"));
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine("[lsp] 引用模块解析失败 " + cacheKey + ": " + ex.Message);
                }
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[lsp] jsonc 解析失败: " + ex.Message);
        }
    }

    /* 引用解析（slb 优先）：返回 json 路径与 slb 路径（至少其一非空）。
     * ① 显式后缀原样 ② 同名互换后缀（Core.module.slb ↔ Core.module.json，
     * 勿用 ChangeExtension——它替换最后段扩展名）③ <exe>\lib\ 官方库直查。 */
    private static string? ResolveModuleJson(string refPath, ProjectInfo project, out string? jsonDir, out string? slbPath)
    {
        jsonDir = null;
        slbPath = null;
        string? jsonPath = null;
        var slbCandidates = new List<string>();
        var jsonCandidates = new List<string>();
        void AddCandidate(string p)
        {
            if (p.EndsWith(".slb", StringComparison.OrdinalIgnoreCase))
            {
                slbCandidates.Add(p);
                jsonCandidates.Add(p[..^".slb".Length] + ".json");
            }
            else if (p.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            {
                jsonCandidates.Add(p);
                slbCandidates.Add(p[..^".json".Length] + ".slb");
            }
            else
            {
                slbCandidates.Add(p + ".slb");
                jsonCandidates.Add(p);
            }
        }
        if (Path.IsPathRooted(refPath))
        {
            AddCandidate(refPath);
        }
        else
        {
            AddCandidate(Path.Combine(project.Dir, refPath));
        }
        // 官方库直查回退：<exe>\lib\<名>.module.slb|json
        try
        {
            string name = Path.GetFileNameWithoutExtension(refPath);
            name = name.EndsWith(".module") ? name[..^".module".Length] : name;
            slbCandidates.Add(Path.Combine(AppContext.BaseDirectory, "lib", name + ".module.slb"));
            jsonCandidates.Add(Path.Combine(AppContext.BaseDirectory, "lib", name + ".module.json"));
        }
        catch
        {
            /* BaseDirectory 异常场景忽略 */
        }
        foreach (var c in slbCandidates)
        {
            if (File.Exists(c))
            {
                slbPath = c;
                jsonDir = Path.GetDirectoryName(Path.GetFullPath(c));
                return jsonPath;
            }
        }
        foreach (var c in jsonCandidates)
        {
            if (File.Exists(c))
            {
                jsonPath = c;
                jsonDir = Path.GetDirectoryName(Path.GetFullPath(c));
                return jsonPath;
            }
        }
        return jsonPath;
    }

    /* module.json / 内存包 json → PackageSymbols（两遍：先收顶层胖方法表，再建类）。
     * ValueKind 防御：slb→对象→序列化路径会产生 JSON null 字段（express/instructionList
     * 等 SLB 不编码的段），所有数组访问前先验 Array（2026-10-19 slb 优先路径实测）。 */
    private static PackageSymbols ParsePackage(string packageJson, bool isProject)
    {
        var pkg = new PackageSymbols();
        using var doc = JsonDocument.Parse(packageJson);
        var root = doc.RootElement;
        if (root.TryGetProperty("moduleName", out var mn) && mn.ValueKind == JsonValueKind.String)
        {
            pkg.ModuleName = mn.GetString() ?? "";
        }

        // 第一遍：顶层 methodList（胖条目，id 为字符串）→ 签名/位置表
        var fat = new Dictionary<string, MethodInfo>();
        if (root.TryGetProperty("methodList", out var methodList) && methodList.ValueKind == JsonValueKind.Array)
        {
            foreach (var m in methodList.EnumerateArray())
            {
                string? name = m.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
                if (string.IsNullOrEmpty(name))
                {
                    continue;
                }
                var info = new MethodInfo
                {
                    Name = name,
                    Declaring = m.TryGetProperty("declaringTypeFullName", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() ?? "" : "",
                    ReturnType = m.TryGetProperty("returnList", out var rl) && rl.ValueKind == JsonValueKind.Array && rl.GetArrayLength() > 0
                        && rl[0].ValueKind == JsonValueKind.Object
                        && rl[0].TryGetProperty("typeDef", out var rt) && rt.ValueKind == JsonValueKind.Object && rt.TryGetProperty("className", out var rcn)
                        && rcn.ValueKind == JsonValueKind.String
                        ? rcn.GetString() ?? "" : "",
                };
                if (m.TryGetProperty("argumentList", out var al) && al.ValueKind == JsonValueKind.Array)
                {
                    foreach (var a in al.EnumerateArray())
                    {
                        string an = a.TryGetProperty("name", out var anEl) && anEl.ValueKind == JsonValueKind.String ? anEl.GetString() ?? "" : "";
                        string at = a.TryGetProperty("typeDef", out var atd) && atd.ValueKind == JsonValueKind.Object && atd.TryGetProperty("className", out var acn)
                            && acn.ValueKind == JsonValueKind.String ? acn.GetString() ?? "" : "";
                        info.Args.Add((at.Length > 0 ? at + " " : "") + an);
                    }
                }
                // 指令 debugInfo 扫首个有效位置（定义跳转用）
                if (m.TryGetProperty("instructionList", out var il) && il.ValueKind == JsonValueKind.Array)
                {
                    foreach (var ins in il.EnumerateArray())
                    {
                        if (ins.TryGetProperty("debugInfo", out var di)
                            && di.TryGetProperty("path", out var dp) && dp.ValueKind == JsonValueKind.String
                            && di.TryGetProperty("beginLine", out var dl) && dl.ValueKind == JsonValueKind.Number
                            && dl.GetInt32() > 0)
                        {
                            info.SourcePath = dp.GetString() ?? "";
                            info.BeginLine = dl.GetInt32();
                            if (di.TryGetProperty("beginChar", out var dc) && dc.ValueKind == JsonValueKind.Number)
                            {
                                info.BeginChar = dc.GetInt32();
                            }
                            break;
                        }
                    }
                }
                if (m.TryGetProperty("id", out var mid) && mid.ValueKind == JsonValueKind.String)
                {
                    fat[mid.GetString() ?? ""] = info;
                }
            }
        }

        // 第二遍：classList → 类 + 成员（瘦条目经 id 关联胖方法；未关联的用名字兜底）
        MethodInfo ResolveThin(JsonElement thin, bool isStatic, ClassInfo owner)
        {
            string name = thin.TryGetProperty("name", out var tn) && tn.ValueKind == JsonValueKind.String ? tn.GetString() ?? "" : "";
            string id = thin.TryGetProperty("id", out var tid) ? (tid.ValueKind == JsonValueKind.String ? tid.GetString() ?? "" : "") : "";
            if (id.Length > 0 && fat.TryGetValue(id, out var f))
            {
                f.IsStatic = isStatic;
                if (f.Declaring.Length == 0)
                {
                    f.Declaring = owner.Name;
                }
                return f;
            }
            return new MethodInfo { Name = name, Declaring = owner.Name, IsStatic = isStatic };
        }

        if (root.TryGetProperty("classList", out var classes) && classes.ValueKind == JsonValueKind.Array)
        {
            foreach (var c in classes.EnumerateArray())
            {
                string? name = c.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
                if (string.IsNullOrEmpty(name) || name.StartsWith("_"))
                {
                    continue; // 内部私有类不下发
                }
                var ci = new ClassInfo
                {
                    Name = name,
                    FullName = c.TryGetProperty("fullName", out var f) && f.ValueKind == JsonValueKind.String ? f.GetString() ?? name : name,
                    SourcePath = c.TryGetProperty("sourcePath", out var sp) && sp.ValueKind == JsonValueKind.String ? sp.GetString() ?? "" : "",
                    Kind = MapClassKind(c),
                    IsProject = isProject,
                };
                if (c.TryGetProperty("staticMethodList", out var sm) && sm.ValueKind == JsonValueKind.Array)
                {
                    foreach (var t in sm.EnumerateArray())
                    {
                        ci.StaticMethods.Add(ResolveThin(t, true, ci));
                    }
                }
                if (c.TryGetProperty("nonStaticMethodList", out var nm) && nm.ValueKind == JsonValueKind.Array)
                {
                    foreach (var t in nm.EnumerateArray())
                    {
                        ci.InstanceMethods.Add(ResolveThin(t, false, ci));
                    }
                }
                if (c.TryGetProperty("fieldList", out var fl) && fl.ValueKind == JsonValueKind.Array)
                {
                    foreach (var ff in fl.EnumerateArray())
                    {
                        var fi = new FieldInfo
                        {
                            Name = ff.TryGetProperty("name", out var fn) && fn.ValueKind == JsonValueKind.String ? fn.GetString() ?? "" : "",
                            Type = ff.TryGetProperty("typeDef", out var ftd) && ftd.ValueKind == JsonValueKind.Object && ftd.TryGetProperty("className", out var fcn)
                                && fcn.ValueKind == JsonValueKind.String ? fcn.GetString() ?? "" : "",
                        };
                        // 字段 express[0].debugInfo 常带定义位置（实测 Console.colorBlack beginLine=188）
                        if (ff.TryGetProperty("express", out var ex) && ex.ValueKind == JsonValueKind.Array && ex.GetArrayLength() > 0
                            && ex[0].ValueKind == JsonValueKind.Object
                            && ex[0].TryGetProperty("debugInfo", out var di)
                            && di.ValueKind == JsonValueKind.Object
                            && di.TryGetProperty("path", out var dp) && dp.ValueKind == JsonValueKind.String
                            && di.TryGetProperty("beginLine", out var dl) && dl.ValueKind == JsonValueKind.Number
                            && dl.GetInt32() > 0)
                        {
                            fi.SourcePath = dp.GetString() ?? "";
                            fi.BeginLine = dl.GetInt32();
                            if (di.TryGetProperty("beginChar", out var dc) && dc.ValueKind == JsonValueKind.Number)
                            {
                                fi.BeginChar = dc.GetInt32();
                            }
                        }
                        if (fi.Name.Length > 0)
                        {
                            ci.Fields.Add(fi);
                        }
                    }
                }
                pkg.Classes.Add(ci);
            }
        }
        /* systemCalls（slb 路径下为 jsonc 原始数组片段，直接抽 name/returnType；
         * L2 重写时曾被误删，2026-10-19 slb 路径联调时补回） */
        if (root.TryGetProperty("systemCalls", out var syscalls) && syscalls.ValueKind == JsonValueKind.Array)
        {
            foreach (var s in syscalls.EnumerateArray())
            {
                string? name = s.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
                if (string.IsNullOrEmpty(name))
                {
                    continue;
                }
                string ret = s.TryGetProperty("returnType", out var r) && r.ValueKind == JsonValueKind.String ? r.GetString() ?? "" : "";
                pkg.SystemCalls.Add(new { label = name, kind = 3, detail = $"系统方法 {(ret.Length > 0 ? "-> " + ret : "")}" });
            }
        }
        return pkg;
    }

    private static int MapClassKind(JsonElement classEl)
    {
        // metaClassKind 数值枚举（Front EMetaClassKind）：0=Class 基准，其余按序猜测
        // Interface/Enum/Data——错标仅影响图标，语义无损
        if (!classEl.TryGetProperty("metaClassKind", out var k) || k.ValueKind != JsonValueKind.Number)
        {
            return 7; // Class
        }
        return k.GetInt32() switch
        {
            1 => 8,   // Interface
            2 => 13,  // Enum
            3 => 23,  // Struct（data）
            _ => 7,
        };
    }

    // =====================================================================
    // 补全：IDENT. 成员感知 / 全局符号
    // =====================================================================
    private object HandleCompletion(JsonElement root)
    {
        var items = new List<object>();
        var seen = new HashSet<string>();
        void Add(string label, int kind, string detail)
        {
            if (seen.Add(label))
            {
                items.Add(new { label, kind, detail });
            }
        }

        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td)
            || !td.TryGetProperty("uri", out var uriEl))
        {
            return new { isIncomplete = false, items };
        }
        string uri = uriEl.GetString() ?? "";
        var project = _docs.TryGetValue(uri, out var p) ? p : ResolveProject(uri);
        if (project == null)
        {
            foreach (var kw in Keywords)
            {
                Add(kw, 14, "关键字");
            }
            return new { isIncomplete = false, items };
        }
        var table = BuildMergedTable(project);

        // 成员感知：光标前是 `IDENT.`（同一行、允许空白）→ 类成员补全
        string text = GetDocText(uri);
        if (parms.TryGetProperty("position", out var pos))
        {
            int offset = PositionToOffset(text, pos);
            string prefix = text[..Math.Min(offset, text.Length)];
            var memberMatch = Regex.Match(prefix, @"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*$");
            if (memberMatch.Success)
            {
                string qualifier = memberMatch.Groups[1].Value;
                if (table.ByName.TryGetValue(qualifier, out var cls))
                {
                    AddClassMembers(cls, Add);
                }
                return new { isIncomplete = false, items }; // 未知限定名：不回落全局
            }
        }

        // 全局补全：关键字 + 类 + 成员裸名 + 系统方法
        foreach (var kw in Keywords)
        {
            Add(kw, 14, "关键字");
        }
        foreach (var cls in table.Classes)
        {
            Add(cls.Name, cls.Kind, cls.FullName);
            AddClassMembers(cls, Add);
        }
        foreach (var pkg in _refPackages.Values.Concat(_projectPackages.Values))
        {
            foreach (var it in pkg.SystemCalls)
            {
                var label = GetSystemCallLabel(it);
                if (label != null)
                {
                    Add(label, 3, "系统方法");
                }
            }
        }

        // 上限保护（VSCode 客户端负责前缀过滤）
        if (items.Count > 4000)
        {
            items = items.GetRange(0, 4000);
        }
        return new { isIncomplete = false, items };
    }

    /* 系统方法补全项（匿名对象）经序列化反查 label */
    private static readonly JsonSerializerOptions _labelOptions = new() { IncludeFields = true };
    /* slb → SLModulePackage → json：忽略 null 属性（与 module.json 文本形态对齐） */
    private static readonly JsonSerializerOptions _slbSerializeOptions = new()
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };
    private static string? GetSystemCallLabel(object item)
    {
        try
        {
            using var d = JsonSerializer.SerializeToDocument(item, _labelOptions);
            return d.RootElement.TryGetProperty("label", out var l) && l.ValueKind == JsonValueKind.String ? l.GetString() : null;
        }
        catch
        {
            return null;
        }
    }

    private static void AddClassMembers(ClassInfo cls, Action<string, int, string> add)
    {
        foreach (var m in cls.StaticMethods)
        {
            add(m.Name, 2, m.Signature + " — " + cls.FullName);
        }
        foreach (var m in cls.InstanceMethods)
        {
            add(m.Name, 2, m.Signature + " — " + cls.FullName);
        }
        foreach (var f in cls.Fields)
        {
            add(f.Name, 5, (f.Type.Length > 0 ? f.Type + " " : "") + f.Name + " — " + cls.FullName);
        }
    }

    // =====================================================================
    // 悬停：类卡片 / 方法签名卡片（IDENT.成员 或 裸名）
    // =====================================================================
    private object? HandleHover(JsonElement root)
    {
        var (uri, project, text, offset) = GetContext(root);
        if (project == null)
        {
            return null;
        }
        var (word, qualifier) = WordAt(text, offset);
        if (word.Length == 0)
        {
            return null;
        }
        var table = BuildMergedTable(project);
        // 1) 限定名成员（`Console.println`）；未命中不提前返回——`global.println`
        //    的 global 是全局空间别名而非类，须回落到裸名搜索
        if (qualifier.Length > 0 && table.ByName.TryGetValue(qualifier, out var qcls))
        {
            var m = FindMember(qcls, word);
            if (m != null)
            {
                return new
                {
                    contents = new { kind = "markdown", value = $"```slang\n{m.Signature}\n```\n\n`{qcls.FullName}`" },
                };
            }
        }
        // 2) 类卡片
        if (table.ByName.TryGetValue(word, out var cls))
        {
            var card = $"```slang\nclass {cls.FullName}\n```\n\n{cls.StaticMethods.Count + cls.InstanceMethods.Count} 个方法 · {cls.Fields.Count} 个字段" + (cls.SourcePath.Length > 0 ? $"\n\n定义于 `{cls.SourcePath}`" : "");
            return new { contents = new { kind = "markdown", value = card } };
        }
        // 3) 裸方法名：全表搜同名，取前 5 个签名
        var hits = new List<MethodInfo>();
        foreach (var c2 in table.Classes)
        {
            foreach (var m in c2.StaticMethods.Concat(c2.InstanceMethods))
            {
                if (string.Equals(m.Name, word, StringComparison.Ordinal))
                {
                    hits.Add(m);
                    if (hits.Count >= 5)
                    {
                        break;
                    }
                }
            }
            if (hits.Count >= 5)
            {
                break;
            }
        }
        if (hits.Count == 0)
        {
            return null;
        }
        return new { contents = new { kind = "markdown", value = "```slang\n" + string.Join("\n", hits.Select(h => h.Signature)) + "\n```" } };
    }

    private static MethodInfo? FindMember(ClassInfo cls, string name)
    {
        foreach (var m in cls.StaticMethods)
        {
            if (string.Equals(m.Name, name, StringComparison.Ordinal))
            {
                return m;
            }
        }
        foreach (var m in cls.InstanceMethods)
        {
            if (string.Equals(m.Name, name, StringComparison.Ordinal))
            {
                return m;
            }
        }
        foreach (var f in cls.Fields)
        {
            if (string.Equals(f.Name, name, StringComparison.Ordinal))
            {
                return new MethodInfo { Name = f.Name, ReturnType = f.Type, Declaring = cls.Name };
            }
        }
        return null;
    }

    // =====================================================================
    // 定义跳转：类/方法 → sourcePath（+ debugInfo 行列）
    // =====================================================================
    private object? HandleDefinition(JsonElement root)
    {
        var (uri, project, text, offset) = GetContext(root);
        if (project == null)
        {
            return null;
        }
        var (word, qualifier) = WordAt(text, offset);
        if (word.Length == 0)
        {
            return null;
        }
        var table = BuildMergedTable(project);

        // 与 hover 同构的三段回退：限定名成员 → 类 → 裸方法名首个命中
        string? file = null;
        int line = 0;
        int chr = 0;
        bool resolved = false;

        if (qualifier.Length > 0 && table.ByName.TryGetValue(qualifier, out var qcls))
        {
            var m = FindMember(qcls, word);
            if (m != null)
            {
                file = ResolveSourcePath(project, qcls, m.SourcePath.Length > 0 ? m.SourcePath : qcls.SourcePath);
                line = m.SourcePath.Length > 0 ? m.BeginLine : 0;
                chr = m.SourcePath.Length > 0 ? m.BeginChar : 0;
                resolved = true;
            }
        }
        if (!resolved && table.ByName.TryGetValue(word, out var cls))
        {
            file = ResolveSourcePath(project, cls, cls.SourcePath);
            resolved = true;
        }
        if (!resolved)
        {
            foreach (var c2 in table.Classes)
            {
                var m = c2.StaticMethods.Concat(c2.InstanceMethods).FirstOrDefault(x => string.Equals(x.Name, word, StringComparison.Ordinal));
                if (m != null)
                {
                    file = ResolveSourcePath(project, c2, m.SourcePath.Length > 0 ? m.SourcePath : c2.SourcePath);
                    line = m.SourcePath.Length > 0 ? m.BeginLine : 0;
                    chr = m.SourcePath.Length > 0 ? m.BeginChar : 0;
                    resolved = true;
                    break;
                }
            }
        }
        if (!resolved || file == null || !File.Exists(file))
        {
            return null; // 源不在本机（发布包形态）——返回空（LSP 允许）
        }
        return new[]
        {
            new
            {
                uri = PathToUri(file),
                range = new
                {
                    start = new { line = Math.Max(0, line - 1), character = Math.Max(0, chr) },
                    end = new { line = Math.Max(0, line - 1), character = Math.Max(0, chr) },
                },
            },
        };
    }

    /* sourcePath 解析：工程类 → 工程目录；引用类 → jsonc 定位到的 module.json 的
     * repo 源根推断（SLangCore\Lib\<模块>\<sourcePath>，开发布局命中；纯包形态落空返回 null） */
    private string? ResolveSourcePath(ProjectInfo project, ClassInfo cls, string sourcePath)
    {
        if (sourcePath.Length == 0)
        {
            return null;
        }
        var candidates = new List<string>();
        if (cls.IsProject)
        {
            candidates.Add(Path.Combine(project.Dir, sourcePath));
        }
        else
        {
            foreach (var kv in _refJsonRoot)
            {
                candidates.Add(Path.Combine(kv.Value, _refPackages.TryGetValue(kv.Key, out var pkg) ? pkg.ModuleName : "", sourcePath));
            }
            candidates.Add(Path.Combine(project.Dir, sourcePath));
        }
        return candidates.FirstOrDefault(File.Exists);
    }

    // =====================================================================
    // 文档大纲：正则 outline（类/interface/enum/data + 方法行）
    // =====================================================================
    private object HandleDocumentSymbol(JsonElement root)
    {
        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td)
            || !td.TryGetProperty("uri", out var uriEl))
        {
            return Array.Empty<object>();
        }
        string uri = uriEl.GetString() ?? "";
        string text = GetDocText(uri);
        var result = new List<Dictionary<string, object?>>();

        // 类声明（SymbolKind：Class=5 Interface=11 Enum=10 Struct=23）
        var classRe = new Regex(@"^\s*(?:(?:public|protected|private|abstract|final|static|partial|inline|extern)\s+)*(class|interface|enum|data)\s+([A-Za-z_][A-Za-z0-9_]*)");
        // 顶层裸命名空间块（SL 文件形态：`LspSmoke` 独行 + 下一行 `{`；.sp 的 `Project` 同型）→ Namespace=3
        var nsRe = new Regex(@"^([A-Za-z_][A-Za-z0-9_]*)\s*\{?\s*$");
        // 方法行：可选修饰符 + 可选返回类型 + 名字 + ( 参数 ) ；排除控制流/赋值/@块/纯注释
        var methodRe = new Regex(@"^\s*(?:(?:public|protected|private|static|final|inline|override|abstract|extern|const|mut)\s+)*((?:[A-Za-z_][A-Za-z0-9_<>,\[\]\s]*?\s+)?)([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\{?\s*(#.*)?$");
        string[] controlWords = { "if", "elif", "while", "dowhile", "for", "switch", "catch", "function", "label", "spawn", "ret", "throw" };

        var lines = text.Split('\n');
        List<Dictionary<string, object?>>? currentChildren = null;
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].Replace("\r", "");
            var cm = classRe.Match(line);
            if (cm.Success)
            {
                string kindWord = cm.Groups[1].Value;
                string name = cm.Groups[2].Value;
                int kind = kindWord switch { "interface" => 11, "enum" => 10, "data" => 23, _ => 5 };
                var children = new List<Dictionary<string, object?>>();
                result.Add(MakeSymbol(name, kind, i, name, line, children));
                currentChildren = children;
                continue;
            }
            if (line.TrimStart().StartsWith("#") || line.TrimStart().StartsWith("@"))
            {
                continue; // 注释 / attribute 行 / @内嵌块
            }
            var nm = nsRe.Match(line);
            if (nm.Success && !Keywords.Contains(nm.Groups[1].Value) && !controlWords.Contains(nm.Groups[1].Value))
            {
                var children = new List<Dictionary<string, object?>>();
                result.Add(MakeSymbol(nm.Groups[1].Value, 3, i, nm.Groups[1].Value, line, children)); // Namespace
                currentChildren = children;
                continue;
            }
            var mm = methodRe.Match(line);
            if (mm.Success)
            {
                string name = mm.Groups[2].Value;
                if (controlWords.Contains(name) || line.Contains('=') && line.IndexOf('=') < line.IndexOf('('))
                {
                    continue; // 控制流 / 赋值语句误配
                }
                (currentChildren ?? result).Add(MakeSymbol(name, 6, i, name, line, null)); // SymbolKind.Method = 6
            }
        }
        return result;
    }

    private static Dictionary<string, object?> MakeSymbol(string name, int kind, int line, string selectionText, string lineText, List<Dictionary<string, object?>>? children)
    {
        int selStart = lineText.IndexOf(selectionText, StringComparison.Ordinal);
        if (selStart < 0)
        {
            selStart = 0;
        }
        var sym = new Dictionary<string, object?>
        {
            ["name"] = name,
            ["kind"] = kind,
            ["range"] = new
            {
                start = new { line, character = 0 },
                end = new { line, character = Math.Max(0, lineText.Length) },
            },
            ["selectionRange"] = new
            {
                start = new { line, character = selStart },
                end = new { line, character = selStart + selectionText.Length },
            },
        };
        if (children != null)
        {
            sym["children"] = children;
        }
        return sym;
    }

    // =====================================================================
    // L3：格式化（md/code.md Tab 缩进规范）+ 重命名（词级，跳字符串/注释/@块）
    // =====================================================================
    private object HandleFormatting(JsonElement root)
    {
        if (!root.TryGetProperty("params", out var parms)
            || !parms.TryGetProperty("textDocument", out var td)
            || !td.TryGetProperty("uri", out var uriEl))
        {
            return Array.Empty<object>();
        }
        string uri = uriEl.GetString() ?? "";
        string text = GetDocText(uri);
        if (text.Length == 0)
        {
            return Array.Empty<object>();
        }
        string formatted;
        try
        {
            formatted = SlangScanner.Format(text);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[lsp] 格式化异常: " + ex.Message);
            return Array.Empty<object>();
        }
        if (formatted == text)
        {
            return Array.Empty<object>(); // 已符合规范：无 edit
        }
        (int endLine, int endChar) = OffsetToPosition(text, text.Length);
        return new object[]
        {
            new
            {
                range = new { start = new { line = 0, character = 0 }, end = new { line = endLine, character = endChar } },
                newText = formatted,
            },
        };
    }

    private object? HandlePrepareRename(JsonElement root)
    {
        var (uri, project, text, offset) = GetContext(root);
        var (word, _) = WordAt(text, offset);
        if (word.Length == 0)
        {
            return null;
        }
        int start = Math.Min(offset, text.Length);
        while (start > 0 && (char.IsLetterOrDigit(text[start - 1]) || text[start - 1] == '_'))
        {
            start--;
        }
        int end = start;
        while (end < text.Length && (char.IsLetterOrDigit(text[end]) || text[end] == '_'))
        {
            end++;
        }
        (int l0, int c0) = OffsetToPosition(text, start);
        (int l1, int c1) = OffsetToPosition(text, end);
        return new
        {
            range = new { start = new { line = l0, character = c0 }, end = new { line = l1, character = c1 } },
            placeholder = word,
        };
    }

    private object HandleRename(JsonElement root)
    {
        string newName = "";
        if (root.TryGetProperty("params", out var parms) && parms.TryGetProperty("newName", out var nn))
        {
            newName = nn.GetString() ?? "";
        }
        var (uri, project, text, offset) = GetContext(root);
        var (word, _) = WordAt(text, offset);
        if (word.Length == 0 || newName.Length == 0 || project == null)
        {
            return new { changes = new Dictionary<string, object>() };
        }
        var changes = new Dictionary<string, List<object>>();
        foreach (var file in ProjectSourceFiles(project))
        {
            string content;
            try
            {
                content = File.ReadAllText(file);
            }
            catch
            {
                continue;
            }
            var edits = new List<object>();
            foreach (var (s, e) in SlangScanner.FindWords(content, word))
            {
                (int l0, int c0) = OffsetToPosition(content, s);
                (int l1, int c1) = OffsetToPosition(content, e);
                edits.Add(new
                {
                    range = new { start = new { line = l0, character = c0 }, end = new { line = l1, character = c1 } },
                    newText = newName,
                });
            }
            if (edits.Count > 0)
            {
                changes[PathToUri(file)] = edits;
            }
        }
        return new { changes };
    }

    /* 工程源文件枚举（rename 扫描范围）：.sl + .sp，排除产物/构建目录 */
    private static IEnumerable<string> ProjectSourceFiles(ProjectInfo project)
    {
        foreach (var ext in new[] { "*.sl", "*.sp" })
        {
            foreach (var f in Directory.EnumerateFiles(project.Dir, ext, SearchOption.AllDirectories))
            {
                string rel = f[(project.Dir.Length + 1)..];
                if (rel.Contains("\\out\\", StringComparison.OrdinalIgnoreCase)
                    || rel.Contains("\\export\\", StringComparison.OrdinalIgnoreCase)
                    || rel.Contains("\\build\\", StringComparison.OrdinalIgnoreCase)
                    || rel.Contains("\\bin\\", StringComparison.OrdinalIgnoreCase)
                    || rel.Contains("\\obj\\", StringComparison.OrdinalIgnoreCase)
                    || rel.Contains("\\node_modules\\", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                yield return f;
            }
        }
    }

    private static (int Line, int Col) OffsetToPosition(string text, int offset)
    {
        int line = 0;
        int lastNl = -1;
        for (int i = 0; i < offset && i < text.Length; i++)
        {
            if (text[i] == '\n')
            {
                line++;
                lastNl = i;
            }
        }
        return (line, offset - lastNl - 1);
    }

    /* SL 词法扫描器：格式化（Tab 缩进规范化，md/code.md）与词匹配共用
     * "跳过字符串/注释/@内嵌块" 语义（与 Front TryCaptureAtSignBlock 一致：@tag(){…} 块内不解析）。 */
    private static class SlangScanner
    {
        private enum Ctx { Code, BlockComment, TripleString, AtBlock }

        public static List<(int Start, int End)> FindWords(string text, string word)
        {
            var result = new List<(int, int)>();
            int i = 0;
            var ctx = Ctx.Code;
            int atBrace = 0;
            int n = text.Length;
            while (i < n)
            {
                char c = text[i];
                switch (ctx)
                {
                    case Ctx.Code:
                        if (c == '#' && i + 1 < n && text[i + 1] == '!')
                        {
                            int end = text.IndexOf("!#", i + 2);
                            i = end < 0 ? n : end + 2;
                        }
                        else if (c == '#')
                        {
                            int nl = text.IndexOf('\n', i);
                            i = nl < 0 ? n : nl;
                        }
                        else if (c == '"' && At(text, i, "\"\"\""))
                        {
                            int end = text.IndexOf("\"\"\"", i + 3);
                            i = end < 0 ? n : end + 3;
                        }
                        else if (c == '"' || c == '\'')
                        {
                            i = SkipString(text, i, c);
                        }
                        else if (c == '@' && IsIdentStart(text, i + 1))
                        {
                            int afterIdent = ReadIdent(text, i + 1);
                            if (afterIdent < n && text[afterIdent] == '(')
                            {
                                int afterParen = SkipParens(text, afterIdent);
                                int probe = afterParen;
                                while (probe < n && char.IsWhiteSpace(text[probe]))
                                {
                                    probe++;
                                }
                                if (probe < n && text[probe] == '{')
                                {
                                    atBrace = 1;
                                    ctx = Ctx.AtBlock;
                                    i = probe + 1;
                                }
                                else
                                {
                                    i = afterParen; // @Nickname("x") annotation：非块，继续 Code
                                }
                            }
                            else
                            {
                                i = afterIdent; // @Name 后无参数表：annotation
                            }
                        }
                        else if (IsIdentStart(text, i))
                        {
                            int end = ReadIdent(text, i);
                            if (text[i..end] == word)
                            {
                                result.Add((i, end));
                            }
                            i = end;
                        }
                        else
                        {
                            i++;
                        }
                        break;
                    case Ctx.BlockComment:
                    {
                        int end = text.IndexOf("!#", i);
                        if (end < 0)
                        {
                            i = n;
                        }
                        else
                        {
                            i = end + 2;
                            ctx = Ctx.Code;
                        }
                        break;
                    }
                    case Ctx.TripleString:
                    {
                        int end = text.IndexOf("\"\"\"", i);
                        if (end < 0)
                        {
                            i = n;
                        }
                        else
                        {
                            i = end + 3;
                            ctx = Ctx.Code;
                        }
                        break;
                    }
                    case Ctx.AtBlock:
                        while (i < n)
                        {
                            char a = text[i];
                            if (a == '"')
                            {
                                i = SkipCSharpString(text, i);
                                continue;
                            }
                            if (a == '/' && i + 1 < n && text[i + 1] == '/')
                            {
                                int nl = text.IndexOf('\n', i);
                                i = nl < 0 ? n : nl;
                                continue;
                            }
                            if (a == '{')
                            {
                                atBrace++;
                            }
                            else if (a == '}')
                            {
                                atBrace--;
                                if (atBrace == 0)
                                {
                                    ctx = Ctx.Code;
                                    i++;
                                    break;
                                }
                            }
                            i++;
                        }
                        break;
                }
            }
            return result;
        }

        /* 格式化：逐行处理；跨行状态 = 块注释/三引号串/@块（原样透传，不重排缩进）；
         * Code 行按花括号深度打 Tab 缩进（行首 } 按"前导闭括号数"回退，} else { 类同），
         * 尾空白清理。@块/三引号/块注释内容保持作者原样。 */
        public static string Format(string text)
        {
            string normalized = text.Replace("\r\n", "\n");
            bool endsWithNl = normalized.EndsWith("\n");
            // 先去掉恰一个末尾换行再切（"a\n".Split → ["a",""] 尾空串会把结尾双 \n 化）
            string body = endsWithNl ? normalized[..^1] : normalized;
            var lines = body.Split('\n');
            var outLines = new List<string>(lines.Length);
            var ctx = Ctx.Code;
            int depth = 0;
            int atBrace = 0;
            foreach (var raw in lines)
            {
                string line = raw;
                switch (ctx)
                {
                    case Ctx.Code:
                    {
                        string trimmed = line.Trim();
                        if (trimmed.Length == 0)
                        {
                            outLines.Add("");
                            break;
                        }
                        int k = 0;
                        while (k < trimmed.Length && trimmed[k] == '}')
                        {
                            k++;
                        }
                        int indent = Math.Max(0, depth - k);
                        outLines.Add(new string('\t', indent) + trimmed);
                        (depth, ctx, atBrace) = ScanCodeLine(trimmed, depth, ctx, atBrace);
                        break;
                    }
                    case Ctx.BlockComment:
                        outLines.Add(line);
                        if (line.Contains("!#"))
                        {
                            ctx = Ctx.Code;
                        }
                        break;
                    case Ctx.TripleString:
                        outLines.Add(line);
                        if (line.Contains("\"\"\""))
                        {
                            ctx = Ctx.Code;
                        }
                        break;
                    case Ctx.AtBlock:
                        outLines.Add(line); // @tag(){} 块内（C# 等）原样
                        int j = 0;
                        while (j < line.Length)
                        {
                            char c = line[j];
                            if (c == '"')
                            {
                                j = SkipCSharpString(line, j);
                                continue;
                            }
                            if (c == '/' && j + 1 < line.Length && line[j + 1] == '/')
                            {
                                break;
                            }
                            if (c == '{')
                            {
                                atBrace++;
                            }
                            else if (c == '}')
                            {
                                atBrace--;
                                if (atBrace == 0)
                                {
                                    ctx = Ctx.Code;
                                }
                            }
                            j++;
                        }
                        break;
                }
            }
            string joined = string.Join("\n", outLines);
            return endsWithNl ? joined + "\n" : joined;
        }

        /* Code 行内扫描：更新花括号深度与跨行状态（块注释/三引号/@块开启） */
        private static (int Depth, Ctx Ctx, int AtBrace) ScanCodeLine(string line, int depth, Ctx ctx, int atBrace)
        {
            int j = 0;
            int n = line.Length;
            while (j < n)
            {
                char c = line[j];
                if (c == '#' && j + 1 < n && line[j + 1] == '!')
                {
                    int end = line.IndexOf("!#", j + 2);
                    if (end < 0)
                    {
                        return (depth, Ctx.BlockComment, atBrace); // 跨行块注释开启
                    }
                    j = end + 2; // 行内闭合：继续扫后续代码
                }
                else if (c == '#')
                {
                    break; // 行注释
                }
                else if (c == '"' && At(line, j, "\"\"\""))
                {
                    int end = line.IndexOf("\"\"\"", j + 3);
                    if (end < 0)
                    {
                        return (depth, Ctx.TripleString, atBrace);
                    }
                    j = end + 3;
                }
                else if (c == '"' || c == '\'')
                {
                    j = SkipString(line, j, c);
                }
                else if (c == '@' && IsIdentStart(line, j + 1))
                {
                    int afterIdent = ReadIdent(line, j + 1);
                    if (afterIdent < n && line[afterIdent] == '(')
                    {
                        int afterParen = SkipParens(line, afterIdent);
                        int probe = afterParen;
                        while (probe < n && char.IsWhiteSpace(line[probe]))
                        {
                            probe++;
                        }
                        if (probe < n && line[probe] == '{')
                        {
                            // 行内找配对 }：找到→块闭合继续 Code；找不到→跨行 @Block
                            int b = probe + 1;
                            int braces = 1;
                            while (b < n && braces > 0)
                            {
                                char x = line[b];
                                if (x == '"')
                                {
                                    b = SkipCSharpString(line, b);
                                    continue;
                                }
                                if (x == '{')
                                {
                                    braces++;
                                }
                                else if (x == '}')
                                {
                                    braces--;
                                }
                                b++;
                            }
                            if (braces > 0)
                            {
                                return (depth, Ctx.AtBlock, braces); // 深度不变：@块内 {} 不算 SL 缩进
                            }
                            j = b;
                        }
                        else
                        {
                            j = afterParen; // annotation
                        }
                    }
                    else
                    {
                        j = afterIdent; // annotation
                    }
                }
                else if (c == '{')
                {
                    depth++;
                    j++;
                }
                else if (c == '}')
                {
                    depth--;
                    j++;
                }
                else
                {
                    j++;
                }
            }
            return (depth, ctx, atBrace);
        }

        private static bool At(string s, int i, string marker)
        {
            if (i + marker.Length > s.Length)
            {
                return false;
            }
            return s.Substring(i, marker.Length) == marker;
        }

        private static bool IsIdentStart(string s, int i) => i < s.Length && (char.IsLetter(s[i]) || s[i] == '_');

        private static int ReadIdent(string s, int i)
        {
            while (i < s.Length && (char.IsLetterOrDigit(s[i]) || s[i] == '_'))
            {
                i++;
            }
            return i;
        }

        /* 普通字符串（SL："…" / '…'，反斜杠转义）到闭合引号后一位 */
        private static int SkipString(string s, int i, char quote)
        {
            i++; // 开引号
            while (i < s.Length)
            {
                if (s[i] == '\\')
                {
                    i += 2;
                    continue;
                }
                if (s[i] == quote)
                {
                    return i + 1;
                }
                i++;
            }
            return i; // 未闭合（行尾）：交给行注释逻辑兜底
        }

        /* C# 字符串（@块内，仅普通 "…"）到闭合后一位 */
        private static int SkipCSharpString(string s, int i)
        {
            i++;
            while (i < s.Length)
            {
                if (s[i] == '\\')
                {
                    i += 2;
                    continue;
                }
                if (s[i] == '"')
                {
                    return i + 1;
                }
                i++;
            }
            return i;
        }

        /* 从开括号（含）起配对到闭括号后一位（跳过字符串） */
        private static int SkipParens(string s, int open)
        {
            int depth = 0;
            int i = open;
            while (i < s.Length)
            {
                char c = s[i];
                if (c == '"' || c == '\'')
                {
                    i = SkipString(s, i, c);
                    continue;
                }
                if (c == '(')
                {
                    depth++;
                }
                else if (c == ')')
                {
                    depth--;
                    if (depth == 0)
                    {
                        return i + 1;
                    }
                }
                i++;
            }
            return i; // 未闭合：交给调用方（@tag() 参数表不跨行，词法层同假设）
        }
    }

    // =====================================================================
    // 上下文工具：position ↔ offset、光标处词与限定名
    // =====================================================================
    private (string Uri, ProjectInfo? Project, string Text, int Offset) GetContext(JsonElement root)
    {
        string uri = "";
        int line = 0, chr = 0;
        if (root.TryGetProperty("params", out var parms))
        {
            if (parms.TryGetProperty("textDocument", out var td) && td.TryGetProperty("uri", out var uriEl))
            {
                uri = uriEl.GetString() ?? "";
            }
            if (parms.TryGetProperty("position", out var pos))
            {
                line = pos.TryGetProperty("line", out var l) ? l.GetInt32() : 0;
                chr = pos.TryGetProperty("character", out var c) ? c.GetInt32() : 0;
            }
        }
        string text = GetDocText(uri);
        int offset = PositionToOffset(text, line, chr);
        var project = _docs.TryGetValue(uri, out var p) ? p : ResolveProject(uri);
        return (uri, project, text, offset);
    }

    private static int PositionToOffset(string text, JsonElement pos)
    {
        int line = pos.TryGetProperty("line", out var l) ? l.GetInt32() : 0;
        int chr = pos.TryGetProperty("character", out var c) ? c.GetInt32() : 0;
        return PositionToOffset(text, line, chr);
    }

    private static int PositionToOffset(string text, int line, int chr)
    {
        int cur = 0;
        for (int i = 0; i < line && cur < text.Length; i++)
        {
            int nl = text.IndexOf('\n', cur);
            if (nl < 0)
            {
                return text.Length;
            }
            cur = nl + 1;
        }
        return Math.Min(cur + chr, text.Length);
    }

    /* 光标处完整词 + 可选限定名（`IDENT.word` 的 IDENT；跨空白找点号）。
     * 光标可在词内任意位置：先向左找词首，再向右延伸到词尾。 */
    private static (string Word, string Qualifier) WordAt(string text, int offset)
    {
        int cursor = Math.Min(offset, text.Length);
        int start = cursor;
        while (start > 0 && (char.IsLetterOrDigit(text[start - 1]) || text[start - 1] == '_'))
        {
            start--;
        }
        int end = cursor;
        while (end < text.Length && (char.IsLetterOrDigit(text[end]) || text[end] == '_'))
        {
            end++;
        }
        if (start == end)
        {
            return ("", "");
        }
        string word = text[start..end];
        // 向左找 `<ident> .`（允许空白）
        int k = start - 1;
        while (k >= 0 && char.IsWhiteSpace(text[k]))
        {
            k--;
        }
        if (k < 0 || text[k] != '.')
        {
            return (word, "");
        }
        k--;
        while (k >= 0 && char.IsWhiteSpace(text[k]))
        {
            k--;
        }
        int qEnd = k + 1;
        while (k >= 0 && (char.IsLetterOrDigit(text[k]) || text[k] == '_'))
        {
            k--;
        }
        if (qEnd > k + 1)
        {
            return (word, text[(k + 1)..qEnd]);
        }
        return (word, "");
    }

    // =====================================================================
    // JSON-RPC 帧 IO
    // =====================================================================
    private string? ReadPayload(Stream s)
    {
        int len = -1;
        while (true)
        {
            string? line = ReadLine(s);
            if (line == null)
            {
                return null;
            }
            if (line.Length == 0)
            {
                break; // 头部结束
            }
            if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
            {
                int.TryParse(line["Content-Length:".Length..].Trim(), out len);
            }
        }
        if (len <= 0)
        {
            return "";
        }
        var buf = new byte[len];
        int off = 0;
        while (off < len)
        {
            int read = s.Read(buf, off, len - off);
            if (read <= 0)
            {
                return null;
            }
            off += read;
        }
        return Encoding.UTF8.GetString(buf);
    }

    private static string? ReadLine(Stream s)
    {
        var sb = new StringBuilder();
        while (true)
        {
            int c = s.ReadByte();
            if (c == -1)
            {
                return sb.Length == 0 ? null : sb.ToString();
            }
            if (c == '\n')
            {
                return sb.ToString().TrimEnd('\r');
            }
            sb.Append((char)c);
        }
    }

    private void Respond(JsonElement id, object? result)
    {
        WriteRaw(new Dictionary<string, object?>
        {
            ["jsonrpc"] = "2.0",
            ["id"] = JsonSerializer.SerializeToElement(id),
            ["result"] = result,
        });
    }

    private void WriteError(JsonElement id, int code, string message)
    {
        WriteRaw(new Dictionary<string, object?>
        {
            ["jsonrpc"] = "2.0",
            ["id"] = JsonSerializer.SerializeToElement(id),
            ["error"] = new { code, message },
        });
    }

    private void Notify(string method, object parms)
    {
        WriteRaw(new Dictionary<string, object?>
        {
            ["jsonrpc"] = "2.0",
            ["method"] = method,
            ["params"] = parms,
        });
    }

    private void WriteRaw(object payload)
    {
        // 经 JsonDom（纯反射→JsonNode）序列化：STJ 反射路径在 Native AOT 下对
        // 匿名类型选 SmallObjectWithParameterizedConverter（运行时构造泛型，无
        // 预生成代码 → 崩溃），详见 JsonDom.cs 头注（2026-10-19）
        var json = JsonDom.ToNode(payload)?.ToJsonString() ?? "null";
        var body = Encoding.UTF8.GetBytes(json);
        var header = Encoding.ASCII.GetBytes("Content-Length: " + body.Length + "\r\n\r\n");
        lock (_writeLock)
        {
            _stdout.Write(header, 0, header.Length);
            _stdout.Write(body, 0, body.Length);
            _stdout.Flush();
        }
    }

    // =====================================================================
    // 工具
    // =====================================================================
    private static string UriToPath(string uri)
    {
        if (Uri.TryCreate(uri, UriKind.Absolute, out var u) && u.IsFile)
        {
            return u.LocalPath;
        }
        return Uri.UnescapeDataString(uri["file://".Length..]);
    }

    private static string PathToUri(string path)
    {
        return new Uri(path).AbsoluteUri;
    }

    /* jsonc 宽松化：去块注释/行注释（与插件 diagnostics 侧同款策略；
     * 行注释仅认行首或空白/分隔符后的 //，容忍 URL 字符串）。 */
    private static string StripJsoncComments(string text)
    {
        text = Regex.Replace(text, @"/\*[\s\S]*?\*/", "");
        text = Regex.Replace(text, @"(^|[\s(:\[,])//[^\r\n]*", "$1");
        return text;
    }
}
