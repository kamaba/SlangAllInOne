import Core;
import Std;

# QLabel —— 标签（文本展示）
namespace SLang
{
    public class QLabel extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_labelCreate( parent ) )
        }
    }
}
