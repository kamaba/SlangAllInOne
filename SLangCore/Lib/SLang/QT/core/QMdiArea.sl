import Core;
import Std;

# QMdiArea —— VS 式主框架：中心多文档区（代码窗口在此以子窗形式打开）
# 原生：slqt_mdiarea_create_sl / slqt_mdiarea_add_subwindow_sl 等
# addSubWindow 返回 QMdiSubWindow 句柄，可继续 setTitle / showMaximized。
namespace SLang
{
    public class QMdiArea extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_mdiareaCreate( parent ) )
        }

        # 把内容控件包成 MDI 子窗，返回 QMdiSubWindow 句柄（0=失败）
        public Int64 addSubWindow( QWidget w )
        {
            ret SLang.QT.ffi_mdiareaAddSubWindow( this.handle, w.handle )
        }

        public int subCount() { ret SLang.QT.ffi_mdiareaCount( this.handle ) }

        public void tile() { SLang.QT.ffi_mdiareaTile( this.handle ) }

        public void cascade() { SLang.QT.ffi_mdiareaCascade( this.handle ) }

        public void closeActive() { SLang.QT.ffi_mdiareaCloseActive( this.handle ) }

        # 当前活动子窗句柄（0=无）
        public Int64 activeSubWindow() { ret SLang.QT.ffi_mdiareaActiveSub( this.handle ) }
    }
}

# QMdiSubWindow —— MDI 子窗句柄封装（QMdiArea.addSubWindow 的返回值）
namespace SLang
{
    public class QMdiSubWindow extends QWidget
    {
        _init_( Int64 handle )
        {
            this.setHandle( handle )
        }

        public void setTitle( string t ) { SLang.QT.ffi_subwindowSetTitle( this.handle, t ) }

        public void showMaximized() { SLang.QT.ffi_subwindowShowMaximized( this.handle ) }
    }
}
