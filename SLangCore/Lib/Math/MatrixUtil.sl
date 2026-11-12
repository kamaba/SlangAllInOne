# =========================================================================
# MatrixUtil.sl —— Float32 矩阵静态工具门面（自 SLangRender\Matrix.sl 迁入）
#
# 约定：统一使用 Float32 系列类型
#   矩阵 -> Float32_3x3 / Float32_4x4，函数 -> Mathf.*
# 与通用稠密矩阵 Matrix（Matrix.sl）互补：Matrix 面向任意行列的通用运算，
# MatrixUtil 面向渲染常用的 3x3/4x4 快捷构造、TRS 组合与视图/投影。
# 自有实现的方法：fromEuler / trs(Quaternion) / inverseRigid /
# perspectiveDegrees，其余为 Float32_3x3 / Float32_4x4 静态方法的转发门面。
# =========================================================================

public class MatrixUtil
{
    # ── 3x3 ──────────────────────────────────────────────
    public static get Float32_3x3 identity3()
    {
        ret Float32_3x3.identity()
    }

    public static Float32_3x3 rotationX3( Float32 radians )
    {
        ret Float32_3x3.rotationX( radians )
    }

    public static Float32_3x3 rotationY3( Float32 radians )
    {
        ret Float32_3x3.rotationY( radians )
    }

    public static Float32_3x3 rotationZ3( Float32 radians )
    {
        ret Float32_3x3.rotationZ( radians )
    }

    public static Float32_3x3 scale2( Float32 sx, Float32 sy )
    {
        ret Float32_3x3.scale( sx, sy )
    }

    public static Float32_3x3 translation2( Float32 tx, Float32 ty )
    {
        ret Float32_3x3.translation( tx, ty )
    }

    public static Float32_3x3 transpose3( Float32_3x3 m )
    {
        ret m.transpose()
    }

    public static Float32_3x3 inverse3( Float32_3x3 m )
    {
        ret m.inverse()
    }

    # ── 4x4 构造 ─────────────────────────────────────────
    public static get Float32_4x4 identity()
    {
        ret Float32_4x4.identity()
    }

    public static Float32_4x4 translation( Float32_3 t )
    {
        ret Float32_4x4.translation( t )
    }

    public static Float32_4x4 scale( Float32_3 s )
    {
        ret Float32_4x4.scale( s )
    }

    public static Float32_4x4 scale( Float32 s )
    {
        ret Float32_4x4.scale( s, s, s )
    }

    public static Float32_4x4 rotationX( Float32 radians )
    {
        ret Float32_4x4.rotationX( radians )
    }

    public static Float32_4x4 rotationY( Float32 radians )
    {
        ret Float32_4x4.rotationY( radians )
    }

    public static Float32_4x4 rotationZ( Float32 radians )
    {
        ret Float32_4x4.rotationZ( radians )
    }

    public static Float32_4x4 rotationAxis( Float32_3 axis, Float32 radians )
    {
        ret Float32_4x4.rotationAxis( axis, radians )
    }

    # 注：fromQuaternion / trs(., Quaternion, .) 随 Quaternion 启用（2026-11-12）
    # 恢复迁入，依赖 q.toFloat32_4x4()。

    # 由四元数构造旋转矩阵
    public static Float32_4x4 fromQuaternion( Quaternion q )
    {
        ret q.toFloat32_4x4()
    }

    # 组合：translation * rotation * scale（四元数旋转版）
    public static Float32_4x4 trs( Float32_3 translation, Quaternion rotation, Float32_3 scale )
    {
        Float32_4x4 r = fromQuaternion( rotation )
        ret Float32_4x4.translation( translation ).multiply( r ).multiply( Float32_4x4.scale( scale ) )
    }

    # 由欧拉角（弧度）构造旋转矩阵
    public static Float32_4x4 fromEuler( Float32_3 eulerRadians )
    {
        Float32_4x4 ry = Float32_4x4.rotationY( eulerRadians.y )
        Float32_4x4 rx = Float32_4x4.rotationX( eulerRadians.x )
        Float32_4x4 rz = Float32_4x4.rotationZ( eulerRadians.z )
        ret ry.multiply( rx ).multiply( rz )
    }

    # 组合：translation * rotation * scale
    public static Float32_4x4 trs( Float32_3 translation, Float32_3 rotationEuler, Float32_3 scale )
    {
        ret Float32_4x4.trs( translation, rotationEuler, scale )
    }

    # ── 4x4 运算 ─────────────────────────────────────────
    public static Float32_4x4 multiply( Float32_4x4 a, Float32_4x4 b )
    {
        ret a.multiply( b )
    }

    public static Float32_4x4 transpose( Float32_4x4 m )
    {
        ret m.transpose()
    }

    # 刚体变换（仅旋转 + 平移）求逆，比通用求逆更快更稳定
    public static Float32_4x4 inverseRigid( Float32_4x4 m )
    {
        # 取 3x3 旋转部分与平移列
        Float32 m00 = m.getValue( 0, 0 )
        Float32 m01 = m.getValue( 0, 1 )
        Float32 m02 = m.getValue( 0, 2 )
        Float32 m10 = m.getValue( 1, 0 )
        Float32 m11 = m.getValue( 1, 1 )
        Float32 m12 = m.getValue( 1, 2 )
        Float32 m20 = m.getValue( 2, 0 )
        Float32 m21 = m.getValue( 2, 1 )
        Float32 m22 = m.getValue( 2, 2 )
        Float32 tx = m.getValue( 0, 3 )
        Float32 ty = m.getValue( 1, 3 )
        Float32 tz = m.getValue( 2, 3 )

        Float32_4x4 rm = Float32_4x4()
        # 转置旋转部分（R^T）
        rm.setValue( 0, 0, m00 )
        rm.setValue( 0, 1, m10 )
        rm.setValue( 0, 2, m20 )
        rm.setValue( 1, 0, m01 )
        rm.setValue( 1, 1, m11 )
        rm.setValue( 1, 2, m21 )
        rm.setValue( 2, 0, m02 )
        rm.setValue( 2, 1, m12 )
        rm.setValue( 2, 2, m22 )
        # 平移部分 = -R^T * t
        rm.setValue( 0, 3, 0.0f - ( m00 * tx + m10 * ty + m20 * tz ) )
        rm.setValue( 1, 3, 0.0f - ( m01 * tx + m11 * ty + m21 * tz ) )
        rm.setValue( 2, 3, 0.0f - ( m02 * tx + m12 * ty + m22 * tz ) )
        rm.setValue( 3, 3, 1.0f )
        ret rm
    }

    # ── 视图 / 投影 ──────────────────────────────────────
    public static Float32_4x4 lookAt( Float32_3 eye, Float32_3 target, Float32_3 upHint )
    {
        ret Float32_4x4.lookAt( eye, target, upHint )
    }

    # 透视投影：fovY 为弧度（垂直视场角）
    public static Float32_4x4 perspective( Float32 fovYRadians, Float32 aspect, Float32 near, Float32 far )
    {
        ret Float32_4x4.perspective( fovYRadians, aspect, near, far )
    }

    # 透视投影：fovY 为角度（度），便于配置
    public static Float32_4x4 perspectiveDegrees( Float32 fovYDegrees, Float32 aspect, Float32 near, Float32 far )
    {
        ret Float32_4x4.perspective( Mathf.radians( fovYDegrees ), aspect, near, far )
    }

    public static Float32_4x4 ortho( Float32 left, Float32 right, Float32 bottom, Float32 top, Float32 near, Float32 far )
    {
        ret Float32_4x4.ortho( left, right, bottom, top, near, far )
    }

    # ── 变换应用 ─────────────────────────────────────────
    public static Float32_3 transformPoint( Float32_4x4 m, Float32_3 p )
    {
        ret m.transformPoint( p )
    }

    public static Float32_3 transformDirection( Float32_4x4 m, Float32_3 v )
    {
        ret m.transformDirection( v )
    }

    override string toString()
    {
        ret "MatrixUtil(static utility)"
    }
}
