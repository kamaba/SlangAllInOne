# ============================================================================
# FontAtlas — 动态字形图集（按需烘焙，Unity TextMeshPro 式工作流）
# ----------------------------------------------------------------------------
# 流程：文本筛字 → Font.createGlyph 得轮廓 → 扫描线填充进 RGBA8 图集
#      → RenderTexture 上传 → TextMesh 用每个字的 UV 生成 quad mesh。
# 首次出现的字即时烘焙，已存在的字直接复用缓存；不生成全字符集。
# 像素：RGB=255、alpha=覆盖率（本版二值），空白区 alpha=0。
# ============================================================================

import Core;
import Std;
import SLangRender;

class GlyphEntry
{
    Int32 code = 0
    Int32 gx = 0
    Int32 gy = 0
    Int32 gw = 0
    Int32 gh = 0
    Float32 advance = 0.0f

    void _init_()
    {
        this.code = 0
        this.gx = 0
        this.gy = 0
        this.gw = 0
        this.gh = 0
        this.advance = 0.0f
    }
}

public class FontAtlas
{
    Font _font = null
    Int32 _w = 256
    Int32 _h = 256
    Int32 _cell = 48
    Int32 _steps = 4
    Int64 _px = 0
    SLang.RenderTexture _tex = null
    Int32 _penX = 1
    Int32 _penY = 1
    Int32 _rowH = 0
    bool _dirty = false
    List<Int32> _codes = null
    List<GlyphEntry> _entries = null
    string _lastError = ""

    public void _init_()
    {
        this._font = null
        this._w = 256
        this._h = 256
        this._cell = 48
        this._steps = 4
        this._px = 0
        this._tex = null
        this._penX = 1
        this._penY = 1
        this._rowH = 0
        this._dirty = false
        this._codes = List<Int32>( 64 )
        this._entries = List<GlyphEntry>( 64 )
        this._lastError = ""
    }

    public static FontAtlas create( Font font, Int32 cellSize )
    {
        FontAtlas a = FontAtlas()
        a._font = font
        if cellSize >= 8 && cellSize <= 128
        {
            a._cell = cellSize
        }
        a._w = 256
        a._h = 256
        Int32 bytes = a._w * a._h * 4
        a._px = Memory.alloc( bytes )
        if a._px == 0
        {
            a._lastError = "atlas alloc failed"
            ret a
        }
        Int32 i = 0
        while i < bytes
        {
            Memory.writeI8( a._px, i, 0 )
            i += 1
        }
        a._dirty = true
        ret a
    }

    public bool isReady()
    {
        ret this._px != 0 && this._font != null
    }

    public string lastError()
    {
        ret this._lastError
    }

    public Int32 width() { ret this._w }
    public Int32 height() { ret this._h }
    public Int32 cellSize() { ret this._cell }
    public Int64 pixelPtr() { ret this._px }

    public Int32 glyphCount()
    {
        ret this._entries.length
    }

    public Int32 glyphCodeAt( Int32 i )
    {
        if i < 0 || i >= this._codes.length
        {
            ret 0
        }
        Int32 v = this._codes[i]
        ret v
    }

    Int32 entryInt( Int32 i, Int32 which )
    {
        if i < 0 || i >= this._entries.length
        {
            ret 0
        }
        GlyphEntry e = this._entries[i]
        if which == 0 { ret e.gx }
        if which == 1 { ret e.gy }
        if which == 2 { ret e.gw }
        ret e.gh
    }

    public Int32 glyphXAt( Int32 i ) { ret this.entryInt( i, 0 ) }
    public Int32 glyphYAt( Int32 i ) { ret this.entryInt( i, 1 ) }
    public Int32 glyphWAt( Int32 i ) { ret this.entryInt( i, 2 ) }
    public Int32 glyphHAt( Int32 i ) { ret this.entryInt( i, 3 ) }

    public Float32 glyphAdvanceAt( Int32 i )
    {
        if i < 0 || i >= this._entries.length
        {
            ret 0.0f
        }
        GlyphEntry e = this._entries[i]
        ret e.advance
    }

    public Int32 indexOfCode( Int32 code )
    {
        Int32 i = 0
        while i < this._codes.length
        {
            Int32 c = this._codes[i]
            if c == code
            {
                ret i
            }
            i += 1
        }
        ret -1
    }

    public bool hasGlyph( Int32 code )
    {
        ret this.indexOfCode( code ) >= 0
    }

    void writePixel( Int32 x, Int32 y )
    {
        if x < 0 || y < 0 || x >= this._w || y >= this._h
        {
            ret
        }
        Int32 off = ( y * this._w + x ) * 4
        Memory.writeI8( this._px, off, 255 )
        Memory.writeI8( this._px, off + 1, 255 )
        Memory.writeI8( this._px, off + 2, 255 )
        Memory.writeI8( this._px, off + 3, 255 )
    }

    # 扫描线偶奇填充：所有轮廓边一起计数，天然支持字形孔洞
    void rasterize( Glyph glyph, Int32 ox, Int32 oy, Float32 scale )
    {
        Int32 baseY = oy + this._cell - 8
        Int32 contours = glyph.contourCount()
        Int32 rows = this._cell
        List<Float32> hits = List<Float32>( 16 )
        Int32 ry = 0
        while ry < rows
        {
            hits.clear()
            Float32 scan = ( oy + ry ).toFloat32() + 0.5f
            Int32 c = 0
            while c < contours
            {
                Int32 ce = c
                Int32 endIdx = glyph.contourEndAt( ce )
                Int32 startIdx = 0
                if ce > 0
                {
                    Int32 pv = ce - 1
                    startIdx = glyph.contourEndAt( pv ) + 1
                }
                Int32 i = startIdx
                while i <= endIdx
                {
                    Int32 j = i + 1
                    if j > endIdx { j = startIdx }
                    Float32 ax = ox + glyph.xAt( i ) * scale
                    Float32 ay = baseY.toFloat32() - glyph.yAt( i ) * scale
                    Float32 bx = ox + glyph.xAt( j ) * scale
                    Float32 by = baseY.toFloat32() - glyph.yAt( j ) * scale
                    if ( ay <= scan && by > scan ) || ( by <= scan && ay > scan )
                    {
                        Float32 t = ( scan - ay ) / ( by - ay )
                        hits.add( ax + ( bx - ax ) * t )
                    }
                    i += 1
                }
                c += 1
            }
            Int32 m = hits.length
            Int32 k = 1
            while k < m
            {
                Float32 hv = hits[k]
                Int32 p = k - 1
                while p >= 0
                {
                    Float32 prev = hits[p]
                    if prev <= hv { break }
                    Int32 np = p + 1
                    hits[np] = prev
                    p -= 1
                }
                Int32 nk = p + 1
                hits[nk] = hv
                k += 1
            }
            Int32 h = 0
            while h + 1 < m
            {
                Int32 hn = h + 1
                Float32 left = hits[h]
                Float32 right = hits[hn]
                Int32 xa = left.toInt32()
                Int32 xb = right.toInt32()
                if xa < ox { xa = ox }
                if xb > ox + this._cell { xb = ox + this._cell }
                Int32 x = xa
                while x < xb
                {
                    this.writePixel( x, oy + ry )
                    x += 1
                }
                h += 2
            }
            ry += 1
        }
    }

    public bool ensureGlyph( Int32 code )
    {
        if !this.isReady()
        {
            this._lastError = "atlas not ready"
            ret false
        }
        if this.hasGlyph( code )
        {
            ret true
        }
        if this._font == null
        {
            this._lastError = "font missing"
            ret false
        }
        Int32 gid = this._font.glyphForCode( code )
        Glyph glyph = this._font.createGlyph( gid, this._steps )
        Float32 scale = this._cell.toFloat32() / this._font.unitsPerEm().toFloat32()
        Float32 adv = glyph.advance() * scale
        GlyphEntry e = GlyphEntry()
        e.code = code
        e.advance = adv
        if glyph.isEmpty()
        {
            this._codes.add( code )
            this._entries.add( e )
            ret true
        }
        Int32 widthNeed = ( adv + 6.0f ).toInt32()
        if widthNeed < 8 { widthNeed = 8 }
        if widthNeed > this._cell { widthNeed = this._cell }
        if this._penX + widthNeed >= this._w
        {
            this._penX = 1
            this._penY = this._penY + this._cell + 1
        }
        if this._penY + this._cell >= this._h
        {
            this._lastError = "atlas full"
            ret false
        }
        e.gx = this._penX
        e.gy = this._penY
        e.gw = widthNeed
        e.gh = this._cell
        this.rasterize( glyph, e.gx, e.gy, scale )
        this._penX = this._penX + widthNeed + 1
        this._codes.add( code )
        this._entries.add( e )
        this._dirty = true
        ret true
    }

    public SLang.RenderTexture texture()
    {
        ret this._tex
    }

    public bool syncTexture()
    {
        if !this._dirty
        {
            ret this._tex != null
        }
        if this._px == 0
        {
            ret false
        }
        if this._tex == null
        {
            this._tex = SLang.RenderTexture.createRgba( this._px, this._w, this._h )
            if this._tex == null
            {
                this._lastError = "texture create failed"
                ret false
            }
        }
        bool ok = this._tex.updatePixels( this._px )
        if ok
        {
            this._dirty = false
        }
        ret ok
    }

    public void dispose()
    {
        if this._tex != null
        {
            this._tex.destroy()
            this._tex = null
        }
        if this._px != 0
        {
            Memory.free( this._px )
            this._px = 0
        }
        this._codes.clear()
        this._entries.clear()
    }
}
