# ============================================================================
# Font — .ttf/.otf 字体解析器（纯 SL，读 sfnt 表 → 字形轮廓数据）
# ----------------------------------------------------------------------------
# 支持：TrueType glyf 轮廓（cmap format 4 / 12，loca 短/长格式，hmtx 宽度）
#      二次 Bezier 控制点展平为折线，交给 Glyph / FontAtlas 光栅化。
# 边界：Composite glyph（numberOfContours < 0）本版返回空轮廓并记录
#      lastError=3；CFF（OTTO）字体无 glyf 表，本版不支持。
# 用法：Font f = Font.load(path) → f.glyphForCode(code) → f.createGlyph(gid,steps)
# ============================================================================

import Core;
import Std;

public class Font
{
    Int64 _data = 0
    Int32 _size = 0
    Int32 _head = 0
    Int32 _maxp = 0
    Int32 _hhea = 0
    Int32 _hmtx = 0
    Int32 _cmap = 0
    Int32 _loca = 0
    Int32 _glyf = 0
    Int32 _units = 1000
    Int32 _numGlyphs = 0
    Int32 _numHMetrics = 0
    Int32 _locaLong = 0
    Int32 _cmapSub = 0
    Int32 _cmapFormat = 0
    Int32 _lastError = 0
    string _path = ""

    public void _init_()
    {
        this._data = 0
        this._size = 0
        this._head = 0
        this._maxp = 0
        this._hhea = 0
        this._hmtx = 0
        this._cmap = 0
        this._loca = 0
        this._glyf = 0
        this._units = 1000
        this._numGlyphs = 0
        this._numHMetrics = 0
        this._locaLong = 0
        this._cmapSub = 0
        this._cmapFormat = 0
        this._lastError = 0
        this._path = ""
    }

    public static Font load( string path )
    {
        Font f = Font()
        f._path = path
        if path == null || path.length == 0
        {
            f._lastError = 1
            ret f
        }
        if !File.exists( path )
        {
            f._lastError = 1
            ret f
        }
        UInt8Array raw = File.readAllBytes( path )
        Int32 n = raw.length
        if n < 12
        {
            f._lastError = 2
            ret f
        }
        Int64 ptr = Memory.alloc( n )
        if ptr == 0
        {
            f._lastError = 4
            ret f
        }
        Int32 i = 0
        while i < n
        {
            Memory.writeI8( ptr, i, raw[i].toInt32() )
            i += 1
        }
        f._data = ptr
        f._size = n
        if !f.parseTables()
        {
            f.dispose()
            ret f
        }
        ret f
    }

    public void dispose()
    {
        if this._data != 0
        {
            Memory.free( this._data )
            this._data = 0
        }
        this._size = 0
    }

    public bool isLoaded()
    {
        ret this._data != 0 && this._lastError == 0
    }

    public Int32 lastError()
    {
        ret this._lastError
    }

    public Int32 unitsPerEm()
    {
        ret this._units
    }

    public Int32 glyphCount()
    {
        ret this._numGlyphs
    }

    public string sourcePath()
    {
        ret this._path
    }

    Int32 u8( Int32 off )
    {
        if this._data == 0 || off < 0 || off >= this._size
        {
            ret 0
        }
        ret Memory.readUInt8( this._data, off )
    }

    Int32 u16( Int32 off )
    {
        Int32 a = this.u8( off )
        Int32 b = this.u8( off + 1 )
        ret ( a << 8 ) | b
    }

    Int32 s16( Int32 off )
    {
        Int32 v = this.u16( off )
        if v > 32767
        {
            ret v - 65536
        }
        ret v
    }

    Int32 u32( Int32 off )
    {
        Int64 v = SystemConvertInt64( this.u8( off ) )
        v = v * 256 + SystemConvertInt64( this.u8( off + 1 ) )
        v = v * 256 + SystemConvertInt64( this.u8( off + 2 ) )
        v = v * 256 + SystemConvertInt64( this.u8( off + 3 ) )
        ret v.toInt32()
    }

    static bool tagIs( Int64 buf, Int32 off, Int32 a, Int32 b, Int32 c, Int32 d )
    {
        ret Memory.readUInt8( buf, off ) == a && Memory.readUInt8( buf, off + 1 ) == b
            && Memory.readUInt8( buf, off + 2 ) == c && Memory.readUInt8( buf, off + 3 ) == d
    }

    bool parseTables()
    {
        Int32 tableCount = this.u16( 4 )
        if tableCount <= 0 || 12 + tableCount * 16 > this._size
        {
            this._lastError = 2
            ret false
        }
        Int32 i = 0
        while i < tableCount
        {
            Int32 rec = 12 + i * 16
            Int32 off = this.u32( rec + 8 )
            Int32 len = this.u32( rec + 12 )
            if off > 0 && len > 0 && off + len <= this._size
            {
                if Font.tagIs( this._data, rec, 104, 101, 97, 100 ) { this._head = off }
                if Font.tagIs( this._data, rec, 109, 97, 120, 112 ) { this._maxp = off }
                if Font.tagIs( this._data, rec, 104, 104, 101, 97 ) { this._hhea = off }
                if Font.tagIs( this._data, rec, 104, 109, 116, 120 ) { this._hmtx = off }
                if Font.tagIs( this._data, rec, 99, 109, 97, 112 ) { this._cmap = off }
                if Font.tagIs( this._data, rec, 108, 111, 99, 97 ) { this._loca = off }
                if Font.tagIs( this._data, rec, 103, 108, 121, 102 ) { this._glyf = off }
            }
            i += 1
        }
        if this._head == 0 || this._maxp == 0 || this._hhea == 0 || this._hmtx == 0
            || this._cmap == 0 || this._loca == 0 || this._glyf == 0
        {
            this._lastError = 2
            ret false
        }
        this._units = this.u16( this._head + 18 )
        if this._units <= 0 { this._units = 1000 }
        this._numGlyphs = this.u16( this._maxp + 4 )
        this._numHMetrics = this.u16( this._hhea + 34 )
        if this._numHMetrics <= 0 { this._numHMetrics = 1 }
        if this._numHMetrics > this._numGlyphs { this._numHMetrics = this._numGlyphs }
        this._locaLong = 0
        if this.s16( this._head + 50 ) == 1 { this._locaLong = 1 }
        if !this.parseCmap()
        {
            this._lastError = 2
            ret false
        }
        ret true
    }

    bool parseCmap()
    {
        Int32 n = this.u16( this._cmap + 2 )
        Int32 bestScore = 0
        Int32 i = 0
        while i < n
        {
            Int32 rec = this._cmap + 4 + i * 8
            Int32 sub = this._cmap + this.u32( rec + 4 )
            Int32 fmt = this.u16( sub )
            Int32 platform = this.u16( rec )
            Int32 encoding = this.u16( rec + 2 )
            Int32 score = 0
            if fmt == 12
            {
                score = 3
                if platform == 3 && encoding == 10 { score = 5 }
            }
            if fmt == 4
            {
                score = 2
                if platform == 3 && encoding == 1 { score = 4 }
                if platform == 0 { score = 3 }
            }
            if score > bestScore
            {
                bestScore = score
                this._cmapSub = sub
                this._cmapFormat = fmt
            }
            i += 1
        }
        ret this._cmapSub != 0
    }

    Int32 glyphForCode( Int32 code )
    {
        if this._data == 0 || code < 0 { ret 0 }
        if this._cmapFormat == 4
        {
            Int32 segCount = this.u16( this._cmapSub + 6 ) / 2
            if segCount <= 0 { ret 0 }
            Int32 i = 0
            while i < segCount
            {
                Int32 endAddr = this._cmapSub + 14 + i * 2
                Int32 endCode = this.u16( endAddr )
                if code > endCode
                {
                    i += 1
                }
                elif i < segCount
                {
                    Int32 startAddr = this._cmapSub + 16 + segCount * 2 + i * 2
                    Int32 startCode = this.u16( startAddr )
                    if code >= startCode
                    {
                        Int32 deltaAddr = this._cmapSub + 16 + segCount * 4 + i * 2
                        Int32 rangeAddr = this._cmapSub + 16 + segCount * 6 + i * 2
                        Int32 delta = this.s16( deltaAddr )
                        Int32 rangeOffset = this.u16( rangeAddr )
                        if rangeOffset == 0
                        {
                            ret ( code + delta ) & 65535
                        }
                        Int32 glyphAddr = rangeAddr + rangeOffset + ( code - startCode ) * 2
                        Int32 gid = this.u16( glyphAddr )
                        if gid == 0 { ret 0 }
                        ret ( gid + delta ) & 65535
                    }
                    ret 0
                }
            }
            ret 0
        }
        if this._cmapFormat == 12
        {
            Int32 groups = this.u32( this._cmapSub + 12 )
            Int32 i = 0
            while i < groups
            {
                Int32 g = this._cmapSub + 16 + i * 12
                Int32 first = this.u32( g )
                Int32 last = this.u32( g + 4 )
                if code >= first && code <= last
                {
                    Int32 startGid = this.u32( g + 8 )
                    ret startGid + ( code - first )
                }
                i += 1
            }
        }
        ret 0
    }

    public Float32 advanceOf( Int32 gid )
    {
        if this._data == 0 || gid < 0 || gid >= this._numGlyphs
        {
            ret 0.0f
        }
        Int32 i = gid
        if i >= this._numHMetrics
        {
            i = this._numHMetrics - 1
        }
        ret this.u16( this._hmtx + i * 4 ).toFloat32()
    }

    Int32 locaAt( Int32 gid )
    {
        if this._locaLong == 0
        {
            ret this.u16( this._loca + gid * 2 ) * 2
        }
        ret this.u32( this._loca + gid * 4 )
    }

    # 二次 Bezier 采样（控制点 bx/by，端点 ax/ay → cx/cy）
    void sampleCurve( Glyph glyph, Float32 ax, Float32 ay,
        Float32 bx, Float32 by, Float32 cx, Float32 cy, Int32 steps )
    {
        Int32 s = 1
        while s <= steps
        {
            Float32 ft = s.toFloat32() / steps.toFloat32()
            Float32 it = 1.0f - ft
            Float32 qx = it * it * ax + 2.0f * it * ft * bx + ft * ft * cx
            Float32 qy = it * it * ay + 2.0f * it * ft * by + ft * ft * cy
            glyph.addPoint( qx, qy )
            s += 1
        }
    }

    public Glyph createGlyph( Int32 gid, Int32 steps )
    {
        Glyph glyph = Glyph()
        glyph.setGlyphId( gid )
        glyph.setAdvance( this.advanceOf( gid ) )
        if !this.isLoaded() || gid < 0 || gid >= this._numGlyphs
        {
            this._lastError = 2
            ret glyph
        }
        if steps < 1 { steps = 4 }
        Int32 start = this.locaAt( gid )
        Int32 stop = this.locaAt( gid + 1 )
        if stop <= start
        {
            ret glyph
        }
        Int32 contours = this.s16( this._glyf + start )
        if contours <= 0
        {
            if contours < 0
            {
                this._lastError = 3   # composite glyph 未支持
            }
            ret glyph
        }
        if contours > 1024
        {
            this._lastError = 2
            ret glyph
        }
        Int32 lastPoint = this.u16( this._glyf + start + 10 + ( contours - 1 ) * 2 )
        Int32 nPoints = lastPoint + 1
        if nPoints <= 0 || nPoints > 8192
        {
            this._lastError = 2
            ret glyph
        }
        Int32 instrLen = this.u16( this._glyf + start + 10 + contours * 2 )
        Int32 flagPos = this._glyf + start + 12 + contours * 2 + instrLen
        List<Int32> flags = List<Int32>( nPoints )
        Int32 i = 0
        while i < nPoints
        {
            Int32 f = this.u8( flagPos )
            flagPos += 1
            flags.add( f )
            if ( f & 8 ) != 0
            {
                Int32 repeat = this.u8( flagPos )
                flagPos += 1
                Int32 r = 0
                while r < repeat
                {
                    flags.add( f )
                    i += 1
                    r += 1
                }
            }
            i += 1
        }
        if flags.length < nPoints
        {
            this._lastError = 2
            ret glyph
        }
        List<Float32> xs = List<Float32>( nPoints )
        List<Float32> ys = List<Float32>( nPoints )
        List<Int32> ons = List<Int32>( nPoints )
        Int32 x = 0
        Int32 y = 0
        i = 0
        while i < nPoints
        {
            Int32 fi = i
            Int32 f = flags[fi]
            ons.add( f & 1 )
            if ( f & 2 ) != 0
            {
                Int32 dx = this.u8( flagPos )
                flagPos += 1
                if ( f & 16 ) == 0 { dx = 0 - dx }
                x = x + dx
            }
            elif ( f & 16 ) == 0
            {
                x = x + this.s16( flagPos )
                flagPos += 2
            }
            xs.add( x.toFloat32() )
            i += 1
        }
        i = 0
        while i < nPoints
        {
            Int32 fi = i
            Int32 f = flags[fi]
            if ( f & 4 ) != 0
            {
                Int32 dy = this.u8( flagPos )
                flagPos += 1
                if ( f & 32 ) == 0 { dy = 0 - dy }
                y = y + dy
            }
            elif ( f & 32 ) == 0
            {
                y = y + this.s16( flagPos )
                flagPos += 2
            }
            ys.add( y.toFloat32() )
            i += 1
        }

        Int32 c = 0
        Int32 begin = 0
        while c < contours
        {
            Int32 ce = c
            Int32 end = this.u16( this._glyf + start + 10 + ce * 2 )
            Int32 before = glyph.pointCount()
            Int32 ip = begin
            Int32 guard = 0
            while ip <= end && guard < 20000
            {
                guard += 1
                Int32 p0 = ip
                Float32 ax = xs[p0]
                Float32 ay = ys[p0]
                Int32 aOn = ons[p0]
                if aOn == 1
                {
                    glyph.addPoint( ax, ay )
                }
                Int32 jp = ip + 1
                if jp > end { jp = begin }
                Int32 p1 = jp
                Float32 bx = xs[p1]
                Float32 by = ys[p1]
                Int32 bOn = ons[p1]
                if bOn == 1
                {
                    ip = ip + 1
                }
                else
                {
                    Int32 kp = jp + 1
                    if kp > end { kp = begin }
                    Int32 p2 = kp
                    Float32 cx = xs[p2]
                    Float32 cy = ys[p2]
                    Int32 cOn = ons[p2]
                    Int32 advance = 2
                    if cOn == 0
                    {
                        cx = ( bx + cx ) / 2.0f
                        cy = ( by + cy ) / 2.0f
                        advance = 1
                    }
                    if aOn == 0
                    {
                        ax = ( ax + bx ) / 2.0f
                        ay = ( ay + by ) / 2.0f
                    }
                    this.sampleCurve( glyph, ax, ay, bx, by, cx, cy, steps )
                    ip = ip + advance
                }
            }
            if glyph.pointCount() > before
            {
                glyph.closeContour()
            }
            begin = end + 1
            c += 1
        }
        ret glyph
    }
}
