import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# 无窗口冒烟（SceneDemo 工程的一种运行模式，`slang run ... -- smoke` 进入）：
# 按路径加载三个 scene.json、验证脚本挂载、跑帧、导出落盘再回读。
public class SceneSmokeTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            SceneSmokeTest._pass = SceneSmokeTest._pass + 1
        }
        else
        {
            SceneSmokeTest._fail = SceneSmokeTest._fail + 1
            Console.println( "FAIL: " + msg )
        }
    }

    static string sceneDir()
    {
        ret SceneDemo.findProjectDir() + "/assets/scenes"
    }

    static void runOne( string file, Int32 expectedNodes, Int32 expectedScripts, string tag )
    {
        SceneManager sm = SceneManager()
        sm.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        sm.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        sm.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        sm.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        sm.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        string path = SceneSmokeTest.sceneDir() + "/" + file
        Scene s = sm.load( path )
        bool loaded = s != null
        SceneSmokeTest.check( loaded, tag + " load" )
        if !loaded
        {
            Console.println( "  err=" + sm.lastError )
            ret
        }
        Int32 nn = sm.nodeCount
        SceneSmokeTest.check( nn == expectedNodes, tag + " nodeCount=" + nn.toString() )
        Int32 sc = sm.scriptCount
        SceneSmokeTest.check( sc == expectedScripts, tag + " scriptCount=" + sc.toString() )
        Int32 i = 0
        while i < 8
        {
            sm.tick( 0.016f )
            i = i + 1
        }
        # 编辑器 Gizmo 验证：ShapeGallery 里形状节点挂的 AxisGizmoScript
        # 若被 C VM 驱动，pushAxisAt 会经 GizmoSystem 往 X 色缓冲灌入顶点。
        if file == "ShapeGallery.scene.json"
        {
            if SceneDemo.gs == null
            {
                SceneDemo.gs = GizmoSystem()
            }
            SceneDemo.gs.setMode( GizmoTypes.MODE_MOVE )
            SceneDemo.beginAxisFrame()
            sm.tick( 0.016f )
            Int32 gv = SceneDemo.gs.vertexCountAt( 0 )
            SceneSmokeTest.check( gv > 0,
                tag + " axis gizmo verts=" + gv.toString() )
        }
        string json = sm.toJson( null )
        bool hasJson = json.length > 20
        SceneSmokeTest.check( hasJson, tag + " export json" )
        SceneManager round = SceneManager()
        round.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        round.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        round.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        round.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        round.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        Scene s2 = round.loadText( json )
        SceneSmokeTest.check( s2 != null, tag + " reload" )
        if s2 == null
        {
            Console.println( "  reload err=" + round.lastError )
        }
        if s2 != null
        {
            SceneSmokeTest.check( s2.rootCount == s.rootCount, tag + " reload roots" )
        }
        string outPath = "D:/project/lang/SlangAllInOne/out/tmp_scene_smoke_" + tag + ".json"
        bool saved = sm.save( outPath, null )
        SceneSmokeTest.check( saved, tag + " save file" )
        SceneManager fromDisk = SceneManager()
        fromDisk.registerScript( "ProbeScript", SceneScriptFactories.makeProbe )
        fromDisk.registerScript( "SphereMeshScript", SceneScriptFactories.makeSphereMesh )
        fromDisk.registerScript( "ShapeMeshScript", SceneScriptFactories.makeShapeMesh )
        fromDisk.registerScript( "SpinScript", SceneScriptFactories.makeSpin )
        fromDisk.registerScript( "LightSwingScript", SceneScriptFactories.makeLightSwing )
        Scene s3 = fromDisk.load( outPath )
        SceneSmokeTest.check( s3 != null, tag + " reload file" )
        if s3 == null
        {
            Console.println( "  reload file err=" + fromDisk.lastError )
        }
        File.delete( outPath )
        Console.println( "[smoke] " + tag + " OK" )
    }

    static string fairyDir()
    {
        ret SceneDemo.findProjectDir() + "/assets/fairygui/Demo"
    }

    static void runFairy()
    {
        SLang.Render.initialize()
        FairyPackage p = FairyPackage()
        bool ok = p.load( SceneSmokeTest.fairyDir() )
        SceneSmokeTest.check( ok, "FairyGUI package load" )
        if !ok
        {
            Console.println( "  err=" + p.lastError )
            ret
        }
        SceneSmokeTest.check( p.sprites.length == 4, "FairyGUI atlas sprites=" + p.sprites.length.toString() )
        SceneSmokeTest.check( p.quads.length == 7, "FairyGUI component quads=" + p.quads.length.toString() )
        SceneSmokeTest.check( p.designW == 480 && p.designH == 480, "FairyGUI design resolution" )
        FairyUIRenderer r = FairyUIRenderer()
        r.pkg = p
        Int32 verts = 0
        Int32 i = 0
        while i < p.quads.length
        {
            FairyQuad fq = p.quads[i]
            verts = verts + r.vertCountOf( fq )
            i = i + 1
        }
        SceneSmokeTest.check( verts == 186, "FairyGUI mesh verts=" + verts.toString() )
        FairyPackage bp = FairyPackage()
        bool fuiOk = bp.loadFui( SceneSmokeTest.fairyDir() )
        SceneSmokeTest.check( fuiOk, "FairyGUI fui package load" )
        if fuiOk
        {
            SceneSmokeTest.check( bp.sprites.length == 4, "FairyGUI fui sprites=" + bp.sprites.length.toString() )
            SceneSmokeTest.check( bp.quads.length == 7, "FairyGUI fui quads=" + bp.quads.length.toString() )
            Int32 bverts = 0
            Int32 j = 0
            while j < bp.quads.length
            {
                FairyQuad bq = bp.quads[j]
                bverts = bverts + r.vertCountOf( bq )
                j = j + 1
            }
            SceneSmokeTest.check( bverts == verts, "FairyGUI fui/XML shared mesh verts=" + bverts.toString() )
        }
        # 主入口菜单包 + 命中测试（5 个场景按钮）
        FairyPackage mp = FairyPackage()
        string menuPath = SceneDemo.findMainMenuDir()
        bool mok = mp.load( menuPath )
        SceneSmokeTest.check( mok, "FairyGUI main menu package load" )
        if mok
        {
            SceneSmokeTest.check( mp.quads.length == 13, "FairyGUI menu quads=" + mp.quads.length.toString() )
            FairyUIRenderer mr = FairyUIRenderer()
            mr.pkg = mp
            Int32 k = 0
            while k < 5
            {
                Int32 my = 174 + k * 58
                string hit = mr.hitTestLocal( 240, my, 480, 480 )
                Int32 idx = FairyUIRenderer.menuIndex( hit, "menu_" )
                SceneSmokeTest.check( idx == k, "FairyGUI menu hit " + k.toString() + " got " + idx.toString() )
                k = k + 1
            }
            string outHit = mr.hitTestLocal( 10, 10, 480, 480 )
            SceneSmokeTest.check( outHit.length == 0, "FairyGUI menu outside hit" )
        }
    }

    public static void run()
    {
        SceneSmokeTest.runOne( "MaterialBall.scene.json", 4, 8, "MaterialBall" )
        SceneSmokeTest.runOne( "ShapeGallery.scene.json", 11, 16, "ShapeGallery" )
        SceneSmokeTest.runOne( "PureTest.scene.json", 2, 2, "PureTest" )
        SceneSmokeTest.runOne( "MaterialGallery.scene.json", 30, 28, "MaterialGallery" )
        SceneSmokeTest.runFairy()
        Console.println( "=== SceneManager smoke PASS=" + SceneSmokeTest._pass.toString()
            + " FAIL=" + SceneSmokeTest._fail.toString() + " ===" )
        if SceneSmokeTest._fail > 0
        {
            OS.Kernel.exit( 1 )
        }
    }
}
