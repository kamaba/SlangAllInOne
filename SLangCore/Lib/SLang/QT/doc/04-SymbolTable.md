# slQT · 04 `slqt_` 符号全量表（已落地版）

- 所属文档集：`SLangCore/Lib/SLang/QT/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · **04 符号表** · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · 09 示例 · 10 路线 · 11 规范）
- 版本：v1（与 `cvm/` / `slang/QTFFI.sl` 同步）
- 三层符号映射：**C 导出** `slqt_<域>_<动作>_sl`（extern "C"）→ **SL 绑定函数** `QT.ffi_<域><动作>`（`@DllStaticImport("slang_qt", "slqt_xxx_sl")`，sig 自动推导）→ **后端实现** `slqt_be_<域>_<动作>`（`slang_qt_stub.c` / `slang_qt_qt.cpp`）。

---

## 4.1 应用域

| C 导出 | SL 绑定 (`QT.ffi_*`) | SL 签名（sig 自动推导） | 说明 |
|---|---|---|---|
| slqt_app_create_sl | ffi_appCreate | `()->i64` | 创建 QApplication，返回句柄 |
| slqt_app_set_style_sl | ffi_appSetStyle | `(utf8)` | 设置 QSS 风格名（如 "Fusion"） |
| slqt_app_set_stylesheet_sl | ffi_appSetStyleSheet | `(utf8)` | 注入全局 QSS |
| slqt_app_exec_sl | ffi_appExec | `()` | 进入 Qt 事件循环（阻塞） |
| slqt_app_process_events_sl | ffi_appProcessEvents | `()` | 非阻塞单轮 |
| slqt_app_quit_sl | ffi_appQuit | `()` | 退出事件循环 |
| slqt_app_argc_sl | ffi_appArgc | `()->i32` | 命令行参数个数 |

## 4.2 通用对象 / 基础控件

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_object_delete_sl | ffi_objectDelete | `(i64)->i64` | deleteLater + 摘除注册表项 |
| slqt_object_is_valid_sl | ffi_objectIsValid | `(i64)->bool` | 句柄仍有效？ |
| slqt_widget_create_sl | ffi_widgetCreate | `(i64)->i64` | 裸 QWidget（parent 句柄） |
| slqt_widget_set_parent_sl | ffi_widgetSetParent | `(i64,i64)` | 设置 Qt 父子关系 |
| slqt_widget_set_text_sl | ffi_widgetSetText | `(i64,utf8)` | setText / setWindowTitle（顶层） |
| slqt_widget_text_sl | ffi_widgetText | `(i64)->utf8` | text()/title() 读出（静态缓冲，即取即用） |
| slqt_widget_set_geometry_sl | ffi_widgetSetGeometry | `(i64,i32,i32,i32,i32)` | setGeometry（5 参上限内） |
| slqt_widget_resize_sl | ffi_widgetResize | `(i64,i32,i32)` | resize |
| slqt_widget_show_sl | ffi_widgetShow | `(i64)` | show() |
| slqt_widget_hide_sl | ffi_widgetHide | `(i64)` | hide() |
| slqt_widget_set_enabled_sl | ffi_widgetSetEnabled | `(i64,bool)` | setEnabled |
| slqt_widget_set_visible_sl | ffi_widgetSetVisible | `(i64,bool)` | setVisible |
| slqt_widget_set_tooltip_sl | ffi_widgetSetTooltip | `(i64,utf8)` | setToolTip |
| slqt_widget_set_style_sheet_sl | ffi_widgetSetStyleSheet | `(i64,utf8)` | 单控件 QSS |
| slqt_widget_set_fixed_size_sl | ffi_widgetSetFixedSize | `(i64,i32,i32)` | setFixedSize |
| slqt_widget_update_sl | ffi_widgetUpdate | `(i64)` | update() |

## 4.3 按钮 / 标签 / 输入

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_button_create_sl | ffi_buttonCreate | `(i64)->i64` | new QPushButton(parent) |
| slqt_label_create_sl | ffi_labelCreate | `(i64)->i64` | new QLabel(parent) |
| slqt_label_set_pixmap_sl | ffi_labelSetPixmap | `(i64,i64,i32)->i32` | 像素块设图（ptr+len；Qt 版暂未实现，返回 0） |
| slqt_edit_create_sl | ffi_editCreate | `(i64)->i64` | new QLineEdit(parent) |
| slqt_edit_set_placeholder_sl | ffi_editSetPlaceholder | `(i64,utf8)` | setPlaceholderText |
| slqt_edit_text_sl | ffi_editText | `(i64)->utf8` | text() |
| slqt_edit_set_readonly_sl | ffi_editSetReadonly | `(i64,bool)` | setReadOnly |

## 4.4 主窗口 / 对话框

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_mainwindow_create_sl | ffi_mainwindowCreate | `()->i64` | new QMainWindow() |
| slqt_mainwindow_set_central_sl | ffi_mainwindowSetCentral | `(i64,i64)` | setCentralWidget |
| slqt_mainwindow_set_title_sl | ffi_mainwindowSetTitle | `(i64,utf8)` | setWindowTitle |
| slqt_mainwindow_resize_sl | ffi_mainwindowResize | `(i64,i32,i32)` | resize |
| slqt_mainwindow_show_sl | ffi_mainwindowShow | `(i64)` | show() |
| slqt_messagebox_info_sl | ffi_messageboxInfo | `(i64,utf8,utf8)->i32` | QMessageBox::information |
| slqt_messagebox_question_sl | ffi_messageboxQuestion | `(i64,utf8,utf8)->i32` | QMessageBox::question |

## 4.5 布局

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_vbox_create_sl | ffi_vboxCreate | `(i64)->i64` | new QVBoxLayout(parent) |
| slqt_hbox_create_sl | ffi_hboxCreate | `(i64)->i64` | new QHBoxLayout(parent) |
| slqt_grid_create_sl | ffi_gridCreate | `(i64)->i64` | new QGridLayout(parent) |
| slqt_layout_add_widget_sl | ffi_layoutAddWidget | `(i64,i64)` | addWidget |
| slqt_layout_add_spacing_sl | ffi_layoutAddSpacing | `(i64,i32)` | addSpacing（仅盒布局） |
| slqt_layout_add_stretch_sl | ffi_layoutAddStretch | `(i64,i32)` | addStretch（仅盒布局） |
| slqt_layout_set_contents_margins_sl | ffi_layoutSetContentsMargins | `(i64,i32,i32,i32,i32)` | setContentsMargins（5 参） |
| slqt_layout_set_spacing_sl | ffi_layoutSetSpacing | `(i64,i32)` | setSpacing |
| slqt_layout_set_widget_at_sl | ffi_layoutSetWidgetAt | `(i64,i64,i32,i32,i32,i32)` | 网格 addWidget(w,row,col,rspan,cspan)（6 参上限内） |
| slqt_widget_set_layout_sl | ffi_widgetSetLayout | `(i64,i64)` | setLayout |

## 4.6 信号连接域（T2 回调桥）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_connect_sl | ffi_connect | `(i64,i32,i64,i64)->i64` | QObject::connect 桥；返回 bind_id（>0 成功） |

信号 id（`SLQT_SIG_*` / `QT.SIG_*`）：`CLICKED=0 / RETURN_PRESSED=1 / TRIGGERED=2 / DESTROYED=3 / TEXT_CHANGED=4`。
- 无参信号（clicked 等）→ trampoline `_dispatchVoid(slot)`：原生 `((void(*)(int64_t))cb)(slot)`。
- 字符串信号（textChanged）→ trampoline `_dispatchString(slot, utf8)`：原生 `((void(*)(int64_t,const char*))cb)(slot, s)`。

---

*符号表即契约（冻结 v1，之后只增不改）。SL 封装类如何包裹见 05，信号槽见 06。*
