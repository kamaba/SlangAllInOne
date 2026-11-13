#ifndef SLANG_QT_H
#define SLANG_QT_H

/* ==========================================================================
 * slang_qt.h —— SLang QT 模块原生层导出声明（产物 slang_qt.dll）
 * --------------------------------------------------------------------------
 * 位于 Qt（Qt6 Widgets）之上的一层扁平 C ABI 包装，供 QTFFI.sl 经
 * @DllStaticImport("slang_qt", "slqt_xxx_sl") 静态绑定直调（opcode 77）。
 *
 * 设计对齐 SLang/WebUI/cvm_webui_lib（MIT 思路，本目录自有实现）：
 *   - 导出命名统一前缀 slqt_*_sl。
 *   - 所有导出函数参数 <= 6、纯标量（bool、整数、const char 指针、ptr），
 *     与 SLang sl_ffi_call 的 x64 ABI 分类对齐（INT 类含指针/utf8）。
 *   - const char* 返回值一律指向本库静态缓冲，SLang VM 在返回瞬间拷入
 *     自身 string（调用方不得 free）。
 *   - Qt 对象不暴露结构布局给 SLang，仅以 Int64 句柄（注册表下标）传递。
 *
 * 后端实现有两套（二选一编译，见 slang_qt.vcxproj / slang_qt_qt.vcxproj）：
 *   - slang_qt_stub.c：纯 C 无操作（headless 验证 SL 链路用，不依赖 Qt）。
 *   - slang_qt_qt.cpp：真实 Qt6 实现（C++，需 Qt6 工具链）。
 * 两套实现统一的扁平 ABI（slqt_be_*），由 slang_qt.c 的绑定层转发。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLQT_API __declspec(dllexport)
#else
#  define SLQT_API
#endif

/* ── 应用 ─────────────────────────────────────────────────────────────── */
SLQT_API int64_t slqt_app_create_sl(void);
SLQT_API void    slqt_app_set_stylesheet_sl(const char* css);
SLQT_API void    slqt_app_exec_sl(void);
SLQT_API void    slqt_app_process_events_sl(void);
SLQT_API void    slqt_app_quit_sl(void);
SLQT_API int32_t slqt_app_argc_sl(void);

/* ── 通用对象 / 基础控件 ─────────────────────────────────────────────── */
SLQT_API int64_t slqt_object_delete_sl(int64_t h);
SLQT_API int32_t slqt_object_is_valid_sl(int64_t h);
SLQT_API int64_t slqt_widget_create_sl(int64_t parent);
SLQT_API void    slqt_widget_set_parent_sl(int64_t h, int64_t parent);
SLQT_API void    slqt_widget_set_text_sl(int64_t h, const char* t);
SLQT_API const char* slqt_widget_text_sl(int64_t h);
SLQT_API void    slqt_widget_set_geometry_sl(int64_t h, int32_t x, int32_t y, int32_t w, int32_t hh);
SLQT_API void    slqt_widget_resize_sl(int64_t h, int32_t w, int32_t hh);
SLQT_API void    slqt_widget_show_sl(int64_t h);
SLQT_API void    slqt_widget_hide_sl(int64_t h);
SLQT_API void    slqt_widget_set_enabled_sl(int64_t h, int32_t on);
SLQT_API void    slqt_widget_set_visible_sl(int64_t h, int32_t on);
SLQT_API void    slqt_widget_set_tooltip_sl(int64_t h, const char* t);
SLQT_API void    slqt_widget_set_style_sheet_sl(int64_t h, const char* css);
SLQT_API void    slqt_widget_set_fixed_size_sl(int64_t h, int32_t w, int32_t hh);
SLQT_API void    slqt_widget_update_sl(int64_t h);

/* ── 按钮 / 标签 / 输入 ──────────────────────────────────────────────── */
SLQT_API int64_t slqt_button_create_sl(int64_t parent);
SLQT_API int64_t slqt_label_create_sl(int64_t parent);
SLQT_API int32_t slqt_label_set_pixmap_sl(int64_t h, int64_t ptr, int32_t len);
/* SLangRender renderTexture 通道：RGBA8 top-down 像素块填充 QLabel。 */
SLQT_API int32_t slqt_label_set_pixmap_rgba_sl(int64_t h, int64_t ptr, int32_t w, int32_t hh);
SLQT_API int64_t slqt_edit_create_sl(int64_t parent);
SLQT_API void    slqt_edit_set_placeholder_sl(int64_t h, const char* t);
SLQT_API const char* slqt_edit_text_sl(int64_t h);
SLQT_API void    slqt_edit_set_readonly_sl(int64_t h, int32_t on);

/* ── 多行文本编辑 / 列表（QTextEdit / QListWidget）──────────────────── */
SLQT_API int64_t     slqt_textedit_create_sl(int64_t parent);
SLQT_API void        slqt_textedit_set_text_sl(int64_t h, const char* t);
SLQT_API const char* slqt_textedit_text_sl(int64_t h);      /* 大缓冲（g_big_buf） */
SLQT_API void        slqt_textedit_set_readonly_sl(int64_t h, int32_t on);
SLQT_API void        slqt_textedit_append_sl(int64_t h, const char* t);
SLQT_API int64_t     slqt_list_create_sl(int64_t parent);
SLQT_API void        slqt_list_add_item_sl(int64_t h, const char* t);
SLQT_API void        slqt_list_clear_sl(int64_t h);
SLQT_API int32_t     slqt_list_count_sl(int64_t h);
SLQT_API int32_t     slqt_list_current_row_sl(int64_t h);
SLQT_API void        slqt_list_set_current_row_sl(int64_t h, int32_t row);
SLQT_API const char* slqt_list_item_text_sl(int64_t h, int32_t row);

/* ── 主窗口 / 对话框 ─────────────────────────────────────────────────── */
SLQT_API int64_t slqt_mainwindow_create_sl(void);
SLQT_API void    slqt_mainwindow_set_central_sl(int64_t h, int64_t widget);
SLQT_API void    slqt_mainwindow_set_title_sl(int64_t h, const char* t);
SLQT_API void    slqt_mainwindow_resize_sl(int64_t h, int32_t w, int32_t hh);
SLQT_API void    slqt_mainwindow_show_sl(int64_t h);
SLQT_API int32_t slqt_messagebox_info_sl(int64_t parent, const char* title, const char* text);
SLQT_API int32_t slqt_messagebox_question_sl(int64_t parent, const char* title, const char* text);

/* ── 布局 ────────────────────────────────────────────────────────────── */
SLQT_API int64_t slqt_vbox_create_sl(int64_t parent);
SLQT_API int64_t slqt_hbox_create_sl(int64_t parent);
SLQT_API int64_t slqt_grid_create_sl(int64_t parent);
SLQT_API void    slqt_layout_add_widget_sl(int64_t layout, int64_t w);
SLQT_API void    slqt_layout_add_spacing_sl(int64_t layout, int32_t px);
SLQT_API void    slqt_layout_add_stretch_sl(int64_t layout, int32_t stretch);
SLQT_API void    slqt_layout_set_contents_margins_sl(int64_t layout, int32_t l, int32_t t, int32_t r, int32_t b);
SLQT_API void    slqt_layout_set_spacing_sl(int64_t layout, int32_t px);
SLQT_API void    slqt_layout_set_widget_at_sl(int64_t grid, int64_t w, int32_t row, int32_t col, int32_t rspan, int32_t cspan);
SLQT_API void    slqt_widget_set_layout_sl(int64_t w, int64_t layout);

/* ── 信号连接（绑定层；dispatchCb 为 createCallback 节流点）─────────── */
SLQT_API int64_t slqt_connect_sl(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot);

/* 信号 id 枚举（与 QTFFI.sl 的 SIG_* 常量逐值一致） */
#define SLQT_SIG_CLICKED        0
#define SLQT_SIG_RETURN_PRESSED 1
#define SLQT_SIG_TRIGGERED      2
#define SLQT_SIG_DESTROYED     3
#define SLQT_SIG_TEXT_CHANGED   4
/* QListWidget::currentRowChanged(int)：int 载荷经 _dispatchInt 桥重入 VM */
#define SLQT_SIG_CURRENT_ROW_CHANGED 5
/* 2026-11-12 P2 扩展信号：
 * 6 = QTreeWidget::itemSelectionChanged，utf8 载荷（选中项完整路径）→ _dispatchString
 * 7 = QCodeEdit 光标行变化，int 载荷（1-based 行号）→ _dispatchInt
 * 8 = QCodeEdit 装订线点击切换断点，int 载荷（行号）→ _dispatchInt */
#define SLQT_SIG_TREE_SELECTED 6
#define SLQT_SIG_CODEEDIT_LINE_CHANGED 7
#define SLQT_SIG_CODEEDIT_BREAKPOINT 8
/* 2026-11-13 VS 多标签：两个 int 载荷信号均走 _dispatchInt
 * 9  = QTabWidget::currentChanged(int)  当前标签变化
 * 10 = QTabWidget::tabCloseRequested(int) 点击标签关闭按钮 */
#define SLQT_SIG_TAB_CHANGED 9
#define SLQT_SIG_TAB_CLOSE_REQUESTED 10
/* 2026-11-13 第十四轮 右键菜单：
 * 11 = QTabWidget 标签区右键，int 载荷（右键所在标签下标，-1=非标签区）→ _dispatchInt
 * 12 = QTreeWidget 节点右键，utf8 载荷（右键节点完整路径，空=空白区）→ _dispatchString
 * 两者均需构造时 setContextMenuPolicy(CustomContextMenu)。 */
#define SLQT_SIG_TAB_CONTEXT 11
#define SLQT_SIG_TREE_CONTEXT 12

/* ==========================================================================
 * 2026-11-03 扩展面：按 jsonc qtRuntime 组合部署（模块 dll + 插件分类）后，
 * QTTest 复杂套件逐面板探测/驱动下列能力。可选 Qt 模块在 vcxproj 侧全部
 * /DELAYLOAD（组合缺件时模块装载不失败），绑定层预装载 + 探测导出兜底。
 * ========================================================================== */

/* ── 运行时自描述 / 模块与插件探测（绑定层或后端实现）───────────────── */
SLQT_API const char* slqt_backend_kind_sl(void);        /* "stub" | "qt" */
SLQT_API const char* slqt_runtime_dir_sl(void);         /* 本 dll 所在目录（部署槽位） */
SLQT_API int32_t     slqt_module_available_sl(const char* dllName);  /* 同位预装载探测 */
SLQT_API const char* slqt_app_platform_name_sl(void);   /* 生效平台插件（windows/offscreen/…） */
SLQT_API const char* slqt_app_library_paths_sl(void);   /* QCoreApplication::libraryPaths */
SLQT_API const char* slqt_app_style_keys_sl(void);      /* QStyleFactory::keys（styles 插件扫描） */
SLQT_API int32_t     slqt_app_set_style_sl(const char* name);  /* 返回 0/1（原 void，随扩展改） */

/* ── 控件移动 + QTimer（动画面板：SL 侧 onTick 里 move 形成移动效果）── */
SLQT_API void    slqt_widget_move_sl(int64_t h, int32_t x, int32_t y);
SLQT_API int64_t slqt_timer_create_sl(int32_t ms, int32_t singleShot, int64_t dispatchCb, int64_t slot);
SLQT_API void    slqt_timer_delete_sl(int64_t h);
SLQT_API void    slqt_timer_start_sl(int64_t h, int32_t ms);
SLQT_API void    slqt_timer_stop_sl(int64_t h);
SLQT_API int32_t slqt_timer_active_sl(int64_t h);

/* ── Network（Qt6Network；networkinformation / tls 插件）──────────────── */
SLQT_API int64_t     slqt_net_create_sl(void);           /* QNetworkAccessManager */
SLQT_API void        slqt_net_delete_sl(int64_t h);
SLQT_API int32_t     slqt_net_is_online_sl(void);        /* 1 在线 / 0 离线 / -1 插件缺失 */
SLQT_API const char* slqt_net_backend_name_sl(void);     /* QNetworkInformation 后端名 */
SLQT_API int64_t     slqt_net_get_sl(int64_t h, const char* url);  /* 异步 GET → reply 句柄 */
SLQT_API void        slqt_net_reply_delete_sl(int64_t h);
SLQT_API int32_t     slqt_net_reply_wait_sl(int64_t h, int32_t ms);  /* 事件循环等待完成 */
SLQT_API int32_t     slqt_net_reply_status_sl(int64_t h);            /* HTTP 状态码 */
SLQT_API const char* slqt_net_reply_error_sl(int64_t h);
SLQT_API const char* slqt_net_reply_body_sl(int64_t h);              /* 大缓冲（256KB） */

/* ── Sql（Qt6Sql；sqldrivers 插件）───────────────────────────────────── */
SLQT_API const char* slqt_sql_drivers_sl(void);          /* 可用驱动表（插件扫描结果） */
SLQT_API int64_t     slqt_sql_add_database_sl(const char* type);
SLQT_API void        slqt_sql_delete_sl(int64_t h);
SLQT_API void        slqt_sql_set_database_name_sl(int64_t h, const char* name);
SLQT_API int32_t     slqt_sql_open_sl(int64_t h);
SLQT_API void        slqt_sql_close_sl(int64_t h);
SLQT_API const char* slqt_sql_last_error_sl(int64_t h);
SLQT_API int64_t     slqt_sql_query_create_sl(int64_t db);
SLQT_API void        slqt_sql_query_delete_sl(int64_t h);
SLQT_API int32_t     slqt_sql_query_exec_sl(int64_t h, const char* sql);
SLQT_API int32_t     slqt_sql_query_next_sl(int64_t h);
SLQT_API const char* slqt_sql_query_value_text_sl(int64_t h, int32_t i);
SLQT_API int64_t     slqt_sql_query_value_int_sl(int64_t h, int32_t i);

/* ── Svg（Qt6Svg / Qt6SvgWidgets）───────────────────────────────────── */
SLQT_API int64_t slqt_svgwidget_create_sl(int64_t parent);
SLQT_API int32_t slqt_svgwidget_load_file_sl(int64_t h, const char* path);
SLQT_API int32_t slqt_svgwidget_load_data_sl(int64_t h, const char* xml);
SLQT_API int64_t slqt_svg_renderer_create_sl(const char* xml);
SLQT_API void    slqt_svg_renderer_delete_sl(int64_t h);
SLQT_API int32_t slqt_svg_renderer_valid_sl(int64_t h);
SLQT_API int32_t slqt_svg_renderer_check_size_sl(int64_t h, int32_t w, int32_t hh);
SLQT_API int32_t slqt_svg_render_to_label_sl(int64_t renderer, int64_t label, int32_t w, int32_t hh);

/* ── 图像 / 图标（Qt6Gui；imageformats / iconengines 插件探测）────────── */
SLQT_API const char* slqt_image_formats_sl(void);        /* QImageReader 可读格式表 */
SLQT_API int32_t     slqt_image_save_solid_sl(const char* path, const char* fmt, int32_t r, int32_t g, int32_t b);
SLQT_API int32_t     slqt_image_check_size_sl(const char* path, int32_t w, int32_t hh);
SLQT_API int32_t     slqt_icon_render_sl(const char* path, int32_t size);  /* iconengines 渲染 .svg/.ico */

/* ── OpenGL（Qt6OpenGLWidgets + Qt6OpenGL；旋转三角动画面板）────────── */
SLQT_API int64_t slqt_glwidget_create_sl(int64_t parent);
SLQT_API void    slqt_glwidget_set_color_sl(int64_t h, int32_t r, int32_t g, int32_t b);
SLQT_API void    slqt_glwidget_set_spinning_sl(int64_t h, int32_t on);
SLQT_API int64_t slqt_glwidget_frame_count_sl(int64_t h);

/* ── Print（Qt6PrintSupport；PDF 输出，无对话框）────────────────────── */
SLQT_API int64_t     slqt_printer_create_sl(void);
SLQT_API void        slqt_printer_delete_sl(int64_t h);
SLQT_API void        slqt_printer_set_output_filename_sl(int64_t h, const char* path);
SLQT_API void        slqt_printer_set_page_size_a4_sl(int64_t h);
SLQT_API int32_t     slqt_printer_print_text_sl(int64_t h, const char* title, const char* body);
SLQT_API const char* slqt_printer_output_file_sl(int64_t h);

/* ── Xml（Qt6Xml；QDomDocument）─────────────────────────────────────── */
SLQT_API int64_t     slqt_dom_create_sl(void);
SLQT_API void        slqt_dom_delete_sl(int64_t h);
SLQT_API int32_t     slqt_dom_set_content_sl(int64_t h, const char* xml);
SLQT_API const char* slqt_dom_root_tag_sl(int64_t h);
SLQT_API int64_t     slqt_dom_count_by_tag_sl(int64_t h, const char* tag);
SLQT_API const char* slqt_dom_first_text_sl(int64_t h, const char* tag);
SLQT_API const char* slqt_dom_to_string_sl(int64_t h);

/* ── Concurrent（Qt6Concurrent；工作线程原生计算，结果轮询）──────────── */
SLQT_API int64_t slqt_concurrent_task_create_sl(int32_t kind, int64_t n);  /* 0 累加 / 1 素数计数 */
SLQT_API void    slqt_concurrent_task_delete_sl(int64_t h);
SLQT_API int32_t slqt_concurrent_task_is_finished_sl(int64_t h);
SLQT_API int64_t slqt_concurrent_task_result_sl(int64_t h);
SLQT_API int32_t slqt_thread_pool_max_sl(void);

/* ── Test（Qt6Test：qSleep / qWait / 版本串）────────────────────────── */
SLQT_API void        slqt_test_qsleep_sl(int32_t ms);
SLQT_API void        slqt_test_qwait_sl(int32_t ms);
SLQT_API const char* slqt_test_version_sl(void);

/* ── UiTools / Designer（.ui 文件装载双通道）────────────────────────── */
SLQT_API int64_t     slqt_uiloader_create_sl(void);       /* QUiLoader（Qt6UiTools） */
SLQT_API void        slqt_uiloader_delete_sl(int64_t h);
SLQT_API int64_t     slqt_uiloader_load_file_sl(int64_t h, const char* path, int64_t parent);
SLQT_API const char* slqt_uiloader_available_widgets_sl(int64_t h);
SLQT_API int64_t     slqt_designer_formbuilder_create_sl(void);  /* QFormBuilder（Qt6Designer） */
SLQT_API void        slqt_designer_formbuilder_delete_sl(int64_t h);
SLQT_API int64_t     slqt_designer_formbuilder_load_sl(int64_t h, const char* path, int64_t parent);

/* ── Help（Qt6Help；依赖 Qt6Sql + qsqlite 插件）─────────────────────── */
SLQT_API int64_t     slqt_help_engine_create_sl(const char* collection);
SLQT_API void        slqt_help_engine_delete_sl(int64_t h);
SLQT_API int32_t     slqt_help_setup_data_sl(int64_t h);
SLQT_API const char* slqt_help_error_sl(int64_t h);

/* ── DBus（Qt6DBus）─────────────────────────────────────────────────── */
SLQT_API int32_t     slqt_dbus_connected_sl(void);
SLQT_API const char* slqt_dbus_base_service_sl(void);

/* ── 2026-11-10 VS 式主框架扩展：菜单 / 工具栏 / Dock / MDI / 对话框 ──
 * QMenuBar + QMenu（一二级菜单，QAction.triggered → SIG_TRIGGERED）
 * QToolBar（快捷图标区）、QDockWidget（自由 Dock 面板）、
 * QMdiArea + QMdiSubWindow（多文档代码区）、QDialog（BaseDialog 基类）
 * 以及 QWidget min/max 尺寸（面板规格钳制落地到 Qt 原生）。 */
SLQT_API int64_t slqt_menubar_create_sl(void);
SLQT_API void    slqt_mainwindow_set_menubar_sl(int64_t win, int64_t mb);
SLQT_API int64_t slqt_menu_create_sl(int64_t parent, const char* title);  /* parent: QMenuBar 或 QMenu */
SLQT_API int64_t slqt_menu_create_popup_sl(const char* title);            /* 独立弹出菜单（parent=nullptr） */
SLQT_API int64_t slqt_menu_add_action_sl(int64_t menu, const char* text); /* 返回 QAction 句柄 */
SLQT_API void    slqt_menu_add_separator_sl(int64_t menu);
/* 阻塞弹出：在 anchor 控件 (x,y) 局部坐标处 exec；返回被选中 QAction 句柄（0=取消） */
SLQT_API int64_t slqt_menu_popup_exec_sl(int64_t menu, int64_t anchor, int32_t x, int32_t y);
/* 阻塞弹出：在当前光标（鼠标）位置 exec（右键菜单标准形态） */
SLQT_API int64_t slqt_menu_popup_cursor_sl(int64_t menu);
SLQT_API void    slqt_action_set_text_sl(int64_t a, const char* t);
SLQT_API void    slqt_action_set_enabled_sl(int64_t a, int64_t on);
SLQT_API int64_t slqt_action_enabled_sl(int64_t a);
SLQT_API int64_t slqt_toolbar_create_sl(int64_t parent, const char* title);
SLQT_API void    slqt_mainwindow_add_toolbar_sl(int64_t win, int64_t tb);
SLQT_API int64_t slqt_toolbar_add_action_sl(int64_t tb, const char* text); /* 返回 QAction 句柄 */
SLQT_API void    slqt_toolbar_add_separator_sl(int64_t tb);
SLQT_API int64_t slqt_dock_create_sl(int64_t parent, const char* title);
SLQT_API void    slqt_mainwindow_add_dock_sl(int64_t win, int64_t dock, int32_t area);
SLQT_API void    slqt_dock_set_widget_sl(int64_t dock, int64_t w);
SLQT_API void    slqt_dock_set_features_sl(int64_t dock, int32_t f);
SLQT_API void    slqt_dock_set_floating_sl(int64_t dock, int32_t on);
SLQT_API int64_t slqt_mdiarea_create_sl(int64_t parent);
SLQT_API int64_t slqt_mdiarea_add_subwindow_sl(int64_t mdi, int64_t w);   /* 返回 QMdiSubWindow 句柄 */
SLQT_API int32_t slqt_mdiarea_count_sl(int64_t mdi);
SLQT_API void    slqt_mdiarea_tile_sl(int64_t mdi);
SLQT_API void    slqt_mdiarea_cascade_sl(int64_t mdi);
SLQT_API void    slqt_mdiarea_close_active_sl(int64_t mdi);
SLQT_API int64_t slqt_mdiarea_active_sub_sl(int64_t mdi);                 /* 0=无活动子窗 */
SLQT_API void    slqt_subwindow_set_title_sl(int64_t sub, const char* t);
SLQT_API void    slqt_subwindow_show_maximized_sl(int64_t sub);
SLQT_API int64_t slqt_dialog_create_sl(int64_t parent);
SLQT_API void    slqt_dialog_set_modal_sl(int64_t d, int32_t on);
SLQT_API int32_t slqt_dialog_exec_sl(int64_t d);
SLQT_API void    slqt_dialog_accept_sl(int64_t d);
SLQT_API void    slqt_dialog_reject_sl(int64_t d);
SLQT_API void    slqt_widget_set_min_size_sl(int64_t h, int32_t w, int32_t hh);
SLQT_API void    slqt_widget_set_max_size_sl(int64_t h, int32_t w, int32_t hh);

/* ── 2026-11-12 P2 能力扩展（能力登记表 D-01~D-05 回补）──────────────────
 * QFileDialog（模态静态调用，返回路径；取消返回空串）
 * QStatusBar（主窗口原生状态条）
 * QTreeWidget（路径式建模：add_path("a/b/c")；选中回传完整路径）
 * QSplitter（尺寸比例精确控制）
 * QCodeEdit（QPlainTextEdit 派生：行号区 / 当前行 / 断点装订线 /
 *            SLang 关键字语法高亮 / 光标行回调；无 Q_OBJECT，无需 moc） */
SLQT_API const char* slqt_filedialog_open_sl(const char* dir, const char* filter);
SLQT_API const char* slqt_filedialog_save_sl(const char* dir, const char* filter);
SLQT_API const char* slqt_filedialog_dir_sl(const char* dir);

SLQT_API int64_t slqt_statusbar_create_sl(int64_t parent);
SLQT_API void    slqt_mainwindow_set_statusbar_sl(int64_t win, int64_t sb);
SLQT_API void    slqt_statusbar_show_message_sl(int64_t sb, const char* t);
SLQT_API void    slqt_statusbar_add_widget_sl(int64_t sb, int64_t w);

SLQT_API int64_t     slqt_tree_create_sl(int64_t parent);
SLQT_API void        slqt_tree_set_header_sl(int64_t h, const char* t);
SLQT_API void        slqt_tree_clear_sl(int64_t h);
SLQT_API void        slqt_tree_add_path_sl(int64_t h, const char* path);
SLQT_API int32_t     slqt_tree_count_sl(int64_t h);
SLQT_API const char* slqt_tree_selected_path_sl(int64_t h);

SLQT_API int64_t slqt_splitter_create_sl(int64_t parent, int32_t vertical);
SLQT_API void    slqt_splitter_add_widget_sl(int64_t sp, int64_t w);
SLQT_API void    slqt_splitter_set_sizes_sl(int64_t sp, int32_t a, int32_t b, int32_t c);

SLQT_API int64_t     slqt_codeedit_create_sl(int64_t parent);
SLQT_API void        slqt_codeedit_set_text_sl(int64_t h, const char* t);
SLQT_API const char* slqt_codeedit_text_sl(int64_t h);
SLQT_API void        slqt_codeedit_set_readonly_sl(int64_t h, int32_t on);
SLQT_API void        slqt_codeedit_goto_line_sl(int64_t h, int32_t line);
SLQT_API int32_t     slqt_codeedit_cursor_line_sl(int64_t h);
SLQT_API void        slqt_codeedit_set_highlight_sl(int64_t h, int32_t on);
SLQT_API void        slqt_codeedit_set_breakpoint_sl(int64_t h, int32_t line, int32_t on);
SLQT_API int32_t     slqt_codeedit_toggle_breakpoint_sl(int64_t h);
SLQT_API void        slqt_codeedit_clear_breakpoints_sl(int64_t h);
SLQT_API const char* slqt_codeedit_breakpoints_sl(int64_t h);
SLQT_API void        slqt_codeedit_set_font_pt_sl(int64_t h, int32_t pt);
/* 2026-11-12 第三轮：光标下单词 / 选中文本（符号索引·转到定义用） */
SLQT_API const char* slqt_codeedit_word_sl(int64_t h);
SLQT_API const char* slqt_codeedit_selected_sl(int64_t h);
/* 2026-11-12 第五轮：断点确认态（实心）与停驻行（箭头 + 行高亮） */
SLQT_API void        slqt_codeedit_set_bound_sl(int64_t h, const char* csv);
SLQT_API void        slqt_codeedit_set_stopped_sl(int64_t h, int32_t line);

/* 2026-11-13 VS 多标签：QTabWidget */
SLQT_API int64_t     slqt_tab_create_sl(int64_t parent);
SLQT_API int32_t     slqt_tab_add_sl(int64_t h, int64_t page, const char* title);
SLQT_API int32_t     slqt_tab_count_sl(int64_t h);
SLQT_API int32_t     slqt_tab_current_sl(int64_t h);
SLQT_API void        slqt_tab_set_current_sl(int64_t h, int32_t idx);
SLQT_API const char* slqt_tab_text_sl(int64_t h, int32_t idx);
SLQT_API void        slqt_tab_set_text_sl(int64_t h, int32_t idx, const char* title);
SLQT_API void        slqt_tab_remove_sl(int64_t h, int32_t idx);
SLQT_API void        slqt_tab_clear_sl(int64_t h);
SLQT_API void        slqt_tab_set_closable_sl(int64_t h, int32_t on);

/* 2026-11-12 第四轮：SLDP TCP 客户端桥
 * Qt 原生 IO：readyRead 在 C++ 侧累积字节，SL 侧同步 poll 取走，
 * 不经过 C VM 的 socket 协程挂起协议（该协议在 Qt 回调重入 VM 时返回 null）。 */
SLQT_API int32_t     slqt_sldp_connect_sl(int32_t port);
SLQT_API void        slqt_sldp_send_sl(const char* utf8);
SLQT_API const char* slqt_sldp_poll_sl(void);
SLQT_API int32_t     slqt_sldp_connected_sl(void);
SLQT_API void        slqt_sldp_close_sl(void);

#ifdef __cplusplus
}
#endif

#endif /* SLANG_QT_H */
