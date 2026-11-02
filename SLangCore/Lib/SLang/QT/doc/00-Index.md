# slQT · SimpleLanguage 绑定 Qt 设计文档集

- 版本：v3（2026-11-02 去插件化：迁标准库模块形态；v1/v2 插件包方案留档 git 历史）
- 日期：2026-11-02
- 关联代码根：`SlangAllInOne/SLangCore/Lib/SLang/QT/`（标准库形态模块，与 Mysql/Render/WebUI 同级）
- 机制依据：
  - FFI 机制：[`SlangAllInOne/md/project/ffi.md`](../../../SlangAllInOne/md/project/ffi.md)
  - 原生绑定范式（参考实现）：`SlangAllInOne/SLangCore/Lib/SLang/Render/doc/04-NativeBinding-And-Platform.md`
  - 模块/包布局：[`SlangAllInOne/md/project/package-layout.md`](../../../SlangAllInOne/md/project/package-layout.md)
  - 全局规则：`AGENTS.md` §2（R6 新 `.c` 双链登记、R17 四端版本统一、R14 改动必配文档）
- 状态：已落地。实现与文档一致；打包与分发见 `08-Packaging.md`，路线图见 `10-Roadmap.md`。
- 用户现有 Qt 工程：`C:\Qt\qtcreator-20.0.2`（Qt Creator 20.0.2，含 Qt 5/6 工具链）。

---

## 0. 文档集索引

| 编号 | 文件 | 内容 | 主要读者 |
|---|---|---|---|
| 00 | `00-Index.md`（本文） | 文档集索引、总览、目标一句话、阅读顺序 | 全员必读 |
| 01 | `01-Overview.md` | 目标 / 范围 / 非目标 / 关键设计决策 D1-D7 | 全员必读 |
| 02 | `02-Architecture.md` | 两种架构方案对比（FFI vs 嵌入 VM）、选定方案、分层、一帧/一次交互的数据流 | 架构 / 绑定面 |
| 03 | `03-NativeBinding.md` | `slqt_` 原生绑定契约（T1/T2 策略、`extern "C"` 封装、QT.jsonc 的 `dllImports`/`static` 配置） | 后端 / 绑定面 |
| 04 | `04-SymbolTable.md` | `slqt_` 符号全量表（QApplication / QWidget / QPushButton / QLabel / 布局 / 信号槽…） | 后端 / 实现 |
| 05 | `05-SL-Wrapper-Classes.md` | SL 侧封装类设计（`QWidget`/`QLabel`/`QPushButton`/`QVBoxLayout`… 包裹原生 handle） | 模块实现 |
| 06 | `06-Events-And-Signals.md` | 事件与信号槽机制：QT signal → FFI callback → SL 函数；槽绑定协议与回调槽限制 | 模块 / 后端 |
| 07 | `07-Build-System.md` | 构建系统：独立 `slang_qt` 原生 DLL 的 vcxproj/CMake 登记、Qt moc 链接、与 R6/R17 对齐 | 构建 |
| 08 | `08-Packaging.md` | 打包与分发：模块产物导出、原生 DLL 部署链、引用方接入 | 分发 |
| 09 | `09-Examples.md` | 端到端示例（Hello World 窗口、按钮点击计数器、布局嵌套） | 使用者 |
| 10 | `10-Roadmap.md` | 里程碑 M0-M5、已知限制（FFI ≤6 参 / x64 / 回调槽 ≤8）、验收标准 | 排期 / 评审 |
| 11 | `11-Conventions.md` | 版本（R17 同步）、UTF-8（R16）、SLang 编码规范、术语表 | 评审 / 规范 |

阅读顺序：**00 → 01 → 02 → 03 → 04 / 05 / 06（并行）→ 07 / 08 → 09 → 10 / 11**。

---

## 1. 一句话目标

> 让 SLang 像 Python 用 PyQt 那样用 Qt：以 **SLang 脚本为应用逻辑层**，通过 **FFI 调用一个包装了 Qt 的 `extern "C"` 原生 DLL（`slang_qt`）**，由 Qt 负责窗口与控件渲染、事件循环与信号槽；SLang VM 作为宿主进程驱动 Qt，Qt 事件再经 FFI 回调回到 SL 函数。

这与本仓库已有的 `Render` 库模式高度一致（`RenderFFI.sl` 经 `@DllStaticImport` 直连 `slang_render.dll`），slQT 直接复用该「**单一绑定面 + 原生 FFI**」范式，不再发明新机制。

---

## 2. 目录规划（已落地 = 标准库模块形态）

```
SLangCore/Lib/SLang/QT/
├── README.md                         # 模块说明（构建 / 引用用法）
├── doc/                              # 本文档集（00-11 共 12 份）
├── slang/                            # SLangQT 模块源码
│   ├── QT.jsonc                      #   编译清单 + dllImports（slang_qt 静态名绑定）+ vmDlls
│   ├── QT.sp                         #   工程入口
│   ├── QT.md                         #   库说明
│   ├── QTFFI.sl                      #   单一原生绑定面（@DllStaticImport -> slqt_*）
│   ├── core/                         #   SL 封装类（QApplication/QObject/QWidget/QPushButton/
│   │                                 #   QLabel/QLineEdit/QMainWindow）
│   └── layout/                       #   布局类（QLayout/QVBoxLayout/QHBoxLayout/QGridLayout）
└── cvm/                              # 原生粘合层（独立原生 DLL，非 cvm 内部）
    ├── src/slang_qt/
    │   ├── slang_qt.h                #   slqt_*_sl 扁平导出声明（extern "C"）
    │   ├── slang_qt_backend.h        #   后端接口 slqt_be_*（stub / Qt 两套实现）
    │   ├── slang_qt.c                #   绑定层：句柄注册表 + 信号绑定表，转发到 slqt_be_*
    │   ├── slang_qt_stub.c           #   STUB 后端：纯 C 无操作（headless 验证用）
    │   └── slang_qt_qt.cpp           #   Qt6 后端：真实 Qt 实现（lambda 回调节流点）
    ├── slang_qt.vcxproj              #   默认 STUB 工程（纯 C）
    ├── slang_qt_qt.vcxproj           #   真实 Qt 工程（需 Qt6 + VC++）
    ├── build-slqt.ps1                #   一键构建（DLL + SL 模块 + 部署）
    └── README.md                     #   构建 / 切换说明
```

> 信号槽桥接逻辑位于 `slang/QTFFI.sl`（`_dispatchVoid` / `_dispatchString` + `connect`），无需独立 `event/` 目录。

> 注：`cvm/` 是**独立原生工程**，不是 `csimple_lang` 内部 `.c`。R6（新 `.c` 双链登记 `CSIMPLE_LIB_SOURCES` + `vm_lib` vcxproj）仅适用于 cvm 自身源码；slQT 的 DLL 与 `cvm_render_lib`/`cvm_sl_mysql_lib` 同级，各自有独立 vcxproj（见 `07-Build-System.md`）。
