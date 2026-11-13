#ifndef SLANG_QT_BACKEND_H
#define SLANG_QT_BACKEND_H

/* ==========================================================================
 * slang_qt_backend.h —— 后端实现接口（stub 与 Qt 两套实现的统一契约）
 * --------------------------------------------------------------------------
 * slang_qt.c（绑定层）调用本头声明的 slqt_be_*；slang_qt_stub.c 与
 * slang_qt_qt.cpp 各自实现它们。slqt_register / slqt_resolve 是绑定层
 * 维护的句柄注册表，供后端把 Int64 句柄还原为真实对象指针。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 句柄注册表（由 slang_qt.c 实现，后端使用） */
int64_t slqt_register(void* obj);
void*   slqt_resolve(int64_t h);
void    slqt_unregister(int64_t h);

/* 应用 */
int64_t slqt_be_app_create(void);
void    slqt_be_app_set_stylesheet(const char* css);
void    slqt_be_app_exec(void);
void    slqt_be_app_process_events(void);
void    slqt_be_app_quit(void);
int32_t slqt_be_app_argc(void);

/* 对象 / 控件 */
void    slqt_be_object_delete(int64_t h);
int32_t slqt_be_object_is_valid(int64_t h);
int64_t slqt_be_widget_create(int64_t parent);
void    slqt_be_widget_set_parent(int64_t h, int64_t parent);
void    slqt_be_widget_set_text(int64_t h, const char* t);
const char* slqt_be_widget_text(int64_t h);
void    slqt_be_widget_set_geometry(int64_t h, int32_t x, int32_t y, int32_t w, int32_t hh);
void    slqt_be_widget_resize(int64_t h, int32_t w, int32_t hh);
void    slqt_be_widget_show(int64_t h);
void    slqt_be_widget_hide(int64_t h);
void    slqt_be_widget_set_enabled(int64_t h, int32_t on);
void    slqt_be_widget_set_visible(int64_t h, int32_t on);
void    slqt_be_widget_set_tooltip(int64_t h, const char* t);
void    slqt_be_widget_set_style_sheet(int64_t h, const char* css);
void    slqt_be_widget_set_fixed_size(int64_t h, int32_t w, int32_t hh);
void    slqt_be_widget_update(int64_t h);

/* 按钮 / 标签 / 输入 */
int64_t slqt_be_button_create(int64_t parent);
int64_t slqt_be_label_create(int64_t parent);
int32_t slqt_be_label_set_pixmap(int64_t h, int64_t ptr, int32_t len);
/* SLangRender renderTexture 通道：ptr 指向 RGBA8 top-down 像素块
   (w*h*4 字节，GL glReadPixels 回读布局 = QImage Format_RGBA8888)，
   构造 QImage -> QPixmap 填入 label 并开启 scaledContents。 */
int32_t slqt_be_label_set_pixmap_rgba(int64_t h, int64_t ptr, int32_t w, int32_t hh);
int64_t slqt_be_edit_create(int64_t parent);
void    slqt_be_edit_set_placeholder(int64_t h, const char* t);
const char* slqt_be_edit_text(int64_t h);
void    slqt_be_edit_set_readonly(int64_t h, int32_t on);

/* 多行文本编辑 / 列表（QTextEdit / QListWidget；currentRowChanged 的 int
   载荷经 dispatchCb(slot, row) 重入，SL 侧 _dispatchInt 桥接回 handler） */
int64_t     slqt_be_textedit_create(int64_t parent);
void        slqt_be_textedit_set_text(int64_t h, const char* t);
const char* slqt_be_textedit_text(int64_t h);
void        slqt_be_textedit_set_readonly(int64_t h, int32_t on);
void        slqt_be_textedit_append(int64_t h, const char* t);
int64_t     slqt_be_list_create(int64_t parent);
void        slqt_be_list_add_item(int64_t h, const char* t);
void        slqt_be_list_clear(int64_t h);
int32_t     slqt_be_list_count(int64_t h);
int32_t     slqt_be_list_current_row(int64_t h);
void        slqt_be_list_set_current_row(int64_t h, int32_t row);
const char* slqt_be_list_item_text(int64_t h, int32_t row);

/* 主窗口 / 对话框 */
int64_t slqt_be_mainwindow_create(void);
void    slqt_be_mainwindow_set_central(int64_t h, int64_t widget);
void    slqt_be_mainwindow_set_title(int64_t h, const char* t);
void    slqt_be_mainwindow_resize(int64_t h, int32_t w, int32_t hh);
void    slqt_be_mainwindow_show(int64_t h);
int32_t slqt_be_messagebox_info(int64_t parent, const char* title, const char* text);
int32_t slqt_be_messagebox_question(int64_t parent, const char* title, const char* text);

/* 布局 */
int64_t slqt_be_vbox_create(int64_t parent);
int64_t slqt_be_hbox_create(int64_t parent);
int64_t slqt_be_grid_create(int64_t parent);
void    slqt_be_layout_add_widget(int64_t layout, int64_t w);
void    slqt_be_layout_add_spacing(int64_t layout, int32_t px);
void    slqt_be_layout_add_stretch(int64_t layout, int32_t stretch);
void    slqt_be_layout_set_contents_margins(int64_t layout, int32_t l, int32_t t, int32_t r, int32_t b);
void    slqt_be_layout_set_spacing(int64_t layout, int32_t px);
void    slqt_be_layout_set_widget_at(int64_t grid, int64_t w, int32_t row, int32_t col, int32_t rspan, int32_t cspan);
void    slqt_be_widget_set_layout(int64_t w, int64_t layout);

/* 信号连接：后端把 h 还原为 QObject* 并 QObject::connect；
   发射时按信号类型调用 dispatchCb(slot)（void 信号）或
   dispatchCb(slot, utf8)（string 信号）。stub 实现为 no-op。 */
int64_t slqt_be_connect(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot);

/* ==========================================================================
 * 2026-11-03 扩展面（与 slang_qt.h 的新增导出一一对应）。可选 Qt 模块经
 * vcxproj /DELAYLOAD 链接：模块未部署时绑定层探测返回 0、调用方跳过，
 * 已部署时绑定层预装载后延迟加载桩按名命中。
 * ========================================================================== */

/* 后端自描述（"stub" / "qt"） */
const char* slqt_be_backend_kind(void);

/* 应用 / 插件路径（Qt 后端真值；stub 安全值） */
const char* slqt_be_app_platform_name(void);
const char* slqt_be_app_library_paths(void);
const char* slqt_be_app_style_keys(void);
int32_t     slqt_be_app_set_style(const char* name);

/* 控件移动 + QTimer */
void    slqt_be_widget_move(int64_t h, int32_t x, int32_t y);
int64_t slqt_be_timer_create(int32_t ms, int32_t singleShot, int64_t dispatchCb, int64_t slot);
void    slqt_be_timer_delete(int64_t h);
void    slqt_be_timer_start(int64_t h, int32_t ms);
void    slqt_be_timer_stop(int64_t h);
int32_t slqt_be_timer_active(int64_t h);

/* Network */
int64_t     slqt_be_net_create(void);
void        slqt_be_net_delete(int64_t h);
int32_t     slqt_be_net_is_online(void);
const char* slqt_be_net_backend_name(void);
int64_t     slqt_be_net_get(int64_t h, const char* url);
void        slqt_be_net_reply_delete(int64_t h);
int32_t     slqt_be_net_reply_wait(int64_t h, int32_t ms);
int32_t     slqt_be_net_reply_status(int64_t h);
const char* slqt_be_net_reply_error(int64_t h);
const char* slqt_be_net_reply_body(int64_t h);

/* Sql */
const char* slqt_be_sql_drivers(void);
int64_t     slqt_be_sql_add_database(const char* type);
void        slqt_be_sql_delete(int64_t h);
void        slqt_be_sql_set_database_name(int64_t h, const char* name);
int32_t     slqt_be_sql_open(int64_t h);
void        slqt_be_sql_close(int64_t h);
const char* slqt_be_sql_last_error(int64_t h);
int64_t     slqt_be_sql_query_create(int64_t db);
void        slqt_be_sql_query_delete(int64_t h);
int32_t     slqt_be_sql_query_exec(int64_t h, const char* sql);
int32_t     slqt_be_sql_query_next(int64_t h);
const char* slqt_be_sql_query_value_text(int64_t h, int32_t i);
int64_t     slqt_be_sql_query_value_int(int64_t h, int32_t i);

/* Svg */
int64_t slqt_be_svgwidget_create(int64_t parent);
int32_t slqt_be_svgwidget_load_file(int64_t h, const char* path);
int32_t slqt_be_svgwidget_load_data(int64_t h, const char* xml);
int64_t slqt_be_svg_renderer_create(const char* xml);
void    slqt_be_svg_renderer_delete(int64_t h);
int32_t slqt_be_svg_renderer_valid(int64_t h);
int32_t slqt_be_svg_renderer_check_size(int64_t h, int32_t w, int32_t hh);
int32_t slqt_be_svg_render_to_label(int64_t renderer, int64_t label, int32_t w, int32_t hh);

/* 图像 / 图标（插件探测） */
const char* slqt_be_image_formats(void);
int32_t     slqt_be_image_save_solid(const char* path, const char* fmt, int32_t r, int32_t g, int32_t b);
int32_t     slqt_be_image_check_size(const char* path, int32_t w, int32_t hh);
int32_t     slqt_be_icon_render(const char* path, int32_t size);

/* OpenGL */
int64_t slqt_be_glwidget_create(int64_t parent);
void    slqt_be_glwidget_set_color(int64_t h, int32_t r, int32_t g, int32_t b);
void    slqt_be_glwidget_set_spinning(int64_t h, int32_t on);
int64_t slqt_be_glwidget_frame_count(int64_t h);

/* Print */
int64_t     slqt_be_printer_create(void);
void        slqt_be_printer_delete(int64_t h);
void        slqt_be_printer_set_output_filename(int64_t h, const char* path);
void        slqt_be_printer_set_page_size_a4(int64_t h);
int32_t     slqt_be_printer_print_text(int64_t h, const char* title, const char* body);
const char* slqt_be_printer_output_file(int64_t h);

/* Xml */
int64_t     slqt_be_dom_create(void);
void        slqt_be_dom_delete(int64_t h);
int32_t     slqt_be_dom_set_content(int64_t h, const char* xml);
const char* slqt_be_dom_root_tag(int64_t h);
int64_t     slqt_be_dom_count_by_tag(int64_t h, const char* tag);
const char* slqt_be_dom_first_text(int64_t h, const char* tag);
const char* slqt_be_dom_to_string(int64_t h);

/* Concurrent */
int64_t slqt_be_concurrent_task_create(int32_t kind, int64_t n);
void    slqt_be_concurrent_task_delete(int64_t h);
int32_t slqt_be_concurrent_task_is_finished(int64_t h);
int64_t slqt_be_concurrent_task_result(int64_t h);
int32_t slqt_be_thread_pool_max(void);

/* Test */
void        slqt_be_test_qsleep(int32_t ms);
void        slqt_be_test_qwait(int32_t ms);
const char* slqt_be_test_version(void);

/* UiTools / Designer */
int64_t     slqt_be_uiloader_create(void);
void        slqt_be_uiloader_delete(int64_t h);
int64_t     slqt_be_uiloader_load_file(int64_t h, const char* path, int64_t parent);
const char* slqt_be_uiloader_available_widgets(int64_t h);
int64_t     slqt_be_designer_formbuilder_create(void);
void        slqt_be_designer_formbuilder_delete(int64_t h);
int64_t     slqt_be_designer_formbuilder_load(int64_t h, const char* path, int64_t parent);

/* Help */
int64_t     slqt_be_help_engine_create(const char* collection);
void        slqt_be_help_engine_delete(int64_t h);
int32_t     slqt_be_help_setup_data(int64_t h);
const char* slqt_be_help_error(int64_t h);

/* DBus */
int32_t     slqt_be_dbus_connected(void);
const char* slqt_be_dbus_base_service(void);

/* ── 2026-11-10 VS 式主框架扩展（与 slang_qt.h 新增导出一一对应）─────── */
/* 菜单：QMenuBar / QMenu / QAction（QAction.triggered → SIG_TRIGGERED） */
int64_t slqt_be_menubar_create(void);
void    slqt_be_mainwindow_set_menubar(int64_t win, int64_t mb);
int64_t slqt_be_menu_create(int64_t parent, const char* title);
int64_t slqt_be_menu_create_popup(const char* title);
int64_t slqt_be_menu_add_action(int64_t menu, const char* text);
void    slqt_be_menu_add_separator(int64_t menu);
int64_t slqt_be_menu_popup_exec(int64_t menu, int64_t anchor, int32_t x, int32_t y);
void    slqt_be_action_set_text(int64_t a, const char* t);
void    slqt_be_action_set_enabled(int64_t a, int64_t on);
int64_t slqt_be_action_enabled(int64_t a);
/* 工具栏：QToolBar */
int64_t slqt_be_toolbar_create(int64_t parent, const char* title);
void    slqt_be_mainwindow_add_toolbar(int64_t win, int64_t tb);
int64_t slqt_be_toolbar_add_action(int64_t tb, const char* text);
void    slqt_be_toolbar_add_separator(int64_t tb);
/* Dock：QDockWidget（area 为 Qt::DockWidgetArea 位值） */
int64_t slqt_be_dock_create(int64_t parent, const char* title);
void    slqt_be_mainwindow_add_dock(int64_t win, int64_t dock, int32_t area);
void    slqt_be_dock_set_widget(int64_t dock, int64_t w);
void    slqt_be_dock_set_features(int64_t dock, int32_t f);
void    slqt_be_dock_set_floating(int64_t dock, int32_t on);
/* MDI：QMdiArea + QMdiSubWindow（多文档代码区） */
int64_t slqt_be_mdiarea_create(int64_t parent);
int64_t slqt_be_mdiarea_add_subwindow(int64_t mdi, int64_t w);
int32_t slqt_be_mdiarea_count(int64_t mdi);
void    slqt_be_mdiarea_tile(int64_t mdi);
void    slqt_be_mdiarea_cascade(int64_t mdi);
void    slqt_be_mdiarea_close_active(int64_t mdi);
int64_t slqt_be_mdiarea_active_sub(int64_t mdi);
void    slqt_be_subwindow_set_title(int64_t sub, const char* t);
void    slqt_be_subwindow_show_maximized(int64_t sub);
/* 对话框：QDialog（BaseDialog 基类） */
int64_t slqt_be_dialog_create(int64_t parent);
void    slqt_be_dialog_set_modal(int64_t d, int32_t on);
int32_t slqt_be_dialog_exec(int64_t d);
void    slqt_be_dialog_accept(int64_t d);
void    slqt_be_dialog_reject(int64_t d);
/* 控件 min/max 尺寸（面板规格钳制落地） */
void    slqt_be_widget_set_min_size(int64_t h, int32_t w, int32_t hh);
void    slqt_be_widget_set_max_size(int64_t h, int32_t w, int32_t hh);

/* ── 2026-11-12 P2 能力扩展后端契约（与 slang_qt.h *_sl 导出一一对应）──── */
/* QFileDialog：返回静态缓冲指针，取消为空串 */
const char* slqt_be_filedialog_open(const char* dir, const char* filter);
const char* slqt_be_filedialog_save(const char* dir, const char* filter);
const char* slqt_be_filedialog_dir(const char* dir);
/* QStatusBar */
int64_t slqt_be_statusbar_create(int64_t parent);
void    slqt_be_mainwindow_set_statusbar(int64_t win, int64_t sb);
void    slqt_be_statusbar_show_message(int64_t sb, const char* t);
void    slqt_be_statusbar_add_widget(int64_t sb, int64_t w);
/* QTreeWidget：路径字符串按 '/' 分层，SL 侧只传字符串不碰 item 句柄 */
int64_t     slqt_be_tree_create(int64_t parent);
void        slqt_be_tree_set_header(int64_t h, const char* t);
void        slqt_be_tree_clear(int64_t h);
void        slqt_be_tree_add_path(int64_t h, const char* path);
int32_t     slqt_be_tree_count(int64_t h);
const char* slqt_be_tree_selected_path(int64_t h);
/* QSplitter */
int64_t slqt_be_splitter_create(int64_t parent, int32_t vertical);
void    slqt_be_splitter_add_widget(int64_t sp, int64_t w);
void    slqt_be_splitter_set_sizes(int64_t sp, int32_t a, int32_t b, int32_t c);
/* QCodeEdit 复合控件 */
int64_t     slqt_be_codeedit_create(int64_t parent);
void        slqt_be_codeedit_set_text(int64_t h, const char* t);
const char* slqt_be_codeedit_text(int64_t h);
void        slqt_be_codeedit_set_readonly(int64_t h, int32_t on);
void        slqt_be_codeedit_goto_line(int64_t h, int32_t line);
int32_t     slqt_be_codeedit_cursor_line(int64_t h);
void        slqt_be_codeedit_set_highlight(int64_t h, int32_t on);
void        slqt_be_codeedit_set_breakpoint(int64_t h, int32_t line, int32_t on);
int32_t     slqt_be_codeedit_toggle_breakpoint(int64_t h);
void        slqt_be_codeedit_clear_breakpoints(int64_t h);
const char* slqt_be_codeedit_breakpoints(int64_t h);
void        slqt_be_codeedit_set_font_pt(int64_t h, int32_t pt);
const char* slqt_be_codeedit_word(int64_t h);
const char* slqt_be_codeedit_selected(int64_t h);
void        slqt_be_codeedit_set_bound(int64_t h, const char* csv);
void        slqt_be_codeedit_set_stopped(int64_t h, int32_t line);

/* 2026-11-13 VS 多标签：QTabWidget（page 为任意 QWidget 句柄；SL 侧只传字符串标题） */
int64_t     slqt_be_tab_create(int64_t parent);
int32_t     slqt_be_tab_add(int64_t h, int64_t page, const char* title);
int32_t     slqt_be_tab_count(int64_t h);
int32_t     slqt_be_tab_current(int64_t h);
void        slqt_be_tab_set_current(int64_t h, int32_t idx);
const char* slqt_be_tab_text(int64_t h, int32_t idx);
void        slqt_be_tab_set_text(int64_t h, int32_t idx, const char* title);
void        slqt_be_tab_remove(int64_t h, int32_t idx);
void        slqt_be_tab_clear(int64_t h);
void        slqt_be_tab_set_closable(int64_t h, int32_t on);

/* 2026-11-12 第四轮：SLDP TCP 客户端桥（Qt/Stub 双后端契约） */
int32_t     slqt_be_sldp_connect(int32_t port);
void        slqt_be_sldp_send(const char* utf8);
const char* slqt_be_sldp_poll(void);
int32_t     slqt_be_sldp_connected(void);
void        slqt_be_sldp_close(void);

#ifdef __cplusplus
}
#endif

#endif /* SLANG_QT_BACKEND_H */
