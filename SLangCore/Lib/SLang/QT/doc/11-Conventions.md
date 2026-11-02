# slQT · 11 版本 / 编码规范 / 术语表

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · **11 规范**）
- 版本：v0.1

---

## 1. 文档与代码同步（R14）

- 任何 slQT 代码/配置/构建改动，**必须有对应 `.md` 承载**（更新本文档集或 `QT.md`），改动完成前文档同步到最新。
- 新增/修改 SL 语法或原生符号，同步更新 04 符号表；契约升版本时同步 10 §1 里程碑状态。

## 2. 版本策略（R17 四端统一）

slQT 不单独设版本号，跟随仓库四端版本（现值以 `PROJECTS.md` §7 为准）。**任一端有改动（含 slQT）即视为整仓版本演进，四处同步 +1**：

| 端 | 锚点 |
|---|---|
| Front | `simple_language/source/CLI/CommandExecutor.cs` `VersionString` |
| C VM | `csimple_lang/src/cli/cli_version.h` `SLVM_VERSION_*` + 构建链版本目录 |
| AllInOne | `SlangAllInOne/SlangAllInOne.csproj` `<Version>` |
| VSCode | `slang_vscode_plugin/package.json` `version` + `package-lock.json` 顶部 `version` |

`slang_qt.dll` 自身随 `SLVM_VERSION_DIR` 部署，无需独立版本；但其**导出符号契约**在 04 冻结 v1，ABI 变更须在 `slqt_types.h` 与本文档标记并升仓库版本。

## 3. 编码规范

### 3.1 文本编码（R16）

- 所有新建 `.sl` / `.jsonc` / `.md` / `.cpp` / `.h` 一律 **UTF-8**（CLI 落盘用 `UTF8Encoding(true)` 带 BOM；其余 Front 产物 UTF-8 无 BOM）。
- `slqt_*` 字符串参数走 UTF-8（`QString::fromUtf8` / `toUtf8`），与 SL `string`（utf8）一致。

### 3.2 命名约定

| 层 | 约定 |
|---|---|
| 原生 C 符号 | `slqt_<域>_<动作>`，全小写下划线（03 §3.1） |
| SL 绑定函数 | `QTFFI.ffi_<域><动作>`（驼峰，单一绑定面） |
| SL 封装类 | `QXxx`（对齐 Qt 类名，如 `QPushButton`）；方法小驼峰（`setText`/`resize`） |
| 句柄 | SL 侧 `Int64 handle`；原生侧 `int64_t` 注册表 key |
| 枚举 | SL `enum`（=Int32）与 `slqt_types.h` 值逐值一致 |

### 3.3 SLang 语法注意

- SLang 标识符大小写不敏感（`setText` 与 `SetText` 等价），但文档与代码统一用小驼峰贴近 Qt 习惯。
- 字符串格式化示例中的 `"...@1" % count` 为示意，实际以 SLang `String` 拼接/格式化语法为准（编写示例时核对 `Std` 库 API）。
- 信号连接示例中的 `createCallback( "Class.method", sig )` 的 method 字符串需为编译期可解析的静态方法全限定名（≤191 字符）。

### 3.4 C++ 侧约束

- `extern "C"` 扁平 ABI，不暴露 C++ 类型/异常到边界。
- 不抛 C++ 异常跨 FFI 边界；错误用返回值（0/false）表达。
- `QPointer` 管理注册表，避免悬空 `QObject*`（03 §3.4）。

## 4. 术语表

| 术语 | 含义 |
|---|---|
| **slQT** | SimpleLanguage 绑定 Qt 的库（类比 PyQt） |
| **FFI** | Foreign Function Interface，SLang 调原生库的机制（`md/project/ffi.md`） |
| **T1 / T2** | 绑定级别：T1=声明式 `@DllStaticImport`；T2=FFI 回调（`createCallback`） |
| **slqt_\*** | `slang_qt.dll` 暴露的 `extern "C"` 扁平函数（契约主体，见 04） |
| **QTFFI.sl** | SL 侧单一绑定面，唯一允许写 `@DllStaticImport` 的文件 |
| **handle** | `int64` 原生对象句柄（`QObject*` 在注册表的 key） |
| **dllImports / static** | `QT.jsonc` 配置：库路径/别名/静态预载名（`slang_qt`） |
| **moc** | Qt 元对象编译器；slQT 首版规避自定义 QObject 子类以省去 moc |
| **R6 / R14 / R16 / R17** | `AGENTS.md` 全局规则：cvm `.c` 双链 / 改动配文档 / UTF-8 / 四端版本统一 |

---

*本文是规范与术语收尾。整个文档集（00-11）即 slQT 的完整设计稿；评审通过后按 10 里程碑实施。*
