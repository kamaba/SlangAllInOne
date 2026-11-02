# slQT · 10 里程碑与已知限制

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · **10 路线** · 11 规范）
- 版本：v0.1

---

## 1. 里程碑

| 里程碑 | 目标 | 交付物 | 验收 |
|---|---|---|---|
| **M0** | 契约冻结 | 04 符号表 v1 定稿；`slqt_types.h` 枚举值表；`QTFFI.sl` 骨架 | 文档评审通过 |
| **M1（MVP）** | 跑通 Hello World + 点击 | `slang_qt.dll`（app/widget/button/label/vbox 基础符号）+ SL 封装类 + 一个可运行示例 | 示例 1、2 在 Windows Qt 6 下出窗口、点击计数正确 |
| **M2** | 控件与布局扩面 | `QLineEdit`/`QMainWindow`/`QHBoxLayout`/`QGridLayout`/`QMessageBox` + 绘图子集（`slqt_painter_*`，含描述符打包） | 示例 3 + 一个网格布局示例跑通 |
| **M3** | 回调槽优化 | 原生「handle→SL method」映射表，突破 8 槽硬限制（06 §4） | 多控件多信号场景无槽泄漏 |
| **M4** | 跨平台 | Linux（`libslang_qt.so`）+ macOS（`libslang_qt.dylib`）构建脚本 + 装载验证 | 三平台各跑通示例 1 |
| **M5** | 打包与分发 | 发布包 `lib/<平台>/slang_qt.dll` 部署 + `slang ffi-check` 契约校验 | `slang run` 用户工程出 UI，无 Qt 机器降级不崩 |
| **M6（演进）** | QSS 主题 / 菜单栏 / 更多控件（QComboBox/ListWidget/Slider/Tab） | 扩充 04 符号表（只增不改） | 对照 PyQt `QtWidgets` 覆盖度清单 |

## 2. 已知限制（来自 FFI 机制）

| 项 | 影响 | 对策 |
|---|---|---|
| **FFI 仅 x64 ABI**（`sl_ffi_call` 静态展开） | Win/Linux/mac 桌面 OK；**arm64（Android/iOS）暂不可用 T1** | M4 前置：FFI 层扩 arm64 派发（`gen_sl_ffi_call.py` 增目标）；未扩展前移动端不可用 slQT |
| **参数 ≤ 6** | 超参函数无法直连 | 描述符打包（`Memory.alloc`+`writeXxx`，见 03 §3.2 / 04 §4.7 `fill_rect`） |
| **库 ≤ 32、回调槽 ≤ 8** | Qt 单库足够；信号回调多时撞槽上限 | M3 原生映射表复用单槽转发 |
| **不支持 varargs** | Qt 无 varargs API 暴露，影响小 | 不暴露变参接口 |
| **C++ 成员函数不可直连** | 必须 `extern "C"` 扁平包装 | `slqt_*` 全 `extern "C"`，`QObject*` 收敛为 `int64` 句柄（D1/D2） |
| **utf8 回调缓冲即取即用** | `textChanged` 的 string 只在回调体内有效 | 用户需立即拷贝（06 §4） |
| **绑定失败静默回退函数体** | 无 `slang_qt.dll` 时控件返回 0 句柄 | 封装类判 0 降级（05 §8），CI 无 Qt 也能编译跑逻辑 |

## 3. 风险与决策点

1. **Qt 版本选择**：用户现装 `qtcreator-20.0.2`（Qt Creator，非 Qt 库本身）。需确认实际 Qt 运行时版本（Qt 5.15 / Qt 6.x）。首版锁定 **Qt 6**（Widgets 模块稳定、CMake 支持好）；若用户只用 Qt 5，则 vcxproj 改 `Qt5` 组件即可（ABI 在 `slqt_*` 层隔离，SL 侧无感）。
2. **moc 需求**：首版 C++ 侧**不定义自定义 QObject 子类**（用 lambda 连接），避免 moc 与构建复杂度（07 §2.1）。
3. **事件循环阻塞**：`app.exec()` 阻塞是首版默认；非阻塞模式（06 §3.2）作为可选，长逻辑卡 UI 的风险需在文档/示例里提示。

## 4. 与仓库其它模块的协同

- **复用 FFI**：slQT 不新造机制，全部消费 `md/project/ffi.md`。
- **复用 Render 范式**：`QTFFI.sl` 对标 `RenderFFI.sl`，`slang_qt.dll` 对标 `slang_render.dll`。
- **不重复造**：网络/HTTP 用 `SLang.Server`；图形用 `Render`；slQT 只做「窗口 + 控件 + 事件」（01 §3 非目标）。
- **版本**：任一里程碑落地即按 R17 同步四端版本号（11 §2）。

---

*路线图与限制已列。版本与规范见 11。*
