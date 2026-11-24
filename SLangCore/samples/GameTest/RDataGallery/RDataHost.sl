import SLangQT;
import Std;
import Core;

# QT 宿主（纯 FFI 句柄形态）：SimGameEngine 与 SLangQT 同为 namespace SLang，
# 本文件只存 Int64 句柄，全部走 SLang.QT.ffi_* 调用表达式规避成员名冲突。
public class RDataHost
{
    static Int64 appHandle = 0
    static Int64 windowHandle = 0
    static Int64 titleHandle = 0
    static List<Int64> cells = null
    static List<Int64> captions = null

    public static void build()
    {
        appHandle = SLang.QT.ffi_appCreate()
        windowHandle = SLang.QT.ffi_keyWidgetCreate( 0 )
        SLang.QT.ffi_widgetSetText( windowHandle, "Std.RData -> SimGameEngine.RDataChart -> RenderTexture -> QLabel" )
        SLang.QT.ffi_widgetSetGeometry( windowHandle, 60, 40, 1280, 780 )
        titleHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( titleHandle, 8, 4, 1264, 28 )
        SLang.QT.ffi_widgetSetText( titleHandle, "6 views | top: vector / factor / time series | bottom: csv column / forecast / RenderTexture blit | close window to exit" )

        cells = List<Int64>()
        captions = List<Int64>()
        Int32 i = 0
        while i < 6
        {
            Int32 x = 8 + ( i % 3 ) * 420
            Int32 y = 54 + ( i / 3 ) * 350
            Int64 cap = SLang.QT.ffi_labelCreate( windowHandle )
            SLang.QT.ffi_widgetSetGeometry( cap, x, y - 20, 412, 18 )
            captions.add( cap )
            Int64 cell = SLang.QT.ffi_labelCreate( windowHandle )
            SLang.QT.ffi_widgetSetGeometry( cell, x, y, 412, 330 )
            cells.add( cell )
            SLang.QT.ffi_widgetShow( cap )
            SLang.QT.ffi_widgetShow( cell )
            i = i + 1
        }
        SLang.QT.ffi_widgetShow( titleHandle )
        SLang.QT.ffi_widgetShow( windowHandle )
    }

    public static void show( Int32 idx, string caption, Int64 ptr, Int32 w, Int32 hh )
    {
        Int64 cap = captions._getItem_( idx )
        Int64 cell = cells._getItem_( idx )
        SLang.QT.ffi_widgetSetText( cap, caption )
        SLang.QT.ffi_labelSetPixmapRgba( cell, ptr, w, hh )
    }

    public static void setTitle( string text )
    {
        SLang.QT.ffi_widgetSetText( titleHandle, text )
    }

    public static void exec()
    {
        SLang.QT.ffi_appExec()
    }
}
