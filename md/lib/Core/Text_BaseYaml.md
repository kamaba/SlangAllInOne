# Text/BaseYaml.sl

> 源文件：`Text/BaseYaml.sl`

## class `BaseYaml`

- **说明**：YAML 文本门面：基于 Tree<string> 树容器实现的 YAML 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/Yaml.sl。 解析与序列化由 VM 层 system_method_call（自研行驱动解析器）完成， 本类只做树容器门面。 弱类型映射约定（TreeNode<string>，与 BaseJson 一致，YAML 是 JSON 超集）： mapping  节点：_value = "{}"，每个成员为一个孩子节点，孩子 _name = 成员键名。 sequence 节点：_value = "[]"，每个元素为一个孩子节点，孩子 _name = ""（空串）。 string   节点：_value = 原文（引号已剥、转义已反转义）。 number   节点：_value = 原文（不做数值转换，弱类型无损保留）。 bool     节点：_value = "true" / "false"（小写规范化）。 null     节点：_value = null。 路径语法沿用 Tree.select：按 _name 定位孩子，纯数字段视为孩子下标， 如 "user/name"、"list/0/id"、"data/items/2"。 序列化：toYaml() 为 flow 单行风格（与 JSON 文本互通可再解析）， toYamlPretty() 为块风格 2 空格缩进多行。 典型用法：BaseYaml y = BaseYaml("name: alice\nage: 30") y.getStr("name", "") / y.getInt("age", 0) / y.toYamlPretty()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(string yamlText)` | 执行 _init_(yamlText)，行为详见源实现。 |
| 方法 | `void _init_(Tree&lt;string&gt; tree)` | 执行 _init_(tree)，行为详见源实现。 |
| 方法 | `BaseYaml parse(string yamlText)` | ---- 静态工厂 ---- |
| 方法 | `BaseYaml fromTree(Tree&lt;string&gt; tree)` | 执行 fromTree(tree)，行为详见源实现。 |
| 方法 | `bool parseText(string yamlText)` | ---- 解析 ---- 解析 YAML 文本并替换当前树；文本为空或非法时返回 false 且不清空原内容。 |
| 属性 | `get Tree&lt;string&gt; tree()` | ---- 基础属性 ---- 内部树容器（活引用，可用于深度遍历与结构操作）。 |
| 属性 | `get TreeNode&lt;string&gt; root()` | 根节点（空文档时为 null）。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int memberCount()` | 顶层成员数（顶层为 mapping 时是成员数，为 sequence 时是元素数）。 |
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
| 方法 | `int getInt(string path)` | 整数取值：解析失败（如非数字文本）按默认值处理。 |
| 方法 | `int getInt(string path, int defaultValue)` | 执行 getInt(path, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path)` | 执行 getFloat(path)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path, Float64 defaultValue)` | 执行 getFloat(path, defaultValue)，行为详见源实现。 |
| 方法 | `string toYaml()` | ---- 序列化 ---- flow 单行风格（{k: v, ...} / [a, b]，与 JSON 文本互通可再解析）。 |
| 方法 | `string toYamlPretty()` | 块风格 2 空格缩进多行（文档尾随一个换行）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
