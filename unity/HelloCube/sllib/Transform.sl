import Core;
import Std;

# UnityEngine.Transform 的 SL 镜像。属性读写直调 C++ 句柄表。
namespace SlangUnity
{
    public class Transform extends Component
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public get Vector3 position()
        {
            ret Vector3(
                UnityFFI.ffi_trPos( this.handle, 0 ),
                UnityFFI.ffi_trPos( this.handle, 1 ),
                UnityFFI.ffi_trPos( this.handle, 2 ) )
        }

        public set void position( Vector3 v )
        {
            UnityFFI.ffi_trSetPos( this.handle, v.x, v.y, v.z )
        }

        public get Vector3 eulerAngles()
        {
            ret Vector3(
                UnityFFI.ffi_trRot( this.handle, 0 ),
                UnityFFI.ffi_trRot( this.handle, 1 ),
                UnityFFI.ffi_trRot( this.handle, 2 ) )
        }

        public set void eulerAngles( Vector3 v )
        {
            UnityFFI.ffi_trSetRot( this.handle, v.x, v.y, v.z )
        }

        public get Vector3 localScale()
        {
            ret Vector3(
                UnityFFI.ffi_trScale( this.handle, 0 ),
                UnityFFI.ffi_trScale( this.handle, 1 ),
                UnityFFI.ffi_trScale( this.handle, 2 ) )
        }

        public set void localScale( Vector3 v )
        {
            UnityFFI.ffi_trSetScale( this.handle, v.x, v.y, v.z )
        }

        public void SetPositionAndRotation( Vector3 p, Vector3 r )
        {
            UnityFFI.ffi_trSetPos( this.handle, p.x, p.y, p.z )
            UnityFFI.ffi_trSetRot( this.handle, r.x, r.y, r.z )
        }

        public void Translate( Vector3 v )
        {
            UnityFFI.ffi_trTranslate( this.handle, v.x, v.y, v.z )
        }

        # SL 扩展：把逐帧自转/浮动交给 C++ 推进，VM 无需每帧回调。
        public void setSpin( double degreesPerSecond )
        {
            UnityFFI.ffi_trSetSpin( this.handle, degreesPerSecond )
        }

        public void setBob( double amplitude, double speed )
        {
            UnityFFI.ffi_trSetBob( this.handle, amplitude, speed )
        }
    }
}
