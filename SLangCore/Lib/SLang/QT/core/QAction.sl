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

        # 第二十九轮：命令快捷键（QKeySequence 可移植串："Ctrl+S" / "F5" /
        # "Shift+F5"；空串清除）。菜单项文本右侧由 Qt 自动显示快捷键。
        # 注意：同一命令的菜单与工具栏是两个独立 QAction，快捷键只绑一侧，
        # 两侧都绑会一次按键触发两次命令。
        public void setShortcut( string keys ) { SLang.QT.ffi_actionSetShortcut( this.handle, keys ) }

        public void setEnabled( bool on )
        {
            int v = 0
            if ( on == true ) { v = 1 }
            SLang.QT.ffi_actionSetEnabled( this.handle, v )
        }

        # 读取自身显式启用态（不含父级 widget 状态）；诊断 / 状态机回归用
        public bool isEnabled()
        {
            int n = SLang.QT.ffi_actionEnabled( this.handle )
            if ( n == 0 ) { ret false }
            ret true
        }

        # 触发（用户点击菜单项 / 工具栏按钮）时回调 handler
        public void onTriggered( Function handler )
        {
            SLang.QT.connect( this.handle, SLang.QT.SIG_TRIGGERED, handler )
        }
    }
}
