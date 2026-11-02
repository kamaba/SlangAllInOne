import Core;
import Std;

# QGridLayout —— 网格布局
namespace SLang
{
    public class QGridLayout extends QLayout
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_gridCreate( parent ) )
        }

        public void addWidgetAt( SLang.QWidget w, int row, int col, int rspan, int cspan )
        {
            SLang.QT.ffi_layoutSetWidgetAt( this.handle, w.handle, row, col, rspan, cspan )
        }
    }
}
