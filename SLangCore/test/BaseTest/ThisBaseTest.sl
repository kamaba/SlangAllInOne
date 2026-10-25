
class Base1
{
    v1 = 1

    int fun1()
    {
        ret 1
    }
}

class Base2 extends Base1
{
    v2 = 2

    override int fun1()
    {
        ret 2
    }

    test1()
    {
    }
}

class Base3 extends Base2
{
    v3 = 1

    override test1()
    {
    }

    override final int fun1()
    {
        base.fun1()
        this.test1()
        ret 3
    }

    int get geta()
    {
        ret 20
    }

    print()
    {
        # this.v2 = 20  # 设计约束：多态下对父类布局字段的写入方式见文档
    }
}

class Base4 extends Base3
{
    test()
    {
        this.fun1()
        this.test1()
        a = this.geta
        global.println("ThisBaseTest Base4.geta -> " + a.toString())
        # this?.x 安全访问链：this 恒非空, 语义等价 this.x (链路字段 isQuestionMarkDot 透传验证)
        b = this?.geta
        global.println("ThisBaseTest Base4.this?.geta -> " + b.toString())
    }
}

# 场景: ret this 链式调用 (receiver 连续叠加)
class ThisChain
{
    int v = 0

    ThisChain add(int n)
    {
        this.v = this.v + n
        ret this
    }

    int getV()
    {
        ret this.v
    }
}

# 场景: this 作方法实参 (隐式第 0 实参显式化传递)
class ThisArg
{
    int id = 0

    _init_(int i)
    {
        this.id = i
    }

    static bool sameId(ThisArg a, ThisArg b)
    {
        ret a.id == b.id
    }

    bool sameAs(ThisArg other)
    {
        ret ThisArg.sameId(this, other)
    }
}

# 场景: 闭包内 this 读写 + 多闭包共享同一 this 槽位 + 嵌套闭包 this 转发
class ThisClosure
{
    int m = 0

    closureCase()
    {
        this.m = 10
        # 两个闭包共享同一 this 捕获槽位 (GetOrAddClosureCapture 复用)
        function int getValue()
        {
            ret this.m
        }
        function setValue(int v)
        {
            this.m = v
        }
        global.println("ThisClosure closure this read = " + getValue().toString())
        setValue(20)
        global.println("ThisClosure closure this write = " + this.m.toString())
    }

    nestedClosureCase()
    {
        this.m = 1
        function int outer()
        {
            # 嵌套闭包(框架限制): 内层闭包不能引用外层捕获变量与 this (CaptureFromHost 显式拦截),
            # 只能使用自身参数; 外层闭包内 this 正常 (捕获自宿主实例方法)
            function int inner(int n)
            {
                ret n + 100
            }
            ret inner(1000) + this.m
        }
        global.println("ThisClosure nested closure = " + outer().toString())
    }
}

ThisBaseTest
{
    static fun()
    {
        global.println("========== ThisBaseTest (start) ==========")
        b4 = Base4()
        b4.test()
        tc = ThisChain()
        global.println("ThisChain chained this.v = " + tc.add(1).add(2).add(3).getV().toString())
        ta1 = ThisArg(7)
        ta2 = ThisArg(7)
        ta3 = ThisArg(8)
        global.println("ThisArg sameAs(7,7) = " + ta1.sameAs(ta2).toString())
        global.println("ThisArg sameAs(7,8) = " + ta1.sameAs(ta3).toString())
        tcl = ThisClosure()
        tcl.closureCase()
        tcl.nestedClosureCase()
        global.println("========== ThisBaseTest (end) ==========")
    }
}

# 测试面向：继承链上的 this、base.fun1()、final 方法、get 访问器；子类中通过 this 调用父类实现与属性式 getter。
#           this?.x 安全访问链、ret this 链式调用、this 作方法实参、闭包内 this 读写/多闭包共享、嵌套闭包(仅参数形态)。
# 预期：Base4.test 调用 final fun1 返回 3 的路径由运行时绑定；geta 打印 20；this?.geta 打印 20；
#       ThisChain 链式叠加 v=6；ThisArg 同 id 为 True、异 id 为 False；
#       闭包内读 10、写后 20；嵌套闭包 outer() = (1000+100)+1 = 1101。
# 已知限制：嵌套闭包的内层闭包不能引用外层捕获变量与 this（框架级限制，MetaClosureBlockStatements.CaptureFromHost 显式拦截）。
