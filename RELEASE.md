# SlangAllInOne 发布策略（RELEASE POLICY）

> 🔥 **本文档是发布渠道的唯一权威**（2026-10-17 用户指令确立，此后所有发版按此执行；
> 2026-10-18 增补四包目录方案，见下）。

## 策略

1. **只发 Native AOT 包**：每个版本的发布产物都是 `-p:PublishAot=true` 打出的
   自包含原生二进制，**目标机无需安装 .NET 运行时**。框架依赖的 Debug 包
   （`package\win32-debug` / `package\linux-debug`）不对外发布，仅本地开发/调试使用。
2. **每次发版两个包，挂同一个 GitHub Release**（缺一不可，双平台必须同发）：
   | 产物 | 目标平台 | 压缩格式 |
   |------|----------|----------|
   | `slang_release_<v>_win-x64.zip` | Windows x64 | zip（顶层文件夹 `slang_release_<v>`） |
   | `slang_release_<v>_linux-x64.tar.gz` | Linux x64 | tar.gz（顶层文件夹同上） |
3. 版本号：`v<x.y.z>` tag + `slang_release <x.y.z>` Release，发布后不可复用。
   发版命令（维护机，工作区根）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\release-slang.ps1 -Version 0.0.4
```

脚本全自动：preflight（tag/Release 查重、token 校验）→ 构建 Windows AOT 包 →
构建 Linux AOT 包（WSL）→ 双包冒烟 → 双压缩 → git 提交 + tag + push →
GitHub Release 附加**两个**资产。参数：`-Draft` / `-SkipBuild`（复用现包重压）/
`-NoCommit` / `-NoPush` / `-Token <t>`（默认取 git 凭据管理器 token，需 `repo` 权限）。

## 本地发布包目录方案（2026-10-18 用户指令；同日三次定稿）

`dotnet publish SlangAllInOne\SlangAllInOne.csproj -c <Debug|Release>`（**零旗标**）
直接生成到 `SlangAllInOne\package\` 下四个平台包目录之一；csproj 已内置形态与
输出目录逻辑（**编译产物按 debug/release 分别落对应平台包的 `lib\`**；平台 =
目标 RID 优先，无 RID 时按宿主 OS：Windows 宿主 → win32-*，WSL/Linux 宿主 →
linux-*）：

| 目录 | 形态 | C VM | lib\ 内容 |
|------|------|------|----------|
| `win32-debug` / `linux-debug` | 框架依赖（.NET 8 Debug 程序集 + pdb，目标机需 .NET 8 运行时） | Debug dll/so + pdb 侧车（**双端可源码调试**；JIT 不编入，解释器语义可调试） | **默认附带一份 json**：`*.module.slb` 主产物 + `*.module.json` 调试副本 + math_lib.dll |
| `win32-release` / `linux-release` | **Native AOT** 单文件 `slang[.exe]`（一体化，零 .NET 依赖） | Release 加固 dll/so（LTO+反调试；**JIT 编入且默认开启**，`--no-jit`/`SL_JIT=0` 关闭） | 仅 `*.module.slb` + math_lib.dll |

- 命名约定：**"win32" 指 Windows 平台包（x64），非 32 位**。
- Debug 包的 json 副本是**配置即默认**（csproj `PackStdModules` → `pack-modules
  --config Debug`），无需任何旗标；Release 包不带 json 与 pdb。
- Release 自动等价 `-p:PublishAot=true`（要退回经典托管发布显式传
  `-p:PublishAot=false`）；RID 缺省按宿主 OS 补 `win-x64`/`linux-x64`——Native AOT
  不能跨 OS 交叉编译，**linux 包必须在 WSL/Linux 侧发布**；显式 `-o` 恒覆盖默认目录。
- 双平台四包一键同建（含依赖编排：linux 包自动补建同配置 win32 包取 `lib\`+`md\`；
  每包布局校验 + 冒烟）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File SlangAllInOne\scripts\build-packages.ps1
#   -Packages win32-debug,linux-release   # 子集（逗号分隔）
#   -NoSmoke                              # 跳过冒烟
```

- WSL 侧冒烟对 Debug 包带 `DOTNET_ROLL_FORWARD=Major`（发行版只有 dotnet-sdk-10，
  net8.0 框架依赖包前滚到 10.x 运行时，官方支持路径）。

## 两个发布包的内容

```
slang_release_<v>/            # 顶层文件夹（zip/tar.gz 解压即得）
├── slang[.exe]                # 统合宿主：Front 编译 + C VM 运行（Native AOT 单文件）
├── bin\                       # C VM 运行时（hardened Release：LTO + 启动反调试，JIT 默认开）
│   ├── Windows: csimple_lang_dll.dll + sqlite3.dll
│   └── Linux : libcsimple_lang_dll.so + libsqlite3.so.0（捆绑，零 LD_LIBRARY_PATH 配置）
├── lib\                       # 系统自带标准库 Core/Math/Std *.module.slb（平铺单目录）
│   └── Windows 另含 math_lib.dll（Math 的 FFI 原生库；Linux 侧不捆绑，见下）
├── plugins\                   # 插件目录（Debug 包含插件 frontend 程序集；插件安装与管理位）
├── test\RefProbe\             # 开箱示例：纯名引用官方库的最小工程（slang run test\RefProbe\RefProbe）
└── md\                        # ~93 篇用户文档
```

> 🔥 **2026-10-18 用户指令：包目录方案**——`module\` 更名 `lib\`（系统自带文件）；
> `modules\`（用户包）与 `plugins\`（插件）为未来 `spm.exe` 包管理器 / 插件管理器
> 预留（`modules\` 未建、按需创建）。决策记录与迁移实录 =
> [md/project/package-layout.md](md/project/package-layout.md)。

> 🔥 2026-10-18 用户指令：`licenses\` **不再随包导出**（csproj `PackThirdPartyLicenses`
> target 与发布脚本注入步骤均已删除）；第三方协议文本真源在仓库
> `csimple_lang\third_party\LICENSES\`（NOTICE.md + 各组件协议全文），需要时从仓库获取。

**官方库直查（2026-10-17 起；2026-10-18 目录更名）**：用户工程 jsonc 的
`references` 直接写官方库名（`{ "path": "Core", "name": "Core.module.json" }`）
即可——Front 编译期与 C VM 运行期都会按 `<slang 目录>\lib\` →
`<slang 目录>\modules\` 顺序按名直查（slb 优先；`modules\` 为未来 spm.exe
安装位，未建自然落空；工程跨盘/包外时 C VM 再兜底 exe 目录），任何放进
`lib\` 的官方库零配置可用。

## 构建链差异（Windows vs Linux）

| 步骤 | Windows | Linux |
|------|---------|-------|
| AOT 编译 | 本机 `dotnet publish -c Release`（csproj 自动 AOT + win-x64） | WSL 内同命令（csproj 自动 linux-x64）；SDK 取 WSL apt 版（Ubuntu 25.10 源只有 SDK 10，与 Windows 侧一致，net8.0 目标兼容已验证） |
| C VM 运行时 | csproj PackCvmRuntime → `build-vm-win.ps1 -Config Release -Harden`（common.ps1 对 Release 树 pin `-DVM_JIT_ENABLE=ON`） | WSL cmake（clang+Ninja，`SLVM_HARDEN=ON -DVM_JIT_ENABLE=ON`）→ `build/ReleaseLinux/libcsimple_lang_dll.so` |
| 标准库打包 | publish 自举（csproj `PackStdModules` target） | `lib\*.slb` 平台无关 → 直接复用 Windows 包产物（csproj 已对 linux RID/非 Windows 宿主门控 Windows 专属 pack target）；Linux 侧冒烟含 `run MiniSmoke` Front 编译 E2E |
| sqlite | 捆绑 `third_party\sqlite\sqlite3.dll` | 捆绑系统 `libsqlite3.so.0`（C VM 链接系统 sqlite3） |
| 宿主动库加载 | `SetDllDirectory(bin)` | `NativeLibrary` DllImportResolver 按绝对路径 dlopen + sqlite 预载（见 `Backend/CvmBackend.cs`） |
| 原生 pdb | csproj `CopyOutputSymbolsToPublishDirectory=false`（见下方 pdb 复活实录） | 同（Linux 侧 ILC 默认 StripSymbols） |

## Linux 包已知限制

- **glibc ≥ 2.43**（构建机 Ubuntu 25.10；更旧的发行版需自行重编 C VM）。
- **Math 的 FFI 不可用**：`math_lib.dll` 是 Windows 产物（矩阵等 FFI 数学调用失败），
  包内不携带；Math 模块本身正常加载。
- 插件 `@csharp_mono`（mono 运行时）与 Windows-only FFI 同理不可用。

## 排障实录（发布链）

- **slang.pdb "删完复活"（2026-10-18 定案）**：ILCompiler 包的 `_CopyAotSymbols`
  target（`AfterTargets="Publish"`，受 `CopyOutputSymbolsToPublishDirectory` 控制，
  默认 true）把 `bin\<C>\net8.0\<rid>\native\slang.pdb`（~48MB）复制进包，且执行
  顺序晚于工程挂在 Publish 后的 Trim targets——先删后复制即"复活"；`DebugType=none`
  只挡住新 pdb 生成、挡不住旧缓存复制，`StripSymbols` 仅对非 Windows 平台生效。
  **正解 = csproj `CopyOutputSymbolsToPublishDirectory=false`**（`_CopyAotSymbols`
  整体不跑）。release-slang.ps1 仍保留归档前兜底删除。
- **NETSDK1150（自动 AOT 化配套）**：csproj 内部设置的 RID 不传导给 ProjectReference
  的设计时求值，自包含宿主引用框架依赖的 Front Exe 被 SDK 拦截；工程内
  `ValidateExecutableReferencesMatchSelfContained=false`（仅 AOT 场景）放行——宿主
  从不运行 SimpleLanguageFront.exe（部署件被 Trim 删除），AOT 链接消费的 IL 与
  FDD/SC 构建完全一致。
- **Linux 裸名 apphost**：Linux apphost 无 `.exe` 后缀（裸名 `SimpleLanguageFront`），
  v0.0.3 linux 包曾带过；TrimReleasePackage 与 release-slang.ps1 forbidden 列表
  已补裸名条目。

## 验证记录

| 版本 | 双包结果 |
|------|----------|
| v0.0.3（2026-10-17） | ✅ 首个双平台 AOT 版：win zip 8.2MB + linux tgz 8.1MB（同一 Release 两资产）；双平台冒烟全过——win run-disk Std/Math exit 0、linux run-disk Std exit 0、linux `run MiniSmoke`（Front 编译→SLIR 内存直传→C VM 执行 `_main_`）exit 0。发布链修复实录：① wsl 调用 stdout 混入返回值导致预检假失败（`Out-Host` 修）；② AOT obj 缓存复活 slang.pdb（归档前兜底删除，根因后于 2026-10-18 定位见上）；③ Linux 系统方法全挂 error_code=-13——C VM 注册表走 `dlsym(dlopen(NULL))` 查主程序全局符号表，.NET 默认 `RTLD_LOCAL` dlopen 使 `.so` 符号不可见，宿主改 `RTLD_GLOBAL` dlopen（对齐 exe `-rdynamic` 语义，`Backend/CvmInterop.cs` + `CvmBackend.cs`）；④ 测试工程 jsonc 平台校验硬编码 win64，Linux 冒烟需 `SL_FORCE_RUN=1`（既有预期差异） |
| 四包方案（2026-10-18） | ✅ `build-packages.ps1` 全绿：win32-debug 87.4MB（FDD+双端 pdb）/ win32-release 17MB（AOT，pdb 已从源头根除）/ linux-debug 72.8MB（冒烟 `DOTNET_ROLL_FORWARD=Major`）/ linux-release ~17MB（裸名 apphost 已清理）；win32-release dll 实测 `SL_JIT` 符号在 + `--jit-stats` 输出正常（JIT 编入且默认开启） |
| 目录更名 module→lib（2026-10-18） | ✅ 四包重建全绿，布局实测：`module\` 消失、`lib\` 就位（debug 7 件=3 slb+3 json+math_lib；release 4 件）、debug 包 `plugins\` 含 SLCSharpMono/SLJavaHotspot frontend dll+pdb；RefProbe 端到端（references 纯名 `Core`/`Std` → `<exe>\lib\` 直查 → 编译 → C VM 运行）win32-release 与 win32-debug 均 exit 0；修复 release-slang.ps1 两处失效的 `examples\RefProbe` 历史路径（真源在 `SLangCore\test\Other\RefProbe`，此前靠 Test-Path 静默跳过从未生效） |
| 默认目录改 package\debug\|release（2026-10-18 二次调整，已废止） | ⛔ 方案当日被用户三次指令推翻：改回四包目录 `package\{win32\|linux}-{debug\|release}`（见下一行），无发布产物残留该布局 |
| 默认目录定稿四包布局（2026-10-18 三次定稿） | ✅ 零旗标 publish 实测：`-c Debug` → `package\win32-debug`（lib\ = 3 slb + **3 json 副本** + math_lib，plugins\ 插件程序集在位）、`-c Release` → `package\win32-release`（根仅 slang.exe，lib\ 仅 slb）；双包 `run-disk Std.module.slb` 冒烟均 exit 0；build-packages.ps1 回归零旗标（与 csproj 默认同源），WSL 侧同命令落 `package\linux-<config>` |
| CompileStdlib 直通包目录（2026-10-18 增补） | ✅ `CompileStdlib core`（等价 VS F5 Debug 跑 Core 预设）实测：产物升级为 slb+json 双产物（内置 `--format binary --export-json`，对齐 R15）并自动同步四包——`[SYNC] Core -> package\{win32,linux}-{debug,release}\lib\`，debug 目录带 json、release 仅 slb、win32-\* 另带 math_lib.dll；冒烟 exit 0。排障实录：用户 VS 调试 CompileStdlib 与 publish 并发编译 Core 时，win32-debug\lib 曾残留 `Core.module.slb1/json1` 异常名文件（正常名被占导致包内 Core"消失"的假象；正常链路复现实验证明工具本身不产生该命名，残留已清理） |
