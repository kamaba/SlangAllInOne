import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# ParallaxLayer — 2D 视差背景层组件（P7 2D 游戏类型支撑，doc/15 §9）
# ----------------------------------------------------------------------------
# 挂在背景/装饰层节点上：相机移动时按系数差速移动，制造纵深。
# 数学（屏幕位移推导）：nodePos = basePos + (cam - anchor) * (1 - f)
#   f = 1  → 节点不动（与世界一起，等同前景）
#   f = 0  → 节点完全跟着相机走（贴屏，等同无限远天空）
#   0<f<1  → 屏幕上以 f 倍相机位移差速移动（越远越慢）
# anchor 取「基准时刻的相机中心」；captureBase() 记录挂载节点当前位置为
# basePos（首次 apply 前未捕获则自动捕获）。
# 约定：X/Y 各自独立系数（横版常 X 差速 Y 固定）。
# 边界：setPosition 写的是 local 位置——多层根节点直挂 Scene 下（或
# 父节点恒在原点），有平移父节点时先 captureBase 于世界位再自行换算。
# straight-line 实现，无循环（Behaviour 子类坑规避，doc/10 §6）。
# ============================================================================

public class ParallaxLayer extends Behaviour
{
    # 视差系数（0 = 贴屏 / 1 = 随世界）
    public Float32 factorX = 0.5f
    public Float32 factorY = 0.5f
    # 基准相机中心（一般 = 相机初始位置）
    public Float32_3 anchor = Float32_3.zero()

    Float32_3 _basePos = Float32_3.zero()
    bool _baseCaptured = false

    # 记录挂载节点当前世界位置为基准位（建层时调用一次）
    public void captureBase()
    {
        GameObject ow = this.owner
        if ow == null
        {
            ret
        }
        Transform t = ow.transform
        this._basePos = t.worldPosition()
        this._baseCaptured = true
    }

    # 相机移动后调用：按系数换算节点位置
    public void apply( Float32_3 camCenter )
    {
        GameObject ow = this.owner
        if ow == null
        {
            ret
        }
        if !this._baseCaptured
        {
            this.captureBase()
        }
        Float32_3 b = this._basePos
        Float32_3 an = this.anchor
        Float32 dx = ( camCenter.x - an.x ) * ( 1.0f - this.factorX )
        Float32 dy = ( camCenter.y - an.y ) * ( 1.0f - this.factorY )
        Float32 nx = b.x + dx
        Float32 ny = b.y + dy
        Float32_3 np = Float32_3( nx, ny, b.z )
        Transform t = ow.transform
        t.setPosition( np )
    }

    # 基准位读取（诊断/测试）
    public Float32_3 basePosition()
    {
        ret this._basePos
    }
}
