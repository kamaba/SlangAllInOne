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

        # ── 应用 ────────────────────────────────────────────────────
        @DllStaticImport( "slang_qt", "slqt_app_create_sl" )
        public static Int64 ffi_appCreate() { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_app_set_style_sl" )
        public static void ffi_appSetStyle( string name ) {}
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
        @DllStaticImport( "slang_qt", "slqt_edit_create_sl" )
        public static Int64 ffi_editCreate( Int64 parent ) { ret 0 }
        @DllStaticImport( "slang_qt", "slqt_edit_set_placeholder_sl" )
        public static void ffi_editSetPlaceholder( Int64 h, string t ) {}
        @DllStaticImport( "slang_qt", "slqt_edit_text_sl" )
        public static string ffi_editText( Int64 h ) { ret "" }
        @DllStaticImport( "slang_qt", "slqt_edit_set_readonly_sl" )
        public static void ffi_editSetReadonly( Int64 h, bool on ) {}

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

        # ── 回调桥：handler 表 + 两个 dispatch trampoline ─────────────
        # 任意 SLang 函数值（静态方法引用 / 实例方法引用 / 闭包）登记进 _handlers，
        # 原生层只保存 (bind_id -> slot)；事件到达经对应 trampoline 取回调用。
        static List<Function> _handlers = null
        static Int64 _dispatchVoidCb = 0
        static Int64 _dispatchStringCb = 0

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

        # 连接信号到任意 SLang 函数值；按 signalId 选择 trampoline 形态。
        public static Int64 connect( Int64 h, Int32 signalId, Function handler )
        {
            if ( _handlers == null ) { _handlers = List<Function>() }
            if ( _dispatchVoidCb == 0 ) { _dispatchVoidCb = FFI.StaticLibrary.createCallback( "SLang.QT._dispatchVoid", "i64->void" ) }
            if ( _dispatchStringCb == 0 ) { _dispatchStringCb = FFI.StaticLibrary.createCallback( "SLang.QT._dispatchString", "i64,utf8->void" ) }
            _handlers.add( handler )
            Int64 slot = ( _handlers.length - 1 ) as Int64
            Int64 cb = _dispatchVoidCb
            if ( signalId == SIG_TEXT_CHANGED ) { cb = _dispatchStringCb }
            ret ffi_connect( h, signalId, cb, slot )
        }

        # ── 工厂（规避带命名空间 new 的限制；类构造函数仍保留供高级用户）──
        public static QApplication newApp() { ret QApplication() }
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
        public static QVBoxLayout newVBox( Int64 parent ) { ret QVBoxLayout(parent) }
        public static QHBoxLayout newHBox( Int64 parent ) { ret QHBoxLayout(parent) }
        public static QGridLayout newGrid( Int64 parent ) { ret QGridLayout(parent) }
    }
}
