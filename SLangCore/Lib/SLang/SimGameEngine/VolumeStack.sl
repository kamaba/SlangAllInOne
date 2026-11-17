import Core;
import Std;
import Math;

# ============================================================================
# VolumeStack — 每相机混合后的最终后处理参数（P8 Volume 落盘 v1，doc/14 §3）
# ----------------------------------------------------------------------------
# VolumeSystem.compute 的输出；brightness/saturation/vignette 即
# Render setPostEffect 的三参（中性默认 1/1/1）；contributing = 贡献
# Volume 数（0 = 无 Volume 生效 → 后处理关闭）。
# 多相机各自 compute 一份（参数栈按相机隔离，防串台，doc/14 §4/§7.5）。
# ============================================================================
public class VolumeStack
{
    public Float32 brightness = 1.0f
    public Float32 saturation = 1.0f
    public Float32 vignette = 1.0f
    # 贡献 Volume 数（weight>0 且通过范围过滤）
    public Int32 contributing = 0

    public bool hasEffect()
    {
        ret this.contributing > 0
    }
}
