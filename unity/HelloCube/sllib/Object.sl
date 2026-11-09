import Core;
import Std;

# UnityEngine.Object 的 SL 镜像基类：持不透明句柄，不直接持有引擎对象指针。
namespace SlangUnity
{
    public class Object
    {
        public Int64 handle = 0

        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public get string name()
        {
            ret UnityFFI.ffi_objName( this.handle )
        }

        public get bool isValid()
        {
            ret UnityFFI.ffi_objValid( this.handle ) != 0
        }

        public static void Destroy( Object obj )
        {
            # 第一版不释放句柄（句柄表复用槽位），仅置无效操作占位。
            UnityFFI.ffi_objValid( obj.handle )
        }
    }
}
