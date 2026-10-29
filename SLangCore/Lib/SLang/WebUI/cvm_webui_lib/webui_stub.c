/*
 * webui_stub.c —— 本地验证用占位实现（NOT 真实 webui）
 * ----------------------------------------------------------------------------
 * 该文件仅用于在无法拉取完整 webui+civetweb 源码树的环境里，验证 SLang <-> webui
 * 绑定链路（@DllStaticImport 静态绑定 / 窗口句柄 / 事件绑定 / FFI 回调节流点）能否
 * 正确编译、导出与运行。它实现 cvm_webui.c 所调用的全部 webui_* 函数为 no-op / 占位，
 * 不会真正打开浏览器。
 *
 * 真实集成：运行 get_webui.ps1 拉取 MIT 的 webui 源码后，vcxproj 会自动改为编译
 * src/webui.c + src/civetweb/civetweb.c（见 get_webui.ps1 末尾的重写逻辑），本文件
 * 即被弃用。
 */
#include "webui_wrap.h"

#include <string.h>

static size_t g_win_id = 0;
static size_t g_bind_id = 0;

WEBUI_EXPORT size_t webui_new_window(void) {
    g_win_id++;
    return g_win_id;
}

WEBUI_EXPORT bool webui_show(size_t window, const char* content) {
    (void)window; (void)content; return 0; /* 占位：无浏览器 */
}
WEBUI_EXPORT bool webui_show_browser(size_t window, const char* content, size_t browser) {
    (void)window; (void)content; (void)browser; return 0;
}
WEBUI_EXPORT bool webui_show_wv(size_t window, const char* content) {
    (void)window; (void)content; return 0;
}

WEBUI_EXPORT void webui_close(size_t window) { (void)window; }
WEBUI_EXPORT void webui_destroy(size_t window) { (void)window; }
WEBUI_EXPORT bool webui_is_shown(size_t window) { (void)window; return 0; }
WEBUI_EXPORT void webui_exit(void) {}
WEBUI_EXPORT void webui_wait(void) {}
WEBUI_EXPORT bool webui_wait_async(void) { return 0; }
WEBUI_EXPORT void webui_clean(void) {}

WEBUI_EXPORT void webui_set_config(webui_config option, bool status) {
    (void)option; (void)status;
}

WEBUI_EXPORT size_t webui_bind(size_t window, const char* element, void (*func)(webui_event_t* e)) {
    (void)window; (void)element; (void)func;
    g_bind_id++;
    return g_bind_id;
}

WEBUI_EXPORT void webui_set_size(size_t window, unsigned int width, unsigned int height) {
    (void)window; (void)width; (void)height;
}
WEBUI_EXPORT void webui_set_minimum_size(size_t window, unsigned int width, unsigned int height) {
    (void)window; (void)width; (void)height;
}
WEBUI_EXPORT void webui_set_position(size_t window, unsigned int x, unsigned int y) {
    (void)window; (void)x; (void)y;
}
WEBUI_EXPORT void webui_set_center(size_t window) { (void)window; }
WEBUI_EXPORT void webui_set_kiosk(size_t window, bool status) { (void)window; (void)status; }
WEBUI_EXPORT void webui_set_hide(size_t window, bool status) { (void)window; (void)status; }
WEBUI_EXPORT void webui_set_resizable(size_t window, bool status) { (void)window; (void)status; }
WEBUI_EXPORT void webui_focus(size_t window) { (void)window; }
WEBUI_EXPORT void webui_minimize(size_t window) { (void)window; }
WEBUI_EXPORT void webui_maximize(size_t window) { (void)window; }

WEBUI_EXPORT void webui_run(size_t window, const char* script) {
    (void)window; (void)script;
}

WEBUI_EXPORT bool webui_script(size_t window, const char* script, size_t timeout,
                               char* buffer, size_t buffer_length) {
    (void)window; (void)script; (void)timeout;
    if (buffer && buffer_length > 0) buffer[0] = '\0';
    return 0;
}

WEBUI_EXPORT bool webui_set_root_folder(size_t window, const char* path) {
    (void)window; (void)path; return 0;
}
WEBUI_EXPORT const char* webui_start_server(size_t window, const char* content) {
    (void)window; (void)content; return "";
}

WEBUI_EXPORT size_t webui_get_count(webui_event_t* e) { (void)e; return 0; }
WEBUI_EXPORT long long int webui_get_int_at(webui_event_t* e, size_t index) {
    (void)e; (void)index; return 0;
}
WEBUI_EXPORT double webui_get_float_at(webui_event_t* e, size_t index) {
    (void)e; (void)index; return 0.0;
}
WEBUI_EXPORT const char* webui_get_string_at(webui_event_t* e, size_t index) {
    (void)e; (void)index; return "";
}
WEBUI_EXPORT bool webui_get_bool_at(webui_event_t* e, size_t index) {
    (void)e; (void)index; return 0;
}

WEBUI_EXPORT void webui_return_int(webui_event_t* e, long long int n) { (void)e; (void)n; }
WEBUI_EXPORT void webui_return_float(webui_event_t* e, double f) { (void)e; (void)f; }
WEBUI_EXPORT void webui_return_string(webui_event_t* e, const char* s) { (void)e; (void)s; }
WEBUI_EXPORT void webui_return_bool(webui_event_t* e, bool b) { (void)e; (void)b; }
