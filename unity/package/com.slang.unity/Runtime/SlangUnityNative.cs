using System;
using System.Runtime.InteropServices;
using System.Text;

namespace SlangUnity
{
    // All P/Invoke declarations for the C++ native plugin.
    // Per frame there is exactly ONE crossing: FrameObjects(dt, buffer).
    public static class SlangUnityNative
    {
        private const string Dll = "slang_unity_native3";

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern int slu_boot(byte[] slbPathUtf8);

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "slu_frame_objects")]
        private static extern unsafe int FrameObjectsRaw(double dt, double* buffer, int capacity);

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "slu_frame")]
        private static extern unsafe int FrameRaw(double dt, double* out9);

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr slu_obj_name(long handle);

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr slu_get_render_event_func();

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern int slu_diag([Out] int[] out6);

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern int slu_frame_count();

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern int slu_last_run_code();

        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr slu_version();

        public static unsafe int FrameObjects(double dt, double[] buffer)
        {
            fixed (double* p = buffer)
            {
                return FrameObjectsRaw(dt, p, buffer.Length);
            }
        }

        public static unsafe int Frame(double dt, double[] state)
        {
            fixed (double* p = state)
            {
                return FrameRaw(dt, p);
            }
        }

        // Only called when a brand-new handle appears (low frequency).
        public static string ObjectName(long handle)
        {
            IntPtr p = slu_obj_name(handle);
            if (p == IntPtr.Zero)
            {
                return string.Empty;
            }
            int length = 0;
            while (length < 256 && Marshal.ReadByte(p, length) != 0)
            {
                length++;
            }
            byte[] bytes = new byte[length];
            Marshal.Copy(p, bytes, 0, length);
            return Encoding.UTF8.GetString(bytes);
        }

        public static string Version()
        {
            IntPtr p = slu_version();
            return p == IntPtr.Zero ? string.Empty : Marshal.PtrToStringAnsi(p);
        }
    }
}
