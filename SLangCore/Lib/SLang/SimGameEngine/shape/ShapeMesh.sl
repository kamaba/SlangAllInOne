import Core;
import Std;
import Math;

# ============================================================================
# ShapeMesh — 形状网格数据容器（P9 shape 库，doc/17）
# ----------------------------------------------------------------------------
# ShapeFactory.build 的产物：positions/normals/uvs 以 Array<Float32> 平铺存储
# （3N/3N/2N），triangles 为 Array<Int32>（3T）。顶点法线/UV 由 C 核心随形状
# 一并生成；全部形状中心在原点、Y 轴向上、CCW 绕序。
# 消费出口：applyTo(MeshRef) —— 顶点灌入引擎合批通道（MeshRef.hasVertexData）。
# 转 SLang.Mesh：消费方自理（本模块引用 SLangRender 为 slb 形态，不可声明
# 跨模块局部变量；引用 .module.json 元数据的模块可用
# SLang.Mesh(getPositions(), getTriangles(), getNormals()) 构造）。
# 注意：方法调用不作实参（doc/10 §6）——需要先取局部变量再传入。
# ============================================================================

public class ShapeMesh
{
    Array<Float32> _positions = null
    Array<Float32> _normals = null
    Array<Float32> _uvs = null
    Array<Int32> _triangles = null

    public void _init_( Array<Float32> positions, Array<Float32> normals, Array<Float32> uvs, Array<Int32> triangles )
    {
        this._positions = positions
        this._normals = normals
        this._uvs = uvs
        this._triangles = triangles
    }

    get int vertexCount()
    {
        if this._positions == null
        {
            ret 0
        }
        ret this._positions.length / 3
    }

    get int triangleCount()
    {
        if this._triangles == null
        {
            ret 0
        }
        ret this._triangles.length / 3
    }

    # 越界返回零向量
    public Float32_3 getVertex( int index )
    {
        if index < 0 || index >= this.vertexCount()
        {
            ret Float32_3( 0.0f, 0.0f, 0.0f )
        }
        ret Float32_3( this._positions[ index * 3 ], this._positions[ index * 3 + 1 ], this._positions[ index * 3 + 2 ] )
    }

    public Float32_3 getNormal( int index )
    {
        if index < 0 || index >= this.vertexCount()
        {
            ret Float32_3( 0.0f, 0.0f, 0.0f )
        }
        ret Float32_3( this._normals[ index * 3 ], this._normals[ index * 3 + 1 ], this._normals[ index * 3 + 2 ] )
    }

    public Float32_2 getUv( int index )
    {
        if index < 0 || index >= this.vertexCount()
        {
            ret Float32_2( 0.0f, 0.0f )
        }
        ret Float32_2( this._uvs[ index * 2 ], this._uvs[ index * 2 + 1 ] )
    }

    public Array<Float32> getPositions()
    {
        ret this._positions
    }

    public Array<Float32> getNormals()
    {
        ret this._normals
    }

    public Array<Float32> getUvs()
    {
        ret this._uvs
    }

    public Array<Int32> getTriangles()
    {
        ret this._triangles
    }

    # 顶点灌入引擎网格组件（模型空间顶点合批通道；重复调用覆盖）
    public void applyTo( MeshRef meshRef )
    {
        if meshRef == null
        {
            ret
        }
        Array<Int32> tri = this._triangles
        Int32 ti = this.triangleCount()
        if tri == null || ti < 1
        {
            ret
        }
        # MeshRef 顶点按三角形汤消费（每 3 顶点一个三角），必须按索引
        # 展开；直接灌 positions 会把索引缓冲当顶点序列，绕序错乱且多数
        # 三角形退化 —— 形状在场景里几乎不可见。
        Int32 n = ti * 3
        List<Float32_3> v = List<Float32_3>( n )
        int i = 0
        while i < n
        {
            Int32 vi = tri[ i ]
            Float32_3 vtx = this.getVertex( vi )
            v.add( vtx )
            i = i + 1
        }
        meshRef.setVertices( v )
    }
}
