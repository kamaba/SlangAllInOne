import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# BatchGroup — 一个合批组（P2）
# ----------------------------------------------------------------------------
# 键分量快照（doc/05 §2）+ 组成员 + 烘焙输出。
# singleObject = true：单对象直通路径（doc/05 §3.1 例外）——顶点保持模型
# 空间，提交方把 soleMember 的世界变换写进 RenderObject 字段；
# singleObject = false：多对象合批——bakeVertices() 现场生成世界空间顶点
# （local × worldMatrix 烘焙），提交方对应 RenderObject transform 保持
# 单位值，并 uploadMesh 到引擎分配的槽位。
# 键分量说明（与 doc/05 §2 对照，补强一条）：
#   1 programId  2 material（实例身份）  3 meshKind/meshSlot  4 layer
#   5 renderQueue  6 specular/castShadow  7 textureId
#   8 animatedMode/animatedSpeed  9(补强) 实例色（setColor 是 RenderObject
#   级字段，合批后作用于整批——不同实例色必须拆批）
# 注意：顶点容器用 List<Float32_3>（List/Array 的值类型泛型实参 Float32
# 不被 Front 解析支持，struct 实参可用）。
# ============================================================================

public class BatchGroup
{
    public Int32 programId = 0
    public Int32 textureId = 0
    public Int32 meshKind = 0
    public Int32 meshSlot = 0
    public Int32 layer = 0
    public Int32 renderQueue = 0
    public Float32 specular = 0.0f
    public bool castShadow = false
    public Int32 animatedMode = 0
    public Float32 animatedSpeed = 0.0f
    public Float32_3 color = Float32_3( 1.0f, 1.0f, 1.0f )
    public Int32 assetId = 0
    public MaterialData material = null

    public bool singleObject = false
    public GameObject soleMember = null
    public List<GameObject> members = List<GameObject>( 0 )

    public Int32 memberCount()
    {
        ret this.members.length
    }

    # 顶点烘焙（写入式）：members 各自 MeshRef.vertices（模型空间
    # Float32_3）× worldMatrix → 追加到 outList（世界空间顶点）。
    # 任一成员无顶点数据时不写入任何顶点（outList 保持原样，提交方应检查
    # singleObject）。坑：方法返回值形态的 List 容器跨模块不可靠
    # （roots().length 读出坏值，doc/10 §6），故改为调用方传容器写入。
    public void bakeVerticesInto( List<Float32_3> outList )
    {
        Int32 i = 0
        Int32 n = this.members.length
        while i < n
        {
            GameObject go = this.members[i]
            MeshRef mr = go.getComponent<MeshRef>()
            if mr == null
            {
                ret
            }
            if !mr.hasVertexData
            {
                ret
            }
            Transform t = go.transform
            Float32_4x4 m4 = t.worldMatrix()
            List<Float32_3> src = mr.vertices
            Int32 j = 0
            Int32 m = src.length
            while j < m
            {
                Float32_3 p = src[j]
                Float32_3 wp = m4.transformPoint( p )
                outList.add( wp )
                j = j + 1
            }
            i = i + 1
        }
    }
}
