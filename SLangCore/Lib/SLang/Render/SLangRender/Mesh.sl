import Math;

# ============================================================================
# Mesh：三角网格数学层（顶点 / 三角形索引 / 法线，平铺存储）
# ----------------------------------------------------------------------------
# 顶点与法线以 Array<Float32> 平铺存储（x,y,z 交错，长度 3N），三角形索
# 引为 Array<Int32>（长度 3T，每 3 个一组）。不引入 Color/Bounds/Ray，
# 保持对 Core + Math 的最小依赖。
# cube(size)：6 面 24 顶点 36 索引。每面 4 顶点按角序 (0,0)(1,0)(1,1)(0,1)
# 排布（从面外侧看逆时针），使用方可按 vi%4 现场推导 UV；三角形为
# (4f,4f+1,4f+2) + (4f,4f+2,4f+3)。
# ============================================================================
namespace SLang
{
    public class Mesh
    {
        Array<Float32> _positions = null
        Array<Int32> _triangles = null
        Array<Float32> _normals = null

        # positions：3N 平铺顶点；triangles：3T 三角形索引；法线全 0（可 recalculate）
        public void _init_( Array<Float32> positions, Array<Int32> triangles )
        {
            this._positions = positions
            this._triangles = triangles
            this._normals = Array<Float32>( positions.length )
        }

        # positions / triangles / normals 三参形式（normals 长度须为 3N）
        public void _init_( Array<Float32> positions, Array<Int32> triangles, Array<Float32> normals )
        {
            this._positions = positions
            this._triangles = triangles
            this._normals = normals
        }

        # ── 基本属性 ─────────────────────────────────────────────
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

        # ── 顶点访问 ─────────────────────────────────────────────
        # 越界返回零向量
        public Float32_3 getVertex( int index )
        {
            if index < 0 || index >= this.vertexCount()
            {
                ret Float32_3( 0.0f, 0.0f, 0.0f )
            }
            ret Float32_3( this._positions[ index * 3 ], this._positions[ index * 3 + 1 ], this._positions[ index * 3 + 2 ] )
        }

        # 越界忽略
        public void setVertex( int index, Float32_3 v )
        {
            if index < 0 || index >= this.vertexCount()
            {
                ret
            }
            this._positions[ index * 3 ] = v.x
            this._positions[ index * 3 + 1 ] = v.y
            this._positions[ index * 3 + 2 ] = v.z
        }

        public Array<Int32> getTriangles()
        {
            ret this._triangles
        }

        # tri：第几个三角形（0 起）；corner：0/1/2；越界返回 -1
        public int getTriangleIndex( int tri, int corner )
        {
            if tri < 0 || tri >= this.triangleCount() || corner < 0 || corner > 2
            {
                ret -1
            }
            ret this._triangles[ tri * 3 + corner ]
        }

        public Float32_3 getNormal( int index )
        {
            if index < 0 || index >= this.vertexCount()
            {
                ret Float32_3( 0.0f, 0.0f, 0.0f )
            }
            ret Float32_3( this._normals[ index * 3 ], this._normals[ index * 3 + 1 ], this._normals[ index * 3 + 2 ] )
        }

        public void setNormal( int index, Float32_3 n )
        {
            if index < 0 || index >= this.vertexCount()
            {
                ret
            }
            this._normals[ index * 3 ] = n.x
            this._normals[ index * 3 + 1 ] = n.y
            this._normals[ index * 3 + 2 ] = n.z
        }

        # 面法线累加到顶点后归一化（面积加权）
        public void recalculateNormals()
        {
            int nv = this.vertexCount()
            int nt = this.triangleCount()
            int i = 0
            while i < nv * 3
            {
                this._normals[ i ] = 0.0f
                i = i + 1
            }
            int t = 0
            while t < nt
            {
                int ia = this._triangles[ t * 3 ]
                int ib = this._triangles[ t * 3 + 1 ]
                int ic = this._triangles[ t * 3 + 2 ]
                Float32_3 a = this.getVertex( ia )
                Float32_3 b = this.getVertex( ib )
                Float32_3 c = this.getVertex( ic )
                Float32_3 fn = b._sub_( a ).cross( c._sub_( a ) )
                this._normals[ ia * 3 ] = this._normals[ ia * 3 ] + fn.x
                this._normals[ ia * 3 + 1 ] = this._normals[ ia * 3 + 1 ] + fn.y
                this._normals[ ia * 3 + 2 ] = this._normals[ ia * 3 + 2 ] + fn.z
                this._normals[ ib * 3 ] = this._normals[ ib * 3 ] + fn.x
                this._normals[ ib * 3 + 1 ] = this._normals[ ib * 3 + 1 ] + fn.y
                this._normals[ ib * 3 + 2 ] = this._normals[ ib * 3 + 2 ] + fn.z
                this._normals[ ic * 3 ] = this._normals[ ic * 3 ] + fn.x
                this._normals[ ic * 3 + 1 ] = this._normals[ ic * 3 + 1 ] + fn.y
                this._normals[ ic * 3 + 2 ] = this._normals[ ic * 3 + 2 ] + fn.z
                t = t + 1
            }
            int v = 0
            while v < nv
            {
                Float32_3 n = this.getNormal( v ).normalize()
                this.setNormal( v, n )
                v = v + 1
            }
        }

        # ── 立方体工厂 ───────────────────────────────────────────
        # 每面 4 顶点角序 (0,0)(1,0)(1,1)(0,1)（从面外看逆时针），
        # 三角形 (4f,4f+1,4f+2) + (4f,4f+2,4f+3)；法线为面法线。
        public static Mesh cube( Float32 size )
        {
            Float32 hs = size * 0.5f
            # 8 角点（编号按 x,y,z 符号位：0=(-,-,-) .. 7=(+,+,+)）
            Array<Float32> cp = Array<Float32>( 24 )
            cp[0] = -hs; cp[1] = -hs; cp[2] = -hs
            cp[3] = -hs; cp[4] = -hs; cp[5] = hs
            cp[6] = -hs; cp[7] = hs; cp[8] = -hs
            cp[9] = -hs; cp[10] = hs; cp[11] = hs
            cp[12] = hs; cp[13] = -hs; cp[14] = -hs
            cp[15] = hs; cp[16] = -hs; cp[17] = hs
            cp[18] = hs; cp[19] = hs; cp[20] = -hs
            cp[21] = hs; cp[22] = hs; cp[23] = hs
            # 6 面 × 4 角点索引（+Z/-Z/+X/-X/+Y/-Y）
            Array<Int32> face = Array<Int32>( 24 )
            face[0] = 1; face[1] = 5; face[2] = 7; face[3] = 3
            face[4] = 4; face[5] = 0; face[6] = 2; face[7] = 6
            face[8] = 5; face[9] = 4; face[10] = 6; face[11] = 7
            face[12] = 0; face[13] = 1; face[14] = 3; face[15] = 2
            face[16] = 3; face[17] = 7; face[18] = 6; face[19] = 2
            face[20] = 0; face[21] = 4; face[22] = 5; face[23] = 1
            # 6 面法线（+Z/-Z/+X/-X/+Y/-Y）
            Array<Float32> fn = Array<Float32>( 18 )
            fn[0] = 0.0f; fn[1] = 0.0f; fn[2] = 1.0f
            fn[3] = 0.0f; fn[4] = 0.0f; fn[5] = -1.0f
            fn[6] = 1.0f; fn[7] = 0.0f; fn[8] = 0.0f
            fn[9] = -1.0f; fn[10] = 0.0f; fn[11] = 0.0f
            fn[12] = 0.0f; fn[13] = 1.0f; fn[14] = 0.0f
            fn[15] = 0.0f; fn[16] = -1.0f; fn[17] = 0.0f
            Array<Float32> pos = Array<Float32>( 72 )
            Array<Float32> nrm = Array<Float32>( 72 )
            Array<Int32> tri = Array<Int32>( 36 )
            int f = 0
            while f < 6
            {
                int k = 0
                while k < 4
                {
                    int vo = f * 4 + k
                    int ci = face[ vo ]
                    pos[ vo * 3 ] = cp[ ci * 3 ]
                    pos[ vo * 3 + 1 ] = cp[ ci * 3 + 1 ]
                    pos[ vo * 3 + 2 ] = cp[ ci * 3 + 2 ]
                    nrm[ vo * 3 ] = fn[ f * 3 ]
                    nrm[ vo * 3 + 1 ] = fn[ f * 3 + 1 ]
                    nrm[ vo * 3 + 2 ] = fn[ f * 3 + 2 ]
                    k = k + 1
                }
                tri[ f * 6 ] = f * 4
                tri[ f * 6 + 1 ] = f * 4 + 1
                tri[ f * 6 + 2 ] = f * 4 + 2
                tri[ f * 6 + 3 ] = f * 4
                tri[ f * 6 + 4 ] = f * 4 + 2
                tri[ f * 6 + 5 ] = f * 4 + 3
                f = f + 1
            }
            ret Mesh( pos, tri, nrm )
        }
    }
}
