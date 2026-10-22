//****************************************************************************
//  File:      LspMetaIndexExporter.cs
//  ------------------------------------------------
//  slang lsp-compile 专用：编译完成后自 MetaCore 层导出「代码关联索引」
//  （code index，2026-10-22 用户方向）——一份 VSCode 可直接消费的数据结构：
//
//   1. files        本轮编译纳入的源文件清单（fileParseList，文件关联）
//   2. ignoredFiles jsonc compileFiles 显式剔除（ignore / group / tag 不匹配）
//                   的文件——编辑器侧整文件灰显（编译期确定性裁剪）
//   3. excluded      @Exclude 等 PreCompile attribute 命中裁剪的类/成员/
//                   local/global 函数的完整源区间——编辑器侧灰显。
//                   区间由源文本扫描定界（声明行首 → 语句/块闭合）；
//                   运行期动态分支不在此列（判不出来的不导出，不灰显）
//   4. symbols      enum/class/data 类型定义 + 成员（方法/字段/枚举成员）
//                   的名字 token 定义位置（比 SLIR instruction debugInfo
//                   更精确的定义锚点），含 static/const 标记与继承关系
//   5. refs         方法/字段/枚举成员/类型名 的引用点 → 目标关联
//                   （遍历 MetaFunction.metaBlockStatements 语句树与
//                   MetaCallLink.visitNodeList 的语义解析结果）。
//                   本地目标携带 tf/tl 直跳坐标；ref module 目标只带
//                   tn/tc/tm 查表键（其源码属编译产物/加密侧，不处理）
//
//   callSites（IR 指令流方法调用关联）保持不变——两者互补：
//   callSites 覆盖含 ref module 在内的全部方法调用；本索引补齐
//   字段/枚举成员/类型名引用，以及定义位置的精化。
//
//  字段契约（LspServer.DoDiagnostics 消费；f/tf 相对工程目录，与
//  diagnostics/callSites 同源；l/el 1-based，c/ec 0-based）：
//    index.files        string[]
//    index.ignoredFiles string[]
//    index.excluded[]   {f,l,c,el,ec,k("class"|"field"|"method"|"func"),n}
//    index.symbols[]    {k("class"|"interface"|"enum"|"data"),n,fn,f,l,c,
//                        ext, m[{k("method"|"field"|"enumMember"),
//                                n,t,st,cn,f,l,c}]}
//    index.refs[]       {k("method"|"field"|"enumMember"|"type"),
//                        f,l,c,ec,n,tn,tc,tm,tf,tl,tc2}
//****************************************************************************
using System.Text;
using SimpleLanguage;
using SimpleLanguage.Compile;
using SimpleLanguage.Core;
using SimpleLanguage.Project;

namespace SlangAllInOne.Lsp;

internal static class LspMetaIndexExporter
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
    // 被裁剪的成员不进 MetaCore（ClassManager.AddClass /
    // ParseFileMetaClassMemeberVarAndFunc / LocalManager / GlobalManager
    // 在创建前即跳过），因此从 FileMeta 语法层枚举并重放同一判定；
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
    // symbols：类型定义 + 成员（定义锚点 = 名字 token，MetaCore 层）
    // =====================================================================
    private static List<object> ExportSymbols()
    {
        var list = new List<object>();
        var cm = ClassManager.instance;
        foreach (var mc in cm.exportMetaClassList)
        {
            if (mc == null || mc.refFromType == RefFromType.RefModule || mc.token == null)
            {
                continue;
            }
            var members = new List<object>();
            var seen = new HashSet<string>();
            foreach (var m in mc.staticMetaMemberFunctionList.Concat(mc.nonStaticVirtualMetaMemberFunctionList)
                         .Concat(mc.interfaceDeclareMetaMemberFunctionList))
            {
                if (m?.token == null || !seen.Add(m.name + "/" + m.metaMemberParamCollection?.metaDefineParamList?.Count))
                {
                    continue;
                }
                members.Add(new
                {
                    k = "method",
                    n = m.name,
                    t = m.returnMetaVariable?.defineMetaType?.name ?? "",
                    st = m.fileMetaMemberFunction?.staticToken != null,
                    cn = false,
                    f = m.token.path,
                    l = m.token.sourceBeginLine,
                    c = m.token.sourceBeginChar,
                });
            }
            foreach (var v in mc.metaMemberVariableDict.Values)
            {
                if (v?.token == null)
                {
                    continue;
                }
                members.Add(new
                {
                    k = "field",
                    n = v.name,
                    t = v.defineMetaType?.name ?? "",
                    st = v.isStatic,
                    cn = v.isConst,
                    f = v.token.path,
                    l = v.token.sourceBeginLine,
                    c = v.token.sourceBeginChar,
                });
            }
            list.Add(new
            {
                k = mc.isInterfaceClass ? "interface" : "class",
                n = mc.name,
                fn = mc.allName,
                f = mc.token.path,
                l = mc.token.sourceBeginLine,
                c = mc.token.sourceBeginChar,
                ext = mc.extendClass?.allName ?? "",
                m = members,
            });
        }
        foreach (var md in cm.exportMetaDataList)
        {
            if (md == null || md.token == null)
            {
                continue;
            }
            var members = new List<object>();
            foreach (var kv in md.metaMemberDataDict)
            {
                var v = kv.Value;
                if (v?.token == null)
                {
                    continue;
                }
                members.Add(new
                {
                    k = "field",
                    n = v.name,
                    t = v.defineMetaType?.name ?? "",
                    st = v.isStatic,
                    cn = v.isConst,
                    f = v.token.path,
                    l = v.token.sourceBeginLine,
                    c = v.token.sourceBeginChar,
                });
            }
            list.Add(new
            {
                k = "data",
                n = md.name,
                fn = md.allName,
                f = md.token.path,
                l = md.token.sourceBeginLine,
                c = md.token.sourceBeginChar,
                ext = "",
                m = members,
            });
        }
        foreach (var me in cm.exportMetaEnumList)
        {
            if (me == null || me.token == null)
            {
                continue;
            }
            var members = new List<object>();
            foreach (var kv in me.metaMemberEnumDict)
            {
                var v = kv.Value;
                if (v?.token == null)
                {
                    continue;
                }
                members.Add(new
                {
                    k = "enumMember",
                    n = v.name,
                    t = "",
                    st = false,
                    cn = v.isConst,
                    f = v.token.path,
                    l = v.token.sourceBeginLine,
                    c = v.token.sourceBeginChar,
                });
            }
            list.Add(new
            {
                k = "enum",
                n = me.name,
                fn = me.allName,
                f = me.token.path,
                l = me.token.sourceBeginLine,
                c = me.token.sourceBeginChar,
                ext = me.extendClass?.allName ?? me.extendMetaData?.allName ?? "",
                m = members,
            });
        }
        return list;
    }

    // =====================================================================
    // refs：引用点 → 目标关联。数据源 = 语句树（metaBlockStatements）与
    // 调用链解析结果（MetaCallLink.visitNodeList）——MetaCore 语义分析的
    // 沉淀；含静态/常量字段初始化表达式。
    // =====================================================================
    private static List<object> ExportRefs()
    {
        var list = new List<object>();
        var dedup = new HashSet<string>();

        void AddRef(string kind, Token? site, string name, MetaBase? target)
        {
            if (site == null || string.IsNullOrEmpty(site.path) || site.sourceBeginLine <= 0 || target == null)
            {
                return;
            }
            if (!dedup.Add(kind + "|" + site.path + "|" + site.sourceBeginLine + "|" + site.sourceBeginChar + "|" + name))
            {
                return;
            }
            bool local = target.refFromType == RefFromType.Local && target.token != null
                && !string.IsNullOrEmpty(target.token.path) && target.token.sourceBeginLine > 0;
            string ownerName = "";
            string memberName = "";
            if (target is MetaFunction mf)
            {
                ownerName = mf.ownerMetaBase?.allName ?? "";
                memberName = mf.name;
            }
            else if (target is MetaVariable mv)
            {
                ownerName = mv.ownerMetaBase?.allName ?? "";
                memberName = mv.name;
            }
            list.Add(new
            {
                k = kind,
                f = site.path,
                l = site.sourceBeginLine,
                c = site.sourceBeginChar,
                ec = site.sourceEndChar,
                n = name,
                tn = target.allName,
                tc = ownerName,
                tm = memberName,
                tf = local ? target.token!.path : "",
                tl = local ? target.token!.sourceBeginLine : 0,
                tc2 = local ? target.token!.sourceBeginChar : 0,
            });
        }

        var walker = new RefWalker(AddRef);

        // 方法体（成员/全局/local/动态闭包全部经 MethodManager 登记簿）
        var mm = MethodManager.instance;
        foreach (var f in mm.metaOriginalFunctionList)
        {
            walker.WalkBlock(f?.metaBlockStatements);
        }
        foreach (var f in mm.metaDynamicFunctionList)
        {
            walker.WalkBlock(f?.metaBlockStatements);
        }
        // 字段/枚举成员初始化表达式（类级，不在任何方法体内）
        var cm = ClassManager.instance;
        foreach (var mc in cm.exportMetaClassList)
        {
            foreach (var v in mc?.metaMemberVariableDict.Values ?? Enumerable.Empty<MetaMemberVariable>())
            {
                walker.WalkExpr(v?.express);
            }
        }
        foreach (var me in cm.exportMetaEnumList)
        {
            foreach (var v in me?.metaMemberEnumDict.Values ?? Enumerable.Empty<MetaMemberEnum>())
            {
                walker.WalkExpr(v?.express);
            }
        }
        return list;
    }

    // =====================================================================
    // 语句/表达式遍历器：从 MetaBlockStatements 语句链与表达式树收集
    // MetaCallLink.visitNodeList 的语义关联（方法调用/成员访问/类型名）。
    // =====================================================================
    private sealed class RefWalker
    {
        private readonly Action<string, Token?, string, MetaBase?> _add;

        public RefWalker(Action<string, Token?, string, MetaBase?> add)
        {
            _add = add;
        }

        public void WalkBlock(MetaBlockStatements? block)
        {
            if (block == null)
            {
                return;
            }
            for (var s = block.nextMetaStatements; s != null; s = s.nextMetaStatements)
            {
                WalkStatement(s);
            }
        }

        private void WalkStatement(MetaStatements? s)
        {
            switch (s)
            {
                case null:
                    return;
                case MetaBlockStatements mb:
                    WalkBlock(mb);
                    return;
                case MetaIfStatements mis:
                    foreach (var ei in mis.metaElseIfStatements)
                    {
                        WalkExpr(ei.finalExpress);
                        WalkBlock(ei.thenMetaStatements);
                    }
                    return;
                case MetaForStatements mfs:
                    WalkStatement(mfs.defineVarStatements);
                    WalkStatement(mfs.assignStatements);
                    WalkExpr(mfs.conditionExpress);
                    WalkStatement(mfs.stepStatements);
                    WalkBlock(mfs.thenMetaStatements);
                    return;
                case MetaWhileDoWhileStatements mws:
                    WalkExpr(mws.conditionExpress);
                    WalkBlock(mws.thenMetaStatements);
                    return;
                case MetaTryStatements mts:
                    WalkBlock(mts.tryBlockStatements);
                    foreach (var cc in mts.catchClauses)
                    {
                        WalkBlock(cc.bodyStatements);
                    }
                    WalkBlock(mts.finallyBlockStatements);
                    return;
                case MetaSwitchStatements mss:
                    WalkCallLink(mss.metaCallLink);
                    WalkExpr(mss.sourceMetaExpress);
                    foreach (var cs in mss.metaCaseStatements)
                    {
                        foreach (var ce in cs.constExpressList)
                        {
                            WalkExpr(ce);
                        }
                        WalkBlock(cs.thenMetaStatements);
                    }
                    WalkBlock(mss.defaultMetaStatements);
                    return;
                case MetaAssignStatements mas:
                    WalkCallLink(mas.leftMetaExpress);
                    WalkExpr(mas.rightMetaExpress);
                    return;
                case MetaCallStatements mcs:
                    WalkCallLink(mcs.metaCallLink);
                    WalkExpr(mcs.expressNode);
                    return;
                case MetaDefineVarStatements mdv:
                    WalkExpr(mdv.expressNode);
                    return;
                case MetaReturnStatements mrs:
                    WalkExpr(mrs.express);
                    return;
                case MetaThrowStatements mts2:
                    WalkExpr(mts2.express);
                    return;
                case MetaClosureDefineStatements mcds:
                    WalkBlock(mcds.closureBlockStatements);
                    return;
                // break/continue/next/goto/AtSignLabel/InlineLambda：无已解析
                // 表达式（内联 lambda 在调用点就地展开，实参由所在链覆盖）
                default:
                    return;
            }
        }

        public void WalkExpr(MetaExpressNodeBase? e)
        {
            switch (e)
            {
                case null:
                    return;
                case MetaCallLinkExpressNode mcl:
                    WalkCallLink(mcl.metaCallLink);
                    return;
                case MetaOpExpressNode mo:
                    WalkExpr(mo.left);
                    WalkExpr(mo.right);
                    WalkExpr(mo.opReceiverExpress);
                    WalkExpr(mo.opParamExpress);
                    return;
                case MetaUnaryOpExpressNode mu:
                    WalkExpr(mu.value);
                    return;
                case MetaThreeItemExpressNode mt:
                    WalkExpr(mt.conditionExpress);
                    WalkExpr(mt.return1Express);
                    WalkExpr(mt.return2Express);
                    return;
                case MetaConstExpressNode mc:
                    foreach (var sp in mc.stringParseExpressList)
                    {
                        WalkExpr(sp);
                    }
                    return;
                case MetaArrayExpressNode ma:
                    foreach (var c in ma.metaCallArray)
                    {
                        WalkExpr(c);
                    }
                    return;
                case MetaNewObjectExpressNode mn:
                    foreach (var ip in mn.metaInputParamList)
                    {
                        WalkExpr(ip);
                    }
                    foreach (var asg in mn.assignStatementsList)
                    {
                        WalkExpr(asg.keyExpressNode);
                        WalkExpr(asg.valueExpressNode);
                    }
                    WalkExpr(mn.arrayLengthExpress);
                    return;
                case MetaAsIsExpressNode mai:
                    WalkCallLink(mai.currentVariableLink);
                    return;
                case MetaCheckedExpressNode mck:
                    WalkExpr(mck.innerExpress);
                    return;
                case MetaTryExpressNode mte:
                    WalkExpr(mte.innerExpress);
                    return;
                case MetaEmptyRetExpressNode mer:
                    WalkExpr(mer.return1Express);
                    WalkExpr(mer.return2Express);
                    return;
                case MetaExecuteStatementsNode mes:
                    WalkStatement(mes.ifStatements);
                    WalkStatement(mes.switchStatements);
                    return;
                // MetaExpressTypeConvert（stub）/ MetaAnonData（语法层保留）：
                // 无已解析子表达式可走
                default:
                    return;
            }
        }

        /* 调用链解析结果 → 引用条目：
         * MethodCall/SystemCall → 方法；Variable/EnumMember → 成员变量/
         * 枚举成员（仅类/enum/data/global 成员；局部变量/参数/迭代变量跳过）；
         * MetaClass/MetaData → 类型名引用（声明位类型名跳转）。 */
        private void WalkCallLink(MetaCallLink? mcl)
        {
            if (mcl == null)
            {
                return;
            }
            foreach (var vn in mcl.visitNodeList)
            {
                var t = vn.visitType;
                if (t == MetaVisitNode.EVisitType.MethodCall || t == MetaVisitNode.EVisitType.SystemCall)
                {
                    var f = vn.methodCall?.function;
                    if (f != null)
                    {
                        _add("method", vn.token, f.name, f);
                    }
                }
                else if (t == MetaVisitNode.EVisitType.Variable || t == MetaVisitNode.EVisitType.EnumMember)
                {
                    var mv = vn.variable;
                    if (mv is MetaMemberEnum mme)
                    {
                        _add("enumMember", vn.token, mme.name, mme);
                    }
                    else if (mv is MetaMemberVariable mmv)
                    {
                        // EnumMember 访问可能是枚举成员对象的包装变量（WrapAsEnumMember
                        // ObjectExpress 产物，variableFrom=EnumMember）——归一到登记原实例
                        if (mmv.variableFrom == MetaVariable.EVariableFrom.EnumMember)
                        {
                            var src = mmv.sourceMetaVariable ?? mmv;
                            _add("enumMember", vn.token, src.name, src);
                        }
                        else if (mmv.variableFrom is MetaVariable.EVariableFrom.ClassMember
                            or MetaVariable.EVariableFrom.Global)
                        {
                            _add("field", vn.token, mmv.name, mmv);
                        }
                    }
                    else if (mv is MetaMemberData mmd)
                    {
                        _add("field", vn.token, mmd.name, mmd);
                    }
                }
                else if (t == MetaVisitNode.EVisitType.MetaClass || t == MetaVisitNode.EVisitType.MetaData)
                {
                    var mb = vn.callMetaType?.metaBase;
                    if (mb != null)
                    {
                        _add("type", vn.token, mb.name, mb);
                    }
                }
            }
        }
    }
}
