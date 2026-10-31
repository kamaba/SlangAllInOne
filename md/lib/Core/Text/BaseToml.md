# Text/BaseToml.sl

> 源文件：`Text/BaseToml.sl`

## class `BaseToml`

- **说明**：TOML 文本门面：基于 Tree<string> 树容器实现的 TOML 文本解析与序列化工具。 只处理文本，不做文件读写；文件相关功能见 Std/Text/Toml.sl。 解析与序列化由 VM 层 system_method_call（自研递归下降解析器，C99 实现）完成， 本类只做树容器门面；核心解析在 csimple_lang/src/vm/system_method_call/toml_system_method.c。 弱类型映射约定（TreeNode<string>，与 BaseJson/BaseYaml 一致）： 表     节点：_value = "{}"，每个键为一个孩子节点，孩子 _name = 键名 （顶层文档根节点即为 "{}" 表；[[数组表]] 的每个元素也是 "{}" 孩子，_name = ""）。 数组   节点：_value = "[]"，每个元素为一个孩子节点，孩子 _name = ""（空串）。 字符串 节点：_value = 内容（引号已剥、转义已反转义、\uXXXX 已解码）。 数字   节点：_value = 原文（下划线分隔符已去除，不做数值转换，弱类型无损保留）。 布尔   节点：_value = "true" / "false"。 日期时间   节点：_value = 原文（与字符串同存弱类型树）。 解析规则（TOML 1.0 实用子集，详见 toml_system_method.h 头注释）： 1) 注释 # 到行尾；键与值的空白忽略；键支持裸键 / 引号键与 a.b.c 点分嵌套； 2) [a.b] 表头切换当前表（缺层自动建表，同名合并，导航遇数组取末元素）； [[a.b]] 数组表：路径末段建 "[]" 数组并追加新表元素； 3) 值：基本串（转义 + 多行续行）、字面串、多行串（首换行裁剪）、布尔、 数字（0x/0o/0b/十进制/浮点，去下划线）、日期时间、跨行数组（容忍尾逗号）、 内联表（限单行，支持 dotted key）； 4) 重复键后者覆盖前者；结构性语法错误整体解析失败返回 false 且不清空原树。 序列化 toToml()：顶层标量成员直接输出（无段头），子表递归输出 [a.b] 段， 数组表输出 [[a.b]] 段（每元素一段），值数组输出内联 [e1, e2]， 含换行的字符串输出多行 """ 形式；数字/布尔/日期原文裸输出（弱类型树 无法区分纯数字字符串，此类值往返后类型会规范化为数字，为弱类型系统固有取舍）。 路径语法沿用 Tree.select：按 _name 定位孩子，纯数字段视为孩子下标， 如 "server/host"、"list/0/id"、"data/items/2"。 典型用法：BaseToml t = BaseToml("[server]\nhost = 0.0.0.0\nport = 8080\n[[items]]\nname = \"a\"") t.getStr("server/host", "") / t.getInt("server/port", 0) / t.getStr("items/0/name", "")。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | ---- 构造 ---- |
| 方法 | `void _init_(string tomlText)` | 执行 _init_(tomlText)，行为详见源实现。 |
| 方法 | `void _init_(Tree&lt;string&gt; tree)` | 执行 _init_(tree)，行为详见源实现。 |
| 方法 | `BaseToml parse(string tomlText)` | ---- 静态工厂 ---- |
| 方法 | `BaseToml fromTree(Tree&lt;string&gt; tree)` | 执行 fromTree(tree)，行为详见源实现。 |
| 方法 | `bool parseText(string tomlText)` | ---- 解析 ---- 解析 TOML 文本并替换当前树；文本为空或非法时返回 false 且不清空原内容。 |
| 属性 | `get Tree&lt;string&gt; tree()` | ---- 基础属性 ---- 内部树容器（活引用，可用于深度遍历与结构操作）。 |
| 属性 | `get TreeNode&lt;string&gt; root()` | 根节点（空文档时为 null）。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int memberCount()` | 顶层成员数。 |
| 属性 | `get int nodeCount()` | 全树节点总数。 |
| 属性 | `get int height()` | 获取 height 的值。 |
| 方法 | `void setRoot(TreeNode&lt;string&gt; node)` | ---- 树操作透传 ---- 设置根节点（注意：节点会先脱离原父节点，即从原树中摘除）。 |
| 方法 | `TreeNode&lt;string&gt; select(string path)` | 按路径选取节点，如 "server/host"、"list/0/id"；未命中返回 null。 |
| 方法 | `TreeNode&lt;string&gt; findByName(string name)` | 按名称在全树中查找第一个匹配节点；未命中返回 null。 |
| 方法 | `bool has(string path)` | 判断 / 校验是否（has）。 |
| 方法 | `bool removeKey(string path)` | 移除路径处节点（从父节点摘除），返回是否存在并已移除。 |
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
| 方法 | `string toToml()` | ---- 序列化 ---- |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
