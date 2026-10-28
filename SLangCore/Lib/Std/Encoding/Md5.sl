# ============================================================================
# Std/Encoding/Md5.sl — 编码层：MD5 摘要（RFC 1321）
#
# 纯静态工具类：本体在 C VM 端（csimple_lang/src/core/sl_core_md5.c，
# RFC 1321 向量交叉验证），SL 层无状态。
# 摘要语义：任意长度输入 -> 16 字节（128 位）小端摘要；
# 警告：MD5 不具备抗碰撞性，仅用于强制兼容的历史场景
#（RuoYi 蓝本 sys_user.password = MD5(pwd)），禁止用于任何安全用途。
# 跨模块访问：经 Core.ByteBuffer 的 handle / fromHandle 桥接注册表 id。
# 守卫约定：入参缓冲已释放（Released）或计算失败时抛错。
# 便捷重载：digest(string) 文本输入适配、digestHex 输出（同 Sha1/Sha256 形态）。
# 主要消费方：slang-server Security 密码兼容（SecurityUtils.EncryptPassword）。
# ============================================================================

public enum Md5Error extends Error
{
    DigestFailed = { code = 1 }
}

public class Md5 extends Object
{
    # ── 摘要 ──

    # 计算 src 可读区的 MD5 摘要，返回新 16 字节缓冲；src 索引不变
    public static ByteBuffer digest( ByteBuffer src ) throws
    {
        if SystemByteBufferIsReleased( src.handle )
        {
            throw BufferError.Released
        }
        var id = SystemMd5( src.handle )
        if id == 0
        {
            throw Md5Error.DigestFailed
        }
        ret ByteBuffer.fromHandle( id )
    }

    # 计算 UTF-8 文本字节的 MD5 摘要，返回新缓冲（中间缓冲即时释放）
    public static ByteBuffer digest( string src ) throws
    {
        var b = ByteBuffer.fromString( src )
        var d = Md5.digest( b )
        b.release()
        ret d
    }

    # 摘要并输出为 32 字符小写十六进制串
    public static string digestHex( ByteBuffer src ) throws
    {
        var d = Md5.digest( src )
        var text = d.toHex()
        d.release()
        ret text
    }

    # 文本到文本高频快捷入口：UTF-8 文本 -> 小写十六进制摘要
    public static string digestHex( string src ) throws
    {
        var b = ByteBuffer.fromString( src )
        var text = Md5.digestHex( b )
        b.release()
        ret text
    }
}
