# ============================================================================
# TextMesh — 字库文本的 quad 网格生成与提交（Unity TextMesh 语义）
# ----------------------------------------------------------------------------
# 每个可见字 = 2 三角形 / 6 顶点（pos2+uv2，stride 16B），走
# RenderSystem.submitUiMeshTex 的 UI 透明队列；顶点 xy 已是 NDC。
# 字符串按 UTF-8 解码（支持中文码点），先筛字烘焙进 FontAtlas 再组网格。
# ============================================================================

import Core;
import Std;
import SLangRender;

public class TextMesh
{
    public const static Int32 DEFAULT_SLOT = 7
    public const static Int32 DEFAULT_QUEUE = 4001

    FontAtlas _atlas = null
    string _content = ""
    Int32 _fontSize = 32
    Float32 _x = 0.0f
    Float32 _y = 0.0f
    Float32 _r = 1.0f
    Float32 _g = 1.0f
    Float32 _b = 1.0f
    Float32 _a = 1.0f
    Int32 _count = 0
    Int32 _cap = 0
    Int64 _px = 0
    Int32 _utf8Advance = 1
    string _lastError = ""

    public void _init_()
    {
        this._atlas = null
        this._content = ""
        this._fontSize = 32
        this._x = 0.0f
        this._y = 0.0f
        this._r = 1.0f
        this._g = 1.0f
        this._b = 1.0f
        this._a = 1.0f
        this._count = 0
        this._cap = 0
        this._px = 0
        this._utf8Advance = 1
        this._lastError = ""
    }

    public void attach( FontAtlas atlas )
    {
        this._atlas = atlas
    }

    public FontAtlas atlas()
    {
        ret this._atlas
    }

    public void setText( string value )
    {
        if value == null
        {
            value = ""
        }
        this._content = value
    }

    public string text()
    {
        ret this._content
    }

    public void setFontSize( Int32 value )
    {
        if value < 4 { value = 4 }
        if value > 512 { value = 512 }
        this._fontSize = value
    }

    public Int32 fontSize()
    {
        ret this._fontSize
    }

    public void setPosition( Float32 x, Float32 y )
    {
        this._x = x
        this._y = y
    }

    public void setColor( Float32 r, Float32 g, Float32 b, Float32 a )
    {
        this._r = r
        this._g = g
        this._b = b
        this._a = a
    }

    public Int32 vertexCount()
    {
        ret this._count
    }

    public Int64 vertexPtr()
    {
        ret this._px
    }

    public string lastError()
    {
        ret this._lastError
    }

    # UTF-8 逐码点解码：返回码点，字节前进量写 _utf8Advance
    Int32 decodeAt( Int32 i )
    {
        Int32 n = this._content.length
        if i < 0 || i >= n
        {
            this._utf8Advance = 0
            ret 0
        }
        Int32 b0 = SystemStringCharCodeAt( this._content, i )
        if b0 < 128
        {
            this._utf8Advance = 1
            ret b0
        }
        if ( b0 & 224 ) == 192 && i + 1 < n
        {
            Int32 b1 = SystemStringCharCodeAt( this._content, i + 1 )
            this._utf8Advance = 2
            ret ( ( b0 & 31 ) * 64 ) + ( b1 & 63 )
        }
        if ( b0 & 240 ) == 224 && i + 2 < n
        {
            Int32 b1 = SystemStringCharCodeAt( this._content, i + 1 )
            Int32 b2 = SystemStringCharCodeAt( this._content, i + 2 )
            this._utf8Advance = 3
            ret ( ( b0 & 15 ) * 4096 ) + ( ( b1 & 63 ) * 64 ) + ( b2 & 63 )
        }
        if ( b0 & 248 ) == 240 && i + 3 < n
        {
            Int32 b1 = SystemStringCharCodeAt( this._content, i + 1 )
            Int32 b2 = SystemStringCharCodeAt( this._content, i + 2 )
            Int32 b3 = SystemStringCharCodeAt( this._content, i + 3 )
            this._utf8Advance = 4
            ret ( ( b0 & 7 ) * 262144 ) + ( ( b1 & 63 ) * 4096 ) + ( ( b2 & 63 ) * 64 ) + ( b3 & 63 )
        }
        this._utf8Advance = 1
        ret b0
    }

    # 先筛字（按需烘焙），返回文本码点数；缺字/空间宽为 0 也计入
    Int32 prepareGlyphs()
    {
        Int32 n = this._content.length
        Int32 i = 0
        Int32 count = 0
        while i < n
        {
            Int32 code = this.decodeAt( i )
            Int32 step = this._utf8Advance
            if step <= 0 { step = 1 }
            i = i + step
            if this._atlas == null
            {
                this._lastError = "atlas missing"
            }
            elif !this._atlas.ensureGlyph( code )
            {
                this._lastError = this._atlas.lastError()
            }
            count += 1
        }
        ret count
    }

    void writeVertex( Int32 index, Float32 x, Float32 y, Float32 u, Float32 v )
    {
        Int32 off = index * 16
        Memory.writeF32( this._px, off, x )
        Memory.writeF32( this._px, off + 4, y )
        Memory.writeF32( this._px, off + 8, u )
        Memory.writeF32( this._px, off + 12, v )
    }

    # 生成 NDC 顶点；返回顶点数（每字 6）。aspect = 视口宽/高。
    public Int32 buildVertices( Int32 viewW, Int32 viewH, Float32 aspect )
    {
        this._count = 0
        this._lastError = ""
        if viewW <= 0 || viewH <= 0 || this._atlas == null
        {
            ret 0
        }
        if aspect <= 0.0001f { aspect = 1.0f }
        Int32 chars = this.prepareGlyphs()
        if chars <= 0
        {
            ret 0
        }
        Int32 need = chars * 6 * 16
        if this._cap < need
        {
            if this._px != 0
            {
                Memory.free( this._px )
                this._px = 0
            }
            this._px = Memory.alloc( need )
            if this._px == 0
            {
                this._lastError = "vertex alloc failed"
                ret 0
            }
            this._cap = need
        }
        Float32 aw = this._atlas.width().toFloat32()
        Float32 ah = this._atlas.height().toFloat32()
        Float32 cell = this._atlas.cellSize().toFloat32()
        Float32 k = this._fontSize.toFloat32() / cell
        Float32 penX = this._x
        Int32 i = 0
        Int32 cursor = 0
        Int32 n = this._content.length
        while i < n
        {
            Int32 code = this.decodeAt( i )
            Int32 step = this._utf8Advance
            if step <= 0 { step = 1 }
            i = i + step
            Int32 idx = this._atlas.indexOfCode( code )
            if idx < 0
            {
                ret cursor
            }
            Float32 adv = this._atlas.glyphAdvanceAt( idx ) * k
            if adv <= 0.0001f
            {
                adv = this._fontSize.toFloat32() * 0.5f
            }
            Int32 gx = this._atlas.glyphXAt( idx )
            Int32 gy = this._atlas.glyphYAt( idx )
            Int32 gw = this._atlas.glyphWAt( idx )
            Int32 gh = this._atlas.glyphHAt( idx )
            if gw > 0 && gh > 0
            {
                Float32 sx0 = penX
                Float32 sy0 = this._y
                Float32 sx1 = penX + adv
                Float32 sy1 = this._y + this._fontSize.toFloat32()
                Int32 gyBottom = gy + gh
                Float32 u0 = gx.toFloat32() / aw
                Float32 u1 = ( gx + gw ).toFloat32() / aw
                Float32 vTop = ( ah - gy.toFloat32() ) / ah
                Float32 vBot = ( ah - gyBottom.toFloat32() ) / ah
                Float32 nx0 = ( sx0 / viewW.toFloat32() * 2.0f - 1.0f ) / aspect
                Float32 nx1 = ( sx1 / viewW.toFloat32() * 2.0f - 1.0f ) / aspect
                Float32 ny0 = 1.0f - sy0 / viewH.toFloat32() * 2.0f
                Float32 ny1 = 1.0f - sy1 / viewH.toFloat32() * 2.0f
                this.writeVertex( cursor, nx0, ny0, u0, vTop )
                this.writeVertex( cursor + 1, nx0, ny1, u0, vBot )
                this.writeVertex( cursor + 2, nx1, ny1, u1, vBot )
                this.writeVertex( cursor + 3, nx0, ny0, u0, vTop )
                this.writeVertex( cursor + 4, nx1, ny1, u1, vBot )
                this.writeVertex( cursor + 5, nx1, ny0, u1, vTop )
                cursor = cursor + 6
            }
            penX = penX + adv
        }
        this._count = cursor
        ret cursor
    }

    public bool draw( RenderSystem rs, Int32 slot, Int32 queue )
    {
        if rs == null || !rs.ready()
        {
            this._lastError = "render system not ready"
            ret false
        }
        Int32 v = this.buildVertices( rs.pixelWidth(), rs.pixelHeight(), rs.aspectValue() )
        if v <= 0
        {
            ret false
        }
        if !this._atlas.syncTexture()
        {
            this._lastError = this._atlas.lastError()
            ret false
        }
        SLang.RenderTexture tex = this._atlas.texture()
        if tex == null
        {
            ret false
        }
        Int64 texHandle = tex.handle
        bool ok = rs.submitUiMeshTex( slot, this._px, this._count, texHandle,
            this._r, this._g, this._b, this._a, queue )
        ret ok
    }

    public void dispose()
    {
        if this._px != 0
        {
            Memory.free( this._px )
            this._px = 0
        }
        this._cap = 0
        this._count = 0
    }
}
