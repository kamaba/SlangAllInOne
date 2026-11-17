import Core;
import Std;
import Math;

# ============================================================================
# VolumeProfile — Volume 效果配置资源（P8 Volume 落盘 v1，doc/14 §2）
# ----------------------------------------------------------------------------
# 可共享资源（多个 Volume 组件引用同一实例，MaterialData 同款）。
# v1 可下发字段 = Render 现有后处理三参（brightness/saturation/vignette），
# **缺省语义是「不修改」**（掩码 hasXxx，doc/14 §3.1：只配了暗角的
# Profile 不得把亮度清掉）；Bloom/Tonemap/DOF/Fog 存参数不下发
# （unsupportedCount 统计，防「以为生效」误判，doc/14 §5）。
# 计算分工（复用专项约定）：混合数学在 C（sle_volume_blend，
# sl_sim_engine_lib），本类与 Volume/VolumeSystem 只做数据与组块。
# ============================================================================
public class VolumeProfile
{
    public string name = "Profile"
    # ── 可下发（Render 后处理三参 + 掩码）──
    public bool hasBrightness = false
    public Float32 brightness = 1.0f
    public bool hasSaturation = false
    public Float32 saturation = 1.0f
    public bool hasVignette = false
    public Float32 vignette = 1.0f
    # ── 未支持效果（存参数不下发）──
    public bool hasBloom = false
    public Float32 bloomIntensity = 0.0f
    public bool hasTonemap = false
    public Int32 tonemapMode = 0
    public bool hasDof = false
    public Float32 dofFocusDistance = 0.0f
    public bool hasFog = false
    public Float32 fogDensity = 0.0f

    # 一次配齐三参（掩码置位）
    public void setPost( Float32 b, Float32 s, Float32 v )
    {
        this.hasBrightness = true
        this.brightness = b
        this.hasSaturation = true
        this.saturation = s
        this.hasVignette = true
        this.vignette = v
    }

    public void setBrightness( Float32 b )
    {
        this.hasBrightness = true
        this.brightness = b
    }

    public void setSaturation( Float32 s )
    {
        this.hasSaturation = true
        this.saturation = s
    }

    public void setVignette( Float32 v )
    {
        this.hasVignette = true
        this.vignette = v
    }

    # 未支持效果配置数（straight-line，跨模块调用可靠）
    public Int32 unsupportedCount()
    {
        Int32 c = 0
        if this.hasBloom
        {
            c = c + 1
        }
        if this.hasTonemap
        {
            c = c + 1
        }
        if this.hasDof
        {
            c = c + 1
        }
        if this.hasFog
        {
            c = c + 1
        }
        ret c
    }
}
