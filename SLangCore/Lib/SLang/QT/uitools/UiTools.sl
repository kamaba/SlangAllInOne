import Core;
import Std;

# QUiLoader / QFormBuilder / QLoadedWidget —— .ui 文件装载双通道
# （QUiLoader = Qt6UiTools；QFormBuilder = Qt6Designer）
namespace SLang
{
    # 句柄收养控件：装载器产出的 QWidget 按句柄接管（继承 show/move 等）
    public class QLoadedWidget extends QWidget
    {
        _init_( Int64 handle )
        {
            this.setHandle( handle )
        }
    }

    public class QUiLoader extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_uiLoaderCreate() )
        }

        public QLoadedWidget loadFile( string path, SLang.QWidget parent )
        {
            Int64 ph = 0
            if ( parent != null ) { ph = parent.handle }
            QLoadedWidget w = QLoadedWidget( SLang.QT.ffi_uiLoaderLoadFile( this.handle, path, ph ) )
            ret w
        }

        public string availableWidgets() { ret SLang.QT.ffi_uiLoaderAvailableWidgets( this.handle ) }
    }

    public class QFormBuilder extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_formBuilderCreate() )
        }

        public QLoadedWidget loadFile( string path, SLang.QWidget parent )
        {
            Int64 ph = 0
            if ( parent != null ) { ph = parent.handle }
            QLoadedWidget w = QLoadedWidget( SLang.QT.ffi_formBuilderLoad( this.handle, path, ph ) )
            ret w
        }
    }
}
