import Core;
import Std;

# QVBoxLayout —— 垂直盒子布局
namespace SLang
{
    public class QVBoxLayout extends QLayout
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_vboxCreate( parent ) )
        }
    }
}
