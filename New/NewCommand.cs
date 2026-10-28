using System.Text;

namespace SlangAllInOne.New;

/// <summary>
/// new：脚手架命令（2026-10-18 自 Front CLI 迁入；CLI 三分后 Front 只保留
/// compile/export，`new` 归宿主）。
///   slang new project &lt;Name&gt; [-p &lt;dir&gt;] —— 在 &lt;dir&gt;\&lt;Name&gt;\ 下创建成套工程：
///       Name.sp / Name.jsonc / Name.sl / Name.md（guide，内嵌模板生成；
///       重生成时 AI-DESCRIPTION 标记区内容原样保留）
///   slang new class &lt;Name&gt; [-p &lt;dir&gt;]   —— 在 &lt;dir&gt; 找到的 &lt;.sp 旁创建 &lt;Name&gt;.sl，
///       并登记进 jsonc 的 compileFiles.files[]（已注册则跳过）
/// 落盘一律 UTF-8 BOM（R16）；改写手写 jsonc 时保持原文件 BOM 形态。
/// </summary>
internal static class NewCommand
{
    // ==== 入口：slang new project|class <Name> [-p <dir>] ====

    public static int Run(string[] args)
    {
        string kind = "";
        string name = "";
        string targetDir = Directory.GetCurrentDirectory();

        for (int i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "-p" || a == "--path") && i + 1 < args.Length)
                targetDir = args[++i];
            else if (kind.Length == 0)
                kind = a;
            else if (name.Length == 0)
                name = a;
            else
            {
                Console.WriteLine($"未知参数: {a}");
                PrintUsage();
                return 2;
            }
        }

        if (kind.Equals("project", StringComparison.OrdinalIgnoreCase))
            return IsValidName(name) ? NewProject(name, targetDir) : InvalidName(name);
        if (kind.Equals("class", StringComparison.OrdinalIgnoreCase))
            return IsValidName(name) ? NewClass(name, targetDir) : InvalidName(name);

        PrintUsage();
        return 2;
    }

    static int InvalidName(string name)
    {
        Console.WriteLine($"[FAIL] 无效名称: \"{name}\"（应为 ^[A-Za-z_][A-Za-z0-9_]*$）");
        return 2;
    }

    static bool IsValidName(string name)
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

    // ==== new project：<dir>\<Name>\{Name.sp, Name.jsonc, Name.sl, Name.md} ====

    static int NewProject(string name, string baseDir)
    {
        string dir = Path.Combine(baseDir, name);
        Directory.CreateDirectory(dir);

        string sp = Path.Combine(dir, name + ".sp");
        string jsonc = Path.Combine(dir, name + ".jsonc");
        string source = Path.Combine(dir, name + ".sl");
        string guide = Path.Combine(dir, name + ".md");

        foreach (var existing in new[] { sp, jsonc, source })
        {
            if (File.Exists(existing))
            {
                Console.WriteLine($"[FAIL] 已存在，拒绝覆盖: {existing}");
                return 1;
            }
        }

        WriteAllTextBom(sp, BuildProjectSpText(name));
        WriteAllTextBom(jsonc, BuildProjectJsoncText(name));
        WriteAllTextBom(source, BuildProjectSourceText(name));
        Console.WriteLine($"Created: {sp}");
        Console.WriteLine($"Created: {jsonc}");
        Console.WriteLine($"Created: {source}");

        // Name.md guide：内嵌模板生成；已存在 = 重生成（保留 AI 描述区）
        string? template = LoadGuideTemplate();
        if (template == null)
        {
            Console.WriteLine("[WARN] guide 模板资源缺失，跳过 guide 生成");
        }
        else
        {
            bool regen = File.Exists(guide);
            string? existingGuide = regen ? File.ReadAllText(guide) : null;
            WriteAllTextBom(guide, BuildGuideMarkdown(template, name, existingGuide));
            Console.WriteLine(regen ? $"Regenerated（AI 描述已保留）: {guide}" : $"Created: {guide}");
        }

        Console.WriteLine($"Next: slang compile \"{dir}\"");
        return 0;
    }

    // ==== new class：<Name>.sl + jsonc 登记 ====

    static int NewClass(string name, string targetDir)
    {
        string? spPath = FindCurrentProjectSp(targetDir);
        if (spPath == null)
        {
            Console.WriteLine($"[FAIL] 目录中未找到工程入口（.sp / .jsonc）: {Path.GetFullPath(targetDir)}");
            return 1;
        }

        string dir = Path.GetDirectoryName(spPath)!;
        string classFile = Path.Combine(dir, name + ".sl");
        if (File.Exists(classFile))
        {
            Console.WriteLine($"[FAIL] 已存在，拒绝覆盖: {classFile}");
            return 1;
        }

        string jsoncPath = Path.ChangeExtension(spPath, ".jsonc");
        if (!File.Exists(jsoncPath))
        {
            Console.WriteLine($"[FAIL] 工程配置不存在: {jsoncPath}");
            return 1;
        }

        WriteAllTextBom(classFile, BuildClassSourceText(name));
        Console.WriteLine($"Created: {classFile}");

        string jsoncText = File.ReadAllText(jsoncPath);
        if (jsoncText.Contains("\"" + name + ".sl\"", StringComparison.Ordinal))
        {
            Console.WriteLine($"Skip: {name}.sl 已登记于 {Path.GetFileName(jsoncPath)}");
            return 0;
        }
        if (InsertJsoncFileEntry(jsoncPath, name, jsoncText))
            Console.WriteLine($"Registered: {name}.sl -> compileFiles.files[]（{Path.GetFileName(jsoncPath)}）");
        Console.WriteLine($"Next: slang compile \"{dir}\"");
        return 0;
    }

    // ==== jsonc 登记：定位 compileFiles.files[] 数组并插入条目 ====

    /// <summary>把 <name>.sl 登记进 jsonc 的 compileFiles.files[]。数组缺失 / 括号
    /// 配对破损时返回 false 并打印手工条目（jsonc 不动，工程照常可编译）。</summary>
    static bool InsertJsoncFileEntry(string jsoncPath, string name, string text)
    {
        string entry = BuildFileEntryText(name);

        int filesKey = text.IndexOf("\"files\"", StringComparison.Ordinal);
        int open = filesKey < 0 ? -1 : text.IndexOf('[', filesKey);
        if (open < 0)
        {
            Console.WriteLine("[WARN] jsonc 中未找到 compileFiles.files[] 数组，请手工追加:");
            Console.WriteLine(entry);
            return false;
        }

        var (close, lastSig, trailingComma) = ScanJsonArray(text, open);
        if (close < 0)
        {
            Console.WriteLine("[WARN] compileFiles.files[] 括号配对破损（缺 ']'），请手工追加:");
            Console.WriteLine(entry);
            return false;
        }

        string insert;
        int at;
        if (lastSig < 0)
        {
            // 空数组：[\n<缩进+2><entry>\n<原缩进>]
            string openIndent = LineIndent(text, open);
            insert = "\n" + openIndent + "  " + entry + "\n" + openIndent;
            at = open + 1;
        }
        else
        {
            // 非空：对齐最后一条目所在行缩进；无尾逗号 = 先补逗号
            insert = (trailingComma ? "\n" : ",\n") + LineIndent(text, lastSig) + entry;
            at = lastSig + 1;
        }

        WriteTextPreservingBom(jsoncPath, text.Insert(at, insert));
        return true;
    }

    static string BuildFileEntryText(string name) =>
        "{ \"path\": \"" + name + ".sl\", \"group\": \"core\", \"tag\": \"base\", \"ignore\": false, \"priority\": 0 }";

    // ==== jsonc 扫描器：跳过字符串 / // 行注释 / /* 块注释，[ ] 配对 ====

    /// <summary>自 text[open]（'['）扫描至配对的 ']'。lastSig = 最后一个非空白非逗号
    /// 字符的位置（-1 = 空数组）；trailingComma = lastSig 与 ']' 之间是否已有逗号
    /// （决定插入前是否补逗号）。</summary>
    static (int Close, int LastSig, bool TrailingComma) ScanJsonArray(string text, int open)
    {
        int n = text.Length;
        int lastSig = -1;
        bool commaAfterSig = false;
        int depth = 1;
        int i = open + 1;
        while (i < n)
        {
            char c = text[i];
            if (c == '"')
            {
                int end = SkipJsonString(text, i);
                lastSig = end - 1;
                commaAfterSig = false;
                i = end;
            }
            else if (c == '/' && i + 1 < n && text[i + 1] == '/')
            {
                i = SkipLineComment(text, i);
            }
            else if (c == '/' && i + 1 < n && text[i + 1] == '*')
            {
                i = SkipBlockComment(text, i);
            }
            else if (c == '[')
            {
                depth++;
                lastSig = i;
                commaAfterSig = false;
                i++;
            }
            else if (c == ']')
            {
                depth--;
                if (depth == 0)
                    return (i, lastSig, commaAfterSig);
                lastSig = i;
                commaAfterSig = false;
                i++;
            }
            else if (c == ',')
            {
                commaAfterSig = true;
                i++;
            }
            else
            {
                if (!char.IsWhiteSpace(c))
                {
                    lastSig = i;
                    commaAfterSig = false;
                }
                i++;
            }
        }
        return (-1, lastSig, commaAfterSig);
    }

    /// <summary>text[i]=='"'；返回闭合引号后一位（反斜杠转义跳过）。</summary>
    static int SkipJsonString(string text, int i)
    {
        int n = text.Length;
        i++;
        while (i < n)
        {
            char c = text[i];
            if (c == '\\') { i += 2; continue; }
            if (c == '"') return i + 1;
            i++;
        }
        return n;
    }

    static int SkipLineComment(string text, int i)
    {
        int n = text.Length;
        while (i < n && text[i] != '\n')
            i++;
        return i;
    }

    static int SkipBlockComment(string text, int i)
    {
        int n = text.Length;
        i += 2;
        while (i < n)
        {
            if (text[i] == '*' && i + 1 < n && text[i + 1] == '/')
                return i + 2;
            i++;
        }
        return n;
    }

    /// <summary>取 text[pos] 所在行的缩进（行首空白）。</summary>
    static string LineIndent(string text, int pos)
    {
        int start = pos;
        while (start > 0 && text[start - 1] != '\n')
            start--;
        int end = start;
        while (end < text.Length && (text[end] == ' ' || text[end] == '\t'))
            end++;
        return text.Substring(start, end - start);
    }

    // ==== 工程入口查找（Front CLI 原实现迁入；2026-10-25 .sp 非必需：无 .sp 回落 *.jsonc） ====

    static string? FindCurrentProjectSp(string dir)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
        {
            return null;
        }

        var files = Directory.GetFiles(dir, "*.sp", SearchOption.TopDirectoryOnly)
            .Where(p => !string.Equals(Path.GetFileNameWithoutExtension(p), "Project", StringComparison.OrdinalIgnoreCase)
                        || Directory.GetFiles(dir, "*.sp").Length == 1)
            .ToList();
        if (files.Count == 0)
        {
            // jsonc-only 工程（.sp 非必需）：*.jsonc 兜底；plugin.jsonc 是插件清单需排除
            files = Directory.GetFiles(dir, "*.jsonc", SearchOption.TopDirectoryOnly)
                .Where(p => !string.Equals(Path.GetFileNameWithoutExtension(p), "plugin", StringComparison.OrdinalIgnoreCase)
                            && (!string.Equals(Path.GetFileNameWithoutExtension(p), "Project", StringComparison.OrdinalIgnoreCase)
                                || Directory.GetFiles(dir, "*.jsonc").Length == 1))
                .ToList();
        }
        if (files.Count == 0)
        {
            return null;
        }

        return Path.GetFullPath(files[0]);
    }

    // ==== 脚手架模板（与旧 Front CLI 输出一致） ====

    static string BuildProjectSpText(string name)
    {
        return
$@"Project
{{
    println( txt )
    {{
        SystemPrintln( txt )
    }}
    print( text )
    {{
        SystemPrint( text )
    }}
    _main_()
    {{
        {name}.fun()
    }}
    _before_()
    {{
    }}
    _after_()
    {{
    }}
}}";
    }

    static string BuildProjectSourceText(string name)
    {
        return
$@"{name}
{{
    static fun()
    {{
        global.println( ""Hello from {name}!"" )
    }}
}}";
    }

    static string BuildClassSourceText(string name)
    {
        return
$@"{name}
{{
    _init_()
    {{
    }}
}}";
    }

    /// <summary>工程 jsonc（NullFastTest 风格，2 空格缩进）：references 用裸模块名
    /// "Core"（官方库直查语义：Front/C VM 两侧均按 &lt;exe 目录&gt;\lib\ 直查
    /// Core.module.slb|json）；outputDir 为 "out\export"（相对 jsonc 所在目录，
    /// 产物落 &lt;工程目录&gt;\out\export\&lt;ModuleName&gt;\）。</summary>
    static string BuildProjectJsoncText(string name)
    {
        return
$@"{{
  ""project"":
  {{
    ""name"": ""{name}"",
    ""desc"": ""{name} project"",
    ""mainVersion"": 0,
    ""subVersion"": 0,
    ""buildVersion"": 1,
    ""buildSubVersion"": 0
  }},
  ""source"": {{
    ""root"": "".""
  }},
  ""compile"": {{
    ""optimize"": false,
    ""target"": ""x64"",
    ""debug"": true,
    ""isUseForceSemiColonInLineEnd"": true,
    ""isForceUseClassKey"": false,
    ""isSupportDoublePlus"": false,
    ""requireSameNumericTypes"": false,
    ""isForceSpaceAfterSharp"": false
  }},
  ""compileFiles"": {{
    ""files"": [
      {BuildFileEntryText(name)}
    ]
  }},
  ""compileFilter"": {{
    ""isAllGroup"": true,
    ""isAllTag"": true
  }},
  ""global"": {{
    ""imports"": [
    ],
    ""replace"": {{
    }}
  }},
  ""references"": [
    {{ ""path"": ""Core"" }}
  ],
  ""struct"": [
  ],
  ""export"": {{
    ""moduleName"": ""{name}"",
    ""outputDir"": ""out\\export"",
    ""versionMain"": 0,
    ""versionSub"": 0,
    ""versionPatch"": 1,
    ""includeMetadata"": true,
    ""debugText"": {{
      ""outputDir"": """",
      ""code"": true,
      ""token"": true,
      ""node"": true,
      ""file"": true,
      ""meta"": true,
      ""ir"": true
    }}
  }}
}}";
    }

    // ==== guide：内嵌模板 + AI 描述区保留 ====

    static string? LoadGuideTemplate()
    {
        var asm = typeof(NewCommand).Assembly;
        string? resourceName = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("ProjectGuideTemplate.md", StringComparison.OrdinalIgnoreCase));
        if (resourceName == null)
            return null;
        using var stream = asm.GetManifestResourceStream(resourceName);
        if (stream == null)
            return null;
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        return reader.ReadToEnd();
    }

    /// <summary>模板占位符替换；已有 guide 重写时 AI-DESCRIPTION:BEGIN/END 标记区
    /// 内容原样保留（其余以最新模板为准）。</summary>
    static string BuildGuideMarkdown(string template, string name, string? existingMarkdown)
    {
        string text = template
            .Replace("{{ProjectName}}", name)
            .Replace("{{EntryFile}}", name + ".sp")
            .Replace("{{ConfigFile}}", name + ".jsonc")
            .Replace("{{GlobalDataKeys}}", "")
            .Replace("{{AiDescription}}", "");

        if (!string.IsNullOrEmpty(existingMarkdown))
        {
            const string begin = "<!-- AI-DESCRIPTION:BEGIN -->";
            const string end = "<!-- AI-DESCRIPTION:END -->";
            int b0 = existingMarkdown.IndexOf(begin, StringComparison.Ordinal);
            int e0 = existingMarkdown.IndexOf(end, StringComparison.Ordinal);
            int b1 = text.IndexOf(begin, StringComparison.Ordinal);
            int e1 = text.IndexOf(end, StringComparison.Ordinal);
            if (b0 >= 0 && e0 > b0 && b1 >= 0 && e1 > b1)
            {
                string preserved = existingMarkdown.Substring(b0, e0 + end.Length - b0);
                text = text.Substring(0, b1) + preserved + text.Substring(e1 + end.Length);
            }
        }
        return text;
    }

    // ==== 落盘（R16：新建 UTF-8 BOM；改写既有文件保持原 BOM 形态） ====

    static void WriteAllTextBom(string path, string content) =>
        File.WriteAllText(path, content, new UTF8Encoding(true));

    static void WriteTextPreservingBom(string path, string content)
    {
        bool hasBom = false;
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            int b1 = fs.ReadByte();
            int b2 = fs.ReadByte();
            int b3 = fs.ReadByte();
            hasBom = b1 == 0xEF && b2 == 0xBB && b3 == 0xBF;
        }
        catch (IOException) { /* 读不到 = 按带 BOM 写 */ }
        File.WriteAllText(path, content, new UTF8Encoding(hasBom));
    }

    static void PrintUsage()
    {
        Console.WriteLine(@"用法:
  slang new project <Name> [-p <dir>]   在 <dir>\<Name>\ 下创建成套工程:
                                          Name.sp / Name.jsonc / Name.sl / Name.md（guide）
  slang new class <Name> [-p <dir>]    在 <dir> 找到的 .sp 旁创建 <Name>.sl 并登记进 jsonc

选项:
  -p, --path <dir>   目标目录（缺省: 当前目录）");
    }
}
