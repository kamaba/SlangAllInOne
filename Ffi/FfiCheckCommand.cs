//****************************************************************************
//  File:      FfiCheckCommand.cs
// ------------------------------------------------
//  slang ffi-check —— FFI 契约（.slffi.json）独立校验子命令（P0-T5，
//  2026-10-27）：
//
//   slang ffi-check <contract.slffi.json> [--dll <lib.dll>]
//
//  校验两级：
//   1. schema 自检：version / functionList[]（entryPoint + returnType +
//      parameterTypeList 必填、类型名合法、entryPoint 去重）+ structs[] /
//      callbacks[]（类型与 sig 合法性、offset/size 完整性）；
//   2. DLL 导出表比对：--dll 显式指定，缺省按契约名推导（X.dll.slffi.json
//      -> X.dll）；用 NativeLibrary（Windows LoadLibrary / POSIX dlopen）
//      逐 entryPoint 取符号验证存在性，缺失即列出。
//
//  全部通过 exit 0；任一失败 exit 1（供 CI / 构建链消费）。
//****************************************************************************
using System.Runtime.InteropServices;

namespace SlangAllInOne.Ffi;

internal static class FfiCheckCommand
{
    /// <summary>契约 schema 校验用类型名合法集（Pascal 名与 FFI 短名均收）。</summary>
    static readonly HashSet<string> KnownTypeNames = new(StringComparer.Ordinal)
    {
        "I8", "U8", "I16", "U16", "I32", "U32", "I64", "U64",
        "Bool", "F32", "F64", "F16", "BF16", "F8E4M3", "F8E5M2",
        "Utf8String", "Ptr", "Void",
        "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64",
        "bool", "f32", "f64", "f16", "bf16", "f8e4m3", "f8e5m2",
        "utf8", "ptr", "void",
    };

    /// <summary>sig（"i32,f32->f64"）合法性分词集（structs[].layoutSig 与 callbacks[].sig 共用）。</summary>
    static readonly HashSet<string> KnownSigTokens = new(StringComparer.Ordinal)
    {
        "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64",
        "bool", "f32", "f64", "f16", "bf16", "f8e4m3", "f8e5m2",
        "utf8", "ptr", "void",
    };

    public static int Run(string[] args)
    {
        string? contractPath = null;
        string? dllOverride = null;
        for (int i = 0; i < args.Length; ++i)
        {
            if (args[i] is "--dll" or "-d")
            {
                if (i + 1 >= args.Length)
                {
                    Console.Error.WriteLine("ffi-check: --dll 后缺少路径实参");
                    return 2;
                }
                dllOverride = args[++i];
            }
            else if (contractPath == null)
            {
                contractPath = args[i];
            }
            else
            {
                Console.Error.WriteLine($"ffi-check: 多余实参 '{args[i]}'");
                return 2;
            }
        }
        if (contractPath == null)
        {
            Console.Error.WriteLine("用法: slang ffi-check <contract.slffi.json> [--dll <lib.dll>]");
            return 2;
        }
        contractPath = Path.GetFullPath(contractPath);
        if (!File.Exists(contractPath))
        {
            Console.Error.WriteLine($"ffi-check: 契约文件不存在: {contractPath}");
            return 2;
        }

        int errors = 0;
        var entryPoints = new List<string>();
        errors += CheckSchema(contractPath, entryPoints);

        // DLL 导出表比对（可推导 / 可显式 / 可跳过）
        string? dllPath = dllOverride;
        if (dllPath == null && contractPath.EndsWith(".dll.slffi.json", StringComparison.OrdinalIgnoreCase))
        {
            dllPath = contractPath[..^".slffi.json".Length];
        }
        if (dllPath == null)
        {
            Console.WriteLine("[skip] 未指定 --dll 且契约名不可推导 dll 路径，跳过导出表比对");
        }
        else
        {
            dllPath = Path.GetFullPath(dllPath);
            if (!File.Exists(dllPath))
            {
                Console.WriteLine($"[FAIL] dll 不存在: {dllPath}");
                ++errors;
            }
            else
            {
                errors += CheckDllExports(dllPath, entryPoints);
            }
        }

        Console.WriteLine(errors == 0
            ? $"ffi-check: OK ({Path.GetFileName(contractPath)})"
            : $"ffi-check: FAILED - {errors} 项不通过 ({Path.GetFileName(contractPath)})");
        return errors == 0 ? 0 : 1;
    }

    /// <summary>schema 自检：functionList / structs / callbacks。</summary>
    static int CheckSchema(string contractPath, List<string> entryPoints)
    {
        int errors = 0;
        using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(contractPath));
        var root = doc.RootElement;
        if (root.ValueKind != System.Text.Json.JsonValueKind.Object)
        {
            Console.WriteLine("[FAIL] root 必须为 JSON object");
            return 1;
        }
        if (!root.TryGetProperty("version", out var ver) || ver.ValueKind != System.Text.Json.JsonValueKind.Number || ver.GetInt32() != 1)
        {
            Console.WriteLine("[FAIL] 缺少 version 字段或版本不为 1");
            ++errors;
        }
        if (!root.TryGetProperty("functionList", out var fns) || fns.ValueKind != System.Text.Json.JsonValueKind.Array)
        {
            Console.WriteLine("[FAIL] 缺少 functionList 数组");
            ++errors;
            return errors;
        }

        int index = 0;
        foreach (var fn in fns.EnumerateArray())
        {
            ++index;
            if (fn.ValueKind != System.Text.Json.JsonValueKind.Object)
            {
                Console.WriteLine($"[FAIL] functionList[{index}] 必须为 object");
                ++errors;
                continue;
            }
            if (!fn.TryGetProperty("entryPoint", out var ep) || ep.ValueKind != System.Text.Json.JsonValueKind.String)
            {
                Console.WriteLine($"[FAIL] functionList[{index}] 缺少 entryPoint 字符串");
                ++errors;
                continue;
            }
            var epName = ep.GetString() ?? string.Empty;
            if (string.IsNullOrWhiteSpace(epName))
            {
                Console.WriteLine($"[FAIL] functionList[{index}] entryPoint 为空");
                ++errors;
                continue;
            }
            if (entryPoints.Contains(epName))
            {
                Console.WriteLine($"[FAIL] entryPoint 重复登记: '{epName}'");
                ++errors;
                continue;
            }
            if (!fn.TryGetProperty("returnType", out var rt) || rt.ValueKind != System.Text.Json.JsonValueKind.String)
            {
                Console.WriteLine($"[FAIL] '{epName}' 缺少 returnType");
                ++errors;
                continue;
            }
            if (!KnownTypeNames.Contains((rt.GetString() ?? string.Empty).Trim()))
            {
                Console.WriteLine($"[FAIL] '{epName}' returnType '{rt.GetString()}' 不是已知类型名");
                ++errors;
            }
            if (!fn.TryGetProperty("parameterTypeList", out var ps) || ps.ValueKind != System.Text.Json.JsonValueKind.Array)
            {
                Console.WriteLine($"[FAIL] '{epName}' 缺少 parameterTypeList 数组");
                ++errors;
                continue;
            }
            foreach (var p in ps.EnumerateArray())
            {
                var t = p.ValueKind == System.Text.Json.JsonValueKind.String ? (p.GetString() ?? string.Empty).Trim() : null;
                if (!KnownTypeNames.Contains(t ?? string.Empty))
                {
                    Console.WriteLine($"[FAIL] '{epName}' 参数类型 '{t}' 不是已知类型名");
                    ++errors;
                }
            }
            entryPoints.Add(epName);
        }

        // structs[]（可选）：name/size/layoutSig/fields[{name,type,offset}]
        if (root.TryGetProperty("structs", out var structs) && structs.ValueKind == System.Text.Json.JsonValueKind.Array)
        {
            foreach (var st in structs.EnumerateArray())
            {
                if (st.ValueKind != System.Text.Json.JsonValueKind.Object ||
                    !st.TryGetProperty("name", out var nm) || nm.ValueKind != System.Text.Json.JsonValueKind.String)
                {
                    Console.WriteLine("[FAIL] structs[] 条目缺少 name");
                    ++errors;
                    continue;
                }
                var name = nm.GetString() ?? string.Empty;
                if (!st.TryGetProperty("size", out var sz) || sz.ValueKind != System.Text.Json.JsonValueKind.Number || sz.GetInt32() <= 0)
                {
                    Console.WriteLine($"[FAIL] struct '{name}' 缺少正整数 size");
                    ++errors;
                }
                if (!st.TryGetProperty("layoutSig", out var ls) || ls.ValueKind != System.Text.Json.JsonValueKind.String)
                {
                    Console.WriteLine($"[FAIL] struct '{name}' 缺少 layoutSig");
                    ++errors;
                }
                else if (!LayoutSigTokensValid(ls.GetString() ?? string.Empty, name))
                {
                    ++errors;
                }
                if (!st.TryGetProperty("fields", out var fs) || fs.ValueKind != System.Text.Json.JsonValueKind.Array)
                {
                    Console.WriteLine($"[FAIL] struct '{name}' 缺少 fields 数组");
                    ++errors;
                    continue;
                }
                foreach (var f in fs.EnumerateArray())
                {
                    if (f.ValueKind != System.Text.Json.JsonValueKind.Object)
                    {
                        Console.WriteLine($"[FAIL] struct '{name}' fields 条目必须为 object");
                        ++errors;
                        continue;
                    }
                    if (!f.TryGetProperty("type", out var ft) || !KnownTypeNames.Contains((ft.GetString() ?? string.Empty).Trim()))
                    {
                        Console.WriteLine($"[FAIL] struct '{name}' 字段类型 '{ft.GetString()}' 不是已知类型名");
                        ++errors;
                    }
                    if (!f.TryGetProperty("offset", out var fo) || fo.ValueKind != System.Text.Json.JsonValueKind.Number || fo.GetInt32() < 0)
                    {
                        Console.WriteLine($"[FAIL] struct '{name}' 字段缺少非负 offset");
                        ++errors;
                    }
                }
            }
        }

        // callbacks[]（可选）：name + sig
        if (root.TryGetProperty("callbacks", out var cbs) && cbs.ValueKind == System.Text.Json.JsonValueKind.Array)
        {
            foreach (var cb in cbs.EnumerateArray())
            {
                if (cb.ValueKind != System.Text.Json.JsonValueKind.Object ||
                    !cb.TryGetProperty("name", out var nm) || nm.ValueKind != System.Text.Json.JsonValueKind.String)
                {
                    Console.WriteLine("[FAIL] callbacks[] 条目缺少 name");
                    ++errors;
                    continue;
                }
                var name = nm.GetString() ?? string.Empty;
                if (!cb.TryGetProperty("sig", out var sg) || !SigTokensValid(sg.GetString() ?? string.Empty, name))
                {
                    Console.WriteLine($"[FAIL] callback '{name}' 缺少 sig 或 sig 含未知类型");
                    ++errors;
                }
            }
        }

        Console.WriteLine($"[schema] functionList {entryPoints.Count} 项，structs/callbacks 校验完成，{errors} 项不通过");
        return errors;
    }

    /// <summary>sig 分词校验（"i32,f32->f64"；packed: 前缀容忍跳过）。</summary>
    static bool SigTokensValid(string sig, string owner)
    {
        var body = sig;
        if (body.StartsWith("packed:", StringComparison.Ordinal))
        {
            body = body["packed:".Length..];
        }
        var arrow = body.IndexOf("->", StringComparison.Ordinal);
        if (arrow < 0)
        {
            Console.WriteLine($"[FAIL] '{owner}' sig '{sig}' 缺少 '->'");
            return false;
        }
        var head = body[..arrow].Trim();
        var ret = body[(arrow + 2)..].Trim();
        if (!KnownSigTokens.Contains(ret))
        {
            Console.WriteLine($"[FAIL] '{owner}' sig 返回类型 '{ret}' 未知");
            return false;
        }
        if (head.Length > 0)
        {
            foreach (var p in head.Split(','))
            {
                if (!KnownSigTokens.Contains(p.Trim()))
                {
                    Console.WriteLine($"[FAIL] '{owner}' sig 参数类型 '{p.Trim()}' 未知");
                    return false;
                }
            }
        }
        return true;
    }

    /// <summary>结构体布局 sig 校验（"i32 width, f64 ratio, utf8 name"：
    /// 逗号分隔的 "类型短名 字段名" 对，可选 packed: 前缀；字段名缺省容忍
    /// （只要类型合法即可，字段名合法性由 Front 侧 define 解析把关））。</summary>
    static bool LayoutSigTokensValid(string layoutSig, string owner)
    {
        var body = layoutSig;
        if (body.StartsWith("packed:", StringComparison.Ordinal))
        {
            body = body["packed:".Length..];
        }
        foreach (var pair in body.Split(','))
        {
            var tok = pair.Trim().Split(' ', '\t');
            var typeName = tok.Length > 0 ? tok[0].Trim() : string.Empty;
            if (!KnownSigTokens.Contains(typeName))
            {
                Console.WriteLine($"[FAIL] struct '{owner}' layoutSig 字段类型 '{typeName}' 未知");
                return false;
            }
        }
        return true;
    }

    /// <summary>DLL 导出表比对：NativeLibrary 装载后逐 entryPoint TryGetExport。</summary>
    static int CheckDllExports(string dllPath, List<string> entryPoints)
    {
        IntPtr handle;
        try
        {
            handle = NativeLibrary.Load(dllPath);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[FAIL] dll 装载失败: {dllPath} ({ex.Message})");
            return 1;
        }
        int errors = 0;
        try
        {
            foreach (var ep in entryPoints)
            {
                if (NativeLibrary.TryGetExport(handle, ep, out _))
                {
                    Console.WriteLine($"[export] ok    {ep}");
                }
                else
                {
                    Console.WriteLine($"[export] MISS  {ep}");
                    ++errors;
                }
            }
        }
        finally
        {
            NativeLibrary.Free(handle);
        }
        return errors;
    }
}
