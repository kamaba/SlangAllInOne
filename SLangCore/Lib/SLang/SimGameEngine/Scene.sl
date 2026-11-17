# 场景：树根容器 + 按名查找 + 帧序遍历 + 延迟销毁收口。
#
# 职责（doc/03 §1）：
#   - 持有根节点列表（_roots），createObject 建节点并挂树；
#   - find 按路径 "Root/Child/Leaf" 查找，findAllByTag/Layer 批量查找；
#   - updateTransforms 显式刷新变换链（世界矩阵读侧即时，本方法为
#     一致性/预热入口）；
#   - destroy 只登记 pendingDestroys，processDestroys（Application 帧尾
#     或调用方手动）统一 dispose + 摘除 —— doc/02 §5 延迟回收契约。
#
# 多场景：同一时刻允许多个 Scene，只有被 Application 激活的参与帧循环。
import Std;
import Math;
import SLangRender;
public class Scene
{
    public string name = "Scene"

    List<GameObject> _roots = null
    List<GameObject> _pendingDestroys = null

    # ── 构造 ─────────────────────────────────────────────
    public void _init_()
    {
        this.name = "Scene"
        this._roots = List<GameObject>(16)
        this._pendingDestroys = List<GameObject>(8)
    }

    public void _init_( string sceneName )
    {
        this.name = sceneName
        this._roots = List<GameObject>(16)
        this._pendingDestroys = List<GameObject>(8)
    }

    # ── 根节点 ───────────────────────────────────────────
    public Array<GameObject> roots()
    {
        ret this._roots.toArray()
    }

    public get Int32 rootCount()
    {
        ret this._roots.length
    }

    public GameObject getRoot( Int32 index )
    {
        if index < 0 || index >= this._roots.length
        {
            ret null
        }
        ret this._roots[index]
    }

    bool _hasRoot( GameObject go )
    {
        ret this._roots.indexOf( go ) >= 0
    }

    # ── 创建 ─────────────────────────────────────────────
    # 建节点挂到根（name 快照注册进 C99 节点注册表——O(1) 哈希按名查）
    public GameObject createObject( string objName )
    {
        GameObject go = GameObject()
        go.name = objName
        go._scene = this
        this._roots.add( go )
        Int64 rid = NodeRegistry.registerNode( objName, "", 0 )
        if rid > 0
        {
            go.nodeId = rid
        }
        ret go
    }

    # 建节点挂到 parent（parent 为 null 时挂根）
    public GameObject createObject( string objName, GameObject parent )
    {
        if parent == null
        {
            ret this.createObject( objName )
        }
        GameObject go = GameObject()
        go.name = objName
        if parent._scene != null
        {
            go._scene = parent._scene
        }
        else
        {
            go._scene = this
        }
        go.parent = parent
        parent._children.add( go )
        # Transform 层级同步（统一版 Transform 走 parentNode 世界累乘链）
        go.transform.parentNode = parent.transform
        Int64 rid = NodeRegistry.registerNode( objName, "", 0 )
        if rid > 0
        {
            go.nodeId = rid
        }
        ret go
    }

    # ── 路径工具 ─────────────────────────────────────────
    # 按 '/' 切分路径（Core.String 无 split，用 slice 扫描实现）
    public static List<string> splitPath( string path )
    {
        List<string> parts = List<string>(4)
        if path == null || path.length == 0
        {
            ret parts
        }
        Int32 start = 0
        Int32 i = 0
        Int32 n = path.length
        while i < n
        {
            string ch = path.slice( i, i + 1 )
            if ch == "/"
            {
                if i > start
                {
                    parts.add( path.slice( start, i ) )
                }
                start = i + 1
            }
            i = i + 1
        }
        if n > start
        {
            parts.add( path.slice( start, n ) )
        }
        ret parts
    }

    # 按 C 注册表 id 找节点（显式栈遍历——不用递归，doc/10 §6）
    GameObject findByNodeId( Int64 targetId )
    {
        List<GameObject> stack = List<GameObject>( 16 )
        Int32 ri = this._roots.length - 1
        while ri > 0 - 1
        {
            stack.add( this._roots[ri] )
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            if cur == null
            {
                continue
            }
            if cur.nodeId == targetId
            {
                ret cur
            }
            Int32 ci = cur.childCount - 1
            while ci > 0 - 1
            {
                GameObject ch = cur.getChild( ci )
                if ch != null
                {
                    stack.add( ch )
                }
                ci = ci - 1
            }
        }
        ret null
    }


    # ── 查找 ─────────────────────────────────────────────
    # 全局路径查找 "Root/Child/Leaf"（首段在根节点中匹配）。
    # 裸名单段：先走 C99 注册表哈希查 id（O(1)），命中再按 nodeId 遍历
    # 比对（doc/11 §3.1 空间网格远期项的前置能力）
    public GameObject find( string path )
    {
        if path == null || path.length == 0
        {
            ret null
        }
        List<string> segs = Scene.splitPath( path )
        if segs.length == 0
        {
            ret null
        }
        if segs.length == 1
        {
            Int64 nid = NodeRegistry.findByName( segs[0] )
            if nid > 0
            {
                GameObject hit = this.findByNodeId( nid )
                if hit != null
                {
                    ret hit
                }
            }
            # C 哈希 miss 或命中其他场景同名节点（注册表全局唯一，跨场景
            # 重名时本场景节点 nodeId=0 不入表）→ 回退本场景树内按名查找
        }
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null && root.name == segs[0]
            {
                if segs.length == 1
                {
                    ret root
                }
                # 剩余段转相对路径下探（同模块内部拼串，无跨模块坑）
                string rest = segs[1]
                Int32 k = 2
                while k < segs.length
                {
                    rest = rest + "/" + segs[k]
                    k = k + 1
                }
                ret root.find( rest )
            }
            i = i + 1
        }
        ret null
    }

    # 深度优先收集 tag 匹配节点（含根）
    public Array<GameObject> findAllByTag( string tag )
    {
        List<GameObject> outList = List<GameObject>(8)
        this._collectByTag( tag, outList )
        ret outList.toArray()
    }

    void _collectByTag( string tag, List<GameObject> outList )
    {
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null
            {
                this._collectByTagWalk( root, tag, outList )
            }
            i = i + 1
        }
    }

    void _collectByTagWalk( GameObject go, string tag, List<GameObject> outList )
    {
        if go.tag == tag
        {
            outList.add( go )
        }
        Int32 j = 0
        Int32 m = go.childCount
        while j < m
        {
            GameObject child = go.getChild( j )
            if child != null
            {
                this._collectByTagWalk( child, tag, outList )
            }
            j = j + 1
        }
    }

    # 深度优先收集 layer 匹配节点（含根）
    public Array<GameObject> findAllByLayer( Int32 layer )
    {
        List<GameObject> outList = List<GameObject>(8)
        this._collectByLayer( layer, outList )
        ret outList.toArray()
    }

    void _collectByLayer( Int32 layer, List<GameObject> outList )
    {
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null
            {
                this._collectByLayerWalk( root, layer, outList )
            }
            i = i + 1
        }
    }

    void _collectByLayerWalk( GameObject go, Int32 layer, List<GameObject> outList )
    {
        if go.layer == layer
        {
            outList.add( go )
        }
        Int32 j = 0
        Int32 m = go.childCount
        while j < m
        {
            GameObject child = go.getChild( j )
            if child != null
            {
                this._collectByLayerWalk( child, layer, outList )
            }
            j = j + 1
        }
    }

    # ── 销毁 ─────────────────────────────────────────────
    # 登记延迟销毁；帧尾 processDestroys() 统一收口
    public void destroy( GameObject go )
    {
        if go == null
        {
            ret
        }
        go.destroy()
    }

    # Application 内部/帧尾调用：dispose 全部待销毁节点并摘树
    public void registerDestroy( GameObject go )
    {
        if go == null
        {
            ret
        }
        if this._pendingDestroys.indexOf( go ) < 0
        {
            this._pendingDestroys.add( go )
        }
    }

    # 帧尾收口：dispose -> 摘树 -> 清登记
    public void processDestroys()
    {
        Int32 i = 0
        Int32 n = this._pendingDestroys.length
        while i < n
        {
            GameObject go = this._pendingDestroys[i]
            if go != null && go.pendingDestroy
            {
                this._disposeSubtree( go )
            }
            i = i + 1
        }
        this._pendingDestroys.clear()
    }

    void _disposeSubtree( GameObject go )
    {
        Int32 j = 0
        Int32 m = go.childCount
        while j < m
        {
            GameObject child = go.getChild( j )
            if child != null
            {
                this._disposeSubtree( child )
            }
            j = j + 1
        }
        go._disposeNow()
    }

    # ── 帧序辅助 ─────────────────────────────────────────
    # 变换刷新一致性入口：自顶向下预热整棵树的 local/world 矩阵链。
    # 世界矩阵读侧即时（无陈旧值问题），本方法用于显式批量刷新。
    public void updateTransforms()
    {
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null && root.transform != null
            {
                root.transform.worldMatrix()
            }
            i = i + 1
        }
    }

    # 深度优先父先子后收集全部 Behaviour（Application 帧序用）
    public void collectBehaviours( List<Behaviour> outList )
    {
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null
            {
                root._collectBehaviours( outList )
            }
            i = i + 1
        }
    }

    # 深度优先父先子后收集全部节点
    public void collectNodes( List<GameObject> outList )
    {
        Int32 i = 0
        Int32 n = this._roots.length
        while i < n
        {
            GameObject root = this._roots[i]
            if root != null
            {
                root._collectNodes( outList )
            }
            i = i + 1
        }
    }

    # ── 内部（GameObject 摘挂用）─────────────────────────
    bool removeRoot( GameObject go )
    {
        Int32 idx = this._roots.indexOf( go )
        if idx >= 0
        {
            this._roots.removeAt( idx )
            ret true
        }
        ret false
    }

    bool addRoot( GameObject go )
    {
        if this._roots.indexOf( go ) >= 0
        {
            ret false
        }
        go._scene = this
        this._roots.add( go )
        ret true
    }

    override string toString()
    {
        ret String.toFormat( "Scene(name={0}, roots={1}, pending={2})",
            this.name, this.rootCount.toString(),
            this._pendingDestroys.length.toString() )
    }
}
