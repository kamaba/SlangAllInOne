# Text/JsonValue.sl

> 源文件：`Text/JsonValue.sl`

## class `JsonValue`

- **基类**：Object
- **说明**：JSON 层次化节点视图：包装 TreeNode<string> 的弱类型 JSON 节点， 提供多层嵌套导航与类型化取值，弥补 BaseJson 路径取值（select）之外的 层次化访问能力（BaseJson 的弱类型映射约定见其文件头注释）。 设计要点： - JsonValue 是树节点的活引用视图（非拷贝），树结构变化实时可见； - 缺失访问安全：_getItem_ 未命中不返回 null 引用，而是返回一个 包装 null 节点的 JsonValue（isNull == true），链式导航不中断： jv["user"]["name"].asInt32()   # 缺 "user" 时得默认值 0 - 存在性判断用 has(name) / isNull，不要对 _getItem_ 结果判 null； - foreach 直接遍历本节点的直接孩子（数组元素或 object 成员）。 典型用法： JsonValue jv = JsonValue.parse("{\"user\":{\"name\":\"alice\",\"age\":30}}") jv["user"]["name"].asString()      # "alice" jv["user"]["age"].asInt32()        # 30 for item in jv["user"]             # 遍历 user 的成员 jv["list"][0].asFloat64() jv["obj"].asMap() / jv["list"].asArray() / jv["list"].asList() jv["data"].asData<MyData>() jv["obj"].toJsonPretty() 复用既有系统调用（data<->json 与 BaseJson 已验证的路径）： SystemTreeChildByName / SystemTreeChildAt  子元素定位 SystemJsonIsNumberText                      数字文本判定（本批新增） SystemJsonParseInt64                        Int64 文本解析（本批新增） SystemInt32Parse / SystemConvertFloat64     标量解析 SystemJsonToData / SystemJsonToString       data 转换与序列化

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `TreeNode&lt;string&gt; _node = null` | --- 核心字段 --- |
| 字段 | `TreeNode&lt;string&gt; _iterNode = null` | --- 迭代器字段（直接孩子序）--- |
| 字段 | `int _index = -1` | 字段 _index（类型见签名）。 |
| 字段 | `JsonValue _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(TreeNode&lt;string&gt; node)` | 以树节点构造（node 可为 null，构造缺失视图） |
| 方法 | `JsonValue wrap(TreeNode&lt;string&gt; node)` | ---- 静态工厂 ---- 包装树节点（node 为 null 时返回 isNull 的缺失视图，不返回 null 引用） |
| 方法 | `JsonValue parse(string jsonText)` | 解析 JSON 文本为根节点视图；文本为空或非法时返回缺失视图 |
| 属性 | `get TreeNode&lt;string&gt; node()` | ---- 基础属性 ---- 被包装的原始树节点（缺失视图为 null；树结构操作的逃生口） |
| 属性 | `get string name()` | 节点名（object 成员的键名；数组元素为空串，根/缺失为 null） |
| 属性 | `get int length()` | 直接孩子数（object 的成员数或 array 的元素数） |
| 属性 | `get bool exists()` | 是否为存在的节点（缺失视图为 false） |
| 属性 | `get bool isNull()` | ---- 节点类型判定（弱类型标记约定与 BaseJson 一致）---- JSON null（或缺失视图） |
| 属性 | `get bool isObject()` | 获取 isObject 的值。 |
| 属性 | `get bool isArray()` | 获取 isArray 的值。 |
| 属性 | `get bool isBool()` | 获取 isBool 的值。 |
| 属性 | `get bool isNumber()` | 数字叶子（严格 JSON 数字语法，复用 C 层序列化方向的判定） |
| 属性 | `get bool isString()` | 字符串叶子（排除 null/object/array/bool/number 之后的剩余情形） |
| 方法 | `string _leafText()` | 叶子原始文本（null/object/array/缺失返回 null，供 asXxx 内部使用） |
| 方法 | `JsonValue _wrapChild(TreeNode&lt;string&gt; child)` | ---- 子元素访问（多层嵌套导航核心）---- 孩子节点包装（实例内构造，避免实例方法走类名静态解析） |
| 方法 | `JsonValue _getItem_(string name)` | 按键名取 object 成员：jv["name"] / jv.$"name"。 未命中返回 isNull 缺失视图（链式导航安全，存在性判断用 has） |
| 方法 | `JsonValue _getItem_(int index)` | 按下标取 array 元素：jv[0] / jv.$0。越界返回 isNull 缺失视图 |
| 方法 | `bool has(string name)` | 是否含有指定键名的直接孩子 |
| 方法 | `bool has(int index)` | 下标是否在直接孩子范围内 |
| 方法 | `JsonValue select(string path)` | 路径导航（沿用 Tree.select 语法："user/address"、"list/0/id"）， 未命中返回 isNull 缺失视图 |
| 方法 | `Array&lt;JsonValue&gt; children()` | 直接孩子视图数组（object 成员与 array 元素通用） |
| 方法 | `Array&lt;string&gt; keys()` | object 成员的键名数组（数组元素场景为空串，一般配合 asMap 使用） |
| 方法 | `bool asBool()` | ---- 标量转换（值缺失 / 非数字文本时返回默认值）---- |
| 方法 | `bool asBool(bool defaultValue)` | 转换 / 序列化 / 格式化（asBool）。 |
| 方法 | `string asString()` | 叶子原文（object/array/null 返回默认值，不做序列化） |
| 方法 | `string asString(string defaultValue)` | 转换 / 序列化 / 格式化（asString）。 |
| 方法 | `int asInt32()` | 转换 / 序列化 / 格式化（asInt32）。 |
| 方法 | `int asInt32(int defaultValue)` | 转换 / 序列化 / 格式化（asInt32）。 |
| 方法 | `Int64 asInt64()` | 转换 / 序列化 / 格式化（asInt64）。 |
| 方法 | `Int64 asInt64(Int64 defaultValue)` | SystemConvertInt64 不解析字符串，走本批新增的 SystemJsonParseInt64 |
| 方法 | `Float32 asFloat32()` | 转换 / 序列化 / 格式化（asFloat32）。 |
| 方法 | `Float32 asFloat32(Float32 defaultValue)` | 先按 Float64 解析字符串再压窄到 Float32（Float32 直转不解析字符串） |
| 方法 | `Float64 asFloat64()` | 转换 / 序列化 / 格式化（asFloat64）。 |
| 方法 | `Float64 asFloat64(Float64 defaultValue)` | 转换 / 序列化 / 格式化（asFloat64）。 |
| 方法 | `Array&lt;JsonValue&gt; asArray()` | ---- 容器转换 ---- 转为数组视图（直接孩子逐个包装；空数组场景含 isNull 视图） |
| 方法 | `List&lt;JsonValue&gt; asList()` | 转为列表（直接孩子逐个包装，动态扩容） |
| 方法 | `Map&lt;string, JsonValue&gt; asMap()` | 转为键值映射（object 成员的键名 -&gt; JsonValue；跳过无键名的孩子） |
| 方法 | `object asData(string typeName)` | ---- data 转换（复用 BaseJson.toData 的 C 层后端）---- 按 typeName（data 类型全名或短名）构建 data 实例；非 data/根非 object 返回 null |
| 方法 | `string toJson()` | ---- 序列化（复用 BaseJson 的 C 层后端）---- 以本节点为根序列化为紧凑 JSON 文本（缺失视图输出 "null"） |
| 方法 | `string toJsonPretty()` | 以本节点为根序列化为 2 空格缩进的格式化文本 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `void reset()` | ---- 迭代器（foreach 遍历直接孩子，沿兄弟链 O(n) 推进）---- |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get JsonValue current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
