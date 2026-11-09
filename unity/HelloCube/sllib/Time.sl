import Core;
import Std;

# UnityEngine.Time 的 SL 镜像（基础：deltaTime / time / frameCount）。
namespace SlangUnity
{
    public class Time
    {
        public static get double deltaTime()
        {
            ret UnityFFI.ffi_timeDelta()
        }

        public static get double time()
        {
            ret UnityFFI.ffi_timeTotal()
        }

        public static get int frameCount()
        {
            ret UnityFFI.ffi_frameCount()
        }
    }
}
