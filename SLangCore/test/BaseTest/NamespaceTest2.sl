# 嵌套 namespace 中类的嵌套类多级访问（源自 未解决问题.txt 的场景）：
# OK2.OK3.Class333.Class444() —— 两层嵌套命名空间 + 外层类 + 嵌套类
# 注意：语言标识符大小写敏感，OK3 不能写成 Ok3
namespace OK2
{
    namespace OK3
    {
        Class333                        # 无 class 关键字的类定义（isForceUseClassKey=false）
        {
            class Class444              # 嵌套类
            {
                int v = 100
            }
        }
    }
}

NamespaceTest2
{
    static fun()
    {
        global.println("========== NamespaceTest2 (start) ==========")

        # 场景1：静态方法内 完整路径构造 嵌套namespace.嵌套namespace.类.嵌套类()
        c = OK2.OK3.Class333.Class444()
        global.println("OK2.OK3.Class333.Class444().v (应等于 100) -> " + c.v.toString())

        # 场景2：嵌套 namespace 路径上的外层类直接构造
        c333 = OK2.OK3.Class333()
        global.println("OK2.OK3.Class333() 构造成功 -> " + (c333 != null).toString())

        # 场景3：链式访问成员 嵌套namespace.类.嵌套类().成员
        global.println("成员链 OK2.OK3.Class333.Class444().v (应等于 100) -> " + OK2.OK3.Class333.Class444().v.toString())

        # 场景4：用户原始场景 —— 普通类方法内无类型声明赋值访问
        u = NamespaceTest2User()
        u.useNestedClass()

        global.println("========== NamespaceTest2 (end) ==========")
    }
}

# 用户原始写法：普通类 fun() 中 v = OK2.OK3.Class333.Class444()
class NamespaceTest2User
{
    useNestedClass()
    {
        v = OK2.OK3.Class333.Class444()
        global.println("user fun v.v (应等于 100) -> " + v.v.toString())
    }
}

# 测试面向：嵌套 namespace（namespace 内嵌 namespace）中定义类，类的嵌套类，
# 以全限定路径 OK2.OK3.Class333.Class444() 构造访问。
# 预期：构造成功，嵌套类成员默认值 v=100 可读；与 Class2Test 的单层 namespace
# 嵌套类场景（N1.Class6.Class6Inner）互补，覆盖多层 namespace 前缀。
