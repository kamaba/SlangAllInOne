#ifndef WEBUI_WRAP_H
#define WEBUI_WRAP_H

/* ============================================================================
 * webui_wrap.h —— webui 的最小 ABI 声明（C 包装层 / stub 共用）
 * ----------------------------------------------------------------------------
 * webui 上游 webui.h 拉入了 windows.h / winsock2 / inttypes / pthread / sys/*
 * 等跨平台头，在某些 MSVC 工具链下会污染 UCRT（uintptr_t 宏被破坏）。本头只声明
 * cvm_webui.c 实际调用的函数 + webui_event_t + webui_config，不引入任何平台头，
 * 彻底规避该冲突。签名严格对齐 webui.h（v2.5.0-beta.4）。
 *
 * 真实编译 webui.c 时，webui.c 自身仍 include 上游 webui.h（那是 webui 自己的文件，
 * 由其原生构建环境负责）；本头仅服务我们的包装层与占位实现，二者不混用。
 * ========================================================================== */

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

/* 包装层 / stub 里的 webui_* 为 DLL 内部符号，无需 dllexport；
 * 真实编译时 webui.c 用上游 webui.h 的 WEBUI_EXPORT（dllexport）。 */
#ifndef WEBUI_EXPORT
#define WEBUI_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 事件结构体：布局严格对齐上游 webui.h v2.5.0-beta.4（bind_id 在偏移 32，
 * 首字段是 window——最小单字段声明会把 window 误读成 bind_id）；
 * 真实 webui.c 用完整结构，此处按同序声明到 cookies 即可。 */
typedef struct webui_event_t
{
    size_t window;        /* 窗口号（多窗口绑定表区分键）*/
    size_t event_type;    /* 事件类型 */
    char*  element;       /* HTML 元素 ID */
    size_t event_number;  /* Internal WebUI */
    size_t bind_id;       /* 绑定 ID（窗口内编号），用于查 SLang 回调节流点 */
    size_t client_id;     /* Client's unique ID */
    size_t connection_id; /* Client's connection ID */
    char*  cookies;       /* Client's full cookies */
} webui_event_t;

typedef enum webui_config
{
    show_wait_connection = 0,
    ui_event_blocking,
    folder_monitor,
    multi_client,
    use_cookies,
    asynchronous_response
} webui_config;

/* webui_* 为 DLL 内部符号（由真实 webui.c 或 webui_stub.c 提供），无需 dllexport；
 * 外部导出的是 cvm_webui.c 的 webui_*_sl（见 cvm_webui.h 的 WEBUI_SL_API）。 */

/* ---- 窗口生命周期 / 控制 ---- */
size_t webui_new_window(void);
bool   webui_show(size_t window, const char* content);
bool   webui_show_browser(size_t window, const char* content, size_t browser);
bool   webui_show_wv(size_t window, const char* content);
void   webui_close(size_t window);
void   webui_destroy(size_t window);
bool   webui_is_shown(size_t window);
void   webui_exit(void);
void   webui_wait(void);
bool   webui_wait_async(void);
void   webui_clean(void);

/* ---- 事件绑定 ---- */
size_t webui_bind(size_t window, const char* element, void (*func)(webui_event_t* e));

/* ---- 配置 ---- */
void   webui_set_config(webui_config option, bool status);

/* ---- 窗口属性 ---- */
void   webui_set_size(size_t window, unsigned int width, unsigned int height);
void   webui_set_minimum_size(size_t window, unsigned int width, unsigned int height);
void   webui_set_position(size_t window, unsigned int x, unsigned int y);
void   webui_set_center(size_t window);
void   webui_set_kiosk(size_t window, bool status);
void   webui_set_hide(size_t window, bool status);
void   webui_set_resizable(size_t window, bool status);
void   webui_focus(size_t window);
void   webui_minimize(size_t window);
void   webui_maximize(size_t window);

/* ---- JS 执行 ---- */
void   webui_run(size_t window, const char* script);
bool   webui_script(size_t window, const char* script, size_t timeout, char* buffer, size_t buffer_length);

/* ---- 服务器 / 文件 ---- */
bool   webui_set_root_folder(size_t window, const char* path);
const char* webui_start_server(size_t window, const char* content);

/* ---- 事件参数读取 ---- */
size_t webui_get_count(webui_event_t* e);
long long int webui_get_int_at(webui_event_t* e, size_t index);
double webui_get_float_at(webui_event_t* e, size_t index);
const char* webui_get_string_at(webui_event_t* e, size_t index);
bool   webui_get_bool_at(webui_event_t* e, size_t index);

/* ---- 事件返回值 ---- */
void   webui_return_int(webui_event_t* e, long long int n);
void   webui_return_float(webui_event_t* e, double f);
void   webui_return_string(webui_event_t* e, const char* s);
void   webui_return_bool(webui_event_t* e, bool b);

#ifdef __cplusplus
}
#endif

#endif /* WEBUI_WRAP_H */
