# @InstanceAttr — 类级单例实例标记（通用机制，服务器路由单例同源于此）。
#
# 机制（attribute 四形态之「形态 3 · runtime 装载」）：类装配完成后
# （静态字段就绪、入口调度前）由 VM 的 Preload SL 触发通道实例化本
# attribute（args → _init_ 重载按参数个数匹配）并注入宿主名后调用
# _enter_——构造宿主类单实例（hostClassNew）并写入编译期合成的
# 静态字段。全部装配逻辑写在 _enter_ 里，VM 不写 per-attribute 代码。
#
# 合成静态字段由 Front 编译期生成（AttributeManager.SynthesizeInstanceAttrMembers）：
#   @InstanceAttr                    → static ClassA instance   （缺省名 instance）
#   @InstanceAttr( "inst" )          → static ClassA inst        （自定义名）
# 装配期 _enter_ 构造单实例写入该字段，源代码经 ClassA.instance /
# ClassA.inst 直接访问（类型即宿主类自身，成员调用免转型）。
#
# 用法：
#   @InstanceAttr
#   class ClassA
#   {
#       public void hello() { ... }
#   }
#   ClassA.instance.hello()          # 单实例，进程级共享
#
#   @InstanceAttr( "inst" )
#   class ClassB { ... }
#   ClassB.inst.hello()
#
# 单实例由 VM 对象池持有（hostClassNew 构造链），装配期一次构造、
# 全程复用；SLang 事件循环单线程派发，无并发竞争。控制器场景：
# 该类方法路由绑定此实例（bind-once，跨请求状态共享，替代旧
# @Singleton 语义——SLang/Server/RouteAttrs.sl 退役实录）。
public class InstanceAttr extends Attribute
{
    # 单例实例的静态字段名（缺省 "instance"）
    private string _instanceName = "instance"

    # 无参构造: @InstanceAttr / @InstanceAttr() 使用缺省字段名 instance
    override _init_()
    {
        this._instanceName = "instance"
        this._attributeStage = EAttributeStage.Preload
        this._attributeTargets = EAttributeTarget.Class
    }

    # 带名构造: @InstanceAttr( "inst" ) → ClassB.inst
    _init_( string instanceName )
    {
        this._instanceName = instanceName
        this._attributeStage = EAttributeStage.Preload
        this._attributeTargets = EAttributeTarget.Class
    }

    public get string instanceName()
    {
        ret this._instanceName
    }

    # 装配期触发：构造宿主类单实例并写入合成静态字段
    #（SystemAttributeSetStaticField 为 VM 通用通道，按类名+字段名定位）
    public override Attribute _enter_()
    {
        object inst = this.hostClassNew()
        if inst != null
        {
            SystemAttributeSetStaticField( this.ownerClassName(), this._instanceName, inst )
        }
        ret this
    }
}
