# cvm —— slQT 原生层（plugin/slqt/cvm）

slQT 的 C/C++ 粘合层，产出 `slang_qt.dll`（Linux/macOS 为 `libslang_qt.so` / `.dylib`）。
对齐 `SLang/WebUI/cvm_webui_lib` 的思路：

- **绑定层 `slang_qt.c`**：维护「Int64 句柄 ↔ 真实对象指针」注册表与信号绑定表，把全部
  `slqt_*_sl` 导出函数转发到后端实现 `slqt_be_*`。纯 C，无 Qt 依赖，自身可独立编译。
- **后端有两套实现（二选一链接）**：
  - `slang_qt_stub.c`：**纯 C 无操作**（headless）。创建返回递增伪句柄、`set*` 静默忽略、
    `app_exec` 立即返回、`connect` 仅记录 bind_id 不发射。用于**无 Qt 环境验证整条 SLang 链路**。
  - `slang_qt_qt.cpp`：**真实 Qt6 Widgets** 实现（C++）。`QObject::connect` + lambda 捕获
    `(dispatchCb, slot)`，事件发射时按信号类型调用 FFI 回调节流点重入 SLang VM。

## 构建

### 一键构建（推荐）

```powershell
# 默认 STUB（无需 Qt，headless 验证 SL 链路）：DLL + SL 模块 + 部署
powershell -ExecutionPolicy Bypass -File build-slqt.ps1

# 真实 Qt6 渲染（需 Qt6 + VC++）
powershell -ExecutionPolicy Bypass -File build-slqt.ps1 -Qt -Qt6Dir "C:\Qt\6.8.0\msvc2019_64"
```

产物：`../package/windows/slang_qt.dll` + `SlangAllInOne/out/export/SLangQT/SLangQT.module.slb`。

### 手动（单工程）

```powershell
msbuild slang_qt.vcxproj /p:Configuration=Release /p:Platform=x64        # STUB
msbuild slang_qt_qt.vcxproj /p:Configuration=Release /p:Platform=x64 `
  /p:Qt6_DIR="C:\Qt\6.8.0\msvc2019_64"                                  # Qt6
```

或在编译 SLangQT 模块时由 Front 自动构建（`../slang/QT.jsonc` 的 `vmDlls` 指向
`slang_qt.vcxproj`，产物拷入模块导出目录）。真实 Qt 版把 `vmDlls.project` 切到
`slang_qt_qt.vcxproj` 重编模块即可；运行期需 Qt6 运行库
（`Qt6Core.dll` / `Qt6Widgets.dll` / `Qt6Gui.dll`）位于 PATH 或程序目录。

> 本机 Qt 安装：`C:\Qt\qtcreator-20.0.2` 是 Qt Creator（IDE），Qt 运行/库通常在
> `C:\Qt\<版本>\msvc20xx_64`。以实际目录为准设置 `Qt6_DIR`。

## 符号约定

- 导出：`slqt_*_sl`（见 `slang_qt.h`）。参数 ≤ 6、纯标量（bool / 整数 / const char* / ptr），
  与 SLang `sl_ffi_call` 的 x64 ABI 分类对齐。
- 句柄：Int64 = 注册表插入下标；0 恒无效。
- 信号 id：`slang_qt.h` 的 `SLQT_SIG_*`，与 `QTFFI.sl` 的 `SIG_*` 逐值一致。
- 信号回调：void 信号（`clicked` 等）经 `_dispatchVoid(slot)` 调用 handler；string 信号
  （`textChanged`）经 `_dispatchString(slot, utf8)` 调用。回调在 Qt 事件循环同线程内同步重入 VM。

## 限制 / 演进

- FFI 仅 x64；参数 > 6 需描述符打包（本期未涉及）。
- 回调槽位当前按 handler 表无限增长（无 8 槽硬限制，因走 handler 表而非 FFI 回调槽）。
- 仅 Widgets 体系；QML / 绘图 / 更多控件见 `../doc/` 设计文档（10-Roadmap）。
