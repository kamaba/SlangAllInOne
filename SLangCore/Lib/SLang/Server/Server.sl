import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Server.sl — 配置与错误码（P0 子集 → P1.5 增补）
    # 设计契约：SERVER_DESIGN.md §4.9（生命周期与配置）/ 附录 D（错误码表）
    #
    # 门面类 SLang.Server（App：onGet 家族 / group / use / run）随 P1 落地，
    # 当前直接使用 SLang.HttpServerCore。
    # 配置字段直改（无 builder 链）；后续阶段字段随能力增补：
    #   P1.5：maxUploadBytes / maxFileBytes（multipart，已落地）
    #   P2：writeTimeoutMs（流式写挂起超时）
    #   P3：maxConnections / showBanner
    # ============================================================================

    # 服务器配置
    public class ServerConfig
    {
        # 监听地址
        public string host = "0.0.0.0"
        # 监听端口（run(port) 为便捷覆盖）
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
    # UnknownSecurity=9 P3 / MissingJwtSecret=10 P5+）
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
    }

    # ============================================================================
    # SLang.Server — 应用门面（P1）
    # 设计契约：SERVER_DESIGN.md §0 / §4.1-§4.2 / §4.6 / §4.9
    #
    # 形态说明（SERVER_DESIGN.md §12 落地实录 ①）：C VM 对跨模块类多实例化
    # 的实例态隔离不可靠（[2026-10-17] 复盘），门面为**静态形态**——
    #   SLang.Server.configure( cfg ) / .onGet( path, fn ) / .run( port )
    # 与设计的 `var app = SLang.Server(); app.onGet(...)` 实例形态等价，
    # 单 VM 单服务器语义（§1.2）；多实例需求待 C VM 实例隔离修复。
    # 用法（§4.1 目标形态的静态等价）：
    #   import SLangServer;
    #   var cfg = SLang.ServerConfig();  cfg.port = 8080;
    #   SLang.Server.configure( cfg );
    #   SLang.Server.onGet( "/hello", function( SLang.Request req, SLang.Response res )
    #   {
    #       res.text( "hello world" );
    #   } );
    #   SLang.Server.run( 8080 );      # = start + awaitStop（阻塞直至 stop）
    # ============================================================================

    public class Server
    {
        # ── 配置 / 生命周期 ──

        # 配置（构造替代；start 前生效；重复调用覆盖配置）
        public static void configure( ServerConfig cfg )
        {
            HttpServerCore.configure( cfg )
        }

        # 启动（便捷覆盖端口；立即返回，accept 循环独立协程）
        public static void start( Int32 port ) throws
        {
            HttpServerCore.setListenPort( port )
            HttpServerCore.start()
        }

        public static void start() throws
        {
            HttpServerCore.start()
        }

        # 阻塞当前协程直至 stop（run = start + awaitStop）
        public static void run( Int32 port ) throws
        {
            SLang.Server.start( port )
            HttpServerCore.awaitStop()
        }

        # 停止（关监听 + 关全部在途连接；路由表保留，可重新 start 复用；
        # 需要清空路由用 reset()）
        public static void stop() throws
        {
            HttpServerCore.stop()
        }

        # 挂起直至停止（不经 start(port) 便捷形态时用）
        public static void awaitStop() throws
        {
            HttpServerCore.awaitStop()
        }

        # 清空路由表（HTTP + WS；stop 后重新配置用）
        public static void reset()
        {
            HttpServerCore.reset()
        }

        public static get bool isRunning()
        {
            ret HttpServerCore.isRunning
        }

        # ── 路由注册（动词家族；get/set 是关键字 → on 前缀）──

        public static RouteInfo onGet( string path, Function handler )
        {
            ret Router.add( "GET", path, handler )
        }

        public static RouteInfo onPost( string path, Function handler )
        {
            ret Router.add( "POST", path, handler )
        }

        public static RouteInfo onPut( string path, Function handler )
        {
            ret Router.add( "PUT", path, handler )
        }

        public static RouteInfo onDelete( string path, Function handler )
        {
            ret Router.add( "DELETE", path, handler )
        }

        public static RouteInfo onPatch( string path, Function handler )
        {
            ret Router.add( "PATCH", path, handler )
        }

        public static RouteInfo onHead( string path, Function handler )
        {
            ret Router.add( "HEAD", path, handler )
        }

        public static RouteInfo onOptions( string path, Function handler )
        {
            ret Router.add( "OPTIONS", path, handler )
        }

        # 全动词（对该 pattern 接受全部 HTTP 动词）
        public static RouteInfo onAny( string path, Function handler )
        {
            ret Router.add( "ANY", path, handler )
        }

        # 原始形式（动态注册 / 方法变量）
        public static RouteInfo on( string method, string path, Function handler )
        {
            ret Router.add( method, path, handler )
        }

        # ── WebSocket 路由（HTTP 同端口 Upgrade 分流；§4.6 形态 A）──

        # handler 签名约定：function( SLang.WsSession s )；会话协程内
        # 循环 s.receive()（null = 关闭），消息消费完调 m.release()
        public static RouteInfo websocket( string path, Function handler )
        {
            ret Router.addWs( path, handler )
        }

        # ── 路由分组（前缀提取，Spring @RequestMapping 形态）──

        public static RouteGroup group( string prefix )
        {
            ret RouteGroup( prefix )
        }

        # ── 中间件 / 插件（P2，§4.7）──

        # 注册中间件（三参 Function：function( SLang.Request req,
        # SLang.Response res, SLang.Next nx )；注册序即执行序；
        # nx.go() 放行 / 不调 = 短路）
        public static void use( Function middleware )
        {
            HttpServerCore.use( middleware )
        }

        # 注册插件（ServerPlugin 子类；onInstall 立即执行，
        # onStart/onStop/onWsOpen/onWsClose 由引擎广播）
        public static void use( ServerPlugin plugin )
        {
            HttpServerCore.use( plugin )
        }

        # ── WS 事件式糖（P2，§4.6）──

        # 事件式 WS 路由：wsEvents( path ).onOpen(fn).onMessage(fn).onClose(fn)
        #（内部仍是一协程；onMessage 回调内消费完消息调 m.release()）
        public static WsEventBuilder wsEvents( string path )
        {
            ret WsEventBuilder( path )
        }

        # ── 会话查询 / 组播（§4.6）──

        # 该 WS 路由的在线会话快照
        public static List<WsSession> sessions( string path )
        {
            ret _WsSessions.sessions( path )
        }

        # 组播文本（返回送达会话数；已断会话跳过）
        public static Int32 broadcast( string path, string text )
        {
            ret _WsSessions.broadcast( path, text )
        }

        # ── API 文档（P3，§4.8）──

        # 文档路由开关（false = start 不挂 /docs 与 /openapi.json；
        # 生产建议关；reset() 恢复默认开）
        public static void docs( bool enable )
        {
            HttpServerCore._docsEnabled = enable
        }

        # 反向导入 OpenAPI json（Apifox 导出 → 路由骨架）：
        # 返回新建文档路由数（未注册路径以 501 文档路由登记、/docs 可见；
        # 已注册路径仅合并文档元数据；后续 onGet(...) 同名覆盖生效，§4.8）
        public static Int32 importOpenApi( string jsonPath ) throws
        {
            ret Docs.importOpenApi( jsonPath )
        }
    }
}
