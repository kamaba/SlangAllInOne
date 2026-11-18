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

    # 脚本工厂注册表（doc/19）：scene.json 的 {type:"Script",script:"<短名>"}
    # 节点按注册名找到工厂，工厂收到该组件 JSON（可读自定义参数），返回
    # Behaviour 实例并挂到节点——等价 Unity「场景里挂 MonoBehaviour」。
    # 工厂形态：void(JsonValue cfg, ScriptResult out)——Function 是唯一可作为
    # List 元素的委托类型（Func<> 字段形式已废弃，MetaCoreCallIssue13）。
    List<string> _scriptNames = null
    List<Function> _scriptFactories = null

    public void _init_()
    {
        this.customSlotBase = 4
        this.customSlotCount = 4
        this._slotCursor = 0
        this._scriptNames = List<string>( 8 )
        this._scriptFactories = List<Function>( 8 )
    }

    public void registerScript( string name, Function factory )
    {
        if name == null || name.length == 0 || factory == null
        {
            ret
        }
        if this._scriptNames.indexOf( name ) >= 0
        {
            ret
        }
        this._scriptNames.add( name )
        this._scriptFactories.add( factory )
    }

    # 直读单个 scene.json 文件（SceneManager 按路径加载用；目录入口仍走 loadDir）
    public ImportReport loadFile( string sceneFilePath )
    {
        ImportReport rep = ImportReport()
        bool has = File.exists( sceneFilePath )
        if !has
        {
            rep.lastError = "scene file not readable: " + sceneFilePath
            ret rep
        }
        string text = File.readAllText( sceneFilePath )
        ImportReport outRep = this.parseCore( 1, text )
        ret outRep
    }

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
            JsonValue kindNode = comp.select("meshKind")
            JsonValue slotNode = comp.select("meshSlot")
            mr.meshKind = kindNode.asInt32( mr.meshKind )
            mr.meshSlot = slotNode.asInt32( mr.meshSlot )
            go.addComponent( mr )
            JsonValue meshNode = comp.select("mesh")
            string meshId = meshNode.asString( "" )
            rep.addMeshId( meshId )
            # SceneExporter 回写的顶点块：还原到 MeshRef 走 Batcher 烘焙路径
            JsonValue verticesNode = comp.select("vertices")
            Array<JsonValue> vs = verticesNode.children()
            if vs.length > 0
            {
                List<Float32_3> vl = List<Float32_3>( vs.length )
                Int32 vi = 0
                while vi < vs.length
                {
                    JsonValue vp = vs[vi]
                    Float32_3 vv = SceneImporter.jsonVec3( vp, 0.0f, 0.0f, 0.0f )
                    vl.add( vv )
                    vi = vi + 1
                }
                mr.setVertices( vl )
            }
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
            JsonValue colorNode = comp.select("color")
            Float32_3 col = SceneImporter.jsonVec3( colorNode, 1.0f, 1.0f, 1.0f )
            md.color = col
            # v2.13：材质模型 / 高光锐度 / 贴图（texture 绝对路径或相对场景
            # 目录的文件；装载失败保持 null = 纯色，不中止导入）
            JsonValue mmNode = comp.select("materialModel")
            md.materialModel = mmNode.asInt32( 0 )
            JsonValue shNode = comp.select("shininess")
            md.shininess = shNode.asFloat32( 32.0f )
            JsonValue txNode = comp.select("texture")
            string texPath = txNode.asString( "" )
            if texPath != ""
            {
                SLang.RenderTexture tex = SLang.RenderTexture.loadFile( texPath )
                md.texture = tex
                if tex == null
                {
                    rep.skippedCount = rep.skippedCount + 1
                }
                else
                {
                    rep.textureCount = rep.textureCount + 1
                }
            }
            MaterialRef mref = MaterialRef()
            mref.material = md
            go.addComponent( mref )
            rep.materialCount = rep.materialCount + 1
            ret
        }
        if ctype == "CapsuleCollider"
        {
            CapsuleCollider cc = CapsuleCollider()
            JsonValue cNode = comp.select("center")
            JsonValue rNode = comp.select("radius")
            JsonValue hNode = comp.select("height")
            JsonValue trigNode = comp.select("isTrigger")
            cc.center = SceneImporter.jsonVec3( cNode, 0.0f, 0.0f, 0.0f )
            cc.radius = rNode.asFloat32( 0.5f )
            cc.height = hNode.asFloat32( 2.0f )
            cc.isTrigger = trigNode.asBool( false )
            go.addComponent( cc )
            rep.colliderCount = rep.colliderCount + 1
            ret
        }
        if ctype == "Script"
        {
            JsonValue scriptNode = comp.select("script")
            string scriptName = scriptNode.asString( "" )
            Int32 idx = this._scriptNames.indexOf( scriptName )
            if idx >= 0
            {
                Function f = this._scriptFactories[idx]
                ScriptResult holder = ScriptResult()
                f( comp, holder )
                Behaviour inst = holder.value
                if inst != null
                {
                    go.addComponent( inst )
                    rep.scriptCount = rep.scriptCount + 1
                    ret
                }
            }
            rep.skippedCount = rep.skippedCount + 1
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
            # v2.13：LightData 光源组件（RenderSystem.sync 每帧收集写管线槽）
            LightData ld = LightData()
            JsonValue ltNode = comp.select("lightType")
            Int32 lt = ltNode.asInt32( 0 )
            if lt < 0
            {
                lt = 0
            }
            if lt > 2
            {
                lt = 2
            }
            ld.type = lt
            JsonValue lcNode = comp.select("color")
            ld.color = SceneImporter.jsonVec3( lcNode, 1.0f, 1.0f, 1.0f )
            JsonValue liNode = comp.select("intensity")
            ld.intensity = liNode.asFloat32( 1.0f )
            JsonValue ldxNode = comp.select("dirX")
            ld.dirX = ldxNode.asFloat32( 1.0f )
            JsonValue ldyNode = comp.select("dirY")
            ld.dirY = ldyNode.asFloat32( 0.0f )
            JsonValue lpxNode = comp.select("posX")
            ld.posX = lpxNode.asFloat32( 0.0f )
            JsonValue lpyNode = comp.select("posY")
            ld.posY = lpyNode.asFloat32( 0.0f )
            JsonValue lsaNode = comp.select("spotAngle")
            ld.spotAngle = lsaNode.asFloat32( 30.0f )
            JsonValue lrNode = comp.select("range")
            ld.lightRange = lrNode.asFloat32( 0.0f )
            JsonValue lsqNode = comp.select("shadowQuality")
            ld.shadowQuality = lsqNode.asFloat32( 0.0f )
            JsonValue lsbNode = comp.select("shadowBias")
            ld.shadowBias = lsbNode.asFloat32( 0.0f )
            JsonValue lstNode = comp.select("shadowStrength")
            ld.shadowStrength = lstNode.asFloat32( 0.0f )
            JsonValue lscNode = comp.select("shadowCascades")
            ld.shadowCascades = lscNode.asFloat32( 0.0f )
            go.addComponent( ld )
            rep.lightCount = rep.lightCount + 1
            ret
        }
        rep.skippedCount = rep.skippedCount + 1
    }
}
