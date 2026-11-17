import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# AnimationClip / AnimationTrack / Keyframe — 关键帧动画数据（P5，doc/07 §3.1）
# ----------------------------------------------------------------------------
# 三态轨道统一用 Float32_3 承载：
#   "position"  → Transform.setPosition(value)
#   "rotationZ" → Transform.setRotationZ(value.x)
#   "scale"     → Transform.setScale(value)
#   "color"     → MaterialRef.instanceColor = value（宿主挂了 MaterialRef 才生效）
# 容器访问走方法式 API（trackCount/trackAt/addTrack）——「方法返回值形态的
# List 容器跨模块读坏」规避家族（doc/10 §6），字段不对外暴露 List。
# ============================================================================

public class Keyframe
{
    public Float32 time = 0.0f
    public Float32_3 value = Float32_3.zero()
}

public class AnimationTrack
{
    public string binding = "position"
    List<Keyframe> _keys = List<Keyframe>( 4 )

    public void addKey( Float32 time, Float32_3 value )
    {
        Keyframe k = Keyframe()
        k.time = time
        k.value = value
        this._keys.add( k )
    }

    public Int32 keyCount()
    {
        ret this._keys.length
    }

    # 采样：t 处线性插值，结果写入 outValue（写入式 API——返回值只报是否命中）
    public bool sample( Float32 t, Float32_3 outValue )
    {
        Int32 n = this._keys.length
        if n <= 0
        {
            ret false
        }
        Int32 z0 = 0
        Keyframe first = this._keys[z0]
        if t <= first.time
        {
            outValue.setValue( first.value.x, first.value.y, first.value.z )
            ret true
        }
        Int32 zl = n - 1
        Keyframe last = this._keys[zl]
        if t >= last.time
        {
            outValue.setValue( last.value.x, last.value.y, last.value.z )
            ret true
        }
        Int32 i = 1
        while i < n
        {
            Keyframe b = this._keys[i]
            if t <= b.time
            {
                Int32 zp = i - 1
                Keyframe a = this._keys[zp]
                Float32 span = b.time - a.time
                Float32 k = 0.0f
                if span > 0.000001f
                {
                    k = ( t - a.time ) / span
                }
                Float32 ax = a.value.x + ( b.value.x - a.value.x ) * k
                Float32 ay = a.value.y + ( b.value.y - a.value.y ) * k
                Float32 az = a.value.z + ( b.value.z - a.value.z ) * k
                outValue.setValue( ax, ay, az )
                ret true
            }
            i = i + 1
        }
        ret false
    }
}

public class AnimationClip
{
    public string name = "clip"
    public Float32 duration = 0.0f
    public bool loop = true

    List<AnimationTrack> _tracks = List<AnimationTrack>( 4 )

    public AnimationTrack addTrack( string binding )
    {
        AnimationTrack tk = AnimationTrack()
        tk.binding = binding
        this._tracks.add( tk )
        ret tk
    }

    public Int32 trackCount()
    {
        ret this._tracks.length
    }

    public AnimationTrack trackAt( Int32 i )
    {
        AnimationTrack tk = this._tracks[i]
        ret tk
    }
}
