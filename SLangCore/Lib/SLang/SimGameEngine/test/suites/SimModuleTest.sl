import SimGameEngine;
import SLangRender;
import SLangAudio;
import Math;
import Std;

# ============================================================================
# SimModuleTest — 引擎 + SLangRender + SLangAudio 三模块共存与复用验证
# ----------------------------------------------------------------------------
# doc/10 双模块同名专项实证（2026-11-16）：
#   1. SimGameEngine.jsonc 引用 SLangRender/SLangAudio slb 后引擎模块编译
#      零冲突（同名 Transform/Ray/Material 模块作用域隔离）；
#   2. 消费方同工程引用三模块：引擎类照常 + Render/Audio 类复用；
#   3. 同名类二义实证：消费方裸名 Transform 解析（引擎 vs Render 均有
#      根级 Transform）——用特征字段 localRotationZ（仅引擎版有）判定。
# 复用点：
#   Render.Vertex.transformed(引擎 Transform.worldMatrix()) —— 交叉复用
#   Render.Vector.distance/reflect 静态向量工具
#   Audio.AudioInfo.probe(手造最小 WAV 字节) —— 音频格式探测
# ============================================================================

public class SimModuleTest
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

    # ── 1. 引擎类照常可用（三模块引用共存下）────────────
    static void testEngineClasses()
    {
        Scene scene = Scene( "M1" )
        GameObject go = scene.createObject( "Node" )
        Transform t = go.transform
        t.setPosition( Float32_3( 1.0f, 2.0f, 3.0f ) )
        t.setRotationZ( 0.5f )
        Float32_3 wp = t.worldPosition()
        bool ok = ( wp.x == 1.0f ) && ( wp.y == 2.0f )
        check( ok, "M1a engine Scene/GameObject/Transform usable" )
        # 引擎版特征字段 localRotationZ（Render 版无此字段）
        Float32 rz = t.localRotationZ
        check( rz == 0.5f, "M1b bare Transform resolves engine variant" )
        # 引擎碰撞体照常
        HitProbeBox hb = HitProbeBox()
        go.addComponent( hb )
        BoxCollider got = go.getComponent<BoxCollider>()
        check( got == hb, "M1c engine collider usable" )
    }

    # ── 2. Render.Vertex × 引擎矩阵 交叉复用 ────────────
    static void testRenderVertexWithEngineMatrix()
    {
        Scene scene = Scene( "M2" )
        GameObject go = scene.createObject( "N" )
        Transform t = go.transform
        t.setPosition( Float32_3( 10.0f, 20.0f, 0.0f ) )
        t.setRotationZ( 1.5707963f )
        Float32_4x4 m4 = t.worldMatrix()
        # Render 顶点：局部 (1,0,0)，经引擎 Transform 的世界矩阵变换
        Vertex v = Vertex( Float32_3( 1.0f, 0.0f, 0.0f ) )
        Vertex w = v.transformed( m4 )
        # rotZ90 × (1,0,0) = (0,1,0) → +pos = (10,21,0)
        Float32_3 wp = w.position
        bool ok = ( wp.x == 10.0f ) && ( wp.y == 21.0f )
        check( ok, "M2a Render.Vertex.transformed( engine worldMatrix ) cross-use" )
    }

    # ── 3. Render 消费（实例方法 + AudioIO 无参静态）────
    # 坑（doc/10 §6）：跨模块静态方法非 string 参数一律 mangle 成
    # Core.Object（Vector.distance(Float32_3,Float32_3) /
    # AudioInfo.probe(Array<UInt8>) 均 not found）——可用形态：
    # 实例方法（Vertex.transformed ✓）+ 无参静态 + string 参数静态
    # （AudioIO.probeFile ✓）
    static void testRenderAudioReuse()
    {
        # Render Vertex 实例字段/方法（transformed 已在 M2 验证）
        Vertex v = Vertex( Float32_3( 1.0f, 2.0f, 3.0f ), Float32_3( 0.0f, 1.0f, 0.0f ), Float32_2( 0.25f, 0.5f ) )
        Float32_2 uv = v.uv
        bool uvOk = ( uv.x == 0.25f ) && ( uv.y == 0.5f )
        check( uvOk, "M3a Render.Vertex fields (pos/normal/uv ctor)" )
        Float32_3 vn = v.normal
        Float32 nl = vn.length()
        bool nOk = nl == 1.0f
        check( nOk, "M3b Vertex ctor normalizes normal" )
        # Audio.AudioIO 无参静态（string 返回）
        string ver = Audio.AudioIO.versionText()
        bool verOk = ver != null
        check( verOk, "M3c Audio.AudioIO.versionText callable" )
        string backends = Audio.AudioIO.backendsText()
        bool bOk = backends != null
        check( bOk, "M3d Audio.AudioIO.backendsText callable" )
    }

    # ── 4. Audio.AudioIO.probeFile（string 参数静态）────
    static void testAudioProbeFile()
    {
        # fixture 同 RenderTest（相对 CWD=SlangAllInOne 优先，绝对兜底）
        string rel = "SlangAllInOne/SLangCore/test/RenderTest/test_audio.wav"
        if SystemFileExists( rel ) == false
        {
            rel = "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_audio.wav"
        }
        Audio.AudioInfo iw = Audio.AudioIO.probeFile( rel )
        bool ok = iw != null
        check( ok, "M4a Audio.AudioIO.probeFile(wav fixture)" )
        if ok
        {
            Int32 sr = iw.sampleRate
            Int32 ch = iw.channels
            Int32 fmt = iw.srcFormatId
            bool detail = ( sr == 44100 ) && ( ch == 1 ) && ( fmt == 1 )
            check( detail, "M4b wav: 44100Hz / 1ch / PCM" )
        }
    }

    # ── 5. 引擎 + Render 同名类二义边界 ─────────────────
    static void testSameNameBoundary()
    {
        # 消费方裸名 Ray：引擎与 Render 都有根级 Ray——本测试文件位于
        # 引用 SimGameEngine 的工程，裸名 Ray 解析行为实证（构造 +
        # 引擎特征方法 fromTo 存在性由编译判定）
        Ray r = Ray()
        bool rNotNull = r != null
        check( rNotNull, "M5a bare Ray constructible (no ambiguity error)" )
    }

    public static void run()
    {
        Console.println( "=== SimModuleTest (engine + SLangRender + SLangAudio co-use) ===" )
        testEngineClasses()
        testRenderVertexWithEngineMatrix()
        testRenderAudioReuse()
        testAudioProbeFile()
        testSameNameBoundary()
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

# 引擎碰撞体探针（验证引擎组件在多模块共存下照常）
public class HitProbeBox extends BoxCollider
{
    public Int32 hits = 0
}
