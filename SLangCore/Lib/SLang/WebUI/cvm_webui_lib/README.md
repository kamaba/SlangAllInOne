# cvm_webui_lib —— SLang WebUI 原生层（产物 webui_lib.dll）

## 职责

`SLangWebUI` 模块的原生实现，位于开源 GUI 库 **[webui](https://github.com/webui-dev/webui)**
（MIT，**v2.5.0-beta.4**）之上的一层扁平 C ABI 包装，供 `WebUI.sl` 经
`@DllStaticImport` 静态绑定（opcode 77）直调。

- `cvm_webui.h` —— 导出声明（前缀 `webui_*_sl`，`WEBUI_SL_API` dllexport）
- `cvm_webui.c` —— 实现：窗口/属性/JS 直调转发 + 回调桥（trampoline 池 +
  `bind_id -> SLang 回调节流点` 映射）+ 事件读取/返回转发 + `webui_script` 输出缓冲封装
- `webui_wrap.h` —— webui 的**最小 ABI 声明**（不拉 windows.h 等平台头，规避
  UCRT 头污染；签名严格对齐上游 webui.h）
- `webui_stub.c` —— **占位实现（默认编译）**：把 cvm_webui.c 调用的全部 `webui_*`
  实现为 no-op，保证无外部依赖即可编译/运行（headless 验证用，不会真正开浏览器）
- `webui.h` / `src\webui.c` / `bridge\webui_bridge.h` / `src\civetweb\*` —— vendored
  上游源码（MIT），由 `get_webui.ps1` 拉取后参与编译（真实 GUI 能力）

## 构建模式（两种）

| 模式 | 编译源 | 能力 | 依赖 |
|---|---|---|---|
| **stub（默认）** | `cvm_webui.c` + `webui_stub.c` | 链路验证（窗口/绑定句柄成立，`show()` 恒 false） | 无 |
| **真实 webui** | `cvm_webui.c` + `src\webui.c` + `src\civetweb\civetweb.c` | 完整 GUI（浏览器作窗口） | 需先跑 `get_webui.ps1` |

两种模式均产出**自包含单 DLL**（真实模式把 webui+civetweb 一并编译进来，与 Mysql
静链 mysqlclient 同思路），产物拷贝到模块 `export\SLangWebUI\`。

## 拉取真实 webui 源码（MIT）

```powershell
cd SlangAllInOne\SLangCore\Lib\SLang\WebUI\cvm_webui_lib
powershell -ExecutionPolicy Bypass -File get_webui.ps1
```

脚本按 webui 仓库目录结构落地（`webui.h` 根 / `src\webui.c` / `bridge\webui_bridge.h` /
`src\civetweb\*` 全套 .inl 与 zlib 头——civetweb.c 以相对路径内联 include 它们，
缺任何一个都编不过），并**自动改写 vcxproj** 切换到真实源码编译。

> ⚠️ 大文件批量下载对网络稳定性敏感（本仓库开发环境曾批量 reset）；
> 部分失败时脚本保持 stub 模式并提示重跑。

## 打包与运行（已验证）

```powershell
# 1) 导出模块（同时构建 webui_lib.dll 并拷到 export\SLangWebUI\）
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile `
    -p SlangAllInOne\SLangCore\Lib\SLang\WebUI\WebUI.sp -e ir

# 2) 编译示例
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile `
    -p SlangAllInOne\SLangCore\test\Other\WebUITest\WebUITest.sp -e ir

# 3) stage（module slb/json + webui_lib.dll -> package\win32-debug\{WebUITest,SLangWebUI,lib\windows}）
#    并运行（或用 CSimpleVMTest 宿主 -- 显式路径）
package\win32-debug\bin\csimple_lang.exe run package\win32-debug\WebUITest\WebUITest.module.slb
```

headless 输出（3/3 PASS）：

```
[PASS] webui init ok
[PASS] window handle > 0
[PASS] bindEvent returns bind_id > 0
[INFO] show() = False  (headless 环境预期 false)
=== pass=3 fail=0 ===
RESULT: PASS
```

## 对接上游 v2.5.0-beta.4 的适配记录

- **无 `webui_set_title`**：该版本没有 set_title API（全头检索确认），窗口标题由页面
  `<title>` 决定；SL 层已移除 `libSetTitle/setTitle`（文档同步）。
- **`webui.h` 平台头污染**：上游 webui.h 拉入 windows.h/winsock2/inttypes 等，
  在本工具链下会破坏 UCRT（uintptr_t 宏）；包装层一律走 `webui_wrap.h`，
  上游头只被 `src\webui.c` 自身引用。
- **`bind` 是 SLang 保留字**：SL 层绑定方法命名为 `bindEvent`。
- **嵌入式 HTML 不自动注入 webui.js**：2.5 起服务端原样发送 `win.show()` 传入的
  HTML（`_webui_http_handler` 无注入逻辑），页面**必须自带**
  `<script src='webui.js'></script>`，否则浏览器不会发起 WS 连接，
  `show()` 15 秒超时返回 false。
- **Debug 配置开 `WEBUI_LOG`**：vcxproj Debug 配置已定义 `WEBUI_LOG`，DLL 会把
  webui 全链路日志（`[User]`/`[Core]`/HTTP/WS）打到进程 stdout——排障直接跑
  Debug 包看输出即可；Release 无日志零开销。
- **已知排障陷阱**：宿主进程内 DLL 起的监听端口 **netstat 可能不可见（假阴性）**，
  判定服务器是否存活要用进程内 `connect()` 探针或真实 HTTP/WS 客户端；
  `void()` 形态的 `@DllStaticImport` 曾因 cvm `sl_ffi_sig_parse` 把 `"->void"`
  误判非法而整体静默回退 SL 空函数体（0.0.51 修复，复盘见
  `md/ai/troubleshooting/05-plugin-ffi.md` 2026-10-29 条）。

## 许可

- 本目录 `cvm_webui.*` / `webui_wrap.h` / `webui_stub.c` 为 SLang 自有代码。
- vendored 的 webui 上游源码为 **MIT**，可随 SLang 官方发布包分发（无 Mysql 的 GPL
  红线）。保留其 MIT 版权头，勿删改。
