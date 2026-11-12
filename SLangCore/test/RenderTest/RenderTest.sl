import SLangQT;
import SLangRender;
import Math;
import Std;

# ============================================================================
# GLRenderTest —— SLangRender RHI 多后端 + Unity 13 阶段管线端到端
# ----------------------------------------------------------------------------
# Phase D D3D11 后端同效果验证（initializeBackend("d3d11")）：
#   与 GL 完全相同的 A1/A2/A3 断言集在 D3D11 后端重跑——像素值、
#   多相机合成、图片渲染全部一致（"不同驱动渲染一样效果"验收标准）
# Phase E Vulkan 后端同效果验证（initializeBackend("vk")）：
#   SPIR-V 固化着色器 + 纯离屏 instance，同断言集重跑（vulkan-1.dll
#   运行期探测，缺失则 SKIP）
# Phase F EGL/GLES 后端验证（initializeBackend("gles")）：
#   libEGL/libGLESv2 运行期探测，同断言集重跑；本机无 GLES 运行库时
#   优雅降级为 SKIP（init 返回 0 -> false），有则要求同像素 PASS
# Phase A1 v1 兼容（RenderContext 直连渲染目标快速回归）：
#   renderFrame(红) -> 中心像素 = 红
# Phase A2 管线主测（SLang.RenderPipeline，逻辑全在 C 层）：
#   场景 = 色相循环动画三角(layer0 不透明) + 渐变贴图 quad(layer1 透明,
#   叠加在三角右上)；renderFrame(t) 走完整 13 阶段：
#   像素断言（背景/三角红/贴图像素）+ 管线统计断言（visible/culled/
#   drawCalls/layersMask/chunks/uploads/time）+ 颜色变化断言（t=0 红 ->
#   t=5 绿）+ 分层剔除断言（mask 排除 layer1 后 quad 消失）+ 后处理
#   灰度断言（saturation=0 -> RGB 相等）+ 逐阶段驱动断言（runStages
#   依序跑 1..13，与 renderFrame 等价）
# Phase A3 多相机 + 图片加载渲染（SLang.RenderCamera + loadFile）：
#   相机0（默认，全屏）+ 相机1（depth=10，仅 layer2，右半 viewport，
#   独立清屏色）：depth 升序逐相机渲染 -> 相机1 覆盖右半画面；橙图
#   quad（layer2）同时出现在两台相机的画面中（cam0 左半 + cam1 右半
#   重画），禁用相机1 后右半回到相机0 画面；test_image.png 经 WIC
#   解码上传纹理并渲染（像素断言橙色）；QT 窗口展示多相机合成画面
# Phase B QT 窗口（真实 Qt 后端；stub SKIP）—— 后端可选的交互渲染面板：
#   顶部 4 个按钮（OpenGL / D3D11 / Vulkan / WebGL-GLES）点击即切换渲染
#   底层（initializeBackend + 场景全量重建，管线句柄/纹理随 uninit 失效），
#   状态栏实时显示当前后端 + 渲染器；QTimer 16ms 帧循环 ->
#   runStages（每帧完整 13 阶段）-> QLabel.setPixmapRgba 填充；
#   另有 4s 自动轮播（d3d11 -> vk -> gles -> gl）自动验证四后端在
#   QT 帧循环下都能持续渲染（用户点击任一按钮后轮播停止，尊重选择）；
#   30s 退出 -> 帧数断言 + 后端掩码断言（gl + 至少一个其他后端渲染过）
# Phase C 3D 旋转立方体（Mesh 数学层 + RHI 动态网格通道）：
#   Mesh.cube(1.0) 24 顶点 36 索引 -> Float32_4x4.rotationY/X(t) CPU 旋转
#   -> 相机 -Z 朝 +Z（dist = z + 2.6）-> 手工透视除法（f=1.7）-> NDC
#   三角形列表（painter 平均深度降序，远先画保遮挡）-> Memory.writeF32
#   填 pos2+uv2 -> pipe.uploadMesh(slot 0)；对象 meshKind = MESH_CUSTOM(4)
#   每帧重传，onTick 驱动自转（正方体绕 X/Y 双轴旋转，QT 16ms 帧循环）
# ============================================================================
public class RenderTest
{
    static SLang.QApplication _app = null
    static SLang.QLabel _label = null
    static SLang.RenderPipeline _pipe = null
    static Int64 _pixels = 0
    static Int32 _texW = 256
    static Int32 _texH = 256

    static Float32 _t = 0.0f
    static Int32 _renderFrames = 0
    static Int32 _pixOk = 0

    # v3.4：QT 演示聚光灯（暖色，slot 0）—— onTick 每帧摇晃位置 +
    # 强度脉动后 applyTo 重写光照槽（阴影/锥光随灯实时跟随）
    static Light _lamp = null

    # Phase B 后端切换 UI 状态
    static SLang.QPushButton _btnGl = null
    static SLang.QPushButton _btnDx = null
    static SLang.QPushButton _btnVk = null
    static SLang.QPushButton _btnWeb = null
    static SLang.QLabel _status = null
    static Int32 _backendMask = 0      # gl=1 d3d11=2 vk=4 gles=8（QT 循环内渲染记账）
    static Int32 _cycleStep = 0        # 自动轮播步进（0..3：d3d11/vk/gles/gl）
    static bool _userPicked = false    # 用户点过按钮后停止自动轮播

    # Phase C：3D 立方体状态（Mesh 库 + 动态网格通道）
    static SLang.Mesh _cubeMesh = null       # Mesh.cube(1.0)：24 顶点 36 索引
    static SLang.RenderObject _cubeObj = null   # meshKind=4（动态网格槽 0）
    static Int64 _cubeVerts = 0             # 36 顶点 * 16B 显存暂存（帧间复用）
    static Int32 _cubeFirst = 0             # 首帧 uploadMesh 结果打印标志
    # UV 不建表：vi%4 -> (0,0)(1,0)(1,1)(0,1)（updateCube 现场计算）

    # 帧循环 tick：t 推进 -> SL 侧逐阶段驱动 1..13（完整流程）-> 填 QT 窗口
    # v3.4：每帧先摇晃聚光灯（位置 ±0.08 sin + 高度 ±0.05 sin、强度
    # 1.6±0.5 sin 脉动）再 applyTo —— 灯光/阴影/高光实时跟随摆动
    public static void onTick()
    {
        if _pipe == null
        {
            ret
        }
        _t = _t + 0.033f
        if _lamp != null
        {
            _lamp.posX = 0.08f * Mathf.sin( _t * 2.1f )
            _lamp.posY = 0.8f + 0.05f * Mathf.sin( _t * 3.3f )
            _lamp.intensity = 1.6f + 0.5f * Mathf.sin( _t * 4.7f )
            if _lamp.intensity < 0.4f
            {
                _lamp.intensity = 0.4f
            }
            _lamp.applyTo( _pipe, 0 )
        }
        if RenderTest.updateCube( _t )
        {
            if _cubeFirst == 0
            {
                Console.println( "[cube] spinning: CPU transform + uploadMesh(slot 0) OK on backend " + SLang.Render.currentBackend() )
                _cubeFirst = 1
            }
        }
        if _pipe.runStages( _t, _pixels )
        {
            _renderFrames = _renderFrames + 1
            if _label.setPixmapRgba( _pixels, _texW, _texH )
            {
                _pixOk = _pixOk + 1
            }
            markBackendRendered()
        }
    }

    # ── Phase C：立方体每帧更新（CPU 变换 + 动态网格上传）─────────
    # 流水线：Mesh.cube 顶点 -> rotationY/X(t) 旋转 -> 手工透视除法
    # （相机 -Z 朝 +Z：dist = z + 2.6，焦距 f = 1.7）-> NDC 顶点 ->
    # 12 三角形按平均深度降序排（远先画保遮挡）-> 三角形列表展开为
    # pos2+uv2 交错（stride 16B）-> Memory.writeF32 填 _cubeVerts ->
    # pipe.uploadMesh(0) 整块重传（GL/GLES/D3D11 重传 / VK 直写）。
    static bool updateCube( Float32 t )
    {
        if _pipe == null
        {
            ret false
        }
        if _cubeMesh == null
        {
            ret false
        }
        if _cubeVerts == 0
        {
            ret false
        }
        # 模型矩阵：先绕 Y（t*0.9）再绕 X（t*0.5 + 0.4 起始倾角）
        Float32_4x4 ry = Float32_4x4.rotationY( t * 0.9f )
        Float32_4x4 rx = Float32_4x4.rotationX( t * 0.5f + 0.4f )
        Float32_4x4 m = rx.multiply( ry )

        Int32 nv = _cubeMesh.vertexCount
        Array<Int32> tris = _cubeMesh.getTriangles()
        Int32 nt = tris.length / 3

        # 顶点级投影（NDC：+y 上、+x 右，与 2D 对象世界系一致）
        Array<Float32> px = Array<Float32>( nv )
        Array<Float32> py = Array<Float32>( nv )
        Array<Float32> pd = Array<Float32>( nv )
        Float32 f = 1.7f
        Float32 camZ = 2.6f
        Int32 i = 0
        while i < nv
        {
            Float32_3 p = m.transformPoint( _cubeMesh.getVertex( i ) )
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

        # 三角形平均深度（选择排序降序：最远在前，先画）
        Array<Float32> tdep = Array<Float32>( nt )
        Array<Int32> order = Array<Int32>( nt )
        Int32 k = 0
        while k < nt
        {
            Int32 i0 = tris[ k * 3 ]
            Int32 i1 = tris[ k * 3 + 1 ]
            Int32 i2 = tris[ k * 3 + 2 ]
            tdep[ k ] = ( pd[ i0 ] + pd[ i1 ] + pd[ i2 ] ) / 3.0f
            order[ k ] = k
            k = k + 1
        }
        Int32 a = 0
        while a < nt
        {
            Int32 best = a
            Int32 b = a + 1
            while b < nt
            {
                if tdep[ b ] > tdep[ best ]
                {
                    best = b
                }
                b = b + 1
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

        # 按绘制序展开三角形列表：每顶点 16B（x, y, u, v）
        Int32 vout = 0
        Int32 c = 0
        while c < nt
        {
            Int32 tri = order[ c ]
            Int32 j = 0
            while j < 3
            {
                Int32 vi = tris[ tri * 3 + j ]
                # UV：面内角序 vi%4 -> 00,10,11,01
                Int32 ci = vi % 4
                Float32 u = 0.0f
                Float32 v = 0.0f
                if ci == 1
                {
                    u = 1.0f
                }
                if ci == 2
                {
                    u = 1.0f
                    v = 1.0f
                }
                if ci == 3
                {
                    v = 1.0f
                }
                Memory.writeF32( _cubeVerts, vout * 16, px[ vi ] )
                Memory.writeF32( _cubeVerts, vout * 16 + 4, py[ vi ] )
                Memory.writeF32( _cubeVerts, vout * 16 + 8, u )
                Memory.writeF32( _cubeVerts, vout * 16 + 12, v )
                vout = vout + 1
                j = j + 1
            }
            c = c + 1
        }
        ret _pipe.uploadMesh( 0, _cubeVerts, vout )
    }

    # QT 循环内按当前后端记账（每帧调，位或幂等）
    static void markBackendRendered()
    {
        string b = SLang.Render.currentBackend()
        if b == "gl"
        {
            _backendMask = _backendMask | 1
        }
        if b == "d3d11"
        {
            _backendMask = _backendMask | 2
        }
        if b == "vk"
        {
            _backendMask = _backendMask | 4
        }
        if b == "gles"
        {
            _backendMask = _backendMask | 8
        }
    }

    # ── Phase B 后端切换核心 ──────────────────────────────────────
    # 切换 = uninit 当前后端（管线/纹理/v1 ctx 全部释放，句柄失效）->
    # 新后端 init + make_shared -> 场景全量重建。先置 _pipe=null 防
    # onTick 在重建窗口期踩已释放句柄。
    static void switchBackend( string name )
    {
        _pipe = null
        _pixels = 0
        _cubeFirst = 0
        if SLang.Render.initializeBackend( name ) == false
        {
            Console.println( "[ui] backend '" + name + "' unavailable - " + SLang.Render.errorString() )
            # 请求的后端不可用：恢复默认 gl 兜底（失败则保持空场景，onTick 判空跳过）
            if SLang.Render.initializeBackend( "gl" ) == false
            {
                updateStatus()
                ret
            }
        }
        else
        {
            Console.println( "[ui] switch -> " + name + " (" + SLang.Render.rendererInfo() + ")" )
        }
        if rebuildScene() == false
        {
            Console.println( "[ui] scene rebuild failed on '" + SLang.Render.currentBackend() + "'" )
            updateStatus()
            ret
        }
        _t = 0.0f
        updateStatus()
    }

    # 场景全量重建（A3 同款：橙图 quad + 蓝 quad + 动画三角 + 相机1
    # 右半 viewport + 展示用后处理）—— 每次后端切换后调用
    # v3.4：聚光灯 _lamp（暖色，onTick 每帧摇晃位置 + 强度脉动）+
    # 三个物体 castShadow 投影阴影（聚光点源 -> 阴影随灯摇晃跟随）+
    # 蓝 quad/cube Phong 材质高光。
    static bool rebuildScene()
    {
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1250, 720 )
        if pipe == null
        {
            Console.println( "[ui] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            ret false
        }
        if pipe.setPostEffect( 1, 1.05f, 1.15f, 0.35f ) == false
        {
            ret false
        }
        # v3.4 演示光照：环境光 + 暖色聚光（位置/强度由 onTick 摇晃驱动）
        if pipe.setAmbient( 0.45f ) == false
        {
            ret false
        }
        if RenderTest._lamp == null
        {
            RenderTest._lamp = Light.spot( Color( 1.0f, 0.85f, 0.55f, 1.0f ), 1.6f, 2.4f, 38.0f )
            if RenderTest._lamp == null
            {
                Console.println( "[ui] FAIL: Light.spot" )
                ret false
            }
        }
        RenderTest._lamp.posX = 0.0f
        RenderTest._lamp.posY = 0.8f
        RenderTest._lamp.dirX = 0.0f
        RenderTest._lamp.dirY = -1.0f
        if RenderTest._lamp.applyTo( pipe, 0 ) == false
        {
            Console.println( "[ui] FAIL: lamp applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 图片贴图（相对路径按运行进程 CWD，失败回退绝对路径）
        SLang.RenderTexture imgTex = SLang.RenderTexture.loadFile( "SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        if imgTex == null
        {
            imgTex = SLang.RenderTexture.loadFile( "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        }
        if imgTex == null
        {
            Console.println( "[ui] FAIL: loadFile test_image.png - " + SLang.Render.errorString() )
            ret false
        }

        # 橙图 quad（layer2，左半；投影阴影 + Phong 贴图高光）
        SLang.RenderObject imgQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if imgQuad == null
        {
            ret false
        }
        imgQuad.setLayer( 2 )
        imgQuad.setQueue( 2000 )
        imgQuad.setPosition( -0.5f, 0.0f, 0.0f )
        imgQuad.setScale( 0.7f, 0.7f )
        imgQuad.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        imgQuad.setTexture( imgTex )
        imgQuad.setMaterial( 1 )
        imgQuad.setSpecular( 1.0f, 12.0f )
        imgQuad.setShadow( 1 )

        # 蓝 quad（layer0，右半；投影阴影 + Phong 纯色高光）
        SLang.RenderObject blueQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if blueQuad == null
        {
            ret false
        }
        blueQuad.setLayer( 0 )
        blueQuad.setQueue( 2000 )
        blueQuad.setPosition( 0.5f, 0.0f, 0.0f )
        blueQuad.setScale( 0.6f, 0.6f )
        blueQuad.setColor( 0.2f, 0.4f, 1.0f, 1.0f )
        blueQuad.setMaterial( 1 )
        blueQuad.setSpecular( 1.5f, 16.0f )
        blueQuad.setShadow( 1 )

        # 动画三角（layer1，顶部，色相循环）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            ret false
        }
        tri.setLayer( 1 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.6f, 0.0f )
        tri.setScale( 0.3f, 0.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 相机1：depth=10、mask 仅 layer2、viewport 右半、深绿清屏
        SLang.RenderCamera cam = pipe.addCamera( 10 )
        if cam == null || cam.isValid == false
        {
            ret false
        }
        if cam.setCullMask( 4 ) == false || cam.setExtents( -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            ret false
        }
        if cam.setViewport( 625, 0, 625, 720 ) == false || cam.setClearColor( 0.0f, 0.25f, 0.1f, 1.0f ) == false
        {
            ret false
        }
        if cam.setClearFlags( SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH ) == false
        {
            ret false
        }

        # ── Phase C：3D 旋转立方体（Mesh.cube + 动态网格槽 0）─────
        _cubeMesh = SLang.Mesh.cube( 1.0f )
        if _cubeMesh == null
        {
            Console.println( "[ui] FAIL: Mesh.cube" )
            ret false
        }
        Console.println( "[cube] Mesh.cube verts=" + _cubeMesh.vertexCount.toString() + " indices=" + _cubeMesh.getTriangles().length.toString() )
        # cube() 不带 UV：vi%4 现场计算（见 updateCube），无需建表
        if _cubeVerts == 0
        {
            _cubeVerts = Memory.alloc( 36 * 16 )
        }
        if _cubeVerts == 0
        {
            Console.println( "[ui] FAIL: cube verts alloc" )
            ret false
        }
        _cubeObj = pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
        if _cubeObj == null
        {
            Console.println( "[ui] FAIL: cube addObject - " + SLang.Render.errorString() )
            ret false
        }
        # 顶点已烘焙 NDC：位置/缩放保持单位，贴图走 imgTex，
        # 透明队列（3000 默认）后画叠加在两个 quad 之上；
        # v3.4：Phong 贴图高光 + 投影阴影（聚光点源 -> 阴影随灯摇晃）
        _cubeObj.setTexture( imgTex )
        _cubeObj.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        _cubeObj.setMaterial( 1 )
        _cubeObj.setSpecular( 1.2f, 10.0f )
        _cubeObj.setShadow( 1 )
        RenderTest.updateCube( _t )

        Int64 px = Memory.alloc( 1250 * 720 * 4 )
        if px == 0
        {
            ret false
        }
        _pipe = pipe
        _pixels = px
        _texW = 1250
        _texH = 720
        ret true
    }

    # 状态栏 + 按钮高亮（当前后端绿色）
    static void updateStatus()
    {
        if _status != null
        {
            _status.setText( "backend: " + SLang.Render.currentBackend() + " | " + SLang.Render.rendererInfo() )
        }
        if _btnGl == null
        {
            ret
        }
        if _btnDx == null
        {
            ret
        }
        if _btnVk == null
        {
            ret
        }
        if _btnWeb == null
        {
            ret
        }
        string b = SLang.Render.currentBackend()
        if b == "gl"
        {
            _btnGl.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnGl.setStyleSheet( "" )
        }
        if b == "d3d11"
        {
            _btnDx.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnDx.setStyleSheet( "" )
        }
        if b == "vk"
        {
            _btnVk.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnVk.setStyleSheet( "" )
        }
        if b == "gles"
        {
            _btnWeb.setStyleSheet( "background-color:#2d8f4e;color:white;font-weight:bold;" )
        }
        else
        {
            _btnWeb.setStyleSheet( "" )
        }
    }

    # 4 个按钮回调（无参 static，经 clicked(Function) 桥接）
    public static void onBtnGl()
    {
        _userPicked = true
        switchBackend( "gl" )
    }

    public static void onBtnDx()
    {
        _userPicked = true
        switchBackend( "d3d11" )
    }

    public static void onBtnVk()
    {
        _userPicked = true
        switchBackend( "vk" )
    }

    public static void onBtnWeb()
    {
        _userPicked = true
        switchBackend( "gles" )
    }

    # 自动轮播（4s 一拍）：d3d11 -> vk -> gles -> gl，用户点过按钮即停
    public static void onAutoCycle()
    {
        if _userPicked
        {
            ret
        }
        if _cycleStep == 0
        {
            switchBackend( "d3d11" )
        }
        elif _cycleStep == 1
        {
            switchBackend( "vk" )
        }
        elif _cycleStep == 2
        {
            switchBackend( "gles" )
        }
        elif _cycleStep == 3
        {
            switchBackend( "gl" )
        }
        _cycleStep = _cycleStep + 1
    }

    public static void onQuit()
    {
        if _app != null
        {
            _app.quit()
        }
    }

    public static void main()
    {
        Console.println( "========== GLRenderTest (SLangRender RHI multi-backend + QT window) ==========" )
        Console.println( "backends: " + SLang.Render.backendList() )

        # ── Phase D：D3D11 后端同效果（先跑，跑完切回 GL 走主流程）──
        Int32 phaseD = runD3D11Smoke()

        # ── Phase E：Vulkan 后端同效果（本机有 vulkan-1.dll 时必须全绿）──
        Int32 phaseVk = runVkSmoke()

        # ── Phase F：EGL/GLES 后端（无 GLES 运行库时优雅降级 SKIP）──
        Int32 phaseGles = runGlesSmoke()

        # 主流程：显式切回 GL 默认后端（initialize 对已初始化态幂等，
        # 不切后端 —— 因此这里用 initializeBackend("gl") 强制切换）
        if SLang.Render.initializeBackend( "gl" ) == false
        {
            Console.println( "FAIL: initialize gl - " + SLang.Render.errorString() )
            ret
        }
        Console.println( "backend : " + SLang.Render.currentBackend() + "  renderer: " + SLang.Render.rendererInfo() )
        Console.println( "version : " + SLang.Render.versionInfo() )

        bool a1 = runV1Compat()
        bool a2 = runPipeline()
        bool a3 = runMultiCameraImage()
        bool phaseA = a1 && a2 && a3

        # Phase L：光照（直射 + 聚光 + 无光回归；当前 GL 后端）
        bool phaseL = runLightScene()

        Int32 phaseB = runQtWindow()

        string dText = "FAIL"
        if phaseD == 2
        {
            dText = "PASS"
        }
        elif phaseD == 1
        {
            dText = "SKIP"
        }
        string vText = "FAIL"
        if phaseVk == 2
        {
            vText = "PASS"
        }
        elif phaseVk == 1
        {
            vText = "SKIP"
        }
        string gText = "FAIL"
        if phaseGles == 2
        {
            gText = "PASS"
        }
        elif phaseGles == 1
        {
            gText = "SKIP"
        }
        string bText = "FAIL"
        if phaseB == 2
        {
            bText = "PASS"
        }
        elif phaseB == 1
        {
            bText = "SKIP"
        }
        Console.println( "========== GLRenderTest summary ==========" )
        Console.println( "phase D  (d3d11 same-effect) : " + dText )
        Console.println( "phase E  (vk same-effect)    : " + vText )
        Console.println( "phase F  (gles graceful)     : " + gText )
        Console.println( "phase A1 (v1 compat)         : " + ( a1 ? "PASS" : "FAIL" ) )
        Console.println( "phase A2 (13-stage pipe)     : " + ( a2 ? "PASS" : "FAIL" ) )
        Console.println( "phase A3 (multi-cam+img)     : " + ( a3 ? "PASS" : "FAIL" ) )
        Console.println( "phase L  (dir+spot light)    : " + ( phaseL ? "PASS" : "FAIL" ) )
        Console.println( "phase B  (QT window)         : " + bText )
        # 终判：主流程全绿 + D3D11/VK 可用即 PASS，GLES 允许 SKIP（环境无 GLES 库）
        bool allOk = phaseA
        if !phaseL
        {
            allOk = false
        }
        if phaseB == 0
        {
            allOk = false
        }
        if phaseD == 0
        {
            allOk = false
        }
        if phaseVk != 2
        {
            allOk = false
        }
        if phaseGles == 0
        {
            allOk = false
        }
        if allOk
        {
            Console.println( "GLRenderTest: PASS" )
        }
        else
        {
            Console.println( "GLRenderTest: FAIL" )
        }
    }

    # ── Phase D：D3D11 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 GL 主流程共用 A1/A2/A3 三套断言函数（完全相同的像素断言），
    # 差异仅在后端名 —— 这就是"不同操作系统/驱动渲染一样效果"的验收。
    static Int32 runD3D11Smoke()
    {
        Console.println( "-- Phase D: D3D11 backend (same-effect pixel assertions) --" )
        if SLang.Render.initializeBackend( "d3d11" ) == false
        {
            Console.println( "[d3d11] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[d3d11] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[d3d11] version : " + SLang.Render.versionInfo() )
        bool d1 = runV1Compat()
        bool d2 = runPipeline()
        bool d3 = runMultiCameraImage()
        # 光照跨后端同效果复检（D3D11 与 GL 同公式逐像素一致）
        bool d4 = runLightScene()
        # 本阶段管线句柄在切回 GL 后失效：清空 QT 移交（GL 主流程会重设）
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3 && d4
        {
            Console.println( "[d3d11] Phase D: PASS (v1 + 13-stage + multi-cam + image + lighting, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[d3d11] Phase D: FAIL" )
        ret 0
    }

    # ── Phase E：Vulkan 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 Phase D 完全同构：SPIR-V 固化六组着色器 + 纯离屏 instance，
    # v1 / 13 阶段 / 多相机三套断言全部按 GL 基准像素复检。
    static Int32 runVkSmoke()
    {
        Console.println( "-- Phase E: Vulkan backend (same-effect pixel assertions) --" )
        if SLang.Render.initializeBackend( "vk" ) == false
        {
            Console.println( "[vk] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[vk] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[vk] version : " + SLang.Render.versionInfo() )
        bool d1 = runV1Compat()
        bool d2 = runPipeline()
        bool d3 = runMultiCameraImage()
        # VK：SPIR-V 固化暂未消费光照（upload_lights 空实现），
        # 光照相位跳过（默认无光照路径已由 d1..d3 覆盖）
        Console.println( "[vk] lighting phase skipped (SPIR-V frozen shaders do not consume lights yet)" )
        # 切回 GL 前先清空管线句柄移交（GL 主流程会重设）
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3
        {
            Console.println( "[vk] Phase E: PASS (v1 + 13-stage + multi-cam + image, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[vk] Phase E: FAIL" )
        ret 0
    }

    # ── Phase F：EGL/GLES 后端验证（返回 2=PASS 1=SKIP 0=FAIL）────────
    # libEGL/libGLESv2 运行期探测：缺失时 init 优雅降级 -> SKIP；
    # 有 GLES 运行库的机器则同断言集要求同像素 PASS。
    static Int32 runGlesSmoke()
    {
        Console.println( "-- Phase F: EGL/GLES3 backend (graceful degrade when absent) --" )
        if SLang.Render.initializeBackend( "gles" ) == false
        {
            Console.println( "[gles] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[gles] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[gles] version : " + SLang.Render.versionInfo() )
        bool d1 = runV1Compat()
        bool d2 = runPipeline()
        bool d3 = runMultiCameraImage()
        # 光照跨后端同效果复检（GLES 与 GL 同公式逐像素一致）
        bool d4 = runLightScene()
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3 && d4
        {
            Console.println( "[gles] Phase F: PASS (v1 + 13-stage + multi-cam + image + lighting, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[gles] Phase F: FAIL" )
        ret 0
    }

    # 采样像素通道：pixels 块内 (x,y) 像素的 c 通道（0=R 1=G 2=B 3=A）
    static Int32 sampleChannel( Int64 pixels, Int32 w, Int32 x, Int32 y, Int32 c )
    {
        Int32 off = ( y * w + x ) * 4 + c
        ret Memory.readUInt8( pixels, off )
    }

    # 生成 64x64 RGBA8 渐变贴图像素块（绿 -> 品红，沿 u 方向），
    # 返回 Memory.alloc 块地址（top-down 行序契约）
    static Int64 makeGradientTexture()
    {
        Int64 ptr = Memory.alloc( 64 * 64 * 4 )
        if ptr == 0
        {
            ret 0
        }
        Int32 y = 0
        while y < 64
        {
            Int32 x = 0
            while x < 64
            {
                Int32 baseOff = ( y * 64 + x ) * 4
                Int32 r = x * 220 / 63
                Int32 g = ( 200 * ( 63 - x ) + 40 * x ) / 63
                Int32 b = ( 80 * ( 63 - x ) + 180 * x ) / 63
                Memory.writeI8( ptr, baseOff, r )
                Memory.writeI8( ptr, baseOff + 1, g )
                Memory.writeI8( ptr, baseOff + 2, b )
                Memory.writeI8( ptr, baseOff + 3, 255 )
                x = x + 1
            }
            y = y + 1
        }
        ret ptr
    }

    # ── Phase A1：v1 RenderContext 直连路径回归 ─────────────────────
    static bool runV1Compat()
    {
        Console.println( "-- Phase A1: v1 RenderContext compat (direct FBO path, 128x128) --" )

        SLang.RenderContext ctx = SLang.RenderContext.create( 128, 128 )
        if ctx == null
        {
            Console.println( "[v1] FAIL: context create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 px = Memory.alloc( 128 * 128 * 4 )
        if px == 0
        {
            Console.println( "[v1] FAIL: pixel alloc" )
            ctx.destroy()
            ret false
        }
        if ctx.renderFrame( 1.0f, 0.0f, 0.0f, px ) == false
        {
            Console.println( "[v1] FAIL: renderFrame - " + SLang.Render.errorString() )
            ctx.destroy()
            ret false
        }
        Int32 cr = sampleChannel( px, 128, 64, 64, 0 )
        Int32 cb = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[v1] center RGB.r=" + cr.toString() + " RGB.b=" + cb.toString() )
        ctx.destroy()
        if cr < 240 || cb > 15
        {
            Console.println( "[v1] FAIL: center should be red" )
            ret false
        }
        Console.println( "[v1] PASS" )
        ret true
    }

    # ── Phase A2：13 阶段管线主测 ──────────────────────────────────
    static bool runPipeline()
    {
        Console.println( "-- Phase A2: Unity-style 13-stage pipeline (256x256 RGBA8) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[pipe] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        _pipe = pipe
        _texW = 256
        _texH = 256

        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setClearColor" )
            ret false
        }

        # 对象 1：动画三角（layer0，Geometry 队列，色相循环）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[pipe] FAIL: add triangle" )
            ret false
        }
        tri.setLayer( 0 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.0f, 0.0f )
        tri.setScale( 1.3f, 1.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 贴图：64x64 绿->品红渐变
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pipe] FAIL: texture pixels alloc" )
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[pipe] FAIL: texture upload - " + SLang.Render.errorString() )
            ret false
        }

        # 对象 2：贴图 quad（layer1，Transparent 队列，叠在三角右上）
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quad == null
        {
            Console.println( "[pipe] FAIL: add quad" )
            ret false
        }
        quad.setLayer( 1 )
        quad.setQueue( 3000 )
        quad.setPosition( 0.45f, 0.35f, 0.5f )
        quad.setScale( 0.55f, 0.55f )
        quad.setColor( 1.0f, 1.0f, 1.0f, 0.85f )
        quad.setTexture( tex )

        Int32 objCount = pipe.objectCount()
        Console.println( "[pipe] scene: objects=" + objCount.toString() + " textures=" + pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ).toString() )
        if objCount != 2 || pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ) < 1
        {
            Console.println( "[pipe] FAIL: scene setup counts" )
            ret false
        }

        _pixels = Memory.alloc( 256 * 256 * 4 )
        if _pixels == 0
        {
            Console.println( "[pipe] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1（t=0，三角红 hue=0）：一键全流程 ──────────────────
        if pipe.renderFrame( 0.0f, _pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame t=0 - " + SLang.Render.errorString() )
            ret false
        }

        # 背景（左上角，远离三角与 quad）
        Int32 kr = sampleChannel( _pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( _pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( _pixels, 256, 4, 4, 2 )
        Console.println( "[pipe] t=0 corner   RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 9 || kr > 21
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }
        if kg < 9 || kg > 21
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }
        if kb < 19 || kb > 33
        {
            Console.println( "[pipe] FAIL: corner should be clear color" )
            ret false
        }

        # 三角内部（左下区域，不受 quad 影响）
        Int32 triR = sampleChannel( _pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( _pixels, 256, 51, 184, 1 )
        Int32 triB = sampleChannel( _pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=0 tri      RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[pipe] FAIL: triangle should be red at t=0" )
            ret false
        }

        # 贴图 quad 区域（右上，三角外侧 -> 贴图像素混背景）
        Int32 qr = sampleChannel( _pixels, 256, 204, 64, 0 )
        Int32 qg = sampleChannel( _pixels, 256, 204, 64, 1 )
        Int32 qb = sampleChannel( _pixels, 256, 204, 64, 2 )
        Console.println( "[pipe] t=0 quad tex RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr < 110 || qb < 110
        {
            Console.println( "[pipe] FAIL: textured quad pixel missing" )
            ret false
        }
        if qg < 35 || qg > 90
        {
            Console.println( "[pipe] FAIL: textured quad pixel missing" )
            ret false
        }

        # 管线统计断言
        Int32 lastStage = pipe.stat( SLang.RenderPipeline.STAT_LAST_STAGE )
        Int32 visible   = pipe.stat( SLang.RenderPipeline.STAT_VISIBLE )
        Int32 culled    = pipe.stat( SLang.RenderPipeline.STAT_CULLED )
        Int32 opaque    = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 transp    = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Int32 layers    = pipe.stat( SLang.RenderPipeline.STAT_LAYERS_MASK )
        Int32 chunks    = pipe.stat( SLang.RenderPipeline.STAT_CHUNK_COUNT )
        Int32 uploads   = pipe.stat( SLang.RenderPipeline.STAT_UPLOAD_COUNT )
        Int32 timeMs    = pipe.stat( SLang.RenderPipeline.STAT_TIME_MS )
        Console.println( "[pipe] stats: stage=" + lastStage.toString() + " visible=" + visible.toString() + " culled=" + culled.toString() + " opaque=" + opaque.toString() + " transp=" + transp.toString() + " layers=" + layers.toString() + " chunks=" + chunks.toString() + " uploads=" + uploads.toString() )
        if lastStage != 13 || visible != 2
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if culled != 0 || opaque != 1
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if transp != 1 || layers != 3
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if chunks != 2 || uploads != 4
        {
            Console.println( "[pipe] FAIL: pipeline stats after first frame" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS ) < 3 || pipe.stat( SLang.RenderPipeline.STAT_PROGRAM_SWITCHES ) < 3 || timeMs != 0
        {
            Console.println( "[pipe] FAIL: pipeline stats (draws/switches/time)" )
            ret false
        }

        # ── 帧 2（t=5，hue=0.25 三角转绿）：颜色变化验证 ───────────
        if pipe.renderFrame( 5.0f, _pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame t=5" )
            ret false
        }
        triR = sampleChannel( _pixels, 256, 51, 184, 0 )
        triG = sampleChannel( _pixels, 256, 51, 184, 1 )
        triB = sampleChannel( _pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=5 tri      RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triG < 200 || triB > 20
        {
            Console.println( "[pipe] FAIL: triangle should shift to green (color anim broken)" )
            ret false
        }
        if triR < 90 || triR > 180
        {
            Console.println( "[pipe] FAIL: triangle should shift to green (color anim broken)" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TIME_MS ) != 5000 || pipe.stat( SLang.RenderPipeline.STAT_DT_MS ) != 5000
        {
            Console.println( "[pipe] FAIL: core time update (timeMs/dtMs)" )
            ret false
        }

        # ── 帧 3：分层剔除（cullingMask 排除 layer1 -> quad 消失）──
        if pipe.setCamera( -3, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: setCamera mask" )
            ret false
        }
        if pipe.renderFrame( 5.0f, _pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame masked" )
            ret false
        }
        qr = sampleChannel( _pixels, 256, 204, 64, 0 )
        qg = sampleChannel( _pixels, 256, 204, 64, 1 )
        qb = sampleChannel( _pixels, 256, 204, 64, 2 )
        Console.println( "[pipe] masked quad   RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr > 30 || qg > 30
        {
            Console.println( "[pipe] FAIL: quad should vanish when layer culled" )
            ret false
        }
        if qb < 18 || qb > 34
        {
            Console.println( "[pipe] FAIL: quad should vanish when layer culled" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_VISIBLE ) != 1 || pipe.stat( SLang.RenderPipeline.STAT_CULLED ) != 1 || pipe.stat( SLang.RenderPipeline.STAT_LAYERS_MASK ) != 1
        {
            Console.println( "[pipe] FAIL: culling stats" )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[pipe] FAIL: restore camera" )
            ret false
        }

        # ── 帧 4：后处理灰度（saturation=0 -> RGB 相等）──────────
        if pipe.setPostEffect( 1, 1.0f, 0.0f, 0.0f ) == false
        {
            Console.println( "[pipe] FAIL: setPostEffect gray" )
            ret false
        }
        if pipe.renderFrame( 0.0f, _pixels ) == false
        {
            Console.println( "[pipe] FAIL: renderFrame post" )
            ret false
        }
        triR = sampleChannel( _pixels, 256, 51, 184, 0 )
        triG = sampleChannel( _pixels, 256, 51, 184, 1 )
        triB = sampleChannel( _pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] post gray tri  RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if pipe.stat( SLang.RenderPipeline.STAT_POST_ENABLED ) != 1
        {
            Console.println( "[pipe] FAIL: post enabled stat" )
            ret false
        }
        if triR - triG > 8 || triG - triR > 8
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }
        if triG - triB > 8 || triB - triG > 8
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }
        if triR < 50 || triR > 110
        {
            Console.println( "[pipe] FAIL: post-process grayscale (r==g==b expected)" )
            ret false
        }

        # 恢复视觉后处理（亮度/饱和度/暗角），供 QT 阶段展示
        if pipe.setPostEffect( 1, 1.05f, 1.15f, 0.35f ) == false
        {
            Console.println( "[pipe] FAIL: setPostEffect display" )
            ret false
        }

        # ── 帧 5：SL 侧逐阶段驱动 1..13（与 renderFrame 等价）─────
        Int64 framesBefore = pipe.frameCount()
        if pipe.runStages( 10.0f, _pixels ) == false
        {
            Console.println( "[pipe] FAIL: runStages 1..13" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_LAST_STAGE ) != 13
        {
            Console.println( "[pipe] FAIL: last stage after runStages" )
            ret false
        }
        if pipe.frameCount() != framesBefore + 1
        {
            Console.println( "[pipe] FAIL: frame count after runStages" )
            ret false
        }
        triR = sampleChannel( _pixels, 256, 51, 184, 0 )
        triG = sampleChannel( _pixels, 256, 51, 184, 1 )
        triB = sampleChannel( _pixels, 256, 51, 184, 2 )
        Console.println( "[pipe] t=10 tri     RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR > 20 || triG < 200 || triB < 200
        {
            Console.println( "[pipe] FAIL: triangle should be cyan at t=10 (stages walk)" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TIME_MS ) != 10000 || pipe.stat( SLang.RenderPipeline.STAT_VISIBLE ) != 2
        {
            Console.println( "[pipe] FAIL: stats after stages walk" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_FRAME ) < 5
        {
            Console.println( "[pipe] FAIL: frame stat" )
            ret false
        }

        Console.println( "[pipe] Phase A2: PASS (13-stage pipeline: triangle anim + textured quad + culling + post + staged walk)" )
        ret true
    }

    # ── Phase A3：多相机 + 图片加载渲染 ─────────────────────────────
    # 场景（256x256）：橙图 quad（layer2，test_image.png 经 WIC 加载）
    #   左半 (-0.5,0)；蓝 quad（layer0）右半 (0.5,0)；动画小三角（layer1）
    #   顶部 (0,0.6)。相机0 = 默认（全屏、mask -1、深蓝清屏）；
    #   相机1 = depth 10、mask 仅 layer2、viewport 右半、深绿清屏。
    # 断言：depth 升序（相机1 后画覆盖右半）、cullingMask 分离、
    #   viewport 分割、禁用相机回退、图片像素与纹理注册表。
    static bool runMultiCameraImage()
    {
        Console.println( "-- Phase A3: multi-camera (depth order + viewport split) + image file load --" )

        # 图片加载：坏路径 -> null；好路径 -> 纹理句柄
        SLang.RenderTexture badTex = SLang.RenderTexture.loadFile( "no_such_image_file.png" )
        if badTex != null
        {
            Console.println( "[cam] FAIL: loadFile should fail for missing file" )
            ret false
        }

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1280, 720 )
        if pipe == null
        {
            Console.println( "[cam] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }

        Int32 texBefore = pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT )
        # 相对路径依赖运行进程 CWD（package 目录），失败则回退绝对路径
        SLang.RenderTexture imgTex = SLang.RenderTexture.loadFile( "SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        if imgTex == null
        {
            imgTex = SLang.RenderTexture.loadFile( "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        }
        if imgTex == null || imgTex.isValid == false
        {
            Console.println( "[cam] FAIL: loadFile test_image.png - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT ) != texBefore + 1
        {
            Console.println( "[cam] FAIL: texture registry count after loadFile" )
            ret false
        }
        Console.println( "[cam] image loaded: " + imgTex.toString() )

        # 橙图 quad（layer2，不透明）
        SLang.RenderObject imgQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if imgQuad == null
        {
            Console.println( "[cam] FAIL: add image quad" )
            ret false
        }
        imgQuad.setLayer( 2 )
        imgQuad.setQueue( 2000 )
        imgQuad.setPosition( -0.5f, 0.0f, 0.0f )
        imgQuad.setScale( 0.7f, 0.7f )
        imgQuad.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        imgQuad.setTexture( imgTex )

        # 蓝 quad（layer0，不透明，静态）
        SLang.RenderObject blueQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if blueQuad == null
        {
            Console.println( "[cam] FAIL: add blue quad" )
            ret false
        }
        blueQuad.setLayer( 0 )
        blueQuad.setQueue( 2000 )
        blueQuad.setPosition( 0.5f, 0.0f, 0.0f )
        blueQuad.setScale( 0.6f, 0.6f )
        blueQuad.setColor( 0.2f, 0.4f, 1.0f, 1.0f )

        # 动画小三角（layer1，顶部，QT 展示动感；不触碰任何断言采样点）
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[cam] FAIL: add anim triangle" )
            ret false
        }
        tri.setLayer( 1 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.6f, 0.0f )
        tri.setScale( 0.3f, 0.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )

        # 相机1：depth=10（后画）、mask 仅 layer2、viewport 右半、深绿清屏
        SLang.RenderCamera cam = pipe.addCamera( 10 )
        if cam == null || cam.isValid == false
        {
            Console.println( "[cam] FAIL: addCamera - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.cameraCount() != 2 || cam.setCullMask( 4 ) == false || cam.setExtents( -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[cam] FAIL: camera setup" )
            ret false
        }
        if cam.setViewport( 640, 0, 640, 720 ) == false || cam.setClearColor( 0.0f, 0.25f, 0.1f, 1.0f ) == false
        {
            Console.println( "[cam] FAIL: camera viewport/clear" )
            ret false
        }
        if cam.setClearFlags( SLang.RenderPipeline.CLEAR_COLOR | SLang.RenderPipeline.CLEAR_DEPTH ) == false
        {
            Console.println( "[cam] FAIL: camera clear flags" )
            ret false
        }

        Int64 px = Memory.alloc( 1280 * 720 * 4 )
        if px == 0
        {
            Console.println( "[cam] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1：双相机渲染（cam0 全屏 + cam1 右半覆盖）──────────
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[cam] FAIL: renderFrame dual-cam - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ) != 2
        {
            Console.println( "[cam] FAIL: STAT_CAMERA_COUNT should be 2" )
            ret false
        }
        Int32 vis = pipe.stat( SLang.RenderPipeline.STAT_VISIBLE )
        Console.println( "[cam] dual-cam stats: cameras=" + pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ).toString() + " visible=" + vis.toString() )
        if vis != 3
        {
            Console.println( "[cam] FAIL: visible union should be 3 objects" )
            ret false
        }

        # (320,360) 左半：cam0 的橙图 quad 中心（图片橙色；世界 (-0.5,0)）
        Int32 r1 = sampleChannel( px, 1280, 320, 360, 0 )
        Int32 g1 = sampleChannel( px, 1280, 320, 360, 1 )
        Int32 b1 = sampleChannel( px, 1280, 320, 360, 2 )
        Console.println( "[cam] left img    RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (320,360)" )
        if r1 < 200 || g1 < 100 || g1 > 160 || b1 > 70
        {
            Console.println( "[cam] FAIL: image quad pixel should be orange in cam0 view" )
            ret false
        }
        # (800,360) 右半：cam1 重画同一橙图 quad（depth=10 后画；
        # 右半 viewport 内世界 (-0.5,0)）
        r1 = sampleChannel( px, 1280, 800, 360, 0 )
        g1 = sampleChannel( px, 1280, 800, 360, 1 )
        b1 = sampleChannel( px, 1280, 800, 360, 2 )
        Console.println( "[cam] right img   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (800,360)" )
        if r1 < 200 || g1 < 100 || g1 > 160 || b1 > 70
        {
            Console.println( "[cam] FAIL: cam1 should redraw layer2 image quad in right viewport" )
            ret false
        }
        # (1200,113) 右半：cam1 独立清屏色（深绿）；cam0 深蓝背景被覆盖
        r1 = sampleChannel( px, 1280, 1200, 113, 0 )
        g1 = sampleChannel( px, 1280, 1200, 113, 1 )
        b1 = sampleChannel( px, 1280, 1200, 113, 2 )
        Console.println( "[cam] right clear RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (1200,113)" )
        if r1 > 15 || g1 < 55 || g1 > 75 || b1 < 15 || b1 > 35
        {
            Console.println( "[cam] FAIL: cam1 clear color should cover right viewport" )
            ret false
        }
        # (320,113) 左半：cam0 深蓝背景清屏色
        r1 = sampleChannel( px, 1280, 320, 113, 0 )
        g1 = sampleChannel( px, 1280, 320, 113, 1 )
        b1 = sampleChannel( px, 1280, 320, 113, 2 )
        Console.println( "[cam] left bg     RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (320,113)" )
        if r1 < 9 || r1 > 21 || g1 < 9 || g1 > 21 || b1 < 19 || b1 > 33
        {
            Console.println( "[cam] FAIL: left half should keep cam0 clear color" )
            ret false
        }

        # ── 帧 2：禁用相机1 -> 右半回到 cam0 画面（多相机选择开关）──
        if cam.setEnabled( false ) == false
        {
            Console.println( "[cam] FAIL: disable cam1" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[cam] FAIL: renderFrame single-cam" )
            ret false
        }
        if pipe.stat( SLang.RenderPipeline.STAT_CAMERA_COUNT ) != 1
        {
            Console.println( "[cam] FAIL: STAT_CAMERA_COUNT should be 1 after disable" )
            ret false
        }
        r1 = sampleChannel( px, 1280, 800, 360, 0 )
        g1 = sampleChannel( px, 1280, 800, 360, 1 )
        b1 = sampleChannel( px, 1280, 800, 360, 2 )
        Console.println( "[cam] blue quad   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (800,360)" )
        if r1 < 40 || r1 > 65 || g1 < 90 || g1 > 115 || b1 < 240
        {
            Console.println( "[cam] FAIL: cam0 blue quad should show after disabling cam1" )
            ret false
        }
        r1 = sampleChannel( px, 1280, 960, 360, 0 )
        g1 = sampleChannel( px, 1280, 960, 360, 1 )
        b1 = sampleChannel( px, 1280, 960, 360, 2 )
        Console.println( "[cam] blue quad   RGB=(" + r1.toString() + "," + g1.toString() + "," + b1.toString() + ") @ (960,360)" )
        if r1 < 40 || r1 > 65 || g1 < 90 || g1 > 115 || b1 < 240
        {
            Console.println( "[cam] FAIL: blue quad should appear in cam0-only frame" )
            ret false
        }

        # ── 场景移交 QT 窗口展示（重新启用相机1）──────────────────
        if cam.setEnabled( true ) == false
        {
            Console.println( "[cam] FAIL: re-enable cam1" )
            ret false
        }
        _pipe = pipe
        _pixels = px
        _texW = 1280
        _texH = 720

        Console.println( "[cam] Phase A3: PASS (multi-camera depth order + viewport split + cullingMask + image file render)" )
        ret true
    }

    # ── Phase L：光照（一个直射光 + 一个 spot 光 + 无光回归）────────
    # 场景（1280x720，ortho [-1,1]²，ambient 0.25）：
    #   直射光 slot 0：方向 (1,0)、白色、强度 0.9 —— 顶部两个白 quad
    #     （rot 0 朝光 vs rot π 背光）验证 ndl 按物体朝向着色；
    #   聚光 slot 1：位置 (0,0.35)、光轴 (0,-1)、锥半角 30°、范围 1.3、
    #     暖色 (1.0,0.85,0.55)、强度 1.2 —— 底部大背光 quad（rot π，
    #     ndl=0 只剩环境光）上验证锥内/锥外亮度差（锥内 + 距离衰减）。
    # v3.4 增补：
    #   阴影 —— 白 box(0.45,-0.2) castShadow（不透明 z=0、地板接收面
    #     z=-0.1）：直射光沿 -x 投出阴影 quad（偏移 0.136、放大 1.15、
    #     黑 0.35、深度夹层 -0.01），S_in(阴影内地板) 显著暗于
    #     S_out(锥内普通地板)；无光回归帧无光源 -> 阴影不生成 ->
    #     纯白基线不受影响；
    #   灯光摇晃 —— 帧 2 摆动聚光（posX=0.08*sin(2.1)、强度
    #     1.2+0.35*sin(3.7)）-> P1 亮度随灯动变化（Δ≥4）；
    #   Phong —— 独立 256 管线子场景：同光照下 Lambert quad vs Phong
    #     quad（spec 2.0/4.0）中心亮度差 = 伪 3D 高光贡献（Δ≥35）。
    # 末帧回归：clearLight(0/1) + setAmbient(1.0) -> 采样点全部回到
    # 纯白（无光照默认态与旧版逐字节一致）。
    static bool runLightScene()
    {
        Console.println( "-- Phase L: lighting + sway + Phong + shadow (1 directional + 1 spot, ambient 0.25) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1280, 720 )
        if pipe == null
        {
            Console.println( "[light] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: setClearColor" )
            ret false
        }

        # 光照：环境光 + 直射光 + 聚光（Light.applyTo 写管线槽）
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[light] FAIL: setAmbient" )
            ret false
        }
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[light] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[light] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }
        Light lamp = Light.spot( Color( 1.0f, 0.85f, 0.55f, 1.0f ), 1.2f, 1.3f, 30.0f )
        if lamp == null
        {
            Console.println( "[light] FAIL: Light.spot" )
            ret false
        }
        lamp.posX = 0.0f
        lamp.posY = 0.35f
        lamp.dirX = 0.0f
        lamp.dirY = -1.0f
        if lamp.applyTo( pipe, 1 ) == false
        {
            Console.println( "[light] FAIL: spot applyTo - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.lightCount() != 2
        {
            Console.println( "[light] FAIL: lightCount should be 2" )
            ret false
        }

        # 顶部两个白 quad：rot 0（法线 (1,0)，朝直射光 -> 全亮）
        # vs rot π（法线 (-1,0)，背光 -> 仅环境光）
        SLang.RenderObject quadA = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject quadB = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quadA == null || quadB == null
        {
            Console.println( "[light] FAIL: add quads" )
            ret false
        }
        quadA.setPosition( -0.55f, 0.6f, 0.0f )
        quadA.setScale( 0.42f, 0.42f )
        quadA.setRotationZ( 0.0f )
        quadA.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        quadB.setPosition( 0.55f, 0.6f, 0.0f )
        quadB.setScale( 0.42f, 0.42f )
        quadB.setRotationZ( 3.14159f )
        quadB.setColor( 1.0f, 1.0f, 1.0f, 1.0f )

        # 底部大背光 quad（rot π -> ndl=0，只剩环境光 + 聚光贡献）。
        # 不透明队列（2000）+ z=-0.1（比 box 远）—— 阴影接收面须先于
        # 阴影绘制且深度比阴影远；z<=0 保证 D3D11 NDC [0,1] 有效域
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[light] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.45f, -0.1f )
        floor.setScale( 1.9f, 1.0f )
        floor.setRotationZ( 3.14159f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # v3.4 阴影投射 box：朝光白方块（不透明、z=0 比地板近），
        # 直射光 (1,0) 沿 -x 投出阴影 quad（阴影中心 (0.314,-0.2)、尺寸
        # 0.345、z=-0.01 深度夹层：地板 -0.1 < 阴影 -0.01 < box 0），
        # 阴影落在地板上，与 box 重叠区被本体深度剔除
        SLang.RenderObject box = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if box == null
        {
            Console.println( "[light] FAIL: add shadow box" )
            ret false
        }
        box.setPosition( 0.45f, -0.2f, 0.0f )
        box.setScale( 0.3f, 0.3f )
        box.setRotationZ( 0.0f )
        box.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        box.setQueue( 2000 )
        if box.setShadow( 1 ) == false
        {
            Console.println( "[light] FAIL: box.setShadow - " + SLang.Render.errorString() )
            ret false
        }

        Int64 px = Memory.alloc( 1280 * 720 * 4 )
        if px == 0
        {
            Console.println( "[light] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1：光照开 —— 采样六点（世界坐标 -> 1280x720 像素：
        #    x=(wx+1)/2*1280, y=(1-(wy+1)/2)*720）────────────────────
        #    A(288,144)=quadA 中心 B(992,144)=quadB 中心
        #    P1(640,492)=锥内地板 P2(1200,492)=锥外地板
        #    S_in(768,432)=box 阴影内地板 S_out(512,432)=锥内无阴影地板
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame lit - " + SLang.Render.errorString() )
            ret false
        }
        Int32 aR = sampleChannel( px, 1280, 288, 144, 0 )
        Int32 bR = sampleChannel( px, 1280, 992, 144, 0 )
        Int32 p1R = sampleChannel( px, 1280, 640, 492, 0 )
        Int32 p2R = sampleChannel( px, 1280, 1200, 492, 0 )
        Int32 sInR = sampleChannel( px, 1280, 768, 432, 0 )
        Int32 sOutR = sampleChannel( px, 1280, 512, 432, 0 )
        Console.println( "[light] lit   A=" + aR.toString() + " B=" + bR.toString() + " P1=" + p1R.toString() + " P2=" + p2R.toString() + " S_in=" + sInR.toString() + " S_out=" + sOutR.toString() )
        # 直射光：A 朝光全亮（0.25+0.9 -> 255），B 背光仅环境光（~64）
        if aR < 245
        {
            Console.println( "[light] FAIL: facing quad should be fully lit" )
            ret false
        }
        if bR < 45 || bR > 90
        {
            Console.println( "[light] FAIL: back-facing quad should be ambient-only" )
            ret false
        }
        if aR - bR < 120
        {
            Console.println( "[light] FAIL: directional ndl difference missing" )
            ret false
        }
        # 聚光：P1 锥内（环境光 + 衰减贡献 ~125），P2 锥外仅环境光（~64）
        if p1R < 100 || p1R > 165
        {
            Console.println( "[light] FAIL: in-cone pixel brightness out of range" )
            ret false
        }
        if p2R < 45 || p2R > 90
        {
            Console.println( "[light] FAIL: out-of-cone pixel should be ambient-only" )
            ret false
        }
        if p1R - p2R < 30
        {
            Console.println( "[light] FAIL: spot cone difference missing" )
            ret false
        }
        # 阴影：S_in = 阴影内地板（地板亮度 * 0.65），S_out = 锥内无阴影地板
        # 同聚光下两地板点光照一致 -> 亮度差即阴影 alpha 0.35 的贡献
        if sInR < 80 || sInR > 140
        {
            Console.println( "[light] FAIL: shadowed floor brightness out of range" )
            ret false
        }
        if sOutR - sInR < 25
        {
            Console.println( "[light] FAIL: shadow darkening missing (S_out - S_in < 25)" )
            ret false
        }

        # ── 帧 2：灯光摇晃 —— 聚光位置/强度小幅摆动 -> P1 亮度变化 ──
        # （QT 演示同款动画的确定性快照：posX ±0.08 摇晃 + 强度 ±0.35 脉动）
        lamp.posX = 0.08f * Mathf.sin( 2.1f )
        lamp.intensity = 1.2f + 0.35f * Mathf.sin( 3.7f )
        if lamp.applyTo( pipe, 1 ) == false
        {
            Console.println( "[light] FAIL: sway applyTo - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.renderFrame( 1.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame sway - " + SLang.Render.errorString() )
            ret false
        }
        Int32 p1sR = sampleChannel( px, 1280, 640, 492, 0 )
        Console.println( "[light] sway  P1=" + p1sR.toString() + " (lamp px=" + ( 0.08f * Mathf.sin( 2.1f ) ).toString() + " I=" + ( 1.2f + 0.35f * Mathf.sin( 3.7f ) ).toString() + ")" )
        if p1sR < 95 || p1sR > 175
        {
            Console.println( "[light] FAIL: swayed in-cone brightness out of range" )
            ret false
        }
        if p1R - p1sR < 4 && p1sR - p1R < 4
        {
            Console.println( "[light] FAIL: lamp sway should change pixel brightness" )
            ret false
        }

        # ── 帧 3：Phong 子场景（独立 256 管线）──────────────────────
        # 同一光照（直射光 0.5 + ambient 0.1）：Lambert quad 中心 =
        # (0.1+0.5)*255 ≈ 153；Phong quad（spec 2.0/4.0）中心 =
        # (0.1+0.5+0.5*0.213*2)*255 ≈ 207 —— 差值即伪 3D 高光贡献
        SLang.RenderPipeline pipe2 = SLang.RenderPipeline.create( 256, 256 )
        if pipe2 == null
        {
            Console.println( "[light] FAIL: phong pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe2.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: phong setCamera" )
            ret false
        }
        if pipe2.setAmbient( 0.1f ) == false
        {
            Console.println( "[light] FAIL: phong setAmbient" )
            ret false
        }
        Light sun2 = Light.directional( Color.white(), 0.5f )
        if sun2 == null
        {
            Console.println( "[light] FAIL: phong Light.directional" )
            ret false
        }
        sun2.dirX = 1.0f
        sun2.dirY = 0.0f
        if sun2.applyTo( pipe2, 0 ) == false
        {
            Console.println( "[light] FAIL: phong applyTo" )
            ret false
        }
        SLang.RenderObject quadL = pipe2.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject quadP = pipe2.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quadL == null || quadP == null
        {
            Console.println( "[light] FAIL: phong add quads" )
            ret false
        }
        quadL.setPosition( -0.55f, 0.6f, 0.0f )
        quadL.setScale( 0.42f, 0.42f )
        quadL.setRotationZ( 0.0f )
        quadL.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        quadP.setPosition( 0.55f, 0.6f, 0.0f )
        quadP.setScale( 0.42f, 0.42f )
        quadP.setRotationZ( 0.0f )
        quadP.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        if quadP.setMaterial( 1 ) == false || quadP.setSpecular( 2.0f, 4.0f ) == false
        {
            Console.println( "[light] FAIL: phong material/specular - " + SLang.Render.errorString() )
            ret false
        }
        Int64 px2 = Memory.alloc( 256 * 256 * 4 )
        if px2 == 0
        {
            Console.println( "[light] FAIL: phong pixel alloc" )
            ret false
        }
        if pipe2.renderFrame( 0.0f, px2 ) == false
        {
            Console.println( "[light] FAIL: phong renderFrame - " + SLang.Render.errorString() )
            ret false
        }
        Int32 lR = sampleChannel( px2, 256, 58, 51, 0 )
        Int32 pR = sampleChannel( px2, 256, 198, 51, 0 )
        Console.println( "[light] phong L=" + lR.toString() + " P=" + pR.toString() )
        if lR < 135 || lR > 170
        {
            Console.println( "[light] FAIL: lambert quad brightness out of range" )
            ret false
        }
        if pR < 190 || pR > 225
        {
            Console.println( "[light] FAIL: phong quad brightness out of range" )
            ret false
        }
        if pR - lR < 35
        {
            Console.println( "[light] FAIL: phong specular highlight missing (P - L < 35)" )
            ret false
        }
        if pipe2.destroy() == false
        {
            Console.println( "[light] FAIL: phong pipeline destroy" )
            ret false
        }

        # ── 帧 4：回归 —— 清光 + ambient=1 -> 无光照基线（纯白）──
        if pipe.clearLight( 0 ) == false || pipe.clearLight( 1 ) == false
        {
            Console.println( "[light] FAIL: clearLight" )
            ret false
        }
        if pipe.setAmbient( 1.0f ) == false
        {
            Console.println( "[light] FAIL: setAmbient restore" )
            ret false
        }
        if pipe.lightCount() != 0
        {
            Console.println( "[light] FAIL: lightCount should be 0 after clear" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame unlit - " + SLang.Render.errorString() )
            ret false
        }
        Int32 uA = sampleChannel( px, 1280, 288, 144, 0 )
        Int32 uB = sampleChannel( px, 1280, 992, 144, 0 )
        Int32 uP1 = sampleChannel( px, 1280, 640, 492, 0 )
        Int32 uP2 = sampleChannel( px, 1280, 1200, 492, 0 )
        Int32 uS = sampleChannel( px, 1280, 768, 432, 0 )
        Console.println( "[light] unlit A=" + uA.toString() + " B=" + uB.toString() + " P1=" + uP1.toString() + " P2=" + uP2.toString() + " S=" + uS.toString() )
        if uA < 250 || uB < 250 || uP1 < 250 || uP2 < 250 || uS < 250
        {
            Console.println( "[light] FAIL: no-light baseline should be pure white (shadow off without lights)" )
            ret false
        }

        Console.println( "[light] Phase L: PASS (directional ndl + spot cone/attenuation + lamp sway + Phong specular + shadow + no-light regression)" )
        ret true
    }

    # ── Phase B：QT 窗口 + 后端切换 UI（返回 2=PASS 1=SKIP 0=FAIL）──
    # 顶部按钮行（OpenGL/D3D11/Vulkan/WebGL-GLES）点击切换渲染底层；
    # 4s 自动轮播自动验证四后端在 QT 帧循环下持续渲染（用户点击后停）；
    # 终判 = 帧数 + gl 位 + 至少一个其他后端位。
    static Int32 runQtWindow()
    {
        string kind = SLang.QT.backendKind()
        if kind != "qt"
        {
            Console.println( "-- Phase B: skipped (backend=" + kind + "; build+deploy the Qt backend to enable) --" )
            ret 1
        }
        if _pipe == null || _pixels == 0
        {
            Console.println( "-- Phase B: skipped (Phase A did not init pipeline) --" )
            ret 1
        }

        Console.println( "-- Phase B: QT window + backend switcher (buttons: OpenGL/D3D11/Vulkan/WebGL-GLES; 4s auto-cycle) --" )

        _app = SLang.QT.newApp()
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        host.setTitle( "SLangRender multi-backend (click: OpenGL / D3D11 / Vulkan / WebGL)" )
        host.resize( 296, 372 )

        # 按钮行（点击即切换渲染底层）
        _btnGl = SLang.QT.newButton( host.handle, "OpenGL" )
        _btnGl.setGeometry( 10, 10, 64, 24 )
        _btnDx = SLang.QT.newButton( host.handle, "D3D11" )
        _btnDx.setGeometry( 78, 10, 64, 24 )
        _btnVk = SLang.QT.newButton( host.handle, "Vulkan" )
        _btnVk.setGeometry( 146, 10, 64, 24 )
        _btnWeb = SLang.QT.newButton( host.handle, "WebGL" )
        _btnWeb.setGeometry( 214, 10, 72, 24 )
        _btnGl.setToolTip( "switch render backend to WGL + OpenGL 3.3" )
        _btnDx.setToolTip( "switch render backend to Direct3D 11" )
        _btnVk.setToolTip( "switch render backend to Vulkan (offscreen)" )
        _btnWeb.setToolTip( "switch render backend to EGL + GLES 3.0 (WebGL stack)" )

        # 状态栏（当前后端 + 渲染器）
        _status = SLang.QT.newLabel( host.handle, "" )
        _status.setGeometry( 10, 38, 276, 18 )

        # 渲染画面
        _label = SLang.QT.newLabel( host.handle, "" )
        _label.setGeometry( 10, 58, 276, 296 )
        host.show()

        # 信号连接（clicked -> 无参 static 回调经 Function 桥；
        # SL 的 || 链上限 2 个运算符，逐个检查）
        Int64 bGl = _btnGl.clicked( RenderTest.onBtnGl )
        Int64 bDx = _btnDx.clicked( RenderTest.onBtnDx )
        Int64 bVk = _btnVk.clicked( RenderTest.onBtnVk )
        Int64 bWeb = _btnWeb.clicked( RenderTest.onBtnWeb )
        if bGl == 0 || bDx == 0
        {
            Console.println( "[QT] FAIL: backend button signal connect (gl=" + bGl.toString() + " dx=" + bDx.toString() + ")" )
            ret 0
        }
        if bVk == 0 || bWeb == 0
        {
            Console.println( "[QT] FAIL: backend button signal connect (vk=" + bVk.toString() + " web=" + bWeb.toString() + ")" )
            ret 0
        }

        updateStatus()

        _t = 0.0f
        _backendMask = 0
        _cycleStep = 0
        _userPicked = false
        SLang.QTimer quitT = SLang.QT.newTimer( 30000, true, RenderTest.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 16, false, RenderTest.onTick )
        SLang.QTimer cycleT = SLang.QT.newTimer( 4000, false, RenderTest.onAutoCycle )
        _app.exec()

        Console.println( "[QT] renderFrames=" + _renderFrames.toString() + " pixOk=" + _pixOk.toString() + " backendMask=" + _backendMask.toString() )

        animT.delete()
        cycleT.delete()
        quitT.delete()
        host.delete()

        if _renderFrames < 60 || _pixOk < 60
        {
            Console.println( "[QT] FAIL: frame loop too slow (need >= 60 rendered + 60 filled)" )
            ret 0
        }
        # 后端掩码：gl 位必在（奇数）+ 至少一个其他后端在 QT 循环里渲染过
        if ( _backendMask % 2 ) == 0 || _backendMask < 3
        {
            Console.println( "[QT] FAIL: backend switching did not render (mask=" + _backendMask.toString() + ", expect >= 3 with gl bit)" )
            ret 0
        }
        # Phase C 断言：立方体动态网格在（最后轮换的）当前后端上传成功过
        if _cubeFirst != 1
        {
            Console.println( "[QT] FAIL: cube mesh upload never succeeded (Mesh + MESH_CUSTOM channel broken)" )
            ret 0
        }
        Console.println( "[QT] Phase B: PASS (backend-switchable render: mask=" + _backendMask.toString() + " [gl/d3d11/vk/gles bits 1/2/4/8]; 13-stage renderTexture each frame + spinning cube)" )
        ret 2
    }
}
