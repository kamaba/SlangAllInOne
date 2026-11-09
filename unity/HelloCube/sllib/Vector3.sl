import Core;
import Std;

# 与 UnityEngine.Vector3 对应的轻量值类型（分量用 double，避免跨模块 Math 依赖）。
namespace SlangUnity
{
    public class Vector3
    {
        public double x = 0.0
        public double y = 0.0
        public double z = 0.0

        public void _init_( double ax, double ay, double az )
        {
            this.x = ax
            this.y = ay
            this.z = az
        }

        public static get Vector3 zero()    { ret Vector3( 0.0, 0.0, 0.0 ) }
        public static get Vector3 one()     { ret Vector3( 1.0, 1.0, 1.0 ) }
        public static get Vector3 up()      { ret Vector3( 0.0, 1.0, 0.0 ) }
        public static get Vector3 down()    { ret Vector3( 0.0, -1.0, 0.0 ) }
        public static get Vector3 right()   { ret Vector3( 1.0, 0.0, 0.0 ) }
        public static get Vector3 left()    { ret Vector3( -1.0, 0.0, 0.0 ) }
        public static get Vector3 forward() { ret Vector3( 0.0, 0.0, 1.0 ) }
        public static get Vector3 back()    { ret Vector3( 0.0, 0.0, -1.0 ) }

        public Vector3 add( Vector3 v )
        {
            ret Vector3( this.x + v.x, this.y + v.y, this.z + v.z )
        }

        public Vector3 scale( double s )
        {
            ret Vector3( this.x * s, this.y * s, this.z * s )
        }

        public Vector3 clone()
        {
            ret Vector3( this.x, this.y, this.z )
        }
    }
}
