# SlangAllInOne 发布策略（RELEASE POLICY）

> 🔥 **本文档是发布渠道的唯一权威**（2026-10-17 用户指令确立，此后所有发版按此执行）。

## 策略

1. **只发 Native AOT 包**：每个版本的发布产物都是 `-p:PublishAot=true` 打出的
   自包含原生二进制，**目标机无需安装 .NET 运行时**。经典 .NET 依赖包
   （`package\release` / `package\debug`）不再对外发布，仅本地开发/调试使用。
2. **每次发版两个包，挂同一个 GitHub Release**（缺一不可，双平台必须同发）：
   | 产物 | 目标平台 | 压缩格式 |
   |------|----------|----------|
   | `slang_release_<v>_win-x64.zip` | Windows x64 | zip（顶层文件夹 `slang_release_<v>`） |
   | `slang_release_<v>_linux-x64.tar.gz` | Linux x64 | tar.gz（顶层文件夹同上） |
3. 版本号：`v<x.y.z>` tag + `slang_release <x.y.z>` Release，发布后不可复用。
   发版命令（维护机，工作区根）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release-slang.ps1 -Version 0.0.4
```

脚本全自动：preflight（tag/Release 查重、token 校验）→ 构建 Windows AOT 包 →
构建 Linux AOT 包（WSL）→ 双包冒烟 → 双压缩 → git 提交 + tag + push →
GitHub Release 附加**两个**资产。参数：`-Draft` / `-SkipBuild`（复用现包重压）/
`-NoCommit` / `-NoPush` / `-Token <t>`（默认取 git 凭据管理器 token，需 `repo` 权限）。

## 两个包的内容

```
slang_release_<v>/            # 顶层文件夹（zip/tar.gz 解压即得）
├── slang[.exe]                # 统合宿主：Front 编译 + C VM 运行（Native AOT 单文件）
├── bin\                       # C VM 运行时（hardened Release：LTO + 启动反调试）
│   ├── Windows: csimple_lang_dll.dll + sqlite3.dll
│   └── Linux : libcsimple_lang_dll.so + libsqlite3.so.0（捆绑，零 LD_LIBRARY_PATH 配置）
├── module\                    # 标准库 Core/Math/Std *.module.slb（平铺单目录）
│   └── Windows 另含 math_lib.dll（Math 的 FFI 原生库；Linux 侧不捆绑，见下）
├── test\RefProbe\             # 开箱示例：纯名引用官方库的最小工程（slang run test\RefProbe\RefProbe）
├── md\                        # ~93 篇用户文档
└── licenses\                  # 第三方协议合规包：NOTICE.md + 各组件协议全文（C VM 静态链 yyjson/lz4/zlib/mimalloc/tlsf/mbedtls，真源 csimple_lang\third_party\LICENSES\；csproj PackThirdPartyLicenses target + 发布脚本双保险注入）
```

**官方库直查（2026-10-17 起）**：用户工程 jsonc 的 `references` 直接写官方库名
（`{ "path": "Core", "name": "Core.module.json" }`）即可——Front 编译期与
C VM 运行期都会在 `<slang 目录>\module\` 下按名直查（slb 优先；工程跨盘/包外
时 C VM 再兜底 exe 目录 module\），任何放进 `module\` 的官方库零配置可用。

## 构建链差异（Windows vs Linux）

| 步骤 | Windows | Linux |
|------|---------|-------|
| AOT 编译 | 本机 `dotnet publish -r win-x64 -p:PublishAot=true` | WSL 内同命令（`-r linux-x64`）；SDK 取 WSL apt 版（Ubuntu 25.10 源只有 SDK 10，与 Windows 侧一致，net8.0 目标兼容已验证） |
| C VM 运行时 | `build-vm-win.ps1 -Config Release -Harden` → `csimple_lang_dll.dll` | WSL cmake（clang+Ninja，`SLVM_HARDEN=ON`）→ `build/ReleaseLinux/libcsimple_lang_dll.so` |
| 标准库打包 | publish 自举（csproj `PackStdModules` target） | `module\*.slb` 平台无关 → 直接复用 Windows 包产物（csproj 已对 linux RID 门控 Windows 专属 pack target）；Linux 侧冒烟含 `run MiniSmoke` Front 编译 E2E |
| sqlite | 捆绑 `third_party\sqlite\sqlite3.dll` | 捆绑系统 `libsqlite3.so.0`（C VM 链接系统 sqlite3） |
| 宿主动库加载 | `SetDllDirectory(bin)` | `NativeLibrary` DllImportResolver 按绝对路径 dlopen + sqlite 预载（见 `Backend/CvmBackend.cs`） |

## Linux 包已知限制

- **glibc ≥ 2.43**（构建机 Ubuntu 25.10；更旧的发行版需自行重编 C VM）。
- **Math 的 FFI 不可用**：`math_lib.dll` 是 Windows 产物（矩阵等 FFI 数学调用失败），
  包内不携带；Math 模块本身正常加载。
- 插件 `@csharp_mono`（mono 运行时）与 Windows-only FFI 同理不可用。

## 验证记录

| 版本 | 双包结果 |
|------|----------|
| v0.0.3（2026-10-17） | ✅ 首个双平台 AOT 版：win zip 8.2MB + linux tgz 8.1MB（同一 Release 两资产）；双平台冒烟全过——win run-disk Std/Math exit 0、linux run-disk Std exit 0、linux `run MiniSmoke`（Front 编译→SLIR 内存直传→C VM 执行 `_main_`）exit 0。发布链修复实录：① wsl 调用 stdout 混入返回值导致预检假失败（`Out-Host` 修）；② AOT obj 缓存复活 slang.pdb（归档前兜底删除）；③ Linux 系统方法全挂 error_code=-13——C VM 注册表走 `dlsym(dlopen(NULL))` 查主程序全局符号表，.NET 默认 `RTLD_LOCAL` dlopen 使 `.so` 符号不可见，宿主改 `RTLD_GLOBAL` dlopen（对齐 exe `-rdynamic` 语义，`Backend/CvmInterop.cs` + `CvmBackend.cs`）；④ 测试工程 jsonc 平台校验硬编码 win64，Linux 冒烟需 `SL_FORCE_RUN=1`（既有预期差异） |
