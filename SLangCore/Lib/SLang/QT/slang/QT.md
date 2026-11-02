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

- 本库是 `SlangAllInOne\SLangCore\Lib\SLang\QT\` 标准库形态模块（2026-11-02 自插件形态迁移，无 `plugin.jsonc`）。引用方工程在 `references` 显式引用本模块产物——开发树 `{ "path": "../../../../out/export/SLangQT/SLangQT.module.slb" }` 或打包副本 `{ "path": "./lib/SLangQT.module.slb" }`（`lib\` 下 slb + slang_qt.dll 一对，与 Core/Std 打包形态一致）；原生 `slang_qt.dll` 经模块 `dllImports` FFI 预载（见 `doc/08-Packaging.md` §2）。
- 一键构建：`powershell -File cvm/build-slqt.ps1`（在 `QT\` 目录下执行；默认 STUB；`-Qt -Qt6Dir <dir>` 切真实 Qt6 后端）。`vmDlls` 挂 `../cvm/slang_qt.vcxproj`，编译模块时 Front 自动 msbuild 出 DLL 并拷入模块导出目录。
- **已验证（2026-11-02）**：`QTTest` 经 `CSimpleVMTest` 宿主以模块形态跑通，`ffi_connect` 返回真实 `bind_id > 0`（FFI 回退体返回 0，故 PASS 即证明原生 DLL 真被装载），输出 `slQT smoke test: PASS`。
- 真实 Qt 渲染：`build-slqt.ps1 -Qt`（或把 `vmDlls.project` 切到 `../cvm/slang_qt_qt.vcxproj` 并设 `Qt6_DIR`）重编即可弹出真实 Qt 窗口。
- 已知显示怪癖（VM 层，非 slQT 范畴）：`"text=" + Int64` 拼接输出为空（`bind_id` 数值不回显），判断逻辑（`bid != 0`）不受影响；WebUITest 同样存在。
- 详见 `../doc/` 设计文档集（00-Index 起）、`../README.md` 与 `../cvm/README.md`。
