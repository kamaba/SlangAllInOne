import Core;
import Std;

# QDialog —— 弹窗类控件基类（BaseDialog 的原生支撑）
# 原生：slqt_dialog_create_sl / slqt_dialog_set_modal_sl / slqt_dialog_exec_sl
namespace SLang
{
    public class QDialog extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_dialogCreate( parent ) )
        }

        public void setModal( bool on ) { SLang.QT.ffi_dialogSetModal( this.handle, on ) }

        # 模态执行：0=Rejected 1=Accepted
        public int exec() { ret SLang.QT.ffi_dialogExec( this.handle ) }

        public void accept() { SLang.QT.ffi_dialogAccept( this.handle ) }

        public void reject() { SLang.QT.ffi_dialogReject( this.handle ) }
    }
}
