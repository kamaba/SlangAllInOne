import SLangQT;
import Std;
import Core;

# QT 宿主门面（纯 FFI 句柄形态）：SimGameEngine 传递的 SLang namespace 与
# SLangQT 同名，若在此文件声明 SLang.Xxx 类型成员会触发 import 平面重名，
# 故只存 Int64 句柄，全部经 SLang.QT.ffi_* 静态调用（调用表达式不触发冲突）。
public class QTHost
{
    static Int64 appHandle = 0
    static Int64 windowHandle = 0
    static Int64 infoHandle = 0
    static Int64 labelHandle = 0
    static Int64 timerHandle = 0

    public static void startHost( Function frameHandler )
    {
        appHandle = SLang.QT.ffi_appCreate()
        windowHandle = SLang.QT.ffi_keyWidgetCreate( 0 )
        SLang.QT.ffi_widgetSetText( windowHandle, "SceneDemo - [5] RotateTest ground+cube+sun, RMB drag rotate" )
        SLang.QT.ffi_widgetSetGeometry( windowHandle, 80, 80, 500, 566 )
        infoHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( infoHandle, 8, 6, 484, 44 )
        SLang.QT.ffi_widgetSetText( infoHandle, "CLICK scene to enter | M back to menu | 1-5 scenes | LMB pan, RMB ROTATE, WASD, wheel | G axes, F ui fmt, Esc quit" )
        labelHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 8, 52, 484, 484 )
        SLang.QT.ffi_widgetShow( windowHandle )
        SLang.QT.ffi_widgetShow( infoHandle )
        SLang.QT.ffi_widgetShow( labelHandle )
        timerHandle = SLang.QT.timer( 16, false, frameHandler )
        SLang.QT.ffi_timerStart( timerHandle, 16 )
        SLang.QT.ffi_appExec()
    }

    public static void blit( Int64 ptr, Int32 w, Int32 h )
    {
        SLang.QT.ffi_labelSetPixmapRgba( labelHandle, ptr, w, h )
    }

    public static void setInfo( string text )
    {
        SLang.QT.ffi_widgetSetText( infoHandle, text )
    }

    public static Int32 keyDown( Int32 key )
    {
        ret SLang.QT.ffi_keyDown( key )
    }

    # ── 鼠标轮询（2026-11-18）：坐标 = 全局屏幕像素；button 1=左 2=右；
    # wheelTake 读累计滚轮格数并清零（上 +1 / 下 -1）。
    public static Int32 mouseX()
    {
        ret SLang.QT.ffi_mouseX()
    }

    public static Int32 mouseY()
    {
        ret SLang.QT.ffi_mouseY()
    }

    # 渲染面（QLabel）局部坐标：FairyGUI 菜单点击命中用
    public static Int32 mouseLocalX()
    {
        ret SLang.QT.ffi_mouseLocalX()
    }

    public static Int32 mouseLocalY()
    {
        ret SLang.QT.ffi_mouseLocalY()
    }

    public static Int32 mouseDown( Int32 button )
    {
        ret SLang.QT.ffi_mouseDown( button )
    }

    public static Int32 mouseWheelTake()
    {
        ret SLang.QT.ffi_mouseWheelTake()
    }

    # ── 窗口尺寸轮询（2026-11-18 动态分辨率）：客户区像素；
    # resizeView 把显示 label 缩到 (8,52,w,h)（顶部留信息条）。
    public static Int32 windowW()
    {
        ret SLang.QT.ffi_widgetWidth( windowHandle )
    }

    public static Int32 windowH()
    {
        ret SLang.QT.ffi_widgetHeight( windowHandle )
    }

    public static void resizeView( Int32 w, Int32 h )
    {
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 8, 52, w, h )
    }
}
