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

    # 标量浮点：Release JIT 下高频 Float32.toString() 可能返回 null，
    # 统一走 toFormat（doc/19 §坑）。
    static string f( Float32 v )
    {
        string s = String.toFormat( "{0}", v )
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
        # v1.1：LightData（SceneImporter 的 Light 分支对称——此前落在
        # 下面的 Behaviour 兜底里被写成 Script 短名，round-trip 丢光源）
        LightData ld = c as LightData
        if ld != null
        {
            string col = SceneExporter.vec3( ld.color.x, ld.color.y, ld.color.z )
            string ty = ld.type.toString()
            string it = SceneExporter.f( ld.intensity )
            string o = "{\"type\":\"Light\",\"lightType\":" + ty + ",\"color\":" + col
            o = o + ",\"intensity\":" + it
            o = o + ",\"dirX\":" + SceneExporter.f( ld.dirX )
            o = o + ",\"dirY\":" + SceneExporter.f( ld.dirY )
            o = o + ",\"posX\":" + SceneExporter.f( ld.posX )
            o = o + ",\"posY\":" + SceneExporter.f( ld.posY )
            o = o + ",\"spotAngle\":" + SceneExporter.f( ld.spotAngle )
            o = o + ",\"range\":" + SceneExporter.f( ld.lightRange )
            o = o + ",\"shadowQuality\":" + SceneExporter.f( ld.shadowQuality )
            o = o + ",\"shadowBias\":" + SceneExporter.f( ld.shadowBias )
            o = o + ",\"shadowStrength\":" + SceneExporter.f( ld.shadowStrength )
            o = o + ",\"shadowCascades\":" + SceneExporter.f( ld.shadowCascades )
            ret o + "}"
        }
        # v1.1：Volume + VolumeProfile（只写 hasXxx=1 的字段——缺省
        # = 不修改，与 SceneImporter 的 select 判空语义对称）
        Volume vol = c as Volume
        if vol != null
        {
            string glob = "false"
            if vol.isGlobal
            {
                glob = "true"
            }
            string pri = vol.priority.toString()
            string wt = SceneExporter.f( vol.weight )
            string bd = SceneExporter.f( vol.blendDistance )
            string o = "{\"type\":\"Volume\",\"isGlobal\":" + glob + ",\"priority\":" + pri
            o = o + ",\"weight\":" + wt + ",\"blendDistance\":" + bd
            VolumeProfile prof = vol.profile
            if prof != null
            {
                if prof.hasBrightness
                {
                    o = o + ",\"brightness\":" + SceneExporter.f( prof.brightness )
                }
                if prof.hasContrast
                {
                    o = o + ",\"contrast\":" + SceneExporter.f( prof.contrast )
                }
                if prof.hasSaturation
                {
                    o = o + ",\"saturation\":" + SceneExporter.f( prof.saturation )
                }
                if prof.hasHueShift
                {
                    o = o + ",\"hueShift\":" + SceneExporter.f( prof.hueShift )
                }
                if prof.hasFilter
                {
                    o = o + ",\"filterR\":" + SceneExporter.f( prof.filterR )
                    o = o + ",\"filterG\":" + SceneExporter.f( prof.filterG )
                    o = o + ",\"filterB\":" + SceneExporter.f( prof.filterB )
                }
                if prof.hasVignette
                {
                    o = o + ",\"vignette\":" + SceneExporter.f( prof.vignette )
                }
                if prof.hasVignetteSmooth
                {
                    o = o + ",\"vignetteSmooth\":" + SceneExporter.f( prof.vignetteSmooth )
                }
                if prof.hasGrain
                {
                    o = o + ",\"grain\":" + SceneExporter.f( prof.grain )
                }
                if prof.hasTonemap
                {
                    o = o + ",\"tonemap\":" + prof.tonemapMode.toString()
                }
            }
            ret o + "}"
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

    # ── 共用序列化核心：DFS 顺序 + 平坦节点数组 ──────────
    # Scene 与 Prefab 共用：输入任意「根列表」，输出 scene.json 同构
    # 的 {version,scene,nodes} 文本（Prefab 只是单根的特例）。
    static string nodesToJson( string name, List<GameObject> order, List<Int32> parents )
    {
        string sname = ""
        if name != null
        {
            sname = SceneExporter.esc( name )
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
            sname = scene.name
        }
        string text = SceneExporter.nodesToJson( sname, order, parents )
        ret text
    }

    # Prefab：单个 GameObject 子树 → scene.json 同构文本（单根 parent=0）。
    # 名字缺省用根节点名；读取侧直接走 SceneImporter.parseCore，零重复代码。
    public static string toJsonRoot( GameObject root, string prefabName )
    {
        if root == null
        {
            ret ""
        }
        List<GameObject> order = List<GameObject>( 16 )
        List<Int32> parents = List<Int32>( 16 )
        SceneExporter.collect( root, 0, order, parents )
        string name = prefabName
        if name == null || name.length == 0
        {
            name = root.name
        }
        string text = SceneExporter.nodesToJson( name, order, parents )
        ret text
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
