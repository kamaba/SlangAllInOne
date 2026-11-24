import Std;
import Core;

# RExamplesHost - web wasm 版桩（GameTest/web 专用，替代桌面 QT 宿主）。
# 与桌面 RExamplesHost 同签名 surface：RExamples.sl 零改动编译进 wasm 模块。
# run() 的 12 个视图在 web 主循环按 idx 惰性重渲染（RExamplesWeb.show），
# 桩只保留打印面 —— 不持有像素（桌面 QT 版的 setPixmap 句柄在 wasm 无意义）。
public class RExamplesHost
{
    public static void build()
    {
        Console.println( "[RExamplesHost] web stub ready" )
    }

    public static void setCaption( Int32 idx, string text )
    {
        Console.println( "[cell " + idx.toString() + "] " + text )
    }

    public static void setPixmap( Int32 idx, Int64 ptr, Int32 w, Int32 hh )
    {
        # web：主循环用 RExamplesWeb.show(idx) 直接 blit，桩不持有像素
    }

    public static void setTitle( string text )
    {
        Console.println( "[RExamples] " + text )
    }

    public static void exec()
    {
        # web：主循环由 RExamplesWeb 驱动，exec 立即返回
    }
}
