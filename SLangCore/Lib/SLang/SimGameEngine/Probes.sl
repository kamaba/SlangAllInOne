import Core;
import Std;
import Math;

# Probes - light/reflection probe data structures (P5, doc/06).
# v0.1: data + scene collection only; sampling/blending lands with the
# Render-side lighting pipeline. Field reads on Behaviour subclasses are
# unreliable cross-module (doc/10 §6) - consumers should live in the
# engine module (lighting collector) or read via same-module code.
public class LightProbe extends Behaviour
{
    public Float32_3 position = Float32_3.zero()
    public Float32 ambient = 1.0f
    public Float32_3 tintColor = Float32_3( 1.0f, 1.0f, 1.0f )
    public Int32 weight = 1
}

public class ReflectionProbe extends Behaviour
{
    public Bounds bounds = Bounds()
    public Int32 cubemapSlot = 0 - 1
    public Float32 intensity = 1.0f
    public Int32 priority = 0
}