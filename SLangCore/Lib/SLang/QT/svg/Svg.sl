import Core;
import Std;

# QSvgWidget / QSvgRenderer —— Qt6Svg / Qt6SvgWidgets 封装
namespace SLang
{
    public class QSvgWidget extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_svgWidgetCreate( parent ) )
        }

        public bool loadFile( string path ) { ret SLang.QT.ffi_svgWidgetLoadFile( this.handle, path ) }
        public bool loadData( string xml ) { ret SLang.QT.ffi_svgWidgetLoadData( this.handle, xml ) }
    }

    public class QSvgRenderer extends QObject
    {
        _init_( string xml )
        {
            this.setHandle( SLang.QT.ffi_svgRendererCreate( xml ) )
        }

        public bool isValid() { ret SLang.QT.ffi_svgRendererValid( this.handle ) }
        public bool checkSize( int w, int h ) { ret SLang.QT.ffi_svgRendererCheckSize( this.handle, w, h ) }

        # 渲染到既有 QLabel（QPixmap 中转，Qt6Svg 光栅化通道）；label 是 SL
        # 关键字，参数名用 lab
        public bool renderToLabel( SLang.QLabel lab, int w, int h )
        {
            ret SLang.QT.ffi_svgRenderToLabel( this.handle, lab.handle, w, h )
        }
    }
}
