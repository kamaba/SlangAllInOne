import Core;
import Std;
import Math;

# ============================================================================
# ContactPair — 持续接触表条目（P3，doc/11 §4.3）
# ----------------------------------------------------------------------------
# 普通类；colA/colB 为碰撞体组件引用（引用跨模块比较可靠，同 indexOf 先例）。
# wasTouching：上一固定步是否接触（Enter/Stay/Exit 判定基准）。
# triggerPair：true = 双方任一为触发器（只发 onTrigger* 事件，无 ContactInfo）。
# ============================================================================

public class ContactPair
{
    public Behaviour colA = null
    public Behaviour colB = null
    public bool wasTouching = false
    public bool triggerPair = false
}
