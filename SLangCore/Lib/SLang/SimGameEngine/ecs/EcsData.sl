import Core;
import Std;

# ============================================================================
# EcsData — ECS 纯数据组件标记（doc/20 §2）
# ----------------------------------------------------------------------------
# ECS 模式下 GameObject 只允许挂 Data 组件：EcsData 子类（业务数据）、
# MeshRef / MaterialRef（渲染数据，由 EcsWorld 接管）、Transform（节点必有）。
# 本类刻意 **不继承 Behaviour**，不会被 Application 的 Behaviour 收集器
# 当成脚本调度；数据只由 System 批量读写。
# 复用 Component（而非 struct）是为了沿用 type.toString() 去重与绑定语义。
# ============================================================================

public class EcsData extends Component
{
    # 所属实体（由 EcsWorld.addData 回填，不手工改）
    public GameObject entity = null
    # 数据分类标签（默认取类型名；方便同类多实例时按标签查询）
    public string kind = "EcsData"

    public void attachTo( GameObject go )
    {
        this.entity = go
        this.parent = go
    }

    override string toString()
    {
        ret String.toFormat( "EcsData(kind={0})", this.kind )
    }
}
