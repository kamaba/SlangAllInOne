import Std;

# HelloCube.sl - 用 SlangUnity 基础类（C# Unity 风格）写 Unity 行为。
# 所有类都通过 UnityFFI 单一绑定面直调 C++ 句柄表，C# 不参与 API 映射。

class HelloCube
{
    # Native binding self-check. This declaration must stay in the entry file:
    # it activates the module-wide FFI binding for the sllib/ class library.
    @DllImport( "C:/Users/Administrator/My project/Packages/com.slang.unity/Plugins/x86_64/slang_unity_native3.dll", "slu_probe", "->i32" )
    public static int localProbe() { ret -1 }

    public static void runMain()
    {
        int probe = SlangUnity.UnityFFI.ffi_probe()
        SystemPrintln( "[SL] native probe = " + localProbe().toString() )

        if probe == 20261109
        {
            SlangUnity.GameObject cube = SlangUnity.GameObject.Find( "SlangCube" )
            SlangUnity.Transform t = cube.transform
            t.position = SlangUnity.Vector3( 0.0, 1.2, 0.0 )
            t.localScale = SlangUnity.Vector3( 1.0, 1.0, 1.0 )
            t.setSpin( 90.0 )
            t.setBob( 0.35, 2.0 )

            SlangUnity.Renderer renderer = cube.renderer
            renderer.color = SlangUnity.Color( 1.0, 0.45, 0.1, 1.0 )

            SlangUnity.Camera cam = SlangUnity.Camera.main
            cam.fieldOfView = 60.0

            SlangUnity.AudioSource audio = cube.audioSource
            audio.volume = 0.8

            SlangUnity.Debug.Log( "HelloCube v4: SL Unity classes -> C++ handles" )
            SystemPrintln( "[SL] target name = " + cube.name )
            SystemPrintln( "[SL] camera fov = " + cam.fieldOfView.toString() )
        }
        else
        {
            SystemPrintln( "[SL] ERROR: C++ native binding is NOT active (SL fallback ran)" )
        }
    }
}
