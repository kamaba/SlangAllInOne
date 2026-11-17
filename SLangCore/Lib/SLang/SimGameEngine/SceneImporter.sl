import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SceneImporter — 统一 JSON 资源导入器（P8 完整导入器 v1，doc/16 §5）
# ----------------------------------------------------------------------------
# 消费 doc/16 §4 schema（Unity 导出器 / 未来 FBX 转换器同一 schema）：
#   manifest.json（version 校验，不识别明确报错）→ scene.json → 建树挂组件。
# 组件映射（v1）：MeshFilter→MeshRef(MESH_CUSTOM，槽位 4..7 轮转登记)、
#   MeshRenderer→MaterialData+MaterialRef、Rigidbody、BoxCollider/
#   SphereCollider、SpriteRenderer；Camera/Light 引擎无对应组件 → 计数登记；
#   未识别 type → skippedCount（与「静默忽略并统计」同原则）。
# 约定（doc/16 §8 + 本轮实证）：
#   - 不 import Core（Core 类型自动可见，显式导入炸解析链）；
#   - 跨模块方法链 a.b().c() 与「方法调用表达式作实参」一律拆单步局部变量；
#   - ret 不携带内联构造表达式/跨模块调用——先落局部变量；
#   - 本模块编译链 try/catch 触发 ParseStatements 元崩溃（MetaTRStatements
#     ctor null，2026-11-17 实证）——文件存在性用 File.exists 预检替代；
#   - 变量名避开 `def`（不支持关键字，Python 词）。
# Transform：Unity 全 3D 四元数经统一版 Transform.setPositionAndRotation
# 直传（Merge 版支持非纯 Z 旋转）；localRotation 缺省 [0,0,0,1]。
# 本类是纯胶水（JSON 遍历 + 建树），JSON 解析本身由 Core Json（VM 内建）
# 承担——符合「重计算下沉 C、SL 只放类与接口」约定，无新增 C 函数。
# ============================================================================
public class SceneImporter
{
    # MESH_CUSTOM 顶点上传槽位轮转（4..7，Render 约定 slot 4..7 可 uploadMesh）
    public Int32 customSlotBase = 4
    public Int32 customSlotCount = 4
    Int32 _slotCursor = 0

    Int32 nextSlot()
    {
        Int32 s = this.customSlotBase + this._slotCursor
        this._slotCursor = this._slotCursor + 1
        if this._slotCursor >= this.customSlotCount
        {
            this._slotCursor = 0
        }
        ret s
    }

    # ── JSON 辅助（缺省兜底）────────────────────────────
    static Float32_3 jsonVec3( JsonValue node, Float32 dx, Float32 dy, Float32 dz )
    {
        Float32 x = dx
        Float32 y = dy
        Float32 z = dz
        bool has = !node.isNull()
        if has
        {
            Array<JsonValue> arr = node.children()
            Int32 n = arr.length
            if n > 0
            {
                JsonValue v0 = arr[0]
                x = v0.asFloat32()
            }
            if n > 1
            {
                JsonValue v1 = arr[1]
                y = v1.asFloat32()
            }
            if n > 2
            {
                JsonValue v2 = arr[2]
                z = v2.asFloat32()
            }
        }
        Float32_3 out3 = Float32_3( x, y, z )
        ret out3
    }

    static Quaternion jsonQuat( JsonValue node )
    {
        Float32 x = 0.0f
        Float32 y = 0.0f
        Float32 z = 0.0f
        Float32 w = 1.0f
        bool has = !node.isNull()
        if has
        {
            Array<JsonValue> arr = node.children()
            Int32 n = arr.length
            if n > 0
            {
                JsonValue v0 = arr[0]
                x = v0.asFloat32()
            }
            if n > 1
            {
                JsonValue v1 = arr[1]
                y = v1.asFloat32()
            }
            if n > 2
            {
                JsonValue v2 = arr[2]
                z = v2.asFloat32()
            }
            if n > 3
            {
                JsonValue v3 = arr[3]
                w = v3.asFloat32()
            }
        }
        Quaternion outq = Quaternion( x, y, z, w )
        ret outq
    }

    # ── 目录入口（manifest.json + scene.json）───────────
    # 坑：本模块编译链 try/catch 触发 ParseStatements 元崩溃——File.exists
    # 预检 + 直读（doc/16 §8.14 的 throws 语义在 SimSceneTest 场景走 try/catch）
    public ImportReport loadDir( string exportDir )
    {
        ImportReport rep = ImportReport()
        string manifestPath = exportDir + "/manifest.json"
        bool hasM = File.exists( manifestPath )
        if !hasM
        {
            rep.lastError = "manifest not readable: " + exportDir
            ret rep
        }
        string manifestText = File.readAllText( manifestPath )
        JsonValue mroot = JsonValue.parse( manifestText )
        bool mNull = mroot.isNull()
        if mNull
        {
            rep.lastError = "manifest parse failed"
            ret rep
        }
        JsonValue mverNode = mroot.select("version")
        Int32 mver = mverNode.asInt32( 0 )
        if mver != 1
        {
            rep.lastError = "unsupported manifest version: " + mver.toString()
            ret rep
        }
        string scenePath = exportDir + "/scene.json"
        bool hasS = File.exists( scenePath )
        if !hasS
        {
            rep.lastError = "scene.json not readable: " + exportDir
            ret rep
        }
        string sceneText = File.readAllText( scenePath )
        ImportReport outRep = this.parseCore( mver, sceneText )
        ret outRep
    }

    # ── 核心：scene.json 文本 → Scene（可脱离文件测试）──
    public ImportReport parseCore( Int32 manifestVersion, string sceneText )
    {
        ImportReport rep = ImportReport()
        rep.version = manifestVersion
        if manifestVersion != 1
        {
            rep.lastError = "unsupported manifest version: " + manifestVersion.toString()
            ret rep
        }
        JsonValue root = JsonValue.parse( sceneText )
        bool rNull = root.isNull()
        if rNull
        {
            rep.lastError = "scene.json parse failed"
            ret rep
        }
        JsonValue sverNode = root.select("version")
        Int32 sver = sverNode.asInt32( 0 )
        if sver != 1
        {
            rep.lastError = "unsupported scene version: " + sver.toString()
            ret rep
        }
        JsonValue snameNode = root.select("scene")
        rep.sceneName = snameNode.asString( "Imported" )
        Scene scene = Scene( rep.sceneName )
        rep.scene = scene
        JsonValue nodesNode = root.select("nodes")
        Array<JsonValue> nodes = nodesNode.children()
        Int32 n = nodes.length
        List<Int32> ids = List<Int32>( n )
        List<GameObject> gos = List<GameObject>( n )
        # Pass A：全量建节点（先挂根；层级在 Pass B 用 setParent 修正）
        Int32 i = 0
        while i < n
        {
            JsonValue node = nodes[i]
            JsonValue nameNode = node.select("name")
            string name = nameNode.asString( "Node" )
            GameObject go = scene.createObject( name )
            JsonValue idNode = node.select("id")
            Int32 id = idNode.asInt32( 0 )
            ids.add( id )
            gos.add( go )
            rep.nodeCount = rep.nodeCount + 1
            i = i + 1
        }
        # Pass B：层级 + 变换 + 组件
        i = 0
        while i < n
        {
            JsonValue node = nodes[i]
            GameObject go = gos[i]
            JsonValue pidNode = node.select("parent")
            Int32 pid = pidNode.asInt32( 0 )
            if pid > 0
            {
                # 父节点查找（ids 线性扫；节点规模千级内可接受）
                GameObject pgo = null
                Int32 j = 0
                while j < n
                {
                    Int32 cand = ids[j]
                    if cand == pid
                    {
                        pgo = gos[j]
                        j = n
                    }
                    else
                    {
                        j = j + 1
                    }
                }
                if pgo == null
                {
                    rep.skippedCount = rep.skippedCount + 1
                }
                else
                {
                    go.setParent( pgo )
                }
            }
            else
            {
                rep.rootCount = rep.rootCount + 1
            }
            # 变换（Unity 全 3D 直传统一版 Transform）
            # ⚠ `tr` 是 Transience 保留字——用它当变量名触发 MetaTRStatements
            # 元崩溃（root is Null，2026-11-17 第 5 次踩）——命名避让 trNode
            JsonValue trNode = node.select("transform")
            JsonValue lpNode = trNode.select("localPosition")
            JsonValue lrNode = trNode.select("localRotation")
            JsonValue lsNode = trNode.select("localScale")
            Float32_3 pos = SceneImporter.jsonVec3( lpNode, 0.0f, 0.0f, 0.0f )
            Quaternion q = SceneImporter.jsonQuat( lrNode )
            Float32_3 scale = SceneImporter.jsonVec3( lsNode, 1.0f, 1.0f, 1.0f )
            Transform t = go.transform
            t.setPositionAndRotation( pos, q )
            t.setScale( scale )
            # 节点级属性
            JsonValue actNode = node.select("active")
            bool active = actNode.asBool( true )
            if !active
            {
                go.setActive( false )
            }
            JsonValue layNode = node.select("layer")
            Int32 layer = layNode.asInt32( 0 )
            go.layer = layer
            JsonValue tagNode = node.select("tag")
            string tag = tagNode.asString( "" )
            if tag != ""
            {
                go.tag = tag
            }
            # 组件
            JsonValue compsNode = node.select("components")
            Array<JsonValue> comps = compsNode.children()
            Int32 cn = comps.length
            Int32 k = 0
            while k < cn
            {
                JsonValue comp = comps[k]
                JsonValue typeNode = comp.select("type")
                string ctype = typeNode.asString( "" )
                this.importComponent( go, comp, ctype, rep )
                k = k + 1
            }
            i = i + 1
        }
        rep.ok = true
        ret rep
    }

    # 组件映射分派（rep 计数与资源登记；JSON 取值一律两步局部变量）
    void importComponent( GameObject go, JsonValue comp, string ctype, ImportReport rep )
    {
        if ctype == "MeshFilter"
        {
            MeshRef mr = MeshRef()
            mr.meshKind = 4
            mr.meshSlot = this.nextSlot()
            go.addComponent( mr )
            JsonValue meshNode = comp.select("mesh")
            string meshId = meshNode.asString( "" )
            rep.addMeshId( meshId )
            rep.meshCount = rep.meshCount + 1
            ret
        }
        if ctype == "MeshRenderer"
        {
            MaterialData md = MaterialData()
            JsonValue matNode = comp.select("material")
            md.name = matNode.asString( "" )
            JsonValue rqNode = comp.select("renderQueue")
            md.renderQueue = rqNode.asInt32( 2000 )
            JsonValue csNode = comp.select("castShadow")
            md.castShadow = csNode.asBool( false )
            MaterialRef mref = MaterialRef()
            mref.material = md
            go.addComponent( mref )
            rep.materialCount = rep.materialCount + 1
            ret
        }
        if ctype == "Rigidbody"
        {
            Rigidbody rb = Rigidbody()
            JsonValue massNode = comp.select("mass")
            rb.mass = massNode.asFloat32( 1.0f )
            JsonValue gravNode = comp.select("useGravity")
            rb.useGravity = gravNode.asBool( true )
            go.addComponent( rb )
            rep.rigidbodyCount = rep.rigidbodyCount + 1
            ret
        }
        if ctype == "BoxCollider"
        {
            BoxCollider bc = BoxCollider()
            JsonValue cNode = comp.select("center")
            JsonValue sNode = comp.select("size")
            JsonValue trigNode = comp.select("isTrigger")
            bc.center = SceneImporter.jsonVec3( cNode, 0.0f, 0.0f, 0.0f )
            bc.size = SceneImporter.jsonVec3( sNode, 1.0f, 1.0f, 1.0f )
            bc.isTrigger = trigNode.asBool( false )
            go.addComponent( bc )
            rep.colliderCount = rep.colliderCount + 1
            ret
        }
        if ctype == "SphereCollider"
        {
            SphereCollider sc = SphereCollider()
            JsonValue cNode = comp.select("center")
            JsonValue rNode = comp.select("radius")
            JsonValue trigNode = comp.select("isTrigger")
            sc.center = SceneImporter.jsonVec3( cNode, 0.0f, 0.0f, 0.0f )
            sc.radius = rNode.asFloat32( 0.5f )
            sc.isTrigger = trigNode.asBool( false )
            go.addComponent( sc )
            rep.colliderCount = rep.colliderCount + 1
            ret
        }
        if ctype == "SpriteRenderer"
        {
            SpriteRenderer sr = SpriteRenderer()
            go.addComponent( sr )
            rep.spriteCount = rep.spriteCount + 1
            ret
        }
        if ctype == "Camera"
        {
            # 引擎无 Camera 组件——计数登记（相机参数随 Render 管线接入消费）
            rep.cameraCount = rep.cameraCount + 1
            ret
        }
        if ctype == "Light"
        {
            # 引擎无 Light 组件——计数登记（LightProbe/直接光随 Render 消费）
            rep.lightCount = rep.lightCount + 1
            ret
        }
        rep.skippedCount = rep.skippedCount + 1
    }
}
