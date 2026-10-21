import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Jwt.sl — JWT claims 读取（P3，§4.11）
    #
    # SLang.Jwt.decode：不验签（P0-P3 明确不自造哈希；sign/verify 挂靠
    # 未来 crypto 库留 P5+）；格式非法 → null。实现零新依赖：
    #   payload 段 base64url 解码复用 Std/Encoding/Base64（RFC 7515：
    #   '-'→'+'、'/'→'_'、去 '=' 填充 → 解码前反归一）+ BaseJson.parse。
    # claims 内部载体 = Map<string,string>；方法名 claim/put 避开 get/set
    # 关键字（HttpClient.getHeader/setHeader 改名同款纪律）。
    # 使用纪律（设计 §4.11）：仅用于己方签发且签验发生在别处的同源身份
    # 读取；第三方 token 验真必须等 verify（P5+）。
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
    }
}


