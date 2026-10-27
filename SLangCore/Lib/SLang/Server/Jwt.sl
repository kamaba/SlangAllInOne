import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Jwt.sl — JWT claims 读取 + HS256 签验（P3 decode → P5 sign/verify）
    #
    # SLang.Jwt.decode：不验签（P0-P3 形态保留——仅解 payload）；
    # SLang.Jwt.sign( claims, secret, expiresInSeconds )：HS256 签发
    #（RFC 7518 §3.2：HMAC-SHA256(key, header.payload)，base64url 无填充）；
    # SLang.Jwt.verify( token, secret )：全量验签（header.alg 必须 HS256 +
    # 签名逐字节比对 + 过期检查），通过返回 JwtClaims、失败返回 null。
    # 哈希原语 = Std.Encoding.Sha256.hmac（C VM core_sha256.c，P5 落地——
    # 此前「P0-P3 不自造哈希」的封锁解除）。
    # base64url 编码复用 Base64.encodeToString + 归一（'+'→'-'、'/'→'_'、
    # 去 '='）；解码侧 _normB64Url 反向（P3 已有）。
    # claims 载体 = Map<string,string>（JwtClaims.put 写入）；方法名
    # claim/put 避开 get/set 关键字（HttpClient 改名同款纪律）。
    # 使用纪律（设计 §4.11）：decode 仍仅用于己方签发且签验发生在别处的
    # 同源身份读取；第三方 token 验真用 verify。
    # ============================================================================

    # JWT claims 视图（decode 产物；sub/exp 标准化 + 自定义 claim 直读）
    public class JwtClaims
    {
        Map<string,string> _c = new()

        # 任意自定义 claim（缺失 null；嵌套对象/数组 claim 存其 JSON 文本）
        public string claim( string name )
        {
            if this._c.containsKey( name )
            {
                ret this._c._getItem_( name )
            }
            ret null
        }

        # 写入（sign 场景预备，P5+；运行期一般只读）
        public void put( string name, string val )
        {
            this._c.add( name, val )
        }

        # "sub" 标准 claim（缺失 null）
        get string subject()
        {
            ret this.claim( "sub" )
        }

        # "exp" → Int64 秒级时间戳（缺失/非数字 = 0）
        get Int64 expiresAt()
        {
            string e = this.claim( "exp" )
            if e == null
            {
                ret 0
            }
            Int64 v = 0
            Int32 len = SystemStringLength( e )
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( e, i )
                if c < 48 || c > 57
                {
                    ret 0
                }
                v = v * 10 + ( c - 48 )
            }
            ret v
        }

        # 现时 > exp（exp 缺失恒 false）——decode 不自动拒，业务自行判（§4.11）
        get bool expired()
        {
            Int64 e = this.expiresAt
            if e <= 0
            {
                ret false
            }
            Int64 nowMs = OS.Timer.now()
            Int64 nowSec = nowMs / 1000
            if nowSec > e
            {
                ret true
            }
            ret false
        }
    }

    public class Jwt
    {
        # 解码 JWT（不验签）；格式非法（非三段 / base64 坏 / 非法 JSON /
        # payload 非对象）→ null
        public static JwtClaims decode( string token )
        {
            if token == null
            {
                ret null
            }
            Int32 len = SystemStringLength( token )
            # 两个 '.' 定位（header.payload.signature）
            Int32 d1 = -1
            Int32 d2 = -1
            for Int32 i = 0, i < len, i = i + 1
            {
                if SystemStringCharCodeAt( token, i ) == 46
                {
                    if d1 < 0
                    {
                        d1 = i
                    }
                    elif d2 < 0
                    {
                        d2 = i
                    }
                    else
                    {
                        # 第三段点：非法
                        ret null
                    }
                }
            }
            if d1 <= 0 || d2 <= d1 + 1 || d2 == len - 1
            {
                ret null
            }
            string payload = SystemStringRange( token, d1 + 1, d2 )
            string b64 = Jwt._normB64Url( payload )
            string text = ""
            label d
            {
                text = Base64.decodeString( b64 )
            }
            catch
            {
                ret null
            }
            if text == null
            {
                ret null
            }
            BaseJson j = BaseJson.parse( text )
            if j.isEmpty
            {
                ret null
            }

            if j.value.isObject == false
            {
                ret null
            }
            # 顶层键全部读进 Map<string,string>（标量原文本；嵌套 JSON 文本；
            # null 值跳过 = claim 缺失）
            JwtClaims c = JwtClaims()
            Array<string> ks = j.value.keys()
            if ks != null
            {
                Int32 n = ks.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    string k = ks[i]
                    JsonValue v = j.value._getItem_( k )
                    string cv = null

                    if v.isObject || v.isArray
                    {
                        cv = v.toJson()
                    }
                    elif v.isBool
                    {
                        if v.asBool()
                        {
                            cv = "true"
                        }
                        else
                        {
                            cv = "false"
                        }
                    }
                    elif v.isString || v.isNumber
                    {
                        cv = v.asString()
                    }

                    # null / 缺失 → cv 保持 null → 不写入（claim 缺失语义）
                    if cv != null
                    {
                        c.put( k, cv )
                    }
                }
            }
            ret c
        }

        # base64url → 标准字母（'-'→'+'、'_'→'/'）+ 补 '=' 填充至 4 倍长
        static string _normB64Url( string s )
        {
            Int32 len = SystemStringLength( s )
            ByteBuffer b = ByteBuffer( len + 4 )
            Int32 kept = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c == 45
                {
                    c = 43
                }
                elif c == 95
                {
                    c = 47
                }
                elif c == 61
                {
                    # 已带填充：跳过（统一由尾部补齐）
                    continue
                }
                b.writeU8( SystemConvertUInt8( c ) )
                kept = kept + 1
            }
            Int32 mod = ( kept & 3 )
            if mod == 2
            {
                b.writeU8( 61 )
                b.writeU8( 61 )
            }
            elif mod == 3
            {
                b.writeU8( 61 )
            }
            string res = b.toString()
            b.release()
            ret res
        }

        # ── HS256 签发 / 验签（P5，§4.11）──

        # 签发 JWT（便捷形态：密钥取 ServerConfig.jwtSecret——未配置抛
        # ServerError.MissingJwtSecret）
        public static string sign( JwtClaims claims, Int64 expiresInSeconds ) throws
        {
            ServerConfig cfg = HttpServerCore._cfg
            string secret = ""
            if cfg != null
            {
                secret = cfg.jwtSecret
            }
            if secret == null
            {
                secret = ""
            }
            if SystemStringLength( secret ) == 0
            {
                throw ServerError.MissingJwtSecret
            }
            ret Jwt.sign( claims, secret, expiresInSeconds )
        }

        # 验签 JWT（便捷形态：密钥取 ServerConfig.jwtSecret——未配置恒 null）
        public static JwtClaims verify( string token )
        {
            ServerConfig cfg = HttpServerCore._cfg
            if cfg == null
            {
                ret null
            }
            string secret = cfg.jwtSecret
            if secret == null
            {
                ret null
            }
            ret Jwt.verify( token, secret )
        }

        # 签发 JWT（HS256）：
        #   claims = 待写入的声明（sub/exp 由参数显式管理，其余经 put 自填）；
        #   secret = HMAC 密钥；expiresInSeconds > 0 时自动写入 "exp"
        #（Int64 秒级时间戳 = now + n），<= 0 不写 exp（永不过期——业务自慎）；
        #   "iat"（签发时刻）恒写入。
        # 输出 = base64url(header).base64url(payload).base64url(hmac)。
        # secret null/空串 → 抛 ServerError（协议防御：无密钥签发无意义）
        public static string sign( JwtClaims claims, string secret, Int64 expiresInSeconds ) throws
        {
            if secret == null || SystemStringLength( secret ) == 0
            {
                throw ServerError.MissingJwtSecret
            }
            if claims == null
            {
                claims = JwtClaims()
            }
            Int64 nowSec = OS.Timer.now() / 1000
            claims.put( "iat", nowSec.toString() )
            if expiresInSeconds > 0
            {
                claims.put( "exp", ( nowSec + expiresInSeconds ).toString() )
            }
            # header（固定 {"alg":"HS256","typ":"JWT"}）+ payload（组 JSON 文本）
            string headerText = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
            string payloadText = Jwt._claimsToJson( claims )
            string signingInput = Jwt._encodeB64Url( headerText ) + "." + Jwt._encodeB64Url( payloadText )
            # 签名 = HMAC-SHA256(secret, signingInput)
            ByteBuffer kb = ByteBuffer.fromString( secret )
            ByteBuffer mb = ByteBuffer.fromString( signingInput )
            ByteBuffer mac = Sha256.hmac( kb, mb )
            kb.release()
            mb.release()
            string sigText = Jwt._encodeB64UrlBytes( mac )
            mac.release()
            ret signingInput + "." + sigText
        }

        # 验签 JWT（HS256）：
        #   全量校验 = 三段格式 + header.alg=="HS256" + 签名逐字节比对 +
        #   exp 过期检查（exp 已过 → null）。
        #   任一环节失败返回 null（不抛——调用方按未认证处理）。
        #   注意：decode 的「不验签读取」语义独立保留；本方法才是对
        #   第三方 token 验真的正确入口。
        public static JwtClaims verify( string token, string secret )
        {
            if secret == null || SystemStringLength( secret ) == 0
            {
                ret null
            }
            if token == null
            {
                ret null
            }
            Int32 len = SystemStringLength( token )
            Int32 d1 = -1
            Int32 d2 = -1
            for Int32 i = 0, i < len, i = i + 1
            {
                if SystemStringCharCodeAt( token, i ) == 46
                {
                    if d1 < 0
                    {
                        d1 = i
                    }
                    elif d2 < 0
                    {
                        d2 = i
                    }
                    else
                    {
                        ret null
                    }
                }
            }
            if d1 <= 0 || d2 <= d1 + 1 || d2 == len - 1
            {
                ret null
            }
            string hPart = SystemStringRange( token, 0, d1 )
            string signingInput = SystemStringRange( token, 0, d2 )
            string sigPart = SystemStringRange( token, d2 + 1, len )

            # header 校验：alg 必须 HS256（拒绝 "none" 与其他算法——防降级攻击）
            string headerText = ""
            bool dhThrew = false
            label dh
            {
                headerText = Base64.decodeString( Jwt._normB64Url( hPart ) )
            }
            catch
            {
                dhThrew = true
            }
            if dhThrew
            {
                ret null
            }
            if headerText == null
            {
                ret null
            }
            BaseJson hj = BaseJson.parse( headerText )
            if hj.isEmpty
            {
                ret null
            }
            if hj.value.isObject == false
            {
                ret null
            }
            JsonValue algV = hj.value._getItem_( "alg" )
            if algV == null || algV.isString == false
            {
                ret null
            }
            if algV.asString() != "HS256"
            {
                ret null
            }

            # 签名重算比对（逐字节，恒时语义不在 v1 范围——本地单机威胁模型接受）
            ByteBuffer kb = ByteBuffer.fromString( secret )
            ByteBuffer mb = ByteBuffer.fromString( signingInput )
            ByteBuffer mac = null
            bool mvThrew = false
            label mv
            {
                mac = Sha256.hmac( kb, mb )
            }
            catch
            {
                mvThrew = true
            }
            if mvThrew
            {
                kb.release()
                mb.release()
                ret null
            }
            kb.release()
            mb.release()
            ByteBuffer sigBuf = null
            bool dvThrew = false
            label dv
            {
                # 签名段是任意二进制（HMAC-SHA256 值域含 0x00），decodeString
                # 的内嵌 NUL 截断语义会在 0x00 处截断签名 → 比对失配；须走
                # 二进制安全链 fromString + Base64.decode，不经字符串
                ByteBuffer sigSrc = ByteBuffer.fromString( Jwt._normB64Url( sigPart ) )
                sigBuf = Base64.decode( sigSrc )
                sigSrc.release()
            }
            catch
            {
                dvThrew = true
            }
            if dvThrew
            {
                sigBuf = null
            }
            bool sigOk = false
            if sigBuf != null
            {
                if sigBuf.readableBytes == mac.readableBytes
                {
                    sigOk = Jwt._bytesEqual( sigBuf, mac )
                }
                sigBuf.release()
            }
            mac.release()
            if sigOk == false
            {
                ret null
            }

            # payload 解码 + 过期检查（exp 已过 → null）
            JwtClaims c = Jwt.decode( token )
            if c == null
            {
                ret null
            }
            if c.expired
            {
                ret null
            }
            ret c
        }

        # claims → 紧凑 JSON 文本（{"k":"v",...}；值含引号/反斜杠时转义）
        static string _claimsToJson( JwtClaims c )
        {
            List<string> ks = c._c.keys
            Int32 n = ks.length
            string text = ""
            for Int32 i = 0, i < n, i = i + 1
            {
                string k = ks[i]
                string v = c._c._getItem_( k )
                if SystemStringLength( text ) > 0
                {
                    text = text + ","
                }
                text = text + "\"" + Jwt._escapeJson( k ) + "\":\"" + Jwt._escapeJson( v ) + "\""
            }
            ret "{" + text + "}"
        }

        # JSON 字符串转义（引号 / 反斜杠 / 控制字符按 \u00XX）
        static string _escapeJson( string s )
        {
            if s == null
            {
                ret ""
            }
            Int32 len = SystemStringLength( s )
            ByteBuffer b = ByteBuffer( len + 8 )
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 ch = SystemStringCharCodeAt( s, i )
                if ch == 34
                {
                    b.writeString( "\\\"" )
                }
                elif ch == 92
                {
                    b.writeString( "\\\\" )
                }
                elif ch < 32
                {
                    # \u00XX（两位十六进制）
                    b.writeString( "\\u00" )
                    Int32 hi = ( ch >> 4 ) & 0x0F
                    Int32 lo = ch & 0x0F
                    b.writeU8( SystemConvertUInt8( Jwt._hexDigit( hi ) ) )
                    b.writeU8( SystemConvertUInt8( Jwt._hexDigit( lo ) ) )
                }
                else
                {
                    b.writeString( SystemStringRange( s, i, i + 1 ) )
                }
            }
            string res = b.toString()
            b.release()
            ret res
        }

        # 0-15 → '0'..'f' 小写十六进制字符码
        static Int32 _hexDigit( Int32 v )
        {
            if v < 10
            {
                ret 48 + v
            }
            ret 87 + v
        }

        # 文本 → base64url（标准编码后归一：'+'→'-'、'/'→'_'、剥 '='）
        static string _encodeB64Url( string s ) throws
        {
            ByteBuffer b = ByteBuffer.fromString( s )
            string res = Jwt._encodeB64UrlBytes( b )
            b.release()
            ret res
        }

        # 缓冲 → base64url（同上归一；消费后由调用方释放 mac）
        static string _encodeB64UrlBytes( ByteBuffer src ) throws
        {
            string std = Base64.encodeToString( src )
            Int32 len = SystemStringLength( std )
            ByteBuffer b = ByteBuffer( len + 1 )
            Int32 kept = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 ch = SystemStringCharCodeAt( std, i )
                if ch == 61
                {
                    break
                }
                if ch == 43
                {
                    ch = 45
                }
                elif ch == 47
                {
                    ch = 95
                }
                b.writeU8( SystemConvertUInt8( ch ) )
                kept = kept + 1
            }
            string res = SystemStringRange( b.toString(), 0, kept )
            b.release()
            ret res
        }

        # 逐字节相等（长度不等调用方已排除；读视图推进独立于源）
        static bool _bytesEqual( ByteBuffer a, ByteBuffer b )
        {
            Int32 n = a.readableBytes
            for Int32 i = 0, i < n, i = i + 1
            {
                UInt8 x = a.readU8()
                UInt8 y = b.readU8()
                if x != y
                {
                    ret false
                }
            }
            ret true
        }
    }
}


