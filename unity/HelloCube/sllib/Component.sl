import Core;
import Std;

# UnityEngine.Component 的 SL 镜像：组件与 GameObject 共用同一个对象句柄。
namespace SlangUnity
{
    public class Component extends Object
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public get GameObject gameObject()
        {
            ret GameObject( this.handle )
        }

        public get Transform transform()
        {
            ret Transform( this.handle )
        }

        public get string tag()
        {
            ret "Untagged"
        }
    }
}
