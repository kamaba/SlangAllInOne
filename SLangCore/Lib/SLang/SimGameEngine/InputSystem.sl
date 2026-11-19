import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# InputSystem —— 输入系统（2026-11-17，SnakeGame 落地专用）
# ----------------------------------------------------------------------------
# 数据面在 C（sl_sim_engine_lib 输入状态表：down/pressed 双区，256 槽），
# 注入方 = QT 宿主键盘回调（QKeyEvent::key() 的 Qt::Key 枚举值），
# 查询方 = 游戏逻辑（isDown 持续态 / wasPressed 本帧边沿）。
# 键码约定（Qt::Key）：字母 A..Z = 0x41..0x5A（与 ASCII 同）、数字 0..9 =
# 0x30..0x39、方向键族（0x01000000+）由 C 侧压缩映射到 128+ 槽。
# 帧尾必须调 endFrame() 清边沿（游戏主循环每帧一次）。
# 本类是纯门面（无计算——重计算才下沉 C，输入是薄状态表，但表本体在 C
# 便于 QT 宿主侧无 VM 重入地写入）。
# 用法（SnakeGame 同款）：
#   InputSystem input = InputSystem()
#   if input.wasPressed( Key.W ) ...     # 边沿（本帧刚按下）
#   if input.isDown( Key.W ) ...         # 持续态
#   ...帧末 input.endFrame()
# ============================================================================
public class InputSystem
{
    # 键码常量（Qt::Key 子集；static Int32 常量**不作实参**——仅用于
    # 逻辑比较（doc/18 §4 坑族），比较两侧局部变量形态可靠）
    public static Int32 KEY_W = 87
    public static Int32 KEY_A = 65
    public static Int32 KEY_S = 83
    public static Int32 KEY_D = 68
    public static Int32 KEY_LEFT = 16777234    # Qt::Key_Left  = 0x01000012
    public static Int32 KEY_RIGHT = 16777236   # Qt::Key_Right = 0x01000014
    public static Int32 KEY_UP = 16777235      # Qt::Key_Up    = 0x01000013
    public static Int32 KEY_DOWN = 16777237    # Qt::Key_Down  = 0x01000015
    public static Int32 KEY_SPACE = 32
    public static Int32 KEY_ESCAPE = 16777216  # Qt::Key_Escape = 0x01000000
    public static Int32 KEY_CTRL = 16777249    # Qt::Key_Control = 0x01000021
    public static Int32 KEY_F12 = 16777334     # Qt::Key_F12    = 0x01000076
    public static Int32 KEY_HOME = 16777232    # Qt::Key_Home   = 0x01000010

    public bool isDown( Int32 key )
    {
        Int32 v = EngineFfi.libInputDown( key )
        ret v == 1
    }

    public bool wasPressed( Int32 key )
    {
        Int32 v = EngineFfi.libInputPressed( key )
        ret v == 1
    }

    public void setKey( Int32 key, bool down )
    {
        Int32 d = 0
        if down
        {
            d = 1
        }
        EngineFfi.libInputSetKey( key, d )
    }

    # ── 鼠标（2026-11-19 统一输入桥）────────────────────────────
    # 注入方 = QT 宿主桥（QTHost.pumpMouse 每帧采样 QT 轮询 FFI 写入
    # C 表）；查询方 = 游戏逻辑。按钮号 1=左 2=右；坐标 = 窗口客户区
    # 像素；滚轮 take 读后清零；按下边沿 endFrame 同步清。
    public static Int32 MOUSE_LEFT = 1
    public static Int32 MOUSE_RIGHT = 2

    public bool mouseDown( Int32 button )
    {
        Int32 v = EngineFfi.libMouseButton( button )
        ret v == 1
    }

    public bool mousePressed( Int32 button )
    {
        Int32 v = EngineFfi.libMousePressed( button )
        ret v == 1
    }

    public Int32 mouseX()
    {
        ret EngineFfi.libMouseX()
    }

    public Int32 mouseY()
    {
        ret EngineFfi.libMouseY()
    }

    public Int32 mouseWheelTake()
    {
        ret EngineFfi.libMouseWheelTake()
    }

    # ── 注入侧（宿主桥专用；游戏逻辑不走这里）───────────
    public void setMouseButton( Int32 button, bool down )
    {
        Int32 d = 0
        if down
        {
            d = 1
        }
        EngineFfi.libInputSetMouseButton( button, d )
    }

    public void setMousePos( Int32 x, Int32 y )
    {
        EngineFfi.libInputSetMousePos( x, y )
    }

    public void addMouseWheel( Int32 delta )
    {
        EngineFfi.libInputSetMouseWheel( delta )
    }

    # 帧尾清边沿（游戏主循环每帧末调一次；键盘+鼠标按下边沿一并清）
    public void endFrame()
    {
        EngineFfi.libInputEndFrame()
    }
}
