# WebUI.sl

> 源文件：`WebUI.sl`

## class `WebUI`

- **说明**：── 门面：模块控制 + 低层原生绑定（@DllStaticImport 直调 webui_*_sl）──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void init()` | 初始化 / 创建（init）。 |
| 方法 | `void wait()` | 执行 wait()。 |
| 方法 | `void exitAll()` | 执行 exitAll()。 |
| 方法 | `void clean()` | 执行 clean()。 |
| 方法 | `Int64 libNewWindow()` | 执行 libNewWindow()。 |
| 方法 | `bool libShow(Int64 w, string c)` | 执行 libShow(w, c)，行为详见源实现。 |
| 方法 | `bool libShowBrowser(Int64 w, string c, Int64 b)` | 执行 libShowBrowser(w, c, b)，行为详见源实现。 |
| 方法 | `bool libShowWv(Int64 w, string c)` | 执行 libShowWv(w, c)，行为详见源实现。 |
| 方法 | `void libClose(Int64 w)` | 执行 libClose(w)，行为详见源实现。 |
| 方法 | `void libDestroy(Int64 w)` | 执行 libDestroy(w)，行为详见源实现。 |
| 方法 | `bool libIsShown(Int64 w)` | 执行 libIsShown(w)，行为详见源实现。 |
| 方法 | `Int64 libBind(Int64 w, string element, Int64 cb)` | 执行 libBind(w, element, cb)，行为详见源实现。 |
| 方法 | `Int64 libBindHandle(Int64 w, string element, Int64 slot, Int64 dispatchCb)` | 执行 libBindHandle(w, element, slot, dispatchCb)，行为详见源实现。 |
| 字段 | `static List&lt;Function&gt; _bindHandles = null` | handler 表 + 分发节流点（懒初始化，一次 createCallback 全局共用） 注意：createCallback 的 method 参数必须传"完整 method id （Module.NS.Class.Method_argc_T1_T2）"或"短方法名"二者之一； "NS.Class.Method" 点路径三条查找路径均不命中（VM 日志报 FFI callback: method not found，事件静默丢弃）。短名按 名字+参数个数全局匹配，_dispatchHandle 唯一，走短名最稳。 |
| 字段 | `static Int64 _dispatchCb = 0` | 字段 Int64（类型见签名）。 |
| 方法 | `Int64 bindHandle(Int64 winHandle, string element, Function handler)` | 把任意函数值（静态方法引用 / 实例方法引用 / 匿名闭包）登记进 handler 表， 原生层只保留 (bind_id -&gt; slot) 映射；事件到达经 _dispatchHandle 取回调用。 |
| 方法 | `void _dispatchHandle(Int64 slot, Int64 e)` | 原生事件重入点：按槽位取回用户 handler 调用。 handler 形态兼容：static void X() / 实例 void t() / function(){} （0 参 handler 由 VM 调用对齐丢弃多余实参）；带参 handler 收到 e（webui_event_t*，配合 getArgString/returnString 等使用）。 |
| 方法 | `void libSetSize(Int64 w, int wd, int ht)` | 执行 libSetSize(w, wd, ht)，行为详见源实现。 |
| 方法 | `void libSetMinimumSize(Int64 w, int wd, int ht)` | 执行 libSetMinimumSize(w, wd, ht)，行为详见源实现。 |
| 方法 | `void libSetPosition(Int64 w, int x, int y)` | 执行 libSetPosition(w, x, y)，行为详见源实现。 |
| 方法 | `void libSetCenter(Int64 w)` | 执行 libSetCenter(w)，行为详见源实现。 |
| 方法 | `void libSetKiosk(Int64 w, bool on)` | 执行 libSetKiosk(w, on)，行为详见源实现。 |
| 方法 | `void libSetHide(Int64 w, bool on)` | 执行 libSetHide(w, on)，行为详见源实现。 |
| 方法 | `void libSetResizable(Int64 w, bool on)` | 执行 libSetResizable(w, on)，行为详见源实现。 |
| 方法 | `void libFocus(Int64 w)` | 执行 libFocus(w)，行为详见源实现。 |
| 方法 | `void libMinimize(Int64 w)` | 执行 libMinimize(w)，行为详见源实现。 |
| 方法 | `void libMaximize(Int64 w)` | 执行 libMaximize(w)，行为详见源实现。 |
| 方法 | `void libRun(Int64 w, string js)` | 执行 libRun(w, js)，行为详见源实现。 |
| 方法 | `string libScript(Int64 w, string js, Int64 timeout)` | 执行 libScript(w, js, timeout)，行为详见源实现。 |
| 方法 | `bool libSetRootFolder(Int64 w, string path)` | 执行 libSetRootFolder(w, path)，行为详见源实现。 |
| 方法 | `string libStartServer(Int64 w, string content)` | 执行 libStartServer(w, content)，行为详见源实现。 |
| 方法 | `Int64 getArgCount(Int64 e)` | 执行 getArgCount(e)，行为详见源实现。 |
| 方法 | `Int64 getArgInt(Int64 e, Int64 i)` | 执行 getArgInt(e, i)，行为详见源实现。 |
| 方法 | `double getArgFloat(Int64 e, Int64 i)` | 执行 getArgFloat(e, i)，行为详见源实现。 |
| 方法 | `string getArgString(Int64 e, Int64 i)` | 执行 getArgString(e, i)，行为详见源实现。 |
| 方法 | `bool getArgBool(Int64 e, Int64 i)` | 执行 getArgBool(e, i)，行为详见源实现。 |
| 方法 | `void returnInt(Int64 e, Int64 n)` | 执行 returnInt(e, n)，行为详见源实现。 |
| 方法 | `void returnFloat(Int64 e, double f)` | 执行 returnFloat(e, f)，行为详见源实现。 |
| 方法 | `void returnString(Int64 e, string s)` | 执行 returnString(e, s)，行为详见源实现。 |
| 方法 | `void returnBool(Int64 e, bool b)` | 执行 returnBool(e, b)，行为详见源实现。 |
| 方法 | `WebUIWindow newWindow()` | ── 窗口工厂 ─────────────────────────────────────────────── 带命名空间的 new 表达式（new SLang.WebUIWindow()）解析受限，统一走工厂创建。 |
| 方法 | `Int64 makeCallback(string methodName)` | ── 回调注册辅助 ─────────────────────────────────────────── 把 SLang 静态方法（按名字 + 参数个数解析）转成 createCallback 节流点地址， 交给 libBind 写入原生层 bind_id -&gt; 节流点 映射表。 |

## class `WebUIWindow`

- **说明**：── 窗口实例类 ─────────────────────────────────────────────────

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
| 属性 | `get Int64 handle()` | 获取 handle 的值。 |
| 方法 | `bool show(string content)` | ── 显示内容 ─────────────────────────────────────────────── |
| 方法 | `bool showBrowser(string content, Int64 browser)` | 执行 showBrowser(content, browser)，行为详见源实现。 |
| 方法 | `bool showWv(string content)` | 执行 showWv(content)，行为详见源实现。 |
| 方法 | `Int64 bindHandle(string element, Function handler)` | ── 事件绑定 ─────────────────────────────────────────────── 绑定 HTML 元素/JS 函数到任意 SLang 函数值，支持三种形态： win.bindHandle( "greet", onGreet )                  # static void onGreet(...) 引用 win.bindHandle( "greet", ca.onEvent )               # 实例方法引用（保留 receiver） win.bindHandle( "greet", function(){ ... } )        # 匿名闭包 handler 可带参（Int64 e = webui_event_t*）或无参（多余实参由 VM 对齐丢弃）。 返回 bind_id（&gt;0 成功）。 |
| 方法 | `Int64 bindEvent(string element, string methodName)` | 旧按名绑定（static void X(Int64)，方法名全局唯一）。保留兼容， 新代码建议用 bindHandle（函数值形态）。 |
| 方法 | `void setSize(int w, int h)` | ── 窗口属性 ─────────────────────────────────────────────── |
| 方法 | `void setMinimumSize(int w, int h)` | 执行 setMinimumSize(w, h)，行为详见源实现。 |
| 方法 | `void setPosition(int x, int y)` | 执行 setPosition(x, y)，行为详见源实现。 |
| 方法 | `void setCenter()` | 执行 setCenter()。 |
| 方法 | `void setKiosk(bool on)` | 执行 setKiosk(on)，行为详见源实现。 |
| 方法 | `void setHide(bool on)` | 执行 setHide(on)，行为详见源实现。 |
| 方法 | `void setResizable(bool on)` | 执行 setResizable(on)，行为详见源实现。 |
| 方法 | `void focus()` | 执行 focus()。 |
| 方法 | `void minimize()` | 执行 minimize()。 |
| 方法 | `void maximize()` | 执行 maximize()。 |
| 方法 | `void runScript(string js)` | ── JS 执行 ──────────────────────────────────────────────── |
| 方法 | `string script(string js, Int64 timeout)` | script(js, timeoutSec) -&gt; string（取回 JS 返回值） |
| 方法 | `bool setRootFolder(string path)` | ── 服务器 / 文件 ────────────────────────────────────────── |
| 方法 | `string startServer(string content)` | 运行 / 调用（startServer）。 |
| 方法 | `void close()` | ── 关闭 ─────────────────────────────────────────────────── |
| 方法 | `void destroy()` | 执行 destroy()。 |
| 属性 | `get bool isShown()` | 获取 isShown 的值。 |
