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

    /// <summary>Locates the C VM runtime. Two layouts are supported:
    /// 1) packaged: &lt;exe dir&gt;\lib\csimple_lang_dll.dll (self-contained
    ///    publish output, no repo/build tree needed);
    /// 2) dev: <paramref name="repoRoot"/>\csimple_lang\build\{Debug,Release}\bin
    ///    (falls back Debug -&gt; Release / Release -&gt; Debug).</summary>
    public static CvmBackend? Locate(string? repoRoot, string config = "Debug")
    {
        // Packaged layout first: the publish step copies the C VM runtime
        // (csimple_lang_dll.dll + sqlite3.dll) next to the app under lib\.
        var libDir = Path.Combine(AppContext.BaseDirectory, "lib");
        if (File.Exists(Path.Combine(libDir, "csimple_lang_dll.dll")))
            return new CvmBackend(libDir, "package");

        if (repoRoot == null)
            return null;

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

    /// <summary>Binary variant of the compile-to-run fast path (SLB_DESIGN.md P2):
    /// the Front-built SLB byte package goes straight into the VM memory entry
    /// (cli_run_module_in_memory_binary) without writing/reading a .module.slb.
    /// The bytes may also be a NUL-terminated JSON text (magic-dispatched).</summary>
    public int RunInMemoryBinary(byte[] packageBytes, string? baseDir, int flags, IReadOnlyList<string> programArgs)
    {
        if (packageBytes == null || packageBytes.Length == 0)
            throw new ArgumentException("package bytes are empty", nameof(packageBytes));

        PrepareNativeLoad();

        var dataPtr = Marshal.AllocHGlobal(packageBytes.Length);
        var baseDirPtr = CvmInterop.AllocUtf8(baseDir);
        var argsPtr = CvmInterop.AllocUtf8Array(programArgs, out var elements);
        try
        {
            Marshal.Copy(packageBytes, 0, dataPtr, packageBytes.Length);
            return CvmInterop.cli_run_module_in_memory_binary(
                dataPtr, packageBytes.LongLength, baseDirPtr, flags, argsPtr, programArgs.Count);
        }
        finally
        {
            CvmInterop.FreeAll(argsPtr, elements, baseDirPtr, dataPtr);
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
