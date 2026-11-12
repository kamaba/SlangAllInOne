import Std;
import Math;

# 射线（屏幕拾取用；Mesh.sl 明确不引入 Ray，这里就近定义）
public class Ray
{
    public Float32_3 origin = Float32_3.zero()
    public Float32_3 direction = Float32_3.forward()

    public void _init_()
    {
        this.origin = Float32_3.zero()
        this.direction = Float32_3.forward()
    }

    public void _init_( Float32_3 _origin, Float32_3 _direction )
    {
        this.origin = _origin.clone()
        this.direction = _direction.normalize()
    }

    # 射线上 t 处的点
    public Float32_3 getPoint( Float32 t )
    {
        ret this.origin._add_( this.direction.scale( t ) ) as Float32_3
    }

    override string toString()
    {
        ret "Ray(origin=" + this.origin.toString() + ", dir=" + this.direction.toString() + ")"
    }
}