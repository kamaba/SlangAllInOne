import Core;
import Std;

# UnityEngine.GameObject 的 SL 镜像。
namespace SlangUnity
{
    public class GameObject extends Object
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        # 第一版语义：按名字取代理句柄；C# 宿主在下一帧绑定到真实对象，
        # 场景里没有同名对象时懒创建一个 Cube（见使用文档「已知差异」）。
        public static GameObject Find( string name )
        {
            ret GameObject( UnityFFI.ffi_objFind( name ) )
        }

        public static GameObject Create( string name )
        {
            ret GameObject( UnityFFI.ffi_objCreate( name ) )
        }

        public get bool active()
        {
            ret UnityFFI.ffi_objActive( this.handle ) != 0
        }

        public set void active( bool value )
        {
            if value
            {
                UnityFFI.ffi_objSetActive( this.handle, 1 )
            }
            else
            {
                UnityFFI.ffi_objSetActive( this.handle, 0 )
            }
        }

        public get Transform transform()
        {
            ret Transform( this.handle )
        }

        public get Renderer renderer()
        {
            ret Renderer( this.handle )
        }

        public get AudioSource audioSource()
        {
            ret AudioSource( UnityFFI.ffi_audioGet( this.handle ) )
        }
    }
}
