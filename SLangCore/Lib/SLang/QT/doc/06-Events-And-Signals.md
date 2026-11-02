# slQT · 06 事件与信号槽机制

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · **06 信号槽** · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v0.1
- 机制依据：[`SlangAllInOne/md/project/ffi.md`](../../../SlangAllInOne/md/project/ffi.md) §2.4（回调）/ §8.6（trampoline）/ §9（限制）。

---

## 1. 总体思路（D3 / D4）

Qt 是事件驱动：`QPushButton::clicked()` 等信号在用户交互时由 Qt 事件循环发射。slQT 让这些信号**重新进入 SLang VM** 执行用户写的 SL 函数，步骤如下：

```
SL 侧                                slang_qt.dll (Qt)                       SL 回调
────────────────────────────         ───────────────────────────────────    ──────────────
cb = FFI.StaticLibrary
     .createCallback(                 slqt_connect_clicked(h, cb)
       "App.onClick","->void")  ─►      QObject::connect(btn,&QPushButton::
                                       clicked, stub)   // stub 持有 cb 句柄
btn.clicked(cb)                  ─►
                                     [用户点击]
                                        stub():
                                          vm_ffi_cb_dispatch(cb)  ─►  vm_execute_method_by_id("App.onClick")
                                                                        │
                                                                        ▼
                                                                   App.onClick() 执行
```

## 2. 回调签名兼容规则（重要）

FFI 回调要求 C 侧形参**全宽**（`ffi.md` §2.4）：整数一律 `int64_t` / `long long`，浮点 `float` / `double`。Qt 信号参数需按此约定在原生 stub 里「扩宽」后传给 VM。

| Qt 信号 | C stub 形参（全宽） | SL 回调 sig | SL 函数形态 |
|---|---|---|---|
| `QPushButton::clicked()` | 无参 | `"->void"` | `void onClick()` |
| `QLineEdit::textChanged(QString)` | `const QString&` → 转为 `char*` → 先拷入槽缓冲，再传 `const char*` | `"utf8->void"` | `void onText(string s)` |
| `QLineEdit::returnPressed()` | 无参 | `"->void"` | `void onReturn()` |
| `QObject::destroyed()` | 无参 | `"->void"` | `void onDestroy()` |
| `QAction::triggered(bool)` | `bool` → `int64_t`（0/1） | `"i64->void"` | `void onTriggered(int checked)` |

> `utf8` 返回值/参数规则：C 侧把 `QString` 转 UTF-8 拷入 FFI 回调槽静态缓冲（4KB，下一次同槽回调前有效），SL 侧 `string` 即取即用（详见 `ffi.md` §2.4 末尾警告：C 侧需即取即用）。

## 3. 两种驱动模式

### 3.1 阻塞模式（推荐，对齐 PyQt）

```sl
QApplication app = new()
...
app.exec()      # 进入 Qt 事件循环，阻塞直到所有顶层窗口关闭
```

`slqt_app_exec` 内部调 `QApplication::exec()`，事件循环在原生侧运行；点击等事件通过 06 §1 的回调重入 VM。窗口关闭后 `exec()` 返回，SL 脚本继续（通常到此结束）。

### 3.2 非阻塞模式（自写循环，适合动画/网络）

```sl
QApplication app = new()
...
app.showAll()                       # 显示所有已构建窗口
while ( app.hasVisibleWindows() )   # 伪属性：原生 slqt_app_any_visible -> bool
{
    app.processEvents()             # slqt_app_process_events：单轮派发
    myGameLogicTick()               # SL 侧自己的逻辑（如用 Std/Server 做网络轮询）
    sleep(16)
}
```

> 非阻塞模式让 SL 在事件循环之外保有主动权，但需注意：Qt 定时器/`QTimer` 在非阻塞模式下需靠 `processEvents` 驱动，长耗时 SL 逻辑会卡 UI（与 PyQt 同理）。

## 4. 回调生命周期与槽位限制

| 项 | 说明 | 对策 |
|---|---|---|
| 回调槽 ≤ 8（`SL_FFI_CB_SLOTS_MAX`） | 同时挂接的信号回调总数 ≤ 8 | 首版控件数量有限足够；若需更多，原生侧维护「handle→SL method」映射表，复用 1 个通用槽转发（M3 优化） |
| 回调 method id ≤ 191 字符 | `createCallback` 的 method 参数长度限制 | SL 静态方法用短名或完整 `Class.method` 全限定名 |
| 回调句柄需释放 | `FFI.StaticLibrary.freeCallback(cb)` | 窗口 `destroyed` 信号里释放对应回调句柄，避免槽泄漏 |
| 跨调用 utf8 缓冲失效 | `textChanged` 的 string 仅在回调体内有效 | 用户若需长期持有，立即 `string s2 = s`（SL 字符串拷贝进 GC 堆） |

## 5. 原生桥接实现要点（`qt_callback_bridge.cpp`）

```cpp
// 通用 stub：持有 cb 句柄，转调 FFI 回调派发
struct QtCbStub { int64_t cbHandle; };

// clicked 示例（无参）
static void stub_clicked(QtCbStub* s){ sl_ffi_cb_dispatch_void(s->cbHandle); }

// textChanged 示例（utf8 参数，全宽 + 槽缓冲）
static void stub_textChanged(QtCbStub* s, const QString& t){
    QByteArray b = t.toUtf8();
    sl_ffi_cb_dispatch_utf8(s->cbHandle, b.constData());   // 内部拷入槽静态缓冲
}

bool slqt_connect_clicked(int64_t h, int64_t cb){
    QPushButton* btn = qobject_cast<QPushButton*>(slqt_resolve(h));
    if(!btn) return false;
    auto* s = new QtCbStub{cb};
    QObject::connect(btn, &QPushButton::clicked, [s]{ stub_clicked(s); });
    return true;
}
```

> `sl_ffi_cb_dispatch_*` 即 FFI 回调 trampoline 重入 VM 的入口（见 `ffi.md` §8.6）；具体符号名以 cvm `src/lib/ffi/sl_ffi_callback_stubs.c` 暴露的 API 为准。

---

*信号槽机制完成事件闭环。构建系统见 07，打包见 08，示例见 09。*
