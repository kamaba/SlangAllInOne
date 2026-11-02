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

/* 应用 */
int64_t slqt_be_app_create(void);
void    slqt_be_app_set_style(const char* name);
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

#ifdef __cplusplus
}
#endif

#endif /* SLANG_QT_BACKEND_H */
