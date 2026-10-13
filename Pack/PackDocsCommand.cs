namespace SlangAllInOne.Pack;

/// <summary>
/// pack-docs：把 FrontEnd 侧**用户会用到的** .md 文档拷进发布包 `md\` 目录，
/// 与 pack-modules 一样由 dotnet publish 自动调起（csproj 的 PackDocs
/// target），也可单独手动执行（`--dest &lt;dir&gt;` 默认 = exe 目录）。
///
/// 拷贝清单（用户视角；排除内部文档）：
///   simple_language\md\ 根     入口文档白名单：INDEX / GUIDE / code / CLI /
///                              SL语法与编码规范总表
///   md\syntax\**               语言语法规范（coroutine.md 为协程权威）
///   md\lib\**                  标准库文档（Contraint/Core/Math/Std）
///   md\project\**              工程配置 / FFI / 参数 / 测试指南
///   md\log\**                  日志系统
///   md\plugins\**              插件（@csharp_mono 等 capability 文档）
///   source\Front\Lib\**\*.md   各库源码树内说明 → md\src-lib\（保持相对
///                              结构；排除 cvm_* 前缀目录 —— C 侧工程自带
///                              的第三方 README 非 SL 用户文档）
/// 不拷：md\ai\（AI 会话内部）、md\vm\（C VM 实现内部）。
/// </summary>
internal static class PackDocsCommand
{
    /// <summary>md 根下整目录镜像的用户文档子目录。</summary>
    private static readonly string[] MirrorDirs = { "syntax", "lib", "project", "log", "plugins" };

    /// <summary>md 根下按文件名白名单拷贝的用户入口文档。</summary>
    private static readonly string[] RootFiles =
    {
        "INDEX.md", "GUIDE.md", "code.md", "CLI.md", "SL语法与编码规范总表.md",
    };

    /// <param name="destDir">包根目录；空 = exe 所在目录（publish 集成默认）。</param>
    public static int Run(string? destDir)
    {
        string? repoRoot = Program.GetRepoRoot();
        if (repoRoot == null)
        {
            Console.WriteLine("pack-docs must run inside the repo (FrontEnd docs not found).");
            return 1;
        }

        string destRoot = string.IsNullOrWhiteSpace(destDir)
            ? AppContext.BaseDirectory
            : Path.GetFullPath(destDir);
        string mdRoot = Path.Combine(repoRoot, "simple_language", "md");
        string libRoot = Path.Combine(repoRoot, "simple_language", "source", "Front", "Lib");
        string destMd = Path.Combine(destRoot, "md");

        Console.WriteLine($"=== pack-docs ===");
        Console.WriteLine($"Repo:    {repoRoot}");
        Console.WriteLine($"Package: {destMd}");

        int copied = 0;

        // 1) md 根入口文档白名单
        foreach (var file in RootFiles)
        {
            string src = Path.Combine(mdRoot, file);
            if (File.Exists(src))
            {
                CopyFile(src, Path.Combine(destMd, file));
                copied++;
            }
        }

        // 2) 用户文档子目录整目录镜像（只拷 .md，防将来混入其他文件）
        foreach (var dir in MirrorDirs)
            copied += CopyTree(Path.Combine(mdRoot, dir), Path.Combine(destMd, dir),
                rel => rel.EndsWith(".md", StringComparison.OrdinalIgnoreCase));

        // 3) 源码树各库说明 → md\src-lib\（排除 cvm_* C 侧工程目录）
        copied += CopyTree(libRoot, Path.Combine(destMd, "src-lib"),
            rel => rel.EndsWith(".md", StringComparison.OrdinalIgnoreCase)
                && !rel.Split('\\', '/').Any(s => s.StartsWith("cvm_", StringComparison.OrdinalIgnoreCase)));

        Console.WriteLine($"[OK] pack-docs: {copied} markdown files -> {destMd}");
        return 0;
    }

    /// <summary>递归拷贝一棵源树；predicate(相对路径) 决定哪些文件入选，保持目录结构。</summary>
    static int CopyTree(string srcRoot, string destRoot, Func<string, bool> predicate)
    {
        if (!Directory.Exists(srcRoot))
            return 0;
        int copied = 0;
        foreach (var src in Directory.EnumerateFiles(srcRoot, "*", SearchOption.AllDirectories))
        {
            string rel = Path.GetRelativePath(srcRoot, src);
            if (!predicate(rel))
                continue;
            CopyFile(src, Path.Combine(destRoot, rel));
            copied++;
        }
        return copied;
    }

    static void CopyFile(string src, string dest)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
        File.Copy(src, dest, overwrite: true);
    }
}
