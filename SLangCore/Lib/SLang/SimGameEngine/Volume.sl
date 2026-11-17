import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Volume — 体积效果组件（P8 Volume 落盘 v1，doc/14 §2）
# ----------------------------------------------------------------------------
# 挂 GameObject（extends Behaviour）；持有 VolumeProfile 共享资源。
# 全局 Volume 直接生效；局部 Volume 按相机位置 ∈ influenceBounds 判定，
# blendDistance 提供范围外扩过渡衰减（进内圈满权重，外扩段线性衰减到 0）。
# 有效权重计算 weightAt（straight-line 无循环——Behaviour 子类方法含循环
# 时字段读失效，doc/10 §6）；排序与混合数学在 C（sle_volume_blend）。
# ============================================================================
public class Volume extends Behaviour
{
    # 效果配置资源（null = 不贡献）
    public VolumeProfile profile = null
    public bool isGlobal = false
    # 优先级：值大者排序靠后 = 后应用 = 覆盖优先（doc/14 §3）
    public Int32 priority = 0
    # 基础权重 [0,1]
    public Float32 weight = 1.0f
    # 局部 Volume 的范围外过渡距离（0 = 硬切）
    public Float32 blendDistance = 0.0f
    # 局部 Volume 生效范围（非全局必填；min/max 直写字段构造）
    public Bounds influenceBounds = null

    # 相机位置处的有效权重：全局 = weight；局部 = 范围内 weight、
    # 外扩段线性衰减、范围外 0；profile 缺失 / 范围缺失不生效。
    public Float32 weightAt( Float32_3 camPos )
    {
        if this.profile == null
        {
            ret 0.0f
        }
        Float32 w = this.weight
        if w <= 0.0f
        {
            ret 0.0f
        }
        if this.isGlobal
        {
            ret w
        }
        Bounds b = this.influenceBounds
        if b == null
        {
            ret 0.0f
        }
        bool inside = b.contains( camPos )
        if inside
        {
            ret w
        }
        Float32 bd = this.blendDistance
        if bd <= 0.0f
        {
            ret 0.0f
        }
        Float32 d = b.distanceTo( camPos )
        if d >= bd
        {
            ret 0.0f
        }
        Float32 fall = 1.0f - d / bd
        ret w * fall
    }
}
