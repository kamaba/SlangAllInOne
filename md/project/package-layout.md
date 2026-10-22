# 发布包目录布局：lib / modules / plugins

> 🔥 **本文档是发布包目录方案的决策记录**（2026-10-18 用户指令确立）。
> 配套改动（官方库直查、打包链、脚本）均以本文档为准；发布渠道策略另见
> [RELEASE.md](../../RELEASE.md)。

## 一、三目录设计

| 目录 | 定位 | 现状 |
|------|------|------|
| `lib\` | **系统自带文件**：官方标准库（Core / Math / Std 的 `*.module.slb` + `math_lib.dll` + Debug 包 json 调试副本）+ `sqlite3.dll`（C VM 唯一硬动态依赖，2026-10-22 布局规则自 bin\ 迁入：delay-load + 运行期预装载解析） | ✅ 2026-10-18 起由原 `module\` 更名（内容不变，平铺单目录）；🔥 2026-10-22 起关联 dll 统一入此目录（§六） |
| `modules\` | **用户包目录**：未来 `spm.exe`（SLang Package Manager，类比 npm / NuGet）安装/管理第三方包的落位 | 🧪 预留：Front 与 C VM 的官方库直查已按 `lib\` → `modules\` 顺序查找，目录未建自然落空；spm.exe 落地时无需再动装载器 |
| `plugins\` | **插件目录**：插件内容的安装与管理位（区别于普通包，见下） | ✅ 插件管理器安装整插件目录到 `plugins\<id>\` 后即可被 `@tag{}` 路由（Front `FindPluginsParent` 已支持回退探测；两个运行时插件 frontend 自 2026-10-21 起 C 化为原生 dll、不经 publish 产出/归位，随插件整目录分发） |

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
   源码树上溯（`simple_language_plugins`，开发布局）落空后，回退探测
   `<exe>\plugins\`——插件管理器把整插件目录（`plugin.jsonc` + `cvm\` +
   `frontend\` + `slang\`）装进 `plugins\<id>\` 后，`@tag{}` 无需源码树即可路由。
5. **FFI / vmDllImports 不受影响**：原生库解析本就按「模块包自身目录（现
   `lib\`）+ 相对路径 / basename 回退」，目录随包整体更名，链路不变。

## 三、为什么 plugins 独立于 modules（插件 ≠ 普通包）

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

因此插件不进 `modules\` 包目录，独立放 `plugins\<id>\`，由（未来的）插件
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

## 六、关联件布局规则（2026-10-22 用户指令）

> 🔥 **规则**：关联的 `.slb` 模块包与关联的 `.dll`（原生依赖）统一放 `lib\`；
> 插件放 `plugins\`；exe 目录只留 exe 本体（发布应用 = `Module.exe` +
> `lib\` + `plugins\`）。发布产物 exe 旁不再有散落的 sqlite3.dll。

1. **sqlite3.dll 迁移**：自发布包 `bin\`、`slang publish` 发布根目录迁入 `lib\`
   （与标准库 slb / math_lib.dll 同目录）。sqlite3.dll 是 C VM exe / dll 唯一硬
   动态依赖——链接侧改 **delay-load**（根 CMakeLists `/DELAYLOAD:sqlite3.dll` +
   `delayimp`；`vm_lib` vcxproj `<DelayLoadDLLs>`，两构建链同步），进程启动不再
   强解析；运行期 `sl_preload_associated_dlls()`（`csimple_lang/src/lib/ffi/
   sl_ffi_lib_manager.c`）在任何 sqlite 调用前显式 `LoadLibrary`
   `<exe>\lib\`（→ `<exe>\..\lib\`，后者覆盖发布包 `bin\` 内 VM exe）副本，
   delay thunk 按已加载模块名绑定；未命中回落 OS 标准搜索——**开发树
   `build\<C>\bin` 的 exe 同目录副本保持 post-build 拷贝，零影响**。接线点 =
   `cli_init_platform`（cli_main + 两个内存宿主 API 汇聚）+ app 载荷模式独立前置。
2. **Linux 等价**：`libsqlite3.so.0` 随包落包根 `lib\`（build-packages.ps1 d' 步，
   在 lib\ robocopy 之后防 `/MIR` 清除；robocopy 顺带带来的 Windows 专属
   `sqlite3.dll`/`math_lib.dll` 同步剔除——linux 包 lib\ 只留 .so）；解析 =
   `csimple_lang_dll.so` 自身 rpath `$ORIGIN/../lib` + CvmBackend 绝对路径预载
   （`bin\..\lib\` → `bin\` 回退）双兜底（此前 `bin\` 副本因 DT_NEEDED 不搜应用
   目录实为死重，本次修复为真实生效）。
3. **FFI / math_lib.dll 无需改动**：原生库解析本就按「模块包自身目录 +
   相对路径 / basename 回退」——模块从 `lib\` 装载时 pkg_dir 即 `lib\`，天然命中。
4. **落点清单**：csproj `PackCvmRuntime`（bin\ 清单去 sqlite3.dll、新增 lib\ 拷贝）、
   `Publish/PublishCommand.cs`（sqlite3.dll → `lib\`）、`Backend/CvmBackend.cs`
   （Linux 预载路径）、`scripts/build-packages.ps1`（双平台布局校验）、
   C VM 链接与预装载（上述）。
5. **验证实录**（2026-10-22）：裸 exe（无 sqlite3 同目录）可启动（delay-load 实证）；
   `slang publish` ExpendTest（ProjectTest2）→ 发布根无散落 sqlite3.dll、`lib\` 五件
   齐；发布应用 `exit 0`（套件 `_main_` 直调 `Sqlite3Test.fun()`，sqlite 确经
   `lib\` 预装载工作）。
