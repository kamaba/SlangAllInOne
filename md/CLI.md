# CLI 指令说明（slang / spm / csimple_lang）

> 本文按当前实际实现编写（2026-11-11 校准）。旧 `cx` 命令体系未实现，已由
> `slang` 宿主 + 独立 `spm` 包管理器取代；文末附历史对照。
>
> 三个可执行文件（发行包布局见 `md/project/package-layout.md`）：
>
> | 程序 | 来源 | 职责 |
> |------|------|------|
> | `slang.exe` | `SlangAllInOne`（内嵌 Front 编译器 + C VM 进程内驱动） | 编译、运行、发布、脚手架、LSP、stdlib 打包 |
> | `spm.exe` | `Project\Spm`（2026-10-30 自 `slang spm` 子命令独立成工程） | 包/插件管理、registry 检索、admin 平台 sync |
> | `csimple_lang.exe` | `csimple_lang`（C VM） | 运行模块包（`bin\csimple_lang_dll.dll` 通常由 slang 进程内调用，exe 形态用于调试） |

***

## 1. slang（宿主主入口）

### 1.1 命令一览

| 命令 | 说明 |
|------|------|
| `slang <project>` | **裸工程路径 = 编译+运行一体化**（内部词 projectrun）：Front 编译 + C VM 运行。缺省 `--export-mode memory`（SLB 不落盘直传 VM）；`--export-mode output\|temp` 时先磁盘导出再从盘运行 |
| `slang compile <project>` | 仅编译（Front 进程内）。缺省导出到 jsonc 配置的 export 目录 |
| `slang run <module>` | 只运行**已编译**模块包（`.module.slb` / `.module.json`），不编译。裸模块包文件可省略 run：`slang Foo.module.slb` |
| `slang run-disk <module>` | `run` 的兼容别名 |
| `slang info <module>` | 经 C VM 显示模块元数据（版本/依赖/符号表等） |
| `slang publish <project>` | 发布（dotnet-publish 风格）：`both`（缺省）= 可运行 app exe（payload 附加 csimple_lang.exe + sqlite3.dll + lib\）+ `<Module>.module.slb`；`exe` / `slb` 只出其一。布局走 jsonc `publish` 段或 `--dest` |
| `slang new project <Name> [-p <dir>]` | 脚手架：`<dir>\<Name>\` 下成套落盘 `Name.sp / Name.jsonc / Name.sl / Name.md`（UTF-8 BOM，含 guide） |
| `slang new class <Name> [-p <dir>]` | 在 `<dir>` 找到的 `.sp` 旁创建 `<Name>.sl` 并登记进 jsonc |
| `slang lsp [--stdio]` | 内嵌 LSP 3.17 服务器（stdio JSON-RPC；VSCode 插件消费：诊断推送 + 符号补全） |
| `slang lsp-compile` | LSP 专用诊断子命令（新进程单次编译，结构化 JSON 到 stdout；`slang lsp` 每轮自动调用，一般不直接用） |
| `slang ffi-check <contract> [--dll <lib.dll>]` | FFI 契约独立校验（`.slffi.json`）：schema 自检（version / functionList / structs / callbacks）+ 可选 DLL 导出表逐符号比对；失败 exit 1（CI 友好） |
| `slang pack-modules [--dest <dir>] [--config Debug\|Release]` | 编译标准库（Core → Std → Math）打包到 `<dest>\out\export\`（镜像仓库布局，package references 原样解析）；Debug 保留 `.module.json` + `.slb`，Release 只留 `.slb`（+ `math_lib.dll`）。dotnet publish 自动执行 |
| `slang pack-docs [--dest <dir>]` | 把用户向文档（syntax / lib / project / log / plugins + 入门文档）拷入 `<dest>\md\`（跳过内部 `md\ai\`、`md\vm\`）。dotnet publish 自动执行 |
| `slang spm <sub>` | **spm 已独立为 spm.exe**（slang 同目录）：仅打印兼容提示并 exit 2，请直接 `spm <命令>` |
| `slang version` | 显示宿主 / Front / C VM 三端版本（四端统一版本号，见 PROJECTS.md §7） |
| `slang help`（或无参数） | 显示帮助 |

### 1.2 通用选项

| 选项 | 说明 |
|------|------|
| `-p, --project <path>` | 工程路径（目录 / `.sp` / `.jsonc`；`.sp` 可省——jsonc-only 工程按非 main 入口/库模块编译） |
| `--export-mode <output\|temp\|memory>` | 前后端交接三态：output = jsonc 配置的导出目录（compile 缺省）；temp = `<cwd>\_temp\<module>\`；memory = 不落盘，SLB 直传 VM（裸工程编译+运行缺省） |
| `--format <json\|binary\|binary+json>` | 导出格式：binary = 仅 SLB；json / binary+json = SLB（必写）+ `.module.json` 调试副本 |
| `-O0..-O3` | Front 优化级别 |
| `-t, --test` | 传 `-test` 给 C VM（VM 端入口 switch 暂未实现，两种路径均跑 `_main_`） |
| `--no-banner` | 关闭横幅 |
| `--force-run` | 跳过 C VM 硬性平台检查 |
| `--debug` | C VM 调试模式（详细 trace） |
| `--strict-plugins` | 插件禁用升级为 C VM 错误 |
| `--debug-server=<port>` | `run <module>` / 裸工程 `--export-mode output\|temp`：在 `127.0.0.1:<port>` 启动 SLDP 调试服务器（NDJSON over TCP，VSCode DAP 适配器连接） |
| `--cvm <Debug\|Release>` | 使用的 C VM 构建树（缺省 Debug；打包布局下从 `<app dir>\bin\` 取） |
| `--mode <exe\|slb\|both>` | publish 产物模式覆盖（jsonc `publish.mode`） |
| `--dest <dir>` | publish 输出目录覆盖（jsonc `publish.outputDir`）；pack-modules 的打包根 |
| `--no-libs` | publish 不携带 `lib\` 标准库（覆盖 jsonc `includeLibs`） |
| `--gui` | publish 强制 GUI 形态（exe PE 子系统 Console→Windows，无 cmd 窗口） |
| `-- [args...]` | `--` 之后的参数透传给 `Project._inputArgs`（运行期程序参数） |

### 1.3 示例

```text
slang new project MyApp                                        # 脚手架
slang SlangAllInOne\SLangCore\test\BaseTest\ProjectTest        # 编译+运行（内存交接）
slang MyProject --export-mode temp                             # 临时目录导出后运行
slang MyProject -- arg1 arg2                                   # 程序参数透传
slang compile MyProject --format binary+json                   # 仅编译，SLB+json 副本
slang run publish\MyApp.module.slb                             # 只运行编译产物
slang publish MyProject --mode exe --cvm Release               # 发布 GUI-less exe
slang info out\export\ProjectTest\ProjectTest.module.json      # 模块元数据
slang pack-modules --config Release                            # 标准库打包
```

***

## 2. spm（包/插件管理器，独立 CLI）

`spm` 于 2026-10-30 自宿主子命令独立为 `Project\Spm` 工程，部署位 = `slang.exe`
同目录，直接驱动。安装位约定：

- 包（module 编译产物）→ 工程侧 `<工程>\modules\<名>\`；语言侧 `<lang>\modules\<名>\`（`-g` 全局共享）
- 插件（plugin.jsonc + 原生库 + 前端的多层扩展）→ `<lang>\plugin\<id>\`（全局共享）

### 2.1 包命令

| 命令 | 说明 |
|------|------|
| `spm install <url\|package> [--registry <url>] [-g]` | url 直拉 zip 解压；按名安装三级查找：① 工程 `modules\` 已存在 → 跳过 ② `<lang>\modules\` 命中 → 移入工程位 ③ 服务器 `GET /api/packages/<名>`（回落 `<reg>/<名>.json`）下载 meta 链接或 `<reg>/<名>.zip` |
| `spm search <keyword>` | 按名查包（先精确命中再全量索引过滤 name/description） |
| `spm list`（`ls`） | 列出工程位与语言侧已装包 |
| `spm outdated`（`check`） | 本地 `modules\<名>\spm.json` 版本与服务器对比 |
| `spm remove <package> [-g]`（`uninstall`） | 删除包目录（`-g` = 语言侧） |
| `spm config registry [<url>]` | 查看/设置全局 registry（存 `<lang>\spm.json`） |

registry 解析优先级：`--registry` 参数 > 工程 jsonc `"spm"."registry"` 段 > `<lang>\spm.json` 全局。

### 2.2 插件命令

| 命令 | 说明 |
|------|------|
| `spm plugin list` | 列出已装插件（读 `plugin\<id>\plugin.jsonc`） |
| `spm plugin search <id>` | 服务器查插件元数据（`GET /api/plugins/<id>`） |
| `spm plugin probe <id>` | 环境探测：插件支持平台 vs 当前 OS/arch |
| `spm plugin install <id\|url> [--registry <url>]` | 下载插件 zip 解压到 `<lang>\plugin\<id>\` |
| `spm plugin remove <id>` | 删除插件目录 |

### 2.3 sync（admin 平台同步，md5 校验）

```text
spm sync [core|vscode|plugin|package|all ...] [name] [--server <url>]
```

对比 admin 平台 md5 与本地缓存，不一致即重新下载（下载先验 md5 再解压）：
`core`（本体）→ 合入 `<lang>\`；`vscode` → `%USERPROFILE%\.vscode\extensions\`；
`plugin` → `<lang>\plugin\<id>\`；`package` → `<lang>\modules\<名>\`。缺省 `all`；
plugin/package 接受名字过滤（`spm sync plugin echo`）。缓存：`<lang>\spm-cache\`。
服务器按序尝试（不可达/404 → 下一个），全部失败时逐服务器列出失败原因。

服务端地址配置：`spm config server [<ip[:port]|url> ...]`（裸 IP 缺省端口 35221；
存 `<lang>\spm.json` 的 `servers` 列表；未设置用内置默认表）。
sync 服务器解析优先级：`--server` > `spm config server` > 内置默认。

### 2.4 声明式依赖（工程 jsonc `references` type=module）

工程 jsonc 的 `references` 支持声明式模块依赖：
`{ "type": "module", "name": "SLangWebUI", "channel": "official|git|url", "url": "", "version": "0.0.53" }`。
编译（`slang compile` / `slang publish`）装载引用前自动执行 **module 检查机制**，查找顺序：
① 工程 `modules\<名>\` 已存在且版本一致（url 渠道未声明 version 时目录存在即可）→ 跳过后续
所有操作；② 解析目标下载地址后对比全局 `<exe>\modules\<名>\` 清单，url + 版本均一致 →
**复制全局模块到工程 `modules\<名>\`**（不下载）；③ 未命中按渠道下载**指定版本**到工程
`modules\<名>\`（official = registry 按 name+version 检索 / git = 仓库 tag 归档 / url = 直链）；
④ 下载失败降级本地已有版本（Warning，工程位优先）或中止编译（Error，后续阶段跳过、产物不导出）。
语法与语义详见 `md/project/project-config-jsonc-guide.md` §4.9。

***

## 3. csimple_lang（C VM 运行时）

发行包中 C VM 以 `bin\csimple_lang_dll.dll` 形态由 slang 进程内驱动（内存/磁盘两种
装载通道）；`csimple_lang.exe` 独立 CLI 主要用于调试与 CI：

| 命令 | 说明 |
|------|------|
| `csimple_lang run <module.slb\|module.json> [选项] [-- args...]` | 运行模块包（磁盘装载按后缀认双通道；裸文件路径 = run 简写） |
| `csimple_lang info <module>` | 显示模块元数据 |
| `csimple_lang plugin list\|info <module>` | 模块的插件清单 / 插件详情 |
| `csimple_lang version`（`--version` / `-v`） | 版本信息 |
| `csimple_lang help`（`--help` / `-h`） | 帮助 |

run 常用选项：`--no-banner`、`--force-run`、`--debug`、`--strict-plugins`、
`--debug-server=<port>`、`--log <path>`、`-test`；`--` 之后为程序参数。
Debug 构建无命令时缺省进入 run。

***

## 4. Front 内部命令面（开发参考）

Front 编译器（`SimpleLanguageFront`，内嵌于 slang.exe）自带的命令面在开发构建中
直接可用：`compile`（`c`/`build`/`b`）、`export`（`e`，仅导出 IR）、`clean`、
`version`、`help`；选项含 `-e ir`、`--export-mode`、`--format`、`--token`、
`--lang <zh|en>` 等。发行形态下这些能力经由 `slang compile` / `slang publish`
暴露，`run` / `new` 归宿主（Front help 中的说明与此一致）。

***

## 5. 旧 `cx` 命令体系对照（历史）

| 旧 cx 设想 | 现状 |
|------------|------|
| `cx init <pkgname>` | `slang new project/class`（原生脚手架） |
| `cx install/list`（包管理） | 独立 `spm.exe`（§2） |
| `cx repl` | 未实现 |
| `cx run <file.cx>` | `slang <project>`（编译+运行）/ `slang run <module>`；脚本扩展名为 `.sl` |
| `cx build` | `slang compile`（Front 进程内编译） |
| `cx test` | 未实现为独立命令（测试工程经 `slang <project>` 运行） |
| `cx fmt` | 未实现 |
| `cx gui` | 未实现为独立命令（GUI 编辑器为独立产品 SLangCodeEditor） |

新增命令或参数变更时，需同步更新本文档与 `SlangAllInOne\Program.cs` 的
`PrintHelp()`，保持文档与行为一致。
