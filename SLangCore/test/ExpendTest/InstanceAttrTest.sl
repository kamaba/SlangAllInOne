import Std;
import Core;

# ============================================================================
# InstanceAttrTest.sl — @InstanceAttr（Std）单例实例字段验收（ExpendTest 宿主）
#
# 机制（attribute 形态 3 · runtime 装载，Std/InstanceAttr.sl）：
#   Front 编译期：AttributeManager.SynthesizeInstanceAttrMembers 为标注类合成
#   `static <宿主类> instance`（缺省名）/ `static <宿主类> inst`（自定义名）字段，
#   类型即宿主类自身——ClassA.instance 直接访问（免转型）。
#   cvm 装配期：Preload 触发通道实例化 InstanceAttr 并调 _enter_——
#   hostClassNew 构造单实例 + SystemAttributeSetStaticField 写入该字段。
#
# 验证点：
#   T1 缺省字段名：ClassA.instance 装配期已构造（非 null）
#      + 实例状态可读写（同一实例）
#      + 方法调用正常（实例方法 this 绑定合成实例）
#   T2 自定义字段名：@InstanceAttr("inst") → ClassB.inst
#      + 同一字段反复访问返回同一实例（单例性）
#   T3 与 new 的隔离：new ClassA() 构造独立实例，不干扰合成实例
#   T4 字段访问语义：instance 是普通静态字段（可读可写），非只读
# ============================================================================

# ── 宿主 A：缺省字段名 instance ──
@InstanceAttr
class ClassA
{
    Int32 count = 7

    public Int32 add( Int32 v )
    {
        this.count = this.count + v
        ret this.count
    }
}

# ── 宿主 B：自定义字段名 inst ──
@InstanceAttr( "inst" )
class ClassB
{
    string name = "bee"

    public string greet()
    {
        ret "hi " + this.name
    }
}

InstanceAttrTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[InstanceAttrTest] " + name + " : OK" )
        }
        else
        {
            Console.println( "[InstanceAttrTest] " + name + " : FAIL" )
        }
    }

    static fun()
    {
        # T1 缺省字段名：装配期构造（hostClassNew 字段初始化器链）
        InstanceAttrTest.check( "T1a default field built (ClassA.instance)", ClassA.instance != null )
        InstanceAttrTest.check( "T1b initializer ran (count=7)", ClassA.instance.count == 7 )

        # T1c 实例方法调用（this 绑定合成实例，状态可写）
        Int32 r1 = ClassA.instance.add( 5 )
        InstanceAttrTest.check( "T1c method call mutates state (7+5=12)", r1 == 12 && ClassA.instance.count == 12 )

        # T2 自定义字段名 + 单例性（同一实例反复访问）
        InstanceAttrTest.check( "T2a custom field built (ClassB.inst)", ClassB.inst != null )
        ClassB.inst.name = "wasp"
        InstanceAttrTest.check( "T2b same instance across accesses", ClassB.inst.name == "wasp" )
        InstanceAttrTest.check( "T2c method call on custom field", ClassB.inst.greet() == "hi wasp" )

        # T3 new 独立实例不干扰合成实例
        ClassA fresh = ClassA()
        fresh.count = 99
        InstanceAttrTest.check( "T3 new instance isolated (99 vs 12)", fresh.count == 99 && ClassA.instance.count == 12 )

        # T4 静态字段语义（可整体替换——单例默认但字段可写）
        ClassA saved = ClassA.instance
        ClassA other = ClassA()
        other.count = 55
        ClassA.instance = other
        InstanceAttrTest.check( "T4a static field writable", ClassA.instance.count == 55 )
        ClassA.instance = saved
        InstanceAttrTest.check( "T4b restored", ClassA.instance.count == 12 )

        Console.println( "[InstanceAttrTest] all done" )
    }
}
