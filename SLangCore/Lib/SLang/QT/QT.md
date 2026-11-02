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
- 详见 `../doc/` 设计文档集（00-Index 起）、`../README.md` 与 `../cvm/README.md`。
