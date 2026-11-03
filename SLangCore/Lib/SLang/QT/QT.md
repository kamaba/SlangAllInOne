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
