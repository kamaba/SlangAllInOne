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

## 4.7 树节点样式 / 展开态 / tooltip（2026-11-14 第二十一轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_tree_expand_all_sl | ffi_treeExpandAll | `(i64)` | QTreeWidget::expandAll |
| slqt_tree_collapse_all_sl | ffi_treeCollapseAll | `(i64)` | QTreeWidget::collapseAll |
| slqt_tree_set_item_expanded_sl | ffi_treeSetItemExpanded | `(i64,utf8,i32)` | 按累计路径定位节点并 setExpanded(on) |
| slqt_tree_item_expanded_sl | ffi_treeItemExpanded | `(i64,utf8)->i32` | 节点 isExpanded，1/0 |
| slqt_tree_set_item_foreground_sl | ffi_treeSetItemForeground | `(i64,utf8,i32)` | setForeground(0, QBrush(QColor(rgb)))，rgb=0xRRGGBB |
| slqt_tree_set_item_tooltip_sl | ffi_treeSetItemTooltip | `(i64,utf8,utf8)` | setToolTip(0, utf8) |

新增信号 id：`SLQT_SIG_TREE_DOUBLE_CLICKED = 13`（QTreeWidget::itemDoubleClicked，utf8 载荷 = 节点完整路径，经 `_dispatchString` 重入 VM）。旧信号 0~12 取值与行为不变。

---

## 4.8 原生选项控件 / 只读属性表（2026-11-15 第二十三轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_combo_create_sl | ffi_comboCreate | `(i64)->i64` | new QComboBox(parent) |
| slqt_combo_add_item_sl | ffi_comboAddItem | `(i64,utf8)` | addItem |
| slqt_combo_count_sl | ffi_comboCount | `(i64)->i32` | count |
| slqt_combo_current_index_sl | ffi_comboCurrentIndex | `(i64)->i32` | currentIndex（空表 / stub 返回 -1） |
| slqt_combo_set_current_index_sl | ffi_comboSetCurrentIndex | `(i64,i32)` | setCurrentIndex |
| slqt_check_create_sl | ffi_checkCreate | `(i64,utf8)->i64` | new QCheckBox(parent, text) |
| slqt_check_is_checked_sl | ffi_checkIsChecked | `(i64)->i32` | isChecked，1/0 |
| slqt_check_set_checked_sl | ffi_checkSetChecked | `(i64,i32)` | setChecked(on != 0) |
| slqt_table_create_sl | ffi_tableCreate | `(i64)->i64` | new QTableWidget；NoEditTriggers + SelectRows + AlternatingRowColors |
| slqt_table_set_column_count_sl | ffi_tableSetColumnCount | `(i64,i32)` | setColumnCount |
| slqt_table_set_row_count_sl | ffi_tableSetRowCount | `(i64,i32)` | setRowCount |
| slqt_table_set_headers_sl | ffi_tableSetHeaders | `(i64,utf8)` | 逗号 csv → setHorizontalHeaderLabels + stretchLastSection |
| slqt_table_set_item_sl | ffi_tableSetItem | `(i64,i32,i32,utf8)` | 越界静默忽略；复用已有 QTableWidgetItem |
| slqt_table_clear_sl | ffi_tableClear | `(i64)` | clearContents + setRowCount(0)，表头保留 |
| slqt_tree_set_current_path_sl | ffi_treeSetCurrentPath | `(i64,utf8)` | 按累计路径 setCurrentItem（不新增 SIG_*） |

新增 SL 封装类 `core/QComboBox.sl` / `core/QCheckBox.sl` / `core/QTableWidget.sl`（`QT.jsonc` 的 `compileFiles` 与 `struct.children` 同步登记）；`core/QTreeWidget.sl` 增 `setCurrentPath(path)`。**有效 FFI 235 → 250、struct 44 → 47、信号仍 14**（无新增 `SLQT_SIG_*`，旧信号 0~13 取值与行为不变）。

---

## 4.9 表格行读取 / 树节点底纹（2026-11-15 第二十四轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_table_current_row_sl | ffi_tableCurrentRow | `(i64)->i32` | QTableWidget::currentRow，无当前项 / stub 返回 -1 |
| slqt_tree_set_item_background_sl | ffi_treeSetItemBackground | `(i64,utf8,i32)` | 按累计路径 setBackground(0, QBrush(QColor(rgb))) |
| slqt_tree_set_item_bold_sl | ffi_treeSetItemBold | `(i64,utf8,i32)` | QFont::setBold(on != 0) 后 setFont(0, f) |

新增信号 id `SLQT_SIG_TABLE_ROW_CLICKED = 14`（`QTableWidget::cellClicked`，int 载荷 = 行号 → `_dispatchInt`，列号丢弃）；旧信号 0~13 取值与行为不变。`core/QTableWidget.sl` 增 `currentRow()` / `onRowClicked(Function)`，`core/QTreeWidget.sl` 增 `setItemBackground(path,rgb)` / `setItemBold(path,on)`。本轮不新增 `.sl`，`QT.jsonc` 无需改。**有效 FFI 250 → 253、信号 14 → 15、struct 47 不变**。

---

## 4.10 值列就地编辑（2026-11-15 第二十五轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_table_set_item_editable_sl | ffi_tableSetItemEditable | `(i64,i32,i32,i32)` | 逐格翻转 `Qt::ItemIsEditable`；表创建时仍是 `NoEditTriggers` |
| slqt_table_item_text_sl | ffi_tableItemText | `(i64,i32,i32)->utf8` | 读单元格文本（`g_text_buf`），无 item 返回 `""` |

新增信号 id `SLQT_SIG_TABLE_ITEM_CHANGED = 15`（`QTableWidget::cellChanged`，int 载荷 = 行号 → `_dispatchInt`；列号由 SL 侧固定为值列 1）。`slqt_be_table_set_item` 与 `slqt_be_table_set_item_editable` 内加 `QSignalBlocker`，**程序化填充不会触发 `cellChanged`**（新增信号后的配套行为修正，旧 API 契约不变）。`core/QTableWidget.sl` 增 `setItemEditable` / `itemText` / `onItemChanged(Function)`。旧信号 0~14 取值与行为不变。**有效 FFI 253 → 255、信号 15 → 16、struct 47 不变**。

---

## 4.11 数值输入与节点图标（2026-11-15 第二十六轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_spin_create_sl | ffi_spinCreate | `(i64)->i64` | new QSpinBox(parent)，默认 range 0..100 |
| slqt_spin_set_range_sl | ffi_spinSetRange | `(i64,i32,i32)` | setRange |
| slqt_spin_set_value_sl | ffi_spinSetValue | `(i64,i32)` | setValue |
| slqt_spin_value_sl | ffi_spinValue | `(i64)->i32` | value |
| slqt_tree_set_item_icon_sl | ffi_treeSetItemIcon | `(i64,utf8,i32)` | 按路径 `setIcon(0, QApplication::style()->standardIcon(...))`；id 0 文件 / 1 目录 / 2 警告 / 3 应用 / 4 取消，其它忽略（无外部图片资源） |

新增信号 id `SLQT_SIG_SPIN_VALUE_CHANGED = 16`（`QSpinBox::valueChanged(int)`，int 载荷 = 新值 → `_dispatchInt`，用 `qOverload<int>` 消歧）。新增封装类 `core/QSpinBox.sl`（`QT.jsonc` 的 `compileFiles` 与 `struct.children` 同步登记），`core/QTreeWidget.sl` 增 `setItemIcon`。旧信号 0~15 取值与行为不变。**有效 FFI 255 → 260、信号 16 → 17、struct 47 → 48**。

---

## 4.12 独立标签条与窗口关闭请求（2026-11-16 第二十七轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_tabbar_create_sl | ffi_tabbarCreate | `(i64)->i64` | new QTabBar(parent)，独立标签条（非 QTabWidget 内置） |
| slqt_tabbar_add_tab_sl | ffi_tabbarAddTab | `(i64,utf8)->i32` | addTab，返回新标签下标（越界/空指针返回 -1） |
| slqt_tabbar_remove_tab_sl | ffi_tabbarRemoveTab | `(i64,i32)` | removeTab |
| slqt_tabbar_set_current_sl | ffi_tabbarSetCurrent | `(i64,i32)` | setCurrentIndex |
| slqt_tabbar_current_sl | ffi_tabbarCurrent | `(i64)->i32` | currentIndex，无标签 -1 |
| slqt_tabbar_count_sl | ffi_tabbarCount | `(i64)->i32` | count |
| slqt_tabbar_tab_text_sl | ffi_tabbarTabText | `(i64,i32)->utf8` | tabText，越界返回空串 |
| slqt_window_close_sl | ffi_windowClose | `(i64)` | 程序化关窗：置 bypass 后 `close()`，绕过关闭过滤器 |

新增信号 id：
- `SLQT_SIG_TABBAR_CHANGED = 17`（`QTabBar::currentChanged(int)`，int 载荷 = 新下标 → `_dispatchInt`）。
- `SLQT_SIG_CLOSE_REQUESTED = 18`（**无原生 Qt 信号**，C++ 侧 `SlqtCloseFilter` 事件过滤器拦 `QEvent::Close`：首次 Close → `ignore()` + 发信号（int 载荷 = 0）；真正关窗须回调 `slqt_window_close_sl`。过滤器以被监听对象为父，随窗口析构；**一个窗口只 connect 一次**，重复 connect 会叠装多个过滤器重复发信号）。

新增封装类 `core/QTabBar.sl`（`QT.jsonc` 的 `compileFiles` 与 `struct.children` 同步登记），`core/QMainWindow.sl` 增 `onCloseRequested` / `close`。旧信号 0~16 取值与行为不变。**有效 FFI 260 → 268、信号 17 → 19、struct 48 → 49**（`@DllStaticImport` 与 `SLQT_API` 声明均为 268，逐条对齐）。

---

## 4.13 QAction 快捷键（2026-11-16 第二十九轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_action_set_shortcut_sl | ffi_actionSetShortcut | `(i64,utf8)` | `QAction::setShortcut(QKeySequence)`；keys 为可移植串（`"Ctrl+S"` / `"F5"` / `"Shift+F5"`），空串清除 |

无新类、无新信号；**有效 FFI 268 → 269、信号 19 不变、struct 50 不变**。注意：同一命令的菜单与工具栏是两个独立 QAction，快捷键只应绑一侧（IDE 侧绑菜单），两侧都绑会一次按键触发两次命令。

---

## 4.14 QTextBrowser 帮助查看器（2026-11-16 第三十轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_browser_create_sl | ffi_browserCreate | `(i64)->i64` | new QTextBrowser(parent)，本身只读 |
| slqt_browser_set_markdown_sl | ffi_browserSetMarkdown | `(i64,utf8)` | `QTextBrowser::setMarkdown`，Qt6 原生 MD 渲染 |

`setText` / `toPlainText` / `setReadOnly` / `append` 复用既有 `slqt_textedit_*`（`qobject_cast<QTextEdit*>` 对子类兼容）。新增封装类 `core/QTextBrowser.sl`（**`extends QTextEdit`**，首个封装类继承链先例：子类构造自建句柄，基类方法经 `this.handle` 转发）。**有效 FFI 269 → 271、信号 19 不变、struct 50 → 51**。

### 4.14.1 文档内链接跳转（2026-11-16 第三十二轮增补）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_browser_set_document_sl | ffi_browserSetDocument | `(i64,utf8,utf8)` | 以 path 所在目录为 base 展示 md（g_browser_base/doc 记录） |
| slqt_browser_current_source_sl | ffi_browserCurrentSource | `(i64)->utf8` | 当前文档绝对路径，未设置空串 |

新增信号 id `SLQT_SIG_BROWSER_NAVIGATED = 19`：connect 时 `setOpenLinks(false)` 关掉 QTextBrowser 默认 setSource 加载（否则 md 被当纯文本覆盖），anchorClicked 经 `slqt_browser_navigate`（静态辅助，`_qt.cpp` 内部）相对 base 解析目标，仅当为本地 `.md`/`.markdown` 且存在时读入渲染（base 随跳转前移），成功才发信号（int 载荷=0）。**有效 FFI 271 → 273、信号 19 → 20、struct 51 不变**。

---

## 4.15 面板右键请求信号（2026-11-16 第三十五轮增补，只增不改）

| 信号 id | Qt 来源 | SL 绑定 | 说明 |
|---|---|---|---|
| SLQT_SIG_LIST_CONTEXT = 20 | `QListWidget::customContextMenuRequested` | `QListWidget.onContext(handler)` | handler 形态 `static void onCtx(int payload)`，载荷恒 0 |
| SLQT_SIG_TEXT_CONTEXT = 21 | `QTextEdit::customContextMenuRequested` | `QTextEdit.onContext(handler)` | 同上 |

connect 时自动 `setContextMenuPolicy(CustomContextMenu)`；弹出位置由 SL 侧 `QMenu.popupCursor()` 取鼠标处（无需坐标载荷）。无新 FFI、struct 不变；**信号 20 → 22**。右键菜单项经既有 `slqt_menu_*` 系（§4.6）弹出。

---

## 4.16 剪贴板与树节点文本（2026-11-16 第三十六轮增补，只增不改）

| C 导出 | SL 绑定 | sig | 说明 |
|---|---|---|---|
| slqt_clipboard_set_sl | ffi_clipboardSet | `(utf8)` | `QGuiApplication::clipboard()->setText`（静态入口，不依赖实例） |
| slqt_tree_current_text_sl | ffi_treeCurrentText | `(i64)->utf8` | QTreeWidget 当前节点第 0 列文本，无选中空串 |

`QApplication.setClipboard(text)`（静态）/ `QTreeWidget.currentText()` 封装落位。无新信号、struct 不变；**有效 FFI 273 → 275、信号 22 不变**。

---

*符号表即契约（冻结 v1，之后只增不改）。SL 封装类如何包裹见 05，信号槽见 06。*
