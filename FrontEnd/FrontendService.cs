using SimpleLanguage.ExportLanguage;
using SimpleLanguage.Logging;
using SimpleLanguage.Project;

namespace SlangAllInOne.FrontEnd;

/// <summary>
/// FrontEnd service: in-process SimpleLanguage compile via the Front CLI
/// (CommandExecutor). One process compiles one project per call.
///
/// 导出三态（前后端联合接口，--export-mode output|temp|memory）：
/// - OutputDir/TempDir：磁盘导出（Result.ModuleSlbPath / ModuleJsonPath 为实际落盘产物）；
/// - Memory：不导出。SLB 二进制（不压缩）留在内存（PackageBytes），宿主直传
///   C VM 内存入口；format 为 json 系时另产出 PackageJson 文本（LSP 符号源）。
/// </summary>
internal sealed class FrontendService
{
    public sealed class CompileResult
    {
        public bool Success = false;
        /// <summary>内存 SLB 包字节（--export-mode memory；SLB 二进制、不压缩，
        /// 直传 C VM cli_run_module_in_memory_binary）。磁盘两态为 null。</summary>
        public byte[]? PackageBytes = null;
        /// <summary>内存 SLIR 包 JSON 文本（--export-mode memory 且 format 为 json 系；
        /// LSP 符号源。磁盘两态为 null）。</summary>
        public string? PackageJson = null;
        /// <summary>磁盘导出的 .module.slb 产物路径（--export-mode output/temp；内存态为 null）。</summary>
        public string? ModuleSlbPath = null;
        /// <summary>磁盘导出的 .module.json 调试副本路径（format 为 json 系才有；否则 null）。</summary>
        public string? ModuleJsonPath = null;
        /// <summary>Export 阶段实际解析出的导出目录（三态通用；内存态作 C VM base_dir，
        /// 引用包/插件库按它解析）。</summary>
        public string? ExportDir = null;
        public int ErrorCount = 0;
    }

    /// <param name="projectPath">Project path (directory or .sp file).</param>
    /// <param name="exportMode">导出三态：OutputDir=指定目录（缺省）/ TempDir=_temp 临时目录 /
    /// Memory=不导出（SLB 二进制不压缩留内存）。</param>
    /// <param name="optimizeLevel">-1 = compiler default, otherwise 0..3 (-O0..-O3).</param>
    /// <param name="format">"" = compiler default (jsonc export.format);
    /// "json" | "binary" (SLB) | "binary+json" (SLB main + .module.json debug copy, R15) overrides it.</param>
    public static CompileResult Compile(string projectPath, EExportMode exportMode, int optimizeLevel = -1, string format = "")
    {
        var result = new CompileResult();

        var frontArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath };
        if (optimizeLevel >= 0)
            frontArgs.Add("-O" + optimizeLevel);
        frontArgs.Add("--export-mode");
        frontArgs.Add(ExportModeToCli(exportMode));
        if (!string.IsNullOrEmpty(format))
            frontArgs.AddRange(new[] { "--format", format });
        frontArgs.Add("--no-banner");

        Console.WriteLine("=== Front compile (in-process) ===");
        Console.WriteLine("Front: " + string.Join(' ', frontArgs));

        ExportLangManager.ResetExportState();
        ExportLangManager.ExportMode = exportMode;

        try
        {
            var inputArgs = new CommandInputArgs(frontArgs.ToArray());
            bool ok = CommandExecutor.Execute(inputArgs);
            result.ErrorCount = Log.errorCount;
            if (!ok || Log.errorCount > 0)
            {
                Console.WriteLine($"Front compile failed, error count: {Log.errorCount}");
                return result;
            }

            // Export 阶段实际解析出的导出目录（三态通用：内存态 = "本应写到"的目录，作 base_dir）
            result.ExportDir = ExportLangManager.LastResolvedOutDir;

            if (exportMode == EExportMode.Memory)
            {
                if (ExportLangManager.LastMemoryPackageBytes == null)
                {
                    // Export phase skipped: an upstream phase failed silently
                    Console.WriteLine("Front compile finished but the in-memory package was not produced (Export phase skipped).");
                    return result;
                }
                result.PackageBytes = ExportLangManager.LastMemoryPackageBytes;
                // json 系 format 的内存 JSON 文本（LSP 符号源；非 json 系为 null）
                result.PackageJson = ExportLangManager.LastMemoryPackageJson;
            }
            else
            {
                result.ModuleSlbPath = ExportLangManager.LastExportedSlbPath;
                result.ModuleJsonPath = ExportLangManager.LastExportedJsonPath;
                if (result.ModuleSlbPath == null || !File.Exists(result.ModuleSlbPath))
                {
                    Console.WriteLine("Front compile finished but the exported .module.slb was not produced (Export phase skipped).");
                    return result;
                }
            }
            result.Success = true;
            return result;
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex);
            return result;
        }
    }

    /// <summary>导出三态 → Front CLI 参数值。</summary>
    static string ExportModeToCli(EExportMode mode) => mode switch
    {
        EExportMode.TempDir => "temp",
        EExportMode.Memory => "memory",
        _ => "output",
    };
}
