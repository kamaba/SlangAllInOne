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
int64_t slqt_be_edit_create(int64_t parent);
void    slqt_be_edit_set_placeholder(int64_t h, const char* t);
const char* slqt_be_edit_text(int64_t h);
void    slqt_be_edit_set_readonly(int64_t h, int32_t on);

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

#ifdef __cplusplus
}
#endif

#endif /* SLANG_QT_BACKEND_H */
