# attribute 生效时点:
#   PreCompile = 0  编译前: Front Meta 层入口回调, 可跳过代码段
#   Compiling  = 1  编译中: Front IR/SLIR 物化
#   Preload    = 2  运行前: cvm 装载/装配期注册
#   Runtime    = 3  运行中: cvm 执行期触发/查询
enum EAttributeStage extends UInt8
{
    PreCompile = 0
    Compiling = 1
    Preload = 2
    Runtime = 3
}

# attribute 合法注册点（位掩码, 可组合）:
#   Class  = 1   class 声明
#   Data   = 2   模块级 data（全局数据）
#   Enum   = 4   enum 声明
#   Field  = 8   成员变量
#   Method = 16  成员函数
#   All    = 31  全部注册点（1|2|4|8|16; enum 位或暂受 Front 限制, 组合值以字面量预定义）
enum EAttributeTarget extends UInt8
{
    Class = 1
    Data = 2
    Enum = 4
    Field = 8
    Method = 16
    All = 31
}

public class Attribute extends Object
{
    # 生效时点 + 合法注册点（位掩码, 可组合）, 子类在 _init_ 中设置
    protected UInt8 _attributeStage = 0
    protected UInt8 _attributeTargets = 0

    # 宿主信息（由系统注入; Runtime 触发/查询回调中可读）
    protected string _ownerClassName = ""
    protected string _ownerMemberName = ""

    # 执行前回调（返回自身, 支持链式）; 仅 Runtime 触发型子类重写并携带真实逻辑
    public override Attribute _enter_()
    {
        ret this
    }

    # 退出回调; 仅 Runtime 触发型子类重写并携带真实逻辑
    public override void _exit_()
    {
    }

    # ---- Runtime 查询通道（ATTRIBUTE_DESIGN.md P7 / Q6）----
    # 返回宿主上绑定的 stage==Runtime 的 attribute 实例数组（与 _enter_/_exit_
    # 触发通道共享同一份实例缓存; 宿主未命中返回空数组）
    # className 支持全名/短名; 方法级仅匹配声明类自身, 同名方法有指令体者优先

    # 查询类级 attribute（含继承自 Attribute 的全部子类实例）
    public static Array<Attribute> getClassAttributes(string className)
    {
        ret SystemAttributeGetClassAttributes(className) as Array<Attribute>
    }

    # 查询成员变量 attribute（覆盖 static 与 instance 字段）
    public static Array<Attribute> getFieldAttributes(string className, string fieldName)
    {
        ret SystemAttributeGetFieldAttributes(className, fieldName) as Array<Attribute>
    }

    # 查询成员函数 attribute
    public static Array<Attribute> getMethodAttributes(string className, string methodName)
    {
        ret SystemAttributeGetMethodAttributes(className, methodName) as Array<Attribute>
    }

    # ---- 装配期宿主接口（形态 3，attribute _enter_ 内消费）----
    # 宿主名由触发通道注入（_ownerClassName / _ownerMemberName）；
    # 具体 attribute 的装配逻辑写在各自 _enter_ 里，经这三个接口
    # 取宿主素材（方法引用 / 绑定引用 / 新实例），VM 不写 per-attribute 代码

    # 宿主类全名（@Singleton / @OnRoute 类级标记登记键）
    public get string ownerClassName()
    {
        ret this._ownerClassName
    }

    # 宿主成员名（方法级 attribute = 宿主方法名；错误提示 / 登记键用）
    public get string ownerMemberName()
    {
        ret this._ownerMemberName
    }

    # 宿主方法引用（双形态，SERVER_DESIGN.md §4.10：static 方法 → 静态
    # method-ref，不实例化；实例方法 → LATE 实例闭包，每次调用先 new
    # 宿主实例——每请求一实例语义；Core 不依赖 Server，策略由消费侧
    # _enter_ 决定）
    public Function hostMethodRef()
    {
        ret SystemAttributeHostMethodRef( this._ownerClassName, this._ownerMemberName )
    }

    # 宿主方法是否静态（§4.10 双形态判定：类上无 @OnRoute 的直挂路由
    # 必须绑定静态函数——SLang/Server registerPreload 消费）
    public bool hostMethodIsStatic()
    {
        ret SystemAttributeHostMethodIsStatic( this._ownerClassName, this._ownerMemberName )
    }

    # 宿主方法绑定实例引用（bound method-ref：全程以 instance 为 this）
    public Function hostMethodRefOf( object instance )
    {
        ret SystemAttributeHostMethodRefOf( this._ownerClassName, this._ownerMemberName, instance )
    }

    # 构造宿主类新实例（NewObject 同款构造链：字段初始化器 + _init_）
    public object hostClassNew()
    {
        ret SystemAttributeHostClassNew( this._ownerClassName )
    }
}

# 序列化标签: 标注在 class/data 上, 声明该类型支持通用序列化
# 成员序列化规则:
#   public 成员默认参与序列化
#   protected/private 成员默认不参与, 可用 @SerializeField() 强制参与
#   public 成员可用 @NonSerialized() 排除
public class Serializable extends Attribute
{
    _init_()
    {
        this._attributeStage = EAttributeStage.Runtime
        this._attributeTargets = EAttributeTarget.Class
    }
}

# 序列化标签: 强制 protected/private 成员参与序列化
public class SerializeField extends Attribute
{
    _init_()
    {
        this._attributeStage = EAttributeStage.Runtime
        this._attributeTargets = EAttributeTarget.Field
    }
}

# 序列化标签: 排除该 public 成员不参与序列化
public class NonSerialized extends Attribute
{
    _init_()
    {
        this._attributeStage = EAttributeStage.Runtime
        this._attributeTargets = EAttributeTarget.Field
    }
}
