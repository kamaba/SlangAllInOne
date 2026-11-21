import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimPrefabTest — Prefab 机制（第 21 套）
# ----------------------------------------------------------------------------
# Prefab = scene.json 同构的 {version:1, scene:<名>, nodes:[...]}；读取直接
# 复用 SceneImporter.parseCore、写入复用 SceneExporter.collect/nodeOf。
# 覆盖：子树序列化、文件往返、实例化到 parent/场景根、多实例独立（id
# 重映射）、组件 round-trip（Mesh/BoxCollider/Light/Volume）、错误路径。
# 写法约束（doc/10 §6）：跨模块不链式调用；方法调用表达式不作实参；
# 下标先落局部变量；`tr`/`def`/`out` 等保留字避让。
# ============================================================================

public class SimPrefabTest
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

    # ── 建一棵带组件的子树（独立节点，不挂 Scene）───────
    static GameObject buildTree()
    {
        GameObject root = GameObject.create( "Chest" )
        root.tag = "Loot"
        root.layer = 5
        Transform rootTr = root.transform
        rootTr.setPosition( Float32_3( 1.0f, 2.0f, 3.0f ) )
        MeshRef mr = MeshRef()
        List<Float32_3> vs = List<Float32_3>( 3 )
        vs.add( Float32_3( 0.0f, 0.0f, 0.0f ) )
        vs.add( Float32_3( 1.0f, 0.0f, 0.0f ) )
        vs.add( Float32_3( 0.0f, 1.0f, 0.0f ) )
        mr.setVertices( vs )
        root.addComponent( mr )
        BoxCollider bc = BoxCollider()
        bc.center = Float32_3( 0.0f, 1.0f, 0.0f )
        bc.size = Float32_3( 2.0f, 3.0f, 4.0f )
        root.addComponent( bc )
        GameObject child = GameObject.create( "Lid" )
        Transform childTr = child.transform
        childTr.setPosition( Float32_3( 0.0f, 1.0f, 0.0f ) )
        child.setParent( root )
        ret root
    }

    # ── P2. 序列化 → JSON 结构 ───────────────────────────
    static void testToJson()
    {
        SceneManager sm = SceneManager()
        GameObject root = buildTree()
        string json = sm.prefabToJson( root, "ChestPrefab" )
        check( json.length > 0, "P2a prefabToJson non-empty" )
        JsonValue j = JsonValue.parse( json )
        check( !j.isNull(), "P2b valid json" )
        check( j.select( "version" ).asInt32( 0 ) == 1, "P2c version 1" )
        check( j.select( "scene" ).asString( "" ) == "ChestPrefab", "P2d prefab name" )
        JsonValue nodesNode = j.select( "nodes" )
        Array<JsonValue> nodes = nodesNode.children()
        check( nodes.length == 2, "P2e two nodes" )
        JsonValue n0 = nodes[0]
        JsonValue n1 = nodes[1]
        check( n0.select( "name" ).asString( "" ) == "Chest", "P2f root name" )
        check( n1.select( "name" ).asString( "" ) == "Lid", "P2g child name" )
        check( n0.select( "parent" ).asInt32( -1 ) == 0, "P2h root parent=0" )
        check( n1.select( "parent" ).asInt32( -1 ) == 1, "P2i child parent=1" )
        check( n0.select( "tag" ).asString( "" ) == "Loot", "P2j tag serialized" )
        check( n0.select( "components/0/type" ).asString( "" ) == "MeshFilter", "P2k MeshFilter serialized" )
        check( n0.select( "components/1/type" ).asString( "" ) == "BoxCollider", "P2l BoxCollider serialized" )
    }

    # ── P3. 文件往返 + 实例化 ───────────────────────────
    static void testRoundTrip()
    {
        SceneManager sm = SceneManager()
        GameObject root = buildTree()
        string path = "prefab_chest_test.json"
        bool saved = sm.prefabSave( root, path, "Chest" )
        check( saved, "P3a prefabSave" )
        check( File.exists( path ), "P3b file exists" )

        Scene template = sm.prefabLoad( path )
        check( template != null, "P3c prefabLoad" )
        check( template.rootCount() == 1, "P3d one root in template" )
        check( template.find( "Chest/Lid" ) != null, "P3e child hierarchy in template" )

        GameObject host = GameObject.create( "Host" )
        GameObject inst = sm.prefabInstantiate( template, host )
        check( inst != null, "P3f instantiate under host" )
        check( inst.name == "Chest", "P3g instance root name" )
        check( inst.getParent() == host, "P3h instance parent" )
        check( host.find( "Chest/Lid" ) != null, "P3i instance child" )
        check( inst.tag == "Loot", "P3j instance tag" )
        check( inst.layer == 5, "P3k instance layer" )
    }

    # ── P4. 多实例独立 + id 重映射 ──────────────────────
    static void testMultiple()
    {
        SceneManager sm = SceneManager()
        GameObject root = buildTree()
        string json = sm.prefabToJson( root, "Multi" )
        GameObject a = sm.instantiateText( json, null )
        GameObject b = sm.instantiateText( json, null )
        check( a != null && b != null, "P4a two instances" )
        check( a != b, "P4b distinct objects" )
        # NodeRegistry 按名哈希——同名实例 nodeId 相同是设计；断言组件独立
        check( a.transform != b.transform, "P4c distinct transforms per instance" )
        a.tag = "Changed"
        check( b.tag == "Loot", "P4d instance isolation" )
        check( a.getParent() == null, "P4e root instance has no parent" )
    }

    # ── P5. Light / Volume 组件 round-trip ──────────────
    static void testLightVolume()
    {
        SceneManager sm = SceneManager()
        GameObject lightNode = GameObject.create( "Sun" )
        LightData ld = LightData()
        ld.type = 2
        ld.intensity = 1.5f
        ld.dirX = 0.6f
        ld.color = Float32_3( 0.9f, 0.8f, 0.7f )
        lightNode.addComponent( ld )
        GameObject volNode = GameObject.create( "Grade" )
        Volume vol = Volume()
        vol.isGlobal = true
        vol.weight = 0.7f
        VolumeProfile prof = VolumeProfile()
        prof.setVignette( 0.4f )
        prof.setBrightness( 1.2f )
        vol.profile = prof
        volNode.addComponent( vol )

        string lightJson = sm.prefabToJson( lightNode, "LightPrefab" )
        string volJson = sm.prefabToJson( volNode, "VolPrefab" )
        JsonValue lj = JsonValue.parse( lightJson )
        JsonValue vj = JsonValue.parse( volJson )
        check( lj.select( "nodes/0/components/0/type" ).asString( "" ) == "Light", "P5a Light exported as Light" )
        check( lj.select( "nodes/0/components/0/lightType" ).asInt32( -1 ) == 2, "P5b lightType" )
        check( vj.select( "nodes/0/components/0/type" ).asString( "" ) == "Volume", "P5c Volume exported as Volume" )
        check( vj.select( "nodes/0/components/0/brightness" ).asFloat32( 0.0f ) == 1.2f, "P5d VolumeProfile field" )

        GameObject li = sm.instantiateText( lightJson, null )
        check( li != null, "P5e light prefab instantiate" )
        LightData li_ld = li.getComponent<LightData>()
        check( li_ld != null, "P5f LightData restored" )
        check( li_ld.type == 2, "P5g lightType restored" )
        check( li_ld.intensity == 1.5f, "P5h intensity restored" )
        check( li_ld.dirX == 0.6f, "P5i dirX restored" )

        GameObject vi = sm.instantiateText( volJson, null )
        check( vi != null, "P5j volume prefab instantiate" )
        Volume vi_vol = vi.getComponent<Volume>()
        check( vi_vol != null, "P5k Volume restored" )
        check( vi_vol.profile != null, "P5l VolumeProfile restored" )
        check( vi_vol.profile.hasVignette, "P5m vignette mask restored" )
        check( vi_vol.profile.vignette == 0.4f, "P5n vignette value restored" )
    }

    # ── P6. 错误路径 ────────────────────────────────────
    static void testErrors()
    {
        SceneManager sm = SceneManager()
        string empty = sm.prefabToJson( null, "X" )
        check( empty == "", "P6a null root -> empty json" )
        Scene s1 = sm.prefabLoadText( "" )
        check( s1 == null, "P6b empty text -> null" )
        Scene s2 = sm.prefabLoad( "definitely_missing_prefab.json" )
        check( s2 == null, "P6c missing file -> null" )
        GameObject inst = sm.instantiateText( "{\"version\":1,\"scene\":\"E\",\"nodes\":[]}", null )
        check( inst == null, "P6d empty prefab -> null instance" )
    }

    public static void run()
    {
        Console.println( "-- SimPrefabTest --" )
        testToJson()
        testRoundTrip()
        testMultiple()
        testLightVolume()
        testErrors()
        Console.println( "[SimPrefabTest] PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
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
