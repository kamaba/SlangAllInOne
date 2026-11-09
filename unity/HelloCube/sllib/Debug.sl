import Core;
import Std;

# UnityEngine.Debug 的 SL 镜像：日志由 C++ 经引擎日志接口直发 Console。
namespace SlangUnity
{
    public class Debug
    {
        public static void Log( string message )
        {
            UnityFFI.ffi_debugLog( message )
        }

        public static void LogWarning( string message )
        {
            UnityFFI.ffi_debugLog( "[warning] " + message )
        }

        public static void LogError( string message )
        {
            UnityFFI.ffi_debugLog( "[error] " + message )
        }
    }
}
