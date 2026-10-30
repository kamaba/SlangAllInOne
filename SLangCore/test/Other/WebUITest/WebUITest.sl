import Core;
import Std;
import SLangWebUI;

# ============================================================================
# WebUITest —— SLang WebUI 模块端到端测试套件
# ----------------------------------------------------------------------------
# 用例来源：webui-dev/webui v2.5.0-beta.4 官方 examples/C（MIT）
#   - call_c_from_js ：多类型参数读取（string/int/float/bool/个数）+ 返回值回传
#   - call_js_from_c ：webui_script 返回值往返 / webui_run 驱动 JS / 事件内 exit
#   - stress_test    ：echo 往返压测、大参数/大响应、批量绑定、多窗口
#
# 运行：package\win32-release\bin\csimple_lang.exe run
#       package\win32-release\WebUITest\WebUITest.module.slb
# （staged 目录需 webui_lib.dll：lib\windows\ 与 SLangWebUI\ 各一份）
#
# 结构：全自动，无需人工点击。页面连接后：
#   Phase A（主线程，show 返回后）C→JS 方向：
#     A1/A2  句柄与 bind_id / A3 show 连接 / A4-A7 script 四种返回
#     A8     run x1000 计数器往返 / A9 60KB 大响应 / A10 DOM 往返
#     A11    第二窗口 show
#   Phase B（事件线程，主线程阻塞在 wait 期间）JS→SL 方向：
#     B1  greet 静态带参 + returnString
#     B2  zero/tick/tick1/closure/oldstyle 五种 handler 形态 + query_state 汇总
#     B3-B7 双字符串 / 三整数 / 浮点 / 双布尔 / 参数个数
#     B8  echo x100 往返（returnInt）
#     B9  50KB 大参数（getArgString + length）
#     B10 40 个批量绑定全命中
#     B11 第二窗口 ping/pong
#     B12 JS 用例计数完整性校验 → 汇总 RESULT: PASS/FAIL → exitAll
# ============================================================================

class WebUITest
{
    # ── 结果统计（Phase A 主线程 + Phase B 事件线程共同累加）──
    static Int64 g_pass = 0
    static Int64 g_fail = 0
    static Int64 g_jsChecks = 0
    static Int64 g_suiteDone = 0

    # ── 无返回值 handler 的执行计数（B2 经 query_state 汇总校验）──
    static Int64 g_zeroCount = 0
    static Int64 g_tickCount = 0
    static Int64 g_tick1Count = 0
    static Int64 g_closureCount = 0
    static Int64 g_oldCount = 0
    static Int64 g_bindHits = 0

    static void expect( bool ok, string name )
    {
        if ok
        {
            g_pass = g_pass + 1
            Console.println( "  [PASS] " + name )
        }
        else
        {
            g_fail = g_fail + 1
            Console.println( "  [FAIL] " + name )
        }
    }

    # ── Phase B handlers ──────────────────────────────────────────

    # 静态带参 + returnString（call_c_from_js: my_function_with_response）
    static void onGreet( Int64 e )
    {
        string who = SLang.WebUI.getArgString( e, 0 )
        Console.println( "  [EVT] onGreet: who=" + who )
        SLang.WebUI.returnString( e, "Hello, " + who + "!" )
    }

    # 静态无参（VM 调用对齐丢弃多余实参）
    static void onZero()
    {
        g_zeroCount = g_zeroCount + 1
        Console.println( "  [EVT] onZero(静态无参) z=" + g_zeroCount )
    }

    # 实例方法 / 匿名闭包 / 旧接口的执行计数（Hooks 与闭包经此类前缀回写）
    static Int64 bumpTick() { g_tickCount = g_tickCount + 1; ret g_tickCount }
    static Int64 bumpTick1() { g_tick1Count = g_tick1Count + 1; ret g_tick1Count }
    static void bumpClosure() { g_closureCount = g_closureCount + 1 }

    # 五种 handler 形态的执行状态汇总（stress_test: report 模式）
    static void onQueryState( Int64 e )
    {
        # 注意：SLang 语句按行解析，续行以 + 开头会被丢弃，必须逐行完整累加
        string s = "z=" + g_zeroCount + ",t=" + g_tickCount + ",t1=" + g_tick1Count
        s = s + ",c=" + g_closureCount + ",ob=" + g_oldCount
        SLang.WebUI.returnString( e, s )
    }

    # call_c_from_js: my_function_string —— 双字符串参数
    static void onArgsStrings( Int64 e )
    {
        string s1 = SLang.WebUI.getArgString( e, 0 )
        string s2 = SLang.WebUI.getArgString( e, 1 )
        SLang.WebUI.returnString( e, s1 + "-" + s2 )
    }

    # call_c_from_js: my_function_integer —— 三整数 + 求和回传
    static void onArgsInts( Int64 e )
    {
        Int64 a = SLang.WebUI.getArgInt( e, 0 )
        Int64 b = SLang.WebUI.getArgInt( e, 1 )
        Int64 c = SLang.WebUI.getArgInt( e, 2 )
        SLang.WebUI.returnInt( e, a + b + c )
    }

    # call_c_from_js: 浮点参数（webui_get_float_at）+ returnFloat
    static void onArgsFloat( Int64 e )
    {
        double f = SLang.WebUI.getArgFloat( e, 0 )
        SLang.WebUI.returnFloat( e, f * 2.0 )
    }

    # call_c_from_js: my_function_boolean —— 双布尔参数
    static void onArgsBools( Int64 e )
    {
        bool b1 = SLang.WebUI.getArgBool( e, 0 )
        bool b2 = SLang.WebUI.getArgBool( e, 1 )
        bool ok = false
        if b1
        {
            if b2
            {
                ok = false
            }
            else
            {
                ok = true
            }
        }
        SLang.WebUI.returnBool( e, ok )
    }

    # call_c_from_js: webui_get_count —— 参数个数
    static void onArgsCount( Int64 e )
    {
        Int64 n = SLang.WebUI.getArgCount( e )
        SLang.WebUI.returnInt( e, n )
    }

    # stress_test: cb_echo —— echo 往返压测
    static void onEcho( Int64 e )
    {
        Int64 v = SLang.WebUI.getArgInt( e, 0 )
        SLang.WebUI.returnInt( e, v * 2 )
    }

    # stress_test: cb_big_arg —— 大参数校验（长度回传）
    static void onBigArg( Int64 e )
    {
        string s = SLang.WebUI.getArgString( e, 0 )
        int len = s.length()
        Console.println( "  [EVT] onBigArg: len=" + len )
        SLang.WebUI.returnString( e, "" + len )
    }

    # stress_test: stage_bindings —— 同一 handler 绑 40 个名字
    static void onManyBind( Int64 e )
    {
        g_bindHits = g_bindHits + 1
    }

    static void onBindHits( Int64 e )
    {
        SLang.WebUI.returnInt( e, g_bindHits )
    }

    # JS 侧校验结果回传：js_check(name, ok)
    static void onJsCheck( Int64 e )
    {
        string name = SLang.WebUI.getArgString( e, 0 )
        Int64 ok = SLang.WebUI.getArgInt( e, 1 )
        g_jsChecks = g_jsChecks + 1
        expect( ok == 1, name )
    }

    # 第二窗口校验回传：走独立绑定，不进 g_jsChecks（B12 只核对主窗口计数）
    static void onW2Check( Int64 e )
    {
        string name = SLang.WebUI.getArgString( e, 0 )
        Int64 ok = SLang.WebUI.getArgInt( e, 1 )
        expect( ok == 1, name )
    }

    # 旧按名绑定接口（bindEvent → createCallback 短名解析）
    static void onOldStyle( Int64 e )
    {
        g_oldCount = g_oldCount + 1
        SLang.WebUI.returnString( e, "old-ok" )
    }

    # 第二窗口 ping/pong
    static void onW2Ping( Int64 e )
    {
        SLang.WebUI.returnString( e, "pong" )
    }

    # 套件收尾：完整性校验 + 汇总 + exitAll（call_js_from_c: my_function_exit）
    static void onSuiteDone( Int64 e )
    {
        Int64 reported = SLang.WebUI.getArgInt( e, 0 )
        g_suiteDone = 1
        expect( reported == g_jsChecks, "B12 JS 用例计数一致 (js报=" + reported + " SL收=" + g_jsChecks + ")" )
        Console.println( "" )
        Console.println( "=== pass=" + g_pass + " fail=" + g_fail + " ===" )
        if g_fail == 0
        {
            Console.println( "RESULT: PASS" )
        }
        else
        {
            Console.println( "RESULT: FAIL" )
        }
        #SLang.WebUI.exitAll()
    }

    # ── 页面 ──────────────────────────────────────────────────────
    # 注意：嵌入式 HTML 必须自带 <script src=/webui.js>（2.5 不注入）；
    # startSuite/startW2 由 SL 在 Phase A 结束后经 runScript 触发，
    # 内部先延时，确保主线程已进入 wait() 再发起 JS→SL 调用。
    static string buildHtml()
    {
        string s = "<html><head><meta charset=utf-8><title>SLang WebUI Test Suite</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>"
        s = s + "body{font-family:sans-serif;background:#141824;color:#dde;padding:18px}"
        s = s + "h2{margin:0 0 6px;font-size:18px}"
        s = s + "#out{color:#8a92b2;font-size:13px;line-height:1.6}"
        s = s + "button{padding:6px 10px;margin:3px;border-radius:3px;border:1px solid #3a4160;"
        s = s + "background:#26304d;color:#dde;cursor:pointer}"
        s = s + "</style></head><body>"
        s = s + "<h2>SLang WebUI 自动化测试</h2>"
        s = s + "<div id=out>Phase A (SL→JS) 运行中...</div>"
        s = s + "<hr><b>手动区（bindHandle 三形态）</b><br>"
        s = s + "<button onclick=greet(&quot;SLang&quot;)>Greet</button> "
        s = s + "<button onclick=zero()>Zero</button> "
        s = s + "<button onclick=tick()>Tick</button> "
        s = s + "<button onclick=tick1()>Tick1</button>"
        s = s + "<script>"
        s = s + "let count = 0;"
        s = s + "let jsChecks = 0;"
        s = s + "function out(s2){ document.getElementById('out').innerHTML += s2 + '<br>'; }"
        s = s + "function chk(ok, name){"
        s = s + "  jsChecks++;"
        s = s + "  out((ok ? '[JS-PASS] ' : '[JS-FAIL] ') + name);"
        s = s + "  webui.call('js_check', name, ok ? 1 : 0);"
        s = s + "}"
        s = s + "async function startSuite(){"
        s = s + "  try {"
        s = s + "    await new Promise(r => setTimeout(r, 300));"
        s = s + "    out('--- Phase B (JS→SL) ---');"
        s = s + "    try { const r = await greet('SLang'); chk(r === 'Hello, SLang!', 'B1 greet 静态带参+returnString'); }"
        s = s + "    catch(e) { chk(false, 'B1 异常: ' + e.message); }"
        s = s + "    try { await zero(); await tick(); await tick1(); await closure_test(); await oldstyle(); }"
        s = s + "    catch(e) { chk(false, 'B2 五形态调用异常: ' + e.message); }"
        s = s + "    try { const t = await query_state(); chk(t === 'z=1,t=1,t1=1,c=1,ob=1', 'B2 handler 状态汇总 query_state'); }"
        s = s + "    catch(e) { chk(false, 'B2 状态异常: ' + e.message); }"
        s = s + "    try { const r = await args_strings('Hello', 'World'); chk(r === 'Hello-World', 'B3 双字符串参数'); }"
        s = s + "    catch(e) { chk(false, 'B3 异常: ' + e.message); }"
        s = s + "    try { const r = await args_ints(10, 20, 30); chk(r === '60', 'B4 三整数参数求和'); }"
        s = s + "    catch(e) { chk(false, 'B4 异常: ' + e.message); }"
        s = s + "    try { const r = await args_float(12.5); chk(Number(r) === 25, 'B5 浮点参数 x2 回传'); }"
        s = s + "    catch(e) { chk(false, 'B5 异常: ' + e.message); }"
        s = s + "    try { const r = await args_bools(true, false); chk(r === '1', 'B6 双布尔参数'); }"
        s = s + "    catch(e) { chk(false, 'B6 异常: ' + e.message); }"
        s = s + "    try { const r = await args_count(1, 2, 3, 4, 5); chk(r === '5', 'B7 参数个数计数'); }"
        s = s + "    catch(e) { chk(false, 'B7 异常: ' + e.message); }"
        s = s + "    try {"
        s = s + "      let bad = 0;"
        s = s + "      for (let i = 0; i < 100; i++) { const r = await echo(i); if (Number(r) !== i * 2) bad++; }"
        s = s + "      chk(bad === 0, 'B8 echo 往返 x100');"
        s = s + "    } catch(e) { chk(false, 'B8 异常: ' + e.message); }"
        s = s + "    try { const r = await big_arg('B'.repeat(50000)); chk(r === '50000', 'B9 50KB 大参数'); }"
        s = s + "    catch(e) { chk(false, 'B9 异常: ' + e.message); }"
        s = s + "    try {"
        s = s + "      for (let i = 0; i < 40; i++) { await webui.call('fn' + i, i); }"
        s = s + "      const r = await bind_hits();"
        s = s + "      chk(r === '40', 'B10 40 个批量绑定全命中');"
        s = s + "    } catch(e) { chk(false, 'B10 异常: ' + e.message); }"
        s = s + "    out('--- 套件完成 ---');"
        s = s + "  } finally {"
        s = s + "    await new Promise(r => setTimeout(r, 500));"
        s = s + "    webui.call('suite_done', jsChecks);"
        s = s + "  }"
        s = s + "}"
        s = s + "</script></body></html>"
        ret s
    }

    static string buildHtml2()
    {
        string s = "<html><head><meta charset=utf-8><title>WebUITest W2</title>"
        s = s + "<script src=/webui.js></script>"
        s = s + "<style>body{font-family:sans-serif;background:#1c2e21;color:#cde;padding:16px}</style>"
        s = s + "</head><body><h2>第二窗口</h2>"
        s = s + "<div id=out>等待启动...</div>"
        s = s + "<script>"
        s = s + "async function startW2(){"
        s = s + "  await new Promise(r => setTimeout(r, 200));"
        s = s + "  try {"
        s = s + "    const r = await w2_ping();"
        s = s + "    webui.call('w2_check', 'B11 第二窗口 ping/pong', r === 'pong' ? 1 : 0);"
        s = s + "    document.getElementById('out').innerHTML = 'w2_ping() = ' + r;"
        s = s + "  } catch(e) {"
        s = s + "    webui.call('w2_check', 'B11 第二窗口异常: ' + e.message, 0);"
        s = s + "  }"
        s = s + "}"
        s = s + "</script></body></html>"
        ret s
    }

    # ── 主流程 ────────────────────────────────────────────────────
    static void main()
    {
        Console.println( "=== WebUITest 套件 (bindHandle/bindEvent + script/run + 多窗口) ===" )
        Console.println( "[1] init..." )
        SLang.WebUI.init()

        Console.println( "[2] newWindow + 绑定..." )
        SLang.WebUIWindow win = SLang.WebUI.newWindow()
        win.setSize( 760, 640 )
        win.setCenter()
        Int64 bGreet = win.bindHandle( "greet", WebUITest.onGreet )
        Int64 bZero = win.bindHandle( "zero", WebUITest.onZero )
        Hooks hooks = Hooks()
        Int64 bTick = win.bindHandle( "tick", hooks.onTick )
        Int64 bTick1 = win.bindHandle( "tick1", hooks.onTick1 )
        Int64 bClosure = win.bindHandle( "closure_test", function(){ WebUITest.bumpClosure() } )
        Int64 bOld = win.bindEvent( "oldstyle", "onOldStyle" )
        Int64 bQuery = win.bindHandle( "query_state", WebUITest.onQueryState )
        Int64 bStr = win.bindHandle( "args_strings", WebUITest.onArgsStrings )
        Int64 bInt = win.bindHandle( "args_ints", WebUITest.onArgsInts )
        Int64 bFlt = win.bindHandle( "args_float", WebUITest.onArgsFloat )
        Int64 bBool = win.bindHandle( "args_bools", WebUITest.onArgsBools )
        Int64 bCnt = win.bindHandle( "args_count", WebUITest.onArgsCount )
        Int64 bEcho = win.bindHandle( "echo", WebUITest.onEcho )
        Int64 bBig = win.bindHandle( "big_arg", WebUITest.onBigArg )
        Int64 bHits = win.bindHandle( "bind_hits", WebUITest.onBindHits )
        Int64 bJsChk = win.bindHandle( "js_check", WebUITest.onJsCheck )
        Int64 bDone = win.bindHandle( "suite_done", WebUITest.onSuiteDone )
        # stress_test: stage_bindings —— 同一 handler 绑 40 个名字
        for i = 0, i < 40, i++
        {
            win.bindHandle( "fn" + i, WebUITest.onManyBind )
        }
        Console.println( "    bind_id: greet=" + bGreet + " old=" + bOld + " done=" + bDone )

        expect( win.handle > 0, "A1 窗口句柄 > 0" )
        expect( bGreet > 0 && bZero > 0 && bTick > 0 && bTick1 > 0, "A2a bindHandle 三形态 bind_id > 0" )
        expect( bClosure > 0 && bOld > 0 && bQuery > 0, "A2b 闭包/旧接口/查询 bind_id > 0" )
        expect( bStr > 0 && bInt > 0 && bFlt > 0 && bBool > 0 && bCnt > 0, "A2c 参数类型绑定 bind_id > 0" )
        expect( bEcho > 0 && bBig > 0 && bHits > 0 && bJsChk > 0 && bDone > 0, "A2d 压测/汇报绑定 bind_id > 0" )

        Console.println( "[3] show + Phase A (SL→JS)..." )
        bool shown = win.show( buildHtml() )
        expect( shown, "A3 show() 浏览器连接成功" )

        if shown
        {
            string r1 = win.script( "return 'hello';", 10 )
            expect( r1 == "hello", "A4 script 字符串返回" )

            string r2 = win.script( "return 40 + 2;", 10 )
            expect( r2 == "42", "A5 script 整数表达式返回" )

            string r3 = win.script( "return true;", 10 )
            expect( r3 == "true", "A6 script 布尔返回" )

            string r4 = win.script( "return no_such_variable_x.y;", 5 )
            expect( r4 == "", "A7 script JS 错误返回空" )

            # stress_test: stage_c_to_js —— 1000 次 run + script 校验
            for i = 0, i < 1000, i++
            {
                win.runScript( "count++;" )
            }
            string r5 = win.script( "return count;", 15 )
            expect( r5 == "1000", "A8 run x1000 计数器往返" )

            string r6 = win.script( "return 'A'.repeat(60000);", 20 )
            expect( r6.length() == 60000 && r6.front( 1 ) == "A", "A9 script 60KB 大响应" )

            win.runScript( "document.title = 'SLang-OK';" )
            string r7 = win.script( "return document.title;", 10 )
            expect( r7 == "SLang-OK", "A10 run+script DOM 往返" )

            # stress_test: stage_multi_window —— 第二窗口
            Console.println( "[4] 第二窗口..." )
            SLang.WebUIWindow win2 = SLang.WebUI.newWindow()
            win2.setSize( 420, 300 )
            win2.setPosition( 200, 200 )
            win2.bindHandle( "w2_ping", WebUITest.onW2Ping )
            win2.bindHandle( "w2_check", WebUITest.onW2Check )
            bool shown2 = win2.show( buildHtml2() )
            expect( shown2, "A11 第二窗口 show 成功" )

            Console.println( "[5] 启动 JS 套件并 wait..." )
            win2.runScript( "startW2();" )
            win.runScript( "startSuite();" )
        }

        SLang.WebUI.wait()

        if g_suiteDone == 0
        {
            Console.println( "RESULT: INCOMPLETE (套件未完成或窗口提前关闭)" )
        }

        Console.println( "[6] clean" )
        SLang.WebUI.clean()
        Console.println( "=== WebUITest done ===" )
    }
}

# ── 实例方法 handler 载体（bindHandle 实例方法引用形态）────────────
class Hooks
{
    Int64 tag = 7

    void onTick()
    {
        Console.println( "  [EVT] onTick(实例无参) tag=" + this.tag + " t=" + WebUITest.bumpTick() )
    }

    void onTick1( Int64 e )
    {
        Console.println( "  [EVT] onTick1(实例带参) tag=" + this.tag + " t1=" + WebUITest.bumpTick1() )
    }
}
