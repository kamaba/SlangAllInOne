//****************************************************************************
//  File:      LspIRIndexExporter.cs
//  ------------------------------------------------
//  slang lsp-compile 专用：编译完成后自 **IR 生成数据** 导出「代码关联索引」
//  （code index）。2026-10-23 用户定稿：编辑器侧代码关联数据源由 MetaCore
//  语义树整体切换为 IR——像「变量.后边的方法/成员」这类链式访问只有 IR 生成期
//  的解析绑定完整可靠（MetaCore visitNodeList 在模板实例 / ref module /
//  链式返回值等场景存在缺口），故一切索引数据一律读 IR。
//
//  总链路（AGENTS.md R19）：VSCode 保存 → slang lsp（防抖）→ spawn
//  slang lsp-compile → Front 全量编译（Code→Token→Node→File→MetaCore→IR）
//  → 本导出器直接读 IRManager（元数据 + 指令流）→ 一份 VSCode 可消费 JSON
//  → LspServer 装载（跳转/悬停/灰显）。
//
//  IR 读取逻辑与 Front 层 RefModule（ProjectReferenceModuleLoader / IRMetaModule：
//  SLClassPackage → IRMetaClass / IRMethod / IRMetaVariable 自包预构建）同源
//  同法：本地编译类与 ref module 导入类（isRefModulePreBuilt）在 IRManager 里
//  是同一套结构，按 irName / index / id 同一套读法解析目标。
//
//   1. files        本轮编译纳入的源文件清单（fileParseList，文件关联；
//                   语法层来源，与语义无关）
//   2. ignoredFiles jsonc compileFiles 显式剔除（ignore / group / tag 不匹配）
//                   的文件——编辑器侧整文件灰显
//   3. excluded      @Exclude 等 PreCompile attribute 命中裁剪的类/成员/
//                   local/global 函数的完整源区间——灰显。
//                   判定从 FileMeta 语法层重放（裁剪成员不进 IR），
//                   区间由源文本扫描定界；运行期动态分支不在此列
//   4. symbols      类型定义 + 成员锚点（IRMetaClass / IRMethod /
//                   IRMetaVariable，名字 token 定义位置）
//   5. refs         引用点 → 目标关联，**全部出自 IR 指令流**：
//        Call*        → 方法（opValue = IRMethodCall.irMethod）
//        NewMethodRef → 方法引用闭包（同上）
//        Load/StoreStaticField 族
//                     → 静态字段/枚举成员（opValue = 声明类 IRMetaType
//                       + index → staticIRMetaVariableList 反查）
//        Load/StoreNotStaticField 族
//                     → 实例字段（debugMemberOwnerIrClass + index →
//                       localIRMetaVariableList 反查；owner 由 IR 发射点
//                       捕获——IRVariable/IRExpress，2026-10-23 接入）
//        LoadConst*   → const 成员直载（常量内联后无字段指令，靠
//                       debugMemberOwnerIrClass + 站点名反查）
//        Load/StoreGlobal → 全局槽静态成员（globalStaticVariableList 按 id）
//        New* / LoadConstType / CastClass → 类型名引用（opValue = IRMetaType
//                       / classId → IRMetaClass）
//
//  原 callSites 通道（2026-10-21，同为 IR 指令流）已并入 refs（kind=method），
//  lsp-compile 不再单独导出——两个 IR 通道合一，LSP 侧单表装载。
//
//  覆盖取舍（IR 指令流的真实边界，宁缺勿错）：
//    - CallSystemMethod：debugInfo 落在系统方法声明 token（非调用点），
//      站点不可用，不导出（悬停/补全另有 MergedTable 通道）
//    - ref module 方法体不导入（IRDataList 空），天然只导出本地站点；
//      ref module 目标仅带 tc/tm 查表键（源码属编译产物/加密侧，不跳转）
//    - 纯 global{} 变量（非全局槽登记）LoadGlobal 的 hash 无登记表可反查，
//      不导出；.sp Project 静态成员 / jsonc global.data / const 静态成员均经
//      全局槽登记（globalStaticVariableList）正常反查
//
//  字段契约（LspServer.DoDiagnostics/LoadCodeIndex 消费；f/tf 相对工程目录，
//  与 diagnostics 同源；l/el 1-based，c/ec 0-based）：
//    index.files        string[]
//    index.ignoredFiles string[]
//    index.excluded[]   {f,l,c,el,ec,k("class"|"field"|"method"|"func"),n}
//    index.symbols[]    {k("class"|"interface"|"enum"|"data"),n,fn,f,l,c,
//                        ext,m[{k("method"|"field"|"enumMember"),
//                               n,t,st,cn,f,l,c}]}
//    index.refs[]       {k("method"|"field"|"enumMember"|"type"),
//                        f,l,c,ec,n,tn,tc,tm,tf,tl,tc2}
//****************************************************************************
using System.Text;
using SimpleLanguage;
using SimpleLanguage.Compile;
using SimpleLanguage.Core;
using SimpleLanguage.IR;
using SimpleLanguage.Project;

namespace SlangAllInOne.Lsp;

internal static class LspIRIndexExporter
{
    public static object? Export()
    {
        try
        {
            return new
            {
                files = ProjectCompile.fileParseList.Select(fp => fp.filePath).ToList(),
                ignoredFiles = ExportIgnoredFiles(),
                excluded = ExportExcluded(),
                symbols = ExportSymbols(),
                refs = ExportRefs(),
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[lsp-index] 导出异常: " + ex.Message);
            return null;
        }
    }

    // =====================================================================
    // ignoredFiles：jsonc compileFiles.files[] 里未纳入本轮编译的文件
    // （ignore=true 或 group/tag 过滤不匹配——与 PorjectClass.IsCanAddFile
    // 同判据；此面是编译期确定性裁剪，编辑器整文件灰显）
    // =====================================================================
    private static List<string> ExportIgnoredFiles()
    {
        var list = new List<string>();
        var cfg = ProjectManager.config;
        if (cfg?.CompileFiles?.Files == null)
        {
            return list;
        }
        foreach (var f in cfg.CompileFiles.Files)
        {
            if (string.IsNullOrEmpty(f.Path))
            {
                continue;
            }
            if (f.Ignore)
            {
                list.Add(f.Path);
                continue;
            }
            if (!cfg.CompileFilter.IsIncludeInGroup(f.Group) || !cfg.CompileFilter.IsIncludeInTag(f.Tag))
            {
                list.Add(f.Path);
            }
        }
        return list;
    }

    // =====================================================================
    // excluded：@Exclude（PreCompile attribute）裁剪区扫描。
    // 被裁剪的成员不进 IR（ClassManager / LocalManager / GlobalManager 在
    // 创建前即跳过），因此从 FileMeta 语法层枚举并重放同一判定；
    // 区间（el/ec）按源文本扫描定界。
    // =====================================================================
    private static List<object> ExportExcluded()
    {
        var list = new List<object>();
        foreach (var fp in ProjectCompile.fileParseList)
        {
            string? text = TryReadSource(fp.filePath);
            var fm = fp.file;
            if (fm == null)
            {
                continue;
            }
            foreach (var fmc in fm.fileMetaAllClassList)
            {
                if (AttributeManager.ShouldExcludeByPreCompileAttribute(fmc.attributeList))
                {
                    AddExcluded(list, text, fmc.attributeList, fmc.token, "class", fmc.name);
                    continue; // 类整体被裁：成员区间已含于类区间
                }
                foreach (var fmv in fmc.memberVariableList)
                {
                    if (AttributeManager.ShouldExcludeByPreCompileAttribute(fmv.attributeList))
                    {
                        AddExcluded(list, text, fmv.attributeList, fmv.token, "field", fmv.name);
                    }
                }
                foreach (var fmf in fmc.memberFunctionList)
                {
                    if (AttributeManager.ShouldExcludeByPreCompileAttribute(fmf.attributeList))
                    {
                        AddExcluded(list, text, fmf.attributeList, fmf.token, "method", fmf.name);
                    }
                }
            }
            // local{} / global{} 块内函数（LocalManager/GlobalManager 裁剪面）
            var local = fm.GetFileMetaLocalSyntax();
            if (local?.functionList != null)
            {
                foreach (var fmf in local.functionList)
                {
                    if (AttributeManager.ShouldExcludeByPreCompileAttribute(fmf.attributeList))
                    {
                        AddExcluded(list, text, fmf.attributeList, fmf.token, "func", fmf.name);
                    }
                }
            }
            var global = fm.GetFileMetaGlobalSyntax();
            if (global?.functionList != null)
            {
                foreach (var fmf in global.functionList)
                {
                    if (AttributeManager.ShouldExcludeByPreCompileAttribute(fmf.attributeList))
                    {
                        AddExcluded(list, text, fmf.attributeList, fmf.token, "func", fmf.name);
                    }
                }
            }
        }
        return list;
    }

    /* 单条灰区：起点取 attribute 首 token（无则名字 token）所在行首，
     * 终点经源文本扫描（field/method/class 三型定界）。text 不可得时
     * 只输出名字 token 单行（灰显兜底，宁少勿错）。 */
    private static void AddExcluded(List<object> list, string? text, List<FileMetaAttributeSyntax> attrs, Token? nameToken, string kind, string name)
    {
        Token? start = attrs?.Count > 0 ? attrs[0].token : nameToken;
        if (start == null || string.IsNullOrEmpty(start.path) || start.sourceBeginLine <= 0)
        {
            return;
        }
        int l = start.sourceBeginLine;
        int c = 0; // 起点归一到声明行行首
        int el = l;
        int ec = 0;
        if (text != null)
        {
            // 字段的扫描起点用名字 token 行（attribute 独占行时新行终止会在
            // attribute 行后就停，吞不到声明本体；method/func/class 从 attribute
            // 行扫到块体 '{' 不受影响）
            int scanLine = kind == "field" && nameToken != null && nameToken.sourceBeginLine > 0
                ? nameToken.sourceBeginLine : l;
            int end = ScanDeclarationEnd(text, scanLine, 0, kind);
            if (end >= 0)
            {
                (el, ec) = OffsetToPos(text, end);
            }
            else
            {
                // 行文本兜底：扫描失败取名字行行末
                el = l;
                ec = LineEndChar(text, l);
            }
        }
        list.Add(new
        {
            f = start.path,
            l,
            c,
            el,
            ec,
            k = kind,
            n = name,
        });
    }

    /* 源文本扫描：声明区终点 offset（开区间尾）。
     * kind=method/func/class：参数表后第一个 '{' → 括号配对到闭合；
     *   接口式声明（';' 先于 '{'）→ ';' 之后。
     * kind=field：深度 0 的 ';'；若先遇 '}'（类体收尾）→ '}' 所在行行末。
     * 起点 = (line,0) 的 offset。失败返回 -1。 */
    private static int ScanDeclarationEnd(string text, int line, int col, string kind)
    {
        int start = PosToOffset(text, line, col);
        if (start < 0)
        {
            return -1;
        }
        bool isBlock = kind == "method" || kind == "func" || kind == "class";
        int parenDepth = 0;
        int bracketDepth = 0;
        int i = start;
        int n = text.Length;
        while (i < n)
        {
            char ch = text[i];
            // 注释/字符串跳过（SL 词法：# 行注释、#!…!# 块注释、"…" '…' """…"""）
            if (ch == '#' && i + 1 < n && text[i + 1] == '!')
            {
                int end = text.IndexOf("!#", i + 2);
                i = end < 0 ? n : end + 2;
                continue;
            }
            if (ch == '#')
            {
                int nl = text.IndexOf('\n', i);
                i = nl < 0 ? n : nl;
                continue;
            }
            if (ch == '"' && HasAt(text, i, "\"\"\""))
            {
                int end = text.IndexOf("\"\"\"", i + 3);
                i = end < 0 ? n : end + 3;
                continue;
            }
            if (ch == '"' || ch == '\'')
            {
                i = SkipString(text, i, ch);
                continue;
            }
            if (ch == '(')
            {
                parenDepth++;
            }
            else if (ch == ')')
            {
                parenDepth--;
            }
            else if (ch == '[')
            {
                bracketDepth++;
            }
            else if (ch == ']')
            {
                bracketDepth--;
            }
            else if (!isBlock && ch == '\n' && parenDepth <= 0 && bracketDepth <= 0)
            {
                // 字段主终止规则：无分号字段声明在深度 0 的换行处结束（止本行行末，
                // 去尾随空白）。多行 data 初始化器（profile = {…} / history = […])
                // 的换行都在花/方括号深度内（花括号走 MatchBrace 整段跨越），
                // 不会提前终止。
                int end = i;
                while (end > start && (text[end - 1] == '\r' || text[end - 1] == ' ' || text[end - 1] == '\t'))
                {
                    end--;
                }
                return end > start ? end : -1;
            }
            else if (ch == '{')
            {
                // 字段专属边界：行首 '{' 属下一成员的方法体（字段声明无分号直落时），
                // 灰区止于上一行行末——不能吞进下一个成员。初始化器的 '{'
                // （profile = { / T(){…}）行内必有前置内容，走正常括号配对。
                if (!isBlock && IsLineStartBrace(text, i))
                {
                    return PrevLineEnd(text, i, start);
                }
                // 块体起点：括号配对到闭合 '}' 之后
                int close = MatchBrace(text, i);
                return close < 0 ? -1 : close;
            }
            else if (ch == ';' && parenDepth <= 0)
            {
                return i + 1; // 接口式声明 / 字段
            }
            else if (ch == '}' && parenDepth <= 0)
            {
                // 字段无分号直落类体收尾：'}' 属类体，灰区止于上一行行末
                if (!isBlock)
                {
                    return PrevLineEnd(text, i, start);
                }
                return LineEndOffsetBefore(text, i);
            }
            i++;
        }
        return -1;
    }

    private static bool HasAt(string s, int i, string marker)
        => i + marker.Length <= s.Length && s.Substring(i, marker.Length) == marker;

    /* '{' 前本行仅空白 = 行首花括号（下一成员的体 / 类体收尾形态） */
    private static bool IsLineStartBrace(string text, int i)
    {
        int ls = text.LastIndexOf('\n', Math.Max(0, i - 1)) + 1;
        for (int k = ls; k < i; k++)
        {
            if (!char.IsWhiteSpace(text[k]))
            {
                return false;
            }
        }
        return true;
    }

    /* offset 所在行的上一行行末（去 '\r' 与尾随空白；退化到 start 前时返回 -1） */
    private static int PrevLineEnd(string text, int i, int minEnd)
    {
        int ls = text.LastIndexOf('\n', Math.Max(0, i - 1)) + 1;
        int end = ls - 1; // 上一行的 '\n'
        while (end > minEnd && (text[end - 1] == '\r' || text[end - 1] == ' ' || text[end - 1] == '\t'))
        {
            end--;
        }
        return end > minEnd ? end : -1;
    }

    private static int SkipString(string s, int i, char quote)
    {
        i++;
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
        return i;
    }

    /* 从 '{' 配对到闭合 '}' 之后（跳字符串/注释），失败 -1 */
    private static int MatchBrace(string text, int open)
    {
        int depth = 0;
        int i = open;
        int n = text.Length;
        while (i < n)
        {
            char ch = text[i];
            if (ch == '#' && i + 1 < n && text[i + 1] == '!')
            {
                int end = text.IndexOf("!#", i + 2);
                i = end < 0 ? n : end + 2;
                continue;
            }
            if (ch == '#')
            {
                int nl = text.IndexOf('\n', i);
                i = nl < 0 ? n : nl;
                continue;
            }
            if (ch == '"' && HasAt(text, i, "\"\"\""))
            {
                int end = text.IndexOf("\"\"\"", i + 3);
                i = end < 0 ? n : end + 3;
                continue;
            }
            if (ch == '"' || ch == '\'')
            {
                i = SkipString(text, i, ch);
                continue;
            }
            if (ch == '{')
            {
                depth++;
            }
            else if (ch == '}')
            {
                depth--;
                if (depth == 0)
                {
                    return i + 1;
                }
            }
            i++;
        }
        return -1;
    }

    private static int LineEndOffsetBefore(string text, int braceOffset)
    {
        int nl = text.IndexOf('\n', braceOffset);
        // '}' 之前的本行末尾（去尾随空白）
        int end = nl < 0 ? text.Length : nl;
        while (end > braceOffset && char.IsWhiteSpace(text[end - 1]))
        {
            end--;
        }
        return end;
    }

    private static string? TryReadSource(string relPath)
    {
        try
        {
            string full = Path.Combine(ProjectManager.projectPath, relPath);
            return File.Exists(full) ? File.ReadAllText(full) : null;
        }
        catch
        {
            return null;
        }
    }

    /* (line 1-based, char 0-based) → offset；行越界返回 -1 */
    private static int PosToOffset(string text, int line, int col)
    {
        if (line <= 0)
        {
            return -1;
        }
        int cur = 0;
        int l = 1;
        while (l < line)
        {
            int nl = text.IndexOf('\n', cur);
            if (nl < 0)
            {
                return -1;
            }
            cur = nl + 1;
            l++;
        }
        return Math.Min(cur + col, text.Length);
    }

    private static (int Line, int Char) OffsetToPos(string text, int offset)
    {
        int line = 1;
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

    private static int LineEndChar(string text, int line)
    {
        int start = PosToOffset(text, line, 0);
        if (start < 0)
        {
            return 0;
        }
        int nl = text.IndexOf('\n', start);
        int end = nl < 0 ? text.Length : nl;
        while (end > start && (text[end - 1] == '\r' || text[end - 1] == ' ' || text[end - 1] == '\t'))
        {
            end--;
        }
        return end - start;
    }

    // =====================================================================
    // symbols：类型定义 + 成员锚点（IR 层）。
    // 遍历 IRManager.GetIRMetaClassList（= 全部本地导出类的 IR 形态，含
    // 模板实例/动态类）；ref module 导入类（isRefModulePreBuilt）无本地
    // 源锚点，跳过——其符号由 LSP MergedTable（packageJson）覆盖。
    // ref module 的 IR 读取逻辑参考：ProjectReferenceModuleLoader /
    // IRMetaModule（SLClassPackage → IRMetaClass/IRMethod/IRMetaVariable）。
    // =====================================================================
    private static List<object> ExportSymbols()
    {
        var list = new List<object>();
        foreach (var irmc in IRManager.instance.GetIRMetaClassList())
        {
            if (irmc == null || irmc.isRefModulePreBuilt)
            {
                continue;
            }
            MetaBase? owner = irmc.OwnerMetaClass ?? (MetaBase?)irmc.OwnerMetaData ?? irmc.OwnerMetaEnum;
            var token = owner?.token;
            if (token == null || string.IsNullOrEmpty(token.path) || token.sourceBeginLine <= 0)
            {
                continue; // 无本地定义锚点（Core 内建/合成类）
            }
            string kind = irmc.metaClassKind switch
            {
                IRMetaClassKind.Enum => "enum",
                IRMetaClassKind.Data => "data",
                IRMetaClassKind.Interface => "interface",
                _ => "class",
            };
            var members = new List<object>();
            var seen = new HashSet<string>();
            foreach (var m in irmc.staticMethodList.Concat(irmc.nonStaticMethodList).Concat(irmc.operatorMethodList))
            {
                if (m == null)
                {
                    continue;
                }
                var mt = m.bindMetaFunction?.token;
                if (mt == null || string.IsNullOrEmpty(mt.path) || mt.sourceBeginLine <= 0)
                {
                    continue;
                }
                if (!seen.Add("m/" + m.onlyFunctionName))
                {
                    continue; // 重载/模板实例同短名：定义锚点按名合一
                }
                members.Add(new
                {
                    k = "method",
                    n = m.onlyFunctionName,
                    t = m.bindMetaFunction?.returnMetaVariable?.defineMetaType?.name ?? "",
                    st = m.isStatic,
                    cn = false,
                    f = mt.path,
                    l = mt.sourceBeginLine,
                    c = mt.sourceBeginChar,
                });
            }
            if (irmc.metaClassKind == IRMetaClassKind.Enum)
            {
                // 枚举成员：IR 存静态字段（staticIRMetaVariableList），锚点 = debugInfo
                foreach (var v in irmc.staticIRMetaVariableList)
                {
                    var di = v?.debugInfo ?? default;
                    if (v == null || string.IsNullOrEmpty(di.path) || di.beginLine <= 0)
                    {
                        continue;
                    }
                    members.Add(new
                    {
                        k = "enumMember",
                        n = MemberName(v),
                        t = "",
                        st = false,
                        cn = true,
                        f = di.path,
                        l = di.beginLine,
                        c = di.beginChar,
                    });
                }
            }
            else
            {
                foreach (var v in irmc.localIRMetaVariableList)
                {
                    AddFieldMember(members, seen, v, "field");
                }
                foreach (var v in irmc.staticIRMetaVariableList)
                {
                    AddFieldMember(members, seen, v, "field");
                }
            }
            string ext = "";
            if (irmc.OwnerMetaClass != null)
            {
                ext = irmc.OwnerMetaClass.extendClass?.allName ?? "";
            }
            else if (irmc.OwnerMetaEnum != null)
            {
                ext = irmc.OwnerMetaEnum.extendClass?.allName ?? irmc.OwnerMetaEnum.extendMetaData?.allName ?? "";
            }
            list.Add(new
            {
                k = kind,
                n = owner!.name,
                fn = irmc.irName,
                f = token.path,
                l = token.sourceBeginLine,
                c = token.sourceBeginChar,
                ext,
                m = members,
            });
        }
        return list;
    }

    private static void AddFieldMember(List<object> members, HashSet<string> seen, IRMetaVariable? v, string kind)
    {
        var di = v?.debugInfo ?? default;
        if (v == null || string.IsNullOrEmpty(di.path) || di.beginLine <= 0)
        {
            return;
        }
        if (!seen.Add("f/" + v.isStatic + "/" + MemberName(v)))
        {
            return; // data 成员同时登记在实例/静态两表，按名合一
        }
        members.Add(new
        {
            k = kind,
            n = MemberName(v),
            t = v.irMetaType?.irMetaClass?.irName ?? "",
            st = v.isStatic,
            cn = v.isConst,
            f = di.path,
            l = di.beginLine,
            c = di.beginChar,
        });
    }

    /* IRMetaVariable 短名：ref 导入的填 shortName；本地构建的 debugInfo.name
     *（= 成员名 token 词元）兜底；再退 name 尾段。 */
    private static string MemberName(IRMetaVariable v)
    {
        if (!string.IsNullOrEmpty(v.shortName))
        {
            return v.shortName;
        }
        if (!string.IsNullOrEmpty(v.debugInfo.name))
        {
            return v.debugInfo.name;
        }
        int dot = v.name.LastIndexOf('.');
        return dot >= 0 ? v.name[(dot + 1)..] : v.name;
    }

    // =====================================================================
    // refs：引用点 → 目标关联（IR 指令流）。
    // 站点 = 指令 debugInfo（访问点 token 的 path/行/列/词元），目标 =
    // 指令 opValue / debugMemberOwnerIrClass + index 反查 IR 元数据。
    // =====================================================================
    private static List<object> ExportRefs()
    {
        var list = new List<object>();
        var ctx = new RefWalker(list);

        // 方法体指令流：IRMethodDict = 全部方法登记簿（成员/全局/local/
        // 动态闭包；ref module 方法只导入签名、IRDataList 为空）
        var seenMethod = new HashSet<IRMethod>();
        foreach (var irm in IRManager.instance.IRMethodDict.Values)
        {
            if (irm == null || !seenMethod.Add(irm))
            {
                continue;
            }
            ctx.Walk(irm.IRDataList);
        }
        // 字段初始化表达式 IR（类级；含静态 init 收口 IRMetaVariable.irDataList）
        foreach (var irmc in IRManager.instance.GetIRMetaClassList())
        {
            if (irmc == null || irmc.isRefModulePreBuilt)
            {
                continue;
            }
            foreach (var v in irmc.localIRMetaVariableList)
            {
                ctx.Walk(v?.irDataList);
            }
            foreach (var v in irmc.staticIRMetaVariableList)
            {
                ctx.Walk(v?.irDataList);
            }
        }
        return list;
    }

    private sealed class RefWalker
    {
        private readonly List<object> _list;
        private readonly HashSet<string> _dedup = new();
        private readonly HashSet<string> _localFiles = new(StringComparer.OrdinalIgnoreCase);

        public RefWalker(List<object> list)
        {
            _list = list;
            foreach (var fp in ProjectCompile.fileParseList)
            {
                if (!string.IsNullOrEmpty(fp.filePath))
                {
                    _localFiles.Add(Normalize(fp.filePath));
                }
            }
        }

        public void Walk(List<IRData>? irdataList)
        {
            if (irdataList == null)
            {
                return;
            }
            foreach (var d in irdataList)
            {
                Handle(d);
            }
        }

        private void Handle(IRData? d)
        {
            switch (d?.opCode)
            {
                case EIROpCode.CallStatic:
                case EIROpCode.CallVirt:
                case EIROpCode.CallDynamic:
                case EIROpCode.CallClosure:
                case EIROpCode.NewMethodRef:
                    if (d.opValue is IRMethodCall imc && imc.irMethod != null)
                    {
                        AddMethodRef(d.debugInfo, imc.irMethod);
                    }
                    return;
                case EIROpCode.LoadStaticField:
                case EIROpCode.StoreStaticField:
                case EIROpCode.StoreStaticFieldConstValue:
                    AddFieldRef(d, isStatic: true);
                    return;
                case EIROpCode.LoadNotStaticField:
                case EIROpCode.StoreNotStaticField1:
                case EIROpCode.StoreNotStaticField2:
                case EIROpCode.StoreNotStaticField1ConstValue:
                case EIROpCode.StoreNotStaticField2ConstValue:
                    AddFieldRef(d, isStatic: false);
                    return;
                case EIROpCode.LoadGlobal:
                case EIROpCode.StoreGlobal:
                case EIROpCode.StoreGlobalConstValue:
                    AddGlobalRef(d);
                    return;
                case EIROpCode.NewObject:
                    // payload/opValue = Int32 classId → IRMetaClass
                    // （词元须匹配目标类型名：过滤合成 IR 打到声明 token 的噪音，
                    //   如 enum 生成 values 数组的 NewArray（站点=enum 名、目标=Array））
                    if (d.opValue is int classId)
                    {
                        AddTypeRef(d.debugInfo, IRManager.instance.GetIRMetaClassById(classId), nameMatchRequired: true);
                    }
                    return;
                case EIROpCode.NewTemplateObject:
                case EIROpCode.NewArray:
                    AddTypeRef(d.debugInfo, (d.opValue as IRMetaType)?.irMetaClass, nameMatchRequired: true);
                    return;
                case EIROpCode.LoadConstType:
                case EIROpCode.CastClass:
                    AddTypeRef(d.debugInfo, (d.opValue as IRMetaType)?.irMetaClass);
                    return;
                default:
                    // const 成员直载：常量内联后无字段指令，靠发射点写入的
                    // debugMemberOwnerIrClass + 站点词元（= 成员名）按名反查
                    if (d != null && d.debugMemberOwnerIrClass != null && IsLoadConstOp(d.opCode))
                    {
                        AddConstMemberRef(d);
                    }
                    return;
            }
        }

        private static bool IsLoadConstOp(EIROpCode op)
            => op >= EIROpCode.LoadConstNull && op <= EIROpCode.LoadConstType;

        /* 站点有效性：token path 非空 + 属本轮编译文件集（.sl/.sp；过滤
         * 合成站点与 ref module 声明 token 等越界路径） */
        private bool SiteOk(in DebugInfo di)
            => !string.IsNullOrEmpty(di.path) && di.beginLine > 0 && _localFiles.Contains(Normalize(di.path));

        private void AddMethodRef(in DebugInfo di, IRMethod target)
        {
            if (!SiteOk(di))
            {
                return;
            }
            var tf = target.bindMetaFunction?.token;
            string n = string.IsNullOrEmpty(di.name) ? (target.onlyFunctionName ?? "") : di.name;
            Add("method|" + di.path + "|" + di.beginLine + "|" + di.beginChar + "|" + n, new
            {
                k = "method",
                f = di.path,
                l = di.beginLine,
                c = di.beginChar,
                ec = di.endChar,
                n,
                tn = target.id ?? "",
                tc = target.irOwnerMetaClass?.irName ?? "",
                tm = target.onlyFunctionName ?? "",
                tf = tf != null && !string.IsNullOrEmpty(tf.path) && tf.sourceBeginLine > 0 ? tf.path : "",
                tl = tf?.sourceBeginLine ?? 0,
                tc2 = tf?.sourceBeginChar ?? 0,
            });
        }

        /* 字段/枚举成员引用：owner（debugMemberOwnerIrClass，静态访问回落
         * opValue 声明类 IRMetaType）+ index → IRMetaClass 成员表反查。
         * 实例/静态两个 index 空间独立（与 IRMetaModule 导入侧约定一致）。 */
        private void AddFieldRef(IRData d, bool isStatic)
        {
            var di = d.debugInfo;
            if (!SiteOk(di))
            {
                return;
            }
            IRMetaClass? owner = d.debugMemberOwnerIrClass;
            if (isStatic && owner == null)
            {
                owner = (d.opValue as IRMetaType)?.irMetaClass;
            }
            if (owner == null)
            {
                return;
            }
            var vars = isStatic ? owner.staticIRMetaVariableList : owner.localIRMetaVariableList;
            IRMetaVariable? mv = null;
            foreach (var v in vars)
            {
                if (v != null && v.index == d.index)
                {
                    mv = v;
                    break;
                }
            }
            if (mv == null)
            {
                return;
            }
            AddMemberRef(di, owner, mv,
                owner.metaClassKind == IRMetaClassKind.Enum ? "enumMember" : "field");
        }

        /* 全局槽静态成员（const 静态成员 / .sp Project / jsonc global.data）：
         * Load/StoreGlobal index = MetaVariable 哈希 id → globalStaticVariableList
         * 反查（登记见 IRMetaClass.CreateMemberData，GLOBAL_SLOT §5.4）。 */
        private void AddGlobalRef(IRData d)
        {
            var di = d.debugInfo;
            if (!SiteOk(di))
            {
                return;
            }
            IRMetaVariable? mv = null;
            foreach (var v in IRManager.instance.globalStaticVariableList)
            {
                if (v != null && v.id == d.index)
                {
                    mv = v;
                    break;
                }
            }
            if (mv == null)
            {
                return; // 纯 global{} 变量无登记表，不导出（宁缺勿错）
            }
            string ownerIr = d.debugMemberOwnerIrClass?.irName
                ?? mv.irMetaType?.irOwnerMetaClass?.irName ?? "";
            AddMemberRef(di, null, mv, "field", ownerIr);
        }

        private void AddConstMemberRef(IRData d)
        {
            var di = d.debugInfo;
            if (!SiteOk(di) || string.IsNullOrEmpty(di.name))
            {
                return;
            }
            var owner = d.debugMemberOwnerIrClass!;
            // const 成员必为静态（const ⇒ static，IRVariable 常量内联分支在静态路径内）
            foreach (var v in owner.staticIRMetaVariableList)
            {
                if (v != null && MemberName(v) == di.name)
                {
                    AddMemberRef(di, owner, v, "field");
                    return;
                }
            }
        }

        private void AddMemberRef(in DebugInfo di, IRMetaClass? owner, IRMetaVariable mv, string kind, string? ownerIrOverride = null)
        {
            string memberName = MemberName(mv);
            string ownerIr = ownerIrOverride ?? owner?.irName ?? "";
            // 目标定义锚点：仅本地编译目标（ref module 导入成员 debugInfo 为空）
            var mdi = mv.debugInfo;
            bool localDef = !string.IsNullOrEmpty(mdi.path) && mdi.beginLine > 0;
            string n = string.IsNullOrEmpty(di.name) ? memberName : di.name;
            Add(kind + "|" + di.path + "|" + di.beginLine + "|" + di.beginChar + "|" + n, new
            {
                k = kind,
                f = di.path,
                l = di.beginLine,
                c = di.beginChar,
                ec = di.endChar,
                n,
                tn = ownerIr.Length > 0 ? ownerIr + "." + memberName : memberName,
                tc = ownerIr,
                tm = memberName,
                tf = localDef ? mdi.path : "",
                tl = localDef ? mdi.beginLine : 0,
                tc2 = localDef ? mdi.beginChar : 0,
            });
        }

        private void AddTypeRef(in DebugInfo di, IRMetaClass? irmc, bool nameMatchRequired = false)
        {
            if (irmc == null || !SiteOk(di))
            {
                return;
            }
            MetaBase? owner = irmc.OwnerMetaClass ?? (MetaBase?)irmc.OwnerMetaData ?? irmc.OwnerMetaEnum;
            var tok = owner?.token;
            bool localDef = tok != null && !string.IsNullOrEmpty(tok.path) && tok.sourceBeginLine > 0;
            string name = owner?.name ?? irmc.irName;
            if (nameMatchRequired && !string.Equals(di.name, name, StringComparison.Ordinal))
            {
                return; // New* 站点词元 ≠ 目标类型名 → 合成 IR 噪音，丢弃
            }
            string n = string.IsNullOrEmpty(di.name) ? name : di.name;
            Add("type|" + di.path + "|" + di.beginLine + "|" + di.beginChar + "|" + n, new
            {
                k = "type",
                f = di.path,
                l = di.beginLine,
                c = di.beginChar,
                ec = di.endChar,
                n,
                tn = irmc.irName,
                tc = irmc.irName,
                tm = "",
                tf = localDef ? tok!.path : "",
                tl = localDef ? tok!.sourceBeginLine : 0,
                tc2 = localDef ? tok!.sourceBeginChar : 0,
            });
        }

        private void Add(string dedupKey, object entry)
        {
            // 同一站点多条指令（const 直载多指令 / 调用与收尾）按 站点+词元 去重
            if (!_dedup.Add(dedupKey))
            {
                return;
            }
            _list.Add(entry);
        }

        private static string Normalize(string p)
            => (p ?? "").Replace('\\', '/').TrimEnd('/');
    }
}
