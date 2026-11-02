# slQT · 01 总体目标与范围

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · **01 总览** · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v0.1
- 本文定义 slQT 的**目标、范围、非目标、关键设计决策**，是评审重点。绑定契约细节见 03/04，SL 封装类见 05，信号槽见 06。

---

## 1. 目标

| 目标 | 说明 |
|---|---|
| 像 PyQt 一样用 Qt | SLang 脚本直接 `SLang.QT.newButton(...)`、`button.clicked( App.onCb )`（handler 全限定引用），Qt 负责渲染与事件循环 |
| 复用已落地 FFI 机制 | 不新造跨语言机制，复用 `@DllStaticImport` / `FFI.StaticLibrary.createCallback`（见 `md/project/ffi.md`） |
| 单一绑定面 | SL 侧只允许 `QTFFI.sl` 出现 FFI 声明，其余 `.sl` 调本文件静态函数（对齐 `RenderFFI.sl` 约定） |
| 零/低 SL 帧开销 | 高频创建/设属性走 T1 `@DllStaticImport`（装配期绑定、零 SL 帧）；事件回调走 T2 FFI 回调 |
| 跨平台一致 | Windows / Linux / macOS 共用 `slang_qt` 一个 DLL 抽象；Qt 自身跨平台，SL 侧不分平台分支 |
| 与仓库同版本 | 跟随 R17 四端（`0.0.52`）统一版本号，任一端改动即 +1 |

## 2. 范围

- **做**：Qt Widgets 基础控件（窗口/按钮/标签/输入框/布局/菜单/对话框）、信号槽连接、事件循环驱动、属性设置、基础绘图（`QPainter` 有限子集）、资源/样式（`QSS` 字符串）。
- **第一版重点（MVP）**：`QApplication` / `QWidget` / `QMainWindow` / `QPushButton` / `QLabel` / `QLineEdit` / `QVBoxLayout` / `QHBoxLayout` / `QMessageBox` + 点击/文本变更两类信号。

## 3. 非目标（明确不做）

- **不做 QML / Qt Quick**：第一版只覆盖 Widgets 体系（PyQt 的 `PyQt5.QtWidgets` 对应面）。QML 留给后续演进。
- **不做 Qt 网络 / 多媒体 / WebEngine**：这些用 SLang 现有的 `SLang.Server`（`SLang/Server/`）、`Std` 库覆盖更好，不在 slQT 重复造。
- **不把 Qt 嵌进 cvm 源码树**：`slang_qt` 是独立 DLL，cvm 本体保持 C99 与平台无关（R3）。
- **不改 FFI 机制本身**：slQT 完全消费现有 FFI；若发现 FFI 能力不足（如需要 >6 参或 arm64），在 FFI 层统一解决，不在此处打补丁。

## 4. 关键设计决策（评审重点）

- **D1 架构：FFI 驱动，而非嵌入 VM。** slQT 采用「SLang 宿主进程 → FFI → `slang_qt.dll`（C++/Qt，`extern "C"` 扁平 ABI）」模式，与 `Render` 库一致。理由：Qt 是 C++，FFI 仅支持 `extern "C"` 扁平 ABI（见 `ffi.md` §9），无法直连 Qt 成员函数；用一个 C++ 包装层把 `QObject*` 收敛为 `int64` 句柄，再经 FFI 暴露扁平函数是最自然的边界。（另一种「把 SLang VM 嵌入 Qt 宿主」方案在 02 §1 对比后否决。）
- **D2 对象生命周期：原生句柄表。** 所有 Qt 对象在 `slang_qt` 侧维护一张 `int64 handle -> QObject*`（实为 `QPointer`）的注册表；SL 端只持 `Int64` 句柄，删除走 `slqt_object_delete(handle)`。避免 SL GC 与 Qt 父子树所有权冲突。
- **D3 事件循环：Qt 主循环阻塞，SL 回调重入。** `QApplication.exec()` 在原生侧阻塞运行；Qt 信号触发时，原生桥接层通过预先注册的 **FFI 回调**（`FFI.StaticLibrary.createCallback`）重入 SLang VM 执行用户函数。同时提供 `slqt_app_process_events()` 非阻塞单轮，供想自己写循环的用户使用。
- **D4 信号槽：原生连接 + 回调桥。** `QObject::connect(sender, SIGNAL(clicked()), ...)` 在原生侧完成；槽函数是一个原生静态 stub，其内部调用已登记的 FFI 回调句柄。信号参数（如 `valueChanged(int)`）按 FFI 回调「全宽」规则（`ffi.md` §2.4）映射：整数一律 `int64_t`、字符串走 `utf8`。
- **D5 属性/创建优先 T1（零 SL 帧），对象构造返回走 T1 句柄。** `slqt_button_create` 返回 `int64` 句柄（0=失败）；`slqt_widget_set_text(handle, utf8)` 返回 void。所有此类函数用 `@DllStaticImport` 声明，绑定失败回退 SL 函数体（无 DLL 时返回 0/空，便于无 Qt 环境降级测试）。
- **D6 单一绑定面 + 单一契约 DLL。** 全部 `slqt_*` 集中在 `QTFFI.sl`（类 `SLang.QT` 的 `@DllStaticImport("slang_qt", ...)`）；`slang_qt.dll` 符号表在 04 冻结 v1，之后只增不改（改名/改签名须升版本并同步调用点）。`QT.jsonc` 用 `"static": "slang_qt"` 预载，别名 `slang_qt` 供 `@DllImport` 兜底。
- **D7 打包与分发跟随 package-layout。** SL module 经 `slang` 导出为 `SLangQT.module.slb`（开发树落 `out/export/SLangQT/`，`vmDlls` 自动部署 `slang_qt.dll` 到同目录）；发布包场景 `slang_qt.dll` 随平台落 `lib/{windows|linux|macos}\`，CVM 预载候选链自动命中（见 08）。

---

*本文是目标与边界定义。架构方案对比见 02，绑定契约见 03，符号表见 04。*
