import SimGameEngine;
import SLangRender;
import Math;
import Std;

# ============================================================================
# SimUICanvasTest — UI 画布两模式 + 引擎层图层叠加（第 17 套，doc/08 §8）
# ----------------------------------------------------------------------------
# 覆盖：UICanvas 数据面（默认值/校验/setter/getter）、UICanvasSystem 场景收集
# 与排序（overlay 先/camera 次/world 后，同模式按 sortingOrder）、相机赋值
# 门控（无相机报错不崩）、C 图层叠加核心（ALPHA/ADD/MULTIPLY 像素真值）、
# Systems.setupCanvas / compositeLayer 门面。
# 不依赖 GL：configure 用未就绪 rs 走 -1 分支（纯 SL 契约验证），
# 像素断言直接对 Memory RGBA8 块调 C 核心，稳定可复现。
# 写法约束（doc/10 §6）：常量先落局部；triple && 拆分；下标先落局部 Int32。
# ============================================================================

public class SimUICanvasTest
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

    # ── U1. UICanvas 默认值与常量 ────────────────────────
    static void testDefaults()
    {
        UICanvas cv = UICanvas()
        Int32 mo = UICanvas.MODE_SCREEN_OVERLAY
        Int32 mc = UICanvas.MODE_CAMERA
        Int32 mw = UICanvas.MODE_WORLD
        check( mo == 0 && mc == 1 && mw == 2, "U1a mode constants" )
        check( cv.renderMode == 0, "U1b default overlay mode" )
        check( cv.uiLayer == 31, "U1c default UI layer 31" )
        check( cv.sortingOrder == 0, "U1d default sorting order" )
        check( cv.clearFlags == 2, "U1e default depth-only clear" )
        check( cv.hasCamera() == false, "U1f no camera by default" )
        Int32 fa = UICanvas.FLAGS_ALL
        check( fa == 3, "U1g FLAGS_ALL constant" )
    }

    # ── U2. setter 校验路径 ──────────────────────────────
    static void testSetters()
    {
        UICanvas cv = UICanvas()
        cv.setRenderMode( 1 )
        check( cv.getRenderMode() == 1, "U2a set camera mode" )
        cv.setRenderMode( 9 )
        check( cv.getRenderMode() == 1, "U2b invalid mode rejected" )
        check( cv.lastError == "invalid render mode", "U2c invalid mode error text" )
        cv.setLayer( 24 )
        check( cv.getLayer() == 24, "U2d set layer" )
        cv.setLayer( 40 )
        check( cv.getLayer() == 24, "U2e invalid layer rejected" )
        cv.setSortingOrder( 7 )
        check( cv.sortingOrder == 7, "U2f sorting order" )
        cv.setReferenceSize( 1920.0f, 1080.0f )
        check( cv.referenceWidth == 1920.0f, "U2g reference width" )
        cv.setScaleFactor( 2.0f )
        check( cv.scaleFactor == 2.0f, "U2h scale factor" )
        cv.setClearFlags( 3 )
        check( cv.clearFlags == 3, "U2i clear flags" )
        cv.setPixelPerfect( true )
        check( cv.pixelPerfect, "U2j pixel perfect" )
    }

    # ── U3. 场景收集 + 排序 ──────────────────────────────
    static void testCollect()
    {
        Scene scene = Scene( "CanvasScene" )
        # camera 模式，order 高（应排后面）
        GameObject a = scene.createObject( "CameraCanvas" )
        UICanvas ca = UICanvas()
        ca.setRenderMode( 1 )
        ca.setSortingOrder( 5 )
        ca.setLayer( 30 )
        a.addComponent( ca )
        # overlay 模式（应排最前）
        GameObject b = scene.createObject( "OverlayCanvas" )
        UICanvas cb = UICanvas()
        cb.setRenderMode( 0 )
        b.addComponent( cb )
        # camera 模式，order 低（应排在另一个 camera 前）
        GameObject c = scene.createObject( "CameraCanvasLow" )
        UICanvas cc = UICanvas()
        cc.setRenderMode( 1 )
        cc.setSortingOrder( 1 )
        c.addComponent( cc )
        # world 模式（最后）
        GameObject d = scene.createObject( "WorldCanvas" )
        UICanvas cd = UICanvas()
        cd.setRenderMode( 2 )
        d.addComponent( cd )
        # 非画布节点（不收集）
        scene.createObject( "Plain" )

        UICanvasSystem sys = UICanvasSystem()
        Int32 n = sys.collect( scene )
        check( n == 4, "U3a collect 4 canvases" )
        check( sys.overlayCount == 1, "U3b overlay count" )
        check( sys.cameraCount == 2, "U3c camera count" )
        check( sys.worldCount == 1, "U3d world count" )
        check( sys.modeAt( 0 ) == 0, "U3e overlay first" )
        Int32 m1 = sys.modeAt( 1 )
        Int32 m2 = sys.modeAt( 2 )
        check( m1 == 1 && m2 == 1, "U3f camera next" )
        check( sys.modeAt( 3 ) == 2, "U3g world last" )
        UICanvas low = sys.canvasAt( 1 )
        check( low.sortingOrder == 1, "U3h lower sorting order first within camera" )
        UICanvas hi = sys.canvasAt( 2 )
        check( hi.sortingOrder == 5, "U3i higher order later" )
        check( sys.canvasAt( 9 ) == null, "U3j out-of-range returns null" )

        # 禁用节点不收集
        a.setActive( false )
        Int32 n2 = sys.collect( scene )
        check( n2 == 3, "U3k inactive canvas excluded" )
    }

    # ── U4. configure 未就绪 rs 走错误分支 ────────────────
    static void testConfigureGuard()
    {
        UICanvasSystem sys = UICanvasSystem()
        RenderSystem rs = RenderSystem()
        Int32 r = sys.configure( rs )
        check( r == 0 - 1, "U4a configure returns -1 when render not ready" )
        check( sys.lastError == "render system not ready", "U4b error text" )
        Int32 r2 = sys.configure( null )
        check( r2 == 0 - 1, "U4c null render system guarded" )
    }

    # ── U5. C 图层叠加核心：ALPHA ────────────────────────
    static void testCompositeAlpha()
    {
        Int32 n = 2
        Int64 dst = Memory.alloc( n * 4 )
        Int64 lay = Memory.alloc( n * 4 )
        Memory.writeI8( dst, 0, 0 )
        Memory.writeI8( dst, 1, 0 )
        Memory.writeI8( dst, 2, 0 )
        Memory.writeI8( dst, 3, 255 )
        Memory.writeI8( dst, 4, 100 )
        Memory.writeI8( dst, 5, 100 )
        Memory.writeI8( dst, 6, 100 )
        Memory.writeI8( dst, 7, 255 )
        # layer 全不透明红
        Memory.writeI8( lay, 0, 200 )
        Memory.writeI8( lay, 1, 0 )
        Memory.writeI8( lay, 2, 0 )
        Memory.writeI8( lay, 3, 255 )
        Memory.writeI8( lay, 4, 200 )
        Memory.writeI8( lay, 5, 0 )
        Memory.writeI8( lay, 6, 0 )
        Memory.writeI8( lay, 7, 255 )
        Int32 mode = UICanvasSystem.BLEND_ALPHA
        Int32 done = EngineFfi.libLayerComposite( dst, lay, n, 1.0f, mode )
        check( done == n, "U5a composite returns pixel count" )
        Int32 r0 = Memory.readUInt8( dst, 0 )
        Int32 g0 = Memory.readUInt8( dst, 1 )
        check( r0 == 200 && g0 == 0, "U5b opaque alpha full overwrite pixel0" )
        Int32 r1 = Memory.readUInt8( dst, 4 )
        check( r1 == 200, "U5c pixel1 overwritten" )
        Memory.free( dst )
        Memory.free( lay )
    }

    # ── U6. C 图层叠加核心：半透明 ALPHA（50% 混合）──────
    static void testCompositeAlphaHalf()
    {
        Int64 dst = Memory.alloc( 4 )
        Int64 lay = Memory.alloc( 4 )
        Memory.writeI8( dst, 0, 0 )
        Memory.writeI8( dst, 1, 0 )
        Memory.writeI8( dst, 2, 0 )
        Memory.writeI8( dst, 3, 255 )
        Memory.writeI8( lay, 0, 200 )
        Memory.writeI8( lay, 1, 0 )
        Memory.writeI8( lay, 2, 0 )
        Memory.writeI8( lay, 3, 255 )
        Int32 mode = UICanvasSystem.BLEND_ALPHA
        Int32 done = EngineFfi.libLayerComposite( dst, lay, 1, 0.5f, mode )
        check( done == 1, "U6a half alpha returns 1" )
        Int32 r = Memory.readUInt8( dst, 0 )
        check( r >= 99 && r <= 101, "U6b 50% alpha red ~= 100 (r=" + r.toString() + ")" )
        Memory.free( dst )
        Memory.free( lay )
    }

    # ── U7. C 图层叠加核心：ADD ─────────────────────────
    static void testCompositeAdd()
    {
        Int64 dst = Memory.alloc( 4 )
        Int64 lay = Memory.alloc( 4 )
        Memory.writeI8( dst, 0, 100 )
        Memory.writeI8( dst, 1, 50 )
        Memory.writeI8( dst, 2, 0 )
        Memory.writeI8( dst, 3, 255 )
        Memory.writeI8( lay, 0, 80 )
        Memory.writeI8( lay, 1, 30 )
        Memory.writeI8( lay, 2, 255 )
        Memory.writeI8( lay, 3, 255 )
        Int32 mode = UICanvasSystem.BLEND_ADD
        Int32 done = EngineFfi.libLayerComposite( dst, lay, 1, 1.0f, mode )
        check( done == 1, "U7a add returns 1" )
        Int32 r = Memory.readUInt8( dst, 0 )
        Int32 g = Memory.readUInt8( dst, 1 )
        Int32 b = Memory.readUInt8( dst, 2 )
        check( r == 180 && g == 80 && b == 255, "U7b additive saturating" )
        Memory.free( dst )
        Memory.free( lay )
    }

    # ── U8. C 图层叠加核心：MULTIPLY ────────────────────
    static void testCompositeMultiply()
    {
        Int64 dst = Memory.alloc( 4 )
        Int64 lay = Memory.alloc( 4 )
        Memory.writeI8( dst, 0, 200 )
        Memory.writeI8( dst, 1, 200 )
        Memory.writeI8( dst, 2, 200 )
        Memory.writeI8( dst, 3, 255 )
        Memory.writeI8( lay, 0, 128 )
        Memory.writeI8( lay, 1, 64 )
        Memory.writeI8( lay, 2, 0 )
        Memory.writeI8( lay, 3, 255 )
        Int32 mode = UICanvasSystem.BLEND_MULTIPLY
        Int32 done = EngineFfi.libLayerComposite( dst, lay, 1, 1.0f, mode )
        check( done == 1, "U8a multiply returns 1" )
        Int32 r = Memory.readUInt8( dst, 0 )
        Int32 g = Memory.readUInt8( dst, 1 )
        Int32 b = Memory.readUInt8( dst, 2 )
        check( r > 99 && r < 103, "U8b multiply 200*128/255 ~= 100 (r=" + r.toString() + ")" )
        check( g > 49 && g < 53, "U8c multiply 200*64/255 ~= 50 (g=" + g.toString() + ")" )
        check( b == 0, "U8d multiply by zero" )
        Memory.free( dst )
        Memory.free( lay )
    }

    # ── U9. UICanvasSystem.composite 参数门控 ────────────
    static void testCompositeGuard()
    {
        UICanvasSystem sys = UICanvasSystem()
        Int64 dst = Memory.alloc( 4 )
        Int64 lay = Memory.alloc( 4 )
        bool b1 = sys.composite( 0, lay, 1, 1, 1.0f, 0 )
        check( b1 == false, "U9a null dst rejected" )
        bool b2 = sys.composite( dst, lay, 0, 1, 1.0f, 0 )
        check( b2 == false, "U9b zero width rejected" )
        bool b3 = sys.composite( dst, lay, 1, 1, 2.0f, 0 )
        check( b3 == false, "U9c bad alpha rejected" )
        bool b4 = sys.composite( dst, lay, 1, 1, 1.0f, 9 )
        check( b4 == false, "U9d bad mode rejected" )
        bool b5 = sys.composite( dst, lay, 1, 1, 1.0f, 0 )
        check( b5, "U9e valid composite ok" )
        check( sys.lastCompositePixels == 1, "U9f composite pixel count recorded" )
        Memory.free( dst )
        Memory.free( lay )
    }

    # ── U10. Systems 门面（未 init 的 canvas 字段存在）────
    static void testSystemsFacade()
    {
        Systems sys = Systems()
        UICanvasSystem cs = sys.canvas
        check( cs != null, "U10a Systems.canvas present" )
        check( cs.canvasCount == 0, "U10b canvas system initially empty" )
    }

    public static void run()
    {
        Console.println( "=== SimUICanvasTest (UI canvas modes + layer composite) ===" )
        testDefaults()
        testSetters()
        testCollect()
        testConfigureGuard()
        testCompositeAlpha()
        testCompositeAlphaHalf()
        testCompositeAdd()
        testCompositeMultiply()
        testCompositeGuard()
        testSystemsFacade()
        Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
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
