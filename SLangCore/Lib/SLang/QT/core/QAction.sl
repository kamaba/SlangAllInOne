import Core;
import Std;

# QAction —— 菜单 / 工具栏动作（由 QMenu/QToolBar 创建，句柄封装）
# 原生：slqt_action_set_text_sl / slqt_action_set_enabled_sl
# 触发回调：SLang.QT.connect( handle, SLang.QT.SIG_TRIGGERED, handler )
namespace SLang
{
    public class QAction extends QObject
    {
        _init_( Int64 handle )
        {
            this.setHandle( handle )
        }

        public void setText( string t ) { SLang.QT.ffi_actionSetText( this.handle, t ) }

        public void setEnabled( bool on ) { SLang.QT.ffi_actionSetEnabled( this.handle, on ) }

        # 触发（用户点击菜单项 / 工具栏按钮）时回调 handler
        public void onTriggered( Function handler )
        {
            SLang.QT.connect( this.handle, SLang.QT.SIG_TRIGGERED, handler )
        }
    }
}
