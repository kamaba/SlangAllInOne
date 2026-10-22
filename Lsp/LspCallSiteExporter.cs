//****************************************************************************
//  File:      LspCallSiteExporter.cs
//  ------------------------------------------------
//  slang lsp-compile 专用：编译完成后扫 IRManager 指令流，导出「方法调用点 →
//  目标方法」精确关联表（callSites）——数据源 = IR 生成期绑定的运行时对象
//  （Call* 指令 opValue = IRMethodCall.irMethod + 指令 debugInfo = 调用点
//  token 完整区间 path/beginLine/beginChar/endChar/name），本质即 MetaCore 层
//  MetaCallNode 解析结果（调用 ↔ 被调绑定）在 IR 层的沉淀。供 LSP definition/
//  hover 光标区间命中即精确跳转，替代文本启发式猜测（2026-10-21 用户方向）。
//
//  字段契约（LspServer.DoDiagnostics 消费）：
//    f  = 调用点文件（token.path，相对工程目录形态，与诊断 file 同源）
//    l  = 调用点行（1-based）；bc/ec = 调用点字符区间（0-based）
//    n  = 调用符号名（token lexeme）
//    tn  = 目标方法 IR id（本地编译 = functionAllName；ref module = IR 体系 id，仅调试参考）
//    tc/tm = 规整查表键（目标类 irName + 目标方法短名，供 LSP MergedTable 回查）
//    tf  = 目标定义文件（bindMetaFunction.token.path；本地编译非空，
//         ref module / 模板实例为空 → LSP 侧按 tc/tm 查 MergedTable）
//    tl  = 目标行（1-based）；tc2 = 目标字符（0-based）
//****************************************************************************
using SimpleLanguage;
using SimpleLanguage.IR;

namespace SlangAllInOne.Lsp;

internal static class LspCallSiteExporter
{
    public static List<object> Export()
    {
        var list = new List<object>();
        var irm = IRManager.instance;
        if (irm == null)
        {
            return list;
        }
        foreach (var irmc in irm.GetIRMetaClassList())
        {
            AppendClass(list, irmc);
        }
        return list;
    }

    private static void AppendClass(List<object> list, IRMetaClass irmc)
    {
        foreach (var m in irmc.staticMethodList)
        {
            AppendMethod(list, m);
        }
        foreach (var m in irmc.nonStaticMethodList)
        {
            AppendMethod(list, m);
        }
        foreach (var m in irmc.operatorMethodList)
        {
            AppendMethod(list, m);
        }
    }

    private static void AppendMethod(List<object> list, IRMethod m)
    {
        foreach (var d in m.IRDataList)
        {
            if (d.opCode != EIROpCode.CallStatic
                && d.opCode != EIROpCode.CallVirt
                && d.opCode != EIROpCode.CallDynamic)
            {
                continue;
            }
            if (d.opValue is not IRMethodCall imc || imc.irMethod == null)
            {
                continue;
            }
            var di = d.debugInfo;
            if (string.IsNullOrEmpty(di.path) || di.beginLine <= 0)
            {
                continue;
            }
            var tf = imc.irMethod.bindMetaFunction?.token;
            list.Add(new
            {
                f = di.path,
                l = di.beginLine,
                bc = di.beginChar,
                ec = di.endChar,
                n = di.name ?? "",
                tn = imc.irMethod.id ?? "",
                // tc/tm = 规整查表键：本地编译 IRMethod.id = functionAllName（类.方法），
                // ref module 还原的是 IR 体系 id（类.方法_参数数_参数类型）不可切分——
                // irOwnerMetaClass.irName + onlyFunctionName 两种来源形态一致
                tc = imc.irMethod.irOwnerMetaClass?.irName ?? "",
                tm = imc.irMethod.onlyFunctionName ?? "",
                tf = tf?.path ?? "",
                tl = tf?.sourceBeginLine ?? 0,
                tc2 = tf?.sourceBeginChar ?? 0,
            });
        }
    }
}
