# P3 · webview 轻量 GUI（替代 QT 的短期方案）—— 执行计划

> **定位**：用最小成本获得"SLang 能做桌面应用"的能力。要的是能力，不是 QT 本身。
> **QT 暂缓的理由**：moc 元对象系统 / signal-slot / QString-QList 全套类型转换 / 部署体积——绑定工作量大一个数量级且单人难维护；且 QT 绑定依赖 P0 完成 + clang 自动生成绑定脚手架才可控。
> **依赖**：P0（FFI 回调 + 结构体）、P2（spm 多平台原生库分发）。**建议节奏**：2~3 周。

---

## 一、目标

1. `webview` 单库（EdgeWebView2 / WKWebView / gtk-webkit 三平台后端）FFI 绑定；
2. SLang 写后端 + HTML/JS 前端 + webview 壳 = 桌面应用完整路径；
3. SL ↔ JS 双向通信闭环；
4. 作为第一个带多平台原生库的 spm 官方包分发。

## 二、方案架构

```
┌─────────────────────────────────────────┐
│  SLang 桌面应用                          │
│  ┌──────────────┐    ┌───────────────┐  │
│  │ SL 业务逻辑    │◄──►│ 本地 HttpServer │  │  ← 复用 P0-P10 框架
│  │ (auth/db/...) │    │ + WebSocket    │  │    （现成）
│  └──────┬───────┘    └───────┬───────┘  │
│         │ FFI (P0)           │ ws://    │
│  ┌──────▼───────────────────▼───────┐  │
│  │ webview 壳（单 DLL）               │  │  ← 本计划新增
│  │  load http://127.0.0.1:<port>     │  │
│  │  + JSBridge 注入（evalJS / 事件）  │  │
│  └──────────────────────────────────┘  │
│         ▲ HTML/CSS/JS 前端（打包进工程）  │
└─────────────────────────────────────────┘
```

**双通信通道**：结构化数据走本地 WebSocket（复用现成 WS 服务）；命令式调用走 JSBridge（`evalJS` 下行 + 注入 `window.slang` 上行回调——依赖 P0 T4 回调 trampoline）。

## 三、任务分解

### T1 · 选型验证（1~2 天）

**候选**：
- [webview/webview](https://github.com/webview/webview)（C API，单 DLL，Win: WebView2 / macOS: WKWebView / Linux: gtk-webkit2gtk）——**首选**；
- 备选：sciter（闭源收费风险）、 Ultralight（体积大）。

**验证步骤**：Windows 下手工 FFI 调 `webview_create / webview_navigate / webview_run` 跑通最小窗口（P0 完成前的手工烟测用现有 @DllStaticImport 窄通道即可，验证 DLL 可行性）。

**产出**：选型结论 + Windows/Linux 两平台 DLL 获取与分发清单（版本、许可证——webview 为 MIT）。

### T2 · FFI 绑定层（3~4 天，依赖 P0）

**步骤**：
1. **绑定工程**：新建 `Project/cvm_webview_lib/`（vcxproj，仿 cvm_math_lib）——不静态链 webview，而是**运行时动态装载** webview.dll，暴露给 VM 的是稳定的 SL 侧 API（这样 webview 升级不用重编 VM）；
2. **`.slffi.json` 契约**：覆盖 webview C API 核心集（create/destroy/navigate/run/terminate/set_title/set_size/eval/bind）；
3. **回调桥**：`webview_bind(name, callback)` → P0 T4 trampoline → SL 闭包（JS 调 `window.slang.call(name, payload)` 上行）；
4. **线程语义**：`webview_run` 阻塞主线程（UI 事件循环）——SL 侧约定：主线程跑 UI 循环，业务逻辑在 HttpServer/isolate 线程，通信走 WS；文档成文（避免与 VM 主循环打架，必要时 webview 独立线程 + 事件泵转发）。

### T3 · SL 侧 API 收敛（2 天）

**API 面严格控制在十个左右**（避免重蹈大而全）：

```sl
import Webview;

Window w = Window.create( 1280, 800, "SLang App" );
w.title( "若依管理终端" );
w.navigate( "http://127.0.0.1:8080" );      # 或 navigateHtml( "<html>..." ) 离线形态
w.onMessage( "cmd", ( payload ) => { ... } ); # JS 上行
w.evalJS( "app.refresh()" );                 # SL 下行
w.run();                                     # 事件循环
```

**步骤**：`SLangCore\Lib\SLang\Webview\` 新建 SLang.Webview 库工程（.sp/.jsonc/Window.sl），systemCalls 走 cvm_webview_lib（R7 四处同步：.sl 声明 / jsonc cvmFunction / C 实现 / Define.cs 枚举）。

### T4 · 桌面版若依演示（3~4 天，依赖 P1）

- 若依 admin-ruoyi-ui 前端构建产物（静态文件）打包进桌面应用：HttpServer staticFiles 中间件本地伺服 + webview 壳加载；
- 产出 `SLangRuoYiDesktop`：双击 exe 起本地服务 + 弹窗 = **完整桌面管理终端**；
- 这是官网/演示的最佳素材（一个 exe，不装任何东西）。

### T5 · spm 分发（1~2 天，依赖 P2）

- `spm pack` 打 `webview` 包：`.spkg` 内 `lib\windows\webview.dll` + `lib\linux\libwebview.so` + SLang.Webview.slb；
- `spm install webview` 后关联 DLL 自动预装载（复用 `sl_preload_associated_dlls` 的 `lib\<平台>\` 探测序）——**验证 P2 多平台原生库容器的最佳用例**。

### T6 · 文档（1 天，R14）

- `md/lib/Webview.md`：API 手册 + 架构图（本文档 §二）+ 线程语义；
- `SLangCore\samples\GUI\` 增桌面应用示例；README 标准库表加行。

## 四、验收标准

- [ ] Windows / Linux 双平台窗口弹出并加载页面；
- [ ] SL→JS（evalJS）与 JS→SL（onMessage/bind 回调）双向通信往返正确；
- [ ] 桌面版若依单 exe 运行（本地 HttpServer + webview 壳）；
- [ ] `spm install webview` 一键可用，原生库自动落位；
- [ ] 关窗 → 事件循环退出 → VM 资源正常回收（无崩溃/泄漏）。

## 五、执行顺序

```
T1 选型（可与 P0 并行）──► T2 FFI 绑定（需 P0）──► T3 SL API ──► T4 若依桌面版（需 P1）──► T5 spm 分发（需 P2）──► T6 文档
```

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| webview_run 阻塞与 VM 主循环冲突 | 独立线程跑 UI 循环 + 事件转发到 SL（T2 成文约定）；MVP 先支持单窗口 |
| Linux gtk-webkit 依赖链重 | 官方 spm 包按平台裁剪；文档标注 Linux 发行版依赖（webkit2gtk-4.0） |
| WebView2 运行时缺失（精简 Win） | 启动探测 + 引导下载提示（WebView2 Evergreen Runtime） |
| JSBridge 回调线程安全 | 上行回调统一投递到 SL 业务 isolate 处理（复用 isolate 消息队列） |

## 七、与 SLangQT 的关系（远期衔接）

本计划完成后若验证 GUI 需求真实存在且原生控件刚需，再立项 SLangQT：
- 前置：P0 FFI 类型表 + struct 描述符 + **clang/libclang 绑定脚手架**（用 libclang 解析 QT 头文件自动生成绑定，避免手写）；
- 形态：`@qt{}` 内联块或 QT 名空间映射，signal-slot 走 P0 T4 回调机制；
- 本计划的 `Window` API 面设计保持与未来 QT 版可替换（接口先行，实现后换）。
