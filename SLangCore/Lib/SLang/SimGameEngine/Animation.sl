import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Animation — 关键帧动画组件（P5，doc/07 §3）
# ----------------------------------------------------------------------------
# 路径 B（自定义采样）：轨道值写回宿主节点 Transform / MaterialRef。
# 与路径 A（RenderObject.setAnimated 内置模式）的分工见 doc/07 §1：
# 批量轻量效果优先 A（不拆批）；需要精确时间轴才用本组件（会拆单对象批）。
# 驱动方式二选一：
#   1. system/AnimSystem.update(scene, dt)（Application.animSystem 接入，
#      每帧自动推进所有 playing 的 Animation——推荐）
#   2. 手动 anim.advance(dt) + anim.evaluate(anim.time)
# 坑（doc/07 §6.6）：销毁节点先 stop() 再 destroy()。
# ============================================================================

public class Animation extends Behaviour
{
    public AnimationClip clip = null
    public Float32 speed = 1.0f
    public Float32 time = 0.0f
    public bool playing = false

    # ── 控制 ────────────────────────────────────────────
    public void play()
    {
        this.playing = true
    }

    public void pause()
    {
        this.playing = false
    }

    public void stop()
    {
        this.playing = false
        this.time = 0.0f
    }

    # 推进：dt*speed；loop 对 duration 取模；到尾停住（非 loop）返回 false
    public bool advance( Float32 dt )
    {
        if this.playing == false || this.clip == null
        {
            ret false
        }
        Float32 dur = this.clip.duration
        this.time = this.time + dt * this.speed
        if dur <= 0.0f
        {
            ret false
        }
        if this.time >= dur
        {
            if this.clip.loop
            {
                this.time = this.time - dur * Mathf.floor( this.time / dur )
                if this.time >= dur
                {
                    this.time = 0.0f
                }
            }
            else
            {
                this.time = dur
                this.playing = false
                ret false
            }
        }
        ret true
    }

    # 采样写回：position/rotationZ/scale → Transform；color → MaterialRef
    public void evaluate( Float32 t )
    {
        if this.clip == null
        {
            ret
        }
        GameObject go = this.owner
        if go == null
        {
            ret
        }
        Transform trans = go.transform
        MaterialRef mref = go.getComponent<MaterialRef>()
        Float32_3 v = Float32_3.zero()
        Int32 n = this.clip.trackCount()
        Int32 i = 0
        while i < n
        {
            AnimationTrack track = this.clip.trackAt( i )
            string binding = track.binding
            if binding == "position"
            {
                if track.sample( t, v )
                {
                    trans.setPosition( v )
                }
            }
            elif binding == "rotationZ"
            {
                if track.sample( t, v )
                {
                    trans.setRotationZ( v.x )
                }
            }
            elif binding == "scale"
            {
                if track.sample( t, v )
                {
                    trans.setScale( v )
                }
            }
            elif binding == "color"
            {
                if mref != null
                {
                    if track.sample( t, v )
                    {
                        mref.instanceColor = v
                    }
                }
            }
            i = i + 1
        }
    }
}
