import Std;
import Core;
import SimGameEngine;

# RExamplesWeb - web wasm 主循环（GameTest/web）：单视图全屏 blit +
# 滚轮/左右方向键切视图。视图构造复用 RExamples.exPlot() 等 12 个工厂
# （CPU DrawCanvas，无需 GPU 后端），每次切换重渲染后释放。
# 页面顶部菜单条：◀/▶ 按钮经 sle_input_set_mouse_wheel 注入滚轮。
public class RExamplesWeb
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
    static Int32 cellCount = 12
    static Int32 KEY_LEFT = 16777234
    static Int32 KEY_RIGHT = 16777236
    static bool prevLeft = false
    static bool prevRight = false
    # 当前画布保持存活：wasm 呈现上下文无 preserveDrawingBuffer，合成后
    # 绘图缓冲会被清空 —— 主循环每帧重 blit 当前像素块（上屏 + fps 计数）
    static DrawCanvas curC = null

    public static void show( Int32 idx )
    {
        DrawCanvas c = RExamplesWeb.render( idx )
        if c == null
        {
            ret
        }
        if RExamplesWeb.curC != null
        {
            Memory.free( RExamplesWeb.curC )
        }
        RExamplesWeb.curC = c
        RExamplesWeb.current = idx
        RExamplesWeb.blitCur()
        Console.println( "[cell " + idx.toString() + "] " + RExamplesWeb.caption( idx ) )
    }

    static void blitCur()
    {
        DrawCanvas c = RExamplesWeb.curC
        if c == null
        {
            ret
        }
        Int32 w = c.width()
        Int32 h = c.height()
        Int64 pp = c.pixelPtr()
        RExamplesWeb.ffiWebBlit( pp, w, h )
    }

    static DrawCanvas render( Int32 idx )
    {
        if idx == 0
        {
            ret RExamples.exPlot()
        }
        if idx == 1
        {
            ret RExamples.exHist()
        }
        if idx == 2
        {
            ret RExamples.exBar()
        }
        if idx == 3
        {
            ret RExamples.exBarGroup()
        }
        if idx == 4
        {
            ret RExamples.exBox()
        }
        if idx == 5
        {
            ret RExamples.exPie()
        }
        if idx == 6
        {
            ret RExamples.exTypes()
        }
        if idx == 7
        {
            ret RExamples.exPar()
        }
        if idx == 8
        {
            ret RExamples.exLegend()
        }
        if idx == 9
        {
            ret RExamples.exAbline()
        }
        if idx == 10
        {
            ret RExamples.exRegression()
        }
        if idx == 11
        {
            ret RExamples.exMathR()
        }
        ret null
    }

    static string caption( Int32 idx )
    {
        if idx == 0
        {
            ret "plot: height/weight + lm"
        }
        if idx == 1
        {
            ret "hist: exam scores + mean/median"
        }
        if idx == 2
        {
            ret "barplot: product sales"
        }
        if idx == 3
        {
            ret "barplot: Q1 vs Q2 grouped"
        }
        if idx == 4
        {
            ret "boxplot: three classes"
        }
        if idx == 5
        {
            ret "pie: market share"
        }
        if idx == 6
        {
            ret "plot(type=n+h+o): temperature"
        }
        if idx == 7
        {
            ret "par(mfrow=c(2,2))"
        }
        if idx == 8
        {
            ret "legend: three products"
        }
        if idx == 9
        {
            ret "abline: regression + mean"
        }
        if idx == 10
        {
            ret "lm: height -> weight + 170 prediction"
        }
        ret "MathR: dnorm + rnorm histogram"
    }

    static void step( Int32 delta )
    {
        Int32 nc = RExamplesWeb.current + delta
        if nc < 0
        {
            nc = 0
        }
        if nc > RExamplesWeb.cellCount - 1
        {
            nc = RExamplesWeb.cellCount - 1
        }
        if nc != RExamplesWeb.current
        {
            RExamplesWeb.current = nc
            RExamplesWeb.show( nc )
        }
    }

    public static void run()
    {
        RExamplesWeb.show( 0 )
        Console.println( "[RExamplesWeb] pump start (wheel / left-right keys switch cells)" )
        bool running = true
        while running
        {
            Int32 wl = RExamplesWeb.ffiWheelTake()
            if wl != 0
            {
                RExamplesWeb.step( wl )
            }
            Int32 kl = RExamplesWeb.ffiKeyDown( RExamplesWeb.KEY_LEFT )
            Int32 kr = RExamplesWeb.ffiKeyDown( RExamplesWeb.KEY_RIGHT )
            if kl == 1 && RExamplesWeb.prevLeft == false
            {
                RExamplesWeb.step( 0 - 1 )
            }
            if kr == 1 && RExamplesWeb.prevRight == false
            {
                RExamplesWeb.step( 1 )
            }
            RExamplesWeb.prevLeft = kl == 1
            RExamplesWeb.prevRight = kr == 1
            RExamplesWeb.blitCur()
            OS.Timer.sleep( 16 )
        }
    }
}
