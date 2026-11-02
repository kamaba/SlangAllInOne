import Core;
import Std;

# QObject —— slQT 所有封装类的基类：持有原生句柄，提供 isValid / delete / handle 读取
namespace SLang
{
    public class QObject
    {
        Int64 _handle = 0

        _init_()
        {
        }

        # 供子类在构造函数里设置原生句柄（避免覆盖 _init_ 造成递归）
        public void setHandle( Int64 h )
        {
            this._handle = h
        }

        # 供 SL 侧直接按句柄构造（如跨模块传参）
        public void _init_( Int64 handle )
        {
            this._handle = handle
        }

        get Int64 handle() { ret this._handle }

        public bool isValid() { ret this._handle != 0 && SLang.QT.ffi_objectIsValid( this._handle ) }

        public void delete()
        {
            SLang.QT.ffi_objectDelete( this._handle )
            this._handle = 0
        }
    }
}
