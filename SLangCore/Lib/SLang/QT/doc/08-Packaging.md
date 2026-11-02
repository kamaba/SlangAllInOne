# slQT · 08 打包与分发

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · **08 打包** · 09 示例 · 10 路线 · 11 规范）
- 版本：v4（2026-11-02 模块布局对齐 Mysql/Server 规则：源文件展平模块根 + 引用方直引 out\export 产物；v1/v2 插件包方案留档 git 历史）
- 布局权威：[`SlangAllInOne/md/project/package-layout.md`](../../../SlangAllInOne/md/project/package-layout.md)

---

## 1. slQT = 标准库形态模块（2026-11-02 迁移）

slQT 位于 `SLangCore/Lib/SLang/QT/`（与 Mysql/Render/WebUI 同级同构），**无 plugin.jsonc、不接插件系统**；模块源文件在模块根（`QT.sp`/`QT.jsonc`/`QTFFI.sl`/`core\`/`layout\`，Mysql/Server 同款布局）：

```
SLangCore/Lib/SLang/QT/      # 模块根（同 Mysql/Server 布局）
├── README.md / QT.md        # 模块说明
├── QT.sp / QT.jsonc         # 工程入口 + 编译清单（dllImports + vmDlls）
├── QTFFI.sl                 # 单一绑定面（@DllStaticImport("slang_qt", ...)）
├── core/*.sl                # QObject/QWidget/QPushButton/QLabel/QLineEdit/QMainWindow/QApplication
├── layout/*.sl              # QLayout/QVBoxLayout/QHBoxLayout/QGridLayout
├── cvm/                     # 原生层（独立 DLL，非 cvm 内部）
│   ├── src/slang_qt/        #   slang_qt.h / slang_qt_backend.h / slang_qt.c / slang_qt_stub.c / slang_qt_qt.cpp
│   ├── slang_qt.vcxproj     #   默认 STUB 工程（纯 C）
│   ├── slang_qt_qt.vcxproj  #   真实 Qt6 工程（需 Qt6_DIR）
│   └── build-slqt.ps1       #   一键构建（DLL + SL 模块 + 部署）
└── doc/                     # 本设计文档集（00-11）
```

**与插件形态的差异（路由形态不变）**：原生库不走六件套 systemCall/signLabel 路由——全部调用经 SLangQT 模块的 `dllImports`（`"static": "slang_qt"`）FFI 预载直调 `slqt_*_sl`。插件系统此前为 slQT 提供的「refModule 自动引用 + plugin\ 包分发」由「**references 显式引用 + vmDlls 自动部署 DLL**」等价承接，编译器与 VM 零改动。

## 2. 引用方工程消费（模块形态）

工程 `references` 引用模块产物，两种形态：

**① spm 包形态（推荐，package-layout §二.6）**：产物装工程 `modules\SLangQT\`（slb + json + 原生 dll 三件齐装，勿裸拷贝只带 slb——publish-guide §6 坑位实录），引用写模块文件夹：

```jsonc
{
  "references": [
    { "path": "./modules/SLangQT" }
  ]
}
```

`cvm\build-slqt.ps1` 步骤 5 一键打包到 `QTTest\modules\SLangQT\`；发布 Step 8 整目录随包（`publish\release\modules\`），CVM 装载回退链 `<dir>/modules` 直查命中。

**② 开发树直引（Mysql/Server 测试同款）**：

```jsonc
{ "path": "../../../../out/export/SLangQT/SLangQT.module.json" }
```

也可引用模块源目录（Front 三级加载策略按 `QT.jsonc` 的 `export.outputDir` + `moduleName` 定位产物）：

```jsonc
{ "path": "SlangAllInOne/SLangCore/Lib/SLang/QT", "name": "SLangQT" }
```

装载链（已实测，2026-11-02）：

1. Front 引用装载三级策略 → 加载 `SlangAllInOne/out/export/SLangQT/SLangQT.module.slb`（json 引用自动重定向 SLB）。
2. 模块 `dllImports`（`static: "slang_qt"`）在 CVM 装配期经 `vm_sys_ffi_static_lib_register` 预载：候选链 `path 原样 → pkg_dir/path → pkg_dir/lib/<平台>/ → pkg_dir/<平台>/ → pkg_dir/`（pkg_dir = 模块导出目录）。
3. `slang/QT.jsonc` 的 `vmDlls` 在模块编译期自动 msbuild `cvm/slang_qt.vcxproj` 并把 `slang_qt.dll` 拷到模块导出目录（即候选链命中位）。
4. 运行期 `SLang.QT.newButton(...)` → `@DllStaticImport` 直调 `slqt_button_create_sl` 等；信号回调经 `FFI.StaticLibrary.createCallback` 重入 SLang。

验收用例：`SlangAllInOne/SLangCore/test/Other/QTTest/`（references 显式引用形态，headless STUB 跑通输出 `slQT smoke test: PASS`）。

## 3. 构建与发布

- 一键构建：`powershell -ExecutionPolicy Bypass -File SLangCore\Lib\SLang\QT\cvm\build-slqt.ps1`（默认 STUB；`-Qt -Qt6Dir <dir>` 切真实 Qt6 后端）。
  产物：`out/export/SLangQT/SLangQT.module.slb`（+ json 调试副本）+ 同目录 `slang_qt.dll`。
- 发布包：标准发布包 `lib\` 仅收 Core/Std/Math（`PackModulesCommand` 三件套）；slQT 与 Render/WebUI/Mysql 同级按需分发——把 `out/export/SLangQT/` 整目录（slb + json + `slang_qt.dll`）拷入发布包 `lib\` 或用户工程引用位即可，CVM 候选链自动命中。
- 换真实 Qt 后端无需改任何配置：`build-slqt.ps1 -Qt` 即产出同名 `slang_qt.dll`（或在 `slang/QT.jsonc` 的 `vmDlls.project` 切到 `slang_qt_qt.vcxproj` 后重编模块）。

## 4. 版本与兼容

- `slang_qt.dll` 符号表在 04 冻结 v1；换 ABI（改名/改签名）须升 slQT 契约版本并同步 `QTFFI.sl` 全部调用点 + 升仓库四端版本（R17）。
- 无独立版本号；跟随仓库四端统一版本（R17，`PROJECTS.md` §7）。

---

*打包与分发已落地（v3，模块形态）。端到端示例见 09，路线图见 10。*
