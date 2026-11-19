import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimSceneAdditiveTest — Additive 子场景验证（第 15 套，2026-11-19）
# ----------------------------------------------------------------------------
# Unity LoadSceneMode.Additive 语义：子场景根节点并入 activeScene，主场景
# 内容不释放；多个子场景共存并参与同一帧循环；unloadAdditive 只销毁对应
# 子场景节点；同名单例守卫；单模式 load/loadText 清空子场景登记。
# 写法约束（doc/10 §6）：JSON 内嵌字符串 \" 转义；SceneManager 实例方法
# （跨模块实例方法可靠）；浮点断言取整值防精度噪声。
# ============================================================================

public class SimSceneAdditiveTest
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

    static string mainJson()
    {
        string json = "{\"version\":1,\"scene\":\"MainScene\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"MainRoot\",\"tag\":\"Core\",\"layer\":2},"
        json = json + "{\"id\":2,\"parent\":1,\"name\":\"MainChild\"}]}"
        ret json
    }

    static string subJsonA()
    {
        string json = "{\"version\":1,\"scene\":\"SubA\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"SubARoot\",\"layer\":5},"
        json = json + "{\"id\":2,\"parent\":1,\"name\":\"Lamp\"}]}"
        ret json
    }

    static string subJsonB()
    {
        string json = "{\"version\":1,\"scene\":\"SubB\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"SubBRoot\"}]}"
        ret json
    }

    # ── A1. 主场景装载 + Additive 并入（主场景内容不释放）────
    static void testLoadAdditive()
    {
        SceneManager sm = SceneManager()
        Scene main = sm.loadText( mainJson() )
        check( main != null, "A1a main scene loaded" )
        Int32 beforeRoots = main.rootCount
        Scene sub = sm.loadAdditiveText( subJsonA() )
        check( sub != null, "A1b additive load ok" )
        check( sm.subSceneCount() == 1, "A1c sub scene registered" )
        check( sm.isSubLoaded( "SubA" ), "A1d isSubLoaded(SubA)" )
        # 主场景内容不动
        check( sm.activeScene == main, "A1e active scene unchanged" )
        check( main.rootCount == beforeRoots + 1, "A1f main root count grew by sub root" )
        check( main.find( "MainRoot" ) != null, "A1g main content intact" )
        check( main.find( "MainRoot/MainChild" ) != null, "A1h main child intact" )
        # 子场景节点并入后可在 activeScene 按路径找到
        GameObject sr = main.find( "SubARoot" )
        check( sr != null, "A1i sub root merged into active scene" )
        check( main.find( "SubARoot/Lamp" ) != null, "A1j sub child path resolvable" )
        check( sr.layer == 5, "A1k sub node props preserved" )
        # 同一帧循环：并入后 tick 不炸
        sm.tick( 0.016f )
        check( true, "A1l tick after merge" )
        sm.unload()
    }

    # ── A2. 多子场景共存 ────────────────────────────────
    static void testMultiSub()
    {
        SceneManager sm = SceneManager()
        sm.loadText( mainJson() )
        sm.loadAdditiveText( subJsonA() )
        Scene b = sm.loadAdditiveText( subJsonB() )
        check( b != null, "A2a second additive ok" )
        check( sm.subSceneCount() == 2, "A2b two subs coexist" )
        check( sm.isSubLoaded( "SubB" ), "A2c SubB registered" )
        check( sm.activeScene.find( "SubARoot" ) != null, "A2d SubA still present" )
        check( sm.activeScene.find( "SubBRoot" ) != null, "A2e SubB present" )
        check( sm.activeScene.find( "MainRoot" ) != null, "A2f main still present" )
        check( sm.subSceneName( 0 ) == "SubA", "A2g sub order kept" )
        sm.unload()
    }

    # ── A3. 同名子场景守卫 ──────────────────────────────
    static void testDuplicateGuard()
    {
        SceneManager sm = SceneManager()
        sm.loadText( mainJson() )
        sm.loadAdditiveText( subJsonA() )
        Scene dup = sm.loadAdditiveText( subJsonA() )
        check( dup == null, "A3a duplicate sub rejected" )
        bool errOk = sm.lastError.length > 0
        check( errOk, "A3b lastError recorded" )
        check( sm.subSceneCount() == 1, "A3c registry unchanged" )
        sm.unload()
    }

    # ── A4. 卸载子场景：只销毁子场景节点 ────────────────
    static void testUnload()
    {
        SceneManager sm = SceneManager()
        sm.loadText( mainJson() )
        sm.loadAdditiveText( subJsonA() )
        sm.loadAdditiveText( subJsonB() )
        bool done = sm.unloadAdditive( "SubA" )
        check( done, "A4a unload ok" )
        check( sm.subSceneCount() == 1, "A4b registry shrunk" )
        check( !sm.isSubLoaded( "SubA" ), "A4c SubA unregistered" )
        check( sm.activeScene.find( "SubARoot" ) == null, "A4d sub nodes destroyed" )
        check( sm.activeScene.find( "SubARoot/Lamp" ) == null, "A4e sub subtree destroyed" )
        check( sm.activeScene.find( "SubBRoot" ) != null, "A4f other sub intact" )
        check( sm.activeScene.find( "MainRoot/MainChild" ) != null, "A4g main intact after unload" )
        # 重复卸载报错
        bool again = sm.unloadAdditive( "SubA" )
        check( !again, "A4h double unload rejected" )
        sm.unload()
    }

    # ── A5. 未装载名卸载 + 主场景替换清空登记 ───────────
    static void testSingleModeClears()
    {
        SceneManager sm = SceneManager()
        sm.loadText( mainJson() )
        sm.loadAdditiveText( subJsonA() )
        bool miss = sm.unloadAdditive( "Nope" )
        check( !miss, "A5a unload unknown name rejected" )
        # 单模式替换：子场景登记清空（Unity 单模式语义）
        Scene main2 = sm.loadText( mainJson() )
        check( main2 != null, "A5b single-mode reload ok" )
        check( sm.subSceneCount() == 0, "A5c subs cleared by single load" )
        check( sm.activeScene.find( "SubARoot" ) == null, "A5d old sub not in new scene" )
        # 新主场景上继续 additive
        Scene again = sm.loadAdditiveText( subJsonB() )
        check( again != null, "A5e additive on fresh main ok" )
        check( sm.activeScene.find( "SubBRoot" ) != null, "A5f merged" )
        sm.unload()
    }

    public static void run()
    {
        Console.println( "=== SimSceneAdditiveTest (additive sub scenes) ===" )
        testLoadAdditive()
        testMultiSub()
        testDuplicateGuard()
        testUnload()
        testSingleModeClears()
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
