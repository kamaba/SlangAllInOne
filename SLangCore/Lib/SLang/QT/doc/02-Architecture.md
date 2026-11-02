# slQT · 02 架构方案

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · **02 架构** · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v0.1

---

## 1. 两种架构方案对比

### 方案 A：FFI 驱动（SLang VM 宿主 ↔ `slang_qt.dll`）

```
SLang 宿主进程 (slang.exe / 宿主)
   │  SL 脚本：new QPushButton / button.clicked(cb) / app.exec()
   ▼
FFI (@DllStaticImport / createCallback)  ── x64 ABI ──►  slang_qt.dll (C++/Qt)
   │                                                     ├ QApplication
   │  Qt 事件循环 (exec) 阻塞                              ├ QWidget / QPushButton / QLabel
   │  ◄── FFI 回调 (createCallback) 重入 VM ──            └ QObject* 注册表 (int64 句柄)
   ▼
SL 用户函数（按钮点击处理等）
```

- 优点：与 `Render` 库完全同构，复用全部 FFI 机制；cvm 本体零改动；Qt 仅作为被调用的原生库，符合 R3（cvm 不含平台代码）。
- 缺点：FFI 限制（≤6 参、x64、回调槽 ≤8）需要原生侧做「描述符打包」与「回调桥」。

### 方案 B：把 SLang VM 嵌入 Qt 宿主

写一个 Qt C++ 应用程序，内部嵌入 cvm（C，需 C API），加载用户 `.sl` module，并把 Qt 对象「反向」暴露给 VM。

- 优点：天然由 Qt 主循环驱动，IDE 集成（Qt Creator）直观。
- 缺点：① cvm 是 C99、Qt 是 C++，需要一套 C↔C++ 互操作把 `QObject*` 来回传；② 反向暴露需要在 cvm 内新增「宿主对象注入」机制（改动 cvm 核心，违反 R3/R8「上游未过不改下游」且放大风险）；③ 每个 Qt 版本/平台都要重编译宿主；④ 与现有 Render 范式不一致，维护双套心智。

**结论：选方案 A。** 它把 Qt 当作「被 SLang 调用的渲染后端库」，与 `slang_render` 同构，风险最低、复用最多。方案 B 列为演进备选（若未来要做 Qt Creator 插件式调试器再评估）。

## 2. 分层设计（方案 A）

```
L3  应用逻辑   SL 用户脚本（.sl）：组装 UI、写事件处理
─────────────────────────────────────────────────────
L2  SL 封装层  QTFFI.sl（单一绑定面，含信号槽桥接）+ core/*.sl / layout/*.sl
              （QPushButton 等 SL 类包裹 int64 句柄，转发到 QTFFI）
─────────────────────────────────────────────────────
L1  原生桥     slang_qt.dll：extern "C" slqt_* 扁平函数
              + QObject* 句柄注册表 + FFI 回调桥（signal -> SL 函数）
─────────────────────────────────────────────────────
L0  渲染引擎   Qt 6（Core + Widgets），由用户机器 Qt 工具链提供
              （本仓库只交付 slang_qt.dll 的源码与构建脚本，
               运行期 Qt 运行库随 Qt 部署或打进发布包）
```

依赖规则：只允许上层引用下层（L3 引用 L2，L2 引用 L1，L1 引用 L0）。SL 封装类**禁止**直接写 `@DllStaticImport`，一律调 `QTFFI.sl` 的静态函数（D6）。

## 3. 一次交互的数据流（目标态）

```
SL 脚本                                    slang_qt.dll (Qt)                  SL 回调
─────────────────────────────────         ─────────────────────────────      ───────────
QApplication app = new()        ─►  slqt_app_create()  -> 注册 QApplication*
QPushButton btn = new()         ─►  slqt_button_create() -> 句柄 h
btn.setText("Click")            ─►  slqt_widget_set_text(h, "Click")
btn.clicked( App.onClick )      ─►  slqt_connect_clicked(h, cbHandle)
                                  Qt: QObject::connect(btn,"clicked()",stub)
app.exec()                      ─►  QApplication::exec()  [阻塞]
                                            │ 用户点击
                                            ▼
                                  stub(): FFI.StaticLibrary 回调槽 -> vm_execute_method_by_id(onClick)
                                            ▼
                                   onClick() 执行（可改 label、计数等）
                                  exec() 返回（窗口关闭）
```

要点：
- `app.exec()` 在原生侧**阻塞**进入 Qt 事件循环；点击等事件通过**预先注册的 FFI 回调**重入 VM（机制见 `ffi.md` §2.4 / §8.6）。
- 若用户希望自己控制循环（如在 SL 里做动画/网络轮询），改用 `slqt_app_process_events()` 单轮 + SL `while` 循环（非阻塞模式，06 §3）。

## 4. 句柄与生命周期约定（D2）

- 每个 Qt 对象在原生侧注册表以 `int64` 句柄返回；SL 端只持句柄。
- 父子关系由 Qt 自身管理（`slqt_widget_set_parent(handle, parentHandle)`）：父销毁自动析构子，注册表用 `QPointer` 自动失效。
- 显式删除：`slqt_object_delete(handle)` —— 从注册表摘除并 `deleteLater()`。
- **0 句柄恒为无效**；创建类函数失败返回 0，SL 封装层应判 0 并报错/降级。

---

*架构已定。绑定契约细节见 03，符号表见 04，SL 封装类见 05，信号槽见 06。*
