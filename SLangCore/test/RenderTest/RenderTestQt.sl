import SLangQT;
import SLangRender;
import SLangAudio;
import Math;
import Std;

# Phase B QT 窗口（真实 Qt 后端；stub SKIP）—— 后端可选的交互渲染面板：
#   顶部 4 个按钮（OpenGL / D3D11 / Vulkan / WebGL-GLES）点击即切换渲染
#   底层（switchBackend：initializeBackend + rebuildScene 场景全量重建），
#   状态栏实时显示当前后端 + 渲染器；QTimer 16ms 帧循环 onTick ->
#   runStages（每帧完整 13 阶段 + 聚光灯摇晃 + 立方体自转）->
#   QLabel.setPixmapRgba 填充；7s 自动轮播（用户点击后停止）；60s 退出
#   -> 帧数断言 + 后端掩码断言。共享 _pipe/_pixels/_lamp 经
#   RenderTest.* 引用；立方体状态经 RenderTestCube.* 引用
public class RenderTestQt
{

    # ── Phase B QT 窗口 / 后端切换 UI 状态 ──────────────────────────
    static SLang.QApplication _app = null
    static SLang.QLabel _label = null
    static SLang.QLabel _status = null
    static SLang.QPushButton _btnGl = null
    static SLang.QPushButton _btnDx = null
    static SLang.QPushButton _btnVk = null
    static SLang.QPushButton _btnWeb = null
    public static Int32 _backendMask = 0     # gl=1 d3d11=2 vk=4 gles=8（QT 循环内渲染记账）
    public static Int32 _cycleStep = 0       # 自动轮播步进（0..3：d3d11/vk/gles/gl）
    public static bool _userPicked = false   # 用户点过按钮后停止自动轮播
    public static Float32 _t = 0.0f
    public static Int32 _renderFrames = 0
    public static Int32 _pixOk = 0
    public static Int32 _stageErr = 0        # N3 诊断：runStages 失败信息（每后端打印一次）
    # UV 不建表：vi/16=面、(vi%16)/4=子块、vi%4=角点 -> 图集 cell（updateCube 现场计算）

    # 帧循环 tick：t 推进 -> SL 侧逐阶段驱动 1..13（完整流程）-> 填 QT 窗口
    # v3.4：每帧先摇晃聚光灯（位置 ±0.08 sin + 高度 ±0.05 sin、强度
    # 1.6±0.5 sin 脉动）再 applyTo —— 灯光/阴影/高光实时跟随摆动
    public static void onTick()
    {
        if RenderTest._pipe == null
        {
            ret
        }
        _t = _t + 0.033f
        if RenderTest._lamp != null
        {
            RenderTest._lamp.posX = 0.08f * Mathf.sin( _t * 2.1f )
            RenderTest._lamp.posY = 0.8f + 0.05f * Mathf.sin( _t * 3.3f )
            RenderTest._lamp.intensity = 1.6f + 0.5f * Mathf.sin( _t * 4.7f )
            if RenderTest._lamp.intensity < 0.4f
            {
                RenderTest._lamp.intensity = 0.4f
            }
            RenderTest._lamp.applyTo( RenderTest._pipe, 0 )
        }
        if RenderTestCube.updateCube( _t )
        {
            if RenderTestCube._cubeFirst == 0
            {
                Console.println( "[cube] spinning: CPU transform + uploadMesh(slot 0) OK on backend " + SLang.Render.currentBackend() )
                RenderTestCube._cubeFirst = 1
            }
        }
        bool frameOk = RenderTest._pipe.runStages( _t, RenderTest._pixels )
        if frameOk == false && _stageErr == 0
        {
            _stageErr = 1
            # errorString 先取（stat/frameCount 也是原生入口会清错误）
            string err = SLang.Render.errorString()
            Console.println( "[tick] runStages FAILED on " + SLang.Render.currentBackend() + " - " + err + " (lastStage=" + RenderTest._pipe.stat( SLang.RenderPipeline.STAT_LAST_STAGE ).toString() + " pipeFrame=" + RenderTest._pipe.frameCount().toString() + " renderFrames=" + _renderFrames.toString() + ")" )
        }
        if frameOk
        {
            _renderFrames = _renderFrames + 1
            if _label.setPixmapRgba( RenderTest._pixels, RenderTest._texW, RenderTest._texH )
            {
                _pixOk = _pixOk + 1
            }
            markBackendRendered()
        }
    }

    # ── Phase C：立方体每帧更新（CPU 变换 + 动态网格上传）─────────
    # 流水线：Mesh.cube 顶点 -> rotationY/X(t) 旋转 -> 手工透视除法
    # （相机 -Z 朝 +Z：dist = z + 2.6，焦距 f = 1.7）-> NDC 顶点 ->
    # 12 三角形按平均深度降序排（远先画保遮挡）-> 三角形列表展开为
    # pos2+uv2 交错（stride 16B）-> Memory.writeF32 填 RenderTestCube._cubeVerts ->
    # pipe.uploadMesh(0) 整块重传（GL/GLES/D3D11 重传 / VK 直写）。


    # QT 循环内按当前后端记账（每帧调，位或幂等）
    public static void markBackendRendered()
    {
        string b = SLang.Render.currentBackend()
        if b == "gl"
        {
            _backendMask = _backendMask | 1
        }
        if b == "d3d11"
        {
            _backendMask = _backendMask | 2
        }
        if b == "vk"
        {
            _backendMask = _backendMask | 4
        }
        if b == "gles"
        {
            _backendMask = _backendMask | 8
        }
    }

    # ── Phase B 后端切换核心 ──────────────────────────────────────
    # 切换 = uninit 当前后端（管线/纹理/v1 ctx 全部释放，句柄失效）->
    # 新后端 init + make_shared -> 场景全量重建。先置 RenderTest._pipe=null 防
    # onTick 在重建窗口期踩已释放句柄。


    # ── Phase B 后端切换核心 ──────────────────────────────────────
    # 切换 = uninit 当前后端（管线/纹理/v1 ctx 全部释放，句柄失效）->
    # 新后端 init + make_shared -> 场景全量重建。先置 RenderTest._pipe=null 防
    # onTick 在重建窗口期踩已释放句柄。
    public static void switchBackend( string name )
    {
        # 2026-11-13 修复：先释放旧帧缓冲再清引用 —— 原直接 RenderTest._pixels = 0
        # 抢跑指针，每轮 rebuildScene 新 alloc 3.6MB（1250*720*4）全部泄漏，
        # 4 轮后 SL 堆耗尽，rebuildScene 在 px 分配静默 ret false（唯一无
        # FAIL 打印的中止点）-> RenderTest._pipe 悬空 -> 立方体上传断言必失败。
        # 旧块无原生侧所有权（仅回写目的地），uninit 前后释放皆安全。
        if RenderTest._pixels != 0
        {
            Memory.free( RenderTest._pixels )
        }
        RenderTest._pipe = null
        RenderTest._pixels = 0
        RenderTestCube._cubeFirst = 0
        RenderTestCube._cubeErr = 0                 # N3 诊断：新后端重新启用失败打印
        _stageErr = 0
        if SLang.Render.initializeBackend( name ) == false
        {
            Console.println( "[ui] backend '" + name + "' unavailable - " + SLang.Render.errorString() )
            # 请求的后端不可用：恢复默认 gl 兜底（失败则保持空场景，onTick 判空跳过）
            if SLang.Render.initializeBackend( "gl" ) == false
            {
                updateStatus()
                ret
            }
        }
        else
        {
            Console.println( "[ui] switch -> " + name + " (" + SLang.Render.rendererInfo() + ")" )
        }
        if rebuildScene() == false
        {
            Console.println( "[ui] scene rebuild failed on '" + SLang.Render.currentBackend() + "'" )
            updateStatus()
            ret
        }
        _t = 0.0f
        updateStatus()
    }

    # 场景全量重建（A3 同款：橙图 quad + 蓝 quad + 动画三角 + 相机1
    # 右半 viewport + 展示用后处理）—— 每次后端切换后调用
    # v3.4：聚光灯 RenderTest._lamp（暖色，onTick 每帧摇晃位置 + 强度脉动）+
    # 三个物体 castShadow 投影阴影（聚光点源 -> 阴影随灯摇晃跟随）+
    # 蓝 quad/cube Phong 材质高光。


    # 场景全量重建（A3 同款：橙图 quad + 蓝 quad + 动画三角 + 相机1
    # 右半 viewport + 展示用后处理）—— 每次后端切换后调用
    # v3.4：聚光灯 RenderTest._lamp（暖色，onTick 每帧摇晃位置 + 强度脉动）+
    # 三个物体 castShadow 投影阴影（聚光点源 -> 阴影随灯摇晃跟随）+
    # 蓝 quad/cube Phong 材质高光。
    public static bool rebuildScene()
    {
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1250, 720 )
        if pipe == null
        {
            Console.println( "[ui] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            ret false
        }
        if pipe.setPostEffect( 1, 1.05f, 1.15f, 0.35f ) == false
        {
            ret false
        }
        # v3.4 演示光照：环境光 + 暖色聚光（位置/强度由 onTick 摇晃驱动）
        if pipe.setAmbient( 0.45f ) == false
        {
            ret false
        }
        if RenderTest._lamp == null
        {
            RenderTest._lamp = RenderLight.spot( Color( 1.0f, 0.85f, 0.55f, 1.0f ), 1.6f, 2.4f, 38.0f )
            if RenderTest._lamp == null
            {
                Console.println( "[ui] FAIL: RenderLight.spot" )
                ret false
            }
        }
        RenderTest._lamp.posX = 0.0f
        RenderTest._lamp.posY = 0.8f
        RenderTest._lamp.dirX = 0.0f
        RenderTest._lamp.dirY = -1.0f
        if RenderTest._lamp.applyTo( pipe, 0 ) == false
        {
            Console.println( "[ui] FAIL: lamp applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 图片贴图（相对路径按运行进程 CWD，失败回退绝对路径）
        SLang.RenderTexture imgTex = SLang.RenderTexture.loadFile( "SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        if imgTex == null
        {
            imgTex = SLang.RenderTexture.loadFile( "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        }
        if imgTex == null
        {
            Console.println( "[ui] FAIL: loadFile test_image.png - " + SLang.Render.errorString() )
            ret false
        }
        # 橙图 quad（layer2，左半；投影阴影 + Phong 贴图高光）
        SLang.RenderObject imgQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if imgQuad == null
        {
            ret false
        }
        imgQuad.setLayer( 2 )
        imgQuad.setQueue( 2000 )
        imgQuad.setPosition( -0.5f, 0.0f, 0.0f )
        imgQuad.setScale( 0.7f, 0.7f )
        imgQuad.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        imgQuad.setTexture( imgTex )
        imgQuad.setMaterial( 1 )
        imgQuad.setSpecular( 1.0f, 12.0f )
        imgQuad.setShadow( 1 )

        # 蓝 quad（layer0，右半；投影阴影 + Toon 卡通阶梯[3 档]）
        SLang.RenderObject blueQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if blueQuad == null
        {
            ret false
        }
        blueQuad.setLayer( 0 )
        blueQuad.setQueue( 2000 )
        blueQuad.setPosition( 0.5f, 0.0f, 0.0f )
        blueQuad.setScale( 0.6f, 0.6f )
        blueQuad.setColor( 0.2f, 0.4f, 1.0f, 1.0f )
        blueQuad.setMaterial( 4 )
        blueQuad.setSpecular( 3.0f, 0.5f )
        blueQuad.setShadow( 1 )

        # v3.5 固化效果展示：BlinnPhong 高光 quad（底部左）+ NormalMap
        # 贴图高光 quad（底部右）—— 5 效果全上屏（Lambert=三角/立方体、
        # Phong=橙图、Toon=蓝 quad、BlinnPhong/NormalMap=本组）
        SLang.RenderObject bpQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if bpQuad == null
        {
            ret false
        }
        bpQuad.setLayer( 0 )
        bpQuad.setQueue( 2000 )
        bpQuad.setPosition( -0.55f, -0.58f, 0.0f )
        bpQuad.setScale( 0.28f, 0.28f )
        bpQuad.setColor( 0.95f, 0.55f, 0.15f, 1.0f )
        bpQuad.setMaterial( 2 )
        bpQuad.setSpecular( 2.5f, 32.0f )

        SLang.RenderObject nmQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if nmQuad == null
        {
            ret false
        }
        nmQuad.setLayer( 0 )
        nmQuad.setQueue( 2000 )
        nmQuad.setPosition( 0.55f, -0.58f, 0.0f )
        nmQuad.setScale( 0.28f, 0.28f )
        nmQuad.setColor( 0.55f, 0.85f, 0.40f, 1.0f )
        nmQuad.setTexture( imgTex )
        nmQuad.setMaterial( 3 )
        nmQuad.setSpecular( 1.5f, 48.0f )

        # 动画三角（layer1，顶部，色相循环）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            ret false
        }
        tri.setLayer( 1 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.6f, 0.0f )
        tri.setScale( 0.3f, 0.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 相机1：depth=10、mask 仅 layer2、viewport 右半、深绿清屏
        SLang.RenderCamera cam = pipe.addCamera( 10 )
        if cam == null || cam.isValid == false
        {
            ret false
        }
        if cam.setCullMask( 4 ) == false || cam.setExtents( -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            ret false
        }
        if cam.setViewport( 625, 0, 625, 720 ) == false || cam.setClearColor( 0.0f, 0.25f, 0.1f, 1.0f ) == false
        {
            ret false
        }
        if cam.setClearFlags( SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH ) == false
        {
            ret false
        }

        # ── Phase C：细分立方体（每面 2x2 子块，f 面留空，e 面透明）──
        # 材质门面串联（SLangRender 纯 SL 类）：Shader(SlPhong 单一
        # shader) -> Texture(192x128 六面图集逐像素构建) -> Material
        # (a..f 每面一份 + 主材质 clone 白色)——对象贴图/颜色/队列/
        # 材质路由全部从门面 Material/Shader 字段派生后下发。
        RenderTestCube._cubeMesh = RenderTestCube.makeComplexCubeMesh( 1.0f )
        if RenderTestCube._cubeMesh == null
        {
            Console.println( "[ui] FAIL: makeComplexCubeMesh" )
            ret false
        }
        Console.println( "[cube] subdivided mesh verts=" + RenderTestCube._cubeMesh.vertexCount.toString() + " indices=" + RenderTestCube._cubeMesh.getTriangles().length.toString() )
        Shader phongShader = Shader( "SlPhong", "// vertex: reuse builtin VS_COMMON_POS_UV", "// fragment: reuse builtin FS_PHONG_TEX" )
        Texture atlas = RenderTestCube.makeCubeAtlas()
        if atlas == null || atlas.isValid == false
        {
            Console.println( "[ui] FAIL: makeCubeAtlas" )
            ret false
        }
        Material matA = RenderTestCube.makeFaceMaterial( phongShader, atlas, 0, "CubeFaceA" )
        Material matB = RenderTestCube.makeFaceMaterial( phongShader, atlas, 1, "CubeFaceB" )
        Material matC = RenderTestCube.makeFaceMaterial( phongShader, atlas, 2, "CubeFaceC" )
        Material matD = RenderTestCube.makeFaceMaterial( phongShader, atlas, 3, "CubeFaceD" )
        Material matE = RenderTestCube.makeFaceMaterial( phongShader, atlas, 4, "CubeFaceE" )
        Material matF = RenderTestCube.makeFaceMaterial( phongShader, atlas, 5, "CubeFaceF" )
        Material matMain = matA.clone()
        matMain.name = "CubeMain"
        matMain.setColor( Color.white() )
        Console.println( "[mat] main: " + matMain.toString() + " shader=" + matMain.shader.name + " " + matMain.getTexture().toString() )
        Console.println( "[mat] faces: " + matB.toString() + " | " + matC.toString() + " | " + matD.toString() )
        string eflag = "false"
        if matE.isTransparent
        {
            eflag = "true"
        }
        Console.println( "[mat] e(transparent)=" + eflag + " f(EMPTY)=" + matF.toString() )
        if RenderTestCube._cubeVerts == 0
        {
            RenderTestCube._cubeVerts = Memory.alloc( 120 * 16 )
        }
        if RenderTestCube._cubeVerts == 0
        {
            Console.println( "[ui] FAIL: cube verts alloc" )
            ret false
        }
        # 门面 Texture(Float32 RGBA) -> RGBA8 显存块 -> RenderTexture
        SLang.RenderTexture atlasRt = RenderTestHelpers.textureToRenderTexture( matMain.getTexture() )
        if atlasRt == null
        {
            Console.println( "[ui] FAIL: atlas upload - " + SLang.Render.errorString() )
            ret false
        }
        RenderTestCube._cubeObj = pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
        if RenderTestCube._cubeObj == null
        {
            Console.println( "[ui] FAIL: cube addObject - " + SLang.Render.errorString() )
            ret false
        }
        # 顶点已烘焙 NDC：位置/缩放保持单位；贴图/颜色取自门面 matMain
        # （图集 atlasRt + 白色调制，六面同槽共用一张纹理）；e 面
        # alpha 0.45 -> 由 isTransparent 派生透明队列 3000 后画叠加；
        # 材质路由由 shader 名派生（SlPhong -> 1）+ 贴图高光 + 投影
        # 阴影（聚光点源 -> 阴影随灯摇晃）
        RenderTestCube._cubeObj.setTexture( atlasRt )
        Color mc = matMain.getColor()
        RenderTestCube._cubeObj.setColor( mc.r, mc.g, mc.b, mc.a )
        Int32 matRoute = 0
        if matMain.shader.name == "SlPhong"
        {
            matRoute = 1
        }
        RenderTestCube._cubeObj.setMaterial( matRoute )
        RenderTestCube._cubeObj.setSpecular( 1.2f, 10.0f )
        RenderTestCube._cubeObj.setShadow( 1 )
        if matE.isTransparent
        {
            RenderTestCube._cubeObj.setQueue( 3000 )
        }
        RenderTestCube.updateCube( _t )

        Int64 px = Memory.alloc( 1250 * 720 * 4 )
        if px == 0
        {
            # 可诊断性：px 分配失败原先静默 ret false（堆耗尽时 RenderTest._pipe 悬空
            # 全部 tick 无声跳过，极难定位）
            Console.println( "[ui] FAIL: frame buffer alloc (SL heap exhausted?)" )
            ret false
        }
        RenderTest._pipe = pipe
        RenderTest._pixels = px
        RenderTest._texW = 1250
        RenderTest._texH = 720
        ret true
    }

    # 状态栏 + 按钮高亮（当前后端绿色）


    # 状态栏 + 按钮高亮（当前后端绿色）
    public static void updateStatus()
    {
        if _status != null
        {
            _status.setText( "backend: " + SLang.Render.currentBackend() + " | " + SLang.Render.rendererInfo() )
        }
        if _btnGl == null
        {
            ret
        }
        if _btnDx == null
        {
            ret
        }
        if _btnVk == null
        {
            ret
        }
        if _btnWeb == null
        {
            ret
        }
        string b = SLang.Render.currentBackend()
        if b == "gl"
        {
            _btnGl.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnGl.setStyleSheet( "" )
        }
        if b == "d3d11"
        {
            _btnDx.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnDx.setStyleSheet( "" )
        }
        if b == "vk"
        {
            _btnVk.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnVk.setStyleSheet( "" )
        }
        if b == "gles"
        {
            _btnWeb.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnWeb.setStyleSheet( "" )
        }
    }

    # 4 个按钮回调（无参 static，经 clicked(Function) 桥接）


    # 4 个按钮回调（无参 static，经 clicked(Function) 桥接）
    public static void onBtnGl()
    {
        _userPicked = true
        switchBackend( "gl" )
    }



    public static void onBtnDx()
    {
        _userPicked = true
        switchBackend( "d3d11" )
    }



    public static void onBtnVk()
    {
        _userPicked = true
        switchBackend( "vk" )
    }



    public static void onBtnWeb()
    {
        _userPicked = true
        switchBackend( "gles" )
    }

    # 自动轮播（7s 一拍）：d3d11 -> vk -> gles -> gl，用户点过按钮即停


    # 自动轮播（7s 一拍）：d3d11 -> vk -> gles -> gl，用户点过按钮即停
    public static void onAutoCycle()
    {
        if _userPicked
        {
            ret
        }
        if _cycleStep == 0
        {
            switchBackend( "d3d11" )
        }
        elif _cycleStep == 1
        {
            switchBackend( "vk" )
        }
        elif _cycleStep == 2
        {
            switchBackend( "gles" )
        }
        elif _cycleStep == 3
        {
            switchBackend( "gl" )
        }
        _cycleStep = _cycleStep + 1
    }



    public static void onQuit()
    {
        Console.println( "[QT] quit timer fired (normal 60s exit)" )
        if _app != null
        {
            _app.quit()
        }
    }

    # ══════════════════════════════════════════════════════════════════
    # Phase AUDIO：SLangAudio 模块端到端（probe / 整段解码 / 流式 / 播放）
    # fixture：test_audio.wav / test_audio.mp4(sowt-PCM) /
    #          test_audio.aac(ADTS) / test_audio_aac.mp4(mp4a-AAC)
    # 后端：sl_audio_lib.dll（minimp4 + minimp3 CC0；MF AAC MFT；waveOut）
    # ══════════════════════════════════════════════════════════════════

    # fixture 路径（相对 CWD 优先，绝对路径兜底，同 test_image.png 约定）


    # ── Phase B：QT 窗口 + 后端切换 UI（返回 2=PASS 1=SKIP 0=FAIL）──
    # 顶部按钮行（OpenGL/D3D11/Vulkan/WebGL-GLES）点击切换渲染底层；
    # 7s 自动轮播自动验证四后端在 QT 帧循环下持续渲染（用户点击后停）；
    # 终判 = 帧数 + gl 位 + 至少一个其他后端位。
    public static Int32 runQtWindow()
    {
        string kind = SLang.QT.backendKind()
        if kind != "qt"
        {
            Console.println( "-- Phase B: skipped (backend=" + kind + "; build+deploy the Qt backend to enable) --" )
            ret 1
        }
        if RenderTest._pipe == null || RenderTest._pixels == 0
        {
            Console.println( "-- Phase B: skipped (Phase A did not init pipeline) --" )
            ret 1
        }

        Console.println( "-- Phase B: QT window + backend switcher (buttons: OpenGL/D3D11/Vulkan/WebGL-GLES; 7s auto-cycle) --" )

        _app = SLang.QT.newApp()
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        host.setTitle( "SLangRender multi-backend (click: OpenGL / D3D11 / Vulkan / WebGL)" )
        host.resize( 296, 372 )

        # 按钮行（点击即切换渲染底层）
        _btnGl = SLang.QT.newButton( host.handle, "OpenGL" )
        _btnGl.setGeometry( 10, 10, 64, 24 )
        _btnDx = SLang.QT.newButton( host.handle, "D3D11" )
        _btnDx.setGeometry( 78, 10, 64, 24 )
        _btnVk = SLang.QT.newButton( host.handle, "Vulkan" )
        _btnVk.setGeometry( 146, 10, 64, 24 )
        _btnWeb = SLang.QT.newButton( host.handle, "WebGL" )
        _btnWeb.setGeometry( 214, 10, 72, 24 )
        _btnGl.setToolTip( "switch render backend to WGL + OpenGL 3.3" )
        _btnDx.setToolTip( "switch render backend to Direct3D 11" )
        _btnVk.setToolTip( "switch render backend to Vulkan (offscreen)" )
        _btnWeb.setToolTip( "switch render backend to EGL + GLES 3.0 (WebGL stack)" )

        # 状态栏（当前后端 + 渲染器）
        _status = SLang.QT.newLabel( host.handle, "" )
        _status.setGeometry( 10, 38, 276, 18 )

        # 渲染画面
        _label = SLang.QT.newLabel( host.handle, "" )
        _label.setGeometry( 10, 58, 276, 296 )
        host.show()
        Console.println( "[QT] window shown (296x372, auto-quit after 60s) -- if not visible, check taskbar / secondary display" )

        # 信号连接（clicked -> 无参 static 回调经 Function 桥；
        # SL 的 || 链上限 2 个运算符，逐个检查）
        Int64 bGl = _btnGl.clicked( RenderTestQt.onBtnGl )
        Int64 bDx = _btnDx.clicked( RenderTestQt.onBtnDx )
        Int64 bVk = _btnVk.clicked( RenderTestQt.onBtnVk )
        Int64 bWeb = _btnWeb.clicked( RenderTestQt.onBtnWeb )
        if bGl == 0 || bDx == 0
        {
            Console.println( "[QT] FAIL: backend button signal connect (gl=" + bGl.toString() + " dx=" + bDx.toString() + ")" )
            ret 0
        }
        if bVk == 0 || bWeb == 0
        {
            Console.println( "[QT] FAIL: backend button signal connect (vk=" + bVk.toString() + " web=" + bWeb.toString() + ")" )
            ret 0
        }

        updateStatus()

        _t = 0.0f
        _backendMask = 0
        _cycleStep = 0
        _userPicked = false
        SLang.QTimer quitT = SLang.QT.newTimer( 60000, true, RenderTestQt.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 16, false, RenderTestQt.onTick )
        SLang.QTimer cycleT = SLang.QT.newTimer( 7000, false, RenderTestQt.onAutoCycle )
        _app.exec()

        Console.println( "[QT] renderFrames=" + _renderFrames.toString() + " pixOk=" + _pixOk.toString() + " backendMask=" + _backendMask.toString() )

        animT.delete()
        cycleT.delete()
        quitT.delete()
        host.delete()

        if _renderFrames < 60 || _pixOk < 60
        {
            Console.println( "[QT] FAIL: frame loop too slow (need >= 60 rendered + 60 filled)" )
            ret 0
        }
        # 后端掩码：gl 位必在（奇数）+ 至少一个其他后端在 QT 循环里渲染过
        if ( _backendMask % 2 ) == 0 || _backendMask < 3
        {
            Console.println( "[QT] FAIL: backend switching did not render (mask=" + _backendMask.toString() + ", expect >= 3 with gl bit)" )
            ret 0
        }
        # Phase C 断言：立方体动态网格在（最后轮换的）当前后端上传成功过
        if RenderTestCube._cubeFirst != 1
        {
            Console.println( "[QT] FAIL: cube mesh upload never succeeded (Mesh + MESH_CUSTOM channel broken)" )
            ret 0
        }
        Console.println( "[QT] Phase B: PASS (backend-switchable render: mask=" + _backendMask.toString() + " [gl/d3d11/vk/gles bits 1/2/4/8]; 13-stage renderTexture each frame + spinning cube)" )
        ret 2
    }
}
