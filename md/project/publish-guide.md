# SLang 工程发布指南（slang publish）

> 权威文档 · 2026-10-21 首版。类比 C# 的 `dotnet publish`：**一次发布产出两种形态的产物**——
> ① 直接执行的**应用 exe**；② 用 `slang run <路径>.slb` 启动的**SLB 模块包**（2026-10-22 起 `slang run` 专指运行模块产物，编译+运行用 `slang <工程>`）。
> 配置面 = 工程 jsonc 顶层 `publish` 段（类比 csproj 的发布属性）；执行面 = 宿主命令 `slang publish`。
>
> 🔥 **发布宿主 = `SlangAllInOne\out\host\slang.exe`**（独立构建输出，见 §8；VSCode 配置见 §9）。

## 1. 三十秒上手

```powershell
cd d:\project\lang

# 编译 + 发布（配置全缺省：mode=both，输出 <工程目录>\publish\）
SlangAllInOne\out\host\slang.exe publish SlangAllInOne\SLangCore\test\Other\NullFastTest\ProjectTest
# （开发仓内：dotnet run --project SlangAllInOne\SlangAllInOne.csproj -- publish <工程>）

# 运行产物
.\NullFastTest\publish\release\NullFastTest.exe              # ① 应用 exe：双击/命令行直接执行（release 缺省；--cvm Debug → publish\debug\）
SlangAllInOne\out\host\slang.exe run .\NullFastTest\publish\release\NullFastTest.module.slb   # ② slb：slang run 启动
```

## 2. jsonc `publish` 段（配置面）

工程 `<名>.jsonc` 顶层新增 `publish` 段（不声明 = 全缺省，Front 解析承载见
`ProjectConfig.PublishSection`，值校验在宿主 `PublishCommand`）：

```jsonc
{
  "project": { "name": "MyApp" },
  "export":  { "moduleName": "MyApp", "format": "binary" },
  "publish": {
    "mode":       "both",     // 产物形态："exe" | "slb" | "both"（缺省 both）
    "outputDir":  "publish",  // 发布目录（相对 jsonc 所在目录；缺省 "publish"）
    "config":     "Release", // C VM 构建树（exe 模板来源；缺省 Release）
    "includeLibs": true,      // 是否携带 lib\ 标准库（缺省 true）
    "libs":       [],         // 精简携带清单（空 = Core/Std/Math 全量；含 Math 自动附带 math_lib.dll）
    "gui":        false       // GUI 应用形态（缺省 false 控制台 exe；见 §5.1）
  }
}
```

| 字段 | 类型 / 取值 | 缺省 | 说明 |
|------|------------|------|------|
| `mode` | `exe` / `slb` / `both` | `both` | 产物形态。`exe` = 仅应用 exe；`slb` = 仅模块包；`both` = 两者 |
| `outputDir` | 相对/绝对路径 | `"publish"` | 发布根目录（相对 jsonc 所在目录）。**实际产物落 `<outputDir>\{debug|release}\` 配置子目录**（2026-10-22 发布规则，两型并存；仅本配置子目录清空重建） |
| `config` | `Debug` / `Release` | `Release` | exe 载荷模板取 `csimple_lang\build\{config}\bin\csimple_lang.exe`（JIT/加固属性随该树；发布包内则取 `<slang>\bin\`，不中回落另一配置树） |
| `includeLibs` | bool | `true` | 是否把官方标准库拷进发布目录 `lib\`。应用引用 Core/Std/Math 时必须为 true |
| `libs` | string[] | `[]`=全量 | `includeLibs=true` 时生效；如 `["Core","Std"]` 只带这两件（Math 附带 `math_lib.dll`）。缺库仅 `[WARN]` 不中断（工程可能不引用它） |
| `gui` | bool | `false` | GUI 应用形态：true 时发布把 exe 的 PE 子系统从 Console(3) 补丁为 Windows(2)——启动/双击**不再弹 cmd 窗口**（WebUI 浏览器窗等 GUI 应用用，见 §5.1）。CLI `--gui` 强制开 |

产物命名：`export.moduleName` > `project.name` > `.sp` 文件名，逐级回退。

## 3. 命令行（执行面）

```
slang publish <projectPath> [--mode exe|slb|both] [--dest <dir>] [--cvm Debug|Release]
              [--no-libs] [--gui] [-O0..-O3]
```

| 旗标 | 覆盖 | 说明 |
|------|------|------|
| `--mode` | jsonc `publish.mode` | 产物形态（CLI 优先） |
| `--dest` | jsonc `publish.outputDir` | 发布目录（绝对/相对 CWD） |
| `--cvm` | jsonc `publish.config` | exe 模板的 C VM 构建树（**显式传参才覆盖**，不传走 jsonc） |
| `--no-libs` | jsonc `publish.includeLibs` | 不携带 `lib\` 标准库 |
| `--gui` | jsonc `publish.gui` | GUI 形态强制开（exe 无 cmd 窗口；关闭请去掉 jsonc `gui` 段，见 §5.1） |
| `-O0..-O3` | Front 优化级 | 编译期参数，同 `slang compile` |

## 4. 发布目录布局

```
<publishRoot>\
├── debug\                   # 配置子目录（--cvm Debug）：布局同 release，模板取 Debug 树
└── release\                 # 配置子目录（--cvm Release 缺省）：每次发布清空重建（仅本子目录）
    ├── MyApp.exe            # mode=exe/both：应用 exe（载荷附着式，见 §5）
    ├── MyApp.module.slb     # mode=slb/both：模块包（slang run <此文件> 启动）
    ├── <Ref>.module.slb     # 引用 stage：moduleReferences 非系统库引用平铺拷入
    │                        #（C VM 引用回退链 basename 直查命中；如 SLangServer）
    ├── lib\                 # 关联件统一目录（布局规则 2026-10-22 平台细分）
    │   ├── Core.module.slb  # includeLibs=true：标准库 slb 平铺（平台无关）
    │   ├── Std.module.slb
    │   ├── Math.module.slb
    │   └── windows\         # 平台子目录：本平台原生库（windows/linux/macos/android/ios
    │       ├── sqlite3.dll  #   承载 .dll/.so/.dylib/.lib/.a 等——一个发布目录可承载
    │       └── math_lib.dll #   多平台运行体，运行时按当前平台查找（C VM
    │                        #   sl_platform_dir_name；平铺 lib\ 为兼容位）
    └── plugins\             # 工程声明了插件时：Front 导出的 plugins\<id>\ 整目录拷贝
```

> 🔥 **发布规则（2026-10-22 用户定稿）**：① 发布分 **debug/release 两型**，落
> `<outputDir>\{debug|release}\` 并存（同工程可同时保有 Debug 调试版 / Release
> 发布版，仅本配置子目录清空重建）；② **lib\ 平台细分**——原生库按平台落
> `lib\{windows|linux|macos|android|ios}\`（slb 仍平铺，平台无关），一个发布
> 目录可承载不同平台运行体，运行时按 `sl_platform_dir_name()` 查当前平台
> 子目录（平铺 lib\ 为兼容位）；③ **引用模块自动 stage**——moduleReferences
> 非系统库引用平铺拷入发布目录（内嵌相对路径在发布布局必然错位，装载期
> 静默跳过曾致 ServerP1Test 全线失效）。决策记录与机制 =
> [package-layout.md](package-layout.md) §六。

## 5. 应用 exe 的实现形态：载荷附着式（SLVMAPP1）

应用 exe = **csimple_lang.exe 副本 + 尾部附着的 SLB 载荷**，文件尾布局（trailer 固定 16 字节，小端）：

```
[ 原始 exe 字节 ][ SLB payload ][ payload_size: u64 LE ][ "SLVMAPP1" ]
```

- **写入端**：宿主 `Publish/PublishCommand.cs` `AttachPayload`（UTF-8 magic + `BitConverter` u64）。
- **读取端**：C VM `csimple_lang/src/cli/cli_app_payload.{h,c}`——独立 exe 的 `main()` 启动时自检尾部：
  magic 命中 → 回读 payload 走**内存二进制通道**执行（`cli_cmd_run_memory_binary`，与
  宿主裸工程路径 `slang <工程>` 的内存链路同一条执行路径）；未命中（普通 csimple_lang.exe）→ 原样 CLI 分派，**零行为变化**。
  两侧字段序必须逐字节镜像（同 R2 思想），载荷上限 1 GiB（坏 trailer 防御）。
- **运行语义**：
  - `base_dir` = exe 所在目录（`lib\*.module.slb`、FFI dllImports、`plugins\` 相对它解析）；
  - argv 与 `run` 子命令同构：`--debug` 等选项照常、裸参数与 `--` 之后进 `Project._inputArgs`；
  - 默认 `--no-banner`（应用不打 VM banner）；
  - 🔥 **收尾 pause（2026-10-22）**：exe 执行结束退出前 `system("pause")` 等键
    （双击直跑防窗口闪退；仅 Windows 载荷模式，`slang run`/cli_main 链路零影响）。
    逃生门：环境变量 `SL_NO_PAUSE`（任意值）跳过；stdin 重定向（`< NUL` / 管道）
    时 pause 本就立即返回，自动化批跑不卡死。
- 仅独立 exe 走检测；dll 宿主（P/Invoke `cli_main`）与 wasm 不经过，测试链路零影响。

### 5.1 GUI 应用形态（`publish.gui: true`，2026-10-29）

WebUI（浏览器窗）、渲染窗口等 **GUI 应用**发布时不想要背后的 cmd 窗口——
jsonc `publish.gui: true`（或 CLI `--gui` 强制开）：

- **机制**：`PublishCommand.PatchSubsystemWindows` 发布时把 exe 的 PE
  Subsystem 字段 Console(3)→Windows(2) 一次写入（模板不动；入口 RVA 不变，
  Windows 加载器只跳 AddressOfEntryPoint，子系统字段只决定进程创建时是否
  自动分配控制台——成熟补丁做法）。缺省 false = 原控制台形态，零行为变化。
- **C 侧配套**（`cli_app_payload.c`，仅 app 载荷模式，`slang run`/cli_main 零影响）：
  - 双击启动（无控制台）：静默跑（`printf` 落 NULL 句柄即丢弃，不崩）；收尾
    pause **跳过**（GUI 进程里 `system("pause")` 反而会新弹一个 cmd 窗再闪退）；
  - 从终端启动：`AttachConsole(ATTACH_PARENT_PROCESS)` 挂回父控制台并
    freopen 重绑 std 流——**日志照常可见**，GUI 形态与可调试性兼得；
  - `Console.println` / `SL_NO_PAUSE` / stdin 重定向语义均不变。
- **验证链**（WebUITest，`gui: true` 已配）：发布后查 `PE subsystem = 2`；
  终端跑 exe 日志可见 + 浏览器窗弹出 + 套件 `RESULT: PASS`；双击无 cmd 窗。

## 6. 流程与依赖

```
slang publish <工程>
  ├─ ① Front 编译（--format binary+json，R15；slb 主产物 + json 调试副本留工程 export 目录）
  ├─ ② 定位 C VM exe 模板：<slang>\bin\csimple_lang.exe（发布包布局，PackCvmRuntime 随包携带）
  │      → 回落 csimple_lang\build\{publish.config}\bin\ → 另一配置树
  ├─ ③ slb 拷贝 / exe 载荷附着 + lib\（标准库平铺 + lib\<平台>\ 原生库）+ 引用 stage + plugins\
  └─ ④ 本配置子目录（debug\|release\）清空重建（publish 根与另一配置保留）
```

前提：C VM 对应配置树已构建（`build-vm-win.ps1 -Config Release`）。**注意**：exe 模板与
`build\{config}\bin` 实时对应——C VM 更新后需重建对应树再发布，否则应用 exe 仍是旧 VM。

## 7. 相关文件索引

| 位置 | 角色 |
|------|------|
| `SlangAllInOne/Publish/PublishCommand.cs` | 宿主发布命令（布局组装 + 载荷写入） |
| `SlangAllInOne/Program.cs` | `publish` 分派、`run` 的 `*.slb/*.module.json` 智能分派 |
| `simple_language/source/Project/ProjectConfig.cs` | `PublishSection`（jsonc publish 段承载） |
| `simple_language/source/Project/ProjectJsoncLoader.cs` | `publish` 段解析 |
| `csimple_lang/src/cli/cli_app_payload.{h,c}` | exe 载荷检测与执行（C 侧） |
| `csimple_lang/src/main.c` | 载荷优先分支（检测命中不进 CLI 分派） |
| `csimple_lang/src/cli/cli.c` | `cli_parse_run_arguments`（run 与 app 模式共用解析） |
| `csimple_lang/md/cli.md` | C VM 侧应用载荷模式说明 |

## 8. 发布宿主：`SlangAllInOne\out\host\slang.exe`（独立构建输出）

发布/CLI 用宿主走**独立构建输出目录**，不与 `bin\Debug\net8.0` 混用：

- **原因**：VSCode 插件 LSP 是常驻进程（`slang lsp --stdio`，宿主 = `bin\Debug\net8.0\slang.exe`），
  它锁住该目录的 `slang.exe / slang.dll / SimpleLanguageFront.dll`，被杀后 VSCode 秒级自动重启——
  常规 `dotnet build` 在编辑器开着时必然 MSB3027 失败，`bin\Debug` 的宿主长期停在旧版。
- **out\host 布局**：`slang.exe`（最新构建）+ `lib\`（Core/Std/Math slb + json + math_lib.dll，
  Front 编译用户工程时官方库直查 `<exe>\lib\` 命中）。
- **刷新命令**（改宿主代码后执行一次）：

```powershell
cd d:\project\lang
dotnet build SlangAllInOne\SlangAllInOne.csproj -c Debug -o SlangAllInOne\out\host
```

## 9. VSCode「运行和调试」一键发布（launch.json）

`launch.json` 为用户保护文件，需手动把以下两条配置粘进 `configurations` 数组
（建议放在「通用入口」两条之后）。`type=node-terminal` = 集成终端执行（无断点），
在下拉里选「发布 SLang: …」→ ▶ 即发布，产物目录打印在终端：

```jsonc
// ════════ 发布（slang publish → md/project/publish-guide.md；out\host 宿主见 §8）════════
{
    // 发布"当前工程"：${command:slang.debugProgram} 同「调试 SLang: 当前工程」的定位逻辑
    // （活动编辑器所在 .sp；无 SLang 工程时弹文件选择）。产物 = <工程>\publish\
    "name": "发布 SLang: 当前工程",
    "type": "node-terminal",
    "request": "launch",
    "command": "& \"${workspaceFolder}\\SlangAllInOne\\out\\host\\slang.exe\" publish \"${command:slang.debugProgram}\" --no-banner",
    "cwd": "${workspaceFolder}"
},
{
    // 发布指定工程（示例 = NullFastTest；复制本条改 command 里的工程路径即可发布任意工程）。
    // CLI 覆盖 jsonc publish 段：--mode exe|slb|both / --dest <目录> / --cvm Release / --no-libs
    "name": "发布 SLang: NullFast（示例，改路径即任意工程）",
    "type": "node-terminal",
    "request": "launch",
    "command": "& \"${workspaceFolder}\\SlangAllInOne\\out\\host\\slang.exe\" publish \"${workspaceFolder}\\SlangAllInOne\\SLangCore\\test\\Other\\NullFastTest\\ProjectTest\" --no-banner",
    "cwd": "${workspaceFolder}"
}
```

> 发布产物跑法：`<Module>.exe` 双击/终端直跑；`slang run <publish>\<Module>.module.slb`。
> F5 调试发布产物暂不适用（载荷 exe 走内存二进制通道，SLDP 调试会话不开放，设计 §7.1）。
