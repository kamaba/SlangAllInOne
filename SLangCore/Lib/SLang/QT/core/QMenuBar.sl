import Core;
import Std;

# QMenuBar —— VS 式主框架：主窗口顶部菜单条（一级菜单入口）
# 原生：slqt_menubar_create_sl / slqt_mainwindow_set_menubar_sl
namespace SLang
{
    public class QMenuBar extends QWidget
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_menubarCreate() )
        }

        # 添加一级菜单，返回 QMenu 句柄（0=失败）；继续用该句柄挂二级菜单或动作
        public Int64 addMenu( string title )
        {
            ret SLang.QT.ffi_menuCreate( this.handle, title )
        }
    }
}
