using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace SlangUnity.Editor
{
    // Slang scene exporter: dumps the active Unity scene into the SimGameEngine
    // asset schema (see SimGameEngine/doc/16-Unity资源导入与导出.md):
    //   manifest.json / scene.json / shadermap.json / mesh_<id>.json + .bin
    //   / material_<id>.json / texture_<id>.json / textures\<id>.png
    // Mesh bin layout (little endian):
    //   "SLMESH" + u32 version + u32 vertexCount + u32 stride + u32 indexCount
    //   + f32[vertexCount * 8]  (position.xyz, normal.xyz, uv.xy)
    //   + u32[indexCount]
    // Ids are stable per export run: mesh_N / mat_N / tex_N (mapping kept in manifest).
    public static class SlangSceneExporter
    {
        const int FormatVersion = 1;
        const string MeshMagic = "SLMESH";

        class MeshRes { public string id; public Mesh mesh; public string name; }
        class MatRes { public string id; public Material mat; public string shaderName; public string mapped; public string degraded; public string texId; }
        class TexRes { public string id; public Texture2D tex; public string srcPath; }
        class NodeInfo { public int id; public int parent; public GameObject go; }

        [MenuItem("Tools/SlangUnity/Export Scene (Slang JSON)")]
        public static void ExportMenu()
        {
            ExportActiveScene(null);
        }

        // Batch entry: Unity.exe -batchmode -quit -projectPath ... -executeMethod
        //   SlangUnity.Editor.SlangSceneExporter.ExportSceneFromCommandLine
        //   [-slangExportOut <dir>]
        public static void ExportSceneFromCommandLine()
        {
            string outDir = null;
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (args[i] == "-slangExportOut")
                {
                    outDir = args[i + 1];
                }
            }
            ExportActiveScene(outDir);
        }

        public static bool ExportActiveScene(string outDirOverride)
        {
            var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            return ExportScene(scene, outDirOverride);
        }

        // 最小起步：临时 Additive 场景里放一个 Cube + 方向光，导出到 SlangExport/CubeDemo。
        // 不修改、不保存当前打开的场景（Additive 关闭即丢弃）。
        [MenuItem("Tools/SlangUnity/Export Cube Demo (Slang JSON)")]
        public static void ExportCubeDemo()
        {
            var prev = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            var tmp = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
            try
            {
                GameObject cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
                cube.name = "Cube";
                GameObject sunGo = new GameObject("Sun");
                Light sun = sunGo.AddComponent<Light>();
                sun.type = LightType.Directional;
                sun.intensity = 1.2f;
                sun.color = new Color(1f, 0.96f, 0.9f);
                sunGo.transform.rotation = Quaternion.Euler(45f, -30f, 0f);
                string outDir = Path.Combine(Application.dataPath,
                    Path.Combine("StreamingAssets", Path.Combine("SlangExport", "CubeDemo")));
                ExportScene(tmp, outDir);
            }
            finally
            {
                if (tmp.IsValid() && tmp.isLoaded)
                {
                    EditorSceneManager.CloseScene(tmp, true);
                }
                if (prev.IsValid() && prev.isLoaded)
                {
                    EditorSceneManager.SetActiveScene(prev);
                }
            }
        }

        public static bool ExportScene(UnityEngine.SceneManagement.Scene scene, string outDirOverride)
        {
            StringBuilder report = new StringBuilder();
            bool ok = false;
            string outDir = outDirOverride;
            try
            {
                string sceneName = string.IsNullOrEmpty(scene.name) ? "Scene" : scene.name;
                if (string.IsNullOrEmpty(outDir))
                {
                    outDir = Path.Combine(Application.dataPath,
                        Path.Combine("StreamingAssets", Path.Combine("SlangExport", Sanitize(sceneName))));
                }
                Directory.CreateDirectory(outDir);
                Directory.CreateDirectory(Path.Combine(outDir, "textures"));
                Directory.CreateDirectory(Path.Combine(outDir, "shaders"));

                List<NodeInfo> nodes = new List<NodeInfo>();
                foreach (GameObject root in scene.GetRootGameObjects())
                {
                    CollectNodes(root, 0, nodes);
                }

                Dictionary<Mesh, MeshRes> meshMap = new Dictionary<Mesh, MeshRes>();
                Dictionary<Material, MatRes> matMap = new Dictionary<Material, MatRes>();
                Dictionary<Texture2D, TexRes> texMap = new Dictionary<Texture2D, TexRes>();
                List<string> skipped = new List<string>();
                int meshSeq = 0, matSeq = 0, texSeq = 0;

                StringBuilder sb = new StringBuilder();
                sb.Append("{\n  \"version\": ").Append(FormatVersion);
                sb.Append(",\n  \"scene\": \"").Append(Escape(sceneName)).Append("\",\n  \"nodes\": [\n");

                for (int n = 0; n < nodes.Count; n++)
                {
                    NodeInfo ni = nodes[n];
                    GameObject go = ni.go;
                    Transform tr = go.transform;
                    if (n > 0) sb.Append(",\n");
                    sb.Append("    {\n");
                    sb.Append("      \"id\": ").Append(ni.id).Append(", \"parent\": ").Append(ni.parent);
                    sb.Append(",\n      \"name\": \"").Append(Escape(go.name)).Append("\"");
                    sb.Append(",\n      \"tag\": \"").Append(Escape(go.tag)).Append("\"");
                    sb.Append(",\n      \"layer\": ").Append(go.layer);
                    sb.Append(",\n      \"active\": ").Append(go.activeInHierarchy ? "true" : "false");
                    sb.Append(",\n      \"transform\": {\n");
                    sb.Append("        \"localPosition\": ").Append(V3(tr.localPosition)).Append(",\n");
                    sb.Append("        \"localRotation\": ").Append(Q(tr.localRotation)).Append(",\n");
                    sb.Append("        \"localScale\": ").Append(V3(tr.localScale)).Append("\n      }");
                    sb.Append(",\n      \"components\": [");

                    List<string> comps = new List<string>();
                    CollectComponents(go, meshMap, matMap, texMap, skipped,
                        ref meshSeq, ref matSeq, ref texSeq, comps);
                    sb.Append(string.Join(", ", comps.ToArray()));
                    sb.Append("]\n    }");
                }
                sb.Append("\n  ]\n}\n");
                WriteUtf8(Path.Combine(outDir, "scene.json"), sb.ToString());

                // mesh 资源
                int totalVerts = 0, totalIdx = 0;
                foreach (KeyValuePair<Mesh, MeshRes> kv in meshMap)
                {
                    WriteMesh(outDir, kv.Value, ref totalVerts, ref totalIdx);
                }

                // 材质 / 贴图 / shadermap
                StringBuilder sm = new StringBuilder();
                sm.Append("{\n  \"version\": ").Append(FormatVersion).Append(",\n  \"mappings\": [\n");
                bool firstMap = true;
                foreach (KeyValuePair<Material, MatRes> kv in matMap)
                {
                    WriteMaterial(outDir, kv.Value);
                    if (!firstMap) sm.Append(",\n");
                    firstMap = false;
                    sm.Append("    { \"material\": \"").Append(kv.Value.id)
                      .Append("\", \"shader\": \"").Append(Escape(kv.Value.shaderName))
                      .Append("\", \"mapped\": \"").Append(kv.Value.mapped).Append("\" }");
                }
                sm.Append("\n  ]\n}\n");
                WriteUtf8(Path.Combine(outDir, "shadermap.json"), sm.ToString());

                foreach (KeyValuePair<Texture2D, TexRes> kv in texMap)
                {
                    WriteTexture(outDir, kv.Value);
                }

                WriteManifest(outDir, sceneName, nodes.Count, meshMap.Count, matMap.Count,
                    texMap.Count, skipped, totalVerts, totalIdx);

                report.AppendLine("outDir=" + outDir);
                report.AppendLine("scene=" + sceneName);
                report.AppendLine("nodes=" + nodes.Count);
                report.AppendLine("meshes=" + meshMap.Count);
                report.AppendLine("materials=" + matMap.Count);
                report.AppendLine("textures=" + texMap.Count);
                report.AppendLine("vertices=" + totalVerts);
                report.AppendLine("indices=" + totalIdx);
                report.AppendLine("skipped=" + skipped.Count);
                foreach (string s in skipped) report.AppendLine("  skip: " + s);
                ok = nodes.Count > 0 && meshMap.Count > 0;
                AssetDatabase.Refresh();
            }
            catch (Exception ex)
            {
                report.AppendLine("EXCEPTION " + ex.GetType().Name + ": " + ex.Message);
                report.AppendLine(ex.StackTrace);
                ok = false;
            }
            report.AppendLine("RESULT=" + (ok ? "PASS" : "FAIL"));
            WriteReport("slang-export-report.txt", report.ToString());
            Debug.Log("[SlangSceneExporter] " + (ok ? "PASS" : "FAIL") + "\n" + report.ToString());
            return ok;
        }

        // ── 节点收集 ──────────────────────────────────────────────
        static void CollectNodes(GameObject go, int parent, List<NodeInfo> nodes)
        {
            NodeInfo ni = new NodeInfo();
            ni.id = nodes.Count + 1;
            ni.parent = parent;
            ni.go = go;
            nodes.Add(ni);
            foreach (Transform child in go.transform)
            {
                CollectNodes(child.gameObject, ni.id, nodes);
            }
        }

        static void CollectComponents(GameObject go,
            Dictionary<Mesh, MeshRes> meshMap, Dictionary<Material, MatRes> matMap,
            Dictionary<Texture2D, TexRes> texMap, List<string> skipped,
            ref int meshSeq, ref int matSeq, ref int texSeq, List<string> comps)
        {
            MeshFilter mf = go.GetComponent<MeshFilter>();
            MeshRenderer mr = go.GetComponent<MeshRenderer>();
            if (mf != null && mf.sharedMesh != null)
            {
                MeshRes mr2;
                if (!meshMap.TryGetValue(mf.sharedMesh, out mr2))
                {
                    meshSeq++;
                    mr2 = new MeshRes();
                    mr2.id = "mesh_" + meshSeq;
                    mr2.mesh = mf.sharedMesh;
                    mr2.name = mf.sharedMesh.name;
                    meshMap[mf.sharedMesh] = mr2;
                }
                comps.Add("{ \"type\": \"MeshFilter\", \"mesh\": \"" + mr2.id + "\" }");
            }
            if (mr != null)
            {
                Material m = mr.sharedMaterial;
                if (m != null)
                {
                    MatRes mres;
                    if (!matMap.TryGetValue(m, out mres))
                    {
                        matSeq++;
                        mres = new MatRes();
                        mres.id = "mat_" + matSeq;
                        mres.mat = m;
                        mres.shaderName = m.shader != null ? m.shader.name : "Unknown";
                        MapShader(mres, m, texMap, ref texSeq);
                        matMap[m] = mres;
                    }
                    string queue = Mathf.Max(2000, m.renderQueue).ToString();
                    comps.Add("{ \"type\": \"MeshRenderer\", \"material\": \"" + mres.id
                        + "\", \"castShadow\": " + (mr.shadowCastingMode != UnityEngine.Rendering.ShadowCastingMode.Off ? "true" : "false")
                        + ", \"renderQueue\": " + queue + " }");
                }
            }
            BoxCollider bc = go.GetComponent<BoxCollider>();
            if (bc != null)
            {
                comps.Add("{ \"type\": \"BoxCollider\", \"center\": " + V3(bc.center)
                    + ", \"size\": " + V3(bc.size) + ", \"isTrigger\": "
                    + (bc.isTrigger ? "true" : "false") + " }");
            }
            SphereCollider sc = go.GetComponent<SphereCollider>();
            if (sc != null)
            {
                comps.Add("{ \"type\": \"SphereCollider\", \"center\": " + V3(sc.center)
                    + ", \"radius\": " + F(sc.radius) + ", \"isTrigger\": "
                    + (sc.isTrigger ? "true" : "false") + " }");
            }
            Rigidbody rb = go.GetComponent<Rigidbody>();
            if (rb != null)
            {
                comps.Add("{ \"type\": \"Rigidbody\", \"mass\": " + F(rb.mass)
                    + ", \"useGravity\": " + (rb.useGravity ? "true" : "false") + " }");
            }
            Camera cam = go.GetComponent<Camera>();
            if (cam != null)
            {
                comps.Add("{ \"type\": \"Camera\", \"orthographic\": "
                    + (cam.orthographic ? "true" : "false") + ", \"orthographicSize\": " + F(cam.orthographicSize)
                    + ", \"fieldOfView\": " + F(cam.fieldOfView) + ", \"depth\": " + F(cam.depth) + " }");
            }
            Light li = go.GetComponent<Light>();
            if (li != null)
            {
                string lt = li.type == LightType.Directional ? "directional"
                    : (li.type == LightType.Point ? "point" : "spot");
                comps.Add("{ \"type\": \"Light\", \"lightType\": \"" + lt
                    + "\", \"intensity\": " + F(li.intensity)
                    + ", \"color\": " + C(li.color) + " }");
            }
            // 引擎不认识的组件计数（v1：ParticleSystem / VFX / Terrain / NavMesh 等）
            Component[] all = go.GetComponents<Component>();
            foreach (Component c in all)
            {
                if (c == null) continue;
                if (c is Transform || c is MeshFilter || c is MeshRenderer || c is BoxCollider
                    || c is SphereCollider || c is Rigidbody || c is Camera || c is Light) continue;
                skipped.Add(go.name + " -> " + c.GetType().Name);
            }
        }

        // Unity shader 名 → 引擎固化效果（见 doc/16 §4.4 映射表）
        static void MapShader(MatRes mres, Material m,
            Dictionary<Texture2D, TexRes> texMap, ref int texSeq)
        {
            string sn = mres.shaderName.ToLowerInvariant();
            if (sn.Contains("unlit"))
            {
                mres.mapped = "unlit";
            }
            else if (sn.Contains("normal") || (m.HasProperty("_BumpMap") && m.GetTexture("_BumpMap") != null))
            {
                mres.mapped = "normalmap";
            }
            else if (sn.Contains("toon"))
            {
                mres.mapped = "toon";
            }
            else if (sn.Contains("specular") || sn.Contains("phong"))
            {
                mres.mapped = "blinn-phong";
            }
            else
            {
                // Standard / URP-Lit / HDRP-Lit 等物理光照近似为 phong
                mres.mapped = "phong";
            }
            Texture mainTex = m.HasProperty("_MainTex") ? m.GetTexture("_MainTex")
                : (m.HasProperty("_BaseMap") ? m.GetTexture("_BaseMap") : null);
            Texture2D t2 = mainTex as Texture2D;
            if (t2 != null)
            {
                TexRes tres;
                if (!texMap.TryGetValue(t2, out tres))
                {
                    string p = AssetDatabase.GetAssetPath(t2);
                    string ext = string.IsNullOrEmpty(p) ? "" : Path.GetExtension(p).ToLowerInvariant();
                    if (ext == ".png" || ext == ".jpg" || ext == ".jpeg")
                    {
                        texSeq++;
                        tres = new TexRes();
                        tres.id = "tex_" + texSeq;
                        tres.tex = t2;
                        tres.srcPath = p;
                        texMap[t2] = tres;
                        mres.texId = tres.id;
                    }
                    else
                    {
                        mres.degraded = "texture-not-importable:" + ext;
                    }
                }
                else
                {
                    mres.texId = tres.id;
                }
            }
        }

        // ── 资源写出 ──────────────────────────────────────────────
        static void WriteMesh(string outDir, MeshRes res, ref int totalVerts, ref int totalIdx)
        {
            Mesh mesh = res.mesh;
            List<Vector3> verts = new List<Vector3>();
            List<Vector3> normals = new List<Vector3>();
            List<Vector2> uvs = new List<Vector2>();
            mesh.GetVertices(verts);
            mesh.GetNormals(normals);
            mesh.GetUVs(0, uvs);
            int vc = verts.Count;
            bool hasNormal = normals.Count == vc;
            bool hasUv = uvs.Count == vc;

            List<int[]> submeshes = new List<int[]>();
            int indexCount = 0;
            for (int s = 0; s < mesh.subMeshCount; s++)
            {
                int[] tris = mesh.GetTriangles(s);
                submeshes.Add(tris);
                indexCount += tris.Length;
            }

            const int stride = 32; // 8 * f32
            string binPath = Path.Combine(outDir, res.id + ".bin");
            using (FileStream fs = new FileStream(binPath, FileMode.Create, FileAccess.Write))
            using (BinaryWriter w = new BinaryWriter(fs))
            {
                foreach (char c in MeshMagic) w.Write((byte)c);
                w.Write(FormatVersion);
                w.Write(vc);
                w.Write(stride);
                w.Write(indexCount);
                for (int i = 0; i < vc; i++)
                {
                    w.Write(verts[i].x); w.Write(verts[i].y); w.Write(verts[i].z);
                    if (hasNormal) { w.Write(normals[i].x); w.Write(normals[i].y); w.Write(normals[i].z); }
                    else { w.Write(0f); w.Write(1f); w.Write(0f); }
                    if (hasUv) { w.Write(uvs[i].x); w.Write(uvs[i].y); }
                    else { w.Write(0f); w.Write(0f); }
                }
                for (int s = 0; s < submeshes.Count; s++)
                {
                    int[] tris = submeshes[s];
                    for (int i = 0; i < tris.Length; i++) w.Write((uint)tris[i]);
                }
            }

            StringBuilder sb = new StringBuilder();
            sb.Append("{\n  \"id\": \"").Append(res.id).Append("\", \"name\": \"").Append(Escape(res.name)).Append("\",\n");
            sb.Append("  \"vertexCount\": ").Append(vc).Append(", \"indexCount\": ").Append(indexCount).Append(",\n");
            sb.Append("  \"layout\": [\"position:float3\", \"normal:float3\", \"uv:float2\"],\n");
            sb.Append("  \"vertexStride\": ").Append(stride).Append(",\n");
            sb.Append("  \"submeshes\": [");
            int offset = 0;
            for (int s = 0; s < submeshes.Count; s++)
            {
                if (s > 0) sb.Append(", ");
                sb.Append("{ \"indexOffset\": ").Append(offset)
                  .Append(", \"indexCount\": ").Append(submeshes[s].Length)
                  .Append(", \"topology\": \"triangles\" }");
                offset += submeshes[s].Length;
            }
            sb.Append("],\n");
            Bounds b = mesh.bounds;
            sb.Append("  \"bounds\": { \"center\": ").Append(V3(b.center))
              .Append(", \"size\": ").Append(V3(b.size)).Append(" },\n");
            sb.Append("  \"bin\": \"").Append(res.id).Append(".bin\"\n}\n");
            WriteUtf8(Path.Combine(outDir, res.id + ".json"), sb.ToString());

            totalVerts += vc;
            totalIdx += indexCount;
        }

        static void WriteMaterial(string outDir, MatRes res)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("{\n  \"id\": \"").Append(res.id).Append("\", \"name\": \"")
              .Append(Escape(res.mat.name)).Append("\",\n");
            sb.Append("  \"shader\": \"").Append(Escape(res.shaderName)).Append("\",\n");
            sb.Append("  \"mapped\": \"").Append(res.mapped).Append("\",\n");
            sb.Append("  \"hlsl\": null,\n");
            if (res.texId != null)
            {
                sb.Append("  \"textures\": { \"_MainTex\": \"").Append(res.texId).Append("\" },\n");
            }
            Color c = Color.white;
            if (res.mat.HasProperty("_Color")) c = res.mat.GetColor("_Color");
            else if (res.mat.HasProperty("_BaseColor")) c = res.mat.GetColor("_BaseColor");
            sb.Append("  \"props\": { \"_Color\": ").Append(C(c)).Append(" },\n");
            sb.Append("  \"degraded\": ").Append(res.degraded != null ? "\"" + Escape(res.degraded) + "\"" : "null").Append("\n}\n");
            WriteUtf8(Path.Combine(outDir, res.id + ".json"), sb.ToString());
        }

        static void WriteTexture(string outDir, TexRes res)
        {
            if (string.IsNullOrEmpty(res.srcPath) || !File.Exists(res.srcPath))
            {
                return;
            }
            File.Copy(res.srcPath, Path.Combine(outDir, "textures", res.id + ".png"), true);
            StringBuilder sb = new StringBuilder();
            sb.Append("{\n  \"id\": \"").Append(res.id).Append("\", \"name\": \"").Append(Escape(res.tex.name)).Append("\",\n");
            sb.Append("  \"width\": ").Append(res.tex.width).Append(", \"height\": ").Append(res.tex.height).Append(",\n");
            sb.Append("  \"file\": \"textures/").Append(res.id).Append(".png\"\n}\n");
            WriteUtf8(Path.Combine(outDir, res.id + ".json"), sb.ToString());
        }

        static void WriteManifest(string outDir, string sceneName, int nodes, int meshes,
            int mats, int texs, List<string> skipped, int verts, int idx)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("{\n  \"version\": ").Append(FormatVersion);
            sb.Append(",\n  \"source\": \"unity\",");
            sb.Append("\n  \"unityVersion\": \"").Append(Application.unityVersion).Append("\",");
            sb.Append("\n  \"scene\": \"").Append(Escape(sceneName)).Append("\",");
            sb.Append("\n  \"exportTime\": \"").Append(DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")).Append("\",");
            sb.Append("\n  \"stats\": { \"nodes\": ").Append(nodes).Append(", \"meshes\": ").Append(meshes)
              .Append(", \"materials\": ").Append(mats).Append(", \"textures\": ").Append(texs)
              .Append(", \"vertices\": ").Append(verts).Append(", \"indices\": ").Append(idx)
              .Append(", \"skipped\": ").Append(skipped.Count).Append(" },");
            sb.Append("\n  \"files\": [");
            List<string> files = new List<string>();
            CollectFiles(outDir, "", files);
            bool first = true;
            foreach (string f in files)
            {
                if (!first) sb.Append(",");
                first = false;
                sb.Append("\n    { \"path\": \"").Append(Escape(f)).Append("\", \"size\": ")
                  .Append(new FileInfo(Path.Combine(outDir, f.Replace('/', Path.DirectorySeparatorChar))).Length)
                  .Append(", \"md5\": \"").Append(Md5(Path.Combine(outDir, f.Replace('/', Path.DirectorySeparatorChar)))).Append("\" }");
            }
            sb.Append("\n  ]\n}\n");
            WriteUtf8(Path.Combine(outDir, "manifest.json"), sb.ToString());
        }

        static void CollectFiles(string dir, string prefix, List<string> files)
        {
            foreach (string f in Directory.GetFiles(dir))
            {
                files.Add(prefix.Length == 0 ? Path.GetFileName(f) : prefix + "/" + Path.GetFileName(f));
            }
            foreach (string d in Directory.GetDirectories(dir))
            {
                CollectFiles(d, prefix.Length == 0 ? Path.GetFileName(d) : prefix + "/" + Path.GetFileName(d), files);
            }
        }

        // ── 工具 ──────────────────────────────────────────────────
        static string V3(Vector3 v)
        {
            return "[" + F(v.x) + ", " + F(v.y) + ", " + F(v.z) + "]";
        }

        static string Q(Quaternion q)
        {
            return "[" + F(q.x) + ", " + F(q.y) + ", " + F(q.z) + ", " + F(q.w) + "]";
        }

        static string C(Color c)
        {
            return "[" + F(c.r) + ", " + F(c.g) + ", " + F(c.b) + ", " + F(c.a) + "]";
        }

        static string F(float v)
        {
            return v.ToString("R", CultureInfo.InvariantCulture);
        }

        static string Escape(string s)
        {
            if (s == null) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"")
                .Replace("\n", "\\n").Replace("\r", "\\r").Replace("\t", "\\t");
        }

        static string Sanitize(string name)
        {
            if (string.IsNullOrEmpty(name)) return "Scene";
            char[] arr = name.ToCharArray();
            for (int i = 0; i < arr.Length; i++)
            {
                if (!char.IsLetterOrDigit(arr[i]) && arr[i] != '_' && arr[i] != '-') arr[i] = '_';
            }
            return new string(arr);
        }

        static string Md5(string path)
        {
            try
            {
                using (MD5 md5 = MD5.Create())
                using (FileStream fs = File.OpenRead(path))
                {
                    byte[] hash = md5.ComputeHash(fs);
                    StringBuilder sb = new StringBuilder(hash.Length * 2);
                    foreach (byte b in hash) sb.Append(b.ToString("x2"));
                    return sb.ToString();
                }
            }
            catch
            {
                return "unavailable";
            }
        }

        static void WriteUtf8(string path, string text)
        {
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }

        static void WriteReport(string name, string text)
        {
            try
            {
                string dir = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "Logs"));
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, name), text, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Debug.LogError("[SlangSceneExporter] cannot write report: " + ex.Message);
            }
        }
    }
}
