//****************************************************************************
//  File:      LspServer.cs
// ------------------------------------------------
//  slang lsp —— 内嵌于宿主的 LSP 3.17 服务器（stdio JSON-RPC，一工作区一实例）。
//
//  范围（slang_vscode_plugin\07_language_server_lsp.md）：
//   L1（2026-10-19）诊断推送 + 全局符号补全；
//   L2（2026-10-19）成员感知补全 + 悬停 + 定义跳转 + 文档大纲；
//      （2026-10-21 L2 增强：类型感知成员补全——接收者解析：局部变量/参数声明、
//        var 推断、方法返回类型、链式推进、限定名聚合、this、构造调用、数组内建
//        length；public 过滤：private/跨模块 protected 字段与 private 类不外显）；
//   L3（2026-10-19）格式化 + 重命名。
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
        public int Flags;                                    // SLFieldPackage.flags：1=private 2=public 4=extern 8=protected 16=const 32=static
        public string SourcePath = "";
        public int BeginLine = 0;
        public int BeginChar = 0;
        public bool IsPrivate => (Flags & 1) != 0;
        public bool IsProtected => (Flags & 8) != 0;
        public bool IsStatic => (Flags & 32) != 0;
    }

    private sealed class ClassInfo
    {
        public required string Name;
        public required string FullName;
        public string SourcePath = "";
        public int Kind = 7;                                 // CompletionItemKind（Class）
        public int Permission;                               // SLClassPackage.permission：0=Null 1=Export 2=Public 3=Protected 4=Private
        public List<MethodInfo> StaticMethods = new();
        public List<MethodInfo> InstanceMethods = new();
        public List<FieldInfo> Fields = new();
        public bool IsProject;                               // 工程自身（定义跳转基准=工程目录）
        public bool IsPrivateClass => Permission == 4 && !IsProject;
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
    private readonly Dictionary<string, Dictionary<string, List<string>>> _refSourceIndex = new(); // 源根 → .sl 基名 → 路径列表（模块名 ≠ 源目录名兜底索引）
    private readonly Dictionary<string, ProjectInfo> _symbolProjects = new();
    private readonly Dictionary<string, HashSet<string>> _publishedFiles = new();

    // ==== 编译期调用点关联（callSites，2026-10-21）====
    // spPath → 全部方法调用点条目；definition/hover 光标区间命中即精确跳转。
    // 数据源 = lsp-compile 导出的 IR 指令流绑定（MetaCallNode 解析结果的 IR 沉淀）。
    // 2026-10-22：MetaCore 代码关联索引（index.refs）的字段/枚举成员/类型名引用
    // 也并入本表（Kind 区分）；LookupCallSite 对 Kind 无感（行+词名命中即跳）。
    private sealed class CallSiteEntry
    {
        public string Kind = "method"; // "method"|"field"|"enumMember"|"type"（index.refs 来源）
        public string File = "";       // 归一化全路径（查询 key）
        public int Line;               // 1-based
        public int BeginChar;          // 0-based
        public int EndChar;            // 0-based（token 终点，容忍式命中）
        public string Name = "";
        public string TargetName = ""; // 目标方法 IR id（本地=functionAllName；ref module=IR 体系 id，仅参考）
        public string TargetClass = ""; // 目标类 irName（规整查表键）
        public string TargetMethod = ""; // 目标方法短名（规整查表键）
        public string TargetFile = ""; // 目标定义文件（相对工程目录；ref module 空）
        public int TargetLine;         // 1-based
        public int TargetChar;         // 0-based
    }
    private readonly Dictionary<string, List<CallSiteEntry>> _projectCallSites = new();

    // ==== 代码关联索引（MetaCore index，2026-10-22）：定义锚点 + 灰区 ====
    // symbols → 定义表（类型 + 成员名字 token 位置；本工程目标优先于
    // MergedTable 的 instruction 锚点，definition 跳转更准）。
    private sealed class DefEntry
    {
        public string Kind = "";       // class|interface|enum|data|method|field|enumMember
        public string Name = "";
        public string FullName = "";   // 成员 = "类全名.成员名"；类型 = 类全名
        public string File = "";       // 相对工程目录
        public int Line;               // 1-based
        public int Char;               // 0-based
    }
    private readonly Dictionary<string, Dictionary<string, DefEntry>> _projectDefs = new(); // spPath → "full"|"full.member" → def

    // 灰显区（编译期确定性裁剪）：@Exclude 成员/类 + jsonc ignored 文件。
    // 动态判不出来的不导出（导出器侧保证），故不在此列。
    private sealed class InactiveRange
    {
        public int Line;      // 0-based
        public int Char;      // 0-based
        public int EndLine;   // 0-based
        public int EndChar;   // 0-based（开区间尾）
    }
    private readonly Dictionary<string, Dictionary<string, List<InactiveRange>>> _projectInactive = new(); // spPath → 全路径 → 灰区
    private readonly Dictionary<string, HashSet<string>> _projectIgnoredFiles = new(); // spPath → 全路径集（整文件灰显）
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

    /* 系统类型小写别名（2026-10-23 用户需求"Int32/int 等系统类型也要提示"）：
     * 与 Front 词法层关键字-类型表同源（LexerParseToToken.cs——byte/sbyte/short/
     * ushort/int/uint/long/ulong/half/float/double/bool/string/object 均为
     * ETokenType.Type 词元，extend=对应 EType）。它们也是类（Core.Int32 等
     * 系统类，ref module 供给）——裸名 hover/定义、接收者声明类型（`int a = 3`
     * 后 `a.` 的成员补全）、链式推进统一经 ResolveClassByName 别名归一命中。 */
    private static readonly Dictionary<string, string> TypeAliases = new(StringComparer.Ordinal)
    {
        ["object"] = "Object",
        ["byte"] = "UInt8",
        ["sbyte"] = "Int8",
        ["short"] = "Int16",
        ["ushort"] = "UInt16",
        ["int"] = "Int32",
        ["uint"] = "UInt32",
        ["long"] = "Int64",
        ["ulong"] = "UInt64",
        ["half"] = "Float16",
        ["float"] = "Float32",
        ["double"] = "Float64",
        ["bool"] = "Boolean",
        ["string"] = "String",
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

    /* [lsp-trace] 取 params.textDocument.uri（无则空串）——插桩辅助。
     * 注意 params 可为 JSON null（shutdown 等），TryGetProperty 前必须验 ValueKind */
    private static string DocUriOf(JsonElement root)
    {
        if (root.TryGetProperty("params", out var p) && p.ValueKind == JsonValueKind.Object
            && p.TryGetProperty("textDocument", out var td) && td.ValueKind == JsonValueKind.Object
            && td.TryGetProperty("uri", out var u) && u.ValueKind == JsonValueKind.String)
        {
            return u.GetString() ?? "";
        }
        return "";
    }

    private bool HandleRequest(string method, JsonElement id, JsonElement root)
    {
        /* [lsp-trace] 2026-10-21 插桩：Trae→宿主请求断点取证（definition 真机不可跳排障），
         * 结论落盘后移除或降级为 --lsp-verbose 门控 */
        Console.Error.WriteLine($"[lsp] req {method}: {DocUriOf(root)}");
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
                Console.Error.WriteLine($"[lsp] {method}: {DocUriOf(root)}");
                OnOpenOrSave(root);
                return true;
            case "textDocument/didChange":
                Console.Error.WriteLine($"[lsp] didChange: {DocUriOf(root)}");
                OnChange(root);   // 仅更新内存文本（保存态诊断语义不变）
                return true;
            case "textDocument/didClose":
                Console.Error.WriteLine($"[lsp] didClose: {DocUriOf(root)}");
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
            Console.Error.WriteLine($"[lsp] didOpen/save 未命中工程: {uri}"); // [lsp-trace]
            return; // 不在 SLang 工程内：无诊断/补全语义
        }
        Console.Error.WriteLine($"[lsp] didOpen/save → 工程 {project.SpPath}，触发编译装载"); // [lsp-trace]
        _docs[uri] = project;
        // 灰区即时呈现：索引已在（最近一次成功编译）时 didOpen/didSave 先按旧表推送，
        // 编译完成后 LoadCodeIndex 会再推新表（ranges 全量替换）
        if (_projectInactive.ContainsKey(project.SpPath) || _projectIgnoredFiles.ContainsKey(project.SpPath))
        {
            SendInactiveRegions(project, uri);
        }
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
            // 工程锚点：*.sp 优先；无 .sp 时回落 *.jsonc（2026-10-25 起 .sp 非必需，
            // jsonc-only 工程按非 main 入口工程编译；plugin.jsonc 是插件清单需排除）
            var sps = Directory.Exists(dir) ? Directory.GetFiles(dir, "*.sp") : Array.Empty<string>();
            if (sps.Length == 0 && Directory.Exists(dir))
            {
                sps = Directory.GetFiles(dir, "*.jsonc")
                    .Where(p => !string.Equals(Path.GetFileNameWithoutExtension(p), "plugin", StringComparison.OrdinalIgnoreCase))
                    .ToArray();
            }
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

        // 成功编译 → 更新工程符号表（补全/悬停/跳转数据源）——必须在 publish 之前：
        // 客户端常以「收到诊断」为编译就绪信号立刻发 definition/hover/completion，
        // 先 publish 后装载会开出一拍符号表为空的竞态窗口（2026-10-21 冒烟 flaky 实锤）
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

        // 成功编译 → 装载代码关联索引（IR 生成数据，2026-10-23 数据源定稿）：
        // refs（方法/字段/枚举成员/类型引用，全部出自 IR 指令流；原 callSites
        // 通道已并入，kind=method）→ 调用点表（definition/hover 共用查询）；
        // symbols → 定义锚点表；excluded/ignoredFiles → 灰显区，随后按打开文档推送。
        // 编译失败不带 index 字段——旧表保留（灰显/跳转以最近一次成功编译为准）
        if (success && root.TryGetProperty("index", out var idxEl) && idxEl.ValueKind == JsonValueKind.Object)
        {
            LoadCodeIndex(project, idxEl);
        }

        // 逐文件发布（移至装载之后：客户端以「收到诊断」为就绪信号，publish 前须保证
        // 符号表/调用点已就位，否则 definition/hover 有一拍空窗）；上轮有本轮无 → 空数组清除。
        // 打开中的文档按客户端原样 URI 回显发布（Trae/VS Code 发 %3A 编码形态，PathToUri
        // 派生形态在盘符大小写/编码细节上可能有偏差 → 诊断映射不到已开文档）；
        // 未打开文件回落 PathToUri（仅 Problems 面板可见，不依赖文档键匹配）。
        var openUriByPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var docUri in _docs.Keys)
        {
            try
            {
                openUriByPath[Path.GetFullPath(UriToPath(docUri))] = docUri;
            }
            catch
            {
                /* 坏路径跳过 */
            }
        }
        var previous = _publishedFiles.TryGetValue(project.SpPath, out var prev) ? prev : new HashSet<string>();
        var current = new HashSet<string>();
        foreach (var kv in byFile)
        {
            string key;
            try
            {
                key = Path.GetFullPath(kv.Key);
            }
            catch
            {
                key = kv.Key;
            }
            string uri = openUriByPath.TryGetValue(key, out var docUri) ? docUri : PathToUri(kv.Key);
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

        int errCount = 0;
        if (root.TryGetProperty("diagnostics", out var dgc) && dgc.ValueKind == JsonValueKind.Array)
        {
            errCount = dgc.EnumerateArray().Count(x => x.TryGetProperty("severity", out var sv) && sv.GetInt32() == 1);
        }
        Console.Error.WriteLine($"[lsp] 诊断 {Path.GetFileName(project.SpPath)}: {(success ? "编译通过" : "失败")}，{errCount} 条 Error 级诊断");
    }

    /* 代码关联索引装载（MetaCore index）：
     *   refs        → 并入 _projectCallSites（CallSiteEntry.Kind 标记来源；
     *                LookupCallSite/ResolveCallSiteTarget 共用既有链路）
     *   symbols     → _projectDefs（类型/成员定义锚点，本工程目标解析优先）
     *   excluded    → _projectInactive（按全路径分组，0-based 区间）
     *   ignoredFiles→ _projectIgnoredFiles（整文件灰显）
     * 装载完成后对当前打开的工程文档推送 slang/publishInactiveRegions。 */
    private void LoadCodeIndex(ProjectInfo project, JsonElement idx)
    {
        // symbols → 定义表
        var defs = new Dictionary<string, DefEntry>(StringComparer.OrdinalIgnoreCase);
        if (idx.TryGetProperty("symbols", out var syms) && syms.ValueKind == JsonValueKind.Array)
        {
            foreach (var s in syms.EnumerateArray())
            {
                string fn = s.TryGetProperty("fn", out var fnE) && fnE.ValueKind == JsonValueKind.String ? fnE.GetString() ?? "" : "";
                if (fn.Length == 0)
                {
                    continue;
                }
                var clsDef = ReadDef(s, fn, s.TryGetProperty("k", out var kE) && kE.ValueKind == JsonValueKind.String ? kE.GetString() ?? "class" : "class");
                if (clsDef != null)
                {
                    defs[fn] = clsDef;
                }
                if (s.TryGetProperty("m", out var members) && members.ValueKind == JsonValueKind.Array)
                {
                    foreach (var m in members.EnumerateArray())
                    {
                        var mDef = ReadDef(m, fn + "." + (m.TryGetProperty("n", out var nE) && nE.ValueKind == JsonValueKind.String ? nE.GetString() ?? "" : ""),
                            m.TryGetProperty("k", out var mkE) && mkE.ValueKind == JsonValueKind.String ? mkE.GetString() ?? "" : "");
                        if (mDef != null)
                        {
                            defs[mDef.FullName] = mDef;
                        }
                    }
                }
            }
        }
        _projectDefs[project.SpPath] = defs;

        // excluded → 灰区（按全路径分组；行 1-based → 0-based）
        var inactive = new Dictionary<string, List<InactiveRange>>(StringComparer.OrdinalIgnoreCase);
        if (idx.TryGetProperty("excluded", out var exs) && exs.ValueKind == JsonValueKind.Array)
        {
            foreach (var x in exs.EnumerateArray())
            {
                string f = x.TryGetProperty("f", out var fE) && fE.ValueKind == JsonValueKind.String ? fE.GetString() ?? "" : "";
                int l = x.TryGetProperty("l", out var lE) && lE.ValueKind == JsonValueKind.Number ? lE.GetInt32() : 0;
                if (f.Length == 0 || l <= 0)
                {
                    continue;
                }
                string full;
                try
                {
                    full = Path.GetFullPath(Path.Combine(project.Dir, f));
                }
                catch
                {
                    continue;
                }
                var r = new InactiveRange
                {
                    Line = l - 1,
                    Char = x.TryGetProperty("c", out var cE) && cE.ValueKind == JsonValueKind.Number ? cE.GetInt32() : 0,
                    EndLine = Math.Max(l - 1, (x.TryGetProperty("el", out var elE) && elE.ValueKind == JsonValueKind.Number ? elE.GetInt32() : l) - 1),
                    EndChar = x.TryGetProperty("ec", out var ecE) && ecE.ValueKind == JsonValueKind.Number ? ecE.GetInt32() : 0,
                };
                if (!inactive.TryGetValue(full, out var list))
                {
                    inactive[full] = list = new List<InactiveRange>();
                }
                list.Add(r);
            }
        }
        _projectInactive[project.SpPath] = inactive;

        // ignoredFiles → 整文件灰显集
        var ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (idx.TryGetProperty("ignoredFiles", out var igf) && igf.ValueKind == JsonValueKind.Array)
        {
            foreach (var p in igf.EnumerateArray())
            {
                if (p.ValueKind != JsonValueKind.String)
                {
                    continue;
                }
                string rel = p.GetString() ?? "";
                try
                {
                    ignored.Add(Path.GetFullPath(Path.Combine(project.Dir, rel)));
                }
                catch
                {
                    /* 路径异常忽略 */
                }
            }
        }
        _projectIgnoredFiles[project.SpPath] = ignored;

        // refs → 调用点表（2026-10-23 起 refs 为唯一引用通道：原 callSites 已并入
        // kind=method，整体替换防跨轮残留）
        int refCount = 0;
        if (idx.TryGetProperty("refs", out var refs) && refs.ValueKind == JsonValueKind.Array)
        {
            var list = new List<CallSiteEntry>();
            _projectCallSites[project.SpPath] = list;
            foreach (var r in refs.EnumerateArray())
            {
                string f = r.TryGetProperty("f", out var fE) && fE.ValueKind == JsonValueKind.String ? fE.GetString() ?? "" : "";
                int l = r.TryGetProperty("l", out var lE) && lE.ValueKind == JsonValueKind.Number ? lE.GetInt32() : 0;
                if (f.Length == 0 || l <= 0)
                {
                    continue;
                }
                string full;
                try
                {
                    full = Path.GetFullPath(Path.Combine(project.Dir, f));
                }
                catch
                {
                    continue;
                }
                list.Add(new CallSiteEntry
                {
                    Kind = r.TryGetProperty("k", out var kE) && kE.ValueKind == JsonValueKind.String ? kE.GetString() ?? "method" : "method",
                    File = full,
                    Line = l,
                    BeginChar = r.TryGetProperty("c", out var cE) && cE.ValueKind == JsonValueKind.Number ? cE.GetInt32() : 0,
                    EndChar = r.TryGetProperty("ec", out var ecE) && ecE.ValueKind == JsonValueKind.Number ? ecE.GetInt32() : 0,
                    Name = r.TryGetProperty("n", out var nE) && nE.ValueKind == JsonValueKind.String ? nE.GetString() ?? "" : "",
                    TargetName = r.TryGetProperty("tn", out var tnE) && tnE.ValueKind == JsonValueKind.String ? tnE.GetString() ?? "" : "",
                    TargetClass = r.TryGetProperty("tc", out var tcE) && tcE.ValueKind == JsonValueKind.String ? tcE.GetString() ?? "" : "",
                    TargetMethod = r.TryGetProperty("tm", out var tmE) && tmE.ValueKind == JsonValueKind.String ? tmE.GetString() ?? "" : "",
                    TargetFile = r.TryGetProperty("tf", out var tfE) && tfE.ValueKind == JsonValueKind.String ? tfE.GetString() ?? "" : "",
                    TargetLine = r.TryGetProperty("tl", out var tlE) && tlE.ValueKind == JsonValueKind.Number ? tlE.GetInt32() : 0,
                    TargetChar = r.TryGetProperty("tc2", out var tc2E) && tc2E.ValueKind == JsonValueKind.Number ? tc2E.GetInt32() : 0,
                });
                refCount++;
            }
        }
        Console.Error.WriteLine($"[lsp] index 装载（{Path.GetFileName(project.SpPath)}）：defs {defs.Count}，灰区 {inactive.Count} 文件，ignored {ignored.Count}，refs {refCount}"); // [lsp-trace]

        PublishInactiveRegions(project);
    }

    /* symbols 数组项 → DefEntry（f/l/c 基准与 excluded 一致：l 1-based / c 0-based） */
    private static DefEntry? ReadDef(JsonElement el, string fullName, string kind)
    {
        if (fullName.Length == 0)
        {
            return null;
        }
        return new DefEntry
        {
            Kind = kind,
            Name = el.TryGetProperty("n", out var nE) && nE.ValueKind == JsonValueKind.String ? nE.GetString() ?? "" : "",
            FullName = fullName,
            File = el.TryGetProperty("f", out var fE) && fE.ValueKind == JsonValueKind.String ? fE.GetString() ?? "" : "",
            Line = el.TryGetProperty("l", out var lE) && lE.ValueKind == JsonValueKind.Number ? lE.GetInt32() : 0,
            Char = el.TryGetProperty("c", out var cE) && cE.ValueKind == JsonValueKind.Number ? cE.GetInt32() : 0,
        };
    }

    /* 灰区推送：对当前打开且属于该工程的文档逐个发 slang/publishInactiveRegions。
     * ranges 为空数组 = 清除该文档灰显（上一轮裁剪本轮不再裁剪时）。 */
    private void PublishInactiveRegions(ProjectInfo project)
    {
        foreach (var kv in _docs)
        {
            if (kv.Value.SpPath != project.SpPath)
            {
                continue;
            }
            SendInactiveRegions(project, kv.Key);
        }
    }

    /* 单文档灰区计算与推送：excluded 区间 + ignored 整文档（取 _docText 定位末行）。 */
    private void SendInactiveRegions(ProjectInfo project, string uri)
    {
        string full;
        try
        {
            full = Path.GetFullPath(UriToPath(uri));
        }
        catch
        {
            return;
        }
        var ranges = new List<object>();
        if (_projectInactive.TryGetValue(project.SpPath, out var byFile) && byFile.TryGetValue(full, out var list))
        {
            foreach (var r in list)
            {
                ranges.Add(new
                {
                    start = new { line = r.Line, character = r.Char },
                    end = new { line = r.EndLine, character = r.EndChar },
                });
            }
        }
        if (_projectIgnoredFiles.TryGetValue(project.SpPath, out var ignored) && ignored.Contains(full))
        {
            string text = GetDocText(uri);
            (int lastLine, int lastChar) = OffsetToPosition(text, text.Length);
            ranges.Add(new
            {
                start = new { line = 0, character = 0 },
                end = new { line = lastLine, character = lastChar },
            });
        }
        Notify("slang/publishInactiveRegions", new { uri, ranges });
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
                    Permission = c.TryGetProperty("permission", out var pm) && pm.ValueKind == JsonValueKind.Number ? pm.GetInt32() : 0,
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
                            Flags = ff.TryGetProperty("flags", out var fg) && fg.ValueKind == JsonValueKind.Number ? fg.GetInt32() : 0,
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

        // 成员感知：光标前是 `<接收者>.`（含 `接收者.部分词`）→ 接收者类型成员补全。
        // 接收者 = 类名（静态）/ this / 局部变量与参数声明 / var 推断 / 方法调用返回类型 /
        // 限定名聚合（SLang.Server.onGet 链）——解析失败不回落全局（作用域正确性优先）。
        string text = GetDocText(uri);
        if (parms.TryGetProperty("position", out var pos))
        {
            int offset = PositionToOffset(text, pos);
            var chain = ExtractMemberChain(text, offset);
            if (chain != null)
            {
                var receiver = ResolveReceiverType(text, offset, chain, table);
                if (receiver != null)
                {
                    if (receiver.Builtin != null)
                    {
                        foreach (var (label, kind, detail) in receiver.Builtin)
                        {
                            Add(label, kind, detail);
                        }
                    }
                    else if (receiver.Cls != null)
                    {
                        AddClassMembers(receiver.Cls, Add, receiver.IsStatic);
                    }
                }
                return new { isIncomplete = false, items }; // 接收者不可解析：不回落全局
            }
        }

        // 全局补全：关键字 + 类 + 成员裸名 + 系统方法
        foreach (var kw in Keywords)
        {
            Add(kw, 14, "关键字");
        }
        // 系统类型小写别名（int → Core.Int32；与类条目并列呈现，输入别名即见目标）
        foreach (var kv in TypeAliases)
        {
            Add(kv.Key, 7, "系统类型别名 → Core." + kv.Value);
        }
        foreach (var cls in table.Classes)
        {
            Add(cls.Name, cls.Kind, cls.FullName);
            // 泛型类双标签：Array<T>/Map<K,V> 之外补裸基名（Array/Map），
            // 输入裸词精确命中（VSCode 模糊匹配只对前缀友好）
            int ltCls = cls.Name.IndexOf('<');
            if (ltCls > 0)
            {
                Add(cls.Name[..ltCls], cls.Kind, cls.FullName);
            }
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

    /* 类成员补全项。staticContext：true=类名静态访问（只静态方法+静态字段）、
     * false=实例访问（实例方法+字段）、null=全局补全（两列全收，兼容旧语义）。
     * 访问级别（public 才提示）：private 字段一律不提示；protected 字段跨模块引用包
     * 不可见（工程自身类保留）；方法 SLIR 不导出访问级别（SL 默认 public）全收。 */
    private static void AddClassMembers(ClassInfo cls, Action<string, int, string> add, bool? staticContext = null)
    {
        if (cls.IsPrivateClass)
        {
            return; // 引用包 private 类：成员不外显
        }
        if (staticContext != true)
        {
            foreach (var m in cls.InstanceMethods)
            {
                add(m.Name, 2, m.Signature + " — " + cls.FullName);
            }
        }
        if (staticContext != false)
        {
            foreach (var m in cls.StaticMethods)
            {
                add(m.Name, 2, m.Signature + " — " + cls.FullName);
            }
        }
        foreach (var f in cls.Fields)
        {
            if (f.IsPrivate)
            {
                continue;
            }
            if (f.IsProtected && !cls.IsProject)
            {
                continue; // 跨模块 protected 不可访问
            }
            if (staticContext == true && !f.IsStatic)
            {
                continue; // 类名静态访问：不提示实例字段
            }
            add(f.Name, 5, (f.Type.Length > 0 ? f.Type + " " : "") + f.Name + " — " + cls.FullName);
        }
    }

    // =====================================================================
    // 接收者类型解析（成员补全核心，2026-10-21）：
    //   `cfg.`            → cfg 声明类型（局部变量/参数/闭包参数）的实例成员
    //   `Box.`            → 类名静态成员（L2 原语义）
    //   `Box(args).`      → 构造调用 → 实例成员
    //   `make().`         → 方法返回类型成员（裸名/链上）
    //   `a.b.c.`          → 链式逐段推进（字段类型/方法返回类型）
    //   `SLang.Server.`   → 限定名聚合（命名空间.类）
    //   `this.`           → 光标所在类实例成员
    // =====================================================================
    private sealed class ReceiverType
    {
        public ClassInfo? Cls;                                                   // 解析到的类（Builtin 非空时为 null）
        public bool IsStatic;                                                    // true=类名静态访问
        public List<(string Label, int Kind, string Detail)>? Builtin;           // 基元/数组内建成员
    }

    private sealed class ChainToken
    {
        public required string Ident;
        public string? Args;                                                     // 非 null = 带实参的调用段
        public bool HasCall => Args != null;
    }

    /* 光标处符号解析结果（hover/definition 共用）：成员（Owner 保住 FieldInfo
     * 源位置）或类名链命中（Class 非空）。 */
    private sealed class SymbolAt
    {
        public ClassInfo? Class;      // 类名链命中（SLang.Server / 裸类名）
        public ClassInfo? Owner;      // 成员所属类
        public MethodInfo? Method;   // 方法命中（与 Field 互斥）
        public FieldInfo? Field;      // 字段命中（保住 FieldInfo：源位置不丢）
    }

    /* 数组内建成员（SLIR 无类条目，`arr.length` 文法内建） */
    private static readonly List<(string, int, string)> ArrayBuiltinMembers = new()
    {
        ("length", 5, "内建 数组长度"),
    };

    /* 提取光标所在行的成员访问链（`.` 左侧接收者，含可选未完成尾词）。
     * 形态：IDENT(.IDENT(实参)?)* —— 实参段限本行配对括号（跳字符串）。
     * 非成员场景（`.` 左非链 / 本行无 `.`）返回 null。
     * token 流中 '.' 之外的标点为链边界（`=` `;` `(` 等），从尾部回溯取连续链段，
     * `ret Box().` / `Int32 n = ServerP3Test.rawReq(..).` 均正确截取接收者。 */
    private static List<ChainToken>? ExtractMemberChain(string text, int offset)
    {
        int cursor = Math.Min(offset, text.Length);
        int lineStart = cursor > 0 ? text.LastIndexOf('\n', cursor - 1) + 1 : 0;
        // 1) 未完成尾词 + 空白 → 必须 '.'
        int p = cursor;
        while (p > lineStart && (char.IsLetterOrDigit(text[p - 1]) || text[p - 1] == '_'))
        {
            p--;
        }
        int q = p;
        while (q > lineStart && char.IsWhiteSpace(text[q - 1]))
        {
            q--;
        }
        if (q <= lineStart || text[q - 1] != '.')
        {
            return null;
        }
        int end = q - 1;   // '.' 位置
        // 2) 行内 token 化（lineStart..end）：IDENT / '.' / (实参) / 其他=边界
        var toks = new List<object>();   // ChainToken | '.' | "BREAK"
        int i = lineStart;
        while (i < end)
        {
            char c = text[i];
            if (char.IsWhiteSpace(c))
            {
                i++;
            }
            else if (char.IsLetter(c) || c == '_')
            {
                int s = i;
                while (i < end && (char.IsLetterOrDigit(text[i]) || text[i] == '_'))
                {
                    i++;
                }
                toks.Add(new ChainToken { Ident = text[s..i] });
            }
            else if (c == '.')
            {
                toks.Add('.');
                i++;
            }
            else if (c == '(')
            {
                // 实参段：配对到 ')'（跳字符串、嵌套计数）；未闭合（跨行）→ 链失败
                int j = i + 1;
                int depth = 1;
                while (j < end && depth > 0)
                {
                    char d = text[j];
                    if (d == '"' || d == '\'')
                    {
                        j = SlangScanner.SkipString(text, j, d);
                        continue;
                    }
                    if (d == '(')
                    {
                        depth++;
                    }
                    else if (d == ')')
                    {
                        depth--;
                    }
                    j++;
                }
                if (depth != 0)
                {
                    return null; // 实参跨行：本行链不完整
                }
                if (toks.Count > 0 && toks[^1] is ChainToken t)
                {
                    t.Args = text[(i + 1)..(j - 1)];
                    i = j;
                }
                else
                {
                    return null; // '(' 无前置 IDENT：非链形态
                }
            }
            else
            {
                toks.Add("BREAK");
                i++;
            }
        }
        // 3) 尾部回溯连续链段：IDENT(.IDENT)*（实参已挂在 IDENT 上）
        int k = toks.Count - 1;
        if (k < 0 || toks[k] is not ChainToken)
        {
            return null; // 尾部非 IDENT（如 `x..`）
        }
        while (k - 2 >= 0 && toks[k - 1] is '.' && toks[k - 2] is ChainToken)
        {
            k -= 2;
        }
        var chain = new List<ChainToken>();
        for (int m = k; m < toks.Count; m++)
        {
            if (toks[m] is ChainToken t)
            {
                chain.Add(t);
            }
        }
        return chain.Count > 0 ? chain : null;
    }

    /* 接收者链 → 类型。优先级：限定名聚合类（SLang.Server → 静态起点）→ this →
     * 声明类型（局部变量/参数，含 var 推断）→ 裸方法调用返回类型。 */
    private ReceiverType? ResolveReceiverType(string text, int offset, List<ChainToken> chain, MergedTable table)
    {
        // 1) 限定名聚合：头部连续段拼全名查类表，最长优先（SLang.Server.onGet → SLang.Server）
        for (int len = chain.Count; len >= 1; len--)
        {
            var cls = ResolveClassByName(string.Join(".", chain.Take(len).Select(t => t.Ident)), table);
            if (cls == null)
            {
                continue;
            }
            if (len == chain.Count)
            {
                // 整链即类型名：`Box(args).` 构造 → 实例；`SLang.Server.` 类型引用 → 静态
                return chain[^1].HasCall
                    ? new ReceiverType { Cls = cls, IsStatic = false }
                    : new ReceiverType { Cls = cls, IsStatic = true };
            }
            // 命中段是链前缀：`SLang.Server.onGet(..)` → 静态起点；
            // `Box(args).field.`（构造调用命中）→ 实例起点
            return WalkChain(cls, isStatic: !chain[len - 1].HasCall, chain, from: len, table);
        }
        // 2) this → 光标所在类
        if (chain[0].Ident == "this")
        {
            var self = FindEnclosingClass(text, offset, table);
            return self != null ? WalkChain(self, isStatic: false, chain, from: 1, table) : null;
        }
        // 3) 声明类型（局部变量/方法参数/闭包参数；var 走初始化推断）
        string? declType = FindDeclarationType(text, offset, chain[0].Ident);
        if (declType != null)
        {
            if (declType.EndsWith("[]"))
            {
                return chain.Count == 1 ? new ReceiverType { Builtin = ArrayBuiltinMembers } : null;
            }
            var cls = ResolveClassByName(declType, table);
            if (cls != null)
            {
                return WalkChain(cls, isStatic: false, chain, from: 1, table);
            }
            // var 推断的初始化表达式非类型名（2026-10-23 修复）：`var v = Animal.make("x")`
            // 的 declType = "Animal.make"（InferVarInitType 原样返回调用前缀）——查类必然落空。
            // 按 '.' 拆段当链解析（InferVarInitType 仅调用形态返回 → 尾段 HasCall），
            // 复用本方法限定名聚合/链式推进/裸调用语义取返回类型，再推进外层 chain
            var initChain = new List<ChainToken>();
            bool ok = declType.Length > 0;
            foreach (var seg in declType.Split('.'))
            {
                if (seg.Length == 0 || !(char.IsLetter(seg[0]) || seg[0] == '_'))
                {
                    ok = false;
                    break;
                }
                initChain.Add(new ChainToken { Ident = seg });
            }
            if (ok && initChain.Count > 0)
            {
                initChain[^1] = new ChainToken { Ident = initChain[^1].Ident, Args = "" }; // 尾段是调用
                var init = ResolveReceiverType(text, offset, initChain, table);
                if (init?.Cls != null)
                {
                    return WalkChain(init.Cls, init.IsStatic, chain, from: 1, table);
                }
            }
            return null;
        }
        // 4) 裸方法调用（global.imports 提升的裸名，如 `println()`）：全表搜方法名取返回类型
        if (chain[0].HasCall)
        {
            foreach (var c in table.Classes)
            {
                foreach (var m in c.StaticMethods.Concat(c.InstanceMethods))
                {
                    if (string.Equals(m.Name, chain[0].Ident, StringComparison.Ordinal) && m.ReturnType.Length > 0
                        && ResolveClassByName(m.ReturnType, table) is { } rc)
                    {
                        return WalkChain(rc, isStatic: false, chain, from: 1, table);
                    }
                }
            }
        }
        return null;
    }

    /* 从 from 段起逐段推进类型：方法段 → 返回类型；字段段 → 字段类型。
     * 基元/void/未知类型名（SLIR 无类条目）链断返回 null。 */
    private ReceiverType? WalkChain(ClassInfo start, bool isStatic, List<ChainToken> chain, int from, MergedTable table)
    {
        var cur = start;
        bool stat = isStatic;
        for (int k = from; k < chain.Count; k++)
        {
            var seg = chain[k];
            MethodInfo? m = (stat
                ? cur.StaticMethods.FirstOrDefault(x => x.Name == seg.Ident) ?? cur.InstanceMethods.FirstOrDefault(x => x.Name == seg.Ident)
                : cur.InstanceMethods.FirstOrDefault(x => x.Name == seg.Ident) ?? cur.StaticMethods.FirstOrDefault(x => x.Name == seg.Ident));
            FieldInfo? fld = m == null ? cur.Fields.FirstOrDefault(x => x.Name == seg.Ident) : null;
            string? next = m != null ? (m.ReturnType.Length > 0 ? m.ReturnType : null) : fld?.Type;
            if (next == null)
            {
                return null;
            }
            if (next.EndsWith("[]"))
            {
                return k == chain.Count - 1 ? new ReceiverType { Builtin = ArrayBuiltinMembers } : null;
            }
            var nextCls = ResolveClassByName(next, table);
            if (nextCls == null)
            {
                return null;
            }
            cur = nextCls;
            stat = false;
        }
        return new ReceiverType { Cls = cur, IsStatic = stat };
    }

    /* 类型名 → 类符号：全名 → 短名 → 尾段（SLang.ServerConfig → ServerConfig）
     * → 剥泛型实参（List<string> → List，含限定名泛型 Std.Map<K,V> → Std.Map）
     * → 小写别名归一（int → Core.Int32，见 TypeAliases 注释——别名词元是词法
     *   关键字不可能是用户类名，最后兜底不影响正常解析序）。 */
    private static ClassInfo? ResolveClassByName(string name, MergedTable table)
    {
        if (name.Length == 0)
        {
            return null;
        }
        if (table.ByFullName.TryGetValue(name, out var byFull))
        {
            return byFull;
        }
        if (table.ByName.TryGetValue(name, out var byShort))
        {
            return byShort;
        }
        int dot = name.LastIndexOf('.');
        if (dot >= 0 && table.ByName.TryGetValue(name[(dot + 1)..], out var byTail))
        {
            return byTail;
        }
        int lt = name.IndexOf('<');
        if (lt > 0)
        {
            string baseName = name[..lt];
            if (table.ByFullName.TryGetValue(baseName, out var b1))
            {
                return b1;
            }
            if (table.ByName.TryGetValue(baseName, out var b2))
            {
                return b2;
            }
            dot = baseName.LastIndexOf('.');
            if (dot >= 0 && table.ByName.TryGetValue(baseName[(dot + 1)..], out var b3))
            {
                return b3;
            }
        }
        // 小写别名兜底：int/float/string 等（词法关键字别名，不可能是用户类名）
        if (TypeAliases.TryGetValue(name, out var canonical)
            && table.ByName.TryGetValue(canonical, out var byAlias))
        {
            return byAlias;
        }
        return null;
    }

    /* ident 的声明类型（光标前最近一次）：`Type ident` 形态（局部变量/方法参数/闭包
     * 参数/for 变量），词后须为 = ; , ) 行尾 # 之一；var 声明走初始化表达式推断。
     * 词位置经 SlangScanner.FindWords（跳字符串/注释/@块）。 */
    private static string? FindDeclarationType(string text, int offset, string ident)
    {
        string head = text[..Math.Min(offset, text.Length)];
        var words = SlangScanner.FindWords(head, ident);
        for (int i = words.Count - 1; i >= 0; i--)
        {
            int end = words[i].End;
            // 词后：= ; , ) 行尾 #（'(' 是方法定义/调用、'.' 是成员访问 → 排除）
            int p = end;
            while (p < head.Length && (head[p] == ' ' || head[p] == '\t' || head[p] == '\r'))
            {
                p++;
            }
            if (p < head.Length && head[p] is not ('=' or ';' or ',' or ')' or '#' or '\n'))
            {
                continue;
            }
            // 词前（空白分隔）：类型 token
            int q = words[i].Start;
            while (q > 0 && (head[q - 1] == ' ' || head[q - 1] == '\t'))
            {
                q--;
            }
            if (q == 0)
            {
                continue;
            }
            var typeTok = ReadTypeBackward(head, q);
            if (typeTok == null)
            {
                continue;
            }
            (string type, int start) = typeTok.Value;
            if (type == "var")
            {
                return InferVarInitType(head, end);
            }
            if (NonTypeWords.Contains(type))
            {
                continue; // 语句关键字误配（ret x / function h / new T 等）
            }
            if (!IsValidDeclPrefix(head, start))
            {
                continue;
            }
            return type;
        }
        return null;
    }

    /* 从 end（类型词尾，紧贴声明名左侧）向左读类型 token：
     *   限定名（A.B.C）+ 可选泛型后缀 <…> + 可选数组后缀 []（均在名字左侧）。
     *   泛型段内出现非类型字符（比较运算符误入防护）→ null。
     * 返回 (类型串, 起始偏移)。 */
    private static (string Type, int Start)? ReadTypeBackward(string text, int end)
    {
        int p = end;
        // 数组后缀：`Type[] name`（可多层 `[][]`）
        while (p > 0 && text[p - 1] == ']')
        {
            int b = p - 1;
            int depth = 0;
            while (b >= 0)
            {
                if (text[b] == ']')
                {
                    depth++;
                }
                else if (text[b] == '[')
                {
                    depth--;
                    if (depth == 0)
                    {
                        break;
                    }
                }
                b--;
            }
            if (b < 0)
            {
                return null;
            }
            p = b;   // 指向 '['，继续向左（可能又是 ']' 或泛型 '>'）
        }
        // 泛型后缀：`Type<T1,T2> name`（嵌套 List<List<int>> 计数配对）
        if (p > 0 && text[p - 1] == '>')
        {
            int b = p - 1;
            int depth = 0;
            while (b >= 0)
            {
                char c = text[b];
                if (c == '>')
                {
                    depth++;
                }
                else if (c == '<')
                {
                    depth--;
                    if (depth == 0)
                    {
                        break;
                    }
                }
                else if (!(char.IsLetterOrDigit(c) || c == '_' || c == '.' || c == ',' || char.IsWhiteSpace(c)))
                {
                    return null; // 段内非法字符：比较运算式误入
                }
                b--;
            }
            if (b < 0)
            {
                return null;
            }
            p = b;   // 指向 '<'
        }
        // 限定名：A.B.C（向左读到非词字符）
        int e = p;
        while (p > 0 && (char.IsLetterOrDigit(text[p - 1]) || text[p - 1] == '_' || text[p - 1] == '.'))
        {
            p--;
        }
        if (p == e)
        {
            return null;
        }
        string raw = text[p..e];
        if (raw.StartsWith('.') || raw.EndsWith('.') || raw.Contains(".."))
        {
            return null; // '.' 悬空（成员访问误入）
        }
        return (raw + text[e..end], p);
    }

    /* 类型 token 起点前的合法前缀：文本首/行首/边界符( ; { } = , (，或修饰符链
     * （public/private/static/const/mut/final/…）继续向前递归。 */
    private static bool IsValidDeclPrefix(string text, int typeStart)
    {
        int p = typeStart;
        while (true)
        {
            while (p > 0 && (text[p - 1] == ' ' || text[p - 1] == '\t'))
            {
                p--;
            }
            if (p == 0)
            {
                return true;
            }
            char c = text[p - 1];
            if (c is ';' or '{' or '}' or '=' or ',' or '(' or '\n' or '\r')
            {
                return true;
            }
            int e = p;
            while (p > 0 && (char.IsLetterOrDigit(text[p - 1]) || text[p - 1] == '_'))
            {
                p--;
            }
            if (p == e || !ModifierWords.Contains(text[p..e]))
            {
                return false;
            }
            // 修饰词（public static …）→ 继续向前
        }
    }

    private static readonly HashSet<string> ModifierWords = new(StringComparer.Ordinal)
    {
        "public", "private", "protected", "static", "const", "mut", "final",
        "inline", "override", "abstract", "extern", "partial", "params", "get", "set",
    };

    /* 不能作为声明类型名的关键字（语句/声明词；修饰符由前缀链消化，var 单独分支） */
    private static readonly HashSet<string> NonTypeWords = new(StringComparer.Ordinal)
    {
        "function", "new", "ret", "in", "out", "for", "if", "elif", "else", "while",
        "dowhile", "switch", "case", "default", "break", "next", "continue", "goto",
        "throw", "throws", "try", "catch", "finally", "checked", "unchecked", "await",
        "spawn", "yield", "import", "as", "namespace", "class", "interface", "enum",
        "data", "extends", "bind", "label", "this", "base", "typealias", "dynamic",
        "var", "void",
    };

    /* `var x = <init>` 初始化类型推断（保守）：构造调用 `Type(…)` → Type；
     * 其余（字面量/复杂表达式）返回 null（宁缺毋错）。 */
    private static string? InferVarInitType(string head, int afterIdent)
    {
        int p = afterIdent;
        while (p < head.Length && char.IsWhiteSpace(head[p]))
        {
            p++;
        }
        if (p >= head.Length || head[p] != '=')
        {
            return null;
        }
        p++;
        while (p < head.Length && (head[p] == ' ' || head[p] == '\t'))
        {
            p++;
        }
        if (p >= head.Length || !(char.IsLetter(head[p]) || head[p] == '_'))
        {
            return null;
        }
        int e = p;
        while (e < head.Length && (char.IsLetterOrDigit(head[e]) || head[e] == '_' || head[e] == '.'))
        {
            e++;
        }
        int q = e;
        while (q < head.Length && head[q] == ' ')
        {
            q++;
        }
        return q < head.Length && head[q] == '(' && e > p ? head[p..e] : null;
    }

    /* 光标向上最近的类/接口/data 声明（this 接收者解析） */
    private static ClassInfo? FindEnclosingClass(string text, int offset, MergedTable table)
    {
        string head = text[..Math.Min(offset, text.Length)];
        var m = Regex.Match(head, @"(?:^|\n)[ \t]*(?:(?:public|protected|private|abstract|final|static|partial|inline|extern)\s+)*(class|interface|data|enum)\s+([A-Za-z_][A-Za-z0-9_]*)",
            RegexOptions.RightToLeft);
        return m.Success ? ResolveClassByName(m.Groups[2].Value, table) : null;
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

        // -1) 编译期调用点关联（callSites，最高优先）：光标落在调用 token 区间 →
        //     目标方法签名卡（覆盖裸方法调用等文本启发式解析不了的形态）
        if (root.TryGetProperty("params", out var hovParms)
            && hovParms.ValueKind == JsonValueKind.Object
            && hovParms.TryGetProperty("position", out var hovPos)
            && hovPos.ValueKind == JsonValueKind.Object
            && hovPos.TryGetProperty("line", out var hl) && hl.ValueKind == JsonValueKind.Number
            && hovPos.TryGetProperty("character", out var hc) && hc.ValueKind == JsonValueKind.Number)
        {
            var hit = LookupCallSite(project, uri, hl.GetInt32(), hc.GetInt32(), word);
            if (hit != null)
            {
                string sig = hit.TargetName;
                string ownerName = "";
                ClassInfo? hcls = null;
                MethodInfo? mm = null;
                if (hit.TargetClass.Length > 0 && hit.TargetMethod.Length > 0)
                {
                    hcls = ResolveClassByName(hit.TargetClass, table); // 尾段/全名/短名多形态回退
                    if (hcls != null)
                    {
                        ownerName = hcls.FullName;
                        mm = FindMember(hcls, hit.TargetMethod);
                        if (mm != null)
                        {
                            sig = mm.Signature;
                        }
                    }
                }
                string ownerTail = ownerName.Length > 0 ? $"\n\n`{ownerName}`" : "";
                var callValue = $"```slang\n{sig}\n```{ownerTail}";
                if (hcls != null && mm != null)
                {
                    var doc = MemberDoc(project, hcls, mm, null);
                    if (doc != null) callValue += "\n\n" + doc;
                }
                return new { contents = new { kind = "markdown", value = callValue } };
            }
        }

        // 0) 类型感知解析（与 definition 共用 SymbolAt）：成员签名卡 / 字段卡 / 类卡片
        var sym = ResolveSymbolAt(text, offset, table);
        if (sym?.Method != null && sym.Owner != null)
        {
            var value = $"```slang\n{sym.Method.Signature}\n```\n\n`{sym.Owner.FullName}`";
            var doc = MemberDoc(project, sym.Owner, sym.Method, null);
            if (doc != null) value += "\n\n" + doc;
            return new { contents = new { kind = "markdown", value } };
        }
        if (sym?.Field != null && sym.Owner != null)
        {
            var value = $"```slang\n{sym.Field.Type} {sym.Field.Name}\n```\n\n`{sym.Owner.FullName}`";
            var doc = MemberDoc(project, sym.Owner, null, sym.Field);
            if (doc != null) value += "\n\n" + doc;
            return new { contents = new { kind = "markdown", value } };
        }
        if (sym?.Class != null)
        {
            var c0 = sym.Class;
            var card0 = $"```slang\nclass {c0.FullName}\n```\n\n{c0.StaticMethods.Count + c0.InstanceMethods.Count} 个方法 · {c0.Fields.Count} 个字段" + (c0.SourcePath.Length > 0 ? $"\n\n定义于 `{c0.SourcePath}`" : "");
            return new { contents = new { kind = "markdown", value = card0 } };
        }
        // 0.5) 成员声明处/类体内裸名：光标所在类体的成员（方法/字段）卡 + 文档。
        //      成员名是裸词、无 '.' 前缀，SymbolAt 解析不到声明自身，此处补齐
        var decl = FindEnclosingClass(text, offset, table);
        if (decl != null)
        {
            var dsym = FindMemberSymbol(decl, word);
            if (dsym?.Method != null)
            {
                var dvalue = $"```slang\n{dsym.Method.Signature}\n```\n\n`{decl.FullName}`";
                var ddoc = MemberDoc(project, decl, dsym.Method, null);
                if (ddoc != null) dvalue += "\n\n" + ddoc;
                return new { contents = new { kind = "markdown", value = dvalue } };
            }
            if (dsym?.Field != null)
            {
                var dvalue = $"```slang\n{dsym.Field.Type} {dsym.Field.Name}\n```\n\n`{decl.FullName}`";
                var ddoc = MemberDoc(project, decl, null, dsym.Field);
                if (ddoc != null) dvalue += "\n\n" + ddoc;
                return new { contents = new { kind = "markdown", value = dvalue } };
            }
        }
        // 1) 限定名成员（`Console.println`）；未命中不提前返回——`global.println`
        //    的 global 是全局空间别名而非类，须回落到裸名搜索
        if (qualifier.Length > 0 && table.ByName.TryGetValue(qualifier, out var qcls))
        {
            var m = FindMember(qcls, word);
            if (m != null)
            {
                var value = $"```slang\n{m.Signature}\n```\n\n`{qcls.FullName}`";
                var doc = MemberDoc(project, qcls, m, null);
                if (doc != null) value += "\n\n" + doc;
                return new { contents = new { kind = "markdown", value } };
            }
        }
        // 2) 类卡片
        if (table.ByName.TryGetValue(word, out var cls))
        {
            var card = $"```slang\nclass {cls.FullName}\n```\n\n{cls.StaticMethods.Count + cls.InstanceMethods.Count} 个方法 · {cls.Fields.Count} 个字段" + (cls.SourcePath.Length > 0 ? $"\n\n定义于 `{cls.SourcePath}`" : "");
            return new { contents = new { kind = "markdown", value = card } };
        }
        // 3) 裸方法名：全表搜同名（前 5 个）；唯一命中附定义类与文档
        var hits = new List<(ClassInfo Owner, MethodInfo M)>();
        foreach (var c2 in table.Classes)
        {
            foreach (var m in c2.StaticMethods.Concat(c2.InstanceMethods))
            {
                if (string.Equals(m.Name, word, StringComparison.Ordinal))
                {
                    hits.Add((c2, m));
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
        if (hits.Count == 1)
        {
            var (oc, om) = hits[0];
            var value = $"```slang\n{om.Signature}\n```\n\n`{oc.FullName}`";
            var doc = MemberDoc(project, oc, om, null);
            if (doc != null) value += "\n\n" + doc;
            return new { contents = new { kind = "markdown", value } };
        }
        return new { contents = new { kind = "markdown", value = "```slang\n" + string.Join("\n", hits.Select(h => h.M.Signature)) + "\n```" } };
    }

    // 取成员上方紧邻的注释块作为文档（供 hover 展示）：
    //  - 块注释 #![md] ... !#：内容为 Markdown（isMd=true）。词法 SharpLevel 块内是原文、
    //    不要求 # 前缀，多行 Markdown 直接支持（开闭标记同行或跨行均可）
    //  - 块注释 #! ... !# 与连续 # 行注释：原样文本（isMd=false）
    //  文档块须紧贴成员（中间空行即止）
    private static (string? text, bool isMd) ExtractDocComment(string[] lines, int memberLine)
    {
        if (memberLine <= 1) return (null, false);
        int i = memberLine - 2; // 0-based：紧邻成员上方的那一行
        if (i < 0) return (null, false);
        var head = lines[i].Trim();

        // 块注释结尾紧贴成员：闭合行（"!#" 独行或 "正文 !#"）不以 # 开头且含 !# →
        // 向上回溯开标记（#![tag] 优先，其次 #!），开闭之间为原文内容
        if (!head.StartsWith("#") && head.IndexOf("!#", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            int open = -1, close = i;
            string? tag = null;
            for (int j = close - 1; j >= 0; j--)
            {
                var u = lines[j];
                int lb = u.IndexOf("#![", StringComparison.Ordinal);
                if (lb >= 0)
                {
                    open = j;
                    int rb = u.IndexOf(']', lb + 3);
                    tag = rb >= 0 ? u.Substring(lb + 3, rb - lb - 3).Trim() : "";
                    break;
                }
                if (u.Contains("#!")) { open = j; break; }
                if (u.Contains("!#")) break; // 又见闭合（嵌套等形态）→ 放弃
            }
            if (open < 0) return (null, false);

            var content = new List<string>();
            for (int k = open; k <= close; k++)
            {
                var s = lines[k];
                if (k == open)
                {
                    s = s.Substring(s.IndexOf("#!", StringComparison.Ordinal) + 2); // 去 #!
                    if (tag != null)
                    {
                        int rb = s.IndexOf(']');
                        s = rb >= 0 ? s.Substring(rb + 1) : ""; // 去 [tag]
                    }
                    s = s.Trim();
                }
                else if (k == close)
                {
                    int e = s.IndexOf("!#", StringComparison.OrdinalIgnoreCase);
                    if (e >= 0) s = s.Substring(0, e);
                    s = s.Trim();
                }
                // 中间行原样保留（含空行——Markdown 段落语义依赖空行）
                if (s.Length > 0 || (k > open && k < close)) content.Add(s);
            }
            // 去公共前导空白（成员缩进会让 Markdown 行渲染成代码块）
            int minIndent = int.MaxValue;
            foreach (var s in content)
            {
                if (s.Trim().Length == 0) continue;
                int n = 0;
                while (n < s.Length && (s[n] == ' ' || s[n] == '\t')) n++;
                if (n < minIndent) minIndent = n;
            }
            if (minIndent == int.MaxValue) minIndent = 0;
            var joined = string.Join("\n", content.Select(s => s.Length > minIndent ? s.Substring(minIndent) : s)).Trim();
            if (joined.Length == 0) return (null, false);
            return (joined, string.Equals(tag, "md", StringComparison.OrdinalIgnoreCase));
        }

        // 连续 # 行注释（含同行自闭合的单行块注释 #![md] x !# / #! x !#）
        var collected = new List<string>();
        while (i >= 0)
        {
            var t = lines[i].Trim();
            if (t.Length == 0) break;          // 空行分隔：文档注释须紧贴成员
            if (t.StartsWith("#")) collected.Add(t);
            else break;
            i--;
        }
        if (collected.Count == 0) return (null, false);

        // 检测 markdown 文档块 #![md] ... !#
        int startIdx = -1, endIdx = -1;
        for (int k = 0; k < collected.Count; k++)
        {
            if (startIdx < 0 && collected[k].StartsWith("#![md]", StringComparison.OrdinalIgnoreCase)) startIdx = k;
            if (endIdx < 0 && collected[k].IndexOf("!#", StringComparison.OrdinalIgnoreCase) >= 0) endIdx = k;
        }
        if (startIdx >= 0 && endIdx >= 0)
        {
            var md = new List<string>();
            for (int k = endIdx; k <= startIdx; k++)
            {
                var s = collected[k];
                if (k == startIdx)
                {
                    int close = s.IndexOf(']');
                    s = close >= 0 ? s.Substring(close + 1) : s;
                }
                if (k == endIdx)
                {
                    int p = s.IndexOf("!#", StringComparison.OrdinalIgnoreCase);
                    if (p >= 0) s = s.Substring(0, p);
                }
                s = s.Trim();
                if (s.Length > 0) md.Add(s);
            }
            return (string.Join("\n", md), true);
        }

        // 普通注释：去前导 #（块注释去 #! 与结尾 !#），按原样文本返回
        var plain = new List<string>();
        foreach (var s in collected)
        {
            var line = s;
            if (line.StartsWith("#![")) { int c = line.IndexOf(']'); line = c >= 0 ? line.Substring(c + 1) : line.Substring(2); }
            else if (line.StartsWith("#!")) line = line.Substring(2);
            else if (line.StartsWith("#")) line = line.Substring(1);
            if (line.EndsWith("!#")) line = line.Substring(0, line.Length - 2);
            line = line.Trim();
            if (line.Length > 0) plain.Add(line);
        }
        return (string.Join("\n", plain), false);
    }

    // 依据成员源码位置，提取其上方文档注释（供 hover 展示）。
    // 定义锚点表优先（index.symbols 成员名 token 位置 = 声明行）；instruction debugInfo
    // 首条指向函数体首语句（如 describe 首指令是 ret 行），直接取其上方注释会落空。
    private string? MemberDoc(ProjectInfo project, ClassInfo owner, MethodInfo? m, FieldInfo? f)
    {
        if (owner == null) return null;
        string name = m != null ? m.Name : (f != null ? f.Name : "");
        if (name.Length > 0 && _projectDefs.TryGetValue(project.SpPath, out var defs)
            && defs.TryGetValue(owner.FullName + "." + name, out var def)
            && def.File.Length > 0 && def.Line > 0)
        {
            try
            {
                string cand = Path.GetFullPath(Path.Combine(project.Dir, def.File));
                if (File.Exists(cand))
                {
                    var (text0, isMd0) = ExtractDocComment(File.ReadAllLines(cand), def.Line);
                    if (!string.IsNullOrEmpty(text0))
                    {
                        return isMd0 ? text0 : "> " + text0.Replace("\n", "\n> ");
                    }
                }
            }
            catch { /* 锚点读盘失败回落 debugInfo 位置 */ }
        }
        string? sp = m != null ? m.SourcePath : f?.SourcePath;
        int line = m != null ? m.BeginLine : (f != null ? f.BeginLine : 0);
        if (string.IsNullOrEmpty(sp) || line <= 0) return null;
        var file = ResolveSourcePath(project, owner, sp);
        if (file == null || !File.Exists(file)) return null;
        try
        {
            var lines = File.ReadAllLines(file);
            var (text, isMd) = ExtractDocComment(lines, line);
            if (string.IsNullOrEmpty(text)) return null;
            // Markdown 块直接拼；普通注释用 blockquote 包一层，避免与 markdown 语法冲突
            return isMd ? text : "> " + text.Replace("\n", "\n> ");
        }
        catch { return null; }
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

    /* 成员名 → SymbolAt（导航不过滤 private：定义即所写处）；方法优先于字段 */
    private static SymbolAt? FindMemberSymbol(ClassInfo cls, string name)
    {
        foreach (var m in cls.StaticMethods)
        {
            if (string.Equals(m.Name, name, StringComparison.Ordinal))
            {
                return new SymbolAt { Owner = cls, Method = m };
            }
        }
        foreach (var m in cls.InstanceMethods)
        {
            if (string.Equals(m.Name, name, StringComparison.Ordinal))
            {
                return new SymbolAt { Owner = cls, Method = m };
            }
        }
        foreach (var f in cls.Fields)
        {
            if (string.Equals(f.Name, name, StringComparison.Ordinal))
            {
                return new SymbolAt { Owner = cls, Field = f };
            }
        }
        return null;
    }

    /* 光标处符号 → 类型感知解析（hover/definition 共用）：
     * ① 词前有 '.' → ExtractMemberChain(text, wordEnd)（链 = 词左侧接收者，不含光标词）
     *    a) 限定名类聚合含词段（SLang.Server，词 = 尾段类名）
     *    b) ResolveReceiverType → FindMemberSymbol（cfg.port / b.inner.w / Box.make().area）
     *    c) 旧兜底：qualifier 类短名（WordAt 的单段限定）
     *    d) 词本身是类名
     * ② 无 '.' → 裸类名 ResolveClassByName
     * global.println 等全局空间别名 → null（调用方回落旧裸名搜索） */
    private SymbolAt? ResolveSymbolAt(string text, int offset, MergedTable table)
    {
        var (word, qualifier) = WordAt(text, offset);
        if (word.Length == 0)
        {
            return null;
        }
        int wordEnd = Math.Min(offset, text.Length);
        while (wordEnd < text.Length && (char.IsLetterOrDigit(text[wordEnd]) || text[wordEnd] == '_'))
        {
            wordEnd++;
        }
        var chain = ExtractMemberChain(text, wordEnd);
        if (chain != null)
        {
            // a) 链前缀 + 光标词 = 限定类名（SLang.Server）
            for (int len = chain.Count; len >= 1; len--)
            {
                var cls = ResolveClassByName(string.Join(".", chain.Take(len).Select(t => t.Ident)) + "." + word, table);
                if (cls != null)
                {
                    return new SymbolAt { Class = cls };
                }
            }
            // b) 接收者类型 → 成员
            var receiver = ResolveReceiverType(text, offset, chain, table);
            if (receiver?.Cls != null)
            {
                var sym = FindMemberSymbol(receiver.Cls, word);
                if (sym != null)
                {
                    return sym;
                }
            }
            // c) 旧兜底：qualifier 类短名（如局部变量遮蔽时仍按类名解析）
            if (qualifier.Length > 0 && table.ByName.TryGetValue(qualifier, out var qcls))
            {
                var m = FindMemberSymbol(qcls, word);
                if (m != null)
                {
                    return m;
                }
            }
            // d) 词本身是类名
            var self = ResolveClassByName(word, table);
            if (self != null)
            {
                return new SymbolAt { Class = self };
            }
            return null;
        }
        // ② 裸名：类优先
        var bare = ResolveClassByName(word, table);
        if (bare != null)
        {
            return new SymbolAt { Class = bare };
        }
        return null;
    }

    // =====================================================================
    // 定义跳转：类/方法 → sourcePath（+ debugInfo 行列）
    // =====================================================================
    /* 编译期调用点关联查询：行匹配 + 光标词 == 调用符号名（主通道，token 列
     * 语义混杂——词首/词尾/调用尾皆有——词名匹配免疫歧义）+ 区间容忍（辅） */
    private CallSiteEntry? LookupCallSite(ProjectInfo project, string uri, int line0, int chr, string word)
    {
        if (!_projectCallSites.TryGetValue(project.SpPath, out var list) || list.Count == 0)
        {
            return null;
        }
        string full;
        try
        {
            full = Path.GetFullPath(UriToPath(uri));
        }
        catch
        {
            return null;
        }
        int line1 = line0 + 1;
        foreach (var e in list)
        {
            if (e.Line != line1)
            {
                continue;
            }
            if (!string.Equals(e.File, full, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (word.Length > 0 && string.Equals(word, e.Name, StringComparison.Ordinal))
            {
                return e;
            }
            // token.sourceEndChar 实测常为 0（未填），用符号名长度兜底区间终点
            int begin = Math.Min(e.BeginChar, Math.Max(0, e.BeginChar - e.Name.Length));
            int end = Math.Max(Math.Max(e.EndChar, e.BeginChar), e.BeginChar + e.Name.Length);
            if (chr >= begin && chr <= end)
            {
                return e;
            }
        }
        return null;
    }

    /* 调用点目标解析：tf（本地编译定义文件）直用 → 本工程定义锚点表（index.symbols，
     * 名字 token 位置，比 instruction 锚点准）→ MergedTable 回查。
     * kind=type（index.refs 类型名引用）：目标为类型本身，走定义表/类表而非成员表。
     * ref module 目标 tf 为空（源码属编译产物/加密侧不处理）→ 仅剩 tc/tm 查表键。 */
    private (string? File, int Line, int Char)? ResolveCallSiteTarget(ProjectInfo project, CallSiteEntry e)
    {
        if (e.TargetFile.Length > 0)
        {
            try
            {
                string cand = Path.GetFullPath(Path.Combine(project.Dir, e.TargetFile));
                if (File.Exists(cand))
                {
                    return (cand, e.TargetLine, e.TargetChar);
                }
            }
            catch
            {
                /* 路径异常回落查表 */
            }
        }
        if (e.TargetClass.Length == 0)
        {
            return null;
        }
        // 本工程定义锚点优先（index.symbols；成员键 "类全名.成员名"，类型键 "类全名"）
        if (_projectDefs.TryGetValue(project.SpPath, out var defs))
        {
            string key = e.TargetMethod.Length > 0 ? e.TargetClass + "." + e.TargetMethod : e.TargetClass;
            if (defs.TryGetValue(key, out var def) && def.File.Length > 0)
            {
                try
                {
                    string cand = Path.GetFullPath(Path.Combine(project.Dir, def.File));
                    if (File.Exists(cand))
                    {
                        return (cand, def.Line, def.Char);
                    }
                }
                catch
                {
                    /* 路径异常回落查表 */
                }
            }
        }
        if (e.TargetMethod.Length == 0)
        {
            // 类型名引用：目标即类型（class/interface/enum/data 声明处）
            if (e.Kind == "type")
            {
                var tableT = BuildMergedTable(project);
                var tcls = ResolveClassByName(e.TargetClass, tableT);
                string? fileT = tcls != null ? ResolveSourcePath(project, tcls, tcls.SourcePath) : null;
                if (fileT != null && tcls != null)
                {
                    // 类型声明锚点：旧实现恒返回 (0,0)（文件头）
                    var anchor = FindTypeAnchor(project, tcls, fileT);
                    return (fileT, anchor?.Line ?? 0, anchor?.Char ?? 0);
                }
            }
            return null;
        }
        var table = BuildMergedTable(project);
        var tc = ResolveClassByName(e.TargetClass, table); // 尾段/全名/短名多形态回退
        if (tc == null)
        {
            return null;
        }
        var mm = FindMember(tc, e.TargetMethod);
        if (mm == null)
        {
            return null;
        }
        string? file = ResolveSourcePath(project, tc, mm.SourcePath.Length > 0 ? mm.SourcePath : tc.SourcePath);
        if (file == null)
        {
            return null;
        }
        return (file, mm.SourcePath.Length > 0 ? mm.BeginLine : 0, mm.SourcePath.Length > 0 ? mm.BeginChar : 0);
    }

    /* 类型声明锚点（2026-10-23 类名定义跳转修复——旧实现无行号恒落文件头）：
     * index.symbols 定义锚点优先（l 1-based；c 实测为名字 token 末位，经行文本
     * 校正到词首）；无索引（引用模块类型/首编成功前）回落源文件文本扫描首个
     * (class|interface|enum|data|typealias)\s+类名 声明行。
     * 返回 (1-based 行, 0-based 名字词首列)；两路皆落空返回 null（调用方回退 0）。 */
    private (int Line, int Char)? FindTypeAnchor(ProjectInfo project, ClassInfo cls, string file)
    {
        if (_projectDefs.TryGetValue(project.SpPath, out var defs)
            && defs.TryGetValue(cls.FullName, out var def) && def.File.Length > 0 && def.Line > 0)
        {
            try
            {
                if (string.Equals(Path.GetFullPath(Path.Combine(project.Dir, def.File)), file, StringComparison.OrdinalIgnoreCase))
                {
                    return (def.Line, NameStartChar(file, def.Line, def.Char, cls.Name));
                }
            }
            catch
            {
                /* 路径异常走文本扫描 */
            }
        }
        return ScanTypeDeclAnchor(file, cls.Name);
    }

    /* 声明行名字词首：锚 char 语义混杂（token 末位/词首皆有），按声明行文本
     * IndexOf(名字) 定位词首；读失败/未命中按「末位 - 名长 + 1」推算，再兜底原值 */
    private static int NameStartChar(string file, int line1, int chr, string name)
    {
        if (name.Length > 0)
        {
            try
            {
                var lines = File.ReadAllLines(file);
                int li = Math.Min(Math.Max(0, line1 - 1), lines.Length - 1);
                int c = lines[li].IndexOf(name, StringComparison.Ordinal);
                if (c >= 0)
                {
                    return c;
                }
            }
            catch
            {
                /* 读失败走末位推算 */
            }
            if (chr >= name.Length - 1)
            {
                return chr - name.Length + 1;
            }
        }
        return Math.Max(0, chr);
    }

    /* 源文件文本扫描类型声明（2026-10-23 对齐 Frontend 规则）：
     * Front 权威 = StructParseFrame.ParseRootNodeToFileMeta / ParseNamespaceOrTopClass——
     * ① class/data/enum/interface/typealias 等关键字 + 名字（容忍 public 等前导修饰，
     *   如 `public class String extends Object`）；② 无关键字裸类（如 .sp 的 `Project{}`）
     *   也是类——[修饰符…]* Name 后随行尾/{/: 继承 即命中。
     * 名字含命名空间段时取尾段比对。文件不可读/未命中返回 null。 */
    private static readonly string[] TypeDeclKeywords = { "class", "interface", "enum", "data", "typealias" };
    private static readonly char[] WhitespaceSeparators = { ' ', '\t' };
    private static readonly string[] TypeDeclModifiers =
    {
        "public", "private", "protected", "projected", "partial", "final", "const",
        "static", "abstract", "inline", "mut", "override", "extern", "bind",
    };

    private static (int Line, int Char)? ScanTypeDeclAnchor(string file, string name)
    {
        int dot = name.LastIndexOf('.');
        string shortName = dot >= 0 ? name.Substring(dot + 1) : name;
        if (shortName.Length == 0)
        {
            return null;
        }
        string[] lines;
        try
        {
            lines = File.ReadAllLines(file);
        }
        catch
        {
            return null;
        }
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            int first = 0;
            while (first < line.Length && char.IsWhiteSpace(line[first]))
            {
                first++;
            }
            if (first >= line.Length || line[first] == '#')
            {
                continue; // 空行/注释行
            }
            // 形态①：关键字 + 空白 + 类名（行内任意词位，容忍前导修饰符）
            foreach (var kw in TypeDeclKeywords)
            {
                for (int idx = 0; (idx = line.IndexOf(kw, idx, StringComparison.Ordinal)) >= 0; idx += kw.Length)
                {
                    int kwEnd = idx + kw.Length;
                    // 关键字须词首起（前是行首/空白），后随空白再接类名
                    if (idx > 0 && !char.IsWhiteSpace(line[idx - 1]))
                    {
                        continue;
                    }
                    if (kwEnd >= line.Length || !char.IsWhiteSpace(line[kwEnd]))
                    {
                        continue;
                    }
                    int nameIdx = kwEnd;
                    while (nameIdx < line.Length && char.IsWhiteSpace(line[nameIdx]))
                    {
                        nameIdx++;
                    }
                    if (nameIdx + shortName.Length > line.Length
                        || !string.Equals(line.Substring(nameIdx, shortName.Length), shortName, StringComparison.Ordinal))
                    {
                        continue;
                    }
                    char after = nameIdx + shortName.Length < line.Length ? line[nameIdx + shortName.Length] : '\0';
                    if (char.IsLetterOrDigit(after) || after == '_')
                    {
                        continue; // 词边界：防前缀同名（AnimalX ≠ Animal）
                    }
                    return (i + 1, nameIdx);
                }
            }
            // 形态②：无关键字裸类（Frontend：顶级 Name{} 也是类）——
            // 剔除行内 # 注释后按空白分词，剥前导修饰符，剩 [Name] 或 [Name, "{"|":", …]
            int hash = line.IndexOf('#');
            string code = hash >= 0 ? line.Substring(0, hash) : line;
            var segs = code.Split(WhitespaceSeparators, StringSplitOptions.RemoveEmptyEntries);
            int s = 0;
            while (s < segs.Length && Array.IndexOf(TypeDeclModifiers, segs[s]) >= 0)
            {
                s++;
            }
            if (s < segs.Length
                && (string.Equals(segs[s], shortName, StringComparison.Ordinal)
                    || string.Equals(segs[s].TrimEnd('{'), shortName, StringComparison.Ordinal))
                && (s + 1 >= segs.Length || segs[s + 1] == "{" || segs[s + 1] == ":"))
            {
                int c = line.IndexOf(shortName, first, StringComparison.Ordinal);
                if (c >= 0)
                {
                    return (i + 1, c);
                }
            }
        }
        return null;
    }

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

        // -1) 编译期调用点关联（callSites，最高优先）：光标落在调用 token 区间 →
        //     精确直达目标定义（数据源 = MetaCallNode 解析结果的 IR 沉淀，
        //     覆盖裸方法调用等文本启发式解析不了的形态）
        if (root.TryGetProperty("params", out var defParms)
            && defParms.ValueKind == JsonValueKind.Object
            && defParms.TryGetProperty("position", out var defPos)
            && defPos.ValueKind == JsonValueKind.Object
            && defPos.TryGetProperty("line", out var dl) && dl.ValueKind == JsonValueKind.Number
            && defPos.TryGetProperty("character", out var dc) && dc.ValueKind == JsonValueKind.Number)
        {
            var hit = LookupCallSite(project, uri, dl.GetInt32(), dc.GetInt32(), word);
            if (hit != null)
            {
                var tgt = ResolveCallSiteTarget(project, hit);
                if (tgt != null && tgt.Value.File != null && File.Exists(tgt.Value.File))
                {
                    int tline = Math.Max(0, tgt.Value.Line - 1);
                    int tchr = Math.Max(0, tgt.Value.Char);
                    // 目标 char 语义混杂（token 列词首/词尾皆有），按目标行文本
                    // IndexOf(方法短名) 定位词首，失败回落 token char
                    string mshort = hit.TargetMethod.Length > 0 ? hit.TargetMethod : hit.TargetName;
                    try
                    {
                        var tl = File.ReadAllLines(tgt.Value.File);
                        int li = Math.Min(tline, tl.Length - 1);
                        int c = tl[li].IndexOf(mshort, StringComparison.Ordinal);
                        if (c >= 0)
                        {
                            tchr = c;
                        }
                    }
                    catch
                    {
                        /* 读失败用 token char */
                    }
                    return new[]
                    {
                        new
                        {
                            uri = PathToUri(tgt.Value.File),
                            range = new
                            {
                                start = new { line = tline, character = tchr },
                                end = new { line = tline, character = tchr },
                            },
                        },
                    };
                }
            }
        }

        var table = BuildMergedTable(project);

        // 0) 类型感知解析（复用成员补全链设施）：cfg.port / SLang.Server.start /
        //    b.inner.w / Box.make().area / 限定类名——直达成员级源位置
        string? file = null;
        int line = 0;
        int chr = 0;
        bool resolved = false;
        var sym = ResolveSymbolAt(text, offset, table);
        if (sym?.Class != null)
        {
            file = ResolveSourcePath(project, sym.Class, sym.Class.SourcePath);
            if (file != null)
            {
                // 类型声明锚点（index.symbols → 文本扫描兜底）：旧实现不置行列，恒跳文件头
                var anchor = FindTypeAnchor(project, sym.Class, file);
                line = anchor?.Line ?? 0;
                chr = anchor?.Char ?? 0;
            }
            resolved = true;
        }
        else if (sym?.Method != null && sym.Owner != null)
        {
            file = ResolveSourcePath(project, sym.Owner, sym.Method.SourcePath.Length > 0 ? sym.Method.SourcePath : sym.Owner.SourcePath);
            line = sym.Method.SourcePath.Length > 0 ? sym.Method.BeginLine : 0;
            chr = sym.Method.SourcePath.Length > 0 ? sym.Method.BeginChar : 0;
            resolved = true;
        }
        else if (sym?.Field != null && sym.Owner != null)
        {
            file = ResolveSourcePath(project, sym.Owner, sym.Field.SourcePath.Length > 0 ? sym.Field.SourcePath : sym.Owner.SourcePath);
            line = sym.Field.SourcePath.Length > 0 ? sym.Field.BeginLine : 0;
            chr = sym.Field.SourcePath.Length > 0 ? sym.Field.BeginChar : 0;
            resolved = true;
        }

        // 兜底：与 hover 同构的旧回退（限定名成员 → 本工程定义锚点成员 → 类 → 裸方法名首个命中）
        if (!resolved && qualifier.Length > 0 && table.ByName.TryGetValue(qualifier, out var qcls))
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
        // 本工程定义锚点表成员短名回查（2026-10-23）：工程入口类（.sp 的 Project{}，
        // 无 class 关键字裸类）成员可能不进 SLIR 类表——全类扫描会首个命中引用模块
        // 同名方法（如 _main_ 跳 Core.sp）；index.symbols（MetaCore 关联索引）才有锚点，
        // 按既有设计"定义锚点优先于 MergedTable 回查"
        if (!resolved && word.Length > 0 && _projectDefs.TryGetValue(project.SpPath, out var pdefs))
        {
            foreach (var kv in pdefs)
            {
                int lastDot = kv.Key.LastIndexOf('.');
                if (lastDot < 0 || lastDot + 1 >= kv.Key.Length
                    || !string.Equals(kv.Key.Substring(lastDot + 1), word, StringComparison.Ordinal))
                {
                    continue;
                }
                if (kv.Value.File.Length == 0 || kv.Value.Line <= 0)
                {
                    continue;
                }
                try
                {
                    string cand = Path.GetFullPath(Path.Combine(project.Dir, kv.Value.File));
                    if (File.Exists(cand))
                    {
                        file = cand;
                        line = kv.Value.Line;
                        chr = NameStartChar(cand, kv.Value.Line, kv.Value.Char, word);
                        resolved = true;
                        break;
                    }
                }
                catch
                {
                    /* 路径异常继续找 */
                }
            }
        }
        if (!resolved && table.ByName.TryGetValue(word, out var cls))
        {
            file = ResolveSourcePath(project, cls, cls.SourcePath);
            if (file != null)
            {
                // 同上：类名命中也取声明锚点，避免恒跳文件头
                var anchor = FindTypeAnchor(project, cls, file);
                line = anchor?.Line ?? 0;
                chr = anchor?.Char ?? 0;
            }
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
     * repo 源根推断（SLangCore\Lib\<模块>\<sourcePath>，开发布局命中；纯包形态落空返回 null）。
     * 模块名 ≠ 源目录名时（SLangServer 模块 → SLang\Server 目录）候选1 落空，
     * 回落源根 .sl 基名索引（后缀命中优先、最浅路径优先，否则首个命中） */
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
            foreach (var kv in _refJsonRoot)
            {
                var alt = LookupRefSource(kv.Value, sourcePath);
                if (alt != null)
                {
                    candidates.Add(alt);
                }
            }
            candidates.Add(Path.Combine(project.Dir, sourcePath));
        }
        return candidates.FirstOrDefault(File.Exists);
    }

    /* 源根 .sl 基名索引查找：整路径后缀命中优先（含子目录形态，多命中取最浅
     * 路径），否则首个命中。sourcePath 为裸文件名（`Server.sl`）或含目录形态均可。 */
    private string? LookupRefSource(string root, string sourcePath)
    {
        var idx = GetRefSourceIndex(root);
        if (idx == null)
        {
            return null;
        }
        string baseName = Path.GetFileName(sourcePath);
        if (!idx.TryGetValue(baseName, out var hits) || hits.Count == 0)
        {
            return null;
        }
        string suffix = "/" + sourcePath.Replace('\\', '/').TrimEnd('/');
        string? best = null;
        int bestDepth = int.MaxValue;
        foreach (var h in hits)
        {
            if (!("/" + h.Replace('\\', '/')).EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            int depth = h.Split(Path.DirectorySeparatorChar).Length;
            if (depth < bestDepth)
            {
                best = h;
                bestDepth = depth;
            }
        }
        return best ?? hits[0];
    }

    /* 源根 → .sl 文件基名索引（懒建 + 缓存；IO 异常返回 null 不缓存，下次重试） */
    private Dictionary<string, List<string>>? GetRefSourceIndex(string root)
    {
        if (_refSourceIndex.TryGetValue(root, out var cached))
        {
            return cached;
        }
        try
        {
            var idx = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (var f in Directory.EnumerateFiles(root, "*.sl", SearchOption.AllDirectories))
            {
                string bn = Path.GetFileName(f);
                if (!idx.TryGetValue(bn, out var list))
                {
                    list = new List<string>();
                    idx[bn] = list;
                }
                list.Add(f);
            }
            _refSourceIndex[root] = idx;
            return idx;
        }
        catch (Exception)
        {
            return null; // 目录不存在/不可读：不缓存，下次重试
        }
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

        /* 普通字符串（SL："…" / '…'，反斜杠转义）到闭合引号后一位
         * （internal：外围类 ExtractMemberChain 实参段跳字符串复用） */
        internal static int SkipString(string s, int i, char quote)
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
            string p = u.LocalPath;
            /* 盘符冒号被编码的客户端形态（VS Code/Trae 实测 file:///d%3A/…）：
             * .NET LocalPath 产出 "/d:/…" 坏路径（前导斜杠）——Directory/File
             * 全线 Exists 失败 → ResolveProject 永远未命中（2026-10-22 真机
             * didOpen 未命中工程实锤）。去前导分隔符即得可用盘符路径；
             * 未编码形态（file:///d:/…）LocalPath 本就正常，条件不触发。 */
            if (p.Length > 2 && (p[0] == '/' || p[0] == '\\') && p[2] == ':')
            {
                p = p[1..];
            }
            return p;
        }
        string raw = Uri.UnescapeDataString(uri["file://".Length..]);
        if (raw.Length > 2 && (raw[0] == '/' || raw[0] == '\\') && raw[2] == ':')
        {
            raw = raw[1..];
        }
        return raw;
    }

    private static string PathToUri(string path)
    {
        /* 对齐 VS Code 客户端 URI 字符串形态（vscode-uri）：'/' 分隔、':' 编码为
         * %3A、盘符大小写保留——publishDiagnostics/rename changes 需与客户端
         * 文档 URI 精确匹配（file:///d:/… 与 file:///d%3A/… 在客户端是两个
         * 不同文档键，Trae 实测发 %3A 形态）。UNC 走 authority 形态。 */
        string p = path.Replace('\\', '/');
        bool unc = p.StartsWith("//");
        var sb = new StringBuilder(unc ? "file:" : "file://");
        if (!unc && p.Length >= 2 && p[1] == ':')
        {
            p = "/" + p; // 盘符路径补前导 '/'（file:/// + d:/…）
        }
        foreach (var ch in p)
        {
            switch (ch)
            {
                case ':': sb.Append("%3A"); break;
                case '%': sb.Append("%25"); break;
                case '#': sb.Append("%23"); break;
                case '?': sb.Append("%3F"); break;
                case ' ': sb.Append("%20"); break;
                case '"': sb.Append("%22"); break;
                case '<': sb.Append("%3C"); break;
                case '>': sb.Append("%3E"); break;
                default: sb.Append(ch); break;
            }
        }
        return sb.ToString();
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
