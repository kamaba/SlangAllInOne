import Core;
import Std;
import SLangWebUI;

# ============================================================================
# WebUIExamples —— python-webui/examples 的 SLang 重写（单工程 + 启动菜单）
# ----------------------------------------------------------------------------
# 对照仓库：https://github.com/webui-dev/python-webui/tree/main/examples
#
# 运行：本工程编译后由启动菜单窗口点选对应示例（每个示例新建自己的窗口）。
# 底层全部走 SLang.WebUI（对标 python-webui 的 webui 模块）：
#   - 窗口：SLang.WebUI.newWindow() -> SLang.WebUIWindow
#   - 显示：win.show(html) / win.show("index.html")（配合 setRootFolder 托管目录）
#   - 绑定：win.bindHandle("name", handler)（handler = 静态方法引用 / 实例方法 / 闭包）
#   - SL->JS：win.runScript(js) / win.script(js, timeout)
#   - JS->SL：事件回调内 SLang.WebUI.getArg* + return*
#   - 控制：SLang.WebUI.init() / wait() / clean() / exitAll()
#
# 9 个示例：minimal / hello_world / call_js_from_python / call_python_from_js /
#          send_raw_to_javascript / public_ui / react / serve_folder / text-editor
#
# 【性能诊断版】本版加了三类日志（卡顿排查用）：
#   1) 全局时间轴：每条日志带 [自启动累计 ms | unix 毫秒]
#   2) 窗口打开：newWindow() / show() 分别计时（show 含浏览器窗口就绪）
#   3) UI 操作：JS 点击时把 Date.now() 作为参数传回，SL 回调入口算
#      "点击->回调入口延迟"；handler 出口再报总耗时
# ============================================================================
class UiLog
{
    # 进程时间轴起点（首次使用时初始化）
    static Int64 s_t0 = 0

    static string ts()
    {
        if UiLog.s_t0 == 0
        {
            UiLog.s_t0 = OS.Timer.clock()
        }
        Int64 ms = OS.Timer.clock() - UiLog.s_t0
        ret "[+" + ms.toString() + " ms | unix=" + OS.Timer.now().toString() + "] "
    }

    static void log( string tag, string msg )
    {
        Console.println( UiLog.ts() + "[" + tag + "] " + msg )
    }

    static Int64 clock()
    {
        if UiLog.s_t0 == 0
        {
            UiLog.s_t0 = OS.Timer.clock()
        }
        ret OS.Timer.clock()
    }

    # 打印"JS 点击 -> SL 回调入口"延迟（JS 侧在 clickMsArg 槽位传了 Date.now()）
    static void clickLatency( string name, Int64 e, Int64 argIndex )
    {
        Int64 clickMs = SLang.WebUI.getArgInt( e, argIndex )
        if clickMs > 0
        {
            Int64 latency = OS.Timer.now() - clickMs
            UiLog.log( name, "点击 -> 回调入口延迟 = " + latency.toString() + " ms" )
        }
        else
        {
            UiLog.log( name, "回调触发（JS 侧未传点击时间）" )
        }
    }

    # 通用耗时报告：返回当前 clock，配对 spanEnd 使用
    static Int64 spanStart()
    {
        ret UiLog.clock()
    }

    static void spanEnd( string tag, string what, Int64 t )
    {
        UiLog.log( tag, what + " 耗时 " + ( UiLog.clock() - t ).toString() + " ms" )
    }
}

class WebUIExamples
{
    static void main()
    {
        UiLog.log( "main", "========== WebUIExamples 启动 ==========" )
        Int64 t = UiLog.spanStart()

        SLang.WebUI.init()
        UiLog.spanEnd( "main", "WebUI.init()", t )

        t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "main", "菜单 newWindow()", t )

        t = UiLog.spanStart()
        w.setSize( 580, 480 )
        w.setCenter()
        UiLog.spanEnd( "main", "setSize+setCenter", t )

        t = UiLog.spanStart()
        w.bindHandle( "run_minimal", WebUIExamples.onMinimal )
        w.bindHandle( "run_hello",   WebUIExamples.onHello )
        w.bindHandle( "run_calljs",  WebUIExamples.onCallJs )
        w.bindHandle( "run_callpy",  WebUIExamples.onCallPy )
        w.bindHandle( "run_raw",     WebUIExamples.onRaw )
        w.bindHandle( "run_public",  WebUIExamples.onPublic )
        w.bindHandle( "run_react",   WebUIExamples.onReact )
        w.bindHandle( "run_serve",   WebUIExamples.onServe )
        w.bindHandle( "run_editor",  WebUIExamples.onEditor )
        w.bindHandle( "exit_all",    WebUIExamples.onExitAll )
        UiLog.spanEnd( "main", "10 个 bindHandle", t )

        t = UiLog.spanStart()
        w.show( WebUIExamples.menuHtml() )
        UiLog.spanEnd( "main", "菜单 show()（含浏览器窗口就绪）", t )

        UiLog.log( "main", "进入 wait()，等待全部窗口关闭..." )
        SLang.WebUI.wait()
        UiLog.log( "main", "wait() 返回（全部窗口已关闭）" )

        t = UiLog.spanStart()
        SLang.WebUI.clean()
        UiLog.spanEnd( "main", "clean()", t )
        UiLog.log( "main", "========== 退出 ==========" )
    }

    # ── 菜单分发（每个 handler：入口报点击延迟，出口报总耗时）────
    static void onMinimal( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_minimal", e, 0 )
        Minimal.run()
        UiLog.spanEnd( "run_minimal", "handler 总计", t )
    }
    static void onHello( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_hello", e, 0 )
        HelloWorld.run()
        UiLog.spanEnd( "run_hello", "handler 总计", t )
    }
    static void onCallJs( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_calljs", e, 0 )
        CallJsFromPython.run()
        UiLog.spanEnd( "run_calljs", "handler 总计", t )
    }
    static void onCallPy( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_callpy", e, 0 )
        CallPythonFromJs.run()
        UiLog.spanEnd( "run_callpy", "handler 总计", t )
    }
    static void onRaw( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_raw", e, 0 )
        SendRawToJavascript.run()
        UiLog.spanEnd( "run_raw", "handler 总计", t )
    }
    static void onPublic( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_public", e, 0 )
        PublicUi.run()
        UiLog.spanEnd( "run_public", "handler 总计", t )
    }
    static void onReact( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_react", e, 0 )
        ReactExample.run()
        UiLog.spanEnd( "run_react", "handler 总计", t )
    }
    static void onServe( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_serve", e, 0 )
        ServeFolder.run()
        UiLog.spanEnd( "run_serve", "handler 总计", t )
    }
    static void onEditor( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "run_editor", e, 0 )
        TextEditor.run()
        UiLog.spanEnd( "run_editor", "handler 总计", t )
    }
    static void onExitAll( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "exit_all", e, 0 )
        UiLog.log( "exit_all", "调用 WebUI.exitAll()" )
        SLang.WebUI.exitAll()
        UiLog.spanEnd( "exit_all", "exitAll()", t )
    }

    static string menuHtml()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>"
        s = s + "body{font-family:'Segoe UI',Arial,sans-serif;background:#0f1424;color:#e6e9f5;margin:0;padding:24px}"
        s = s + "h1{font-size:20px;margin:0 0 4px}"
        s = s + "p.sub{color:#8a92b2;margin:0 0 18px;font-size:13px}"
        s = s + ".grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}"
        s = s + "button{padding:14px 10px;border-radius:8px;border:1px solid #2c3554;background:#1b2440;color:#e6e9f5;cursor:pointer;font-size:14px;transition:.15s}"
        s = s + "button:hover{background:#27325a}"
        s = s + ".exit{grid-column:1/-1;background:#3a2030;border-color:#5a2c44}"
        s = s + "</style></head><body>"
        s = s + "<h1>SLang WebUI Examples</h1>"
        s = s + "<p class=sub>python-webui/examples 的 SLang 重写 · 点击启动对应示例</p>"
        s = s + "<div class=grid>"
        # 每个按钮把 Date.now() 传回，SL 侧可算"点击->回调入口"延迟
        s = s + "<button onclick='t=Date.now();webui.call(\"run_minimal\", t)'>minimal</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_hello\", t)'>hello_world</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_calljs\", t)'>call_js_from_python</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_callpy\", t)'>call_python_from_js</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_raw\", t)'>send_raw_to_javascript</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_public\", t)'>public_ui</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_react\", t)'>react</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_serve\", t)'>serve_folder</button>"
        s = s + "<button onclick='t=Date.now();webui.call(\"run_editor\", t)'>text-editor</button>"
        s = s + "<button class=exit onclick='t=Date.now();webui.call(\"exit_all\", t)'>退出所有窗口 (Exit All)</button>"
        s = s + "</div></body></html>"
        ret s
    }
}

# ============================================================================
# 1) minimal  —— 最精简：一个窗口显示 "Hello World !"
#    python: MyWindow = webui.Window(); MyWindow.show('...'); webui.wait()
# ============================================================================
class Minimal
{
    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "minimal", "newWindow()", t )

        t = UiLog.spanStart()
        w.show( "<html><head><script src=\"/webui.js\"></script></head><body>Hello World !</body></html>" )
        UiLog.spanEnd( "minimal", "show()（含浏览器窗口就绪）", t )
    }
}

# ============================================================================
# 2) hello_world —— 密码登录 -> 仪表盘（对标官方 hello_world.py）
#    python: 绑定 CheckPassword / Exit；回调内 e.window.script 取密码、
#            e.window.show(dashboard) 切换页面；Exit -> webui.exit()
# ============================================================================
class HelloWorld
{
    static SLang.WebUIWindow s_win = null

    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "hello_world", "newWindow()", t )
        s_win = w
        w.setSize( 360, 280 )
        w.setCenter()
        t = UiLog.spanStart()
        w.bindHandle( "CheckPassword", HelloWorld.onCheckPassword )
        w.bindHandle( "Exit", HelloWorld.onExit )
        UiLog.spanEnd( "hello_world", "2 个 bindHandle", t )
        t = UiLog.spanStart()
        w.show( HelloWorld.loginHtml() )
        UiLog.spanEnd( "hello_world", "show()（含浏览器窗口就绪）", t )
    }

    static void onCheckPassword( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "hello_world:CheckPassword", e, 0 )
        # 对标 e.window.script("return document.getElementById('MyInput').value;")
        string pass = s_win.script( "return document.getElementById('MyInput').value;", 5 )
        UiLog.spanEnd( "hello_world", "script(取密码) 同步往返", t )
        t = UiLog.spanStart()
        if pass == "123456"
        {
            s_win.show( HelloWorld.dashboardHtml() )
            UiLog.spanEnd( "hello_world", "show(仪表盘)", t )
        }
        else
        {
            s_win.runScript( "document.getElementById('err').innerHTML = '[ ! ] Wrong password';" )
            UiLog.spanEnd( "hello_world", "runScript(报错提示)", t )
        }
    }

    static void onExit( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "hello_world:Exit", e, 0 )
        SLang.WebUI.exitAll()
        UiLog.spanEnd( "hello_world:Exit", "exitAll()", t )
    }

    static string loginHtml()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>WebUI Python Example</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>"
        s = s + "body{font-family:Arial,sans-serif;color:#fff;text-align:center;padding:40px;"
        s = s + "background:linear-gradient(to right,#507d91,#1c596f,#022737)}"
        s = s + "input{padding:8px;border-radius:3px;border:1px solid #ccc;outline:none}"
        s = s + "button{padding:8px 14px;border-radius:3px;border:1px solid #ccc;background:#3498db;color:#fff;cursor:pointer;font-size:14px}"
        s = s + "h3{color:#dbd552}</style></head><body>"
        s = s + "<h1>WebUI Python Example</h1>"
        s = s + "<input type=password id=MyInput placeholder=Password>"
        s = s + "<h3 id=err>&nbsp;</h3>"
        s = s + "<button id=CheckPassword onclick='t=Date.now();webui.call(\"CheckPassword\", t)'>Check Password</button>"
        s = s + " - <button id=Exit onclick='t=Date.now();webui.call(\"Exit\", t)'>Exit</button>"
        s = s + "</body></html>"
        ret s
    }

    static string dashboardHtml()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>Dashboard</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:Arial,sans-serif;background:#1c2e21;color:#cde;text-align:center;padding:40px}"
        s = s + "button{padding:8px 14px;border-radius:3px;border:1px solid #ccc;background:#2e7d32;color:#fff;cursor:pointer}</style></head><body>"
        s = s + "<h1>Welcome !</h1>"
        s = s + "<button id=Exit onclick='t=Date.now();webui.call(\"Exit\", t)'>Exit</button>"
        s = s + "</body></html>"
        ret s
    }
}

# ============================================================================
# 3) call_js_from_python —— SLang 侧主动调用 JS（对标 ui.run）
#    python: 绑定 call_js；回调内 ui.run("alert('...')")
# ============================================================================
class CallJsFromPython
{
    static SLang.WebUIWindow s_win = null

    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "call_js", "newWindow()", t )
        s_win = w
        w.setSize( 440, 220 )
        w.setCenter()
        w.bindHandle( "call_js", CallJsFromPython.onCallJs )
        t = UiLog.spanStart()
        w.show( CallJsFromPython.html() )
        UiLog.spanEnd( "call_js", "show()（含浏览器窗口就绪）", t )
    }

    static void onCallJs( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "call_js", e, 0 )
        # 对标 ui.run：SLang 侧执行 JavaScript
        s_win.runScript( "alert('Hello from SLang!');" )
        UiLog.spanEnd( "call_js", "runScript(alert)", t )
        t = UiLog.spanStart()
        s_win.runScript( "console.log('This is a log from SLang.');" )
        UiLog.spanEnd( "call_js", "runScript(console.log)", t )
    }

    static string html()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>Call JS from Python</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:Arial;background:#141824;color:#dde;padding:24px}"
        s = s + "button{padding:10px 14px;border-radius:6px;border:1px solid #3a4160;background:#26304d;color:#dde;cursor:pointer}</style></head><body>"
        s = s + "<h2>Call JS from SLang (Python)</h2>"
        s = s + "<button onclick='t=Date.now();webui.call(\"call_js\", t)'>Call JS from SLang</button>"
        s = s + "</body></html>"
        ret s
    }
}

# ============================================================================
# 4) call_python_from_js —— JS 调用 SLang 并取回返回值
#    python: 绑定 my_function；回调内 return "Hello " + name
# ============================================================================
class CallPythonFromJs
{
    static SLang.WebUIWindow s_win = null

    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "call_py", "newWindow()", t )
        s_win = w
        w.setSize( 440, 250 )
        w.setCenter()
        w.bindHandle( "my_function", CallPythonFromJs.onMyFunction )
        t = UiLog.spanStart()
        w.show( CallPythonFromJs.html() )
        UiLog.spanEnd( "call_py", "show()（含浏览器窗口就绪）", t )
    }

    static void onMyFunction( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "call_py:my_function", e, 1 )
        string name = SLang.WebUI.getArgString( e, 0 )
        UiLog.spanEnd( "call_py", "getArgString", t )
        t = UiLog.spanStart()
        SLang.WebUI.returnString( e, "Hello " + name + "!" )
        UiLog.spanEnd( "call_py", "returnString", t )
    }

    static string html()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>Call Python from JS</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:Arial;background:#141824;color:#dde;padding:24px}"
        s = s + "input{padding:6px}button{padding:8px 12px;border-radius:6px;border:1px solid #3a4160;background:#26304d;color:#dde;cursor:pointer}</style></head><body>"
        s = s + "<h2>Call SLang from JS</h2>"
        s = s + "<input id=name value='world'>"
        s = s + "<button onclick='callPy()'>Call SLang</button>"
        s = s + "<h3 id=out></h3>"
        s = s + "<script>"
        s = s + "async function callPy(){"
        s = s + "  const t0 = Date.now();"
        s = s + "  const r = await webui.call('my_function', document.getElementById('name').value, t0);"
        s = s + "  document.getElementById('out').innerHTML = r + ' (JS 往返 ' + (Date.now()-t0) + ' ms)';"
        s = s + "}"
        s = s + "</script></body></html>"
        ret s
    }
}

# ============================================================================
# 5) send_raw_to_javascript —— SLang 把原始数据推送到 JS
#    python: 绑定 send_raw；回调内 ui.run("receiveRaw('...')")
#    本实现自带内联 HTML（定义 receiveRaw），开箱即用；也可用 setRootFolder
#    托管外部 index.html（见 README）。
# ============================================================================
class SendRawToJavascript
{
    static SLang.WebUIWindow s_win = null

    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "send_raw", "newWindow()", t )
        s_win = w
        w.setSize( 480, 260 )
        w.setCenter()
        w.bindHandle( "send_raw", SendRawToJavascript.onSendRaw )
        t = UiLog.spanStart()
        w.show( SendRawToJavascript.html() )
        UiLog.spanEnd( "send_raw", "show()（含浏览器窗口就绪）", t )
    }

    static void onSendRaw( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "send_raw", e, 0 )
        # 对标 ui.run：把一段"原始"数据（字符串）注入 JS 调用
        string payload = "Hello from SLang (raw) @ " + "data-blob"
        s_win.runScript( "receiveRaw('" + payload + "');" )
        UiLog.spanEnd( "send_raw", "runScript(receiveRaw)", t )
    }

    static string html()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>Send Raw to JS</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:Arial;background:#101820;color:#cde;padding:24px}"
        s = s + "button{padding:8px 12px;border-radius:6px;border:1px solid #3a4160;background:#26304d;color:#cde;cursor:pointer}</style></head><body>"
        s = s + "<h2>Send Raw Data to JavaScript</h2>"
        s = s + "<button onclick='t=Date.now();webui.call(\"send_raw\", t)'>Send Raw</button>"
        s = s + "<pre id=out>等待数据...</pre>"
        s = s + "<script>"
        s = s + "function receiveRaw(data){ document.getElementById('out').innerHTML = data + ' (收到于 ' + Date.now() + ')'; }"
        s = s + "</script></body></html>"
        ret s
    }
}

# ============================================================================
# 6) public_ui —— 把窗口暴露到局域网（对标 webui_set_public）
#    python: webui.set_config / ui.set_public(True)
# ============================================================================
class PublicUi
{
    static SLang.WebUIWindow s_win = null

    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "public_ui", "newWindow()", t )
        s_win = w
        w.setSize( 460, 260 )
        w.setCenter()
        # 让 UI 可被外部网络访问
        # 【临时】10-29 版 SLangWebUI 库无 setPublic（10-31+ 库有但当前触发
        # bindHandle 崩溃回归），此处降级为日志提示，见排查结论
        t = UiLog.spanStart()
        Console.println( UiLog.ts() + "[public_ui] setPublic(true) 跳过（当前库版本不支持，功能回归后恢复）" )
        UiLog.spanEnd( "public_ui", "setPublic(true)占位", t )
        w.bindHandle( "my_function", PublicUi.onMyFunction )
        t = UiLog.spanStart()
        w.show( PublicUi.html() )
        UiLog.spanEnd( "public_ui", "show()（含浏览器窗口就绪）", t )
    }

    static void onMyFunction( Int64 e )
    {
        Int64 t = UiLog.spanStart()
        UiLog.clickLatency( "public_ui:my_function", e, 1 )
        string name = SLang.WebUI.getArgString( e, 0 )
        SLang.WebUI.returnString( e, "Hello " + name + " from a PUBLIC window!" )
        UiLog.spanEnd( "public_ui", "getArg+return", t )
    }

    static string html()
    {
        string s = "<!doctype html><html><head><meta charset=utf-8><title>Public UI</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:Arial;background:#1a1030;color:#ecd;padding:24px}"
        s = s + "input{padding:6px}button{padding:8px 12px;border-radius:6px;border:1px solid #5a2c44;background:#3a2030;color:#ecd;cursor:pointer}</style></head><body>"
        s = s + "<h2>Public UI (accessible from the network)</h2>"
        s = s + "<input id=name value='guest'>"
        s = s + "<button onclick='callPy()'>Call SLang</button>"
        s = s + "<h3 id=out></h3>"
        s = s + "<script>"
        s = s + "async function callPy(){"
        s = s + "  const t0 = Date.now();"
        s = s + "  const r = await webui.call('my_function', document.getElementById('name').value, t0);"
        s = s + "  document.getElementById('out').innerHTML = r + ' (JS 往返 ' + (Date.now()-t0) + ' ms)';"
        s = s + "}"
        s = s + "</script></body></html>"
        ret s
    }
}

# ============================================================================
# 7) react —— 托管 React 构建产物（需先 npm build，见 README）
#    python: 把 webui-react-example/build 设为根目录并 show("index.html")
# ============================================================================
class ReactExample
{
    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "react", "newWindow()", t )
        w.setSize( 900, 640 )
        w.setCenter()
        # 用户先把 React 工程构建到本目录下的 www_react/（npm run build），再启动。
        w.setRootFolder( "www_react" )
        t = UiLog.spanStart()
        w.show( "index.html" )
        UiLog.spanEnd( "react", "show(index.html)（含浏览器窗口就绪）", t )
    }
}

# ============================================================================
# 8) serve_folder —— 托管静态目录（index.html / second.html）
#    用户把静态文件放到本目录下的 www/（见 README 示例）。
# ============================================================================
class ServeFolder
{
    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "serve_folder", "newWindow()", t )
        w.setSize( 900, 640 )
        w.setCenter()
        w.setRootFolder( "www_serve" )
        t = UiLog.spanStart()
        w.show( "index.html" )
        UiLog.spanEnd( "serve_folder", "show(index.html)（含浏览器窗口就绪）", t )
    }
}

# ============================================================================
# 9) text-editor —— 托管文本编辑器静态资源（用户把编辑器文件放到 www/）
# ============================================================================
class TextEditor
{
    static void run()
    {
        Int64 t = UiLog.spanStart()
        SLang.WebUIWindow w = SLang.WebUI.newWindow()
        UiLog.spanEnd( "text-editor", "newWindow()", t )
        w.setSize( 900, 640 )
        w.setCenter()
        w.setRootFolder( "www_editor" )
        t = UiLog.spanStart()
        w.show( "index.html" )
        UiLog.spanEnd( "text-editor", "show(index.html)（含浏览器窗口就绪）", t )
    }
}
