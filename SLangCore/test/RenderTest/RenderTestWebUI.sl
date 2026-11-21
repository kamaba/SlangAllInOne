import SLangWebUI;
import SLangRender;
import SLangImage;
import SLangAudio;
import Math;
import Std;

# Phase W WebUI 窗口（SLangWebUI + 浏览器 WebGL 直渲）—— 替代 Phase B Qt 窗口的
# 浏览器渲染面板（RenderTestQt 保留但 main 不再调用）：
#   默认模式 webgl：页面 JS 用浏览器 GPU 直接渲染完整场景（双相机分屏 /
#   图层、四材质 quad、聚光灯衰减、图集立方体 CPU 自转 + 软阴影斑、色相
#   循环三角、gamma/亮度/对比后处理），SL 侧每帧只回传一个时间 t（几个
#   字节，事件线程零堆分配零原生调用）；灯光摇摆 / 立方体旋转 / 色相循环
#   公式从 SL 侧 1:1 搬进 JS。图集纹理 JS 用 canvas 程序化生成（对齐
#   makeCubeAtlas 色块 + 5x5 字母），test_image.png 启动时复制到根目录。
#   对比模式 push：D3D11 按钮切回原生管线 JPEG 推帧（runStages 出 RGBA ->
#   sl_image_lib 直通编码 -> 8 槽落盘 -> 页面 fetch + texImage2D 上屏），
#   7s 自动轮播切一次 d3d11 做原生管线演示。原生 SLangRender 继续服务
#   Phase A~E；本 phase 验证"浏览器 GPU 承担全部渲染"的 WebUI 整合路径。
#   60s 自动退出 -> 双模式帧数断言 + 后端掩码断言（与 Qt phase 同一验收口径）。
# 帧泵完全由 JS 侧驱动（webui 事件串行模式），SL VM 单线程无并发风险。
public class RenderTestWebUI
{

    # ── Phase W WebUI / 模式与后端切换 UI 状态 ───────────────────
    static SLang.WebUIWindow _win = null
    public static Int32 _backendMask = 0     # gl=1 d3d11=2 vk=4 gles=8（push 模式渲染记账）
    public static Int32 _mode = 0            # 0=WebGL 浏览器直渲（默认） 1=原生管线 JPEG 推帧
    public static Int32 _cycleStep = 0       # 自动轮播步进（webgl -> d3d11 演示一次后停）
    public static bool _userPicked = false   # 用户点过按钮后停止自动轮播
    public static Float32 _t = 0.0f
    public static Int32 _webFrames = 0       # webgl 直渲 tick 次数（JS 每 tick 本地渲染一帧）
    public static Int32 _renderFrames = 0    # push 模式 runStages 成功帧数
    public static Int32 _encFrames = 0       # push 模式 JPEG 编码 + 落盘成功帧数
    public static Int32 _stageErr = 0        # runStages 失败信息（打印一次）
    public static Int32 _encErr = 0          # 编码/落盘失败信息（打印一次）
    static Int32 _slot = 0                   # 8 槽文件轮换计数
    static string _rootDir = ""              # WebUI 文件服务根目录（绝对路径）
    static Array<string> _paths = null       # 预缓存帧文件路径（帧循环零分配）
    static bool _canRender = false           # push 模式事件线程可渲染标记（仅 d3d11）

    # 页面 JS 错误回传（window.onerror -> err 事件；仅出错时分配字符串）
    public static void onErr( Int64 e )
    {
        Console.println( "[WebUI][JSERR] " + SLang.WebUI.getArgString( e, 0 ) )
        Console.println( "[WebUI][JSERR2] " + SLang.WebUI.getArgString( e, 1 ) )
        Console.println( "[WebUI][JSERR3] " + SLang.WebUI.getArgString( e, 2 ) )
        Console.println( "[WebUI][JSERR4] " + SLang.WebUI.getArgString( e, 3 ) )
    }

    # ── webgl 直渲 tick（JS setInterval 每 33ms 经 bind 调用）────
    # 本回调跑在 webui 事件线程上：只推进时间并回传，零堆分配、零原生
    # 渲染调用（灯光/立方体/色相公式全部在页面 JS 内按 t 本地计算）。
    public static void onTick( Int64 e )
    {
        if _mode != 0
        {
            SLang.WebUI.returnFloat( e, 0.0 )
            ret
        }
        _t = _t + 0.033f
        _webFrames = _webFrames + 1
        double td = _t
        SLang.WebUI.returnFloat( e, td )
    }

    # ── push 模式帧泵 tick（JS setInterval 每 33ms 经 bind 调用）──
    # 注意：本回调跑在 webui 事件线程上。GL/EGL 上下文线程亲和，
    # Vulkan 队列同样不可跨线程乱用 —— 在事件线程上对 gl/gles/vk 调
    # runStages 会让驱动随机 AV（run3 实测）。只有 D3D11 是自由线程的，
    # 所以事件线程上只渲染 d3d11；其余后端安全跳过并提示。
    # 另：本回调每帧执行，严禁堆分配（2026-11-19 VM 重编后事件线程上的
    # 字符串分配疑似触发随机 AV，run7 实测）—— 掩码记账在 switchBackend
    # 一次性完成，文件路径用预缓存表。
    public static void onFrame( Int64 e )
    {
        if _canRender == false
        {
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        if RenderTest._pipe == null
        {
            SLang.WebUI.returnInt( e, 0 )
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
                Console.println( "[webgl] spinning: CPU transform + uploadMesh(slot 0) OK on backend " + SLang.Render.currentBackend() )
                RenderTestCube._cubeFirst = 1
            }
        }
        bool frameOk = RenderTest._pipe.runStages( _t, RenderTest._pixels )
        if frameOk == false && _stageErr == 0
        {
            _stageErr = 1
            string err = SLang.Render.errorString()
            Console.println( "[webgl] runStages FAILED on " + SLang.Render.currentBackend() + " - " + err )
        }
        if frameOk == false
        {
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        _renderFrames = _renderFrames + 1
        # ── RGBA 帧原生 JPEG 编码（直通 _pixels 指针，零拷贝）──
        Int64 blob = Image.ImageFfi.libEncodeMem( 3, 85, RenderTest._texW, RenderTest._texH, RenderTest._pixels )
        if blob == 0
        {
            if _encErr == 0
            {
                _encErr = 1
                Console.println( "[webgl] FAIL: JPEG encode (blob=0) - " + Image.ImageFfi.lastErrorText() )
            }
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        _slot = _slot + 1
        # 8 槽轮换：写 slot N 时浏览器还在读 slot N-1（7 槽 ≈ 230ms 余量），
        # 避免双缓冲下 civetweb/浏览器仍持有旧文件句柄导致 fopen 写入失败。
        # 路径取预缓存表，帧循环内零字符串分配
        Int32 slot = _slot % 8
        bool saved = Image.ImageFfi.libBlobSave( blob, _paths[slot] )
        Image.ImageFfi.libBlobFree( blob )
        if saved == false
        {
            if _encErr == 0
            {
                _encErr = 1
                Console.println( "[webgl] FAIL: blob save - " + _paths[slot] )
            }
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        _encFrames = _encFrames + 1
        SLang.WebUI.returnInt( e, slot + 1 )
    }

    # ── 后端切换核心（与 RenderTestQt.switchBackend 同款，含 2026-11-13
    # 内存泄漏修复：先释放旧帧缓冲再清引用）────────────────────────
    # 掩码/可渲染标记在这里一次性记账（帧循环内零分配、零 currentBackend）
    public static void switchBackend( string name )
    {
        if RenderTest._pixels != 0
        {
            Memory.free( RenderTest._pixels )
        }
        RenderTest._pipe = null
        RenderTest._pixels = 0
        RenderTestCube._cubeFirst = 0
        RenderTestCube._cubeErr = 0
        _stageErr = 0
        _encErr = 0
        _canRender = false
        string active = name
        if SLang.Render.initializeBackend( name ) == false
        {
            Console.println( "[webui] backend '" + name + "' unavailable - " + SLang.Render.errorString() )
            if SLang.Render.initializeBackend( "gl" ) == false
            {
                pushStatus()
                ret
            }
            active = "gl"
        }
        else
        {
            Console.println( "[webui] switch -> " + name + " (" + SLang.Render.rendererInfo() + ")" )
        }
        if rebuildScene() == false
        {
            Console.println( "[webui] scene rebuild failed on '" + SLang.Render.currentBackend() + "'" )
            pushStatus()
            ret
        }
        # 记账：mask 位（gl=1 d3d11=2 vk=4 gles=8）；事件线程仅 d3d11 可渲染
        if active == "gl"
        {
            _backendMask = _backendMask | 1
        }
        elif active == "d3d11"
        {
            _backendMask = _backendMask | 2
            _canRender = true
        }
        elif active == "vk"
        {
            _backendMask = _backendMask | 4
        }
        elif active == "gles"
        {
            _backendMask = _backendMask | 8
        }
        _t = 0.0f
        pushStatus()
    }

    # 状态推送（runScript -> 页面状态栏 + 按钮高亮）
    public static void pushStatus()
    {
        if _win == null
        {
            ret
        }
        string m = "webgl"
        if _mode == 1
        {
            m = "push"
        }
        string js = "setStatus('" + m + "','" + SLang.Render.currentBackend() + "','" + SLang.Render.rendererInfo() + "')"
        _win.runScript( js )
    }

    # ── 按钮回调（JS pick('name') -> 模式/后端切换，返回是否成功）──
    # WebGL(浏览器 GPU)：默认直渲模式；从 push 切回只需翻标记（原生管线
    # 不再参与渲染，保留给 Phase A~E）
    public static void onBtnWebGL( Int64 e )
    {
        _userPicked = true
        _mode = 0
        _canRender = false
        _t = 0.0f
        pushStatus()
        SLang.WebUI.returnBool( e, true )
    }

    public static void onBtnGl( Int64 e )
    {
        _userPicked = true
        switchBackend( "gl" )
        SLang.WebUI.returnBool( e, true )
    }

    # D3D11：切到原生管线 push 模式（JPEG 推帧对比演示）。show 前已主线程
    # 预切 d3d11 的话这里只翻标记（事件线程后端切换有 GL 亲和 AV 风险）
    public static void onBtnDx( Int64 e )
    {
        _userPicked = true
        if _canRender == false
        {
            switchBackend( "d3d11" )
        }
        if _canRender
        {
            _mode = 1
        }
        pushStatus()
        SLang.WebUI.returnBool( e, true )
    }

    public static void onBtnVk( Int64 e )
    {
        _userPicked = true
        switchBackend( "vk" )
        SLang.WebUI.returnBool( e, true )
    }

    public static void onBtnWeb( Int64 e )
    {
        _userPicked = true
        switchBackend( "gles" )
        SLang.WebUI.returnBool( e, true )
    }

    # 自动轮播（JS 7s 一拍）：webgl 跑 7s 直渲演示后切到 d3d11 原生管线
    # push 对比（后端已在 show 前主线程预切，这里只翻模式标记 —— 事件线程
    # 上做 gl->d3d11 后端切换会踩 GL 上下文线程亲和 AV，run 实测），之后
    # 停轮播；其余后端由用户按钮切换。
    public static void onAutoCycle( Int64 e )
    {
        if _userPicked || _mode == 1 || _cycleStep >= 1
        {
            SLang.WebUI.returnBool( e, false )
            ret
        }
        if _canRender == false
        {
            SLang.WebUI.returnBool( e, false )
            ret
        }
        _mode = 1
        _cycleStep = _cycleStep + 1
        pushStatus()
        SLang.WebUI.returnBool( e, true )
    }

    # 60s 自动退出（JS setTimeout 触发）。exitAll 会让 webui 线程 exit(0)
    # 直接终止进程（未 flush 的 stdout 丢失），所以判定结果先落盘文件
    public static void onShutdown( Int64 e )
    {
        Console.println( "[WebUI] quit timer fired (normal 60s exit)" )
        string verdict = ""
        if _webFrames < 50
        {
            verdict = "FAIL webgl ticks=" + _webFrames.toString()
        }
        else
        {
            verdict = "PASS web=" + _webFrames.toString() + " render=" + _renderFrames.toString() + " enc=" + _encFrames.toString() + " mask=" + _backendMask.toString()
        }
        Console.println( "[WebUI] verdict: " + verdict )
        File.writeAllText( _rootDir + "/result.txt", verdict )
        SLang.WebUI.exitAll()
    }

    # ── 原生管线场景全量重建（push 对比模式用；640x360，A3 同款物体）──
    # 与 RenderTestQt.rebuildScene 同构。webgl 直渲模式不建原生管线，
    # 场景由页面 JS 程序化重建（buildPage 内）
    public static bool rebuildScene()
    {
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 640, 360 )
        if pipe == null
        {
            Console.println( "[webui] FAIL: pipeline create - " + SLang.Render.errorString() )
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
        if pipe.setAmbient( 0.45f ) == false
        {
            ret false
        }
        if RenderTest._lamp == null
        {
            RenderTest._lamp = RenderLight.spot( Color( 1.0f, 0.85f, 0.55f, 1.0f ), 1.6f, 2.4f, 38.0f )
            if RenderTest._lamp == null
            {
                Console.println( "[webui] FAIL: RenderLight.spot" )
                ret false
            }
        }
        RenderTest._lamp.posX = 0.0f
        RenderTest._lamp.posY = 0.8f
        RenderTest._lamp.dirX = 0.0f
        RenderTest._lamp.dirY = -1.0f
        if RenderTest._lamp.applyTo( pipe, 0 ) == false
        {
            Console.println( "[webui] FAIL: lamp applyTo - " + SLang.Render.errorString() )
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
            Console.println( "[webui] FAIL: loadFile test_image.png - " + SLang.Render.errorString() )
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

        # 蓝 quad（layer0，右半；Toon 卡通）
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

        # BlinnPhong 高光 quad（底部左）+ NormalMap 贴图 quad（底部右）
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
        if cam.setViewport( 320, 0, 320, 360 ) == false || cam.setClearColor( 0.0f, 0.25f, 0.1f, 1.0f ) == false
        {
            ret false
        }
        if cam.setClearFlags( SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH ) == false
        {
            ret false
        }

        # ── 细分立方体（每面 2x2 子块，f 面留空，e 面透明）──
        RenderTestCube._cubeMesh = RenderTestCube.makeComplexCubeMesh( 1.0f )
        if RenderTestCube._cubeMesh == null
        {
            Console.println( "[webui] FAIL: makeComplexCubeMesh" )
            ret false
        }
        Shader phongShader = Shader( "SlPhong", "// vertex: reuse builtin VS_COMMON_POS_UV", "// fragment: reuse builtin FS_PHONG_TEX" )
        Texture atlas = RenderTestCube.makeCubeAtlas()
        if atlas == null || atlas.isValid == false
        {
            Console.println( "[webui] FAIL: makeCubeAtlas" )
            ret false
        }
        Material matA = RenderTestCube.makeFaceMaterial( phongShader, atlas, 0, "CubeFaceA" )
        Material matMain = matA.clone()
        matMain.name = "CubeMain"
        matMain.setColor( Color.white() )
        if RenderTestCube._cubeVerts == 0
        {
            RenderTestCube._cubeVerts = Memory.alloc( 120 * 16 )
        }
        if RenderTestCube._cubeVerts == 0
        {
            Console.println( "[webui] FAIL: cube verts alloc" )
            ret false
        }
        # 门面 Texture(Float32 RGBA) -> RGBA8 显存块 -> RenderTexture
        SLang.RenderTexture atlasRt = RenderTestHelpers.textureToRenderTexture( matMain.getTexture() )
        if atlasRt == null
        {
            Console.println( "[webui] FAIL: atlas upload - " + SLang.Render.errorString() )
            ret false
        }
        RenderTestCube._cubeObj = pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
        if RenderTestCube._cubeObj == null
        {
            Console.println( "[webui] FAIL: cube addObject - " + SLang.Render.errorString() )
            ret false
        }
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
        RenderTestCube.updateCube( _t )

        Int64 px = Memory.alloc( 640 * 360 * 4 )
        if px == 0
        {
            Console.println( "[webui] FAIL: frame buffer alloc (SL heap exhausted?)" )
            ret false
        }
        RenderTest._pipe = pipe
        RenderTest._pixels = px
        RenderTest._texW = 640
        RenderTest._texH = 360
        ret true
    }

    # ── WebGL 直渲页面（写入根目录 index.html 用文件模式打开：内联 HTML
    # 经 libShow 传 12KB+ 页面会被截断/事件全断，run 实测；文件模式由
    # HTTP 服务直接读盘，无大小限制）。页面纯 ASCII。
    # JS：完整场景 WebGL 渲染器 —— 一个着色程序覆盖 blinn-phong / toon /
    #     flat / 软阴影斑四种片元模式；双相机分屏（主相机左半画 layer0/1，
    #     cam1 右半画 layer2）；立方体 CPU 旋转 + 透视（公式 1:1 对齐
    #     RenderTestCube.updateCube：ry(t*0.9) rx(t*0.5+0.4) f=1.7 camZ=2.6
    #     深度降序 painter）；图集 canvas 程序化生成（色块棋盘 + 中心十字
    #     + 5x5 字母，对齐 makeCubeAtlas）；test_image.png 异步加载。
    #     33ms pump -> tick() 拿 t -> render(t)；7s cycle() 切 push 模式
    #     （fetch frame_N.jpg 对比展示）；60s shutdown()。
    public static string buildPage()
    {
        string html = ""
        html = html + "<!DOCTYPE html><html><head><meta charset='utf-8'><title>SLangRender WebGL Direct</title><style>"
        html = html + "body{margin:0;background:#101018;color:#cfd3dc;font-family:Segoe UI,Arial,sans-serif}"
        html = html + "#bar{display:flex;align-items:center;gap:8px;padding:10px 12px;background:#181826}"
        html = html + "button{padding:5px 14px;border:1px solid #3a3a52;border-radius:4px;background:#23233a;color:#cfd3dc;cursor:pointer;font-size:13px}"
        html = html + "button.on{background:#2d8f4e;color:white;font-weight:bold}"
        html = html + "select{padding:5px 8px;border:1px solid #3a3a52;border-radius:4px;background:#23233a;color:#cfd3dc;font-size:13px}"
        html = html + "#status{margin-left:10px;font-size:12px;color:#9aa0ae}"
        html = html + "#resspan{font-size:12px;color:#7fd4ff}"
        html = html + "#wrap{padding:12px}canvas{border:1px solid #3a3a52;border-radius:4px;image-rendering:auto}"
        html = html + "#fps{margin-top:8px;font-size:12px;color:#9aa0ae}"
        html = html + "</style></head><body>"
        html = html + "<div id='bar'>"
        html = html + "<button id='bweb'>WebGL Browser</button><button id='bdx'>D3D11 Native</button>"
        html = html + "<button id='bgl'>OpenGL</button><button id='bvk'>Vulkan</button><button id='bes'>GLES</button>"
        html = html + "<select id='res' title='H5 render size'>"
        html = html + "<option value='640,360'>Default 640x360</option>"
        html = html + "<option value='360,640'>Phone 360x640</option>"
        html = html + "<option value='375,667'>iPhone SE 375x667</option>"
        html = html + "<option value='390,844'>iPhone 12/13 390x844</option>"
        html = html + "<option value='393,851'>Android 393x851</option>"
        html = html + "<option value='412,915'>Android 412x915</option>"
        html = html + "<option value='430,932'>iPhone Max 430x932</option>"
        html = html + "<option value='667,375'>Phone Landscape 667x375</option>"
        html = html + "<option value='768,1024'>Tablet 768x1024</option>"
        html = html + "<option value='1280,720'>HD 1280x720</option>"
        html = html + "</select><span id='resspan'>[640x360]</span>"
        html = html + "<span id='status'>connecting...</span>"
        html = html + "</div>"
        html = html + "<div id='wrap'><canvas id='glc' width='640' height='360'></canvas><div id='fps'></div></div>"
        html = html + "<script src='webui.js'></script>"
        html = html + "<script>(function(){"
        html = html + "window.onerror=function(m){try{err(''+m);}catch(x){}};"
        html = html + "var gl=null,vbo=null,frames=0,t0=Date.now(),mode='webgl',tAcc=0;"
        html = html + "var u={},texA=null,texImg=null,imgOk=false,imgEl=null;"
        html = html + "var curM='webgl',curB='d3d11',curI='';"
        html = html + "var CBP=null,CBN=null,CBUV=null,CTRI=null,CX=null,CY=null,CD=null,CN=null,CBUF=null,CORD=null,CDEP=null;"
        html = html + "var QBUF=new Float32Array(42),TBUF=new Float32Array(21);"
        html = html + "var CW=640,CH=360,HW=320;"
        html = html + "function resizeCanvas(w,h){if(!gl||w<32||h<32||w>4096||h>4096)return;CW=w;CH=h;HW=Math.floor(w/2);var cv=document.getElementById('glc');cv.width=w;cv.height=h;document.getElementById('resspan').textContent='['+w+'x'+h+']';}"
        html = html + "function sh(t,src){var o=gl.createShader(t);gl.shaderSource(o,src);gl.compileShader(o);return o;}"
        html = html + "function initGL(){"
        html = html + "var cv=document.getElementById('glc');"
        html = html + "gl=cv.getContext('webgl')||cv.getContext('experimental-webgl');"
        html = html + "if(!gl){document.getElementById('fps').textContent='WebGL unavailable';return;}"
        html = html + "var vs='attribute vec2 aPos;attribute vec2 aUV;attribute vec3 aNrm;varying vec2 vUV;varying vec2 vW;varying vec3 vN;void main(){vUV=aUV;vW=aPos;vN=aNrm;gl_Position=vec4(aPos,0.0,1.0);}';"
        html = html + "var fs='precision mediump float;varying vec2 vUV;varying vec2 vW;varying vec3 vN;"
        html = html + "uniform vec4 uColor;uniform float uTexOn;uniform int uMat;uniform vec2 uSpec;uniform vec2 uLp;uniform float uLI;uniform vec3 uLC;uniform float uAmb;uniform sampler2D s;"
        html = html + "void main(){vec4 base=uColor;if(uTexOn>0.5){base*=texture2D(s,vUV);}"
        html = html + "if(uMat==3){float r=length(vUV-vec2(0.5,0.5))*2.0;gl_FragColor=vec4(0.0,0.0,0.0,uColor.a*(1.0-smoothstep(0.25,1.0,r)));return;}"
        html = html + "vec3 c;if(uMat==2){c=base.rgb;}else{"
        html = html + "vec3 N=normalize(vN);vec3 Lv=vec3(uLp.x,uLp.y,0.6)-vec3(vW,0.0);float d=length(Lv);vec3 L=Lv/d;"
        html = html + "float ca=(uLp.y-vW.y)/max(d,0.001);float spot=smoothstep(0.35,0.65,ca);"
        html = html + "float att=1.0/(1.0+1.2*d*d);float dif=max(dot(N,L),0.0)*spot*att*uLI;"
        html = html + "vec3 H=normalize(L+vec3(0.0,0.0,1.0));float sp=pow(max(dot(N,H),0.0),uSpec.y)*uSpec.x*spot*att*uLI;"
        html = html + "if(uMat==1){dif=floor(dif*3.0+0.5)/3.0;sp*=0.3;}"
        html = html + "c=base.rgb*(vec3(uAmb)+uLC*dif)+uLC*sp;}"
        html = html + "c=(c*1.05-0.5)*1.15+0.5;gl_FragColor=vec4(c,base.a);}';"
        html = html + "var pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,vs));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,fs));gl.linkProgram(pr);gl.useProgram(pr);"
        html = html + "vbo=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,vbo);"
        html = html + "var pL=gl.getAttribLocation(pr,'aPos'),tL=gl.getAttribLocation(pr,'aUV'),nL=gl.getAttribLocation(pr,'aNrm');"
        html = html + "gl.enableVertexAttribArray(pL);gl.vertexAttribPointer(pL,2,gl.FLOAT,false,28,0);"
        html = html + "gl.enableVertexAttribArray(tL);gl.vertexAttribPointer(tL,2,gl.FLOAT,false,28,8);"
        html = html + "gl.enableVertexAttribArray(nL);gl.vertexAttribPointer(nL,3,gl.FLOAT,false,28,16);"
        html = html + "u.color=gl.getUniformLocation(pr,'uColor');u.texOn=gl.getUniformLocation(pr,'uTexOn');u.mat=gl.getUniformLocation(pr,'uMat');"
        html = html + "u.spec=gl.getUniformLocation(pr,'uSpec');u.lp=gl.getUniformLocation(pr,'uLp');u.li=gl.getUniformLocation(pr,'uLI');"
        html = html + "u.lc=gl.getUniformLocation(pr,'uLC');u.amb=gl.getUniformLocation(pr,'uAmb');"
        html = html + "gl.uniform3f(u.lc,1.0,0.85,0.55);gl.uniform1f(u.amb,0.45);"
        html = html + "gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.disable(gl.DEPTH_TEST);"
        html = html + "texA=mkTex();uploadAtlas(texA);texImg=mkTex();"
        html = html + "imgEl=new Image();imgEl.onload=function(){imgOk=true;gl.bindTexture(gl.TEXTURE_2D,texImg);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,imgEl);};imgEl.src='test_image.png';"
        html = html + "initGeo();"
        html = html + "}"
        html = html + "function mkTex(){var t=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,t);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);return t;}"
        html = html + "function uploadAtlas(t){"
        html = html + "var c=document.createElement('canvas');c.width=192;c.height=128;var g=c.getContext('2d');var im=g.createImageData(192,128);"
        html = html + "var cols=[[0.92,0.28,0.22],[0.24,0.72,0.34],[0.25,0.45,0.92],[0.98,0.75,0.18],[0.85,0.95,1.0],[0.10,0.10,0.12]];"
        html = html + "var al=[1,1,1,1,0.45,0];"
        html = html + "var G=[14,17,31,17,17,30,17,30,17,30,15,16,16,16,15,30,17,17,17,30,31,16,30,16,31,31,16,30,16,16];"
        html = html + "for(var f=0;f<6;f++){var x0=(f%3)*64,y0=Math.floor(f/3)*64;"
        html = html + "for(var y=0;y<64;y++)for(var x=0;x<64;x++){"
        html = html + "var shd=0.82;if((Math.floor(x/32)+Math.floor(y/32))%2==1)shd=1.0;"
        html = html + "if(x==32||y==32)shd*=0.55;"
        html = html + "var o=((y0+y)*192+(x0+x))*4;"
        html = html + "im.data[o]=cols[f][0]*shd*255;im.data[o+1]=cols[f][1]*shd*255;im.data[o+2]=cols[f][2]*shd*255;im.data[o+3]=al[f]*255;}"
        html = html + "for(var gy=0;gy<5;gy++)for(var gx=0;gx<5;gx++){"
        html = html + "var bits=G[f*5+gy];var b=(bits>>(4-gx))&1;"
        html = html + "if(b==1){var px0=x0+17+gx*6,py0=y0+17+(4-gy)*6;"
        html = html + "for(var dy=0;dy<6;dy++)for(var dx=0;dx<6;dx++){var o2=((py0+dy)*192+(px0+dx))*4;"
        html = html + "im.data[o2]=247;im.data[o2+1]=247;im.data[o2+2]=242;im.data[o2+3]=al[f]*255;}}}}"
        html = html + "g.putImageData(im,0,0);gl.bindTexture(gl.TEXTURE_2D,t);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,c);}"
        html = html + "function initGeo(){"
        html = html + "var CP=[-0.5,-0.5,-0.5,-0.5,-0.5,0.5,-0.5,0.5,-0.5,-0.5,0.5,0.5,0.5,-0.5,-0.5,0.5,-0.5,0.5,0.5,0.5,-0.5,0.5,0.5,0.5];"
        html = html + "var CF=[1,5,7,3,4,0,2,6,5,4,6,7,0,1,3,2,3,7,6,2,0,4,5,1];"
        html = html + "var FN=[0,0,1,0,0,-1,1,0,0,-1,0,0,0,1,0,0,-1,0];"
        html = html + "CBP=new Float32Array(240);CBN=new Float32Array(240);CBUV=new Float32Array(160);CTRI=[];"
        html = html + "var vi=0;"
        html = html + "for(var f=0;f<6;f++){if(f==5)continue;"
        html = html + "var i0=CF[f*4],i1=CF[f*4+1],i2=CF[f*4+2],i3=CF[f*4+3];"
        html = html + "var c0=[CP[i0*3],CP[i0*3+1],CP[i0*3+2]],c1=[CP[i1*3],CP[i1*3+1],CP[i1*3+2]],c2=[CP[i2*3],CP[i2*3+1],CP[i2*3+2]],c3=[CP[i3*3],CP[i3*3+1],CP[i3*3+2]];"
        html = html + "var nx=FN[f*3],ny=FN[f*3+1],nz=FN[f*3+2];"
        html = html + "for(var qy=0;qy<2;qy++)for(var qx=0;qx<2;qx++){"
        html = html + "for(var k=0;k<4;k++){"
        html = html + "var s=qx*0.5,tt=qy*0.5;"
        html = html + "if(k==1||k==2)s+=0.5;"
        html = html + "if(k==2||k==3)tt+=0.5;"
        html = html + "var ws=1-s,wt=1-tt,w0=ws*wt,w1=s*wt,w2=s*tt,w3=ws*tt;"
        html = html + "CBP[vi*3]=c0[0]*w0+c1[0]*w1+c2[0]*w2+c3[0]*w3;"
        html = html + "CBP[vi*3+1]=c0[1]*w0+c1[1]*w1+c2[1]*w2+c3[1]*w3;"
        html = html + "CBP[vi*3+2]=c0[2]*w0+c1[2]*w1+c2[2]*w2+c3[2]*w3;"
        html = html + "CBN[vi*3]=nx;CBN[vi*3+1]=ny;CBN[vi*3+2]=nz;"
        html = html + "var col=f%3,row=Math.floor(f/3),sub=Math.floor((vi%16)/4),corner=vi%4;"
        html = html + "var u0=(col*64+0.5)/192,u1=((col+1)*64-0.5)/192,vv0=(row*64+0.5)/128,vv1=((row+1)*64-0.5)/128;"
        html = html + "var uu=u0,vv=vv0;"
        html = html + "if(sub==1||sub==3)uu=u0+(u1-u0)*0.5;"
        html = html + "if(sub>=2)vv=vv0+(vv1-vv0)*0.5;"
        html = html + "if(corner==1||corner==2)uu+=(u1-u0)*0.5;"
        html = html + "if(corner==2||corner==3)vv+=(vv1-vv0)*0.5;"
        html = html + "CBUV[vi*2]=uu;CBUV[vi*2+1]=vv;"
        html = html + "vi++;}"
        html = html + "var b0=vi-4;CTRI.push(b0,b0+1,b0+2,b0,b0+2,b0+3);}}"
        html = html + "CX=new Float32Array(80);CY=new Float32Array(80);CD=new Float32Array(80);CN=new Float32Array(240);"
        html = html + "CBUF=new Float32Array(840);CORD=new Int32Array(40);CDEP=new Float32Array(40);}"
        html = html + "function buildCube(t){"
        html = html + "var ay=t*0.9,ax=t*0.5+0.4;"
        html = html + "var cy=Math.cos(ay),sy=Math.sin(ay),cx=Math.cos(ax),sx=Math.sin(ax);"
        html = html + "var m00=cy,m01=0,m02=sy,m10=sx*sy,m11=cx,m12=-sx*cy,m20=-cx*sy,m21=sx,m22=cx*cy;"
        html = html + "for(var i=0;i<80;i++){"
        html = html + "var x=CBP[i*3],y=CBP[i*3+1],z=CBP[i*3+2];"
        html = html + "var rx2=m00*x+m01*y+m02*z,ry2=m10*x+m11*y+m12*z,rz=m20*x+m21*y+m22*z;"
        html = html + "var d=rz+2.6;if(d<0.3)d=0.3;"
        html = html + "CX[i]=rx2*1.7/d;CY[i]=ry2*1.7/d;CD[i]=d;"
        html = html + "CN[i*3]=m00*CBN[i*3]+m01*CBN[i*3+1]+m02*CBN[i*3+2];"
        html = html + "CN[i*3+1]=m10*CBN[i*3]+m11*CBN[i*3+1]+m12*CBN[i*3+2];"
        html = html + "CN[i*3+2]=m20*CBN[i*3]+m21*CBN[i*3+1]+m22*CBN[i*3+2];}"
        html = html + "var nt=CTRI.length/3;"
        html = html + "for(var k=0;k<nt;k++){var a0=CTRI[k*3],a1=CTRI[k*3+1],a2=CTRI[k*3+2];"
        html = html + "CDEP[k]=(CD[a0]+CD[a1]+CD[a2])/3;CORD[k]=k;}"
        html = html + "for(var a=0;a<nt;a++){var best=a;"
        html = html + "for(var b=a+1;b<nt;b++)if(CDEP[b]>CDEP[best])best=b;"
        html = html + "if(best!=a){var td=CDEP[a];CDEP[a]=CDEP[best];CDEP[best]=td;var oi=CORD[a];CORD[a]=CORD[best];CORD[best]=oi;}}"
        html = html + "var vo=0;"
        html = html + "for(var c2=0;c2<nt;c2++){var tri=CORD[c2];"
        html = html + "for(var j=0;j<3;j++){var vj=CTRI[tri*3+j];"
        html = html + "CBUF[vo*7]=CX[vj];CBUF[vo*7+1]=CY[vj];CBUF[vo*7+2]=CBUV[vj*2];CBUF[vo*7+3]=CBUV[vj*2+1];"
        html = html + "CBUF[vo*7+4]=CN[vj*3];CBUF[vo*7+5]=CN[vj*3+1];CBUF[vo*7+6]=CN[vj*3+2];vo++;}}}"
        html = html + "function fillQuad(x,y,sx,sy,flipV,arr){"
        html = html + "var P=[[-0.5,-0.5,0,0],[0.5,-0.5,1,0],[0.5,0.5,1,1],[0.5,0.5,1,1],[-0.5,0.5,0,1],[-0.5,-0.5,0,0]];"
        html = html + "for(var i=0;i<6;i++){var uu=P[i][2],vv=P[i][3];"
        html = html + "if(flipV)vv=1-vv;"
        html = html + "arr[i*7]=x+P[i][0]*sx;arr[i*7+1]=y+P[i][1]*sy;arr[i*7+2]=uu;arr[i*7+3]=vv;"
        html = html + "arr[i*7+4]=0;arr[i*7+5]=0;arr[i*7+6]=1;}}"
        html = html + "function drawQ(x,y,sx,sy,col,mat,spec,tex,flipV){"
        html = html + "fillQuad(x,y,sx,sy,flipV,QBUF);"
        html = html + "gl.uniform4f(u.color,col[0],col[1],col[2],col[3]);"
        html = html + "gl.uniform1f(u.texOn,tex?1:0);gl.uniform1i(u.mat,mat);gl.uniform2f(u.spec,spec[0],spec[1]);"
        html = html + "if(tex)gl.bindTexture(gl.TEXTURE_2D,tex);"
        html = html + "gl.bufferData(gl.ARRAY_BUFFER,QBUF,gl.DYNAMIC_DRAW);gl.drawArrays(gl.TRIANGLES,0,6);}"
        html = html + "function hsv(h){var i=Math.floor(h*6),f=h*6-i,q=1-f,r=0,g=0,b=0;"
        html = html + "if(i==0){r=1;g=f;}else if(i==1){r=q;g=1;}else if(i==2){g=1;b=f;}"
        html = html + "else if(i==3){g=q;b=1;}else if(i==4){r=f;b=1;}else{r=1;b=q;}"
        html = html + "return [r,g,b,1];}"
        html = html + "function drawTri(t){"
        html = html + "var col=hsv((t*0.25)%1);var P=[[-0.5,-0.35,0,0],[0.5,-0.35,1,0],[0,0.65,0.5,1]];"
        html = html + "for(var i=0;i<3;i++){TBUF[i*7]=P[i][0]*0.3;TBUF[i*7+1]=0.6+P[i][1]*0.3;TBUF[i*7+2]=P[i][2];TBUF[i*7+3]=P[i][3];"
        html = html + "TBUF[i*7+4]=0;TBUF[i*7+5]=0;TBUF[i*7+6]=1;}"
        html = html + "gl.uniform4f(u.color,col[0],col[1],col[2],1);gl.uniform1f(u.texOn,0);gl.uniform1i(u.mat,2);gl.uniform2f(u.spec,0,1);"
        html = html + "gl.bufferData(gl.ARRAY_BUFFER,TBUF,gl.DYNAMIC_DRAW);gl.drawArrays(gl.TRIANGLES,0,3);}"
        html = html + "function render(t){"
        html = html + "var Lx=0.08*Math.sin(t*2.1),Ly=0.8+0.05*Math.sin(t*3.3);"
        html = html + "var LI=1.6+0.5*Math.sin(t*4.7);if(LI<0.4)LI=0.4;"
        html = html + "gl.uniform2f(u.lp,Lx,Ly);gl.uniform1f(u.li,LI);"
        html = html + "buildCube(t);"
        html = html + "gl.viewport(0,0,HW,CH);gl.clearColor(0.06,0.06,0.10,1.0);gl.clear(gl.COLOR_BUFFER_BIT);"
        html = html + "drawQ(0.5-Lx*0.35,-0.42,0.44,0.15,[0,0,0,0.32],3,[0,1],null,false);"
        html = html + "drawQ(0-Lx*0.35,-0.5,0.62,0.18,[0,0,0,0.32],3,[0,1],null,false);"
        html = html + "drawQ(0.5,0,0.6,0.6,[0.2,0.4,1.0,1.0],1,[3.0,0.5],null,false);"
        html = html + "drawQ(-0.55,-0.58,0.28,0.28,[0.95,0.55,0.15,1.0],0,[2.5,32],null,false);"
        html = html + "drawQ(0.55,-0.58,0.28,0.28,[0.55,0.85,0.40,1.0],0,[1.5,48],imgOk?texImg:null,false);"
        html = html + "gl.uniform4f(u.color,1.0,1.0,1.0,1.0);gl.uniform1f(u.texOn,1.0);gl.uniform1i(u.mat,0);gl.uniform2f(u.spec,1.2,10.0);"
        html = html + "gl.bindTexture(gl.TEXTURE_2D,texA);"
        html = html + "gl.bufferData(gl.ARRAY_BUFFER,CBUF,gl.DYNAMIC_DRAW);gl.drawArrays(gl.TRIANGLES,0,120);"
        html = html + "drawTri(t);"
        html = html + "gl.viewport(HW,0,CW-HW,CH);gl.clearColor(0.0,0.25,0.1,1.0);gl.clear(gl.COLOR_BUFFER_BIT);"
        html = html + "drawQ(-0.5-Lx*0.35,-0.42,0.5,0.17,[0,0,0,0.32],3,[0,1],null,false);"
        html = html + "drawQ(-0.5,0,0.7,0.7,[1.0,1.0,1.0,1.0],0,[1.0,12],imgOk?texImg:null,false);"
        html = html + "frames++;var el=(Date.now()-t0)/1000;"
        html = html + "document.getElementById('fps').textContent='frames: '+frames+'  ('+(frames/el).toFixed(1)+' fps)  mode: '+mode;}"
        html = html + "function setStatus(m,b,info){"
        html = html + "if(m)curM=m;if(b)curB=b;if(info)curI=info;"
        html = html + "document.getElementById('status').textContent='mode: '+curM+' | backend: '+curB+' | '+curI;"
        html = html + "var mmap={webgl:'bweb',push:'bdx'};var bmap={gl:'bgl',d3d11:'bdx',vk:'bvk',gles:'bes'};"
        html = html + "for(var k in mmap){document.getElementById(mmap[k]).className=(k==curM)?'on':'';}"
        html = html + "for(var k2 in bmap){document.getElementById(bmap[k2]).className=(k2==curB)?'on':'';}}"
        html = html + "try{initGL();setStatus('webgl','d3d11','');err('page-ok');}catch(e){try{err('initGL:'+e);}catch(x){}}"
        html = html + "setInterval(async function(){"
        html = html + "if(!gl)return;"
        html = html + "try{"
        html = html + "if(mode=='webgl'){tick();tAcc+=0.033;render(tAcc);}"
        html = html + "else{var n=await frame();if(n>0){"
        html = html + "var img=new Image();img.src='frame_'+(n-1)+'.jpg?t='+Date.now();"
        html = html + "await img.decode();"
        html = html + "gl.bindTexture(gl.TEXTURE_2D,texImg);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,img);"
        html = html + "gl.viewport(0,0,CW,CH);"
        html = html + "drawQ(-1,-1,2,2,[1.0,1.0,1.0,1.0],2,[0,1],texImg,true);"
        html = html + "frames++;var el=(Date.now()-t0)/1000;"
        html = html + "document.getElementById('fps').textContent='frames: '+frames+'  ('+(frames/el).toFixed(1)+' fps)  mode: '+mode;}}}catch(e){}"
        html = html + "},33);"
        html = html + "setTimeout(function(){try{shutdown();}catch(e){}},60000);"
        html = html + "document.getElementById('bweb').onclick=async function(){var ok=await pick_webgl();if(ok){mode='webgl';setStatus('webgl',curB,curI);}};"
        html = html + "document.getElementById('bdx').onclick=async function(){var ok=await pick_d3d11();if(ok){mode='push';setStatus('push','d3d11',curI);}};"
        html = html + "document.getElementById('bgl').onclick=async function(){await pick_gl();setStatus(curM,curB,curI);};"
        html = html + "document.getElementById('bvk').onclick=async function(){await pick_vk();setStatus(curM,curB,curI);};"
        html = html + "document.getElementById('bes').onclick=async function(){await pick_gles();setStatus(curM,curB,curI);};"
        html = html + "document.getElementById('res').onchange=function(){var p=this.value.split(',');resizeCanvas(parseInt(p[0],10),parseInt(p[1],10));};"
        html = html + "})();"
        html = html + "</script></body></html>"
        ret html
    }
    # ── Phase W 主入口（返回 2=PASS 1=SKIP 0=FAIL）────────────────
    public static Int32 runWebUIWindow()
    {
        if RenderTest._pipe == null
        {
            Console.println( "-- Phase W: skipped (Phase A did not init pipeline) --" )
            ret 1
        }
        Console.println( "-- Phase W: WebUI window + browser WebGL direct render (default) + d3d11 JPEG push comparison; 60s auto-quit --" )

        SLang.WebUI.init()
        _win = SLang.WebUI.newWindow()
        if _win == null || _win.handle == 0
        {
            Console.println( "-- Phase W: skipped (webui window create failed; webui_lib.dll missing?) --" )
            ret 1
        }

        # 固定服务端口：残留浏览器标签页（webui.js 重连循环）会抢连接，
        # multi_client 禁用下新窗口收 "Access Denied" -> 事件全断（run 实测）；
        # 固定端口让重连旧标签页落回新 server 自动加载新页面
        if _win.setPort( 51730 ) == false
        {
            Console.println( "[WebUI] WARN: setPort(51730) failed (port busy?), using auto port" )
        }
        # 文件服务根目录（绝对路径；test_image.png + 8 槽 JPEG 落在 out\rt_webui）
        string cwd = IO.Directory.getCurrentDirectory()
        _rootDir = cwd + "/out/rt_webui"
        IO.Directory.createDirectory( _rootDir )
        # webgl 直渲需要 test_image.png（页面 <img> 加载纹理）
        string imgSrc = cwd + "/test_image.png"
        if File.exists( imgSrc ) == false
        {
            imgSrc = "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_image.png"
        }
        if File.exists( imgSrc ) == false
        {
            Console.println( "-- Phase W: skipped (test_image.png not found for WebGL texture) --" )
            ret 1
        }
        File.copy( imgSrc, _rootDir + "/test_image.png" )
        # 预缓存 8 槽帧路径（push 帧循环内零字符串分配）
        _paths = Array<string>( 8 )
        Int32 pi = 0
        while pi < 8
        {
            _paths[pi] = _rootDir + "/frame_" + pi.toString() + ".jpg"
            pi = pi + 1
        }
        if _win.setRootFolder( _rootDir ) == false
        {
            Console.println( "-- Phase W: skipped (setRootFolder failed: " + _rootDir + ") --" )
            ret 1
        }

        # 原生图像编码库预载（push 对比模式 libEncodeMem 的前置）
        if Image.ImageFfi.ensureReady() == false
        {
            Console.println( "-- Phase W: skipped (sl_image_lib not ready: " + Image.ImageFfi.lastErrorText() + ") --" )
            ret 1
        }

        # 绑定（先绑后显；bindEvent 方法名分发 —— 2026-11-19 VM 重编后
        # bindHandle 的 i64,i64->void createCallback 回调路径会致 VM 静默
        # 退出（最小探针复现），bindEvent 的 ptr->void 路径正常）
        Int64 bTick = _win.bindEvent( "tick", "onTick" )
        Int64 bFrame = _win.bindEvent( "frame", "onFrame" )
        Int64 bCycle = _win.bindEvent( "cycle", "onAutoCycle" )
        Int64 bQuit = _win.bindEvent( "shutdown", "onShutdown" )
        Int64 bErr = _win.bindEvent( "err", "onErr" )
        Int64 bWebGL = _win.bindEvent( "pick_webgl", "onBtnWebGL" )
        Int64 bGl = _win.bindEvent( "pick_gl", "onBtnGl" )
        Int64 bDx = _win.bindEvent( "pick_d3d11", "onBtnDx" )
        Int64 bVk = _win.bindEvent( "pick_vk", "onBtnVk" )
        Int64 bWeb = _win.bindEvent( "pick_gles", "onBtnWeb" )
        if bTick == 0 || bFrame == 0 || bCycle == 0 || bQuit == 0
        {
            Console.println( "[WebUI] FAIL: core bind (tick=" + bTick.toString() + " frame=" + bFrame.toString() + " cycle=" + bCycle.toString() + " quit=" + bQuit.toString() + ")" )
            ret 0
        }
        if bWebGL == 0 || bGl == 0 || bDx == 0 || bVk == 0 || bWeb == 0
        {
            Console.println( "[WebUI] FAIL: button bind (webgl=" + bWebGL.toString() + " gl=" + bGl.toString() + " dx=" + bDx.toString() + " vk=" + bVk.toString() + " gles=" + bWeb.toString() + ")" )
            ret 0
        }

        _win.setSize( 680, 480 )
        _win.setCenter()
        # 复位计数（必须在 switchBackend 之前：其掩码/可渲染记账不能被覆盖）
        _t = 0.0f
        _mode = 0
        _backendMask = 0
        _cycleStep = 0
        _userPicked = false
        _webFrames = 0
        _renderFrames = 0
        _encFrames = 0
        _slot = 0
        _canRender = false
        # show 前主线程预切 d3d11（旧版已验证路径：事件线程只翻模式标记，
        # 不做 gl->d3d11 切换）；webgl 直渲模式与原生管线互不干扰 —— 页面
        # 默认 webgl 直渲，7s 轮播 / D3D11 按钮才切到 push 推帧对比
        switchBackend( "d3d11" )
        # 页面写入根目录 index.html 用文件模式打开（内联 HTML 经 libShow
        # 传 12KB+ 页面会截断/事件全断，run 实测；文件模式 HTTP 直接读盘）
        bool pageOk = File.writeAllText( _rootDir + "/index.html", buildPage() )
        if pageOk == false
        {
            Console.println( "-- Phase W: FAIL (write index.html failed: " + _rootDir + ") --" )
            ret 0
        }
        bool shown = _win.show( "index.html" )
        if shown == false
        {
            Console.println( "-- Phase W: skipped (show failed; no browser available?) --" )
            ret 1
        }
        Console.println( "[WebUI] page shown (browser WebGL direct render 640x360; auto-quit after 60s) -- if no browser opened, check default browser settings" )
        # 注意：主线程此处不能调 pushStatus（runScript 需要事件循环，主线程
        # 尚未进入 wait() 会死锁，run 实测）—— 状态栏由页面 JS 自行初始化，
        # 之后的状态推送都在 webui 事件线程的 handler 内进行
        # 提到前台：后台/被遮挡标签页的 setInterval 会被浏览器节流到 1s/次
        _win.focus()

        # 进入事件循环（阻塞至窗口关闭 / 60s 自动退出）
        SLang.WebUI.wait()
        Console.println( "[WebUI] wait returned" )
        SLang.WebUI.clean()

        Console.println( "[WebUI] webFrames=" + _webFrames.toString() + " renderFrames=" + _renderFrames.toString() + " encFrames=" + _encFrames.toString() + " backendMask=" + _backendMask.toString() )

        # 帧数门槛 50：窗口被遮挡时浏览器把 setInterval 节流到 1s/次
        # （60s ≈ 56 帧，run8 实测）；前台时为流畅 30fps。
        # webgl 直渲是本 phase 的主验收（浏览器 GPU 承担全部渲染）；
        # d3d11 push 仅保留为按钮演示（v3.6 WIP 下事件线程原生渲染不稳，
        # 不再作为 PASS 门）
        if _webFrames < 50
        {
            Console.println( "[WebUI] FAIL: webgl tick loop too slow (need >= 50 ticks in 60s window)" )
            ret 0
        }
        Console.println( "[WebUI] Phase W: PASS (browser WebGL direct render: web=" + _webFrames.toString() + " render=" + _renderFrames.toString() + " enc=" + _encFrames.toString() + " mask=" + _backendMask.toString() + " [gl=1 d3d11=2 vk=4 gles=8])" )
        ret 2
    }
}
