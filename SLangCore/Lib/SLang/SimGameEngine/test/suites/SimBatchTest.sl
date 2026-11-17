import SimGameEngine;
import SLangRender;
import Std;
import SLangRender;
import Math;
import SLangRender;

# ============================================================================
# SimBatchTest — SimGameEngine P2 合批器冒烟验证
# ----------------------------------------------------------------------------
# 覆盖：可见收集（激活/layer 掩码/MeshRef.visible/材质就绪）+ 稳定排序 +
#       聚组（共享材质合批、不同材质/queue/layer/实例色拆批、256 上限拆批、
#       单对象直通路径）+ 顶点烘焙（worldMatrix × local）+ clear 复用。
# 写法约束（doc/10 §6）：跨模块链式调用拆单步、&& 双操作数、List 表达式
# 下标先落局部变量、`dynamic` 是保留字。
# ============================================================================

public class SimBatchTest
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

    # 本地材质工厂（跨模块静态方法 IR 错位，见 doc/10 §6）
    static MaterialData newMat( string name )
    {
        MaterialData m = MaterialData()
        m.name = name
        ret m
    }

    # 造一个「节点 + MeshRef(三角顶点) + MaterialRef(共享材质)」
    # 注：跨模块静态工厂（MeshRef.create 等）经 IR 签名错位不可用（同
    # GameObject.create 坑，doc/10 §6），统一构造器 + 字段赋值形态。
    static GameObject makeTri( Scene scene, string name, GameObject parent, MaterialData mat, Float32 x, Float32 y )
    {
        GameObject go = scene.createObject( name, parent )
        go.layer = 0
        MeshRef mr = MeshRef()
        mr.meshKind = 1
        mr.useTriangle( 1.0f )
        go.addComponent( mr )
        MaterialRef mref = MaterialRef()
        mref.material = mat
        go.addComponent( mref )
        Transform t = go.transform
        t.setPosition( Float32_3( x, y, 0.0f ) )
        ret go
    }

    static GameObject makeCube( Scene scene, string name, GameObject parent, MaterialData mat, Int32 layer )
    {
        GameObject go = scene.createObject( name, parent )
        go.layer = layer
        MeshRef mr = MeshRef()
        mr.meshKind = 2
        mr.useCube( 1.0f )
        go.addComponent( mr )
        MaterialRef mref = MaterialRef()
        mref.material = mat
        go.addComponent( mref )
        ret go
    }

    # ── 1. 共享材质合批 ─────────────────────────────────
    static void testSharedMaterialBatch()
    {
        Scene scene = Scene( "B1" )
        MaterialData mat = newMat( "shared" )
        makeTri( scene, "A", null, mat, 0.0f, 0.0f )
        makeTri( scene, "B", null, mat, 5.0f, 0.0f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        check( bt.candidateCount() == 2, "B1a collect 2 candidates" )
        bt.build()
        Int32 gc = bt.groupCount()
        check( gc == 1, "B1b shared material merges to 1 group" )
        BatchGroup g = bt.groupAt( 0 )
        Int32 mc = g.memberCount()
        check( mc == 2, "B1c group has 2 members" )
        check( g.singleObject == false, "B1d baked group" )
        List<Float32_3> baked = List<Float32_3>( 0 )
        g.bakeVerticesInto( baked )
        Int32 bn = baked.length
        check( bn == 6, "B1e baked 3+3 vertices" )
        # A 的三角形顶点 x∈{0,-0.5,0.5}，B 的 x∈{5,4.5,5.5}：抽查首顶点
        Float32_3 v0 = baked[0]
        bool v0ok = ( v0.x == 0.0f ) && ( v0.y == 1.0f )
        check( v0ok, "B1f first vertex is A world" )
        Float32_3 v3 = baked[3]
        bool v3ok = ( v3.x == 5.0f ) && ( v3.y == 1.0f )
        check( v3ok, "B1g 4th vertex is B world (translate baked)" )
    }

    # ── 2. 不同材质实例拆批（含同参数克隆语义）──────────
    static void testDifferentMaterialSplit()
    {
        Scene scene = Scene( "B2" )
        MaterialData m1 = newMat( "m1" )
        MaterialData m2 = newMat( "m2" )
        m1.programId = 7
        m2.programId = 7
        m2.color = Float32_3( 1.0f, 0.0f, 0.0f )
        makeTri( scene, "A", null, m1, 0.0f, 0.0f )
        makeTri( scene, "B", null, m2, 0.0f, 0.0f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        bt.build()
        check( bt.groupCount() == 2, "B2a different material instances split" )
    }

    # ── 3. renderQueue 拆批 + 升序排序 ──────────────────
    static void testQueueSplitAndOrder()
    {
        Scene scene = Scene( "B3" )
        MaterialData opaque = newMat( "opaque" )
        opaque.renderQueue = 2000
        MaterialData transparent = newMat( "alpha" )
        transparent.renderQueue = 3000
        makeTri( scene, "T1", null, transparent, 0.0f, 0.0f )
        makeTri( scene, "O1", null, opaque, 1.0f, 0.0f )
        makeTri( scene, "O2", null, opaque, 2.0f, 0.0f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        bt.build()
        check( bt.groupCount() == 2, "B3a queue split (transparent not merged)" )
        BatchGroup first = bt.groupAt( 0 )
        Int32 fq = first.renderQueue
        BatchGroup second = bt.groupAt( 1 )
        Int32 sq = second.renderQueue
        bool orderOk = ( fq == 2000 ) && ( sq == 3000 )
        check( orderOk, "B3b stable ascending queue order" )
        Int32 fmc = first.memberCount()
        Int32 smc = second.memberCount()
        bool memberOk = ( fmc == 2 ) && ( smc == 1 )
        check( memberOk, "B3c opaque batch holds 2, transparent 1" )
    }

    # ── 4. layer 拆批 + cullMask 过滤 ───────────────────
    static void testLayerAndMask()
    {
        Scene scene = Scene( "B4" )
        MaterialData mat = newMat( "m" )
        makeCube( scene, "L0", null, mat, 0 )
        makeCube( scene, "L1", null, mat, 1 )
        makeCube( scene, "L2", null, mat, 2 )
        Batcher bt = Batcher()
        bt.collect( scene, 3 )
        check( bt.candidateCount() == 2, "B4a cullMask 3 filters layer 2" )
        bt.build()
        check( bt.groupCount() == 2, "B4b different layers split" )
        bt.clear()
        bt.collect( scene, 2 )
        check( bt.candidateCount() == 1, "B4c mask 2 keeps only layer 1" )
    }

    # ── 5. 实例色 override 进键 ─────────────────────────
    static void testColorOverrideSplit()
    {
        Scene scene = Scene( "B5" )
        MaterialData mat = newMat( "m" )
        GameObject a = makeTri( scene, "A", null, mat, 0.0f, 0.0f )
        makeTri( scene, "B", null, mat, 1.0f, 0.0f )
        MaterialRef ar = a.getComponent<MaterialRef>()
        ar.instanceColorOverride = true
        ar.instanceColor = Float32_3( 1.0f, 0.5f, 0.25f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        bt.build()
        check( bt.groupCount() == 2, "B5a color override splits batch" )
        BatchGroup g1 = bt.groupAt( 0 )
        Float32_3 c1 = g1.color
        bool colorOk = ( c1.x == 1.0f ) && ( c1.y == 0.5f )
        check( colorOk, "B5b group color is instance color" )
    }

    # ── 6. 可见性/激活过滤 ──────────────────────────────
    static void testVisibilityFilter()
    {
        Scene scene = Scene( "B6" )
        MaterialData mat = newMat( "m" )
        GameObject a = makeTri( scene, "A", null, mat, 0.0f, 0.0f )
        GameObject b = makeTri( scene, "B", null, mat, 1.0f, 0.0f )
        GameObject c = makeTri( scene, "C", null, mat, 2.0f, 0.0f )
        GameObject d = makeTri( scene, "D", null, mat, 3.0f, 0.0f )
        MeshRef bm = b.getComponent<MeshRef>()
        bm.visible = false
        a.setActive( false )
        GameObject child = makeTri( scene, "E", c, mat, 4.0f, 0.0f )
        GameObject grand = makeTri( scene, "F", child, mat, 5.0f, 0.0f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        check( bt.candidateCount() == 4, "B6a A(inactive)+B(hidden) filtered, C/D/E/F in" )
        # 禁用 C：整棵子树（C/E/F）剪枝
        c.setActive( false )
        bt.clear()
        bt.collect( scene, 1 )
        check( bt.candidateCount() == 1, "B6b inactive subtree pruned (only D)" )
    }

    # ── 7. 单对象直通路径（无顶点数据）──────────────────
    static void testSingleObjectPath()
    {
        Scene scene = Scene( "B7" )
        MaterialData mat = newMat( "m" )
        GameObject a = scene.createObject( "A" )
        MeshRef mr = MeshRef()
        mr.meshKind = 2
        a.addComponent( mr )
        MaterialRef ma = MaterialRef()
        ma.material = mat
        a.addComponent( ma )
        GameObject b = scene.createObject( "B" )
        MeshRef mr2 = MeshRef()
        mr2.meshKind = 2
        b.addComponent( mr2 )
        MaterialRef mb = MaterialRef()
        mb.material = mat
        b.addComponent( mb )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        bt.build()
        check( bt.groupCount() == 2, "B7a no-vertex members never merge" )
        BatchGroup g1 = bt.groupAt( 0 )
        check( g1.singleObject == true, "B7b single object path" )
        GameObject sole = g1.soleMember
        bool soleOk = ( sole == a ) || ( sole == b )
        check( soleOk, "B7c soleMember is the node" )
    }

    # ── 8. 256 上限拆批 + clear 复用 ────────────────────
    static void testCapAndReuse()
    {
        Scene scene = Scene( "B8" )
        MaterialData mat = newMat( "m" )
        Int32 i = 0
        while i < 300
        {
            string nm = "N" + i.toString()
            makeTri( scene, nm, null, mat, 0.0f, 0.0f )
            i = i + 1
        }
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        check( bt.candidateCount() == 300, "B8a 300 candidates" )
        bt.build()
        Int32 gc = bt.groupCount()
        check( gc == 2, "B8b cap 256 splits into 2 groups" )
        BatchGroup g1 = bt.groupAt( 0 )
        Int32 c1 = g1.memberCount()
        check( c1 == 256, "B8c first group full at 256" )
        BatchGroup g2 = bt.groupAt( 1 )
        Int32 c2 = g2.memberCount()
        check( c2 == 44, "B8d remainder 44" )
        # clear 复用
        bt.clear()
        check( bt.groupCount() == 0, "B8e clear resets groups" )
        bt.collect( scene, 1 )
        bt.build()
        Int32 gc2 = bt.groupCount()
        check( gc2 == 2, "B8f reusable after clear" )
    }

    # ── 9. 烘焙含旋转/缩放 ──────────────────────────────
    static void testBakeWithRotation()
    {
        Scene scene = Scene( "B9" )
        MaterialData mat = newMat( "m" )
        GameObject go = makeTri( scene, "R", null, mat, 10.0f, 20.0f )
        Transform t = go.transform
        t.setRotationZ( 1.5707963f )
        t.setScale( 2.0f )
        Batcher bt = Batcher()
        bt.collect( scene, 1 )
        bt.build()
        BatchGroup g = bt.groupAt( 0 )
        List<Float32_3> baked = List<Float32_3>( 0 )
        g.bakeVerticesInto( baked )
        Float32_3 v0 = baked[0]
        # local (0,1,0) ×2 → (0,2,0) → rotZ90 → (-2,0,0) → +pos(10,20) = (8,20,0)
        bool ok = ( v0.x == 8.0f ) && ( v0.y == 20.0f )
        check( ok, "B9 rotZ+scale baked into world vertex" )
    }

    public static void run()
    {
        Console.println( "=== SimBatchTest (SimGameEngine P2 batching smoke) ===" )
        testSharedMaterialBatch()
        testDifferentMaterialSplit()
        testQueueSplitAndOrder()
        testLayerAndMask()
        testColorOverrideSplit()
        testVisibilityFilter()
        testSingleObjectPath()
        testCapAndReuse()
        testBakeWithRotation()
        Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }

    # 计数读取（Test.sl 统一入口汇总用；不单独 exit，失败由入口统一判）
    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }
}
