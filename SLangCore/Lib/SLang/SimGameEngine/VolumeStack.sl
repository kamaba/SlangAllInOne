import Core;
import Std;
import Math;

# ============================================================================
# VolumeStack — 每相机混合后的最终后处理参数（P8 Volume v1.1，doc/14 §3）
# ----------------------------------------------------------------------------
# VolumeSystem.compute 的输出；字段即 setPostParams 参数块的最终值
# （中性默认 = 无效果：brightness/contrast/saturation/filter = 1、
# hueShift/grain/tonemap = 0、vignette = 0、vigSmooth = 1）；contributing =
# 贡献 Volume 数（0 = 无 Volume 生效 → 后处理关闭）。
# 多相机各自 compute 一份（参数栈按相机隔离，防串台，doc/14 §4/§7.5）。
# ============================================================================
public class VolumeStack
{
    # Color Adjustments
    public Float32 brightness = 1.0f
    public Float32 contrast = 1.0f
    public Float32 saturation = 1.0f
    public Float32 hueShift = 0.0f
    public Float32 filterR = 1.0f
    public Float32 filterG = 1.0f
    public Float32 filterB = 1.0f
    # Vignette
    public Float32 vignette = 0.0f
    public Float32 vignetteSmooth = 1.0f
    # Film Grain / Tonemapping
    public Float32 grain = 0.0f
    public Int32 tonemap = 0        # 0 = 关 / 1 = Reinhard
    # 贡献 Volume 数（weight>0 且通过范围过滤）
    public Int32 contributing = 0

    public bool hasEffect()
    {
        ret this.contributing > 0
    }
}
