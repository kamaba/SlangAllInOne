import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/WebSocketServer.sl — WsSession / 会话注册表 / WebSocket 服务（实例双形态）
    # 设计契约：SERVER_DESIGN.md §4.6 / §6.8
    #
    # WsSession：包装 Net.WebSocketStream + 会话标识 + 路由信息（路径参数 /
    #   查询参数与 HTTP 路由同一套 {param} 语法）；模块内构造（引擎升级分流 /
    #   独立服务 accept 后创建），跨模块字段/方法消费（HttpResponse 安全模式）。
    # 注册表：按 pattern 分组（sessions/broadcast 的底座）。
    #
    # WebSocketServer（2026-10-26 自静态门面转实例形态——服务器类按协议
    #   分工，WS 侧 API 整体收口到本类；原 SLang.Server 上的 websocket/
    #   wsEvents/sessions/broadcast 四方法随之迁移）：
    #   形态 A（HTTP 同端口升级）：无参构造——依附 HttpServer 的监听端口，
    #     注册升级路由（websocket/wsEvents）+ 会话查询/组播；
    #   形态 B（独立端口）：带端口构造——裸 TCP 直握手，不经 HTTP 层，
    #     onMessage/onClose 回调 + 自有生命周期。
    #   两形态 idleTimeout(ms) 统一配置 WS 空闲心跳（升级形态写
    #     ServerConfig.wsIdleTimeoutMs、独立形态写本服务字段）。
    #
    # v1 语义说明：引擎与会话注册表均为模块级静态（C VM 跨模块多实例化
    #   实例态隔离不可靠，[2026-10-17] 复盘 ①；§19 Server→HttpServer 实例
    #   门面同款薄壳纪律）——实例方法只是转发层，状态跨实例共享，单 VM
    #   单 WS 服务语义。
    # ============================================================================

    # ── 会话注册表（内部静态；pattern → List<WsSession>）──
    class _WsSessions
    {
        static Map<string, object> _byPattern = null

        static void _ensure()
        {
            if _byPattern == null
            {
                _byPattern = new()
            }
        }

        static void register( string pattern, WsSession s )
        {
            _WsSessions._ensure()
            if pattern == null
            {
                pattern = ""
            }
            List<WsSession> list = null
            object cur = _byPattern[pattern]
            if cur == null
            {
                list = new()
                _byPattern[pattern] = list
            }
            else
            {
                list = cur as List<WsSession>
            }
            list.add( s )
        }

        static void unregister( string pattern, WsSession s )
        {
            if _byPattern == null
            {
                ret
            }
            if pattern == null
            {
                pattern = ""
            }
            object cur = _byPattern[pattern]
            if cur == null
            {
                ret
            }
            List<WsSession> list = cur as List<WsSession>
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                if list[i] == s
                {
                    list.removeRange( i, 1 )
                    ret
                }
            }
        }

        # 在线会话快照（该 pattern 全部会话）。
        # 注意：struct 登记类的方法体内 List.add 链解析失败（Front Meta 层，
        # _SrvUtil 头注记同款）——拷贝循环收进本内部类（sessions 是内部类方法）
        static List<WsSession> sessions( string pattern )
        {
            List<WsSession> outList = new()
            if _byPattern == null
            {
                ret outList
            }
            if pattern == null
            {
                pattern = ""
            }
            object cur = _byPattern[pattern]
            if cur == null
            {
                ret outList
            }
            List<WsSession> list = cur as List<WsSession>
            _WsSessions._copySessions( list, outList )
            ret outList
        }

        # 会话拷贝（内部类方法：List.add 在内部类内可解析）
        static void _copySessions( List<WsSession> src, List<WsSession> dst )
        {
            Int32 n = src.length
            for Int32 i = 0, i < n, i = i + 1
            {
                dst.add( src[i] )
            }
        }

        # 组播文本（已断会话 try? 吞错跳过）
        static Int32 broadcast( string pattern, string text )
        {
            Int32 sent = 0
            List<WsSession> list = _WsSessions.sessions( pattern )
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                WsSession s = list[i]
                label sendOne
                {
                    s.sendText( text )
                    sent = sent + 1
                }
                catch { }
            }
            ret sent
        }

        # 组播二进制（P6，§4.6 broadcast binary 重载；已断会话跳过）
        static Int32 broadcastBinary( string pattern, ByteBuffer payload )
        {
            Int32 sent = 0
            List<WsSession> list = _WsSessions.sessions( pattern )
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                WsSession s = list[i]
                label sendOne
                {
                    s.sendBinary( payload )
                    sent = sent + 1
                }
                catch { }
            }
            ret sent
        }

        # 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标）
        static Int32 broadcastTag( string pattern, string tag, string text )
        {
            Int32 sent = 0
            if tag == null
            {
                ret 0
            }
            List<WsSession> list = _WsSessions.sessions( pattern )
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                WsSession s = list[i]
                if _WsSessions.sessionTagged( s, tag ) == false
                {
                    continue
                }
                label sendOne
                {
                    s.sendText( text )
                    sent = sent + 1
                }
                catch { }
            }
            ret sent
        }

        # 定向组播二进制（P6，§4.6）
        static Int32 broadcastTagBinary( string pattern, string tag, ByteBuffer payload )
        {
            Int32 sent = 0
            if tag == null
            {
                ret 0
            }
            List<WsSession> list = _WsSessions.sessions( pattern )
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                WsSession s = list[i]
                if _WsSessions.sessionTagged( s, tag ) == false
                {
                    continue
                }
                label sendOne
                {
                    s.sendBinary( payload )
                    sent = sent + 1
                }
                catch { }
            }
            ret sent
        }

        # ── 会话标签（P6，§4.6 定向广播底座；struct 登记类 WsSession
        #    方法体内 List.add 链解析失败纪律——容器写操作全部收进本
        #    内部类，_SrvUtil/_WsSessions 先例同款）──

        # 打标签（幂等；null/空名忽略）
        static void tagSession( WsSession s, string name )
        {
            if s == null || name == null
            {
                ret
            }
            if SystemStringLength( name ) == 0
            {
                ret
            }
            if s._tags == null
            {
                s._tags = new()
            }
            if _WsSessions._hasTag( s._tags, name )
            {
                ret
            }
            s._tags.add( name )
        }

        # 移除标签（无该标签 no-op）
        static void untagSession( WsSession s, string name )
        {
            if s == null || s._tags == null || name == null
            {
                ret
            }
            List<string> ts = s._tags
            Int32 n = ts.length
            for Int32 i = 0, i < n, i = i + 1
            {
                if ts[i] == name
                {
                    ts.removeRange( i, 1 )
                    ret
                }
            }
        }

        # 是否带该标签
        static bool sessionTagged( WsSession s, string name )
        {
            if s == null || s._tags == null || name == null
            {
                ret false
            }
            ret _WsSessions._hasTag( s._tags, name )
        }

        # 标签快照（List<string> 拷贝）
        static List<string> sessionTags( WsSession s )
        {
            List<string> outList = new()
            if s == null || s._tags == null
            {
                ret outList
            }
            List<string> ts = s._tags
            Int32 n = ts.length
            for Int32 i = 0, i < n, i = i + 1
            {
                outList.add( ts[i] )
            }
            ret outList
        }

        # 标签线性查找（标签数少，无需哈希集）
        static bool _hasTag( List<string> ts, string name )
        {
            Int32 n = ts.length
            for Int32 i = 0, i < n, i = i + 1
            {
                if ts[i] == name
                {
                    ret true
                }
            }
            ret false
        }
    }

    # ============================================================================
    # WsSession — WebSocket 会话（模块内构造；用户侧只消费）
    # ============================================================================
    public class WsSession
    {
        # 底层连接（握手完成后移交）
        Net.WebSocketStream _ws = null
        # 会话标识（GUID 字符串；注册表键）
        string _id = ""
        # 对端地址（"ip:port"）
        string _remote = ""
        # 命中的路由 pattern（注册表分组键）
        string _pattern = ""
        # 升级 URL 的路径参数
        Map<string,string> _pathParams = null
        # 升级 URL 原始 query（惰性解码）
        string _rawQuery = ""
        Map<string,string> _queryParsed = null
        # ── 空闲心跳（P5，§6.8）──
        # 最后活跃时刻（receive 返回时刷新；构造即 now）
        Int64 _lastActive = 0
        # 空闲超时毫秒（引擎/独立服务接线时写入；<= 0 = 不启用）
        Int32 _idleMs = 0
        # 看门狗已启动（防重复 spawn）
        bool _watchdogOn = false
        # ── 会话标签（P6，§4.6 定向广播底座；惰性建表，写操作经
        #    _WsSessions 内部类——struct 登记类 List.add 纪律）──
        List<string> _tags = null

        # 引擎/独立服务内部构造（用户勿直接 new）
        _init_( Net.WebSocketStream ws, string pattern, Map<string,string> pathParams, string rawQuery )
        {
            this._ws = ws
            this._id = Guid.newGuid()
            this._pattern = pattern
            this._pathParams = pathParams
            this._rawQuery = rawQuery
            this._lastActive = OS.Timer.now()
            this._idleMs = 0
            this._watchdogOn = false
            this._tags = null
            string ra = ws.remoteAddress
            Int32 rp = ws.remotePort
            this._remote = ra + ":" + rp.toString()
        }

        # 空闲心跳配置 + 看门狗启动（引擎在会话注册后调用；idleMs <= 0 不启用）。
        # 语义：空闲超过 idleMs（无任何入站消息）→ 看门狗主动 close 会话
        # （handler 的 receive 随之返回 null 自然收尾）；对端主动 Ping 的
        # autoPong 回帧发生在 handler 协程（receive 循环内），与看门狗的
        # close 写帧存在极小交错窗口（单 VM 非抢占，仅在写挂起点切换），
        # v1 接受——写锁留后续。
        void _startHeartbeat( Int32 idleMs )
        {
            this._idleMs = idleMs
            if idleMs <= 0 || this._watchdogOn
            {
                ret
            }
            this._watchdogOn = true
            # 闭包零捕获（P0 复盘纪律）：session 经实参传值
            WsSession self = this
            function wd = function( object a )
            {
                WsSession._watchdogLoop( a as WsSession )
            }
            Coroutine.spawnClosure1( wd, self )
        }

        # 看门狗协程体：周期检查空闲；超时关会话后退出（会话先关也退出）
        static void _watchdogLoop( WsSession s )
        {
            Int32 idle = s._idleMs
            if idle <= 0
            {
                ret
            }
            # 检查步长：idle/4，钳制 [100, 1000]ms
            Int32 step = idle / 4
            if step < 100
            {
                step = 100
            }
            if step > 1000
            {
                step = 1000
            }
            bool run = true
            while run
            {
                Coroutine.delay( step )
                if s.isOpen == false
                {
                    run = false
                }
                elif OS.Timer.now() - s._lastActive > idle
                {
                    s.close()
                    run = false
                }
            }
        }

        # ── 会话标识 ──

        public get string id()
        {
            ret this._id
        }

        public get string remoteAddress()
        {
            ret this._remote
        }

        # 命中的路由 pattern（注册/broadcast 分组键）
        public get string routePattern()
        {
            ret this._pattern
        }

        # ── 升级 URL 参数（与 HTTP 路由同一套 {param} 语法）──

        # 路径段参数；不存在返回 null
        public string pathParam( string name )
        {
            if this._pathParams == null
            {
                ret null
            }
            if this._pathParams.containsKey( name ) == false
            {
                ret null
            }
            ret this._pathParams[name]
        }

        # 路径参数 Int32 化；坏格式用 defVal
        public Int32 pathInt( string name, Int32 defVal )
        {
            string v = this.pathParam( name )
            if v == null
            {
                ret defVal
            }
            Int64 parsed = HttpServerCore._parseDec64( v )
            if parsed < 0
            {
                ret defVal
            }
            ret parsed.toInt32()
        }

        # 查询参数（已解码：percent-decode + '+'→空格）；不存在返回 null
        public string query( string name )
        {
            if this._queryParsed == null
            {
                this._queryParsed = BodyParser.parseForm( this._rawQuery )
            }
            if this._queryParsed.containsKey( name ) == false
            {
                ret null
            }
            ret this._queryParsed[name]
        }

        # ── 会话标签（P6，§4.6：定向广播 broadcastTag 按标签过滤；
        #    容器写操作经 _WsSessions 内部类——struct 登记类 List.add 纪律）──

        # 打标签（幂等；null/空名忽略）
        public void tag( string name )
        {
            _WsSessions.tagSession( this, name )
        }

        # 移除标签（无该标签 no-op）
        public void untag( string name )
        {
            _WsSessions.untagSession( this, name )
        }

        # 是否带该标签
        public bool tagged( string name )
        {
            ret _WsSessions.sessionTagged( this, name )
        }

        # 标签快照（List<string> 拷贝）
        public get List<string> tags()
        {
            ret _WsSessions.sessionTags( this )
        }

        # ── 收发（透传底层连接）──

        # 收一条完整消息（null = 连接关闭；载荷归属返回值，消费完 release）
        # P5：成功返回即刷新 _lastActive（空闲心跳观测点）
        public Net.WsMessage receive() throws
        {
            Net.WsMessage m = this._ws.receive()
            this._lastActive = OS.Timer.now()
            ret m
        }

        public void sendText( string text ) throws
        {
            this._ws.sendText( text )
        }

        # 二进制（底层 slice 视图，src 不被读空）
        public void sendBinary( ByteBuffer payload ) throws
        {
            this._ws.sendBinary( payload )
        }

        public void sendPing() throws
        {
            this._ws.sendPing()
        }

        # 优雅关闭（尽力发 Close 帧后关底层流）
        public void close()
        {
            label closeWs
            {
                this._ws.close()
            }
            catch { }
        }

        public get Net.WsCloseInfo closeInfo()
        {
            ret this._ws.closeInfo
        }

        public get bool isOpen()
        {
            ret this._ws.state == Net.WsState.Open
        }
    }

    # ============================================================================
    # WebSocketServer — WebSocket 服务（实例形态，双形态）
    #
    # 形态 A（HTTP 同端口升级——依附 HttpServer 监听）：
    #   SLang.WebSocketServer ws = SLang.WebSocketServer();
    #   ws.websocket( "/chat", function( SLang.WsSession s ) { ... } );
    #   ws.wsEvents( "/tick" ).onOpen( fn ).onMessage( fn ).onClose( fn );
    #   ws.sessions( "/chat" ); ws.broadcast( "/chat", text );
    #   # HttpServer.start() 后升级路由生效（Upgrade 分流在引擎层）
    #
    # 形态 B（独立端口——裸 TCP 直握手，不经 HTTP 层；§4.6 形态 B）：
    #   SLang.WebSocketServer wss = SLang.WebSocketServer( 9090 );
    #   wss.onMessage( function( SLang.WsSession s, Net.WsMessage m ) { ... } );
    #   wss.onClose(  function( SLang.WsSession s ) { ... } );
    #   wss.start();                          # 或 run( port ) 阻塞形态
    #   wss.sessions(); wss.broadcast( text );
    #
    # 两形态通用：idleTimeout( ms ) 空闲心跳（升级形态写 ServerConfig，
    # 独立形态写本服务字段）。
    # 静态状态保留（v1 单 VM 单 WS 服务语义，§19 实例门面同款薄壳纪律）。
    # ============================================================================
    public class WebSocketServer
    {
        # 独立监听端口（构造入参；0 = 形态 A——不独立监听，仅升级路由注册器）
        public Int32 port = 0

        # ── 独立形态静态状态（模块级单例；实例方法转发）──
        static Int32 _listenPort = 0
        static Net.TcpServer _server = null
        static bool _running = false
        static Task _acceptTask = null
        # function( WsSession s, Net.WsMessage m )；消息回调（msg 归回调所有，
        # 消费完调 m.release()；WebSocketClient.onMessage 先例）
        static Function _onMessage = null
        # function( WsSession s )；会话收尾回调（可选）
        static Function _onClose = null
        # WS 会话空闲超时毫秒（P5，§6.8；<= 0 不启用；start 前生效）
        static Int32 _idleTimeoutMs = 0
        # 本服务在线会话注册键（sessions/broadcast 底座）。
        # 静态 string 字面量默认值初始化不可靠（[2026-10-17] 复盘 ② 同族），
        # 经方法返回字面量（模块内字符串常量可靠）
        static string _key()
        {
            ret "*standalone*"
        }

        # ── 构造 ──

        # 形态 A：HTTP 同端口升级路由器（依附 HttpServer 监听；无独立端口）
        public void _init_()
        {
            this.port = 0
        }

        # 形态 B：独立端口 WS 服务（裸 TCP 直握手）
        public void _init_( Int32 port )
        {
            this.port = port
            WebSocketServer._listenPort = port
        }

        # ── 形态 A：HTTP 同端口升级路由（§4.6 形态 A）──

        # WS 升级路由注册（HTTP 引擎 Upgrade 分流命中后进 handler）。
        # handler 签名约定：function( SLang.WsSession s )；会话协程内
        # 循环 s.receive()（null = 关闭），消息消费完调 m.release()
        public RouteInfo websocket( string path, Function handler )
        {
            ret Router.addWs( path, handler )
        }

        # 事件式 WS 路由糖：wsEvents( path ).onOpen(fn).onMessage(fn).onClose(fn)
        #（内部仍是一协程；onMessage 回调内消费完消息调 m.release()）
        public WsEventBuilder wsEvents( string path )
        {
            ret WsEventBuilder( path )
        }

        # 该 WS 路由的在线会话快照
        public List<WsSession> sessions( string path )
        {
            ret _WsSessions.sessions( path )
        }

        # 组播文本到该 WS 路由（返回送达会话数；已断会话跳过）
        public Int32 broadcast( string path, string text )
        {
            ret _WsSessions.broadcast( path, text )
        }

        # 组播二进制到该 WS 路由（P6，§4.6 binary 重载；返回送达会话数）
        public Int32 broadcast( string path, ByteBuffer payload )
        {
            ret _WsSessions.broadcastBinary( path, payload )
        }

        # 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标；
        # 返回送达数）
        public Int32 broadcastTag( string path, string tag, string text )
        {
            ret _WsSessions.broadcastTag( path, tag, text )
        }

        # 定向组播二进制（P6，§4.6；返回送达数）
        public Int32 broadcastTag( string path, string tag, ByteBuffer payload )
        {
            ret _WsSessions.broadcastTagBinary( path, tag, payload )
        }

        # ── 形态 B：独立端口生命周期（§4.6 形态 B）──

        # 消息回调（2 参：会话 + 消息；msg 归回调所有）
        public void onMessage( Function fn )
        {
            WebSocketServer._onMessage = fn
        }

        # 会话收尾回调（1 参：会话）
        public void onClose( Function fn )
        {
            WebSocketServer._onClose = fn
        }

        public get bool isRunning()
        {
            ret WebSocketServer._running
        }

        # 启动独立监听（端口 = 构造端口 / 本方法覆盖；立即返回，accept
        # 循环独立协程）
        public void start( Int32 port ) throws
        {
            this.port = port
            WebSocketServer._listenPort = port
            WebSocketServer._startInternal()
        }

        # 启动独立监听（端口 = 构造端口）
        public void start() throws
        {
            if this.port > 0
            {
                WebSocketServer._listenPort = this.port
            }
            WebSocketServer._startInternal()
        }

        # 内部启动体（静态；端口取 _listenPort）
        static void _startInternal() throws
        {
            if _running
            {
                throw ServerError.AlreadyRunning
            }
            if _listenPort <= 0 || _listenPort > 65535
            {
                throw ServerError.InvalidConfig
            }
            _server = Net.Tcp.listen( _listenPort )
            _running = true
            # accept 循环协程：闭包零捕获，实参传值（NetConcurrentTest.ef 先例）
            Net.TcpServer srv = _server
            function f = function( object a )
            {
                WebSocketServer._acceptLoop( a as Net.TcpServer )
            }
            _acceptTask = Coroutine.spawnClosure1( f, srv )
        }

        # 停止：关监听 + 关全部会话（会话协程随 receive null 自然收尾注销）
        public void stop() throws
        {
            if !WebSocketServer._running
            {
                throw ServerError.NotRunning
            }
            WebSocketServer._running = false
            if WebSocketServer._server != null
            {
                WebSocketServer._server.close()
                WebSocketServer._server = null
            }
            string key = WebSocketServer._key()
            List<WsSession> list = _WsSessions.sessions( key )
            Int32 n = list.length
            for Int32 i = 0, i < n, i = i + 1
            {
                WsSession s = list[i]
                s.close()
            }
        }

        # 挂起直至停止
        public void awaitStop() throws
        {
            if WebSocketServer._acceptTask == null
            {
                throw ServerError.NotRunning
            }
            Task t = WebSocketServer._acceptTask
            Coroutine.awaitTask( t )
        }

        # run = start + awaitStop（阻塞当前协程直至 stop）
        public void run( Int32 port ) throws
        {
            this.start( port )
            this.awaitStop()
        }

        # ── 形态 B：独立端口会话查询 / 组播（无参重载）──

        # 独立端口全部在线会话快照
        public List<WsSession> sessions()
        {
            ret _WsSessions.sessions( WebSocketServer._key() )
        }

        # 组播文本到独立端口全部会话（返回送达数）
        public Int32 broadcast( string text )
        {
            ret _WsSessions.broadcast( WebSocketServer._key(), text )
        }

        # 组播二进制到独立端口全部会话（P6，§4.6；返回送达数）
        public Int32 broadcast( ByteBuffer payload )
        {
            ret _WsSessions.broadcastBinary( WebSocketServer._key(), payload )
        }

        # 定向组播文本（P6，§4.6：只发带 tag 标签的会话；返回送达数）
        public Int32 broadcastTag( string tag, string text )
        {
            ret _WsSessions.broadcastTag( WebSocketServer._key(), tag, text )
        }

        # 定向组播二进制（P6，§4.6；返回送达数）
        public Int32 broadcastTag( string tag, ByteBuffer payload )
        {
            ret _WsSessions.broadcastTagBinary( WebSocketServer._key(), tag, payload )
        }

        # ── 两形态通用：WS 空闲心跳（P5，§6.8）──

        # 空闲超时配置：无入站消息超过 ms 即断开会话（<= 0 不启用）。
        # 形态 A（升级路由）：写 ServerConfig.wsIdleTimeoutMs（HttpServer
        # 须已构造——时序：先 HttpServer( port ) 再本调用）；
        # 形态 B（独立端口）：写本服务字段（start 前生效）
        public void idleTimeout( Int32 idleTimeoutMs )
        {
            WebSocketServer._idleTimeoutMs = idleTimeoutMs
            ServerConfig cfg = HttpServerCore._cfg
            if cfg != null
            {
                cfg.wsIdleTimeoutMs = idleTimeoutMs
            }
        }

        # ── 内部：accept 循环（每连接一协程：握手 → 会话循环 → 收尾）──

        static void _acceptLoop( Net.TcpServer srv )
        {
            bool run = true
            while run
            {
                label accOne
                {
                    Net.TcpStream client = srv.accept()
                    # 连接协程：零捕获 + 实参传值
                    function f = function( object a )
                    {
                        WebSocketServer._runSession( a as Net.TcpStream )
                    }
                    Coroutine.spawnClosure1( f, client )
                }
                catch
                {
                    # 监听已关闭（stop）或 accept 失败：退出循环
                    run = false
                }
            }
        }

        # 单连接会话：握手 → WsSession → 消息循环（onMessage）→ 收尾（onClose）
        static void _runSession( Net.TcpStream client )
        {
            string key = WebSocketServer._key()
            # ws/s 提到 label 块外声明：catch 收尾路径须可见（stop() 强制
            # 关闭会令 receive 抛异常走 catch，漏注销则 sessions 不清零）
            Net.WebSocketStream ws = null
            WsSession s = null
            label sessBlock
            {
                # 独立形态无 HTTP 预读 → 两参 accept（无 preRead）
                ws = Net.WebSocketStream.accept( client, null )
                s = WsSession( ws, key, null, "" )
                _WsSessions.register( key, s )
                # 空闲心跳看门狗（P5，§6.8；同引擎升级分流形态）
                if WebSocketServer._idleTimeoutMs > 0
                {
                    s._startHeartbeat( WebSocketServer._idleTimeoutMs )
                }
                # 插件 WS 会话钩子（对所有插件广播，§6.9）
                _PluginHost.notifyWsOpen( s )
                # Function 字段先拷局部再传参/调用（HttpHeaders 头注记纪律）
                function hMsg = _onMessage
                bool looping = true
                while looping
                {
                    Net.WsMessage m = ws.receive()
                    if m == null
                    {
                        looping = false
                    }
                    elif hMsg != null
                    {
                        # 回调异常吞掉（会话不因单条消息处理失败而中断；
                        # WebSocketClient 事件循环同款取舍）
                        label msgBlock
                        {
                            hMsg( s, m )
                        }
                        catch { }
                    }
                }
                _WsSessions.unregister( key, s )
                # 插件 WS 会话钩子（注销后广播，§6.8 收尾序）
                _PluginHost.notifyWsClose( s )
                function hClose = _onClose
                if hClose != null
                {
                    label closeCb
                    {
                        hClose( s )
                    }
                    catch { }
                }
                ws.close()
            }
            catch
            {
                # 握手失败 / IO 异常（含 stop() 强制关闭）：已注册会话
                # 仍须注销 + 通知 onClose，再静默收尾
                if s != null
                {
                    _WsSessions.unregister( key, s )
                    function hClose2 = _onClose
                    if hClose2 != null
                    {
                        label closeCb2
                        {
                            hClose2( s )
                        }
                        catch { }
                    }
                }
                label rawClose
                {
                    if ws != null
                    {
                        ws.close()
                    }
                    client.close()
                }
                catch { }
                ret
            }
            # 正常路径：ws.close() 已关底层流，client.close 幂等无害
            label cleanup
            {
                client.close()
            }
            catch { }
        }
    }

    # ============================================================================
    # WsEventBuilder — WS 事件式糖（P2，§4.6：wsEvents(path).onOpen(...)
    #   .onMessage(...).onClose(...)；内部仍是一协程，适合不想写循环的场景）
    # WebSocketServer.wsEvents(path) 构造：构造期注册 WS 路由，会话回调经
    # 静态注册表按 pattern 反查分发（闭包零捕获纪律，P0 复盘）。
    # 回调签名：onOpen/onClose = function( WsSession s )；
    #   onMessage = function( WsSession s, Net.WsMessage m )——消息归回调
    #   所有，消费完调 m.release()（§4.7 示例同款约定）。
    # ============================================================================
    class _WsEventRoutes
    {
        # pattern → WsEventBuilder（静态注册表）
        static Map<string, object> _byPattern = null

        static void register( string pattern, WsEventBuilder b )
        {
            if _WsEventRoutes._byPattern == null
            {
                _WsEventRoutes._byPattern = new()
            }
            _WsEventRoutes._byPattern[pattern] = b
        }

        static WsEventBuilder find( string pattern )
        {
            if _WsEventRoutes._byPattern == null
            {
                ret null
            }
            if pattern == null
            {
                pattern = ""
            }
            object cur = _WsEventRoutes._byPattern[pattern]
            if cur == null
            {
                ret null
            }
            ret cur as WsEventBuilder
        }
    }

    public class WsEventBuilder
    {
        string _pattern = ""
        Function _onOpen = null
        Function _onMessage = null
        Function _onClose = null

        # 构造即注册 WS 路由（WebSocketServer.wsEvents 调用；用户勿直接 new）
        _init_( string path )
        {
            this._pattern = path
            _WsEventRoutes.register( path, this )
            # 会话回调零捕获：经 s.routePattern() 静态反查 builder 分发；
            # 闭包字面量先赋局部变量再传参（内联实参形态语言不支持）
            function h = function( SLang.WsSession s )
            {
                WsEventBuilder._serve( s )
            }
            Router.addWs( path, h )
        }

        # ── 链式事件注册 ──

        public WsEventBuilder onOpen( Function fn )
        {
            this._onOpen = fn
            ret this
        }

        public WsEventBuilder onMessage( Function fn )
        {
            this._onMessage = fn
            ret this
        }

        public WsEventBuilder onClose( Function fn )
        {
            this._onClose = fn
            ret this
        }

        # 会话服务（注册的 WS 路由回调；单协程——open → 消息循环 → close）
        static void _serve( WsSession s )
        {
            WsEventBuilder b = _WsEventRoutes.find( s.routePattern )
            if b == null
            {
                ret
            }
            # Function 字段先拷局部（HttpHeaders 头注记纪律）
            function hop = b._onOpen
            if hop != null
            {
                label openCb
                {
                    hop( s )
                }
                catch { }
            }
            function hm = b._onMessage
            bool looping = true
            while looping
            {
                Net.WsMessage m = s.receive()
                if m == null
                {
                    looping = false
                }
                elif hm != null
                {
                    # 回调异常吞掉（会话不因单条消息失败而中断）
                    label msgCb
                    {
                        hm( s, m )
                    }
                    catch { }
                }
                else
                {
                    m.release()
                }
            }
            function hc = b._onClose
            if hc != null
            {
                label closeCb
                {
                    hc( s )
                }
                catch { }
            }
        }
    }
}
