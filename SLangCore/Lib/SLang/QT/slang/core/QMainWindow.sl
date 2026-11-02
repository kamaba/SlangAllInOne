import Core;
import Std;

# QMainWindow —— 主窗口（顶层）
namespace SLang
{
    public class QMainWindow extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_mainwindowCreate() )
        }

        public void setCentralWidget( SLang.QWidget w ) { SLang.QT.ffi_mainwindowSetCentral( this.handle, w.handle ) }
        public void setTitle( string t ) { SLang.QT.ffi_mainwindowSetTitle( this.handle, t ) }
        public void resize( int w, int h ) { SLang.QT.ffi_mainwindowResize( this.handle, w, h ) }
        public void show() { SLang.QT.ffi_mainwindowShow( this.handle ) }
    }
}
