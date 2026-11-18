import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# SceneDemo（doc/19）：按路径加载场景 + 脚本随帧循环跑 + O 键导出 JSON。
# 键位 1/2/3/4 切场景，WASD 移动相机，左键拖拽平移视角，滚轮缩放，O 导出，
# Esc 退出。
public class SceneDemo
{
    static SceneManager sm = null
    static RenderSystem rs = null
    static Int64 pixels = 0
    static string baseDir = ""
    static string lastInfo = ""
    static bool prev1 = false
    static bool prev2 = false
    static bool prev3 = false
    static bool prev4 = false
    static bool prevO = false
    # 相机操作状态（SL 侧权威值，每帧写回 rs.cameraCenter/viewSize——
    # 跨模块只整块赋值，不直写字段分量）
    static Float32 camX = 0.0f
    static Float32 camY = 2.5f
    static Float32 camView = 7.0f
    static Int32 prevMx = 0
    static Int32 prevMy = 0
    static bool prevMDown = false
    # 动态分辨率状态（Unity OnResize 语义：窗口变 → 渲染目标/像素块/
    # 显示 label 同步变）
    static Int32 renderW = 480
    static Int32 renderH = 480

    # 单位圆网格上传（自定义槽 0）：27 材质球共用该网格，各自 MVP/颜色不同
    static void initBallMesh()
    {
        List<Float32_3> verts = List<Float32_3>( 240 )
        Int32 seg = 40
        Int32 i = 0
        while i < seg
        {
            Float32 a0 = i.toFloat32() * 0.1570796f
            Float32 a1 = ( i + 1 ).toFloat32() * 0.1570796f
            Float32_3 c = Float32_3( 0.0f, 0.0f, 0.0f )
            Float32_3 p0 = Float32_3( Mathf.cos( a0 ), Mathf.sin( a0 ), 0.0f )
            Float32_3 p1 = Float32_3( Mathf.cos( a1 ), Mathf.sin( a1 ), 0.0f )
            verts.add( c )
            verts.add( p0 )
            verts.add( p1 )
            i = i + 1
        }
        bool ok = SceneDemo.rs.uploadMeshXyz( 0, verts )
        Console.println( "[scene] ball mesh upload ok=" + ok.toString() )
    }

    static string findSceneDir()
    {
        string cwd = IO.Directory.getCurrentDirectory()
        string c1 = cwd + "/assets/scenes"
        bool e1 = File.exists( c1 + "/MaterialBall.scene.json" )
        if e1
        {
            ret c1
        }
        string c2 = cwd + "/SlangAllInOne/SLangCore/Lib/SLang/SimGameEngine/gameExample/Test/assets/scenes"
        bool e2 = File.exists( c2 + "/MaterialBall.scene.json" )
        if e2
        {
            ret c2
        }
        ret "D:/project/lang/SlangAllInOne/SLangCore/Lib/SLang/SimGameEngine/gameExample/Test/assets/scenes"
    }

    static void loadScene( Int32 idx )
    {
        string name = "MaterialBall.scene.json"
        if idx == 1
        {
            name = "ShapeGallery.scene.json"
        }
        elif idx == 2
        {
            name = "PureTest.scene.json"
        }
        elif idx == 3
        {
            name = "MaterialGallery.scene.json"
        }
        string path = SceneDemo.baseDir + "/" + name
        Scene loaded = SceneDemo.sm.load( path )
        if loaded == null
        {
            Console.println( "[scene] load failed: " + SceneDemo.sm.lastError )
        }
        else
        {
            Console.println( "[scene] loaded " + loaded.name )
        }
        SceneDemo.updateInfo()
    }

    static void updateInfo()
    {
        string n = "none"
        Scene cur = SceneDemo.sm.activeScene
        if cur != null
        {
            n = cur.name
        }
        string nn = SceneDemo.sm.nodeCount.toString()
        string sn = SceneDemo.sm.scriptCount.toString()
        string ln = SceneDemo.rs.lightCount.toString()
        string on = SceneDemo.rs.lastSubmitted.toString()
        string s = "Scene: " + n + "   nodes=" + nn + "   scripts=" + sn + "   lights=" + ln + "   objs=" + on
        if !SceneDemo.sm.ok
        {
            s = s + "   ERR: " + SceneDemo.sm.lastError
        }
        if s != SceneDemo.lastInfo
        {
            SceneDemo.lastInfo = s
            QTHost.setInfo( s )
        }
    }

    # ── 动态分辨率（每帧调用）：探测窗口客户区尺寸，变化时重建渲染
    # 目标（rs.resize → slr_pipeline_resize，对象句柄保留）、重分配
    # 像素块、label 同步缩到新尺寸（顶部 60px 留信息条）。钳 [64,2048]。
    static void updateRenderTarget()
    {
        Int32 ww = QTHost.windowW()
        Int32 wh = QTHost.windowH()
        if ww < 80 || wh < 80
        {
            ret
        }
        Int32 w = ww - 16
        Int32 h = wh - 60
        if w < 64
        {
            w = 64
        }
        if h < 64
        {
            h = 64
        }
        if w > 2048
        {
            w = 2048
        }
        if h > 2048
        {
            h = 2048
        }
        if w == SceneDemo.renderW && h == SceneDemo.renderH
        {
            ret
        }
        bool ok = SceneDemo.rs.resize( w, h )
        if ok
        {
            Int64 old = SceneDemo.pixels
            if old != 0
            {
                Memory.free( old )
            }
            SceneDemo.pixels = Memory.alloc( w * h * 4 )
            SceneDemo.renderW = w
            SceneDemo.renderH = h
            QTHost.resizeView( w, h )
            Console.println( "[scene] render target " + w.toString() + "x" + h.toString() )
        }
    }

    # ── 相机操作（每帧调用，写回 SL 侧权威值）────────────────────
    # W/S 前后（世界 Y），A/D 左右（世界 X），每帧固定步长（60Hz 定时器）；
    # 左键按住拖拽 = 平移视角（内容跟随鼠标，全局坐标差值换算世界步长）；
    # 滚轮缩放（每格 ×0.85，上限 40 下限 1.5）。
    static void updateCamera()
    {
        Float32 step = 0.16f
        if QTHost.keyDown( 87 ) == 1
        {
            SceneDemo.camY = SceneDemo.camY + step
        }
        if QTHost.keyDown( 83 ) == 1
        {
            SceneDemo.camY = SceneDemo.camY - step
        }
        if QTHost.keyDown( 65 ) == 1
        {
            SceneDemo.camX = SceneDemo.camX - step
        }
        if QTHost.keyDown( 68 ) == 1
        {
            SceneDemo.camX = SceneDemo.camX + step
        }
        Int32 md = QTHost.mouseDown( 1 )
        Int32 mx = QTHost.mouseX()
        Int32 my = QTHost.mouseY()
        if md == 1 && SceneDemo.prevMDown
        {
            Int32 dxi = mx - SceneDemo.prevMx
            Int32 dyi = my - SceneDemo.prevMy
            Int32 rh = SceneDemo.renderH
            Float32 wpp = SceneDemo.camView * 2.0f / rh.toFloat32()
            Float32 dxw = dxi.toFloat32() * wpp
            Float32 dyw = dyi.toFloat32() * wpp
            SceneDemo.camX = SceneDemo.camX - dxw
            SceneDemo.camY = SceneDemo.camY + dyw
        }
        SceneDemo.prevMDown = md == 1
        SceneDemo.prevMx = mx
        SceneDemo.prevMy = my
        Int32 wn = QTHost.mouseWheelTake()
        while wn != 0
        {
            if wn > 0
            {
                SceneDemo.camView = SceneDemo.camView * 0.85f
            }
            else
            {
                SceneDemo.camView = SceneDemo.camView / 0.85f
            }
            if SceneDemo.camView < 1.5f
            {
                SceneDemo.camView = 1.5f
            }
            if SceneDemo.camView > 40.0f
            {
                SceneDemo.camView = 40.0f
            }
            wn = wn - 1
        }
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
    }

    static void frameTick()
    {
        Int32 k1 = QTHost.keyDown( 49 )
        Int32 k2 = QTHost.keyDown( 50 )
        Int32 k3 = QTHost.keyDown( 51 )
        Int32 k4 = QTHost.keyDown( 52 )
        Int32 ko = QTHost.keyDown( 79 )
        Int32 ke = QTHost.keyDown( 16777216 )
        bool p1 = k1 == 1 && !SceneDemo.prev1
        bool p2 = k2 == 1 && !SceneDemo.prev2
        bool p3 = k3 == 1 && !SceneDemo.prev3
        bool p4 = k4 == 1 && !SceneDemo.prev4
        bool po = ko == 1 && !SceneDemo.prevO
        SceneDemo.prev1 = k1 == 1
        SceneDemo.prev2 = k2 == 1
        SceneDemo.prev3 = k3 == 1
        SceneDemo.prev4 = k4 == 1
        SceneDemo.prevO = ko == 1
        if p1
        {
            SceneDemo.loadScene( 0 )
        }
        if p2
        {
            SceneDemo.loadScene( 1 )
        }
        if p3
        {
            SceneDemo.loadScene( 2 )
        }
        if p4
        {
            SceneDemo.loadScene( 3 )
        }
        if po
        {
            string outPath = SceneDemo.baseDir + "/exported.scene.json"
            bool saved = SceneDemo.sm.save( outPath, null )
            Console.println( "[scene] export ok=" + saved.toString() )
        }
        if ke == 1
        {
            OS.Kernel.exit( 0 )
        }
        SceneDemo.updateRenderTarget()
        SceneDemo.updateCamera()
        SceneDemo.sm.tick( -1.0f )
        SceneDemo.rs.sync( SceneDemo.sm.activeScene )
        Int64 pp = SceneDemo.pixels
        SceneDemo.rs.frame( 0.0f, pp )
        Int32 w = SceneDemo.renderW
        Int32 h = SceneDemo.renderH
        QTHost.blit( pp, w, h )
        SceneDemo.updateInfo()
    }

    public static void run()
    {
        SceneDemo.sm = SceneManager()
        SceneDemo.sm.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        SceneDemo.sm.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        SceneDemo.sm.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        SceneDemo.sm.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        SceneDemo.sm.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        Console.println( "[scene] scripts=" + SceneDemo.sm.scriptTypeCount().toString() )
        SceneDemo.baseDir = SceneDemo.findSceneDir()
        Console.println( "[scene] scenes at " + SceneDemo.baseDir )
        SceneDemo.rs = RenderSystem()
        SceneDemo.rs.init( 480, 480 )
        Float32 cx = SceneDemo.camX
        Float32 cy = SceneDemo.camY
        Float32_3 cc = Float32_3( cx, cy, 0.0f )
        SceneDemo.rs.cameraCenter = cc
        SceneDemo.rs.viewSize = SceneDemo.camView
        SceneDemo.pixels = Memory.alloc( 480 * 480 * 4 )
        SceneDemo.initBallMesh()
        SceneDemo.loadScene( 0 )
        QTHost.startHost( SceneDemo.frameTick )
    }
}
