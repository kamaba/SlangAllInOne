import Std;
import Core;
import SimGameEngine;

# RDataWeb - web wasm 主循环（GameTest/web）：单视图全屏 blit +
# 滚轮/左右方向键切视图。视图构造复用 RDataGallery.view0()..view5()
# （2026-11-24 重构后的 public 视图工厂；CPU DrawCanvas，无需 GPU 后端），
# 每次切换重渲染后释放。
# 页面顶部菜单条：◀/▶ 按钮经 sle_input_set_mouse_wheel 注入滚轮。
public class RDataWeb
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
    static Int32 cellCount = 6
    static Int32 KEY_LEFT = 16777234
    static Int32 KEY_RIGHT = 16777236
    static bool prevLeft = false
    static bool prevRight = false
    # 当前画布保持存活：wasm 呈现上下文无 preserveDrawingBuffer，合成后
    # 绘图缓冲会被清空 —— 主循环每帧重 blit 当前像素块（上屏 + fps 计数）
    static DrawCanvas curC = null

    public static void show( Int32 idx )
    {
        DrawCanvas c = RDataWeb.render( idx )
        if c == null
        {
            ret
        }
        if RDataWeb.curC != null
        {
            Memory.free( RDataWeb.curC )
        }
        RDataWeb.curC = c
        RDataWeb.current = idx
        RDataWeb.blitCur()
        Console.println( "[view " + idx.toString() + "] " + RDataGallery.caption( idx ) )
    }

    static void blitCur()
    {
        DrawCanvas c = RDataWeb.curC
        if c == null
        {
            ret
        }
        Int32 w = c.width()
        Int32 h = c.height()
        Int64 pp = c.pixelPtr()
        RDataWeb.ffiWebBlit( pp, w, h )
    }

    static DrawCanvas render( Int32 idx )
    {
        if idx == 0
        {
            ret RDataGallery.view0()
        }
        if idx == 1
        {
            ret RDataGallery.view1()
        }
        if idx == 2
        {
            ret RDataGallery.view2()
        }
        if idx == 3
        {
            ret RDataGallery.view3()
        }
        if idx == 4
        {
            ret RDataGallery.view4()
        }
        ret RDataGallery.view5()
    }

    static void step( Int32 delta )
    {
        Int32 nc = RDataWeb.current + delta
        if nc < 0
        {
            nc = 0
        }
        if nc > RDataWeb.cellCount - 1
        {
            nc = RDataWeb.cellCount - 1
        }
        if nc != RDataWeb.current
        {
            RDataWeb.current = nc
            RDataWeb.show( nc )
        }
    }

    public static void run()
    {
        # 桌面同款 run()：渲染全部 6 视图（校验 + 桩打印）+ exec 立即返回
        RDataGallery.run()
        RDataWeb.show( 0 )
        Console.println( "[RDataWeb] pump start (wheel / left-right keys switch views)" )
        bool running = true
        while running
        {
            Int32 wl = RDataWeb.ffiWheelTake()
            if wl != 0
            {
                RDataWeb.step( wl )
            }
            Int32 kl = RDataWeb.ffiKeyDown( RDataWeb.KEY_LEFT )
            Int32 kr = RDataWeb.ffiKeyDown( RDataWeb.KEY_RIGHT )
            if kl == 1 && RDataWeb.prevLeft == false
            {
                RDataWeb.step( 0 - 1 )
            }
            if kr == 1 && RDataWeb.prevRight == false
            {
                RDataWeb.step( 1 )
            }
            RDataWeb.prevLeft = kl == 1
            RDataWeb.prevRight = kr == 1
            RDataWeb.blitCur()
            OS.Timer.sleep( 16 )
        }
    }
}
