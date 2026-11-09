import Core;
import Std;

# 与 UnityEngine.Color 对应的值类型。
namespace SlangUnity
{
    public class Color
    {
        public double r = 1.0
        public double g = 1.0
        public double b = 1.0
        public double a = 1.0

        public void _init_( double ar, double ag, double ab, double aa )
        {
            this.r = ar
            this.g = ag
            this.b = ab
            this.a = aa
        }

        public static get Color white() { ret Color( 1.0, 1.0, 1.0, 1.0 ) }
        public static get Color black() { ret Color( 0.0, 0.0, 0.0, 1.0 ) }
        public static get Color red()   { ret Color( 1.0, 0.0, 0.0, 1.0 ) }
        public static get Color green() { ret Color( 0.0, 1.0, 0.0, 1.0 ) }
        public static get Color blue()  { ret Color( 0.0, 0.0, 1.0, 1.0 ) }
        public static get Color clear() { ret Color( 0.0, 0.0, 0.0, 0.0 ) }

        public Color clone()
        {
            ret Color( this.r, this.g, this.b, this.a )
        }
    }
}
