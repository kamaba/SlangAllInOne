# Text/BaseJson.sl

> 源文件：`Text/BaseJson.sl`

## class `BaseJson`

- **说明**：JSON 文本门面：基于 Tree<string> 树容器实现的 JSON 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/Json.sl。 解析与序列化由 VM 层 system_method_call（yyjson）完成，本类只做树容器门面。 弱类型映射约定（TreeNode<string>）： object 节点：_value = "{}"，每个成员为一个孩子节点，孩子 _name = 成员键名。 array  节点：_value = "[]"，每个元素为一个孩子节点，孩子 _name = ""（空串）。 string 节点：_value = 原文（已反转义）。 number 节点：_value = 最短往返十进制文本。 bool   节点：_value = "true" / "false"。 null   节点：_value = null。 路径语法沿用 Tree.select：按 _name 定位孩子，纯数字段视为孩子下标， 如 "user/name"、"list/0/id"、"data/items/2"。 典型用法：BaseJson j = BaseJson("{\"name\":\"alice\",\"age\":30}") j.getStr("name", "") / j.getInt("age", 0) / j.toString()。 层次化导航（多层嵌套取值见 Text/JsonValue.sl）： j["user"]["name"].asString() / j.value["list"][0].asInt32()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(string jsonText)` | 执行 _init_(jsonText)，行为详见源实现。 |
| 方法 | `void _init_(Tree&lt;string&gt; tree)` | 执行 _init_(tree)，行为详见源实现。 |
| 方法 | `BaseJson parse(string jsonText)` | ---- 静态工厂 ---- |
| 方法 | `BaseJson fromTree(Tree&lt;string&gt; tree)` | 执行 fromTree(tree)，行为详见源实现。 |
| 方法 | `BaseJson fromData(object obj)` | 由 data/class 实例构建 JSON 树（正向转换）：data 成员内置递归展开为 对象，class 成员虚调其 toJson() 嫁接子树，enum 成员取底层值， array/list/set/tuple 转数组、map 转对象。参数为 null 或转换失败 时返回空 BaseJson。参数名不能用 data（data 是类型定义关键字， 不能作标识符在表达式中使用）。 |
| 方法 | `bool parseText(string jsonText)` | ---- 解析 ---- 解析 JSON 文本并替换当前树；文本为空或非法时返回 false 且不清空原内容。 |
| 属性 | `get Tree&lt;string&gt; tree()` | ---- 基础属性 ---- 内部树容器（活引用，可用于深度遍历与结构操作）。 |
| 属性 | `get TreeNode&lt;string&gt; root()` | 根节点（空文档时为 null）。 |
| 属性 | `get JsonValue value()` | 根节点 JsonValue 视图（层次化导航入口，详见 Text/JsonValue.sl）： j.value["user"]["name"].asString() j.value["list"][0].asInt32() |
| 方法 | `JsonValue _getItem_(string name)` | 顶层成员的 JsonValue 快捷索引：j["user"]["name"].asInt32()。 未命中返回 isNull 缺失视图（链式导航安全，存在性用 has(path) 判定）。 |
| 方法 | `JsonValue _getItem_(int index)` | 顶层（数组文档）元素的 JsonValue 快捷索引：j[0].asFloat64()。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int memberCount()` | 顶层成员数（顶层为 object 时是成员数，为 array 时是元素数）。 |
| 属性 | `get int nodeCount()` | 全树节点总数。 |
| 属性 | `get int height()` | 获取 height 的值。 |
| 方法 | `void setRoot(TreeNode&lt;string&gt; node)` | ---- 树操作透传 ---- 设置根节点（注意：节点会先脱离原父节点，即从原树中摘除）。 |
| 方法 | `TreeNode&lt;string&gt; select(string path)` | 按路径选取节点，如 "user/name"、"list/0/id"；未命中返回 null。 |
| 方法 | `TreeNode&lt;string&gt; findByName(string name)` | 按名称在全树中查找第一个匹配节点；未命中返回 null。 |
| 方法 | `bool has(string path)` | 判断 / 校验是否（has）。 |
| 方法 | `void clear()` | 执行 clear()。 |
| 方法 | `bool isObject(TreeNode&lt;string&gt; node)` | ---- 节点类型判定 ---- |
| 方法 | `bool isArray(TreeNode&lt;string&gt; node)` | 判断状态是否（isArray）。 |
| 方法 | `bool isNull(TreeNode&lt;string&gt; node)` | 判断状态是否（isNull）。 |
| 方法 | `string getStr(string path)` | ---- 类型化取值（路径未命中或值为 null 时返回默认值）---- |
| 方法 | `string getStr(string path, string defaultValue)` | 执行 getStr(path, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBool(string path)` | 执行 getBool(path)，行为详见源实现。 |
| 方法 | `bool getBool(string path, bool defaultValue)` | 执行 getBool(path, defaultValue)，行为详见源实现。 |
| 方法 | `int getInt(string path)` | 整数取值：解析失败（如非数字文本）按 0 处理。 |
| 方法 | `int getInt(string path, int defaultValue)` | 执行 getInt(path, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path)` | 执行 getFloat(path)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path, Float64 defaultValue)` | 执行 getFloat(path, defaultValue)，行为详见源实现。 |
| 方法 | `object toData(string typeName)` | ---- 反向转换（JSON -&gt; data）---- 按 typeName（data 类型全名或短名）从当前树构建 data 实例； 类型不存在/非 data/根节点非 object/成员 布局不符时返回 null（成员缺失保持默认值，不报错）。 |
| 方法 | `string toJson()` | ---- 序列化 ---- |
| 方法 | `string toJsonPretty()` | 转换 / 序列化 / 格式化（toJsonPretty）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
