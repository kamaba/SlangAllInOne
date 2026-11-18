import Core;
import Std;
import Math;
import SimGameEngine;

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
        string cwd = IO.Directory.getCurrentDirectory()
        string c1 = cwd + "/SlangAllInOne/SLangCore/Lib/SLang/SimGameEngine/gameExample/Test/assets/scenes"
        bool e1 = File.exists( c1 + "/PureTest.scene.json" )
        if e1
        {
            ret c1
        }
        ret "D:/project/lang/SlangAllInOne/SLangCore/Lib/SLang/SimGameEngine/gameExample/Test/assets/scenes"
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

    public static void run()
    {
        SceneSmokeTest.runOne( "MaterialBall.scene.json", 4, 8, "MaterialBall" )
        SceneSmokeTest.runOne( "ShapeGallery.scene.json", 9, 14, "ShapeGallery" )
        SceneSmokeTest.runOne( "PureTest.scene.json", 2, 2, "PureTest" )
        SceneSmokeTest.runOne( "MaterialGallery.scene.json", 30, 28, "MaterialGallery" )
        Console.println( "=== SceneManager smoke PASS=" + SceneSmokeTest._pass.toString()
            + " FAIL=" + SceneSmokeTest._fail.toString() + " ===" )
        if SceneSmokeTest._fail > 0
        {
            OS.Kernel.exit( 1 )
        }
    }
}
