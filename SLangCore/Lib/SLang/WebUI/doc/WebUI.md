# SLang.WebUI 库说明

> 模块名 `SLangWebUI`，命名空间 `SLang`，门面类 `SLang.WebUI` + 实例类
> `SLang.WebUIWindow`。底层经 FFI 静态绑定调用 `webui_lib.dll`，后者 vendored
> [webui](https://github.com/webui-dev/webui)（MIT，v2.5.0-beta.4）。
>
> 设计文档见同目录 `00-总览与路线图.md` ~ `07-风险待办与验收.md`。

---

## 1. 这是什么

用**系统已装浏览器**作 GUI、用 SLang 作后端，前端用 HTML/CSS/JS 做桌面应用。
程序体积小、启动快、可移植（运行时唯一依赖是一个浏览器）。对标 `SLang.Mysql` 的
FFI 接入范式。

与既有模块的关系：

| 需求 | 推荐 |
|---|---|
| 桌面 GUI（本地程序 + 浏览器） | **SLang.WebUI** |
| 后端 HTTP/WS 服务 | `SLang.Server` |
| 重型桌面 UI 工具包 | `SLang.QT`（依赖 Qt 运行时） |
| 图形绘制 | `SLang.Render` |

---

## 2. 快速开始

```sl
import SLangWebUI;

class App
{
    # 处理函数：static void X( Int64 eventPtr )，方法名全局唯一
    static void onGreet( Int64 e )
    {
        string who = SLang.WebUI.getArgString( e, 0 )
        SLang.WebUI.returnString( e, "Hello, " + who + "!" )
    }

    static void main()
    {
        SLang.WebUI.init()                          # 默认开启事件串行，规避 VM 并发

        SLang.WebUIWindow win = SLang.WebUI.newWindow()
        win.setSize( 480, 320 )
        win.bindHandle( "greet", onGreet )          # 绑定 JS 函数 greet -> SLang 函数值（方法引用）

        win.show( "<html><body style='padding:20px'>" +
                  "<input id='name' value='world'>" +
                  "<button onclick=\"greet(document.getElementById('name').value)\">Greet</button>" +
                  "<script src='webui.js'></script></body></html>" )

        SLang.WebUI.wait()                          # 阻塞至所有窗口关闭
        SLang.WebUI.clean()
    }
}
```

前端需引入 `webui.js`（webui 自动注入到本地服务，按 `<script src='webui.js'>` 引用）。

---

## 3. API

### 3.1 模块控制（`SLang.WebUI`）

| 方法 | 说明 |
|---|---|
| `init()` | 初始化（开启事件串行 `ui_event_blocking`） |
| `wait()` | 阻塞至所有窗口关闭 |
| `exitAll()` | 强制关闭所有窗口（`wait` 返回） |
| `clean()` | 释放全部资源 |
| `makeCallback(name)` | 把静态方法（按名+参数个数）转成 FFI 回调节流点地址 |
| `getArgCount/Int/Float/String/Bool(e, i)` | 读取事件参数（回调内） |
| `returnInt/Float/String/Bool(e, v)` | 回写事件返回值（回调内） |

### 3.2 窗口（`SLang.WebUIWindow`）

| 方法 | 说明 |
|---|---|
| `newWindow()`（静态工厂） | 新建窗口（窗口标题由页面 `<title>` 决定） |
| `show(html)` / `showBrowser(html, browser)` / `showWv(html)` | 注入 HTML/文件/URL |
| `bindHandle(element, Function)` | **主推**：绑定 JS 函数到任意 SLang 函数值（静态方法引用 / 实例方法引用 / 匿名闭包），返回 bind_id |
| `bindEvent(element, methodName)` | 兼容保留：按方法短名绑定（static void X(Int64)），返回 bind_id |
| `setSize/setMinimumSize/setPosition/setCenter` | 尺寸与位置 |
| `setKiosk/setHide/setResizable/focus/minimize/maximize` | 外观与状态 |
| `runScript(js)` | 单向执行 JS |
| `script(js, timeoutSec) -> string` | 取回 JS 返回值 |
| `setRootFolder(path)` / `startServer(content)` | 本地文件根 / 仅起服务 |
| `close()` / `destroy()` / `isShown` | 关闭与状态 |

### 3.3 bindHandle：函数值事件绑定（主推）

```s
win.bindHandle( "greet", onGreet )            # 静态方法引用（带参/无参皆可）
win.bindHandle( "tick", hooks.onTick )        # 实例方法引用（receiver 被保留）
win.bindHandle( "once", function(){ ... } )   # 匿名闭包
```

- handler 带参时首参为 `Int64 e`（`webui_event_t*`），配合 `getArgString/returnString` 等；
  **无参 handler 也合法**（VM 调用按声明参数槽对齐，多余实参自动丢弃）。
- 实现：SL 层把函数值登记进 `List<Function>`（slot），原生层只存 `bind_id -> slot`；
  事件到达经统一 trampoline 以 `cb(slot, e)` 重入 VM，`WebUI._dispatchHandle` 按槽位取回调用。
- 依赖两项编译器/运行时修复（0.0.52）：① Front 实参位置 0 参方法引用可成立
  （`allowMethodReference` 链尾规则 + SLB 方法旗标补 isGet/isSet 位 512/1024）；
  ② C VM method-ref 调用按声明参数槽对齐（0 参实例引用 this 不再被实参顶掉）。
- 旧 `bindEvent(element, methodName)`（按方法短名）保留兼容，新代码建议 bindHandle。

---

## 4. 处理函数约定（关键）

- 必须是 `static void X( Int64 eventPtr )`（参数即 `webui_event_t*`）。
- 方法名**全局唯一**（按 名字 + 参数个数 解析，见 `FFI.StaticLibrary.createCallback`）。
- 在回调内用 `SLang.WebUI.getArg*` 读取参数、`SLang.WebUI.return*` 回写返回值；
  `return*` 必须在**同一调用栈内**完成（默认事件串行模式）。
- 事件指针仅在回调调用栈内有效，SLang 侧即时拷入 string，无需手动释放。

---

## 5. 线程模型

默认 `webui_init_sl()` 开启 `ui_event_blocking`，使事件在单线程串行处理，规避 SLang VM
并发重入风险。`multi_client`（Web 多客户端并发）模式需 VM 真正线程安全，**当前不支持**。

---

## 6. 构建与许可

- 原生层 `cvm_webui_lib` 内嵌 vendored webui.c，产物 `webui_lib.dll` 自包含。
- 构建前需 `get_webui.ps1` 拉取 webui 源码（MIT），详见 `cvm_webui_lib/README.md`。
- 许可：webui 为 **MIT**，可随 SLang 官方发布包分发（无 GPL 红线）。

---

## 7. 参考

- 设计文档：`doc/00`~`doc/07`
- 范式模板：`SLang.Mysql`（`MysqlClient.sl` / `cvm_sl_mysql_lib`）
- webui 上游：<https://github.com/webui-dev/webui>
