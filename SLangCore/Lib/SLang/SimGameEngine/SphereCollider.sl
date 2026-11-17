import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SphereCollider — 球碰撞体（P3，doc/11 §2）
# ----------------------------------------------------------------------------
# center 为节点 local 空间球心；世界球心 = center × worldMatrix；
# 世界半径 = radius × max(scale.x, scale.y, scale.z)（非均匀缩放近似）。
# 设计偏离（doc/11 §2）：不做 Collider 公共基类（doc/10 §6 字段读规避），
# isTrigger 直接声明在本类；事件钩子签名与 BoxCollider 对齐（doc/11 §4.2
# 的 Collider 参数在 P3 简化为具体碰撞体类型）。
# ============================================================================

public class SphereCollider extends Behaviour
{
    public bool isTrigger = false
    public Float32_3 center = Float32_3.zero()
    public Float32 radius = 0.5f
    public Float32_3 worldCenter = Float32_3.zero()
    public Float32 worldRadius = 0.5f
    public Bounds worldBounds = Bounds()

    # 事件钩子（引擎经 SystemSimEngineCallHook1/2 按名派发；参数统一
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

    # 刷新世界球心/半径与包围 AABB
    public void refreshWorldBounds()
    {
        GameObject go = this.owner
        if go == null
        {
            ret
        }
        Transform t = go.transform
        Float32_4x4 m4 = t.worldMatrix()
        this.worldCenter = m4.transformPoint( this.center )
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
        Float32 r = this.worldRadius
        Float32_3 c = this.worldCenter
        this.worldBounds = Bounds.fromCenterSize( c, Float32_3( r * 2.0f, r * 2.0f, r * 2.0f ) )
    }

    # 球 vs 球：中心距 <= 半径和
    public bool computeSphereContact( SphereCollider other, ContactInfo info )
    {
        Float32_3 d = this.worldCenter._sub_( other.worldCenter ) as Float32_3
        Float32 dist = d.length()
        Float32 sum = this.worldRadius + other.worldRadius
        if dist > sum
        {
            ret false
        }
        # 法线从 other 指向自身；重合时给 +Y 兜底
        Float32_3 n = Float32_3( 0.0f, 1.0f, 0.0f )
        if dist > 0.0001f
        {
            n = d._mul_( 1.0f / dist ) as Float32_3
        }
        info.normal = n
        info.penetration = sum - dist
        info.point = other.worldCenter._add_( n._mul_( other.worldRadius ) ) as Float32_3
        ret true
    }

    # 球 vs 盒（other 为盒）：委托盒侧计算，法线取反（盒侧法线从球指向盒，
    # 本方法视角需要从盒（other）指向球（自身））
    public bool computeBoxContact( BoxCollider box, ContactInfo info )
    {
        bool hit = box.computeSphereContact( this.worldCenter, this.worldRadius, info )
        if !hit
        {
            ret false
        }
        info.normal = info.normal._mul_( 0.0f - 1.0f ) as Float32_3
        ret true
    }
}
