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
 * 窗口生命周期 / 控制
 * ======================================================================== */

WEBUI_SL_API int64_t webui_new_window_sl(void) {
    return (int64_t)webui_new_window();
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

/* ========================================================================
 * JS 执行
 * ======================================================================== */

WEBUI_SL_API void webui_run_sl(int64_t w, const char* js) {
    webui_run( (size_t)w, js );
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
