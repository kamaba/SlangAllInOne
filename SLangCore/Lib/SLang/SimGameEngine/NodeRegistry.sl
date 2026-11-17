import Core;
import Std;

# ============================================================================
# NodeRegistry — 节点注册表封装（C99 哈希按名查找，doc/11 §3.1 远期项落地）
# ----------------------------------------------------------------------------
# GameObject 在 Scene.createObject 时向 C 侧注册（id 存 nodeId 字段），
# destroy 时注销；Scene.find 经 C 哈希 O(1) 查 id 后按 nodeId 匹配。
# 注意：name 快照在注册时拷贝（改名不自动同步——调 rebind）；
# tag/layer 注册时快照（setLayer 走 syncLayer）。
# ============================================================================

public class NodeRegistry
{
    public static Int32 count()
    {
        ret EngineFfi.libNodeCount()
    }

    # 注册节点（name 空返回 0；同名重复注册拒绝返回 0）
    public static Int64 registerNode( string name, string tag, Int32 layer )
    {
        ret EngineFfi.libNodeRegister( name, tag, layer )
    }

    public static bool unregister( Int64 id )
    {
        ret EngineFfi.libNodeUnregister( id ) == 1
    }

    # O(1) 哈希按名查 id；未找到 0
    public static Int64 findByName( string name )
    {
        ret EngineFfi.libNodeFindByName( name )
    }

    # 节点名读回（id 无效返回 ""；C 直返 utf8 指针，VM 拷贝为 SL string）
    public static string nameOf( Int64 id )
    {
        ret EngineFfi.libNodeName( id )
    }

    public static bool setLayer( Int64 id, Int32 layer )
    {
        ret EngineFfi.libNodeSetLayer( id, layer ) == 1
    }

    public static bool setActive( Int64 id, bool active )
    {
        Int32 v = 0
        if active
        {
            v = 1
        }
        ret EngineFfi.libNodeSetActive( id, v ) == 1
    }

    public static bool isActive( Int64 id )
    {
        ret EngineFfi.libNodeActive( id ) == 1
    }
}
