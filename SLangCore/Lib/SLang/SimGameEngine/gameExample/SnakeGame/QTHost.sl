import SLangQT;
import Std;
import Core;

# QTHost - QT host facade in pure FFI-handle form (SnakeGame, 2026-11-17).
# Why this exists: SimGameEngine (transitively brings SLangRender namespace
# SLang) + SLangQT (namespace SLang) referenced by one module -> the import
# plane name "SLang" clashes -> ANY member declaration typed `SLang.Xxx`
# raises MetaCoreMemberNameImportConflict (call expressions are fine).
# Workaround: NO wrapped-object members here - QT objects are kept as
# Int64 handles and driven via QTFFI static exports directly.
public class QTHost
{
    static Int64 appHandle = 0
    static Int64 keyWHandle = 0
    static Int64 labelHandle = 0
    static Int64 infoHandle = 0
    static Int64 timerHandle = 0

    # key bridge (int payload = Qt::Key) -> engine input state table (C)
    static void keyPressedBridge( Int32 key )
    {
        QTHost.ffiInputSetKey( key, 1 )
    }

    static void keyReleasedBridge( Int32 key )
    {
        QTHost.ffiInputSetKey( key, 0 )
    }

    # direct write into sle_input table (dll-name binding, no module import)
    static void inputSetKey( Int32 key, Int32 down )
    {
        QTHost.ffiInputSetKey( key, down )
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_key", "i32,i32->i32" )
    public static Int32 ffiInputSetKey( Int32 key, Int32 down )
    {
        ret 0 - 1
    }

    # startHost - build window + wire handlers; exec blocks in Qt loop.
    # handlers: frame = static void(); keyPress/Release = static void( int key )
    public static void startHost( Function frameHandler, Function keyPressHandler, Function keyReleaseHandler )
    {
        appHandle = SLang.QT.ffi_appCreate()
        # 单一顶层窗口 = SlangKeyWidget（键盘事件源）。原实现另建一个
        # ffi_widgetCreate(0) 的普通 QWidget 当"标题窗口"，两个 parent=0
        # 窗口几何完全重合；盖在上面的空 QWidget 把挂了 label 的键盘窗口
        # 整个遮住 -> 截图只见空白标题窗，游戏画面永远不可见。
        keyWHandle = SLang.QT.ffi_keyWidgetCreate( 0 )
        SLang.QT.ffi_widgetSetText( keyWHandle, "SnakeGame - SimGameEngine + SLangQT" )
        SLang.QT.ffi_widgetSetGeometry( keyWHandle, 80, 80, 500, 566 )
        # info bar (top): score / status text; QLabel setText via widgetSetText
        infoHandle = SLang.QT.ffi_labelCreate( keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( infoHandle, 10, 6, 480, 40 )
        SLang.QT.ffi_widgetSetText( infoHandle, "Score: 0    Use arrow keys / R to restart" )
        # game canvas (square, below info bar)
        labelHandle = SLang.QT.ffi_labelCreate( keyWHandle )
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 10, 48, 480, 480 )
        SLang.QT.connect( keyWHandle, SLang.QT.SIG_KEY_PRESSED, keyPressHandler )
        SLang.QT.connect( keyWHandle, SLang.QT.SIG_KEY_RELEASED, keyReleaseHandler )
        SLang.QT.ffi_widgetShow( keyWHandle )
        SLang.QT.ffi_widgetShow( infoHandle )
        SLang.QT.ffi_widgetShow( labelHandle )
        timerHandle = SLang.QT.timer( 16, false, frameHandler )
        SLang.QT.ffi_timerStart( timerHandle, 16 )
        SLang.QT.ffi_appExec()
    }

    # blit - engine frame pixels (RGBA8 top-down) onto the label
    public static void blit( Int64 ptr, Int32 w, Int32 h )
    {
        SLang.QT.ffi_labelSetPixmapRgba( labelHandle, ptr, w, h )
    }

    # setInfo - update the top score/status bar text
    public static void setInfo( string text )
    {
        SLang.QT.ffi_widgetSetText( infoHandle, text )
    }

    # keyDown - poll current pressed state (Qt::Key) via SLangQT FFI.
    # Kept in QTHost (the only file importing SLangQT) to avoid the
    # double namespace SLang import conflict in SnakeGame.sl.
    public static Int32 keyDown( Int32 key )
    {
        ret SLang.QT.ffi_keyDown( key )
    }
}