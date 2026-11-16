import Core;
import Std;
import Math;

# ============================================================================
# MeshRef — 网格引用组件（P2）
# ----------------------------------------------------------------------------
# doc/04 §3.1：组件每实例只属一个 GameObject；meshKind 为内置网格枚举值
# （Render 侧 MESH_* 的数值由提交方映射），meshSlot = -1 表示内置网格、
# >= 0 表示 uploadMesh 动态槽。
# 顶点数据：hasVertexData = true 时 vertices 携带模型空间顶点（每元素一个
# Float32_3，引擎侧合批烘焙的输入）；false（纯内置网格）时无顶点数据，
# Batcher 会把它走「单对象直通」路径（doc/05 §3.1 例外）。
# 注意：① `dynamic` 是 SL 关键字，字段名用 hasVertexData；
#       ② 顶点容器用 List<Float32_3>（List<Array> 的值类型泛型实参
#         Float32/Int32 不被 Front 解析支持，struct 实参可用）。
# 内置网格顶点可用 static 工厂（cube/quad/triangle）生成。
# ============================================================================

public class MeshRef extends Behaviour
{
    public Int32 meshKind = 0
    public Int32 meshSlot = 0 - 1
    public bool visible = true
    public bool hasVertexData = false
    public List<Float32_3> vertices = List<Float32_3>( 0 )

    public static MeshRef create( Int32 kind )
    {
        MeshRef mr = MeshRef()
        mr.meshKind = kind
        ret mr
    }

    public void setVertices( List<Float32_3> v )
    {
        this.vertices = v
        this.hasVertexData = true
    }

    # 实例化内置网格顶点（消费方勿直接调 static 工厂——跨模块静态方法
    # 经 IR 签名错位不可用，doc/10 §6；实例方法内调用同模块 static 无碍）
    public void useTriangle( Float32 size )
    {
        this.setVertices( MeshRef.triangleVertices( size ) )
    }

    public void useQuad( Float32 size )
    {
        this.setVertices( MeshRef.quadVertices( size ) )
    }

    public void useCube( Float32 size )
    {
        this.setVertices( MeshRef.cubeVertices( size ) )
    }

    # ── 内置网格顶点工厂（模型空间，右手系）────────────────
    # 单位三角形（3 顶点）
    public static List<Float32_3> triangleVertices( Float32 size )
    {
        List<Float32_3> v = List<Float32_3>( 3 )
        v.add( Float32_3( 0.0f, size, 0.0f ) )
        v.add( Float32_3( 0.0f - size * 0.5f, 0.0f - size * 0.5f, 0.0f ) )
        v.add( Float32_3( size * 0.5f, 0.0f - size * 0.5f, 0.0f ) )
        ret v
    }

    # 单位四边形（2 三角形，6 顶点）
    public static List<Float32_3> quadVertices( Float32 size )
    {
        Float32 h = size * 0.5f
        List<Float32_3> v = List<Float32_3>( 6 )
        # tri 1: (-h,-h) (-h,h) (h,h)
        v.add( Float32_3( 0.0f - h, 0.0f - h, 0.0f ) )
        v.add( Float32_3( 0.0f - h, h, 0.0f ) )
        v.add( Float32_3( h, h, 0.0f ) )
        # tri 2: (-h,-h) (h,h) (h,-h)
        v.add( Float32_3( 0.0f - h, 0.0f - h, 0.0f ) )
        v.add( Float32_3( h, h, 0.0f ) )
        v.add( Float32_3( h, 0.0f - h, 0.0f ) )
        ret v
    }

    # 单位立方体（6 面 × 2 三角形，36 顶点）
    public static List<Float32_3> cubeVertices( Float32 size )
    {
        Float32 h = size * 0.5f
        List<Float32_3> v = List<Float32_3>( 36 )
        # -Z 面
        MeshRef.pushQuad( v,
            Float32_3( 0.0f - h, 0.0f - h, 0.0f - h ), Float32_3( 0.0f - h, h, 0.0f - h ),
            Float32_3( h, h, 0.0f - h ), Float32_3( h, 0.0f - h, 0.0f - h ) )
        # +Z 面
        MeshRef.pushQuad( v,
            Float32_3( h, 0.0f - h, h ), Float32_3( h, h, h ),
            Float32_3( 0.0f - h, h, h ), Float32_3( 0.0f - h, 0.0f - h, h ) )
        # -X 面
        MeshRef.pushQuad( v,
            Float32_3( 0.0f - h, 0.0f - h, h ), Float32_3( 0.0f - h, h, h ),
            Float32_3( 0.0f - h, h, 0.0f - h ), Float32_3( 0.0f - h, 0.0f - h, 0.0f - h ) )
        # +X 面
        MeshRef.pushQuad( v,
            Float32_3( h, 0.0f - h, 0.0f - h ), Float32_3( h, h, 0.0f - h ),
            Float32_3( h, h, h ), Float32_3( h, 0.0f - h, h ) )
        # -Y 面
        MeshRef.pushQuad( v,
            Float32_3( 0.0f - h, 0.0f - h, 0.0f - h ), Float32_3( h, 0.0f - h, 0.0f - h ),
            Float32_3( h, 0.0f - h, h ), Float32_3( 0.0f - h, 0.0f - h, h ) )
        # +Y 面
        MeshRef.pushQuad( v,
            Float32_3( 0.0f - h, h, h ), Float32_3( h, h, h ),
            Float32_3( h, h, 0.0f - h ), Float32_3( 0.0f - h, h, 0.0f - h ) )
        ret v
    }

    static void pushQuad( List<Float32_3> v, Float32_3 a, Float32_3 b, Float32_3 c, Float32_3 d )
    {
        v.add( a )
        v.add( b )
        v.add( c )
        v.add( a )
        v.add( c )
        v.add( d )
    }
}
