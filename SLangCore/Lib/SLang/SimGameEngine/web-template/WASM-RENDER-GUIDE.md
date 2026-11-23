# SimGameEngine Web（wasm + WebGL2）渲染接入指南与模板

> 适用范围：任何 SL 工程，想在浏览器里用 **SimGameEngine（渲染/音频/输入/时间）** 显示渲染内容。
> 参考实现：`SlangAllInOne/SLangCore/samples/SnakeGame/web/`（贪吃蛇 web 演示，已完整验证）。
> 模板位置：`SlangAllInOne/SLangCore/Lib/SLang/SimGameEngine/web-template/template/`。

---

## 1. 架构总览

一句话：**引擎整体跑在 wasm 里，页面只是"平台后端"——注入事件 + 上屏像素，没有帧协议**。

```
浏览器                                     wasm 二进制（csimple_lang_game）
┌─────────────────────────────┐            ┌────────────────────────────────────┐
│ index.html                  │            │  SL VM（cvm 解释器 + ASYNCIFY）      │
│  ├ canvas (WebGL2 ctx)      │◄── EGL ────┤   └ 主模块 .slb（WebHost + 游戏）    │
│  ├ app.js                   │            │      └ 依赖模块 Core/Std/Math/...   │
│  │   ├ 输入注入  ────────────┼──事件──────►│  sl_sim_engine_lib（C）             │
│  │   ├ 呈现 blit ◄───────────┼──像素───────┤   ├ sle_web_blit → EM_JS 回调       │
│  │   └ 音频 resume ◄─────────┼──AudioCtx──┤   └ 输入状态表 sle_input_*          │
│  └ server.js（静态服务）     │            │  sl_render_lib → GLES RHI → WebGL2  │
└─────────────────────────────┘            │  sl_audio_lib → WebAudio 环形缓冲    │
                                           └────────────────────────────────────┘
```

两条像素路径都落在**同一个 WebGL2 context**：

- **渲染**：引擎 EGL shim（`-sUSE_EGL`）在 `Module.canvas` 上建 WebGL2 上下文，GLES RHI 全部 13 阶段管线（FBO/UBO/光照/阴影）在 wasm 内完成，产出 RGBA8 像素块；
- **呈现**：`rs.frame` readback → `sle_web_blit` → JS `onBlit` → `texImage2D` + 全屏三角贴图。

游戏逻辑层（Behaviour）只走引擎公开 API，对 web 宿主零依赖——同一份逻辑层桌面可跑（换 QTHost），web 也可跑（换 WebHost）。

---

## 2. 演示工程逐层逻辑（SnakeGame/web）

### 2.1 构建产物链（两条独立产物线）

| 产物 | 命令 | 输出 |
|---|---|---|
| SL 主模块 | `web/compile.ps1`（slang.exe 编译 `SnakeGameWeb.jsonc`） | `out/export/SnakeGameWeb/SnakeGameWeb.module.slb` |
| wasm 引擎载体 | `csimple_lang/scripts/cmake-build-wasm.ps1 -Game -Configuration Release` | `csimple_lang/build/Wasm/bin/csimple_lang_game.{js,wasm}` |

改 `.sl` 只需跑 compile.ps1（SLB 由 server 直接从构建树服务，无需重链 wasm）；改 C 侧才需要重链。

**wasm 目标组成**（`csimple_lang/CMakeLists.txt` game 目标，关键 EXTRA_SOURCES）：

- `sl_ffi_wasm_shims.c` —— @DllStaticImport 的 i64/double 形状包装（wasm `call_indirect` 签名严格）
- `sle_engine.c` + `sle_web_glue.c` —— 输入表/时钟/节点注册 + web 平台桥
- `cvm_math_lib/*.c` —— Math 模块系统方法（`mathvm_mat4f_*` 等）
- `sl_render.c` + `Pipeline/*` + `RHI/sl_rhi_gles.c` —— 渲染管线 + GLES 后端（排除 gl/vk/d3d11）
- `sl_audio.c` + `Codec/*` + `sl_audio_wave_web.c` —— 音频解码 + WebAudio 输出（排除 winmm/MF）
- 编译参数：`-sUSE_EGL=1`（EGL shim）、`MAX_WEBGL_VERSION=2`、`FULL_ES3=1`、ASYNCIFY、gnu11

### 2.2 index.html

纯页面壳。唯一硬约定：`<canvas id="cv" width="320" height="320">` 存在，**width/height 属性 = 渲染分辨率**（CSS 显示尺寸可任意缩放），`#status` 用于状态/日志输出。

### 2.3 game.js（页面宿主，模板化为 `app.js`）

职责四件事：

1. **资源装载**：fetch 主模块 SLB + 7 个依赖模块（json+slb）+ 工程资源（sfx/fairyui），`Promise.all` 后写 MEMFS **同构目录** `/work/out/export/<模块名>/<模块名>.module.{json,slb}` —— 与桌面 `out/export` 布局完全一致，SL 装载器按此布局解析 import 依赖。这是页面侧唯一的布局契约。
2. **boot**：动态加载 `wasm/csimple_lang_game.js` → `createModule({ canvas, print, printErr, noInitialRun: true })` → `callMain(['run', '--no-banner', '/work/.../主模块.slb'])`。
3. **呈现**：初始化独立呈现 program（全屏三角 + `u_tex`）；每帧 blit 回调里 `texImage2D` 上屏。**每次 blit 必须完整恢复呈现 GL 状态**（引擎渲染会改写 program/activeTexture/attrib 绑定，不复位 → GL_INVALID_OPERATION + 黑屏）。
4. **输入/音频**：`keydown/keyup → _sle_input_set_key(Qt码, down)`；`mousemove/mousedown → _sle_input_set_mouse_pos/button`（CSS 坐标换算回画布像素 + `MOUSE_OFFSET=10` 补偿）；首个手势 `AudioContext.resume()`。

### 2.4 WebHost.sl（SL 宿主层）

```
initializeBackend("gles") → RenderSystem.init(320,320) → Scene + Behaviour 组件
→ Application.init/loadScene → 主循环：
   a.tick(-1)                 # 引擎 C 单调钟实测 dt → fixedUpdate×N → 生命周期
   hostRs.frame(0, pixels)    # 渲染 + readback 到像素缓冲
   ffiWebBlit(pixels, w, h)   # → sle_web_blit → JS onBlit 上屏
   inp.endFrame()             # 清输入按下边沿
   OS.Timer.sleep(16)         # ASYNCIFY 挂起，让出浏览器事件循环
```

平台桥 FFI（`@DllStaticImport("sl_sim_engine_lib", ...)`）：

| 函数 | 签名 | 作用 |
|---|---|---|
| `sle_web_blit` | `i64,i32,i32->i32` | 像素块（指针/w/h）→ JS 上屏 |
| `sle_web_window_width/height` | `->i32` | 引擎查询画布尺寸 |

**EM_JS 回调契约名**（`sle_web_glue.c` 固定查找，页面侧必须提供）：
`Module.__snakeOnBlit(ptr,w,h)`、`Module.__snakeCanvasWidth()`、`Module.__snakeCanvasHeight()`。

### 2.5 server.js

零依赖静态服务，路由把虚拟路径映射到**构建产物原位**（重构建免拷贝）：
`/wasm/csimple_lang_game.*` → `csimple_lang/build/Wasm/bin/`；`/mod/*.module.{json,slb}` → `SlangAllInOne/out/export/`；其余映射页面目录/资源目录。

---

## 3. 用模板快速接入新工程

模板文件（`web-template/template/`）：

| 文件 | 说明 | 需要改吗 |
|---|---|---|
| `index.html` | 页面壳 | 改标题/样式；canvas 尺寸对齐渲染分辨率 |
| `app.js` | 通用 web 宿主 | **只改顶部 `APP_CONFIG`** |
| `server.js` | 静态服务 | 改 `ROOT_MODULE`（其余通用） |
| `WebHost.sl` | SL 宿主层 | 把 `MyGameBehaviour` 换成你的 Behaviour，调相机参数 |

### 五步接入

1. **写游戏逻辑层**：一个 `XxxBehaviour`（参考 `SnakeGameBehaviour.sl`）：`_init_`/`start()`/`update()` 生命周期，经引擎 API 建网格/材质/DrawCall；输入经 `InputSystem.wasPressed(Qt码)` 查询（帧尾宿主统一 `endFrame()`）。
2. **写 jsonc + WebHost**：复制模板 `WebHost.sl`，替换 Behaviour 与相机参数；jsonc imports 含 `SimGameEngine`、`SLangRender`（+按需 `SLangAudio`/`SLangImage`）；入口 = `WebHost.run()`。
3. **改 `app.js` 的 `APP_CONFIG`**：`rootModuleName`/`rootSlbUrl`/`rootSlbMemPath`、`depMods`（按 jsonc 实际 import 增减）、`assets`（url↔MEMFS 路径）、`renderWidth/Height`。
4. **改 `server.js`**：`ROOT_MODULE`；工程资源放 `assets/` 目录。
5. **构建**：
   - SL：仿照 `samples/SnakeGame/web/compile.ps1`（成功判据 = slb 时间戳被重写）；
   - wasm：`cmake-build-wasm.ps1 -Game`（若引擎 C 侧无改动，产物直接复用）；
   - `node server.js 8080` → 浏览器打开，点击画布恢复声音。

### 参数契约速查

| 契约 | 值 | 出错表现 |
|---|---|---|
| MEMFS 布局 | `/work/out/export/<Name>/<Name>.module.{json,slb}` | 模块装载失败 |
| EM_JS 回调名 | `__snakeOnBlit` / `__snakeCanvasWidth` / `__snakeCanvasHeight` | 黑屏（blit 找不到回调） |
| 键码 | Qt::Key 枚举（字母=ASCII，方向键=0x01000000+） | 按键无响应 |
| 帧尾 | `input.endFrame()` 每帧一次 | 按键边沿永久残留（连发） |
| blit 状态恢复 | 每次上屏前恢复 program/texture/attrib/viewport | GL_INVALID_OPERATION + 黑屏 |
| canvas 属性 | width/height = 渲染分辨率 | 画面拉伸/坐标错位 |

---

## 4. 已踩过的坑（排查时先看这里）

1. **wasm32 对象布局**：扩展 C 代码里硬编码 x64 结构偏移（如 VMObject 的 `member_data_size` 在 x64 是 16，wasm32 是 **12**）会静默校验失败。镜像结构必须按 `__wasm__` 条件选择偏移。
2. **mathvm/系统方法导出面**：jsonc `"cvmFunction": "xxx.dll!sym"` 声明的符号必须出现在 wasm 导出面（`EXPORTED_FUNCTIONS` 由 `csimple_lang/build/extract_ffi_syms.js` + `filter_ffi_syms.js` 生成，改 jsonc 后需重建导出清单并强链）。
3. **dlopen 主模块自解析**：wasm 下 FFI 符号在主模块内，装载用 `dlopen(NULL, RTLD_NOW)`，不要短路返回 NULL（NULL 占位会永久封死后续惰性重解析）。
4. **EM_ASM 宏**：花括号内禁裸逗号（含数组字面量），用 push 风格或无参宏；`EM_ASM({...}, args)` 用 `$0/$1` 或 `arguments[i]` 取参。
5. **GL 状态互踩**：引擎 GLES 渲染与 JS 呈现共享 context，见上"blit 状态恢复"。
6. **EGL shim 限制**：shim 未实现 pbuffer（存根恒 NULL），绑定路径固定 surfaceless；shim 函数是 JS 库实现，禁止对其取函数指针（用普通包装函数直调）。
7. **音频自动播放**：首次手势前 AudioContext 处于 suspended，页面必须在 `mousedown/keydown` 里 resume。
8. **ASYNCIFY**：`OS.Timer.sleep(16)` 是让出点——浏览器事件循环靠它运行；宿主主循环不能去掉 sleep，否则页面卡死。
9. **输入边沿**：`sle_input_set_key` 只在 down 且 prev==0 时置 pressed 边沿（自动重复不去重会破坏边沿语义）；边沿由 `endFrame` 帧尾清零。
10. **构建成功判据**：slang.exe 退出码不可靠，以 **slb 时间戳被重写** 为准（compile.ps1 已内置校验）。
11. **桌面回归隔离**：wasm game 目标产物独立命名（`csimple_lang_game.*`），不覆盖官网/async 现役产物；C 侧平台分支一律包 `__EMSCRIPTEN__` 宏。

---

## 5. 调试入口

- 浏览器控制台：`window.__mod` 可达全部 wasm 导出（如 `__mod._sle_input_down(16777235)` 直接查输入表）；`print/printErr` 通道把 SL `Console.println` 打到页面 `#status` 区。
- 初始化失败定位：`sl_rhi_gles.c` 的 `GLESTRI` 宏在 gl_init 各失败点直打页面状态区（仅 init 期，无每帧开销）。
- 分层排查顺序：页面资源 404？→ wasm 加载？→ `[WebHost] initializeBackend(gles) -> True`？→ RenderSystem.init？→ 每帧 blit 计数增长？（可在 onBlit 里临时计数）→ 呈现 program 状态恢复？
