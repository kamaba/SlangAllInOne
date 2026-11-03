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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

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

/* 注销句柄（原生对象析构后调用）：used=0 使后续 resolve 返回 NULL，
 * 防悬垂指针与二次 delete（Qt 后端 object_delete/各类型化 delete 统一收口）。
 * Qt 后端的非 QObject 对象（QSqlQuery/QDomDocument 等）由后端侧的
 * 类型化析构器分发表负责，本层只管句柄生命周期标记。 */
void slqt_unregister(int64_t h)
{
    if (h < 0 || h >= (int64_t)g_reg_count) return;
    g_reg[(int)h].used = 0;
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
 * 2026-11-03 运行库自描述 / 可选 Qt 模块同位预装载（组合部署探测）。
 * 可选 Qt 模块在 vcxproj 一律 /DELAYLOAD：组合部署缺件时本 dll 装载不
 * 失败；预装载从自身目录（同位部署槽位）带 LOAD_WITH_ALTERED_SEARCH_PATH
 * 装载，其依赖也从同目录解析（无需 PATH），随后延迟加载桩按模块名命中
 * 已装载句柄。缺件静默跳过，slqt_module_available_sl 返回 0 供调用方
 * 优雅降级（未探测直接调用才会触发延迟加载异常）。
 * ======================================================================== */
#ifdef _WIN32

static int slqt_self_dir(char* out, size_t out_size)
{
    HMODULE self = NULL;
    char path[MAX_PATH];
    DWORD n;
    char* slash;
    if (!GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            (LPCSTR)&slqt_self_dir, &self)
        || self == NULL)
    {
        return 0;
    }
    n = GetModuleFileNameA(self, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;
    slash = strrchr(path, '\\');
    if (slash == NULL) return 0;
    *slash = '\0';
    if (strlen(path) + 1 > out_size) return 0;
    strcpy(out, path);
    return 1;
}

static char g_self_dir[MAX_PATH] = {0};
static int  g_self_dir_ok = -1;   /* -1 未探测 / 0 失败 / 1 成功 */

#endif /* _WIN32 */

/* 可选 Qt 模块 dll 清单（与 slang_qt_qt.vcxproj 的 DelayLoadDLLs 一致；
 * Debug 构建 SLQT_QT_DEBUG 对应 d 后缀调试运行库）。 */
static const char* const SLQT_OPTIONAL_DLLS[] =
{
#ifdef SLQT_QT_DEBUG
    "Qt6Networkd.dll", "Qt6Sqld.dll", "Qt6Svgd.dll", "Qt6SvgWidgetsd.dll",
    "Qt6OpenGLd.dll", "Qt6OpenGLWidgetsd.dll", "Qt6PrintSupportd.dll", "Qt6Xmld.dll",
    "Qt6Concurrentd.dll", "Qt6Testd.dll", "Qt6UiToolsd.dll", "Qt6Helpd.dll",
    "Qt6DBusd.dll", "Qt6Designerd.dll",
#else
    "Qt6Network.dll", "Qt6Sql.dll", "Qt6Svg.dll", "Qt6SvgWidgets.dll",
    "Qt6OpenGL.dll", "Qt6OpenGLWidgets.dll", "Qt6PrintSupport.dll", "Qt6Xml.dll",
    "Qt6Concurrent.dll", "Qt6Test.dll", "Qt6UiTools.dll", "Qt6Help.dll",
    "Qt6DBus.dll", "Qt6Designer.dll",
#endif
    NULL
};

static int g_preloaded = 0;

static void slqt_preload_optional(void)
{
#ifdef _WIN32
    int i;
    if (g_preloaded) return;
    g_preloaded = 1;
    if (g_self_dir_ok < 0)
    {
        g_self_dir_ok = slqt_self_dir(g_self_dir, sizeof(g_self_dir));
    }
    if (!g_self_dir_ok) return;
    for (i = 0; SLQT_OPTIONAL_DLLS[i] != NULL; i++)
    {
        char full[MAX_PATH + 64];
        if (snprintf(full, sizeof(full), "%s\\%s", g_self_dir, SLQT_OPTIONAL_DLLS[i])
            >= (int)sizeof(full))
        {
            continue;
        }
        /* 失败（组合未部署该模块）静默跳过 */
        LoadLibraryExA(full, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    }
#else
    g_preloaded = 1;
#endif
}

SLQT_API const char* slqt_runtime_dir_sl(void)
{
#ifdef _WIN32
    if (g_self_dir_ok < 0)
    {
        g_self_dir_ok = slqt_self_dir(g_self_dir, sizeof(g_self_dir));
    }
    return g_self_dir_ok ? g_self_dir : "";
#else
    return "";
#endif
}

SLQT_API int32_t slqt_module_available_sl(const char* dllName)
{
#ifdef _WIN32
    if (dllName == NULL || dllName[0] == '\0') return 0;
    slqt_preload_optional();
    return GetModuleHandleA(dllName) != NULL ? 1 : 0;
#else
    (void)dllName;
    return 0;
#endif
}

/* ========================================================================
 * 导出函数：全部转发到后端 slqt_be_*（sig 由 SLang 侧函数签名自动推导）。
 * ======================================================================== */

SLQT_API int64_t slqt_app_create_sl(void) { slqt_preload_optional(); return slqt_be_app_create(); }
SLQT_API void    slqt_app_set_stylesheet_sl(const char* c) { slqt_be_app_set_stylesheet(c); }
SLQT_API int32_t slqt_app_set_style_sl(const char* n) { return slqt_be_app_set_style(n); }
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

/* ==== 2026-11-03 扩展面转发（slang_qt.h 新增导出 → 后端 slqt_be_*）==== */

SLQT_API const char* slqt_backend_kind_sl(void) { return slqt_be_backend_kind(); }
SLQT_API const char* slqt_app_platform_name_sl(void) { return slqt_be_app_platform_name(); }
SLQT_API const char* slqt_app_library_paths_sl(void) { return slqt_be_app_library_paths(); }
SLQT_API const char* slqt_app_style_keys_sl(void) { return slqt_be_app_style_keys(); }

SLQT_API void    slqt_widget_move_sl(int64_t h, int32_t x, int32_t y) { slqt_be_widget_move(h, x, y); }
SLQT_API int64_t slqt_timer_create_sl(int32_t ms, int32_t single, int64_t cb, int64_t slot) { return slqt_be_timer_create(ms, single, cb, slot); }
SLQT_API void    slqt_timer_delete_sl(int64_t h) { slqt_be_timer_delete(h); }
SLQT_API void    slqt_timer_start_sl(int64_t h, int32_t ms) { slqt_be_timer_start(h, ms); }
SLQT_API void    slqt_timer_stop_sl(int64_t h) { slqt_be_timer_stop(h); }
SLQT_API int32_t slqt_timer_active_sl(int64_t h) { return slqt_be_timer_active(h); }

SLQT_API int64_t     slqt_net_create_sl(void) { return slqt_be_net_create(); }
SLQT_API void        slqt_net_delete_sl(int64_t h) { slqt_be_net_delete(h); }
SLQT_API int32_t     slqt_net_is_online_sl(void) { return slqt_be_net_is_online(); }
SLQT_API const char* slqt_net_backend_name_sl(void) { return slqt_be_net_backend_name(); }
SLQT_API int64_t     slqt_net_get_sl(int64_t h, const char* url) { return slqt_be_net_get(h, url); }
SLQT_API void        slqt_net_reply_delete_sl(int64_t h) { slqt_be_net_reply_delete(h); }
SLQT_API int32_t     slqt_net_reply_wait_sl(int64_t h, int32_t ms) { return slqt_be_net_reply_wait(h, ms); }
SLQT_API int32_t     slqt_net_reply_status_sl(int64_t h) { return slqt_be_net_reply_status(h); }
SLQT_API const char* slqt_net_reply_error_sl(int64_t h) { return slqt_be_net_reply_error(h); }
SLQT_API const char* slqt_net_reply_body_sl(int64_t h) { return slqt_be_net_reply_body(h); }

SLQT_API const char* slqt_sql_drivers_sl(void) { return slqt_be_sql_drivers(); }
SLQT_API int64_t     slqt_sql_add_database_sl(const char* type) { return slqt_be_sql_add_database(type); }
SLQT_API void        slqt_sql_delete_sl(int64_t h) { slqt_be_sql_delete(h); }
SLQT_API void        slqt_sql_set_database_name_sl(int64_t h, const char* name) { slqt_be_sql_set_database_name(h, name); }
SLQT_API int32_t     slqt_sql_open_sl(int64_t h) { return slqt_be_sql_open(h); }
SLQT_API void        slqt_sql_close_sl(int64_t h) { slqt_be_sql_close(h); }
SLQT_API const char* slqt_sql_last_error_sl(int64_t h) { return slqt_be_sql_last_error(h); }
SLQT_API int64_t     slqt_sql_query_create_sl(int64_t db) { return slqt_be_sql_query_create(db); }
SLQT_API void        slqt_sql_query_delete_sl(int64_t h) { slqt_be_sql_query_delete(h); }
SLQT_API int32_t     slqt_sql_query_exec_sl(int64_t h, const char* sql) { return slqt_be_sql_query_exec(h, sql); }
SLQT_API int32_t     slqt_sql_query_next_sl(int64_t h) { return slqt_be_sql_query_next(h); }
SLQT_API const char* slqt_sql_query_value_text_sl(int64_t h, int32_t i) { return slqt_be_sql_query_value_text(h, i); }
SLQT_API int64_t     slqt_sql_query_value_int_sl(int64_t h, int32_t i) { return slqt_be_sql_query_value_int(h, i); }

SLQT_API int64_t slqt_svgwidget_create_sl(int64_t p) { return slqt_be_svgwidget_create(p); }
SLQT_API int32_t slqt_svgwidget_load_file_sl(int64_t h, const char* path) { return slqt_be_svgwidget_load_file(h, path); }
SLQT_API int32_t slqt_svgwidget_load_data_sl(int64_t h, const char* xml) { return slqt_be_svgwidget_load_data(h, xml); }
SLQT_API int64_t slqt_svg_renderer_create_sl(const char* xml) { return slqt_be_svg_renderer_create(xml); }
SLQT_API void    slqt_svg_renderer_delete_sl(int64_t h) { slqt_be_svg_renderer_delete(h); }
SLQT_API int32_t slqt_svg_renderer_valid_sl(int64_t h) { return slqt_be_svg_renderer_valid(h); }
SLQT_API int32_t slqt_svg_renderer_check_size_sl(int64_t h, int32_t w, int32_t hh) { return slqt_be_svg_renderer_check_size(h, w, hh); }
SLQT_API int32_t slqt_svg_render_to_label_sl(int64_t r, int64_t l, int32_t w, int32_t hh) { return slqt_be_svg_render_to_label(r, l, w, hh); }

SLQT_API const char* slqt_image_formats_sl(void) { return slqt_be_image_formats(); }
SLQT_API int32_t     slqt_image_save_solid_sl(const char* path, const char* fmt, int32_t r, int32_t g, int32_t b) { return slqt_be_image_save_solid(path, fmt, r, g, b); }
SLQT_API int32_t     slqt_image_check_size_sl(const char* path, int32_t w, int32_t hh) { return slqt_be_image_check_size(path, w, hh); }
SLQT_API int32_t     slqt_icon_render_sl(const char* path, int32_t size) { return slqt_be_icon_render(path, size); }

SLQT_API int64_t slqt_glwidget_create_sl(int64_t p) { return slqt_be_glwidget_create(p); }
SLQT_API void    slqt_glwidget_set_color_sl(int64_t h, int32_t r, int32_t g, int32_t b) { slqt_be_glwidget_set_color(h, r, g, b); }
SLQT_API void    slqt_glwidget_set_spinning_sl(int64_t h, int32_t on) { slqt_be_glwidget_set_spinning(h, on); }
SLQT_API int64_t slqt_glwidget_frame_count_sl(int64_t h) { return slqt_be_glwidget_frame_count(h); }

SLQT_API int64_t     slqt_printer_create_sl(void) { return slqt_be_printer_create(); }
SLQT_API void        slqt_printer_delete_sl(int64_t h) { slqt_be_printer_delete(h); }
SLQT_API void        slqt_printer_set_output_filename_sl(int64_t h, const char* path) { slqt_be_printer_set_output_filename(h, path); }
SLQT_API void        slqt_printer_set_page_size_a4_sl(int64_t h) { slqt_be_printer_set_page_size_a4(h); }
SLQT_API int32_t     slqt_printer_print_text_sl(int64_t h, const char* title, const char* body) { return slqt_be_printer_print_text(h, title, body); }
SLQT_API const char* slqt_printer_output_file_sl(int64_t h) { return slqt_be_printer_output_file(h); }

SLQT_API int64_t     slqt_dom_create_sl(void) { return slqt_be_dom_create(); }
SLQT_API void        slqt_dom_delete_sl(int64_t h) { slqt_be_dom_delete(h); }
SLQT_API int32_t     slqt_dom_set_content_sl(int64_t h, const char* xml) { return slqt_be_dom_set_content(h, xml); }
SLQT_API const char* slqt_dom_root_tag_sl(int64_t h) { return slqt_be_dom_root_tag(h); }
SLQT_API int64_t     slqt_dom_count_by_tag_sl(int64_t h, const char* tag) { return slqt_be_dom_count_by_tag(h, tag); }
SLQT_API const char* slqt_dom_first_text_sl(int64_t h, const char* tag) { return slqt_be_dom_first_text(h, tag); }
SLQT_API const char* slqt_dom_to_string_sl(int64_t h) { return slqt_be_dom_to_string(h); }

SLQT_API int64_t slqt_concurrent_task_create_sl(int32_t kind, int64_t n) { return slqt_be_concurrent_task_create(kind, n); }
SLQT_API void    slqt_concurrent_task_delete_sl(int64_t h) { slqt_be_concurrent_task_delete(h); }
SLQT_API int32_t slqt_concurrent_task_is_finished_sl(int64_t h) { return slqt_be_concurrent_task_is_finished(h); }
SLQT_API int64_t slqt_concurrent_task_result_sl(int64_t h) { return slqt_be_concurrent_task_result(h); }
SLQT_API int32_t slqt_thread_pool_max_sl(void) { return slqt_be_thread_pool_max(); }

SLQT_API void        slqt_test_qsleep_sl(int32_t ms) { slqt_be_test_qsleep(ms); }
SLQT_API void        slqt_test_qwait_sl(int32_t ms) { slqt_be_test_qwait(ms); }
SLQT_API const char* slqt_test_version_sl(void) { return slqt_be_test_version(); }

SLQT_API int64_t     slqt_uiloader_create_sl(void) { return slqt_be_uiloader_create(); }
SLQT_API void        slqt_uiloader_delete_sl(int64_t h) { slqt_be_uiloader_delete(h); }
SLQT_API int64_t     slqt_uiloader_load_file_sl(int64_t h, const char* path, int64_t p) { return slqt_be_uiloader_load_file(h, path, p); }
SLQT_API const char* slqt_uiloader_available_widgets_sl(int64_t h) { return slqt_be_uiloader_available_widgets(h); }
SLQT_API int64_t     slqt_designer_formbuilder_create_sl(void) { return slqt_be_designer_formbuilder_create(); }
SLQT_API void        slqt_designer_formbuilder_delete_sl(int64_t h) { slqt_be_designer_formbuilder_delete(h); }
SLQT_API int64_t     slqt_designer_formbuilder_load_sl(int64_t h, const char* path, int64_t p) { return slqt_be_designer_formbuilder_load(h, path, p); }

SLQT_API int64_t     slqt_help_engine_create_sl(const char* collection) { return slqt_be_help_engine_create(collection); }
SLQT_API void        slqt_help_engine_delete_sl(int64_t h) { slqt_be_help_engine_delete(h); }
SLQT_API int32_t     slqt_help_setup_data_sl(int64_t h) { return slqt_be_help_setup_data(h); }
SLQT_API const char* slqt_help_error_sl(int64_t h) { return slqt_be_help_error(h); }

SLQT_API int32_t     slqt_dbus_connected_sl(void) { return slqt_be_dbus_connected(); }
SLQT_API const char* slqt_dbus_base_service_sl(void) { return slqt_be_dbus_base_service(); }
