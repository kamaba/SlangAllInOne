import Core;
import Std;

# ============================================================================
# EcsLogic — ECS 逻辑组件（doc/20 §3）
# ----------------------------------------------------------------------------
# 形态上像 Behaviour（可 override awake/start/update/lateUpdate/fixedUpdate），
# 但挂载时不进 GameObject.components，而是被 EcsLogicSystem 集中登记、按
# order 排序后统一调度——即「逻辑拔离节点，交给一个总的逻辑系统」。
# 钩子仍走 SystemSimEngineCallHook 按名派发（跨模块 slb 虚表不派发 override）。
# ============================================================================

public class EcsLogic extends Behaviour
{
    # 关联实体（逻辑不挂在节点上，靠 entity 读取/写回数据）
    public GameObject entity = null
    # 同一逻辑系统内的调度序（升序；相同则保持登记顺序）
    public Int32 order = 0

    public void attachTo( GameObject go )
    {
        this.entity = go
        this.owner = go
        this.parent = go
    }

    override string toString()
    {
        ret String.toFormat( "EcsLogic(order={0})", this.order.toString() )
    }
}
