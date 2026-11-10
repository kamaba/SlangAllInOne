import Core;
import Std;

# QMenu —— VS 式主框架：菜单（一级/二级均可，由 addMenu 逐级嵌套）
# 原生：slqt_menu_create_sl / slqt_menu_add_action_sl / slqt_menu_add_separator_sl
# 动作句柄（QAction）用 SLang.QT.connect( h, SIG_TRIGGERED, handler ) 挂回调。
namespace SLang
{
    public class QMenu extends QWidget
    {
        # parent 为 QMenuBar（一级）或父 QMenu（二级）的句柄
        _init_( Int64 parent, string title )
        {
            this.setHandle( SLang.QT.ffi_menuCreate( parent, title ) )
        }

        public Int64 addMenu( string title ) { ret SLang.QT.ffi_menuCreate( this.handle, title ) }

        # 添加菜单项，返回 QAction 句柄（0=失败）
        public Int64 addAction( string text ) { ret SLang.QT.ffi_menuAddAction( this.handle, text ) }

        public void addSeparator() { SLang.QT.ffi_menuAddSeparator( this.handle ) }
    }
}
