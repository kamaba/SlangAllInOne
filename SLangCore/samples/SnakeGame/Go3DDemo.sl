import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# Go3DDemo - FairyGUI GoWrapper equivalent demo (2026-11-19):
# CPU software-rendered spinning wireframe cube -> RGBA8 buffer ->
# RenderTexture.updatePixels in-place update -> go3d element quad.
# Buffer size follows the element texture. Edges = DDA lines.

public class Go3DDemo
{
    static bool ok = false
    static string lastError = ""
    static Int64 bufPtr = 0
    static Int32 bufW = 128
    static Int32 bufH = 128
    static Int32 goTexIdx = 0 - 1
    static FairyPackage boundPkg = null

    public static bool attach( FairyPackage pkg )
    {
        if pkg == null
        {
            ret false
        }
        Int32 qi = pkg.quadIndex( "m_go3d" )
        if qi < 0
        {
            lastError = "go3d element missing"
            ret false
        }
        Int32 ti = pkg.quadTexIndex( "m_go3d" )
        if ti <= 0
        {
            lastError = "go3d texture group missing"
            ret false
        }
        Int32 tw = pkg.texWidthAt( ti )
        Int32 th = pkg.texHeightAt( ti )
        if tw <= 0 || th <= 0
        {
            lastError = "go3d texture size invalid"
            ret false
        }
        bufW = tw
        bufH = th
        bufPtr = Memory.alloc( bufW * bufH * 4 )
        if bufPtr == 0
        {
            lastError = "buffer alloc failed"
            ret false
        }
        boundPkg = pkg
        goTexIdx = ti
        ok = true
        ret true
    }

    public static bool ready()
    {
        ret ok
    }

    public static string statusText()
    {
        if ok
        {
            ret "go3d=" + bufW.toString() + "x" + bufH.toString()
        }
        ret "go3d=off(" + lastError + ")"
    }

    static void clearBuf()
    {
        Int32 n = bufW * bufH
        Int32 i = 0
        while i < n
        {
            Memory.writeI8( bufPtr, i * 4, SystemConvertUInt8( 10 ) )
            Memory.writeI8( bufPtr, i * 4 + 1, SystemConvertUInt8( 16 ) )
            Memory.writeI8( bufPtr, i * 4 + 2, SystemConvertUInt8( 10 ) )
            Memory.writeI8( bufPtr, i * 4 + 3, SystemConvertUInt8( 255 ) )
            i = i + 1
        }
    }

    # 帧内容更新：旋转线框立方体（GoWrapper 语义的软渲染源）
    public static void update( Int64 nowMs )
    {
        if !ok
        {
            ret
        }
        clearBuf()
        Float32 yaw = nowMs.toFloat32() * 0.001f
        Float32 cy = Mathf.cos( yaw )
        Float32 sy = Mathf.sin( yaw )
        Float32 pitch = 0.55f
        Float32 cxr = Mathf.cos( pitch )
        Float32 sxr = Mathf.sin( pitch )
        List<Float32> vx = List<Float32>( 8 )
        List<Float32> vy = List<Float32>( 8 )
        Int32 vi = 0
        while vi < 8
        {
            Float32 x = 46.0f
            if vi == 1 || vi == 3 || vi == 5 || vi == 7
            {
                x = 0.0f - 46.0f
            }
            Float32 y = 46.0f
            if vi >= 4
            {
                y = 0.0f - 46.0f
            }
            Float32 z = 46.0f
            if vi == 2 || vi == 3 || vi == 6 || vi == 7
            {
                z = 0.0f - 46.0f
            }
            Float32 rx = x * cy + z * sy
            Float32 rz = 0.0f - x * sy + z * cy
            Float32 ry = y * cxr - rz * sxr
            Float32 rz2 = y * sxr + rz * cxr
            Float32 zz = rz2 + 192.0f
            Float32 k = 300.0f / zz
            Float32 px = bufW.toFloat32() * 0.5f + rx * k
            Float32 py = bufH.toFloat32() * 0.5f - ry * k
            vx.add( px )
            vy.add( py )
            vi = vi + 1
        }
        # 立方体 12 边：前后面（绿）/连接边（青黄）
        drawEdge( vx, vy, 0, 1, 120, 255, 120 )
        drawEdge( vx, vy, 1, 3, 120, 255, 120 )
        drawEdge( vx, vy, 3, 2, 120, 255, 120 )
        drawEdge( vx, vy, 2, 0, 120, 255, 120 )
        drawEdge( vx, vy, 4, 5, 160, 220, 255 )
        drawEdge( vx, vy, 5, 7, 160, 220, 255 )
        drawEdge( vx, vy, 7, 6, 160, 220, 255 )
        drawEdge( vx, vy, 6, 4, 160, 220, 255 )
        drawEdge( vx, vy, 0, 4, 255, 220, 120 )
        drawEdge( vx, vy, 1, 5, 255, 220, 120 )
        drawEdge( vx, vy, 3, 7, 255, 220, 120 )
        drawEdge( vx, vy, 2, 6, 255, 220, 120 )
        boundPkg.updateTexPixels( goTexIdx, bufPtr )
    }

    # DDA 直线（RGB 写入，越界裁剪）
    static void drawEdge( List<Float32> vx, List<Float32> vy, Int32 a, Int32 b,
        Int32 r, Int32 g, Int32 bl )
    {
        Float32 x0 = vx[a]
        Float32 y0 = vy[a]
        Float32 x1 = vx[b]
        Float32 y1 = vy[b]
        Float32 dx = x1 - x0
        Float32 dy = y1 - y0
        Int32 steps = SystemConvertInt32( Mathf.abs( dx ) )
        Int32 sy = SystemConvertInt32( Mathf.abs( dy ) )
        if sy > steps
        {
            steps = sy
        }
        if steps < 1
        {
            steps = 1
        }
        Float32 sx = dx / steps.toFloat32()
        Float32 syf = dy / steps.toFloat32()
        Float32 x = x0
        Float32 y = y0
        Int32 i = 0
        while i <= steps
        {
            Int32 px = x.toInt32()
            Int32 py = y.toInt32()
            if px >= 0 && px < bufW && py >= 0 && py < bufH
            {
                Int32 o = ( py * bufW + px ) * 4
                Memory.writeI8( bufPtr, o, SystemConvertUInt8( r ) )
                Memory.writeI8( bufPtr, o + 1, SystemConvertUInt8( g ) )
                Memory.writeI8( bufPtr, o + 2, SystemConvertUInt8( bl ) )
                Memory.writeI8( bufPtr, o + 3, SystemConvertUInt8( 255 ) )
            }
            x = x + sx
            y = y + syf
            i = i + 1
        }
    }
}
