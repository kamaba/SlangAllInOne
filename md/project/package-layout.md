# 发布包目录布局：lib / modules / plugins

> 🔥 **本文档是发布包目录方案的决策记录**（2026-10-18 用户指令确立）。
> 配套改动（官方库直查、打包链、脚本）均以本文档为准；发布渠道策略另见
> [RELEASE.md](../../RELEASE.md)。

## 一、三目录设计

| 目录 | 定位 | 现状 |
|------|------|------|
| `lib\` | **系统自带文件**：官方标准库（Core / Math / Std 的 `*.module.slb` + `math_lib.dll` + Debug 包 json 调试副本） | ✅ 2026-10-18 起由原 `module\` 更名（内容不变，平铺单目录） |
| `modules\` | **用户包目录**：未来 `spm.exe`（SLang Package Manager，类比 npm / NuGet）安装/管理第三方包的落位 | 🧪 预留：Front 与 C VM 的官方库直查已按 `lib\` → `modules\` 顺序查找，目录未建自然落空；spm.exe 落地时无需再动装载器 |
| `plugins\` | **插件目录**：插件内容的安装与管理位（区别于普通包，见下） | ✅ 包根的插件 frontend 程序集（SLCSharpMonoFrontend / SLJavaHotspotFrontend）已移入；插件管理器安装整插件目录到 `plugins\<id>\` 后即可被 `@tag{}` 路由 |

包根其余目录不变：`bin\`（C VM 运行时）、`md\`（用户文档）、`test\RefProbe\`（开箱示例）。

## 二、迁移记录（2026-10-18）

0. **CompileStdlib 直通包目录（同日晚些增补）**：CompileStdlib 驱动（core/math/std/all 预设）编译成功后自动把产物（R15 slb+json 双产物，`--format binary --export-json` 内置）同步到四个包目录的 `lib\`——slb 恒同步、json 副本仅 `*-debug` 目录、math_lib.dll 仅 `win32-*`；与 publish 的 pack-modules 同一落位，VS 里 F5 任意预设即可在包目录 `lib\` 看到新鲜产物（显式工程路径 selector 不属于标准库，不同步）。
1. **`module\` → `lib\`**：PackModulesCommand 打包目录更名；发布包目录 = `package\{win32|linux}-{debug|release}` 四目录（csproj 零旗标 publish 默认；编译产物按 debug/release 分别落对应平台包的 lib\），与 release-slang.ps1 / build-packages.ps1 布局校验、冒烟路径同步。
2. **官方库直查改链**：references 写纯模块名（"Core"/"Std"/"Math"）时——
   - Front 编译期：`ProjectReferenceModuleLoader.TryResolveRuntimeModuleDirPath`（Strategy 4）按 `<exe>\lib\` → `<exe>\modules\` 顺序直查 `<名>.module.slb|json`（slb 优先）；
   - C VM 运行期：`sl_load_references` ④（`csimple_lang/src/vm/load/slir_json_module_loader.c`）同序直查 `<exe_dir>/lib/` → `<exe_dir>/modules/`。
   两端一致，发布包内用户工程继续零相对路径配置。
3. **插件程序集归位**：csproj `RelocatePluginFrontends` target 把包根的
   `SLCSharpMonoFrontend.*` / `SLJavaHotspotFrontend.*`（Front 工程
   ProjectReference 的发布伴生物）移入 `<包>\plugins\`（Native AOT Release
   发布不产出这些托管 dll，target 静默跳过）。
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
- `run-disk <任意路径>` 与模块内嵌相对引用解析不受目录名影响；
- `linux-dist/` 旧独立分发包走 `out/export\` 布局，不依赖官方库直查，不受影响；
- 开发布局（`build\<C>\bin` / `bin\Debug\net8.0`）无 `lib\` 子目录，直查链
  自然落空，行为不变。
