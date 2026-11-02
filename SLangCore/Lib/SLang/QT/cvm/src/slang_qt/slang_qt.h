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
SLQT_API void    slqt_app_set_style_sl(const char* name);
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
SLQT_API int64_t slqt_edit_create_sl(int64_t parent);
SLQT_API void    slqt_edit_set_placeholder_sl(int64_t h, const char* t);
SLQT_API const char* slqt_edit_text_sl(int64_t h);
SLQT_API void    slqt_edit_set_readonly_sl(int64_t h, int32_t on);

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
#define SLQT_SIG_DESTROYED      3
#define SLQT_SIG_TEXT_CHANGED   4

#ifdef __cplusplus
}
#endif

#endif /* SLANG_QT_H */
