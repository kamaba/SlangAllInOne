// SlCSharpCodeUtil.cs —— SpecialTest 工程外部 C# 源示例（CsharpCode\ 目录）：
// 由工程 jsonc plugins.csharp_mono.sources 引入（Front 读文件内容随 Build
// 请求下发），与全部 @csharp_mono(){} 块体条目同批合并编译进 SLAtSign.dll
// ——块内头区 using SlCsCode; 即可调用（无需手工放进插件 lib 目录）。
// 约束：类名/命名空间勿与镜像 class（SLAtSign 命名空间）撞名——同库合并
// 编译，冲突由 csc 报错拒收整批；C#5 兼容（vendored csc 无 C#6+ 语法）。
namespace SlCsCode
{
    // 静态工具类：块内直接调用静态方法
    public static class SlCSharpCodeUtil
    {
        public static int Add( int a, int b )
        {
            return a + b;
        }

        // string 拼接回传（string 出通道用例）
        public static string Banner( string name )
        {
            return "[" + name + "]";
        }
    }
}
