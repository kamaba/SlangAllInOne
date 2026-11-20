import Core;
import Std;
import Math;

# ============================================================================
# GizmoGeometry — 编辑器 Gizmo 纯几何生成器（doc/21，零 C 改动）
# ----------------------------------------------------------------------------
# 全部为 static 几何函数：输入 List<Float32_3> 目标缓冲 + 中心/尺寸/方向，
# 追加模型空间三角形顶点（每 3 顶点一个三角形）。线段/圆环一律用细长
# 四边形与三角扇近似——现有渲染库无线段图元，MeshRef.hasVertexData 烘焙
# 路径是唯一稳妥出口（与 SceneDemo 临时坐标轴同款）。
#
# 写法约束（doc/10 §6）：所有向量加法用显式分量辅助 add3/sub3（不依赖
# 运算符重载解析）；方法调用结果先落局部变量再参与运算；List 下标先落
# 局部变量；循环下界用 Int32，浮点循环变量先落局部再 toFloat32。
# 本类无状态、无跨模块调用，可独立单测（SimGizmoTest）。
# ============================================================================
public class GizmoGeometry
{
    # ── 显式分量运算（规避运算符重载解析差异）────────────
    static Float32_3 add3( Float32_3 a, Float32_3 b )
    {
        ret Float32_3( a.x + b.x, a.y + b.y, a.z + b.z )
    }

    static Float32_3 sub3( Float32_3 a, Float32_3 b )
    {
        ret Float32_3( a.x - b.x, a.y - b.y, a.z - b.z )
    }

    static void tri( List<Float32_3> dst, Float32_3 a, Float32_3 b, Float32_3 c )
    {
        dst.add( a )
        dst.add( b )
        dst.add( c )
    }

    # 细长四边形线段（a→b，side 为平面内侧向单位向量，hw = 半宽）
    static void seg( List<Float32_3> dst, Float32_3 a, Float32_3 b,
        Float32_3 side, Float32 hw )
    {
        Float32_3 o = side.scale( hw )
        Float32_3 a0 = add3( a, o )
        Float32_3 a1 = sub3( a, o )
        Float32_3 b0 = add3( b, o )
        Float32_3 b1 = sub3( b, o )
        tri( dst, a0, b0, b1 )
        tri( dst, a0, b1, a1 )
    }

    # 以 center 为中心、side/upv 为两正交轴的正方形面（billboard 方块）
    static void box( List<Float32_3> dst, Float32_3 center,
        Float32_3 side, Float32_3 upv, Float32 hh )
    {
        Float32_3 ss = side.scale( hh )
        Float32_3 uu = upv.scale( hh )
        Float32_3 p0 = add3( add3( center, ss ), uu )
        Float32_3 p1 = add3( sub3( center, ss ), uu )
        Float32_3 p2 = sub3( sub3( center, ss ), uu )
        Float32_3 p3 = sub3( add3( center, ss ), uu )
        tri( dst, p0, p1, p2 )
        tri( dst, p0, p2, p3 )
    }

    # 圆环上一点：center + u*(cos*t*r) + v*(sin*t*r)
    static Float32_3 ringPoint( Float32_3 center, Float32_3 u, Float32_3 v,
        Float32 c, Float32 s, Float32 r )
    {
        Float32 ku = c * r
        Float32 kv = s * r
        Float32_3 pu = u.scale( ku )
        Float32_3 pv = v.scale( kv )
        ret add3( add3( center, pu ), pv )
    }

    # 为给定法线选一组平面正交基 (u, v)；避免 u 与法线平行退化
    static Float32_3 planeU( Float32_3 normal )
    {
        Float32_3 refv = Float32_3( 0.0f, 1.0f, 0.0f )
        Float32 ny2 = normal.y * normal.y
        if ny2 > 0.81f
        {
            refv = Float32_3( 1.0f, 0.0f, 0.0f )
        }
        Float32_3 raw = normal.cross( refv )
        ret raw.normalize()
    }

    # ── 方向箭头（杆 + 三角箭头）────────────────────────
    # dir/up 需已归一化且近似正交；len 全长，width 杆宽
    public static void arrow( List<Float32_3> dst, Float32_3 org,
        Float32_3 dir, Float32_3 up, Float32 len, Float32 width )
    {
        Float32_3 cr = dir.cross( up )
        Float32_3 side = cr.normalize()
        Float32 hw = width * 0.5f
        Float32 rodLen = len * 0.68f
        Float32_3 rodEnd = add3( org, dir.scale( rodLen ) )
        GizmoGeometry.seg( dst, org, rodEnd, side, hw )
        # 箭头菱形（两三角形），宽度放大 1.8×
        Float32_3 tip = add3( org, dir.scale( len ) )
        Float32_3 w = side.scale( width * 0.9f )
        Float32_3 c0 = add3( rodEnd, w )
        Float32_3 c1 = sub3( rodEnd, w )
        tri( dst, c0, tip, c1 )
        tri( dst, c0, c1, rodEnd )
    }

    # ── 旋转圆环（绕法线 normal 的平面，三角带近似）──────
    public static void ring( List<Float32_3> dst, Float32_3 center,
        Float32_3 normal, Float32 radius, Float32 thickness, Int32 segments )
    {
        if segments < 3
        {
            segments = 3
        }
        Float32_3 u = GizmoGeometry.planeU( normal )
        Float32_3 vu = normal.cross( u )
        Float32_3 v = vu.normalize()
        Float32 ro = radius + thickness * 0.5f
        Float32 ri = radius - thickness * 0.5f
        if ri < 0.0f
        {
            ri = 0.0f
        }
        Int32 i = 0
        while i < segments
        {
            Int32 j = i + 1
            Float32 t0 = 6.28318531f * i.toFloat32() / segments.toFloat32()
            Float32 t1 = 6.28318531f * j.toFloat32() / segments.toFloat32()
            Float32 c0 = Mathf.cos( t0 )
            Float32 s0 = Mathf.sin( t0 )
            Float32 c1 = Mathf.cos( t1 )
            Float32 s1 = Mathf.sin( t1 )
            Float32_3 p0 = GizmoGeometry.ringPoint( center, u, v, c0, s0, ro )
            Float32_3 p1 = GizmoGeometry.ringPoint( center, u, v, c1, s1, ro )
            Float32_3 q0 = GizmoGeometry.ringPoint( center, u, v, c0, s0, ri )
            Float32_3 q1 = GizmoGeometry.ringPoint( center, u, v, c1, s1, ri )
            tri( dst, p0, p1, q1 )
            tri( dst, p0, q1, q0 )
            i = i + 1
        }
    }

    # ── 缩放手柄（杆 + 末端方块）────────────────────────
    public static void scaleHandle( List<Float32_3> dst, Float32_3 org,
        Float32_3 dir, Float32_3 up, Float32 len, Float32 width )
    {
        Float32_3 cr = dir.cross( up )
        Float32_3 side = cr.normalize()
        Float32 hw = width * 0.5f
        Float32 rodLen = len * 0.80f
        Float32_3 rodEnd = add3( org, dir.scale( rodLen ) )
        GizmoGeometry.seg( dst, org, rodEnd, side, hw )
        Float32_3 other = side.cross( dir )
        Float32_3 otherN = other.normalize()
        GizmoGeometry.box( dst, rodEnd, side, otherN, width * 0.9f )
    }

    # ── 相机图标（2D：小方块 + 视锥梯形；3D：加中轴线）──
    public static void cameraIcon2D( List<Float32_3> dst, Float32_3 center, Float32 size )
    {
        Float32_3 ex = Float32_3( 1.0f, 0.0f, 0.0f )
        Float32_3 ey = Float32_3( 0.0f, 1.0f, 0.0f )
        Float32_3 bodyC = add3( center, ex.scale( 0.0f - size * 0.26f ) )
        GizmoGeometry.box( dst, bodyC, ex, ey, size * 0.22f )
        # 视锥两条斜边 + 远端横线
        Float32_3 near0 = add3( center, ex.scale( size * 0.02f ) )
        Float32_3 farC = add3( center, ex.scale( size * 0.78f ) )
        Float32_3 farTop = add3( farC, ey.scale( size * 0.46f ) )
        Float32_3 farBot = add3( farC, ey.scale( 0.0f - size * 0.46f ) )
        Float32_3 alongY = ex.cross( ey )
        Float32_3 side = alongY.normalize()
        GizmoGeometry.seg( dst, near0, farTop, side, size * 0.028f )
        GizmoGeometry.seg( dst, near0, farBot, side, size * 0.028f )
        GizmoGeometry.seg( dst, farTop, farBot, side, size * 0.028f )
    }

    public static void cameraIcon3D( List<Float32_3> dst, Float32_3 center, Float32 size )
    {
        GizmoGeometry.cameraIcon2D( dst, center, size )
        # 3D 额外：相机到视锥中心的中轴线（用 Y 作厚度方向，正交镜头下可见）
        Float32_3 ex = Float32_3( 1.0f, 0.0f, 0.0f )
        Float32_3 ey = Float32_3( 0.0f, 1.0f, 0.0f )
        Float32_3 nearC = add3( center, ex.scale( size * 0.02f ) )
        Float32_3 farC = add3( center, ex.scale( size * 0.78f ) )
        GizmoGeometry.seg( dst, nearC, farC, ey, size * 0.022f )
    }

    # ── 光照图标（太阳/点光放射线 + 聚光锥）──────────────
    public static void lightIcon( List<Float32_3> dst, Float32_3 center,
        Float32 size, Int32 lightType, bool is2D )
    {
        Float32_3 nrm = Float32_3( 0.0f, 0.0f, 1.0f )
        GizmoGeometry.ring( dst, center, nrm, size * 0.26f, size * 0.07f, 12 )
        Int32 rays = 8
        if lightType == GizmoTypes.LIGHT_POINT
        {
            rays = 12
        }
        if lightType == GizmoTypes.LIGHT_SPOT
        {
            rays = 6
        }
        Int32 i = 0
        while i < rays
        {
            Float32 ang = 6.28318531f * i.toFloat32() / rays.toFloat32()
            Float32 cs = Mathf.cos( ang )
            Float32 sn = Mathf.sin( ang )
            Float32_3 dir = Float32_3( cs, sn, 0.0f )
            Float32_3 side = Float32_3( 0.0f - sn, cs, 0.0f )
            Float32_3 a = add3( center, dir.scale( size * 0.44f ) )
            Float32_3 b = add3( center, dir.scale( size * 0.72f ) )
            GizmoGeometry.seg( dst, a, b, side, size * 0.03f )
            i = i + 1
        }
        if lightType == GizmoTypes.LIGHT_SPOT
        {
            # 聚光锥：两条斜线收束到中心前方
            Float32_3 ex = Float32_3( 1.0f, 0.0f, 0.0f )
            Float32_3 ey = Float32_3( 0.0f, 1.0f, 0.0f )
            Float32_3 apex = add3( center, ex.scale( size * 0.85f ) )
            Float32_3 l0 = add3( center, ey.scale( size * 0.5f ) )
            Float32_3 l1 = add3( center, ey.scale( 0.0f - size * 0.5f ) )
            GizmoGeometry.seg( dst, l0, apex, ex, size * 0.03f )
            GizmoGeometry.seg( dst, l1, apex, ex, size * 0.03f )
        }
        if !is2D
        {
            # 3D 光源额外一圈（绕 Y 轴的环），与平面环交叉成球感
            Float32_3 ny = Float32_3( 0.0f, 1.0f, 0.0f )
            GizmoGeometry.ring( dst, center, ny, size * 0.26f, size * 0.05f, 12 )
        }
    }

    # ── 图标分发 ─────────────────────────────────────────
    public static void icon( List<Float32_3> dst, Int32 iconType,
        Float32_3 center, Float32 size, Int32 lightType )
    {
        if iconType == GizmoTypes.ICON_CAMERA_2D
        {
            GizmoGeometry.cameraIcon2D( dst, center, size )
        }
        elif iconType == GizmoTypes.ICON_CAMERA_3D
        {
            GizmoGeometry.cameraIcon3D( dst, center, size )
        }
        elif iconType == GizmoTypes.ICON_LIGHT_DIR
        {
            GizmoGeometry.lightIcon( dst, center, size, GizmoTypes.LIGHT_DIRECTIONAL, false )
        }
        elif iconType == GizmoTypes.ICON_LIGHT_POINT
        {
            GizmoGeometry.lightIcon( dst, center, size, GizmoTypes.LIGHT_POINT, false )
        }
        elif iconType == GizmoTypes.ICON_LIGHT_SPOT
        {
            GizmoGeometry.lightIcon( dst, center, size, GizmoTypes.LIGHT_SPOT, false )
        }
    }

    # ── 变换 Gizmo 分发：按 mode 向三色缓冲追加几何 ───────
    public static void transformGizmo( List<Float32_3> xb,
        List<Float32_3> yb, List<Float32_3> zb,
        Float32_3 center, Int32 mode, Float32 size )
    {
        Float32_3 ox = Float32_3( 1.0f, 0.0f, 0.0f )
        Float32_3 oy = Float32_3( 0.0f, 1.0f, 0.0f )
        Float32_3 oz = Float32_3( 0.0f, 0.0f, 1.0f )
        if mode == GizmoTypes.MODE_MOVE
        {
            GizmoGeometry.arrow( xb, center, ox, oy, size, size * 0.07f )
            GizmoGeometry.arrow( yb, center, oy, ox, size, size * 0.07f )
            GizmoGeometry.arrow( zb, center, oz, oy, size, size * 0.07f )
        }
        elif mode == GizmoTypes.MODE_ROTATE
        {
            GizmoGeometry.ring( xb, center, ox, size, size * 0.035f, 24 )
            GizmoGeometry.ring( yb, center, oy, size, size * 0.035f, 24 )
            GizmoGeometry.ring( zb, center, oz, size, size * 0.035f, 24 )
        }
        elif mode == GizmoTypes.MODE_SCALE
        {
            GizmoGeometry.scaleHandle( xb, center, ox, oy, size, size * 0.07f )
            GizmoGeometry.scaleHandle( yb, center, oy, ox, size, size * 0.07f )
            GizmoGeometry.scaleHandle( zb, center, oz, oy, size, size * 0.07f )
        }
    }

    # ── 工具：顶点是否全部有限（测试断言用）──────────────
    public static bool allFinite( List<Float32_3> v )
    {
        Int32 i = 0
        Int32 n = v.length
        while i < n
        {
            Float32_3 p = v[i]
            if p.x != p.x || p.y != p.y || p.z != p.z
            {
                ret false
            }
            i = i + 1
        }
        ret true
    }
}
