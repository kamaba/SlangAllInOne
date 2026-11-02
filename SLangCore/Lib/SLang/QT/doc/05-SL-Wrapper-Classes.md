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

## 10. 降级与判空（D5）

- `QT.ffi_*` 无 `slang_qt.dll` 时回退函数体返回 0 / 空 / false；封装类判定 `isValid()` 即可降级（CI 无 Qt 也能编译跑通）。
- `QT.jsonc` 的 `struct[].children` 登记全部类（`{ "class": "QT" }` 形式），保证模块导出与引用解析正确。

---

*封装类完成 SL 侧 API（已随模块编译通过）。信号槽接线见 06，构建见 07。*
