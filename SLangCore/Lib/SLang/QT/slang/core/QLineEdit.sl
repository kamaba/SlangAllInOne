import Core;
import Std;

# QLineEdit —— 单行文本输入框；textChanged(string) / returnPressed() 信号
namespace SLang
{
    public class QLineEdit extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_editCreate( parent ) )
        }

        public void setPlaceholder( string p ) { SLang.QT.ffi_editSetPlaceholder( this.handle, p ) }

        # 覆盖 QWidget.text()：读取输入框文本
        public string text() { ret SLang.QT.ffi_editText( this.handle ) }

        public void setReadOnly( bool on ) { SLang.QT.ffi_editSetReadonly( this.handle, on ) }

        public Int64 onTextChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TEXT_CHANGED, handler )
        }

        public Int64 onReturnPressed( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_RETURN_PRESSED, handler )
        }
    }
}
