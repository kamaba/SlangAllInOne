import Core;
import Std;
import Math;

# ============================================================================
# ContactInfo — 接触信息（P3，doc/11 §2）
# ----------------------------------------------------------------------------
# 窄相输出的单次接触描述（世界空间）。normal 约定：从 other 指向自身
# （接收方视角）；触发器事件不带 ContactInfo（doc/11 §4.1——不要从
# onTriggerEnter 里读法线做反弹）。
# 普通类（非 Behaviour 继承链）——跨模块字段读可靠（doc/10 §6 规避家族）。
# ============================================================================

public class ContactInfo
{
    public Float32_3 point = Float32_3.zero()
    public Float32_3 normal = Float32_3.zero()
    public Float32 penetration = 0.0f

    public string toString()
    {
        ret String.toFormat( "ContactInfo(point={0}, normal={1}, pen={2})",
            this.point.toString(), this.normal.toString(), this.penetration.toString() )
    }
}
