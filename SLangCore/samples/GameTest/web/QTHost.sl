import Core;
import Std;
import SimGameEngine;

# QTHost - web wasm 版宿主门面（GameTest/web 专用，替代桌面 QTHost.sl）。
# 与桌面版同签名 surface：SceneDemo.sl 零改动编译进 wasm 模块。
#   输入：引擎 C 输入状态表（sle_input_*；页面 JS 经 sle_input_set_* 注入，
#         与桌面 QT 宿主喂同一张表——见 WASM-RENDER-GUIDE.md §2.3）
#   呈现：sle_web_blit（RGBA8 块 → EM_JS __snakeOnBlit → JS texImage2D 上屏）
#   尺寸：sle_web_window_width/height（= canvas width/height 属性）
# 坐标约定（两处补偿）：
#   - JS 注入鼠标坐标时 +10（FairyGUI 命中测试内部会减掉，模板 MOUSE_OFFSET）；
#   - tryMenuClick 用「窗口客户区坐标」再减 QLabel 原点 (8,52)；web 画布即
#     渲染面，无 (8,52) 偏移，故 mouseLocalX/Y 加回 8/52 抵消。
#   - updateRenderTarget 按「窗口客户区 - 信息条 (16,60)」算渲染尺寸；web
#     顶栏在 canvas 外，故 windowW/H 返回画布尺寸 +16/+60 抵消，使渲染
#     目标 = canvas 属性精确一致（分辨率下拉框改 canvas 即生效）。
public class QTHost
{
    # wasm 平台桥（sl_sim_engine_lib 编进 csimple_lang_game，dlopen(NULL) 自解析）
    @DllStaticImport( "sl_sim_engine_lib", "sle_web_blit", "i64,i32,i32->i32" )
    public static Int32 ffiWebBlit( Int64 ptr, Int32 w, Int32 h )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_web_window_width", "->i32" )
    public static Int32 ffiWebWinWidth()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_web_window_height", "->i32" )
    public static Int32 ffiWebWinHeight()
    {
        ret 0
    }

    # 引擎 C 输入状态表（Qt::Key 键码）
    @DllStaticImport( "sl_sim_engine_lib", "sle_input_down", "i32->i32" )
    public static Int32 ffiKeyDown( Int32 key )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_mouse_button", "i32->i32" )
    public static Int32 ffiMouseButton( Int32 button )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_mouse_x", "->i32" )
    public static Int32 ffiMouseX()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_mouse_y", "->i32" )
    public static Int32 ffiMouseY()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_mouse_wheel_take", "->i32" )
    public static Int32 ffiMouseWheelTake()
    {
        ret 0
    }

    # ── 桌面 QTHost 同签名 surface ────────────────────────────────

    # web：主循环由 SceneDemoWeb.sp 驱动（ASYNCIFY sleep 让出事件循环），
    # 无 QT timer/app.exec；两个 Function 实参仅保持调用点兼容。
    public static void startHost( Function frameHandler, Function toggleGizmoHandler )
    {
        Console.println( "[QTHost] web facade ready (pump loop owned by SceneDemoWeb)" )
    }

    public static void toggleMenuBar()
    {
        # web 无 QT 菜单栏（顶部菜单条由页面 HTML 提供）
    }

    public static void blit( Int64 ptr, Int32 w, Int32 h )
    {
        QTHost.ffiWebBlit( ptr, w, h )
    }

    public static void setInfo( string text )
    {
        Console.println( "[info] " + text )
    }

    public static Int32 keyDown( Int32 key )
    {
        ret QTHost.ffiKeyDown( key )
    }

    public static Int32 mouseX()
    {
        ret QTHost.ffiMouseX()
    }

    public static Int32 mouseY()
    {
        ret QTHost.ffiMouseY()
    }

    # 「窗口客户区坐标」语义：引擎表坐标剥掉 +10 补偿再抵消 QLabel 原点，
    # tryMenuClick 里的 -8/-52 之后正好落在画布像素。
    public static Int32 mouseLocalX()
    {
        ret QTHost.ffiMouseX() - 10 + 8
    }

    public static Int32 mouseLocalY()
    {
        ret QTHost.ffiMouseY() - 10 + 52
    }

    public static Int32 mouseDown( Int32 button )
    {
        ret QTHost.ffiMouseButton( button )
    }

    public static Int32 mouseWheelTake()
    {
        ret QTHost.ffiMouseWheelTake()
    }

    # +16/+60 抵消 updateRenderTarget 的信息条扣除 → 渲染目标 = canvas 属性
    public static Int32 windowW()
    {
        ret QTHost.ffiWebWinWidth() + 16
    }

    public static Int32 windowH()
    {
        ret QTHost.ffiWebWinHeight() + 60
    }

    # web：画布尺寸由页面 JS 控制，无需同步 label 几何
    public static void resizeView( Int32 w, Int32 h )
    {
    }

    # ── wasm 主循环（SceneDemoWeb.sp 入口转发到这里；sp 无 import 平面，
    #    不能直接调 Console/OS）──────────────────────────────────────
    # gles 后端（wasm 注册表唯一后端）+ 桌面同款 run()（装配引擎/菜单/
    # 场景 4，startHost 为 web 桩 no-op）+ frameTick 泵帧（键鼠读引擎
    # 输入表，渲染经 sle_web_blit 上屏；16ms ASYNCIFY 让出事件循环）。
    public static void pumpWeb()
    {
        SceneDemo.preferredBackend = "gles"
        SceneDemo.run()
        Console.println( "[SceneDemoWeb] pump start" )
        bool running = true
        while running
        {
            SceneDemo.frameTick()
            OS.Timer.sleep( 16 )
        }
    }
}
