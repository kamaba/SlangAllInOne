import SLangWebUI;
import SLangRender;
import SLangImage;
import SLangAudio;
import Math;
import Std;

# Phase W WebUI 窗口（SLangWebUI + WebGL 帧流整合）—— 替代 Phase B Qt 窗口的
# 浏览器渲染面板（RenderTestQt 保留但 main 不再调用）：
#   WebUI 开浏览器窗口，页面里 WebGL canvas 做显示基底；
#   SLangRender 管线照常 runStages 出 RGBA 帧（共享 RenderTest._pipe/_pixels），
#   原生侧 sl_image_lib 直通编码 JPEG（libEncodeMem 直接吃 _pixels 原生指针，
#   零 SL 逐字节搬运）-> libBlobSave 落盘 frame_a/frame_b.jpg 双缓冲轮换 ->
#   页面 fetch + texImage2D 上屏（全屏 quad shader，WebGL 纹理采样）。
#   顶部 4 按钮（OpenGL/D3D11/Vulkan/WebGL-GLES）切换渲染底层
#   （switchBackend：initializeBackend + 场景全量重建），状态栏实时显示
#   当前 backend + 渲染器；JS 每 33ms 拉一帧；7s 自动轮播（用户点击后停）；
#   60s 自动退出 -> 帧数断言 + 后端掩码断言（与 Qt phase 同一验收口径）。
# 帧泵完全由 JS 侧驱动（webui 事件串行模式），SL VM 单线程无并发风险。
public class RenderTestWebUI
{

    # ── Phase W WebUI / 后端切换 UI 状态 ──────────────────────────
    static SLang.WebUIWindow _win = null
    public static Int32 _backendMask = 0     # gl=1 d3d11=2 vk=4 gles=8（帧泵内渲染记账）
    public static Int32 _cycleStep = 0       # 自动轮播步进（0..3：d3d11/vk/gles/gl）
    public static bool _userPicked = false   # 用户点过按钮后停止自动轮播
    public static Float32 _t = 0.0f
    public static Int32 _renderFrames = 0
    public static Int32 _encFrames = 0       # JPEG 编码 + 落盘成功帧数
    public static Int32 _stageErr = 0        # runStages 失败信息（打印一次）
    public static Int32 _encErr = 0          # 编码/落盘失败信息（打印一次）
    static Int32 _slot = 0                   # 双缓冲文件轮换（0->frame_a 1->frame_b）
    static string _rootDir = ""              # WebUI 文件服务根目录（绝对路径）

    # ── 帧泵 tick（JS setInterval 每 33ms 经 bind 调用）────────────
    # t 推进 -> 聚光灯摇晃 -> 立方体自转 -> runStages（完整 13 阶段）->
    # RGBA 帧原生 JPEG 编码落盘（双缓冲轮换）-> 返回文件槽（1=a 2=b 0=未就绪）
    public static void onFrame( Int64 e )
    {
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
        markBackendRendered()
        # ── RGBA 帧原生 JPEG 编码（直通 _pixels 指针，零拷贝）──
        Int32 fmt = Image.ImageFfi.formatToInt( Image.EImageFormat.Jpeg )
        Int64 blob = Image.ImageFfi.libEncodeMem( fmt, 85, RenderTest._texW, RenderTest._texH, RenderTest._pixels )
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
        string path = _rootDir + "/frame_b.jpg"
        if ( _slot % 2 ) == 1
        {
            path = _rootDir + "/frame_a.jpg"
        }
        bool saved = Image.ImageFfi.libBlobSave( blob, path )
        Image.ImageFfi.libBlobFree( blob )
        if saved == false
        {
            if _encErr == 0
            {
                _encErr = 1
                Console.println( "[webgl] FAIL: blob save - " + path )
            }
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        _encFrames = _encFrames + 1
        if ( _slot % 2 ) == 1
        {
            SLang.WebUI.returnInt( e, 1 )
        }
        else
        {
            SLang.WebUI.returnInt( e, 2 )
        }
    }

    # WebUI 循环内按当前后端记账（每帧调，位或幂等）
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

    # ── 后端切换核心（与 RenderTestQt.switchBackend 同款，含 2026-11-13
    # 内存泄漏修复：先释放旧帧缓冲再清引用）────────────────────────
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
        if SLang.Render.initializeBackend( name ) == false
        {
            Console.println( "[webui] backend '" + name + "' unavailable - " + SLang.Render.errorString() )
            if SLang.Render.initializeBackend( "gl" ) == false
            {
                pushStatus()
                ret
            }
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
        string b = SLang.Render.currentBackend()
        string js = "setStatus('" + b + "','" + SLang.Render.rendererInfo() + "')"
        _win.runScript( js )
    }

    # ── 4 个按钮回调（JS pick('name') -> 后端切换，返回是否切换成功）──
    public static void onBtnGl( Int64 e )
    {
        _userPicked = true
        switchBackend( "gl" )
        SLang.WebUI.returnBool( e, true )
    }

    public static void onBtnDx( Int64 e )
    {
        _userPicked = true
        switchBackend( "d3d11" )
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

    # 自动轮播（JS 7s 一拍）：d3d11 -> vk -> gles -> gl；用户点过按钮返回
    # false，JS 收到后停轮播
    public static void onAutoCycle( Int64 e )
    {
        if _userPicked
        {
            SLang.WebUI.returnBool( e, false )
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
        SLang.WebUI.returnBool( e, true )
    }

    # 60s 自动退出（JS setTimeout 触发）
    public static void onShutdown( Int64 e )
    {
        Console.println( "[WebUI] quit timer fired (normal 60s exit)" )
        SLang.WebUI.exitAll()
    }

    # ── WebUI 场景全量重建（640x360，A3 同款物体 + v3.4 光照 + 立方体）──
    # 与 RenderTestQt.rebuildScene 同构，尺寸换 640x360（JPEG 编码轻量，
    # 浏览器 WebGL 线性过滤放大显示）
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

    # ── WebGL 页面（内联 HTML；全部用单引号规避 SL 字符串转义）────────
    # 结构：顶部按钮行 + 状态栏 + WebGL canvas（640x360）。
    # JS：全屏 quad shader + 纹理；33ms pump -> 调 bind 的 frame() 拿文件槽
    #     -> fetch frame_a/b.jpg -> texImage2D -> drawArrays；
    #     7s 轮播 cycle()（返回 false 停）；60s setTimeout shutdown()。
    public static string buildPage()
    {
        string html = ""
        html = html + "<!DOCTYPE html><html><head><meta charset='utf-8'><title>SLangRender WebGL (WebUI)</title><style>"
        html = html + "body{margin:0;background:#101018;color:#cfd3dc;font-family:Segoe UI,Arial,sans-serif}"
        html = html + "#bar{display:flex;align-items:center;gap:8px;padding:10px 12px;background:#181826}"
        html = html + "button{padding:5px 14px;border:1px solid #3a3a52;border-radius:4px;background:#23233a;color:#cfd3dc;cursor:pointer;font-size:13px}"
        html = html + "button.on{background:#2d8f4e;color:white;font-weight:bold}"
        html = html + "#status{margin-left:10px;font-size:12px;color:#9aa0ae}"
        html = html + "#wrap{padding:12px}canvas{border:1px solid #3a3a52;border-radius:4px;image-rendering:auto}"
        html = html + "#fps{margin-top:8px;font-size:12px;color:#9aa0ae}"
        html = html + "</style></head><body>"
        html = html + "<div id='bar'>"
        html = html + "<button id='bgl'>OpenGL</button><button id='bdx'>D3D11</button>"
        html = html + "<button id='bvk'>Vulkan</button><button id='bweb'>WebGL-GLES</button>"
        html = html + "<span id='status'>connecting...</span>"
        html = html + "</div>"
        html = html + "<div id='wrap'><canvas id='glc' width='640' height='360'></canvas><div id='fps'></div></div>"
        html = html + "<script src='webui.js'></script>"
        html = html + "<script>"
        html = html + "var gl=null,tex=null,frames=0,t0=Date.now();"
        html = html + "function initGL(){"
        html = html + "var cv=document.getElementById('glc');"
        html = html + "gl=cv.getContext('webgl')||cv.getContext('experimental-webgl');"
        html = html + "if(!gl){document.getElementById('fps').textContent='WebGL unavailable';return;}"
        html = html + "var vs='attribute vec2 p;varying vec2 v;void main(){v=vec2(p.x*0.5+0.5,0.5-p.y*0.5);gl_Position=vec4(p,0.0,1.0);}';"
        html = html + "var fs='precision mediump float;varying vec2 v;uniform sampler2D s;void main(){gl_FragColor=texture2D(s,v);}';"
        html = html + "function sh(t,src){var o=gl.createShader(t);gl.shaderSource(o,src);gl.compileShader(o);return o;}"
        html = html + "var pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,vs));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,fs));gl.linkProgram(pr);gl.useProgram(pr);"
        html = html + "var buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);"
        html = html + "gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);"
        html = html + "var loc=gl.getAttribLocation(pr,'p');gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);"
        html = html + "tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,tex);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);"
        html = html + "gl.viewport(0,0,640,360);gl.clearColor(0.06,0.06,0.10,1.0);gl.clear(gl.COLOR_BUFFER_BIT);"
        html = html + "}"
        html = html + "initGL();"
        html = html + "function drawImg(img){"
        html = html + "gl.bindTexture(gl.TEXTURE_2D,tex);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,img);gl.drawArrays(gl.TRIANGLES,0,6);"
        html = html + "frames++;var el=(Date.now()-t0)/1000;document.getElementById('fps').textContent='frames: '+frames+'  ('+(frames/el).toFixed(1)+' fps)';"
        html = html + "}"
        html = html + "setInterval(async function(){"
        html = html + "if(!gl)return;"
        html = html + "try{var n=await frame();if(n>0){"
        html = html + "var img=new Image();img.src=(n==1?'frame_a.jpg':'frame_b.jpg')+'?t='+Date.now();"
        html = html + "await img.decode();drawImg(img);}}catch(e){}"
        html = html + "},33);"
        html = html + "var cyc=null;"
        html = html + "cyc=setInterval(async function(){"
        html = html + "try{var more=await cycle();if(!more)clearInterval(cyc);}catch(e){}"
        html = html + "},7000);"
        html = html + "setTimeout(function(){try{shutdown();}catch(e){}},60000);"
        html = html + "function setStatus(b,info){"
        html = html + "document.getElementById('status').textContent='backend: '+b+' | '+info;"
        html = html + "var map={gl:'bgl',d3d11:'bdx',vk:'bvk',gles:'bweb'};"
        html = html + "for(var k in map){var el=document.getElementById(map[k]);if(k==b){el.className='on';}else{el.className='';}}"
        html = html + "}"
        html = html + "document.getElementById('bgl').onclick=async function(){await pick_gl();};"
        html = html + "document.getElementById('bdx').onclick=async function(){await pick_d3d11();};"
        html = html + "document.getElementById('bvk').onclick=async function(){await pick_vk();};"
        html = html + "document.getElementById('bweb').onclick=async function(){await pick_gles();};"
        html = html + "</script></body></html>"
        ret html
    }

    # ── Phase W 主入口（返回 2=PASS 1=SKIP 0=FAIL）────────────────
    public static Int32 runWebUIWindow()
    {
        if RenderTest._pipe == null || RenderTest._pixels == 0
        {
            Console.println( "-- Phase W: skipped (Phase A did not init pipeline) --" )
            ret 1
        }
        Console.println( "-- Phase W: WebUI window + WebGL canvas frame stream (buttons: OpenGL/D3D11/Vulkan/WebGL-GLES; 7s auto-cycle) --" )

        SLang.WebUI.init()
        _win = SLang.WebUI.newWindow()
        if _win == null || _win.handle == 0
        {
            Console.println( "-- Phase W: skipped (webui window create failed; webui_lib.dll missing?) --" )
            ret 1
        }

        # 文件服务根目录（绝对路径；双缓冲 JPEG 落在 out\rt_webui）
        string cwd = IO.Directory.getCurrentDirectory()
        _rootDir = cwd + "/out/rt_webui"
        IO.Directory.createDirectory( _rootDir )
        if _win.setRootFolder( _rootDir ) == false
        {
            Console.println( "-- Phase W: skipped (setRootFolder failed: " + _rootDir + ") --" )
            ret 1
        }

        # 原生图像编码库预载（libEncodeMem 直通帧指针的前置）
        if Image.ImageFfi.ensureReady() == false
        {
            Console.println( "-- Phase W: skipped (sl_image_lib not ready: " + Image.ImageFfi.lastErrorText() + ") --" )
            ret 1
        }

        # 绑定（先绑后显）
        Int64 bFrame = _win.bindHandle( "frame", RenderTestWebUI.onFrame )
        Int64 bCycle = _win.bindHandle( "cycle", RenderTestWebUI.onAutoCycle )
        Int64 bQuit = _win.bindHandle( "shutdown", RenderTestWebUI.onShutdown )
        Int64 bGl = _win.bindHandle( "pick_gl", RenderTestWebUI.onBtnGl )
        Int64 bDx = _win.bindHandle( "pick_d3d11", RenderTestWebUI.onBtnDx )
        Int64 bVk = _win.bindHandle( "pick_vk", RenderTestWebUI.onBtnVk )
        Int64 bWeb = _win.bindHandle( "pick_gles", RenderTestWebUI.onBtnWeb )
        if bFrame == 0 || bCycle == 0 || bQuit == 0
        {
            Console.println( "[WebUI] FAIL: core bind (frame=" + bFrame.toString() + " cycle=" + bCycle.toString() + " quit=" + bQuit.toString() + ")" )
            ret 0
        }
        if bGl == 0 || bDx == 0 || bVk == 0 || bWeb == 0
        {
            Console.println( "[WebUI] FAIL: backend button bind (gl=" + bGl.toString() + " dx=" + bDx.toString() + " vk=" + bVk.toString() + " web=" + bWeb.toString() + ")" )
            ret 0
        }

        _win.setSize( 680, 480 )
        _win.setCenter()
        bool shown = _win.show( buildPage() )
        if shown == false
        {
            Console.println( "-- Phase W: skipped (show failed; no browser available?) --" )
            ret 1
        }
        Console.println( "[WebUI] page shown (WebGL canvas 640x360, auto-quit after 60s) -- if no browser opened, check default browser settings" )

        # 复位计数后进入事件循环（阻塞至窗口关闭 / 60s 自动退出）
        _t = 0.0f
        _backendMask = 0
        _cycleStep = 0
        _userPicked = false
        _renderFrames = 0
        _encFrames = 0
        _slot = 0
        SLang.WebUI.wait()
        SLang.WebUI.clean()

        Console.println( "[WebUI] renderFrames=" + _renderFrames.toString() + " encFrames=" + _encFrames.toString() + " backendMask=" + _backendMask.toString() )

        if _renderFrames < 100 || _encFrames < 100
        {
            Console.println( "[WebUI] FAIL: frame loop too slow (need >= 100 rendered + 100 encoded/saved)" )
            ret 0
        }
        # 后端掩码：gl 位必在（奇数）+ 至少一个其他后端在循环里渲染过
        if ( _backendMask % 2 ) == 0 || _backendMask < 3
        {
            Console.println( "[WebUI] FAIL: backend switching did not render (mask=" + _backendMask.toString() + ", expect >= 3 with gl bit)" )
            ret 0
        }
        # 立方体动态网格在（最后轮换的）当前后端上传成功过
        if RenderTestCube._cubeFirst != 1
        {
            Console.println( "[WebUI] FAIL: cube mesh upload never succeeded (Mesh + MESH_CUSTOM channel broken)" )
            ret 0
        }
        Console.println( "[WebUI] Phase W: PASS (WebGL canvas frame stream: mask=" + _backendMask.toString() + " [gl/d3d11/vk/gles bits 1/2/4/8]; 13-stage renderTexture + native JPEG encode -> browser texImage2D)" )
        ret 2
    }
}
