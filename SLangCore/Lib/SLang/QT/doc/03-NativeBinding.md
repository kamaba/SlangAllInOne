# slQT · 03 原生绑定契约（已落地版）

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · **03 绑定** · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v1（与 `slang/QTFFI.sl` / `cvm/` 实现同步）
- 机制依据：[`SlangAllInOne/md/project/ffi.md`](../../../SlangAllInOne/md/project/ffi.md)；实现范本 `SLang/WebUI/cvm_webui_lib`。

---

## 1. 调用策略（T1 声明式 + T2 FFI 回调）

| 级别 | 用途 | 机制 |
|---|---|---|
| **T1 原生 FFI 声明式** | 全部创建/设属性/布局/exec（≥95%） | `@DllStaticImport("slang_qt", "slqt_xxx_sl")`（**2 实参**：库名 + 符号；sig 由 SL 函数签名自动推导，见 §2） |
| **T2 FFI 回调** | 信号槽：Qt 事件回到 SL 函数 | `FFI.StaticLibrary.createCallback(method, sig)` + 原生 `connect` 桥（见 06） |

> 本库**不使用** `SystemCallExternalFunction` 字符串分发（那是 Render 的存量债）；slQT 是新库，直接上 FFI。

### 1.1 T1 —— `@DllStaticImport`（2 实参，sig 自动推导）

SLang 的 `@DllStaticImport` 仅需「库静态名 + 符号名」两个实参；FFI 调用形状（sig）**由 SL 函数签名自动推导**（bool→bool、Int32→i32、Int64→i64、string→utf8、void→void）。无 DLL 时回退执行 SL 函数体（stub）。

```sl
@DllStaticImport( "slang_qt", "slqt_app_create_sl" )
public static Int64 ffi_appCreate() { ret 0 }   # 无 slang_qt.dll 时回退：返回 0 句柄
```

SLang → C ABI 映射（sig 自动推导，无需手写）：

| SL 形参 / 返回 | 自动推导 sig | C 形参（`slqt_*_sl`） |
|---|---|---|
| `Int32` | `i32` | `int32_t` |
| `Int64` / 句柄 / 回调句柄 | `i64` | `int64_t` |
| `bool` | `bool` | `int32_t`（0/1） |
| `string` | `utf8` | `const char*`（返回走静态缓冲） |
| `void` | （省略返回段） | `void` |

### 1.2 T2 —— FFI 回调（信号槽）

```sl
Int64 cb = FFI.StaticLibrary.createCallback( "_dispatchVoid", "i64->void" )
QTFFI.ffi_connect( h, signalId, cb, slot )
```

原生侧 `slqt_connect_sl` 内部 `QObject::connect(sender, SIGNAL, lambda)`，`lambda` 调用该回调句柄重入 VM（详见 06）。

## 2. 单一绑定面：`QTFFI.sl`（类 `SLang.QT`）+ `QT.jsonc`

### 2.1 QTFFI.sl（SL 侧唯一允许 FFI 声明处）

```sl
import Core; import Std;
namespace SLang {
  public class QT {
    @DllStaticImport( "slang_qt", "slqt_app_create_sl" )
    public static Int64 ffi_appCreate() { ret 0 }
    @DllStaticImport( "slang_qt", "slqt_button_create_sl" )
    public static Int64 ffi_buttonCreate( Int64 parent ) { ret 0 }
    # … 其余 ffi_* 见 04 …
  }
}
```

所有 `@DllStaticImport` 集中在 `QT` 类（单一绑定面）；`core/`、`layout/` 封装类只调 `QT.ffi_xxx`，**不得**自己写 FFI 声明。

### 2.2 QT.jsonc 配置

```jsonc
{
  "dllImports": [
    { "path": "slang_qt.dll", "name": "slang_qt", "alias": "slang_qt", "static": "slang_qt" }
  ],
  "vmDlls": [
    { "project": "../cvm/slang_qt.vcxproj", "name": "slang_qt.dll", "configuration": "Release", "platform": "x64" }
  ]
}
```

- `"static":"slang_qt"` 是 T1 的锚；别名 `slang_qt` 供 `@DllStaticImport` 解析。
- `dllImports` 随 module 导出自动合并到引用方；运行期 VM 按 `lib/{windows|linux|macos}/` 探测。
- `vmDlls` 在编译本模块时顺带编译原生 DLL（默认 STUB 纯 C 版；真实 Qt 渲染替换为 `slang_qt_qt.vcxproj`）。

## 3. C 侧分层（实际文件）

| 文件 | 角色 |
|---|---|
| `cvm/src/slang_qt/slang_qt.h` | `slqt_*_sl` 扁平导出声明（extern "C"） |
| `cvm/src/slang_qt/slang_qt_backend.h` | 后端接口 `slqt_be_*`（stub / Qt 两套实现） |
| `cvm/src/slang_qt/slang_qt.c` | **绑定层**：句柄注册表 + 信号绑定表，把 `slqt_*_sl` 转发到 `slqt_be_*` |
| `cvm/src/slang_qt/slang_qt_stub.c` | **STUB 后端**：纯 C 无操作（headless 验证用） |
| `cvm/src/slang_qt/slang_qt_qt.cpp` | **Qt6 后端**：真实 Qt 实现（C++，lambda 回调节流点） |

### 3.1 命名与形态

- 导出符号前缀 `slqt_<域>_<动作>_sl`（全小写下划线 + `_sl` 后缀，对齐 `webui_*_sl`）。
- 句柄类型统一 `int64_t`（注册表下标）；0 恒无效。
- 后端函数 `slqt_be_<域>_<动作>`：`slqt_register(obj)` 登记，`slqt_resolve(h)` 取回指针。
- 枚举值（`SLQT_SIG_*`）与 SL 侧 `SIG_*` 逐值一致（见 `slang_qt.h` / `QTFFI.sl`）。

### 3.2 sig 规则（自动推导，禁止手写）

- 只写 2 实参 `@DllStaticImport`；sig 由 SL 函数签名推导（见 §1.1）。
- 返回 void 的函数省略返回段；string 返回走 utf8（C 侧静态缓冲，SL 侧即取即用）。
- 参数 > 6 或复合结构：描述符打包（`Memory.alloc` + `writeXxx`），以 `ptr` 传入（本期未涉及）。

---

*绑定契约已落地。符号全量表见 04，SL 封装类见 05，信号槽见 06。*
