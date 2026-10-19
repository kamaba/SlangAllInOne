//****************************************************************************
//  File:      JsonDom.cs
// ------------------------------------------------
//  LSP 链路共用的 object → JsonNode 转换器（2026-10-19，AOT 形态修复）：
//  LspServer.WriteRaw/Respond/Notify 与 LspCompileCommand 的 payload 全是
//  匿名类型 + Dictionary<string,object?> 组合，此前经 JsonSerializer.Serialize(object)
//  反射序列化——Native AOT 下 STJ 对带参 ctor 小对象（匿名类型）选
//  SmallObjectWithParameterizedConverter`N 泛型 converter，属运行时构造泛型，
//  ILC 无预生成代码 → NotSupportedException（实测 lsp-compile 崩溃 0xC0000409，
//  取证见 slang_vscode_plugin\07_language_server_lsp.md）。本 helper 改用纯反射
//  遍历属性（宿主程序集已 TrimmerRootAssembly 置根保形，匿名属性 getter 元数据在，
//  PropertyInfo.GetValue 无需运行时泛型构造），绕开 STJ converter 工厂；Debug 与
//  AOT 两形态同一路径。
//****************************************************************************
using System.Collections;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SlangAllInOne.Lsp;

internal static class JsonDom
{
    /* 匿名对象/字典/数组/基元/JsonNode/JsonElement → JsonNode（递归）。
     * 注意：新增出口字段类型若超出下列基元清单，须在此登记——落入 default 的
     * 基元会被 GetProperties 反射成空 {}（匿名对象才走 default 反射分支）。 */
    public static JsonNode? ToNode(object? v)
    {
        switch (v)
        {
            case null: return null;
            case JsonNode n: return n;
            case JsonElement e: return JsonNode.Parse(e.GetRawText());
            case string s: return JsonValue.Create(s);
            case bool b: return JsonValue.Create(b);
            case int i: return JsonValue.Create(i);
            case long l: return JsonValue.Create(l);
            case double d: return JsonValue.Create(d);
            case float f: return JsonValue.Create(f);
            case uint u: return JsonValue.Create(u);
            case decimal m: return JsonValue.Create(m);
            case IDictionary d: // 任意泛型形状的字典（Dictionary<string,object?>、
            // Dictionary<string,List<object>>…）都实现非泛型 IDictionary——rename
            // 响应的 changes 即 Dictionary<string, List<object>>，此前仅匹配
            // Dictionary<string,object?> 会漏入 IEnumerable 分支变成 KeyValuePair
            // 数组（2026-10-19 Debug 冒烟 rename 2 断言回归实锤）
            {
                var o = new JsonObject();
                foreach (var key in d.Keys)
                {
                    o[key.ToString() ?? ""] = ToNode(d[key]);
                }
                return o;
            }
            case IEnumerable seq: // 数组/List（string/Dictionary 已在上方命中）
            {
                var a = new JsonArray();
                foreach (var item in seq)
                {
                    a.Add(ToNode(item));
                }
                return a;
            }
            default: // 匿名对象：纯反射遍历属性（置根保形，AOT 可用）
            {
                var o = new JsonObject();
                foreach (var p in v.GetType().GetProperties())
                {
                    o[p.Name] = ToNode(p.GetValue(v));
                }
                return o;
            }
        }
    }
}
