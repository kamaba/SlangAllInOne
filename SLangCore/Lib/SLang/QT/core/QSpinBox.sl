import Core;
import Std;

# QSpinBox —— 原生数值输入（2026-11-15 第二十六轮）
# 用于扫描深度等整数设置；模态对话框在「确定」时读 value() 即可。
namespace SLang
{
    public class QSpinBox extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_spinCreate( parent ) )
        }

        public void setRange( int minValue, int maxValue )
        {
            SLang.QT.ffi_spinSetRange( this.handle, minValue, maxValue )
        }

        public void setValue( int v )
        {
            SLang.QT.ffi_spinSetValue( this.handle, v )
        }

        public int value() { ret SLang.QT.ffi_spinValue( this.handle ) }

        # handler 形态：static void onSpinValueChanged( int v )
        public Int64 onValueChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_SPIN_VALUE_CHANGED, handler )
        }
    }
}
