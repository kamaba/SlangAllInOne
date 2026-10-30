# Attribute.sl

> 源文件：`Attribute.sl`

## class `Attribute`

- **说明**：SLang 标准库类型 Attribute（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `protected UInt8 _attributeStage = 0` | 生效时点 + 合法注册点（位掩码, 可组合）, 子类在 _init_ 中设置 |
| 字段 | `protected UInt8 _attributeTargets = 0` | 字段 UInt8（类型见签名）。 |
| 字段 | `protected string _ownerClassName = ""` | 宿主信息（由系统注入; Runtime 触发/查询回调中可读） |
| 字段 | `protected string _ownerMemberName = ""` | 字段 string（类型见签名）。 |
| 方法 | `Attribute _enter_()` | 执行前回调（返回自身, 支持链式）; 仅 Runtime 触发型子类重写并携带真实逻辑 |
| 方法 | `void _exit_()` | 退出回调; 仅 Runtime 触发型子类重写并携带真实逻辑 |
| 方法 | `Array&lt;Attribute&gt; getClassAttributes(string className)` | ---- Runtime 查询通道（ATTRIBUTE_DESIGN.md P7 / Q6）---- 返回宿主上绑定的 stage==Runtime 的 attribute 实例数组（与 _enter_/_exit_ 触发通道共享同一份实例缓存; 宿主未命中返回空数组） className 支持全名/短名; 方法级仅匹配声明类自身, 同名方法有指令体者优先 查询类级 attribute（含继承自 Attribute 的全部子类实例） |
| 方法 | `Array&lt;Attribute&gt; getFieldAttributes(string className, string fieldName)` | 查询成员变量 attribute（覆盖 static 与 instance 字段） |
| 方法 | `Array&lt;Attribute&gt; getMethodAttributes(string className, string methodName)` | 查询成员函数 attribute |
| 属性 | `get string ownerClassName()` | ---- 装配期宿主接口（形态 3，attribute _enter_ 内消费）---- 宿主名由触发通道注入（_ownerClassName / _ownerMemberName）； 具体 attribute 的装配逻辑写在各自 _enter_ 里，经这三个接口 取宿主素材（方法引用 / 绑定引用 / 新实例），VM 不写 per-attribute 代码 宿主类全名（@Singleton / @OnRoute 类级标记登记键） |
| 属性 | `get string ownerMemberName()` | 宿主成员名（方法级 attribute = 宿主方法名；错误提示 / 登记键用） |
| 方法 | `Function hostMethodRef()` | 宿主方法引用（双形态，SERVER_DESIGN.md §4.10：static 方法 → 静态 method-ref，不实例化；实例方法 → LATE 实例闭包，每次调用先 new 宿主实例——每请求一实例语义；Core 不依赖 Server，策略由消费侧 _enter_ 决定） |
| 方法 | `bool hostMethodIsStatic()` | 宿主方法是否静态（§4.10 双形态判定：类上无 @OnRoute 的直挂路由 必须绑定静态函数——SLang/Server registerPreload 消费） |
| 方法 | `Function hostMethodRefOf(object instance)` | 宿主方法绑定实例引用（bound method-ref：全程以 instance 为 this） |
| 方法 | `object hostClassNew()` | 构造宿主类新实例（NewObject 同款构造链：字段初始化器 + _init_） |

## class `Serializable`

- **说明**：序列化标签: 标注在 class/data 上, 声明该类型支持通用序列化 成员序列化规则: public 成员默认参与序列化 protected/private 成员默认不参与, 可用 @SerializeField() 强制参与 public 成员可用 @NonSerialized() 排除

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `SerializeField`

- **说明**：序列化标签: 强制 protected/private 成员参与序列化

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |

## class `NonSerialized`

- **说明**：序列化标签: 排除该 public 成员不参与序列化

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
