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

    # ── D13. RenderSystem 无头像素尺寸登记（宽高比适配前置）──
    static void testPixelSize()
    {
        RenderSystem rs = RenderSystem()
        check( rs.pixelWidth() == 0, "D13a default width 0" )
        rs.setPixelSize( 1280, 720 )
        check( rs.pixelWidth() == 1280, "D13b width registered" )
        check( rs.pixelHeight() == 720, "D13c height registered" )
        rs.setPixelSize( 1600, 900 )
        Float32 a = rs.aspectValue()
        bool aok = ( a > 1.77f ) && ( a < 1.78f )
        check( aok, "D13d aspect 16:9" )
        rs.setPixelSize( 720, 1280 )
        Float32 a2 = rs.aspectValue()
        bool a2ok = ( a2 > 0.56f ) && ( a2 < 0.57f )
        check( a2ok, "D13e portrait aspect" )
    }

    # ── D14. CameraRig2D 宽高比三模式 ──────────────────
    static void testRigFitModes()
    {
        RenderSystem rs = RenderSystem()
        rs.setPixelSize( 1600, 900 )
        CameraRig2D rig = CameraRig2D()
        rig.fitMode = 0
        rig.refSize = 5.4f
        Float32 v0 = rig.applyViewSize( rs )
        check( v0 == 5.4f, "D14a matchHeight refSize" )
        check( rs.viewSize == 5.4f, "D14b viewSize written" )
        rig.fitMode = 1
        rig.refSize = 8.0f
        Float32 v1 = rig.applyViewSize( rs )
        # 8 / (1600/900) = 4.5
        bool v1ok = ( v1 > 4.49f ) && ( v1 < 4.51f )
        check( v1ok, "D14c matchWidth refW/aspect" )
        rig.fitMode = 2
        rig.refPixelHeight = 300
        Float32 v2 = rig.applyViewSize( rs )
        # scale = floor(900/300)=3 → span 300 → half 150
        check( v2 == 150.0f, "D14d pixelPerfect scale 3" )
        rig.refPixelHeight = 400
        Float32 v3 = rig.applyViewSize( rs )
        # scale = floor(2.25)=2 → span 450 → half 225
        check( v3 == 225.0f, "D14e pixelPerfect scale 2" )
        rs.setPixelSize( 640, 200 )
        rig.refPixelHeight = 300
        Float32 v4 = rig.applyViewSize( rs )
        # scale = 0 → 下限 1 → half 100
        check( v4 == 100.0f, "D14f pixelPerfect min scale" )
    }

    # ── D15. 跟随 + 边界钳制 + 平滑 ────────────────────
    static void testRigFollowClamp()
    {
        Scene scene = Scene( "D15" )
        GameObject go = scene.createObject( "Player" )
        RenderSystem rs = RenderSystem()
        rs.setPixelSize( 800, 400 )
        CameraRig2D rig = CameraRig2D()
        rig.target = go
        rig.fitMode = 0
        rig.refSize = 5.0f
        Transform t = go.transform
        Float32_3 p = Float32_3( 100.0f, 50.0f, 0.0f )
        t.setPosition( p )
        # 首帧硬切跟随（无边界）
        rig.update( rs, 0.016f )
        check( rs.cameraCenter.x == 100.0f, "D15a follow hard x" )
        check( rs.cameraCenter.y == 50.0f, "D15b follow hard y" )
        # 边界钳制：viewSize=5 aspect=2 → 半视野 (10,5)
        rig.useBounds = true
        rig.boundMinX = 0.0f
        rig.boundMaxX = 20.0f
        rig.boundMinY = 0.0f
        rig.boundMaxY = 10.0f
        rig.update( rs, 0.016f )
        check( rs.cameraCenter.x == 10.0f, "D15c clamp x" )
        check( rs.cameraCenter.y == 5.0f, "D15d clamp y" )
        # 目标在自由区：不钳
        Float32_3 p2 = Float32_3( 10.0f, 5.0f, 0.0f )
        t.setPosition( p2 )
        rig.update( rs, 0.016f )
        check( rs.cameraCenter.x == 10.0f, "D15e center free" )
        # 地图纵向小于视野：居中（span 4 < 10 → y=2）
        rig.boundMaxY = 4.0f
        Float32_3 p3 = Float32_3( 10.0f, 3.0f, 0.0f )
        t.setPosition( p3 )
        rig.update( rs, 0.016f )
        check( rs.cameraCenter.y == 2.0f, "D15f small map centers" )
        # 平滑：τ=0.1 dt=0.1 → f=1-e^-1≈0.632；x 10→12
        rig.boundMaxY = 10.0f
        rig.useBounds = false
        rig.smoothTime = 0.1f
        Float32_3 p4 = Float32_3( 12.0f, 4.0f, 0.0f )
        t.setPosition( p4 )
        rig.update( rs, 0.1f )
        Float32 sx = rs.cameraCenter.x
        bool sxok = ( sx > 11.2f ) && ( sx < 11.3f )
        check( sxok, "D15g smooth lerp x" )
        # snap 后硬切
        rig.snap()
        rig.update( rs, 0.1f )
        check( rs.cameraCenter.x == 12.0f, "D15h snap hard cut" )
    }

    # ── D16. world→cell 换算（原点跟随节点）────────────
    static void testWorldToCell()
    {
        Scene scene = Scene( "D16" )
        GameObject go = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 4, 4 )
        go.addComponent( tm )
        Transform t = go.transform
        Float32_3 p = Float32_3( 10.0f, 5.0f, 0.0f )
        t.setPosition( p )
        check( tm.cellXAtWorld( 10.5f ) == 0, "D16a cell x at origin" )
        check( tm.cellXAtWorld( 12.5f ) == 2, "D16b cell x +2" )
        check( tm.cellYAtWorld( 7.5f ) == 2, "D16c cell y +2" )
        check( tm.cellXAtWorld( 9.9f ) == 0 - 1, "D16d negative cell" )
        check( tm.cellXAtWorld( 14.5f ) == 4, "D16e beyond width" )
        Float32_3 cc = tm.cellCenterWorld( 2, 1 )
        bool ccok = ( cc.x == 12.5f ) && ( cc.y == 6.5f )
        check( ccok, "D16f cell center roundtrip" )
    }

    # ── D17. tile 属性表（solid 位）────────────────────
    static void testTileFlags()
    {
        Scene scene = Scene( "D17" )
        GameObject go = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 3, 2 )
        tm.setTile( 0, 0, 1 )
        tm.setTile( 1, 0, 2 )
        tm.setTile( 0, 1, 3 )
        go.addComponent( tm )
        check( tm.tileFlag( 1 ) == 0, "D17a unregistered flag 0" )
        tm.setTileFlag( 1, 1 )
        tm.setTileFlag( 2, 2 )
        check( tm.tileFlag( 1 ) == 1, "D17b flag set" )
        check( tm.tileFlag( 2 ) == 2, "D17c flag multi-bit" )
        check( tm.tileFlag( 99 ) == 0, "D17d oob index 0" )
        check( tm.isSolidAt( 0, 0 ), "D17e tile1 solid" )
        check( !tm.isSolidAt( 1, 0 ), "D17f tile2 bit0 clear" )
        check( !tm.isSolidAt( 0, 1 ), "D17g tile3 unsolid" )
        tm.setTileFlag( 2, 1 )
        check( tm.isSolidAt( 1, 0 ), "D17h tile2 solid after flag" )
        tm.setTile( 2, 0, 0 - 1 )
        check( !tm.isSolidAt( 2, 0 ), "D17i empty cell unsolid" )
        # 稀疏索引扩容
        tm.setTileFlag( 5, 1 )
        check( tm.tileFlag( 5 ) == 1, "D17j sparse grow" )
        check( tm.tileFlag( 3 ) == 0, "D17k gap default 0" )
        tm.setTileFlag( 0 - 1, 7 )
        check( tm.tileFlag( 7 ) == 0, "D17l negative index ignored" )
    }

    # ── D18. tile 实心格行合并碰撞体 ───────────────────
    static void testColliderBaker()
    {
        Scene scene = Scene( "D18" )
        GameObject mapGo = scene.createObject( "Map" )
        Tilemap tm = Tilemap()
        tm.resize( 4, 2 )
        # 行 0：格 0,1 一段（len2）+ 格 3 一段（len1）；格 2 空
        tm.setTile( 0, 0, 1 )
        tm.setTile( 1, 0, 1 )
        tm.setTile( 3, 0, 2 )
        # 行 1：格 0
        tm.setTile( 0, 1, 1 )
        tm.setTileFlag( 1, 1 )
        tm.setTileFlag( 2, 1 )
        mapGo.addComponent( tm )
        GameObject parent = scene.createObject( "Colliders" )
        Int32 made = TileColliderBaker.bakeRowColliders( scene, tm, parent, "Seg" )
        check( made == 3, "D18a three runs" )
        check( parent.childCount == 3, "D18b three children" )
        GameObject seg0 = parent.getChild( 0 )
        BoxCollider bc = seg0.getComponent<BoxCollider>()
        check( bc != null, "D18c collider attached" )
        # 段 0：格 0..1 行 0 → center (1.0, 0.5)
        Transform t0 = seg0.transform
        Float32_3 p0 = t0.localPosition
        check( p0.x == 1.0f, "D18d run center x" )
        check( p0.y == 0.5f, "D18e run center y" )
        Float32_3 s0 = bc.size
        check( s0.x == 2.0f, "D18f run size len2" )
        # 段 2：行 1 格 0 → center (0.5, 1.5)
        GameObject seg2 = parent.getChild( 2 )
        Transform t2 = seg2.transform
        Float32_3 p2 = t2.localPosition
        check( p2.x == 0.5f, "D18g row1 run x" )
        check( p2.y == 1.5f, "D18h row1 run y" )
    }

    # ── D19. ParallaxLayer 视差系数 ────────────────────
    static void testParallaxLayer()
    {
        Scene scene = Scene( "D19" )
        GameObject bg = scene.createObject( "BG" )
        ParallaxLayer pl = ParallaxLayer()
        pl.factorX = 0.5f
        pl.factorY = 1.0f
        bg.addComponent( pl )
        Transform t = bg.transform
        Float32_3 p = Float32_3( 10.0f, 4.0f, 0.0f )
        t.setPosition( p )
        # 首次 apply 自动捕获基准位
        Float32_3 cam0 = Float32_3.zero()
        pl.apply( cam0 )
        Float32_3 bp = pl.basePosition()
        bool bpok = ( bp.x == 10.0f ) && ( bp.y == 4.0f )
        check( bpok, "D19a base captured" )
        # 相机 (4,2)：dx = 4*(1-0.5)=2, dy = 2*(1-1)=0 → (12,4)
        Float32_3 cam1 = Float32_3( 4.0f, 2.0f, 0.0f )
        pl.apply( cam1 )
        Float32_3 p1 = t.worldPosition()
        bool p1ok = ( p1.x == 12.0f ) && ( p1.y == 4.0f )
        check( p1ok, "D19b parallax offset" )
        # factor 0：完全贴屏（base + camOffset 全量）
        pl.factorX = 0.0f
        pl.factorY = 0.0f
        pl.apply( cam1 )
        Float32_3 p2 = t.worldPosition()
        bool p2ok = ( p2.x == 14.0f ) && ( p2.y == 6.0f )
        check( p2ok, "D19c factor 0 glued" )
        # factor 1：随世界（不动）
        pl.factorX = 1.0f
        pl.factorY = 1.0f
        pl.apply( cam1 )
        Float32_3 p3 = t.worldPosition()
        check( p3.x == 10.0f, "D19d factor 1 static" )
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
        testPixelSize()
        testRigFitModes()
        testRigFollowClamp()
        testWorldToCell()
        testTileFlags()
        testColliderBaker()
        testParallaxLayer()
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
