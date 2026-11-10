/*
 * slang_qt_stub.c —— SLang QT 模块后端 STUB 实现（纯 C，无 Qt 依赖）
 * ==========================================================================
 * 把 slang_qt_backend.h 声明的 slqt_be_* 全部实现为 no-op（或返回安全值），
 * 使 slang_qt.dll 在**无 Qt 环境**即可编译/运行，用于 headless 验证整条
 * SLang 链路（FFI 绑定、句柄注册表、信号连接 bind_id、示例逻辑）。
 *
 * 行为约定（对照 webui_stub.c）：
 *   - 创建类函数返回递增的伪句柄（>0），SLang 侧判 isValid。
 *   - set* 系列静默忽略；get* 返回空串 / 0。
 *   - app_exec 立即返回（不阻塞），保证 headless 示例跑完。
 *   - connect 由绑定层记录并返回 bind_id（>0），但不发射事件。
 *
 * 真实 GUI 能力由 slang_qt_qt.cpp（Qt6）提供；构建切换见 README 与
 * slang_qt.vcxproj / slang_qt_qt.vcxproj。
 */

#include "slang_qt_backend.h"

#include <stdio.h>
#include <string.h>

static char g_empty[] = "";

/* 伪句柄：stub 不持有真实对象，注册表存 NULL 即可；句柄下标本身 >0。 */
int64_t slqt_be_app_create(void)
{
    return slqt_register(NULL);
}
void    slqt_be_app_set_stylesheet(const char* c) { (void)c; }
void    slqt_be_app_exec(void) { /* headless：不进入事件循环，立即返回 */ }
void    slqt_be_app_process_events(void) { /* no-op */ }
void    slqt_be_app_quit(void) { /* no-op */ }
int32_t slqt_be_app_argc(void) { return 0; }

void    slqt_be_object_delete(int64_t h) { (void)h; }
int32_t slqt_be_object_is_valid(int64_t h) { return (h >= 0) ? 1 : 0; }

int64_t slqt_be_widget_create(int64_t p) { (void)p; return slqt_register(NULL); }
void    slqt_be_widget_set_parent(int64_t h, int64_t p) { (void)h; (void)p; }
void    slqt_be_widget_set_text(int64_t h, const char* t) { (void)h; (void)t; }
const char* slqt_be_widget_text(int64_t h) { (void)h; return g_empty; }
void    slqt_be_widget_set_geometry(int64_t h, int32_t x, int32_t y, int32_t w, int32_t hh) { (void)h;(void)x;(void)y;(void)w;(void)hh; }
void    slqt_be_widget_resize(int64_t h, int32_t w, int32_t hh) { (void)h;(void)w;(void)hh; }
void    slqt_be_widget_show(int64_t h) { (void)h; }
void    slqt_be_widget_hide(int64_t h) { (void)h; }
void    slqt_be_widget_set_enabled(int64_t h, int32_t on) { (void)h;(void)on; }
void    slqt_be_widget_set_visible(int64_t h, int32_t on) { (void)h;(void)on; }
void    slqt_be_widget_set_tooltip(int64_t h, const char* t) { (void)h;(void)t; }
void    slqt_be_widget_set_style_sheet(int64_t h, const char* c) { (void)h;(void)c; }
void    slqt_be_widget_set_fixed_size(int64_t h, int32_t w, int32_t hh) { (void)h;(void)w;(void)hh; }
void    slqt_be_widget_update(int64_t h) { (void)h; }

int64_t slqt_be_button_create(int64_t p) { (void)p; return slqt_register(NULL); }
int64_t slqt_be_label_create(int64_t p) { (void)p; return slqt_register(NULL); }
int32_t slqt_be_label_set_pixmap(int64_t h, int64_t ptr, int32_t len) { (void)h;(void)ptr;(void)len; return 0; }
int64_t slqt_be_edit_create(int64_t p) { (void)p; return slqt_register(NULL); }
void    slqt_be_edit_set_placeholder(int64_t h, const char* t) { (void)h;(void)t; }
const char* slqt_be_edit_text(int64_t h) { (void)h; return g_empty; }
void    slqt_be_edit_set_readonly(int64_t h, int32_t on) { (void)h;(void)on; }

/* QTextEdit / QListWidget stub：伪句柄 + 安全值（headless 链路验证用） */
int64_t     slqt_be_textedit_create(int64_t p) { (void)p; return slqt_register(NULL); }
void        slqt_be_textedit_set_text(int64_t h, const char* t) { (void)h;(void)t; }
const char* slqt_be_textedit_text(int64_t h) { (void)h; return g_empty; }
void        slqt_be_textedit_set_readonly(int64_t h, int32_t on) { (void)h;(void)on; }
void        slqt_be_textedit_append(int64_t h, const char* t) { (void)h;(void)t; }
int64_t     slqt_be_list_create(int64_t p) { (void)p; return slqt_register(NULL); }
void        slqt_be_list_add_item(int64_t h, const char* t) { (void)h;(void)t; }
void        slqt_be_list_clear(int64_t h) { (void)h; }
int32_t     slqt_be_list_count(int64_t h) { (void)h; return 0; }
int32_t     slqt_be_list_current_row(int64_t h) { (void)h; return -1; }
void        slqt_be_list_set_current_row(int64_t h, int32_t row) { (void)h;(void)row; }
const char* slqt_be_list_item_text(int64_t h, int32_t row) { (void)h;(void)row; return g_empty; }

int64_t slqt_be_mainwindow_create(void) { return slqt_register(NULL); }
void    slqt_be_mainwindow_set_central(int64_t h, int64_t w) { (void)h;(void)w; }
void    slqt_be_mainwindow_set_title(int64_t h, const char* t) { (void)h;(void)t; }
void    slqt_be_mainwindow_resize(int64_t h, int32_t w, int32_t hh) { (void)h;(void)w;(void)hh; }
void    slqt_be_mainwindow_show(int64_t h) { (void)h; }
int32_t slqt_be_messagebox_info(int64_t p, const char* t, const char* x) { (void)p;(void)t;(void)x; return 0; }
int32_t slqt_be_messagebox_question(int64_t p, const char* t, const char* x) { (void)p;(void)t;(void)x; return 0; }

int64_t slqt_be_vbox_create(int64_t p) { (void)p; return slqt_register(NULL); }
int64_t slqt_be_hbox_create(int64_t p) { (void)p; return slqt_register(NULL); }
int64_t slqt_be_grid_create(int64_t p) { (void)p; return slqt_register(NULL); }
void    slqt_be_layout_add_widget(int64_t l, int64_t w) { (void)l;(void)w; }
void    slqt_be_layout_add_spacing(int64_t l, int32_t px) { (void)l;(void)px; }
void    slqt_be_layout_add_stretch(int64_t l, int32_t s) { (void)l;(void)s; }
void    slqt_be_layout_set_contents_margins(int64_t l, int32_t a, int32_t b, int32_t c, int32_t d) { (void)l;(void)a;(void)b;(void)c;(void)d; }
void    slqt_be_layout_set_spacing(int64_t l, int32_t px) { (void)l;(void)px; }
void    slqt_be_layout_set_widget_at(int64_t g, int64_t w, int32_t r, int32_t c, int32_t rs, int32_t cs) { (void)g;(void)w;(void)r;(void)c;(void)rs;(void)cs; }
void    slqt_be_widget_set_layout(int64_t w, int64_t l) { (void)w;(void)l; }

int64_t slqt_be_connect(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot)
{
    /* stub：不发射事件；绑定层已记录并返回 bind_id。 */
    (void)h; (void)signalId; (void)dispatchCb; (void)slot;
    return 1;
}

/* ========================================================================
 * 2026-11-03 扩展面 stub：全部 no-op / 安全值。QTTest 按 backend_kind ==
 * "stub" 只走 smoke 断言，扩展面板按组合探测结果 SKIP。
 * ======================================================================== */
const char* slqt_be_backend_kind(void) { return "stub"; }

const char* slqt_be_app_platform_name(void) { return "none"; }
const char* slqt_be_app_library_paths(void) { return g_empty; }
const char* slqt_be_app_style_keys(void) { return g_empty; }
int32_t     slqt_be_app_set_style(const char* n) { (void)n; return 0; }

void    slqt_be_widget_move(int64_t h, int32_t x, int32_t y) { (void)h;(void)x;(void)y; }
int64_t slqt_be_timer_create(int32_t ms, int32_t single, int64_t cb, int64_t slot)
{ (void)ms;(void)single;(void)cb;(void)slot; return slqt_register(NULL); }
void    slqt_be_timer_delete(int64_t h) { (void)h; }
void    slqt_be_timer_start(int64_t h, int32_t ms) { (void)h;(void)ms; }
void    slqt_be_timer_stop(int64_t h) { (void)h; }
int32_t slqt_be_timer_active(int64_t h) { (void)h; return 0; }

int64_t     slqt_be_net_create(void) { return slqt_register(NULL); }
void        slqt_be_net_delete(int64_t h) { (void)h; }
int32_t     slqt_be_net_is_online(void) { return -1; }
const char* slqt_be_net_backend_name(void) { return g_empty; }
int64_t     slqt_be_net_get(int64_t h, const char* url) { (void)h;(void)url; return slqt_register(NULL); }
void        slqt_be_net_reply_delete(int64_t h) { (void)h; }
int32_t     slqt_be_net_reply_wait(int64_t h, int32_t ms) { (void)h;(void)ms; return 0; }
int32_t     slqt_be_net_reply_status(int64_t h) { (void)h; return 0; }
const char* slqt_be_net_reply_error(int64_t h) { (void)h; return g_empty; }
const char* slqt_be_net_reply_body(int64_t h) { (void)h; return g_empty; }

const char* slqt_be_sql_drivers(void) { return g_empty; }
int64_t     slqt_be_sql_add_database(const char* type) { (void)type; return slqt_register(NULL); }
void        slqt_be_sql_delete(int64_t h) { (void)h; }
void        slqt_be_sql_set_database_name(int64_t h, const char* name) { (void)h;(void)name; }
int32_t     slqt_be_sql_open(int64_t h) { (void)h; return 0; }
void        slqt_be_sql_close(int64_t h) { (void)h; }
const char* slqt_be_sql_last_error(int64_t h) { (void)h; return g_empty; }
int64_t     slqt_be_sql_query_create(int64_t db) { (void)db; return slqt_register(NULL); }
void        slqt_be_sql_query_delete(int64_t h) { (void)h; }
int32_t     slqt_be_sql_query_exec(int64_t h, const char* sql) { (void)h;(void)sql; return 0; }
int32_t     slqt_be_sql_query_next(int64_t h) { (void)h; return 0; }
const char* slqt_be_sql_query_value_text(int64_t h, int32_t i) { (void)h;(void)i; return g_empty; }
int64_t     slqt_be_sql_query_value_int(int64_t h, int32_t i) { (void)h;(void)i; return 0; }

int64_t slqt_be_svgwidget_create(int64_t p) { (void)p; return slqt_register(NULL); }
int32_t slqt_be_svgwidget_load_file(int64_t h, const char* path) { (void)h;(void)path; return 0; }
int32_t slqt_be_svgwidget_load_data(int64_t h, const char* xml) { (void)h;(void)xml; return 0; }
int64_t slqt_be_svg_renderer_create(const char* xml) { (void)xml; return slqt_register(NULL); }
void    slqt_be_svg_renderer_delete(int64_t h) { (void)h; }
int32_t slqt_be_svg_renderer_valid(int64_t h) { (void)h; return 0; }
int32_t slqt_be_svg_renderer_check_size(int64_t h, int32_t w, int32_t hh) { (void)h;(void)w;(void)hh; return 0; }
int32_t slqt_be_svg_render_to_label(int64_t r, int64_t l, int32_t w, int32_t hh) { (void)r;(void)l;(void)w;(void)hh; return 0; }

const char* slqt_be_image_formats(void) { return g_empty; }
int32_t     slqt_be_image_save_solid(const char* path, const char* fmt, int32_t r, int32_t g, int32_t b) { (void)path;(void)fmt;(void)r;(void)g;(void)b; return 0; }
int32_t     slqt_be_image_check_size(const char* path, int32_t w, int32_t hh) { (void)path;(void)w;(void)hh; return 0; }
int32_t     slqt_be_icon_render(const char* path, int32_t size) { (void)path;(void)size; return 0; }

int64_t slqt_be_glwidget_create(int64_t p) { (void)p; return slqt_register(NULL); }
void    slqt_be_glwidget_set_color(int64_t h, int32_t r, int32_t g, int32_t b) { (void)h;(void)r;(void)g;(void)b; }
void    slqt_be_glwidget_set_spinning(int64_t h, int32_t on) { (void)h;(void)on; }
int64_t slqt_be_glwidget_frame_count(int64_t h) { (void)h; return 0; }

int64_t     slqt_be_printer_create(void) { return slqt_register(NULL); }
void        slqt_be_printer_delete(int64_t h) { (void)h; }
void        slqt_be_printer_set_output_filename(int64_t h, const char* path) { (void)h;(void)path; }
void        slqt_be_printer_set_page_size_a4(int64_t h) { (void)h; }
int32_t     slqt_be_printer_print_text(int64_t h, const char* t, const char* b) { (void)h;(void)t;(void)b; return 0; }
const char* slqt_be_printer_output_file(int64_t h) { (void)h; return g_empty; }

int64_t     slqt_be_dom_create(void) { return slqt_register(NULL); }
void        slqt_be_dom_delete(int64_t h) { (void)h; }
int32_t     slqt_be_dom_set_content(int64_t h, const char* xml) { (void)h;(void)xml; return 0; }
const char* slqt_be_dom_root_tag(int64_t h) { (void)h; return g_empty; }
int64_t     slqt_be_dom_count_by_tag(int64_t h, const char* tag) { (void)h;(void)tag; return 0; }
const char* slqt_be_dom_first_text(int64_t h, const char* tag) { (void)h;(void)tag; return g_empty; }
const char* slqt_be_dom_to_string(int64_t h) { (void)h; return g_empty; }

int64_t slqt_be_concurrent_task_create(int32_t kind, int64_t n) { (void)kind;(void)n; return slqt_register(NULL); }
void    slqt_be_concurrent_task_delete(int64_t h) { (void)h; }
int32_t slqt_be_concurrent_task_is_finished(int64_t h) { (void)h; return 1; }
int64_t slqt_be_concurrent_task_result(int64_t h) { (void)h; return 0; }
int32_t slqt_be_thread_pool_max(void) { return 0; }

void        slqt_be_test_qsleep(int32_t ms) { (void)ms; }
void        slqt_be_test_qwait(int32_t ms) { (void)ms; }
const char* slqt_be_test_version(void) { return "stub"; }

int64_t     slqt_be_uiloader_create(void) { return slqt_register(NULL); }
void        slqt_be_uiloader_delete(int64_t h) { (void)h; }
int64_t     slqt_be_uiloader_load_file(int64_t h, const char* path, int64_t p) { (void)h;(void)path;(void)p; return 0; }
const char* slqt_be_uiloader_available_widgets(int64_t h) { (void)h; return g_empty; }
int64_t     slqt_be_designer_formbuilder_create(void) { return slqt_register(NULL); }
void        slqt_be_designer_formbuilder_delete(int64_t h) { (void)h; }
int64_t     slqt_be_designer_formbuilder_load(int64_t h, const char* path, int64_t p) { (void)h;(void)path;(void)p; return 0; }

int64_t     slqt_be_help_engine_create(const char* collection) { (void)collection; return slqt_register(NULL); }
void        slqt_be_help_engine_delete(int64_t h) { (void)h; }
int32_t     slqt_be_help_setup_data(int64_t h) { (void)h; return 0; }
const char* slqt_be_help_error(int64_t h) { (void)h; return g_empty; }

int32_t     slqt_be_dbus_connected(void) { return 0; }
const char* slqt_be_dbus_base_service(void) { return g_empty; }
