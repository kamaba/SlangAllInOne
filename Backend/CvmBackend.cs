using System.Runtime.InteropServices;
using System.Threading;

namespace SlangAllInOne.Backend;

/// <summary>
/// Backend service: locates the C VM binaries (csimple_lang_dll.dll on Windows /
/// libcsimple_lang_dll.so on Linux) and runs modules either from memory
/// (compile-to-run) or from a disk module.json.
/// </summary>
internal sealed class CvmBackend
{
    public string BinDir { get; }
    public string Config { get; }

    /// <summary>C VM 动态库文件名：Windows 为 csimple_lang_dll.dll；Unix 为
    /// libcsimple_lang_dll.so（CMake SHARED 目标 csimple_lang_dll 的默认命名）。
    /// DllImport 名统一写 "csimple_lang_dll.dll"，Unix 侧经 DllImportResolver
    /// 重定向（见 PrepareNativeLoad）。</summary>
    private static string DllFileName =>
        OperatingSystem.IsWindows() ? "csimple_lang_dll.dll" : "libcsimple_lang_dll.so";

    private CvmBackend(string binDir, string config)
    {
        BinDir = binDir;
        Config = config;
    }

    /// <summary>Locates the C VM runtime. Two layouts are supported:
    /// 1) packaged: &lt;exe dir&gt;\bin\{csimple_lang_dll.dll|libcsimple_lang_dll.so}
    ///    (self-contained publish output, no repo/build tree needed);
    /// 2) dev: <paramref name="repoRoot"/>\csimple_lang\build\{Debug,Release}\bin
    ///    (falls back Debug -&gt; Release / Release -&gt; Debug; Unix dev trees live
    ///    under build\{cfg}Linux\bin — scripts\build-vm-linux.ps1).</summary>
    public static CvmBackend? Locate(string? repoRoot, string config = "Debug")
    {
        // Packaged layout first: the publish/pack step copies the C VM runtime
        // (csimple_lang_dll.dll + sqlite3.dll on Windows; libcsimple_lang_dll.so
        // + libsqlite3.so.0 on Linux) next to the app under bin\.
        var packBinDir = Path.Combine(AppContext.BaseDirectory, "bin");
        if (File.Exists(Path.Combine(packBinDir, DllFileName)))
            return new CvmBackend(packBinDir, "package");

        if (repoRoot == null)
            return null;

        var candidates = string.Equals(config, "Release", StringComparison.OrdinalIgnoreCase)
            ? new[] { "Release", "Debug" }
            : new[] { "Debug", "Release" };

        foreach (var cfg in candidates)
        {
            var binDir = Path.GetFullPath(Path.Combine(repoRoot, "csimple_lang", "build", cfg, "bin"));
            if (File.Exists(Path.Combine(binDir, DllFileName)))
                return new CvmBackend(binDir, cfg);
            if (!OperatingSystem.IsWindows())
            {
                var unixDir = Path.GetFullPath(Path.Combine(repoRoot, "csimple_lang", "build", cfg + "Linux", "bin"));
                if (File.Exists(Path.Combine(unixDir, DllFileName)))
                    return new CvmBackend(unixDir, cfg);
            }
        }
        return null;
    }

    /// <summary>Binary compile-to-run fast path (SLB_DESIGN.md P2): the Front-built
    /// SLB byte package goes straight into the VM memory entry
    /// (cli_run_module_in_memory_binary) without writing/reading a .module.slb.
    /// The Front memory export never compresses (headerFlags bit clear), so the
    /// C VM reads the bytes directly with no inflate step.</summary>
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

    private static int s_ResolverInstalled;
    private static IntPtr s_SoHandle;

    /// <summary>Makes the "csimple_lang_dll.dll" DllImport resolve against BinDir.
    /// Windows: SetDllDirectory adds bin\ to the loader search path (also covers
    /// its sqlite3.dll dep). Unix: the dynamic loader never searches the app
    /// dir, so dlopen the packaged libcsimple_lang_dll.so by absolute path and
    /// install a DllImport resolver returning that handle; the dlopen MUST be
    /// RTLD_GLOBAL so the C VM's dlsym(dlopen(NULL))-based system-method
    /// registry can find its own vm_sys_* exports (RTLD_LOCAL -> every
    /// CallSystemMethod fails with error_code=-13, see CvmInterop). The
    /// bundled libsqlite3.so.0 (a NEEDED dep) is pre-loaded the same way so
    /// the package runs with zero LD_LIBRARY_PATH setup (2026-10-17, Linux 包)。</summary>
    private void PrepareNativeLoad()
    {
        if (OperatingSystem.IsWindows())
        {
            CvmInterop.SetDllDirectory(BinDir);
            return;
        }

        if (Interlocked.Exchange(ref s_ResolverInstalled, 1) == 0)
        {
            string binDir = BinDir;
            string soPath = Path.Combine(binDir, DllFileName);
            s_SoHandle = CvmInterop.dlopen(soPath, CvmInterop.RtldNow | CvmInterop.RtldGlobal);
            if (s_SoHandle == IntPtr.Zero)
                Console.WriteLine("dlopen('" + soPath + "', RTLD_GLOBAL) failed: C VM system-method registry will be empty (-13)");
            NativeLibrary.SetDllImportResolver(typeof(CvmInterop).Assembly, (name, _, _) =>
            {
                if (name == "csimple_lang_dll.dll")
                    return s_SoHandle != IntPtr.Zero ? s_SoHandle : NativeLibrary.Load(soPath);
                return IntPtr.Zero;
            });
        }

        // Pre-load the bundled sqlite (NEEDED dep of the C VM .so) if present:
        // ld.so then resolves that dependency against the already-loaded object.
        var sqlite = Path.Combine(BinDir, "libsqlite3.so.0");
        if (File.Exists(sqlite))
            NativeLibrary.Load(sqlite);
    }
}
