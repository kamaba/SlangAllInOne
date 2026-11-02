import Core;
import Std;

# QLayout —— 布局基类（盒子/网格共通操作）
namespace SLang
{
    public class QLayout extends QObject
    {
        public void addWidget( SLang.QWidget w ) { SLang.QT.ffi_layoutAddWidget( this.handle, w.handle ) }
        public void addSpacing( int px ) { SLang.QT.ffi_layoutAddSpacing( this.handle, px ) }
        public void addStretch( int s ) { SLang.QT.ffi_layoutAddStretch( this.handle, s ) }
        public void setContentsMargins( int l, int t, int r, int b ) { SLang.QT.ffi_layoutSetContentsMargins( this.handle, l, t, r, b ) }
        public void setSpacing( int px ) { SLang.QT.ffi_layoutSetSpacing( this.handle, px ) }
    }
}
