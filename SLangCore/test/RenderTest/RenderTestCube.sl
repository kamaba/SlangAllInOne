import SLangRender;
import SLangAudio;
import Math;
import Std;

# Phase C：3D 旋转细分立方体（Mesh 数学层 + RHI 动态网格 + 材质门面）：
#   makeComplexCubeMesh 复用 Mesh.cube 面表双线性插值出每面 2x2 子块
#   （5 实体面 80 顶点 120 索引，f/-Y 底面留空可透视内部，e/+Y 顶面
#   alpha 0.45 半透）-> updateCube 每帧 CPU 旋转 + 手工透视除法 ->
#   NDC 三角形列表（painter 平均深度降序）-> uploadMesh(slot 0) 重传；
#   makeCubeAtlas 六面图集 + makeFaceMaterial 材质门面逐面串联。
#   共享 _pipe 经 RenderTest._pipe 引用（跨类静态字段）
public class RenderTestCube
{

    # ── Phase C：立方体状态（跨类读写经 RenderTestCube.*）─────────
    public static SLang.Mesh _cubeMesh = null          # 细分立方体：5 面各 2x2 = 80 顶点 120 索引
    public static SLang.RenderObject _cubeObj = null   # meshKind=4（动态网格槽 0）
    public static Int64 _cubeVerts = 0                 # 120 顶点 * 16B 显存暂存（帧间复用）
    public static Int32 _cubeFirst = 0                 # 首帧 uploadMesh 结果打印标志
    public static Int32 _cubeErr = 0                   # N3 诊断：uploadMesh 失败信息（每后端打印一次）
    # UV 不建表：vi/16=面、(vi%16)/4=子块、vi%4=角点 -> 图集 cell（updateCube 现场计算）

    # ── Phase C：立方体每帧更新（CPU 变换 + 动态网格上传）─────────
    # 流水线：Mesh.cube 顶点 -> rotationY/X(t) 旋转 -> 手工透视除法
    # （相机 -Z 朝 +Z：dist = z + 2.6，焦距 f = 1.7）-> NDC 顶点 ->
    # 12 三角形按平均深度降序排（远先画保遮挡）-> 三角形列表展开为
    # pos2+uv2 交错（stride 16B）-> Memory.writeF32 填 _cubeVerts ->
    # pipe.uploadMesh(0) 整块重传（GL/GLES/D3D11 重传 / VK 直写）。
    public static bool updateCube( Float32 t )
    {
        if RenderTest._pipe == null
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
        if RenderTest._pipe.uploadMesh( 0, _cubeVerts, vout )
        {
            ret true
        }
        if _cubeErr == 0
        {
            _cubeErr = 1
            # errorString 先取（任何后续原生调用会清错误）
            string err = SLang.Render.errorString()
            Console.println( "[cube] uploadMesh FAILED on " + SLang.Render.currentBackend() + " - " + err + " (verts=" + vout.toString() + ")" )
        }
        ret false
    }

    # ── Phase C：细分立方体网格（每面 2x2 子块，f 底面留空）──────────
    # 复用 Mesh.cube 的面表角序：a..f = +Z/-Z/+X/-X/+Y/-Y，每面 4 角点
    # 双线性插值出 2x2 子方块（4 子块 x 4 角点）；f 面（face 5，-Y 底面）
    # 跳过几何 —— 旋转时透过空面可见立方体内部。顶点布局 face-major：
    # face = vi/16、sub = (vi%16)/4、corner = vi%4（updateCube 据此推 UV）。
    # 产出：5 面 x 20 子块角点 = 80 顶点、40 三角形 120 索引、面法线。


    # ── Phase C：细分立方体网格（每面 2x2 子块，f 底面留空）──────────
    # 复用 Mesh.cube 的面表角序：a..f = +Z/-Z/+X/-X/+Y/-Y，每面 4 角点
    # 双线性插值出 2x2 子方块（4 子块 x 4 角点）；f 面（face 5，-Y 底面）
    # 跳过几何 —— 旋转时透过空面可见立方体内部。顶点布局 face-major：
    # face = vi/16、sub = (vi%16)/4、corner = vi%4（updateCube 据此推 UV）。
    # 产出：5 面 x 20 子块角点 = 80 顶点、40 三角形 120 索引、面法线。
    public static SLang.Mesh makeComplexCubeMesh( Float32 size )
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


    # 字母位图取位：5bit 行值，x=0 取最高位（最左列）
    public static Int32 glyphBit( Int32 rowBits, Int32 x )
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


    # ── Phase C：六面图集（Texture 门面类逐像素构建）──────────────────
    # 192x128 = 3x2 cell（每 cell 64x64），face -> col=face%3、row=face/3：
    # a 红 / b 绿 / c 蓝 / d 琥珀 不透明；e 白青 alpha 0.45（透明面）；
    # f 暗色 alpha 0（空面，无几何引用）。每 cell：2x2 象限明暗棋盘
    # （与几何子块对应）+ 中心 1px 十字暗线 + 居中 5x5 位图字母（x6
    # 缩放）。字母按渲染方向垂直翻转写入（v=0 <-> 像素 y=0 <-> 面底部）。
    public static Texture makeCubeAtlas()
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
                    if glyphBit( gl[ face * 5 + gy ], gx ) == 1
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


    # 单面材质门面：颜色取图集 cell 中心采样，e 面（face 4）透明化
    public static Material makeFaceMaterial( Shader sh, Texture atlas, Int32 face, string name )
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
}
