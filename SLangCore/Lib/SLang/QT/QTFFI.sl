import Core;
import Std;

# ============================================================================
# QTFFI.sl —— SLang QT 模块原生绑定面 + 门面（模块名 SLangQT）
# ----------------------------------------------------------------------------
# 对照 SLang/WebUI/WebUI.sl（FFI 驱动、@DllStaticImport 2 参、handler 表 +
# 单 dispatch trampoline 重入 VM）。所有原生绑定集中在 QT 类（单一绑定面），
# 其余 core/layout 封装类只调本类的 ffi_* / connect / 工厂方法。
#
# 用法：
#   import SLangQT;
#   SLang.QApplication app = SLang.QT.newApp()
#   SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
#   btn.clicked( onClick )          # onClick 为 static void onClick()
#   app.exec()
# ============================================================================

namespace SLang
{
    public class QT
    {
        # ── 信号 id（与 cvm_qt_lib/slang_qt.h 的 SLQT_SIG_* 逐值一致）──
        public static Int32 SIG_CLICKED        = 0
        public static Int32 SIG_RETURN_PRESSED = 1
        public static Int32 SIG_TRIGGERED      = 2
        public static Int32 SIG_DESTROYED      = 3
        public static Int32 SIG_TEXT_CHANGED   = 4
        public static Int32 SIG_CURRENT_ROW_CHANGED = 5

        # ── 应用 ────────────────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_app_create_sl" )
        public static Int64 ffi_appCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_app_set_style_sl" )
        public static bool ffi_appSetStyle( string name ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_app_set_stylesheet_sl" )
        public static void ffi_appSetStyleSheet( string css ) {}
        @DllStaticImport( "slang_qt", "slqt_app_exec_sl" )
        public static void ffi_appExec() {}
        @DllStaticImport( "slang_qt", "slqt_app_process_events_sl" )
        public static void ffi_appProcessEvents() {}
        @DllStaticImport( "slang_qt", "slqt_app_quit_sl" )
        public static void ffi_appQuit() {}
        @DllStaticImport( "slang_qt", "slqt_app_argc_sl" )
        public static Int32 ffi_appArgc() { ret 0 }

        # ── 对象 / 控件 ────────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_object_delete_sl" )
        public static Int64 ffi_objectDelete( Int64 h ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_object_is_valid_sl" )
        public static bool ffi_objectIsValid( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_widget_create_sl" )
        public static Int64 ffi_widgetCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_widget_set_parent_sl" )
        public static void ffi_widgetSetParent( Int64 h, Int64 parent ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_text_sl" )
        public static void ffi_widgetSetText( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_text_sl" )
        public static string ffi_widgetText( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_widget_set_geometry_sl" )
        public static void ffi_widgetSetGeometry( Int64 h, int x, int y, int w, int hh ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_resize_sl" )
        public static void ffi_widgetResize( Int64 h, int w, int hh ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_show_sl" )
        public static void ffi_widgetShow( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_hide_sl" )
        public static void ffi_widgetHide( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_enabled_sl" )
        public static void ffi_widgetSetEnabled( Int64 h, bool on ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_visible_sl" )
        public static void ffi_widgetSetVisible( Int64 h, bool on ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_tooltip_sl" )
        public static void ffi_widgetSetTooltip( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_style_sheet_sl" )
        public static void ffi_widgetSetStyleSheet( Int64 h, string css ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_fixed_size_sl" )
        public static void ffi_widgetSetFixedSize( Int64 h, int w, int hh ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_update_sl" )
        public static void ffi_widgetUpdate( Int64 h ) {}

        # ── 按钮 / 标签 / 输入 ──────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_button_create_sl" )
        public static Int64 ffi_buttonCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_label_create_sl" )
        public static Int64 ffi_labelCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_label_set_pixmap_sl" )
        public static Int32 ffi_labelSetPixmap( Int64 h, Int64 ptr, int len ) { ret 0 }
        # SLangRender renderTexture 通道：ptr = RGBA8 top-down 像素块（w*hh*4），
        # 布局与 GL glReadPixels 回读 / QImage Format_RGBA8888 一致（含 ptr 手写 sig）。
        @DllStaticImport( "slang_qt", "slqt_label_set_pixmap_rgba_sl", "i64,ptr,i32,i32->bool" )
        public static bool ffi_labelSetPixmapRgba( Int64 h, Int64 ptr, int w, int hh ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_edit_create_sl" )
        public static Int64 ffi_editCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_edit_set_placeholder_sl" )
        public static void ffi_editSetPlaceholder( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_edit_text_sl" )
        public static string ffi_editText( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_edit_set_readonly_sl" )
        public static void ffi_editSetReadonly( Int64 h, bool on ) {}

        # ── 多行文本编辑 / 列表（QTextEdit / QListWidget）────────────
        @DllStaticImport( "slang_qt", "slqt_textedit_create_sl" )
        public static Int64 ffi_texteditCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_textedit_set_text_sl" )
        public static void ffi_texteditSetText( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_textedit_text_sl" )
        public static string ffi_texteditText( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_textedit_set_readonly_sl" )
        public static void ffi_texteditSetReadonly( Int64 h, bool on ) {}
        @DllStaticImport( "slang_qt", "slqt_textedit_append_sl" )
        public static void ffi_texteditAppend( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_list_create_sl" )
        public static Int64 ffi_listCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_list_add_item_sl" )
        public static void ffi_listAddItem( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_list_clear_sl" )
        public static void ffi_listClear( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_list_count_sl" )
        public static Int32 ffi_listCount( Int64 h ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_list_current_row_sl" )
        public static Int32 ffi_listCurrentRow( Int64 h ) { ret -1 }
        @DllStaticImport( "slang_qt", "slqt_list_set_current_row_sl" )
        public static void ffi_listSetCurrentRow( Int64 h, Int32 row ) {}
        @DllStaticImport( "slang_qt", "slqt_list_item_text_sl" )
        public static string ffi_listItemText( Int64 h, Int32 row ) { ret "" }

        # ── 主窗口 / 对话框 ────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_mainwindow_create_sl" )
        public static Int64 ffi_mainwindowCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mainwindow_set_central_sl" )
        public static void ffi_mainwindowSetCentral( Int64 h, Int64 w ) {}
        @DllStaticImport( "slang_qt", "slqt_mainwindow_set_title_sl" )
        public static void ffi_mainwindowSetTitle( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_mainwindow_resize_sl" )
        public static void ffi_mainwindowResize( Int64 h, int w, int hh ) {}
        @DllStaticImport( "slang_qt", "slqt_mainwindow_show_sl" )
        public static void ffi_mainwindowShow( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_messagebox_info_sl" )
        public static Int32 ffi_messageboxInfo( Int64 p, string t, string x ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_messagebox_question_sl" )
        public static Int32 ffi_messageboxQuestion( Int64 p, string t, string x ) { ret 0 }

        # ── 布局 ──────────────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_vbox_create_sl" )
        public static Int64 ffi_vboxCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_hbox_create_sl" )
        public static Int64 ffi_hboxCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_grid_create_sl" )
        public static Int64 ffi_gridCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_layout_add_widget_sl" )
        public static void ffi_layoutAddWidget( Int64 l, Int64 w ) {}
        @DllStaticImport( "slang_qt", "slqt_layout_add_spacing_sl" )
        public static void ffi_layoutAddSpacing( Int64 l, int px ) {}
        @DllStaticImport( "slang_qt", "slqt_layout_add_stretch_sl" )
        public static void ffi_layoutAddStretch( Int64 l, int s ) {}
        @DllStaticImport( "slang_qt", "slqt_layout_set_contents_margins_sl" )
        public static void ffi_layoutSetContentsMargins( Int64 l, int a, int b, int c, int d ) {}
        @DllStaticImport( "slang_qt", "slqt_layout_set_spacing_sl" )
        public static void ffi_layoutSetSpacing( Int64 l, int px ) {}
        @DllStaticImport( "slang_qt", "slqt_layout_set_widget_at_sl" )
        public static void ffi_layoutSetWidgetAt( Int64 g, Int64 w, int r, int c, int rs, int cs ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_layout_sl" )
        public static void ffi_widgetSetLayout( Int64 w, Int64 l ) {}

        # ── 信号连接（绑定层）────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_connect_sl" )
        public static Int64 ffi_connect( Int64 h, Int32 signalId, Int64 cb, Int64 slot ) { ret 0 }

        # ════════════════════════════════════════════════════════════════
        # 2026-11-03 扩展面：运行时探测 / QTimer / Network / Sql / Svg /
        # GL / Print / Xml / Concurrent / Test / UiTools / Help / DBus /
        # Designer / 图像图标。可选模块组合部署（jsonc qtRuntime），缺件时
        # moduleAvailable 探测失败、调用方跳过（不触碰未装载模块的导出）。
        # ════════════════════════════════════════════════════════════════

        # ── 运行时自描述 / 探测 ────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_backend_kind_sl" )
        public static string ffi_backendKind() { ret "stub" }
        @DllStaticImport( "slang_qt", "slqt_runtime_dir_sl" )
        public static string ffi_runtimeDir() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_module_available_sl" )
        public static bool ffi_moduleAvailable( string dllName ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_app_platform_name_sl" )
        public static string ffi_appPlatformName() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_app_library_paths_sl" )
        public static string ffi_appLibraryPaths() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_app_style_keys_sl" )
        public static string ffi_appStyleKeys() { ret "" }

        # ── 控件移动 + QTimer ──────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_widget_move_sl" )
        public static void ffi_widgetMove( Int64 h, int x, int y ) {}
        @DllStaticImport( "slang_qt", "slqt_timer_create_sl" )
        public static Int64 ffi_timerCreate( int ms, bool single, Int64 cb, Int64 slot ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_timer_delete_sl" )
        public static void ffi_timerDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_timer_start_sl" )
        public static void ffi_timerStart( Int64 h, int ms ) {}
        @DllStaticImport( "slang_qt", "slqt_timer_stop_sl" )
        public static void ffi_timerStop( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_timer_active_sl" )
        public static bool ffi_timerActive( Int64 h ) { ret false }

        # ── Network（Qt6Network）───────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_net_create_sl" )
        public static Int64 ffi_netCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_net_delete_sl" )
        public static void ffi_netDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_net_is_online_sl" )
        public static int ffi_netIsOnline() { ret -1 }
        @DllStaticImport( "slang_qt", "slqt_net_backend_name_sl" )
        public static string ffi_netBackendName() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_net_get_sl" )
        public static Int64 ffi_netGet( Int64 h, string url ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_net_reply_delete_sl" )
        public static void ffi_netReplyDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_net_reply_wait_sl" )
        public static bool ffi_netReplyWait( Int64 h, int ms ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_net_reply_status_sl" )
        public static int ffi_netReplyStatus( Int64 h ) { ret -1 }
        @DllStaticImport( "slang_qt", "slqt_net_reply_error_sl" )
        public static string ffi_netReplyError( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_net_reply_body_sl" )
        public static string ffi_netReplyBody( Int64 h ) { ret "" }

        # ── Sql（Qt6Sql）───────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_sql_drivers_sl" )
        public static string ffi_sqlDrivers() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_sql_add_database_sl" )
        public static Int64 ffi_sqlAddDatabase( string type ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_sql_delete_sl" )
        public static void ffi_sqlDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_sql_set_database_name_sl" )
        public static void ffi_sqlSetDatabaseName( Int64 h, string name ) {}
        @DllStaticImport( "slang_qt", "slqt_sql_open_sl" )
        public static bool ffi_sqlOpen( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_sql_close_sl" )
        public static void ffi_sqlClose( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_sql_last_error_sl" )
        public static string ffi_sqlLastError( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_sql_query_create_sl" )
        public static Int64 ffi_sqlQueryCreate( Int64 db ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_sql_query_delete_sl" )
        public static void ffi_sqlQueryDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_sql_query_exec_sl" )
        public static bool ffi_sqlQueryExec( Int64 h, string sql ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_sql_query_next_sl" )
        public static bool ffi_sqlQueryNext( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_sql_query_value_text_sl" )
        public static string ffi_sqlQueryValueText( Int64 h, int i ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_sql_query_value_int_sl" )
        public static Int64 ffi_sqlQueryValueInt( Int64 h, int i ) { ret 0 }

        # ── Svg（Qt6Svg / Qt6SvgWidgets）───────────────────────────
        @DllStaticImport( "slang_qt", "slqt_svgwidget_create_sl" )
        public static Int64 ffi_svgWidgetCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_svgwidget_load_file_sl" )
        public static bool ffi_svgWidgetLoadFile( Int64 h, string path ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_svgwidget_load_data_sl" )
        public static bool ffi_svgWidgetLoadData( Int64 h, string xml ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_svg_renderer_create_sl" )
        public static Int64 ffi_svgRendererCreate( string xml ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_svg_renderer_delete_sl" )
        public static void ffi_svgRendererDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_svg_renderer_valid_sl" )
        public static bool ffi_svgRendererValid( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_svg_renderer_check_size_sl" )
        public static bool ffi_svgRendererCheckSize( Int64 h, int w, int hh ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_svg_render_to_label_sl" )
        public static bool ffi_svgRenderToLabel( Int64 r, Int64 l, int w, int hh ) { ret false }

        # ── 图像 / 图标（Qt6Gui 插件探测）─────────────────────────
        @DllStaticImport( "slang_qt", "slqt_image_formats_sl" )
        public static string ffi_imageFormats() { ret "" }
        @DllStaticImport( "slang_qt", "slqt_image_save_solid_sl" )
        public static bool ffi_imageSaveSolid( string path, string fmt, int r, int g, int b ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_image_check_size_sl" )
        public static bool ffi_imageCheckSize( string path, int w, int hh ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_icon_render_sl" )
        public static bool ffi_iconRender( string path, int size ) { ret false }

        # ── OpenGL（Qt6OpenGLWidgets）──────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_glwidget_create_sl" )
        public static Int64 ffi_glWidgetCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_glwidget_set_color_sl" )
        public static void ffi_glWidgetSetColor( Int64 h, int r, int g, int b ) {}
        @DllStaticImport( "slang_qt", "slqt_glwidget_set_spinning_sl" )
        public static void ffi_glWidgetSetSpinning( Int64 h, bool on ) {}
        @DllStaticImport( "slang_qt", "slqt_glwidget_frame_count_sl" )
        public static Int64 ffi_glWidgetFrameCount( Int64 h ) { ret 0 }

        # ── Print（Qt6PrintSupport）────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_printer_create_sl" )
        public static Int64 ffi_printerCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_printer_delete_sl" )
        public static void ffi_printerDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_printer_set_output_filename_sl" )
        public static void ffi_printerSetOutputFilename( Int64 h, string path ) {}
        @DllStaticImport( "slang_qt", "slqt_printer_set_page_size_a4_sl" )
        public static void ffi_printerSetPageSizeA4( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_printer_print_text_sl" )
        public static bool ffi_printerPrintText( Int64 h, string title, string body ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_printer_output_file_sl" )
        public static string ffi_printerOutputFile( Int64 h ) { ret "" }

        # ── Xml（Qt6Xml）───────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_dom_create_sl" )
        public static Int64 ffi_domCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_dom_delete_sl" )
        public static void ffi_domDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_dom_set_content_sl" )
        public static bool ffi_domSetContent( Int64 h, string xml ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_dom_root_tag_sl" )
        public static string ffi_domRootTag( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_dom_count_by_tag_sl" )
        public static Int64 ffi_domCountByTag( Int64 h, string tag ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_dom_first_text_sl" )
        public static string ffi_domFirstText( Int64 h, string tag ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_dom_to_string_sl" )
        public static string ffi_domToString( Int64 h ) { ret "" }

        # ── Concurrent（Qt6Concurrent）─────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_concurrent_task_create_sl" )
        public static Int64 ffi_concurrentTaskCreate( int kind, Int64 n ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_concurrent_task_delete_sl" )
        public static void ffi_concurrentTaskDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_concurrent_task_is_finished_sl" )
        public static bool ffi_concurrentTaskIsFinished( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_concurrent_task_result_sl" )
        public static Int64 ffi_concurrentTaskResult( Int64 h ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_thread_pool_max_sl" )
        public static int ffi_threadPoolMax() { ret 0 }

        # ── Test（Qt6Test）─────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_test_qsleep_sl" )
        public static void ffi_testQSleep( int ms ) {}
        @DllStaticImport( "slang_qt", "slqt_test_qwait_sl" )
        public static void ffi_testQWait( int ms ) {}
        # 探针：手写 sig（第 3 参）对照自动推导——FFI utf8 返回丢失定位
        @DllStaticImport( "slang_qt", "slqt_test_version_sl", "->utf8" )
        public static string ffi_testVersion() { ret "" }

        # ── UiTools / Designer ─────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_uiloader_create_sl" )
        public static Int64 ffi_uiLoaderCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_uiloader_delete_sl" )
        public static void ffi_uiLoaderDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_uiloader_load_file_sl" )
        public static Int64 ffi_uiLoaderLoadFile( Int64 h, string path, Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_uiloader_available_widgets_sl" )
        public static string ffi_uiLoaderAvailableWidgets( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_designer_formbuilder_create_sl" )
        public static Int64 ffi_formBuilderCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_designer_formbuilder_delete_sl" )
        public static void ffi_formBuilderDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_designer_formbuilder_load_sl" )
        public static Int64 ffi_formBuilderLoad( Int64 h, string path, Int64 parent ) { ret 0 }

        # ── Help（Qt6Help）─────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_help_engine_create_sl" )
        public static Int64 ffi_helpEngineCreate( string collection ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_help_engine_delete_sl" )
        public static void ffi_helpEngineDelete( Int64 h ) {}
        @DllStaticImport( "slang_qt", "slqt_help_setup_data_sl" )
        public static bool ffi_helpSetupData( Int64 h ) { ret false }
        @DllStaticImport( "slang_qt", "slqt_help_error_sl" )
        public static string ffi_helpError( Int64 h ) { ret "" }

        # ── DBus（Qt6DBus）─────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_dbus_connected_sl" )
        public static bool ffi_dbusConnected() { ret false }
        @DllStaticImport( "slang_qt", "slqt_dbus_base_service_sl" )
        public static string ffi_dbusBaseService() { ret "" }

        # ── 回调桥：handler 表 + 三个 dispatch trampoline ─────────────
        # 任意 SLang 函数值（静态方法引用 / 实例方法引用 / 闭包）登记进 _handlers，
        # 原生层只保存 (bind_id -> slot)；事件到达经对应 trampoline 取回调用。
        static List<Function> _handlers = null
        static Int64 _dispatchVoidCb = 0
        static Int64 _dispatchStringCb = 0
        static Int64 _dispatchIntCb = 0

        # 无参信号（clicked / returnPressed / destroyed）重入点
        public static void _dispatchVoid( Int64 slot )
        {
            Int32 idx = slot as Int32
            Function f = _handlers[idx]
            f()
        }

        # 带字符串参数信号（textChanged）重入点
        public static void _dispatchString( Int64 slot, string s )
        {
            Int32 idx = slot as Int32
            Function f = _handlers[idx]
            f( s )
        }

        # 带 int 参数信号（currentRowChanged）重入点
        public static void _dispatchInt( Int64 slot, Int64 value )
        {
            Int32 idx = slot as Int32
            Function f = _handlers[idx]
            f( value as Int32 )
        }

        # 连接信号到任意 SLang 函数值；按 signalId 选择 trampoline 形态。
        # createCallback 失败（cb=0，方法查找 miss）时不连接、bind 返回 0
        # ——原生层对 cb=0 同款拒绝（slqt_connect_sl），悬空 null 桩会让
        # 信号发射即崩溃；bind=0 在调用侧可见可诊断。
        # method 参数形态（回调目标识别契约归 SL 库层，2026-11-05 定稿）：
        # 必须传完整 method id（Module.NS.Class.Method_argc_T1_T2）或短方法名
        # （按 名字+参数个数 全局匹配）。"SLang.QT._dispatchVoid" 点路径
        # 不在 VM 查找表内——VM 曾为其加过 type_path 兜底（2026-11-02），
        # 已随本契约移除，勿再回退点路径写法。_dispatchVoid/_dispatchString
        # 全局唯一，走短名（WebUI._dispatchHandle 同款）。
        public static Int64 connect( Int64 h, Int32 signalId, Function handler )
        {
            if ( _handlers == null ) { _handlers = List<Function>() }
            if ( _dispatchVoidCb == 0 ) { _dispatchVoidCb = FFI.StaticLibrary.createCallback( "_dispatchVoid", "i64->void" ) }
            if ( _dispatchStringCb == 0 ) { _dispatchStringCb = FFI.StaticLibrary.createCallback( "_dispatchString", "i64,utf8->void" ) }
            if ( _dispatchIntCb == 0 ) { _dispatchIntCb = FFI.StaticLibrary.createCallback( "_dispatchInt", "i64,i64->void" ) }
            Int64 cb = _dispatchVoidCb
            if ( signalId == SIG_TEXT_CHANGED ) { cb = _dispatchStringCb }
            if ( signalId == SIG_CURRENT_ROW_CHANGED ) { cb = _dispatchIntCb }
            if ( cb == 0 ) { ret 0 }
            _handlers.add( handler )
            Int64 slot = ( _handlers.length - 1 ) as Int64
            ret ffi_connect( h, signalId, cb, slot )
        }

        # QTimer 桥：与 connect 同款 trampoline（void dispatch），超时重入 VM。
        # 返回句柄 > 0 表示创建成功；QTTest 动画面板据此驱动 widget move。
        public static Int64 timer( int ms, bool single, Function handler )
        {
            if ( _handlers == null ) { _handlers = List<Function>() }
            if ( _dispatchVoidCb == 0 ) { _dispatchVoidCb = FFI.StaticLibrary.createCallback( "_dispatchVoid", "i64->void" ) }
            if ( _dispatchVoidCb == 0 ) { ret 0 }
            _handlers.add( handler )
            Int64 slot = ( _handlers.length - 1 ) as Int64
            ret ffi_timerCreate( ms, single, _dispatchVoidCb, slot )
        }

        # ── 运行时门面（组合部署探测 / 自描述输出）──────────────────
        public static string backendKind() { ret ffi_backendKind() }
        public static string runtimeDir() { ret ffi_runtimeDir() }
        public static bool moduleAvailable( string dll ) { ret ffi_moduleAvailable( dll ) }
        public static string appPlatformName() { ret ffi_appPlatformName() }
        public static string appLibraryPaths() { ret ffi_appLibraryPaths() }
        public static string appStyleKeys() { ret ffi_appStyleKeys() }
        public static string sqlDrivers() { ret ffi_sqlDrivers() }
        public static string imageFormats() { ret ffi_imageFormats() }
        public static int threadPoolMax() { ret ffi_threadPoolMax() }
        public static string testVersion() { ret ffi_testVersion() }
        public static bool imageSaveSolid( string path, string fmt, int r, int g, int b ) { ret ffi_imageSaveSolid( path, fmt, r, g, b ) }
        public static bool imageCheckSize( string path, int w, int h ) { ret ffi_imageCheckSize( path, w, h ) }
        public static bool iconRender( string path, int size ) { ret ffi_iconRender( path, size ) }

        # ── 工厂（规避带命名空间 new 的限制；类构造函数仍保留供高级用户）──
        public static QApplication newApp() { ret QApplication() }
        public static QTimer newTimer( int ms, bool single, Function handler ) { ret QTimer( ms, single, handler ) }
        public static QNetworkAccessManager newNetManager() { ret QNetworkAccessManager() }
        public static QSqlDatabase addDatabase( string type ) { ret QSqlDatabase( type ) }
        public static QSvgRenderer newSvgRenderer( string xml ) { ret QSvgRenderer( xml ) }
        public static QSvgWidget newSvgWidget( Int64 parent ) { ret QSvgWidget( parent ) }
        public static QGLPanel newGLPanel( Int64 parent ) { ret QGLPanel( parent ) }
        public static QPrinter newPrinter() { ret QPrinter() }
        public static QDomDocument newDomDocument() { ret QDomDocument() }
        public static QConcurrentTask runConcurrent( int kind, Int64 n ) { ret QConcurrentTask( kind, n ) }
        public static QUiLoader newUiLoader() { ret QUiLoader() }
        public static QFormBuilder newFormBuilder() { ret QFormBuilder() }
        public static QHelpEngine newHelpEngine( string collection ) { ret QHelpEngine( collection ) }
        public static QPushButton newButton( Int64 parent, string text )
        {
            QPushButton b = QPushButton(parent)
            if ( text != null ) { b.setText( text ) }
            ret b
        }
        public static QLabel newLabel( Int64 parent, string text )
        {
            QLabel l = QLabel(parent)
            if ( text != null ) { l.setText( text ) }
            ret l
        }
        public static QLineEdit newLineEdit( Int64 parent, string placeholder )
        {
            QLineEdit e = QLineEdit(parent)
            if ( placeholder != null ) { e.setPlaceholder( placeholder ) }
            ret e
        }
        public static QWidget newWidget( Int64 parent ) { ret QWidget(parent) }
        public static QMainWindow newMainWindow() { ret QMainWindow() }
        public static QTextEdit newTextEdit( Int64 parent )
        {
            QTextEdit e = QTextEdit(parent)
            ret e
        }
        public static QListWidget newListWidget( Int64 parent ) { ret QListWidget(parent) }
        public static QVBoxLayout newVBox( Int64 parent ) { ret QVBoxLayout(parent) }
        public static QHBoxLayout newHBox( Int64 parent ) { ret QHBoxLayout(parent) }
        public static QGridLayout newGrid( Int64 parent ) { ret QGridLayout(parent) }

        # ── 2026-11-10 VS 式主框架扩展 FFI 面 ──────────────────────
        # 菜单：QMenuBar / QMenu / QAction（SIG_TRIGGERED 触发）
        @DllStaticImport( "slang_qt", "slqt_menubar_create_sl" )
        public static Int64 ffi_menubarCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mainwindow_set_menubar_sl" )
        public static void ffi_mainwindowSetMenubar( Int64 win, Int64 mb ) {}
        @DllStaticImport( "slang_qt", "slqt_menu_create_sl" )
        public static Int64 ffi_menuCreate( Int64 parent, string title ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_menu_add_action_sl" )
        public static Int64 ffi_menuAddAction( Int64 menu, string text ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_menu_add_separator_sl" )
        public static void ffi_menuAddSeparator( Int64 menu ) {}
        @DllStaticImport( "slang_qt", "slqt_action_set_text_sl" )
        public static void ffi_actionSetText( Int64 a, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_action_set_enabled_sl" )
        public static void ffi_actionSetEnabled( Int64 a, bool on ) {}

        # 工具栏：QToolBar（快捷图标区）
        @DllStaticImport( "slang_qt", "slqt_toolbar_create_sl" )
        public static Int64 ffi_toolbarCreate( Int64 parent, string title ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mainwindow_add_toolbar_sl" )
        public static void ffi_mainwindowAddToolbar( Int64 win, Int64 tb ) {}
        @DllStaticImport( "slang_qt", "slqt_toolbar_add_action_sl" )
        public static Int64 ffi_toolbarAddAction( Int64 tb, string text ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_toolbar_add_separator_sl" )
        public static void ffi_toolbarAddSeparator( Int64 tb ) {}

        # Dock：QDockWidget（自由停靠；area = Qt::DockWidgetArea 位值）
        @DllStaticImport( "slang_qt", "slqt_dock_create_sl" )
        public static Int64 ffi_dockCreate( Int64 parent, string title ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mainwindow_add_dock_sl" )
        public static void ffi_mainwindowAddDock( Int64 win, Int64 dock, int area ) {}
        @DllStaticImport( "slang_qt", "slqt_dock_set_widget_sl" )
        public static void ffi_dockSetWidget( Int64 dock, Int64 w ) {}
        @DllStaticImport( "slang_qt", "slqt_dock_set_features_sl" )
        public static void ffi_dockSetFeatures( Int64 dock, int f ) {}
        @DllStaticImport( "slang_qt", "slqt_dock_set_floating_sl" )
        public static void ffi_dockSetFloating( Int64 dock, bool on ) {}

        # MDI：QMdiArea + QMdiSubWindow（多文档代码区）
        @DllStaticImport( "slang_qt", "slqt_mdiarea_create_sl" )
        public static Int64 ffi_mdiareaCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mdiarea_add_subwindow_sl" )
        public static Int64 ffi_mdiareaAddSubWindow( Int64 mdi, Int64 w ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mdiarea_count_sl" )
        public static int ffi_mdiareaCount( Int64 mdi ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_mdiarea_tile_sl" )
        public static void ffi_mdiareaTile( Int64 mdi ) {}
        @DllStaticImport( "slang_qt", "slqt_mdiarea_cascade_sl" )
        public static void ffi_mdiareaCascade( Int64 mdi ) {}
        @DllStaticImport( "slang_qt", "slqt_mdiarea_close_active_sl" )
        public static void ffi_mdiareaCloseActive( Int64 mdi ) {}
        @DllStaticImport( "slang_qt", "slqt_mdiarea_active_sub_sl" )
        public static Int64 ffi_mdiareaActiveSub( Int64 mdi ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_subwindow_set_title_sl" )
        public static void ffi_subwindowSetTitle( Int64 sub, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_subwindow_show_maximized_sl" )
        public static void ffi_subwindowShowMaximized( Int64 sub ) {}

        # 对话框：QDialog（BaseDialog 基类）
        @DllStaticImport( "slang_qt", "slqt_dialog_create_sl" )
        public static Int64 ffi_dialogCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_dialog_set_modal_sl" )
        public static void ffi_dialogSetModal( Int64 d, bool on ) {}
        @DllStaticImport( "slang_qt", "slqt_dialog_exec_sl" )
        public static int ffi_dialogExec( Int64 d ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_dialog_accept_sl" )
        public static void ffi_dialogAccept( Int64 d ) {}
        @DllStaticImport( "slang_qt", "slqt_dialog_reject_sl" )
        public static void ffi_dialogReject( Int64 d ) {}

        # 控件 min/max 尺寸（面板规格钳制落地）
        @DllStaticImport( "slang_qt", "slqt_widget_set_min_size_sl" )
        public static void ffi_widgetSetMinSize( Int64 h, int w, int hh ) {}
        @DllStaticImport( "slang_qt", "slqt_widget_set_max_size_sl" )
        public static void ffi_widgetSetMaxSize( Int64 h, int w, int hh ) {}

        # ── VS 扩展工厂 ────────────────────────────────────────────
        public static QMenuBar newMenuBar() { ret QMenuBar() }
        public static QMenu newMenu( Int64 parent, string title ) { ret QMenu( parent, title ) }
        public static QToolBar newToolBar( Int64 parent, string title ) { ret QToolBar( parent, title ) }
        public static QDockWidget newDockWidget( Int64 parent, string title ) { ret QDockWidget( parent, title ) }
        public static QMdiArea newMdiArea( Int64 parent ) { ret QMdiArea( parent ) }
        public static QDialog newDialog( Int64 parent ) { ret QDialog( parent ) }
        # QAction / QMdiSubWindow 由原生创建（menu/toolbar/mdi 返回句柄），工厂按句柄收养
        public static QAction newAction( Int64 handle ) { ret QAction( handle ) }
        public static QMdiSubWindow newMdiSubWindow( Int64 handle ) { ret QMdiSubWindow( handle ) }
    }
}
