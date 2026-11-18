# SnakeGame —— 贪吃蛇示例（gameExample 首个工程）

## 架构

```
QT 窗口（SLangQT：QApplication/QWidget/QLabel/QTimer，slang_qt.dll）
├ 键盘：SlangKeyWidget（slang_qt 子类）keyPress/Release → C++ 按键状态表
│       （s_slqt_keys[256]，Qt::Key 压缩到槽）；SL 每帧轮询 QTHost.keyDown
│       → SLang.QT.ffi_keyDown → slqt_key_down_sl 读状态表（跨模块回调不稳，
│       输入主路径改为轮询 + 边沿检测；R 重开）
├ 帧循环：QTimer(16ms) → SnakeGame.frameTick（QTHost.startHost 内 exec 阻塞驱动）
│   1) 轮询读方向键（防 180° 反向）+ 150ms 蛇步进；R 键重开
│   2) 每帧重建 5 组烘焙顶点（棋盘格深/浅背景各 128 格 / 蛇身 / 蛇头高亮 /
│      食物，各单色 MaterialData）→ MeshRef.setVertices → 正交烘焙路径
│      （C sle_ortho_bake → uploadMesh MESH_CUSTOM = SimSystemsTest S10 形态）
│   3) rs.frame → RGBA8 块 → QLabel.setPixmapRgba 上屏（scaledContents 随窗缩放）
│   4) 状态栏 setInfo("Score / Len / GAME OVER")（QTHost.infoHandle QLabel）
└ InputSystem（引擎）：endFrame 清边沿（键盘主路径已改轮询，C 输入表保留兼容）
```

## 文件

| 文件 | 说明 |
|---|---|
| `SnakeGame.jsonc` | 工程清单（references：SimGameEngine slb + SLangQT json 绝对路径 + Lib 包相对路径——**形态照抄 Test.jsonc：模块产物绝对、Lib 包相对**） |
| `SnakeGame.sp` | **入口工程**（`_main_() { SnakeGame.run() }`——**无 sp 的 _main_ 模块入口不被调用**） |
| `SnakeGame.sl` | 游戏逻辑（全 static 形态；QT 对象不在此文件——见 QTHost 坑说明） |
| `QTHost.sl` | QT 宿主门面（**纯 FFI 句柄形态**，见下「双 SLang namespace 冲突」） |

## 关键坑（全部实证，后续示例必读）

1. **双 SLang namespace 冲突**：SimGameEngine（传递 SLangRender 的 `namespace SLang`）与
   SLangQT（`namespace SLang`）同模块引用 → import 平面「SLang」重名 → 任何
   `SLang.Xxx` 限定**成员声明**报 MetaCoreMemberNameImportConflict（**调用表达式
   `SLang.QT.connect` 不触发**）。规避：**QTHost.sl 独立 import SLangQT 承接全部
   QT 对象（纯 FFI 句柄形态，零包装对象成员）；SnakeGame.sl 不 import SLangQT**。
2. **模块入口 = 同名 `.sp` 的 `_main_()`**：缺 sp → `slang run` 静默不调任何方法
   （进程空转挂起）。Test.sp 形态：`Project { _main_() { SnakeGame.run() } }`。
3. **裸方法名不可作实参 / 跨类需类名限定**：`QTHost.startHost( SnakeGame.frameTick, ... )`
   （QTTest.onClick 同款）；同类内也要类名限定。
4. **`int` 不是 SL 类型**：handler 参数用 `Int32`（`int` 导致方法注册失败 → not found）。
5. **jsonc struct 的 `namespace` 包装**：源文件无 namespace 块时**不要**加
   `"namespace": "Xxx"` 包装（方法不注册 → not found 级联）。
6. **非 static 成员 + namespace 限定类型** = 成员名冲突——**成员全 static 化**。
7. **成员变量必须 `= 初始值`**（对象字段 `= null`）。
8. **跨模块对象入 List 污染字段**（QT 轮同族）——QT 对象只存 Int64 句柄。
9. **slang_qt.dll 依赖环境**：stub 版与 -Qt 版不可与 Qt6*.dll 混放（stub 探测遇
   Qt6Core.dll 走错分支崩溃）；-Qt 版 Qt 依赖经静态/PATH 解析（QTTest 验证无需
   目录内 Qt6 dll）。运行真窗口需 -Qt 版 dll（build-slqt.ps1 -Qt）+ 可选
   deploy-qt.ps1 部署 Qt 运行时。
10. **键盘输入走轮询，不走信号 trampoline**：SIG_KEY_PRESSED/RELEASED 经 FFI
    回调跨模块重入 VM 不稳（补 `_dispatchIntCb` 映射仍不触发）；改为 C++ 侧
    `s_slqt_keys` 状态表 + `slqt_key_down_sl` 导出，SL 每帧轮询 + 边沿检测。
    按键需保持 ≥1 个帧周期（16ms）才被轮询捕获——真人按键天然满足；自动化
    脚本瞬间 down+up 会被漏掉，须在中间 Sleep ≥50ms。
11. **QLabel 纯色网格需多 MeshRef**：单 MeshRef 的多色顶点只取首色（材质单色），
    故棋盘格深/浅、蛇身/蛇头/食物各建一个节点 + 独立 MaterialData，每帧
    `setVertices` 各自分组顶点。

## 构建 / 运行

```powershell
# 1) 引擎（含 InputSystem + C 输入表）
slang compile SLangCore\Lib\SLang\SimGameEngine\SimGameEngine.jsonc --format binary
# 2) QT 模块（-Qt 真后端；真窗口必须有此版，不能用 stub）
powershell -File SLangCore\Lib\SLang\QT\cvm\build-slqt.ps1 -Qt
# 3) 游戏模块（源改了必做；产出 out\export\SnakeGame\SnakeGame.module.slb）
slang compile SLangCore\Lib\SLang\SimGameEngine\gameExample\SnakeGame\SnakeGame.jsonc --format binary
# 4a) 开发态运行（真窗口；Qt6 运行时须就位，见下「Qt 运行时」）
slang run out\export\SnakeGame\SnakeGame.module.slb
# 4b) 发布态（VSCode 右键「发布工程」走的就是这条；jsonc 的 publish/qtRuntime
#     段会自动带全 Qt 运行库 + 去黑窗，产物在 publish\release\，开箱即跑）
slang publish SLangCore\Lib\SLang\SimGameEngine\gameExample\SnakeGame\SnakeGame.sp
#     CLI 直跑会在 publish\release\ 下生成；若带 --dest X 则落在 X\release\，
#     需把 X\release\ 内容拷回 publish\release\（VSCode 右键不带 --dest，无需拷）
```

## Qt 运行时（真窗口必需，否则 0xC0000409）

`slang_qt.dll`（-Qt 版）依赖 Core/Gui/Widgets + Network/Sql/Svg/SvgWidgets/
OpenGL/OpenGLWidgets/PrintSupport/Xml 等 Qt6 dll，且 QApplication 构造期要
`plugins\platforms\qwindows.dll`。缺任一依赖 → 崩在 `ffi_appCreate()`（进程
`0xC0000409`，无后续日志）。

**发布态已自动化**：`SnakeGame.jsonc` 的 `qtRuntime` 段（enabled=true，
targetDir=`lib/windows`，全模块+全插件）让 `slang publish` / VSCode 右键发布
自动带全 17 个 Qt6 dll + plugins 全套 + `qt.conf`（Plugins=`lib/windows/plugins`），
`publish.gui=true` 去黑窗。**不需要**手工 deploy-qt.ps1。

**开发态 `slang run` / VSCode 调试**走 `out\export\SnakeGame`，Qt 运行时不随
compile 自动部署，仍需 deploy-qt.ps1 的 `snakeexp` 槽位（或临时把
`C:\Qt\6.8.1\msvc2022_64\bin` 加进 PATH 应急）：

```powershell
powershell -File SLangCore\Lib\SLang\QT\cvm\deploy-qt.ps1 -Combo full -Targets snakeexp
```

**发布 exe 内嵌模块**：改了 `.sl` 源码只 `slang compile` 不够——`publish\release\
SnakeGame.exe` 是从 publish 时附加的 payload 加载模块，必须重新 `slang publish`
（右键发布即可），否则跑的还是旧逻辑。

## 运行秒退 / 0xC0000409（2026-11-18 排障结论）

现象：`slang run out\export\SnakeGame\SnakeGame.module.slb` 秒退（qwindows，exit 0）
或崩 0xC0000409（offscreen）；发布链路本身正常（`slang publish` EXIT=0、发布包
exe 实测正常）。

**根因 = 开发态槽位的 `slang_qt.dll` 是陈旧构建**（哈希 !=
`out\export\SLangQT\slang_qt.dll`，两者相差十几分钟的重编）。FFI 预载到旧 dll
后行为不稳。**与 PATH/CWD 无关**（对照实验证实）。

修法（二选一）：

```powershell
# 1) 自愈脚本（推荐：每次运行前自动按哈比对齐 export 槽位的 dll）
powershell -File SLangCore\Lib\SLang\SimGameEngine\gameExample\SnakeGame\run-dev.ps1
powershell -File run-dev.ps1 -Offscreen   # 无头验证
powershell -File run-dev.ps1 -Debug       # slang run --debug-server

# 2) 手工覆盖
copy SlangAllInOne\out\export\SLangQT\slang_qt.dll SlangAllInOne\out\export\SnakeGame\
```

验证记录（2026-11-18）：同步 dll 后 dev 态 offscreen / 真窗口两种方式均进入
60Hz 事件循环持续运行；`slang publish` 与 `--mode exe` 两变体 EXIT=0，
发布包 exe 离屏启动正常。

## VSCode 调试 / 发布（2026-11-17 修复）

- **调试连不上**：DAP adapter 等 C VM debug-server hello 原本只给 20 秒；
  SnakeGame 引用 29 个包（SimGameEngine + SLangQT + Core/Std/Math），装配 +
  逐方法字节码预热实测约 27 秒才 listen，被误判超时。已把
  `slang_vscode_plugin/src/debug/dapAdapter.ts` 的等待上限改 90 秒并加每 5 秒
  进度提示（改后需 `npm run compile` 重编 `dist/extension.js`）。RenderTest
  装配仅约 6 秒、本就在 20 秒内，故此前一直可用。
- **发布跑不起来**：jsonc 原缺 `publish`/`qtRuntime` 段 → publish 只带 3 个
  Qt dll → 真窗口崩。补齐两段后 VSCode 右键「发布工程」产物开箱即跑。
- **发布后窗口空白（有窗口无画面）**：三个独立坑叠加，均已修：
  ① `QTHost` 原建两个 parent=0 顶层窗口且几何完全重合，空的那个盖住挂了
  label 的那个 → 改为单窗口（SlangKeyWidget 作主窗口，label 为其子控件）。
  ② **发布包缺 `sl_render_lib.dll`**：publish 只扫描「直接引用模块」导出
  目录里的原生库，SLangRender 是 SimGameEngine 的传递依赖故被漏掉 →
  渲染 FFI 静默失败、pixels 全 0（透明）→ QLabel 白底。修复=在 jsonc
  `references` 里**显式列出 SLangRender**（path 指向其 module.slb），
  publish 即把它连同 sl_render_lib.dll 打进 `lib\windows\`。
  ③ 启动需约 25 秒（C VM 装配 29 个包 + 逐方法字节码预热），窗口出现后
  画面才逐帧渲染；等待期间勿误判为卡死（VSCode 调试侧已有进度提示）。

验证记录（2026-11-17）：debug-server 26.5 秒连上、收到 hello、`initialize`
返回 ok:true；发布包 `SnakeGame.exe` 真窗口启动、60Hz 帧循环持续运行，
pixels 左上采样 = (31,36,31,255) 深绿背景（非 0 透明），画面含蛇/食物像素，
`lib\windows` 同时具备 sl_render_lib.dll + sl_sim_engine_lib.dll，无打点残留。
此前 offscreen+stub 全链路冒烟亦通过。

验证记录（2026-11-18，视觉/交互增强收尾）：源码清除 `lastKey` 诊断字段与
状态栏 `Key:` 显示；`slang compile --format binary` + `slang publish` 重编重发
均 EXIT=0，发布 exe 与 slb 时间戳刷新。真窗口截图确认：棋盘格深/浅背景、
绿色蛇身/高亮蛇头、红色食物、状态栏 `Score / Len / GAME OVER` 全部正常，
无 `Key:` 残留。键盘轮询方案（上一轮实证按 R 重置有效）本轮未改动逻辑。

## 玩法

方向键控制（←↑→↓）；吃红色食物 +10 分并变长（初始额外生长 2 格）；
撞墙/撞身结束，按 R 重开。网格 16×16，步进 150ms，输出 320×320 RGBA8
经 QLabel 随窗口缩放。

## 注意事项 / 已知约束

- **烘焙组数量不得超过 4**：引擎 RHI 动态网格槽只有 4 个（`SLR_CUSTOM_MESHES=4`），
  `RenderSystem` 按组轮转上传，第 5 组会与第 1 组落在同一个槽互相覆盖，导致
  渲染异常（曾表现为食物格消失）。因此棋盘深/浅、蛇、食物合并为 4 个材质组
  ——蛇头与蛇身使用同一材质色，不再单独高亮。若需新增第五种颜色，须走
  `singleObject` 直通路径或扩展 RHI 槽位数。
- **上下方向**：屏幕 Y 经渲染回读做了行翻转，网格 y 增大即屏幕向上；方向键
  映射与之一致（↑ → `dirY=+1`），并禁止 180° 直接反向。
