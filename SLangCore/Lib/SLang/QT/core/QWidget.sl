import Core;
import Std;

# QWidget —— 通用控件基类（窗口/按钮/标签/输入框/布局的父类型）
namespace SLang
{
    public class QWidget extends QObject
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_widgetCreate( parent ) )
        }

        public void setText( string t ) { SLang.QT.ffi_widgetSetText( this.handle, t ) }
        # 顶层控件等价于窗口标题（Qt 后端对 QWidget 调用 setWindowTitle）
        public void setTitle( string t ) { SLang.QT.ffi_widgetSetText( this.handle, t ) }
        public string text() { ret SLang.QT.ffi_widgetText( this.handle ) }
        public void setGeometry( int x, int y, int w, int h ) { SLang.QT.ffi_widgetSetGeometry( this.handle, x, y, w, h ) }
        public void resize( int w, int h ) { SLang.QT.ffi_widgetResize( this.handle, w, h ) }
        # 移动控件（动画面板：QTimer onTick 里连续 move 形成移动效果）
        public void move( int x, int y ) { SLang.QT.ffi_widgetMove( this.handle, x, y ) }
        public void show() { SLang.QT.ffi_widgetShow( this.handle ) }
        public void hide() { SLang.QT.ffi_widgetHide( this.handle ) }
        public void setEnabled( bool on ) { SLang.QT.ffi_widgetSetEnabled( this.handle, on ) }
        public void setVisible( bool on ) { SLang.QT.ffi_widgetSetVisible( this.handle, on ) }
        public void setToolTip( string t ) { SLang.QT.ffi_widgetSetTooltip( this.handle, t ) }
        public void setStyleSheet( string css ) { SLang.QT.ffi_widgetSetStyleSheet( this.handle, css ) }
        public void setFixedSize( int w, int h ) { SLang.QT.ffi_widgetSetFixedSize( this.handle, w, h ) }
        # 2026-11-10 VS 扩展：min/max 尺寸钳制（面板规格落地到 Qt 原生）
        public void setMinimumSize( int w, int h ) { SLang.QT.ffi_widgetSetMinSize( this.handle, w, h ) }
        public void setMaximumSize( int w, int h ) { SLang.QT.ffi_widgetSetMaxSize( this.handle, w, h ) }
        public void update() { SLang.QT.ffi_widgetUpdate( this.handle ) }
        public void setParent( SLang.QObject p ) { SLang.QT.ffi_widgetSetParent( this.handle, p.handle ) }
        public void setLayout( SLang.QLayout layout ) { SLang.QT.ffi_widgetSetLayout( this.handle, layout.handle ) }
    }
}
