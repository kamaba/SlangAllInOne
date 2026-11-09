using System;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace SlangUnity.Editor
{
    // Editor tooling for the SLang Unity package: sample installation,
    // one-shot verification, play-mode entry and .unitypackage export.
    [InitializeOnLoad]
    public static class SlangUnityEditor
    {
        private static double nextCheck;

        static SlangUnityEditor()
        {
            EditorApplication.update += Tick;
        }

        private static string ProjectRoot
        {
            get { return Path.GetFullPath(Path.Combine(Application.dataPath, "..")); }
        }

        private static string LogDir
        {
            get { return Path.Combine(ProjectRoot, "Logs"); }
        }

        private static string PackageRoot
        {
            get { return Path.Combine(ProjectRoot, "Packages", "com.slang.unity"); }
        }

        private static string SampleRoot
        {
            get { return Path.Combine(PackageRoot, "Samples~", "HelloCube"); }
        }

        private static string StreamingSlang
        {
            get { return Path.Combine(Application.dataPath, "StreamingAssets", "Slang"); }
        }

        private static void Tick()
        {
            if (EditorApplication.isCompiling || EditorApplication.isUpdating)
            {
                return;
            }
            if (EditorApplication.timeSinceStartup < nextCheck)
            {
                return;
            }
            nextCheck = EditorApplication.timeSinceStartup + 0.5;

            string flag = Path.Combine(LogDir, "slang-unity-cmd.flag");
            if (!File.Exists(flag))
            {
                return;
            }
            string command = File.ReadAllText(flag).Trim();
            File.Delete(flag);

            if (command == "play")
            {
                EditorApplication.isPlaying = true;
            }
            else if (command == "verify")
            {
                Verify();
            }
            else if (command == "report")
            {
                Report();
            }
            else if (command == "export")
            {
                ExportPackage();
            }
        }

        [MenuItem("Tools/SlangUnity/Install HelloCube Sample")]
        public static void InstallSample()
        {
            string dst = StreamingSlang;
            string dstLib = Path.Combine(dst, "lib");
            Directory.CreateDirectory(dstLib);

            CopyOne("HelloCube.module.slb", dst);
            CopyOne("HelloCube.module.json", dst);
            CopyOne("HelloCube.sl", dst);
            CopyOne("HelloCube.sp", dst);
            CopyOne("HelloCube.jsonc", dst);
            foreach (string m in new[] { "Core.module.slb", "Std.module.slb" })
            {
                string src = Path.Combine(SampleRoot, "lib", m);
                if (File.Exists(src))
                {
                    File.Copy(src, Path.Combine(dstLib, m), true);
                }
            }
            AssetDatabase.Refresh();
            Debug.Log("[SlangUnity] HelloCube sample installed to " + dst);
        }

        private static void CopyOne(string name, string dst)
        {
            string src = Path.Combine(SampleRoot, name);
            if (File.Exists(src))
            {
                File.Copy(src, Path.Combine(dst, name), true);
            }
        }

        [MenuItem("Tools/SlangUnity/Verify (Editor)")]
        public static void Verify()
        {
            string slb = Path.Combine(StreamingSlang, "HelloCube.module.slb");
            StringBuilder report = new StringBuilder();
            try
            {
                report.AppendLine("slb=" + slb);
                report.AppendLine("slbExists=" + File.Exists(slb));
                report.AppendLine("nativeVersion=" + SlangUnityNative.Version());

                int rc = SlangUnityNative.slu_boot(Encoding.UTF8.GetBytes(slb + "\0"));
                double[] state = new double[9];
                for (int i = 0; i < 60; i++)
                {
                    SlangUnityNative.Frame(1.0 / 60.0, state);
                }
                int[] diag = new int[6];
                SlangUnityNative.slu_diag(diag);

                report.AppendLine("slu_boot rc=" + rc);
                report.AppendLine("angleY=" + state[4]);
                report.AppendLine("color=" + state[6] + "," + state[7] + "," + state[8]);
                report.AppendLine("diag[0] IUnityLogAttached=" + diag[0]);
                report.AppendLine("diag[1] renderer=" + diag[1]);
                report.AppendLine("diag[2] d3d11Device=" + diag[2]);
                report.AppendLine("diag[3] renderEventCount=" + diag[3]);
                report.AppendLine("diag[4] nativeFrameCount=" + diag[4]);
                report.AppendLine("diag[5] gfxDeviceEvents=" + diag[5]);

                bool pass = rc == 0 && state[4] > 0.0 && diag[4] >= 60;
                report.AppendLine("RESULT=" + (pass ? "PASS" : "FAIL"));
                Debug.Log("[SlangUnity verify] " + (pass ? "PASS" : "FAIL"));
            }
            catch (Exception ex)
            {
                report.AppendLine("EXCEPTION " + ex.GetType().Name + ": " + ex.Message);
                report.AppendLine("RESULT=FAIL");
                Debug.LogError("[SlangUnity verify] " + ex);
            }
            WriteReport("slang-unity-verify.txt", report.ToString());
        }

        [MenuItem("Tools/SlangUnity/Report (Play Mode)")]
        public static void Report()
        {
            int[] diag = new int[6];
            StringBuilder report = new StringBuilder();
            try
            {
                SlangUnityNative.slu_diag(diag);
                report.AppendLine("isPlaying=" + EditorApplication.isPlaying);
                report.AppendLine("unityFrameCount=" + Time.frameCount);
                report.AppendLine("IUnityLogAttached=" + diag[0]);
                report.AppendLine("renderer=" + diag[1]);
                report.AppendLine("d3d11Device=" + diag[2]);
                report.AppendLine("renderEventCount=" + diag[3]);
                report.AppendLine("nativeFrameCount=" + diag[4]);
                report.AppendLine("gfxDeviceEvents=" + diag[5]);
                report.AppendLine("RESULT=" + (diag[3] > 0 ? "PASS" : "FAIL"));
                Debug.Log("[SlangUnity report] renderEventCount=" + diag[3]);
            }
            catch (Exception ex)
            {
                report.AppendLine("EXCEPTION " + ex.Message);
                report.AppendLine("RESULT=FAIL");
            }
            WriteReport("slang-unity-report.txt", report.ToString());
        }

        [MenuItem("Tools/SlangUnity/Enter Play Mode")]
        public static void EnterPlay()
        {
            EditorApplication.isPlaying = true;
        }

        [MenuItem("Tools/SlangUnity/Export .unitypackage")]
        public static void ExportPackage()
        {
            string dest = Path.Combine(ProjectRoot, "SlangUnity.unitypackage");
            try
            {
                AssetDatabase.ExportPackage("Packages/com.slang.unity", dest,
                    ExportPackageOptions.Recurse);
                Debug.Log("[SlangUnity] exported " + dest);
            }
            catch (Exception ex)
            {
                Debug.LogError("[SlangUnity] export failed: " + ex.Message);
            }
        }

        private static void WriteReport(string name, string text)
        {
            try
            {
                Directory.CreateDirectory(LogDir);
                File.WriteAllText(Path.Combine(LogDir, name), text, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Debug.LogError("[SlangUnity] cannot write report: " + ex.Message);
            }
        }
    }
}
