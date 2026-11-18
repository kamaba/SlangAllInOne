import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SceneExporter — 运行时 Scene → scene.json（doc/19）
# ----------------------------------------------------------------------------
# 与 SceneImporter 对称的导出侧：把帧内的场景树（节点 / 层级 / 变换 / 组件 /
# 脚本）序列化为 doc/16 §4.3 的 scene.json 文本，供落盘、版本管理、编辑器
# 回读或 SceneManager 再加载。
#
# 组件映射（与 SceneImporter.importComponent 一一对应）：
#   MeshRef        → MeshFilter（meshKind / meshSlot / vertices 可选）
#   MaterialRef    → MeshRenderer（material / color / renderQueue / castShadow）
#   Rigidbody      → Rigidbody（mass / useGravity）
#   BoxCollider    → BoxCollider（center / size / isTrigger）
#   SphereCollider → SphereCollider（center / radius / isTrigger）
#   CapsuleCollider→ CapsuleCollider（center / radius / height / isTrigger）
#   SpriteRenderer → SpriteRenderer
#   其它 Behaviour → Script（script = 类短名；参数由消费方脚本自定）
# Transform 是节点自带组件，不重复写进 components。
#
# 约束（跨模块 slb 常见坑，doc/10 §6）：方法调用表达式不作实参；ret 不携带
# 内联构造 / 跨模块调用；下标参与比较一律先落局部变量；`tr`/`base`/`out`/
# `params`/`global`/`def` 为保留字避让。
# ============================================================================
public class SceneExporter
{
    # ── 字符串 / 数值工具 ─────────────────────────────────
    static string esc( string s )
    {
        if s == null
        {
            ret ""
        }
        string o = ""
        Int32 i = 0
        Int32 n = s.length
        while i < n
        {
            string ch = s.slice( i, i + 1 )
            if ch == "\""
            {
                o = o + "\\\""
            }
            elif ch == "\\"
            {
                o = o + "\\\\"
            }
            elif ch == "\n"
            {
                o = o + "\\n"
            }
            elif ch == "\r"
            {
                o = o + "\\r"
            }
            elif ch == "\t"
            {
                o = o + "\\t"
            }
            else
            {
                o = o + ch
            }
            i = i + 1
        }
        ret o
    }

    # 标量三参 + String.toFormat：Release JIT 会把高频调用的标量 toString()
    # 误编译为 null（连续导出多场景时拼串只剩尾括号），toFormat 通道不受影响。
    static string vec3( Float32 x, Float32 y, Float32 z )
    {
        string s = String.toFormat( "[{0},{1},{2}]", x, y, z )
        ret s
    }

    static string quat( Quaternion q )
    {
        string x = q.x.toString()
        string y = q.y.toString()
        string z = q.z.toString()
        string w = q.w.toString()
        ret "[" + x + "," + y + "," + z + "," + w + "]"
    }

    # ── DFS 收集（父 id 与节点顺序对齐）──────────────────
    static void collect( GameObject go, Int32 parentId, List<GameObject> order, List<Int32> parents )
    {
        order.add( go )
        parents.add( parentId )
        Int32 myId = order.length
        Int32 i = 0
        Int32 n = go.childCount
        while i < n
        {
            GameObject child = go.getChild( i )
            if child != null
            {
                SceneExporter.collect( child, myId, order, parents )
            }
            i = i + 1
        }
    }

    # ── 组件导出 ─────────────────────────────────────────
    static string verticesOf( MeshRef mr )
    {
        string o = "["
        Int32 i = 0
        Int32 n = mr.vertices.length
        while i < n
        {
            Float32_3 v = mr.vertices[i]
            if i > 0
            {
                o = o + ","
            }
            o = o + SceneExporter.vec3( v.x, v.y, v.z )
            i = i + 1
        }
        ret o + "]"
    }

    static string componentOf( Component c )
    {
        Transform trans = c as Transform
        if trans != null
        {
            ret ""
        }
        MeshRef mr = c as MeshRef
        if mr != null
        {
            string kind = mr.meshKind.toString()
            string slot = mr.meshSlot.toString()
            string o = "{\"type\":\"MeshFilter\",\"mesh\":\"mesh_" + kind + "\",\"meshKind\":" + kind
            o = o + ",\"meshSlot\":" + slot
            if mr.hasVertexData
            {
                string vs = SceneExporter.verticesOf( mr )
                o = o + ",\"vertices\":" + vs
            }
            ret o + "}"
        }
        MaterialRef mref = c as MaterialRef
        if mref != null
        {
            string mn = "mat"
            string col = "[1,1,1]"
            string rq = mref.renderQueue.toString()
            string cs = "false"
            MaterialData md = mref.material
            if md != null
            {
                mn = md.name
                col = SceneExporter.vec3( md.color.x, md.color.y, md.color.z )
                string mdRq = md.renderQueue.toString()
                rq = mdRq
                if md.castShadow
                {
                    cs = "true"
                }
            }
            if mref.renderQueue > 0
            {
                rq = mref.renderQueue.toString()
            }
            string oname = SceneExporter.esc( mn )
            string o = "{\"type\":\"MeshRenderer\",\"material\":\"" + oname + "\",\"color\":" + col
            o = o + ",\"renderQueue\":" + rq + ",\"castShadow\":" + cs + "}"
            ret o
        }
        Rigidbody rb = c as Rigidbody
        if rb != null
        {
            string mass = rb.mass.toString()
            string grav = "false"
            if rb.useGravity
            {
                grav = "true"
            }
            ret "{\"type\":\"Rigidbody\",\"mass\":" + mass + ",\"useGravity\":" + grav + "}"
        }
        BoxCollider bc = c as BoxCollider
        if bc != null
        {
            string trig = "false"
            if bc.isTrigger
            {
                trig = "true"
            }
            string cen = SceneExporter.vec3( bc.center.x, bc.center.y, bc.center.z )
            string siz = SceneExporter.vec3( bc.size.x, bc.size.y, bc.size.z )
            string o = "{\"type\":\"BoxCollider\",\"center\":" + cen + ",\"size\":" + siz
            o = o + ",\"isTrigger\":" + trig + "}"
            ret o
        }
        SphereCollider sc = c as SphereCollider
        if sc != null
        {
            string trig = "false"
            if sc.isTrigger
            {
                trig = "true"
            }
            string cen = SceneExporter.vec3( sc.center.x, sc.center.y, sc.center.z )
            string rad = sc.radius.toString()
            string o = "{\"type\":\"SphereCollider\",\"center\":" + cen + ",\"radius\":" + rad
            o = o + ",\"isTrigger\":" + trig + "}"
            ret o
        }
        CapsuleCollider cc = c as CapsuleCollider
        if cc != null
        {
            string trig = "false"
            if cc.isTrigger
            {
                trig = "true"
            }
            string cen = SceneExporter.vec3( cc.center.x, cc.center.y, cc.center.z )
            string rad = cc.radius.toString()
            string hgt = cc.height.toString()
            string o = "{\"type\":\"CapsuleCollider\",\"center\":" + cen + ",\"radius\":" + rad
            o = o + ",\"height\":" + hgt + ",\"isTrigger\":" + trig + "}"
            ret o
        }
        SpriteRenderer sr = c as SpriteRenderer
        if sr != null
        {
            ret "{\"type\":\"SpriteRenderer\"}"
        }
        Behaviour bh = c as Behaviour
        if bh != null
        {
            string tname = c.type.toString()
            string oname = SceneExporter.esc( tname )
            ret "{\"type\":\"Script\",\"script\":\"" + oname + "\"}"
        }
        ret ""
    }

    static string componentsOf( GameObject go )
    {
        string o = "["
        bool first = true
        Int32 i = 0
        Int32 n = go.components.length
        while i < n
        {
            Component c = go.components[i]
            string part = SceneExporter.componentOf( c )
            if part != ""
            {
                if !first
                {
                    o = o + ","
                }
                o = o + part
                first = false
            }
            i = i + 1
        }
        ret o + "]"
    }

    static string nodeOf( GameObject go, Int32 id, Int32 parentId )
    {
        string idS = id.toString()
        string pidS = parentId.toString()
        string oname = SceneExporter.esc( go.name )
        string otag = SceneExporter.esc( go.tag )
        string lay = go.layer.toString()
        string act = "true"
        if !go.activeSelf
        {
            act = "false"
        }
        Transform t = go.transform
        Float32_3 p = t.localPosition
        Float32_3 s = t.localScale
        string pos = SceneExporter.vec3( p.x, p.y, p.z )
        string rot = SceneExporter.quat( t.rotation )
        string scl = SceneExporter.vec3( s.x, s.y, s.z )
        string comps = SceneExporter.componentsOf( go )
        string o = "{\"id\":" + idS + ",\"parent\":" + pidS + ",\"name\":\"" + oname + "\""
        o = o + ",\"tag\":\"" + otag + "\",\"layer\":" + lay + ",\"active\":" + act
        o = o + ",\"transform\":{\"localPosition\":" + pos + ",\"localRotation\":" + rot
        o = o + ",\"localScale\":" + scl + "}"
        o = o + ",\"components\":" + comps + "}"
        ret o
    }

    # ── 公共出口 ─────────────────────────────────────────
    public static string toJson( Scene scene )
    {
        List<GameObject> order = List<GameObject>( 16 )
        List<Int32> parents = List<Int32>( 16 )
        Int32 ri = 0
        Int32 rn = scene.rootCount
        while ri < rn
        {
            GameObject root = scene.getRoot( ri )
            if root != null
            {
                SceneExporter.collect( root, 0, order, parents )
            }
            ri = ri + 1
        }
        string sname = ""
        if scene.name != null
        {
            sname = SceneExporter.esc( scene.name )
        }
        string o = "{\n  \"version\": 1,\n  \"scene\": \"" + sname + "\",\n  \"nodes\": ["
        Int32 i = 0
        Int32 n = order.length
        while i < n
        {
            GameObject go = order[i]
            Int32 parentId = parents[i]
            Int32 id = i + 1
            if i > 0
            {
                o = o + ","
            }
            o = o + "\n    " + SceneExporter.nodeOf( go, id, parentId )
            i = i + 1
        }
        if n > 0
        {
            o = o + "\n  "
        }
        o = o + "]\n}\n"
        ret o
    }

    public static bool save( Scene scene, string path )
    {
        if scene == null || path == null || path.length == 0
        {
            ret false
        }
        string text = SceneExporter.toJson( scene )
        bool ok = File.writeAllText( path, text )
        ret ok
    }
}
