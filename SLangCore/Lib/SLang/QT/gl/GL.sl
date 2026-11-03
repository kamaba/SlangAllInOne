import Core;
import Std;

# QGLPanel —— QOpenGLWidget 封装（旋转三角动画面板，Qt6OpenGLWidgets）
namespace SLang
{
    public class QGLPanel extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_glWidgetCreate( parent ) )
        }

        public void setColor( int r, int g, int b ) { SLang.QT.ffi_glWidgetSetColor( this.handle, r, g, b ) }
        public void setSpinning( bool on ) { SLang.QT.ffi_glWidgetSetSpinning( this.handle, on ) }
        public Int64 frameCount() { ret SLang.QT.ffi_glWidgetFrameCount( this.handle ) }
    }
}
