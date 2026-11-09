import Core;
import Std;

# UnityEngine.AudioSource 的 SL 镜像（基础：播放/停止/音量）。
namespace SlangUnity
{
    public class AudioSource extends Component
    {
        public void _init_( Int64 h )
        {
            this.handle = h
        }

        public void Play()
        {
            UnityFFI.ffi_audioPlay( this.handle )
        }

        public void Stop()
        {
            UnityFFI.ffi_audioStop( this.handle )
        }

        public get double volume()
        {
            ret UnityFFI.ffi_audioVolume( this.handle )
        }

        public set void volume( double value )
        {
            UnityFFI.ffi_audioSetVolume( this.handle, value )
        }

        public get bool isPlaying()
        {
            ret UnityFFI.ffi_audioPlaying( this.handle ) != 0
        }
    }
}
