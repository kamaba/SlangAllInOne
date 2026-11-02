# slQT · 07 构建系统

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · **07 构建** · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v4（2026-11-02 模块布局对齐：源文件展平到模块根，与 Mysql/Server 同构）
- 关键规则：`AGENTS.md` R6（cvm 内部 `.c` 双链登记——**slQT 不适用**，它是独立 DLL）、R15（模块产物 binary+json）、R16（UTF-8）、R17（四端版本统一）。

---

## 1. slQT 是独立原生工程（不是 cvm 内部）

`slang_qt.dll` 是独立 C 工程（Qt 后端为 C++/Qt），与 `cvm_render_lib`、`cvm_sl_mysql_lib` 同级（各自独立 vcxproj）。它**不**进 `csimple_lang/src/`、也**不**登记 `CSIMPLE_LIB_SOURCES` / `vm_lib` vcxproj（R6 双链仅约束 cvm 自身源码）。

源码在 `SLangCore/Lib/SLang/QT/cvm/src/slang_qt/`，两套后端共享绑定层：

| 文件 | 作用 |
|---|---|
| `slang_qt.h` | `slqt_*_sl` 扁平导出声明（`extern "C"` + `__declspec(dllexport)`） |
| `slang_qt_backend.h` | 后端接口 `slqt_be_*`（stub / Qt 两套实现的切换面） |
| `slang_qt.c` | **绑定层**：句柄注册表 + 信号绑定表，`slqt_*_sl` → `slqt_be_*` |
| `slang_qt_stub.c` | **STUB 后端**：纯 C 无操作（headless 验证链路用） |
| `slang_qt_qt.cpp` | **Qt6 后端**：真实 Qt 实现（lambda 连接，免 moc） |

工程文件：`cvm/slang_qt.vcxproj`（默认 STUB，纯 C，`SLQT_STUB` 宏，输出 `x64\Release\`）与 `cvm/slang_qt_qt.vcxproj`（真实 Qt6，`Qt6_DIR` 指向 Qt 安装根，链接 `Qt6Widgets/Gui/Core`；`/std:c++17 /Zc:__cplusplus /EHsc` 为 Qt 6.8 MSVC 硬性要求，输出独立 `x64\QtRelease\`——两工程产物位隔离，防 vmDlls 重编 STUB 覆盖 Qt 后端）。两者均 `/utf-8`、输出名 `slang_qt`（必须等于 `QT.jsonc` 的 `vmDlls.name`）。

> Qt moc：`slqt_*` 全是扁平 C 函数，Qt 后端用 lambda 连接信号，不定义 `QObject` 子类，**无需 moc**。

## 2. 一键构建（cvm/build-slqt.ps1）

```powershell
# STUB 后端（默认，纯 C，无 Qt）：DLL + SL 模块 + 部署
powershell -ExecutionPolicy Bypass -File SLangCore\Lib\SLang\QT\cvm\build-slqt.ps1

# 真实 Qt6 后端（需本机 Qt6 + VC++）
powershell -ExecutionPolicy Bypass -File SLangCore\Lib\SLang\QT\cvm\build-slqt.ps1 -Qt -Qt6Dir C:\Qt\6.8.0\msvc2019_64
```

脚本三步（MSVC 探测复用 PATH 或本地 VS/SDK）：

1. 原生 DLL → `cvm/obj/slang_qt.dll` 中间位（STUB 用 `cl /LD`；`-Qt` 用 msbuild `slang_qt_qt.vcxproj`）。
2. Front 编译 SLangQT 模块（R15 `--format binary+json`，入口 `QT.sp` 在模块根）→ `SlangAllInOne/out/export/SLangQT/SLangQT.module.slb`。
   **`QT.jsonc` 的 `vmDlls` 同时自动 msbuild `cvm/slang_qt.vcxproj` 并把 DLL 拷到模块导出目录**（Front `ExportVmDllBuildProject` 链路）。
3. 部署：把步骤 1 的 DLL 拷到模块导出目录（pkg_dir 平铺位，FFI 静态库预载候选链命中位）。

## 3. 运行期 DLL 装载链（已实测）

模块 `dllImports`（`"static": "slang_qt"`，`"path": "slang_qt.dll"`）在 CVM 装配期经
`vm_sys_ffi_static_lib_register` 预载，候选序：`path 原样 → pkg_dir/path →
pkg_dir/lib/<平台>/ → pkg_dir/<平台>/ → pkg_dir/`（pkg_dir = 模块导出目录）。
`vmDlls` 的自动部署使 `pkg_dir/slang_qt.dll` 恒命中。缺失时 `@DllStaticImport`
回退 SL 函数体（返回 0/空），封装类降级为空对象——**无 Qt/无 DLL 机器可 headless 编译运行**，仅 UI 不呈现。

## 4. SL 库编译（QT.jsonc → SLangQT.module.slb）

`SLangCore/Lib/SLang/QT/QT.sp` 经 Front 编译（`compile -p ... -e ir --format binary+json`），
产物落 `QT.jsonc` 的 `export.outputDir` = `..\..\..\..\out\export`（模块目录
`out/export/SLangQT/`，Mysql/Server 同款落位）。引用方工程 `references` 直引模块
产物（08 §2），与 ServerTest 引 SLangServer 同款。

> 常规发布不并入 `CompileStdlib`：slQT 与 Render/WebUI/Mysql 同级按需分发——产物 =
> `out/export/SLangQT/` 整目录（slb + json 调试副本 + slang_qt.dll），标准库 `lib\` 仅收 Core/Std/Math 等核心模块。

## 5. 版本同步（R17）

slQT 不是独立版本锚点；仓库任一处改动即四端版本 +1（当前以 `SlangAllInOne/PROJECTS.md` §7 为准）：

| 端 | 锚点文件 |
|---|---|
| Front | `simple_language/source/CLI/CommandExecutor.cs` `VersionString` |
| C VM | `csimple_lang/src/cli/cli_version.h` `SLVM_VERSION_*` |
| AllInOne | `SlangAllInOne/SlangAllInOne.csproj` `<Version>` |
| VSCode | `slang_vscode_plugin/package.json` `version` + `package-lock.json` 顶部 `version` |

---

*构建系统与标准库模块形态同步（v4）。打包与分发见 08，示例见 09。*
