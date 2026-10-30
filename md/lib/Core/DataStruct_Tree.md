# DataStruct/Tree.sl

> 源文件：`DataStruct/Tree.sl`

## class `TreeNode<T>`

- **说明**：树结构库：N 叉树（左孩子右兄弟）+ 二叉树 + 二叉搜索树，最通用树算法的统一实现。 本文件五个类同时被 Xml/Yaml/Json/Toml/Config(ini) 等层级数据结构复用： - TreeNode<T> 的 _name（标签名/键名/节名）与 _value（文本/标量值）直接对应文档节点； - select("a/b/0/c") 路径选择、childByName、buildPath 与 XPath 风格路径互通。 核心数据结构： N 叉树（左孩子右兄弟表示）： TreeNode<T>: _name(可选) _value(可选) _parent _firstChild _lastChild _prevSibling _nextSibling _childCount Tree<T>    : _root _iterNode/_index/_current（先序迭代器） 二叉树： BinaryNode<T>: _value _left _right _parent BinaryTree<T>: _root _iterNode/_index/_current（中序迭代器） BinarySearchTree<T> extends BinaryTree<T> 设计（与 Queue/LinkedList/Set 一致的分层）： - SL 层：泛型实例化（TreeNode<T>/BinaryNode<T> 须由前端实例化）、新节点创建、数组分配； - C 层：指针手术（挂接/摘除/防环）、遍历（先序/中序/后序/层序）、查找、 高度/深度/计数、LCA、路径、镜像、BST 插入删除等全部耗时操作 通过 SystemTree*/SystemBinary*/SystemBst* 系统调用映射到 CVM 原生实现 （tree_system_method.c）。 遍历序约定：N 叉 0=先序 1=后序 2=层序；二叉 0=先序 1=中序 2=后序 3=层序。 高度/深度约定：空树 0，单节点高度 1，根深度 1。 查找未命中返回 null（与本库其他容器越界返回 null 的语义一致）。 N 叉树节点（左孩子右兄弟表示，可直接充当 Xml/Yaml/Json/Toml/Config 的文档节点）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _name = null` | --- 核心字段 --- |
| 字段 | `T _value = null` | 字段 _value（类型见签名）。 |
| 字段 | `TreeNode&lt;T&gt; _parent = null` | 字段 _parent（类型见签名）。 |
| 字段 | `TreeNode&lt;T&gt; _firstChild = null` | 字段 _firstChild（类型见签名）。 |
| 字段 | `TreeNode&lt;T&gt; _lastChild = null` | 字段 _lastChild（类型见签名）。 |
| 字段 | `TreeNode&lt;T&gt; _prevSibling = null` | 字段 _prevSibling（类型见签名）。 |
| 字段 | `TreeNode&lt;T&gt; _nextSibling = null` | 字段 _nextSibling（类型见签名）。 |
| 字段 | `int _childCount = 0` | 字段 _childCount（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(string name)` | 指定节点名构造（文档场景：仅命名节点） |
| 方法 | `void _init_(string name, T value)` | 指定节点名与值构造 |
| 属性 | `get string name()` | ── 属性 ── |
| 属性 | `set void name(string value)` | 设置 name 的值。 |
| 属性 | `get T value()` | 获取 value 的值。 |
| 属性 | `set void value(T value)` | 设置 value 的值。 |
| 属性 | `get TreeNode&lt;T&gt; parent()` | 获取 parent 的值。 |
| 属性 | `get TreeNode&lt;T&gt; firstChild()` | 获取 firstChild 的值。 |
| 属性 | `get TreeNode&lt;T&gt; lastChild()` | 获取 lastChild 的值。 |
| 属性 | `get TreeNode&lt;T&gt; prevSibling()` | 获取 prevSibling 的值。 |
| 属性 | `get TreeNode&lt;T&gt; nextSibling()` | 获取 nextSibling 的值。 |
| 属性 | `get int childCount()` | 获取 childCount 的值。 |
| 属性 | `get bool isLeaf()` | 获取 isLeaf 的值。 |
| 属性 | `get bool isRoot()` | 获取 isRoot 的值。 |
| 属性 | `get bool hasChildren()` | 获取 hasChildren 的值。 |
| 属性 | `get string path()` | 从根到本节点的 '/' 分隔路径（用各节点 _name，文档场景的 XPath 风格定位） |
| 方法 | `bool attach(TreeNode&lt;T&gt; node)` | ── 孩子操作（指针手术在 VM 层完成）── 挂接已有节点为本节点的末子（自动脱离原父，拒绝自挂/挂到子孙防环） |
| 方法 | `TreeNode&lt;T&gt; addChild(string name)` | 创建并挂接命名子节点 |
| 方法 | `TreeNode&lt;T&gt; addChild(string name, T value)` | 创建并挂接带值子节点 |
| 方法 | `bool detach()` | 摘除本节点（保留其子树成为新的独立树），根节点返回 false |
| 方法 | `TreeNode&lt;T&gt; childAt(int index)` | 取第 index 个直接孩子（0 起，越界返回 null） |
| 方法 | `TreeNode&lt;T&gt; childByName(string name)` | 取第一个名为 name 的直接孩子（文档场景：按标签/键取子节点） |
| 方法 | `int childrenToArray(Array&lt;TreeNode&lt;T&gt;&gt; arr)` | 直接孩子填入 arr（须预分配足够容量），返回实际个数 |
| 方法 | `bool contains(TreeNode&lt;T&gt; target)` | 本节点与其全部子孙是否包含 target（按对象身份） |
| 方法 | `int count()` | ── 子树算法（全部在 VM 层完成）── 子树节点总数（含自身） |
| 方法 | `int height()` | 子树高度（单节点 1） |
| 方法 | `int depth()` | 节点深度（根 1） |
| 方法 | `TreeNode&lt;T&gt; find(T value)` | 先序查找第一个 _value 相等的节点（未命中返回 null） |
| 方法 | `TreeNode&lt;T&gt; findByName(string name)` | 先序查找第一个 _name 相等的节点（文档场景：按名深查） |
| 方法 | `int findAll(T value, Array&lt;TreeNode&lt;T&gt;&gt; arr)` | 先序收集全部 _value 相等节点到 arr（须预分配足够容量），返回实际个数 |
| 方法 | `TreeNode&lt;T&gt; select(string path)` | 路径选择（"a/b/0/c"：名字定位，纯数字段为孩子下标；空路径返回自身） |
| 方法 | `TreeNode&lt;T&gt; lca(TreeNode&lt;T&gt; other)` | 最近公共祖先（不同树返回 null） |
| 方法 | `int nodesToArray(int order, Array&lt;TreeNode&lt;T&gt;&gt; arr)` | ── 遍历（节点版/取值版，order：0=先序 1=后序 2=层序）── 按序填充节点数组（须预分配足够容量），返回实际个数 |
| 方法 | `int valuesToArray(int order, Array&lt;T&gt; arr)` | 按序填充各节点 _value 数组（须预分配足够容量），返回实际个数 |
| 方法 | `Array&lt;T&gt; values(int order)` | 按序取值数组（新数组，长度精确） |
| 方法 | `Array&lt;T&gt; preorderValues()` | 先序取值数组 |
| 方法 | `Array&lt;T&gt; postorderValues()` | 后序取值数组 |
| 方法 | `Array&lt;T&gt; levelOrderValues()` | 层序取值数组 |
| 方法 | `string toString()` | 输出 name=value（无值只输出 name）形式 |

## class `Tree<T>`

- **基类**：Object
- **说明**：N 叉树（持有根节点，foreach 按先序迭代 _value）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `TreeNode&lt;T&gt; _root = null` | --- 核心字段 --- |
| 字段 | `TreeNode&lt;T&gt; _iterNode = null` | --- 迭代器字段（先序迭代）--- |
| 字段 | `int _index = -1` | 字段 _index（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(TreeNode&lt;T&gt; root)` | 以已有节点为根构造（节点先脱离原父） |
| 方法 | `void _init_(string rootName)` | 创建命名根节点 |
| 方法 | `void _init_(string rootName, T rootValue)` | 创建命名带值根节点 |
| 属性 | `get TreeNode&lt;T&gt; root()` | ── 属性 ── |
| 属性 | `set void root(TreeNode&lt;T&gt; node)` | 设置 root 的值。 |
| 属性 | `get int length()` | 节点总数（Python len / C# Count） |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int height()` | 树高（空树 0） |
| 属性 | `get string rootName()` | 根节点名字（文档场景：根标签名） |
| 方法 | `void setRoot(TreeNode&lt;T&gt; node)` | ── 根操作 ── 设根（null 表示清根；节点先脱离原父，迭代器重置） |
| 方法 | `TreeNode&lt;T&gt; addRoot(string name)` | 创建并设置命名根节点，返回新根 |
| 方法 | `TreeNode&lt;T&gt; addRoot(string name, T value)` | 创建并设置命名带值根节点，返回新根 |
| 方法 | `TreeNode&lt;T&gt; find(T value)` | ── 子树算法（委托根节点，全部在 VM 层完成）── 先序查找第一个 _value 相等节点 |
| 方法 | `TreeNode&lt;T&gt; findByName(string name)` | 先序查找第一个 _name 相等节点（文档场景：按名深查） |
| 方法 | `TreeNode&lt;T&gt; select(string path)` | 路径选择（"a/b/0/c"：名字定位，纯数字段为孩子下标） |
| 方法 | `TreeNode&lt;T&gt; lca(TreeNode&lt;T&gt; a, TreeNode&lt;T&gt; b)` | 最近公共祖先（不同树返回 null） |
| 方法 | `bool contains(TreeNode&lt;T&gt; node)` | 是否包含某节点（按对象身份） |
| 方法 | `bool containsValue(T value)` | 是否包含某值 |
| 方法 | `Array&lt;T&gt; values(int order)` | 按序取值数组（新数组，长度精确） |
| 方法 | `Array&lt;T&gt; preorderValues()` | 执行 preorderValues()。 |
| 方法 | `Array&lt;T&gt; postorderValues()` | 执行 postorderValues()。 |
| 方法 | `Array&lt;T&gt; levelOrderValues()` | 执行 levelOrderValues()。 |
| 方法 | `void clear()` | ── 删除 ── 清空（置空根并重置迭代器，节点由 GC 回收） |
| 方法 | `void reset()` | ── 迭代器（foreach 热路径，SystemTreeMoveNext 在 VM 层按先序推进）── |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 方法 | `string toString()` | 输出 Tree(root=a,b,c) 格式（先序取值） |

## class `BinaryNode<T>`

- **说明**：二叉树节点（三叉链：_left/_right/_parent）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `T _value = null` | --- 核心字段 --- |
| 字段 | `BinaryNode&lt;T&gt; _left = null` | 字段 _left（类型见签名）。 |
| 字段 | `BinaryNode&lt;T&gt; _right = null` | 字段 _right（类型见签名）。 |
| 字段 | `BinaryNode&lt;T&gt; _parent = null` | 字段 _parent（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(T value)` | 指定值构造 |
| 属性 | `get T value()` | ── 属性 ── |
| 属性 | `set void value(T value)` | 设置 value 的值。 |
| 属性 | `get BinaryNode&lt;T&gt; left()` | 获取 left 的值。 |
| 属性 | `set void left(BinaryNode&lt;T&gt; node)` | 设置 left 的值。 |
| 属性 | `get BinaryNode&lt;T&gt; right()` | 获取 right 的值。 |
| 属性 | `set void right(BinaryNode&lt;T&gt; node)` | 设置 right 的值。 |
| 属性 | `get BinaryNode&lt;T&gt; parent()` | 获取 parent 的值。 |
| 属性 | `get bool isLeaf()` | 获取 isLeaf 的值。 |
| 属性 | `get bool isRoot()` | 获取 isRoot 的值。 |
| 属性 | `get bool hasLeft()` | 获取 hasLeft 的值。 |
| 属性 | `get bool hasRight()` | 获取 hasRight 的值。 |
| 方法 | `bool linkLeft(BinaryNode&lt;T&gt; node)` | ── 挂接/摘除（指针手术在 VM 层完成）── 接到本节点左槽（node 先脱离原父，旧占用者脱离） |
| 方法 | `bool linkRight(BinaryNode&lt;T&gt; node)` | 接到本节点右槽 |
| 方法 | `BinaryNode&lt;T&gt; addLeft(T value)` | 创建带值节点接到左槽，返回新节点 |
| 方法 | `BinaryNode&lt;T&gt; addRight(T value)` | 创建带值节点接到右槽，返回新节点 |
| 方法 | `bool unlink()` | 脱离父节点（保留其子树成独立树），根节点返回 false |
| 方法 | `int count()` | ── 子树算法（全部在 VM 层完成）── 子树节点总数（含自身） |
| 方法 | `int height()` | 子树高度（单节点 1） |
| 方法 | `int depth()` | 节点深度（根 1） |
| 方法 | `BinaryNode&lt;T&gt; find(T value)` | 先序查找第一个 _value 相等节点 |
| 方法 | `int findAll(T value, Array&lt;BinaryNode&lt;T&gt;&gt; arr)` | 先序收集全部 _value 相等节点到 arr（须预分配足够容量），返回实际个数 |
| 方法 | `bool contains(T value)` | 是否包含某值 |
| 方法 | `BinaryNode&lt;T&gt; lca(BinaryNode&lt;T&gt; other)` | 最近公共祖先（不同树返回 null） |
| 方法 | `Array&lt;T&gt; pathFromRoot()` | 从根到本节点的取值路径（本节点值在前） |
| 方法 | `BinaryNode&lt;T&gt; invert()` | 镜像翻转本子树（原地） |
| 方法 | `bool isSymmetric()` | 本子树是否镜像对称 |
| 方法 | `bool isBalanced()` | 本子树是否平衡（任意节点左右高差 &lt;= 1） |
| 方法 | `bool isBst()` | 本子树是否二叉搜索树（中序严格递增） |
| 方法 | `int nodesToArray(int order, Array&lt;BinaryNode&lt;T&gt;&gt; arr)` | ── 遍历（order：0=先序 1=中序 2=后序 3=层序）── 按序填充节点数组（须预分配足够容量），返回实际个数 |
| 方法 | `int valuesToArray(int order, Array&lt;T&gt; arr)` | 按序填充各节点 _value 数组（须预分配足够容量），返回实际个数 |
| 方法 | `Array&lt;T&gt; values(int order)` | 按序取值数组（新数组，长度精确） |
| 方法 | `Array&lt;T&gt; preorderValues()` | 执行 preorderValues()。 |
| 方法 | `Array&lt;T&gt; inorderValues()` | 执行 inorderValues()。 |
| 方法 | `Array&lt;T&gt; postorderValues()` | 执行 postorderValues()。 |
| 方法 | `Array&lt;T&gt; levelOrderValues()` | 执行 levelOrderValues()。 |
| 方法 | `string toString()` | 输出值形式 |

## class `BinaryTree<T>`

- **基类**：Object
- **说明**：二叉树（持有根节点，foreach 按中序迭代 _value）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `BinaryNode&lt;T&gt; _root = null` | --- 核心字段 --- |
| 字段 | `BinaryNode&lt;T&gt; _iterNode = null` | --- 迭代器字段（中序迭代）--- |
| 字段 | `int _index = -1` | 字段 _index（类型见签名）。 |
| 字段 | `T _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(BinaryNode&lt;T&gt; root)` | 以已有节点为根构造（节点先脱离原父） |
| 方法 | `void _init_(T rootValue)` | 创建带值根节点 |
| 属性 | `get BinaryNode&lt;T&gt; root()` | ── 属性 ── |
| 属性 | `set void root(BinaryNode&lt;T&gt; node)` | 设置 root 的值。 |
| 属性 | `get int length()` | 节点总数 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get int height()` | 树高（空树 0） |
| 方法 | `void setRoot(BinaryNode&lt;T&gt; node)` | ── 构建（新节点在 SL 层实例化，挂接在 VM 层完成）── 设根（null 表示清根；节点先脱离原父，迭代器重置） |
| 方法 | `BinaryNode&lt;T&gt; addRoot(T value)` | 创建并设置带值根节点，返回新根 |
| 方法 | `bool linkLeft(BinaryNode&lt;T&gt; parent, BinaryNode&lt;T&gt; node)` | node 接到 parent 左槽 |
| 方法 | `bool linkRight(BinaryNode&lt;T&gt; parent, BinaryNode&lt;T&gt; node)` | node 接到 parent 右槽 |
| 方法 | `BinaryNode&lt;T&gt; addLeft(BinaryNode&lt;T&gt; parent, T value)` | 创建带值节点接到 parent 左槽，返回新节点 |
| 方法 | `BinaryNode&lt;T&gt; addRight(BinaryNode&lt;T&gt; parent, T value)` | 创建带值节点接到 parent 右槽，返回新节点 |
| 方法 | `BinaryNode&lt;T&gt; find(T value)` | ── 算法（委托根节点，全部在 VM 层完成）── 先序查找第一个 _value 相等节点 |
| 方法 | `bool contains(T value)` | 是否包含某值 |
| 方法 | `bool containsSubtree(BinaryNode&lt;T&gt; pattern)` | pattern 是否为本树某先序起点的完全同构同值子树 |
| 方法 | `BinaryNode&lt;T&gt; lca(BinaryNode&lt;T&gt; a, BinaryNode&lt;T&gt; b)` | 最近公共祖先（不同树返回 null） |
| 方法 | `Array&lt;T&gt; pathToNode(BinaryNode&lt;T&gt; target)` | 从根到 target 的取值路径（找不到返回空数组） |
| 方法 | `void invert()` | 镜像翻转整树（原地） |
| 方法 | `bool isSymmetric()` | 是否镜像对称 |
| 方法 | `bool isBalanced()` | 是否平衡（任意节点左右高差 &lt;= 1） |
| 方法 | `bool isBst()` | 是否二叉搜索树（中序严格递增） |
| 方法 | `Array&lt;T&gt; values(int order)` | 按序取值数组（新数组，长度精确） |
| 方法 | `Array&lt;T&gt; preorderValues()` | 执行 preorderValues()。 |
| 方法 | `Array&lt;T&gt; inorderValues()` | 执行 inorderValues()。 |
| 方法 | `Array&lt;T&gt; postorderValues()` | 执行 postorderValues()。 |
| 方法 | `Array&lt;T&gt; levelOrderValues()` | 执行 levelOrderValues()。 |
| 方法 | `void clear()` | ── 删除 ── 清空（置空根并重置迭代器，节点由 GC 回收） |
| 方法 | `void reset()` | ── 迭代器（foreach 热路径，SystemBinaryMoveNext 在 VM 层按中序推进）── |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get T current()` | 获取 current 的值。 |
| 属性 | `get int index()` | 获取 index 的值。 |
| 方法 | `string toString()` | 输出 BinaryTree(a,b,c) 格式（中序取值） |

## class `BinarySearchTree<T>`

- **说明**：二叉搜索树（继承 BinaryTree，插入/查找/删除全部在 VM 层完成） 值须可有序比较（数值按大小、字符串按字典序）；重复值插入返回已存在节点。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `override _init_()` | 执行 _init_()。 |
| 方法 | `void _init_(T rootValue)` | 创建带值根节点 |
| 方法 | `BinaryNode&lt;T&gt; insert(T value)` | 插入值（返回实际落位节点；重复值返回已存在节点，不重复插入） |
| 方法 | `void insertRange(Array&lt;T&gt; values)` | 批量插入 |
| 方法 | `BinaryNode&lt;T&gt; findNode(T value)` | 二分下降查找（未命中返回 null） |
| 方法 | `bool contains(T value)` | 是否包含某值（BST 专用二分下降版） |
| 方法 | `bool remove(T value)` | 删除某值（叶/单孩/双孩三 case：双孩拷中序后继值再删后继） |
| 方法 | `BinaryNode&lt;T&gt; minNode()` | 最小值节点（最左节点） |
| 方法 | `BinaryNode&lt;T&gt; maxNode()` | 最大值节点（最右节点） |
| 方法 | `T min()` | 最小值（空树返回 null） |
| 方法 | `T max()` | 最大值（空树返回 null） |
