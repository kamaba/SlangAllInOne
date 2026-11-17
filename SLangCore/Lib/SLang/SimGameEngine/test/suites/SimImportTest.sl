import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimImportTest — SceneImporter 统一 JSON 资源导入验证（第 11 套）
# ----------------------------------------------------------------------------
# 覆盖：两遍建树（任意顺序 parent）、层级/标签/激活态、变换直传（含父子
# 累乘）、组件映射（MeshFilter/MeshRenderer/Rigidbody/BoxCollider/Camera/
# Light/未知 type）、version 不识别明确报错、坏 JSON 报错、loadDir 缺失
# 目录报错、mesh 槽位轮转。
# 写法约束（doc/10 §6）：JSON 内嵌字符串用 \" 转义（JsonTest 先例）；
# 跨模块读走 counts/getter 方法；浮点断言取整值防精度噪声。
# ============================================================================

public class SimImportTest
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

    # ── N1. 建树 + 层级 + 属性 ─────────────────────────
    static void testTree()
    {
        string json = "{\"version\":1,\"scene\":\"Demo\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"Root\",\"tag\":\"Main\",\"layer\":3,\"active\":true},"
        json = json + "{\"id\":2,\"parent\":1,\"name\":\"Child\",\"active\":false},"
        json = json + "{\"id\":3,\"parent\":0,\"name\":\"Second\"}]}"
        SceneImporter imp = SceneImporter()
        ImportReport rep = imp.parseCore( 1, json )
        check( rep.ok, "N1a parse ok" )
        check( rep.nodeCount == 3, "N1b node count 3" )
        check( rep.sceneName == "Demo", "N1c scene name" )
        Scene s = rep.scene
        check( s.rootCount() == 2, "N1d two roots (Child reparented)" )
        GameObject child = s.find( "Root/Child" )
        check( child != null, "N1e child under Root" )
        GameObject root = s.find( "Root" )
        check( root.layer == 3, "N1f layer applied" )
        check( root.tag == "Main", "N1g tag applied" )
        bool childActive = child.getActiveInHierarchy()
        check( !childActive, "N1h inactive node" )
    }

    # ── N2. 变换直传 + 父子累乘 ────────────────────────
    static void testTransform()
    {
        string json = "{\"version\":1,\"scene\":\"T\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"P\",\"transform\":{\"localPosition\":[1,2,3],\"localRotation\":[0,0,0,1],\"localScale\":[2,2,2]}},"
        json = json + "{\"id\":2,\"parent\":1,\"name\":\"C\",\"transform\":{\"localPosition\":[0,1,0]}}]}"
        SceneImporter imp = SceneImporter()
        ImportReport rep = imp.parseCore( 1, json )
        check( rep.ok, "N2a parse ok" )
        Scene s = rep.scene
        GameObject p = s.find( "P" )
        GameObject c = s.find( "P/C" )
        check( p != null && c != null, "N2b nodes built" )
        Transform tp = p.transform
        Float32_3 wp = tp.worldPosition()
        bool pok = ( wp.x == 1.0f ) && ( wp.y == 2.0f ) && ( wp.z == 3.0f )
        check( pok, "N2c parent world pos" )
        Transform tc = c.transform
        Float32_3 wc = tc.worldPosition()
        # 父 scale 2 × 子 local y=1 → 世界 (1, 2+2, 3)
        bool cok = ( wc.x == 1.0f ) && ( wc.y == 4.0f ) && ( wc.z == 3.0f )
        check( cok, "N2d child world pos (parent scale composed)" )
    }

    # ── N3. 组件映射：MeshFilter/MeshRenderer ──────────
    static void testComponents()
    {
        string json = "{\"version\":1,\"scene\":\"C\",\"nodes\":["
        json = json + "{\"id\":1,\"parent\":0,\"name\":\"Cube\",\"components\":["
        json = json + "{\"type\":\"MeshFilter\",\"mesh\":\"mesh_1001\"},"
        json = json + "{\"type\":\"MeshRenderer\",\"material\":\"mat_2001\",\"renderQueue\":2225,\"castShadow\":true}]},"
        json = json + "{\"id\":2,\"parent\":1,\"name\":\"Sub\",\"components\":[{\"type\":\"MeshFilter\",\"mesh\":\"mesh_1002\"}]},"
        json = json + "{\"id\":3,\"parent\":0,\"name\":\"Body\",\"components\":[{\"type\":\"Rigidbody\",\"mass\":2.5,\"useGravity\":true},"
        json = json + "{\"type\":\"BoxCollider\",\"center\":[0,1,0],\"size\":[2,2,2],\"isTrigger\":true}]},"
        json = json + "{\"id\":4,\"parent\":0,\"name\":\"Cam\",\"components\":[{\"type\":\"Camera\"}]},"
        json = json + "{\"id\":5,\"parent\":0,\"name\":\"Sun\",\"components\":[{\"type\":\"Light\"}]},"
        json = json + "{\"id\":6,\"parent\":0,\"name\":\"Mystery\",\"components\":[{\"type\":\"Terrain\"}]}]}"
        SceneImporter imp = SceneImporter()
        ImportReport rep = imp.parseCore( 1, json )
        check( rep.ok, "N3a parse ok" )
        check( rep.meshCount == 2, "N3b mesh count" )
        check( rep.materialCount == 1, "N3c material count" )
        check( rep.rigidbodyCount == 1, "N3d rigidbody count" )
        check( rep.colliderCount == 1, "N3e collider count" )
        check( rep.cameraCount == 1, "N3f camera counted" )
        check( rep.lightCount == 1, "N3g light counted" )
        check( rep.skippedCount == 1, "N3h unknown type skipped" )
        check( rep.meshIdCount() == 2, "N3i mesh ids registered" )
        string m0 = rep.meshIdAt( 0 )
        check( m0 == "mesh_1001", "N3j mesh id value" )
        Scene s = rep.scene
        GameObject cube = s.find( "Cube" )
        MeshRef mr = cube.getComponent<MeshRef>()
        check( mr != null, "N3k MeshRef attached" )
        bool kindOk = mr.meshKind == 4
        check( kindOk, "N3l MESH_CUSTOM kind" )
        Int32 slot = mr.meshSlot
        bool slotOk = ( slot >= 4 ) && ( slot < 8 )
        check( slotOk, "N3m slot in 4..7" )
        GameObject sub = s.find( "Cube/Sub" )
        MeshRef mr2 = sub.getComponent<MeshRef>()
        Int32 slot2 = mr2.meshSlot
        check( slot2 != slot, "N3n slot rotates" )
        GameObject body = s.find( "Body" )
        Rigidbody rb = body.getComponent<Rigidbody>()
        check( rb != null, "N3o Rigidbody attached" )
        BoxCollider bc = body.getComponent<BoxCollider>()
        check( bc != null, "N3p BoxCollider attached" )
    }

    # ── N4. version 不识别 + 坏 JSON ───────────────────
    static void testVersionGuard()
    {
        SceneImporter imp = SceneImporter()
        ImportReport rep = imp.parseCore( 7, "{\"version\":1,\"nodes\":[]}" )
        check( !rep.ok, "N4a bad manifest version rejected" )
        bool errOk = rep.lastError != "" && rep.lastError != null
        check( errOk, "N4b error message present" )
        ImportReport rep2 = imp.parseCore( 1, "{\"version\":3,\"nodes\":[]}" )
        check( !rep2.ok, "N4c bad scene version rejected" )
        ImportReport rep3 = imp.parseCore( 1, "not json at all" )
        check( !rep3.ok, "N4d bad json rejected" )
    }

    # ── N5. loadDir 缺失目录优雅报错 ───────────────────
    static void testLoadDirMissing()
    {
        SceneImporter imp = SceneImporter()
        ImportReport rep = imp.loadDir( "definitely/not/exist/dir" )
        check( !rep.ok, "N5a missing dir rejected" )
        bool errOk = rep.lastError != "" && rep.lastError != null
        check( errOk, "N5b error message" )
    }

    public static void run()
    {
        testTree()
        testTransform()
        testComponents()
        testVersionGuard()
        testLoadDirMissing()
        Console.println( "SimImportTest: PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
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
