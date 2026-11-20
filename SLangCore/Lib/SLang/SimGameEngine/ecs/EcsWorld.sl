import Core;
import Std;

# ============================================================================
# EcsWorld — ECS 世界（doc/20 §2/§4）
# ----------------------------------------------------------------------------
# 单一职责三件套：
#   1) 实体注册表（GameObject 保留 Transform/层级，渲染数据从节点拔离到本世界）；
#   2) 数据仓（EcsData 按实体 + 类型标签集中存放）；
#   3) 分层合并（复用 Batcher 的键排序/聚组，产出 EcsLayer 交 RenderSystem 提交）。
# 逻辑由 logic（EcsLogicSystem）集中跑；本类只做编排，不做逐节点钩子派发。
# active 静态指针 = 当前世界，供 GameObject.addComponent 在 ECS 模式下自动路由。
# ============================================================================

public class EcsWorld
{
    public static EcsWorld active = null

    public EcsLogicSystem logic = EcsLogicSystem()
    public Batcher layerBatcher = Batcher()
    public Int32 cullMask = 0x7FFFFFFF
    public Int32 lastLayerCount = 0
    public Int32 lastMergedCount = 0

    List<GameObject> _entities = List<GameObject>( 32 )
    List<MeshRef> _meshes = List<MeshRef>( 32 )
    List<MaterialRef> _materials = List<MaterialRef>( 32 )
    List<GameObject> _dataOwners = List<GameObject>( 32 )
    List<string> _dataKinds = List<string>( 32 )
    List<EcsData> _dataVals = List<EcsData>( 32 )

    # 挂到 Application：自动填 app.ecsWorld 并置为当前世界
    public void attach( Application app )
    {
        if app == null
        {
            ret
        }
        app.ecsWorld = this
        EcsWorld.active = this
    }

    public void detach()
    {
        if EcsWorld.active == this
        {
            EcsWorld.active = null
        }
    }

    # ── 实体 ─────────────────────────────────────────────
    public Int32 entityCount()
    {
        ret this._entities.length
    }

    public GameObject entityAt( Int32 idx )
    {
        if idx < 0 || idx >= this._entities.length
        {
            ret null
        }
        ret this._entities[idx]
    }

    Int32 indexOf( GameObject go )
    {
        if go == null
        {
            ret 0 - 1
        }
        ret this._entities.indexOf( go )
    }

    # 注册实体：把节点上已有的 MeshRef / MaterialRef 拔离到本世界
    public bool register( GameObject go )
    {
        if go == null
        {
            ret false
        }
        Int32 old = this.indexOf( go )
        if old >= 0
        {
            ret true
        }
        go.useEcs = true
        go.ecsWorld = this
        this._entities.add( go )
        MeshRef mesh = null
        MaterialRef mat = null
        Int32 i = go.componentCount() - 1
        while i > 0 - 1
        {
            Component c = go.componentAt( i )
            MeshRef m = c as MeshRef
            MaterialRef mr = c as MaterialRef
            if m != null
            {
                mesh = m
            }
            if mr != null
            {
                mat = mr
            }
            if m != null || mr != null
            {
                go.components.removeAt( i )
                m.parent = go
                mr.parent = go
            }
            i = i - 1
        }
        this._meshes.add( mesh )
        this._materials.add( mat )
        ret true
    }

    # 注销：渲染数据归还节点（未挂载过的保持 null）
    public bool unregister( GameObject go )
    {
        Int32 idx = this.indexOf( go )
        if idx < 0
        {
            ret false
        }
        MeshRef mesh = this._meshes[idx]
        MaterialRef mat = this._materials[idx]
        if mesh != null
        {
            go.components.add( mesh )
            mesh.parent = go
        }
        if mat != null
        {
            go.components.add( mat )
            mat.parent = go
        }
        this._entities.removeAt( idx )
        this._meshes.removeAt( idx )
        this._materials.removeAt( idx )
        go.useEcs = false
        go.ecsWorld = null
        Int32 i = this._dataOwners.length - 1
        while i > 0 - 1
        {
            GameObject owner = this._dataOwners[i]
            if owner == go
            {
                this._dataOwners.removeAt( i )
                this._dataKinds.removeAt( i )
                this._dataVals.removeAt( i )
            }
            i = i - 1
        }
        ret true
    }

    public void clear()
    {
        this.logic.clear()
        this._entities.clear()
        this._meshes.clear()
        this._materials.clear()
        this._dataOwners.clear()
        this._dataKinds.clear()
        this._dataVals.clear()
        this.layerBatcher.clear()
        this.lastLayerCount = 0
        this.lastMergedCount = 0
        this.detach()
    }

    # ── 渲染数据（拔离后由世界持有）──────────────────────
    public void setRenderData( GameObject go, MeshRef mesh, MaterialRef mat )
    {
        this.register( go )
        Int32 idx = this.indexOf( go )
        if mesh != null
        {
            this._meshes[idx] = mesh
            mesh.parent = go
        }
        if mat != null
        {
            this._materials[idx] = mat
            mat.parent = go
        }
    }

    public MeshRef meshOf( GameObject go )
    {
        Int32 idx = this.indexOf( go )
        if idx < 0
        {
            ret null
        }
        ret this._meshes[idx]
    }

    public MaterialRef materialOf( GameObject go )
    {
        Int32 idx = this.indexOf( go )
        if idx < 0
        {
            ret null
        }
        ret this._materials[idx]
    }

    # ── 数据仓（按实体 + 类型标签）──────────────────────
    public void addData( GameObject go, EcsData value )
    {
        if value == null
        {
            ret
        }
        this.register( go )
        string kindName = value.kind
        if kindName.length == 0 || kindName == "EcsData"
        {
            kindName = value.type.toString()
        }
        value.kind = kindName
        value.attachTo( go )
        Int32 i = 0
        Int32 n = this._dataOwners.length
        while i < n
        {
            GameObject owner = this._dataOwners[i]
            string oldKind = this._dataKinds[i]
            if owner == go && oldKind == kindName
            {
                this._dataVals[i] = value
                ret
            }
            i = i + 1
        }
        this._dataOwners.add( go )
        this._dataKinds.add( kindName )
        this._dataVals.add( value )
    }

    public EcsData dataOf( GameObject go, string typeName )
    {
        Int32 i = 0
        Int32 n = this._dataOwners.length
        while i < n
        {
            GameObject owner = this._dataOwners[i]
            string kindName = this._dataKinds[i]
            if owner == go && kindName == typeName
            {
                ret this._dataVals[i]
            }
            i = i + 1
        }
        ret null
    }

    public Int32 dataCount( GameObject go )
    {
        Int32 count = 0
        Int32 i = 0
        Int32 n = this._dataOwners.length
        while i < n
        {
            GameObject owner = this._dataOwners[i]
            if owner == go
            {
                count = count + 1
            }
            i = i + 1
        }
        ret count
    }

    # ── 逻辑集中调度 ─────────────────────────────────────
    public void addLogic( EcsLogic item, GameObject go )
    {
        if item == null
        {
            ret
        }
        this.register( go )
        this.logic.add( item, go )
    }

    public void fixedLogic()
    {
        this.logic.fixedUpdate()
    }

    public void updateLogic( Float32 dt )
    {
        this.logic.update( dt )
    }

    public void lateLogic( Float32 dt )
    {
        this.logic.lateUpdate( dt )
    }

    # ── 自动分层 + 合并（逻辑跑完、变换刷新后调用）───────
    public Int32 buildLayers()
    {
        this.layerBatcher.collectEcs( this, this.cullMask )
        this.layerBatcher.build()
        this.lastLayerCount = this.layerBatcher.groupCount()
        Int32 merged = 0
        Int32 i = 0
        while i < this.lastLayerCount
        {
            EcsLayer layer = this.layerAt( i )
            if layer != null
            {
                merged = merged + layer.mergedCount
            }
            i = i + 1
        }
        this.lastMergedCount = merged
        ret this.lastLayerCount
    }

    public Int32 layerCount()
    {
        ret this.lastLayerCount
    }

    public EcsLayer layerAt( Int32 idx )
    {
        BatchGroup g = this.layerBatcher.groupAt( idx )
        ret g as EcsLayer
    }
}
