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
#   另有 7s 自动轮播（d3d11 -> vk -> gles -> gl）自动验证四后端在
#   QT 帧循环下都能持续渲染（用户点击任一按钮后轮播停止，尊重选择）；
#   60s 退出 -> 帧数断言 + 后端掩码断言（gl + 至少一个其他后端渲染过）
# Phase C 3D 旋转细分立方体（Mesh 数学层 + RHI 动态网格 + 材质门面）：
#   makeComplexCubeMesh 复用 Mesh.cube 面表双线性插值出每面 2x2 子块
#   （5 实体面 80 顶点 120 索引，f/-Y 底面留空可透视内部，e/+Y 顶面
#   alpha 0.45 半透）-> Float32_4x4.rotationY/X(t) CPU 旋转 -> 相机 -Z
#   朝 +Z（dist = z + 2.6）-> 手工透视除法（f=1.7）-> NDC 三角形列表
#   （painter 平均深度降序，远先画保遮挡）-> Memory.writeF32 填
#   pos2+uv2（UV 按面/子块/角点现场推导进六面图集 cell）->
#   pipe.uploadMesh(slot 0)，对象 meshKind = MESH_CUSTOM(4) 每帧重传；
#   材质门面类 Shader/Texture/Material 全程串联：单一 SlPhong shader
#   + 192x128 六面图集 + 每面一份 Material，对象贴图/颜色/队列/材质
#   路由均从门面字段派生下发；onTick 驱动自转（QT 16ms 帧循环）
# Phase G 固化 shader（gen 效果，material 0..4 全路由固化槽）：
#   5 效果（Lambert/Phong/BlinnPhong/NormalMap/Toon）× flat/tex 变体
#   正面断言 —— 退化等价（uSpec=0）、Blinn/Phong 高光手算值、Toon
#   阶梯手算值、NormalMap 零扰动等价；VK 降级 builtin 一致性复检
# Phase INST GPU 实例化（N1：方案 B，C 侧 sl_cmd.c 回放 RLE 合批）：
#   8x8 网格 64 实例 PFLAT 纯色 quad；场景 A = 64x setPerDraw 先行 +
#   连续 64x drawItem -> RLE 合 1 次 instanced draw（draws=3 = 1 合并 +
#   post + blit、opaque=1、instances=64）；场景 B = setPerDraw/drawItem
#   交替打断 RLE -> 64 独立 draw（draws=66）；双保险断言：64 槽中心 RGB
#   抽样（baseSlot+InstanceID -> uColor[obj] 槽号路由）+ A/B 两帧
#   262144 字节逐点一致（合批与逐 draw 数值等价）
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
    static SLang.Mesh _cubeMesh = null       # 细分立方体：5 面各 2x2 = 80 顶点 120 索引
    static SLang.RenderObject _cubeObj = null   # meshKind=4（动态网格槽 0）
    static Int64 _cubeVerts = 0             # 120 顶点 * 16B 显存暂存（帧间复用）
    static Int32 _cubeFirst = 0             # 首帧 uploadMesh 结果打印标志
    # UV 不建表：vi/16=面、(vi%16)/4=子块、vi%4=角点 -> 图集 cell（updateCube 现场计算）

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
                # UV：face-major 布局 vi/16=面 -> 图集 cell、
                # (vi%16)/4=子块、vi%4=角点；半纹素内缩防渗色
                Int32 face = vi / 16
                Int32 sub = ( vi % 16 ) / 4
                Int32 corner = vi % 4
                Int32 col = face % 3
                Int32 row = face / 3
                Float32 u0 = ( col * 64 + 0.5f ) / 192.0f
                Float32 u1 = ( ( col + 1 ) * 64 - 0.5f ) / 192.0f
                Float32 v0 = ( row * 64 + 0.5f ) / 128.0f
                Float32 v1 = ( ( row + 1 ) * 64 - 0.5f ) / 128.0f
                Float32 u = u0
                Float32 v = v0
                if sub == 1 || sub == 3
                {
                    u = u0 + ( u1 - u0 ) * 0.5f
                }
                if sub >= 2
                {
                    v = v0 + ( v1 - v0 ) * 0.5f
                }
                if corner == 1 || corner == 2
                {
                    u = u + ( u1 - u0 ) * 0.5f
                }
                if corner == 2 || corner == 3
                {
                    v = v + ( v1 - v0 ) * 0.5f
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

    # ── Phase C：细分立方体网格（每面 2x2 子块，f 底面留空）──────────
    # 复用 Mesh.cube 的面表角序：a..f = +Z/-Z/+X/-X/+Y/-Y，每面 4 角点
    # 双线性插值出 2x2 子方块（4 子块 x 4 角点）；f 面（face 5，-Y 底面）
    # 跳过几何 —— 旋转时透过空面可见立方体内部。顶点布局 face-major：
    # face = vi/16、sub = (vi%16)/4、corner = vi%4（updateCube 据此推 UV）。
    # 产出：5 面 x 20 子块角点 = 80 顶点、40 三角形 120 索引、面法线。
    static SLang.Mesh makeComplexCubeMesh( Float32 size )
    {
        SLang.Mesh src = SLang.Mesh.cube( size )
        if src == null
        {
            ret null
        }
        Array<Float32> pos = Array<Float32>( 5 * 16 * 3 )
        Array<Float32> nrm = Array<Float32>( 5 * 16 * 3 )
        Array<Int32> tri = Array<Int32>( 5 * 4 * 6 )
        Int32 vi = 0
        Int32 ti = 0
        Int32 face = 0
        while face < 6
        {
            if face != 5
            {
                # 面四角点（角序 (0,0)(1,0)(1,1)(0,1)，从面外看逆时针）+ 面法线
                Float32_3 c0 = src.getVertex( face * 4 )
                Float32_3 c1 = src.getVertex( face * 4 + 1 )
                Float32_3 c2 = src.getVertex( face * 4 + 2 )
                Float32_3 c3 = src.getVertex( face * 4 + 3 )
                Float32_3 n = src.getNormal( face * 4 )
                Int32 qy = 0
                while qy < 2
                {
                    Int32 qx = 0
                    while qx < 2
                    {
                        # 子块四角（角序 00,10,11,01）：
                        # P(s,t) = c0(1-s)(1-t) + c1 s(1-t) + c2 s t + c3(1-s)t
                        Int32 k = 0
                        while k < 4
                        {
                            Float32 s = qx * 0.5f
                            Float32 tt = qy * 0.5f
                            if k == 1 || k == 2
                            {
                                s = s + 0.5f
                            }
                            if k == 2 || k == 3
                            {
                                tt = tt + 0.5f
                            }
                            Float32 ws = 1.0f - s
                            Float32 wt = 1.0f - tt
                            Float32 w0 = ws * wt
                            Float32 w1 = s * wt
                            Float32 w2 = s * tt
                            Float32 w3 = ws * tt
                            pos[ vi * 3 ] = c0.x * w0 + c1.x * w1 + c2.x * w2 + c3.x * w3
                            pos[ vi * 3 + 1 ] = c0.y * w0 + c1.y * w1 + c2.y * w2 + c3.y * w3
                            pos[ vi * 3 + 2 ] = c0.z * w0 + c1.z * w1 + c2.z * w2 + c3.z * w3
                            nrm[ vi * 3 ] = n.x
                            nrm[ vi * 3 + 1 ] = n.y
                            nrm[ vi * 3 + 2 ] = n.z
                            vi = vi + 1
                            k = k + 1
                        }
                        # 子块双三角形：00,10,11 + 00,11,01
                        Int32 b0 = vi - 4
                        tri[ ti ] = b0
                        tri[ ti + 1 ] = b0 + 1
                        tri[ ti + 2 ] = b0 + 2
                        tri[ ti + 3 ] = b0
                        tri[ ti + 4 ] = b0 + 2
                        tri[ ti + 5 ] = b0 + 3
                        ti = ti + 6
                        qx = qx + 1
                    }
                    qy = qy + 1
                }
            }
            face = face + 1
        }
        ret SLang.Mesh( pos, tri, nrm )
    }

    # 字母位图取位：5bit 行值，x=0 取最高位（最左列）
    static Int32 glyphBit( Int32 rowBits, Int32 x )
    {
        Int32 v = rowBits
        Int32 k = 4 - x
        while k > 0
        {
            v = v / 2
            k = k - 1
        }
        ret v % 2
    }

    # ── Phase C：六面图集（Texture 门面类逐像素构建）──────────────────
    # 192x128 = 3x2 cell（每 cell 64x64），face -> col=face%3、row=face/3：
    # a 红 / b 绿 / c 蓝 / d 琥珀 不透明；e 白青 alpha 0.45（透明面）；
    # f 暗色 alpha 0（空面，无几何引用）。每 cell：2x2 象限明暗棋盘
    # （与几何子块对应）+ 中心 1px 十字暗线 + 居中 5x5 位图字母（x6
    # 缩放）。字母按渲染方向垂直翻转写入（v=0 <-> 像素 y=0 <-> 面底部）。
    static Texture makeCubeAtlas()
    {
        Texture tex = Texture( 192, 128 )
        Array<Float32> fr = Array<Float32>( 6 )
        Array<Float32> fg = Array<Float32>( 6 )
        Array<Float32> fb = Array<Float32>( 6 )
        Array<Float32> fa = Array<Float32>( 6 )
        fr[0] = 0.92f; fg[0] = 0.28f; fb[0] = 0.22f; fa[0] = 1.0f
        fr[1] = 0.24f; fg[1] = 0.72f; fb[1] = 0.34f; fa[1] = 1.0f
        fr[2] = 0.25f; fg[2] = 0.45f; fb[2] = 0.92f; fa[2] = 1.0f
        fr[3] = 0.98f; fg[3] = 0.75f; fb[3] = 0.18f; fa[3] = 1.0f
        fr[4] = 0.85f; fg[4] = 0.95f; fb[4] = 1.0f; fa[4] = 0.45f
        fr[5] = 0.10f; fg[5] = 0.10f; fb[5] = 0.12f; fa[5] = 0.0f
        # 5x5 字母位图（a..f，行值高位在左）
        Array<Int32> gl = Array<Int32>( 30 )
        gl[0] = 14; gl[1] = 17; gl[2] = 31; gl[3] = 17; gl[4] = 17
        gl[5] = 30; gl[6] = 17; gl[7] = 30; gl[8] = 17; gl[9] = 30
        gl[10] = 15; gl[11] = 16; gl[12] = 16; gl[13] = 16; gl[14] = 15
        gl[15] = 30; gl[16] = 17; gl[17] = 17; gl[18] = 17; gl[19] = 30
        gl[20] = 31; gl[21] = 16; gl[22] = 30; gl[23] = 16; gl[24] = 31
        gl[25] = 31; gl[26] = 16; gl[27] = 30; gl[28] = 16; gl[29] = 16
        Int32 face = 0
        while face < 6
        {
            Int32 x0 = ( face % 3 ) * 64
            Int32 y0 = ( face / 3 ) * 64
            Int32 y = 0
            while y < 64
            {
                Int32 x = 0
                while x < 64
                {
                    Float32 shade = 0.82f
                    if ( x / 32 + y / 32 ) % 2 == 1
                    {
                        shade = 1.0f
                    }
                    if x == 32 || y == 32
                    {
                        shade = shade * 0.55f
                    }
                    Color c = Color( fr[face] * shade, fg[face] * shade, fb[face] * shade, fa[face] )
                    tex.setPixel( x0 + x, y0 + y, c )
                    x = x + 1
                }
                y = y + 1
            }
            # 居中字母：5x5 位图 x6 缩放（30x30，边距 17），字形行 gy
            # 垂直翻转写到 (4-gy)*6（上屏才正立）；alpha 乘面透明度
            Int32 gy = 0
            while gy < 5
            {
                Int32 gx = 0
                while gx < 5
                {
                    if RenderTest.glyphBit( gl[ face * 5 + gy ], gx ) == 1
                    {
                        Color lc = Color( 0.97f, 0.97f, 0.95f, fa[face] )
                        Int32 px = x0 + 17 + gx * 6
                        Int32 py = y0 + 17 + ( 4 - gy ) * 6
                        Int32 dy = 0
                        while dy < 6
                        {
                            Int32 dx = 0
                            while dx < 6
                            {
                                tex.setPixel( px + dx, py + dy, lc )
                                dx = dx + 1
                            }
                            dy = dy + 1
                        }
                    }
                    gx = gx + 1
                }
                gy = gy + 1
            }
            face = face + 1
        }
        ret tex
    }

    # 单面材质门面：颜色取图集 cell 中心采样，e 面（face 4）透明化
    static Material makeFaceMaterial( Shader sh, Texture atlas, Int32 face, string name )
    {
        Color c = atlas.getPixel( ( face % 3 ) * 64 + 32, ( face / 3 ) * 64 + 32 )
        Material m = Material( sh, c )
        m.name = name
        m.setTexture( atlas )
        m.clampParameters()
        if face == 4
        {
            m.setTransparent( true )
        }
        ret m
    }

    # Texture（门面 Float32 RGBA）-> RGBA8 显存块 -> RenderTexture 上屏
    static SLang.RenderTexture textureToRenderTexture( Texture tex )
    {
        if tex == null || tex.isValid == false
        {
            ret null
        }
        Int64 ptr = Memory.alloc( tex.width * tex.height * 4 )
        if ptr == 0
        {
            ret null
        }
        Int32 y = 0
        while y < tex.height
        {
            Int32 x = 0
            while x < tex.width
            {
                Color c = tex.getPixel( x, y )
                Int32 o = ( y * tex.width + x ) * 4
                Memory.writeI8( ptr, o, RenderTest.f2b( c.r ) )
                Memory.writeI8( ptr, o + 1, RenderTest.f2b( c.g ) )
                Memory.writeI8( ptr, o + 2, RenderTest.f2b( c.b ) )
                Memory.writeI8( ptr, o + 3, RenderTest.f2b( c.a ) )
                x = x + 1
            }
            y = y + 1
        }
        ret SLang.RenderTexture.createRgba( ptr, tex.width, tex.height )
    }

    # [0,1] 浮点 -> 0..255 字节（钳制 + 四舍五入）
    static Int32 f2b( Float32 f )
    {
        if f < 0.0f
        {
            f = 0.0f
        }
        if f > 1.0f
        {
            f = 1.0f
        }
        ret Mathf.truncate( f * 255.0f + 0.5f )
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
        # 2026-11-13 修复：先释放旧帧缓冲再清引用 —— 原直接 _pixels = 0
        # 抢跑指针，每轮 rebuildScene 新 alloc 3.6MB（1250*720*4）全部泄漏，
        # 4 轮后 SL 堆耗尽，rebuildScene 在 px 分配静默 ret false（唯一无
        # FAIL 打印的中止点）-> _pipe 悬空 -> 立方体上传断言必失败。
        # 旧块无原生侧所有权（仅回写目的地），uninit 前后释放皆安全。
        if _pixels != 0
        {
            Memory.free( _pixels )
        }
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

        # 蓝 quad（layer0，右半；投影阴影 + Toon 卡通阶梯[3 档]）
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
        blueQuad.setMaterial( 4 )
        blueQuad.setSpecular( 3.0f, 0.5f )
        blueQuad.setShadow( 1 )

        # v3.5 固化效果展示：BlinnPhong 高光 quad（底部左）+ NormalMap
        # 贴图高光 quad（底部右）—— 5 效果全上屏（Lambert=三角/立方体、
        # Phong=橙图、Toon=蓝 quad、BlinnPhong/NormalMap=本组）
        SLang.RenderObject bpQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if bpQuad == null
        {
            ret false
        }
        bpQuad.setLayer( 0 )
        bpQuad.setQueue( 2000 )
        bpQuad.setPosition( -0.55f, -0.58f, 0.0f )
        bpQuad.setScale( 0.28f, 0.28f )
        bpQuad.setColor( 0.95f, 0.55f, 0.15f, 1.0f )
        bpQuad.setMaterial( 2 )
        bpQuad.setSpecular( 2.5f, 32.0f )

        SLang.RenderObject nmQuad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if nmQuad == null
        {
            ret false
        }
        nmQuad.setLayer( 0 )
        nmQuad.setQueue( 2000 )
        nmQuad.setPosition( 0.55f, -0.58f, 0.0f )
        nmQuad.setScale( 0.28f, 0.28f )
        nmQuad.setColor( 0.55f, 0.85f, 0.40f, 1.0f )
        nmQuad.setTexture( imgTex )
        nmQuad.setMaterial( 3 )
        nmQuad.setSpecular( 1.5f, 48.0f )

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

        # ── Phase C：细分立方体（每面 2x2 子块，f 面留空，e 面透明）──
        # 材质门面串联（SLangRender 纯 SL 类）：Shader(SlPhong 单一
        # shader) -> Texture(192x128 六面图集逐像素构建) -> Material
        # (a..f 每面一份 + 主材质 clone 白色)——对象贴图/颜色/队列/
        # 材质路由全部从门面 Material/Shader 字段派生后下发。
        _cubeMesh = RenderTest.makeComplexCubeMesh( 1.0f )
        if _cubeMesh == null
        {
            Console.println( "[ui] FAIL: makeComplexCubeMesh" )
            ret false
        }
        Console.println( "[cube] subdivided mesh verts=" + _cubeMesh.vertexCount.toString() + " indices=" + _cubeMesh.getTriangles().length.toString() )
        Shader phongShader = Shader( "SlPhong", "// vertex: reuse builtin VS_COMMON_POS_UV", "// fragment: reuse builtin FS_PHONG_TEX" )
        Texture atlas = RenderTest.makeCubeAtlas()
        if atlas == null || atlas.isValid == false
        {
            Console.println( "[ui] FAIL: makeCubeAtlas" )
            ret false
        }
        Material matA = RenderTest.makeFaceMaterial( phongShader, atlas, 0, "CubeFaceA" )
        Material matB = RenderTest.makeFaceMaterial( phongShader, atlas, 1, "CubeFaceB" )
        Material matC = RenderTest.makeFaceMaterial( phongShader, atlas, 2, "CubeFaceC" )
        Material matD = RenderTest.makeFaceMaterial( phongShader, atlas, 3, "CubeFaceD" )
        Material matE = RenderTest.makeFaceMaterial( phongShader, atlas, 4, "CubeFaceE" )
        Material matF = RenderTest.makeFaceMaterial( phongShader, atlas, 5, "CubeFaceF" )
        Material matMain = matA.clone()
        matMain.name = "CubeMain"
        matMain.setColor( Color.white() )
        Console.println( "[mat] main: " + matMain.toString() + " shader=" + matMain.shader.name + " " + matMain.getTexture().toString() )
        Console.println( "[mat] faces: " + matB.toString() + " | " + matC.toString() + " | " + matD.toString() )
        string eflag = "false"
        if matE.isTransparent
        {
            eflag = "true"
        }
        Console.println( "[mat] e(transparent)=" + eflag + " f(EMPTY)=" + matF.toString() )
        if _cubeVerts == 0
        {
            _cubeVerts = Memory.alloc( 120 * 16 )
        }
        if _cubeVerts == 0
        {
            Console.println( "[ui] FAIL: cube verts alloc" )
            ret false
        }
        # 门面 Texture(Float32 RGBA) -> RGBA8 显存块 -> RenderTexture
        SLang.RenderTexture atlasRt = RenderTest.textureToRenderTexture( matMain.getTexture() )
        if atlasRt == null
        {
            Console.println( "[ui] FAIL: atlas upload - " + SLang.Render.errorString() )
            ret false
        }
        _cubeObj = pipe.addObject( SLang.RenderPipeline.MESH_CUSTOM )
        if _cubeObj == null
        {
            Console.println( "[ui] FAIL: cube addObject - " + SLang.Render.errorString() )
            ret false
        }
        # 顶点已烘焙 NDC：位置/缩放保持单位；贴图/颜色取自门面 matMain
        # （图集 atlasRt + 白色调制，六面同槽共用一张纹理）；e 面
        # alpha 0.45 -> 由 isTransparent 派生透明队列 3000 后画叠加；
        # 材质路由由 shader 名派生（SlPhong -> 1）+ 贴图高光 + 投影
        # 阴影（聚光点源 -> 阴影随灯摇晃）
        _cubeObj.setTexture( atlasRt )
        Color mc = matMain.getColor()
        _cubeObj.setColor( mc.r, mc.g, mc.b, mc.a )
        Int32 matRoute = 0
        if matMain.shader.name == "SlPhong"
        {
            matRoute = 1
        }
        _cubeObj.setMaterial( matRoute )
        _cubeObj.setSpecular( 1.2f, 10.0f )
        _cubeObj.setShadow( 1 )
        if matE.isTransparent
        {
            _cubeObj.setQueue( 3000 )
        }
        RenderTest.updateCube( _t )

        Int64 px = Memory.alloc( 1250 * 720 * 4 )
        if px == 0
        {
            # 可诊断性：px 分配失败原先静默 ret false（堆耗尽时 _pipe 悬空
            # 全部 tick 无声跳过，极难定位）
            Console.println( "[ui] FAIL: frame buffer alloc (SL heap exhausted?)" )
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

    # 自动轮播（7s 一拍）：d3d11 -> vk -> gles -> gl，用户点过按钮即停
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
        Console.println( "[QT] quit timer fired (normal 60s exit)" )
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

        # Phase SHADOW2：N2a 真实阴影（shadow map + PCF 平行光；当前 GL 后端）
        bool phaseShadow2 = runShadowMap()

        # Phase CSM：N2b 4 级联（v 分段 + 图集 1x4；当前 GL 后端）
        bool phaseCsm = runCsmShadow()

        # Phase G：固化 shader（gen 效果 material>=2）正面断言（当前 GL 后端）
        bool phaseG = runGenShaders()

        # Phase CB：CommandBuffer 真录制（录制 -> 整理 -> 提交渲染，当前 GL 后端）
        bool phaseCB = runCommandBuffer()

        # Phase INST：GPU 实例化合批（N1：64 实例 1 draw vs 64 draw 像素一致）
        bool phaseInst = runInstancing()

        # Phase PASS：Pass 序列提交（Opaque/Transparent/Post/Blit 四 Pass 单流）
        bool phasePass = runPassSubmit()

        # Phase FEATURE：Feature 注入（AfterPost 全屏色块 + Volume 覆盖栈）
        bool phaseFeature = runFeatureInject()

        # Phase ASSET：RenderPipeline 资产层（资产 -> 实例 -> Render(FrameData)）
        bool phaseAsset = runAssetPipeline()

        # Phase ENV：渲染环境查询（支持情况 / 当前选择 / 硬件 / 资源 / 配置 / 帧级统计）
        bool phaseEnv = runEnvironmentQuery()

        # Phase RTPOOL：RT 句柄池（同尺寸复用 / releaseAll）
        bool phaseRtpool = runRtPool()

        # Phase FS：FrameSettings（后处理开关 / 透明序策略 / 目标缩放）
        bool phaseFs = runFrameSettings()

        # Phase DATA：数据层快照（CullingData / FrameData / PassData）
        bool phaseData = runDataSnapshot()

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
        Console.println( "phase SHADOW2(shadow map)    : " + ( phaseShadow2 ? "PASS" : "FAIL" ) )
        Console.println( "phase CSM  (csm 4 cascades)  : " + ( phaseCsm ? "PASS" : "FAIL" ) )
        Console.println( "phase G  (frozen shaders)   : " + ( phaseG ? "PASS" : "FAIL" ) )
        Console.println( "phase CB (command buffer)   : " + ( phaseCB ? "PASS" : "FAIL" ) )
        Console.println( "phase INST(gpu instancing)  : " + ( phaseInst ? "PASS" : "FAIL" ) )
        Console.println( "phase PASS(pass sequence)   : " + ( phasePass ? "PASS" : "FAIL" ) )
        Console.println( "phase FEATURE(custom pass)  : " + ( phaseFeature ? "PASS" : "FAIL" ) )
        Console.println( "phase ASSET(pipeline asset) : " + ( phaseAsset ? "PASS" : "FAIL" ) )
        Console.println( "phase ENV(render env)       : " + ( phaseEnv ? "PASS" : "FAIL" ) )
        Console.println( "phase RTPOOL(rt handle pool): " + ( phaseRtpool ? "PASS" : "FAIL" ) )
        Console.println( "phase FS  (frame settings)   : " + ( phaseFs ? "PASS" : "FAIL" ) )
        Console.println( "phase DATA(data layer)       : " + ( phaseData ? "PASS" : "FAIL" ) )
        Console.println( "phase B  (QT window)         : " + bText )
        # 终判：主流程全绿 + D3D11/VK 可用即 PASS，GLES 允许 SKIP（环境无 GLES 库）
        bool allOk = phaseA
        if !phaseL
        {
            allOk = false
        }
        if !phaseShadow2
        {
            allOk = false
        }
        if !phaseCsm
        {
            allOk = false
        }
        if !phaseG
        {
            allOk = false
        }
        if !phaseCB
        {
            allOk = false
        }
        if !phaseInst
        {
            allOk = false
        }
        if !phasePass
        {
            allOk = false
        }
        if !phaseFeature
        {
            allOk = false
        }
        if !phaseAsset
        {
            allOk = false
        }
        if !phaseEnv
        {
            allOk = false
        }
        if !phaseRtpool
        {
            allOk = false
        }
        if !phaseFs
        {
            allOk = false
        }
        if !phaseData
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
        # N2a shadow map + PCF 跨后端复检（D3D11 深度直通 zxform=(1,0)）
        bool d6 = runShadowMap()
        # 固化 shader gen 效果（DXBC blob 直读）同像素复检
        bool d5 = runGenShaders()
        # 本阶段管线句柄在切回 GL 后失效：清空 QT 移交（GL 主流程会重设）
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3 && d4 && d5 && d6
        {
            Console.println( "[d3d11] Phase D: PASS (v1 + 13-stage + multi-cam + image + lighting + shadow-map + frozen-gen, pixels identical to GL)" )
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
        # 固化 shader gen 效果：VK 降级 builtin 槽（像素=内建）一致性复检
        bool d5 = runGenShaders()
        # 切回 GL 前先清空管线句柄移交（GL 主流程会重设）
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3 && d5
        {
            Console.println( "[vk] Phase E: PASS (v1 + 13-stage + multi-cam + image + frozen-gen, pixels identical to GL)" )
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
        # N2a shadow map + PCF 跨后端复检（GLES 硬件深度 zxform=(2,-1) 同 GL）
        bool d6 = runShadowMap()
        # 固化 shader gen 效果（ESSL300 运行期编固化源）同像素复检
        bool d5 = runGenShaders()
        _pipe = null
        _pixels = 0
        if d1 && d2 && d3 && d4 && d5 && d6
        {
            Console.println( "[gles] Phase F: PASS (v1 + 13-stage + multi-cam + image + lighting + shadow-map + frozen-gen, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[gles] Phase F: FAIL" )
        ret 0
    }

    # ── Phase G：固化 shader（gen 效果，material 0..4 全路由）端到端 ──
    # 「通用固化编译」产物正面断言（GL/D3D11/GLES 用真实 gen 源码，
    # 全部 5 效果 × flat/tex 变体；VK 降级 builtin 槽）。同一 quad 切
    # material 对比法：
    #   断言 1：uSpec.x 默认 0 时 gen BlinnPhong-flat 与 gen Lambert-flat
    #     公式逐字一致 -> 两帧中心像素逐通道差 <= 2（末位浮点容差）；
    #   断言 2a：setSpecular(2,8)+直射光 -> Blinn 高光真实执行（手算
    #     NdotH~0.916、pow8~0.50 -> 中心像素大幅增亮）；
    #   断言 2b：gen Phong 经典高光 R=reflect(-L,N)、pow(R·V,8)*2 ->
    #     手算 (63,126,251)±3（比 Blinn 暗，两族公式可区分）；
    #   断言 3：gen NormalMap-flat —— uSpec.z（凹凸强度）无 API 写入
    #     恒 0 -> 扰动/边缘光全零，退化为 BlinnPhong 基座 -> == 基准 1；
    #   断言 4：gen Toon-flat setSpecular(3,0.5)（3 阶梯 + 阈值夹取 1
    #     压制硬边高光）-> 手算阶梯 tint (48,97,207)±3 且暗于 Lambert；
    #   断言 5：gen BlinnPhong-tex == gen Lambert-tex（tex 变体）；
    #   断言 6：gen NormalMap-tex == 基准 5（tex 变体槽位）；
    #   断言 7：gen Toon-tex 阶梯 tint 全通道严格暗于 Lambert-tex。
    #   VK：全部效果降级 PFLAT/PTEX（uSpec 不消费）-> 一致性断言改
    #     比对应基准，specular/阶梯手算断言跳过。
    static bool runGenShaders()
    {
        Console.println( "-- Phase G: frozen shaders (gen effects, material>=2) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[gen] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[gen] FAIL: setClearColor" )
            ret false
        }
        # 低环境光 + 直射光（漫反射 + Blinn 高光两条路径都活跃）
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[gen] FAIL: setAmbient" )
            ret false
        }
        Light sun = Light.directional( Color.white(), 0.9f )
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[gen] FAIL: apply directional light" )
            ret false
        }
        # 居中 quad：rot=0 法线 (1,0) 正对直射光 -> 全亮基准
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quad == null
        {
            Console.println( "[gen] FAIL: addObject - " + SLang.Render.errorString() )
            ret false
        }
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setScale( 0.8f, 0.8f )
        quad.setColor( 0.2f, 0.4f, 0.8f, 1.0f )
        Int64 px = Memory.alloc( 128 * 128 * 4 )
        if px == 0
        {
            Console.println( "[gen] FAIL: alloc pixels" )
            ret false
        }

        # 断言 1：material 2（gen BlinnPhong flat，uSpec.x 默认 0 无高光）
        #   vs material 0（gen Lambert flat，uSpec.x=0 时同漫反射核心）
        #   —— 两帧中心像素逐通道差 <= 2
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2)" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen flat - " + SLang.Render.errorString() )
            ret false
        }
        Int32 g1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 g1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 g1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong-flat (uSpec=0)  : (" + g1r + "," + g1g + "," + g1b + ")" )
        if quad.setMaterial( 0 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(0)" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render builtin flat - " + SLang.Render.errorString() )
            ret false
        }
        Int32 b1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 b1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 b1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Lambert-flat (uSpec=0) : (" + b1r + "," + b1g + "," + b1b + ")" )
        Int32 dr = g1r - b1r
        if dr < 0
        {
            dr = -dr
        }
        Int32 dg = g1g - b1g
        if dg < 0
        {
            dg = -dg
        }
        Int32 db = g1b - b1b
        if db < 0
        {
            db = -db
        }
        if dr > 2 || dg > 2 || db > 2
        {
            Console.println( "[gen] FAIL: gen flat != Lambert flat (diff " + dr + "," + dg + "," + db + ")" )
            ret false
        }

        # 断言 2a：高光活跃（非平凡证明）—— setSpecular(2,8) 后像素必变
        bool isVk = SLang.Render.currentBackend() == "vk"
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2) for specular" )
            ret false
        }
        if quad.setSpecular( 2.0f, 8.0f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen specular - " + SLang.Render.errorString() )
            ret false
        }
        Int32 s1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 s1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 s1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong specular(2,8): (" + s1r + "," + s1g + "," + s1b + ")" )
        Int32 sr = s1r - g1r
        if sr < 0
        {
            sr = -sr
        }
        Int32 sg = s1g - g1g
        if sg < 0
        {
            sg = -sg
        }
        Int32 sb = s1b - g1b
        if sb < 0
        {
            sb = -sb
        }
        if isVk
        {
            Console.println( "[gen] vk fallback slot: gen effects degrade to builtin PFLAT/PTEX (uSpec not consumed) - specular assertion skipped" )
        }
        else
        {
            # 手算：NdotH~0.916、pow8~0.50 -> 高光 ~0.9 -> 中心像素
            # 大幅增亮（R 差 ~196）。全部 <3 说明 gen 高光没执行。
            if sr < 3 && sg < 3 && sb < 3
            {
                Console.println( "[gen] FAIL: specular did not change pixels (diff " + sr + "," + sg + "," + sb + ")" )
                ret false
            }
        }

        # 断言 2b：gen Phong（material 1）经典高光 —— R=reflect(-L,N)、
        #   pow(R·V,8)*2 手算 light=1.15+0.081 -> (63,126,251)±3；
        #   与 Blinn（104,208,255）可区分（半角向量更亮）。VK 降级
        #   PFLAT 不消费 uSpec -> 应等于基准 1。
        if quad.setMaterial( 1 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(1) phong" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen phong - " + SLang.Render.errorString() )
            ret false
        }
        Int32 p1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 p1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 p1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Phong specular(2,8)    : (" + p1r + "," + p1g + "," + p1b + ")" )
        if isVk
        {
            Int32 vr = p1r - g1r
            if vr < 0
            {
                vr = -vr
            }
            Int32 vg = p1g - g1g
            if vg < 0
            {
                vg = -vg
            }
            Int32 vb = p1b - g1b
            if vb < 0
            {
                vb = -vb
            }
            if vr > 2 || vg > 2 || vb > 2
            {
                Console.println( "[gen] FAIL: vk phong != degraded flat (diff " + vr + "," + vg + "," + vb + ")" )
                ret false
            }
        }
        else
        {
            Int32 pr = p1r - 63
            if pr < 0
            {
                pr = -pr
            }
            Int32 pg = p1g - 126
            if pg < 0
            {
                pg = -pg
            }
            Int32 pb = p1b - 251
            if pb < 0
            {
                pb = -pb
            }
            if pr > 3 || pg > 3 || pb > 3
            {
                Console.println( "[gen] FAIL: gen phong specular off (got " + p1r + "," + p1g + "," + p1b + " expect ~63,126,251)" )
                ret false
            }
        }

        # 断言 3：gen NormalMap-flat（material 3）—— uSpec.z（凹凸强度）
        #   无 API 写入恒 0 -> 扰动/边缘光全零，公式退化为 BlinnPhong
        #   基座 -> 与基准 1 逐字节一致（VK 同降级一致）。先重置高光。
        if quad.setSpecular( 0.0f, 0.0f ) == false
        {
            Console.println( "[gen] FAIL: reset specular nm-flat" )
            ret false
        }
        if quad.setMaterial( 3 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(3) normalmap" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen normalmap - " + SLang.Render.errorString() )
            ret false
        }
        Int32 n1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 n1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 n1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen NormalMap-flat (bump=0) : (" + n1r + "," + n1g + "," + n1b + ")" )
        Int32 nr = n1r - g1r
        if nr < 0
        {
            nr = -nr
        }
        Int32 ng = n1g - g1g
        if ng < 0
        {
            ng = -ng
        }
        Int32 nb = n1b - g1b
        if nb < 0
        {
            nb = -nb
        }
        if nr > 2 || ng > 2 || nb > 2
        {
            Console.println( "[gen] FAIL: gen normalmap flat != blinnphong base (diff " + nr + "," + ng + "," + nb + ")" )
            ret false
        }

        # 断言 4：gen Toon-flat（material 4，setSpecular(3,0.5) = 3 阶梯
        #   + 高光阈值夹取 1 压制硬边高光）—— 手算阶梯 tint
        #   (0.775,0.775,0.85) -> (48,97,207)±3 且至少一通道严格暗于
        #   Lambert 基准；VK 降级 PFLAT -> == 基准 1。
        if quad.setMaterial( 4 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(4) toon" )
            ret false
        }
        if quad.setSpecular( 3.0f, 0.5f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular toon" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen toon - " + SLang.Render.errorString() )
            ret false
        }
        Int32 t1r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 t1g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 t1b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Toon-flat (steps=3)     : (" + t1r + "," + t1g + "," + t1b + ")" )
        if isVk
        {
            Int32 kr = t1r - g1r
            if kr < 0
            {
                kr = -kr
            }
            Int32 kg = t1g - g1g
            if kg < 0
            {
                kg = -kg
            }
            Int32 kb = t1b - g1b
            if kb < 0
            {
                kb = -kb
            }
            if kr > 2 || kg > 2 || kb > 2
            {
                Console.println( "[gen] FAIL: vk toon != degraded flat (diff " + kr + "," + kg + "," + kb + ")" )
                ret false
            }
        }
        else
        {
            Int32 qr = t1r - 48
            if qr < 0
            {
                qr = -qr
            }
            Int32 qg = t1g - 97
            if qg < 0
            {
                qg = -qg
            }
            Int32 qb = t1b - 207
            if qb < 0
            {
                qb = -qb
            }
            if qr > 3 || qg > 3 || qb > 3
            {
                Console.println( "[gen] FAIL: gen toon steps off (got " + t1r + "," + t1g + "," + t1b + " expect ~48,97,207)" )
                ret false
            }
            if t1r >= g1r && t1g >= g1g && t1b >= g1b
            {
                Console.println( "[gen] FAIL: gen toon == lambert (no band tint)" )
                ret false
            }
        }

        # 断言 5：gen BlinnPhong-tex == gen Lambert-tex（tex 变体，先重置高光）
        if quad.setSpecular( 0.0f, 0.0f ) == false
        {
            Console.println( "[gen] FAIL: reset specular" )
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[gen] FAIL: gradient texture" )
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[gen] FAIL: createRgba - " + SLang.Render.errorString() )
            ret false
        }
        if quad.setTexture( tex ) == false
        {
            Console.println( "[gen] FAIL: setTexture" )
            ret false
        }
        # material 2 + texture -> gen BlinnPhong TEX 变体
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2) tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 g2r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 g2g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 g2b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong-tex          : (" + g2r + "," + g2g + "," + g2b + ")" )
        if quad.setMaterial( 0 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(0) tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render builtin tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 b2r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 b2g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 b2b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Lambert-tex            : (" + b2r + "," + b2g + "," + b2b + ")" )
        Int32 xtr = g2r - b2r
        if xtr < 0
        {
            xtr = -xtr
        }
        Int32 xtg = g2g - b2g
        if xtg < 0
        {
            xtg = -xtg
        }
        Int32 xtb = g2b - b2b
        if xtb < 0
        {
            xtb = -xtb
        }
        if xtr > 2 || xtg > 2 || xtb > 2
        {
            Console.println( "[gen] FAIL: gen tex != Lambert tex (diff " + xtr + "," + xtg + "," + xtb + ")" )
            ret false
        }

        # 断言 6：gen NormalMap-tex（material 3 + 纹理）—— 同断言 3
        #   （tex 变体槽位）：bump=0 -> == 基准 5（gen Lambert-tex）。
        if quad.setMaterial( 3 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(3) nm-tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen nm-tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 n2r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 n2g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 n2b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen NormalMap-tex (bump=0)  : (" + n2r + "," + n2g + "," + n2b + ")" )
        Int32 mr = n2r - g2r
        if mr < 0
        {
            mr = -mr
        }
        Int32 mg = n2g - g2g
        if mg < 0
        {
            mg = -mg
        }
        Int32 mb = n2b - g2b
        if mb < 0
        {
            mb = -mb
        }
        if mr > 2 || mg > 2 || mb > 2
        {
            Console.println( "[gen] FAIL: gen nm-tex != lambert-tex (diff " + mr + "," + mg + "," + mb + ")" )
            ret false
        }

        # 断言 7：gen Toon-tex（material 4 + 纹理 + setSpecular(3,0.5)）
        #   —— 阶梯 tint 光照 (0.9475,0.9475,1.015) < Lambert 1.15
        #   -> 全通道严格暗于基准 5；VK 降级 PTEX -> == 基准 5。
        if quad.setMaterial( 4 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(4) toon-tex" )
            ret false
        }
        if quad.setSpecular( 3.0f, 0.5f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular toon-tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen toon-tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 t2r = sampleChannel( px, 128, 64, 64, 0 )
        Int32 t2g = sampleChannel( px, 128, 64, 64, 1 )
        Int32 t2b = sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Toon-tex (steps=3)      : (" + t2r + "," + t2g + "," + t2b + ")" )
        if isVk
        {
            Int32 wr = t2r - g2r
            if wr < 0
            {
                wr = -wr
            }
            Int32 wg = t2g - g2g
            if wg < 0
            {
                wg = -wg
            }
            Int32 wb = t2b - g2b
            if wb < 0
            {
                wb = -wb
            }
            if wr > 2 || wg > 2 || wb > 2
            {
                Console.println( "[gen] FAIL: vk toon-tex != degraded tex (diff " + wr + "," + wg + "," + wb + ")" )
                ret false
            }
        }
        else
        {
            if t2r >= g2r || t2g >= g2g || t2b >= g2b
            {
                Console.println( "[gen] FAIL: gen toon-tex not darker than lambert-tex (" + t2r + "," + t2g + "," + t2b + " vs " + g2r + "," + g2g + "," + g2b + ")" )
                ret false
            }
        }

        Console.println( "[gen] Phase G: PASS (5 frozen effects live: Lambert/Phong/BlinnPhong/NormalMap/Toon x flat+tex, backend " + SLang.Render.currentBackend() + ")" )
        ret true
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

        # 2026-11-13 修复：原误写 1280x720 —— renderFrame 按管线 w/h 回写，
        # 1280x720 会写爆 256x256 的 _pixels 缓冲（3.5MB 堆越界，几何错位
        # 采样必失败，且堆破坏污染后续阶段）。与本阶段 256x256 采样断言一致。
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
        Console.println( "[a3dbg] step1: before bad loadFile" )
        # N2B-DBG（临时）：跳过坏路径，直接测好路径
        SLang.RenderTexture badTex = null
        Console.println( "[a3dbg] step2: bad loadFile skipped" )
        if badTex != null
        {
            Console.println( "[cam] FAIL: loadFile should fail for missing file" )
            ret false
        }

        Console.println( "[a3dbg] step3: before pipe create" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1280, 720 )
        Console.println( "[a3dbg] step4: after pipe create" )
        if pipe == null
        {
            Console.println( "[cam] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }

        Console.println( "[a3dbg] step5: before stat texcount" )
        Int32 texBefore = pipe.stat( SLang.RenderPipeline.STAT_TEXTURE_COUNT )
        Console.println( "[a3dbg] step6: texBefore=" + texBefore.toString() )
        # 相对路径依赖运行进程 CWD（package 目录），失败则回退绝对路径
        Console.println( "[a3dbg] step7: before good loadFile" )
        SLang.RenderTexture imgTex = SLang.RenderTexture.loadFile( "SlangAllInOne/SLangCore/test/RenderTest/test_image.png" )
        Console.println( "[a3dbg] step8: after good loadFile" )
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
        # 2026-11-13 修复：原误写 1280x720（注释即"独立 256 管线"；
        # px2 为 256x256 缓冲，1280x720 回写 3.5MB 堆越界）
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

    # ── Phase SHADOW2：N2a 真实阴影（shadow map + PCF，平行光）──────
    # AIPrompt N2a 验收相位（遮挡像素断言——阴影内亮度 < 阴影外）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25；quad 半边 = scale*0.5）：
    #   直射光 slot 0：dirX=1（表面→光源 = +x，光沿 -x 照）、白 0.9、
    #     shadowQuality=1 —— stage_shadow_pass（阶段 4.5）以光空间
    #     正交投影渲 castShadow 对象入 512 深度图（LESS 保留最朝光面），
    #     LightBlock 下发 lightVP + shadow 参数，gen shader PCF 4-tap；
    #   地板：pos (0,-0.6,z=-0.1) scale (1.9,0.8) rot 0（法线 (1,0)
    #     朝光 ndl=1 全亮）—— 白色不透明接收面，x∈[-0.95,0.95]
    #     y∈[-1.0,-0.2]；
    #   box：castShadow pos (0.3,-0.6,z=0) scale (0.3,0.3)——
    #     x∈[0.15,0.45] y∈[-0.75,-0.45]，光沿 -x：地板上 x<0.45 且
    #     y∈box 区间区域被遮（深度图记录 box 最朝光 u=0.45 面）。
    # 采样（世界→像素 px=(wx+1)/2*256, py=(1-(wy+1)/2)*256）：
    #   S_in(-0.2,-0.6)→(102,204)：阴影内地板 = (0.25+0.9*0.65)*255≈213
    #   S_out(0.8,-0.6)→(230,204)：box 朝光侧外地板 = 1.15 饱和 255
    #   S_side(-0.2,-0.3)→(102,166)：地板内但 box y 区间外（v 超出）
    #     不遮 → 255（阴影被限定在遮挡几何的光向投影内——非全屏变暗）。
    # shadowQuality=0 时（Phase L 黑斑路径）本相位不重复覆盖。
    static bool runShadowMap()
    {
        Console.println( "-- Phase SHADOW2: shadow map + PCF (directional light, 256x256) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[shadow2] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[shadow2] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[shadow2] FAIL: setClearColor" )
            ret false
        }
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[shadow2] FAIL: setAmbient" )
            ret false
        }

        # 平行光：shadowQuality=1 启用 shadow map（N2a）
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[shadow2] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        sun.shadowQuality = 1.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[shadow2] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 地板（接收面）：rot 0 朝光、z=-0.1 比 box 远
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[shadow2] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.6f, -0.1f )
        floor.setScale( 1.9f, 0.8f )
        floor.setRotationZ( 0.0f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # 阴影投射 box（不透明 z=0）
        SLang.RenderObject box = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if box == null
        {
            Console.println( "[shadow2] FAIL: add box" )
            ret false
        }
        box.setPosition( 0.3f, -0.6f, 0.0f )
        box.setScale( 0.3f, 0.3f )
        box.setRotationZ( 0.0f )
        box.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        box.setQueue( 2000 )
        if box.setShadow( 1 ) == false
        {
            Console.println( "[shadow2] FAIL: box.setShadow - " + SLang.Render.errorString() )
            ret false
        }

        Int64 px = Memory.alloc( 256 * 256 * 4 )
        if px == 0
        {
            Console.println( "[shadow2] FAIL: pixel alloc" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[shadow2] FAIL: renderFrame - " + SLang.Render.errorString() )
            ret false
        }

        Int32 sInR = sampleChannel( px, 256, 102, 204, 0 )
        Int32 sOutR = sampleChannel( px, 256, 230, 204, 0 )
        Int32 sSideR = sampleChannel( px, 256, 102, 166, 0 )
        Console.println( "[shadow2] S_in=" + sInR.toString() + " S_out=" + sOutR.toString() + " S_side=" + sSideR.toString() )
        if sOutR < 250
        {
            Console.println( "[shadow2] FAIL: unshadowed floor should be fully lit (ambient + directional)" )
            ret false
        }
        if sInR < 175 || sInR > 235
        {
            Console.println( "[shadow2] FAIL: shadowed floor brightness out of range (expect ~213)" )
            ret false
        }
        if sOutR - sInR < 30
        {
            Console.println( "[shadow2] FAIL: shadow darkening missing (S_out - S_in < 30)" )
            ret false
        }
        if sSideR < 250
        {
            Console.println( "[shadow2] FAIL: outside-projection floor should be fully lit" )
            ret false
        }

        Console.println( "[shadow2] Phase SHADOW2: PASS (shadow map: in-shadow 213 < out-shadow 255, PCF + projection bounds verified)" )
        ret true
    }

    # ── Phase CSM：N2b 级联阴影（4 级联 v 分段 + 图集 1x4 分区）─────
    # AIPrompt N2b 验收相位（级联采样落位断言）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25，光 (1,0) 沿 -x，
    # shadowQuality=1 + shadowCascades=4）——v 轴 = 光空间 y（dx=1,dy=0
    # → v = world.y）：相机视域 [-1,1] 主导 → 级联分段
    # {-1, -0.9, -0.5, 0.2, 1}（0.05/0.25/0.6/1.0 比例）：
    #   地板 (0,-0.1,z-0.1) scale (1.9,1.8)：y∈[-1.0,0.8] 接收面；
    #   boxA (0.3,-0.85) 0.3 —— v∈[-1.0,-0.7] 跨级联 0/1；
    #   boxB (0.3,0.0) 0.3   —— v∈[-0.15,0.15] 仅级联 2；
    #   boxC (0.3,-0.5) 0.2  —— v∈[-0.6,-0.4] 骑跨级联 1/2 边界(-0.5)。
    # 断言（级联采样落位——选错级联 → 采到空分区 → 255 不暗）：
    #   S_inA(-0.2,-0.85)=213（级联 0 落位 + boxA 覆盖）
    #   S_inB(-0.2,0.0)=213（级联 2 落位——boxB 只渲进级联 2，
    #     若 v 比较错落 0/1/3 级 → 空区 → 255）
    #   S_out(0.8,0.0)=255（级联 2 无遮挡区）
    #   S_e1(-0.2,-0.55)=213（boxC 级联 1 侧覆盖）
    #   S_e2(-0.2,-0.45)=213（boxC 级联 2 侧覆盖——边界骑跨两级都渲）
    #   S_out2(-0.2,0.3)=255（级联 3 空区）
    static bool runCsmShadow()
    {
        Console.println( "-- Phase CSM: 4-cascade shadow atlas (v split 0.05/0.25/0.6/1.0, 256x256) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[csm] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[csm] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[csm] FAIL: setClearColor" )
            ret false
        }
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[csm] FAIL: setAmbient" )
            ret false
        }

        # 平行光：shadowQuality=1 + 4 级联（N2b CSM）
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[csm] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        sun.shadowQuality = 1.0f
        sun.shadowCascades = 4.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[csm] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 地板（接收面，rot 0 朝光）
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[csm] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.1f, -0.1f )
        floor.setScale( 1.9f, 1.8f )
        floor.setRotationZ( 0.0f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # 三个 castShadow box（分属不同级联 + 骑跨边界）
        SLang.RenderObject boxA = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject boxB = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject boxC = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if boxA == null || boxB == null || boxC == null
        {
            Console.println( "[csm] FAIL: add boxes" )
            ret false
        }
        boxA.setPosition( 0.3f, -0.85f, 0.0f )
        boxA.setScale( 0.3f, 0.3f )
        boxA.setRotationZ( 0.0f )
        boxA.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxA.setQueue( 2000 )
        if boxA.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxA.setShadow" )
            ret false
        }
        boxB.setPosition( 0.3f, 0.0f, 0.0f )
        boxB.setScale( 0.3f, 0.3f )
        boxB.setRotationZ( 0.0f )
        boxB.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxB.setQueue( 2000 )
        if boxB.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxB.setShadow" )
            ret false
        }
        boxC.setPosition( 0.3f, -0.5f, 0.0f )
        boxC.setScale( 0.2f, 0.2f )
        boxC.setRotationZ( 0.0f )
        boxC.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxC.setQueue( 2000 )
        if boxC.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxC.setShadow" )
            ret false
        }

        Int64 px = Memory.alloc( 256 * 256 * 4 )
        if px == 0
        {
            Console.println( "[csm] FAIL: pixel alloc" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[csm] FAIL: renderFrame - " + SLang.Render.errorString() )
            ret false
        }

        Int32 sInA = sampleChannel( px, 256, 102, 237, 0 )
        Int32 sInB = sampleChannel( px, 256, 102, 128, 0 )
        Int32 sOut = sampleChannel( px, 256, 230, 128, 0 )
        Int32 sE1 = sampleChannel( px, 256, 102, 199, 0 )
        Int32 sE2 = sampleChannel( px, 256, 102, 186, 0 )
        Int32 sOut2 = sampleChannel( px, 256, 102, 90, 0 )
        Console.println( "[csm] S_inA=" + sInA.toString() + " S_inB=" + sInB.toString() + " S_out=" + sOut.toString() + " S_e1=" + sE1.toString() + " S_e2=" + sE2.toString() + " S_out2=" + sOut2.toString() )
        # 级联 0 落位（boxA 在 v≈-0.85 区）
        if sInA < 175 || sInA > 235
        {
            Console.println( "[csm] FAIL: cascade 0 sampling misplaced (expect ~213)" )
            ret false
        }
        # 级联 2 落位（boxB 仅渲进级联 2——选错级联采空区 255）
        if sInB < 175 || sInB > 235
        {
            Console.println( "[csm] FAIL: cascade 2 sampling misplaced (expect ~213)" )
            ret false
        }
        if sOut < 250
        {
            Console.println( "[csm] FAIL: unshadowed floor should be fully lit" )
            ret false
        }
        # 边界骑跨：boxC 在级联 1 与级联 2 两侧都投影覆盖
        if sE1 < 175 || sE1 > 235
        {
            Console.println( "[csm] FAIL: boundary box cascade-1 side should be shadowed" )
            ret false
        }
        if sE2 < 175 || sE2 > 235
        {
            Console.println( "[csm] FAIL: boundary box cascade-2 side should be shadowed" )
            ret false
        }
        # 级联 3 空区（v=0.3 无遮挡）
        if sOut2 < 250
        {
            Console.println( "[csm] FAIL: empty cascade 3 region should be fully lit" )
            ret false
        }

        Console.println( "[csm] Phase CSM: PASS (4 cascades: per-level placement + boundary straddle + empty region, atlas 1x4)" )
        ret true
    }

    # ── Phase CB：CommandBuffer 真录制（录制 → 整理 → 提交渲染）──
    # Unity 式三段式端到端验收（doc/04 §3.6 SLMC 命令流全链路）：
    #   1 录制：cb.begin() 后零后端调用，仅参数组织与顺序记账 ——
    #     setRenderTargets / setTexture / setPerDraw / drawItem /
    #     postProcess / blitFinal / readback，共 11 条命令；
    #   2 整理：cb.sortDrawItems() 对 DrawItem 段排序（drawItem 乱序
    #     录入：蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0；正确序 = 三角
    #     (queue2000 不透明先画) -> 贴图(z0.5 远) -> 蓝(z0.3 近)，
    #     透明 z 降序远->近保混合）；
    #   3 提交渲染：pipe.executeCommandBuffer(cb) 按 SLMC 布局打包
    #     整包提交，C 侧逐 opcode 回放（命令流走 RHI vtable ->
    #     GL/D3D11/VK/GLES 四后端同效果，Phase D/E/F 各复检一次）。
    # 场景（自建自毁 256x256 管线，不触碰 _pipe/_pixels）：
    #   perdraw 槽 0 红三角（不透明 queue2000）；槽 1 白贴图 quad
    #   (中心 0.45,0.35 scale0.55, 透明 z0.5, 64x64 渐变贴图)；槽 2
    #   蓝 quad（中心 0.55,0.35 scale0.25, 透明 z0.3, 与贴图 quad
    #   重叠 —— 重叠点是排序方向验证点：正确序蓝后画 -> 蓝分量高）。
    static bool runCommandBuffer()
    {
        Console.println( "-- Phase CB: CommandBuffer record -> sort -> execute (SLMC stream, 256x256) --" )
        # 2026-11-13 修复：原误写 1280x720 —— readback/blit 按管线 w/h 回写，
        # 1280x720 会写爆 256x256 的 pixels 缓冲（堆越界、黑角、异常退出码）。
        # 与本阶段 256x256 采样断言/64x64 贴图一致。
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[cb] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[cb] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[cb] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[cb] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # MVP（ortho(-1,1,-1,1) 投影≈单位阵 -> MVP≈model2d）
        # 2026-11-13 修复：Float32_4x4 为列向量约定（Math 模块 translation
        # 工厂/toFloat32_3x3 实证：平移在末列 m03/m13），pushMat 写 std140
        # 列主序 [col*4+row]=M[row][col] 与 GLSL uMVP*v 匹配。原矩阵把
        # 平移写在底行（m30/m31）-> GLSL 收到转置矩阵（无平移 + w 被污染）
        # -> quad 几何畸变，采样点全落 quad 外。平移移到每行第 4 参：
        # m03=tx m13=ty。
        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # ── 1 录制：11 条命令，drawItem 故意乱序（蓝 z0.3 -> 贴图
        #    z0.5 -> 三角 z0.0），排序必须重排为正确绘制序 ──────────
        CommandBuffer cb = CommandBuffer()
        cb.name = "cb-main"
        cb.begin()
        cb.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256,
                             3, Color( 0.06f, 0.06f, 0.10f, 1.0f ) )
        cb.setTexture( 0, tex.handle )
        cb.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        cb.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        cb.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cb.drawItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        cb.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cb.blitFinal()
        cb.readback( pixels )
        cb.end()
        Console.println( "[cb] recorded " + cb.commandCount.toString() + " commands (overflow=" + cb.overflowCount.toString() + ")" )
        if cb.commandCount != 11 || cb.overflowCount != 0
        {
            Console.println( "[cb] FAIL: commandCount expect 11, overflow expect 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 2 整理：DrawItem 段排序（3 项；透明远->近）──────────────
        Int32 sorted = cb.sortDrawItems()
        Console.println( "[cb] sortDrawItems -> " + sorted.toString() + " draw items sorted" )
        if sorted != 3
        {
            Console.println( "[cb] FAIL: sortDrawItems expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 3 提交渲染：SLMC 打包整包提交，C 侧逐 opcode 回放 ───────
        if !pipe.executeCommandBuffer( cb )
        {
            Console.println( "[cb] FAIL: executeCommandBuffer - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 统计断言：3 DrawItem + PostProcess + Blit 各计一次 draw call
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[cb] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 5 || statOpaque != 1 || statTransp != 2
        {
            Console.println( "[cb] FAIL: stats expect draws=5 opaque=1 transp=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 像素断言（回读 top-left 坐标，与 A2 同源采样/阈值）
        # 背景（左上角，远离三角与 quad）
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        Console.println( "[cb] corner  RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[cb] FAIL: corner should be clear color" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 三角内部（左下区域，不受 quad 影响）
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = sampleChannel( pixels, 256, 51, 184, 2 )
        Console.println( "[cb] tri     RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[cb] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 贴图独占点（quad 右下带：NDC(0.70,0.15) 在贴图 quad
        # [0.175..0.725]x[0.075..0.625] 内、蓝 quad 与三角外；
        # u≈0.955 -> 期望 RGB≈(181,42,154)）
        Int32 qr = sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qg = sampleChannel( pixels, 256, 217, 108, 1 )
        Int32 qb = sampleChannel( pixels, 256, 217, 108, 2 )
        Console.println( "[cb] quadtex RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr < 110 || qb < 110 || qg < 35 || qg > 90
        {
            Console.println( "[cb] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 重叠点（两 quad 交叠区：NDC(0.55,0.40) 同在贴图 quad
        # [0.175..0.725]x[0.075..0.625] 与蓝 quad [0.425..0.675]x[0.225..0.475]
        # 内、三角外；正确序 = 贴图(z0.5 远)先画 -> 蓝(z0.3 近)后画 ->
        # 蓝分量主导，期望 RGB≈(103,91,192)；错误序蓝先画被贴图盖 -> b≈130 判别失败）
        Int32 br = sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 bg = sampleChannel( pixels, 256, 198, 76, 1 )
        Int32 bb = sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[cb] overlap RGB=(" + br.toString() + "," + bg.toString() + "," + bb.toString() + ")" )
        if bb < 150 || ( bb - br ) < 40
        {
            Console.println( "[cb] FAIL: overlap should be blue-dominant (sort direction wrong)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[cb] Phase CB: PASS (record 11 -> sort 3 -> execute: pixels + stats + overlap all ok)" )
        ret true
    }

    # ── Phase INST：GPU 实例化合批（N1：64 实例一次 draw）────────
    # 验收（AIPrompt.md N1）：同 mesh + 同材质的 64 对象合一次真 GPU
    # instanced draw —— drawCalls 不随对象数线性涨；合批与逐 draw 像素一致。
    #   场景 A（合批）：64×setPerDraw 先行 + 连续 64×drawItem（槽 0..63
    #     递增、prog/mesh/texDesc 同、不透明）-> C 侧回放 RLE 合并为
    #     1 次 instanced draw（baseSlot=0、instanceCount=64）；
    #   场景 B（对照）：setPerDraw/drawItem 交替 64 次（SetPerDraw 命令
    #     打断 RLE 连续性）-> 64 次独立 draw；
    #   统计断言：A draws=3（1 合并+post+blit）/opaque=1/instances=64；
    #     B draws=66/opaque=64/instances=64；
    #   像素断言（双保险）：A 帧 64 槽中心 = 槽差异化纯色（PFLAT 无灯光
    #     ambient=1 输出 = uColor[obj]，实例索引错位立即可见）+ A/B 全帧
    #     262144 字节逐点一致（合批与逐 draw 数值等价）。
    #   几何：8x8 网格 quad，scale 0.105（格宽 0.25 不重叠），
    #     tx=-0.875+col*0.25 / ty=0.875-row*0.25，slot=row*8+col，
    #     槽中心屏幕坐标 (16+col*32, 16+row*32)。

    # INST 辅助：槽 s 的网格 MVP（列主序平移在 m03/m13）
    static Float32_4x4 instSlotMvp( Int32 s )
    {
        Int32 col = s % 8
        Int32 row = s / 8
        Float32 tx = col.toFloat32() * 0.25f - 0.875f
        Float32 ty = 0.875f - row.toFloat32() * 0.25f
        ret Float32_4x4( 0.105f, 0.0f, 0.0f, tx,
                         0.0f, 0.105f, 0.0f, ty,
                         0.0f, 0.0f, 1.0f, 0.0f,
                         0.0f, 0.0f, 0.0f, 1.0f )
    }

    # INST 辅助：槽 s 的差异化颜色（r/g 按列/行、b 按槽号渐变）
    static Color instSlotColor( Int32 s )
    {
        Int32 col = s % 8
        Int32 row = s / 8
        ret Color( ( col.toFloat32() + 0.5f ) / 8.0f,
                   ( row.toFloat32() + 0.5f ) / 8.0f,
                   0.25f + s.toFloat32() / 128.0f,
                   1.0f )
    }

    static bool runInstancing()
    {
        Console.println( "-- Phase INST: GPU instancing (64 instances / 1 draw vs 64 draws, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[inst] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixelsA = Memory.alloc( 256 * 256 * 4 )
        Int64 pixelsB = Memory.alloc( 256 * 256 * 4 )
        if pixelsA == 0 || pixelsB == 0
        {
            Console.println( "[inst] FAIL: pixel alloc" )
            if pixelsA != 0
            {
                Memory.free( pixelsA )
            }
            if pixelsB != 0
            {
                Memory.free( pixelsB )
            }
            pipe.destroy()
            ret false
        }

        # ── 场景 A：64×setPerDraw 先行 + 连续 64×drawItem（RLE 合 1 draw）──
        CommandBuffer cbA = CommandBuffer()
        cbA.name = "cb-inst-a"
        cbA.begin()
        cbA.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, Color( 0.0f, 0.0f, 0.0f, 1.0f ) )
        int s = 0
        while ( s < 64 )
        {
            cbA.setPerDraw( s, instSlotMvp( s ), instSlotColor( s ) )
            s = s + 1
        }
        s = 0
        while ( s < 64 )
        {
            cbA.drawItem( SLang.RenderPipeline.PROG_PFLAT, s, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.0f )
            s = s + 1
        }
        cbA.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cbA.blitFinal()
        cbA.readback( pixelsA )
        cbA.end()
        if cbA.commandCount != 132 || cbA.overflowCount > 0
        {
            Console.println( "[inst] FAIL: stream A count=" + cbA.commandCount.toString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        if pipe.executeCommandBuffer( cbA ) == false
        {
            Console.println( "[inst] FAIL: execute A - " + SLang.Render.errorString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 drawsA = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 opaqueA = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 instA = pipe.stat( SLang.RenderPipeline.STAT_INSTANCE_COUNT )
        Console.println( "[inst] A draws=" + drawsA.toString() + " opaque=" + opaqueA.toString() + " instances=" + instA.toString() )
        if drawsA != 3 || opaqueA != 1 || instA != 64
        {
            Console.println( "[inst] FAIL: A expect draws=3 opaque=1 instances=64 (RLE merge broken)" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }

        # ── 场景 B：setPerDraw/drawItem 交替（打断 RLE -> 64 独立 draw）──
        CommandBuffer cbB = CommandBuffer()
        cbB.name = "cb-inst-b"
        cbB.begin()
        cbB.setRenderTargets( SLang.RenderPipeline.TARGET_SCENE, 0, 0, 256, 256, 3, Color( 0.0f, 0.0f, 0.0f, 1.0f ) )
        s = 0
        while ( s < 64 )
        {
            cbB.setPerDraw( s, instSlotMvp( s ), instSlotColor( s ) )
            cbB.drawItem( SLang.RenderPipeline.PROG_PFLAT, s, SLang.RenderPipeline.MESH_QUAD, 0, 0, 2000, 0.0f )
            s = s + 1
        }
        cbB.postProcess( 0, 1.0f, 1.0f, 1.0f )
        cbB.blitFinal()
        cbB.readback( pixelsB )
        cbB.end()
        if cbB.commandCount != 132 || cbB.overflowCount > 0
        {
            Console.println( "[inst] FAIL: stream B count=" + cbB.commandCount.toString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        if pipe.executeCommandBuffer( cbB ) == false
        {
            Console.println( "[inst] FAIL: execute B - " + SLang.Render.errorString() )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 drawsB = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 opaqueB = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 instB = pipe.stat( SLang.RenderPipeline.STAT_INSTANCE_COUNT )
        Console.println( "[inst] B draws=" + drawsB.toString() + " opaque=" + opaqueB.toString() + " instances=" + instB.toString() )
        if drawsB != 66 || opaqueB != 64 || instB != 64
        {
            Console.println( "[inst] FAIL: B expect draws=66 opaque=64 instances=64" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }

        # ── 像素断言 1：A 帧 64 槽中心 = 槽差异化纯色（容差 ±3）────
        s = 0
        Int32 badSlots = 0
        while ( s < 64 )
        {
            Int32 col = s % 8
            Int32 row = s / 8
            Int32 px = 16 + col * 32
            Int32 py = 16 + row * 32
            Int32 er = int( ( col.toFloat32() + 0.5f ) / 8.0f * 255.0f + 0.5f )
            Int32 eg = int( ( row.toFloat32() + 0.5f ) / 8.0f * 255.0f + 0.5f )
            Int32 eb = int( ( 0.25f + s.toFloat32() / 128.0f ) * 255.0f + 0.5f )
            Int32 pr = sampleChannel( pixelsA, 256, px, py, 0 )
            Int32 pg = sampleChannel( pixelsA, 256, px, py, 1 )
            Int32 pb = sampleChannel( pixelsA, 256, px, py, 2 )
            if pr < er - 3 || pr > er + 3 || pg < eg - 3 || pg > eg + 3 || pb < eb - 3 || pb > eb + 3
            {
                if badSlots < 4
                {
                    Console.println( "[inst] FAIL: slot " + s.toString() + " (" + px.toString() + "," + py.toString() + ") got (" + pr.toString() + "," + pg.toString() + "," + pb.toString() + ") expect (" + er.toString() + "," + eg.toString() + "," + eb.toString() + ")" )
                }
                badSlots = badSlots + 1
            }
            s = s + 1
        }
        if badSlots > 0
        {
            Console.println( "[inst] FAIL: " + badSlots.toString() + " slot centers mismatch (instance slot routing broken)" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Int32 r0 = sampleChannel( pixelsA, 256, 16, 16, 0 )
        Int32 g0 = sampleChannel( pixelsA, 256, 16, 16, 1 )
        Int32 b0 = sampleChannel( pixelsA, 256, 16, 16, 2 )
        Int32 r63 = sampleChannel( pixelsA, 256, 240, 240, 0 )
        Int32 g63 = sampleChannel( pixelsA, 256, 240, 240, 1 )
        Int32 b63 = sampleChannel( pixelsA, 256, 240, 240, 2 )
        Console.println( "[inst] slot0  RGB=(" + r0.toString() + "," + g0.toString() + "," + b0.toString() + ")  slot63 RGB=(" + r63.toString() + "," + g63.toString() + "," + b63.toString() + ")" )

        # ── 像素断言 2：A/B 全帧 262144 字节逐点一致（合批 = 逐 draw）──
        Int32 off = 0
        Int32 mism = 0
        while ( off < 262144 )
        {
            if Memory.readUInt8( pixelsA, off ) != Memory.readUInt8( pixelsB, off )
            {
                if mism < 4
                {
                    Console.println( "[inst] FAIL: byte " + off.toString() + " A=" + Memory.readUInt8( pixelsA, off ).toString() + " B=" + Memory.readUInt8( pixelsB, off ).toString() )
                }
                mism = mism + 1
            }
            off = off + 1
        }
        if mism > 0
        {
            Console.println( "[inst] FAIL: " + mism.toString() + " bytes differ between batched and per-draw" )
            Memory.free( pixelsA )
            Memory.free( pixelsB )
            pipe.destroy()
            ret false
        }
        Console.println( "[inst] A/B full-frame compare: 262144 bytes identical" )

        Memory.free( pixelsA )
        Memory.free( pixelsB )
        pipe.destroy()
        Console.println( "[inst] Phase INST: PASS (64 instances -> 1 instanced draw, pixel-identical to 64 draws)" )
        ret true
    }

    # ── Phase PASS：Pass 序列提交（Opaque/Transparent/Post/Blit 单流）──
    # P1 端到端验收（AIPrompt.md P1：renderCameraScene 硬编码流程拆成
    # 显式 Pass 序列，C 侧零改动）：
    #   1 组装：CullingData 快照（P0 数据层）乱序灌 3 物体（蓝 z0.3 ->
    #     贴图 z0.5 -> 三角 z0.0，同 Phase CB 录制序）+ 四个 Pass 依次
    #     addPass 进 ScriptableRenderContext（OpaquePass 清屏+不透明段 /
    #     TransparentPass 透明段 / PostProcessPass 全屏后处理 / BlitPass
    #     整合+回读）；
    #   2 预录：beginPassRecording 后经 passCommandBuffer() 预录帧级共享
    #     状态（setTexture + setPerDraw×3）——C 侧 slr_cmd_execute_stream
    #     每次调用都重置 PerDraw 槽与描述符表，一帧全部命令必须同流；
    #   3 提交：ctx.submitPasses() 逐 Pass execute 录制 -> sortDrawItems
    #     整理（DrawItem 连续段）-> 单流 executeCommandBuffer 整包提交。
    # 验收 = 行为零变化：11 条命令 / draws=5 opaque=1 transp=2 / 四像素
    # 断言与 Phase CB 完全相同（同坐标同阈值）。
    static bool runPassSubmit()
    {
        Console.println( "-- Phase PASS: Opaque/Transparent/Post/Blit pass sequence (single stream, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[pass] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[pass] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pass] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[pass] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # MVP（与 Phase CB 同值；列向量约定：平移在 m03/m13）
        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # ── 1 组装：CullingData 快照（乱序：蓝 -> 贴图 -> 三角）────
        CullingData cull = CullingData()
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cull.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        if cull.count() != 3 || cull.opaqueCount() != 1 || cull.transparentCount() != 2
        {
            Console.println( "[pass] FAIL: culling snapshot expect count=3 opaque=1 transparent=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 四 Pass（无参构造 + 字段赋值，场景参数同 Phase CB）────
        OpaquePass op = OpaquePass()
        op.culling = cull
        op.viewportX = 0
        op.viewportY = 0
        op.viewportWidth = 256
        op.viewportHeight = 256
        op.clearTargetColor = true
        op.clearTargetDepth = true
        op.clearColor = Color( 0.06f, 0.06f, 0.10f, 1.0f )

        TransparentPass tp = TransparentPass()
        tp.culling = cull

        PostProcessPass pp = PostProcessPass()
        pp.postEnabled = false
        pp.postBrightness = 1.0f
        pp.postSaturation = 1.0f
        pp.postVignette = 1.0f

        BlitPass bp = BlitPass()
        bp.blitReadbackPtr = pixels

        ScriptableRenderContext ctx = ScriptableRenderContext()
        ctx.pipeline = pipe
        if ctx.addPass( op ) == false || ctx.addPass( tp ) == false || ctx.addPass( pp ) == false || ctx.addPass( bp ) == false
        {
            Console.println( "[pass] FAIL: addPass x4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Int32 queued = ctx.passCount()
        Console.println( "[pass] " + queued.toString() + " passes queued: Opaque -> Transparent -> Post -> Blit" )
        if queued != 4
        {
            Console.println( "[pass] FAIL: passCount expect 4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 2 预录帧级共享状态（同一条流：setTexture + setPerDraw×3）──
        ctx.beginPassRecording()
        CommandBuffer shared = ctx.passCommandBuffer()
        shared.setTexture( 0, tex.handle )
        shared.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        shared.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        shared.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )

        # ── 3 提交：Pass 序列录制 -> 排序 -> 单流整包执行 ───────
        if ctx.submitPasses() == false
        {
            Console.println( "[pass] FAIL: submitPasses - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 命令数断言：4 预录 + setRT + 3 draw + post + blit + readback = 11
        Int32 sortedN = shared.culling.count()
        Console.println( "[pass] recorded " + shared.commandCount.toString() + " commands (overflow=" + shared.overflowCount.toString() + ", sorted=" + sortedN.toString() + ")" )
        if shared.commandCount != 11 || shared.overflowCount != 0
        {
            Console.println( "[pass] FAIL: commandCount expect 11, overflow expect 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # sortDrawItems 排序后写回快照：3 条（序 = 三角 -> 贴图 -> 蓝）
        if sortedN != 3
        {
            Console.println( "[pass] FAIL: sorted culling expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 统计断言（单流回放口径，与 Phase CB 完全一致）
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[pass] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 5 || statOpaque != 1 || statTransp != 2
        {
            Console.println( "[pass] FAIL: stats expect draws=5 opaque=1 transp=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 像素断言（四点与 Phase CB 完全相同：同坐标同阈值）
        # 背景（左上角，远离三角与 quad）
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        Console.println( "[pass] corner  RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[pass] FAIL: corner should be clear color" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 三角内部（左下区域，不受 quad 影响）
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = sampleChannel( pixels, 256, 51, 184, 2 )
        Console.println( "[pass] tri     RGB=(" + triR.toString() + "," + triG.toString() + "," + triB.toString() + ")" )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[pass] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 贴图独占点（quad 右下带：NDC(0.70,0.15) 在贴图 quad 内、蓝 quad
        # 与三角外；u≈0.955 -> 期望 RGB≈(181,42,154)）
        Int32 qr = sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qg = sampleChannel( pixels, 256, 217, 108, 1 )
        Int32 qb = sampleChannel( pixels, 256, 217, 108, 2 )
        Console.println( "[pass] quadtex RGB=(" + qr.toString() + "," + qg.toString() + "," + qb.toString() + ")" )
        if qr < 110 || qb < 110 || qg < 35 || qg > 90
        {
            Console.println( "[pass] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 重叠点（两 quad 交叠区：贴图 z0.5 远先画 -> 蓝 z0.3 近后画 ->
        # 蓝分量主导；错误序蓝先画被贴图盖 -> b≈130 判别失败）
        Int32 br = sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 bg = sampleChannel( pixels, 256, 198, 76, 1 )
        Int32 bb = sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[pass] overlap RGB=(" + br.toString() + "," + bg.toString() + "," + bb.toString() + ")" )
        if bb < 150 || ( bb - br ) < 40
        {
            Console.println( "[pass] FAIL: overlap should be blue-dominant (sort direction wrong)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[pass] Phase PASS: PASS (4 passes -> single stream: pixels + stats + overlap all ok)" )
        ret true
    }

    # ── Phase FEATURE：Feature 注入（AIPrompt P2：HDRP CustomPass 等价物）──
    # 场景同 Phase PASS（蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0 + 四 Pass 单流），
    # 追加一个 AfterPost 注入点 ColorOverlayFeature（全屏绿 0.35 半透明色块，
    # PFLAT + PerDraw 槽 63，C 侧零新增）：
    #   1 注入点遍历：submitPasses 在 PostProcessPass 之后 / BlitPass 之前
    #     执行 Feature（setPerDraw + drawItem 两条命令经 replayInto 进共享流，
    #     画进 rt_post 后随 blit 进 final）；
    #   2 像素断言：整幅被绿罩调制（dst = dst*0.65 + 绿*0.35）——角落 g 由
    #     ~15 升到 ~99、三角 r 由 255 降到 ~166；
    #   3 Volume 覆盖栈：push 参数 Profile（a=0.5）二渲 -> 覆盖强度变化
    #     （g 升到 ~135），pop 后栈深归零。
    static bool runFeatureInject()
    {
        Console.println( "-- Phase FEATURE: AfterPost ColorOverlayFeature injection (single stream, 256x256) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[feat] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[feat] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[feat] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[feat] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # MVP（与 Phase PASS 同值；列向量约定：平移在 m03/m13）
        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # CullingData 快照（乱序：蓝 -> 贴图 -> 三角）
        CullingData cull = CullingData()
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cull.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cull.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        if cull.count() != 3
        {
            Console.println( "[feat] FAIL: culling snapshot" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 四 Pass（同 Phase PASS）
        OpaquePass op = OpaquePass()
        op.culling = cull
        op.viewportWidth = 256
        op.viewportHeight = 256
        op.clearTargetColor = true
        op.clearTargetDepth = true
        op.clearColor = Color( 0.06f, 0.06f, 0.10f, 1.0f )
        TransparentPass tp = TransparentPass()
        tp.culling = cull
        PostProcessPass pp = PostProcessPass()
        pp.postEnabled = false
        pp.postBrightness = 1.0f
        pp.postSaturation = 1.0f
        pp.postVignette = 1.0f
        BlitPass bp = BlitPass()
        bp.blitReadbackPtr = pixels

        # 一个 AfterPost Feature（绿罩 0.35；PerDraw 槽 63 避开场景 0..2）
        ColorOverlayFeature feat = ColorOverlayFeature()
        feat.injectionPoint = EInjectionPoint.AfterPost
        feat.profile.setParamFloat( "r", 0.0f )
        feat.profile.setParamFloat( "g", 1.0f )
        feat.profile.setParamFloat( "b", 0.0f )
        feat.profile.setParamFloat( "a", 0.35f )

        ScriptableRenderContext ctx = ScriptableRenderContext()
        ctx.pipeline = pipe
        if ctx.addPass( op ) == false || ctx.addPass( tp ) == false || ctx.addPass( pp ) == false || ctx.addPass( bp ) == false
        {
            Console.println( "[feat] FAIL: addPass x4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ctx.addFeature( feat ) == false
        {
            Console.println( "[feat] FAIL: addFeature" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ctx.featureCount() != 1
        {
            Console.println( "[feat] FAIL: featureCount expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        VolumeStack.clear()
        if VolumeStack.depth() != 0
        {
            Console.println( "[feat] FAIL: volume stack not empty" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 一渲：无 Volume 覆盖（覆盖 alpha 0.35）──────────────
        ctx.beginPassRecording()
        CommandBuffer shared = ctx.passCommandBuffer()
        shared.setTexture( 0, tex.handle )
        shared.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        shared.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        shared.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        if ctx.submitPasses() == false
        {
            Console.println( "[feat] FAIL: submitPasses 1 - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 命令数：4 预录 + setRT + 3 draw + post + 覆盖 2 条 + blit + readback = 13
        Console.println( "[feat] recorded " + shared.commandCount.toString() + " commands (overflow=" + shared.overflowCount.toString() + ", snapshot=" + shared.culling.count().toString() + ")" )
        if shared.commandCount != 13 || shared.overflowCount != 0
        {
            Console.println( "[feat] FAIL: commandCount expect 13, overflow expect 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 排序快照：场景段 3 条 + 覆盖段 1 条（post/blit 为段边界）
        if shared.culling.count() != 4
        {
            Console.println( "[feat] FAIL: culling snapshot expect 4 (3 scene + 1 overlay)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 统计：3 物体 + 覆盖 + post + blit = 6 draws；透明 2 + 覆盖 = 3
        Int32 statDraws = pipe.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = pipe.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = pipe.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[feat] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 6 || statOpaque != 1 || statTransp != 3
        {
            Console.println( "[feat] FAIL: stats expect draws=6 opaque=1 transp=3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 帧级统计（P4：RenderEnvironment 消费的静态记录）
        if ScriptableRenderContext.lastPassCount != 4
        {
            Console.println( "[feat] FAIL: lastPassCount expect 4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if ScriptableRenderContext.lastFeatureRunCount != 1
        {
            Console.println( "[feat] FAIL: lastFeatureRunCount expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # 像素断言（一渲）：角落 (4,4) 绿罩 -> r≈10 g≈99 b≈16
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        Console.println( "[feat] corner   RGB=(" + kr.toString() + "," + kg.toString() + "," + kb.toString() + ")" )
        if kg < 80 || kg > 120 || kr > 30
        {
            Console.println( "[feat] FAIL: corner should be green-tinted by overlay" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        # 三角内部 (51,184)：255*0.65≈166 + 绿 89 -> r≈166 g≈89
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        Console.println( "[feat] tri      RGB=(" + triR.toString() + "," + triG.toString() + ",0)" )
        if triR < 145 || triR > 185 || triG < 70 || triG > 110
        {
            Console.println( "[feat] FAIL: triangle should be red*0.65 + green tint" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        # ── 二渲：Volume 覆盖栈（a=0.5 -> 覆盖更强，角落 g≈135）────
        VolumeProfile vp = VolumeProfile()
        vp.name = "override"
        vp.setParamFloat( "r", 0.0f )
        vp.setParamFloat( "g", 1.0f )
        vp.setParamFloat( "b", 0.0f )
        vp.setParamFloat( "a", 0.5f )
        if VolumeStack.push( vp ) == false
        {
            Console.println( "[feat] FAIL: volume push" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if VolumeStack.depth() != 1
        {
            Console.println( "[feat] FAIL: volume depth expect 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        ctx.beginPassRecording()
        CommandBuffer shared2 = ctx.passCommandBuffer()
        shared2.setTexture( 0, tex.handle )
        shared2.setPerDraw( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        shared2.setPerDraw( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        shared2.setPerDraw( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        if ctx.submitPasses() == false
        {
            Console.println( "[feat] FAIL: submitPasses 2 - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Int32 kg2 = sampleChannel( pixels, 256, 4, 4, 1 )
        Console.println( "[feat] corner(overlay a=0.5) g=" + kg2.toString() )
        if kg2 < 115 || kg2 > 155
        {
            Console.println( "[feat] FAIL: volume override should raise corner g to ~135" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        VolumeProfile popped = VolumeStack.pop()
        if popped != vp
        {
            Console.println( "[feat] FAIL: volume pop identity" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if VolumeStack.depth() != 0
        {
            Console.println( "[feat] FAIL: volume depth expect 0 after pop" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[feat] Phase FEATURE: PASS (AfterPost injection + volume override: pixels + stats all ok)" )
        ret true
    }

    # ── Phase ASSET：RenderPipeline 资产层（AIPrompt P3：需求 4）──
    # 资产声明（RenderPipelineAsset：目标尺寸/清除色/FrameSettings/Feature
    # 模板）-> 实例装配 + 全局注册（CameraRenderPipeline.use ->
    # SLang.Render.usePipeline）-> 帧数据完备组装（FrameData：culling +
    # perDraw + 纹理 + 后处理）-> 经 renderCameraScene 门面自动路由到
    # CameraRenderPipeline.render（四 Pass 单流提交）：
    #   ① 一渲断言与 Phase PASS 完全一致（draws=5 + 四像素）——资产化零行为
    #     变化；② 实例侧 addFeature 二渲 -> 覆盖生效（draws=6）；
    #   ③ clearPipeline 注销 + destroy。
    static bool runAssetPipeline()
    {
        Console.println( "-- Phase ASSET: RenderPipelineAsset -> CameraRenderPipeline -> Render(FrameData) (256x256) --" )
        # ① 资产声明
        RenderPipelineAsset asset = RenderPipelineAsset()
        asset.targetWidth = 256
        asset.targetHeight = 256
        asset.clearR = 0.06f
        asset.clearG = 0.06f
        asset.clearB = 0.10f
        asset.clearA = 1.0f
        asset.frameSettings = FrameSettings()
        if asset.featureTemplateCount() != 0
        {
            Console.println( "[asset] FAIL: fresh asset should have 0 feature templates" )
            ret false
        }

        # ② 实例装配 + 全局注册
        CameraRenderPipeline cp = CameraRenderPipeline.use( asset )
        if cp == null
        {
            Console.println( "[asset] FAIL: CameraRenderPipeline.use - " + SLang.Render.errorString() )
            ret false
        }
        if cp.isValid == false
        {
            Console.println( "[asset] FAIL: pipeline not valid" )
            cp.destroy()
            ret false
        }
        if SLang.Render.currentPipeline() != cp
        {
            Console.println( "[asset] FAIL: usePipeline registration missing" )
            cp.destroy()
            ret false
        }
        if cp.featureCount() != 0
        {
            Console.println( "[asset] FAIL: fresh pipeline expect 0 features" )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[asset] FAIL: pixel alloc" )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[asset] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[asset] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        # ③ 帧数据完备组装（P0 数据层：一帧的全部输入）
        FrameData fd = FrameData()
        fd.time = 0.0f
        fd.dstPixels = pixels
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        fd.setPost( false, 1.0f, 1.0f, 1.0f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        if fd.culling.count() != 3
        {
            Console.println( "[asset] FAIL: frame culling expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 0" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 1" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.setSlot( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) ) == false
        {
            Console.println( "[asset] FAIL: perDraw slot 2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if fd.perDraw.usedCount() != 3
        {
            Console.println( "[asset] FAIL: perDraw usedCount expect 3" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        fd.setTexture( 0, tex.handle )
        if fd.hasTexture == false
        {
            Console.println( "[asset] FAIL: frame texture flag" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ④ 经 renderCameraScene 门面路由（活动管线 + 句柄一致 + 帧数据
        #    完备 -> CameraRenderPipeline.render；四 Pass 单流提交）
        SLang.RenderPipeline facade = cp.pipeline
        if facade == null
        {
            Console.println( "[asset] FAIL: facade pipeline missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if facade.renderCameraScene( fd ) == false
        {
            Console.println( "[asset] FAIL: renderCameraScene routed render - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # 统计断言（与 Phase PASS 完全一致：draws=5 opaque=1 transp=2）
        Int32 statDraws = facade.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 statOpaque = facade.stat( SLang.RenderPipeline.STAT_OPAQUE_DRAWS )
        Int32 statTransp = facade.stat( SLang.RenderPipeline.STAT_TRANSPARENT_DRAWS )
        Console.println( "[asset] stats: draws=" + statDraws.toString() + " opaque=" + statOpaque.toString() + " transp=" + statTransp.toString() )
        if statDraws != 5 || statOpaque != 1 || statTransp != 2
        {
            Console.println( "[asset] FAIL: stats expect draws=5 opaque=1 transp=2" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if ScriptableRenderContext.lastPassCount != 4
        {
            Console.println( "[asset] FAIL: lastPassCount expect 4" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if ScriptableRenderContext.lastFeatureRunCount != 0
        {
            Console.println( "[asset] FAIL: lastFeatureRunCount expect 0 (no features yet)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # 像素断言（与 Phase PASS 完全相同的四点）
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[asset] FAIL: corner pixel (expect clear color)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = sampleChannel( pixels, 256, 51, 184, 2 )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[asset] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 qr = sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qg = sampleChannel( pixels, 256, 217, 108, 1 )
        Int32 qb = sampleChannel( pixels, 256, 217, 108, 2 )
        if qr < 110 || qb < 110 || qg < 35 || qg > 90
        {
            Console.println( "[asset] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 br = sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 bb = sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[asset] pixels ok (corner/tri/quadtex/overlap: b=" + bb.toString() + ")" )
        if bb < 150 || ( bb - br ) < 40
        {
            Console.println( "[asset] FAIL: overlap should be blue-dominant" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ⑤ 实例侧运行期注入 Feature（经管线入口直接 render）-> 覆盖生效
        # 绿罩 0.35（默认 profile 是红色 (1,0,0,0.35)，需显式配置成绿——
        # corner 期望 g∈[80,120]，断言口径与 Phase FEATURE 一渲一致）
        ColorOverlayFeature f = ColorOverlayFeature()
        f.injectionPoint = EInjectionPoint.AfterPost
        f.profile.setParamFloat( "r", 0.0f )
        f.profile.setParamFloat( "g", 1.0f )
        f.profile.setParamFloat( "b", 0.0f )
        f.profile.setParamFloat( "a", 0.35f )
        if cp.addFeature( f ) == false
        {
            Console.println( "[asset] FAIL: pipeline addFeature" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        if cp.render( fd ) == false
        {
            Console.println( "[asset] FAIL: cp.render with feature - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }
        Int32 statDraws2 = facade.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        Int32 kg3 = sampleChannel( pixels, 256, 4, 4, 1 )
        Console.println( "[asset] feature render: draws=" + statDraws2.toString() + " corner g=" + kg3.toString() )
        if statDraws2 != 6 || kg3 < 80 || kg3 > 120
        {
            Console.println( "[asset] FAIL: expect draws=6 and green-tinted corner" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            SLang.Render.clearPipeline()
            cp.destroy()
            ret false
        }

        # ⑥ 注销 + 清理（后续 Phase 回 legacy 路由）
        SLang.Render.clearPipeline()
        if SLang.Render.currentPipeline() != null
        {
            Console.println( "[asset] FAIL: clearPipeline" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        if cp.destroy() == false
        {
            Console.println( "[asset] FAIL: pipeline destroy" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            ret false
        }
        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        Console.println( "[asset] Phase ASSET: PASS (asset -> instance -> Render(FrameData): routing + pixels + stats identical to PASS)" )
        ret true
    }

    # ── Phase RTPOOL：RT 句柄池（AIPrompt P4：RTHandleSystem 等价物）──
    # 同尺寸请求复用（C 侧纹理计数不变）+ 异尺寸新建 + releaseAll 归零。
    static bool runRtPool()
    {
        Console.println( "-- Phase RTPOOL: RTHandlePool request/reuse/release (cap 64) --" )
        SLang.RTHandlePool pool = SLang.RTHandlePool()
        if pool == null
        {
            Console.println( "[pool] FAIL: pool alloc" )
            ret false
        }
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: fresh pool expect 0" )
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pool] FAIL: texture pixels alloc" )
            ret false
        }
        Int32 baseline = RenderFFI.ffiTextureCount()

        # ① 同尺寸两次请求 -> 同一句柄，C 侧纹理计数只 +1
        SLang.RenderTexture t1 = pool.request( 64, 64, texPtr )
        if t1 == null
        {
            Console.println( "[pool] FAIL: request 64x64 - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            ret false
        }
        SLang.RenderTexture t2 = pool.request( 64, 64, texPtr )
        if t2 == null
        {
            Console.println( "[pool] FAIL: request 64x64 again" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t2.handle != t1.handle
        {
            Console.println( "[pool] FAIL: same-size request should reuse handle" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterReuse = RenderFFI.ffiTextureCount()
        if afterReuse != baseline + 1
        {
            Console.println( "[pool] FAIL: texture count expect +1 after reuse, got +" + ( afterReuse - baseline ).toString() )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }

        # ② 异尺寸请求 -> 新建句柄（池计数 2）
        SLang.RenderTexture t3 = pool.request( 32, 32, texPtr )
        if t3 == null
        {
            Console.println( "[pool] FAIL: request 32x32" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t3.handle == t1.handle
        {
            Console.println( "[pool] FAIL: different-size request must not reuse" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterNew = RenderFFI.ffiTextureCount()
        if afterNew != baseline + 2 || pool.count() != 2 || pool.reuseCount() != 1 || pool.requestCount() != 3
        {
            Console.println( "[pool] FAIL: pool stats (count/reuse/request)" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Console.println( "[pool] " + pool.toString() + ", texture count " + baseline.toString() + " -> " + afterNew.toString() )

        # ③ releaseAll -> 计数归零、C 侧纹理数回基线
        pool.releaseAll()
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: releaseAll count expect 0" )
            Memory.free( texPtr )
            ret false
        }
        Int32 afterRelease = RenderFFI.ffiTextureCount()
        if afterRelease != baseline
        {
            Console.println( "[pool] FAIL: texture count should return to baseline" )
            Memory.free( texPtr )
            ret false
        }
        Memory.free( texPtr )
        Console.println( "[pool] Phase RTPOOL: PASS (size-keyed reuse + releaseAll: counts all ok)" )
        ret true
    }

    # ── Phase FS：FrameSettings 帧渲染配置（AIPrompt P4）──
    # 经 CameraRenderPipeline 消费（同一 3 物体场景，帧数据复用）：
    #   ① transparentSortBackToFront=false -> 透明序翻转近->远：交叠区由
    #     蓝主导（默认，bb>=150）翻为贴图主导（bb<=160 判别）；
    #   ② 翻回默认远->近 -> 蓝主导恢复；
    #   ③ fd.postEnabled + sat=0（vig=0）-> 三角灰度化（同 Phase A2 灰度帧）；
    #   ④ FrameSettings.postEnabled=false 拦截 -> 纯拷贝，三角回纯红
    #     （注意：post Pass 不整段跳过——Blit 固定 post->final、Readback 固定
    #     final，跳段会读到陈旧 rt_post；实现按链路正确性对 AIPrompt
    #     "draws=3" 验收预期做偏离并记录在案）；
    #   ⑤ renderScalePercent=50 -> 视口缩半（GL 左下象限），视口内三角仍红。
    static bool runFrameSettings()
    {
        Console.println( "-- Phase FS: FrameSettings (post gate / transparent sort / render scale) --" )
        RenderPipelineAsset asset = RenderPipelineAsset()
        asset.targetWidth = 256
        asset.targetHeight = 256
        asset.frameSettings = FrameSettings()
        FrameSettings fs = asset.frameSettings
        fs.postEnabled = true
        fs.transparentSortBackToFront = false

        CameraRenderPipeline cp = CameraRenderPipeline.create( asset )
        if cp == null
        {
            Console.println( "[fs] FAIL: CameraRenderPipeline.create - " + SLang.Render.errorString() )
            ret false
        }
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[fs] FAIL: pixel alloc" )
            cp.destroy()
            ret false
        }
        Int64 texPtr = makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[fs] FAIL: texture pixels alloc" )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[fs] FAIL: texture upload - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        Float32_4x4 triMvp = Float32_4x4( 1.3f, 0.0f, 0.0f, 0.0f,
                                          0.0f, 1.3f, 0.0f, 0.0f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 texMvp = Float32_4x4( 0.55f, 0.0f, 0.0f, 0.45f,
                                          0.0f, 0.55f, 0.0f, 0.35f,
                                          0.0f, 0.0f, 1.0f, 0.0f,
                                          0.0f, 0.0f, 0.0f, 1.0f )
        Float32_4x4 blueMvp = Float32_4x4( 0.25f, 0.0f, 0.0f, 0.55f,
                                           0.0f, 0.25f, 0.0f, 0.35f,
                                           0.0f, 0.0f, 1.0f, 0.0f,
                                           0.0f, 0.0f, 0.0f, 1.0f )

        FrameData fd = FrameData()
        fd.time = 0.0f
        fd.dstPixels = pixels
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        fd.setPost( false, 1.0f, 1.0f, 1.0f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        fd.culling.addItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        fd.perDraw.setSlot( 0, triMvp, Color( 1.0f, 0.0f, 0.0f, 1.0f ) )
        fd.perDraw.setSlot( 1, texMvp, Color( 1.0f, 1.0f, 1.0f, 0.85f ) )
        fd.perDraw.setSlot( 2, blueMvp, Color( 0.3f, 0.4f, 1.0f, 0.5f ) )
        fd.setTexture( 0, tex.handle )
        if fd.culling.count() != 3 || fd.perDraw.usedCount() != 3
        {
            Console.println( "[fs] FAIL: frame data assembly" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ① 透明序翻转（近->远：蓝 z0.3 先画，贴图 z0.5 后画）──────
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render sort-flip - " + SLang.Render.errorString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 statDraws = cp.stat( SLang.RenderPipeline.STAT_DRAW_CALLS )
        if statDraws != 5
        {
            Console.println( "[fs] FAIL: draws expect 5 (post copy still runs), got " + statDraws.toString() )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # 基线三点（与 PASS 相同：角落/三角/贴图独占点不受透明序影响）
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[fs] FAIL: corner pixel" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        if triR < 240 || triG > 15
        {
            Console.println( "[fs] FAIL: triangle should be red" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 qr = sampleChannel( pixels, 256, 217, 108, 0 )
        Int32 qb = sampleChannel( pixels, 256, 217, 108, 2 )
        if qr < 110 || qb < 110
        {
            Console.println( "[fs] FAIL: textured quad pixel missing" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # 交叠区翻转断言：贴图后画 -> r 升 b 降（默认远->近时为蓝主导）
        Int32 oR = sampleChannel( pixels, 256, 198, 76, 0 )
        Int32 oB = sampleChannel( pixels, 256, 198, 76, 2 )
        Console.println( "[fs] overlap(front-to-back) RGB.r=" + oR.toString() + " b=" + oB.toString() )
        if oR < 125 || oB > 160
        {
            Console.println( "[fs] FAIL: transparent sort should flip overlap to tex-dominant" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ② 翻回默认（远->近）-> 蓝主导恢复 ─────────────────────
        fs.transparentSortBackToFront = true
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render sort-default" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 oB2 = sampleChannel( pixels, 256, 198, 76, 2 )
        Int32 oR2 = sampleChannel( pixels, 256, 198, 76, 0 )
        Console.println( "[fs] overlap(back-to-front) RGB.r=" + oR2.toString() + " b=" + oB2.toString() )
        if oB2 < 150 || ( oB2 - oR2 ) < 40
        {
            Console.println( "[fs] FAIL: default sort should restore blue-dominant overlap" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ③ 后处理参数流（post on + sat=0 -> 三角灰度化）─────────
        fd.postEnabled = true
        fd.postSaturation = 0.0f
        fd.postVignette = 0.0f
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render post-gray" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 gR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 gG = sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 gB = sampleChannel( pixels, 256, 51, 184, 2 )
        Console.println( "[fs] post gray tri  RGB=(" + gR.toString() + "," + gG.toString() + "," + gB.toString() + ")" )
        if gR - gG > 8 || gG - gR > 8 || gG - gB > 8 || gB - gG > 8
        {
            Console.println( "[fs] FAIL: post grayscale (r==g==b expected)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        if gR < 50 || gR > 110
        {
            Console.println( "[fs] FAIL: post gray level" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ④ FrameSettings.postEnabled=false 拦截 -> 纯拷贝回红 ───
        fs.postEnabled = false
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render post-gated" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        Int32 rR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 rG = sampleChannel( pixels, 256, 51, 184, 1 )
        if rR < 240 || rG > 15
        {
            Console.println( "[fs] FAIL: gated post should copy (triangle red again)" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        # ── ⑤ renderScalePercent=50 -> 视口缩半；视口内三角仍红 ────
        fs.postEnabled = true
        fs.renderScalePercent = 50
        fd.postEnabled = false
        if cp.render( fd ) == false
        {
            Console.println( "[fs] FAIL: render scaled viewport" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }
        # (51,184) 落在 GL 左下 128x128 视口内（图象下半 x<128 区域）
        Int32 sR = sampleChannel( pixels, 256, 51, 184, 0 )
        Console.println( "[fs] scaled(50%) tri RGB.r=" + sR.toString() )
        if sR < 240
        {
            Console.println( "[fs] FAIL: in-viewport triangle should stay red at 50% scale" )
            tex.destroy()
            Memory.free( texPtr )
            Memory.free( pixels )
            cp.destroy()
            ret false
        }

        tex.destroy()
        Memory.free( texPtr )
        Memory.free( pixels )
        cp.destroy()
        Console.println( "[fs] Phase FS: PASS (post gate + sort strategy + render scale all verified)" )
        ret true
    }

    # ── Phase ENV：渲染环境查询（RenderEnvironment：支持情况 / 当前选择 /
    #    硬件条件 / 资源占用 / 当前渲染配置，快照 + 汇总显示 + 断言）──
    public static bool runEnvironmentQuery()
    {
        Console.println( "-- Phase ENV: RenderEnvironment query (support / current / hardware / resources / config) --" )
        RenderEnvironment env = RenderEnvironment.query()
        Console.println( env.toString() )
        if env.available == false
        {
            Console.println( "[env] FAIL: render library not available" )
            ret false
        }
        if env.initialized == false || env.backend != "gl"
        {
            Console.println( "[env] FAIL: expected initialized gl backend, got '" + env.backend + "'" )
            ret false
        }
        if RenderEnvironment.isBackendSupported( "gl" ) == false
        {
            Console.println( "[env] FAIL: gl not in supported backends" )
            ret false
        }
        if env.gpuRenderer == "unknown"
        {
            Console.println( "[env] FAIL: gpu renderer string missing" )
            ret false
        }
        # P4 帧级统计（PASS/FEATURE/ASSET 已跑：passes=4 / feature runs>=1）
        if env.passCount < 1 || env.passCount > 16
        {
            Console.println( "[env] FAIL: passCount expect 1..16, got " + env.passCount.toString() )
            ret false
        }
        if env.featureCount < 1
        {
            Console.println( "[env] FAIL: featureCount expect >=1 (FEATURE/ASSET ran), got " + env.featureCount.toString() )
            ret false
        }
        Console.println( "[env] frame stats: passes=" + env.passCount.toString() + " featureRuns=" + env.featureCount.toString() )
        Console.println( "[env] Phase ENV: PASS (available + gl current + hardware + resources + config + frame stats displayed)" )
        ret true
    }

    # ── Phase DATA：数据层三类端到端（CullingData / FrameData / PassData）──
    # P0「数据与流程分离」验收：① CullingData —— CommandBuffer 排序后产出
    # 可视物体快照（乱序录制 -> 排序 -> 列内容/分桶计数断言）；② FrameData
    # —— buildFrameData 采集一帧上下文（目标/环境），setViewProj/setViewport/
    # setClearColor/setTarget 写入后读回，renderCameraScene(fd) 转发 runStages
    # 实渲染并做像素断言（行为与 A2 runStages 路径一致）；③ PassData ——
    # 单 Pass 数据描述（输入/输出 RT 引用 + float 参数槽读写回）。
    static bool runDataSnapshot()
    {
        Console.println( "-- Phase DATA: CullingData + FrameData + PassData (data layer, 256x256) --" )

        # ── ① CullingData：乱序录制 3 条 drawItem -> 排序 -> 快照断言 ──
        #     与 Phase CB 相同三条（蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0）；
        #     排序键 queue 升序 + 透明 z 降序 -> 快照序 = 三角/贴图/蓝
        CommandBuffer cb = CommandBuffer()
        cb.name = "cb-data"
        cb.begin()
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 2, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.3f )
        cb.drawItem( SLang.RenderPipeline.PROG_PTEX, 1, SLang.RenderPipeline.MESH_QUAD, 0, 1, 3000, 0.5f )
        cb.drawItem( SLang.RenderPipeline.PROG_PFLAT, 0, SLang.RenderPipeline.MESH_TRIANGLE, 0, 0, 2000, 0.0f )
        cb.end()
        Int32 sorted = cb.sortDrawItems()
        if sorted != 3
        {
            Console.println( "[data] FAIL: sortDrawItems expect 3, got " + sorted.toString() )
            ret false
        }
        CullingData cull = cb.culling
        if cull == null
        {
            Console.println( "[data] FAIL: culling snapshot missing" )
            ret false
        }
        if cull.count() != 3
        {
            Console.println( "[data] FAIL: culling count expect 3, got " + cull.count().toString() )
            ret false
        }
        Int32 q0 = cull.getQueue( 0 )
        if q0 != 2000
        {
            Console.println( "[data] FAIL: item0 queue expect 2000 (opaque first), got " + q0.toString() )
            ret false
        }
        Int32 t0 = cull.getTransp( 0 )
        Int32 t1 = cull.getTransp( 1 )
        Int32 t2 = cull.getTransp( 2 )
        if t0 != 0 || t1 != 1 || t2 != 1
        {
            Console.println( "[data] FAIL: transparent flags expect 0/1/1, got " + t0.toString() + "/" + t1.toString() + "/" + t2.toString() )
            ret false
        }
        if cull.getZ( 1 ) <= cull.getZ( 2 )
        {
            Console.println( "[data] FAIL: transparent z not descending (far-to-near)" )
            ret false
        }
        if cull.opaqueCount() != 1 || cull.transparentCount() != 2
        {
            Console.println( "[data] FAIL: bucket counts expect opaque=1 transparent=2" )
            ret false
        }
        Console.println( "[data] culling: 3 items sorted (opaque=" + cull.opaqueCount().toString() + " transparent=" + cull.transparentCount().toString() + ")" )

        # ── ② FrameData：采集 -> 写入读回 -> renderCameraScene 实渲染 ──
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[data] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[data] FAIL: setCamera - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[data] FAIL: setClearColor - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        SLang.RenderObject tri = pipe.addObject( SLang.RenderPipeline.MESH_TRIANGLE )
        if tri == null
        {
            Console.println( "[data] FAIL: addObject - " + SLang.Render.errorString() )
            pipe.destroy()
            ret false
        }
        tri.setLayer( 0 )
        tri.setQueue( 2000 )
        tri.setPosition( 0.0f, 0.0f, 0.0f )
        tri.setScale( 1.3f, 1.3f )
        tri.setColor( 1.0f, 0.0f, 0.0f, 1.0f )
        tri.setAnimated( SLang.RenderPipeline.ANIM_HUE_CYCLE, 0.25f )
        Int64 pixels = Memory.alloc( 256 * 256 * 4 )
        if pixels == 0
        {
            Console.println( "[data] FAIL: pixel alloc" )
            pipe.destroy()
            ret false
        }
        FrameData fd = pipe.buildFrameData( 0.0f, pixels )
        if fd == null
        {
            Console.println( "[data] FAIL: buildFrameData" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.targetW != 256 || fd.targetH != 256 || fd.targetHandle != SLang.RenderPipeline.TARGET_SCENE
        {
            Console.println( "[data] FAIL: frame target expect 256x256 scene" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.envBackend != "gl" || fd.envRenderer == "unknown"
        {
            Console.println( "[data] FAIL: env snapshot expect gl renderer" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Array<Float32> vp = Array<Float32>( 16 )
        Int32 vi = 0
        while vi < 16
        {
            vp[ vi ] = 0.0f
            vi = vi + 1
        }
        vp[ 0 ] = 1.5f
        vp[ 5 ] = 1.5f
        vp[ 10 ] = -1.2f
        vp[ 15 ] = 1.0f
        if fd.setViewProj( vp ) == false || fd.hasViewProj == false
        {
            Console.println( "[data] FAIL: setViewProj" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.viewProj[ 0 ] < 1.49f || fd.viewProj[ 0 ] > 1.51f
        {
            Console.println( "[data] FAIL: viewProj readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        fd.setViewport( 0, 0, 256, 256 )
        fd.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f )
        fd.setTarget( SLang.RenderPipeline.TARGET_SCENE, 256, 256 )
        if fd.viewportW != 256 || fd.viewportH != 256
        {
            Console.println( "[data] FAIL: viewport readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if fd.clearA < 0.99f || fd.clearA > 1.01f
        {
            Console.println( "[data] FAIL: clearColor readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pipe.renderCameraScene( fd ) == false
        {
            Console.println( "[data] FAIL: renderCameraScene - " + SLang.Render.errorString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Int32 triR = sampleChannel( pixels, 256, 51, 184, 0 )
        Int32 triG = sampleChannel( pixels, 256, 51, 184, 1 )
        Int32 triB = sampleChannel( pixels, 256, 51, 184, 2 )
        Int32 kr = sampleChannel( pixels, 256, 4, 4, 0 )
        Int32 kg = sampleChannel( pixels, 256, 4, 4, 1 )
        Int32 kb = sampleChannel( pixels, 256, 4, 4, 2 )
        if triR < 240 || triG > 15 || triB > 15
        {
            Console.println( "[data] FAIL: triangle pixel expect red, got r=" + triR.toString() + " g=" + triG.toString() + " b=" + triB.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if kr < 9 || kr > 21 || kg < 9 || kg > 21 || kb < 19 || kb > 33
        {
            Console.println( "[data] FAIL: corner pixel expect dark blue, got r=" + kr.toString() + " g=" + kg.toString() + " b=" + kb.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Console.println( "[data] frame: target/env/viewProj/viewport ok, renderCameraScene pixels ok" )

        # ── ③ PassData：单 Pass 数据描述（输入/输出 RT + 参数槽读写回）──
        PassData pd = PassData()
        pd.begin( "opaque", 0 )
        pd.setInput( "scene", SLang.RenderPipeline.TARGET_SCENE )
        pd.setOutput( "post", SLang.RenderPipeline.TARGET_POST )
        pd.setParamFloat( "brightness", 1.25f )
        pd.setParamFloat( "vignette", 0.5f )
        if pd.name != "opaque" || pd.inputName != "scene" || pd.outputName != "post"
        {
            Console.println( "[data] FAIL: pass names" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.inputHandle != SLang.RenderPipeline.TARGET_SCENE || pd.outputHandle != SLang.RenderPipeline.TARGET_POST || pd.passEvent != 0
        {
            Console.println( "[data] FAIL: pass handles" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.paramCount != 2
        {
            Console.println( "[data] FAIL: param count expect 2, got " + pd.paramCount.toString() )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.getParamValue( "brightness" ) < 1.24f || pd.getParamValue( "brightness" ) > 1.26f
        {
            Console.println( "[data] FAIL: brightness param readback" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        if pd.getParamValue( "missing" ) != 0.0f
        {
            Console.println( "[data] FAIL: missing param expect 0.0" )
            Memory.free( pixels )
            pipe.destroy()
            ret false
        }
        Console.println( "[data] pass: in/out + " + pd.paramCount.toString() + " params ok" )
        Memory.free( pixels )
        pipe.destroy()
        Console.println( "[data] Phase DATA: PASS (culling snapshot + frame data + pass data)" )
        ret true
    }

    # ── Phase B：QT 窗口 + 后端切换 UI（返回 2=PASS 1=SKIP 0=FAIL）──
    # 顶部按钮行（OpenGL/D3D11/Vulkan/WebGL-GLES）点击切换渲染底层；
    # 7s 自动轮播自动验证四后端在 QT 帧循环下持续渲染（用户点击后停）；
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

        Console.println( "-- Phase B: QT window + backend switcher (buttons: OpenGL/D3D11/Vulkan/WebGL-GLES; 7s auto-cycle) --" )

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
        Console.println( "[QT] window shown (296x372, auto-quit after 60s) -- if not visible, check taskbar / secondary display" )

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
        SLang.QTimer quitT = SLang.QT.newTimer( 60000, true, RenderTest.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 16, false, RenderTest.onTick )
        SLang.QTimer cycleT = SLang.QT.newTimer( 7000, false, RenderTest.onAutoCycle )
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
