import SimGameEngine;
import Std;
import Math;
import Core;

# WebHost - web 平台宿主层（桌面 QTHost 的 web 等价物，2026-11-22）。
# 职责（与桌面 QTHost 对齐，全部是宿主职责而非游戏逻辑）：
#   1. 持有引擎系统：Application（统一时间/固定步长/生命周期）、
#      RenderSystem（gles 后端 → WebGL2）、InputSystem、Scene；
#   2. 泵帧：app.tick(-1) 实测 dt → Behaviour 生命周期（等价桌面
#      QT QTimer(16) → frameTick）；
#   3. 呈现：rs.frame readback RGBA8 → sle_web_blit → JS texImage2D
#      （等价桌面 QTHost.blit 上 QLabel；像素块由引擎 C 管线产出）；
#   4. 帧尾 input.endFrame + 16ms 让出（ASYNCIFY 挂起 wasm，浏览器
#      事件循环继续跑 rAF/键盘/音频）。
# 游戏逻辑层（SnakeGameBehaviour）只走引擎 API，对本类零依赖。
public class WebHost
{
    static Application app = null
    static Scene hostScene = null
    static RenderSystem hostRs = null
    static InputSystem hostInput = null
    static SnakeGameBehaviour game = null
    static Int64 pixels = 0
    static Int32 renderW = 320
    static Int32 renderH = 320
    static Int32 frameNo = 0

    # wasm 平台桥（sl_sim_engine_lib 编进二进制；dlopen(NULL) 自解析）。
    # 仅宿主层使用 —— 游戏层不得触碰呈现桥。
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

    public static void run()
    {
        # ── 引擎系统创建（顺序与桌面 SnakeGame.start 同构）────────
        # 显式选 GLES 后端（wasm 注册表仅含 gles；与 SceneDemo.webInit
        # 的 initializeBackend 模式一致，错误串可读）
        bool bok = SLang.Render.initializeBackend( "gles" )
        Console.println( "[WebHost] initializeBackend(gles) -> " + bok.toString() +
            " err=" + SLang.Render.errorString() )
        RenderSystem rs = RenderSystem()
        bool rok = rs.init( renderW, renderH )
        Console.println( "[WebHost] RenderSystem.init -> " + rok.toString() +
            " err=" + rs.lastError )
        rs.cameraCenter = Float32_3( 80.0f, 80.0f, 0.0f )
        # viewSize = 纵向半高（桌面同款）：16×16 网格（160）四周留边，
        # 顶部边距容纳 FairyGUI HUD 顶栏
        rs.viewSize = 100.0f
        hostRs = rs
        Scene sc = Scene( "SnakeWeb" )
        hostScene = sc
        InputSystem inp = InputSystem()
        hostInput = inp
        # ── 游戏逻辑层挂载（Behaviour 组件；构造器 + addComponent，
        #    doc/10 §6：跨模块静态工厂不可用）────────────────────
        GameObject gameGo = sc.createObject( "SnakeGameRoot" )
        SnakeGameBehaviour gb = SnakeGameBehaviour()
        # 注入引擎系统（static 字段直赋；addComponent 前）
        SnakeGameBehaviour.rs = rs
        SnakeGameBehaviour.input = inp
        SnakeGameBehaviour.scene = sc
        gameGo.addComponent( gb )
        game = gb
        # ── Application：统一时间/生命周期全由引擎驱动 ────────────
        Application a = Application()
        a.init()
        a.loadScene( sc )
        app = a
        pixels = Memory.alloc( renderW * renderH * 4 )
        Console.println( "[WebHost] pump start (tick/sync/frame/blit @16ms)" )
        bool running = true
        while running
        {
            # 引擎泵：C 单调钟实测 dt → fixedUpdate×N → start/update/lateUpdate
            a.tick( 0 - 1.0f )
            frameNo = frameNo + 1
            if frameNo == 1 || frameNo == 2 || frameNo == 30 || frameNo == 120
            {
                Float32 dbgDt = a.deltaTime
                string dbgScene = "null"
                if a.activeScene != null
                {
                    dbgScene = a.activeScene.name
                }
                Console.println( "[WebHost] frame " + frameNo.toString() +
                    " dt=" + dbgDt.toString() + " scene=" + dbgScene +
                    " clockMs=" + EngineClock.nowMs().toString() )
            }
            # 呈现：像素 readback → JS 上屏（引擎 C 管线 13 阶段产出）
            Int64 pix = pixels
            Int32 w2 = renderW
            Int32 h2 = renderH
            hostRs.frame( 0.0f, pix )
            WebHost.ffiWebBlit( pix, w2, h2 )
            # 帧尾清输入边沿（桌面 frameTick 尾部同款）
            inp.endFrame()
            # 16ms 让出事件循环（ASYNCIFY；桌面 = QT QTimer 节拍）
            OS.Timer.sleep( 16 )
        }
    }
}
