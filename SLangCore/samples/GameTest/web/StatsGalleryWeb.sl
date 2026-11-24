import Std;
import Core;
import SimGameEngine;

# StatsGalleryWeb - web wasm 主循环（GameTest/web）：单视图全屏 blit +
# 滚轮/左右方向键切视图。视图构造复用 StatsGallery.view0()..view15()
# （2026-11-24 重构后的 public 视图工厂；CPU DrawCanvas/PlotCanvas，无需
# GPU 后端），每次切换重渲染后释放。
# 页面顶部菜单条：◀/▶ 按钮经 sle_input_set_mouse_wheel 注入滚轮。
public class StatsGalleryWeb
{
    @DllStaticImport( "sl_sim_engine_lib", "sle_web_blit", "i64,i32,i32->i32" )
    public static Int32 ffiWebBlit( Int64 ptr, Int32 w, Int32 h )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_mouse_wheel_take", "->i32" )
    public static Int32 ffiWheelTake()
    {
        ret 0
    }

    # 仅导出面登记用（页面 JS 直调 _sle_input_set_mouse_wheel）；SL 侧不调
    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_mouse_wheel", "i32->i32" )
    public static Int32 ffiWheelSet( Int32 delta )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_down", "i32->i32" )
    public static Int32 ffiKeyDown( Int32 key )
    {
        ret 0
    }

    static Int32 current = 0
    static Int32 cellCount = 16
    static Int32 KEY_LEFT = 16777234
    static Int32 KEY_RIGHT = 16777236
    static bool prevLeft = false
    static bool prevRight = false
    # 当前画布保持存活：wasm 呈现上下文无 preserveDrawingBuffer，合成后
    # 绘图缓冲会被清空 —— 主循环每帧重 blit 当前像素块（上屏 + fps 计数）
    static DrawCanvas curC = null
    static StatsPlot.PlotCanvas curS = null

    public static void show( Int32 idx )
    {
        StatsGalleryWeb.freeCur()
        StatsGalleryWeb.current = idx
        if idx >= 0 && idx <= 7
        {
            StatsGalleryWeb.curC = StatsGalleryWeb.renderDraw( idx )
        }
        elif idx >= 8 && idx <= 14
        {
            StatsGalleryWeb.curS = StatsGalleryWeb.renderStats( idx )
        }
        else
        {
            StatsGalleryWeb.curC = StatsGallery.view15()
        }
        StatsGalleryWeb.blitCur()
        Console.println( "[view " + idx.toString() + "] " + StatsGallery.caption( idx ) )
    }

    static void freeCur()
    {
        if StatsGalleryWeb.curC != null
        {
            Memory.free( StatsGalleryWeb.curC )
            StatsGalleryWeb.curC = null
        }
        if StatsGalleryWeb.curS != null
        {
            StatsGalleryWeb.curS.free()
            StatsGalleryWeb.curS = null
        }
    }

    static void blitCur()
    {
        if StatsGalleryWeb.curC != null
        {
            Int32 w = StatsGalleryWeb.curC.width()
            Int32 h = StatsGalleryWeb.curC.height()
            Int64 pp = StatsGalleryWeb.curC.pixelPtr()
            StatsGalleryWeb.ffiWebBlit( pp, w, h )
        }
        elif StatsGalleryWeb.curS != null
        {
            Int32 w2 = StatsGalleryWeb.curS.width()
            Int32 h2 = StatsGalleryWeb.curS.height()
            Int64 pp2 = StatsGalleryWeb.curS.pixelPtr()
            StatsGalleryWeb.ffiWebBlit( pp2, w2, h2 )
        }
    }

    static DrawCanvas renderDraw( Int32 idx )
    {
        if idx == 0
        {
            ret StatsGallery.view0()
        }
        if idx == 1
        {
            ret StatsGallery.view1()
        }
        if idx == 2
        {
            ret StatsGallery.view2()
        }
        if idx == 3
        {
            ret StatsGallery.view3()
        }
        if idx == 4
        {
            ret StatsGallery.view4()
        }
        if idx == 5
        {
            ret StatsGallery.view5()
        }
        if idx == 6
        {
            ret StatsGallery.view6()
        }
        if idx == 7
        {
            ret StatsGallery.view7()
        }
        ret null
    }

    static StatsPlot.PlotCanvas renderStats( Int32 idx )
    {
        if idx == 8
        {
            ret StatsGallery.view8()
        }
        if idx == 9
        {
            ret StatsGallery.view9()
        }
        if idx == 10
        {
            ret StatsGallery.view10()
        }
        if idx == 11
        {
            ret StatsGallery.view11()
        }
        if idx == 12
        {
            ret StatsGallery.view12()
        }
        if idx == 13
        {
            ret StatsGallery.view13()
        }
        ret StatsGallery.view14()
    }

    static void step( Int32 delta )
    {
        Int32 nc = StatsGalleryWeb.current + delta
        if nc < 0
        {
            nc = 0
        }
        if nc > StatsGalleryWeb.cellCount - 1
        {
            nc = StatsGalleryWeb.cellCount - 1
        }
        if nc != StatsGalleryWeb.current
        {
            StatsGalleryWeb.current = nc
            StatsGalleryWeb.show( nc )
        }
    }

    public static void run()
    {
        # 桌面同款 run()：渲染全部 16 视图（校验 + 桩打印）+ exec 立即返回
        StatsGallery.run()
        StatsGalleryWeb.show( 0 )
        Console.println( "[StatsGalleryWeb] pump start (wheel / left-right keys switch views)" )
        bool running = true
        while running
        {
            Int32 wl = StatsGalleryWeb.ffiWheelTake()
            if wl != 0
            {
                StatsGalleryWeb.step( wl )
            }
            Int32 kl = StatsGalleryWeb.ffiKeyDown( StatsGalleryWeb.KEY_LEFT )
            Int32 kr = StatsGalleryWeb.ffiKeyDown( StatsGalleryWeb.KEY_RIGHT )
            if kl == 1 && StatsGalleryWeb.prevLeft == false
            {
                StatsGalleryWeb.step( 0 - 1 )
            }
            if kr == 1 && StatsGalleryWeb.prevRight == false
            {
                StatsGalleryWeb.step( 1 )
            }
            StatsGalleryWeb.prevLeft = kl == 1
            StatsGalleryWeb.prevRight = kr == 1
            StatsGalleryWeb.blitCur()
            OS.Timer.sleep( 16 )
        }
    }
}
