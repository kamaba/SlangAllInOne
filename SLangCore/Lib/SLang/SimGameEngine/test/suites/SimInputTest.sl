import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimInputTest — InputSystem 统一输入验证（第 16 套，2026-11-19）
# ----------------------------------------------------------------------------
# 数据面 = C 输入状态表（键盘 down/pressed 双区 + 鼠标按钮/坐标/滚轮）。
# 覆盖：按下沿 / 持续态 / QT 自动重复去重（按住连发不破坏边沿语义）/
# endFrame 清边沿 / 鼠标按钮与按下沿 / 坐标读写 / 滚轮累计与 take /
# Enter 等压缩槽键码。
# 写法约束（doc/10 §6）：常量不作实参（先落局部变量）；triple && 拆分。
# ============================================================================

public class SimInputTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    # ── I1. 键盘按下沿 + 持续态 ─────────────────────────
    static void testKeyEdge()
    {
        InputSystem input = InputSystem()
        Int32 kw = InputSystem.KEY_W
        input.setKey( kw, true )
        check( input.isDown( kw ), "I1a down after press" )
        check( input.wasPressed( kw ), "I1b pressed edge on press" )
        # 自动重复（按住连发 down=1）：不得重复置边沿
        input.setKey( kw, true )
        input.setKey( kw, true )
        input.endFrame()
        check( input.isDown( kw ), "I1c down persists across endFrame" )
        check( !input.wasPressed( kw ), "I1d auto-repeat does not re-set edge" )
        # 释放：down 清、边沿不受影响
        input.setKey( kw, false )
        check( !input.isDown( kw ), "I1e down cleared on release" )
        check( !input.wasPressed( kw ), "I1f no edge on release" )
        input.endFrame()
    }

    # ── I2. 再次按下产生新边沿（跨帧语义）───────────────
    static void testRepress()
    {
        InputSystem input = InputSystem()
        Int32 ks = InputSystem.KEY_SPACE
        input.setKey( ks, true )
        input.endFrame()
        check( !input.wasPressed( ks ), "I2a edge cleared by endFrame" )
        check( input.isDown( ks ), "I2b down persists" )
        input.setKey( ks, false )
        input.endFrame()
        input.setKey( ks, true )
        check( input.wasPressed( ks ), "I2c re-press sets fresh edge" )
        input.endFrame()
    }

    # ── I3. 压缩槽键码（Enter/方向键族）─────────────────
    static void testMappedKeys()
    {
        InputSystem input = InputSystem()
        Int32 kEnt = 16777220
        Int32 kUp = InputSystem.KEY_UP
        input.setKey( kEnt, true )
        input.setKey( kUp, true )
        check( input.isDown( kEnt ), "I3a Enter (0x01000004) mapped" )
        check( input.wasPressed( kEnt ), "I3b Enter edge" )
        check( input.isDown( kUp ), "I3c Up mapped" )
        input.endFrame()
        input.setKey( kEnt, false )
        input.setKey( kUp, false )
        check( !input.isDown( kEnt ), "I3d Enter released" )
        input.endFrame()
    }

    # ── I4. 鼠标按钮 + 按下沿 ───────────────────────────
    static void testMouseButton()
    {
        InputSystem input = InputSystem()
        Int32 btnL = InputSystem.MOUSE_LEFT
        Int32 btnR = InputSystem.MOUSE_RIGHT
        input.setMouseButton( btnL, true )
        check( input.mouseDown( btnL ), "I4a left down" )
        check( input.mousePressed( btnL ), "I4b left pressed edge" )
        # 重复注入 down=true（同帧重复采样）不重复置边沿
        input.setMouseButton( btnL, true )
        input.endFrame()
        check( input.mouseDown( btnL ), "I4c left down persists" )
        check( !input.mousePressed( btnL ), "I4d edge cleared" )
        input.setMouseButton( btnL, false )
        check( !input.mouseDown( btnL ), "I4e left released" )
        # 右键独立
        input.setMouseButton( btnR, true )
        check( input.mouseDown( btnR ), "I4f right independent" )
        check( !input.mouseDown( btnL ), "I4g left unaffected" )
        input.endFrame()
        input.setMouseButton( btnR, false )
        input.endFrame()
    }

    # ── I5. 鼠标坐标 + 滚轮累计/take ────────────────────
    static void testMousePosWheel()
    {
        InputSystem input = InputSystem()
        input.setMousePos( 123, 45 )
        Int32 mx = input.mouseX()
        Int32 my = input.mouseY()
        check( mx == 123, "I5a mouse x" )
        check( my == 45, "I5b mouse y" )
        input.addMouseWheel( 2 )
        input.addMouseWheel( 1 )
        Int32 took = input.mouseWheelTake()
        check( took == 3, "I5c wheel accumulated" )
        Int32 took2 = input.mouseWheelTake()
        check( took2 == 0, "I5d take clears" )
        input.endFrame()
    }

    # ── I6. 统一时间线形态：帧首注入 → 帧内消费 → 帧尾清 ─
    static void testFramePipeline()
    {
        InputSystem input = InputSystem()
        Int32 kd = InputSystem.KEY_D
        Int32 btnL = InputSystem.MOUSE_LEFT
        # 帧间事件（宿主桥注入）
        input.setKey( kd, true )
        input.setMouseButton( btnL, true )
        input.setMousePos( 50, 60 )
        # 帧内消费
        bool kdEdge = input.wasPressed( kd )
        bool mEdge = input.mousePressed( btnL )
        Int32 mx = input.mouseX()
        check( kdEdge && mEdge, "I6a edges visible in frame" )
        check( mx == 50, "I6b pos visible in frame" )
        # 帧尾收口：边沿全清、持续态保留
        input.endFrame()
        bool kdDown = input.isDown( kd )
        bool mDown = input.mouseDown( btnL )
        bool kdEdge2 = input.wasPressed( kd )
        bool mEdge2 = input.mousePressed( btnL )
        bool clean = ( kdDown ) && ( mDown ) && ( !kdEdge2 ) && ( !mEdge2 )
        check( clean, "I6c endFrame: states persist, edges cleared" )
        input.setKey( kd, false )
        input.setMouseButton( btnL, false )
        input.endFrame()
    }

    public static void run()
    {
        Console.println( "=== SimInputTest (unified input pipeline) ===" )
        testKeyEdge()
        testRepress()
        testMappedKeys()
        testMouseButton()
        testMousePosWheel()
        testFramePipeline()
        Console.println( "PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }

    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }
}
