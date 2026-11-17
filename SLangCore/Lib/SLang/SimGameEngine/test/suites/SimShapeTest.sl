import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimShapeTest — 固定形状库验证（第 13 套，doc/17）
# ----------------------------------------------------------------------------
# 覆盖：11 种形状 counts/build 规模公式（V/T 与 C 侧 sle_shape_dims 一致）、
# 关键顶点/法线精确值、包围范围、三角形索引与 UV 范围、绕序一致（三角形
# 几何法线与顶点法线同向 = CCW 外向）、applyTo(MeshRef)/toMesh() 消费出口、
# 便捷方法与错误路径（形状号/参数非法返回 null）。
# 写法约束（doc/10 §6）：方法调用不作实参（先取局部变量）；浮点断言取
# 二进制精确值或粗界；保留字避让。
# ============================================================================

public class SimShapeTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static Int32 passCount()
    {
        ret _pass
    }

    static Int32 failCount()
    {
        ret _fail
    }

    # 构造 5 float 参数块
    static Array<Float32> pf( Float32 a, Float32 b, Float32 c, Float32 d, Float32 e )
    {
        Array<Float32> p = Array<Float32>( 5 )
        p[0] = a
        p[1] = b
        p[2] = c
        p[3] = d
        p[4] = e
        ret p
    }

    static Array<Float32> cut( Array<Float32> p, Int32 n )
    {
        Array<Float32> q = Array<Float32>( n )
        Int32 i = 0
        while i < n
        {
            q[ i ] = p[ i ]
            i = i + 1
        }
        ret q
    }

    # build + 规模断言；返回 ShapeMesh（失败返回 null）
    static ShapeMesh buildOk( Int32 shapeType, Array<Float32> p, Int32 ev, Int32 et, string tag )
    {
        ShapeMesh m = ShapeFactory.build( shapeType, p )
        if m == null
        {
            check( false, tag + " build non-null" )
            ret null
        }
        check( true, tag + " build non-null" )
        int v = m.vertexCount()
        int t = m.triangleCount()
        check( v == ev, tag + " vertexCount=" + v.toString() + " expect " + ev.toString() )
        check( t == et, tag + " triangleCount=" + t.toString() + " expect " + et.toString() )
        ret m
    }

    # ── 通用数据体检：索引范围 / UV 范围 / 绕序一致 ────────
    static void checkData( ShapeMesh m, string tag )
    {
        int v = m.vertexCount()
        int nt = m.triangleCount()
        Array<Int32> tri = m.getTriangles()
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        Array<Float32> uv = m.getUvs()
        # 三角形索引在 [0, V)
        Int32 bad = 0
        Int32 i = 0
        Int32 total = nt * 3
        while i < total
        {
            Int32 idx = tri[ i ]
            if idx < 0 || idx >= v
            {
                bad = bad + 1
            }
            i = i + 1
        }
        check( bad == 0, tag + " triangle indices in range" )
        # UV 在 [0,1]
        Int32 badU = 0
        i = 0
        while i < v * 2
        {
            Float32 u = uv[ i ]
            if u < 0.0f || u > 1.0f
            {
                badU = badU + 1
            }
            i = i + 1
        }
        check( badU == 0, tag + " uv in range" )
        # 绕序：三角形几何法线与首顶点法线同向（CCW 外向）
        Int32 badW = 0
        i = 0
        while i < nt
        {
            Int32 ia = tri[ i * 3 ]
            Int32 ib = tri[ i * 3 + 1 ]
            Int32 ic = tri[ i * 3 + 2 ]
            Float32 ax = pos[ ia * 3 ]
            Float32 ay = pos[ ia * 3 + 1 ]
            Float32 az = pos[ ia * 3 + 2 ]
            Float32 e1x = pos[ ib * 3 ] - ax
            Float32 e1y = pos[ ib * 3 + 1 ] - ay
            Float32 e1z = pos[ ib * 3 + 2 ] - az
            Float32 e2x = pos[ ic * 3 ] - ax
            Float32 e2y = pos[ ic * 3 + 1 ] - ay
            Float32 e2z = pos[ ic * 3 + 2 ] - az
            Float32 gx = e1y * e2z - e1z * e2y
            Float32 gy = e1z * e2x - e1x * e2z
            Float32 gz = e1x * e2y - e1y * e2x
            Float32 dot = gx * nrm[ ia * 3 ] + gy * nrm[ ia * 3 + 1 ] + gz * nrm[ ia * 3 + 2 ]
            # 垂直（共享顶点端盖，dot≈0）容忍；明显负值 = 绕序翻转
            if dot < 0.0f - 0.0001f
            {
                badW = badW + 1
            }
            i = i + 1
        }
        check( badW == 0, tag + " winding matches normals" )
    }

    # 法线长度平方均在 (0.98, 1.02)（平滑形状用）
    static void checkUnitNormals( ShapeMesh m, string tag )
    {
        Array<Float32> nrm = m.getNormals()
        int v = m.vertexCount()
        Int32 bad = 0
        Int32 i = 0
        while i < v
        {
            Float32 nx = nrm[ i * 3 ]
            Float32 ny = nrm[ i * 3 + 1 ]
            Float32 nz = nrm[ i * 3 + 2 ]
            Float32 d = nx * nx + ny * ny + nz * nz
            if d < 0.98f || d > 1.02f
            {
                bad = bad + 1
            }
            i = i + 1
        }
        check( bad == 0, tag + " normals unit length" )
    }

    # 坐标粗界（|x|,|y|,|z| <= bound）
    static void checkBounds( ShapeMesh m, Float32 bound, string tag )
    {
        Array<Float32> pos = m.getPositions()
        int n3 = m.vertexCount() * 3
        Int32 bad = 0
        Int32 i = 0
        while i < n3
        {
            Float32 c = pos[ i ]
            if c > bound || c < 0.0f - bound
            {
                bad = bad + 1
            }
            i = i + 1
        }
        check( bad == 0, tag + " positions within bound" )
    }

    # ── S1. 各形状规模 + 关键精确值 ────────────────────────
    static void testCube()
    {
        Array<Float32> p5 = pf( 1.0f, 1.0f, 1.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        ShapeMesh m = buildOk( 0, p, 24, 12, "S1 cube" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        # 首顶点 = +Z 面 (-hx,-hy,+hz)，法线 (0,0,1)（二进制精确）
        check( pos[0] == 0.0f - 0.5f && pos[1] == 0.0f - 0.5f && pos[2] == 0.5f, "S1 cube first vert" )
        check( nrm[0] == 0.0f && nrm[1] == 0.0f && nrm[2] == 1.0f, "S1 cube first normal +Z" )
        checkBounds( m, 0.5f, "S1 cube" )
        checkData( m, "S1 cube" )
    }

    static void testPlane()
    {
        Array<Float32> p5 = pf( 4.0f, 4.0f, 2.0f, 1.0f, 0.0f )
        Array<Float32> p = cut( p5, 4 )
        ShapeMesh m = buildOk( 1, p, 6, 4, "S1 plane" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        # 首顶点 = (-w/2, 0, +h/2)，法线 (0,1,0)
        check( pos[0] == 0.0f - 2.0f && pos[1] == 0.0f && pos[2] == 2.0f, "S1 plane first vert" )
        check( nrm[1] == 1.0f && nrm[0] == 0.0f && nrm[2] == 0.0f, "S1 plane normal +Y" )
        # 细分规模：cols=2,rows=3 → V=12 T=12
        Array<Float32> q5 = pf( 4.0f, 4.0f, 2.0f, 3.0f, 0.0f )
        Array<Float32> q = cut( q5, 4 )
        ShapeMesh m2 = buildOk( 1, q, 12, 12, "S1 plane subdiv" )
        if m2 != null
        {
            checkData( m2, "S1 plane subdiv" )
        }
        checkData( m, "S1 plane" )
    }

    static void testSprite()
    {
        Array<Float32> p5 = pf( 1.0f, 2.0f, 0.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 2 )
        ShapeMesh m = buildOk( 2, p, 4, 2, "S1 sprite" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        check( pos[0] == 0.0f - 0.5f && pos[1] == 0.0f - 1.0f && pos[2] == 0.0f, "S1 sprite first vert" )
        checkData( m, "S1 sprite" )
    }

    static void testSphere()
    {
        Array<Float32> p5 = pf( 1.0f, 8.0f, 4.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        # V = 2 + (4-1)*(8+1) = 29；T = 8*(2*4-2) = 48
        ShapeMesh m = buildOk( 3, p, 29, 48, "S1 sphere" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        # 顶极点精确 (0,1,0)
        check( pos[0] == 0.0f && pos[1] == 1.0f && pos[2] == 0.0f, "S1 sphere top pole" )
        check( nrm[0] == 0.0f && nrm[1] == 1.0f && nrm[2] == 0.0f, "S1 sphere top normal" )
        # 底极点 = 末顶点 (0,-1,0)
        Int32 last = 28 * 3
        check( pos[last] == 0.0f && pos[last + 1] == 0.0f - 1.0f && pos[last + 2] == 0.0f, "S1 sphere bottom pole" )
        checkUnitNormals( m, "S1 sphere" )
        checkBounds( m, 1.0f, "S1 sphere" )
        checkData( m, "S1 sphere" )
    }

    static void testCylinder()
    {
        Array<Float32> p5 = pf( 1.0f, 2.0f, 8.0f, 1.0f, 0.0f )
        Array<Float32> p = cut( p5, 4 )
        # V = (8+1)*(1+1) + 2*(8+2) = 38（端盖各含 1 中心顶点）；T = 2*8*1 + 2*8 = 32
        ShapeMesh m = buildOk( 4, p, 38, 32, "S1 cylinder" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        # 侧面首顶点 = (r, +h/2, 0)，法线 (1,0,0)
        check( pos[0] == 1.0f && pos[1] == 1.0f && pos[2] == 0.0f, "S1 cylinder side vert" )
        check( nrm[0] == 1.0f && nrm[1] == 0.0f && nrm[2] == 0.0f, "S1 cylinder side normal" )
        # 顶盖环首顶点（基址 18）法线 (0,1,0)
        Int32 cb = 18 * 3
        check( nrm[cb] == 0.0f && nrm[cb + 1] == 1.0f && nrm[cb + 2] == 0.0f, "S1 cylinder cap normal +Y" )
        checkUnitNormals( m, "S1 cylinder" )
        checkBounds( m, 1.0f, "S1 cylinder" )
        checkData( m, "S1 cylinder" )
    }

    static void testCone()
    {
        Array<Float32> p5 = pf( 1.0f, 2.0f, 8.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        # V = 8+3 = 11；T = 2*8 = 16
        ShapeMesh m = buildOk( 5, p, 11, 16, "S1 cone" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        # 底环首顶点 = (r, -h/2, 0)
        check( pos[0] == 1.0f && pos[1] == 0.0f - 1.0f && pos[2] == 0.0f, "S1 cone base vert" )
        # 顶点（索引 9 = 底环 seg+1 之后）= (0, +h/2, 0)
        Int32 ap = 9 * 3
        check( pos[ap] == 0.0f && pos[ap + 1] == 1.0f && pos[ap + 2] == 0.0f, "S1 cone apex" )
        checkUnitNormals( m, "S1 cone" )
        checkBounds( m, 1.0f, "S1 cone" )
        checkData( m, "S1 cone" )
    }

    static void testTorus()
    {
        Array<Float32> p5 = pf( 1.0f, 0.3f, 8.0f, 6.0f, 0.0f )
        Array<Float32> p = cut( p5, 4 )
        # V = 9*7 = 63；T = 2*8*6 = 96
        ShapeMesh m = buildOk( 6, p, 63, 96, "S1 torus" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        # 首顶点 = (R+tube, 0, 0)（与 SL 同序浮点运算逐位一致）
        Float32 rx = 1.0f + 0.3f
        check( pos[0] == rx && pos[1] == 0.0f && pos[2] == 0.0f, "S1 torus first vert" )
        checkUnitNormals( m, "S1 torus" )
        checkBounds( m, rx, "S1 torus" )
        checkData( m, "S1 torus" )
    }

    static void testPrism()
    {
        Array<Float32> p5 = pf( 1.0f, 1.0f, 1.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        ShapeMesh m = buildOk( 7, p, 18, 8, "S1 prism" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        Array<Float32> nrm = m.getNormals()
        # 首顶点 = 前端盖 BL = (-hx,-hy,+hz)，法线 +Z
        check( pos[0] == 0.0f - 0.5f && pos[1] == 0.0f - 0.5f && pos[2] == 0.5f, "S1 prism first vert" )
        check( nrm[2] == 1.0f && nrm[0] == 0.0f && nrm[1] == 0.0f, "S1 prism front normal" )
        checkBounds( m, 0.5f, "S1 prism" )
        checkData( m, "S1 prism" )
    }

    static void testPipe()
    {
        Array<Float32> p5 = pf( 1.0f, 2.0f, 0.3f, 8.0f, 0.0f )
        Array<Float32> p = cut( p5, 4 )
        # V = 6*9 = 54；T = 8*8 = 64
        ShapeMesh m = buildOk( 8, p, 54, 64, "S1 pipe" )
        if m == null
        {
            ret
        }
        Array<Float32> nrm = m.getNormals()
        # 顶盖环首顶点（基址 36）法线 +Y
        Int32 cb = 36 * 3
        check( nrm[cb] == 0.0f && nrm[cb + 1] == 1.0f && nrm[cb + 2] == 0.0f, "S1 pipe cap normal" )
        checkUnitNormals( m, "S1 pipe" )
        checkBounds( m, 1.0f, "S1 pipe" )
        checkData( m, "S1 pipe" )
    }

    static void testArch()
    {
        Array<Float32> p5 = pf( 180.0f, 1.0f, 1.0f, 0.3f, 8.0f )
        Array<Float32> p = cut( p5, 5 )
        # V = 4*9 = 36；T = 8*8 + 4 = 68（180° 两端封口）
        ShapeMesh m = buildOk( 9, p, 36, 68, "S1 arch" )
        if m != null
        {
            Array<Float32> pos = m.getPositions()
            Array<Float32> nrm = m.getNormals()
            # 首顶点 = 外弧起点 θ0=0°：(ro, 0, +w/2)，法线 (1,0,0)
            Float32 ro = 1.0f + 0.3f
            check( pos[0] == ro && pos[1] == 0.0f && pos[2] == 0.5f, "S1 arch first vert" )
            check( nrm[0] == 1.0f && nrm[1] == 0.0f && nrm[2] == 0.0f, "S1 arch first normal" )
            checkUnitNormals( m, "S1 arch" )
            checkData( m, "S1 arch" )
        }
        # 360° 无封口：T = 64
        Array<Float32> f5 = pf( 360.0f, 1.0f, 1.0f, 0.3f, 8.0f )
        Array<Float32> f = cut( f5, 5 )
        ShapeMesh m2 = buildOk( 9, f, 36, 64, "S1 arch full" )
        if m2 != null
        {
            checkData( m2, "S1 arch full" )
        }
    }

    static void testStair()
    {
        Array<Float32> p5 = pf( 4.0f, 2.0f, 0.5f, 1.0f, 0.0f )
        Array<Float32> p = cut( p5, 4 )
        # V = 24*4 = 96；T = 12*4 = 48
        ShapeMesh m = buildOk( 10, p, 96, 48, "S1 stair" )
        if m == null
        {
            ret
        }
        Array<Float32> pos = m.getPositions()
        int n3 = m.vertexCount() * 3
        # 粗界：x∈[-1,1] y∈[-1,1] z∈[-2,2]（整梯居中）
        Int32 bad = 0
        Int32 i = 0
        while i < n3
        {
            Float32 x = pos[ i ]
            Float32 y = pos[ i + 1 ]
            Float32 z = pos[ i + 2 ]
            if x > 1.0f || x < 0.0f - 1.0f || y > 1.0f || y < 0.0f - 1.0f || z > 2.0f || z < 0.0f - 2.0f
            {
                bad = bad + 1
            }
            i = i + 3
        }
        check( bad == 0, "S1 stair bounds centered" )
        checkData( m, "S1 stair" )
    }

    # ── S2. 消费出口：applyTo(MeshRef) / toMesh() ─────────
    static void testConsumers()
    {
        Array<Float32> p5 = pf( 1.0f, 1.0f, 1.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        ShapeMesh m = ShapeFactory.build( 0, p )
        check( m != null, "S2 cube build" )
        if m == null
        {
            ret
        }
        int v = m.vertexCount()
        # applyTo
        MeshRef meshRef = MeshRef.create( 0 )
        m.applyTo( meshRef )
        check( meshRef.hasVertexData == true, "S2 applyTo sets hasVertexData" )
        int lv = meshRef.vertices.length
        check( lv == v, "S2 applyTo vertex count" )
        # toMesh（消费方自理：跨模块类型声明与构造都须限定名 SLang.Mesh）
        SLang.Mesh mesh = SLang.Mesh( m.getPositions(), m.getTriangles(), m.getNormals() )
        int mv = mesh.vertexCount()
        int mt = mesh.triangleCount()
        check( mv == v, "S2 toMesh vertexCount" )
        check( mt == 12, "S2 toMesh triangleCount" )
        Float32_3 n0 = mesh.getNormal( 0 )
        check( n0.z == 1.0f && n0.x == 0.0f && n0.y == 0.0f, "S2 toMesh normal passthrough" )
    }

    # ── S3. 便捷方法（字面量形状号路径）──────────────────
    static void testConvenience()
    {
        ShapeMesh a = ShapeFactory.cube( 2.0f, 2.0f, 2.0f )
        check( a != null, "S3 cube()" )
        if a != null
        {
            int v = a.vertexCount()
            check( v == 24, "S3 cube() V" )
            Array<Float32> pos = a.getPositions()
            check( pos[0] == 0.0f - 1.0f && pos[2] == 1.0f, "S3 cube() size 2" )
        }
        ShapeMesh b = ShapeFactory.sphere( 1.0f, 8, 4 )
        check( b != null, "S3 sphere()" )
        ShapeMesh c = ShapeFactory.cylinder( 1.0f, 2.0f, 8, 1 )
        check( c != null, "S3 cylinder()" )
        ShapeMesh d = ShapeFactory.cone( 1.0f, 2.0f, 8 )
        check( d != null, "S3 cone()" )
        ShapeMesh e = ShapeFactory.torus( 1.0f, 0.3f, 8, 6 )
        check( e != null, "S3 torus()" )
        ShapeMesh g = ShapeFactory.plane( 4.0f, 4.0f, 2, 2 )
        check( g != null, "S3 plane()" )
        ShapeMesh h = ShapeFactory.sprite( 1.0f, 1.0f )
        check( h != null, "S3 sprite()" )
        ShapeMesh i2 = ShapeFactory.prism( 1.0f, 1.0f, 1.0f )
        check( i2 != null, "S3 prism()" )
        ShapeMesh j = ShapeFactory.pipe( 1.0f, 2.0f, 0.3f, 8 )
        check( j != null, "S3 pipe()" )
        ShapeMesh k = ShapeFactory.arch( 180.0f, 1.0f, 1.0f, 0.3f, 8 )
        check( k != null, "S3 arch()" )
        ShapeMesh l = ShapeFactory.stair( 4, 2.0f, 0.5f, 1.0f )
        check( l != null, "S3 stair()" )
    }

    # ── S4. 错误路径 ──────────────────────────────────────
    static void testErrors()
    {
        Array<Float32> p5 = pf( 1.0f, 1.0f, 1.0f, 0.0f, 0.0f )
        Array<Float32> p = cut( p5, 3 )
        # 形状号非法
        ShapeMesh m = ShapeFactory.build( 99, p )
        check( m == null, "S4 bad type returns null" )
        ShapeMesh m2 = ShapeFactory.build( 0 - 1, p )
        check( m2 == null, "S4 negative type returns null" )
        # 参数不足（null / 空块）
        ShapeMesh m3 = ShapeFactory.build( 0, null )
        check( m3 == null, "S4 null params returns null" )
        Array<Float32> empty = Array<Float32>( 0 )
        ShapeMesh m4 = ShapeFactory.build( 0, empty )
        check( m4 == null, "S4 empty params returns null" )
        # 参数非法（负尺寸）
        Array<Float32> neg5 = pf( 0.0f - 1.0f, 1.0f, 1.0f, 0.0f, 0.0f )
        Array<Float32> neg = cut( neg5, 3 )
        ShapeMesh m5 = ShapeFactory.build( 0, neg )
        check( m5 == null, "S4 negative size returns null" )
        # pipe thickness >= radius
        Array<Float32> thick5 = pf( 1.0f, 2.0f, 1.0f, 8.0f, 0.0f )
        Array<Float32> thick = cut( thick5, 4 )
        ShapeMesh m6 = ShapeFactory.build( 8, thick )
        check( m6 == null, "S4 pipe thickness>=radius returns null" )
    }

    public static void run()
    {
        Console.println( "" )
        Console.println( "===== SimShapeTest (shape library, 11 shapes) =====" )
        testCube()
        testPlane()
        testSprite()
        testSphere()
        testCylinder()
        testCone()
        testTorus()
        testPrism()
        testPipe()
        testArch()
        testStair()
        testConsumers()
        testConvenience()
        testErrors()
        Console.println( "===== SimShapeTest PASS=" + _pass.toString() + " FAIL=" + _fail.toString() + " =====" )
    }
}
