/*
 * slang_qt.c —— SLang QT 模块原生绑定层（产物 slang_qt.dll 的共用核心）
 * ==========================================================================
 * 与 cvm_webui_lib/cvm_webui.c 同思路：维护句柄注册表（Int64 句柄 <-> 真实
 * 对象指针）与信号绑定表，并把全部 slqt_*_sl 导出函数转发到后端实现
 * slqt_be_*（stub 或 Qt）。回调桥与 trampoline 在后端（Qt）内完成；stub
 * 不发射事件，仅记录绑定并返回 bind_id 供 headless 验证。
 *
 * 本文件为纯 C（不拉 Qt 头），可独立编译；后端实现由链接的
 * slang_qt_stub.c 或 slang_qt_qt.cpp 提供。
 */

#include "slang_qt.h"
#include "slang_qt_backend.h"

#include <stdlib.h>
#include <string.h>

/* ========================================================================
 * 句柄注册表：Int64 句柄 = 注册表插入下标（0 基）。删除仅标记 used=0。
 * ======================================================================== */
typedef struct _SLQTRegEntry { void* obj; int used; } SLQTRegEntry;

#define SLQT_REG_INIT 1024
static SLQTRegEntry* g_reg = NULL;
static int          g_reg_count = 0;
static int          g_reg_cap = 0;

int64_t slqt_register(void* obj)
{
    if (g_reg == NULL)
    {
        g_reg_cap = SLQT_REG_INIT;
        g_reg = (SLQTRegEntry*)calloc((size_t)g_reg_cap, sizeof(SLQTRegEntry));
        if (g_reg == NULL) return 0;
    }
    if (g_reg_count >= g_reg_cap)
    {
        int ncap = g_reg_cap * 2;
        SLQTRegEntry* nr = (SLQTRegEntry*)realloc(g_reg, (size_t)ncap * sizeof(SLQTRegEntry));
        if (nr == NULL) return 0;
        g_reg = nr;
        g_reg_cap = ncap;
    }
    int64_t h = (int64_t)g_reg_count;   /* 句柄 = 插入下标 */
    g_reg[g_reg_count].obj = obj;
    g_reg[g_reg_count].used = 1;
    g_reg_count++;
    return h;
}

void* slqt_resolve(int64_t h)
{
    if (h < 0 || h >= (int64_t)g_reg_count) return NULL;
    if (!g_reg[(int)h].used) return NULL;
    return g_reg[(int)h].obj;
}

/* ========================================================================
 * 信号绑定表：bind_id（1 基）用于 SL 侧校验；Qt 后端用 lambda 捕获
 * (dispatchCb, slot)，无需查表。stub 后端不发射，仅依赖此表返回 bind_id。
 * ======================================================================== */
typedef struct _SLQTBind
{
    int64_t h;
    int32_t signalId;
    int64_t dispatchCb;
    int64_t slot;
    int     used;
} SLQTBind;

#define SLQT_BIND_INIT 256
static SLQTBind* g_binds = NULL;
static int       g_bind_count = 0;
static int       g_bind_cap = 0;

static int slqt_add_binding(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot)
{
    if (g_binds == NULL)
    {
        g_bind_cap = SLQT_BIND_INIT;
        g_binds = (SLQTBind*)calloc((size_t)g_bind_cap, sizeof(SLQTBind));
        if (g_binds == NULL) return 0;
    }
    if (g_bind_count >= g_bind_cap)
    {
        int ncap = g_bind_cap * 2;
        SLQTBind* nb = (SLQTBind*)realloc(g_binds, (size_t)ncap * sizeof(SLQTBind));
        if (nb == NULL) return 0;
        g_binds = nb;
        g_bind_cap = ncap;
    }
    g_binds[g_bind_count].h = h;
    g_binds[g_bind_count].signalId = signalId;
    g_binds[g_bind_count].dispatchCb = dispatchCb;
    g_binds[g_bind_count].slot = slot;
    g_binds[g_bind_count].used = 1;
    g_bind_count++;
    return g_bind_count;   /* bind_id = 1 基 */
}

/* ========================================================================
 * 信号连接（绑定层）：记录绑定 + 转发后端真正连接。
 * dispatchCb == 0（createCallback 失败，如方法查找 miss）时拒绝连接并
 * 返回 0——放行会让 Qt 后端挂一个 null-call 桩，信号一发射即 0xC0000005
 * 崩溃（QTTest 发布版实录 2026-11-02）；拒绝后 SL 侧 bind=0 可见可诊断。
 * ======================================================================== */
SLQT_API int64_t slqt_connect_sl(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot)
{
    int bind_id;
    if (dispatchCb == 0)
    {
        return 0;
    }
    bind_id = slqt_add_binding(h, signalId, dispatchCb, slot);
    if (bind_id == 0) return 0;
    slqt_be_connect(h, signalId, dispatchCb, slot);
    return (int64_t)bind_id;
}

/* ========================================================================
 * 导出函数：全部转发到后端 slqt_be_*（sig 由 SLang 侧函数签名自动推导）。
 * ======================================================================== */

SLQT_API int64_t slqt_app_create_sl(void) { return slqt_be_app_create(); }
SLQT_API void    slqt_app_set_style_sl(const char* n) { slqt_be_app_set_style(n); }
SLQT_API void    slqt_app_set_stylesheet_sl(const char* c) { slqt_be_app_set_stylesheet(c); }
SLQT_API void    slqt_app_exec_sl(void) { slqt_be_app_exec(); }
SLQT_API void    slqt_app_process_events_sl(void) { slqt_be_app_process_events(); }
SLQT_API void    slqt_app_quit_sl(void) { slqt_be_app_quit(); }
SLQT_API int32_t slqt_app_argc_sl(void) { return slqt_be_app_argc(); }

SLQT_API int64_t slqt_object_delete_sl(int64_t h) { slqt_be_object_delete(h); return h; }
SLQT_API int32_t slqt_object_is_valid_sl(int64_t h) { return slqt_be_object_is_valid(h); }
SLQT_API int64_t slqt_widget_create_sl(int64_t p) { return slqt_be_widget_create(p); }
SLQT_API void    slqt_widget_set_parent_sl(int64_t h, int64_t p) { slqt_be_widget_set_parent(h, p); }
SLQT_API void    slqt_widget_set_text_sl(int64_t h, const char* t) { slqt_be_widget_set_text(h, t); }
SLQT_API const char* slqt_widget_text_sl(int64_t h) { return slqt_be_widget_text(h); }
SLQT_API void    slqt_widget_set_geometry_sl(int64_t h, int32_t x, int32_t y, int32_t w, int32_t hh) { slqt_be_widget_set_geometry(h, x, y, w, hh); }
SLQT_API void    slqt_widget_resize_sl(int64_t h, int32_t w, int32_t hh) { slqt_be_widget_resize(h, w, hh); }
SLQT_API void    slqt_widget_show_sl(int64_t h) { slqt_be_widget_show(h); }
SLQT_API void    slqt_widget_hide_sl(int64_t h) { slqt_be_widget_hide(h); }
SLQT_API void    slqt_widget_set_enabled_sl(int64_t h, int32_t on) { slqt_be_widget_set_enabled(h, on); }
SLQT_API void    slqt_widget_set_visible_sl(int64_t h, int32_t on) { slqt_be_widget_set_visible(h, on); }
SLQT_API void    slqt_widget_set_tooltip_sl(int64_t h, const char* t) { slqt_be_widget_set_tooltip(h, t); }
SLQT_API void    slqt_widget_set_style_sheet_sl(int64_t h, const char* c) { slqt_be_widget_set_style_sheet(h, c); }
SLQT_API void    slqt_widget_set_fixed_size_sl(int64_t h, int32_t w, int32_t hh) { slqt_be_widget_set_fixed_size(h, w, hh); }
SLQT_API void    slqt_widget_update_sl(int64_t h) { slqt_be_widget_update(h); }

SLQT_API int64_t slqt_button_create_sl(int64_t p) { return slqt_be_button_create(p); }
SLQT_API int64_t slqt_label_create_sl(int64_t p) { return slqt_be_label_create(p); }
SLQT_API int32_t slqt_label_set_pixmap_sl(int64_t h, int64_t ptr, int32_t len) { return slqt_be_label_set_pixmap(h, ptr, len); }
SLQT_API int64_t slqt_edit_create_sl(int64_t p) { return slqt_be_edit_create(p); }
SLQT_API void    slqt_edit_set_placeholder_sl(int64_t h, const char* t) { slqt_be_edit_set_placeholder(h, t); }
SLQT_API const char* slqt_edit_text_sl(int64_t h) { return slqt_be_edit_text(h); }
SLQT_API void    slqt_edit_set_readonly_sl(int64_t h, int32_t on) { slqt_be_edit_set_readonly(h, on); }

SLQT_API int64_t slqt_mainwindow_create_sl(void) { return slqt_be_mainwindow_create(); }
SLQT_API void    slqt_mainwindow_set_central_sl(int64_t h, int64_t w) { slqt_be_mainwindow_set_central(h, w); }
SLQT_API void    slqt_mainwindow_set_title_sl(int64_t h, const char* t) { slqt_be_mainwindow_set_title(h, t); }
SLQT_API void    slqt_mainwindow_resize_sl(int64_t h, int32_t w, int32_t hh) { slqt_be_mainwindow_resize(h, w, hh); }
SLQT_API void    slqt_mainwindow_show_sl(int64_t h) { slqt_be_mainwindow_show(h); }
SLQT_API int32_t slqt_messagebox_info_sl(int64_t p, const char* t, const char* x) { return slqt_be_messagebox_info(p, t, x); }
SLQT_API int32_t slqt_messagebox_question_sl(int64_t p, const char* t, const char* x) { return slqt_be_messagebox_question(p, t, x); }

SLQT_API int64_t slqt_vbox_create_sl(int64_t p) { return slqt_be_vbox_create(p); }
SLQT_API int64_t slqt_hbox_create_sl(int64_t p) { return slqt_be_hbox_create(p); }
SLQT_API int64_t slqt_grid_create_sl(int64_t p) { return slqt_be_grid_create(p); }
SLQT_API void    slqt_layout_add_widget_sl(int64_t l, int64_t w) { slqt_be_layout_add_widget(l, w); }
SLQT_API void    slqt_layout_add_spacing_sl(int64_t l, int32_t px) { slqt_be_layout_add_spacing(l, px); }
SLQT_API void    slqt_layout_add_stretch_sl(int64_t l, int32_t s) { slqt_be_layout_add_stretch(l, s); }
SLQT_API void    slqt_layout_set_contents_margins_sl(int64_t l, int32_t a, int32_t b, int32_t c, int32_t d) { slqt_be_layout_set_contents_margins(l, a, b, c, d); }
SLQT_API void    slqt_layout_set_spacing_sl(int64_t l, int32_t px) { slqt_be_layout_set_spacing(l, px); }
SLQT_API void    slqt_layout_set_widget_at_sl(int64_t g, int64_t w, int32_t r, int32_t c, int32_t rs, int32_t cs) { slqt_be_layout_set_widget_at(g, w, r, c, rs, cs); }
SLQT_API void    slqt_widget_set_layout_sl(int64_t w, int64_t l) { slqt_be_widget_set_layout(w, l); }
