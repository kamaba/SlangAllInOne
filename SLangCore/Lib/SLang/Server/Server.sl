import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Server.sl — 配置与错误码 + HTTP 应用门面（实例形态）
    # 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 / §4.9（生命周期与配置）
    #           / 附录 D（错误码表）
    #
    # 门面类 SLang.HttpServer（2026-10-26 自 SLang.Server 改名——服务器类
    # 按协议分工：HttpServer 承载 HTTP + WebSocket 同端口升级两协议；
    # WebSocket 侧 API（升级路由注册 / wsEvents / 会话查询 / 组播）整体
    # 收口到 SLang.WebSocketServer 实例类）：
    #   var app = SLang.HttpServer();        # 缺省端口 80
    #   var app = SLang.HttpServer( 8080 );  # 构造带端口
    #   app.onGet( "/hello", function( SLang.Request req, SLang.Response res )
    #   {
    #       res.text( "hello world" );
    #   } );
    #   app.run();                           # = start + awaitStop（阻塞直至 stop）
    #   app.run( 8080 );                     # run(port)/start(port) 便捷覆盖
    #
    # WS 升级路由（同端口）：SLang.WebSocketServer ws = SLang.WebSocketServer()
    # → ws.websocket( path, fn ) / ws.wsEvents( path )——详见 WebSocketServer.sl。
    #
    # 构造期落位默认 ServerConfig（cfg.port = 构造端口），start 前可经
    # app.config 直改字段；app.configure( cfg ) 为全量覆盖。
    #
    # v1 语义说明：引擎（HttpServerCore / Router / 会话表）仍为模块级单例
    # （SERVER_DESIGN.md §12 复盘 ①——C VM 跨模块类多实例化的实例态隔离
    # 不可靠），路由 / 中间件 / 插件 / WS 会话跨实例共享，单 VM 单服务器；
    # 多实例需求待 C VM 实例隔离修复。插件 onInstall / 闭包等无实例引用
    # 场景经引擎级静态通道（HttpServerCore.use / .onGet / .sessions /
    # .broadcast）注册与查询，语义与实例形态完全一致。
    # 配置字段直改（无 builder 链）；后续阶段字段随能力增补：
    #   P1.5：maxUploadBytes / maxFileBytes（multipart，已落地）
    #   P2：writeTimeoutMs（流式写挂起超时）
    #   P3：maxConnections / showBanner
    #   P5：wsIdleTimeoutMs / jwtSecret
    # ============================================================================

    # 服务器配置
    public class ServerConfig
    {
        # 监听地址
        public string host = "0.0.0.0"
        # 监听端口（门面构造 seed / start(port) 为便捷覆盖）
        public Int32 port = 8080
        # 空闲连接超时毫秒（超时静默断开）
        public Int32 keepAliveTimeoutMs = 15000
        # handler 协程执行超时毫秒（防 await 死等；<= 0 无限等待；
        # 超时 cancel + 504 + 断连，SERVER_DESIGN.md §6.1）
        public Int32 handlerTimeoutMs = 30000
        # 请求头上限字节，超出 431
        public Int32 maxHeaderBytes = 16384
        # 普通请求 body 上限字节，超出 413
        public Int32 maxBodyBytes = 10485760
        # multipart 请求总量上限字节，超出 413（P1.5，§4.9）
        public Int32 maxUploadBytes = 104857600
        # 单文件上限字节，超出 413（P1.5，§4.9）
        public Int32 maxFileBytes = 52428800
        # 流式写挂起超时毫秒（防慢客户端拖死；<= 0 无限等待；P2，§4.9）
        public Int32 writeTimeoutMs = 30000
        # 并发连接上限（超出 503 + 断连；<= 0 不限；P3，§4.9）
        public Int32 maxConnections = 1024
        # WS 会话空闲超时毫秒（无入站消息即断开；<= 0 不启用；P5，§6.8）。
        # 引擎在 WS 会话注册后启动看门狗协程：空闲超时 close 会话，
        # handler 的 receive() 随之返回 null 自然收尾
        public Int32 wsIdleTimeoutMs = 0
        # JWT HS256 密钥（P5，§4.11；Jwt.sign 缺省密钥——sign/verify 显式
        # 传 secret 优先；空串 = 未配置，sign 抛 MissingJwtSecret）
        public string jwtSecret = ""

        # 字段默认值经无参构造显式落位（HttpClient._init_ 先例：跨模块消费侧
        # 类字段默认值初始化不可靠，实测 host 读出空串致 listen 绑错地址）
        _init_()
        {
            this.host = "0.0.0.0"
            this.port = 8080
            this.keepAliveTimeoutMs = 15000
            this.handlerTimeoutMs = 30000
            this.maxHeaderBytes = 16384
            this.maxBodyBytes = 10485760
            this.maxUploadBytes = 104857600
            this.maxFileBytes = 52428800
            this.writeTimeoutMs = 30000
            this.maxConnections = 1024
            this.wsIdleTimeoutMs = 0
            this.jwtSecret = ""
        }
    }

    # ============================================================================
    # _SrvUtil — 模块内部工具（不入 jsonc struct）。
    # 注：struct 登记类方法体内局部/形参位泛型容器 .add 曾解析失败，根因为
    # Front gen 实例成员一次性快照时序缺陷——已在 MetaCallNode.GetFunction-
    # OrVariableByOwnerClass 加 gen→原始模板类回退修复（2026-10-17），本类
    # 保留作模块内部工具收口。
    # ============================================================================
    class _SrvUtil
    {
        # Map 键拷贝进 List（queryKeys/formKeys 底座）
        static void copyKeys( Map<string,string> src, List<string> dst )
        {
            List<string> ks = src.keys
            Int32 n = ks.length
            for Int32 i = 0, i < n, i = i + 1
            {
                dst.add( ks[i] )
            }
        }
    }

    # 框架错误码（SERVER_DESIGN.md 附录 D；P0/P1 已启用条目，
    # 其余随各阶段接线：BadUpgrade=6 P1 接入 / DocConflict=7·BadSkipPath=8·
    # UnknownSecurity=9 P3 / MissingJwtSecret=10 P5 接入）
    public enum ServerError extends Error
    {
        # 1 同 method+pattern 重复注册（start() 时 fail-fast）
        DuplicateRoute = { code = 1 }
        # 2 终端响应方法二次调用
        AlreadyResponded = { code = 2 }
        # 3 stop / awaitStop 于未启动时调用
        NotRunning = { code = 3 }
        # 4 重复 start
        AlreadyRunning = { code = 4 }
        # 5 配置非法（端口越界等）
        InvalidConfig = { code = 5 }
        # 10 Jwt.sign 于 secret 空/未配置时调用（P5）
        MissingJwtSecret = { code = 10 }
    }

    # ============================================================================
    # SLang.HttpServer — HTTP 应用门面（App 本体，实例形态）
    # 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 / §4.6 / §4.9
    #
    # 用法：
    #   import SLangServer;
    #   var app = SLang.HttpServer( 8080 );  # 缺省端口 80
    #   var cfg = app.config;                 # 直改字段（start 前生效）
    #   cfg.keepAliveTimeoutMs = 20000;
    #   app.onGet( "/hello", function( SLang.Request req, SLang.Response res )
    #   {
    #       res.text( "hello world" );
    #   } );
    #   app.run();                           # = start + awaitStop（阻塞直至 stop）
    #
    # 形态说明（SERVER_DESIGN.md §12 复盘 ①）：P0-P4 曾以静态形态落地
    # （SLang.Server.configure( cfg ) / .onGet( path, fn ) / .run( port )），
    # 现按设计目标形态转实例（§19 实录）；引擎层维持模块级单例（C VM 多实例
    # 实例态隔离不可靠），跨实例共享路由/中间件/会话——v1 单 VM 单服务器语义。
    # ============================================================================

    public class HttpServer
    {
        # 监听端口（构造入参；SLang.HttpServer() = 80；start(port)/run(port)
        # 便捷覆盖后同步本字段）
        public Int32 port = 80

        # ── 构造 ──

        # 缺省构造：端口 80（构造期落位默认配置，start 前可 app.config 直改）
        public void _init_()
        {
            this.port = 80
            ServerConfig cfg = ServerConfig()
            cfg.port = 80
            HttpServerCore.configure( cfg )
        }

        # 带端口构造：SLang.HttpServer( 8080 )（构造期落位默认配置）
        public void _init_( Int32 port )
        {
            this.port = port
            ServerConfig cfg = ServerConfig()
            cfg.port = port
            HttpServerCore.configure( cfg )
        }

        # ── 配置 / 生命周期 ──

        # 运行配置（构造期已 seed 默认值；start 前直改字段生效——
        # SERVER_DESIGN.md §4.9「var cfg = app.config; cfg.port = 8080」形态）
        public get ServerConfig config()
        {
            ServerConfig cfg = HttpServerCore._cfg
            if cfg == null
            {
                # 兜底：绕过门面直连 HttpServerCore.configure 的极端路径
                cfg = ServerConfig()
                cfg.port = this.port
                HttpServerCore.configure( cfg )
            }
            ret cfg
        }

        # 全量配置覆盖（构造期 seed 之外的显式配置；start 前生效；
        # 重复调用覆盖；this.port 随 cfg.port 同步）
        public void configure( ServerConfig cfg )
        {
            HttpServerCore.configure( cfg )
            this.port = cfg.port
        }

        # 启动（立即返回，accept 循环独立协程；端口 = 配置端口——
        # 构造期 seed 自构造入参，app.config 直改后以直改值为准）
        public void start() throws
        {
            ServerConfig cfg = this.config()
            HttpServerCore.setListenPort( cfg.port )
            HttpServerCore.start()
        }

        # 启动（便捷覆盖端口；立即返回）
        public void start( Int32 port ) throws
        {
            this.port = port
            HttpServerCore.setListenPort( port )
            HttpServerCore.start()
        }

        # 阻塞当前协程直至 stop（run = start + awaitStop）
        public void run() throws
        {
            this.start()
            HttpServerCore.awaitStop()
        }

        # 阻塞当前协程直至 stop（便捷覆盖端口）
        public void run( Int32 port ) throws
        {
            this.start( port )
            HttpServerCore.awaitStop()
        }

        # 停止（关监听 + 关全部在途连接；路由表保留，可重新 start 复用；
        # 需要清空路由用 reset()）
        public void stop() throws
        {
            HttpServerCore.stop()
        }

        # 挂起直至停止（不经 run 形态时用）
        public void awaitStop() throws
        {
            HttpServerCore.awaitStop()
        }

        # 清空路由表（HTTP + WS；stop 后重新配置用）
        public void reset()
        {
            HttpServerCore.reset()
        }

        public get bool isRunning()
        {
            ret HttpServerCore.isRunning
        }

        # ── app 级事件钩子（P6，§4.9；字段赋值形态——set/get 访问器）──
        # onStart/onStop：function()；onError：function( SLang.Request req,
        # SLang.Response res, Error e )。钩子零捕获（体内只能引用全局静态）；
        # onError 内可写响应自救（未写则 500 兜底）；触发时序：onStart 在
        # start 末尾（插件 onStart 之后）、onStop 在 stop 收尾（插件 onStop
        # 之后）；reset() 清空全部钩子

        public void set onStart( Function fn )
        {
            HttpServerCore._hookOnStart = fn
        }

        public get Function onStart()
        {
            ret HttpServerCore._hookOnStart
        }

        public void set onStop( Function fn )
        {
            HttpServerCore._hookOnStop = fn
        }

        public get Function onStop()
        {
            ret HttpServerCore._hookOnStop
        }

        public void set onError( Function fn )
        {
            HttpServerCore._hookOnError = fn
        }

        public get Function onError()
        {
            ret HttpServerCore._hookOnError
        }

        # ── 路由注册（动词家族；get/set 是关键字 → on 前缀）──

        public RouteInfo onGet( string path, Function handler )
        {
            ret Router.add( "GET", path, handler )
        }

        public RouteInfo onPost( string path, Function handler )
        {
            ret Router.add( "POST", path, handler )
        }

        public RouteInfo onPut( string path, Function handler )
        {
            ret Router.add( "PUT", path, handler )
        }

        public RouteInfo onDelete( string path, Function handler )
        {
            ret Router.add( "DELETE", path, handler )
        }

        public RouteInfo onPatch( string path, Function handler )
        {
            ret Router.add( "PATCH", path, handler )
        }

        public RouteInfo onHead( string path, Function handler )
        {
            ret Router.add( "HEAD", path, handler )
        }

        public RouteInfo onOptions( string path, Function handler )
        {
            ret Router.add( "OPTIONS", path, handler )
        }

        # 全动词（对该 pattern 接受全部 HTTP 动词）
        public RouteInfo onAny( string path, Function handler )
        {
            ret Router.add( "ANY", path, handler )
        }

        # 原始形式（动态注册 / 方法变量）
        public RouteInfo on( string method, string path, Function handler )
        {
            ret Router.add( method, path, handler )
        }

        # ── 预装载路由注册中心（P4/P9 §26；attribute _enter_ 消费侧）──

        # 装配期缓冲（模块静态：Preload attribute 的 _enter_ 在入口调度
        # 前写入；reset() 不清空——与全局 Router 生命周期解耦，各 app
        # 经 usePreloadRoutes() 按需拉取，可多 app 反复并入）
        static List<string> _plVerbs = null
        static List<string> _plPatterns = null
        static List<Function> _plHandlers = null
        # 类级 @OnRoute 前缀表（宿主类全名 -> prefix）
        static Map<string, string> _plPrefix = null
        # 隐式默认 Server（装配期注册载体；端口 0 占位，不启动——
        # 真实 app 构造时覆盖引擎配置）
        static HttpServer _preloadHost = null

        # 隐式共享 Server（首次访问构造；@On* 家族 attribute 的 _enter_
        # 经它注册装配期路由——「new 一个 Server 后调它的实例方法」；
        # 名避关键字 default）
        public static HttpServer shared()
        {
            if HttpServer._preloadHost == null
            {
                HttpServer._preloadHost = HttpServer( 0 )
            }
            ret HttpServer._preloadHost
        }

        # verb 大写规整（HTTP 动词封闭集；大写原文直通——OnGet 家族
        # 传常量，@Route 传用户串；v1 无自定义动词用例）
        static string _upperVerb( string v )
        {
            if v == "get" { ret "GET" }

            if v == "post" { ret "POST" }

            if v == "put" { ret "PUT" }

            if v == "delete" { ret "DELETE" }

            if v == "patch" { ret "PATCH" }

            if v == "head" { ret "HEAD" }

            if v == "options" { ret "OPTIONS" }

            if v == "any" { ret "ANY" }

            ret v
        }

        # 预装载路由注册（方法级 attribute _enter_ 调用）：
        #   1. verb 大写规整；宿主类命中 @OnRoute 前缀则 prefix + path
        #      拼接（§4.10）；
        #   2. 宿主类已标 @InstanceAttr（Std）→ SystemAttributeGetInstanceField
        #      取装配期单实例（InstanceAttr._enter_ 构造并写入合成静态
        #      字段）→ hostMethodRefOf(单实例)（绑定实例 method-ref，全程
        #      复用，bind-once，§26）；否则 hostMethodRef()（LATE 闭包，
        #      每请求一实例，§4.10）；
        #   3. (verb, pattern, handler) 入缓冲，usePreloadRoutes() 拉取。
        public void registerPreload( string verb, string path, Attribute attr )
        {
            if HttpServer._plVerbs == null
            {
                HttpServer._plVerbs = new()
                HttpServer._plPatterns = new()
                HttpServer._plHandlers = new()
            }
            string cls = attr.ownerClassName()
            string full = path
            Map<string, string> pfxMap = HttpServer._plPrefix
            if pfxMap != null && pfxMap.containsKey( cls )
            {
                string pfx = pfxMap[ cls ]
                full = pfx + path
            }
            Function h = null
            object inst = SystemAttributeGetInstanceField( cls )
            if inst != null
            {
                h = attr.hostMethodRefOf( inst )
            }
            if h == null
            {
                h = attr.hostMethodRef()
            }
            HttpServer._plVerbs.add( HttpServer._upperVerb( verb ) )
            HttpServer._plPatterns.add( full )
            HttpServer._plHandlers.add( h )
        }

        # 类级 @OnRoute 前缀登记（类级 attribute _enter_ 调用；先于
        # 该类方法级 _enter_ 触发，前缀表就绪后拼接生效）
        public void registerPrefix( string prefix, string className )
        {
            if HttpServer._plPrefix == null
            {
                HttpServer._plPrefix = new()
            }
            HttpServer._plPrefix.add( className, prefix )
        }

        # ── 预装载路由接线（P4，§4.10 / §7）──

        # 把默认 Server 上缓冲的装配期路由（@OnGet 家族 / Route / OnRoute
        # 控制器语法经各 attribute _enter_ 注册）并入 Router。configure
        # 之后、start 之前调用；返回并入条数。重复调用按普通 Router.add
        # 语义（同 method+pattern 重复注册由 start() fail-fast 拦截，
        # ServerError.DuplicateRoute）。
        public Int32 usePreloadRoutes()
        {
            Int32 added = 0
            List<string> verbs = HttpServer._plVerbs
            if verbs != null
            {
                List<string> patterns = HttpServer._plPatterns
                List<Function> handlers = HttpServer._plHandlers
                Int32 n = verbs.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    string v = verbs[i]
                    string p = patterns[i]
                    Function h = handlers[i]
                    Router.add( v, p, h )
                    added = added + 1
                }
            }
            ret added
        }

        # ── 路由分组（前缀提取，Spring @RequestMapping 形态）──

        public RouteGroup group( string prefix )
        {
            ret RouteGroup( prefix )
        }

        # ── 中间件 / 插件（P2，§4.7）──

        # 注册中间件（三参 Function：function( SLang.Request req,
        # SLang.Response res, SLang.Next nx )；注册序即执行序；
        # nx.go() 放行 / 不调 = 短路）
        public void use( Function middleware )
        {
            HttpServerCore.use( middleware )
        }

        # 注册插件（ServerPlugin 子类；onInstall 立即执行，
        # onStart/onStop/onWsOpen/onWsClose 由引擎广播）
        public void use( ServerPlugin plugin )
        {
            HttpServerCore.use( plugin )
        }

        # ── API 文档（P3，§4.8）──

        # 文档路由开关（false = start 不挂 /docs 与 /openapi.json；
        # 生产建议关；reset() 恢复默认开）
        public void docs( bool enable )
        {
            HttpServerCore._docsEnabled = enable
        }

        # 反向导入 OpenAPI json（Apifox 导出 → 路由骨架）：
        # 返回新建文档路由数（未注册路径以 501 文档路由登记、/docs 可见；
        # 已注册路径仅合并文档元数据；后续 onGet(...) 同名覆盖生效，§4.8）
        public Int32 importOpenApi( string jsonPath ) throws
        {
            ret Docs.importOpenApi( jsonPath )
        }
    }
}
