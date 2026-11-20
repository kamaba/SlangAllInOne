import Core;
import Std;
import Math;

# ============================================================================
# GizmoSystem — 编辑器 Gizmo 状态机 + 场景提交（doc/21）
# ----------------------------------------------------------------------------
# 六色槽（X/Y/Z/中性/相机/光）各持一个持久 GameObject(MeshRef+MaterialRef)，
# 由 GizmoGeometry 每帧填充模型空间三角形顶点，再经 MeshRef.setVertices
# 走 Batcher/sync 既有烘焙路径渲染——零 C 改动、零新渲染 API。
#
# 用法（消费方每帧）：
#   gs.beginFrame()
#   gs.drawTransform( selectedWorldPos )   # 按 mode 画 move/rotate/scale
#   gs.drawCamera( camPos, is2D )
#   gs.drawLight( lightPos, lightType, is2D )
#   gs.endFrame()                          # setVertices 写回六色 MeshRef
#   rs.sync( scene )
#
# 约束：跨模块对象字段只在 attach（收集上下文）读；draw/endFrame 只消费
# 本类字段与 GizmoGeometry 纯函数（doc/10 §6）。attach 之外的裸对象不持有。
# ============================================================================
public class GizmoSystem
{
    public Int32 mode = GizmoTypes.MODE_MOVE
    public bool enabled = true
    public Float32 size = 1.2f

    Scene _scene = null
    # 六色顶点缓冲（本类字段，draw 阶段只写本模块容器）
    List<Float32_3> _xV = List<Float32_3>( 0 )
    List<Float32_3> _yV = List<Float32_3>( 0 )
    List<Float32_3> _zV = List<Float32_3>( 0 )
    List<Float32_3> _nV = List<Float32_3>( 0 )
    List<Float32_3> _cV = List<Float32_3>( 0 )
    List<Float32_3> _lV = List<Float32_3>( 0 )
    # 六色 MeshRef（单对象字段，非 List——跨模块对象入 List 会污染字段）
    MeshRef _xM = null
    MeshRef _yM = null
    MeshRef _zM = null
    MeshRef _nM = null
    MeshRef _cM = null
    MeshRef _lM = null

    # ── 场景节点惰性绑定（切场景/首次 attach 时重建引用）──
    public void attach( Scene scene )
    {
        if scene == null
        {
            ret
        }
        if this._scene == scene && this._xM != null
        {
            ret
        }
        this._scene = scene
        this._xM = GizmoSystem.makeNode( scene, "__Gizmo_X", GizmoTypes.colorX() )
        this._yM = GizmoSystem.makeNode( scene, "__Gizmo_Y", GizmoTypes.colorY() )
        this._zM = GizmoSystem.makeNode( scene, "__Gizmo_Z", GizmoTypes.colorZ() )
        this._nM = GizmoSystem.makeNode( scene, "__Gizmo_N", GizmoTypes.colorNeutral() )
        this._cM = GizmoSystem.makeNode( scene, "__Gizmo_Cam", GizmoTypes.colorCamera() )
        this._lM = GizmoSystem.makeNode( scene, "__Gizmo_Light", GizmoTypes.colorLight() )
    }

    static MeshRef makeNode( Scene scene, string name, Float32_3 color )
    {
        GameObject go = scene.createObject( name )
        MeshRef mr = MeshRef.create( 0 )
        go.addComponent( mr )
        MaterialData mat = MaterialData.create( name + "_mat" )
        mat.color = color
        MaterialRef mref = MaterialRef.create( mat )
        go.addComponent( mref )
        ret mr
    }

    # ── 帧生命周期 ───────────────────────────────────────
    public void beginFrame()
    {
        this._xV.clear()
        this._yV.clear()
        this._zV.clear()
        this._nV.clear()
        this._cV.clear()
        this._lV.clear()
    }

    public void setMode( Int32 m )
    {
        if m < GizmoTypes.MODE_NONE || m > GizmoTypes.MODE_SCALE
        {
            ret
        }
        this.mode = m
    }

    # 变换柄：按 mode 生成三色几何
    public void drawTransform( Float32_3 center )
    {
        if !this.enabled || this.mode == GizmoTypes.MODE_NONE
        {
            ret
        }
        Float32 sz = this.size
        GizmoGeometry.transformGizmo( this._xV, this._yV, this._zV,
            center, this.mode, sz )
    }

    # 相机图标（2D/3D 形象）
    public void drawCamera( Float32_3 center, bool is2D )
    {
        if !this.enabled
        {
            ret
        }
        Int32 it = GizmoTypes.ICON_CAMERA_3D
        if is2D
        {
            it = GizmoTypes.ICON_CAMERA_2D
        }
        Float32 sz = this.size
        GizmoGeometry.icon( this._cV, it, center, sz, GizmoTypes.LIGHT_DIRECTIONAL )
    }

    # 光照图标（按 Light 子类型取太阳/点光/聚光）
    public void drawLight( Float32_3 center, Int32 lightType, bool is2D )
    {
        if !this.enabled
        {
            ret
        }
        Int32 it = GizmoTypes.ICON_LIGHT_DIR
        if lightType == GizmoTypes.LIGHT_POINT
        {
            it = GizmoTypes.ICON_LIGHT_POINT
        }
        elif lightType == GizmoTypes.LIGHT_SPOT
        {
            it = GizmoTypes.ICON_LIGHT_SPOT
        }
        Float32 sz = this.size
        GizmoGeometry.icon( this._lV, it, center, sz, lightType )
    }

    # 把六色缓冲写回 MeshRef（未 attach 时仅更新缓冲，便于离屏单测）
    public void endFrame()
    {
        if this._xM != null
        {
            this._xM.setVertices( this._xV )
        }
        if this._yM != null
        {
            this._yM.setVertices( this._yV )
        }
        if this._zM != null
        {
            this._zM.setVertices( this._zV )
        }
        if this._nM != null
        {
            this._nM.setVertices( this._nV )
        }
        if this._cM != null
        {
            this._cM.setVertices( this._cV )
        }
        if this._lM != null
        {
            this._lM.setVertices( this._lV )
        }
    }

    # 按槽序号追加（测试/扩展用：0=X 1=Y 2=Z 3=N 4=Cam 5=Light）
    public void appendTo( Int32 slot, Float32_3 v )
    {
        if slot == 0
        {
            this._xV.add( v )
        }
        elif slot == 1
        {
            this._yV.add( v )
        }
        elif slot == 2
        {
            this._zV.add( v )
        }
        elif slot == 3
        {
            this._nV.add( v )
        }
        elif slot == 4
        {
            this._cV.add( v )
        }
        elif slot == 5
        {
            this._lV.add( v )
        }
    }

    # ── 诊断 getters（跨模块读一律方法返回，doc/10 §6）──
    public Int32 vertexCountAt( Int32 slot )
    {
        if slot == 0
        {
            ret this._xV.length
        }
        if slot == 1
        {
            ret this._yV.length
        }
        if slot == 2
        {
            ret this._zV.length
        }
        if slot == 3
        {
            ret this._nV.length
        }
        if slot == 4
        {
            ret this._cV.length
        }
        if slot == 5
        {
            ret this._lV.length
        }
        ret 0
    }

    public Int32 totalVertexCount()
    {
        Int32 t = 0
        t = t + this._xV.length
        t = t + this._yV.length
        t = t + this._zV.length
        t = t + this._nV.length
        t = t + this._cV.length
        t = t + this._lV.length
        ret t
    }

    public bool allFinite()
    {
        if !GizmoGeometry.allFinite( this._xV )
        {
            ret false
        }
        if !GizmoGeometry.allFinite( this._yV )
        {
            ret false
        }
        if !GizmoGeometry.allFinite( this._zV )
        {
            ret false
        }
        if !GizmoGeometry.allFinite( this._nV )
        {
            ret false
        }
        if !GizmoGeometry.allFinite( this._cV )
        {
            ret false
        }
        if !GizmoGeometry.allFinite( this._lV )
        {
            ret false
        }
        ret true
    }

    public Int32 currentMode()
    {
        ret this.mode
    }

    public bool isEnabled()
    {
        ret this.enabled
    }
}
