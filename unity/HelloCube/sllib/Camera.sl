import Core;
import Std;

# UnityEngine.Camera 的 SL 镜像（基础属性：main / fieldOfView）。
namespace SlangUnity
{
    public class Camera extends Component
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public static get Camera main()
        {
            ret Camera( UnityFFI.ffi_camMain() )
        }

        public get double fieldOfView()
        {
            ret UnityFFI.ffi_camFov( this.handle )
        }

        public set void fieldOfView( double value )
        {
            UnityFFI.ffi_camSetFov( this.handle, value )
        }
    }
}
