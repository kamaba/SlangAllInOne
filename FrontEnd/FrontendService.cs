using SimpleLanguage.ExportLanguage;
using SimpleLanguage.Logging;
using SimpleLanguage.Project;

namespace SlangAllInOne.FrontEnd;

/// <summary>
/// FrontEnd service: in-process SimpleLanguage compile via the Front CLI
/// (CommandExecutor). One process compiles one project per call.
///
/// In-memory mode passes --in-memory: the Export phase builds the SLIR package
/// JSON text in memory (no module.json write). The result is read from
/// ExportLangManager.LastMemoryPackageJson and handed straight to the C VM.
/// </summary>
internal sealed class FrontendService
{
    public sealed class CompileResult
    {
        public bool Success = false;
        /// <summary>In-memory SLIR package JSON (null when the Export phase was skipped).</summary>
        public string? PackageJson = null;
        /// <summary>Directory the package would have been written to;
        /// the C VM resolves reference packages / plugin libs against it.</summary>
        public string? ExportDir = null;
        public int ErrorCount = 0;
    }

    /// <param name="projectPath">Project path (directory or .sp file).</param>
    /// <param name="inMemory">true = keep the exported package JSON in memory.</param>
    /// <param name="optimizeLevel">-1 = compiler default, otherwise 0..3 (-O0..-O3).</param>
    public static CompileResult Compile(string projectPath, bool inMemory, int optimizeLevel = -1)
    {
        var result = new CompileResult();

        var frontArgs = new List<string> { "compile", "-e", "ir", "-p", projectPath };
        if (optimizeLevel >= 0)
            frontArgs.Add("-O" + optimizeLevel);
        if (inMemory)
            frontArgs.Add("--in-memory");
        frontArgs.Add("--no-banner");

        Console.WriteLine("=== Front compile (in-process) ===");
        Console.WriteLine("Front: " + string.Join(' ', frontArgs));

        ExportLangManager.ResetMemoryExport();
        ExportLangManager.MemoryExportMode = false;

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

            if (inMemory)
            {
                if (string.IsNullOrEmpty(ExportLangManager.LastMemoryPackageJson))
                {
                    // Export phase skipped: an upstream phase failed silently
                    Console.WriteLine("Front compile finished but the in-memory package was not produced (Export phase skipped).");
                    return result;
                }
                result.PackageJson = ExportLangManager.LastMemoryPackageJson;
                result.ExportDir = ExportLangManager.LastMemoryExportDir;
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
}
