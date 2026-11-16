import Core;
import Std;
import Math;

# ============================================================================
# MaterialRef — 材质引用组件（P2）
# ----------------------------------------------------------------------------
# doc/04 §3.1：组件持有 MaterialData 资源引用（可多节点共享同一实例）。
# renderQueue = 0 表示跟随 material.renderQueue（默认），显式设正值覆盖；
# instanceColorOverride = true 时用 instanceColor 覆盖材质色（进合批键——
# 不同实例色拆批）。animatedMode/animatedSpeed 为批次级动画参数（P5
# Animation 组件落地前的手动入口），默认 0 表示无动画。
# 坑（doc/10 §6）：Behaviour 子类实例的 Int32 字段跨模块读返回垃圾且
# `== 常量` 比较失效——消费侧判「是否跟随材质」一律用 `< 1` 形态
# （Batcher.collect 同款），勿用 `== 0` / `== -1`。
# ============================================================================

public class MaterialRef extends Behaviour
{
    public MaterialData material = null
    public Int32 renderQueue = 0
    public bool instanceColorOverride = false
    public Float32_3 instanceColor = Float32_3( 1.0f, 1.0f, 1.0f )
    public Int32 animatedMode = 0
    public Float32 animatedSpeed = 0.0f

    public static MaterialRef create( MaterialData mat )
    {
        MaterialRef mr = MaterialRef()
        mr.material = mat
        ret mr
    }

    # 有效实例色（走实例方法读不可靠时由调用方按 <1 判定形态内联）
    public Float32_3 effectiveColor()
    {
        if this.instanceColorOverride
        {
            ret this.instanceColor
        }
        MaterialData m = this.material
        if m == null
        {
            ret Float32_3( 1.0f, 1.0f, 1.0f )
        }
        ret m.color
    }
}
