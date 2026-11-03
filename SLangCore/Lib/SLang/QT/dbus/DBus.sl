import Core;
import Std;

# QDBus —— Qt6DBus 静态门面（Windows 常无会话总线：isConnected=false 属预期）
namespace SLang
{
    public class QDBus
    {
        public static bool isConnected() { ret SLang.QT.ffi_dbusConnected() }
        public static string baseService() { ret SLang.QT.ffi_dbusBaseService() }
    }
}
