#!
本文件测试面向的是已移除的 CSharp CLR 绑定能力（旧 .NET 宿主时期，SL 源码可
import CSharp.System 后直接调用 CLR 符号，如 System.Diagnostics.Debug.Write）。
2026-10-13 起 import 解析严格化为硬错误，CSharp 命名空间在当前编译器中并不存在，
本文件整体保留为历史参考并注释停用；宿主级调试输出现改用 Std 的 Console / SLang.Log。
原测试体如下（预期：三处 Write 均不报错，控制台可见 test / Test2 / Test3）：
!#

#!
import Std
import CSharp.System

Class1
{
}

BindCSharpTest
{
    static fun()
    {
        global.println("========== BindCSharpTest (start) ==========")
        global.println("面向：从 .sl 调用 CSharp.System 下的 Debug 等 CLR 绑定符号。")
        Debug.Write("test")
        CSharp.System.Debug.Write("Test2")
        System.Debug.Write("Test3")
        global.println("========== BindCSharpTest (end) ==========")
    }
}
!#
