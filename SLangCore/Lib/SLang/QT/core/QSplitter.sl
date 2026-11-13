import Core;
import Std;

# QSplitter —— 精确尺寸比例控制（能力登记表 D-05 回补，2026-11-12）
# vertical=true 为纵向分隔；setSizes 最多三段，0 表示该段不参与。
namespace SLang
{
    public class QSplitter extends QWidget
    {
        _init_( Int64 parent, bool vertical )
        {
            this.setHandle( SLang.QT.ffi_splitterCreate( parent, vertical ) )
        }

        public void addWidget( QWidget w )
        {
            SLang.QT.ffi_splitterAddWidget( this.handle, w.handle )
        }

        public void setSizes( int a, int b, int c )
        {
            SLang.QT.ffi_splitterSetSizes( this.handle, a, b, c )
        }
    }
}
