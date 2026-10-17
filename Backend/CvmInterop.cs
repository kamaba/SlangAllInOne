using System.Runtime.InteropServices;
using System.Text;

namespace SlangAllInOne.Backend;

/// <summary>
/// P/Invoke bindings into the C VM (csimple_lang_dll.dll).
///
/// The DLL exports two host entry points (see csimple_lang/src/cli/cli.h):
///   - cli_main                  classic argv-based CLI ("run|info <module.json>")
///   - cli_run_module_in_memory  compile-to-run from an in-memory SLIR package
///                                JSON text; no module.json write/read round trip.
///
/// All string marshalling is manual UTF-8 into unmanaged memory because the
/// C side expects `const char*` (default CharSet would marshal as ANSI).
/// </summary>
internal static class CvmInterop
{
    // SLVM_MEM_FLAG_* (must match csimple_lang/src/cli/cli.h)
    public const int FlagNoBanner = 0x01;
    public const int FlagQuiet = 0x02;
    public const int FlagDebug = 0x04;
    public const int FlagForceRun = 0x08;
    public const int FlagStrictPlugins = 0x10;
    public const int FlagTest = 0x20;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern bool SetDllDirectory(string? lpPathName);

    // ---- Unix: manual dlopen with RTLD_GLOBAL (2026-10-17, linux 包 -13 修复) ----
    // The C VM registers its ~614 vm_sys_* system methods through
    // dlsym(dlopen(NULL), symbol) - i.e. it looks itself up in the GLOBAL
    // dynamic symbol namespace. .NET's NativeLibrary.Load dlopens with
    // RTLD_LOCAL, so the symbols never become globally visible and every
    // CallSystemMethod dies with error_code=-13 ("not registered").
    // dlopen(path, RTLD_NOW|RTLD_GLOBAL) up front makes the .so's exported
    // symbols resolvable from the main-program handle - the moral equivalent
    // of the -rdynamic link the standalone csimple_lang exe uses.
    internal const int RtldNow = 0x2;      // glibc RTLD_NOW
    internal const int RtldGlobal = 0x100; // glibc RTLD_GLOBAL

    [DllImport("libdl.so.2", SetLastError = true)]
    internal static extern IntPtr dlopen(string? filename, int flags);

    [DllImport("csimple_lang_dll.dll", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int cli_main(int argc, IntPtr argv);

    [DllImport("csimple_lang_dll.dll", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int cli_run_module_in_memory(
        IntPtr jsonText, IntPtr baseDir, int flags, IntPtr programArgs, int programArgCount);

    [DllImport("csimple_lang_dll.dll", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int cli_run_module_in_memory_binary(
        IntPtr data, long dataSize, IntPtr baseDir, int flags, IntPtr programArgs, int programArgCount);

    /// <summary>Allocates a NUL-terminated UTF-8 copy of text (or returns IntPtr.Zero
    /// for null). Caller must free with Marshal.FreeHGlobal.</summary>
    internal static IntPtr AllocUtf8(string? text)
    {
        if (text == null)
            return IntPtr.Zero;
        var bytes = Encoding.UTF8.GetBytes(text + "\0");
        var ptr = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, ptr, bytes.Length);
        return ptr;
    }

    /// <summary>Allocates a native (const char**) array of UTF-8 copies of args.
    /// Returns the array pointer; element pointers are returned for cleanup.
    /// An empty list yields IntPtr.Zero (C side treats count 0 as no args).</summary>
    internal static IntPtr AllocUtf8Array(IReadOnlyList<string> args, out IntPtr[] elements)
    {
        elements = Array.Empty<IntPtr>();
        if (args.Count == 0)
            return IntPtr.Zero;

        elements = new IntPtr[args.Count];
        for (int i = 0; i < args.Count; i++)
            elements[i] = AllocUtf8(args[i]);

        var arrayPtr = Marshal.AllocHGlobal(IntPtr.Size * args.Count);
        Marshal.Copy(elements, 0, arrayPtr, args.Count);
        return arrayPtr;
    }

    internal static void FreeAll(IntPtr arrayPtr, IntPtr[] elements, params IntPtr[] singles)
    {
        foreach (var p in elements)
        {
            if (p != IntPtr.Zero)
                Marshal.FreeHGlobal(p);
        }
        if (arrayPtr != IntPtr.Zero)
            Marshal.FreeHGlobal(arrayPtr);
        foreach (var p in singles)
        {
            if (p != IntPtr.Zero)
                Marshal.FreeHGlobal(p);
        }
    }
}
