# webui 开源库调研

> 调研对象：[webui-dev/webui](https://github.com/webui-dev/webui)（官网
> <https://webui.me>）。调研依据：GitHub README + 仓库 `include/webui.h` 头文件
> （`WEBUI_VERSION "2.5.0-beta.4"`，MIT License）。本文只做**事实归集与 SLang 可行性
> 判定**，具体封装设计见 `02-集成架构设计.md` / `04-原生C包装层设计.md`。

---

## 1. webui 是什么

- 一句话：**用任意系统浏览器（或可选 WebView）作为 GUI，后端用你偏好的语言，前端用
  现代 Web 技术**。
- 关键区别（vs WebView 嵌运行时）：webui **不把 WebView 运行时塞进程序**，而是启动
  系统已装的浏览器，通过**本地 WebServer + WebSocket** 与后端通信。结果：程序体积小、
  启动快、可移植，运行时唯一依赖是「一个浏览器」。
- 语言绑定丰富：官方提供 Python / Go / Rust / C# / TS / Swift 等 wrapper；C/C++ 是
  一等公民（单头 `webui.h` + 单源 `webui.c`）。**SLang 走 C ABI 直连即可，无需官方 wrapper**。

### 1.1 特性速览

- 便携（运行时仅依赖浏览器；WebView 可选）、单头文件、轻量（几 KB）、小内存占用
- 快速二进制 WebSocket 通信协议
- 多平台 / 多浏览器（Chrome / Firefox / Edge / Safari / Chromium / Opera / Brave …）
- 私有配置 profile 保障安全（cookie 鉴权，防 URL 直连）
- 可选跨平台 WebView：Windows WebView2 ✔ / Linux GTK WebView ✔ / macOS WKWebView ✔

---

## 2. 架构与通信模型

```
┌──────────────┐   本地 HTTP/WS    ┌────────────────────┐
│ 浏览器窗口    │ ◀──────────────▶ │  webui 本地服务      │
│ (HTML/JS/CSS)│   webui.js 注入   │  (随程序启动)        │
└──────────────┘                  └─────────┬──────────┘
                                            │ C ABI
                                            ▼
                                  ┌──────────────────┐
                                  │  后端程序          │
                                  │  (SLang VM +       │
                                  │   cvm_webui_lib)   │
                                  └──────────────────┘
```

- 前端通过 `<script src="webui.js"></script>` 引入 webui 前端脚本；`myFunction(...)` 调用
  经 WebSocket 发到后端，后端 `webui_bind` 注册的回调被触发，返回结果经
  `webui_return_*` 回传 JS。
- 后端直接 `webui_show(window, html)` 注入 HTML 字符串、本地文件或 URL；
  `webui_run(window, js)` 单向执行 JS；`webui_script(window, js, ...)` 取回 JS 返回值。

---

## 3. 完整 C API 清单（按用途分组，附 SLang 可行性）

> 类型映射约定：`size_t`(窗口号/索引) → SLang `Int64/u64`；`bool` → `bool`；
> `const char*` → `utf8/string`；`webui_event_t*` → `ptr`；`void*`(context/raw) → `ptr`。
> 所有 API 参数 ≤6，满足 SLang FFI `SL_FFI_MAX_ARGS`，**可直接静态绑定**。

### 3.1 窗口生命周期

| C API | 签名要点 | SLang 绑定 |
|---|---|---|
| `webui_new_window` | `size_t(void)` | `@DllStaticImport` → `Int64` |
| `webui_new_window_id` | `size_t(size_t)` | 指定窗口号 |
| `webui_get_new_window_id` | `size_t(void)` | 取空闲号 |
| `webui_show` | `bool(size_t, const char*)` | html/文件/URL |
| `webui_show_browser` | `bool(size_t, const char*, size_t)` | 指定浏览器 |
| `webui_show_wv` | `bool(size_t, const char*)` | WebView 形态 |
| `webui_close` | `void(size_t)` | 关单窗 |
| `webui_destroy` | `void(size_t)` | 关窗并释放 |
| `webui_exit` | `void(void)` | 关所有窗（wait 返回） |
| `webui_wait` | `void(void)` | 阻塞至全关 |
| `webui_wait_async` | `bool(void)` | 非阻塞轮询 |
| `webui_is_shown` | `bool(size_t)` | 是否运行中 |
| `webui_clean` | `void(void)` | 释放全部资源 |

### 3.2 事件绑定（核心）

| C API | 签名要点 | 说明 |
|---|---|---|
| `webui_bind` | `size_t(size_t, const char* element, void(*)(webui_event_t*))` | 绑定元素/JS 对象到后端函数；返回 bind_id |
| `webui_set_context` | `void(size_t, const char*, void*)` | 绑用户数据 |
| `webui_get_context` | `void*(webui_event_t*)` | 取回 |

⚠️ 回调指针 `void(*)(webui_event_t*)` **不能直接走 SLang FFI 静态绑定**，必须经
`cvm_webui_lib` 的 trampoline 桥接（见 `02` §3 / `04` §3）。

### 3.3 事件参数读取（回调内调用，全部 `webui_event_t* → 标量`）

| C API | 签名 | 作用 |
|---|---|---|
| `webui_get_count` | `size_t(webui_event_t*)` | 参数个数 |
| `webui_get_int` / `webui_get_int_at` | `long long(webui_event_t* [, size_t])` | 取整数参 |
| `webui_get_float` / `webui_get_float_at` | `double(webui_event_t* [, size_t])` | 取浮点参 |
| `webui_get_string` / `webui_get_string_at` | `const char*(webui_event_t* [, size_t])` | 取字符串参 |
| `webui_get_bool` / `webui_get_bool_at` | `bool(webui_event_t* [, size_t])` | 取布尔参 |
| `webui_get_size` / `webui_get_size_at` | `size_t(webui_event_t* [, size_t])` | 取字节长度 |

### 3.4 事件返回值（回调内调用，回传 JS）

| C API | 签名 | 作用 |
|---|---|---|
| `webui_return_int` | `void(webui_event_t*, long long)` | 返回整数 |
| `webui_return_float` | `void(webui_event_t*, double)` | 返回浮点 |
| `webui_return_string` | `void(webui_event_t*, const char*)` | 返回字符串 |
| `webui_return_bool` | `void(webui_event_t*, bool)` | 返回布尔 |

> 这些返回函数 **可在 SLang 处理函数内直接 `@DllStaticImport` 调用**（参数 ≤6，标量），
> 不需要经过回调指针机制。

### 3.5 JavaScript 执行

| C API | 签名 | 作用 |
|---|---|---|
| `webui_run` | `void(size_t, const char*)` | 单向执行 JS |
| `webui_script` | `bool(size_t, const char*, size_t timeout, char* buf, size_t len)` | 取回 JS 返回值 |

⚠️ `webui_script` 的 `char* buf + size_t len` 是**输出缓冲区**形参（指针 + 长度），
SLang FFI 无法直接表达「输出缓冲区」语义，需由 `cvm_webui_lib` 提供封装
`webui_script_sl(window, script, timeout) -> string`（内部固定缓冲，返回 utf8）。

### 3.6 窗口属性 / 外观

`webui_set_size(size_t, uint, uint)`、`webui_set_minimum_size`、`webui_set_position`、
`webui_set_center`、`webui_set_kiosk`、`webui_set_hide`、`webui_set_title`、
`webui_set_icon`、`webui_set_frameless`、`webui_set_transparent`、
`webui_set_resizable`（WebView）、`webui_focus`、`webui_minimize`、`webui_maximize`、
`webui_set_high_contrast`、`webui_set_custom_parameters`、`webui_set_profile`、
`webui_set_proxy`、`webui_set_public`。

### 3.7 服务器 / 文件 / 路由

`webui_start_server(size_t, const char*)`（只起服务返回 URL）、
`webui_set_root_folder(size_t, const char*)`、`webui_set_default_root_folder`、
`webui_set_file_handler`（自定义文件响应，含异步 `webui_interface_set_response_file_handler`）、
`webui_get_url`、`webui_get_port`、`webui_set_port`、`webui_get_free_port`、
`webui_navigate`、`webui_open_url`。

### 3.8 配置 / 日志 / 运行时

`webui_set_config(webui_config, bool)`（关键：`ui_event_blocking` / `multi_client` /
`asynchronous_response` / `show_wait_connection` / `folder_monitor` / `use_cookies`）、
`webui_set_event_blocking(size_t, bool)`、`webui_set_runtime`、`webui_set_timeout`、
`webui_set_logger`、`webui_get_last_error_number`、`webui_get_last_error_message`。

### 3.9 内存 / 编解码 / 原生数据

`webui_malloc` / `webui_free` / `webui_memcpy` / `webui_encode`(base64) / `webui_decode` /
`webui_send_raw`（二进制直发 UI）。

### 3.10 关键结构体与枚举

```c
typedef struct webui_event_t {
    size_t window;        // 窗口号
    size_t event_type;    // WEBUI_EVENT_* 见下
    char*  element;       // HTML 元素 ID
    size_t event_number;  // 内部序号
    size_t bind_id;       // 绑定 ID（回调分发关键）
    size_t client_id;     // 客户端唯一 ID
    size_t connection_id; // 连接 ID
    char*  cookies;       // 客户端完整 cookie
} webui_event_t;

enum webui_event {
    WEBUI_EVENT_DISCONNECTED = 0,
    WEBUI_EVENT_CONNECTED,
    WEBUI_EVENT_MOUSE_CLICK,
    WEBUI_EVENT_NAVIGATION,
    WEBUI_EVENT_CALLBACK
};

enum webui_browser { NoBrowser, AnyBrowser, Chrome, Firefox, Edge, Safari,
                     Chromium, Opera, Brave, Vivaldi, Epic, Yandex,
                     ChromiumBased, Webview };

enum webui_runtime { None, Deno, NodeJS, Bun };

enum webui_config { show_wait_connection, ui_event_blocking, folder_monitor,
                    multi_client, use_cookies, asynchronous_response };
```

`bind_id` 是**回调分发的枢纽**：原生层以 `bind_id` 为键查 SLang 回调节流点（见 `04` §3）。

---

## 4. 许可（关键结论）

- **MIT License**（头文件与 README 明示）。
- 对比：`SLang.Mysql` 静链 MySQL Connector/C 是 **GPL-2.0**，有「不随官方包分发」红线
  （见 `MysqlClient.md`）。**webui 是 MIT，可自由内嵌源码 / 静态编译并随官方发布包分发**，
  无合规风险。这是选 webui 而非其它 GPL 类 GUI 库的重要加分项。

---

## 5. 构建与分发形态

- 仓库自带：`webui.h`（单头）+ `webui.c`（单源），以及 CMake / Make / Zig 构建描述。
- 编译示例（仅示意，实际由 `cvm_webui_lib` vcxproj / CMake 接管）：
  - Windows：`cl webui.c app.c`（可选 `WEBUI_USE_TLS=1` 需 OpenSSL）
  - Linux：`gcc webui.c app.c -lpthread`
  - macOS：`gcc webui.c app.c`
- 可选 TLS：安全库 `webui-2-secure`（需证书）；默认本地回环通信，普通形态已够用。
- **SLang 方案**：把 `webui.c` + `webui.h` vendored 进 `cvm_webui_lib`，与
  `mysqlclient.lib` 静态链接同思路——产物 `webui_lib.dll` 自包含，不依赖外部
  `webui.dll`。WebView2 形态需目标机有 `WebView2Loader.dll`（仅 Windows WebView 模式需要）。

---

## 6. SLang 可行性判定（汇总）

| 维度 | 判定 |
|---|---|
| 窗口/属性/JS 执行类 API | ✅ 标量参数 ≤6，全部可 `@DllStaticImport` 直调 |
| 事件**读取/返回** API | ✅ 同上，直调 |
| 事件**回调注册** `webui_bind` | ⚠️ 回调指针需原生 trampoline 桥接到 SLang `createCallback`（见 02/04） |
| 输出缓冲区 API（`webui_script`） | ⚠️ 需原生封装为 `->string` |
| `webui_event_t` 结构体 | ⚠️ 不透明，原生层按字段拆成标量经 `get_*` 暴露，SLang 只持有 `ptr` |
| 参数个数上限 | ✅ webui 自身 `WEBUI_MAX_ARG=16` 指 JS→后端参数个数，由 `get_*_at` 逐条读取，不受 SLang FFI ≤6 限制 |
| 许可 | ✅ MIT，可随包分发 |
| 跨平台 | ✅ webui 自带 Win/Linux/mac 分支；SLang 仅 x64（FFI 限制，见 `ffi.md`） |
