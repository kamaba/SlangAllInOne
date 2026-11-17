import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SpriteRenderer — 2D 精灵组件（P7，doc/15 §3.1）
# ----------------------------------------------------------------------------
# 挂 GameObject 的世界内精灵（区别于 UI：UI 走 RectTransform/UISystem，doc/08）。
# 提交路径：RenderSystem.collect2D 在收集上下文一次读全本组件字段（同模块
# 读可靠），映射为 MESH_QUAD RenderObject：
#   - 队列 = SortingLayers.queueOf(sortingLayer, orderInLayer)（setQueue）；
#   - 位置 = 节点世界位 + pivot 偏移（pivot(0.5,0.5) 居中不偏移）；
#   - 尺寸 = size × 节点世界缩放；旋转 = worldRotationZ；
#   - 颜色 = color + colorAlpha（setColor 第四参）。
# v1 边界（doc/15 §8）：
#   - flipX/flipY 登记不下发（翻转走顶点 UV，随烘焙/uploadMesh 路径生效）；
#   - 贴图用 textureId（Render 门面句柄 id，MaterialData.textureId 同款
#     映射，引擎数据层不引用 SLangRender——双模块根级同名类规避）；
#   - material 可选（MaterialData 共享资源，供合批键/程序选择用，v1 直通
#     路径未消费）。
# 坑（doc/10 §6）：消费侧读本组件数值字段跨模块不可靠——统一走
# RenderSystem.collect2D 的平行数组 getters（spriteQueueAt 等）或本类
# getter 方法（isFlippedX 等），勿直接字段读。
# ============================================================================

public class SpriteRenderer extends Behaviour
{
    public bool visible = true
    # 贴图句柄 id（0 = 无贴图纯色 quad）
    public Int32 textureId = 0
    # 可选共享材质资源（合批键 / 程序选择；v1 直通路径未消费）
    public MaterialData material = null
    # 世界单位尺寸（× 节点世界缩放后生效）
    public Float32_2 size = Float32_2( 1.0f, 1.0f )
    # 枢轴（0..1，0.5 居中；偏移 = (pivot-0.5)*size*worldScale）
    public Float32_2 pivot = Float32_2( 0.5f, 0.5f )
    # 翻转标记（v1 登记不下发，随烘焙 UV 路径生效）
    public bool flipX = false
    public bool flipY = false
    # 排序：层 + 层内次序（→ RenderQueue，SortingLayers 映射）
    public Int32 sortingLayer = 0
    public Int32 orderInLayer = 0
    # 着色与透明度
    public Float32_3 color = Float32_3( 1.0f, 1.0f, 1.0f )
    public Float32 colorAlpha = 1.0f

    public void setSprite( Int32 texId )
    {
        this.textureId = texId
    }

    public void setFlip( bool fx, bool fy )
    {
        this.flipX = fx
        this.flipY = fy
    }

    public void setSorting( Int32 layer, Int32 order )
    {
        this.sortingLayer = layer
        this.orderInLayer = order
    }

    public void setTint( Float32 r, Float32 g, Float32 b )
    {
        this.color = Float32_3( r, g, b )
    }

    # 枢轴世界偏移（未旋转，worldScale 已计入；collect2D 消费同款公式）
    public Float32 pivotOffsetX()
    {
        Float32_2 pv = this.pivot
        Float32_2 sz = this.size
        ret ( pv.x - 0.5f ) * sz.x
    }

    public Float32 pivotOffsetY()
    {
        Float32_2 pv = this.pivot
        Float32_2 sz = this.size
        ret ( pv.y - 0.5f ) * sz.y
    }

    # getter 方法（跨模块字段读规避形态，doc/10 §6）
    public bool isFlippedX()
    {
        ret this.flipX
    }

    public bool isFlippedY()
    {
        ret this.flipY
    }

    public Int32 getTextureId()
    {
        ret this.textureId
    }
}
