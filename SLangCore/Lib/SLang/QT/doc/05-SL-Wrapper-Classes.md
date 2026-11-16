# slQT · 05 SL 侧封装类设计（已落地版）

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · **05 封装类** · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v1（与 `QTFFI.sl` / `core/` / `layout/` 同步）

---

## 1. 约定

- 所有封装类位于 `namespace SLang`，基类 `QObject`（持 `Int64 _handle`）。
- **SLang 对象创建语法是 `ClassName(args)`（不带 `new` 关键字）**，构造函数即 `_init_`；跨命名空间带参构造受限，统一走 `QT` 门面的**工厂方法**（`QT.newButton` 等）。
- 封装类**只持句柄**，全部操作转发到 `QT.ffi_xxx`；构造里调 `setHandle(QT.ffi_xxxCreate(parent))` 避免覆盖 `_init_` 递归。
- `@DllStaticImport` 仅在 `QT` 类出现（单一绑定面），封装类不写 FFI 声明。

## 2. 基类 `QObject`（core/QObject.sl）

```sl
namespace SLang {
  public class QObject {
    Int64 _handle = 0
    _init_() {}
    public void setHandle( Int64 h ) { this._handle = h }   # 子类构造用
    public void _init_( Int64 handle ) { this._handle = handle }
    get Int64 handle() { ret this._handle }
    get bool isValid() { ret this._handle != 0 && SLang.QT.ffi_objectIsValid( this._handle ) }
    public void delete() { SLang.QT.ffi_objectDelete( this._handle ); this._handle = 0 }
  }
}
```

## 3. `QWidget`（core/QWidget.sl）

```sl
public class QWidget extends QObject {
  _init_( Int64 parent ) { this.setHandle( SLang.QT.ffi_widgetCreate( parent ) ) }
  public void setText( string t ) { SLang.QT.ffi_widgetSetText( this.handle, t ) }
  public void setTitle( string t ) { SLang.QT.ffi_widgetSetText( this.handle, t ) }  # 顶层=窗口标题
  public string text() { ret SLang.QT.ffi_widgetText( this.handle ) }
  public void resize( int w, int h ) { SLang.QT.ffi_widgetResize( this.handle, w, h ) }
  public void show() { SLang.QT.ffi_widgetShow( this.handle ) }
  public void hide() { SLang.QT.ffi_widgetHide( this.handle ) }
  public void setEnabled( bool on ) { SLang.QT.ffi_widgetSetEnabled( this.handle, on ) }
  public void setVisible( bool on ) { SLang.QT.ffi_widgetSetVisible( this.handle, on ) }
  public void setLayout( SLang.QLayout layout ) { SLang.QT.ffi_widgetSetLayout( this.handle, layout.handle ) }
}
```

## 4. `QPushButton`（core/QPushButton.sl）

```sl
public class QPushButton extends QWidget {
  _init_( Int64 parent ) { this.setHandle( SLang.QT.ffi_buttonCreate( parent ) ) }
  # 连接 clicked（无参）；返回 bind_id > 0 表示成功（headless 也可据此校验）
  public Int64 clicked( Function handler ) { ret SLang.QT.connect( this.handle, SLang.QT.SIG_CLICKED, handler ) }
}
```

## 5. `QLabel` / `QLineEdit`

```sl
public class QLabel extends QWidget {
  _init_( Int64 parent ) { this.setHandle( SLang.QT.ffi_labelCreate( parent ) ) }
}
public class QLineEdit extends QWidget {
  _init_( Int64 parent ) { this.setHandle( SLang.QT.ffi_editCreate( parent ) ) }
  public void setPlaceholder( string p ) { SLang.QT.ffi_editSetPlaceholder( this.handle, p ) }
  public string text() { ret SLang.QT.ffi_editText( this.handle ) }   # 覆盖 QWidget.text()
  public void setReadOnly( bool on ) { SLang.QT.ffi_editSetReadonly( this.handle, on ) }
  public Int64 onTextChanged( Function handler ) { ret SLang.QT.connect( this.handle, SLang.QT.SIG_TEXT_CHANGED, handler ) }
  public Int64 onReturnPressed( Function handler ) { ret SLang.QT.connect( this.handle, SLang.QT.SIG_RETURN_PRESSED, handler ) }
}
```

## 6. `QMainWindow`（core/QMainWindow.sl）

```sl
public class QMainWindow extends QObject {
  _init_() { this.setHandle( SLang.QT.ffi_mainwindowCreate() ) }
  public void setCentralWidget( SLang.QWidget w ) { SLang.QT.ffi_mainwindowSetCentral( this.handle, w.handle ) }
  public void setTitle( string t ) { SLang.QT.ffi_mainwindowSetTitle( this.handle, t ) }
  public void resize( int w, int h ) { SLang.QT.ffi_mainwindowResize( this.handle, w, h ) }
  public void show() { SLang.QT.ffi_mainwindowShow( this.handle ) }
}
```

## 7. `QApplication`（core/QApplication.sl）

```sl
public class QApplication extends QObject {
  _init_() { this.setHandle( SLang.QT.ffi_appCreate() ) }
  public void setStyle( string name ) { SLang.QT.ffi_appSetStyle( name ) }
  public void exec() { SLang.QT.ffi_appExec() }              # 阻塞进入事件循环
  public void processEvents() { SLang.QT.ffi_appProcessEvents() }  # 非阻塞单轮
  public void quit() { SLang.QT.ffi_appQuit() }
}
```

## 8. 布局类（layout/*.sl）

```sl
public class QLayout extends QObject {
  public void addWidget( SLang.QWidget w ) { SLang.QT.ffi_layoutAddWidget( this.handle, w.handle ) }
  public void addSpacing( int px ) { SLang.QT.ffi_layoutAddSpacing( this.handle, px ) }
  public void addStretch( int s ) { SLang.QT.ffi_layoutAddStretch( this.handle, s ) }
  public void setContentsMargins( int l,int t,int r,int b ) { SLang.QT.ffi_layoutSetContentsMargins( this.handle, l, t, r, b ) }
  public void setSpacing( int px ) { SLang.QT.ffi_layoutSetSpacing( this.handle, px ) }
}
public class QVBoxLayout extends QLayout { _init_( Int64 parent ) { this.setHandle( SLang.QT.ffi_vboxCreate( parent ) ) } }
# QHBoxLayout / QGridLayout 同构；QGridLayout 多 addWidgetAt(w,row,col,rspan,cspan)
```

## 9. 工厂（规避带命名空间 new 的限制）

`QT` 类提供 `newApp()` / `newButton(parent,text)` / `newLabel` / `newLineEdit` / `newWidget` / `newMainWindow` / `newVBox` / `newHBox` / `newGrid`，内部用 `ClassName(args)`（不带 new）构造后返回。示例与测试统一走工厂。

## 9.1 原生选项控件封装类（2026-11-15 第二十三轮增补，只增不改）

三个新类均在 `namespace SLang` 且 `extends QWidget`，构造统一走 `QT` 门面工厂 `newComboBox(parent)` / `newCheckBox(parent,text)` / `newTableWidget(parent)`：

| 类 | 方法 | FFI |
|---|---|---|
| `QComboBox` | `addItem(string)` / `count()` / `currentIndex()` / `setCurrentIndex(int)` | `ffi_combo*` |
| `QCheckBox` | `isChecked()` / `setChecked(bool)`（SL 侧转 0/1） | `ffi_check*` |
| `QTableWidget` | `setColumnCount(int)` / `setRowCount(int)` / `setHeaders(string csv)` / `setItem(int,int,string)` / `clearItems()` | `ffi_table*` |

`QTreeWidget` 增 `setCurrentPath(string path)`（按累计路径 `setCurrentItem`，不新增信号）。`QTableWidget` 创建即只读（`NoEditTriggers` + `SelectRows` + `AlternatingRowColors`），不承担编辑职责；`setHeaders` 收逗号分隔 csv，`clearItems` 只清内容不清表头。stub 后端 create 返回安全空句柄、`count=0` / `currentIndex=-1` / `isChecked=false`，调用方须对 `-1` 做回落（IDE 向导已按第 0 项兜底）。符号全量见 [04 §4.8](04-SymbolTable.md)。

## 9.2 表格行回调与树节点底纹（2026-11-15 第二十四轮增补，只增不改）

| 类 | 新增方法 | 契约 |
|---|---|---|
| `QTableWidget` | `currentRow()` | 无当前项返回 -1；stub 恒 -1 |
| `QTableWidget` | `onRowClicked(Function)` | `SIG_TABLE_ROW_CLICKED=14`；handler 形态 `static void onTableRow(int row)`，点任意单元格都触发，列号不传 |
| `QTreeWidget` | `setItemBackground(string path, int rgb)` | 淡色底纹，与前/背景色同用路径定位 |
| `QTreeWidget` | `setItemBold(string path, int on)` | 1=加粗 / 0=取消，字体其余属性保留 |

`QSplitter` 已于 D-05 登记（工厂 `QT.newSplitter(parent, vertical)`、`addWidget(QWidget)`、`setSizes(a,b,c)`）；本轮 IDE 属性页用它做左右分栏 + 右侧上下分栏，**QT 能力本身零改动**。符号全量见 [04 §4.9](04-SymbolTable.md)，信号槽见 [06](06-Events-And-Signals.md)。

## 9.3 值列就地编辑（2026-11-15 第二十五轮增补，只增不改）

`QTableWidget` 创建时仍是只读（`NoEditTriggers + SelectRows`）；要允许编辑，须在填完单元格后**逐格**开启：

| 方法 | 契约 |
|---|---|
| `setItemEditable(int row, int col, int on)` | 1 = 加 `Qt::ItemIsEditable`，0 = 去掉；只应对标量的值列开户 |
| `itemText(int row, int col)` | 读回单元格文本；无 item / stub 返回 `""` |
| `onItemChanged(Function handler)` | `SIG_TABLE_ITEM_CHANGED=15`；handler 形态 `static void onTableItemChanged(int row)`，列号由调用方固定为值列 |

`slqt_be_table_set_item` 与 `slqt_be_table_set_item_editable` 内部有 `QSignalBlocker`，**程序化填充不会触发 `onItemChanged`**；只有真实用户编辑会触发。IDE 侧另有 `fillingTable` 静态守卫做第二道保险。符号见 [04 §4.10](04-SymbolTable.md)，信号见 [06 §6](06-Events-And-Signals.md)。

## 9.4 QSpinBox 与节点图标（2026-11-15 第二十六轮增补，只增不改）

新增 `core/QSpinBox.sl`（`extends QWidget`，`namespace SLang`），工厂 `QT.newSpinBox(parent)`：

| 方法 | 契约 |
|---|---|
| `setRange(int min, int max)` / `setValue(int v)` / `value()` | 原生整数输入；stub 的 `value()` 恒 0 |
| `onValueChanged(Function handler)` | `SIG_SPIN_VALUE_CHANGED=16`；handler 形态 `static void onSpinValueChanged(int v)` |

`core/QTreeWidget.sl` 增 `setItemIcon(string path, int iconId)`，id 映射 Qt 标准图标：0 文件 / 1 目录 / 2 警告 / 3 应用（勾选）/ 4 取消；未知 id 静默忽略。图标取自 `QApplication::style()`，**不需要打包任何图片资源**。符号见 [04 §4.11](04-SymbolTable.md)，信号见 [06 §7](06-Events-And-Signals.md)。

## 9.5 QTabBar 与窗口关闭请求（2026-11-16 第二十七轮增补，只增不改）

新增 `core/QTabBar.sl`（`extends QWidget`，`namespace SLang`），工厂 `QT.newTabBar(parent)`：

| 方法 | 契约 |
|---|---|
| `addTab(string title)` | 追加标签，返回新下标 |
| `removeTab(int idx)` / `setCurrentIndex(int idx)` | 删标签 / 切换当前 |
| `currentIndex()` / `count()` / `tabText(int idx)` | 无标签 -1；越界文本为空串 |
| `onCurrentChanged(Function handler)` | `SIG_TABBAR_CHANGED=17`；handler 形态 `static void onTabbarChanged(int idx)` |

`core/QMainWindow.sl` 增：

| 方法 | 契约 |
|---|---|
| `onCloseRequested(Function handler)` | `SIG_CLOSE_REQUESTED=18`；订阅后点 X 不直接关窗（Close 被过滤器 ignore），handler 形态 `static void onCloseRequest(int payload)` |
| `close()` | 程序化关窗，绕过关闭过滤器；确认退出时由 handler 链调用 |

符号见 [04 §4.12](04-SymbolTable.md)，信号见 [06 §8](06-Events-And-Signals.md)。

## 9.6 QMessageBox（2026-11-16 第二十八轮增补，部分实现回补）

总纲 §3.3「无 SL 封装类但已有 FFI」欠账清零：`slqt_messagebox_info_sl` / `slqt_messagebox_question_sl` 的 C++ 实现早已在（[04 §「主窗口/对话框」](04-SymbolTable.md)），本轮只补 SL 封装类。新增 `core/QMessageBox.sl`（`extends QObject` **静态工具类**，不实例化、无工厂）：

| 方法 | 契约 |
|---|---|
| `QMessageBox.information(parent, title, text)` | 原生模态信息框（Ok），返回 `Qt::StandardButton` 值 |
| `QMessageBox.question(parent, title, text)` | 原生模态询问框（Yes\|No），返回被点按钮值 |

常用返回值：`Ok=1024` / `Yes=16384` / `No=65536` / `Cancel=4194304`；调用阻塞至弹窗关闭。FFI 零新增、信号不变、**struct 49→50**（`QT.jsonc` 的 `compileFiles` / `struct.children` 已登记）。IDE 现有 `ConfirmDialog` 为自绘对话框，与本类并存。

## 9.7 QAction 快捷键（2026-11-16 第二十九轮增补）

`core/QAction.sl` 增 `setShortcut(string keys)`（`QKeySequence` 可移植串：`"Ctrl+S"` / `"F5"` / `"Shift+F5"`，空串清除）；菜单项文本右侧由 Qt 自动显示快捷键。**同一命令的菜单与工具栏是两个独立 QAction，快捷键只绑一侧**（两侧都绑会一次按键触发两次）。符号见 [04 §4.13](04-SymbolTable.md)。

## 9.8 QTextBrowser（2026-11-16 第三十轮增补）

新增 `core/QTextBrowser.sl`（**`extends QTextEdit`**——首个封装类继承链先例：子类 `_init_` 自建句柄，基类 `setPlainText` / `toPlainText` / `setReadOnly` / `append` 经 `this.handle` 原生转发），工厂 `QT.newTextBrowser(parent)`：

| 方法 | 契约 |
|---|---|
| `setMarkdown(string md)` | 整体替换内容并按 Qt6 原生 Markdown 渲染（标题/列表/代码块/链接） |
| 继承自 QTextEdit | `setPlainText` / `toPlainText` / `setReadOnly` / `append` 直接可用 |

QTextBrowser 天然只读（不可编辑源文本），适用于内置帮助/文档查看器。**有效 FFI 269→271、struct 50→51**。符号见 [04 §4.14](04-SymbolTable.md)。

第三十二轮增：`setDocument(string path, string md)`（以 path 目录为 base → 文档内相对 `.md` 链接可点击跳转）、`currentSource()`（当前文档绝对路径）、`onNavigated(Function handler)`（`SIG_BROWSER_NAVIGATED=19`，handler 形态 `static void onNavigated(int payload)`）。符号见 [04 §4.14.1](04-SymbolTable.md)，信号见 [06 §9](06-Events-And-Signals.md)。

## 10. 降级与判空（D5）

- `QT.ffi_*` 无 `slang_qt.dll` 时回退函数体返回 0 / 空 / false；封装类判定 `isValid()` 即可降级（CI 无 Qt 也能编译跑通）。
- `QT.jsonc` 的 `struct[].children` 登记全部类（`{ "class": "QT" }` 形式），保证模块导出与引用解析正确。

---

*封装类完成 SL 侧 API（已随模块编译通过）。信号槽接线见 06，构建见 07。*
