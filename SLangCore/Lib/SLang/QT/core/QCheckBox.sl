import Core;
import Std;

# QCheckBox —— 原生复选框（2026-11-15 第二十三轮）
# 二值选项（生成/跳过详细说明）不再用列表单选模拟。
namespace SLang
{
    public class QCheckBox extends QWidget
    {
        _init_( Int64 parent, string text )
        {
            this.setHandle( SLang.QT.ffi_checkCreate( parent, text ) )
        }

        public bool isChecked()
        {
            int v = SLang.QT.ffi_checkIsChecked( this.handle )
            if ( v != 0 ) { ret true }
            ret false
        }

        public void setChecked( bool on )
        {
            if ( on == true )
            {
                SLang.QT.ffi_checkSetChecked( this.handle, 1 )
            }
            else
            {
                SLang.QT.ffi_checkSetChecked( this.handle, 0 )
            }
        }
    }
}
