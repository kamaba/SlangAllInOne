import SimGameEngine;
import SLangRender;
import SLangAudio;
import Math;
import Std;

# ============================================================================
# SimSystemsTest — system/ 层（Systems/RenderSystem/AudioSystem）冒烟
# ----------------------------------------------------------------------------
# 覆盖：Systems.init（真实 GL 离屏管线 + 音频后端）、场景→RenderObject
# 同步（正交相机 NDC 映射断言）、frame 出帧到原生块（像素非均匀 =
# 有物体渲染）、AudioSystem 加载/探测（fixture WAV）、shutdown。
# 无 GPU / 无声卡环境：对应断言按 SKIP 形态跳过（ref RenderTest 惯例）。
# ============================================================================

public class SimSystemsTest
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

    static string audioFixture( string name )
    {
        string rel = "SlangAllInOne/SLangCore/test/RenderTest/" + name
        if SystemFileExists( rel )
        {
            ret rel
        }
        ret "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/" + name
    }

    public static void run()
    {
        Console.println( "=== SimSystemsTest (system/ layer smoke) ===" )
        Systems sys = Systems()
        bool inited = sys.init( 160, 160 )
        if inited == false
        {
            Console.println( "[SKIP] init failed: render=" + sys.render.lastError + " audio=" + sys.audio.lastError )
            Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
            ret
        }
        check( sys.render.ready(), "S1 render pipeline ready" )
        check( sys.audio.ready == true, "S2 audio backend ready" )

        # 场景：QUAD 网格节点（meshKind = Render MESH_QUAD = 1）
        Application app = Application()
        app.init()
        app.collisionSystem = sys.collision
        Scene scene = app.activeScene
        GameObject go = scene.createObject( "Quad" )
        go.layer = 0
        MeshRef mr = MeshRef()
        mr.meshKind = 1
        go.addComponent( mr )
        MaterialRef mref = MaterialRef()
        mref.material = MaterialData()
        go.addComponent( mref )
        Transform t = go.transform
        t.setPosition( Float32_3( 2.0f, 0.0f, 0.0f ) )
        t.setScale( Float32_3( 2.0f, 2.0f, 1.0f ) )

        # 相机默认 center=0 viewSize=10 → NDC x = 2/10 = 0.2
        Int32 n = sys.sync( scene, 0.0f )
        check( n == 1, "S3 sync submits 1 direct-pass object" )
        Int32 skip = sys.render.bakedSkipped
        check( skip == 0, "S4 no baked group (no vertex data)" )

        # 出帧到原生块：中心（物体）与角落（背景）像素应有差异
        Int64 pixels = Memory.alloc( 160 * 160 * 4 )
        bool ok = sys.frame( 0.0f, pixels )
        check( ok, "S5 frame rendered to native block" )
        if ok
        {
            # NDC(0.2, 0) → 像素 (x=96, y=80)（y 翻转取决于管线，取两处采样比较）
            Int32 cx = 96 * 4 + 80 * 160 * 4
            Int32 bx = 8 * 4 + 8 * 160 * 4
            Int32 cr = Memory.readUInt8( pixels, cx )
            Int32 cg = Memory.readUInt8( pixels, cx + 1 )
            Int32 cb = Memory.readUInt8( pixels, cx + 2 )
            Int32 br = Memory.readUInt8( pixels, bx )
            Int32 bg = Memory.readUInt8( pixels, bx + 1 )
            Int32 bb = Memory.readUInt8( pixels, bx + 2 )
            bool diff = ( cr != br ) || ( cg != bg ) || ( cb != bb )
            check( diff, "S6 object pixel differs from background" )
        }

        # P6 渐变天空：开天空（上蓝下绿）重出帧 → 顶部偏蓝 / 底部偏绿 /
        # 上下不同（readback 已行翻 top-down：y=8 为图像顶部）
        Float32_3 skyTop = Float32_3( 0.1f, 0.3f, 0.9f )
        Float32_3 skyBot = Float32_3( 0.9f, 0.6f, 0.1f )
        bool skySet = sys.render.setSky( skyTop, skyBot )
        check( skySet, "S6b render system forwards setSky" )
        sys.render.setSkyEnabled( true )
        bool ok2 = sys.frame( 0.0f, pixels )
        check( ok2, "S6c frame with sky rendered" )
        if ok2
        {
            Int32 tx = 8 * 4 + 8 * 160 * 4
            Int32 bxx = 8 * 4 + 152 * 160 * 4
            Int32 topR = Memory.readUInt8( pixels, tx )
            Int32 topG = Memory.readUInt8( pixels, tx + 1 )
            Int32 topB = Memory.readUInt8( pixels, tx + 2 )
            Int32 botR = Memory.readUInt8( pixels, bxx )
            Int32 botG = Memory.readUInt8( pixels, bxx + 1 )
            Int32 botB = Memory.readUInt8( pixels, bxx + 2 )
            bool topBlue = ( topB > topR ) && ( topB > 150 )
            bool botGreen = ( botG > botB ) && ( botG > 100 )
            check( topBlue, "S6d top pixel is sky-top blue (r=" + topR.toString() + " g=" + topG.toString() + " b=" + topB.toString() + ")" )
            check( botGreen, "S6e bottom pixel is sky-bottom green (r=" + botR.toString() + " g=" + botG.toString() + " b=" + botB.toString() + ")" )
            bool skyDiff = ( topR != botR ) || ( topG != botG ) || ( topB != botB )
            check( skyDiff, "S6f top/bottom sky pixels differ" )
            sys.render.setSkyEnabled( false )
        }

        # P7 收尾：烘焙组提交（MeshRef 带顶点数据 → bake → C 正交投影 →
        # uploadMesh MESH_CUSTOM）——sync 计数 + 像素断言（红色三角盖住中心）
        # （独立场景：仅烘焙三角一个对象）
        Scene bscene = Scene( "BakedOnly" )
        GameObject bgo = bscene.createObject( "BakedTri" )
        bgo.layer = 0
        MeshRef bmr = MeshRef()
        bmr.meshKind = 1
        bmr.useTriangle( 4.0f )
        bgo.addComponent( bmr )
        MaterialRef bmref = MaterialRef()
        MaterialData bmd = MaterialData()
        Float32_3 red = Float32_3( 1.0f, 0.0f, 0.0f )
        bmd.color = red
        bmref.material = bmd
        bgo.addComponent( bmref )
        Int32 bn = sys.sync( bscene, 0.0f )
        check( bn == 1, "S10 baked group submitted via uploadMesh" )
        Int32 bskip = sys.render.bakedSkipped
        check( bskip == 0, "S11 no bake skipped" )
        bool ok3 = sys.frame( 0.0f, pixels )
        check( ok3, "S12 frame with baked mesh rendered" )
        if ok3
        {
            # 三角（half 4，NDC ±0.4）盖住中心 (80,80)；角落在背景
            Int32 cxx = 80 * 4 + 80 * 160 * 4
            Int32 bxx = 8 * 4 + 8 * 160 * 4
            Int32 cr = Memory.readUInt8( pixels, cxx )
            Int32 br2 = Memory.readUInt8( pixels, bxx )
            check( cr > 200, "S13 baked triangle center red (r=" + cr.toString() + ")" )
            check( cr != br2, "S14 baked triangle differs from background" )
        }

        # doc/13 §2.1 第一步：cubemap 纹理上传（GL/GLES 后端）——6 面 4×4
        # 各一色 → createCubeTexture → 句柄有效 → 帧渲染不受影响 → destroy
        Int64 cubeFaces = Memory.alloc( 6 * 4 * 4 * 4 )
        check( cubeFaces != 0, "S15a cube face buffer alloc" )
        Int32 fi = 0
        while fi < 6
        {
            Int32 pi = 0
            Int32 fbase = fi * 64
            while pi < 16
            {
                Memory.writeI8( cubeFaces, fbase + pi * 4 + 0, 20 + fi * 20 )
                Memory.writeI8( cubeFaces, fbase + pi * 4 + 1, 10 + fi * 10 )
                Memory.writeI8( cubeFaces, fbase + pi * 4 + 2, 80 )
                Memory.writeI8( cubeFaces, fbase + pi * 4 + 3, 127 )
                pi = pi + 1
            }
            fi = fi + 1
        }
        SLang.RenderTexture cubeTex = SLang.RenderTexture.createCubeTexture( cubeFaces, 4, 4 )
        check( cubeTex != null, "S15b cube texture created (gl backend)" )
        if cubeTex != null
        {
            bool vok = cubeTex.isValid()
            check( vok, "S15c cube handle valid" )
            bool frameOk = sys.frame( 0.0f, pixels )
            check( frameOk, "S15d frame with cube texture alive" )
            bool dok = cubeTex.destroy()
            check( dok, "S15e cube texture destroyed" )
        }
        Memory.free( cubeFaces )

        # doc/13 §2.1 第二步：cubemap 天空出图——重建 cube（-Z 面亮绿、
        # 其余暗）→ setSkyCube + setSkyEnabled → frame：中心（视线
        # (0,0,-1)）命中 -Z 面亮绿，角落（斜向）为暗面
        Int64 faces2 = Memory.alloc( 6 * 4 * 4 * 4 )
        check( faces2 != 0, "S16a face buffer alloc" )
        Int32 fi2 = 0
        while fi2 < 6
        {
            Int32 pi2 = 0
            Int32 fbase2 = fi2 * 64
            Int32 fr = 10
            Int32 fg = 10
            Int32 fb = 20
            if fi2 == 5
            {
                fr = 20
                fg = 120
                fb = 30
            }
            while pi2 < 16
            {
                # -Z 面（面序 index 5）绿色，其余洋红——区分面方向
                Int32 fr2 = 120
                Int32 fg2 = 30
                Int32 fb2 = 120
                if fi2 == 5
                {
                    fr2 = 20
                    fg2 = 120
                    fb2 = 30
                }
                Memory.writeI8( faces2, fbase2 + pi2 * 4 + 0, fr2 )
                Memory.writeI8( faces2, fbase2 + pi2 * 4 + 1, fg2 )
                Memory.writeI8( faces2, fbase2 + pi2 * 4 + 2, fb2 )
                Memory.writeI8( faces2, fbase2 + pi2 * 4 + 3, 127 )
                pi2 = pi2 + 1
            }
            fi2 = fi2 + 1
        }
        SLang.RenderTexture skyCube = SLang.RenderTexture.createCubeTexture( faces2, 4, 4 )
        check( skyCube != null, "S16b sky cube created" )
        if skyCube != null
        {
            # 空场景 + 关 sky：中心应回到清屏色（验证烘焙对象已被 sync 回收，
            # 不残留到后续帧）
            Scene skyOnly = Scene( "SkyOnly" )
            Int32 sn = sys.sync( skyOnly, 0.0f )
            SLang.RenderPipeline dbgPipe = sys.render.pipe()
            Int32 dbgObj = dbgPipe.objectCount()
            check( dbgObj == 0, "S16o sync recycles pipeline objects" )
            bool f0 = sys.frame( 0.0f, pixels )
            Console.println( "DBG f0=" + f0.toString() )
            Int32 p0r = Memory.readUInt8( pixels, 80 * 4 + 80 * 160 * 4 )
            Int32 pxUp = Memory.readUInt8( pixels, 80 * 4 + 100 * 160 * 4 )
            Int32 pxDn = Memory.readUInt8( pixels, 80 * 4 + 60 * 160 * 4 )
            Int32 pxLf = Memory.readUInt8( pixels, 40 * 4 + 80 * 160 * 4 )
            Int32 pxRt = Memory.readUInt8( pixels, 120 * 4 + 80 * 160 * 4 )
            check( p0r < 60, "S16p empty scene clears baked triangle (r=" + p0r.toString() + ")" )
            Console.println( "DBG step1 setSkyCube" )
            Int64 chandle = skyCube.handle()
            bool s1 = sys.render.setSkyCube( chandle )
            Console.println( "DBG step2 setSkyCube ret=" + s1.toString() )
            bool s1 = sys.render.setSkyCube( chandle )
            check( s1, "S16c setSkyCube accepted" )
            sys.render.setSkyEnabled( true )
            Console.println( "DBG step3 before cube frame" )
            bool f2 = sys.frame( 0.0f, pixels )
            Console.println( "DBG step4 cube frame done" )
            check( f2, "S16d frame with cube sky" )
            # 像素级断言（懒创建程序后全链路通）：中心朝 -Z → 绿面；
            # 角落朝 +X/Y 面 → 洋红。诊断通道复核分派与 GL 状态。
            Int32 mid = 80 * 4 + 80 * 160 * 4
            Int32 cor = 8 * 4 + 8 * 160 * 4
            Int32 ctr = Memory.readUInt8( pixels, mid )
            Int32 ctg = Memory.readUInt8( pixels, mid + 1 )
            Int32 cnr = Memory.readUInt8( pixels, cor )
            Int32 cng = Memory.readUInt8( pixels, cor + 1 )
            bool centerGreen = ( ctg > 100 ) && ( ctr < 60 )
            check( centerGreen, "S16e center pixel hits -Z face (r=" + ctr.toString() + " g=" + ctg.toString() + ")" )
            # 正交视线恒朝 -Z（dir.z=-1 归一后仍主导）→ 全屏都落 -Z 面；
            # 多面覆盖需透视相机（doc/13 §2.1 边界：透视 MVP 随相机专项）
            bool cornerGreen = ( cng > 100 ) && ( cnr < 60 )
            check( cornerGreen, "S16f corner pixel also -Z face (ortho dir; r=" + cnr.toString() + " g=" + cng.toString() + ")" )
            SLang.RenderPipeline sp2 = sys.render.pipe()
            Int32 sm = sp2.skyLastMode( sp2.handle )
            check( sm == 2, "S16g sky dispatch cube mode" )
            sys.render.setSkyCube( 0 )
            sys.render.setSkyEnabled( false )
            bool d2 = skyCube.destroy()
            check( d2, "S16h sky cube destroyed" )
        }
        Memory.free( faces2 )

        # 音频：fixture 探测（string 参数静态）+ 无声卡降级
        string info = sys.audio.probeFile( audioFixture( "test_audio.wav" ) )
        bool probeOk = info != ""
        check( probeOk, "S7 audio probeFile fixture" )
        if sys.audio.deviceAvailable()
        {
            Audio.AudioClip clip = sys.audio.loadClip( audioFixture( "test_audio.wav" ) )
            check( clip != null, "S8 loadClip fixture" )
            if clip != null
            {
                Audio.AudioSource src = sys.audio.createSource( clip, 0.5f, false )
                check( src != null, "S9 createSource" )
                clip.free()
            }
        }
        else
        {
            Console.println( "[SKIP] no audio output device" )
        }

        app.shutdown()
        sys.shutdown()
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
