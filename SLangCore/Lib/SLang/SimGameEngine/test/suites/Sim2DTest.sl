import SimGameEngine;
import SLangRender;
import Std;
import SLangRender;
import Math;
import SLangRender;

# ============================================================================
# Sim2DTest — SimGameEngine P7 2D 渲染验证（第 9 套）
# ----------------------------------------------------------------------------
# 覆盖：SortingLayers 基值/钳位/越界回退 + RenderSystem.collect2D 收集
#       （激活/掩码/visible 过滤、queue 排序、pivot 偏移、着色透传）+
#       sync2D 无管线优雅 -1 + Tilemap 数据（resize/set/get/越界）+
#       顶点烘焙（全量/相机裁剪/世界原点跟随节点）。
# 写法约束（doc/10 §6）：跨模块静态工厂不可用（构造器 + addComponent）；
# 跨模块数值字段读走 getter 方法；内联构造表达式不作实参；`base`/`half`/
# `out`/`dynamic` 是保留字；`&&` 只写双操作数；不用 `continue`/递归。
# ============================================================================

public class Sim2DTest
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

    # 本地精灵工厂（跨模块静态工厂经 IR 签名错位不可用，doc/10 §6）
    static GameObject makeSprite( Scene scene, string name, GameObject parent, Int32 nodeLayer, Int32 sortLayer, Int32 order, Float32 x, Float32 y )
    {
        GameObject go = scene.createObject( name, parent )
        go.layer = nodeLayer
        SpriteRenderer sr = SpriteRenderer()
        sr.setSorting( sortLayer, order )
        go.addComponent( sr )
        Transform t = go.transform
        Float32_3 pos = Float32_3( x, y, 0.0f )
        t.setPosition( pos )
        ret go
    }

    # ── D1. SortingLayers 映射 ─────────────────────────
    static void testSortingLayers()
    {
        SortingLayers sl = SortingLayers()
        check( sl.queueOf( 0, 0 ) == 2500, "D1a layer0 base 2500" )
        check( sl.queueOf( 3, 0 ) == 2800, "D1b layer3 base 2800" )
        sl.setBase( 2, 5000 )
        check( sl.queueOf( 2, 0 ) == 5000, "D1c setBase override" )
        check( sl.queueOf( 1, 10 ) == 2610, "D1d order offset" )
        check( sl.queueOf( 1, 500 ) == 2699, "D1e order clamp 99" )
        check( sl.queueOf( 9, 0 ) == 2500, "D1f layer out-of-range fallback" )
        check( sl.queueOf( 0 - 1, 0 ) == 2500, "D1g negative layer fallback" )
    }

    # ── D2. 收集基础 + 无管线优雅失败 ──────────────────
    static void testCollectBasics()
    {
        Scene scene = Scene( "D2" )
        makeSprite( scene, "S0", null, 0, 0, 0, 1.0f, 2.0f )
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        check( rs.spriteCount() == 1, "D2a collect 1 sprite" )
        check( rs.spriteQueueAt( 0 ) == 2500, "D2b default queue" )
        check( rs.spriteAlphaAt( 0 ) == 1.0f, "D2c default alpha" )
        check( rs.spriteWidthAt( 0 ) == 1.0f, "D2d default width" )
        check( rs.spriteWorldXAt( 0 ) == 1.0f, "D2e world x passthrough" )
        check( rs.spriteWorldYAt( 0 ) == 2.0f, "D2f world y passthrough" )
        check( rs.sync2D() == 0 - 1, "D2g sync2D no-pipe graceful -1" )
    }

    # ── D3. 同层 order 排序（收集序稳定）───────────────
    static void testOrderSorting()
    {
        Scene scene = Scene( "D3" )
        makeSprite( scene, "A", null, 0, 0, 20, 0.0f, 0.0f )
        makeSprite( scene, "B", null, 0, 0, 10, 0.0f, 0.0f )
        makeSprite( scene, "C", null, 0, 0, 0, 0.0f, 0.0f )
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        check( rs.spriteCount() == 3, "D3a collect 3" )
        check( rs.spriteQueueAt( 0 ) == 2500, "D3b first = order 0" )
        check( rs.spriteQueueAt( 1 ) == 2510, "D3c second = order 10" )
        check( rs.spriteQueueAt( 2 ) == 2520, "D3d third = order 20" )
    }

    # ── D4. 排序层分层 + 基值覆盖 ──────────────────────
    static void testLayerSplit()
    {
        Scene scene = Scene( "D4" )
        makeSprite( scene, "L0", null, 0, 0, 0, 0.0f, 0.0f )
        makeSprite( scene, "L2", null, 0, 2, 0, 0.0f, 0.0f )
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        check( rs.spriteQueueAt( 0 ) == 2500, "D4a layer0 first" )
        check( rs.spriteQueueAt( 1 ) == 2700, "D4b layer2 base 2700" )
        rs.setLayerBase( 0, 3000 )
        rs.collect2D( scene, 1 )
        # 覆盖后 L0=3000 > L2=2700：排序后 2700 在前（升序）
        check( rs.spriteQueueAt( 0 ) == 2700, "D4c layer2 sorts first" )
        check( rs.spriteQueueAt( 1 ) == 3000, "D4d setLayerBase override effective" )
    }

    # ── D5. 过滤：未激活 / invisible / 掩码 ────────────
    static void testFiltering()
    {
        Scene scene = Scene( "D5" )
        GameObject dead = makeSprite( scene, "dead", null, 0, 0, 0, 0.0f, 0.0f )
        dead.setActive( false )
        makeSprite( scene, "masked", null, 3, 0, 0, 0.0f, 0.0f )
        GameObject hidden = makeSprite( scene, "hidden", null, 0, 0, 0, 0.0f, 0.0f )
        SpriteRenderer hsr = hidden.getComponent<SpriteRenderer>()
        hsr.visible = false
        makeSprite( scene, "alive", null, 0, 0, 0, 0.0f, 0.0f )
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        check( rs.spriteCount() == 1, "D5a only visible+active+masked survives" )
    }

    # ── D6. 着色与透明度透传 ───────────────────────────
    static void testTintAlpha()
    {
        Scene scene = Scene( "D6" )
        GameObject go = makeSprite( scene, "S", null, 0, 0, 0, 0.0f, 0.0f )
        SpriteRenderer sr = go.getComponent<SpriteRenderer>()
        sr.setTint( 1.0f, 0.0f, 0.5f )
        sr.colorAlpha = 0.5f
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        Float32_3 col = rs.spriteColorAt( 0 )
        check( col.x == 1.0f, "D6a tint r" )
        check( col.y == 0.0f, "D6b tint g" )
        check( col.z == 0.5f, "D6c tint b" )
        check( rs.spriteAlphaAt( 0 ) == 0.5f, "D6d alpha passthrough" )
    }

    # ── D7. pivot 偏移（世界缩放计入）──────────────────
    static void testPivotOffset()
    {
        Scene scene = Scene( "D7" )
        GameObject go = makeSprite( scene, "P", null, 0, 0, 0, 5.0f, 3.0f )
        SpriteRenderer sr = go.getComponent<SpriteRenderer>()
        Float32_2 sz = Float32_2( 2.0f, 4.0f )
        sr.size = sz
        Float32_2 pv = Float32_2( 0.0f, 0.0f )
        sr.pivot = pv
        RenderSystem rs = RenderSystem()
        rs.collect2D( scene, 1 )
        check( rs.spriteWorldXAt( 0 ) == 4.0f, "D7a pivot(0,0) x-1" )
        check( rs.spriteWorldYAt( 0 ) == 1.0f, "D7b pivot(0,0) y-2" )
        check( rs.spriteWidthAt( 0 ) == 2.0f, "D7c size passthrough" )
        check( rs.spriteHeightAt( 0 ) == 4.0f, "D7d height passthrough" )
    }

    # ── D8. 翻转登记 / 贴图 id getter ──────────────────
    static void testFlipSprite()
    {
        Scene scene = Scene( "D8" )
        GameObject go = makeSprite( scene, "F", null, 0, 0, 0, 0.0f, 0.0f )
        SpriteRenderer sr = go.getComponent<SpriteRenderer>()
        sr.setFlip( true, false )
        sr.setSprite( 7 )
        check( sr.isFlippedX(), "D8a flipX on" )
        check( !sr.isFlippedY(), "D8b flipY off" )
        check( sr.getTextureId() == 7, "D8c textureId getter" )
    }

    # ── D9. Tilemap 数据层 ─────────────────────────────
    static void testTilemapData()
    {
        Tilemap tm = Tilemap()
        tm.resize( 2, 3 )
        check( tm.getTile( 0, 0 ) == 0 - 1, "D9a resize fills -1" )
        check( tm.inBounds( 1, 2 ), "D9b inBounds last cell" )
        check( !tm.inBounds( 2, 2 ), "D9c out of bounds x" )
        check( !tm.inBounds( 1, 3 ), "D9d out of bounds y" )
        tm.setTile( 1, 2, 5 )
        check( tm.getTile( 1, 2 ) == 5, "D9e set/get roundtrip" )
        tm.setTile( 0 - 1, 0, 9 )
        check( tm.getTile( 0 - 1, 0 ) == 0 - 1, "D9f oob set ignored" )
        tm.setTile( 2, 0, 9 )
        check( tm.getTile( 2, 0 ) == 0 - 1, "D9g oob set ignored 2" )
        check( tm.tileCount() == 1, "D9h tileCount 1" )
    }

    # ── D10. 烘焙全量（2×2 三格）───────────────────────
    static void testBakeAll()
    {
        Scene scene = Scene( "D10" )
        GameObject go = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 2, 2 )
        tm.setTile( 0, 0, 1 )
        tm.setTile( 1, 0, 2 )
        tm.setTile( 0, 1, 3 )
        go.addComponent( tm )
        List<Float32_3> baked = List<Float32_3>( 0 )
        Int32 n = tm.bakeAll( baked )
        check( n == 3, "D10a bakeAll 3 cells" )
        Int32 vn = baked.length
        check( vn == 18, "D10b 18 vertices" )
        # 格 (0,0) 中心 (0.5,0.5)：quad a(0,0) c(1,1)
        Float32_3 v0 = baked[0]
        bool v0ok = ( v0.x == 0.0f ) && ( v0.y == 0.0f )
        check( v0ok, "D10c cell(0,0) first vertex" )
        Float32_3 v2 = baked[2]
        bool v2ok = ( v2.x == 1.0f ) && ( v2.y == 1.0f )
        check( v2ok, "D10d cell(0,0) third vertex" )
        # 格 (1,0) 中心 (1.5,0.5)：首顶点 (1.0,0.0)
        Float32_3 v6 = baked[6]
        bool v6ok = ( v6.x == 1.0f ) && ( v6.y == 0.0f )
        check( v6ok, "D10e cell(1,0) first vertex" )
        # 格 (0,1) 中心 (0.5,1.5)：首顶点 (0.0,1.0)
        Float32_3 v12 = baked[12]
        bool v12ok = ( v12.x == 0.0f ) && ( v12.y == 1.0f )
        check( v12ok, "D10f cell(0,1) first vertex" )
    }

    # ── D11. 烘焙相机裁剪 ──────────────────────────────
    static void testBakeCulling()
    {
        Scene scene = Scene( "D11" )
        GameObject go = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 2, 2 )
        tm.setTile( 0, 0, 1 )
        tm.setTile( 1, 0, 2 )
        tm.setTile( 0, 1, 3 )
        go.addComponent( tm )
        # 相机 [0,2]×[0,2]：三格中心都在界内（外扩半格）
        List<Float32_3> wide = List<Float32_3>( 0 )
        Int32 nw = tm.bake( 0.0f, 2.0f, 0.0f, 2.0f, wide )
        check( nw == 3, "D11a wide camera bakes 3" )
        # 相机 [0,1]×[0,1]：只 (0,0) 中心 (0.5,0.5) 在界内
        List<Float32_3> tight = List<Float32_3>( 0 )
        Int32 nt = tm.bake( 0.0f, 1.0f, 0.0f, 1.0f, tight )
        check( nt == 1, "D11b tight camera bakes 1" )
        Int32 vn = tight.length
        check( vn == 6, "D11c 6 vertices" )
    }

    # ── D12. 世界原点跟随挂载节点 ──────────────────────
    static void testWorldOrigin()
    {
        Scene scene = Scene( "D12" )
        GameObject go = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 2, 1 )
        tm.setTile( 0, 0, 1 )
        tm.setTile( 1, 0, 2 )
        go.addComponent( tm )
        Transform t = go.transform
        Float32_3 pos = Float32_3( 10.0f, 5.0f, 0.0f )
        t.setPosition( pos )
        Float32_3 cc = tm.cellCenterWorld( 0, 0 )
        bool ccok = ( cc.x == 10.5f ) && ( cc.y == 5.5f )
        check( ccok, "D12a cell(0,0) center follows node" )
        Float32_3 cc2 = tm.cellCenterWorld( 1, 0 )
        bool cc2ok = ( cc2.x == 11.5f ) && ( cc2.y == 5.5f )
        check( cc2ok, "D12b cell(1,0) center" )
        List<Float32_3> baked = List<Float32_3>( 0 )
        Int32 n = tm.bakeAll( baked )
        check( n == 2, "D12c bakeAll 2 cells" )
        Float32_3 v0 = baked[0]
        bool v0ok = ( v0.x == 10.0f ) && ( v0.y == 5.0f )
        check( v0ok, "D12d first vertex at node origin" )
    }

    public static void run()
    {
        testSortingLayers()
        testCollectBasics()
        testOrderSorting()
        testLayerSplit()
        testFiltering()
        testTintAlpha()
        testPivotOffset()
        testFlipSprite()
        testTilemapData()
        testBakeAll()
        testBakeCulling()
        testWorldOrigin()
        Console.println( "Sim2DTest: PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
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
