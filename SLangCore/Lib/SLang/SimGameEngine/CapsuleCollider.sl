import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# CapsuleCollider — 胶囊碰撞体（P3 补全，doc/11 §2）
# ----------------------------------------------------------------------------
# 形状：沿节点 local +Y 的线段（两端点 = center ± (0, height/2 - radius)）
# 加世界半径（radius × max 缩放分量，近似同 SphereCollider）。
# 窄相三对：
#   capsule/sphere — 线段最近点 + 球判定
#   capsule/capsule — 线段-线段最近点（Ericson 5.1.4）
#   capsule/box    — 三候选近似（线段对盒心投影点 + 两端帽心各做一次
#                    盒.closestPoint 球判定，取穿透最大者；精确 GJK 远期，
#                    与 MeshCollider 同族 doc/11 §2）
# 法线约定与既有碰撞体一致：info.normal 从 other 指向自身（B→A，doc/12 §4）。
# 数学注意：跨模块静态 dot(Float32_3,Float32_3) 不用——点积手工展开分量
# （doc/10 §6 跨模块静态非 string 参数坑的保守规避）。
# ============================================================================

public class CapsuleCollider extends Behaviour
{
    public bool isTrigger = false
    public Float32_3 center = Float32_3.zero()
    public Float32 radius = 0.5f
    # 总高（含两端半球），自动钳到 >= 2*radius
    public Float32 height = 2.0f
    # 世界缓存（refreshWorldBounds 回填）
    public Float32_3 worldA = Float32_3.zero()
    public Float32_3 worldB = Float32_3.zero()
    public Float32 worldRadius = 0.5f
    public Bounds worldBounds = Bounds()

    # 事件钩子（与 Box/Sphere 对齐；经 SystemSimEngineCallHook1/2 按名派发）
    public virtual void onCollisionEnter( Behaviour other, ContactInfo info )
    {
    }

    public virtual void onCollisionStay( Behaviour other, ContactInfo info )
    {
    }

    public virtual void onCollisionExit( Behaviour other )
    {
    }

    public virtual void onTriggerEnter( Behaviour other )
    {
    }

    public virtual void onTriggerStay( Behaviour other )
    {
    }

    public virtual void onTriggerExit( Behaviour other )
    {
    }

    # 刷新世界线段端点 / 半径 / AABB
    public void refreshWorldBounds()
    {
        GameObject go = this.owner
        if go == null
        {
            ret
        }
        Transform t = go.transform
        Float32_4x4 m4 = t.worldMatrix()
        Float32 halfSpan = this.height * 0.5f - this.radius
        if halfSpan < 0.0f
        {
            halfSpan = 0.0f
        }
        Float32_3 la = Float32_3( this.center.x, this.center.y + halfSpan, this.center.z )
        Float32_3 lb = Float32_3( this.center.x, this.center.y - halfSpan, this.center.z )
        this.worldA = m4.transformPoint( la )
        this.worldB = m4.transformPoint( lb )
        Float32_3 sc = t.worldScale()
        Float32 smax = sc.x
        if sc.y > smax
        {
            smax = sc.y
        }
        if sc.z > smax
        {
            smax = sc.z
        }
        this.worldRadius = this.radius * smax
        # AABB：两端点 ± 半径（逐轴 max/min 手工展开）
        Float32 mnx = this.worldA.x
        Float32 mny = this.worldA.y
        Float32 mnz = this.worldA.z
        Float32 mxx = this.worldA.x
        Float32 mxy = this.worldA.y
        Float32 mxz = this.worldA.z
        if this.worldB.x < mnx
        {
            mnx = this.worldB.x
        }
        if this.worldB.y < mny
        {
            mny = this.worldB.y
        }
        if this.worldB.z < mnz
        {
            mnz = this.worldB.z
        }
        if this.worldB.x > mxx
        {
            mxx = this.worldB.x
        }
        if this.worldB.y > mxy
        {
            mxy = this.worldB.y
        }
        if this.worldB.z > mxz
        {
            mxz = this.worldB.z
        }
        Float32 cx = ( mnx + mxx ) * 0.5f
        Float32 cy = ( mny + mxy ) * 0.5f
        Float32 cz = ( mnz + mxz ) * 0.5f
        Float32 r = this.worldRadius
        this.worldBounds = Bounds.fromCenterSize( Float32_3( cx, cy, cz ),
            Float32_3( mxx - mnx + r * 2.0f, mxy - mny + r * 2.0f, mxz - mnz + r * 2.0f ) )
    }

    # ── 线段最近点 ───────────────────────────────────────
    # 点 p 到线段 ab 的最近点（t 钳到 [0,1]）
    Float32_3 closestOnSegment( Float32_3 a, Float32_3 b, Float32_3 p )
    {
        Float32 abx = b.x - a.x
        Float32 aby = b.y - a.y
        Float32 abz = b.z - a.z
        Float32 len2 = abx * abx + aby * aby + abz * abz
        Float32 t = 0.0f
        if len2 > 0.000001f
        {
            Float32 wx = p.x - a.x
            Float32 wy = p.y - a.y
            Float32 wz = p.z - a.z
            t = ( wx * abx + wy * aby + wz * abz ) / len2
            if t < 0.0f
            {
                t = 0.0f
            }
            if t > 1.0f
            {
                t = 1.0f
            }
        }
        ret Float32_3( a.x + abx * t, a.y + aby * t, a.z + abz * t )
    }

    # ── capsule(自身) vs sphere(other)：n 从 other 指向自身 ──
    public bool computeSphereContact( SphereCollider other, ContactInfo info )
    {
        Float32_3 c = other.worldCenter
        Float32_3 p = this.closestOnSegment( this.worldA, this.worldB, c )
        Float32 dx = p.x - c.x
        Float32 dy = p.y - c.y
        Float32 dz = p.z - c.z
        Float32 dist = Float32_3( dx, dy, dz ).length()
        Float32 sum = this.worldRadius + other.worldRadius
        if dist > sum
        {
            ret false
        }
        # 重合兜底 +Y
        Float32_3 n = Float32_3( 0.0f, 1.0f, 0.0f )
        if dist > 0.0001f
        {
            n = Float32_3( dx / dist, dy / dist, dz / dist )
        }
        info.normal = n
        info.penetration = sum - dist
        info.point = Float32_3( c.x + n.x * other.worldRadius, c.y + n.y * other.worldRadius, c.z + n.z * other.worldRadius )
        ret true
    }

    # ── capsule(自身) vs capsule(other)：n 从 other 指向自身 ──
    public bool computeCapsuleContact( CapsuleCollider other, ContactInfo info )
    {
        # 线段-线段最近点（Ericson Real-Time Collision Detection 5.1.4）
        Float32_3 p1 = this.worldA
        Float32_3 q1 = this.worldB
        Float32_3 p2 = other.worldA
        Float32_3 q2 = other.worldB
        Float32 d1x = q1.x - p1.x
        Float32 d1y = q1.y - p1.y
        Float32 d1z = q1.z - p1.z
        Float32 d2x = q2.x - p2.x
        Float32 d2y = q2.y - p2.y
        Float32 d2z = q2.z - p2.z
        Float32 rx = p1.x - p2.x
        Float32 ry = p1.y - p2.y
        Float32 rz = p1.z - p2.z
        Float32 a = d1x * d1x + d1y * d1y + d1z * d1z
        Float32 e = d2x * d2x + d2y * d2y + d2z * d2z
        Float32 f = d2x * rx + d2y * ry + d2z * rz
        Float32 c = d1x * rx + d1y * ry + d1z * rz
        Float32 b = d1x * d2x + d1y * d2y + d1z * d2z
        Float32 s = 0.0f
        Float32 t = 0.0f
        if a <= 0.000001f && e <= 0.000001f
        {
            # 两线段均退化（球对球形态）
            s = 0.0f
            t = 0.0f
        }
        else
        {
            if a <= 0.000001f
            {
                s = 0.0f
                t = f / e
                if t < 0.0f
                {
                    t = 0.0f
                }
                if t > 1.0f
                {
                    t = 1.0f
                }
            }
            else
            {
                Float32 denom = a * e - b * b
                if denom > 0.000001f
                {
                    s = ( b * f - c * e ) / denom
                    if s < 0.0f
                    {
                        s = 0.0f
                    }
                    if s > 1.0f
                    {
                        s = 1.0f
                    }
                }
                t = ( b * s + f ) / e
                if t < 0.0f
                {
                    t = 0.0f
                }
                if t > 1.0f
                {
                    t = 1.0f
                }
            }
        }
        Float32 c1x = p1.x + d1x * s
        Float32 c1y = p1.y + d1y * s
        Float32 c1z = p1.z + d1z * s
        Float32 c2x = p2.x + d2x * t
        Float32 c2y = p2.y + d2y * t
        Float32 c2z = p2.z + d2z * t
        Float32 dx = c1x - c2x
        Float32 dy = c1y - c2y
        Float32 dz = c1z - c2z
        Float32 dist = Float32_3( dx, dy, dz ).length()
        Float32 sum = this.worldRadius + other.worldRadius
        if dist > sum
        {
            ret false
        }
        # n 从 other(c2) 指向自身(c1) = B→A；重合兜底 +Y
        Float32_3 n = Float32_3( 0.0f, 1.0f, 0.0f )
        if dist > 0.0001f
        {
            n = Float32_3( dx / dist, dy / dist, dz / dist )
        }
        info.normal = n
        info.penetration = sum - dist
        info.point = Float32_3( c2x + n.x * other.worldRadius, c2y + n.y * other.worldRadius, c2z + n.z * other.worldRadius )
        ret true
    }

    # ── capsule(自身) vs box(other)：三候选近似，n 从 other 指向自身 ──
    # 候选：① 线段对盒心的投影点 ② A 端帽心 ③ B 端帽心；各做一次
    # 盒.closestPoint 球判定，取穿透最大者（盒侧返回 n 从球点指向盒，
    # 取反即 B→A ✓）。近似的已知偏差：细长盒角落处接触点略有偏移。
    public bool computeBoxContact( BoxCollider box, ContactInfo info )
    {
        Float32_3 bc = box.worldBounds.center()
        bool found = false
        Float32 bestPen = 0.0f
        # 候选 ①：投影点
        Float32_3 p1 = this.closestOnSegment( this.worldA, this.worldB, bc )
        ContactInfo t1 = ContactInfo()
        bool h1 = box.computeSphereContact( p1, this.worldRadius, t1 )
        if h1
        {
            found = true
            bestPen = t1.penetration
            info.normal = t1.normal
            info.penetration = t1.penetration
            info.point = t1.point
        }
        # 候选 ②③：两端帽心
        ContactInfo t2 = ContactInfo()
        bool h2 = box.computeSphereContact( this.worldA, this.worldRadius, t2 )
        if h2 && ( !found || t2.penetration > bestPen )
        {
            found = true
            bestPen = t2.penetration
            info.normal = t2.normal
            info.penetration = t2.penetration
            info.point = t2.point
        }
        ContactInfo t3 = ContactInfo()
        bool h3 = box.computeSphereContact( this.worldB, this.worldRadius, t3 )
        if h3 && ( !found || t3.penetration > bestPen )
        {
            found = true
            info.normal = t3.normal
            info.penetration = t3.penetration
            info.point = t3.point
        }
        if !found
        {
            ret false
        }
        # 盒侧 n 从球点指向盒（A→B）→ 取反 = B→A ✓
        info.normal = info.normal._mul_( 0.0f - 1.0f ) as Float32_3
        ret true
    }
}
