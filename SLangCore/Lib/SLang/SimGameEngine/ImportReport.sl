import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# ImportReport — SceneImporter 导入结果（P8 完整导入器 v1，doc/16 §5）
# ----------------------------------------------------------------------------
# 携带重建的 Scene 与导入统计；失败时 ok=false + error（version 不识别等
# 明确报错不猜，doc/16 §5）。资源登记：meshIds 走 meshIdCount/meshIdAt
# 方法（跨模块读可靠形态）；MaterialData 以 MeshRenderer 的 material id
# 建实例（color/queue 资产 json 的深解析随资源管线 v2）。
# ============================================================================
public class ImportReport
{
    public bool ok = false
    public string lastError = ""
    public string sceneName = ""
    public Int32 version = 0
    public Scene scene = null

    public Int32 nodeCount = 0
    public Int32 rootCount = 0
    public Int32 meshCount = 0
    public Int32 materialCount = 0
    public Int32 colliderCount = 0
    public Int32 rigidbodyCount = 0
    public Int32 cameraCount = 0
    public Int32 lightCount = 0
    public Int32 spriteCount = 0
    public Int32 scriptCount = 0
    public Int32 skippedCount = 0
    public Int32 textureCount = 0

    List<string> _meshIds = List<string>( 4 )

    public void addMeshId( string id )
    {
        this._meshIds.add( id )
    }

    public Int32 meshIdCount()
    {
        ret this._meshIds.length
    }

    public string meshIdAt( Int32 idx )
    {
        string v = this._meshIds[idx]
        ret v
    }
}
