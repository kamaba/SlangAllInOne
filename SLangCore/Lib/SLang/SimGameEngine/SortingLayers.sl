import Core;
import Std;
import Math;

# ============================================================================
# SortingLayers — 2D 排序层 → RenderQueue 基值映射表（P7，doc/15 §3.2）
# ----------------------------------------------------------------------------
# Unity 的「SortingLayer → Order in Layer → 深度」映射到 Render 已支持的
# 排序输入：每个排序层分配一个 queue 基值，orderInLayer 在基值上加偏移，
# 最终写 RenderObject.setQueue（透明段 queue >= 2500 后→前绘制）。
# 默认 8 层：base(layer) = 2500 + layer * 100（层内 order 0..99）。
# 用法（实例类，由 RenderSystem 持有一份全局表；消费方也可自建实例）：
#   rs.layers.setBase( 1, 3000 )
#   Int32 q = rs.layers.queueOf( 1, 10 )     # 3010
# 规则：
#   - 层号越界（<0 或 >7）回退 defaultBase（2500）——不抛错，方便渐进配置；
#   - order 越界钳位到 0..99——避免穿透到下一层的基值区间；
#   - 同层同 order 的次序由收集顺序（场景树先序）稳定保持。
# ============================================================================

public class SortingLayers
{
    public Int32 layerCount = 8
    public Int32 maxOrder = 99
    public Int32 defaultBase = 2500

    # 基值表用 Array<Int32>（List 下标写跨模块失效——doc/10 §6；
    # Array 索引走 SystemArray* 系统调用路径可靠，CollisionSystem 同款）
    Array<Int32> _bases = Array<Int32>( 8 )

    public void _init_()
    {
        Int32 i = 0
        while i < 8
        {
            this._bases[i] = 2500 + i * 100
            i = i + 1
        }
    }

    # 设置某层 queue 基值（越界层号忽略；`base` 是保留字，参数名避让）
    public void setBase( Int32 layer, Int32 baseValue )
    {
        if layer < 0
        {
            ret
        }
        if layer > 7
        {
            ret
        }
        this._bases[layer] = baseValue
    }

    # 某层 queue 基值（越界回退 defaultBase）
    public Int32 baseOf( Int32 layer )
    {
        if layer < 0
        {
            ret this.defaultBase
        }
        if layer > 7
        {
            ret this.defaultBase
        }
        ret this._bases[layer]
    }

    # 排序层 + 层内次序 → 最终 RenderQueue
    public Int32 queueOf( Int32 layer, Int32 order )
    {
        Int32 o = order
        if o < 0
        {
            o = 0
        }
        if o > this.maxOrder
        {
            o = this.maxOrder
        }
        ret this.baseOf( layer ) + o
    }
}
