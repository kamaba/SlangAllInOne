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

#include <string.h>

static char g_empty[] = "";

/* 伪句柄：stub 不持有真实对象，注册表存 NULL 即可；句柄下标本身 >0。 */
int64_t slqt_be_app_create(void) { return slqt_register(NULL); }
void    slqt_be_app_set_style(const char* n) { (void)n; }
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
