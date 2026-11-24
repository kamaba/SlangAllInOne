import SLangQT;
import Std;
import Core;

# QT 图库宿主（纯 FFI 句柄形态）。与 SceneDemo QTHost 同款规避：
# SimGameEngine 与 SLangQT 均带 namespace SLang，本文件只存 Int64 句柄，
# 全部走 SLang.QT.ffi_* 调用表达式，不声明 SLang.Xxx 类型成员。
public class GalleryHost
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
        SLang.QT.ffi_widgetSetText( windowHandle, "SimGameEngine - Drawing & StatsPlot Gallery" )
        SLang.QT.ffi_widgetSetGeometry( windowHandle, 60, 40, 1280, 920 )
        titleHandle = SLang.QT.ffi_labelCreate( windowHandle )
        SLang.QT.ffi_widgetSetGeometry( titleHandle, 8, 4, 1264, 28 )
        SLang.QT.ffi_widgetSetText( titleHandle, "16 views | rows 1-2: engine drawing/ | rows 3-4: merged StatsPlot | close window to exit" )

        cells = List<Int64>()
        captions = List<Int64>()
        Int32 row = 0
        while row < 4
        {
            Int32 col = 0
            while col < 4
            {
                Int32 x = 8 + col * 310
                Int32 y = 54 + row * 209
                Int64 cap = SLang.QT.ffi_labelCreate( windowHandle )
                SLang.QT.ffi_widgetSetGeometry( cap, x, y - 20, 306, 18 )
                captions.add( cap )
                Int64 cell = SLang.QT.ffi_labelCreate( windowHandle )
                SLang.QT.ffi_widgetSetGeometry( cell, x, y, 306, 205 )
                cells.add( cell )
                SLang.QT.ffi_widgetShow( cap )
                SLang.QT.ffi_widgetShow( cell )
                col = col + 1
            }
            row = row + 1
        }
        SLang.QT.ffi_widgetShow( titleHandle )
        SLang.QT.ffi_widgetShow( windowHandle )
    }

    public static void setCaption( Int32 idx, string text )
    {
        Int64 cap = captions._getItem_( idx )
        SLang.QT.ffi_widgetSetText( cap, text )
    }

    public static void setPixmap( Int32 idx, Int64 ptr, Int32 w, Int32 hh )
    {
        Int64 cell = cells._getItem_( idx )
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

    public static void quit()
    {
        SLang.QT.ffi_appQuit()
    }
}
