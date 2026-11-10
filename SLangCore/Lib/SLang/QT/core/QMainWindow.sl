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

        # ── 2026-11-10 VS 式主框架：菜单条 / 工具栏 / Dock 挂载 ──
        # setMenuBar 交出 QMenuBar 的所有权（QMainWindow 成为父对象）
        public void setMenuBar( SLang.QMenuBar mb ) { SLang.QT.ffi_mainwindowSetMenubar( this.handle, mb.handle ) }

        # 工具栏停靠在窗口顶部（Qt::TopToolBarArea）
        public void addToolBar( SLang.QToolBar tb ) { SLang.QT.ffi_mainwindowAddToolbar( this.handle, tb.handle ) }

        # area 取 Qt::DockWidgetArea 位值：1=左 2=右 4=顶 8=底
        public void addDockWidget( SLang.QDockWidget dock, int area ) { SLang.QT.ffi_mainwindowAddDock( this.handle, dock.handle, area ) }
    }
}
