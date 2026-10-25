# 发布包目录布局：lib / modules / plugin

> 🔥 **本文档是发布包目录方案的决策记录**（2026-10-18 用户指令确立；
> 🔥 **2026-10-25 布局标准全量定稿，见 §七——§一~§六与 §七 冲突处以 §七 为准**）。
> 配套改动（官方库直查、打包链、脚本）均以本文档为准；发布渠道策略另见
> [RELEASE.md](../../RELEASE.md)。

## 七、🔥 布局标准全量定稿（2026-10-25 用户指令；强制执行版）

> **标准 = 包根四件套 + 插件包两件套**。自 Front 编译装载 → C VM 运行 → 发布打包 →
> 分发脚本，全链路一律按本节执行（装载链回退只做过渡兼容，不再作为目标态）。

### 7.1 主包（`package\{win32|linux}-{debug|release}\` / 未来 slang 分发包）

```
<包根>\
├── slang(.exe)                 入口 = frontEnd 编译 + cvm_runtime 执行
├── bin\                        打包的工具链产物与 VM 本体：
│   ├── csimple_lang.exe / csimple_lang_dll.dll（C VM）
│   ├── llc.exe / mlir-opt.exe / mlir-translate.exe / mlir_float16_utils.dll
│   │   （MLIR/LLVM AOT 工具链，csproj PackMlirTools 自 simple_language\tools\llvm）
│   └── （Debug 另有 *.pdb 侧车）
├── lib\                        引入的 module 与 module 关联的原生库：
│   ├── *.module.slb            官方标准库等模块包（平铺）
│   └── windows\                module 关联 dll 按平台分目录（2026-10-22 平台细分）
│       ├── sqlite3.dll         （Core 关联：C VM 唯一硬动态依赖，delay-load +
│       │                        sl_preload_associated_dlls 预装载）
│       └── math_lib.dll        （Math 关联：FFI 原生库）
│       （linux 包 = lib\linux\libsqlite3.so.0；slb 平铺、平台无关）
├── plugin\<id>\                插件包安装位（csproj PackPlugins；见 7.2）
└── md\                         用户文档
```

### 7.2 插件包（`plugin\<id>\`，仓库侧 = `plugin\<id>\` 目录本体）

**两件套 = `plugin.jsonc` + `package\`（dev 侧）**。三个工程（`frontend\`、
`cvm\`=runtime、`slang\`）的产物**统一导出到插件根下的 `package\`**（2026-10-25
二次定稿：lib\ → package\，用户指令——产物生成到 package\，不进 lib\）；发布
打包（csproj PackPlugins）剥掉 `package\` 层平铺装进 `<包根>\plugin\<id>\`：

```
plugin\csharp_mono\                       （dev 树，仓库侧）
├── plugin.jsonc                          权威清单
├── package\                              ← 三工程导出汇聚（= 未来压缩成一个文件的插件包）
│   ├── CSharpMono.module.slb             第三个工程：slang\ 的 .sl 打包产物（平铺 package\ 根）
│   └── windows\                          平台分类库：windows | linux | macos | iOS | android
│       ├── cvm_csharp_mono.dll           runtime(cvm) 工程 dll
│       ├── sl_csharp_mono_frontend.dll   frontend 工程原生 dll
│       └── mono-2.0-sgen.dll、lib\mono\4.5\…  运行体附属子树原样随包
├── frontend\  cvm\  slang\               源码区（产物已全部上移 package\；.obj 落各自 obj\）

<包根>\plugin\csharp_mono\                （发布包内——剥掉 package\ 层的平铺形态）
├── plugin.jsonc
├── CSharpMono.module.slb
└── windows\ …（平台子目录直接挂 plugin\<id>\ 下，无 lib\ / package\ 两层目录名）
```

- 平台目录名 = `windows|linux|macos|ios|android`，与主包 `lib\<平台>\`、
  C VM `sl_platform_dir_name` **同名约定**；旧 `lib\<os>-<arch>`（如
  `windows-x64`）降为装载回退兼容变体。
- **Front 双形态探测**（2026-10-25 二次定稿）：dev 树优先探测
  `<插件根>\package\<平台>\`，发布包平铺位 `<插件根>\<平台>\` 回退
  （PluginFrontendParser.EnsureNativeLoaded / PluginManager.ResolvePluginLibDir、
  ResolveOne 全链同口径）。
- **分发形态演进**：当前发布打包把插件 package\ 剥层平铺装进
  `<包根>\plugin\<id>\`；未来插件包压缩成一个文件，直接放到
  `slang\plugin\` 下的一个目录里。
- 构建入口：`plugin\<id>\cvm\build-<id>.ps1`（一键产出三工程全部产物进
  `package\`）；vcxproj（VS 链）OutDir 同指 `..\package\windows\`。

### 7.3 调用关系（全链路一致性）

| 环节 | 路径行为 |
|------|----------|
| Front 编译期 references 纯名（Core/Std/Math） | 官方库直查 `<exe>\lib\<名>.module.slb`（slb 优先；modules\ 兜底） |
| Front `@tag{}` 路由 | `FindPluginsParent` 上溯 `plugin` → `<exe>\plugin\` 探测；frontendNative dll 取 `<插件根>\package\<平台>\<lib>`（发布包平铺 `<插件根>\<平台>\` 回退） |
| Front PluginLib 导出段 | 平台目录回退（`<os>` 新标准位优先）→ **递归拷贝** `outDir\plugin\<id>\<平台>\`；module.json 记 `plugin/<id>/<平台>/<file>` |
| C VM 引用装载 | `<exe>\lib\` → `<exe>\modules\` 直查（slb 优先） |
| C VM 关联 dll 预载 | `<exe>\lib\<平台>\` → 平铺 `lib\` → `<exe>\..\lib\<平台>\` → `<exe>\..\lib\`（sqlite delay-load 绑定） |
| C VM FFI/插件库 | 候选链含 `<exe>\lib\<平台>\<basename>`；插件 dll 按 module.json 包相对路径（Front 已按 7.2 求值）拼接加载 |
| AOT 工具链 | MLIRToolchain 探测 `<exe>\bin\` 优先（发布包 PackMlirTools 就位；开发树回落 `simple_language\tools\llvm`，auto-deploy 也进 `<exe>\bin\`） |

### 7.4 落点清单（本次强制执行改动，2026-10-25）

| 层 | 落点 |
|----|------|
| 插件仓库侧 | 4×vcxproj OutDir `..\package\windows\`；3×build-*.ps1 全产物导出 `package\`（obj 隔离 obj\、副产物清理、无部署步）；plugin.jsonc `entry.lib` 键改平台名；🔥 2026-10-25 二次定稿：`lib\` → `package\`（用户指令——产物生成到 package\，不进 lib\） |
| Front 层 | [PluginFrontendParser.cs](../../../simple_language/source/Core/PluginFrontendParser.cs) 探测 `package\<平台>\`（回退发布包平铺 `<平台>\`）；[PluginManager.cs](../../../simple_language/source/Export/PluginManager.cs) libDir 三级 + 平台目录回退 + 递归拷贝 + module.json 新路径形态 |
| 发布打包 | csproj **PackMlirTools**（bin\ 工具链）、**PackPlugins**（plugin\ 安装 + 副产物 Exclude）；PackCvmRuntime sqlite3→`lib\windows\`；PackModulesCommand/CompileStdlib math_lib→`lib\windows\`；RelocatePluginFrontends 空壳删除 |
| 脚本 | build-packages.ps1 / release-slang.ps1 布局校验与 linux 包组装（sqlite → `lib\linux\`、剔除 lib\windows\）按 7.1 |
| 清理 | MLIR 工具散拷副本（dev 树 exe 旁 + 旧包根）清除，EnsureLocalTools 改进 `bin\` |



## 一、三目录设计

| 目录 | 定位 | 现状 |
|------|------|------|
| `lib\` | **系统自带文件**：官方标准库（Core / Math / Std 的 `*.module.slb` + `math_lib.dll` + Debug 包 json 调试副本）+ `sqlite3.dll`（C VM 唯一硬动态依赖，2026-10-22 布局规则自 bin\ 迁入：delay-load + 运行期预装载解析） | ✅ 2026-10-18 起由原 `module\` 更名（内容不变，平铺单目录）；🔥 2026-10-22 起关联 dll 统一入此目录（§六） |
| `modules\` | **用户包目录**：未来 `spm.exe`（SLang Package Manager，类比 npm / NuGet）安装/管理第三方包的落位 | 🧪 预留：Front 与 C VM 的官方库直查已按 `lib\` → `modules\` 顺序查找，目录未建自然落空；spm.exe 落地时无需再动装载器 |
| `plugin\` | **插件目录**：插件内容的安装与管理位（区别于普通包，见下） | ✅ 插件管理器安装整插件目录到 `plugin\<id>\` 后即可被 `@tag{}` 路由（Front `FindPluginsParent` 已支持回退探测；两个运行时插件 frontend 自 2026-10-21 起 C 化为原生 dll、不经 publish 产出/归位，随插件整目录分发） |

包根其余目录不变：`bin\`（C VM 运行时**本体**：`csimple_lang_dll.dll` / `csimple_lang.exe` / pdb 侧车——sqlite3.dll 已按 §六迁 `lib\`）、`md\`（用户文档）。~~`test\RefProbe\`（开箱示例）~~ 已于 2026-10-18 按用户指令移除（v0.0.5 起发布包不再带 `test\`，示例保留在仓库测试树 `SLangCore\test\Other\RefProbe`）。

## 二、迁移记录（2026-10-18）

0. **CompileStdlib 直通包目录（同日晚些增补）**：CompileStdlib 驱动（core/math/std/all 预设）编译成功后自动把产物（R15 slb+json 双产物，`--format binary+json` 内置）同步到四个包目录的 `lib\`——slb 恒同步、json 副本仅 `*-debug` 目录、math_lib.dll 仅 `win32-*`；与 publish 的 pack-modules 同一落位，VS 里 F5 任意预设即可在包目录 `lib\` 看到新鲜产物（显式工程路径 selector 不属于标准库，不同步）。
1. **`module\` → `lib\`**：PackModulesCommand 打包目录更名；发布包目录 = `package\{win32|linux}-{debug|release}` 四目录（csproj 零旗标 publish 默认；编译产物按 debug/release 分别落对应平台包的 lib\），与 release-slang.ps1 / build-packages.ps1 布局校验、冒烟路径同步。
2. **官方库直查改链**：references 写纯模块名（"Core"/"Std"/"Math"）时——
   - Front 编译期：`ProjectReferenceModuleLoader.TryResolveRuntimeModuleDirPath`（Strategy 4）按 `<exe>\lib\` → `<exe>\modules\` 顺序直查 `<名>.module.slb|json`（slb 优先）；
   - C VM 运行期：`sl_load_references` ④（`csimple_lang/src/vm/load/slir_json_module_loader.c`）同序直查 `<exe_dir>/lib/` → `<exe_dir>/modules/`。
   两端一致，发布包内用户工程继续零相对路径配置。
3. **插件程序集归位**：csproj `RelocatePluginFrontends` target 原把包根的
   插件 frontend 程序集（Front 工程 ProjectReference 的发布伴生物）移入
   `<包>\plugins\`——🔥 2026-10-21 起两个运行时插件 frontend 均已 C 化
   （csharp_mono + java_hotspot 原托管 csproj 已删除，原生 dll 随插件
   整目录分发），target 清单已清空、保留空壳兼容管线（Native AOT
   Release 发布本就不产出这些托管 dll）。
4. **插件路由支持包内安装**：`PluginFrontendParser.FindPluginsParent` 在
   源码树上溯（`plugin`，开发布局）落空后，回退探测
   `<exe>\plugin\`——插件管理器把整插件目录（`plugin.jsonc` + `cvm\` +
   `frontend\` + `slang\`）装进 `plugin\<id>\` 后，`@tag{}` 无需源码树即可路由。
5. **FFI / vmDllImports 不受影响**：原生库解析本就按「模块包自身目录（现
   `lib\`）+ 相对路径 / basename 回退」，目录随包整体更名，链路不变。

## 三、为什么 plugin 独立于 modules（插件 ≠ 普通包）

普通包（module）只是编译产物 `*.module.slb|json`，装载即用；插件是**多层
结构 + 生命周期**的复合体（权威：`csimple_lang/md/design/PLUGIN_SYSTEM_DESIGN.md`）：

- **三目录结构**：`cvm\`（原生库，`lib/<os>-<arch>/`）、`frontend\`（Front 层
  parser/builder 程序集，`@tag{}` 块体的解析与构建）、`slang\`（refModule，
  声明追加进引用链的 SL 模块）；
- **清单驱动**：`plugin.jsonc`（plugin.id / frontendLibs / parserType /
  builderType / refModule.channelClassPath）；
- **能力点模型**：`@tag{}` 只是 capability 的一种；注册走 module.json
  `plugins[]`，装载懒激活（`load`·`enter`·`exit`·`unload` 四阶段）；
- **双宿主**：Front 层（编译期转调）与 C VM 层（运行期 native 库 + ABI）各一份。

因此插件不进 `modules\` 包目录，独立放 `plugin\<id>\`，由（未来的）插件
管理器单独管理安装/启停。

## 四、spm.exe 愿景（未实现，备忘）

`spm.exe` = SLang 的包管理器，定位类比 npm / NuGet：

- 命令集草案：`spm install <pkg>` / `spm remove` / `spm list` / `spm publish`
  / `spm update`；注册表（registry）与版本解析待定；
- 安装落位：`<slang>\modules\<pkg>\<pkg>.module.slb|json`——装载器查找链
  已就绪（本文档 §二.2），`references` 纯模块名即可引用已安装包；
- `lib\` 与 `modules\` 的边界：lib = 随 slang 发行、官方维护的系统标准库；
  modules = 用户/第三方生态包。查找序 lib → modules 保证官方库优先。

## 五、兼容性说明

- 旧发布包（≤ v0.0.3）的 `module\` 布局**不被**新 slang 的官方库直查识别
  （查找目录已改 lib）——发布包总是随 slang 整体重建分发，无跨版本混用场景；
- `run <任意路径>`（run-disk 别名同效）与模块内嵌相对引用解析不受目录名影响；
- `linux-dist/` 旧独立分发包走 `out/export\` 布局，不依赖官方库直查，不受影响；
- 开发布局（`build\<C>\bin` / `bin\Debug\net8.0`）无 `lib\` 子目录，直查链
  自然落空，行为不变（sqlite3.dll 开发树 post-build 仍拷贝在 exe 同目录，
  作为 delay-load 回落位，见 §六）。

## 六、关联件布局规则（2026-10-22 用户指令；同日平台细分定稿）

> 🔥 **规则**：关联的 `.slb` 模块包与关联的原生库统一放 `lib\`；插件放 `plugin\`；
> exe 目录只留 exe 本体（发布应用 = `Module.exe` + `lib\` + `plugin\`）。
> 发布产物 exe 旁不再有散落的 sqlite3.dll。🔥 **平台细分（同日定稿）**：原生库
> 在 lib\ 下按平台分目录 `lib\{windows|linux|macos|android|ios}\`（承载
> .dll/.so/.dylib/.lib/.a 等）——一个发布目录可承载多平台运行体，运行体按
> 当前平台自取连接库（slb 平铺，平台无关）。`slang publish` 产物 additionally
> 分 `publish\{debug|release}\` 两配置子目录并存（发布规则，权威 =
> publish-guide.md §4）。

1. **sqlite3.dll 迁移**：自发布包 `bin\`、`slang publish` 发布根目录迁入 `lib\<平台>\`
   （slb 仍平铺）。sqlite3.dll 是 C VM exe / dll 唯一硬动态依赖——链接侧改
   **delay-load**（根 CMakeLists `/DELAYLOAD:sqlite3.dll` + `delayimp`；`vm_lib`
   vcxproj `<DelayLoadDLLs>`，两构建链同步），进程启动不再强解析；运行期
   `sl_preload_associated_dlls()`（`csimple_lang/src/lib/ffi/sl_ffi_lib_manager.c`）
   在任何 sqlite 调用前显式 `LoadLibrary` `<exe>\lib\<平台>\`（→ 平铺 `lib\` →
   `<exe>\..\lib\` 同序）副本，delay thunk 按已加载模块名绑定；未命中回落 OS
   标准搜索——**开发树 `build\<C>\bin` 的 exe 同目录副本保持 post-build 拷贝，
   零影响**。接线点 = `cli_init_platform`（cli_main + 两个内存宿主 API 汇聚）+
   app 载荷模式独立前置。平台名 = `sl_platform_dir_name()`（编译期判定
   windows/linux/macos/android/ios，`__ANDROID__` 先于 `__linux__`）。
2. **Linux 等价**：`libsqlite3.so.0` 随包落包根 `lib\`（build-packages.ps1 d' 步，
   在 lib\ robocopy 之后防 `/MIR` 清除；robocopy 顺带带来的 Windows 专属
   `sqlite3.dll`/`math_lib.dll` 同步剔除——linux 包 lib\ 只留 .so）；解析 =
   `csimple_lang_dll.so` 自身 rpath `$ORIGIN/../lib` + CvmBackend 绝对路径预载
   （`bin\..\lib\` → `bin\` 回退）双兜底（此前 `bin\` 副本因 DT_NEEDED 不搜应用
   目录实为死重，本次修复为真实生效）。
3. **FFI / math_lib.dll 平台回退**：原生库解析按「模块包自身目录 + 相对路径 /
   basename 回退」——模块从 `lib\` 装载时 pkg_dir 即 `lib\`，天然命中；🔥 平台
   细分后 FFI 候选链同步扩展（2026-10-22）：`sl_ffi_lib_load` 候选 3-6 按
   basename 依次查 `<exe>\lib\<平台>\` → `<exe>\lib\` → `<exe>\..\lib\<平台>\`
   → `<exe>\..\lib\`；`vm_sys_ffi_static_lib_register`（dllImports "static" 预载）
   同序三重回退（pkg_dir 下 `<平台>/basename` 优先于平铺 basename）。
4. **引用模块 stage（发布应用专属，2026-10-22）**：`slang publish` 把主模块
   moduleReferences 非系统库引用（如 SLangServer）平铺拷入发布目录
   `<名>.module.{slb,json}`——发布目录深度与开发导出树不同，内嵌相对路径必然
   错位（装载期静默跳过，曾致 ServerP1Test 全线失效的实录），C VM 引用回退链
   basename 直查恰好命中平铺形态。
5. **落点清单**：csproj `PackCvmRuntime`（bin\ 清单去 sqlite3.dll、新增 lib\ 拷贝）、
   `Publish/PublishCommand.cs`（配置子目录 + lib\<平台>\ + 引用 stage）、
   `Backend/CvmBackend.cs`（Linux 预载路径）、`scripts/build-packages.ps1`
   （双平台布局校验）、C VM 链接与预装载（上述）。
6. **验证实录**（2026-10-22）：裸 exe（无 sqlite 同目录）可启动（delay-load 实证）；
   `slang publish` ExpendTest 双配置（debug+release 并存）→ 发布根无散落
   sqlite3.dll、`lib\windows\{sqlite3,math_lib}.dll` + slb 平铺齐、SLangServer
   平铺 stage；发布应用 `exit 0` 且 **ServerP1/P15/P2/P3 全部 all done**
   （引用 stage 修复后完整跑通；此前止步 ServerP1Test T1）。
