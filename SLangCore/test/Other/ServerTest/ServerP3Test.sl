import Std;
import Core;
import SLangServer;

# ============================================================================
# ServerP3Test.sl -- SLangServer P3 验收（ServerTest 宿主）
# 设计契约：SERVER_DESIGN.md §8 P3 验收（§4.8 OpenAPI 文档 / §4.11 auth）
#
#   T1  openapi.json 生成：路由元数据（summary/tags/param/requestBody/
#       response/security）→ OpenAPI 3.0.3 骨架断言（paths/parameters in:path/
#       requestBody $ref/components.schemas/securitySchemes/operation security/
#       嵌套 DTO schema/example）
#   T2  /docs 页面：自包含 HTML（DOCTYPE + openapi.json 同源引用）+ docs(false)
#       关闭开关（start 后 404）+ 用户已注册 /docs 让位
#   T3  auth 三挂法：① Bearer（无头/坏 token → 401 + WWW-Authenticate；
#       好 token → 200 + req.auth=JwtClaims 读 claim）+ .skip 白名单放行
#       ② API Key（自定义 header + key 校验回调）③ 通用回调（双头组合校验）
#   T4  Jwt.decode：三段式手造 token（base64url）→ claims 读取（subject/
#       claim/自定义）+ expired（未来 exp=false / 过去 exp=true / 缺失恒
#       false）+ 坏格式（段数错/base64 坏/非对象 payload）→ null
#   T5  importOpenApi：spec 文件导入 → 未注册路径文档路由（命中 501 +
#       added 计数）+ 真实路由覆盖让位（元数据继承进 openapi.json）
#   T6  maxConnections：上限 1 → 第二连接 503（协议层应答）
#   T7  swaggerUI：GET /swagger 自研 index（外链 dist 资产 + /openapi.json）
#       + /swagger/<file> dist 直出（MIME 随扩展名）+ '..' 段 403 + 未命中
#       放行（404 尾环）+ 用户已注册 /swagger 让位
#
# 端口：19431-19436（避开 P1/P1.5/P2 的 19401-19424）。
# 编写约定同 ServerP2Test.sl（原始 HTTP 客户端助手同款实现）。
# 断言文本回避 "$"（字符串插值前缀，字面量含 $ 会破坏编译——$ref 以
# "#/components/schemas/" 前缀断言替代）。
# ============================================================================

# 样例 DTO（探针法 schema 用；@Serializable 必备）
@Serializable()
class P3User
{
    public string name = ""
    public Int32 age = 0

    _init_()
    {
        this.name = "alice"
        this.age = 30
    }
}

# 嵌套 DTO（T1 嵌套 schema 断言用）
@Serializable()
class P3Order
{
    public string id = ""
    public P3User buyer = null

    _init_()
    {
        this.id = "o1"
        P3User u = P3User()
        this.buyer = u
    }
}

ServerP3Test
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerP3Test] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerP3Test] " + name + " : FAIL" )
        }
    }

    # ── 通用助手（ServerP2Test 同款）──

    static Int32 sfFind( string text, string sub )
    {
        Int32 tlen = SystemStringLength( text )
        Int32 slen = SystemStringLength( sub )
        if slen == 0
        {
            ret 0
        }

        if tlen < slen
        {
            ret -1
        }

        Int32 last = tlen - slen
        for Int32 i = 0, i <= last, i = i + 1
        {
            bool matched = true
            for Int32 j = 0, j < slen, j = j + 1
            {
                if SystemStringCharCodeAt( text, i + j ) != SystemStringCharCodeAt( sub, j )
                {
                    matched = false
                    break
                }
            }

            if matched
            {
                ret i
            }
        }
        ret -1
    }

    static string rawReq( Int32 port, string reqText ) throws
    {
        P3RawClient c = P3RawClient.connect( port )
        c.send( reqText )
        P3Resp r = c.readResp()
        c.close()
        ret r._head + "\n" + r._body
    }

    # base64 标准字母 → base64url（'+'→'-'、'/'→'_'、去 '=' 填充）
    static string b64url( string s ) throws
    {
        string b = Base64.encodeToString( s )
        Int32 len = SystemStringLength( b )
        ByteBuffer bufOut = ByteBuffer( len + 4 )
        for Int32 i = 0, i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( b, i )
            if c == 43
            {
                c = 45
            }
            elif c == 47
            {
                c = 95
            }
            elif c == 61
            {
                continue
            }
            bufOut.writeU8( SystemConvertUInt8( c ) )
        }
        string res = bufOut.toString()
        bufOut.release()
        ret res
    }

    # 十六进制串 → Int32（chunk size 行解析；非法返回 -1）
    static Int32 hexVal( string s )
    {
        Int32 len = SystemStringLength( s )
        if len == 0
        {
            ret -1
        }

        Int32 v = 0
        for Int32 i = 0, i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            Int32 d = -1
            if c >= 48 && c <= 57
            {
                d = c - 48
            }
            elif c >= 97 && c <= 102
            {
                d = c - 87
            }
            elif c >= 65 && c <= 70
            {
                d = c - 55
            }

            if d < 0
            {
                ret -1
            }
            v = v * 16 + d
        }
        ret v
    }

    # 头区提取整数头（如 Content-Length；未找到 -1）
    static Int32 headInt( string head, string name )
    {
        Int32 pos = sfFind( head, name )
        if pos < 0
        {
            ret -1
        }

        Int32 len = SystemStringLength( head )
        Int32 v = 0
        bool any = false
        for Int32 i = pos + SystemStringLength( name ), i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( head, i )
            if c < 48 || c > 57
            {
                break
            }
            v = v * 10 + ( c - 48 )
            any = true
        }

        if any == false
        {
            ret -1
        }
        ret v
    }

    # 三段式 token 手造（decode 不验签——sig 占位即可）
    # 注意：ret 后跨行 "+" 续链混方法调用会触发 Front File 层 NRE——
    # 一律先拆局部变量再拼接（mkJwt 实测复现）
    static string mkJwt( string payloadJson ) throws
    {
        string h = ServerP3Test.b64url( "{\"alg\":\"HS256\",\"typ\":\"JWT\"}" )
        string p = ServerP3Test.b64url( payloadJson )
        ret h + "." + p + ".sig"
    }

    # ── T1 openapi.json 生成 ──

    static void t1OpenApi()
    {
        Console.println( "[ServerP3Test] T1 begin (port 19431)" )
        SLang.HttpServer app = SLang.HttpServer( 19431 )
        app.reset()

        function hUser = function( SLang.Request req, SLang.Response res )
        {
            res.jsonOk( req.pathParam( "id" ) )
        }
        SLang.RouteInfo r1 = app.onGet( "/api/user/{id}", hUser )
        r1.summary = "获取用户"
        r1.tags = "用户,基础"
        r1.param( "id", "integer", "用户ID", true )
        r1.response( 200, P3User() )
        r1.security( "bearerAuth" )

        function hCreate = function( SLang.Request req, SLang.Response res )
        {
            res.jsonOk( "created" )
        }
        SLang.RouteInfo r2 = app.onPost( "/api/user", hCreate )
        r2.summary = "创建用户"
        r2.requestBody( P3User() )
        r2.response( 200, P3Order() )

        function hLogin = function( SLang.Request req, SLang.Response res )
        {
            res.jsonOk( "ok" )
        }
        SLang.RouteInfo r3 = app.onPost( "/api/login", hLogin )
        r3.summary = "登录"
        r3.formField( "username", "用户名" )
        r3.security( "apiKeyAuth" )

        app.start( 19431 )

        string doc = ServerP3Test.rawReq( 19431, "GET /openapi.json HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T1a openapi 3.0.3 骨架 + servers",
            sfFind( doc, "200" ) >= 0 && sfFind( doc, "\"openapi\":\"3.0.3\"" ) >= 0
            && sfFind( doc, "\"servers\"" ) >= 0 )
        ServerP3Test.check( "T1b paths + summary + tags",
            sfFind( doc, "\"paths\"" ) >= 0 && sfFind( doc, "/api/user/{id}" ) >= 0
            && sfFind( doc, "\"summary\":\"获取用户\"" ) >= 0
            && sfFind( doc, "\"tags\":[" ) >= 0 && sfFind( doc, "\"用户\"" ) >= 0 )
        ServerP3Test.check( "T1c path 参数（in/required/type）",
            sfFind( doc, "\"name\":\"id\"" ) >= 0 && sfFind( doc, "\"in\":\"path\"" ) >= 0
            && sfFind( doc, "\"required\":true" ) >= 0 && sfFind( doc, "\"type\":\"integer\"" ) >= 0 )
        ServerP3Test.check( "T1d requestBody + schema 复用（P3User 登记 + example）",
            sfFind( doc, "\"requestBody\"" ) >= 0
            && sfFind( doc, "#/components/schemas/P3User" ) >= 0
            && sfFind( doc, "\"example\"" ) >= 0 && sfFind( doc, "\"alice\"" ) >= 0 )
        ServerP3Test.check( "T1e 嵌套 DTO schema（P3Order.buyer → object properties）",
            sfFind( doc, "#/components/schemas/P3Order" ) >= 0
            && sfFind( doc, "\"buyer\"" ) >= 0 && sfFind( doc, "\"properties\"" ) >= 0 )
        ServerP3Test.check( "T1f securitySchemes 双定义 + operation 级 security",
            sfFind( doc, "\"securitySchemes\"" ) >= 0
            && sfFind( doc, "\"bearerAuth\":{\"type\":\"http\",\"scheme\":\"bearer\"" ) >= 0
            && sfFind( doc, "\"apiKeyAuth\":{\"type\":\"apiKey\",\"in\":\"header\",\"name\":\"X-API-Key\"" ) >= 0
            && sfFind( doc, "\"security\":[{\"bearerAuth\":[]}" ) >= 0 )
        ServerP3Test.check( "T1g form 字段（urlencoded requestBody schema）",
            sfFind( doc, "application/x-www-form-urlencoded" ) >= 0
            && sfFind( doc, "\"username\"" ) >= 0 )

        app.stop()
    }

    # ── T2 /docs 页面 + 开关 ──

    static void t2DocsPage()
    {
        Console.println( "[ServerP3Test] T2 begin (port 19432)" )
        SLang.HttpServer app = SLang.HttpServer( 19432 )
        app.reset()

        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "pong" )
        }
        app.onGet( "/ping", hPing )

        app.start( 19432 )

        # T2a 自包含 HTML（DOCTYPE + 同源 openapi.json 引用）
        string page = ServerP3Test.rawReq( 19432, "GET /docs HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T2a /docs 自包含页面",
            sfFind( page, "200" ) >= 0 && sfFind( page, "text/html" ) >= 0
            && sfFind( page, "<!DOCTYPE html>" ) >= 0 && sfFind( page, "/openapi.json" ) >= 0 )

        # T2b 用户已注册 /docs → 让位（用户优先，§6.10）
        app.stop()
        app.reset()
        function hMine = function( SLang.Request req, SLang.Response res )
        {
            res.text( "mine" )
        }
        app.onGet( "/docs", hMine )
        app.start( 19432 )
        string mine = ServerP3Test.rawReq( 19432, "GET /docs HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T2b 用户注册 /docs 让位", sfFind( mine, "mine" ) >= 0 )

        # T2c docs(false) 关闭（start 后 /docs 404；reset 恢复默认开）
        app.stop()
        app.reset()
        app.docs( false )
        app.start( 19432 )
        string off = ServerP3Test.rawReq( 19432, "GET /docs HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        string offApi = ServerP3Test.rawReq( 19432, "GET /openapi.json HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T2c docs(false) 双路由关闭",
            sfFind( off, "404" ) >= 0 && sfFind( offApi, "404" ) >= 0 )

        app.stop()
    }

    # ── T3 auth 三挂法 ──

    static void t3Auth()
    {
        Console.println( "[ServerP3Test] T3 begin (port 19431)" )
        SLang.HttpServer app = SLang.HttpServer( 19431 )
        app.reset()

        # Bearer 预设 + skip 白名单（登录接口放行）
        function hUser = function( SLang.Request req, SLang.Response res )
        {
            SLang.JwtClaims c = req.auth as SLang.JwtClaims
            string sub = ""
            string role = ""
            if c != null
            {
                sub = c.claim( "sub" )
                role = c.claim( "role" )
            }
            res.text( "sub=" + sub + ";role=" + role )
        }
        app.onGet( "/api/user", hUser )
        function hLogin = function( SLang.Request req, SLang.Response res )
        {
            res.text( "login-ok" )
        }
        app.onPost( "/api/login", hLogin )
        app.use( SLang.Plugins.authBearer().skip( "/api/login" ) )

        app.start( 19431 )

        # T3a 无 Authorization → 401 + WWW-Authenticate
        string a1 = ServerP3Test.rawReq( 19431, "GET /api/user HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3a Bearer 缺失 → 401 + WWW-Authenticate",
            sfFind( a1, "401" ) >= 0 && sfFind( a1, "WWW-Authenticate: Bearer" ) >= 0 )

        # T3b 坏 token → 401
        string a2 = ServerP3Test.rawReq( 19431, "GET /api/user HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer not.a.jwt\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3b Bearer 坏 token → 401", sfFind( a2, "401" ) >= 0 )

        # T3c 好 token → 200 + req.auth = JwtClaims（claim 读取）
        string token = ServerP3Test.mkJwt( "{\"sub\":\"1001\",\"role\":\"admin\"}" )
        string a3 = ServerP3Test.rawReq( 19431, "GET /api/user HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " + token + "\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3c Bearer 好.token → 200 + claims 透传",
            sfFind( a3, "200" ) >= 0 && sfFind( a3, "sub=1001" ) >= 0 && sfFind( a3, "role=admin" ) >= 0 )

        # T3d skip 白名单放行
        string a4 = ServerP3Test.rawReq( 19431, "POST /api/login HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\nContent-Length: 0\r\n\r\n" )
        ServerP3Test.check( "T3d skip 白名单放行", sfFind( a4, "login-ok" ) >= 0 )

        app.stop()

        # ── API Key 预设（端口 19433）──
        app = SLang.HttpServer( 19433 )
        app.reset()

        function hKey = function( SLang.Request req, SLang.Response res )
        {
            res.text( "key-user" )
        }
        app.onGet( "/data", hKey )
        function keyCheck = function( string key )
        {
            if key == "secret123"
            {
                ret "account-9"
            }
            ret null
        }
        app.use( SLang.Plugins.authApiKey( "X-API-Key", keyCheck ) )
        app.start( 19433 )

        string b1 = ServerP3Test.rawReq( 19433, "GET /data HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3e API Key 缺失 → 401（无 WWW-Authenticate）",
            sfFind( b1, "401" ) >= 0 && sfFind( b1, "WWW-Authenticate" ) < 0 )
        string b2 = ServerP3Test.rawReq( 19433, "GET /data HTTP/1.1\r\nHost: 127.0.0.1\r\nX-API-Key: secret123\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3f API Key 正确 → 200", sfFind( b2, "key-user" ) >= 0 )
        string b3 = ServerP3Test.rawReq( 19433, "GET /data HTTP/1.1\r\nHost: 127.0.0.1\r\nX-API-Key: wrong\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3g API Key 错误 → 401", sfFind( b3, "401" ) >= 0 )

        app.stop()

        # ── 通用回调（双头组合，端口 19434 之前先占 19431 复用）──
        app = SLang.HttpServer( 19431 )
        app.reset()

        function hAny = function( SLang.Request req, SLang.Response res )
        {
            res.text( "any-ok" )
        }
        app.onGet( "/any", hAny )
        function genCheck = function( SLang.Request req )
        {
            string t1 = req.header( "X-Token" )
            string t2 = req.header( "X-Sign" )
            if t1 == null
            {
                ret null
            }

            if t2 == null
            {
                ret null
            }

            if t1 == "tok" && t2 == "sig"
            {
                ret "who-1"
            }
            ret null
        }
        app.use( SLang.Plugins.auth( genCheck ) )
        app.start( 19431 )

        string c1 = ServerP3Test.rawReq( 19431, "GET /any HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3h 通用回调缺头 → 401", sfFind( c1, "401" ) >= 0 )
        string c2 = ServerP3Test.rawReq( 19431, "GET /any HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Token: tok\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3i 通用回调单头 → 401", sfFind( c2, "401" ) >= 0 )
        string c3 = ServerP3Test.rawReq( 19431, "GET /any HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Token: tok\r\nX-Sign: sig\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T3j 通用回调双头 → 200", sfFind( c3, "any-ok" ) >= 0 )

        app.stop()
    }

    # ── T4 Jwt.decode 单元 ──

    static void t4Jwt() throws
    {
        Console.println( "[ServerP3Test] T4 begin（无端口，纯单元）" )

        # T4a claims 读取（subject + 自定义 claim）
        string tok = ServerP3Test.mkJwt( "{\"sub\":\"1001\",\"role\":\"admin\",\"uid\":\"u9\"}" )
        SLang.JwtClaims c = SLang.Jwt.decode( tok )
        bool okA = c != null && c.subject == "1001" && c.claim( "role" ) == "admin" && c.claim( "uid" ) == "u9"
        ServerP3Test.check( "T4a decode + subject/claim 读取", okA )

        # T4b exp 未来 → expired=false；expiresAt 正确解析
        Int64 futureExp = OS.Timer.now() / 1000 + 3600
        SLang.JwtClaims c2 = SLang.Jwt.decode( ServerP3Test.mkJwt( "{\"sub\":\"x\",\"exp\":\"" + futureExp.toString() + "\"}" ) )
        ServerP3Test.check( "T4b 未来 exp → expired=false",
            c2 != null && c2.expired == false && c2.expiresAt == futureExp )

        # T4c exp 过去 → expired=true
        Int64 pastExp = OS.Timer.now() / 1000 - 100
        SLang.JwtClaims c3 = SLang.Jwt.decode( ServerP3Test.mkJwt( "{\"exp\":\"" + pastExp.toString() + "\"}" ) )
        ServerP3Test.check( "T4c 过去 exp → expired=true", c3 != null && c3.expired == true )

        # T4d exp 缺失 → expiresAt=0 + expired 恒 false
        SLang.JwtClaims c4 = SLang.Jwt.decode( ServerP3Test.mkJwt( "{\"sub\":\"y\"}" ) )
        ServerP3Test.check( "T4d exp 缺失 → 0/false", c4 != null && c4.expiresAt == 0 && c4.expired == false )

        # T4e 坏格式三连：单段 / base64 坏 / 非对象 payload
        SLang.JwtClaims e1 = SLang.Jwt.decode( "not-a-jwt" )
        SLang.JwtClaims e2 = SLang.Jwt.decode( "x.@@@.y" )
        SLang.JwtClaims e3 = SLang.Jwt.decode( ServerP3Test.b64url( "{\"alg\":\"HS256\"}" ) + "." + ServerP3Test.b64url( "[1,2]" ) + ".s" )
        ServerP3Test.check( "T4e 坏格式 → null（单段/坏b64/数组payload）",
            e1 == null && e2 == null && e3 == null )
    }

    # ── T5 importOpenApi ──

    static void t5Import() throws
    {
        Console.println( "[ServerP3Test] T5 begin (port 19434)" )
        SLang.HttpServer app = SLang.HttpServer( 19434 )
        app.reset()

        # spec 文件（手写 OpenAPI 子集：paths/summary/parameters/security）
        File.writeAllText( "p3_spec.json",
            "{\"paths\":{\"/api/future\":{\"get\":{\"summary\":\"未来接口\","
            + "\"parameters\":[{\"name\":\"q\",\"in\":\"query\",\"required\":false,"
            + "\"schema\":{\"type\":\"string\"}}],"
            + "\"security\":[{\"bearerAuth\":[]}]}," 
            + "\"post\":{\"summary\":\"创建未来\"}}}}" )

        # 已有真实路由（验证"仅合并元数据"分支）
        function hExist = function( SLang.Request req, SLang.Response res )
        {
            res.text( "exist" )
        }
        SLang.RouteInfo re = app.onGet( "/api/exist", hExist )
        re.summary = "已有接口"

        Int32 added = app.importOpenApi( "p3_spec.json" )
        ServerP3Test.check( "T5a 导入计数（get+post 两文档路由）", added == 2 )

        app.start( 19434 )

        # T5b 文档路由命中 501（未实现 ApiResult）
        string f1 = ServerP3Test.rawReq( 19434, "GET /api/future HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T5b 文档路由命中 → 501",
            sfFind( f1, "501" ) >= 0 && sfFind( f1, "\"code\":501" ) >= 0 )

        # T5c 已注册路由不受导入影响
        string f2 = ServerP3Test.rawReq( 19434, "GET /api/exist HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T5c 已注册路由照常 200", sfFind( f2, "exist" ) >= 0 )

        # T5d 覆盖工作流：真实路由顶替文档路由（元数据继承进 openapi.json）
        app.stop()
        function hImpl = function( SLang.Request req, SLang.Response res )
        {
            res.text( "implemented" )
        }
        app.onGet( "/api/future", hImpl )
        app.start( 19434 )
        string f3 = ServerP3Test.rawReq( 19434, "GET /api/future HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T5d 覆盖让位 → 200", sfFind( f3, "implemented" ) >= 0 )

        string doc = ServerP3Test.rawReq( 19434, "GET /openapi.json HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerP3Test.check( "T5e 覆盖后元数据继承（summary/param/security）",
            sfFind( doc, "\"summary\":\"未来接口\"" ) >= 0
            && sfFind( doc, "\"in\":\"query\"" ) >= 0
            && sfFind( doc, "\"security\":[{\"bearerAuth\":[]}" ) >= 0 )

        app.stop()
        File.delete( "p3_spec.json" )
    }

    # ── T6 maxConnections ──

    static void t6MaxConn() throws
    {
        Console.println( "[ServerP3Test] T6 begin (port 19435)" )
        SLang.HttpServer app = SLang.HttpServer( 19435 )
        SLang.ServerConfig cfg = app.config
        cfg.maxConnections = 1
        cfg.keepAliveTimeoutMs = 2000
        app.reset()

        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "pong" )
        }
        app.onGet( "/ping", hPing )
        app.start( 19435 )

        # 连接 1：占住唯一名额（keep-alive 挂住不关）
        P3RawClient c1 = P3RawClient.connect( 19435 )
        c1.send( "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n" )
        P3Resp r1 = c1.readResp()
        bool firstOk = sfFind( r1._head, "200" ) >= 0

        # 连接 2：超限 → 503（协议层应答 + 断连）
        P3RawClient c2 = P3RawClient.connect( 19435 )
        c2.send( "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        P3Resp r2 = c2.readResp()
        bool second503 = sfFind( r2._head, "503" ) >= 0 && sfFind( r2._body, "\"code\":503" ) >= 0

        ServerP3Test.check( "T6 maxConnections=1 → 首连接 200 / 次连接 503", firstOk && second503 )

        c1.close()
        c2.close()
        app.stop()
    }

    # ── T7 swaggerUI（P9 收官，§10 风险 #8）──

    static void t7Swagger() throws
    {
        Console.println( "[ServerP3Test] T7 begin (port 19436)" )
        # 测试宿主 cwd = 测试工程目录 ...\Other\ServerTest（宿主 Main 在 RunCVM
        # 前切 Environment.CurrentDirectory=projectDir；p2_hooks.txt 等相对路径
        # 产物落此为证）——fixture 与 cwd 同级，裸相对路径可达
        string dist = "swagger-ui"
        SLang.HttpServer app = SLang.HttpServer( 19436 )
        app.reset()
        app.use( SLang.Plugins.swaggerUI( dist ) )

        function hPing = function( SLang.Request req, SLang.Response res )
        {
            res.text( "pong" )
        }
        app.onGet( "/ping", hPing )
        app.start( 19436 )

        # a) GET /swagger → 200 + 自研 index（外链 bundle.js / swagger-ui.css /
        #    openapi.json 三引用齐全）
        string r1 = rawReq( 19436, "GET /swagger HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool idxOk = sfFind( r1, "200" ) >= 0 && sfFind( r1, "/swagger/swagger-ui-bundle.js" ) >= 0 && sfFind( r1, "/swagger/swagger-ui.css" ) >= 0 && sfFind( r1, "/openapi.json" ) >= 0 && sfFind( r1, "text/html" ) >= 0
        ServerP3Test.check( "T7a /swagger 自研 index（外链 dist 资产 + openapi.json）", idxOk )

        # b) GET /swagger/swagger-ui.css → 200 + text/css（dist 直出 MIME）
        string r2 = rawReq( 19436, "GET /swagger/swagger-ui.css HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool cssOk = sfFind( r2, "200" ) >= 0 && sfFind( r2, "text/css" ) >= 0
        ServerP3Test.check( "T7b /swagger/swagger-ui.css dist 直出（text/css）", cssOk )

        # c) GET /swagger/swagger-ui-bundle.js → 200 + application/javascript
        string r3 = rawReq( 19436, "GET /swagger/swagger-ui-bundle.js HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool jsOk = sfFind( r3, "200" ) >= 0 && sfFind( r3, "application/javascript" ) >= 0
        ServerP3Test.check( "T7c /swagger/swagger-ui-bundle.js dist 直出（application/javascript）", jsOk )

        # d) 穿越防护：/swagger/../secret → 403
        string r4 = rawReq( 19436, "GET /swagger/../ServerP3Test.sl HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool dotOk = sfFind( r4, "403" ) >= 0
        ServerP3Test.check( "T7d /swagger/.. 穿越段 403", dotOk )

        # e) dist 未命中 → 放行 → 尾环 404（不误吞其他路由）
        string r5 = rawReq( 19436, "GET /swagger/no-such-asset.xyz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool missOk = sfFind( r5, "404" ) >= 0
        ServerP3Test.check( "T7e dist 未命中放行（尾环 404）", missOk )

        # f) 未注册路径不受插件影响（/ping 正常 200 pong）
        string r6 = rawReq( 19436, "GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool pingOk = sfFind( r6, "200" ) >= 0 && sfFind( r6, "pong" ) >= 0
        ServerP3Test.check( "T7f 普通路由不受影响（/ping 200 pong）", pingOk )

        app.stop()

        # g) 用户优先让位：用户注册 GET /swagger → 插件让位（用户应答）
        SLang.HttpServer app2 = SLang.HttpServer( 19436 )
        app2.reset()
        app2.use( SLang.Plugins.swaggerUI( dist ) )
        function hMine = function( SLang.Request req, SLang.Response res )
        {
            res.text( "mine" )
        }
        app2.onGet( "/swagger", hMine )
        app2.start( 19436 )
        string r7 = rawReq( 19436, "GET /swagger HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        bool yieldOk = sfFind( r7, "200" ) >= 0 && sfFind( r7, "mine" ) >= 0
        ServerP3Test.check( "T7g 用户已注册 /swagger 让位（用户应答）", yieldOk )
        app2.stop()
    }

    static fun()
    {
        ServerP3Test.t1OpenApi()
        ServerP3Test.t2DocsPage()
        ServerP3Test.t3Auth()
        label t4
        {
            ServerP3Test.t4Jwt()
        }
        catch
        {
            Console.println( "[ServerP3Test] T4 Jwt 异常" )
        }
        label t5
        {
            ServerP3Test.t5Import()
        }
        catch
        {
            Console.println( "[ServerP3Test] T5 import 异常" )
        }
        label t6
        {
            ServerP3Test.t6MaxConn()
        }
        catch
        {
            Console.println( "[ServerP3Test] T6 maxConn 异常" )
        }
        label t7
        {
            ServerP3Test.t7Swagger()
        }
        catch
        {
            Console.println( "[ServerP3Test] T7 swagger 异常" )
        }
        Console.println( "[ServerP3Test] all done" )
    }
}

# ============================================================================
# P3Resp -- 响应解析结果（P2Resp 同款）
# ============================================================================
class P3Resp
{
    bool _ok = false
    bool _chunked = false
    string _head = ""
    string _body = ""

    _init_()
    {
        this._ok = false
        this._chunked = false
        this._head = ""
        this._body = ""
    }
}

# ============================================================================
# P3RawClient -- 原始 HTTP 测试客户端（P2RawClient 同款；支持 keep-alive 复用）
# ============================================================================
class P3RawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static P3RawClient connect( Int32 port ) throws
    {
        P3RawClient rc = P3RawClient()
        rc.c = Net.Tcp.connect( "127.0.0.1", port )
        rc.rtext = ""
        ret rc
    }

    void send( string text ) throws
    {
        ByteBuffer b = ByteBuffer.fromString( text )
        this.c.write( b )
        b.release()
    }

    # 读一行（不含行尾；EOF 无行返回 null）
    string readLine() throws
    {
        Int32 pos = ServerP3Test.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerP3Test.sfFind( this.rtext, "\n" )
        }
        Int32 cut = pos
        if cut > 0 && SystemStringCharCodeAt( this.rtext, cut - 1 ) == 13
        {
            cut = cut - 1
        }
        string line = SystemStringRange( this.rtext, 0, cut )
        this.rtext = SystemStringRange( this.rtext, pos + 1, SystemStringLength( this.rtext ) )
        ret line
    }

    # 读 n 字节（文本安全：测试数据无内嵌 NUL）
    string readN( Int32 n ) throws
    {
        while SystemStringLength( this.rtext ) < n
        {
            ByteBuffer b = ByteBuffer( 8192 )
            Int32 got = this.c.read( b )
            if got == 0
            {
                break
            }
            this.rtext = this.rtext + b.readString( got )
        }
        Int32 have = SystemStringLength( this.rtext )
        Int32 take = n
        if have < take
        {
            take = have
        }
        string part = SystemStringRange( this.rtext, 0, take )
        this.rtext = SystemStringRange( this.rtext, take, have )
        ret part
    }

    # 读完整响应（Content-Length 定长 / EOF 截止；chunked 解码同 P2）
    P3Resp readResp() throws
    {
        P3Resp r = P3Resp()
        string head = ""
        bool headDone = false
        while headDone == false
        {
            string line = this.readLine()
            if line == null
            {
                ret r
            }

            if SystemStringLength( line ) == 0
            {
                headDone = true
            }
            else
            {
                head = head + line + "\n"
            }
        }
        r._head = head
        r._ok = true
        if ServerP3Test.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
        {
            r._chunked = true
            string body = ""
            bool bodyDone = false
            while bodyDone == false
            {
                string sizeLine = this.readLine()
                if sizeLine == null
                {
                    bodyDone = true
                }
                else
                {
                    Int32 sz = ServerP3Test.hexVal( sizeLine )
                    if sz == 0
                    {
                        this.readLine()
                        bodyDone = true
                    }
                    else
                    {
                        body = body + this.readN( sz )
                        this.readLine()
                    }
                }
            }
            r._body = body
            ret r
        }
        Int32 cl = ServerP3Test.headInt( head, "Content-Length: " )
        if cl >= 0
        {
            r._body = this.readN( cl )
            ret r
        }
        # 无长度 → EOF 截止
        string all = ""
        while true
        {
            string part = this.readN( 8192 )
            if SystemStringLength( part ) == 0
            {
                break
            }
            all = all + part
        }
        r._body = all
        ret r
    }

    void close()
    {
        if this.c != null
        {
            label cl
            {
                this.c.close()
            }
            catch { }
            this.c = null
        }
    }
}
