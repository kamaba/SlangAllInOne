import Std;
import Core;

# RDataHost - web wasm 版桩（GameTest/web 专用，替代桌面 QT 宿主）。
# 与桌面 RDataHost 同签名 surface：RDataGallery.sl 零改动编译进 wasm 模块。
# run() 的 6 个视图在 web 主循环按 idx 惰性重渲染（RDataWeb.show），
# 桩只保留打印面。
public class RDataHost
{
    public static void build()
    {
        Console.println( "[RDataHost] web stub ready" )
    }

    public static void show( Int32 idx, string caption, Int64 ptr, Int32 w, Int32 hh )
    {
        Console.println( "[view " + idx.toString() + "] " + caption )
    }

    public static void setTitle( string text )
    {
        Console.println( "[RDataGallery] " + text )
    }

    public static void exec()
    {
        # web：主循环由 RDataWeb 驱动，exec 立即返回
    }
}
