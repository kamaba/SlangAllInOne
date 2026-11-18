import Core;
import Std;

# 场景脚本工厂回填槽（doc/19）：工厂形态 void(JsonValue cfg, ScriptResult out)，
# 把创建的 Behaviour 写进 out.value，由 SceneImporter 挂到节点。
# 之所以不用 Func<> 返回值：Func<> 字段/泛型实参在本编译链受限
#（MetaCoreCallIssue13），List<Function> 是既有可用形态。
public class ScriptResult
{
    public Behaviour value = null
}
