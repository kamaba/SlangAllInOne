import SLangRender;
import SLangAudio;
import Math;
import Std;

# 共享像素/纹理辅助函数（各 phase 分组类经 RenderTestHelpers.* 调用）：
#   f2b                    [0,1] 浮点 -> 0..255 字节（钳制 + 四舍五入）
#   sampleChannel          RGBA8 帧缓冲取单通道
#   makeGradientTexture    渐变贴图逐像素构建（Texture 门面类）
#   textureToRenderTexture Texture -> RenderTexture（RGBA8 内存直传）
public class RenderTestHelpers
{

    # Texture（门面 Float32 RGBA）-> RGBA8 显存块 -> RenderTexture 上屏
    public static SLang.RenderTexture textureToRenderTexture( Texture tex )
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
                Memory.writeI8( ptr, o, f2b( c.r ) )
                Memory.writeI8( ptr, o + 1, f2b( c.g ) )
                Memory.writeI8( ptr, o + 2, f2b( c.b ) )
                Memory.writeI8( ptr, o + 3, f2b( c.a ) )
                x = x + 1
            }
            y = y + 1
        }
        ret SLang.RenderTexture.createRgba( ptr, tex.width, tex.height )
    }

    # [0,1] 浮点 -> 0..255 字节（钳制 + 四舍五入）


    # [0,1] 浮点 -> 0..255 字节（钳制 + 四舍五入）
    public static Int32 f2b( Float32 f )
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


    # 采样像素通道：pixels 块内 (x,y) 像素的 c 通道（0=R 1=G 2=B 3=A）
    public static Int32 sampleChannel( Int64 pixels, Int32 w, Int32 x, Int32 y, Int32 c )
    {
        Int32 off = ( y * w + x ) * 4 + c
        ret Memory.readUInt8( pixels, off )
    }

    # 生成 64x64 RGBA8 渐变贴图像素块（绿 -> 品红，沿 u 方向），
    # 返回 Memory.alloc 块地址（top-down 行序契约）


    # 生成 64x64 RGBA8 渐变贴图像素块（绿 -> 品红，沿 u 方向），
    # 返回 Memory.alloc 块地址（top-down 行序契约）
    public static Int64 makeGradientTexture()
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
}
