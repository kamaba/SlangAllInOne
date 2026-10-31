#TOML 文本门面：基于 Tree<string> 树容器实现的 TOML 文本解析与序列化工具。
#只处理文本，不做文件读写；文件相关功能见 Std/Text/Toml.sl。
#解析与序列化由 VM 层 system_method_call（自研递归下降解析器，C99 实现）完成，
#本类只做树容器门面；核心解析在 csimple_lang/src/vm/system_method_call/toml_system_method.c。
#
#弱类型映射约定（TreeNode<string>，与 BaseJson/BaseYaml 一致）：
#  表     节点：_value = "{}"，每个键为一个孩子节点，孩子 _name = 键名
#            （顶层文档根节点即为 "{}" 表；[[数组表]] 的每个元素也是
#              "{}" 孩子，_name = ""）。
#  数组   节点：_value = "[]"，每个元素为一个孩子节点，孩子 _name = ""（空串）。
#  字符串 节点：_value = 内容（引号已剥、转义已反转义、\uXXXX 已解码）。
#  数字   节点：_value = 原文（下划线分隔符已去除，不做数值转换，弱类型无损保留）。
#  布尔   节点：_value = "true" / "false"。
#  日期时间   节点：_value = 原文（与字符串同存弱类型树）。
#
#解析规则（TOML 1.0 实用子集，详见 toml_system_method.h 头注释）：
#  1) 注释 # 到行尾；键与值的空白忽略；键支持裸键 / 引号键与 a.b.c 点分嵌套；
#  2) [a.b] 表头切换当前表（缺层自动建表，同名合并，导航遇数组取末元素）；
#     [[a.b]] 数组表：路径末段建 "[]" 数组并追加新表元素；
#  3) 值：基本串（转义 + 多行续行）、字面串、多行串（首换行裁剪）、布尔、
#     数字（0x/0o/0b/十进制/浮点，去下划线）、日期时间、跨行数组（容忍尾逗号）、
#     内联表（限单行，支持 dotted key）；
#  4) 重复键后者覆盖前者；结构性语法错误整体解析失败返回 false 且不清空原树。
#
#序列化 toToml()：顶层标量成员直接输出（无段头），子表递归输出 [a.b] 段，
#  数组表输出 [[a.b]] 段（每元素一段），值数组输出内联 [e1, e2]，
#  含换行的字符串输出多行 """ 形式；数字/布尔/日期原文裸输出（弱类型树
#  无法区分纯数字字符串，此类值往返后类型会规范化为数字，为弱类型系统固有取舍）。
#
#路径语法沿用 Tree.select：按 _name 定位孩子，纯数字段视为孩子下标，
#  如 "server/host"、"list/0/id"、"data/items/2"。
#
#典型用法：BaseToml t = BaseToml("[server]\nhost = 0.0.0.0\nport = 8080\n[[items]]\nname = \"a\"")
#          t.getStr("server/host", "") / t.getInt("server/port", 0) / t.getStr("items/0/name", "")。
public class BaseToml extends Object
{
    Tree<string> _tree = new()

    # ---- 构造 ----

    override _init_()
    {
    }

    void _init_( string tomlText )
    {
        if tomlText == null { ret }
        this.parseText(tomlText)
    }

    void _init_( Tree<string> tree )
    {
        if tree != null
        {
            this._tree = tree
        }
    }

    # ---- 静态工厂 ----

    public static BaseToml parse( string tomlText )
    {
        ret BaseToml(tomlText)
    }

    public static BaseToml fromTree( Tree<string> tree )
    {
        ret BaseToml(tree)
    }

    # ---- 解析 ----

    #解析 TOML 文本并替换当前树；文本为空或非法时返回 false 且不清空原内容。
    public bool parseText( string tomlText )
    {
        TreeNode<string> proto = TreeNode<string>()
        TreeNode<string> root = SystemTomlParse(proto, tomlText) as TreeNode<string>
        if root == null { ret false }
        this._tree.setRoot(root)
        ret true
    }

    # ---- 基础属性 ----

    #内部树容器（活引用，可用于深度遍历与结构操作）。
    get Tree<string> tree()
    {
        ret this._tree
    }

    #根节点（空文档时为 null）。
    get TreeNode<string> root()
    {
        ret this._tree.root
    }

    get bool isEmpty()
    {
        ret this._tree.isEmpty
    }

    get bool isNotEmpty()
    {
        ret this._tree.isNotEmpty
    }

    #顶层成员数。
    get int memberCount()
    {
        TreeNode<string> root = this._tree.root
        if root == null { ret 0 }
        ret root.childCount
    }

    #全树节点总数。
    get int nodeCount()
    {
        ret this._tree.length
    }

    get int height()
    {
        ret this._tree.height
    }

    # ---- 树操作透传 ----

    #设置根节点（注意：节点会先脱离原父节点，即从原树中摘除）。
    public void setRoot( TreeNode<string> node )
    {
        if node == null { ret }
        this._tree.setRoot(node)
    }

    #按路径选取节点，如 "server/host"、"list/0/id"；未命中返回 null。
    public TreeNode<string> select( string path )
    {
        ret this._tree.select(path)
    }

    #按名称在全树中查找第一个匹配节点；未命中返回 null。
    public TreeNode<string> findByName( string name )
    {
        ret this._tree.findByName(name)
    }

    public bool has( string path )
    {
        ret this.select(path) != null
    }

    #移除路径处节点（从父节点摘除），返回是否存在并已移除。
    public bool removeKey( string path )
    {
        TreeNode<string> node = this.select(path)
        if node == null { ret false }
        ret node.detach()
    }

    public void clear()
    {
        this._tree.clear()
    }

    # ---- 节点类型判定 ----

    public static bool isObject( TreeNode<string> node )
    {
        if node == null { ret false }
        ret node._value == "{}"
    }

    public static bool isArray( TreeNode<string> node )
    {
        if node == null { ret false }
        ret node._value == "[]"
    }

    public static bool isNull( TreeNode<string> node )
    {
        if node == null { ret false }
        ret node._value == null
    }

    # ---- 类型化取值（路径未命中或值为 null 时返回默认值）----

    public string getStr( string path )
    {
        ret this.getStr(path, "")
    }

    public string getStr( string path, string defaultValue )
    {
        TreeNode<string> node = this.select(path)
        if node == null { ret defaultValue }
        if node._value == null { ret defaultValue }
        ret node._value
    }

    public bool getBool( string path )
    {
        ret this.getBool(path, false)
    }

    public bool getBool( string path, bool defaultValue )
    {
        TreeNode<string> node = this.select(path)
        if node == null { ret defaultValue }
        if node._value == null { ret defaultValue }
        ret node._value == "true"
    }

    #整数取值：解析失败（如非数字文本）按 0 处理。
    public int getInt( string path )
    {
        ret this.getInt(path, 0)
    }

    public int getInt( string path, int defaultValue )
    {
        TreeNode<string> node = this.select(path)
        if node == null { ret defaultValue }
        if node._value == null { ret defaultValue }
        ret SystemInt32Parse(node._value)
    }

    public Float64 getFloat( string path )
    {
        ret this.getFloat(path, 0.0d)
    }

    public Float64 getFloat( string path, Float64 defaultValue )
    {
        TreeNode<string> node = this.select(path)
        if node == null { ret defaultValue }
        if node._value == null { ret defaultValue }
        ret SystemConvertFloat64(node._value)
    }

    # ---- 序列化 ----

    public string toToml()
    {
        ret SystemTomlToString(this._tree.root, false)
    }

    override string toString()
    {
        ret this.toToml()
    }
}
