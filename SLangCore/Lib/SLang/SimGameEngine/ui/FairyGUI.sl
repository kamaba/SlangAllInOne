import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# FairyGUI 适配层（首期：XML 包 / 图集 / uvRect / 九宫格 / 组层级）
# ----------------------------------------------------------------------------
# 数据来自 FairyGUI 编辑器导出的 XML 包（package.xml + 组件 XML + 图集 PNG）；
# 渲染落在引擎既有 2D 管线：顶点 UV 承载图集裁剪与九宫格，整张 UI 作为
# 一个带 UV 的自定义网格（pos2+uv2，stride 16B）经 RenderSystem.submitUiMesh
# 送进与 3D 场景相同的 RenderPipeline，无需改 C 层 UBO/着色器。
#
# 文本首期只用图集白色块占位（FairyQuad.kind=2），字体栅格化另行专项。
# 每元素 tint 首期不下发（顶点格式无 color 字段），颜色由图集素材本身承担。
# ============================================================================

public class FairySprite
{
    public string name = ""
    public Float32 x = 0.0f
    public Float32 y = 0.0f
    public Float32 w = 0.0f
    public Float32 h = 0.0f
    public Float32 u0 = 0.0f
    public Float32 u1 = 1.0f
    public Float32 vTop = 1.0f
    public Float32 vBot = 0.0f
    public Float32 bl = 0.0f
    public Float32 bt = 0.0f
    public Float32 br = 0.0f
    public Float32 bb = 0.0f

    # XML 属性节点名 "l,t,r,b" 形式的九宫格边距（源图像素）
    public void setBorders( string s )
    {
        Int32 n = s.length
        if n <= 0
        {
            ret
        }
        Int32 comma1 = 0 - 1
        Int32 comma2 = 0 - 1
        Int32 comma3 = 0 - 1
        Int32 i = 0
        while i < n
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            if c == 44
            {
                if comma1 < 0
                {
                    comma1 = i
                }
                elif comma2 < 0
                {
                    comma2 = i
                }
                elif comma3 < 0
                {
                    comma3 = i
                }
            }
            i = i + 1
        }
        if comma1 < 0 || comma2 < 0 || comma3 < 0
        {
            ret
        }
        string a = SystemStringRange( s, 0, comma1 )
        string b = SystemStringRange( s, comma1 + 1, comma2 )
        string c3 = SystemStringRange( s, comma2 + 1, comma3 )
        string d = SystemStringRange( s, comma3 + 1, n )
        this.bl = FairySprite.parseF32( a )
        this.bt = FairySprite.parseF32( b )
        this.br = FairySprite.parseF32( c3 )
        this.bb = FairySprite.parseF32( d )
    }

    # 自包含十进制解析（不依赖系统转换调用；XML 属性都是简单数值）
    public static Float32 parseF32( string s )
    {
        if s == null || s.length == 0
        {
            ret 0.0f
        }
        Int32 sign = 1
        Int32 i = 0
        Int32 c = SystemStringCharCodeAt( s, 0 )
        if c == 45
        {
            sign = 0 - 1
            i = 1
        }
        Float32 whole = 0.0f
        Float32 frac = 0.0f
        Float32 scale = 0.1f
        bool dot = false
        while i < s.length
        {
            c = SystemStringCharCodeAt( s, i )
            i = i + 1
            if c == 46
            {
                dot = true
                continue
            }
            if c < 48 || c > 57
            {
                continue
            }
            Int32 d = c - 48
            if dot
            {
                frac = frac + d.toFloat32() * scale
                scale = scale * 0.1f
            }
            else
            {
                whole = whole * 10.0f + d.toFloat32()
            }
        }
        Float32 v = whole + frac
        if sign < 0
        {
            v = 0.0f - v
        }
        ret v
    }

    public static Int32 parseI32( string s )
    {
        if s == null || s.length == 0
        {
            ret 0
        }
        Int32 sign = 1
        Int32 i = 0
        Int32 c = SystemStringCharCodeAt( s, 0 )
        if c == 45
        {
            sign = 0 - 1
            i = 1
        }
        Int32 v = 0
        while i < s.length
        {
            c = SystemStringCharCodeAt( s, i )
            i = i + 1
            if c < 48 || c > 57
            {
                continue
            }
            v = v * 10 + c - 48
        }
        ret v * sign
    }

    # XML 取值助手（属性节点在 BaseXml 里以 "@名字" 挂在元素下）
    public static string attr( TreeNode<string> node, string name )
    {
        if node == null || name == null || name.length == 0
        {
            ret ""
        }
        string an = "@" + name
        TreeNode<string> a = node.childByName( an )
        if a == null || a._value == null
        {
            ret ""
        }
        ret a._value
    }

    public static Float32 attrF( TreeNode<string> node, string name )
    {
        string s = FairySprite.attr( node, name )
        if s.length == 0
        {
            ret 0.0f
        }
        ret FairySprite.parseF32( s )
    }

    public static Int32 attrI( TreeNode<string> node, string name )
    {
        string s = FairySprite.attr( node, name )
        if s.length == 0
        {
            ret 0
        }
        ret FairySprite.parseI32( s )
    }
}

public class FairyQuad
{
    public string name = ""
    public Int32 kind = 0
    public Float32 x = 0.0f
    public Float32 y = 0.0f
    public Float32 w = 0.0f
    public Float32 h = 0.0f
    public Float32 u0 = 0.0f
    public Float32 u1 = 1.0f
    public Float32 vTop = 1.0f
    public Float32 vBot = 0.0f
    public Float32 sw = 0.0f
    public Float32 sh = 0.0f
    public Float32 bl = 0.0f
    public Float32 bt = 0.0f
    public Float32 br = 0.0f
    public Float32 bb = 0.0f
    public bool use9 = false
}

public class FairyPackage
{
    public string name = ""
    public Int32 designW = 480
    public Int32 designH = 480
    public SLang.RenderTexture texture = null
    public string lastError = ""
    public List<FairySprite> sprites = List<FairySprite>( 8 )
    public List<FairyQuad> quads = List<FairyQuad>( 16 )

    public void _init_()
    {
        this.sprites = List<FairySprite>( 8 )
        this.quads = List<FairyQuad>( 16 )
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
            if tag != "image" && tag != "text"
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
        }
    }
}

public class FairyUIRenderer
{
    public FairyPackage pkg = null
    public Float32 aspect = 1.0f
    public string lastError = ""
    public Int32 lastVerts = 0
    public Int32 lastQuads = 0

    public void _init_()
    {
        this.aspect = 1.0f
    }

    public Int32 vertCountOf( FairyQuad q )
    {
        if q.use9
        {
            ret 54
        }
        ret 6
    }

    Int32 emitOne( Int64 ptr, Int32 cursor,
        Float32 dx, Float32 dy, Float32 dw, Float32 dh,
        Float32 u0, Float32 vTop, Float32 u1, Float32 vBot )
    {
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        if dwf <= 0.0f || dhf <= 0.0f
        {
            ret cursor
        }
        Float32 nx0 = ( dx / dwf * 2.0f - 1.0f ) / this.aspect
        Float32 nx1 = ( ( dx + dw ) / dwf * 2.0f - 1.0f ) / this.aspect
        Float32 nyTop = 1.0f - dy / dhf * 2.0f
        Float32 nyBot = 1.0f - ( dy + dh ) / dhf * 2.0f
        Int32 off = cursor * 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vTop )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vTop )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vTop )
        ret cursor + 6
    }

    Int32 emitQuad( Int64 ptr, Int32 cursor, FairyQuad q )
    {
        if !q.use9 || q.sw <= 0.0f || q.sh <= 0.0f
        {
            ret this.emitOne( ptr, cursor, q.x, q.y, q.w, q.h, q.u0, q.vTop, q.u1, q.vBot )
        }
        Float32 l = q.bl
        Float32 t = q.bt
        Float32 r = q.br
        Float32 b = q.bb
        Int32 col = 0
        while col < 3
        {
            Float32 ssx = 0.0f
            Float32 ssw = 0.0f
            Float32 ddx = 0.0f
            Float32 ddw = 0.0f
            if col == 0
            {
                ssx = 0.0f
                ssw = l
                ddx = q.x
                ddw = l
            }
            elif col == 1
            {
                ssx = l
                ssw = q.sw - l - r
                ddx = q.x + l
                ddw = q.w - l - r
            }
            else
            {
                ssx = q.sw - r
                ssw = r
                ddx = q.x + q.w - r
                ddw = r
            }
            Int32 row = 0
            while row < 3
            {
                Float32 ssy = 0.0f
                Float32 ssh = 0.0f
                Float32 ddy = 0.0f
                Float32 ddh = 0.0f
                if row == 0
                {
                    ssy = 0.0f
                    ssh = t
                    ddy = q.y
                    ddh = t
                }
                elif row == 1
                {
                    ssy = t
                    ssh = q.sh - t - b
                    ddy = q.y + t
                    ddh = q.h - t - b
                }
                else
                {
                    ssy = q.sh - b
                    ssh = b
                    ddy = q.y + q.h - b
                    ddh = b
                }
                Float32 fu0 = ssx / q.sw
                Float32 fu1 = ( ssx + ssw ) / q.sw
                Float32 fv0 = ssy / q.sh
                Float32 fv1 = ( ssy + ssh ) / q.sh
                Float32 cu0 = q.u0 + ( q.u1 - q.u0 ) * fu0
                Float32 cu1 = q.u0 + ( q.u1 - q.u0 ) * fu1
                Float32 cvTop = q.vTop + ( q.vBot - q.vTop ) * fv0
                Float32 cvBot = q.vTop + ( q.vBot - q.vTop ) * fv1
                cursor = this.emitOne( ptr, cursor, ddx, ddy, ddw, ddh, cu0, cvTop, cu1, cvBot )
                row = row + 1
            }
            col = col + 1
        }
        ret cursor
    }

    # ── 点击命中测试（FairyGUI 逻辑 → 引擎 input）────────────
    # localX/localY = 渲染面（QLabel）局部像素，viewW/viewH = 渲染目标像素。
    # 顶点 NDC 的 aspect 缩放在这里与视口映射抵消，故局部像素 → 设计坐标
    # 只需按 design/view 比例换算；倒序遍历 quads（后画在上）取最上层命中。
    public string hitTestLocal( Int32 localX, Int32 localY, Int32 viewW, Int32 viewH )
    {
        if this.pkg == null || viewW <= 0 || viewH <= 0
        {
            ret ""
        }
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        if dwf <= 0.0f || dhf <= 0.0f
        {
            ret ""
        }
        Float32 dx = localX.toFloat32() * dwf / viewW.toFloat32()
        Float32 dy = localY.toFloat32() * dhf / viewH.toFloat32()
        Int32 i = this.pkg.quads.length - 1
        while i >= 0
        {
            FairyQuad q = this.pkg.quads[i]
            if dx >= q.x && dx <= q.x + q.w && dy >= q.y && dy <= q.y + q.h
            {
                ret q.name
            }
            i = i - 1
        }
        ret ""
    }

    # 命中项名字前缀判定（菜单项统一命名 menu_N）
    public static Int32 menuIndex( string name, string prefix )
    {
        if name == null || prefix == null || name.length <= prefix.length
        {
            ret 0 - 1
        }
        string head = SystemStringRange( name, 0, prefix.length )
        if head != prefix
        {
            ret 0 - 1
        }
        string tail = SystemStringRange( name, prefix.length, name.length )
        ret FairySprite.parseI32( tail )
    }

    public bool draw( RenderSystem rs )
    {
        this.lastError = ""
        this.lastVerts = 0
        this.lastQuads = 0
        if rs == null || this.pkg == null || this.pkg.texture == null
        {
            this.lastError = "renderer not ready"
            ret false
        }
        Int32 n = this.pkg.quads.length
        if n <= 0
        {
            this.lastError = "no quads"
            ret false
        }
        Int32 total = 0
        Int32 i = 0
        while i < n
        {
            FairyQuad q = this.pkg.quads[i]
            total = total + this.vertCountOf( q )
            i = i + 1
        }
        if total <= 0 || total > 4096
        {
            this.lastError = "vertex budget exceeded: " + total.toString()
            ret false
        }
        Int64 ptr = Memory.alloc( total * 16 )
        if ptr == 0
        {
            this.lastError = "vertex memory alloc failed"
            ret false
        }
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        Float32 asp = this.aspect
        Int32 cursor = 0
        i = 0
        while i < n
        {
            FairyQuad fq = this.pkg.quads[i]
            Int32 cells = 1
            if fq.use9 && fq.sw > 0.0f && fq.sh > 0.0f
            {
                cells = 9
            }
            Int32 ci = 0
            while ci < cells
            {
                Float32 dx = fq.x
                Float32 dy = fq.y
                Float32 dw = fq.w
                Float32 dh = fq.h
                Float32 u0 = fq.u0
                Float32 u1 = fq.u1
                Float32 vT = fq.vTop
                Float32 vB = fq.vBot
                if cells == 9
                {
                    Int32 col = ci % 3
                    Int32 row = ci / 3
                    Float32 ssx = 0.0f
                    Float32 ssw = 0.0f
                    if col == 0
                    {
                        ssx = 0.0f
                        ssw = fq.bl
                        dx = fq.x
                        dw = fq.bl
                    }
                    elif col == 1
                    {
                        ssx = fq.bl
                        ssw = fq.sw - fq.bl - fq.br
                        dx = fq.x + fq.bl
                        dw = fq.w - fq.bl - fq.br
                    }
                    else
                    {
                        ssx = fq.sw - fq.br
                        ssw = fq.br
                        dx = fq.x + fq.w - fq.br
                        dw = fq.br
                    }
                    Float32 ssy = 0.0f
                    Float32 ssh = 0.0f
                    if row == 0
                    {
                        ssy = 0.0f
                        ssh = fq.bt
                        dy = fq.y
                        dh = fq.bt
                    }
                    elif row == 1
                    {
                        ssy = fq.bt
                        ssh = fq.sh - fq.bt - fq.bb
                        dy = fq.y + fq.bt
                        dh = fq.h - fq.bt - fq.bb
                    }
                    else
                    {
                        ssy = fq.sh - fq.bb
                        ssh = fq.bb
                        dy = fq.y + fq.h - fq.bb
                        dh = fq.bb
                    }
                    Float32 fu0 = ssx / fq.sw
                    Float32 fu1 = ( ssx + ssw ) / fq.sw
                    Float32 fv0 = ssy / fq.sh
                    Float32 fv1 = ( ssy + ssh ) / fq.sh
                    u0 = fq.u0 + ( fq.u1 - fq.u0 ) * fu0
                    u1 = fq.u0 + ( fq.u1 - fq.u0 ) * fu1
                    vT = fq.vTop + ( fq.vBot - fq.vTop ) * fv0
                    vB = fq.vTop + ( fq.vBot - fq.vTop ) * fv1
                }
                Float32 x0 = ( dx / dwf * 2.0f - 1.0f ) / asp
                Float32 x1 = ( ( dx + dw ) / dwf * 2.0f - 1.0f ) / asp
                Float32 y0 = 1.0f - dy / dhf * 2.0f
                Float32 y1 = 1.0f - ( dy + dh ) / dhf * 2.0f
                Int32 off = cursor * 16
                Memory.writeF32( ptr, off + 0, x0 )
                Memory.writeF32( ptr, off + 4, y0 )
                Memory.writeF32( ptr, off + 8, u0 )
                Memory.writeF32( ptr, off + 12, vT )
                Memory.writeF32( ptr, off + 16, x0 )
                Memory.writeF32( ptr, off + 20, y1 )
                Memory.writeF32( ptr, off + 24, u0 )
                Memory.writeF32( ptr, off + 28, vB )
                Memory.writeF32( ptr, off + 32, x1 )
                Memory.writeF32( ptr, off + 36, y1 )
                Memory.writeF32( ptr, off + 40, u1 )
                Memory.writeF32( ptr, off + 44, vB )
                Memory.writeF32( ptr, off + 48, x0 )
                Memory.writeF32( ptr, off + 52, y0 )
                Memory.writeF32( ptr, off + 56, u0 )
                Memory.writeF32( ptr, off + 60, vT )
                Memory.writeF32( ptr, off + 64, x1 )
                Memory.writeF32( ptr, off + 68, y1 )
                Memory.writeF32( ptr, off + 72, u1 )
                Memory.writeF32( ptr, off + 76, vB )
                Memory.writeF32( ptr, off + 80, x1 )
                Memory.writeF32( ptr, off + 84, y0 )
                Memory.writeF32( ptr, off + 88, u1 )
                Memory.writeF32( ptr, off + 92, vT )
                cursor = cursor + 6
                ci = ci + 1
            }
            i = i + 1
        }
        bool ok = rs.submitUiMesh( ptr, cursor, this.pkg.texture,
            1.0f, 1.0f, 1.0f, 1.0f, 4000 )
        Memory.free( ptr )
        this.lastVerts = cursor
        this.lastQuads = n
        if !ok
        {
            this.lastError = "submitUiMesh failed"
        }
        ret ok
    }
}
