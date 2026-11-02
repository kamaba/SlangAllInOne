import Core;
import Std;

# QPushButton —— 按钮；clicked 信号无参
namespace SLang
{
    public class QPushButton extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_buttonCreate( parent ) )
        }

        # 连接 clicked 信号到任意 SLang 函数值（static void onClick() / 实例方法 / 闭包）。
        # 返回 bind_id > 0 表示连接成功（headless 也可据此校验 FFI 绑定）。
        public Int64 clicked( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_CLICKED, handler )
        }
    }
}
