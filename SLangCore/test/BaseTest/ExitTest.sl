
namespace ExitTestNS
{
    # ── 对照类：无 _exit_，正常释放零输出 ──
    PlainResource
    {
        string name = "plain"
    }

    # ── 基本：定义 _exit_，退出作用域归零自动触发 ──
    SimpleResource
    {
        string name = "simple"
        int id = 0

        override _exit_()
        {
            string n = this.name
            int i = this.id
            global.println("[exit] SimpleResource name=" + n + " id=" + i.toString())
        }
    }

    # ── 继承：基类定义 _exit_，派生类未定义 → 以派生实例为 this 触发基类钩子 ──
    BaseResource
    {
        string owner = "base"

        override _exit_()
        {
            string o = this.owner
            global.println("[exit] BaseResource owner=" + o)
        }
    }

    DerivedResource extends BaseResource
    {
        int extra = 7
    }

    # ── 嵌套：外层持有子对象字段，级联释放触发子 _exit_（外层先、子层后） ──
    InnerResource
    {
        int tag = 0

        override _exit_()
        {
            int t = this.tag
            global.println("[exit] InnerResource tag=" + t.toString())
        }
    }

    OuterResource
    {
        InnerResource holds = null

        override _exit_()
        {
            global.println("[exit] OuterResource")
        }
    }

    ExitTest
    {
        # ── 1. 基本：函数返回 → epilogue ArcRelease 归零 → _exit_ 触发 ──
        static exitBasicTest()
        {
            global.println("========== 1. exit basic ==========")
            SimpleResource r = SimpleResource()
            r.id = 101
            global.println("created r (id=101)")
        }

        # ── 2. 继承：基类 _exit_ 以派生实例为 this ──
        static exitInheritTest()
        {
            global.println("========== 2. exit inherit ==========")
            DerivedResource d = DerivedResource()
            d.owner = "derived"
            global.println("created d (owner=derived)")
        }

        # ── 3. 嵌套：外层释放 → 级联释放子字段 → 子 _exit_ 触发 ──
        static exitNestedTest()
        {
            global.println("========== 3. exit nested ==========")
            OuterResource o = OuterResource()
            InnerResource child = InnerResource()
            child.tag = 300
            o.holds = child
            global.println("created o + child (tag=300)")
        }

        # ── 4. 同函数多个认领局部按声明序在 epilogue 释放 ──
        static exitOrderTest()
        {
            global.println("========== 4. exit order ==========")
            SimpleResource a = SimpleResource()
            a.name = "first"
            a.id = 1
            SimpleResource b = SimpleResource()
            b.name = "second"
            b.id = 2
            global.println("created a,b")
        }

        # ── 5. 对照：无 _exit_ 的类正常释放，无 [exit] 输出 ──
        static exitPlainTest()
        {
            global.println("========== 5. plain (no _exit_) ==========")
            PlainResource p = PlainResource()
            global.println("created p, no [exit] line expected")
        }

        # ── main entry ──
        static fun()
        {
            exitBasicTest()
            exitInheritTest()
            exitNestedTest()
            exitOrderTest()
            exitPlainTest()
            global.println("========== all exit tests done ==========")
        }
    }
}
# 测试面向：ARC 引用计数归零时自动调用类定义的 _exit_ 方法（RAII/deinit 语义）。
# 前提：类无自定义非空 ctor（ARC v1 认领规则 §16-C），new 赋给 LocalStatement 局部，
#       函数 epilogue 发射 ArcRelease；归零后先调 _exit_ 再级联释放 strong 成员。
# 预期：1/2/3/4 场景各出现对应 [exit] 行；场景 3 中 Outer 先于 Inner 输出；场景 5 无 [exit] 行。
