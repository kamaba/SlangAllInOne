import Core;
import Std;
import Math;
import SLangRender;
# ============================================================================
# FairyGUI 包加载层（XML 包 + .fui 二进制包，共用同一套 FairyQuad 渲染层）
# ----------------------------------------------------------------------------
# XML：package.xml（图集 sprite/uvRect/九宫格边距/设计分辨率）+ 组件 XML
#（组层级递归累加绝对坐标）。fui：FairyGUI 风格精简二进制（无字符串表），
# 布局见 loadFui 注释。文本元素映射为图集白块占位（kind=2）。
# ============================================================================
public class FairyPackage
{
    public string name = ""
    public Int32 designW = 480
    public Int32 designH = 480
    public SLang.RenderTexture texture = null
    public string lastError = ""
    public List<FairySprite> sprites = List<FairySprite>( 8 )
    public List<FairyQuad> quads = List<FairyQuad>( 16 )
    # 动态 quad 配套（2026-11-19 SnakeGame）：quad 原始位置（quadSetHidden
    # 恢复用）；与 quads 平行增长。addQuad 追加的动态 quad home 记 (-9999,0)。
    List<Float32> homeXs = List<Float32>( 0 )
    List<Float32> homeYs = List<Float32>( 0 )
    # ── 多纹理基建（2026-11-19 FairyGUI v2：Loader/Graph/Go3D）────
    # texIndex 0 = 包图集（this.texture）；≥1 = extra 句柄（loader 文件
    # 装载 / graph 纯色小纹理 / go3d 运行时更新纹理）。**存 Int64 句柄**
    #（泛型 List<SLang.RenderTexture> 跨模块类型参数不可用）。上限 7 组
    #（渲染槽 7..13，SLR_CUSTOM_MESHES=10）。
    List<Int64> texHandles = List<Int64>( 0 )
    Array<Int32> texWidths = null
    Array<Int32> texHeights = null
    Int32 texCount = 0
    List<string> texNames = List<string>( 0 )
    string pkgDir = ""

    public void _init_()
    {
        this.sprites = List<FairySprite>( 8 )
        this.quads = List<FairyQuad>( 16 )
        this.homeXs = List<Float32>( 0 )
        this.homeYs = List<Float32>( 0 )
        this.texHandles = List<Int64>( 0 )
        this.texWidths = Array<Int32>( 8 )
        this.texHeights = Array<Int32>( 8 )
        this.texNames = List<string>( 0 )
    }

    public FairySprite findSprite( string nm )
    {
        Int32 i = 0
        while i < this.sprites.length
        {
            FairySprite s = this.sprites[i]
            if s.name == nm
            {
                ret s
            }
            i = i + 1
        }
        ret null
    }

    public bool load( string dir )
    {
        this.lastError = ""
        this.sprites.clear()
        this.quads.clear()
        this.texHandles.clear()
        this.texNames.clear()
        this.texCount = 0
        this.pkgDir = dir
        string pkgPath = dir + "/package.xml"
        Text.Xml px = Text.Xml.load( pkgPath )
        TreeNode<string> root = px.root
        if root == null
        {
            this.lastError = "package.xml missing or invalid: " + pkgPath
            ret false
        }
        this.name = FairySprite.attr( root, "name" )
        TreeNode<string> atlas = root.childByName( "atlas" )
        if atlas == null
        {
            this.lastError = "atlas element missing"
            ret false
        }
        Int32 aw = FairySprite.attrI( atlas, "width" )
        Int32 ah = FairySprite.attrI( atlas, "height" )
        if aw <= 0 || ah <= 0
        {
            this.lastError = "atlas size invalid"
            ret false
        }
        Float32 awf = aw.toFloat32()
        Float32 ahf = ah.toFloat32()
        Int32 si = 0
        while si < atlas.childCount
        {
            TreeNode<string> sn = atlas.childAt( si )
            si = si + 1
            if sn == null || sn._name != "sprite"
            {
                continue
            }
            FairySprite fs = FairySprite()
            fs.name = FairySprite.attr( sn, "name" )
            fs.x = FairySprite.attrF( sn, "x" )
            fs.y = FairySprite.attrF( sn, "y" )
            fs.w = FairySprite.attrF( sn, "w" )
            fs.h = FairySprite.attrF( sn, "h" )
            fs.u0 = fs.x / awf
            fs.u1 = ( fs.x + fs.w ) / awf
            fs.vTop = 1.0f - fs.y / ahf
            fs.vBot = 1.0f - ( fs.y + fs.h ) / ahf
            fs.setBorders( FairySprite.attr( sn, "scale9" ) )
            this.sprites.add( fs )
        }
        string imageFile = FairySprite.attr( atlas, "file" )
        string texPath = dir + "/" + imageFile
        this.texture = SLang.RenderTexture.loadFile( texPath )
        if this.texture == null
        {
            this.lastError = "atlas texture load failed: " + texPath
            ret false
        }
        TreeNode<string> comps = root.childByName( "components" )
        TreeNode<string> comp = null
        if comps != null
        {
            comp = comps.childByName( "component" )
        }
        if comp == null
        {
            comp = root.childByName( "component" )
        }
        if comp == null
        {
            this.lastError = "component element missing"
            ret false
        }
        string compPath = dir + "/" + FairySprite.attr( comp, "file" )
        Text.Xml cx = Text.Xml.load( compPath )
        TreeNode<string> croot = cx.root
        if croot == null
        {
            this.lastError = "component xml invalid: " + compPath
            ret false
        }
        Int32 dw = FairySprite.attrI( root, "designWidth" )
        Int32 dh = FairySprite.attrI( root, "designHeight" )
        if dw <= 0
        {
            dw = FairySprite.attrI( croot, "width" )
        }
        if dh <= 0
        {
            dh = FairySprite.attrI( croot, "height" )
        }
        this.designW = dw
        this.designH = dh
        this.parseChildren( croot, 0.0f, 0.0f )
        ret true
    }

    # ── .fui 二进制包（与 XML 共用同一套 FairyQuad/渲染层）────
    # 小端布局（FairyGUI 风格精简子集，无字符串表）：
    #   magic 'FUI\\0'(4) version:i32(1) designW:i32 designH:i32
    #   atlasW:i32 atlasH:i32
    #   spriteCount:i32 + 每 sprite 8×f32(x,y,w,h,l,t,r,b) + 4B 保留
    #   quadCount:i32 + 每 quad: kind:i32 x:f32 y:f32 w:f32 h:f32
    #     spriteIndex:i32(-1 = 用 white) scale9:i32
    # 图集 PNG 约定与 XML 包同目录同名 atlas@ui.png。
    public bool loadFui( string dir )
    {
        this.lastError = ""
        this.sprites.clear()
        this.quads.clear()
        string path = dir + "/Demo.fui"
        if !File.exists( path )
        {
            this.lastError = "fui package missing: " + path
            ret false
        }
        UInt8Array raw = File.readAllBytes( path )
        Int32 n = raw.length
        if n < 24
        {
            this.lastError = "fui package too small"
            ret false
        }
        Int64 ptr = Memory.alloc( n )
        if ptr == 0
        {
            this.lastError = "fui buffer alloc failed"
            ret false
        }
        Int32 i = 0
        while i < n
        {
            Memory.writeI8( ptr, i, raw[i].toInt32() )
            i = i + 1
        }
        if Memory.readUInt8( ptr, 0 ) != 70 || Memory.readUInt8( ptr, 1 ) != 85
            || Memory.readUInt8( ptr, 2 ) != 73 || Memory.readUInt8( ptr, 3 ) != 0
        {
            Memory.free( ptr )
            this.lastError = "fui bad magic"
            ret false
        }
        Int32 version = Memory.readInt32( ptr, 4 )
        if version != 1
        {
            Memory.free( ptr )
            this.lastError = "fui unsupported version"
            ret false
        }
        this.name = "Demo"
        this.designW = Memory.readInt32( ptr, 8 )
        this.designH = Memory.readInt32( ptr, 12 )
        Int32 atlasW = Memory.readInt32( ptr, 16 )
        Int32 atlasH = Memory.readInt32( ptr, 20 )
        if atlasW <= 0 || atlasH <= 0
        {
            Memory.free( ptr )
            this.lastError = "fui bad atlas size"
            ret false
        }
        Float32 atw = atlasW.toFloat32()
        Float32 ath = atlasH.toFloat32()
        Int32 off = 24
        Int32 sc = Memory.readInt32( ptr, off )
        off = off + 4
        i = 0
        while i < sc
        {
            if off + 36 > n
            {
                Memory.free( ptr )
                this.lastError = "fui sprite table truncated"
                ret false
            }
            FairySprite fs = FairySprite()
            fs.x = Memory.readFloat32( ptr, off + 0 )
            fs.y = Memory.readFloat32( ptr, off + 4 )
            fs.w = Memory.readFloat32( ptr, off + 8 )
            fs.h = Memory.readFloat32( ptr, off + 12 )
            fs.bl = Memory.readFloat32( ptr, off + 16 )
            fs.bt = Memory.readFloat32( ptr, off + 20 )
            fs.br = Memory.readFloat32( ptr, off + 24 )
            fs.bb = Memory.readFloat32( ptr, off + 28 )
            fs.name = "s" + i.toString()
            fs.u0 = fs.x / atw
            fs.u1 = ( fs.x + fs.w ) / atw
            fs.vTop = 1.0f - fs.y / ath
            fs.vBot = 1.0f - ( fs.y + fs.h ) / ath
            this.sprites.add( fs )
            off = off + 36
            i = i + 1
        }
        Int32 qc = Memory.readInt32( ptr, off )
        off = off + 4
        i = 0
        while i < qc
        {
            if off + 28 > n
            {
                Memory.free( ptr )
                this.lastError = "fui quad table truncated"
                ret false
            }
            Int32 kind = Memory.readInt32( ptr, off + 0 )
            FairyQuad q = FairyQuad()
            q.kind = kind
            q.name = "q" + i.toString()
            q.x = Memory.readFloat32( ptr, off + 4 )
            q.y = Memory.readFloat32( ptr, off + 8 )
            q.w = Memory.readFloat32( ptr, off + 12 )
            q.h = Memory.readFloat32( ptr, off + 16 )
            Int32 si = Memory.readInt32( ptr, off + 20 )
            q.use9 = Memory.readInt32( ptr, off + 24 ) == 1
            if si < 0 || si >= this.sprites.length
            {
                si = this.sprites.length - 1
            }
            if si >= 0
            {
                FairySprite sp = this.sprites[si]
                q.u0 = sp.u0
                q.u1 = sp.u1
                q.vTop = sp.vTop
                q.vBot = sp.vBot
                q.sw = sp.w
                q.sh = sp.h
                q.bl = sp.bl
                q.bt = sp.bt
                q.br = sp.br
                q.bb = sp.bb
                q.use9 = q.use9 && ( q.bl > 0.0f || q.br > 0.0f || q.bt > 0.0f || q.bb > 0.0f )
            }
            this.quads.add( q )
            off = off + 28
            i = i + 1
        }
        Memory.free( ptr )
        this.texture = SLang.RenderTexture.loadFile( dir + "/atlas@ui.png" )
        if this.texture == null
        {
            this.lastError = "fui atlas texture load failed"
            ret false
        }
        ret true
    }

    void parseChildren( TreeNode<string> parent, Float32 ox, Float32 oy )
    {
        Int32 i = 0
        while i < parent.childCount
        {
            TreeNode<string> n = parent.childAt( i )
            i = i + 1
            if n == null || n._name == null
            {
                continue
            }
            string tag = n._name
            if tag == "group"
            {
                Float32 gx = ox + FairySprite.attrF( n, "x" )
                Float32 gy = oy + FairySprite.attrF( n, "y" )
                this.parseChildren( n, gx, gy )
                continue
            }
            if tag != "image" && tag != "text" && tag != "loader" && tag != "graph" && tag != "go3d"
            {
                continue
            }
            FairyQuad q = FairyQuad()
            q.name = FairySprite.attr( n, "name" )
            q.kind = 0
            if tag == "text"
            {
                q.kind = 2
            }
            q.x = ox + FairySprite.attrF( n, "x" )
            q.y = oy + FairySprite.attrF( n, "y" )
            q.w = FairySprite.attrF( n, "w" )
            q.h = FairySprite.attrF( n, "h" )
            string src = FairySprite.attr( n, "src" )
            if q.kind == 2 || src.length == 0
            {
                src = "white"
            }
            # ── loader / graph / go3d：独立纹理元素（FairyGUI v2）────
            # loader：file 属性装载包外图片文件（相对包目录），拉伸填充
            # graph：color 属性 #RRGGBB 的纯色 1x1 纹理（无图集依赖）
            # go3d：3D 包装占位纹理（file 属性装载），运行期经
            #       updateTexPixels 原位更新（GoWrapper 等价）
            if tag == "loader" || tag == "go3d"
            {
                string f = FairySprite.attr( n, "file" )
                if f.length > 0 && this.texHandles.length < 6
                {
                    SLang.RenderTexture lt = SLang.RenderTexture.loadFile( this.pkgDir + "/" + f )
                    if lt != null
                    {
                        Int64 lh = lt.handle
                        # 纹理像素尺寸用 XML tw/th 属性显式声明——跨模块读
                        # RenderTexture 尺寸返回 0 不可靠（2026-11-19 实证）
                        Int32 lw = FairySprite.attrF( n, "tw" )
                        Int32 lh2 = FairySprite.attrF( n, "th" )
                        this.texHandles.add( lh )
                        Int32 widx = this.texCount
                        this.texWidths[widx] = lw
                        this.texHeights[widx] = lh2
                        this.texCount = this.texCount + 1
                        this.texNames.add( f )
                        q.texIndex = this.texHandles.length
                    }
                }
                q.u0 = 0.0f
                q.u1 = 1.0f
                q.vTop = 1.0f
                q.vBot = 0.0f
                this.quads.add( q )
                this.homeXs.add( q.x )
                this.homeYs.add( q.y )
                continue
            }
            if tag == "graph"
            {
                string col = FairySprite.attr( n, "color" )
                Int64 texh = this.makeColorTexture( col )
                if texh != 0 && this.texHandles.length < 6
                {
                    SLang.RenderTexture gt = SLang.RenderTexture.createRgba( texh, 1, 1 )
                    if gt != null
                    {
                        this.texHandles.add( gt.handle )
                        Int32 gidx = this.texCount
                        this.texWidths[gidx] = 1
                        this.texHeights[gidx] = 1
                        this.texCount = this.texCount + 1
                        this.texNames.add( "graph:" + col )
                        q.texIndex = this.texHandles.length
                    }
                    Memory.free( texh )
                }
                q.u0 = 0.0f
                q.u1 = 1.0f
                q.vTop = 1.0f
                q.vBot = 0.0f
                this.quads.add( q )
                this.homeXs.add( q.x )
                this.homeYs.add( q.y )
                continue
            }
            FairySprite sp = this.findSprite( src )
            if sp != null
            {
                q.u0 = sp.u0
                q.u1 = sp.u1
                q.vTop = sp.vTop
                q.vBot = sp.vBot
                q.sw = sp.w
                q.sh = sp.h
                q.bl = sp.bl
                q.bt = sp.bt
                q.br = sp.br
                q.bb = sp.bb
            }
            string s9 = FairySprite.attr( n, "scale9" )
            q.use9 = s9 == "1" && ( q.bl > 0.0f || q.br > 0.0f || q.bt > 0.0f || q.bb > 0.0f )
            this.quads.add( q )
            this.homeXs.add( q.x )
            this.homeYs.add( q.y )
        }
    }

    # 纯色 1x1 像素缓冲（#RRGGBB；alpha=255）——graph 元素纹理源
    Int64 makeColorTexture( string hex )
    {
        Int64 ptr = Memory.alloc( 4 )
        if ptr == 0
        {
            ret 0
        }
        Int32 r = FairySprite.parseI32( this.hexPair( hex, 1 ) )
        Int32 g = FairySprite.parseI32( this.hexPair( hex, 3 ) )
        Int32 b = FairySprite.parseI32( this.hexPair( hex, 5 ) )
        Memory.writeI8( ptr, 0, SystemConvertUInt8( r ) )
        Memory.writeI8( ptr, 1, SystemConvertUInt8( g ) )
        Memory.writeI8( ptr, 2, SystemConvertUInt8( b ) )
        Memory.writeI8( ptr, 3, SystemConvertUInt8( 255 ) )
        ret ptr
    }

    static string hexPair( string hex, Int32 start )
    {
        if hex.length < start + 2
        {
            ret "00"
        }
        ret SystemStringRange( hex, start, start + 2 )
    }

    # ── 动态 quad API（2026-11-19 SnakeGame HUD/数字文本）────────
    # 消费方（游戏模块）只经这些实例方法操作（跨模块直写 FairyQuad
    # 字段有对象污染风险）；加载路径（parseChildren）同步登记 home。

    public Int32 quadCount()
    {
        ret this.quads.length
    }

    # ── 多纹理访问（渲染器按 texIndex 分组提交；游戏侧 Go3D 消费）──

    public Int32 texGroupCount()
    {
        ret this.texHandles.length + 1
    }

    # texIndex 0 = 包图集；≥1 = texHandles[i-1]；越界返回 0
    public Int64 texHandleAt( Int32 texIndex )
    {
        if texIndex <= 0
        {
            if this.texture != null
            {
                ret this.texture.handle
            }
            ret 0
        }
        if texIndex - 1 >= this.texHandles.length
        {
            ret 0
        }
        Int32 oi = texIndex - 1
        Int64 hv = this.texHandles[oi]
        ret hv
    }

    public Int32 texWidthAt( Int32 texIndex )
    {
        Int32 oi = texIndex - 1
        if texIndex < 1 || oi >= this.texCount
        {
            ret 0
        }
        ret this.texWidths[oi]
    }

    public Int32 texHeightAt( Int32 texIndex )
    {
        Int32 oi = texIndex - 1
        if texIndex < 1 || oi >= this.texCount
        {
            ret 0
        }
        ret this.texHeights[oi]
    }

    # GoWrapper 通路：原位更新某纹理组的像素（RGBA8 top-down，尺寸 =
    # 组纹理原始尺寸；句柄不变，C 侧销毁重传）
    public bool updateTexPixels( Int32 texIndex, Int64 dataPtr )
    {
        Int64 h = this.texHandleAt( texIndex )
        if h == 0 || dataPtr == 0
        {
            ret false
        }
        ret EngineFfi.libTextureUpdateRgba( h, dataPtr )
    }

    # 元素名 → 纹理组下标（-1 = 未找到）；Go3D 运行期更新用
    public Int32 quadTexIndex( string name )
    {
        Int32 qi = this.quadIndex( name )
        if qi < 0
        {
            ret 0 - 1
        }
        FairyQuad q = this.quads[qi]
        ret q.texIndex
    }

    public Int32 quadVertCount( Int32 idx )
    {
        if idx < 0 || idx >= this.quads.length
        {
            ret 0
        }
        FairyQuad q = this.quads[idx]
        Int32 cells = 1
        if q.use9 && q.sw > 0.0f && q.sh > 0.0f
        {
            cells = 9
        }
        ret cells * 6
    }

    public string quadName( Int32 idx )
    {
        if idx < 0 || idx >= this.quads.length
        {
            ret ""
        }
        FairyQuad q = this.quads[idx]
        ret q.name
    }

    public Int32 quadIndex( string name )
    {
        Int32 i = 0
        while i < this.quads.length
        {
            FairyQuad q = this.quads[i]
            if q.name == name
            {
                ret i
            }
            i = i + 1
        }
        ret 0 - 1
    }

    # 显隐：隐藏 = x 挪到画布外（尺寸不变，渲染越界裁剪）；恢复 = home x
    public bool quadSetHidden( Int32 idx, bool on )
    {
        if idx < 0 || idx >= this.quads.length || idx >= this.homeXs.length
        {
            ret false
        }
        FairyQuad q = this.quads[idx]
        if on
        {
            q.x = 0.0f - 9999.0f
        }
        else
        {
            q.x = this.homeXs[idx]
        }
        ret true
    }

    # 追加空白动态 quad（不进 home 语义，home 恒 -9999），返回下标
    public Int32 addQuad()
    {
        FairyQuad q = FairyQuad()
        q.name = "dyn" + this.quads.length.toString()
        q.x = 0.0f - 9999.0f
        q.w = 0.0f
        this.quads.add( q )
        this.homeXs.add( 0.0f - 9999.0f )
        this.homeYs.add( 0.0f )
        ret this.quads.length - 1
    }

    # 按 sprite 名换装（UV/九宫格字段整体拷贝）
    public bool quadSetSprite( Int32 idx, string spriteName )
    {
        if idx < 0 || idx >= this.quads.length
        {
            ret false
        }
        FairySprite sp = this.findSprite( spriteName )
        if sp == null
        {
            ret false
        }
        FairyQuad q = this.quads[idx]
        q.u0 = sp.u0
        q.u1 = sp.u1
        q.vTop = sp.vTop
        q.vBot = sp.vBot
        q.sw = sp.w
        q.sh = sp.h
        q.bl = sp.bl
        q.bt = sp.bt
        q.br = sp.br
        q.bb = sp.bb
        q.use9 = false
        if q.bl > 0.0f
        {
            q.use9 = true
        }
        if q.br > 0.0f
        {
            q.use9 = true
        }
        if q.bt > 0.0f
        {
            q.use9 = true
        }
        if q.bb > 0.0f
        {
            q.use9 = true
        }
        ret true
    }

    public bool quadSetRect( Int32 idx, Float32 x, Float32 y, Float32 w, Float32 h )
    {
        if idx < 0 || idx >= this.quads.length
        {
            ret false
        }
        FairyQuad q = this.quads[idx]
        q.x = x
        q.y = y
        q.w = w
        q.h = h
        ret true
    }
}
