using System.Runtime.InteropServices;

namespace SlangAllInOne.Backend;

/// <summary>
/// Backend service: locates the C VM binaries (csimple_lang_dll.dll) and runs
/// modules either from memory (compile-to-run) or from a disk module.json.
/// </summary>
internal sealed class CvmBackend
{
    /// <summary>Directory containing csimple_lang_dll.dll (the build bin dir).</summary>
    public string BinDir { get; }
    public string Config { get; }

    private CvmBackend(string binDir, string config)
    {
        BinDir = binDir;
        Config = config;
    }

    /// <summary>Locates the C VM build tree under <paramref name="repoRoot"/>
    /// (csimple_lang/build/{Debug,Release}/bin). Falls back Debug -> Release.</summary>
    public static CvmBackend? Locate(string repoRoot, string config = "Debug")
    {
        var candidates = string.Equals(config, "Release", StringComparison.OrdinalIgnoreCase)
            ? new[] { "Release", "Debug" }
            : new[] { "Debug", "Release" };

        foreach (var cfg in candidates)
        {
            var binDir = Path.GetFullPath(Path.Combine(repoRoot, "csimple_lang", "build", cfg, "bin"));
            var dllPath = Path.Combine(binDir, "csimple_lang_dll.dll");
            if (File.Exists(dllPath))
                return new CvmBackend(binDir, cfg);
        }
        return null;
    }

    /// <summary>Runs a module whose SLIR package JSON lives in memory.
    /// This is the compile-to-run fast path: the Front-built package text goes
    /// straight into the VM loader without writing/reading a module.json.
    /// baseDir is the directory the package would have been written to;
    /// moduleReferences and plugin libs resolve against it.</summary>
    public int RunInMemory(string packageJson, string? baseDir, int flags, IReadOnlyList<string> programArgs)
    {
        if (string.IsNullOrEmpty(packageJson))
            throw new ArgumentException("package JSON text is empty", nameof(packageJson));

        PrepareNativeLoad();

        var jsonPtr = CvmInterop.AllocUtf8(packageJson);
        var baseDirPtr = CvmInterop.AllocUtf8(baseDir);
        var argsPtr = CvmInterop.AllocUtf8Array(programArgs, out var elements);
        try
        {
            return CvmInterop.cli_run_module_in_memory(
                jsonPtr, baseDirPtr, flags, argsPtr, programArgs.Count);
        }
        finally
        {
            CvmInterop.FreeAll(argsPtr, elements, jsonPtr, baseDirPtr);
        }
    }

    /// <summary>Invokes the classic C VM CLI in-process (e.g. "run|info <module.json>").</summary>
    public int RunCli(IReadOnlyList<string> cliArgs)
    {
        if (cliArgs.Count == 0)
            throw new ArgumentException("at least one CLI argument is required", nameof(cliArgs));

        PrepareNativeLoad();

        // argv[0] is the program name, as in a real command line
        var argv = new List<string>(cliArgs.Count + 1) { "csimple_lang" };
        argv.AddRange(cliArgs);

        var ptrs = new IntPtr[argv.Count];
        var arrayPtr = IntPtr.Zero;
        try
        {
            for (int i = 0; i < argv.Count; i++)
                ptrs[i] = CvmInterop.AllocUtf8(argv[i]);
            arrayPtr = Marshal.AllocHGlobal(IntPtr.Size * argv.Count);
            Marshal.Copy(ptrs, 0, arrayPtr, argv.Count);
            return CvmInterop.cli_main(argv.Count, arrayPtr);
        }
        finally
        {
            foreach (var p in ptrs)
            {
                if (p != IntPtr.Zero)
                    Marshal.FreeHGlobal(p);
            }
            if (arrayPtr != IntPtr.Zero)
                Marshal.FreeHGlobal(arrayPtr);
        }
    }

    /// <summary>Adds BinDir to the DLL search path so the "csimple_lang_dll.dll"
    /// DllImport can resolve the freshly built DLL (and its sqlite3.dll dep).</summary>
    private void PrepareNativeLoad()
    {
        if (OperatingSystem.IsWindows())
            CvmInterop.SetDllDirectory(BinDir);
    }
}
