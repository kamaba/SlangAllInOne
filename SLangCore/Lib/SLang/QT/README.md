# SLangQT — SLang 绑定 Qt6 的 GUI 库（PyQt 风格）

用 SLang 脚本写应用逻辑，Qt6 Widgets 负责窗口/控件渲染、事件循环与信号槽；
SLang VM 经 FFI 驱动 `slang_qt.dll`，Qt 信号再经 FFI 回调重入 SLang 函数。

- SL 引用模块名：`SLangQT`；原生库：`slang_qt.dll`（`slqt_*_sl` 扁平 ABI）。
- **标准库形态模块**（2026-11-02 自插件形态迁移）：位于 `SlangAllInOne\SLangCore\Lib\SLang\QT\`（与 Mysql/Render/WebUI 同级），无 `plugin.jsonc`、不接插件系统——引用方工程 `references` 显式引用模块产物，原生库经模块 `dllImports`（`"static": "slang_qt"`）FFI 预载。
- 设计文档集：[`doc/`](doc/)（00-Index 起，12 篇）。

## 目录

```
SLangCore/Lib/SLang/QT/
├── cvm/                    # 原生层（C99 绑定层 + stub/Qt 双后端）
│   ├── src/slang_qt/       #   slang_qt.c/h、slang_qt_backend.h、slang_qt_stub.c、slang_qt_qt.cpp
│   ├── slang_qt.vcxproj    #   默认 STUB 工程（纯 C，无 Qt）
│   ├── slang_qt_qt.vcxproj #   真实 Qt6 工程（需 Qt6_DIR + VC++）
│   └── build-slqt.ps1      #   一键构建（DLL + SL 模块 + 部署）
├── slang/                  # SLangQT 模块源码（QT.sp/QT.jsonc/QTFFI.sl + core/ layout/）
└── doc/                    # 设计文档集（00-Index ~ 11）
```

## 构建

```powershell
# 默认 STUB 后端（纯 C，headless 可跑通整条链路）：
powershell -ExecutionPolicy Bypass -File cvm\build-slqt.ps1

# 真实 Qt6 窗口（需本机 Qt6 + VC++）：
powershell -ExecutionPolicy Bypass -File cvm\build-slqt.ps1 -Qt -Qt6Dir C:\Qt\6.8.0\msvc2019_64
```

产物：`SlangAllInOne\out\export\SLangQT\SLangQT.module.slb` + 同目录 `slang_qt.dll`（`slang/QT.jsonc` 的 `vmDlls` 随模块编译自动构建并部署 DLL 到模块导出目录）；步骤 5 再把 slb + dll 打包进 `QTTest\lib\` 供测试用例以打包形态调用。

## 引用方工程用法（模块形态）

```jsonc
// <工程>.jsonc —— 两种形态二选一：
{
  "references": [
    /* ① 开发树产物（相对路径层级按工程位置调整） */
    { "path": "../../../../out/export/SLangQT/SLangQT.module.slb" },

    /* ② 打包副本（测试用例同款：lib\ 下 slb + slang_qt.dll 一对；
         build-slqt.ps1 步骤 5 自动打包到 QTTest\lib\） */
    { "path": "./lib/SLangQT.module.slb" }
  ]
}
```

```sl
import SLangQT;
import Std;

public class App
{
    public static void onClick() { Console.println( "clicked!" ) }

    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()
        SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
        btn.clicked( App.onClick )    # handler 全限定引用
        btn.show()
        app.exec()
    }
}
```

验收用例：`SlangAllInOne/SLangCore/test/Other/QTTest/`（`lib\` 打包形态：`./lib/SLangQT.module.slb` 引用 + 平铺 `slang_qt.dll` 预载，headless STUB 跑通输出 PASS）。

## 版本与契约

- `slang_qt.dll` 符号表 v1 冻结于 `doc/04-SymbolTable.md`（只增不改；改签名升契约版本并同步 `QTFFI.sl` 全部调用点）。
- 四端版本跟随仓库统一版本（AGENTS.md R17）。
