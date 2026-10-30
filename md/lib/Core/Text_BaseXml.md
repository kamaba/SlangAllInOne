# Text/BaseXml.sl

> 源文件：`Text/BaseXml.sl`

## class `BaseXml`

- **说明**：XML 文本门面：基于 Tree<string> 树容器实现的 XML 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/Xml.sl。 解析与序列化由 VM 层 system_method_call 完成，本类只做树容器门面。 弱类型映射约定（TreeNode<string>）： 元素节点：_name = 标签名，_value = 元素直接文本（无文本为 null； 多段文本拼接，CDATA 并入，已反转义）。 属性节点：元素的孩子，_name = "@" + 属性名，_value = 属性值文本； 解析时排在子元素之前（构建时顺序不限，序列化统一先输出属性）。 声明/DOCTYPE/注释/处理指令：解析时跳过，序列化不输出。 路径语法沿用 Tree.select：按 _name 定位孩子，纯数字段视为孩子下标， 如 "user/name"、"items/0/id"、"user/@id"（属性定位）。 典型用法：BaseXml x = BaseXml("<user id=\"1\"><name>alice</name></user>") x.getText("user/name", "") / x.getAttr("user", "id", "") / x.toString()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(string xmlText)` | 执行 _init_(xmlText)，行为详见源实现。 |
| 方法 | `void _init_(Tree&lt;string&gt; tree)` | 执行 _init_(tree)，行为详见源实现。 |
| 方法 | `BaseXml parse(string xmlText)` | ---- 静态工厂 ---- |
| 方法 | `BaseXml fromTree(Tree&lt;string&gt; tree)` | 执行 fromTree(tree)，行为详见源实现。 |
| 方法 | `bool parseText(string xmlText)` | ---- 解析 ---- 解析 XML 文本并替换当前树；文本为空或非法时返回 false 且不清空原内容。 |
| 属性 | `get Tree&lt;string&gt; tree()` | ---- 基础属性 ---- 内部树容器（活引用，可用于深度遍历与结构操作）。 |
| 属性 | `get TreeNode&lt;string&gt; root()` | 根节点（空文档时为 null）。 |
| 属性 | `get string rootName()` | 根标签名（空文档时为 null）。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int memberCount()` | 根元素直接孩子数（属性孩子 + 子元素）。 |
| 属性 | `get int nodeCount()` | 全树节点总数。 |
| 属性 | `get int height()` | 获取 height 的值。 |
| 方法 | `void setRoot(TreeNode&lt;string&gt; node)` | ---- 树操作透传 ---- 设置根节点（注意：节点会先脱离原父节点，即从原树中摘除）。 |
| 方法 | `TreeNode&lt;string&gt; select(string path)` | 按路径选取节点，如 "user/name"、"items/0/id"、"user/@id"；未命中返回 null。 |
| 方法 | `TreeNode&lt;string&gt; findByName(string name)` | 按名称在全树中查找第一个匹配节点；未命中返回 null。 |
| 方法 | `bool has(string path)` | 判断 / 校验是否（has）。 |
| 方法 | `void clear()` | 执行 clear()。 |
| 方法 | `string attrName(string name)` | ---- 节点类型判定 ---- 属性孩子名（"@" + 属性名），孩子定位与属性构建共用。 |
| 方法 | `bool isElement(TreeNode&lt;string&gt; node)` | 是否元素节点（_name 非空且不以 "@" 开头）。 |
| 方法 | `bool isAttr(TreeNode&lt;string&gt; node)` | 是否属性节点（_name 以 "@" 开头）。 |
| 方法 | `string getText(string path)` | ---- 元素文本（路径未命中或无文本时返回默认值）---- |
| 方法 | `string getText(string path, string defaultValue)` | 取 path 元素的直接文本；未命中或无文本返回默认值。 |
| 方法 | `string getAttr(string path, string name)` | ---- 属性操作 ---- |
| 方法 | `string getAttr(string path, string name, string defaultValue)` | 取 path 元素的 name 属性值；元素缺失/无该属性时返回默认值。 |
| 方法 | `bool hasAttr(string path, string name)` | path 元素是否含有 name 属性。 |
| 方法 | `bool setAttr(string path, string name, string value)` | 设置 path 元素的 name 属性（已有属性改值，没有则新建属性孩子）。 |
| 方法 | `TreeNode&lt;string&gt; addRootElement(string name)` | ---- 元素构建 ---- 创建并设置根元素，返回新根节点。 |
| 方法 | `TreeNode&lt;string&gt; addElement(string path, string name)` | 在 path 元素下创建并挂接无文本子元素。 |
| 方法 | `TreeNode&lt;string&gt; addElement(string path, string name, string text)` | 在 path 元素下创建并挂接带文本子元素。 |
| 方法 | `bool getBool(string path)` | ---- 类型化取值（元素文本；路径未命中或值为 null 时返回默认值）---- |
| 方法 | `bool getBool(string path, bool defaultValue)` | 执行 getBool(path, defaultValue)，行为详见源实现。 |
| 方法 | `int getInt(string path)` | 整数取值：解析失败（如非数字文本）按 0 处理。 |
| 方法 | `int getInt(string path, int defaultValue)` | 执行 getInt(path, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path)` | 执行 getFloat(path)，行为详见源实现。 |
| 方法 | `Float64 getFloat(string path, Float64 defaultValue)` | 执行 getFloat(path, defaultValue)，行为详见源实现。 |
| 方法 | `string toXml()` | ---- 序列化 ---- |
| 方法 | `string toXmlPretty()` | 转换 / 序列化 / 格式化（toXmlPretty）。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
