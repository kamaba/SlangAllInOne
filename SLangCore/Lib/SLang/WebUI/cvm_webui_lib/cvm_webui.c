/*
 * cvm_webui.c —— SLang WebUI 模块原生实现（产物 webui_lib.dll）
 * ==========================================================================
 * 位于 webui（MIT，见 webui.h / webui.c）之上的一层扁平 C ABI 包装，
 * 供 WebUI.sl 经 @DllStaticImport 静态绑定直调（opcode 77）。
 *
 * 设计取舍：
 *   1) **句柄化 / 标量化**：webui 的 size_t 窗口号、webui_event_t* 一律换成
 *      Int64 / ptr 传给 SLang，避开 Ptr 无法由编译器推导 FFI sig 的问题。
 *   2) **自包含构建**：webui.c 与本项目一同编译进 webui_lib.dll（与
 *      Mysql 静链 mysqlclient 同思路），产物单 DLL、无外部 webui.dll 依赖。
 *   3) **回调桥**：webui 的 void(*)(webui_event_t*) 经本层单一 trampoline
 *      （按 bind_id 查 SLang 回调节流点）重入 SLang VM；SLang 处理函数签名
 *      `static void onEvent(Int64 e)`。不依赖运行时代码生成。
 *
 * 线程模型：默认 webui_init_sl() 开启 ui_event_blocking，使事件串行处理，
 * 规避 SLang VM 并发重入（详见 设计文档 02 §4）。
 */

#include "cvm_webui.h"

/* webui_wrap.h：webui 的最小 ABI 声明（不拉 windows.h 等平台头，规避 UCRT 冲突）。
 * 真实 webui.c 仍自带 webui.h；本头仅服务包装层与占位实现。 */
#include "webui_wrap.h"

#include <stdlib.h>
#include <string.h>

/* ========================================================================
 * 回调桥：bind_id -> SLang 回调节流点地址（createCallback 生成的 C 指针）
 * ======================================================================== */

typedef struct _SLWebUIBinding
{
    size_t   window;   /* 事件所属窗口号：webui_bind 的 index 按窗口独立编号，
                          必须与 bind_id 联合作键，否则多窗口同 index 互相覆盖 */
    size_t   bind_id;  /* webui_bind 返回的（窗口内）绑定 ID */
    int64_t  sl_cb;     /* void(*)(int64_t)：createCallback 节流点 */
    int64_t  slot;      /* bindHandle: SL 层 handler 表槽位 */
    int      has_slot;  /* 0 = bindEvent 单参 cb(e)；1 = bindHandle 双参 cb(slot, e) */
} SLWebUIBinding;

#define SL_WEBUI_BIND_INIT 256
static SLWebUIBinding* g_bindings = NULL;
static int             g_bind_count = 0;
static int             g_bind_cap = 0;

static int sl_webui_add_binding2( size_t window, size_t bind_id, int64_t sl_cb, int64_t slot, int has_slot )
{
    if ( g_bindings == NULL )
    {
        g_bind_cap = SL_WEBUI_BIND_INIT;
        g_bindings = (SLWebUIBinding*)calloc( g_bind_cap, sizeof(SLWebUIBinding) );
        if ( g_bindings == NULL ) return 0;
    }
    if ( g_bind_count >= g_bind_cap )
    {
        int ncap = g_bind_cap * 2;
        SLWebUIBinding* nb = (SLWebUIBinding*)realloc( g_bindings, (size_t)ncap * sizeof(SLWebUIBinding) );
        if ( nb == NULL ) return 0;
        g_bindings = nb;
        g_bind_cap = ncap;
    }
    g_bindings[g_bind_count].window  = window;
    g_bindings[g_bind_count].bind_id = bind_id;
    g_bindings[g_bind_count].sl_cb   = sl_cb;
    g_bindings[g_bind_count].slot    = slot;
    g_bindings[g_bind_count].has_slot = has_slot;
    g_bind_count++;
    return 1;
}

static const SLWebUIBinding* sl_webui_find( size_t window, size_t bind_id )
{
    int i;
    for ( i = 0; i < g_bind_count; i++ )
    {
        if ( g_bindings[i].window == window && g_bindings[i].bind_id == bind_id )
            return &g_bindings[i];
    }
    return NULL;
}

/* webui 调用的原生回调：统一入口，按 (window, bind_id) 查 SLang 节流点并重入 VM。
 * bindEvent（按名绑定）走单参 cb(e)；bindHandle（函数值绑定）走双参
 * cb(slot, e)，由 SL 层 _dispatchHandle 按槽位取回 Function 值调用。 */
static void sl_webui_trampoline( webui_event_t* e )
{
    const SLWebUIBinding* b = sl_webui_find( e->window, e->bind_id );
    if ( b == NULL || b->sl_cb == 0 ) return;   /* 未绑定 / 桩创建失败，安全跳过 */
    if ( b->has_slot )
    {
        ((void (*)(int64_t, int64_t))b->sl_cb)( b->slot, (int64_t)(size_t)e );
        return;
    }
    /* 重入 SLang VM：事件指针作为 int64 参数传入 createCallback 节流点 */
    ((void (*)(int64_t))b->sl_cb)( (int64_t)(size_t)e );
}

/* ========================================================================
 * 文件处理器桥（webui_set_file_handler -> SLang handler）
 * ------------------------------------------------------------------------
 * webui 期望 const void* (*)(const char* filename, int* length)。SLang FFI
 * 回调只能返回标量，故本层中转：
 *   1) trampoline 收到 filename，重入 SLang handler（sig "ptr->void"）；
 *   2) SLang handler 经 webui_file_response_sl() 把响应（含 HTTP 头的完整
 *      报文）拷入本层缓冲（自持堆拷贝，规避 SL 字符串封送生命周期）；
 *   3) trampoline 把缓冲拷入 webui_malloc（webui 自动释放）并置 *length；
 *      SLang 未设置响应 -> 返回 NULL，webui 回落本地文件。
 * 串行化依赖 webui_init_sl 的 ui_event_blocking（单缓冲即安全）。
 * ======================================================================== */

static int64_t g_file_sl_cb = 0;            /* SLang handler 节流点 */
static char*   g_file_response = NULL;      /* webui_file_response_sl 写入 */
static int     g_file_response_len = 0;
static int     g_file_has_response = 0;

static const void* sl_webui_file_trampoline( const char* filename, int* length )
{
    g_file_response = NULL;
    g_file_response_len = 0;
    g_file_has_response = 0;
    if ( g_file_sl_cb != 0 )
    {
        ((void (*)(int64_t))g_file_sl_cb)( (int64_t)(size_t)filename );
    }
    if ( !g_file_has_response || g_file_response == NULL )
    {
        *length = 0;
        return NULL;                        /* 回落本地文件 */
    }
    {
        void* buf = webui_malloc( (size_t)g_file_response_len );
        if ( buf == NULL )
        {
            *length = 0;
            return NULL;
        }
        memcpy( buf, g_file_response, (size_t)g_file_response_len );
        *length = g_file_response_len;
        return buf;
    }
}

WEBUI_SL_API void webui_set_file_handler_sl(int64_t w, int64_t sl_cb)
{
    g_file_sl_cb = sl_cb;
    webui_set_file_handler( (size_t)w, sl_webui_file_trampoline );
}

/* SLang handler 回调体内调用：写入本次文件请求的响应（完整 HTTP 报文）。
 * has_content = 0 -> 本次回落本地文件。内容立即拷贝，调用返回后失效。 */
WEBUI_SL_API void webui_file_response_sl(const char* content, int32_t has_content)
{
    if ( has_content == 0 || content == NULL )
    {
        g_file_has_response = 0;
        return;
    }
    {
        size_t len = strlen( content );
        char* nb = (char*)realloc( g_file_response, len + 1 );
        if ( nb == NULL )
        {
            g_file_has_response = 0;
            return;
        }
        g_file_response = nb;
        memcpy( nb, content, len + 1 );
        g_file_response_len = (int)len;
        g_file_has_response = 1;
    }
}

/* ========================================================================
 * 窗口生命周期 / 控制
 * ======================================================================== */

WEBUI_SL_API int64_t webui_new_window_sl(void) {
    return (int64_t)webui_new_window();
}

WEBUI_SL_API int64_t webui_new_window_id_sl(int64_t id) {
    return (int64_t)webui_new_window_id( (size_t)id );
}

WEBUI_SL_API int64_t webui_get_new_window_id_sl(void) {
    return (int64_t)webui_get_new_window_id();
}

WEBUI_SL_API int32_t webui_show_sl(int64_t w, const char* c) {
    return webui_show( (size_t)w, c ) ? 1 : 0;
}

WEBUI_SL_API int32_t webui_show_browser_sl(int64_t w, const char* c, int64_t b) {
    return webui_show_browser( (size_t)w, c, (size_t)b ) ? 1 : 0;
}

WEBUI_SL_API int32_t webui_show_wv_sl(int64_t w, const char* c) {
    return webui_show_wv( (size_t)w, c ) ? 1 : 0;
}

WEBUI_SL_API void webui_close_sl(int64_t w) { webui_close( (size_t)w ); }
WEBUI_SL_API void webui_destroy_sl(int64_t w) { webui_destroy( (size_t)w ); }

WEBUI_SL_API int32_t webui_is_shown_sl(int64_t w) {
    return webui_is_shown( (size_t)w ) ? 1 : 0;
}

WEBUI_SL_API void webui_exit_sl(void) { webui_exit(); }
WEBUI_SL_API void webui_wait_sl(void) { webui_wait(); }

WEBUI_SL_API int32_t webui_wait_async_sl(void) {
    return webui_wait_async() ? 1 : 0;
}

WEBUI_SL_API void webui_clean_sl(void) { webui_clean(); }

/* 默认安全：单窗串行处理事件，规避 SLang VM 并发重入（见设计文档 02 §4）。 */
WEBUI_SL_API void webui_init_sl(void) {
    webui_set_config( ui_event_blocking, 1 /*true*/ );
}

/* ========================================================================
 * 事件绑定
 * ======================================================================== */

WEBUI_SL_API int64_t webui_bind_sl(int64_t w, const char* element, int64_t sl_cb)
{
    size_t id = webui_bind( (size_t)w, element, sl_webui_trampoline );
    if ( id == 0 ) return 0;          /* webui 失败 */
    sl_webui_add_binding2( (size_t)w, id, sl_cb, 0, 0 ); /* (win,bind_id) -> SLang 节流点 */
    return (int64_t)id;
}

/* bindHandle：函数值绑定。slot = SL 层 handler 表下标，dispatch_cb =
 * SLang.WebUI._dispatchHandle 的 createCallback 节流点（sig "i64,i64->void"）。
 * 事件到达时 trampoline 以 cb(slot, e) 重入 VM，SL 层按槽位取回用户 Function 调用。 */
WEBUI_SL_API int64_t webui_bind_handle_sl(int64_t w, const char* element, int64_t slot, int64_t dispatch_cb)
{
    size_t id = webui_bind( (size_t)w, element, sl_webui_trampoline );
    if ( id == 0 ) return 0;
    sl_webui_add_binding2( (size_t)w, id, dispatch_cb, slot, 1 );
    return (int64_t)id;
}

/* ========================================================================
 * 窗口属性
 * ======================================================================== */

WEBUI_SL_API void webui_set_size_sl(int64_t w, int32_t wd, int32_t ht) {
    webui_set_size( (size_t)w, (unsigned int)wd, (unsigned int)ht );
}
WEBUI_SL_API void webui_set_minimum_size_sl(int64_t w, int32_t wd, int32_t ht) {
    webui_set_minimum_size( (size_t)w, (unsigned int)wd, (unsigned int)ht );
}
WEBUI_SL_API void webui_set_position_sl(int64_t w, int32_t x, int32_t y) {
    webui_set_position( (size_t)w, (unsigned int)x, (unsigned int)y );
}
WEBUI_SL_API void webui_set_center_sl(int64_t w) {
    webui_set_center( (size_t)w );
}
WEBUI_SL_API void webui_set_kiosk_sl(int64_t w, int32_t on) {
    webui_set_kiosk( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_set_hide_sl(int64_t w, int32_t on) {
    webui_set_hide( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_set_resizable_sl(int64_t w, int32_t on) {
    webui_set_resizable( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_focus_sl(int64_t w) { webui_focus( (size_t)w ); }
WEBUI_SL_API void webui_minimize_sl(int64_t w) { webui_minimize( (size_t)w ); }
WEBUI_SL_API void webui_maximize_sl(int64_t w) { webui_maximize( (size_t)w ); }
WEBUI_SL_API void webui_set_frameless_sl(int64_t w, int32_t on) {
    webui_set_frameless( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_set_transparent_sl(int64_t w, int32_t on) {
    webui_set_transparent( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_set_high_contrast_sl(int64_t w, int32_t on) {
    webui_set_high_contrast( (size_t)w, on != 0 );
}
WEBUI_SL_API void webui_set_icon_sl(int64_t w, const char* icon, const char* icon_type) {
    webui_set_icon( (size_t)w, icon, icon_type );
}
WEBUI_SL_API void webui_set_public_sl(int64_t w, int32_t on) {
    webui_set_public( (size_t)w, on != 0 );
}

/* ========================================================================
 * JS 执行
 * ======================================================================== */

WEBUI_SL_API void webui_run_sl(int64_t w, const char* js) {
    webui_run( (size_t)w, js );
}

WEBUI_SL_API void webui_run_client_sl(int64_t e, const char* js) {
    webui_run_client( (webui_event_t*)(size_t)e, js );
}

/* webui_script 的 char* buf/len 是输出缓冲区，SLang FFI 无法表达 ->
 * 本层封装为 -> const char*（内部静态缓冲，VM 立即拷走，安全）。 */
#define SL_WEBUI_SCRIPT_BUF 65536
WEBUI_SL_API const char* webui_script_sl(int64_t w, const char* js, int64_t timeout)
{
    static char buf[SL_WEBUI_SCRIPT_BUF];
    if ( !webui_script( (size_t)w, js, (size_t)timeout, buf, sizeof(buf) ) ) return "";
    return buf;
}

/* ========================================================================
 * 服务器 / 文件
 * ======================================================================== */

WEBUI_SL_API int32_t webui_set_root_folder_sl(int64_t w, const char* path) {
    return webui_set_root_folder( (size_t)w, path ) ? 1 : 0;
}
WEBUI_SL_API const char* webui_start_server_sl(int64_t w, const char* content) {
    return webui_start_server( (size_t)w, content );
}
WEBUI_SL_API int32_t webui_set_port_sl(int64_t w, int64_t port) {
    return webui_set_port( (size_t)w, (size_t)port ) ? 1 : 0;
}
WEBUI_SL_API int64_t webui_get_port_sl(int64_t w) {
    return (int64_t)webui_get_port( (size_t)w );
}
WEBUI_SL_API const char* webui_get_url_sl(int64_t w) {
    return webui_get_url( (size_t)w );
}
WEBUI_SL_API void webui_open_url_sl(const char* url) {
    webui_open_url( url );
}
WEBUI_SL_API void webui_navigate_sl(int64_t w, const char* url) {
    webui_navigate( (size_t)w, url );
}
WEBUI_SL_API void webui_set_timeout_sl(int64_t second) {
    webui_set_timeout( (size_t)second );
}
WEBUI_SL_API void webui_set_runtime_sl(int64_t w, int64_t runtime) {
    webui_set_runtime( (size_t)w, (size_t)runtime );
}

/* ========================================================================
 * 事件参数读取（回调内调用，e = webui_event_t*）
 * ======================================================================== */

WEBUI_SL_API int64_t webui_get_count_sl(int64_t e) {
    return (int64_t)webui_get_count( (webui_event_t*)(size_t)e );
}
WEBUI_SL_API int64_t webui_get_int_at_sl(int64_t e, int64_t i) {
    return (int64_t)webui_get_int_at( (webui_event_t*)(size_t)e, (size_t)i );
}
WEBUI_SL_API double webui_get_float_at_sl(int64_t e, int64_t i) {
    return webui_get_float_at( (webui_event_t*)(size_t)e, (size_t)i );
}
WEBUI_SL_API const char* webui_get_string_at_sl(int64_t e, int64_t i) {
    return webui_get_string_at( (webui_event_t*)(size_t)e, (size_t)i );
}
WEBUI_SL_API int32_t webui_get_bool_at_sl(int64_t e, int64_t i) {
    return webui_get_bool_at( (webui_event_t*)(size_t)e, (size_t)i ) ? 1 : 0;
}

/* ---- 事件结构体字段读取（回调内；e = webui_event_t*）---- */

WEBUI_SL_API int64_t webui_event_window_sl(int64_t e) {
    return (int64_t)((webui_event_t*)(size_t)e)->window;
}
WEBUI_SL_API int64_t webui_event_type_sl(int64_t e) {
    return (int64_t)((webui_event_t*)(size_t)e)->event_type;
}
WEBUI_SL_API const char* webui_event_element_sl(int64_t e) {
    return ((webui_event_t*)(size_t)e)->element;
}
WEBUI_SL_API int64_t webui_event_client_id_sl(int64_t e) {
    return (int64_t)((webui_event_t*)(size_t)e)->client_id;
}
WEBUI_SL_API int64_t webui_event_connection_id_sl(int64_t e) {
    return (int64_t)((webui_event_t*)(size_t)e)->connection_id;
}
WEBUI_SL_API const char* webui_event_cookies_sl(int64_t e) {
    return ((webui_event_t*)(size_t)e)->cookies;
}

/* 读任意 C 字符串（如文件处理器回调收到的 filename 指针） */
WEBUI_SL_API const char* webui_peek_string_sl(int64_t ptr) {
    return (const char*)(size_t)ptr;
}

/* ========================================================================
 * 事件返回值（回调内调用，回传 JS）
 * ======================================================================== */

WEBUI_SL_API void webui_return_int_sl(int64_t e, int64_t n) {
    webui_return_int( (webui_event_t*)(size_t)e, (long long)n );
}
WEBUI_SL_API void webui_return_float_sl(int64_t e, double f) {
    webui_return_float( (webui_event_t*)(size_t)e, f );
}
WEBUI_SL_API void webui_return_string_sl(int64_t e, const char* s) {
    webui_return_string( (webui_event_t*)(size_t)e, s );
}
WEBUI_SL_API void webui_return_bool_sl(int64_t e, int32_t b) {
    webui_return_bool( (webui_event_t*)(size_t)e, b != 0 );
}
