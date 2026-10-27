# ============================================================================
# Std/Encoding/Sha256.sl — 编码层：SHA-256 摘要 + HMAC-SHA256（FIPS 180-4 / RFC 2104）
#
# 纯静态工具类：本体在 C VM 端（csimple_lang/src/core/sl_core_sha256.c，
# .NET 权威实现交叉验证），SL 层无状态。
# 摘要语义：任意长度输入 -> 32 字节（256 位）大端摘要；
# HMAC 语义：RFC 2104 H(K0^opad || H(K0^ipad || msg))，键长任意
#（> 64 字节先哈希），键/消息均可为空。
# 跨模块访问：经 Core.ByteBuffer 的 handle / fromHandle 桥接注册表 id。
# 守卫约定：入参缓冲已释放（Released）或计算失败时抛错。
# 便捷重载：digest(string) / digestHex 文本适配（同 Sha1 形态）；
# hmac 亦有 string,string 便捷形态与 hmacHex 输出。
# 主要消费方：SLangServer Jwt HS256 签验（RFC 7518 §3.2）。
# ============================================================================

public enum Sha256Error extends Error
{
    DigestFailed = { code = 1 }
    HmacFailed = { code = 2 }
}

public class Sha256 extends Object
{
    # ── 摘要 ──

    # 计算 src 可读区的 SHA-256 摘要，返回新 32 字节缓冲；src 索引不变
    public static ByteBuffer digest( ByteBuffer src ) throws
    {
        if SystemByteBufferIsReleased( src.handle )
        {
            throw BufferError.Released
        }
        var id = SystemSha256( src.handle )
        if id == 0
        {
            throw Sha256Error.DigestFailed
        }
        ret ByteBuffer.fromHandle( id )
    }

    # 计算 UTF-8 文本字节的 SHA-256 摘要，返回新缓冲（中间缓冲即时释放）
    public static ByteBuffer digest( string src ) throws
    {
        var b = ByteBuffer.fromString( src )
        var d = Sha256.digest( b )
        b.release()
        ret d
    }

    # 摘要并输出为 64 字符小写十六进制串
    public static string digestHex( ByteBuffer src ) throws
    {
        var d = Sha256.digest( src )
        var text = d.toHex()
        d.release()
        ret text
    }

    # 文本到文本高频快捷入口：UTF-8 文本 -> 小写十六进制摘要
    public static string digestHex( string src ) throws
    {
        var b = ByteBuffer.fromString( src )
        var text = Sha256.digestHex( b )
        b.release()
        ret text
    }

    # ── HMAC-SHA256 ──

    # 计算消息可读区在密钥下的 HMAC-SHA256，返回新 32 字节缓冲；
    # key/src 索引均不变；键/消息空可读区均合法
    public static ByteBuffer hmac( ByteBuffer key, ByteBuffer src ) throws
    {
        if SystemByteBufferIsReleased( key.handle )
        {
            throw BufferError.Released
        }
        if SystemByteBufferIsReleased( src.handle )
        {
            throw BufferError.Released
        }
        var id = SystemHmacSha256( key.handle, src.handle )
        if id == 0
        {
            throw Sha256Error.HmacFailed
        }
        ret ByteBuffer.fromHandle( id )
    }

    # 文本便捷形态：UTF-8 密钥 + UTF-8 消息 -> 新缓冲（中间缓冲即时释放）
    public static ByteBuffer hmac( string key, string src ) throws
    {
        var kb = ByteBuffer.fromString( key )
        var mb = ByteBuffer.fromString( src )
        var d = Sha256.hmac( kb, mb )
        kb.release()
        mb.release()
        ret d
    }

    # HMAC 并输出为 64 字符小写十六进制串
    public static string hmacHex( ByteBuffer key, ByteBuffer src ) throws
    {
        var d = Sha256.hmac( key, src )
        var text = d.toHex()
        d.release()
        ret text
    }

    # 文本到文本高频快捷入口：UTF-8 密钥 + UTF-8 消息 -> 小写十六进制 HMAC
    public static string hmacHex( string key, string src ) throws
    {
        var kb = ByteBuffer.fromString( key )
        var mb = ByteBuffer.fromString( src )
        var text = Sha256.hmacHex( kb, mb )
        kb.release()
        mb.release()
        ret text
    }
}
