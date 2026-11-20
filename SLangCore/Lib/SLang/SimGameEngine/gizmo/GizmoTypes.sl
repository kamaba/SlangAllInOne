import Core;
import Std;
import Math;

# ============================================================================
# GizmoTypes — 编辑器 Gizmo 常量表（Unity 风格编辑态渲染，doc/21）
# ----------------------------------------------------------------------------
# 纯常量层：变换模式 / 轴枚举 / 图标类型 / 调色板。
# 颜色用 static 方法返回 Float32_3（Float32_3 静态字段初始化在 Front 未实证，
# 参照 Float32_3.zero 的 getter 形态改为方法，调用方落局部变量即可）。
# 本类零 C 依赖、零跨模块调用，任何模块可直接引用。
# ============================================================================
public class GizmoTypes
{
    # ── 变换模式 ─────────────────────────────────────────
    public static Int32 MODE_NONE = 0
    public static Int32 MODE_MOVE = 1
    public static Int32 MODE_ROTATE = 2
    public static Int32 MODE_SCALE = 3

    # ── 轴 ───────────────────────────────────────────────
    public static Int32 AXIS_X = 0
    public static Int32 AXIS_Y = 1
    public static Int32 AXIS_Z = 2

    # ── 图标类型（给 GizmoGeometry.icon 使用）───────────
    public static Int32 ICON_CAMERA_2D = 10
    public static Int32 ICON_CAMERA_3D = 11
    public static Int32 ICON_LIGHT_DIR = 12
    public static Int32 ICON_LIGHT_POINT = 13
    public static Int32 ICON_LIGHT_SPOT = 14

    # ── 光源子类型（与 Light.TYPE_* 数值一致）────────────
    public static Int32 LIGHT_DIRECTIONAL = 0
    public static Int32 LIGHT_POINT = 1
    public static Int32 LIGHT_SPOT = 2

    # ── 数学常量 ─────────────────────────────────────────
    public static Float32 PI = 3.14159265f

    # ── 调色板（Unity 编辑器风格）────────────────────────
    public static Float32_3 colorX()
    {
        ret Float32_3( 0.92f, 0.16f, 0.18f )
    }

    public static Float32_3 colorY()
    {
        ret Float32_3( 0.20f, 0.80f, 0.24f )
    }

    public static Float32_3 colorZ()
    {
        ret Float32_3( 0.20f, 0.42f, 0.95f )
    }

    public static Float32_3 colorNeutral()
    {
        ret Float32_3( 0.82f, 0.82f, 0.86f )
    }

    public static Float32_3 colorHighlight()
    {
        ret Float32_3( 0.98f, 0.82f, 0.18f )
    }

    public static Float32_3 colorCamera()
    {
        ret Float32_3( 0.35f, 0.85f, 0.90f )
    }

    public static Float32_3 colorLight()
    {
        ret Float32_3( 0.98f, 0.86f, 0.22f )
    }
}
