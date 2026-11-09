import Core;
import Std;

# UnityEngine.Renderer 的 SL 镜像（基础：材质颜色）。
namespace SlangUnity
{
    public class Renderer extends Component
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public get Color color()
        {
            ret Color(
                UnityFFI.ffi_rendererColor( this.handle, 0 ),
                UnityFFI.ffi_rendererColor( this.handle, 1 ),
                UnityFFI.ffi_rendererColor( this.handle, 2 ),
                1.0 )
        }

        public set void color( Color c )
        {
            UnityFFI.ffi_rendererSetColor( this.handle, c.r, c.g, c.b )
        }
    }
}
