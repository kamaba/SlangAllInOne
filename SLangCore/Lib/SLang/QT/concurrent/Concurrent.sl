import Core;
import Std;

# QConcurrentTask —— Qt6Concurrent 封装（工作线程原生计算，结果轮询）
# kind 0 = 累加 1..n；kind 1 = 素数计数 < n（计算在 Qt 线程池，不重入 VM）
namespace SLang
{
    public class QConcurrentTask extends QObject
    {
        _init_( int kind, Int64 n )
        {
            this.setHandle( SLang.QT.ffi_concurrentTaskCreate( kind, n ) )
        }

        public bool isFinished() { ret SLang.QT.ffi_concurrentTaskIsFinished( this.handle ) }
        public Int64 result() { ret SLang.QT.ffi_concurrentTaskResult( this.handle ) }
    }
}
