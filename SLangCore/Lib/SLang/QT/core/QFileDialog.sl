import Core;
import Std;

# QFileDialog —— 原生模态文件选择（能力登记表 D-01 回补，2026-11-12）
# 静态方法直接调 FFI，不持有 QWidget 句柄；取消返回空串。
# filter 形如 "SLang (*.sl *.sp);;All (*)"。
namespace SLang
{
    public class QFileDialog
    {
        public static string open( string dir, string filter )
        {
            ret SLang.QT.ffi_filedialogOpen( dir, filter )
        }

        public static string save( string dir, string filter )
        {
            ret SLang.QT.ffi_filedialogSave( dir, filter )
        }

        public static string selectDir( string dir )
        {
            ret SLang.QT.ffi_filedialogDir( dir )
        }
    }
}
