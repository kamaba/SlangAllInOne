# SLangQT

SLang 绑定 Qt 的 GUI 库（类比 PyQt）：用 SLang 脚本作为应用逻辑层，通过 FFI 调用包装了 Qt6 Widgets 的原生 DLL（`slang_qt.dll`），由 Qt 负责窗口/控件渲染、事件循环与信号槽；SLang VM 作为宿主驱动 Qt，Qt 事件再经 FFI 回调回到 SLang 函数。

## 层级

- `QTFFI.sl`（模块单一绑定面）：全部 `@DllStaticImport("slang_qt", ...)` 声明 + 信号回调桥 + 工厂。
- `core/*.sl`：SLang 封装类（`QApplication` / `QWidget` / `QPushButton` / `QLabel` / `QLineEdit` / `QMainWindow`）。
- `layout/*.sl`：布局类（`QVBoxLayout` / `QHBoxLayout` / `QGridLayout`）。
- `cvm/`：原生层（`slang_qt.c` 绑定层 + `slang_qt_stub.c` 无 Qt 桩 / `slang_qt_qt.cpp` 真实 Qt 实现；两个 vcxproj）。

## 用法

```sl
import SLangQT;
import Std;

public class App
{
    public static void onClick()
    {
        Console.println( "clicked!" )
    }

    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()
        SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
        btn.clicked( App.onClick )   # handler 必须全限定引用，裸名无法解析
        btn.show()
        app.exec()
    }
}
```

> 两处硬约定（2026-11-02 经 `test/Other/QTTest` 编译+运行实测）：**handler 必须传全限定引用**（`类名.方法` / `实例.方法` / 闭包）；**对象创建不带 `new`**（`QPushButton b = QPushButton(parent)`，或走 `SLang.QT.newXxx` 工厂）。

## 构建 / 运行（标准库形态模块 `Lib/SLang/QT/`）

- 本库是 `SlangAllInOne\SLangCore\Lib\SLang\QT\` 标准库形态模块，**与 Mysql/Server 同构布局**（模块源文件在模块根：`QT.sp`/`QT.jsonc`/`QTFFI.sl`/`core\`/`layout\`，原生层 `cvm\`；2026-11-02 自插件形态迁移并展平）。引用方工程走 **spm 包形态**：`references` 写 `{ "path": "./modules/SLangQT" }`，产物（slb + json + slang_qt.dll）由 `cvm\build-slqt.ps1` 步骤 5 一键打包进工程 `modules\SLangQT\`；备选直引 out\export 产物 `{ "path": "../../../../out/export/SLangQT/SLangQT.module.json" }`。原生 `slang_qt.dll` 经模块 `dllImports` FFI 预载（见 `doc/08-Packaging.md` §2）。
- 一键构建：`powershell -File cvm/build-slqt.ps1`（在 `QT\` 目录下执行；默认 STUB；`-Qt -Qt6Dir <dir>` 切真实 Qt6 后端）。`vmDlls` 挂 `cvm/slang_qt.vcxproj`，编译模块时 Front 自动 msbuild 出 DLL 并拷入模块导出目录。
- **已验证（2026-11-02）**：`QTTest` 经 `CSimpleVMTest` 宿主以模块形态跑通，`ffi_connect` 返回真实 `bind_id > 0`（FFI 回退体返回 0，故 PASS 即证明原生 DLL 真被装载），输出 `slQT smoke test: PASS`。
- 真实 Qt 渲染：`build-slqt.ps1 -Qt`（Qt6_DIR 默认 `C:\Qt\6.8.1\msvc2022_64`，本机 aqtinstall 装位）编出 Qt 后端（独立落 `cvm/x64/QtRelease/`），再跑 `cvm/run-qttest.ps1` 在自己终端弹真实 Qt 窗口（agent 会话无可视桌面时 exec 即返属预期）。
- 已知显示怪癖（VM 层，非 slQT 范畴）：`"text=" + Int64` 拼接输出为空（`bind_id` 数值不回显），判断逻辑（`bid != 0`）不受影响；WebUITest 同样存在。

## Qt 运行库自位部署（qtRuntime，2026-11-03）

发布/运行不再引用系统 Qt 安装：把 Qt 模块 dll + 插件**分类**复制进自身运行目录（同位槽
`modules\SLangQT\`，与 `slang_qt.dll` 同目录，FFI 用 `LOAD_WITH_ALTERED_SEARCH_PATH`
从该目录解析依赖链），qt.conf（exe 同位）重定向插件搜索并抑制 Qt6Core 编译期烘焙的
SDK 前缀。

- **配置**：工程 jsonc 顶层 `"qtRuntime"` 段（`enabled/qt6Dir/modules/plugins/extraBinDlls/debugRuntime/targetDir`，
  见 `QTTest.jsonc`）。`enabled=true` 时 `slang publish` 缺 SDK/缺件按 **FAIL** 处理
  （`PublishCommand.DeployQtRuntime`），Core/Gui/Widgets 三件套强制补齐。
- **开发态换组合**：`cvm\deploy-qt.ps1 -Combo minimal|gui|data|full [-Targets modules,package,publish]`
  （组合表见脚本头注释；full=17 模块 + 8 插件分类 + opengl32sw）。`cvm\run-qttest.ps1 -Combo full`
  封装"构建→stage→deploy→跑"全链。
- **QTTest 验证矩阵（2026-11-03 全绿）**：stub headless / qt+minimal(0/14，面板 SKIP) /
  qt+gui(2/14) / qt+data(6/14，qsqlite+https+线程池) / qt+full(14/14，13 面板 + GL 187 帧 +
  QTimer 51 tick 移动动画)，真实窗口与 offscreen 均通过；发布目录移动 + SDK 改名后
  `QTTest.exe` 独立运行 exit=0（自洽可移植）。
- **陷阱清单**（排障实录）：
  1. stage 重编模块会把 vmDlls 的 STUB 盖回部署槽——**每次真实运行前先 re-deploy**
     （run-qttest.ps1 已封装顺序；本机 QT.jsonc 的 vmDlls 指向不存在的 `cvm/slang_qt.vcxproj`，
     vmDlls 构建静默跳过，真实后端靠 deploy-qt.ps1 同步）。
  2. 包内 C VM 陈旧会整体回退 `backend=stub`（FFI 装载失败静默降级；`FFI: failed to load library`
     见 `SL_VM_LOG=on` 日志）——改 `sl_ffi_lib_manager.c` 等底层后须重建 C VM 并
     `scripts\build-packages.ps1` 刷新 package。
  3. `QSqlQuery/QSqlDatabase/QDomDocument/QPrinter/QConcurrentTask` **非 QObject**：
     通用 `object_delete` 按 QObject vtable 派发会 AV——后端经 `slqt_register_dtor` 侧表
     分派类型化析构器（勿直接 `delete (QObject*)`）。
  4. FFI 静态库（`dllImports` "static"）已 **pinned**：`sl_ffi_lib_manager_clear` 不再
     显式 FreeLibrary（提前卸载会打乱 Qt 依赖链退出序 → atexit 崩溃）。
  5. Qt 6.8 的 `qWait/qSleep` 已移入 QtCore（Q_CORE_EXPORT）；`QtConcurrent::run` 为内联
     模板——要让链接器为 Qt6Test/Qt6Concurrent 生成 /DELAYLOAD 桩，须引用其真实导出
     符号（`QTest::qVerify` / `ThreadEngineBase`，见 `slang_qt_qt.cpp`）。
  6. GL 面板：`setAttributeBuffer` 必须在 VBO 绑定态调用，否则 offset 被当客户端指针
     （=0），核心 profile 下 `glDrawArrays` 从 NULL 读顶点 → ICD thunk 崩溃
     （0xC0000005，堆可执行页 +0xff3c 特征）。
- 详见 `../doc/` 设计文档集（00-Index 起）、`../README.md` 与 `../cvm/README.md`。

## 2026-11-12 P2 能力扩展（CodeEditor 缺口回补）

按 `SLangCodeEditor/doc/参考工程分析/总纲.md` §6 的「七处登记」一次补齐 5 个 Widgets 能力：

| 能力 | SL 侧 | 原生导出 |
|---|---|---|
| `QFileDialog` | `core/QFileDialog.sl`（静态 open/save/selectDir） | `slqt_filedialog_{open,save,dir}_sl` |
| `QStatusBar` | `core/QStatusBar.sl`（attachTo/showMessage/addWidget） | `slqt_statusbar_*_sl` + `slqt_mainwindow_set_statusbar_sl` |
| `QTreeWidget` | `core/QTreeWidget.sl`（路径式 addPath + onSelected） | `slqt_tree_*_sl` |
| `QSplitter` | `core/QSplitter.sl`（addWidget/setSizes） | `slqt_splitter_*_sl` |
| `QCodeEdit` | `core/QCodeEdit.sl`（文本/光标/断点/高亮/两个信号） | `slqt_codeedit_*_sl` |

- **七处登记**：`cvm/src/slang_qt/` 五件套（`slang_qt.h` 声明 + 信号宏、`slang_qt.c` 转发、`slang_qt_backend.h` 契约、`slang_qt_qt.cpp` Qt6 实现、`slang_qt_stub.c` headless 桩）+ `QTFFI.sl`（28 条 `@DllStaticImport`、3 个 `SIG_*`、8 个工厂、connect 的 cb 分派）+ `QT.jsonc`（5 条 compileFiles、5 个 struct children）。
- **新增信号**：`SIG_TREE_SELECTED=6`（`QTreeWidget::itemSelectionChanged`，utf8 完整路径 → `_dispatchString`）、`SIG_CODEEDIT_LINE_CHANGED=7` / `SIG_CODEEDIT_BREAKPOINT=8`（int 行号 → `_dispatchInt`）。与 `slang_qt.h` 的 `SLQT_SIG_*` 宏逐值一致。
- **复合控件策略**：`SlangHighlighter : QSyntaxHighlighter` 只覆盖 `highlightBlock`，`SlangCodeEdit : QPlainTextEdit` 只覆盖 `paintEvent`（行号区/断点圆点/当前行）与 `mousePressEvent`（装订线点击），**均无 `Q_OBJECT`、不需要 moc**；信号连接全部用 lambda + 回调指针，不用 `qobject_cast` 下转自定义类型（避免 RTTI 依赖）。
- **踩坑**：`QAbstractScrollArea::setViewportMargins` 是 protected，后端函数不能直接调；改为在 `SlangCodeEdit` 内提供 `public void syncGutter()`，由 `slqt_be_codeedit_set_font_pt` 触发。
- **构建验证**：`build-slqt.ps1 -Qt`（MSVC 14.51 + Qt 6.8.1）与默认 stub 双构建均通过；stub 构建会覆盖导出目录的 DLL，**验证完必须再跑一次 `-Qt` 恢复**（见上文陷阱 #1）。运行时 `backend: qt`，`QCodeEdit` 读写/光标行/断点探针返回 `codeLen=17 line=2 bps=2`。
- **消费方**：`SLangCodeEditor` 的 `InputDialog` / `MainFrameUi` / `SolutionPanelUi` / `CodePanelUi` 已接线；`QSplitter` 于第三轮在 `CodePanelUi` 完成接线。

## 2026-11-12 第三轮补记（QCodeEdit 取词）

应用侧实现「转到定义」需要读光标下单词，按 §6 [C] 先在 QTModule 补齐能力，再双构建部署，最后才在应用接线：

- 新增两条导出 `slqt_codeedit_word_sl(int64_t)` / `slqt_codeedit_selected_sl(int64_t)`，五件套同步登记（`slang_qt.h` 声明、`slang_qt.c` 转发、`slang_qt_backend.h` 契约、`slang_qt_qt.cpp` 实现、`slang_qt_stub.c` 空桩），`QTFFI.sl` 加 `ffi_codeeditWord` / `ffi_codeeditSelected`（有效 FFI 206 → 208）。
- Qt6 实现走 `QTextCursor::WordUnderCursor` 与 `selectedText()`；stub 后端返回空串，调用方按「无符号」处理，不会崩。
- `core/QCodeEdit.sl` 暴露 `wordUnderCursor()` / `selectedText()`，应用侧只经 `UiContext.codeWord()` / `codeSelected()` 取纯字符串，逻辑层不 import SLangQT。
- 验证：`build-slqt.ps1`（stub）与 `build-slqt.ps1 -Qt` 双构建 + stage 后，Qt 后端探针返回 `p3: word=import sel=`，证明光标取词真实生效。
- `SLang.QT.timer` 被应用侧用作非阻塞进程轮询时，务必复用同一个 `QTimer`/回调登记（每次 `timer()` 都会 `new QTimer` 并追加 `_handlers`，长轮询会泄漏句柄与函数值）。

## 2026-11-12 第四轮补记（Qt 原生 TCP 客户端桥 / SLDP）

按总纲 §6 [C] 五件套同步新增 5 条导出，供 CodeEditor 的真实调试会话使用：

- `slqt_sldp_connect_sl(int32_t port)` / `slqt_sldp_send_sl(const char*)` / `slqt_sldp_poll_sl()` / `slqt_sldp_connected_sl()` / `slqt_sldp_close_sl()`；`QTFFI.sl` 加 5 条 `@DllStaticImport` 与 5 个 `SLang.QT.sldpXxx` 门面（有效 FFI 208 → 213，43 struct 不变，无新增 `SIG_*`）。
- Qt6 实现：全局 `QTcpSocket*` + `QByteArray` 收件箱，`readyRead` lambda 只把 `readAll()` 追加进缓冲；`poll` 取走并清空后经 `slqt_put` 转 UTF-8 返回；`connected` 查 `QAbstractSocket::ConnectedState`；`close` 先 `disconnectFromHost()` 再 `deleteLater()`。`#include <QTcpSocket>` 就近放在实现段前以保持改动集中。stub 后端返回 0 / 空串，headless 下不建连。
- **为什么不用 `Std.Net.TcpSocket`**：C VM 的 socket「Option A 协程挂起」协议需要 VM 主循环调度，而 `QApplication.exec()` 阻塞主循环；实测在 QTimer / Qt 信号回调重入 VM 时 `Net.Tcp.connectTimeout` 恒返回 `null`。把 TCP IO 放到 C++ 侧、SL 侧只同步 `poll()` 取字符串，可完全避开挂起路径。
- 消费方：`SLangCodeEditor` 的 `UiContext.debugOpen/Send/Take/Connected/Close` → `DebugSession`（逻辑层不 import SLangQT）。验证：stub / `-Qt` 双构建 + stage 后，真实会话 `hello → initialize → set-breakpoints → resume → pause → stack/variables` 全通，停止后端口无残留监听。

## 2026-11-12 第五轮补记（断点确认态 / 停驻行）

按总纲 §6 [C] 五件套同步新增 2 条导出（有效 FFI 213 → 215，43 struct / 9 信号不变，无新控件类型）：

- `slqt_codeedit_set_bound_sl(int64_t h, const char* csv)` / `slqt_codeedit_set_stopped_sl(int64_t h, int32_t line)`；`QTFFI.sl` 加 `ffi_codeeditSetBound` / `ffi_codeeditSetStopped`，`core/QCodeEdit.sl` 暴露 `setBoundBreakpoints(string csv)` / `setStoppedLine(int line)`。
- Qt6 实现：`SlangCodeEdit` 增 `QSet<int> boundLines` 与 `int stoppedLine`，`paintEvent` 中用户断点画空心红圈、`boundLines` 命中画实心红圈、`stoppedLine` 画橙色行高亮与装订线箭头；`csv` 为空表示会话未起（点全空心），`line=0` 清除箭头。**两者只改绘制状态，不修改用户设置的断点集合**。stub 后端为空桩，headless 下不影响。
- 消费方：`SLangCodeEditor` 的 `DebugSession.onBreakpointReceipt`（按请求 id 反查文件、读 `verified` 拼 csv）与 `stopped` 事件 → `UiContext.setBoundBreakpoints/setStoppedLine`（逻辑层不 import SLangQT）。
- 验证：stub / `-Qt` 双构建 + stage 后（`msbuild` 编译 40 个新函数），真实会话回执 `[breakpoints] 6/6 verified`、`bound=[420..425]`，停驻 `stoppedLine=27`，停止后 `bound` 回空；零 stderr。

## 2026-11-12 第六轮补记（QAction 启用态读取 + FFI ABI 对齐）

按总纲 §6 [C] 五件套同步新增 1 条导出（有效 FFI 215 → 216，43 struct / 9 信号不变，无新控件类型）：

- `slqt_action_enabled_sl(int64_t a) -> int64_t`；`QTFFI.sl` 加 `ffi_actionEnabled`，`core/QAction.sl` 暴露 `isEnabled()`。stub 返回默认启用态。
- **ABI 对齐**：所有新增/改动的 action 接口参数与返回值统一为 `int64_t`；`QAction.setEnabled(bool)` 在 SL 侧显式转成 `0/1` 整数再跨 FFI。原先 `bool → int32_t` / `int32_t → SL int(64)` 的编码在 Qt 回调链里不稳定，对齐后写入稳定。
- **读回边界**：Qt 侧 `QAction::isEnabled()` 经 FFI 读回仍不能作为按位断言数据源（多次复现 `commandDiag` 与 `commandEnabled` 对同一命令码结果互相矛盾）。应用侧改用 `UiContext` 的状态机下发镜像做确定性断言；`UiContext.commandDiag()` 保留为 Qt 真值的独立诊断接口。
- 消费方：`SLangCodeEditor` 的 `MenuLogic.refreshDebugState()` → `UiContext.setCommandEnabled`（同时记录镜像）→ `QAction.setEnabled`。
- 验证：stub / `-Qt` 双构建 + stage 后，`p7 writeRead=[000000]`，`idle/running/paused/restored` 四态按位断言全部符合预期。

## 2026-11-13 第七轮补记（变量层级树，QTModule 零改动）

局部变量视图从扁平 `QListWidget` 升级为 `QTreeWidget` 路径式层级树，**QTModule 无任何改动**（有效 FFI 保持 216）：

- 复用 P2 的路径式建模：`addPath("name : text")` 建顶层节点、`addPath("parent/child : text")` 挂子节点，`tree_count` 返回全部节点数（含子级）。
- SLDP 侧用 v1.1 的 `children{ref}`（D-P4a）自动展开：`variables` 响应中 `ref>0 && childCount>0` 的条目入队（上限 16），单挂起串行发 `children` 请求，响应按请求 id 区分并挂到父路径下。
- **消费方约定**：条目文本统一经 `sanitize` 把 `/` 换成 `\` 后再 `addPath`——路径式建模按 `/` 拆层，值摘要（如 `str:"D:/..."`）含斜杠会被误拆成多层（实测 32 节点 → sanitize 后 15 节点 = 顶层 10 + `Core.List<T>` 的 5 个字段）。
- 验证：确定性断点命中（启动必经行）下，`[stopped] breakpoint framework/data/WorkspaceData.sl:96`，树 15 节点 = 顶层 10 + children 5，注入 `"p/a/b"` 三层 +3；停止后清 0；零 stderr。

## 2026-11-13 第十轮补记（QTabWidget，VS 式多标签）

按「QTModule 先行」补 `QTabWidget`，有效 FFI **216 → 226**、`SIG_*` **9 → 11**、struct **43 → 44**。

- 五处原生登记：`slang_qt.h`（10 条 `SLQT_API` + `SLQT_SIG_TAB_CHANGED=9` / `SLQT_SIG_TAB_CLOSE_REQUESTED=10`）、`slang_qt.c` 转发、`slang_qt_backend.h` 契约、`slang_qt_qt.cpp` Qt6 实现（`#include <QTabWidget>`，`currentChanged` / `tabCloseRequested` 两个 int 载荷 connect 分支）、`slang_qt_stub.c` headless 桩。
- 两处 SL 登记：`QTFFI.sl`（10 条 `@DllStaticImport` + 2 个信号常量 + `connect()` 的 `_dispatchIntCb` 分派 + `newTabWidget` 工厂）、`QT.jsonc`（`compileFiles` + `struct.children`）；新增 `core/QTabWidget.sl`。
- 能力面：`create / add(page 句柄, 标题) / count / current / setCurrent / tabText / setTabText / remove / clear / setTabsClosable`；创建时设 `documentMode + movable + tabsClosable`。
- `QCodeEdit.sl` 增 `QCodeEdit( Int64 handle, bool adopt )` 与 `fromHandle(h)`：按已有句柄收养，**不创建新控件**。
- **重要纪律（跨模块对象存储）**：应用侧不要把 `SLang.Q*` 对象存进 `List<对象>` —— 实测 `List<SLang.QCodeEdit>` 取回后 `_handle` 被污染成无效大整数，`toPlainText()` 返回指针样数字、按句柄直调 FFI 返回空串。正确做法是 `List<Int64>` 只存句柄，需要操作时 `QCodeEdit.fromHandle(h)` 临时收养封装对象。
- **生命周期**：`QTabWidget::removeTab` 只解除父子关系、不 delete 页面；SL 侧关闭标签时对收养对象显式 `delete()`（走 `slqt_be_object_delete` → `delete (QObject*)o` + `slqt_unregister`），避免泄漏与二次释放。
- 验证：stub / `-Qt` 双构建 + stage 通过；消费方 `SLangCodeEditor` 探针 `p11` 得 `open count=3`、`cur=[CCC] h1=18 viaFfi=[CCC]`、`switch A=[AAA-edited] B=[BBB]`、三种关闭与空态全部正确、`failures=0`；主工程编译 `EXIT=0`、Qt 后端零 stderr。
