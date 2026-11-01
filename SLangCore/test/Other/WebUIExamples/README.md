# WebUIExamples —— python-webui/examples 的 SLang 重写

把 [webui-dev/python-webui](https://github.com/webui-dev/python-webui/tree/main/examples)
官方 9 个示例用 **SLang**（`SLang.WebUI`，对标 Python 的 `webui` 模块）重写，
并合并成**单工程 + 启动菜单**：运行后弹出一个菜单窗口，点选任意示例即在新窗口中启动。

> 底层 WebUI 能力由 `SlangAllInOne/SLangCore/Lib/SLang/WebUI/` 的 `SLangWebUI` 模块提供
> （C 层 `webui_lib.dll`，基于 webui 2.5 的 MIT 代码）。本目录只新增示例工程，不改动库本身
> （仅给 `WebUI.sl` 补了一个 `setPublic` 绑定，对应 C 层已有的 `webui_set_public_sl`）。

## 目录结构

```
WebUIExamples/
├── WebUIExamples.sl        # 启动菜单(Launcher) + 9 个示例类
├── WebUIExamples.sp        # 工程入口
├── WebUIExamples.jsonc     # 工程配置（引用 Core/Std/SLangWebUI）
├── README.md
├── www_serve/              # serve_folder 示例的静态目录（index.html / second.html）
├── www_editor/             # text-editor 示例的静态目录（index.html）
└── www_react/              # react 示例占位（npm build 后覆盖）
```

## 运行方式

### 方式 A：测试宿主（推荐，自动托管依赖）

```powershell
# 在工程根目录（SlangAllInOne/）执行；最后一个参数是显式工程路径（可省略 .sp）
dotnet run --project Project\CSimpleVMTest\CSimpleVMTest.csproj `
  -- SLangCore\test\Other\WebUIExamples\WebUIExamples
```

### 方式 B：发布后直接运行

```powershell
# 先确保发布包已构建（含 webui_lib.dll 等原生依赖）
SlangAllInOne\out\host\slang.exe publish `
  SlangAllInOne\SLangCore\test\Other\WebUIExamples\WebUIExamples --no-banner
# 产物：WebUIExamples\publish\WebUIExamples.exe（双击或命令行运行）
```

启动后浏览器会弹出**菜单窗口**，点击按钮即可逐个体验示例；点 "Exit All" 关闭全部窗口退出。

## 示例对照（python-webui → SLang）

| 示例 | python-webui 要点 | SLang 实现要点 |
|------|------------------|----------------|
| `minimal` | `webui.Window()` + `show` | `SLang.WebUI.newWindow()` + `win.show(html)` |
| `hello_world` | 密码登录；回调 `e.window.script` 取密码、`e.window.show` 切换页面 | `s_win.script(...)` 取密码，`s_win.show(dashboard)` 切换；密码 `123456` |
| `call_js_from_python` | 回调内 `ui.run("alert(...)")` | 回调内 `s_win.runScript("alert(...)")` |
| `call_python_from_js` | 绑定 `my_function`，`return "Hello "+name` | 回调内 `getArgString` + `returnString` |
| `send_raw_to_javascript` | 回调内 `ui.run("receiveRaw('...')")` | 回调内 `s_win.runScript("receiveRaw('...')")`（内联 HTML 已定义 `receiveRaw`） |
| `public_ui` | `webui.set_public(True)` | `win.setPublic(true)`（新增绑定） |
| `react` | 托管 `webui-react-example/build` | `win.setRootFolder("www_react")` + `show("index.html")` |
| `serve_folder` | 托管静态目录 | `win.setRootFolder("www_serve")` + `show("index.html")` |
| `text-editor` | 托管编辑器静态资源 | `win.setRootFolder("www_editor")` + `show("index.html")` |

## 需要你自备资源的示例

按既定方案，下列示例只提供 SLang 入口 + 说明，外部资源由你放置：

### react
1. 把官方 `examples/react/webui-react-example` 工程拷到本地并 `npm install`；
2. `npm run build`，把 `build/` 目录内容放到本目录的 `www_react/` 下（覆盖占位 `index.html`）；
3. 启动本示例即可加载 React 应用。
   （`examples/react` 里的 `build_react.bat` / `build_react.sh` 可作参考。）

### serve_folder / text-editor
已各附一份可直接运行的示例 `index.html`（分别位于 `www_serve/`、`www_editor/`），
你可按需替换成自己的静态文件；`serve_folder` 还带了 `second.html` 演示多文件跳转。

## 备注
- 所有内联/托管 HTML 均自带 `<script src="/webui.js"></script>`（webui 自动注入，无需手动放文件）。
- 菜单在新窗口中创建示例窗口，依赖 webui 在事件回调内创建窗口的能力（webui 原生支持）。
- 若某示例窗口未弹出，请先看控制台/日志；多数情况是 `webui_lib.dll` 未随模块拷贝到运行目录。
