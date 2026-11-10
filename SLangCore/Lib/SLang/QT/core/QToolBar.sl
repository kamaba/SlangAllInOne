import Core;
import Std;

# QToolBar —— VS 式主框架：菜单栏下方的快捷图标入口区
# 原生：slqt_toolbar_create_sl / slqt_mainwindow_add_toolbar_sl / slqt_toolbar_add_action_sl
namespace SLang
{
    public class QToolBar extends QWidget
    {
        _init_( Int64 parent, string title )
        {
            this.setHandle( SLang.QT.ffi_toolbarCreate( parent, title ) )
        }

        # 添加快捷入口按钮，返回 QAction 句柄（0=失败）
        public Int64 addAction( string text ) { ret SLang.QT.ffi_toolbarAddAction( this.handle, text ) }

        public void addSeparator() { SLang.QT.ffi_toolbarAddSeparator( this.handle ) }
    }
}
