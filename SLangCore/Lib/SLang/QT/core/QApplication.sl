import Core;
import Std;

# QApplication —— 应用对象；exec() 阻塞进入 Qt 事件循环，processEvents() 单轮
namespace SLang
{
    public class QApplication extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_appCreate() )
        }

        public void setStyle( string name ) { SLang.QT.ffi_appSetStyle( name ) }
        public void setStyleSheet( string css ) { SLang.QT.ffi_appSetStyleSheet( css ) }
        public void exec() { SLang.QT.ffi_appExec() }
        public void processEvents() { SLang.QT.ffi_appProcessEvents() }
        public void quit() { SLang.QT.ffi_appQuit() }
    }
}
