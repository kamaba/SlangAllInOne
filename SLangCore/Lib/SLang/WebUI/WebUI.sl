import Core;
import Std;

# ============================================================================
# WebUI.sl —— SLang WebUI 模块 SL 层封装（模块名 SLangWebUI）
# ----------------------------------------------------------------------------
# 设计详见 doc/（00~07）。对照 SLang.Mysql 的门面风格。
#
# 用法（门面在 namespace SLang，实例类 SLang.WebUIWindow）：
#
#   import SLangWebUI;
#
#   class App
#   {
#       static void onGreet( Int64 e )
#       {
#           string who = SLang.WebUI.getArgString( e, 0 )
#           SLang.WebUI.returnString( e, "Hello, " + who + "!" )
#       }
#
#       static void main()
#       {
#           SLang.WebUI.init()
#           SLang.WebUIWindow win = SLang.WebUI.newWindow()
#           win.setSize( 480, 320 )
#           win.bindEvent( "greet", "onGreet" )    # 处理函数短名（static void onGreet(Int64)）
#           win.show( "<html>...<button onclick=\"greet('world')\">Go</button>...</html>" )
#           SLang.WebUI.wait()                     # 阻塞至所有窗口关闭
#           SLang.WebUI.clean()
#       }
#   }
#
# 处理函数约定：必须是 `static void X( Int64 eventPtr )`，方法名全局唯一
# （按 名字 + 参数个数 解析，见 FFI.StaticLibrary.createCallback）。
# ============================================================================

namespace SLang
{
    # ── 门面：模块控制 + 低层原生绑定（@DllStaticImport 直调 webui_*_sl）──
    public class WebUI
    {
        # ── 模块控制 ───────────────────────────────────────────────
        @DllStaticImport( "webui_lib", "webui_init_sl" )
        public static void init() {}

        @DllStaticImport( "webui_lib", "webui_wait_sl" )
        public static void wait() {}

        @DllStaticImport( "webui_lib", "webui_exit_sl" )
        public static void exitAll() {}

        @DllStaticImport( "webui_lib", "webui_clean_sl" )
        public static void clean() {}

        # ── 窗口生命周期（低层绑定，函数体即兜底）──────────────────
        @DllStaticImport( "webui_lib", "webui_new_window_sl" )
        public static Int64 libNewWindow() { ret 0 }

        @DllStaticImport( "webui_lib", "webui_show_sl" )
        public static bool libShow( Int64 w, string c ) { ret false }

        @DllStaticImport( "webui_lib", "webui_show_browser_sl" )
        public static bool libShowBrowser( Int64 w, string c, Int64 b ) { ret false }

        @DllStaticImport( "webui_lib", "webui_show_wv_sl" )
        public static bool libShowWv( Int64 w, string c ) { ret false }

        @DllStaticImport( "webui_lib", "webui_close_sl" )
        public static void libClose( Int64 w ) {}

        @DllStaticImport( "webui_lib", "webui_destroy_sl" )
        public static void libDestroy( Int64 w ) {}

        @DllStaticImport( "webui_lib", "webui_is_shown_sl" )
        public static bool libIsShown( Int64 w ) { ret false }

        # ── 事件绑定 ───────────────────────────────────────────────
        @DllStaticImport( "webui_lib", "webui_bind_sl" )
        public static Int64 libBind( Int64 w, string element, Int64 cb ) { ret 0 }

        # ── 函数值事件绑定（bindHandle）──────────────────────────
        # 低层入口：slot = SL 层 handler 表下标，dispatchCb = _dispatchHandle 节流点
        @DllStaticImport( "webui_lib", "webui_bind_handle_sl" )
        public static Int64 libBindHandle( Int64 w, string element, Int64 slot, Int64 dispatchCb ) { ret 0 }

        # handler 表 + 分发节流点（懒初始化，一次 createCallback 全局共用）
        # 注意：createCallback 的 method 参数必须传"完整 method id
        # （Module.NS.Class.Method_argc_T1_T2）"或"短方法名"二者之一；
        # "NS.Class.Method" 点路径三条查找路径均不命中（VM 日志报
        # FFI callback: method not found，事件静默丢弃）。短名按
        # 名字+参数个数全局匹配，_dispatchHandle 唯一，走短名最稳。
        static List<Function> _bindHandles = null
        static Int64 _dispatchCb = 0

        # 把任意函数值（静态方法引用 / 实例方法引用 / 匿名闭包）登记进 handler 表，
        # 原生层只保留 (bind_id -> slot) 映射；事件到达经 _dispatchHandle 取回调用。
        public static Int64 bindHandle( Int64 winHandle, string element, Function handler )
        {
            if ( _bindHandles == null )
            {
                _bindHandles = List<Function>()
            }

            if ( _dispatchCb == 0 )
            {
                _dispatchCb = FFI.StaticLibrary.createCallback( "_dispatchHandle", "i64,i64->void" )
            }
            _bindHandles.add( handler )
            Int64 slot = ( _bindHandles.length - 1 ) as Int64
            ret libBindHandle( winHandle, element, slot, _dispatchCb )
        }

        # 原生事件重入点：按槽位取回用户 handler 调用。
        # handler 形态兼容：static void X() / 实例 void t() / function(){}
        # （0 参 handler 由 VM 调用对齐丢弃多余实参）；带参 handler 收到
        # e（webui_event_t*，配合 getArgString/returnString 等使用）。
        public static void _dispatchHandle( Int64 slot, Int64 e )
        {
            # 下标内联 as 转型（_bindHandles[slot as Int32]）触发 Front 解析断言，
            # 拆两行规避（2026-10-29 实测）
            Int32 idx = slot as Int32
            Function f = _bindHandles[idx]
            f( e )
        }

        # ── 窗口属性 ───────────────────────────────────────────────
        @DllStaticImport( "webui_lib", "webui_set_size_sl" )
        public static void libSetSize( Int64 w, int wd, int ht ) {}
        @DllStaticImport( "webui_lib", "webui_set_minimum_size_sl" )
        public static void libSetMinimumSize( Int64 w, int wd, int ht ) {}
        @DllStaticImport( "webui_lib", "webui_set_position_sl" )
        public static void libSetPosition( Int64 w, int x, int y ) {}
        @DllStaticImport( "webui_lib", "webui_set_center_sl" )
        public static void libSetCenter( Int64 w ) {}
        @DllStaticImport( "webui_lib", "webui_set_kiosk_sl" )
        public static void libSetKiosk( Int64 w, bool on ) {}
        @DllStaticImport( "webui_lib", "webui_set_hide_sl" )
        public static void libSetHide( Int64 w, bool on ) {}
        @DllStaticImport( "webui_lib", "webui_set_resizable_sl" )
        public static void libSetResizable( Int64 w, bool on ) {}
        @DllStaticImport( "webui_lib", "webui_focus_sl" )
        public static void libFocus( Int64 w ) {}
        @DllStaticImport( "webui_lib", "webui_minimize_sl" )
        public static void libMinimize( Int64 w ) {}
        @DllStaticImport( "webui_lib", "webui_maximize_sl" )
        public static void libMaximize( Int64 w ) {}

        # ── JS 执行 ────────────────────────────────────────────────
        @DllStaticImport( "webui_lib", "webui_run_sl" )
        public static void libRun( Int64 w, string js ) {}
        @DllStaticImport( "webui_lib", "webui_script_sl" )
        public static string libScript( Int64 w, string js, Int64 timeout ) { ret "" }

        # ── 服务器 / 文件 ──────────────────────────────────────────
        @DllStaticImport( "webui_lib", "webui_set_root_folder_sl" )
        public static bool libSetRootFolder( Int64 w, string path ) { ret false }
        @DllStaticImport( "webui_lib", "webui_start_server_sl" )
        public static string libStartServer( Int64 w, string content ) { ret "" }

        # ── 事件参数读取（回调内调用，e = webui_event_t*）──────────
        @DllStaticImport( "webui_lib", "webui_get_count_sl" )
        public static Int64 getArgCount( Int64 e ) { ret 0 }
        @DllStaticImport( "webui_lib", "webui_get_int_at_sl" )
        public static Int64 getArgInt( Int64 e, Int64 i ) { ret 0 }
        @DllStaticImport( "webui_lib", "webui_get_float_at_sl" )
        public static double getArgFloat( Int64 e, Int64 i ) { ret 0.0 }
        @DllStaticImport( "webui_lib", "webui_get_string_at_sl" )
        public static string getArgString( Int64 e, Int64 i ) { ret "" }
        @DllStaticImport( "webui_lib", "webui_get_bool_at_sl" )
        public static bool getArgBool( Int64 e, Int64 i ) { ret false }

        # ── 事件返回值（回调内调用，回传 JS）──────────────────────
        @DllStaticImport( "webui_lib", "webui_return_int_sl" )
        public static void returnInt( Int64 e, Int64 n ) {}
        @DllStaticImport( "webui_lib", "webui_return_float_sl" )
        public static void returnFloat( Int64 e, double f ) {}
        @DllStaticImport( "webui_lib", "webui_return_string_sl" )
        public static void returnString( Int64 e, string s ) {}
        @DllStaticImport( "webui_lib", "webui_return_bool_sl" )
        public static void returnBool( Int64 e, bool b ) {}

        # ── 窗口工厂 ───────────────────────────────────────────────
        # 带命名空间的 new 表达式（new SLang.WebUIWindow()）解析受限，统一走工厂创建。
        public static WebUIWindow newWindow()
        {
            ret WebUIWindow()
        }

        # ── 回调注册辅助 ───────────────────────────────────────────
        # 把 SLang 静态方法（按名字 + 参数个数解析）转成 createCallback 节流点地址，
        # 交给 libBind 写入原生层 bind_id -> 节流点 映射表。
        public static Int64 makeCallback( string methodName )
        {
            ret FFI.StaticLibrary.createCallback( methodName, "ptr->void" )
        }
    }

    # ── 窗口实例类 ─────────────────────────────────────────────────
    public class WebUIWindow
    {
        Int64 _handle = 0

        _init_()
        {
            this._handle = SLang.WebUI.libNewWindow()
        }

        get Int64 handle() { ret this._handle }

        # ── 显示内容 ───────────────────────────────────────────────
        public bool show( string content ) { ret SLang.WebUI.libShow( this._handle, content ) }
        public bool showBrowser( string content, Int64 browser ) { ret SLang.WebUI.libShowBrowser( this._handle, content, browser ) }
        public bool showWv( string content ) { ret SLang.WebUI.libShowWv( this._handle, content ) }

        # ── 事件绑定 ───────────────────────────────────────────────
        # 绑定 HTML 元素/JS 函数到任意 SLang 函数值，支持三种形态：
        #   win.bindHandle( "greet", onGreet )                  # static void onGreet(...) 引用
        #   win.bindHandle( "greet", ca.onEvent )               # 实例方法引用（保留 receiver）
        #   win.bindHandle( "greet", function(){ ... } )        # 匿名闭包
        # handler 可带参（Int64 e = webui_event_t*）或无参（多余实参由 VM 对齐丢弃）。
        # 返回 bind_id（>0 成功）。
        public Int64 bindHandle( string element, Function handler )
        {
            ret SLang.WebUI.bindHandle( this._handle, element, handler )
        }

        # 旧按名绑定（static void X(Int64)，方法名全局唯一）。保留兼容，
        # 新代码建议用 bindHandle（函数值形态）。
        public Int64 bindEvent( string element, string methodName )
        {
            ret SLang.WebUI.libBind( this._handle, element, SLang.WebUI.makeCallback( methodName ) )
        }

        # ── 窗口属性 ───────────────────────────────────────────────
        public void setSize( int w, int h ) { SLang.WebUI.libSetSize( this._handle, w, h ) }
        public void setMinimumSize( int w, int h ) { SLang.WebUI.libSetMinimumSize( this._handle, w, h ) }
        public void setPosition( int x, int y ) { SLang.WebUI.libSetPosition( this._handle, x, y ) }
        public void setCenter() { SLang.WebUI.libSetCenter( this._handle ) }
        public void setKiosk( bool on ) { SLang.WebUI.libSetKiosk( this._handle, on ) }
        public void setHide( bool on ) { SLang.WebUI.libSetHide( this._handle, on ) }
        public void setResizable( bool on ) { SLang.WebUI.libSetResizable( this._handle, on ) }
        public void focus() { SLang.WebUI.libFocus( this._handle ) }
        public void minimize() { SLang.WebUI.libMinimize( this._handle ) }
        public void maximize() { SLang.WebUI.libMaximize( this._handle ) }

        # ── JS 执行 ────────────────────────────────────────────────
        public void runScript( string js ) { SLang.WebUI.libRun( this._handle, js ) }
        # script(js, timeoutSec) -> string（取回 JS 返回值）
        public string script( string js, Int64 timeout ) { ret SLang.WebUI.libScript( this._handle, js, timeout ) }

        # ── 服务器 / 文件 ──────────────────────────────────────────
        public bool setRootFolder( string path ) { ret SLang.WebUI.libSetRootFolder( this._handle, path ) }
        public string startServer( string content ) { ret SLang.WebUI.libStartServer( this._handle, content ) }

        # ── 关闭 ───────────────────────────────────────────────────
        public void close() { SLang.WebUI.libClose( this._handle ) }
        public void destroy() { SLang.WebUI.libDestroy( this._handle ) }
        get bool isShown() { ret SLang.WebUI.libIsShown( this._handle ) }
    }
}
