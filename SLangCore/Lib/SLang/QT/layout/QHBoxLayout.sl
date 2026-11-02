import Core;
import Std;

# QHBoxLayout —— 水平盒子布局
namespace SLang
{
    public class QHBoxLayout extends QLayout
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_hboxCreate( parent ) )
        }
    }
}
