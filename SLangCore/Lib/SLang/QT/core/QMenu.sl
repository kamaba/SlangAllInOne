import Core;
import Std;

# QMenu —— VS 式主框架：菜单（一级/二级均可，由 addMenu 逐级嵌套）
# 原生：slqt_menu_create_sl / slqt_menu_create_popup_sl / slqt_menu_add_action_sl
#       / slqt_menu_add_separator_sl / slqt_menu_popup_exec_sl
# 动作句柄（QAction）用 SLang.QT.connect( h, SIG_TRIGGERED, handler ) 挂回调。
# 弹出式菜单（第十四轮）：createPopup 独立创建，popupExec 在控件局部坐标处
# 阻塞弹出并返回被选中 QAction 句柄（0=取消），用于右键上下文菜单。
namespace SLang
{
    public class QMenu extends QWidget
    {
        # parent 为 QMenuBar（一级）或父 QMenu（二级）的句柄
        _init_( Int64 parent, string title )
        {
            this.setHandle( SLang.QT.ffi_menuCreate( parent, title ) )
        }

        # 按已有句柄收养（popup_exec 返回的 QAction/菜单句柄桥接用）
        _init_( Int64 handle, bool adopt )
        {
            this.setHandle( handle )
        }

        public static QMenu fromHandle( Int64 h ) { ret QMenu( h, true ) }

        # 独立弹出菜单（不挂菜单栏）
        public static QMenu createPopup( string title )
        {
            ret QMenu.fromHandle( SLang.QT.ffi_menuCreatePopup( title ) )
        }

        # 在 anchor 控件 (x,y) 局部坐标处阻塞弹出；返回选中 QAction 句柄（0=取消）
        public Int64 popupExec( Int64 anchor, int x, int y )
        {
            ret SLang.QT.ffi_menuPopupExec( this.handle, anchor, x, y )
        }

        # 在当前鼠标位置阻塞弹出；返回选中 QAction 句柄（0=取消）
        public Int64 popupCursor() { ret SLang.QT.ffi_menuPopupCursor( this.handle ) }

        public Int64 addMenu( string title ) { ret SLang.QT.ffi_menuCreate( this.handle, title ) }

        # 添加菜单项，返回 QAction 句柄（0=失败）
        public Int64 addAction( string text ) { ret SLang.QT.ffi_menuAddAction( this.handle, text ) }

        public void addSeparator() { SLang.QT.ffi_menuAddSeparator( this.handle ) }
    }
}
