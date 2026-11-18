import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# MaterialData — 引擎侧材质数据资源（P2）
# ----------------------------------------------------------------------------
# doc/04 §1「资源不等于组件」：本类是可共享的资源对象（多个 GameObject 的
# MaterialRef 组件引用同一实例），对象引用本身即合批键分量 2 的「材质实例
# 身份」——两个节点引用同一 MaterialData 可合批，引用不同实例（即使参数
# 全同，等价于 clone）不可合批。
# 与 SLangRender 的 Material 门面的映射在 Submit 段做（Render 同名类冲突，
# 见 doc/10 §6）：programId 对应 resolveProgram() 的结果，textureId 对应
# setTexture 的句柄 id，由调用方在提交时换算。
# ============================================================================

public class MaterialData
{
    # 资产身份 id（静态工厂 create 分配；合批键分量 2「材质实例身份」，
    # 不同实例即使参数全同也不合批——等价 clone 语义。
    # 注意：身份分配放静态工厂不放 _init_——构造期静态字段自增实测会
    # 破坏后续跨模块字段读取（doc/10 §6））
    static Int32 _nextAssetId = 1
    public Int32 assetId = 0
    public string name = ""
    public Int32 programId = 0
    public Int32 textureId = 0
    public Float32_3 color = Float32_3( 1.0f, 1.0f, 1.0f )
    public Float32 specular = 0.0f
    public bool castShadow = false
    # v2.13：材质模型 0=Lambert 1=Phong 2=BlinnPhong 3=BlinnPhongNormalMap
    # 4=Toon（固化 HLSL 程序槽路由；越界 C 侧夹取 [0,4]）
    public Int32 materialModel = 0
    # v2.13：Phong/BlinnPhong 高光锐度（1..256，C 侧夹取）
    public Float32 shininess = 32.0f
    # v2.13：贴图（SceneImporter 经 RenderTexture.loadFile 装载；null = 纯色）。
    # 跨模块对象单字段持有可靠（RenderSystem._pipe 同款，doc/10 §6）
    public SLang.RenderTexture texture = null
    public Int32 renderQueue = 2000
    public Int32 animatedMode = 0
    public Float32 animatedSpeed = 0.0f

    public static MaterialData create( string matName )
    {
        MaterialData m = MaterialData()
        m.name = matName
        m.assetId = MaterialData._nextAssetId
        MaterialData._nextAssetId = m.assetId + 1
        ret m
    }
}
