import Core;
import Std;

# 唯一允许出现 @DllImport 的绑定面（参照 SLang/QT/QTFFI.sl 的单一绑定面约定）。
# 其余 SlangUnity.* 类只调这里的 ffi_* 静态方法，SL -> C++ 零 C# 参与。
namespace SlangUnity
{
    public class UnityFFI
    {
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_probe", "->i32" )
        public static int ffi_probe() { ret -1 }

        # ── Object / GameObject ──────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_find", "utf8->i64" )
        public static Int64 ffi_objFind( string name ) { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_create", "utf8->i64" )
        public static Int64 ffi_objCreate( string name ) { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_valid", "i64->i32" )
        public static int ffi_objValid( Int64 h ) { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_name", "i64->utf8" )
        public static string ffi_objName( Int64 h ) { ret "" }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_set_active", "i64,i32->i32" )
        public static int ffi_objSetActive( Int64 h, int v ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_obj_active", "i64->i32" )
        public static int ffi_objActive( Int64 h ) { ret 0 }

        # ── Transform ────────────────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_set_pos", "i64,f64,f64,f64->i32" )
        public static int ffi_trSetPos( Int64 h, double x, double y, double z ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_pos", "i64,i32->f64" )
        public static double ffi_trPos( Int64 h, int axis ) { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_set_rot", "i64,f64,f64,f64->i32" )
        public static int ffi_trSetRot( Int64 h, double x, double y, double z ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_rot", "i64,i32->f64" )
        public static double ffi_trRot( Int64 h, int axis ) { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_set_scale", "i64,f64,f64,f64->i32" )
        public static int ffi_trSetScale( Int64 h, double x, double y, double z ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_scale", "i64,i32->f64" )
        public static double ffi_trScale( Int64 h, int axis ) { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_set_spin", "i64,f64->i32" )
        public static int ffi_trSetSpin( Int64 h, double degPerSec ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_set_bob", "i64,f64,f64->i32" )
        public static int ffi_trSetBob( Int64 h, double amplitude, double speed ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_tr_translate", "i64,f64,f64,f64->i32" )
        public static int ffi_trTranslate( Int64 h, double x, double y, double z ) { ret -1 }

        # ── Camera ───────────────────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_cam_main", "->i64" )
        public static Int64 ffi_camMain() { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_cam_set_fov", "i64,f64->i32" )
        public static int ffi_camSetFov( Int64 h, double fov ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_cam_fov", "i64->f64" )
        public static double ffi_camFov( Int64 h ) { ret 60.0 }

        # ── AudioSource ──────────────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_get", "i64->i64" )
        public static Int64 ffi_audioGet( Int64 h ) { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_play", "i64->i32" )
        public static int ffi_audioPlay( Int64 h ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_stop", "i64->i32" )
        public static int ffi_audioStop( Int64 h ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_set_volume", "i64,f64->i32" )
        public static int ffi_audioSetVolume( Int64 h, double v ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_volume", "i64->f64" )
        public static double ffi_audioVolume( Int64 h ) { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_audio_playing", "i64->i32" )
        public static int ffi_audioPlaying( Int64 h ) { ret 0 }

        # ── Renderer ─────────────────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_renderer_set_color", "i64,f64,f64,f64->i32" )
        public static int ffi_rendererSetColor( Int64 h, double r, double g, double b ) { ret -1 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_renderer_color", "i64,i32->f64" )
        public static double ffi_rendererColor( Int64 h, int axis ) { ret 0.0 }

        # ── Time / Debug ─────────────────────────────────────
        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_time_delta", "->f64" )
        public static double ffi_timeDelta() { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_time_total", "->f64" )
        public static double ffi_timeTotal() { ret 0.0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_frame_count", "->i32" )
        public static int ffi_frameCount() { ret 0 }

        @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_debug_log", "utf8->i32" )
        public static int ffi_debugLog( string msg ) { ret -1 }
    }
}
