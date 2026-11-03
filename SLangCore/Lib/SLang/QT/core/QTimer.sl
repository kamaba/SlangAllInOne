import Core;
import Std;

# QTimer —— 定时器：超时经 dispatchVoid 桥重入 VM（动画面板 / 周期任务）
namespace SLang
{
    public class QTimer extends QObject
    {
        _init_( int ms, bool single, Function handler )
        {
            this.setHandle( SLang.QT.timer( ms, single, handler ) )
        }

        public void start( int ms ) { SLang.QT.ffi_timerStart( this.handle, ms ) }
        public void stop() { SLang.QT.ffi_timerStop( this.handle ) }
        public bool isActive() { ret SLang.QT.ffi_timerActive( this.handle ) }
    }
}
