import Core;
import Std;

# QComboBox —— 原生下拉单选（2026-11-15 第二十三轮）
# 模态对话框在「确定」时读 currentIndex() 即可，无需信号绑定。
namespace SLang
{
    public class QComboBox extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_comboCreate( parent ) )
        }

        public void addItem( string t )
        {
            SLang.QT.ffi_comboAddItem( this.handle, t )
        }

        public int count() { ret SLang.QT.ffi_comboCount( this.handle ) }

        public int currentIndex() { ret SLang.QT.ffi_comboCurrentIndex( this.handle ) }

        public void setCurrentIndex( int idx )
        {
            SLang.QT.ffi_comboSetCurrentIndex( this.handle, idx )
        }
    }
}
