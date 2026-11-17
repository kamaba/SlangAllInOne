import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimGjkTest — GJK 凸点集相交验证（第 12 套，doc/11 远期项落盘）
# ----------------------------------------------------------------------------
# 覆盖：C 核心直测（Memory 组块）——单位立方体点集分离/重叠/微 overlap、
# 平移/旋转矩阵点变换、GJK 旋转体；引擎集成——MeshCollider.setVertices +
# CollisionSystem 盒-盒窄相 GJK 精化（包围盒误报撤销）+ 无点集盒退化回归。
# 写法约束（doc/10 §6）：浮点断言取整值/二进制精确值；Memory 组块 stride 12；
# `tr` 等保留字避让。
# ============================================================================

public class SimGjkTest
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

    # 组一个立方体凸点集（8 顶点，中心 + 半边长）到 Memory 块；返回指针
    static Int64 packCube( Float32 cx, Float32 cy, Float32 cz, Float32 h )
    {
        Int64 p = Memory.alloc( 8 * 12 )
        if p == 0
        {
            ret 0
        }
        Int32 i = 0
        while i < 8
        {
            Float32 sx = 1.0f
            if i == 1 || i == 3 || i == 5 || i == 7
            {
                sx = 0.0f - 1.0f
            }
            Float32 sy = 1.0f
            if i >= 2
            {
                if i <= 5
                {
                    sy = 0.0f - 1.0f
                }
            }
            Float32 sz = 1.0f
            if i >= 4
            {
                sz = 0.0f - 1.0f
            }
            Int32 off = i * 12
            Memory.writeF32( p, off + 0, cx + sx * h )
            Memory.writeF32( p, off + 4, cy + sy * h )
            Memory.writeF32( p, off + 8, cz + sz * h )
            i = i + 1
        }
        ret p
    }

    # ── G1. C 核心直测：轴对齐立方体 ───────────────────
    static void testGjkDirect()
    {
        Int64 a = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 b = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 c = packCube( 10.0f, 0.0f, 0.0f, 1.0f )
        Int64 e = packCube( 1.5f, 0.0f, 0.0f, 1.0f )
        check( a != 0 && b != 0 && c != 0 && e != 0, "G1a alloc" )
        check( EngineFfi.libGjkIntersect( a, 8, b, 8 ) == 1, "G1b identical cubes intersect" )
        check( EngineFfi.libGjkIntersect( a, 8, c, 8 ) == 0, "G1c separated cubes disjoint" )
        check( EngineFfi.libGjkIntersect( a, 8, e, 8 ) == 1, "G1d slight overlap (gap 0.5... overlap 0.5)" )
        Memory.free( a )
        Memory.free( b )
        Memory.free( c )
        Memory.free( e )
    }

    # ── G2. 点集矩阵变换 ───────────────────────────────
    static void testPointsTransform()
    {
        Int64 src = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 dst = Memory.alloc( 8 * 12 )
        Int64 mp = Memory.alloc( 64 )
        check( src != 0 && dst != 0 && mp != 0, "G2a alloc" )
        # 平移矩阵：+5 X
        Memory.writeF32( mp, 0, 1.0f )
        Memory.writeF32( mp, 4, 0.0f )
        Memory.writeF32( mp, 8, 0.0f )
        Memory.writeF32( mp, 12, 5.0f )
        Memory.writeF32( mp, 16, 0.0f )
        Memory.writeF32( mp, 20, 1.0f )
        Memory.writeF32( mp, 24, 0.0f )
        Memory.writeF32( mp, 28, 0.0f )
        Memory.writeF32( mp, 32, 0.0f )
        Memory.writeF32( mp, 36, 0.0f )
        Memory.writeF32( mp, 40, 1.0f )
        Memory.writeF32( mp, 44, 0.0f )
        Memory.writeF32( mp, 48, 0.0f )
        Memory.writeF32( mp, 52, 0.0f )
        Memory.writeF32( mp, 56, 0.0f )
        Memory.writeF32( mp, 60, 1.0f )
        Int32 ok = EngineFfi.libPointsTransform( mp, src, 8, dst )
        check( ok == 8, "G2b transform returns count" )
        Float32 x0 = Memory.readFloat32( dst, 0 )
        check( x0 == 6.0f, "G2c corner x translated 5+1" )
        # 平移后的立方体与原点立方体分离（+5 X，半长 1 → 间隙 3）
        Int64 a = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        check( EngineFfi.libGjkIntersect( a, 8, dst, 8 ) == 0, "G2d transformed cube disjoint" )
        Memory.free( src )
        Memory.free( dst )
        Memory.free( mp )
        Memory.free( a )
    }

    # ── G3. 旋转体相交（45° 绕 Y）──────────────────────
    static void testRotated()
    {
        Int64 a = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 src = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 rot = Memory.alloc( 8 * 12 )
        Int64 mp = Memory.alloc( 64 )
        check( a != 0 && src != 0 && rot != 0 && mp != 0, "G3a alloc" )
        # 绕 Y 45°：x' = c*x + s*z; z' = -s*x + c*z（c=s=√2/2）
        Float32 c45 = 0.70710678f
        Memory.writeF32( mp, 0, c45 )
        Memory.writeF32( mp, 4, 0.0f )
        Memory.writeF32( mp, 8, c45 )
        Memory.writeF32( mp, 12, 0.0f )
        Memory.writeF32( mp, 16, 0.0f )
        Memory.writeF32( mp, 20, 1.0f )
        Memory.writeF32( mp, 24, 0.0f )
        Memory.writeF32( mp, 28, 0.0f )
        Memory.writeF32( mp, 32, 0.0f - c45 )
        Memory.writeF32( mp, 36, 0.0f )
        Memory.writeF32( mp, 40, c45 )
        Memory.writeF32( mp, 44, 0.0f )
        Memory.writeF32( mp, 48, 0.0f )
        Memory.writeF32( mp, 52, 0.0f )
        Memory.writeF32( mp, 56, 0.0f )
        Memory.writeF32( mp, 60, 1.0f )
        EngineFfi.libPointsTransform( mp, src, 8, rot )
        # 同心 → 必相交；远移 → 分离
        check( EngineFfi.libGjkIntersect( a, 8, rot, 8 ) == 1, "G3b rotated concentric intersect" )
        Int64 far = packCube( 20.0f, 0.0f, 0.0f, 1.0f )
        check( EngineFfi.libGjkIntersect( rot, 8, far, 8 ) == 0, "G3c rotated far disjoint" )
        Memory.free( a )
        Memory.free( src )
        Memory.free( rot )
        Memory.free( mp )
        Memory.free( far )
    }

    # ── G4. 引擎集成：MeshCollider + CollisionSystem ───
    static List<Float32_3> cubeVerts( Float32 h )
    {
        List<Float32_3> v = List<Float32_3>( 8 )
        Int32 i = 0
        while i < 8
        {
            Float32 sx = 1.0f
            if i == 1 || i == 3 || i == 5 || i == 7
            {
                sx = 0.0f - 1.0f
            }
            Float32 sy = 1.0f
            if i >= 2
            {
                if i <= 5
                {
                    sy = 0.0f - 1.0f
                }
            }
            Float32 sz = 1.0f
            if i >= 4
            {
                sz = 0.0f - 1.0f
            }
            Float32_3 p = Float32_3( sx * h, sy * h, sz * h )
            v.add( p )
            i = i + 1
        }
        ret v
    }

    static GameObject makeMeshNode( Scene scene, string name, Float32 x, Float32 y, Float32 z, Float32 boxHalf, Float32 meshHalf )
    {
        GameObject go = scene.createObject( name )
        Transform t = go.transform
        Float32_3 pos = Float32_3( x, y, z )
        t.setPosition( pos )
        MeshCollider mc = MeshCollider()
        Float32_3 bs = Float32_3( boxHalf * 2.0f, boxHalf * 2.0f, boxHalf * 2.0f )
        mc.size = bs
        mc.setMeshVertices( cubeVerts( meshHalf ) )
        go.addComponent( mc )
        ret go
    }

    static void testEngineMeshPair()
    {
        # 包围盒误报撤销：盒 half=2（重叠），点集 half=1（间隙 0.5）
        Scene scene = Scene( "G4" )
        makeMeshNode( scene, "A", 0.0f, 0.0f, 0.0f, 2.0f, 1.0f )
        makeMeshNode( scene, "B", 2.5f, 0.0f, 0.0f, 2.0f, 1.0f )
        CollisionSystem cs = CollisionSystem()
        cs.step( scene )
        check( cs.contactCount() == 0, "G4a gjk cancels box false positive" )
        # 点集真重叠（B x=1.5：盒重叠且点集重叠）→ 接触保留
        Scene scene2 = Scene( "G4b" )
        makeMeshNode( scene2, "A", 0.0f, 0.0f, 0.0f, 2.0f, 1.0f )
        makeMeshNode( scene2, "B", 1.5f, 0.0f, 0.0f, 2.0f, 1.0f )
        CollisionSystem cs2 = CollisionSystem()
        cs2.step( scene2 )
        check( cs2.contactCount() == 1, "G4b real overlap keeps contact" )
        # 无点集 MeshCollider 对 → 盒退化路径（v0.1 行为回归）
        Scene scene3 = Scene( "G4c" )
        GameObject n1 = scene3.createObject( "A" )
        MeshCollider m1 = MeshCollider()
        Float32_3 s1 = Float32_3( 2.0f, 2.0f, 2.0f )
        m1.size = s1
        n1.addComponent( m1 )
        GameObject n2 = scene3.createObject( "B" )
        MeshCollider m2 = MeshCollider()
        Float32_3 s2 = Float32_3( 2.0f, 2.0f, 2.0f )
        m2.size = s2
        n2.addComponent( m2 )
        Transform t2 = n2.transform
        Float32_3 p2 = Float32_3( 0.5f, 0.0f, 0.0f )
        t2.setPosition( p2 )
        CollisionSystem cs3 = CollisionSystem()
        cs3.step( scene3 )
        check( cs3.contactCount() == 1, "G4c no-verts falls back to box path" )
    }

    # ── G5. C MTV 直测（26 方向采样法线/深度）───────────
    static void testMtv()
    {
        Int64 a = packCube( 0.0f, 0.0f, 0.0f, 1.0f )
        Int64 b = packCube( 1.5f, 0.0f, 0.0f, 1.0f )
        Int64 c = packCube( 10.0f, 0.0f, 0.0f, 1.0f )
        Int64 o = Memory.alloc( 16 )
        check( a != 0 && b != 0 && c != 0 && o != 0, "G5a alloc" )
        # X 向重叠 0.5 → normal (−1,0,0) depth 0.5
        Int32 hit = EngineFfi.libGjkMtv( a, 8, b, 8, o )
        check( hit == 1, "G5b mtv intersect" )
        Float32 nx = Memory.readFloat32( o, 0 )
        Float32 ny = Memory.readFloat32( o, 4 )
        Float32 nz = Memory.readFloat32( o, 8 )
        Float32 dep = Memory.readFloat32( o, 12 )
        bool nok = ( nx == 0.0f - 1.0f ) && ( ny == 0.0f ) && ( nz == 0.0f )
        check( nok, "G5c normal B->A = (-1,0,0)" )
        check( dep == 0.5f, "G5d depth 0.5" )
        # Y 向重叠 → normal (0,−1,0) depth 1.25
        Int64 d = packCube( 0.0f, 0.75f, 0.0f, 1.0f )
        Int32 hit2 = EngineFfi.libGjkMtv( a, 8, d, 8, o )
        Float32 ny2 = Memory.readFloat32( o, 4 )
        Float32 dep2 = Memory.readFloat32( o, 12 )
        bool yok = ( hit2 == 1 ) && ( ny2 == 0.0f - 1.0f ) && ( dep2 == 1.25f )
        check( yok, "G5e y-overlap normal/depth" )
        # 分离 → 0
        Int32 hit3 = EngineFfi.libGjkMtv( a, 8, c, 8, o )
        check( hit3 == 0, "G5f separated mtv 0" )
        Memory.free( a )
        Memory.free( b )
        Memory.free( c )
        Memory.free( d )
        Memory.free( o )
    }

    # ── G6. 引擎物理集成：mesh 刚体落 mesh 地面静置 ────
    static List<Float32_3> boxVerts( Float32 hx, Float32 hy, Float32 hz )
    {
        List<Float32_3> v = List<Float32_3>( 8 )
        Int32 i = 0
        while i < 8
        {
            Float32 sx = 1.0f
            if i == 1 || i == 3 || i == 5 || i == 7
            {
                sx = 0.0f - 1.0f
            }
            Float32 sy = 1.0f
            if i >= 2
            {
                if i <= 5
                {
                    sy = 0.0f - 1.0f
                }
            }
            Float32 sz = 1.0f
            if i >= 4
            {
                sz = 0.0f - 1.0f
            }
            Float32_3 p = Float32_3( sx * hx, sy * hy, sz * hz )
            v.add( p )
            i = i + 1
        }
        ret v
    }

    static void testMeshPhysicsRest()
    {
        Scene scene = Scene( "G6" )
        # 地面：扁平 mesh 点集（无刚体 = 静态）
        GameObject floor = scene.createObject( "Floor" )
        MeshCollider fm = MeshCollider()
        Float32_3 fs = Float32_3( 20.0f, 1.0f, 20.0f )
        fm.size = fs
        fm.setMeshVertices( boxVerts( 10.0f, 0.5f, 10.0f ) )
        floor.addComponent( fm )
        # 落体：mesh 立方体（half 1）+ 刚体
        GameObject cube = scene.createObject( "Cube" )
        MeshCollider cm = MeshCollider()
        Float32_3 cs2 = Float32_3( 2.0f, 2.0f, 2.0f )
        cm.size = cs2
        cm.setMeshVertices( cubeVerts( 1.0f ) )
        cube.addComponent( cm )
        Rigidbody rb = Rigidbody()
        rb.mass = 1.0f
        rb.useGravity = true
        cube.addComponent( rb )
        Transform t = cube.transform
        Float32_3 p0 = Float32_3( 0.0f, 3.0f, 0.0f )
        t.setPosition( p0 )
        # 固定步 300 步（5 秒）
        PhysicsSystem ps = PhysicsSystem()
        CollisionSystem cs = CollisionSystem()
        Int32 i = 0
        while i < 300
        {
            ps.step( scene, 0.0166667f, cs )
            i = i + 1
        }
        Transform t2 = cube.transform
        Float32_3 py = t2.worldPosition()
        # 静置 y ≈ 地面顶 0.5 + 立方体半长 1 = 1.5
        bool rest = ( py.y > 1.3f ) && ( py.y < 1.7f )
        check( rest, "G6a mesh cube rests on mesh floor (y~1.5, got " + py.y.toString() + ")" )
        bool onFloor = ( py.x == 0.0f ) && ( py.z == 0.0f )
        check( onFloor, "G6b no lateral drift" )
    }

    public static void run()
    {
        testGjkDirect()
        testPointsTransform()
        testRotated()
        testEngineMeshPair()
        testMtv()
        testMeshPhysicsRest()
        Console.println( "SimGjkTest: PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }

    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }
}
