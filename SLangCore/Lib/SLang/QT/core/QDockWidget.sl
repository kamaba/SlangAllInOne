import Core;
import Std;

# QDockWidget —— VS 式主框架：自由停靠面板（可关 / 可浮动 / 可拖拽换区）
# 原生：slqt_dock_create_sl / slqt_mainwindow_add_dock_sl / slqt_dock_set_widget_sl
# area 取 Qt::DockWidgetArea 位值：1=左 2=右 4=顶 8=底
# features 取 QDockWidget::Feature 位值：1=Closable 2=Movable 4=Floatable 8=VerticalTitleBar
namespace SLang
{
    public class QDockWidget extends QWidget
    {
        _init_( Int64 parent, string title )
        {
            this.setHandle( SLang.QT.ffi_dockCreate( parent, title ) )
        }

        # 把内容控件装进 Dock（标题沿用构造时传入的 title）
        public void setDockWidget( QWidget w )
        {
            SLang.QT.ffi_dockSetWidget( this.handle, w.handle )
        }

        # 覆盖默认 feature 位组合（按需收紧，如侧栏锁死浮动）
        public void setFeatures( int f ) { SLang.QT.ffi_dockSetFeatures( this.handle, f ) }

        public void setFloating( bool on ) { SLang.QT.ffi_dockSetFloating( this.handle, on ) }
    }
}
