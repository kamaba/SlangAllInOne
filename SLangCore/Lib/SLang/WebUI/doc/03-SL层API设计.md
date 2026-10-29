# SL 层 API 设计（`SLang.WebUI`）

> 本文定义 SLang 程序员**直接调用**的 API 形态（实现于 `WebUI.sl`），对标
> `SLang.Mysql` 的门面风格。底层原生绑定与回调桥见 `02` / `04`。

---

## 1. 命名空间与模块

- 命名空间：`SLang.WebUI`（与 `SLang.Mysql` 平铺在 `SLang` 下一致）。
- 模块名（export）：`SLangWebUI` → 产物 `out/export/SLangWebUI/`。
- 引入：`import SLangWebUI;`（或 `import SLang;` 后 `SLang.WebUI.*`）。

---

## 2. 核心类：`WebUI.Window`

窗口是 SLang 侧的主要对象，内部持 `Int64 _handle`（webui 窗口号 `size_t`）。

```sl
namespace SLang
{
    public class WebUI.Window
    {
        Int64 _handle = 0

        # 新建窗口（webui_new_window）
        _init_()
        {
            this._handle = WebUI.libNewWindow()
        }

        get Int64 handle() { ret this._handle }

        # ── 显示内容 ──────────────────────────────────────
        # show(htmlOrFileOrUrl) —— 注入 HTML 字符串 / 本地文件 / URL
        public bool show( string content )
        { ret WebUI.libShow( this._handle, content ) }

        public bool showBrowser( string content, int browser )
        { ret WebUI.libShowBrowser( this._handle, content, browser ) }

        # ── 事件绑定 ──────────────────────────────────────
        # bindHandle(element, Function) —— 主推：任意函数值（静态方法引用 /
        #   实例方法引用 / 匿名闭包）；handler 带参收 Int64 e（webui_event_t*），
        #   无参合法（VM 按声明参数槽对齐，多余实参自动丢弃）。返回 bind_id
        public Int64 bindHandle( string element, Function handler )
        { ret WebUI.bindHandle( this._handle, element, handler ) }

        # 兼容保留：bindEvent(element, methodName) —— 按方法短名绑定

        # ── 窗口属性 ──────────────────────────────────────
        public void setSize( int w, int h ) { WebUI.libSetSize( this._handle, w, h ) }
        public void setPosition( int x, int y ) { WebUI.libSetPosition( this._handle, x, y ) }
        public void setCenter() { WebUI.libSetCenter( this._handle ) }
        public void setKiosk( bool on ) { WebUI.libSetKiosk( this._handle, on ) }
        public void setHide( bool on ) { WebUI.libSetHide( this._handle, on ) }
        public void setResizable( bool on ) { WebUI.libSetResizable( this._handle, on ) }

        # ── JS 执行 ───────────────────────────────────────
        public void runScript( string js ) { WebUI.libRun( this._handle, js ) }
        # script(js, timeoutSec) -> string（取回 JS 返回值）
        public string script( string js, int timeoutSec ) { ret WebUI.libScript( this._handle, js, timeoutSec ) }

        # ── 关闭 ──────────────────────────────────────────
        public void close() { WebUI.libClose( this._handle ) }
        public void destroy() { WebUI.libDestroy( this._handle ) }
        get bool isShown() { ret WebUI.libIsShown( this._handle ) }
    }
}
```

---

## 3. 静态工具类：`WebUI`（事件读取 / 返回 / 全局控制）

```sl
namespace SLang
{
    public class WebUI
    {
        # ── 模块控制 ──────────────────────────────────────
        public static void init()            # webui_set_config(ui_event_blocking,true) 等
        public static void wait()            # webui_wait()
        public static void exitAll()         # webui_exit()
        public static void clean()           # webui_clean()

        # ── 低层原生绑定（@DllStaticImport，函数体=兜底）────
        @DllStaticImport( "webui_lib", "webui_new_window_sl" )
        public static Int64 libNewWindow() { ret 0 }

        @DllStaticImport( "webui_lib", "webui_show_sl" )
        public static bool libShow( Int64 w, string c ) { ret false }

        @DllStaticImport( "webui_lib", "webui_bind_sl" )
        public static Int64 libBind( Int64 w, string el, Int64 cb ) { ret 0 }

        @DllStaticImport( "webui_lib", "webui_set_size_sl" )
        public static void libSetSize( Int64 w, int wd, int ht ) {}

        # …… 其余窗口/属性/JS 直调同构 ……

        # ── 事件参数读取（回调内调用）────────────────────
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

        # ── 事件返回值（回调内调用，回传 JS）─────────────
        @DllStaticImport( "webui_lib", "webui_return_int_sl" )
        public static void returnInt( Int64 e, Int64 n ) {}

        @DllStaticImport( "webui_lib", "webui_return_float_sl" )
        public static void returnFloat( Int64 e, double f ) {}

        @DllStaticImport( "webui_lib", "webui_return_string_sl" )
        public static void returnString( Int64 e, string s ) {}

        @DllStaticImport( "webui_lib", "webui_return_bool_sl" )
        public static void returnBool( Int64 e, bool b ) {}

        # ── 回调注册辅助 ──────────────────────────────────
        # 把 SL 静态方法 / lambda 转成 createCallback 节流点地址
        public static Int64 makeCallback( string methodId )
        { ret FFI.StaticLibrary.createCallback( methodId, "ptr->void" ) }
    }
}
```

---

## 4. 处理函数写法（两种）

### 4.1 静态方法（显式 methodId）

```sl
public class MyApp
{
    static void onClick( Int64 e )
    {
        string name = SLang.WebUI.getArgString( e, 0 )
        SLang.WebUI.returnString( e, "Hello, " + name )
    }
}

# 绑定：先 makeCallback 得节流点地址，再 win.bind
Int64 cb = SLang.WebUI.makeCallback( "onClick" )
win.bindEvent( "onClick", cb )
```

### 4.2 Lambda（语法糖，内部合成 methodId + createCallback）

```sl
Int64 cb = SLang.WebUI.makeCallback( (Int64 e) => {
    string name = SLang.WebUI.getArgString( e, 0 )
    SLang.WebUI.returnString( e, "Hello, " + name )
} )
win.bindEvent( "onClick", cb )
```

> 注：SLang lambda 能否直接喂给 `createCallback` 取决于「lambda → 静态方法 id」的
> 现有能力（见 `ffi.md` §2.4 回调仅支持静态方法）。若 lambda 不可直接注册，P1 先用
> 4.1 显式静态方法；4.2 作为语法糖后续补齐（在 `WebUI.sl` 内做闭包→命名方法映射）。
> 本设计以 4.1 为基线，4.2 为增强。

---

## 5. 最小用法（Hello World）

```sl
import SLangWebUI;

public class App
{
    static void onGreet( Int64 e )
    {
        string who = SLang.WebUI.getArgString( e, 0 )
        SLang.WebUI.returnString( e, "Hello, " + who + " from SLang!" )
    }

    static void main()
    {
        SLang.WebUI.init()

        SLang.WebUI.Window win = new SLang.WebUI.Window()
        win.setSize( 480, 320 )
        win.bindEvent( "greet", SLang.WebUI.makeCallback( "onGreet" ) )

        win.show( "<html><body>" +
                  "<input id='name' value='world'>" +
                  "<button onclick=\"greet(document.getElementById('name').value)\">" +
                  "Greet</button>" +
                  "<script src='webui.js'></script></body></html>" )

        SLang.WebUI.wait()       # 阻塞至窗口关闭
        SLang.WebUI.clean()
    }
}
```

---

## 6. API 一览速查

| SLang 调用 | 底层 webui | 形态 |
|---|---|---|
| `new WebUI.Window()` | `webui_new_window` | 直调 |
| `win.show(html)` | `webui_show` | 直调 |
| `win.bindHandle(el, Function)` | `webui_bind` + trampoline + slot 分发（函数值经 SL 层 handler 表） | 桥接 |
| `WebUI.getArgString(e,i)` | `webui_get_string_at` | 直调 |
| `WebUI.returnString(e,s)` | `webui_return_string` | 直调 |
| `win.runScript(js)` | `webui_run` | 直调 |
| `win.script(js,t)` | `webui_script` | 原生封装 `->string` |
| `WebUI.wait()` | `webui_wait` | 直调 |
| `WebUI.makeCallback(id)` | `FFI.createCallback` | FFI 回调 |

---

## 7. 设计取舍

- **门面 vs 直连**：`Window` 类是门面（持句柄、收敛属性 API），`WebUI` 静态类是工具/
  低层绑定聚合；与 Mysql 的 `Mysql`/`MysqlConnection` 分工一致。
- **兜底函数体**：所有 `@DllStaticImport` 都带等价 SL 兜底（返回零值/空串），DLL 缺失时
  不致崩溃，仅功能不可用（可经 `WebUI.init()` 后置标志位提示）。
- **不暴露 `webui_event_t`**：SLang 只持有 `Int64` 事件指针，字段读取全走 `getArg*`，
  隔离 webui 结构体布局变化（版本漂移防护，见 `07`）。
