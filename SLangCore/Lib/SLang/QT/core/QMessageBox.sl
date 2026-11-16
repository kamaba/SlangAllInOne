import Core;
import Std;

# QMessageBox —— 原生模态消息框（2026-11-16 第二十八轮，部分实现回补）
# C++ 侧 slqt_messagebox_info/question 早已实现，此前缺 SL 封装类（总纲 §3.3
# 「无 SL 封装类但已有 FFI」欠账）。静态工具类：弹出后阻塞，返回被点按钮的
# Qt::StandardButton 值（常用：Ok=1024 / Yes=16384 / No=65536 / Cancel=4194304）。
# question 默认按钮集为 Yes|No。IDE 现有 ConfirmDialog 是自绘对话框，不冲突；
# 需要系统原生样式消息框时用本类。
namespace SLang
{
    public class QMessageBox extends QObject
    {
        # 信息框（单 Ok 按钮）
        public static int information( Int64 parent, string title, string text )
        {
            ret SLang.QT.ffi_messageboxInfo( parent, title, text )
        }

        # 询问框（Yes|No）
        public static int question( Int64 parent, string title, string text )
        {
            ret SLang.QT.ffi_messageboxQuestion( parent, title, text )
        }
    }
}
