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
    # 顶部菜单栏（Ctrl+Home 切换显示；菜单项「显示辅助 Gizmo」切 Gizmo 开关）
    static Int64 menuBarHandle = 0
    static Int64 gizmoMenuHandle = 0
    static Int64 gizmoActionHandle = 0
    static bool menuVisible = false

    # toggleGizmoHandler = static void()，菜单动作触发回调（切 Gizmo 显示开关）
    public static void startHost( Function frameHandler, Function toggleGizmoHandler )
    {
        appHandle = SLang.QT.ffi_appCreate()
        windowHandle = SLang.QT.ffi_keyWidgetCreate( 0 )
        SLang.QT.ffi_widgetSetText( windowHandle, "SceneDemo - [5] RotateTest ground+cube+sun, RMB drag rotate" )
        SLang.QT.ffi_widgetSetGeometry( windowHandle, 80, 80, 500, 566 )
        infoHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( infoHandle, 8, 6, 484, 44 )
        SLang.QT.ffi_widgetSetText( infoHandle, "CLICK scene to enter | M back to menu | 1-5 scenes | LMB pan, RMB ROTATE, WASD, wheel | G axes, U ui overlay, F ui fmt, Ctrl+Home menu, Esc quit" )
        labelHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( labelHandle, 8, 52, 484, 484 )
        # 顶部菜单栏：QMenuBar 作普通 QWidget 子控件放窗口最顶（非 QMainWindow
        # 不走 setMenuBar）。Ctrl+Home 切换显示；菜单项「显示辅助 Gizmo」
        # 经 SIG_TRIGGERED 连到 toggleGizmoHandler（无参 void trampoline）。
        menuBarHandle = SLang.QT.ffi_menubarCreate()
        SLang.QT.ffi_widgetSetParent( menuBarHandle, windowHandle )
        SLang.QT.ffi_widgetSetGeometry( menuBarHandle, 0, 0, 500, 26 )
        gizmoMenuHandle = SLang.QT.ffi_menuCreate( menuBarHandle, "辅助 Gizmo" )
        gizmoActionHandle = SLang.QT.ffi_menuAddAction( gizmoMenuHandle, "显示辅助 Gizmo" )
        SLang.QT.connect( gizmoActionHandle, SLang.QT.SIG_TRIGGERED, toggleGizmoHandler )
        SLang.QT.ffi_widgetHide( menuBarHandle )
        SLang.QT.ffi_widgetShow( windowHandle )
        SLang.QT.ffi_widgetShow( infoHandle )
        SLang.QT.ffi_widgetShow( labelHandle )
        timerHandle = SLang.QT.timer( 16, false, frameHandler )
        SLang.QT.ffi_timerStart( timerHandle, 16 )
        SLang.QT.ffi_appExec()
    }

    # Ctrl+Home 切换菜单栏显示
    public static void toggleMenuBar()
    {
        if menuVisible
        {
            SLang.QT.ffi_widgetHide( menuBarHandle )
            menuVisible = false
        }
        else
        {
            SLang.QT.ffi_widgetShow( menuBarHandle )
            menuVisible = true
        }
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
