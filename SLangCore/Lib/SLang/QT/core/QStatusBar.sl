import Core;
import Std;

# QStatusBar —— 主窗口原生状态条（能力登记表 D-04 回补，2026-11-12）
# 替代此前用「底部 QDockWidget + QLabel」承载状态文本的降级方案。
namespace SLang
{
    public class QStatusBar extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_statusbarCreate( parent ) )
        }

        # timeout=0：常驻消息，不被临时消息覆盖后立刻消失
        public void showMessage( string text )
        {
            SLang.QT.ffi_statusbarShowMessage( this.handle, text )
        }

        # 右侧常驻控件（语言 / 行列号 / 分区说明）
        public void addWidget( QWidget w )
        {
            SLang.QT.ffi_statusbarAddWidget( this.handle, w.handle )
        }

        public void attachTo( Int64 mainWindowHandle )
        {
            SLang.QT.ffi_mainwindowSetStatusbar( mainWindowHandle, this.handle )
        }
    }
}
