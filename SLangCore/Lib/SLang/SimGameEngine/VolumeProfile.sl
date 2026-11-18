import Core;
import Std;
import Math;

# ============================================================================
# VolumeProfile — Volume 效果配置资源（P8 Volume v1.1 扩参，doc/14 §2/§5）
# ----------------------------------------------------------------------------
# 可共享资源（多个 Volume 组件引用同一实例，MaterialData 同款）。
# v1.1 可下发字段（Unity URP Color Adjustments / Vignette / Film Grain /
# Tonemapping 子集，GL/GLES 后端全量消费；VK/D3D11 只吃 brightness/
# saturation/vignette 三参，其余静默忽略——doc/14 §5 兼容表）：
#   brightness 曝光 / contrast 对比度 / saturation 饱和度
#   vignette 暗角强度 / vignetteSmooth 暗角柔度（1 = 标准曲线）
#   hueShift 色相偏移（角度制）/ grain 胶片颗粒强度 / tonemap 0 关 1 Reinhard
#   colorFilter 颜色滤片（乘法 tint RGB）
# **缺省语义是「不修改」**（掩码 hasXxx，doc/14 §3.1：只配了暗角的
# Profile 不得把亮度清掉）；
# Bloom/DOF/Fog 仍存参数不下发（unsupportedCount 统计，需 Render HDR
# 中间缓冲，M5；防「以为生效」误判）。
# 计算分工（复用专项约定）：混合数学在 C（sle_volume_blend，块布局
# 24 float/Volume），本类与 Volume/VolumeSystem 只做数据与组块。
# ============================================================================
public class VolumeProfile
{
    public string name = "Profile"
    # ── 可下发：Color Adjustments ──
    public bool hasBrightness = false
    public Float32 brightness = 1.0f
    public bool hasContrast = false
    public Float32 contrast = 1.0f
    public bool hasSaturation = false
    public Float32 saturation = 1.0f
    public bool hasHueShift = false
    public Float32 hueShift = 0.0f
    public bool hasFilter = false
    public Float32 filterR = 1.0f
    public Float32 filterG = 1.0f
    public Float32 filterB = 1.0f
    # ── 可下发：Vignette ──
    public bool hasVignette = false
    public Float32 vignette = 1.0f
    public bool hasVignetteSmooth = false
    public Float32 vignetteSmooth = 1.0f
    # ── 可下发：Film Grain / Tonemapping ──
    public bool hasGrain = false
    public Float32 grain = 0.0f
    public bool hasTonemap = false
    public Int32 tonemapMode = 0     # 0 = 关 / 1 = Reinhard（LDR 近似；ACES 需 M5）
    # ── 未支持效果（存参数不下发）──
    public bool hasBloom = false
    public Float32 bloomIntensity = 0.0f
    public bool hasDof = false
    public Float32 dofFocusDistance = 0.0f
    public bool hasFog = false
    public Float32 fogDensity = 0.0f

    # 一次配齐基础三参（掩码置位；v1 兼容入口）
    public void setPost( Float32 b, Float32 s, Float32 v )
    {
        this.setBrightness( b )
        this.setSaturation( s )
        this.setVignette( v )
    }

    public void setBrightness( Float32 b )
    {
        this.hasBrightness = true
        this.brightness = b
    }

    public void setContrast( Float32 c )
    {
        this.hasContrast = true
        this.contrast = c
    }

    public void setSaturation( Float32 s )
    {
        this.hasSaturation = true
        this.saturation = s
    }

    public void setHueShift( Float32 deg )
    {
        this.hasHueShift = true
        this.hueShift = deg
    }

    public void setColorFilter( Float32 r, Float32 g, Float32 b )
    {
        this.hasFilter = true
        this.filterR = r
        this.filterG = g
        this.filterB = b
    }

    public void setVignette( Float32 v )
    {
        this.hasVignette = true
        this.vignette = v
    }

    public void setVignetteSmooth( Float32 s )
    {
        this.hasVignetteSmooth = true
        this.vignetteSmooth = s
    }

    public void setGrain( Float32 amt )
    {
        this.hasGrain = true
        this.grain = amt
    }

    # tonemap：0 = 关 / 1 = Reinhard（枚举语义：不插值，高优先级覆盖）
    public void setTonemap( Int32 mode )
    {
        this.hasTonemap = true
        this.tonemapMode = mode
    }

    # 未支持效果配置数（straight-line，跨模块调用可靠）
    public Int32 unsupportedCount()
    {
        Int32 c = 0
        if this.hasBloom
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
