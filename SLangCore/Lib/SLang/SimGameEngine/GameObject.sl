# 场景节点：空壳容器 + 组件集合（Unity 式组合优于继承）。
#
# 硬规则（doc/02 §1）：
#   1. 每个 GameObject 必带 Transform（_init_ 自动创建并挂载），不可移除；
#   2. 同类组件只能挂一个（addComponent<T> 按类型去重，已存在返回既有实例）；
#   3. 组件实例不跨节点共享（资源类 Mesh/Material 可共享）。
#
# 继承 Std.Component 的「组件即节点」模型：
#   - inherited parent 字段指向上级 GameObject（组件树与节点树同构）；
#   - getComponent<T>() 等查询直接复用 Std 既有 VM 系统方法；
#   - 子节点另存 _children，与 components（组件）分离。
#
# 激活传播（doc/03 §2.3）：
#   activeInHierarchy = activeSelf && 祖先链全 activeSelf；
#   禁用祖先不改子节点 activeSelf；setActive 状态翻转时对子树触发
#   onEnable/onDisable（仅 isEnabled=true 的 Behaviour）。
import Std;
import Math;
import SLangRender;
public class GameObject extends Component
{
    # 节点变换（创建即有，禁止移除）
    public Transform transform = null
    # 自身激活开关；实际可见/可更新看 getActiveInHierarchy()
    public bool activeSelf = true
    # 渲染层 0..31，与相机 cullMask 位对应
    public Int32 layer = 0
    # 延迟销毁标记（destroy() 置位，Scene.processDestroys() 帧尾收口）
    public bool pendingDestroy = false
    # C99 节点注册表 id（Scene.createObject 注册；destroy 注销；0 = 未注册）
    public Int64 nodeId = 0

    List<GameObject> _children = null
    Scene _scene = null

    # ── 构造 ─────────────────────────────────────────────
    public void _init_()
    {
        this.parent = null
        this.components = List<Component>(8)
        this.name = "GameObject"
        this.tag = "Untagged"
        this.transform = Transform()
        # 统一版 Transform（SLangRender，2026-11-17 合并）：层级经
        # transform.parentNode（Transform 级父链）由宿主在各层级变更点同步；
        # Component 树 parent（组件挂载关系）照旧指向本 GameObject。
        this.transform.parent = this
        this.components.add( this.transform )
        this.activeSelf = true
        this.layer = 0
        this.pendingDestroy = false
        this._children = List<GameObject>(8)
        this._scene = null
    }

    public void _init_( string _name )
    {
        this.parent = null
        this.components = List<Component>(8)
        this.name = _name
        this.tag = "Untagged"
        this.transform = Transform()
        # 统一版 Transform（SLangRender，2026-11-17 合并）：层级经
        # transform.parentNode（Transform 级父链）由宿主在各层级变更点同步；
        # Component 树 parent（组件挂载关系）照旧指向本 GameObject。
        this.transform.parent = this
        this.components.add( this.transform )
        this.activeSelf = true
        this.layer = 0
        this.pendingDestroy = false
        this._children = List<GameObject>(8)
        this._scene = null
    }

    # ── 工厂 ─────────────────────────────────────────────
    # 独立节点（不属于任何场景）；需要进场景用 Scene.createObject
    public static GameObject create( string name )
    {
        GameObject go = GameObject()
        go.name = name
        ret go
    }

    # ── 父子层级 ─────────────────────────────────────────
    # 上级节点（根节点为 null）
    public GameObject getParent()
    {
        if this.parent == null
        {
            ret null
        }
        ret this.parent as GameObject
    }

    public get Int32 childCount()
    {
        ret this._children.length
    }

    public GameObject getChild( Int32 index )
    {
        if index < 0 || index >= this._children.length
        {
            ret null
        }
        ret this._children[index]
    }

    # 直接子节点快照（数组拷贝，遍历安全）
    public Array<GameObject> children()
    {
        ret this._children.toArray()
    }

    # 改挂父节点；null = 移到根。保持 local 变换不变（世界位置会变）。
    # 环检测：禁止把祖先/自身挂到自己子孙下。返回是否成功。
    public bool setParent( GameObject newParent )
    {
        if newParent == null
        {
            ret this._detachToRoot()
        }
        if newParent == this
        {
            ret false
        }
        # 环检测：newParent 的祖先链里不允许出现 this
        GameObject walker = newParent
        while walker != null
        {
            if walker == this
            {
                ret false
            }
            walker = walker.getParent()
        }

        # 激活态快照（改挂可能改变 activeInHierarchy）
        bool wasActive = this.getActiveInHierarchy()

        # 摘除旧位置（indexOf + removeAt，见 _detachToRoot 注记）
        GameObject oldParent = this.getParent()
        if oldParent != null
        {
            Int32 oldIdx = oldParent._children.indexOf( this )
            if oldIdx >= 0
            {
                oldParent._children.removeAt( oldIdx )
            }
        }
        elif this._scene != null
        {
            this._scene.removeRoot( this )
        }

        # 挂到新父
        this.parent = newParent
        newParent._children.add( this )
        # Transform 层级同步（统一版 Transform 走 parentNode 世界累乘链）
        this.transform.parentNode = newParent.transform
        if this._scene == null
        {
            this._scene = newParent._scene
        }

        # 激活态结算（onEnable/onDisable 子树触发）
        bool nowActive = this.getActiveInHierarchy()
        if wasActive != nowActive
        {
            this._settleActivation( nowActive )
        }
        ret true
    }

    # ── 组件容器 ─────────────────────────────────────────
    # 挂载组件（覆盖 Std.Component.addComponent 增加引擎语义）：
    #   - 同类组件唯一：已存在同类型组件则忽略本次挂载（doc/02 硬规则 2）；
    #   - Behaviour 立即 awake()，激活态下补发 onEnable()；
    #   - 挂载期其它组件可能尚未挂载，跨组件查找放 start()。
    # 用法：go.addComponent( Probe() )
    # 注：方法级泛型构造 `T()`（addComponent<T>() 形态）会触发编译器
    #     ParseStatements 空引用崩溃（MetaCallLink.AddVisitNodeList），已登记
    #     未解决问题，此处改用「调用方构造 + 引擎去重挂载」形态。
    public void addComponent( Component comp )
    {
        if comp == null
        {
            ret
        }
        string tname = comp.type.toString()
        Int32 i = 0
        Int32 n = this.components.length
        while i < n
        {
            Component c = this.components[i]
            if c != null && c.type.toString() == tname
            {
                ret
            }
            i = i + 1
        }
        comp.parent = this
        this.components.add( comp )
        Behaviour b = comp as Behaviour
        if b != null
        {
            b.owner = this
            # 钩子走 C VM 按名派发（跨模块 slb 基类 CallVirt 不派发消费方 override）
            SystemSimEngineCallHook( b, "awake" )
            if this.getActiveInHierarchy()
            {
                SystemSimEngineCallHook( b, "onEnable" )
            }
        }
    }

    # ── 组件枚举（跨模块消费入口；components 是字段，跨模块字段链
    # （go.components.length / [i]）会崩 ParseStatements——必须走方法）──
    public Int32 componentCount()
    {
        ret this.components.length
    }

    public Component componentAt( Int32 index )
    {
        if index < 0 || index >= this.components.length
        {
            ret null
        }
        ret this.components[index]
    }

    # 移除组件（Transform 不可移除）；Behaviour 走 onDisable + dispose
    public bool removeComponent<T>()
    {
        Component c = this.getComponent<T>()
        if c == null
        {
            ret false
        }
        Component tcomp = this.transform
        if c == tcomp
        {
            ret false
        }
        Behaviour b = c as Behaviour
        if b != null
        {
            bool en = SystemSimEngineGetEnabled( b )
            if en
            {
                SystemSimEngineCallHook( b, "onDisable" )
            }
            SystemSimEngineCallHook( b, "dispose" )
        }
        Int32 idx = this.components.indexOf( c )
        if idx >= 0
        {
            this.components.removeAt( idx )
        }
        ret true
    }

    # ── 激活控制 ─────────────────────────────────────────
    public bool getActiveInHierarchy()
    {
        if !this.activeSelf
        {
            ret false
        }
        GameObject pgo = this.getParent()
        if pgo == null
        {
            ret true
        }
        ret pgo.getActiveInHierarchy()
    }

    # 切换 activeSelf；activeInHierarchy 翻转时子树触发 onEnable/onDisable
    public void setActive( bool value )
    {
        if this.activeSelf == value
        {
            ret
        }
        bool wasActive = this.getActiveInHierarchy()
        this.activeSelf = value
        # C99 节点注册表活跃标志同步（注册过的节点）
        if this.nodeId > 0
        {
            NodeRegistry.setActive( this.nodeId, value )
        }
        bool nowActive = this.getActiveInHierarchy()
        if wasActive != nowActive
        {
            this._settleActivation( nowActive )
        }
    }

    # ── 查找 ─────────────────────────────────────────────
    # 相对路径查找 "Child/Leaf"；空串/找不到返回 null
    public GameObject find( string path )
    {
        if path == null || path.length == 0
        {
            ret null
        }
        List<string> segs = Scene.splitPath( path )
        GameObject cur = this
        Int32 i = 0
        while i < segs.length
        {
            string seg = segs[i]
            GameObject matched = null
            Int32 j = 0
            Int32 n = cur.childCount
            while j < n
            {
                GameObject child = cur.getChild( j )
                if child != null && child.name == seg
                {
                    matched = child
                    j = n
                }
                j = j + 1
            }
            if matched == null
            {
                ret null
            }
            cur = matched
            i = i + 1
        }
        ret cur
    }

    # ── 销毁 ─────────────────────────────────────────────
    # 延迟销毁：标记 pendingDestroy + 立即 onDisable；本帧仍可安全读节点，
    # 帧尾由 Scene.processDestroys() 统一 dispose/摘除（doc/02 §5）。
    public void destroy()
    {
        if this.pendingDestroy
        {
            ret
        }
        this.pendingDestroy = true
        # C99 节点注册表：注销（立即；后续帧注册表查询不再命中）
        if this.nodeId > 0
        {
            NodeRegistry.unregister( this.nodeId )
            this.nodeId = 0
        }
        if this.getActiveInHierarchy()
        {
            this._settleActivation( false )
        }
        if this._scene != null
        {
            this._scene.registerDestroy( this )
        }
    }

    # ── 内部 ─────────────────────────────────────────────
    # 从当前位置摘除并挂回场景根（无场景则孤立）；不触发激活钩子。
    # 摘除用 indexOf + removeAt（List.remove 的 C 侧值比较对跨模块基类
    # 派生对象不可靠，见 doc/10 §6）
    bool _detachToRoot()
    {
        GameObject oldParent = this.getParent()
        if oldParent != null
        {
            Int32 idx = oldParent._children.indexOf( this )
            if idx >= 0
            {
                oldParent._children.removeAt( idx )
            }
        }
        elif this._scene != null
        {
            this._scene.removeRoot( this )
        }
        this.parent = null
        this.transform.parentNode = null
        # doc/03：setParent(null) = 移到根 —— 有场景归属则挂回根列表
        if this._scene != null
        {
            this._scene.addRoot( this )
        }
        ret true
    }

    # 子树激活结算：父先子后触发 onEnable/onDisable（父序即遍历序）
    void _settleActivation( bool nowActive )
    {
        Int32 i = 0
        Int32 n = this.components.length
        while i < n
        {
            Component c = this.components[i]
            Behaviour b = c as Behaviour
            if b != null
            {
                bool en = SystemSimEngineGetEnabled( b )
                if en
                {
                    if nowActive
                    {
                        SystemSimEngineCallHook( b, "onEnable" )
                    }
                    else
                    {
                        SystemSimEngineCallHook( b, "onDisable" )
                    }
                }
            }
            i = i + 1
        }
        Int32 j = 0
        Int32 m = this._children.length
        while j < m
        {
            GameObject child = this._children[j]
            if child != null && child.activeSelf && !child.pendingDestroy
            {
                child._settleActivation( nowActive )
            }
            j = j + 1
        }
    }

    # 深度优先父先子后收集全部 Behaviour（Application 帧序遍历用）
    void _collectBehaviours( List<Behaviour> outList )
    {
        Int32 i = 0
        Int32 n = this.components.length
        while i < n
        {
            Component c = this.components[i]
            Behaviour b = c as Behaviour
            if b != null
            {
                outList.add( b )
            }
            i = i + 1
        }
        Int32 j = 0
        Int32 m = this._children.length
        while j < m
        {
            GameObject child = this._children[j]
            if child != null
            {
                child._collectBehaviours( outList )
            }
            j = j + 1
        }
    }

    # 深度优先父先子后收集全部节点（含自身）
    void _collectNodes( List<GameObject> outList )
    {
        outList.add( this )
        Int32 j = 0
        Int32 m = this._children.length
        while j < m
        {
            GameObject child = this._children[j]
            if child != null
            {
                child._collectNodes( outList )
            }
            j = j + 1
        }
    }

    # 帧尾销毁收口：组件 dispose -> 摘除（返回是否已处理）
    bool _disposeNow()
    {
        Int32 i = 0
        Int32 n = this.components.length
        while i < n
        {
            Component c = this.components[i]
            Behaviour b = c as Behaviour
            if b != null
            {
                SystemSimEngineCallHook( b, "dispose" )
            }
            i = i + 1
        }
        this.components.clear()
        GameObject pgo = this.getParent()
        if pgo != null
        {
            Int32 idx = pgo._children.indexOf( this )
            if idx >= 0
            {
                pgo._children.removeAt( idx )
            }
        }
        elif this._scene != null
        {
            this._scene.removeRoot( this )
        }
        this.parent = null
        this.transform.parentNode = null
        ret true
    }

    override string toString()
    {
        ret String.toFormat( "GameObject(name={0}, children={1}, active={2}, layer={3})",
            this.name, this.childCount.toString(),
            this.activeSelf.toString(), this.layer.toString() )
    }
}
