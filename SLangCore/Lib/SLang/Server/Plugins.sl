import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Plugins.sl — 内置插件门面（P2）
    # 设计契约：SERVER_DESIGN.md §4.7（内置插件路线：logger / cors /
    #   staticFiles；P3 增 bodyLimit/requestId/auth，P5 增 rateLimit）
    #
    # 用法（一行装一个插件，产物为普通 ServerPlugin 子类，经 app.use 注册）：
    #   var app = SLang.HttpServer( 8080 );
    #   app.use( SLang.Plugins.logger() );
    #   app.use( SLang.Plugins.cors() );
    #   app.use( SLang.Plugins.staticFiles( "./www" ) );
    #
    # 实现约束：中间件闭包零捕获（P0 复盘纪律）——staticFiles 的 root 经
    #   静态字段传递（v1 单实例：重复注册后者覆盖前者，P2 实录记录）；
    #   中间件逻辑收进静态方法、闭包只做转发；onInstall 内注册走引擎级
    #   静态通道 HttpServerCore.use（插件无门面实例引用——闭包/插件
    #   零捕获纪律，Server.sl 门面注记同源）。
    # ============================================================================

    # ── logger：请求日志（方法/路径/状态/耗时）──
    class _LoggerPlugin extends ServerPlugin
    {
        override public void onInstall()
        {
            # 闭包字面量先赋局部变量再传参（内联实参形态语言不支持）
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _LoggerPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            Int64 t0 = OS.Timer.now()
            nx.go()
            Int64 cost = OS.Timer.now() - t0
            Int32 st = res._status
            Console.println( "[server] " + req.method + " " + req.path + " " + st.toString() + " " + cost.toString() + "ms" )
        }
    }

    # ── cors：跨域（自动应答 OPTIONS 预检 + 放行头）──
    class _CorsPlugin extends ServerPlugin
    {
        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _CorsPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            res.header( "Access-Control-Allow-Origin", "*" )
            string m = req.method
            if m == "OPTIONS"
            {
                # 预检直接应答短路（不进 handler；含未注册路径——预检请求
                # 通常无对应路由）
                res.header( "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS" )
                res.header( "Access-Control-Allow-Headers", "Content-Type, Authorization" )
                res.header( "Access-Control-Max-Age", "86400" )
                res.status( 204 ).text( "" )
                ret
            }
            nx.go()
        }
    }

    # ── staticFiles：静态目录服务（root 下文件直出；仅 GET）──
    class _StaticFilesPlugin extends ServerPlugin
    {
        # 静态根目录（闭包零捕获纪律：root 经静态字段传递；v1 单实例，
        # 重复注册后者覆盖前者）
        static string _root = ""

        _init_( string root )
        {
            _StaticFilesPlugin._root = root
        }

        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _StaticFilesPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            # 仅 GET 直出（HEAD 放行——sendFile 直写路径未做 HEAD 摘除）
            string m = req.method
            if m != "GET"
            {
                nx.go()
                ret
            }
            string rel = req.path
            if rel == null || SystemStringLength( rel ) == 0
            {
                nx.go()
                ret
            }

            # 路径穿越防护：'..' 独立段拒绝（403）
            if _StaticFilesPlugin._hasDotDot( rel )
            {
                res.status( 403 ).rawJson( "{\"code\":403,\"message\":\"forbidden\",\"data\":null}" )
                ret
            }
            string root = _StaticFilesPlugin._root
            string dirBase = root
            Int32 bl = SystemStringLength( dirBase )
            if bl > 0 && SystemStringCharCodeAt( dirBase, bl - 1 ) == 47
            {
                dirBase = SystemStringRange( dirBase, 0, bl - 1 )
            }
            string full = dirBase + rel
            if File.exists( full ) == false
            {
                # 未命中：放行（后续路由 / 404 尾环）
                nx.go()
                ret
            }
            # 命中：流式直出（MIME 按扩展名）+ Range 断点续传（P5：
            # req 的 Range 头透传 sendFileRange，206/416 语义见 Response）+ 短路
            res.sendFileRange( full, req.header( "Range" ) )
        }

        # '..' 独立路径段检测（前后为 '/' 或串首尾；"file..txt" 不误杀）
        static bool _hasDotDot( string path )
        {
            Int32 len = SystemStringLength( path )
            for Int32 i = 0, i < len, i = i + 1
            {
                if SystemStringCharCodeAt( path, i ) == 46 && i + 1 < len && SystemStringCharCodeAt( path, i + 1 ) == 46
                {
                    bool leftOk = i == 0 || SystemStringCharCodeAt( path, i - 1 ) == 47
                    Int32 end = i + 2
                    bool rightOk = end >= len || SystemStringCharCodeAt( path, end ) == 47
                    if leftOk && rightOk
                    {
                        ret true
                    }
                }
            }
            ret false
        }
    }

    # ── swaggerUI（P9 收官，§10 风险 #8）：Swagger UI 静态包托管 ──
    #    路由：GET /swagger → 自研 index（外链 dist 资产 + /openapi.json）；
    #          GET /swagger/<file> → dist 目录文件直出。
    #    让位约定（/docs 同款）：用户已注册 GET /swagger 则本插件不接管，
    #    由用户路由应答（findExact 先查 + ret 让位）。
    class _SwaggerUIPlugin extends ServerPlugin
    {
        # 闭包零捕获纪律：dist 目录经静态字段传递（v1 单实例，后者覆盖）
        static string _dist = ""

        _init_( string distDir )
        {
            _SwaggerUIPlugin._dist = distDir
        }

        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _SwaggerUIPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            string m = req.method
            if m != "GET"
            {
                nx.go()
                ret
            }
            string p = req.path
            if p == "/swagger"
            {
                # 用户优先让位（/docs 同款约定）：用户已注册 GET /swagger
                # 则放行给路由层（中间件在路由前执行，运行期 findExact 先查）
                if Router.findExact( "GET", "/swagger" ) != null
                {
                    nx.go()
                    ret
                }
                _SwaggerUIPlugin._serveIndex( res )
                ret
            }

            if SystemStringLength( p ) < 10 || SystemStringRange( p, 0, 9 ) != "/swagger/"
            {
                # 非 /swagger/ 前缀：放行（不归本插件管）
                nx.go()
                ret
            }

            # /swagger/<file> → dist 目录直出（staticFiles 同款纪律：
            # '..' 段 403 / 未命中放行 / sendFileRange 流式直出 + MIME + Range）
            if _StaticFilesPlugin._hasDotDot( p )
            {
                res.status( 403 ).rawJson( "{\"code\":403,\"message\":\"forbidden\",\"data\":null}" )
                ret
            }
            string rel = SystemStringRange( p, 9, SystemStringLength( p ) )
            string dirBase = _SwaggerUIPlugin._dist
            Int32 bl = SystemStringLength( dirBase )
            if bl > 0 && SystemStringCharCodeAt( dirBase, bl - 1 ) == 47
            {
                dirBase = SystemStringRange( dirBase, 0, bl - 1 )
            }
            # rel 无前导斜杠（staticFiles 的 rel=req.path 自带 /，此处剥了
            # "/swagger/" 前缀），拼接须显式补 "/"
            string full = dirBase + "/" + rel
            if File.exists( full ) == false
            {
                nx.go()
                ret
            }
            res.sendFileRange( full, req.header( "Range" ) )
        }

        # GET /swagger：自研 index 直出（让位检查在 _serve 运行期做：
        # 中间件先于路由执行，findExact 命中用户路由则已放行至此）
        static void _serveIndex( SLang.Response res )
        {
            res.html( _SwaggerUIPlugin._indexPage() )
        }

        # index.html（外链 dist 资产 + /openapi.json；零自包含）
        # 约束：长字符串一律 StringBuilder 逐段追加（"+" 链截断）；若 JS 需要
        # "$" 须经 String.fromCharCode(36) 运行期生成（"$" 是 SL 插值前缀，
        # 本页恰好不含）
        static string _indexPage()
        {
            string nl = "\n"
            StringBuilder sb = StringBuilder()
            sb.append( "<!DOCTYPE html>" )
            sb.append( nl )
            sb.append( "<html lang=\"zh\">" )
            sb.append( nl )
            sb.append( "<head>" )
            sb.append( nl )
            sb.append( "<meta charset=\"utf-8\">" )
            sb.append( nl )
            sb.append( "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" )
            sb.append( nl )
            sb.append( "<title>SLang Server API - Swagger UI</title>" )
            sb.append( nl )
            sb.append( "<link rel=\"stylesheet\" href=\"/swagger/swagger-ui.css\">" )
            sb.append( nl )
            sb.append( "</head>" )
            sb.append( nl )
            sb.append( "<body>" )
            sb.append( nl )
            sb.append( "<div id=\"swagger-ui\"></div>" )
            sb.append( nl )
            sb.append( "<script src=\"/swagger/swagger-ui-bundle.js\"></script>" )
            sb.append( nl )
            sb.append( "<script>" )
            sb.append( nl )
            sb.append( "window.onload=function(){" )
            sb.append( nl )
            # const ui = SwaggerUIBundle({ url:"/openapi.json", dom_id:"#swagger-ui" })
            sb.append( "var ui=window.SwaggerUIBundle({" )
            sb.append( nl )
            sb.append( "url:\"/openapi.json\"," )
            sb.append( nl )
            sb.append( "dom_id:\"#swagger-ui\"," )
            sb.append( nl )
            sb.append( "deepLinking:true," )
            sb.append( nl )
            sb.append( "docExpansion:\"none\"," )
            sb.append( nl )
            sb.append( "presets:[window.SwaggerUIBundle.presets.apis]," )
            sb.append( nl )
            sb.append( "layout:\"BaseLayout\"" )
            sb.append( nl )
            sb.append( "})" )
            sb.append( nl )
            sb.append( "}" )
            sb.append( nl )
            sb.append( "</script>" )
            sb.append( nl )
            sb.append( "</body>" )
            sb.append( nl )
            sb.append( "</html>" )
            string res = sb.toString()
            sb.release()
            ret res
        }
    }

    # ── bodyLimit（P3，§4.7）：场景化 body 上限收紧（低于全局
    #    maxBodyBytes 的应用级限制；超限 413 ApiResult 短路）──
    class _BodyLimitPlugin extends ServerPlugin
    {
        # 闭包零捕获纪律：限额经静态字段传递（v1 单实例，后者覆盖前者）
        static Int64 _limit = 0

        _init_( Int64 limitBytes )
        {
            _BodyLimitPlugin._limit = limitBytes
        }

        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _BodyLimitPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            if _BodyLimitPlugin._limit > 0 && req.contentLength > _BodyLimitPlugin._limit
            {
                res.jsonFail( 413, "payload too large", 413 )
                ret
            }
            nx.go()
        }
    }

    # ── requestId（P3，§4.7）：X-Request-Id 响应头（Guid；请求追踪）──
    class _RequestIdPlugin extends ServerPlugin
    {
        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _RequestIdPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            res.header( "X-Request-Id", Guid.newGuid() )
            nx.go()
        }
    }

    # ── rateLimit（P5，§4.7）：按客户端 IP 固定窗口限流 ──
    #    窗口内请求数超 max → 429 + Retry-After（剩余秒）短路；
    #    桶表懒清理（每 256 次判定顺带清一遍过期桶，防内存增长）。
    #    v1 单实例（静态字段态，多 rateLimit 插件后者覆盖——staticFiles 同款纪律）。
    class _RateBucket
    {
        Int64 _start = 0
        Int32 _count = 0

        _init_()
        {
            this._start = 0
            this._count = 0
        }
    }

    class _RateLimitPlugin extends ServerPlugin
    {
        static Int32 _max = 0
        static Int32 _windowMs = 60000
        # 桶表（值 object 持有 + as 转型——Map<string,_RateBucket> 值为
        # 模块内部类时 Front 泛型解析失败，_WsSessions 同款规避）
        static Map<string, object> _buckets = null
        static Int32 _sweepCounter = 0

        _init_( Int32 maxRequests, Int32 windowMs )
        {
            _RateLimitPlugin._max = maxRequests
            _RateLimitPlugin._windowMs = windowMs
            _RateLimitPlugin._buckets = new()
            _RateLimitPlugin._sweepCounter = 0
        }

        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _RateLimitPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            if _RateLimitPlugin._max <= 0
            {
                nx.go()
                ret
            }
            Int64 now = OS.Timer.now()
            string ip = req.ip
            if _RateLimitPlugin._buckets.containsKey( ip ) == false
            {
                _RateBucket nb = _RateBucket()
                nb._start = now
                _RateLimitPlugin._buckets.add( ip, nb )
            }
            object cur = _RateLimitPlugin._buckets[ip]
            _RateBucket b = cur as _RateBucket
            if b == null
            {
                # 防御（理论不可达）：无桶直接放行
                nx.go()
                ret
            }
            Int32 window = _RateLimitPlugin._windowMs
            if now - b._start >= window
            {
                # 窗口翻转：重置计数
                b._start = now
                b._count = 0
            }
            b._count = b._count + 1
            if b._count > _RateLimitPlugin._max
            {
                # 剩余秒（向上取整）
                Int64 elapsed = now - b._start
                Int32 remainSec = 1
                if window > 0
                {
                    remainSec = ( ( window - elapsed ) / 1000 ).toInt32() + 1
                }
                res.header( "Retry-After", remainSec.toString() )
                res.jsonFail( 429, "rate limit exceeded", 429 )
                ret
            }
            nx.go()
            # 周期性过期桶清理（每 256 次放行判定顺带一遍）
            _RateLimitPlugin._sweepCounter = _RateLimitPlugin._sweepCounter + 1
            if _RateLimitPlugin._sweepCounter >= 256
            {
                _RateLimitPlugin._sweepCounter = 0
                _RateLimitPlugin._sweepExpired( now )
            }
        }

        # 过期桶清理（窗口已翻转的桶整表移除；Map 无遍历删除——键快照后逐删）
        static void _sweepExpired( Int64 now )
        {
            List<string> keys = _RateLimitPlugin._buckets.keys
            Int32 window = _RateLimitPlugin._windowMs
            Int32 n = keys.length
            for Int32 i = 0, i < n, i = i + 1
            {
                string k = keys[i]
                object cur = _RateLimitPlugin._buckets[k]
                _RateBucket b = cur as _RateBucket
                if b == null || now - b._start >= window
                {
                    _RateLimitPlugin._buckets.remove( k )
                }
            }
        }
    }

    # ── auth（P3，§4.11）：认证插件——三挂法共用一类 ──
    #    mode 0 = 通用回调（收整个 req）；1 = Bearer 预设（Jwt.decode）；
    #    2 = API Key 预设（自定义 header 名 + key 校验回调）。
    #    通过 → 身份写 req.auth + 放行；未通过 → 401 ApiResult 短路
    #    （Bearer 模式附 WWW-Authenticate: Bearer，RFC 6750）。
    #    .skip(path) = 公开路径白名单（精确匹配，可链式；未声明 = 全站锁死）；
    #    .ws(true) = WS 升级 token 查询参数接管（onWsOpen 钩子校验，
    #    失败即关会话；仅 bearer/apiKey 两模式，通用回调无 req 可用）。
    #    v1 单实例（静态字段态，多 auth 插件后者覆盖——staticFiles 同款纪律）。
    class _AuthPlugin extends ServerPlugin
    {
        static Int32 _mode = 0
        # 通用回调 Function(Request)->object / API Key 回调 Function(string)->object
        static Function _validator = null
        static string _apiKeyHeader = ""
        static List<string> _skips = null
        static bool _ws = false

        _init_( Int32 mode, Function validator, string apiKeyHeader )
        {
            _AuthPlugin._mode = mode
            _AuthPlugin._validator = validator
            _AuthPlugin._apiKeyHeader = apiKeyHeader
            _AuthPlugin._skips = new()
            _AuthPlugin._ws = false
        }

        # 公开路径白名单（链式；override 基类占位——返回类型须一致为
        # ServerPlugin，跨模块链式调用按基类签名决议）
        override public ServerPlugin skip( string path )
        {
            if _AuthPlugin._skips == null
            {
                _AuthPlugin._skips = new()
            }
            _AuthPlugin._skips.add( path )
            ret this
        }

        # WS 升级 token 接管开关（链式；同上 override 基类签名）
        override public ServerPlugin ws( bool on )
        {
            _AuthPlugin._ws = on
            ret this
        }

        override public void onInstall()
        {
            function mw = function( SLang.Request req, SLang.Response res, SLang.Next nx )
            {
                _AuthPlugin._serve( req, res, nx )
            }
            HttpServerCore.use( mw )
        }

        # WS 升级校验（§4.11 落点 B：浏览器 WS 无法自定义头 → token 走
        # 查询参数；onWsOpen 引擎广播触发，失败即关会话）
        override public void onWsOpen( WsSession s )
        {
            if _AuthPlugin._ws == false
            {
                ret
            }
            string token = s.query( "token" )
            object who = _AuthPlugin._wsIdent( token )
            if who == null
            {
                s.close()
            }
        }

        # token → 身份（bearer 解 JWT / apiKey 走校验回调；通用模式不适用）
        static object _wsIdent( string token )
        {
            if token == null
            {
                ret null
            }

            if _AuthPlugin._mode == 1
            {
                ret Jwt.decode( token )
            }

            if _AuthPlugin._mode == 2 && _AuthPlugin._validator != null
            {
                function vf = _AuthPlugin._validator
                ret vf( token )
            }
            ret null
        }

        static void _serve( SLang.Request req, SLang.Response res, SLang.Next nx ) throws
        {
            # skip 白名单（精确匹配；放行优先于认证）
            List<string> sk = _AuthPlugin._skips
            if sk != null
            {
                Int32 n = sk.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    if req.path == sk[i]
                    {
                        nx.go()
                        ret
                    }
                }
            }

            if _AuthPlugin._mode == 1
            {
                # Bearer：Authorization: Bearer <token> → Jwt.decode → req.auth
                string ah = req.header( "Authorization" )
                if ah == null || SystemStringLength( ah ) < 8
                {
                    _AuthPlugin._deny( res, true )
                    ret
                }

                if SystemStringRange( ah, 0, 7 ) != "Bearer "
                {
                    _AuthPlugin._deny( res, true )
                    ret
                }
                string token = SystemStringRange( ah, 7, SystemStringLength( ah ) )
                JwtClaims c = Jwt.decode( token )
                if c == null
                {
                    _AuthPlugin._deny( res, true )
                    ret
                }
                req.auth = c
                nx.go()
                ret
            }

            if _AuthPlugin._mode == 2
            {
                # API Key：自定义 header 名 + key 校验回调
                string key = req.header( _AuthPlugin._apiKeyHeader )
                if key == null
                {
                    _AuthPlugin._deny( res, false )
                    ret
                }
                function vf = _AuthPlugin._validator
                object who = vf( key )
                if who == null
                {
                    _AuthPlugin._deny( res, false )
                    ret
                }
                req.auth = who
                nx.go()
                ret
            }
            # 通用：回调收整个 req，任意 header 组合都能验
            function vf = _AuthPlugin._validator
            object who = vf( req )
            if who == null
            {
                _AuthPlugin._deny( res, false )
                ret
            }
            req.auth = who
            nx.go()
        }

        # 401 应答（Bearer 模式附 WWW-Authenticate 头；RFC 6750）
        static void _deny( SLang.Response res, bool bearer )
        {
            if bearer
            {
                res.header( "WWW-Authenticate", "Bearer" )
            }
            res.jsonFail( 401, "unauthorized", 401 )
        }
    }

    # ============================================================================
    # Plugins — 内置插件工厂门面（静态；产物为普通 ServerPlugin 子类）
    # ============================================================================
    public class Plugins
    {
        # 请求日志（方法/路径/状态/耗时，[server] 前缀）
        public static ServerPlugin logger()
        {
            # 子类实例经局部赋型上行（HttpTest 头注记先例）
            ServerPlugin p = _LoggerPlugin()
            ret p
        }

        # CORS（OPTIONS 预检 204 短路 + Access-Control-Allow-Origin: *）
        public static ServerPlugin cors()
        {
            ServerPlugin p = _CorsPlugin()
            ret p
        }

        # 静态目录服务（root 下文件按扩展名 MIME 直出；仅 GET；'..' 段 403）
        public static ServerPlugin staticFiles( string root )
        {
            ServerPlugin p = _StaticFilesPlugin( root )
            ret p
        }

        # Swagger UI 静态包托管（P9 收官）：GET /swagger 自研 index（外链
        # dist 资产 + /openapi.json）；GET /swagger/<file> 直出 dist 目录；
        # 用户已注册 GET /swagger 让位（/docs 同款约定）；v1 单实例后者覆盖
        public static ServerPlugin swaggerUI( string distDir )
        {
            ServerPlugin p = _SwaggerUIPlugin( distDir )
            ret p
        }

        # body 上限收紧（P3；超限 413；v1 单实例后者覆盖）
        public static ServerPlugin bodyLimit( Int64 limitBytes )
        {
            ServerPlugin p = _BodyLimitPlugin( limitBytes )
            ret p
        }

        # X-Request-Id 响应头（P3；Guid 生成，请求追踪）
        public static ServerPlugin requestId()
        {
            ServerPlugin p = _RequestIdPlugin()
            ret p
        }

        # 按客户端 IP 固定窗口限流（P5；窗口内超 max → 429 + Retry-After；
        # windowMs 缺省 60000；v1 单实例后者覆盖）
        public static ServerPlugin rateLimit( Int32 maxRequests, Int32 windowMs )
        {
            ServerPlugin p = _RateLimitPlugin( maxRequests, windowMs )
            ret p
        }

        # 按客户端 IP 固定窗口限流（60 秒窗口便捷形态）
        public static ServerPlugin rateLimit( Int32 maxRequests )
        {
            ServerPlugin p = _RateLimitPlugin( maxRequests, 60000 )
            ret p
        }

        # 通用认证（P3，§4.11 ①）：回调收整个 req，ret 身份对象 / ret null
        public static ServerPlugin auth( Function validator )
        {
            ServerPlugin p = _AuthPlugin( 0, validator, "" )
            ret p
        }

        # Bearer 预设（§4.11 ②）：Authorization: Bearer <token> →
        # Jwt.decode → req.auth = JwtClaims；.skip/.ws 链式
        public static ServerPlugin authBearer()
        {
            ServerPlugin p = _AuthPlugin( 1, null, "" )
            ret p
        }

        # API Key 预设（§4.11 ③）：自定义 header 名 + key 校验回调
        public static ServerPlugin authApiKey( string headerName, Function validator )
        {
            ServerPlugin p = _AuthPlugin( 2, validator, headerName )
            ret p
        }
    }
}


