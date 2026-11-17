import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# BoxCollider — 盒碰撞体（P3，doc/11 §2）
# ----------------------------------------------------------------------------
# center/size 为节点 local 空间（相对节点原点）；世界 AABB 由
# CollisionSystem 用 worldMatrix 变换 8 顶点后 Bounds.fromPoints 生成
# （旋转节点必须重算——doc/11 §6.2）。
# 设计偏离（doc/11 §2，原因见 doc/10 §6）：不做 Collider 公共基类——
# Behaviour 子类实例的跨模块字段读不可靠，isTrigger 直接声明在本类；
# 多态窄相用 CollisionSystem 的 kind 分派替代。
# 比较判定注意：`== -1`/`== 常量` 对本类实例字段跨模块读不可靠，消费方
# 判定用区间/小于形态（doc/10 §6）。
# ============================================================================

public class BoxCollider extends Behaviour
{
    public bool isTrigger = false
    public Float32_3 center = Float32_3.zero()
    public Float32_3 size = Float32_3( 1.0f, 1.0f, 1.0f )
    public Bounds worldBounds = Bounds()

    # 事件钩子（引擎经 SystemSimEngineCallHook1/2 按名派发到最派生
    # override；P3 简化：事件只投给宿主的 Collider 组件自身；参数统一
    # Behaviour 类型以兼容混合形状对——按名派发不校验参数类型）
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

    # 本盒世界 AABB（8 顶点 × worldMatrix → fromPoints）；
    # 由 CollisionSystem 每步刷新，脚本可读
    public void refreshWorldBounds()
    {
        GameObject go = this.owner
        if go == null
        {
            ret
        }
        Transform t = go.transform
        Float32_4x4 m4 = t.worldMatrix()
        Float32 hx = this.size.x * 0.5f
        Float32 hy = this.size.y * 0.5f
        Float32 hz = this.size.z * 0.5f
        Float32 cx = this.center.x
        Float32 cy = this.center.y
        Float32 cz = this.center.z
        Array<Float32_3> pts = Array<Float32_3>( 8 )
        pts[0] = m4.transformPoint( Float32_3( cx - hx, cy - hy, cz - hz ) )
        pts[1] = m4.transformPoint( Float32_3( cx + hx, cy - hy, cz - hz ) )
        pts[2] = m4.transformPoint( Float32_3( cx - hx, cy + hy, cz - hz ) )
        pts[3] = m4.transformPoint( Float32_3( cx + hx, cy + hy, cz - hz ) )
        pts[4] = m4.transformPoint( Float32_3( cx - hx, cy - hy, cz + hz ) )
        pts[5] = m4.transformPoint( Float32_3( cx + hx, cy - hy, cz + hz ) )
        pts[6] = m4.transformPoint( Float32_3( cx - hx, cy + hy, cz + hz ) )
        pts[7] = m4.transformPoint( Float32_3( cx + hx, cy + hy, cz + hz ) )
        this.worldBounds = Bounds.fromPoints( pts )
    }

    # AABB 对 AABB 精确接触（最小穿透轴）；重叠返回 true 并写 info
    public bool computeBoxContact( BoxCollider other, ContactInfo info )
    {
        Bounds a = this.worldBounds
        Bounds b = other.worldBounds
        if !a.intersects( b )
        {
            ret false
        }
        # 各轴重叠量
        Float32 ox = a.max.x - b.min.x
        Float32 ox2 = b.max.x - a.min.x
        if ox2 < ox
        {
            ox = ox2
        }
        Float32 oy = a.max.y - b.min.y
        Float32 oy2 = b.max.y - a.min.y
        if oy2 < oy
        {
            oy = oy2
        }
        Float32 oz = a.max.z - b.min.z
        Float32 oz2 = b.max.z - a.min.z
        if oz2 < oz
        {
            oz = oz2
        }
        # 最小穿透轴作法线（从 other 指向自身 = a - b 方向）
        Float32 acx = ( a.min.x + a.max.x ) * 0.5f
        Float32 acy = ( a.min.y + a.max.y ) * 0.5f
        Float32 acz = ( a.min.z + a.max.z ) * 0.5f
        Float32 bcx = ( b.min.x + b.max.x ) * 0.5f
        Float32 bcy = ( b.min.y + b.max.y ) * 0.5f
        Float32 bcz = ( b.min.z + b.max.z ) * 0.5f
        Float32 nx = 0.0f
        Float32 ny = 0.0f
        Float32 nz = 0.0f
        Float32 pen = ox
        if oy < pen
        {
            pen = oy
        }
        if oz < pen
        {
            pen = oz
        }
        if pen == ox
        {
            nx = 1.0f
        }
        elif pen == oy
        {
            ny = 1.0f
        }
        else
        {
            nz = 1.0f
        }
        if acx < bcx
        {
            nx = 0.0f - nx
        }
        if acy < bcy
        {
            ny = 0.0f - ny
        }
        if acz < bcz
        {
            nz = 0.0f - nz
        }
        info.normal = Float32_3( nx, ny, nz )
        info.penetration = pen
        # 接触点 = 两中心中点（近似，doc/11 不要求精确接触点）
        info.point = Float32_3( ( acx + bcx ) * 0.5f, ( acy + bcy ) * 0.5f, ( acz + bcz ) * 0.5f )
        ret true
    }

    # 本盒 vs 世界空间球（球心 + 半径）：closestPoint + distanceTo（已落盘）
    public bool computeSphereContact( Float32_3 sphereCenter, Float32 radius, ContactInfo info )
    {
        Bounds a = this.worldBounds
        Float32_3 closest = a.closestPoint( sphereCenter )
        Float32_3 diff = closest._sub_( sphereCenter ) as Float32_3
        Float32 dist = diff.length()
        if dist > radius
        {
            ret false
        }
        # 法线从球（other 视角重排由 CollisionSystem 处理）指向盒；
        # dist ~ 0（球心在盒内）时退化为盒中心指向
        Float32_3 n = diff
        if dist < 0.0001f
        {
            Float32_3 ac = a.center()
            n = closest._sub_( ac ) as Float32_3
            Float32 nl = n.length()
            if nl < 0.0001f
            {
                n = Float32_3( 0.0f, 1.0f, 0.0f )
            }
            else
            {
                n = n._mul_( 1.0f / nl ) as Float32_3
            }
        }
        else
        {
            n = n._mul_( 1.0f / dist ) as Float32_3
        }
        info.normal = n
        info.penetration = radius - dist
        info.point = closest
        ret true
    }
}
