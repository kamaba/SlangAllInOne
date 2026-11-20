import Core;
import Std;

# ============================================================================
# EcsLayer — ECS 分层合并结果（doc/20 §4）
# ----------------------------------------------------------------------------
# 继承 BatchGroup，沿用其合批键与烘焙提交路径；仅补充分层序号与「是否由
# 多个实体合并」标记。world.layerAt(i) 返回本类型，RenderSystem 仍按
# BatchGroup 消费，渲染层零分支。
# ============================================================================

public class EcsLayer extends BatchGroup
{
    public Int32 layerIndex = 0
    public bool merged = false
    # 本层合并掉的实体数（成员数 - 1；单实体直通为 0）
    public Int32 mergedCount = 0

    public void finish( Int32 idx )
    {
        this.layerIndex = idx
        Int32 mc = this.memberCount()
        if mc > 1
        {
            this.merged = true
            this.mergedCount = mc - 1
        }
        else
        {
            this.merged = false
            this.mergedCount = 0
        }
    }
}
