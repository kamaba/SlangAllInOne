#ifndef CVM_WEBUI_H
#define CVM_WEBUI_H

/* ==========================================================================
 * cvm_webui.h —— SLang WebUI 模块原生层导出声明（产物 webui_lib.dll）
 * --------------------------------------------------------------------------
 * 本文件是 webui（MIT，见 webui.h / webui.c）之上的一层扁平 C ABI 包装，
 * 供 WebUI.sl 通过 @DllStaticImport 静态绑定直调（opcode 77）。
 *
 * 设计要点（对照 SlangAllInOne/SLangCore/Lib/SLang/Mysql/cvm_sl_mysql_lib/
 *           vm_sl_mysql.h）：
 *   - 导出命名统一前缀 webui_*_sl（区别于 vendored webui 自身的 webui_*）。
 *   - 所有导出函数参数 <= 6、纯标量（bool、整数、const char 指针、ptr），与 SLang
 *     sl_ffi_call 的 x64 ABI 分类（INT 类含指针/utf8，DBL 类 f32/f64）对齐。
 *   - const char* 返回值一律指向 webui 内部缓冲或本库静态缓冲，
 *     SLang VM 在返回瞬间拷入自身 string（调用方不得 free）。
 *   - webui_event_t* 不暴露结构布局给 SLang，仅以 ptr 形态传递；字段读取
 *     全经 webui_get_*_at 系列（见 cvm_webui.c）。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define WEBUI_SL_API __declspec(dllexport)
#else
#  define WEBUI_SL_API
#endif

/* ── 窗口生命周期 / 控制 ─────────────────────────────────────────────── */
WEBUI_SL_API int64_t webui_new_window_sl(void);
WEBUI_SL_API int32_t webui_show_sl(int64_t w, const char* c);
WEBUI_SL_API int32_t webui_show_browser_sl(int64_t w, const char* c, int64_t b);
WEBUI_SL_API int32_t webui_show_wv_sl(int64_t w, const char* c);
WEBUI_SL_API void    webui_close_sl(int64_t w);
WEBUI_SL_API void    webui_destroy_sl(int64_t w);
WEBUI_SL_API int32_t webui_is_shown_sl(int64_t w);
WEBUI_SL_API void    webui_exit_sl(void);
WEBUI_SL_API void    webui_wait_sl(void);
WEBUI_SL_API int32_t webui_wait_async_sl(void);
WEBUI_SL_API void    webui_clean_sl(void);

/* ── 模块初始化 / 事件绑定 ───────────────────────────────────────────── */
WEBUI_SL_API void    webui_init_sl(void);
WEBUI_SL_API int64_t webui_bind_sl(int64_t w, const char* element, int64_t sl_cb);

/* ── 窗口属性 ───────────────────────────────────────────────────────── */
WEBUI_SL_API void webui_set_size_sl(int64_t w, int32_t wd, int32_t ht);
WEBUI_SL_API void webui_set_minimum_size_sl(int64_t w, int32_t wd, int32_t ht);
WEBUI_SL_API void webui_set_position_sl(int64_t w, int32_t x, int32_t y);
WEBUI_SL_API void webui_set_center_sl(int64_t w);
WEBUI_SL_API void webui_set_kiosk_sl(int64_t w, int32_t on);
WEBUI_SL_API void webui_set_hide_sl(int64_t w, int32_t on);
WEBUI_SL_API void webui_set_resizable_sl(int64_t w, int32_t on);
WEBUI_SL_API void webui_focus_sl(int64_t w);
WEBUI_SL_API void webui_minimize_sl(int64_t w);
WEBUI_SL_API void webui_maximize_sl(int64_t w);

/* ── JS 执行 ────────────────────────────────────────────────────────── */
WEBUI_SL_API void         webui_run_sl(int64_t w, const char* js);
WEBUI_SL_API const char*  webui_script_sl(int64_t w, const char* js, int64_t timeout);

/* ── 服务器 / 文件 ──────────────────────────────────────────────────── */
WEBUI_SL_API int32_t      webui_set_root_folder_sl(int64_t w, const char* path);
WEBUI_SL_API const char*  webui_start_server_sl(int64_t w, const char* content);

/* ── 事件参数读取（回调内调用，e = webui_event_t*）──────────────────── */
WEBUI_SL_API int64_t      webui_get_count_sl(int64_t e);
WEBUI_SL_API int64_t      webui_get_int_at_sl(int64_t e, int64_t i);
WEBUI_SL_API double       webui_get_float_at_sl(int64_t e, int64_t i);
WEBUI_SL_API const char*  webui_get_string_at_sl(int64_t e, int64_t i);
WEBUI_SL_API int32_t      webui_get_bool_at_sl(int64_t e, int64_t i);

/* ── 事件返回值（回调内调用，回传 JS）───────────────────────────────── */
WEBUI_SL_API void webui_return_int_sl(int64_t e, int64_t n);
WEBUI_SL_API void webui_return_float_sl(int64_t e, double f);
WEBUI_SL_API void webui_return_string_sl(int64_t e, const char* s);
WEBUI_SL_API void webui_return_bool_sl(int64_t e, int32_t b);

#ifdef __cplusplus
}
#endif

#endif /* CVM_WEBUI_H */
