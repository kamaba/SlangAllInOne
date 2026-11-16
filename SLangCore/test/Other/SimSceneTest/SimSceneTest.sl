import SLangQT;
import SLangRender;
import Math;
import Std;
# 注意：不要 import Core —— Core 类型（JsonValue 等）随引用自动可见，
# 显式 import 会触发 MetaCore 解析链异常（节点 not found / 表达式 604）。

# ============================================================================
# SimSceneTest — Unity CubeDemo 导出数据 -> SLangRender 端到端
# ----------------------------------------------------------------------------
# 数据源（Unity 导出器 SlangSceneExporter 产出，见 SimGameEngine/doc/16）：
#   <EXPORT_DIR>/scene.json    节点树（Cube: MeshFilter/MeshRenderer/BoxCollider;
#                              Sun: Light directional）
#   <EXPORT_DIR>/mesh_1.json   网格元数据（24 顶点 / 36 索引 / stride 32）
#   <EXPORT_DIR>/mesh_1.bin    "SLMESH" + u32*4 + f32[vc*8](pos3,normal3,uv2) + u32[ic]
# 本测试从导出数据重建网格（顶点/UV/索引/Transform 全部来自 Unity 导出），
# 经 MESH_CUSTOM + uploadMesh 通道进 13 阶段管线渲染旋转 Cube。
#
# SL 侧经验（本轮实证，复盘待归档）：
#   1) 不要显式 import Core（引用模块类型已自动可见，显式导入炸解析链）；
#   2) 跨模块对象方法调用不要链式（a.b().c()），一律拆单步局部变量；
#   3) return 不要直接携带跨模块方法调用，先赋局部变量再 ret；
#   4) throws 方法（File.readAllBytes）必须 try/catch。
# ============================================================================

public class SimSceneTest
{
    static string EXPORT_DIR = "C:/Users/Administrator/My project (1)/Assets/StreamingAssets/SlangExport/CubeDemo"

    static Int32 W = 276
    static Int32 H = 296

    static SLang.QApplication _app = null
    static SLang.QLabel _label = null
    static SLang.RenderPipeline _pipe = null
    static SLang.RenderObject _cube = null
    static Int64 _pixels = 0
    static Int64 _vbuf = 0
    static Float32 _t = 0.0f
    static Int32 _okFrames = 0

    # 导出网格数据（bin 解析结果）
    static Array<Float32> _vx = null
    static Array<Float32> _vy = null
    static Array<Float32> _vz = null
    static Array<Float32> _vu = null
    static Array<Float32> _vv = null
    static Array<Int32> _tris = null

    # 节点 Transform（scene.json）
    static Float32 _ox = 0.0f
    static Float32 _oy = 0.0f
    static Float32 _oz = 0.0f
    static Float32 _scale = 1.0f
    static Int32 _renderQueue = 2000

    # ── 导出数据装载 ────────────────────────────────────────────
    static Int32 u32At( UInt8Array b, Int32 off )
    {
        Int32 v = b[off] + b[off + 1] * 256 + b[off + 2] * 65536 + b[off + 3] * 16777216
        ret v
    }

    static bool loadData()
    {
        # 1) scene.json：取第一个 MeshFilter 节点
        string sceneText = File.readAllText( EXPORT_DIR + "/scene.json" )
        JsonValue scene = JsonValue.parse( sceneText )
        if scene.isNull()
        {
            Console.println( "[data] FAIL: parse scene.json" )
            ret false
        }
        JsonValue nodesNode = scene.select("nodes")
        Array<JsonValue> nodes = nodesNode.children()
        Int32 nodeCount = nodes.length
        string meshId = ""
        Int32 i = 0
        while i < nodeCount
        {
            JsonValue curNode = nodes[ i ]
            JsonValue compsNode = curNode.select("components")
            Array<JsonValue> comps = compsNode.children()
            JsonValue trNode = curNode.select("transform")
            Int32 cn = comps.length
            Int32 j = 0
            while j < cn
            {
                JsonValue comp = comps[ j ]
                JsonValue typeNode = comp.select("type")
                string ctype = typeNode.asString()
                if ctype == "MeshFilter" && meshId == ""
                {
                    JsonValue meshNode = comp.select("mesh")
                    meshId = meshNode.asString()
                    JsonValue lpNode = trNode.select("localPosition")
                    Array<JsonValue> lp = lpNode.children()
                    JsonValue v0 = lp[ 0 ]
                    JsonValue v1 = lp[ 1 ]
                    JsonValue v2 = lp[ 2 ]
                    _ox = v0.asFloat32()
                    _oy = v1.asFloat32()
                    _oz = v2.asFloat32()
                    JsonValue lsNode = trNode.select("localScale")
                    Array<JsonValue> ls = lsNode.children()
                    JsonValue s0 = ls[ 0 ]
                    JsonValue s1 = ls[ 1 ]
                    JsonValue s2 = ls[ 2 ]
                    Float32 sx = s0.asFloat32()
                    Float32 sy = s1.asFloat32()
                    Float32 sz = s2.asFloat32()
                    _scale = ( sx + sy + sz ) / 3.0f
                }
                if ctype == "MeshRenderer"
                {
                    JsonValue rqNode = comp.select("renderQueue")
                    _renderQueue = rqNode.asInt32()
                }
                j = j + 1
            }
            i = i + 1
        }
        if meshId == ""
        {
            Console.println( "[data] FAIL: no MeshFilter node in scene.json" )
            ret false
        }
        Console.println( "[data] node mesh=" + meshId + " pos=" + _ox.toString() + "," + _oy.toString() + "," + _oz.toString() + " queue=" + _renderQueue.toString() )

        # 2) mesh json 元数据
        string meshPath = EXPORT_DIR + "/" + meshId + ".json"
        string meshText = File.readAllText( meshPath )
        JsonValue mj = JsonValue.parse( meshText )
        if mj.isNull()
        {
            Console.println( "[data] FAIL: parse mesh json" )
            ret false
        }
        JsonValue vcNode = mj.select("vertexCount")
        Int32 vc = vcNode.asInt32()
        JsonValue strideNode = mj.select("vertexStride")
        Int32 stride = strideNode.asInt32()
        JsonValue icNode = mj.select("indexCount")
        Int32 ic = icNode.asInt32()
        JsonValue binNode = mj.select("bin")
        string binName = binNode.asString()
        Console.println( "[data] mesh vc=" + vc.toString() + " stride=" + stride.toString() + " ic=" + ic.toString() + " bin=" + binName )
        if stride != 32
        {
            Console.println( "[data] FAIL: unexpected stride (expect 32)" )
            ret false
        }

        # 3) mesh bin：SLMESH 头 + 顶点 + 索引
        string binPath = EXPORT_DIR + "/" + binName
        if File.exists( binPath ) == false
        {
            Console.println( "[data] FAIL: bin missing: " + binPath )
            ret false
        }
        UInt8Array bytes = null
        try
        {
            bytes = File.readAllBytes( binPath )
        }
        catch ex
        {
            Console.println( "[data] FAIL: read bin exception" )
            ret false
        }
        # 坑：当前 VM 上 UInt8Array.length 返回容量语义（实测 512），不可信——
        # 以 json 声明的 vc/stride/ic 推导数据长度，逐字节拷贝并越界捕获。
        Int32 need = 22 + vc * stride + ic * 4
        if u32At( bytes, 6 ) != 1
        {
            Console.println( "[data] FAIL: unsupported bin version" )
            ret false
        }
        Int32 headVc = u32At( bytes, 10 )
        Int32 headStride = u32At( bytes, 14 )
        Int32 headIc = u32At( bytes, 18 )
        if headVc != vc || headStride != stride || headIc != ic
        {
            Console.println( "[data] FAIL: bin header mismatch json" )
            ret false
        }

        # 拷入原生内存供 readFloat32 读取
        Int64 raw = Memory.alloc( need )
        if raw == 0
        {
            Console.println( "[data] FAIL: alloc raw" )
            ret false
        }
        Int32 bi = 0
        while bi < need
        {
            Memory.writeI8( raw, bi, bytes[bi] )
            bi = bi + 1
        }

        _vx = Array<Float32>( vc )
        _vy = Array<Float32>( vc )
        _vz = Array<Float32>( vc )
        _vu = Array<Float32>( vc )
        _vv = Array<Float32>( vc )
        Int32 vi = 0
        while vi < vc
        {
            Int32 vo = 22 + vi * stride
            _vx[ vi ] = Memory.readFloat32( raw, vo )
            _vy[ vi ] = Memory.readFloat32( raw, vo + 4 )
            _vz[ vi ] = Memory.readFloat32( raw, vo + 8 )
            _vu[ vi ] = Memory.readFloat32( raw, vo + 24 )
            _vv[ vi ] = Memory.readFloat32( raw, vo + 28 )
            vi = vi + 1
        }
        _tris = Array<Int32>( ic )
        Int32 ti = 0
        while ti < ic
        {
            _tris[ ti ] = Memory.readInt32( raw, 22 + vc * stride + ti * 4 )
            ti = ti + 1
        }
        Memory.free( raw )
        Int32 triCount = ic / 3
        Console.println( "[data] OK: verts=" + vc.toString() + " tris=" + triCount.toString() )
        ret true
    }

    # ── 渲染初始化 ──────────────────────────────────────────────
    static bool setup()
    {
        if SLang.Render.initialize() == false
        {
            Console.println( "FAIL: render init - " + SLang.Render.errorString() )
            ret false
        }
        if SLang.Render.initializeBackend( "gl" ) == false
        {
            Console.println( "FAIL: init gl - " + SLang.Render.errorString() )
            ret false
        }
        _pipe = SLang.RenderPipeline.create( W, H )
        if _pipe == null
        {
            Console.println( "FAIL: pipe create - " + SLang.Render.errorString() )
            ret false
        }
        _cube = _pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
        if _cube == null
        {
            Console.println( "FAIL: cube addObject - " + SLang.Render.errorString() )
            ret false
        }
        _cube.setColor( 0.95f, 0.62f, 0.20f, 1.0f )
        if _renderQueue >= 2500
        {
            _cube.setQueue( _renderQueue )
        }
        _pixels = Memory.alloc( W * H * 4 )
        _vbuf = Memory.alloc( 65536 )
        if _pixels == 0 || _vbuf == 0
        {
            Console.println( "FAIL: alloc buffers" )
            ret false
        }
        ret true
    }

    # ── 每帧：导出顶点 -> NDC 投影 + 深度排序 -> 16B 展开上传 ────
    # 自定义网格顶点布局（C 侧约定）：每顶点 16B = (x, y, u, v) f32，
    # x/y 为 NDC（+y 上）；投影/排序在 SL 侧完成（对齐 RenderTest.updateCube）。
    static bool updateVerts()
    {
        Float32_4x4 ry = Float32_4x4.rotationY( _t * 0.9f )
        Float32_4x4 rx = Float32_4x4.rotationX( _t * 0.5f + 0.4f )
        Float32_4x4 m = rx.multiply( ry )

        Int32 nv = _vx.length
        Int32 nt = _tris.length / 3

        Array<Float32> px = Array<Float32>( nv )
        Array<Float32> py = Array<Float32>( nv )
        Array<Float32> pd = Array<Float32>( nv )
        Float32 f = 1.7f
        Float32 camZ = 2.6f
        Int32 i = 0
        while i < nv
        {
            Float32 wx = _vx[ i ] * _scale + _ox
            Float32 wy = _vy[ i ] * _scale + _oy
            Float32 wz = _vz[ i ] * _scale + _oz
            Float32_3 p0 = Float32_3( wx, wy, wz )
            Float32_3 p = m.transformPoint( p0 )
            Float32 d = p.z + camZ
            if d < 0.3f
            {
                d = 0.3f
            }
            px[ i ] = p.x * f / d
            py[ i ] = p.y * f / d
            pd[ i ] = d
            i = i + 1
        }

        # 三角形平均深度（选择排序降序：最远先画）
        Array<Float32> tdep = Array<Float32>( nt )
        Array<Int32> order = Array<Int32>( nt )
        Int32 k = 0
        while k < nt
        {
            Int32 i0 = _tris[ k * 3 ]
            Int32 i1 = _tris[ k * 3 + 1 ]
            Int32 i2 = _tris[ k * 3 + 2 ]
            tdep[ k ] = ( pd[ i0 ] + pd[ i1 ] + pd[ i2 ] ) / 3.0f
            order[ k ] = k
            k = k + 1
        }
        Int32 a = 0
        while a < nt
        {
            Int32 best = a
            Int32 b2 = a + 1
            while b2 < nt
            {
                if tdep[ b2 ] > tdep[ best ]
                {
                    best = b2
                }
                b2 = b2 + 1
            }
            if best != a
            {
                Float32 td = tdep[ a ]
                tdep[ a ] = tdep[ best ]
                tdep[ best ] = td
                Int32 oi = order[ a ]
                order[ a ] = order[ best ]
                order[ best ] = oi
            }
            a = a + 1
        }

        # 按绘制序展开：每顶点 16B (x, y, u, v)，UV 来自导出数据
        Int32 vout = 0
        Int32 c = 0
        while c < nt
        {
            Int32 tri = order[ c ]
            Int32 j = 0
            while j < 3
            {
                Int32 vi2 = _tris[ tri * 3 + j ]
                Memory.writeF32( _vbuf, vout * 16, px[ vi2 ] )
                Memory.writeF32( _vbuf, vout * 16 + 4, py[ vi2 ] )
                Memory.writeF32( _vbuf, vout * 16 + 8, _vu[ vi2 ] )
                Memory.writeF32( _vbuf, vout * 16 + 12, _vv[ vi2 ] )
                vout = vout + 1
                j = j + 1
            }
            c = c + 1
        }
        bool upOk = _pipe.uploadMesh( 0, _vbuf, vout )
        ret upOk
    }

    static void onTick()
    {
        if _pipe == null || _cube == null || _vx == null || _label == null
        {
            ret
        }
        _t = _t + 0.016f
        if updateVerts()
        {
            _pipe.renderFrame( _t, _pixels )
            if _label.setPixmapRgba( _pixels, W, H )
            {
                _okFrames = _okFrames + 1
            }
        }
    }

    static void onQuit()
    {
        Console.println( "[qt] quit timer fired (15s)" )
        if _app != null
        {
            _app.quit()
        }
    }

    static void teardown()
    {
        if _cube != null
        {
            _cube.destroy()
        }
        if _pipe != null
        {
            _pipe.destroy()
        }
        if _pixels != 0
        {
            Memory.free( _pixels )
        }
        if _vbuf != 0
        {
            Memory.free( _vbuf )
        }
        SLang.Render.uninitialize()
    }

    public static void main()
    {
        Console.println( "========== SimSceneTest (Unity CubeDemo export -> SLangRender) ==========" )
        Console.println( "export dir: " + EXPORT_DIR )
        if loadData() == false
        {
            ret
        }
        if setup() == false
        {
            ret
        }
        _app = SLang.QT.newApp()
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        host.setTitle( "SimSceneTest: Unity CubeDemo -> SLangRender" )
        _label = SLang.QT.newLabel( host.handle, "" )
        _label.setGeometry( 10, 10, W, H )
        host.show()
        SLang.QTimer quitT = SLang.QT.newTimer( 15000, true, SimSceneTest.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 16, false, SimSceneTest.onTick )
        _app.exec()
        Console.println( "[done] okFrames=" + _okFrames.toString() + " (expect ~900 @15s)" )
        teardown()
    }
}
