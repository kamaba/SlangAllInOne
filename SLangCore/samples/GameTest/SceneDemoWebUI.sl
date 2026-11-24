import SLangWebUI;
import SLangImage;
import Std;
import Core;

# SceneDemo 的网页版（H5）宿主：把 SimGameEngine 的离屏 RGBA8 帧经原生
# JPEG 编码 + 8 槽落盘推给浏览器 canvas 显示（与 RenderTestWebUI push 模式
# 同款机制）。渲染始终跑在 SLang 主线程（SceneDemo.frameTick 驱动），WebUI
# 事件线程只处理「要切哪个分辨率 / 哪个场景 / 是否退出」等简单状态，规避
# GL/D3D11 上下文线程亲和风险。
#
# 画布外的 HTML 工具栏提供：
#   - 分辨率下拉框（常用手机/平板/HD）：选中后即时 rs.resize + 重分配像素块
#   - 场景按钮 1~5：切 SceneDemo 的五个场景
#   - FPS 标签：JS 侧按实际刷新计数显示帧数
# 页面纯 ASCII（File.writeAllText 文件模式，无内联体积限制）。
public class SceneDemoWebUI
{
    static SLang.WebUIWindow _win = null
    static string _rootDir = ""
    static Array<string> _paths = null       # 预缓存 8 槽帧文件路径（帧循环零分配）
    static Int32 _slot = 0                   # 8 槽轮换计数
    static Int32 _latest = 0                 # 最新已落盘槽（JS frame() 回调读取）
    static Int32 _frames = 0                 # 成功推帧数（FPS 由 JS 侧统计）
    static Int32 _err = 0                    # 编码/落盘失败打印一次
    static bool _ready = false               # show 完成、进入 wait 后置 true

    # 供 SceneDemo.frameTick 消费的跨模块状态已下沉到 SceneDemo.webPending*
    # （页面事件写、主线程读的简单标量）；本类只剩展示/推帧状态。
    static bool isWeb = false

    # ── 页面 JS 错误回传（仅出错时分配字符串）────────────────────
    public static void onErr( Int64 e )
    {
        Console.println( "[SceneWeb][JSERR] " + SLang.WebUI.getArgString( e, 0 ) )
    }

    # ── 分辨率选择：JS setRes(w,h) -> 记录请求，主线程 frameTick 执行 resize ──
    public static void onSetRes( Int64 e )
    {
        Int32 w = SLang.WebUI.getArgInt( e, 0 ).toInt32()
        Int32 h = SLang.WebUI.getArgInt( e, 1 ).toInt32()
        if w >= 16 && h >= 16 && w <= 4096 && h <= 4096
        {
            SceneDemo.webPendingW = w
            SceneDemo.webPendingH = h
        }
        SLang.WebUI.returnBool( e, true )
    }

    # ── 场景切换：JS setScene(idx) -> 记录请求 ──
    public static void onSetScene( Int64 e )
    {
        Int32 idx = SLang.WebUI.getArgInt( e, 0 ).toInt32()
        if idx >= 0 && idx < SceneDemoWebUI.sceneCount
        {
            SceneDemo.webPendingScene = idx
        }
        SLang.WebUI.returnBool( e, true )
    }

    # ── 帧泵：JS await frame() 每 33ms 调一次 ──
    # 渲染/编码/落盘都在这个 WebUI 事件回调内完成，主线程阻塞在 wait()，
    # 避免主线程 VM 与事件线程 VM 并发重入（实测 0xC0000005）。
    # D3D11 是自由线程后端，事件线程渲染无 GL 上下文亲和问题（沿用
    # RenderTestWebUI push 模式结论）。
    public static void onFrame( Int64 e )
    {
        if SceneDemoWebUI._ready == false || SceneDemo.webReqQuit
        {
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        if SceneDemo.webFrame() == false
        {
            SLang.WebUI.returnInt( e, 0 )
            ret
        }
        SceneDemoWebUI.pushFrame( SceneDemo.pixels, SceneDemo.renderW, SceneDemo.renderH )
        SLang.WebUI.returnInt( e, SceneDemoWebUI._latest )
    }

    # ── 退出：JS quit() -> exitAll（webui 线程直接终止进程）──
    public static void onQuit( Int64 e )
    {
        SceneDemo.webReqQuit = true
        SLang.WebUI.returnBool( e, true )
        SLang.WebUI.exitAll()
    }

    # ── 推一帧：由 SceneDemo.frameTick 在主线程渲染完成后调用 ──
    # dstPtr = 本帧 RGBA8 块（top-down）；w/h = 当前渲染尺寸
    public static void pushFrame( Int64 dstPtr, Int32 w, Int32 h )
    {
        if SceneDemoWebUI._ready == false || dstPtr == 0
        {
            ret
        }
        Int64 blob = Image.ImageFfi.libEncodeMem( 3, 82, w, h, dstPtr )
        if blob == 0
        {
            if SceneDemoWebUI._err == 0
            {
                SceneDemoWebUI._err = 1
                Console.println( "[SceneWeb] FAIL: JPEG encode - " + Image.ImageFfi.lastErrorText() )
            }
            ret
        }
        SceneDemoWebUI._slot = SceneDemoWebUI._slot + 1
        Int32 slot = SceneDemoWebUI._slot % 8
        bool saved = Image.ImageFfi.libBlobSave( blob, SceneDemoWebUI._paths[slot] )
        Image.ImageFfi.libBlobFree( blob )
        if saved == false
        {
            if SceneDemoWebUI._err == 0
            {
                SceneDemoWebUI._err = 1
                Console.println( "[SceneWeb] FAIL: blob save - " + SceneDemoWebUI._paths[slot] )
            }
            ret
        }
        SceneDemoWebUI._frames = SceneDemoWebUI._frames + 1
        # 发布最新槽号（slot+1，0 保留为「无帧」）；JS 轮询 frame() 取它
        SceneDemoWebUI._latest = slot + 1
    }

    # ── 场景配置（可配置多个场景）────────────────────────────────
    # 增删场景只改这里 + SceneDemo.loadScene 的文件映射 + sceneCount。
    # 菜单项与场景内顶部按钮条都由这张表生成，二者始终一致。
    static Int32 sceneCount = 5
    public static string sceneLabel( Int32 i )
    {
        if i == 0
        {
            ret "Ball"
        }
        if i == 1
        {
            ret "Shapes"
        }
        if i == 2
        {
            ret "Probe"
        }
        if i == 3
        {
            ret "Gallery"
        }
        ret "Rotate"
    }

    # 生成 JS 场景名数组字面量：'Ball','Shapes',...
    public static string buildSceneListJS()
    {
        string s = ""
        Int32 i = 0
        while i < SceneDemoWebUI.sceneCount
        {
            if i > 0
            {
                s = s + ","
            }
            s = s + "'" + SceneDemoWebUI.sceneLabel( i ) + "'"
            i = i + 1
        }
        ret s
    }

    # ── 生成 H5 页面 ──────────────────────────────────────────────
    # 两层 UI：总入口 = UI 菜单（可配置多场景，点一项进入）；场景内 =
    # 顶部一排按钮菜单（Menu 返回 + 场景切换按钮 + 分辨率 + 尺寸 + FPS）。
    # canvas 接收推帧（img -> WebGL texImage2D，避免直接 <img> 缩放失真）。
    public static string buildPage()
    {
        string html = ""
        html = html + "<!DOCTYPE html><html><head><meta charset='utf-8'><title>SceneDemo H5</title><style>"
        html = html + "body{margin:0;background:#0e0e18;color:#cfd3dc;font-family:Segoe UI,Arial,sans-serif}"
        html = html + "#home{position:fixed;left:0;top:0;right:0;bottom:0;background:radial-gradient(circle at 50% 28%,#1b2442,#0a0a11 72%);display:flex;flex-direction:column;align-items:center;justify-content:center;z-index:9}"
        html = html + "#home h1{margin:0 0 4px;font-size:30px;letter-spacing:2px;color:#eef1f8}"
        html = html + "#home .sub{margin:0 0 24px;font-size:13px;color:#8f97ad}"
        html = html + "#homeMenu{display:flex;flex-direction:column;align-items:center}"
        html = html + ".mi{min-width:280px;margin:5px 0;padding:13px 18px;border:1px solid #3a3a52;border-radius:6px;background:#1b1b2e;color:#cfd3dc;cursor:pointer;font-size:15px;text-align:left;font-family:inherit}"
        html = html + ".mi:hover{background:#283a6e;border-color:#5a78c8;color:#fff}"
        html = html + ".mi b{display:inline-block;width:28px;color:#7fd4ff}"
        html = html + ".scn.on{background:#2d8f4e;color:#fff;font-weight:bold}"
        html = html + "#stage{display:none}"
        html = html + "#bar{display:flex;align-items:center;gap:6px;padding:8px 10px;background:#181826;flex-wrap:wrap}"
        html = html + "button{padding:4px 10px;border:1px solid #3a3a52;border-radius:4px;background:#23233a;color:#cfd3dc;cursor:pointer;font-size:12px}"
        html = html + "button.on{background:#2d8f4e;color:white;font-weight:bold}"
        html = html + "button.home{background:#3a3a6a;color:#fff}"
        html = html + "select{padding:4px 6px;border:1px solid #3a3a52;border-radius:4px;background:#23233a;color:#cfd3dc;font-size:12px}"
        html = html + "#lbl{font-size:12px;color:#9aa0ae;margin-left:4px}"
        html = html + "#fps{font-size:12px;color:#7fd4ff;margin-left:auto}"
        html = html + "#wrap{padding:10px;text-align:center}"
        html = html + "canvas{border:1px solid #3a3a52;background:#08080c}"
        html = html + "</style></head><body>"
        html = html + "<div id='home'><h1>SceneDemo</h1><div class='sub'>select a scene to enter</div><div id='homeMenu'></div></div>"
        html = html + "<div id='stage'><div id='bar'><button id='homeBtn' class='home'>Menu</button>"
        html = html + "<span id='scenes'></span>"
        html = html + "<select id='res' title='render size'>"
        html = html + "<option value='640,360'>Default 640x360</option>"
        html = html + "<option value='360,640'>Phone 360x640</option>"
        html = html + "<option value='375,667'>iPhone SE 375x667</option>"
        html = html + "<option value='390,844'>iPhone 12/13 390x844</option>"
        html = html + "<option value='393,851'>Android 393x851</option>"
        html = html + "<option value='412,915'>Android 412x915</option>"
        html = html + "<option value='430,932'>iPhone Max 430x932</option>"
        html = html + "<option value='667,375'>Landscape 667x375</option>"
        html = html + "<option value='768,1024'>Tablet 768x1024</option>"
        html = html + "<option value='1280,720'>HD 1280x720</option>"
        html = html + "</select>"
        html = html + "<span id='lbl'>[640x360]</span><span id='fps'>0.0 fps</span></div>"
        html = html + "<div id='wrap'><canvas id='glc' width='640' height='360'></canvas></div></div>"
        html = html + "<script src='webui.js'></script>"
        html = html + "<script>(function(){"
        html = html + "var gl=null,tex=null,frames=0,t0=Date.now(),slot=0,pending=null;"
        html = html + "var cv=document.getElementById('glc');"
        html = html + "gl=cv.getContext('webgl')||cv.getContext('experimental-webgl');"
        html = html + "if(!gl){document.getElementById('fps').textContent='WebGL unavailable';return;}"
        html = html + "var pr=gl.createProgram();"
        html = html + "var vs=gl.createShader(gl.VERTEX_SHADER);gl.shaderSource(vs,'attribute vec2 aP;attribute vec2 aUV;varying vec2 vUV;void main(){vUV=aUV;gl_Position=vec4(aP,0.0,1.0);}');gl.compileShader(vs);"
        html = html + "var fs=gl.createShader(gl.FRAGMENT_SHADER);gl.shaderSource(fs,'precision mediump float;varying vec2 vUV;uniform sampler2D s;void main(){gl_FragColor=texture2D(s,vUV);}');gl.compileShader(fs);"
        html = html + "gl.attachShader(pr,vs);gl.attachShader(pr,fs);gl.linkProgram(pr);gl.useProgram(pr);"
        html = html + "var buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);"
        html = html + "var pl=gl.getAttribLocation(pr,'aP'),tl=gl.getAttribLocation(pr,'aUV');"
        html = html + "gl.enableVertexAttribArray(pl);gl.vertexAttribPointer(pl,2,gl.FLOAT,false,16,0);"
        html = html + "gl.enableVertexAttribArray(tl);gl.vertexAttribPointer(tl,2,gl.FLOAT,false,16,8);"
        html = html + "gl.uniform1i(gl.getUniformLocation(pr,'s'),0);"
        html = html + "tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,tex);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);"
        html = html + "gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);"
        html = html + "function resize(w,h){cv.width=w;cv.height=h;document.getElementById('lbl').textContent='['+w+'x'+h+']';gl.viewport(0,0,w,h);}"
        html = html + "async function draw(){"
        html = html + "var n=await frame();if(n>0){"
        html = html + "var img=new Image();img.onload=function(){gl.bindTexture(gl.TEXTURE_2D,tex);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,img);"
        html = html + "gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,0,1, 1,-1,1,1, 1,1,1,0, -1,-1,0,1, 1,1,1,0, -1,1,0,0]),gl.DYNAMIC_DRAW);"
        html = html + "gl.clearColor(0.03,0.03,0.05,1);gl.clear(gl.COLOR_BUFFER_BIT);gl.drawArrays(gl.TRIANGLES,0,6);"
        html = html + "frames++;var el=(Date.now()-t0)/1000;if(el>0)document.getElementById('fps').textContent=(frames/el).toFixed(1)+' fps';"
        html = html + "};img.src='frame_'+n+'.jpg?t='+Date.now();}"
        html = html + "}"
        html = html + "setInterval(function(){try{draw();}catch(e){}},33);"
        html = html + "var SCENES=[" + SceneDemoWebUI.buildSceneListJS() + "];"
        html = html + "var home=document.getElementById('home'),stage=document.getElementById('stage');"
        html = html + "var hm=document.getElementById('homeMenu'),sb=document.getElementById('scenes');"
        html = html + "function iScene(i){home.style.display='none';stage.style.display='block';var bs=sb.children;for(var k=0;k<bs.length;k++)bs[k].className=(k===i)?'scn on':'scn';try{setScene(i);}catch(e){}}"
        html = html + "for(var i=0;i<SCENES.length;i++){"
        html = html + "var b=document.createElement('button');b.className='mi';b.innerHTML='<b>'+(i+1)+'</b>'+SCENES[i];"
        html = html + "b.onclick=(function(k){return function(){iScene(k);};})(i);hm.appendChild(b);"
        html = html + "var c=document.createElement('button');c.className='scn';c.textContent=(i+1)+' '+SCENES[i];"
        html = html + "c.onclick=(function(k){return function(){iScene(k);};})(i);sb.appendChild(c);}"
        html = html + "document.getElementById('homeBtn').onclick=function(){stage.style.display='none';home.style.display='flex';};"
        html = html + "var sel=document.getElementById('res');"
        html = html + "sel.onchange=async function(){var p=this.value.split(',');var w=parseInt(p[0],10),h=parseInt(p[1],10);resize(w,h);try{await setRes(w,h);}catch(e){}};"
        html = html + "})();"
        html = html + "</script></body></html>"
        ret html
    }

    # ── 主入口：WebUI 窗口 + 帧服务根目录 + 事件绑定（先绑后显）──
    public static bool runWebUI()
    {
        Console.println( "-- SceneDemo H5: WebUI browser render + phone resolution + FPS --" )
        SLang.WebUI.init()
        SceneDemoWebUI._win = SLang.WebUI.newWindow()
        if SceneDemoWebUI._win == null || SceneDemoWebUI._win.handle == 0
        {
            Console.println( "[SceneWeb] skipped: window create failed (webui_lib missing?)" )
            ret false
        }
        if SceneDemoWebUI._win.setPort( 51731 ) == false
        {
            Console.println( "[SceneWeb] WARN: setPort(51731) failed, using auto port" )
        }
        string cwd = IO.Directory.getCurrentDirectory()
        SceneDemoWebUI._rootDir = cwd + "/out/scene_webui"
        IO.Directory.createDirectory( SceneDemoWebUI._rootDir )
        SceneDemoWebUI._paths = Array<string>( 8 )
        Int32 pi = 0
        while pi < 8
        {
            SceneDemoWebUI._paths[pi] = SceneDemoWebUI._rootDir + "/frame_" + pi.toString() + ".jpg"
            pi = pi + 1
        }
        if SceneDemoWebUI._win.setRootFolder( SceneDemoWebUI._rootDir ) == false
        {
            Console.println( "[SceneWeb] skipped: setRootFolder failed" )
            ret false
        }
        if Image.ImageFfi.ensureReady() == false
        {
            Console.println( "[SceneWeb] skipped: image lib not ready - " + Image.ImageFfi.lastErrorText() )
            ret false
        }
        Int64 bFrame = SceneDemoWebUI._win.bindEvent( "frame", "onFrame" )
        Int64 bRes = SceneDemoWebUI._win.bindEvent( "setRes", "onSetRes" )
        Int64 bScene = SceneDemoWebUI._win.bindEvent( "setScene", "onSetScene" )
        Int64 bQuit = SceneDemoWebUI._win.bindEvent( "quit", "onQuit" )
        Int64 bErr = SceneDemoWebUI._win.bindEvent( "err", "onErr" )
        if bFrame == 0 || bRes == 0 || bScene == 0 || bQuit == 0
        {
            Console.println( "[SceneWeb] FAIL: bind (frame=" + bFrame.toString() + " res=" + bRes.toString() + " scene=" + bScene.toString() + " quit=" + bQuit.toString() + ")" )
            ret false
        }
        SceneDemoWebUI._win.setSize( 760, 560 )
        SceneDemoWebUI._win.setCenter()
        bool pageOk = File.writeAllText( SceneDemoWebUI._rootDir + "/index.html", SceneDemoWebUI.buildPage() )
        if pageOk == false
        {
            Console.println( "[SceneWeb] FAIL: write index.html" )
            ret false
        }
        # 引擎场景初始化（主线程）：D3D11 后端 + 5 场景脚本 + 像素块
        if SceneDemo.webInit( 640, 360 ) == false
        {
            Console.println( "[SceneWeb] FAIL: webInit" )
            ret false
        }
        SceneDemoWebUI.isWeb = true
        bool shown = SceneDemoWebUI._win.show( "index.html" )
        if shown == false
        {
            Console.println( "[SceneWeb] skipped: show failed (no browser?)" )
            ret false
        }
        SceneDemoWebUI._win.focus()
        # 复位推帧状态（show 之前引擎尚未渲染，pushFrame 会跳过）
        SceneDemoWebUI._slot = 0
        SceneDemoWebUI._frames = 0
        SceneDemoWebUI._err = 0
        SceneDemo.webPendingW = 0
        SceneDemo.webPendingH = 0
        SceneDemo.webPendingScene = 0 - 1
        SceneDemo.webReqQuit = false
        SceneDemoWebUI._ready = true
        Console.println( "[SceneWeb] page shown; frame pump active (out/scene_webui)" )

        # 主线程阻塞在 wait()：帧渲染全部由 JS frame() 事件回调驱动，
        # 与主线程无 VM 并发。onQuit / 浏览器关窗会解除 wait()。
        SLang.WebUI.wait()
        Console.println( "[SceneWeb] wait returned, frames=" + SceneDemoWebUI._frames.toString() )
        SLang.WebUI.clean()
        ret true
    }
}
