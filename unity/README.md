# SlangUnity · v2（UPM 插件包）

SLang 作为 Unity 附属脚本：**SL 直接调 C++，C++ 直接调 Unity 引擎原生接口**，C# 只是极薄宿主。
完整使用文档在包内：`SlangAllInOne/unity/package/com.slang.unity/README.md`
（安装到 Unity 工程后位于 `Packages/com.slang.unity/README.md`）。

---

## 1. 构建 / 安装 / 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File d:\project\lang\SlangAllInOne\unity\build-unity-package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File d:\project\lang\SlangAllInOne\unity\verify-hello-cube.ps1
```

- 第一条：编译 C++ 插件（接入 Unity 原生接口）与 SL 模块，组装 UPM 包安装到
  `<UnityProject>\Packages\com.slang.unity\`，并把示例数据放进 `Assets\StreamingAssets\Slang\`。
- 第二条：不进 Unity 的端到端验证，输出 `PASS` 表示 `slu_boot` 装载、批量对象表、
  60 帧推进与 SL 属性写回 C++ 全部可用。
- Unity 内菜单：`Tools > SlangUnity` 下有 `Install HelloCube Sample`、`Verify (Editor)`、
  `Enter Play Mode`、`Report (Play Mode)`、`Export .unitypackage`。

也可以用 `.unitypackage` 方式分发：菜单导出后双击导入其它工程。该格式只含包本体（Unity 忽略 `Samples~`），
导入后需手动把 `HelloCube.module.slb` 与 `lib/` 放到 `Assets/StreamingAssets/Slang/`；UPM 安装则可用菜单一键安装示例。

## 2. 改 SL 脚本与热更

1. 改 `SlangAllInOne/unity/HelloCube/HelloCube.sl`。
2. 执行 `build-unity-package.ps1 -SlOnly`（Unity 运行时不可覆盖原生 DLL）。
3. C++ 每 30 帧检查一次 SLB 时间戳，变化时随帧返回重载标志，C# 收到后重新执行 SL 模块；
   不重启 Play Mode，物体位置与角度不跳变。

## 3. 速度口径（实测）

| 环节 | 每帧次数 |
|---|---|
| SL → C++ | 0（只在装载/热更时执行一次，逐帧数值推进全在 C++） |
| C# → C++ | **1**（帧推进 + 状态读取 + 热更检查合并为一次调用，状态数组走原始指针） |
| C++ → Unity 日志 | 0（引擎日志接口直发 Console，C# 不转印） |
| 引擎 → C++ 渲染回调 | 1（一次性注册后由引擎在渲染线程直接调用） |
| C# → 引擎对象 | **1**（一次写入位置+旋转；颜色仅在脏标志变化时写） |

本机实测一次原生调用约 10 ns。Unity Play Mode 报告中 `renderEventCount` 与
`unityFrameCount` 相等、`nativeFrameCount` 仅比它们多出 Editor 验证的 60 次，
即**每帧恰好 1 次跨边界调用**。打成 IL2CPP 后 C# 编译为原生代码，边界进一步退化。

## 4. 目录速查

| 位置 | 内容 |
|---|---|
| `SlangAllInOne/unity/native/` | C++ 绑定层源码、编译批处理、随包附带的 Unity 官方插件头文件 |
| `SlangAllInOne/unity/HelloCube/` | SL 源码、工程配置、`.sp` 入口 |
| `SlangAllInOne/unity/package/com.slang.unity/` | UPM 包源码（`Runtime/` C# 极薄宿主、`Editor/` 工具、`README.md`） |
| `SlangAllInOne/unity/build-unity-package.ps1` | 全量构建 / `-SlOnly` 热更 |
| `SlangAllInOne/unity/verify-hello-cube.ps1` | 不进 Unity 的端到端验证 |
| `<Unity>/Packages/com.slang.unity/Plugins/x86_64/` | 原生插件、`csimple_lang.exe` / `csimple_lang_dll.dll` |
| `<Unity>/Packages/com.slang.unity/Plugins/x86_64/lib/` | 标准库模块 `Core.module.slb` / `Std.module.slb`（CLI 装载必需） |
| `<Unity>/Packages/com.slang.unity/Samples~/HelloCube/` | SL 源码与 SLB 示例 |
| `<Unity>/Assets/StreamingAssets/Slang/` | 运行时 SLB、示例源码与标准库模块副本 |

## 5. 注意事项与已知坑

- `HelloCube.jsonc` 的 `dllImports.path` 与 `sllib/UnityFFI.sl` 里的 `@DllImport` 都是本机绝对路径，
  指向包内 `Plugins/x86_64/slang_unity_native3.dll`；工程移动或换机器后要改这些路径并重新编译 SL 模块，
  否则 FFI 会静默走 fallback（入口文件 `HelloCube.sl` 的 `localProbe()` 自检打印 `20261109` 才算命中 C++）。
  入口文件必须保留至少一条 `@DllImport` 声明，否则整模块绑定面不激活。
- **标准库模块必须放在 CLI 同级 `Plugins/x86_64/lib/`**：导出的 SLB 里模块引用路径是相对 Front
  导出目录的，搬到 `StreamingAssets` 后无法解析。`build-unity-package.ps1` 已自动部署 `Core.module.slb`
  与 `Std.module.slb` 到该目录；缺失时现象是 `slu_boot rc=0`、日志正常，但 SL 实例方法/属性赋值静默失效、
  对象表全是默认值（不要误判成 FFI 绑定问题）。
- Unity 运行时只换 SLB；改 C++ 需先退出 Play Mode 或关闭编辑器。
- v1 遗留的 `Assets/Plugins/x86_64/` 若因 DLL 被 Unity 占用删不掉，关闭编辑器后手动删除；
  它与包内 DLL 不同名，不影响功能。
- `UnityPluginLoad` 只在 Unity 进程里触发；命令行跑同一个 DLL 时日志回退到 stdout。
- 渲染回调注册在 `AfterForwardOpaque`；自定义渲染管线若不触发该事件，`Report` 里
  `renderEventCount` 会是 0，需要换事件点。
- 仅 Windows x64；IL2CPP 下 JIT 已关闭。包内 `UnityPluginAPI` 头文件来自 Unity 安装目录，
  遵循 Unity Companion License（见其 `LICENSE.md`）。
