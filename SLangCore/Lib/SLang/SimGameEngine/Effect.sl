import Core;
import Std;
import Math;

# Effect - VFX component (P5, doc/07 §4). Thin data component owning the
# timeline and lifecycle: flash/tint effects should use RenderObject
# setAnimated (path A, batch friendly); trails/particles update vertices
# via uploadMesh on the caller side. Non-loop effects auto-stop at
# duration and, with autoDestroy=true, register the host node for
# deferred destroy (collected by Scene.processDestroys at frame end).
public class Effect extends Behaviour
{
    public Int32 effectType = 0
    public Float32 duration = 1.0f
    public bool loop = false
    public bool autoDestroy = false

    public Float32 elapsed = 0.0f
    public bool playing = false

    public void play()
    {
        this.elapsed = 0.0f
        this.playing = true
    }

    public void stop()
    {
        this.playing = false
    }

    # advance timeline (drive per frame like AnimSystem);
    # returns true while still playing
    public bool advance( Float32 dt )
    {
        if this.playing == false
        {
            ret false
        }
        this.elapsed = this.elapsed + dt
        if this.elapsed >= this.duration
        {
            if this.loop
            {
                this.elapsed = this.elapsed - this.duration * Mathf.floor( this.elapsed / this.duration )
                if this.elapsed >= this.duration
                {
                    this.elapsed = 0.0f
                }
            }
            else
            {
                this.elapsed = this.duration
                this.playing = false
                if this.autoDestroy
                {
                    GameObject go = this.owner
                    if go != null
                    {
                        go.destroy()
                    }
                }
                ret false
            }
        }
        ret true
    }
}