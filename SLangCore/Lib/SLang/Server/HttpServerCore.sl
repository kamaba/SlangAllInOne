import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/HttpServerCore.sl — HTTP/1.1 连接引擎（P0 → P1 → P1.5）
    # 设计契约：SERVER_DESIGN.md §6.1 / §6.2 / §6.8 / §6.4-6.5（上传）
    #
    # 范围（P1）：
    #   - _HttpParser：请求行 / 头（行数与总字节双上限）/ body（Content-Length
    #     精确读 | chunked 聚合 | 无则空）解析，预读缓冲跨 read 边界安全；
    #   - 响应编码：状态行 + Content-Type/Length/Connection + 用户头 + body；
    #   - keep-alive 循环（每连接一协程；Connection: close / HTTP/1.0 即断，
    #     残留预读自然衔接下一条请求）；
    #   - handler 协程派发：spawnClosure2 独立协程 + waitTimeout 超时守护
    #     （超时 cancel + 504 + 断连）+ awaitTask 等待（异常传播走 500 兜底）；
    #   - 路由：Router（{param} 段参数提取 / 404·405+Allow / ANY /
    #     HEAD 视同 GET / DuplicateRoute fail-fast）；
    #   - WS Upgrade 分流：Upgrade: websocket 命中 WS 路由 → 三参 accept
    #     （预读残留直传）→ WsSession 会话；未命中 / 握手失败 → 400。
    #
    # 范围（P1.5 上传）：
    #   - body 上限分流：multipart 请求按 maxUploadBytes 判 413（CL 与
    #     chunked 两路），其余请求维持 maxBodyBytes（§6.4 第 5 步）；
    #   - multipart 即时解析：handler 派发前经 Request._ensureMultipart
    #     （构造期语义 §6.5）——单文件超 maxFileBytes → 413、boundary
    #     缺失/格式坏 → 400，均优雅断连（协议层，§6.11）；
    #   - 请求级资源回收 _releaseRequest：body + multipart 文件内容缓冲
    #     （UploadedFile._data）请求收尾统一回收（§6.5）。
    #
    # 范围（P2 管道与流式）：
    #   - 中间件管道：连接协程内联执行（onion 嵌套；中间件可 await，§6.9），
    #     尾环 = handler 协程派发 或 404/405 应答（未匹配请求同样过管道
    #     ——staticFiles / CORS 预检依赖此语义）；_PluginHost 承载中间件与
    #     插件（生命周期 / WS 钩子广播），reset 联动清空；
    #   - 流式响应三态写出：chunked（stream/sse——头已直发，引擎兜底
    #     close）/ sendFile 直写完成（Content-Length 精确）/ 普通缓冲；
    #     handler 超时豁免：流式开启后 handlerTimeoutMs 不再掐（转无限
    #     等待，写侧由连接级 writeTimeoutMs 守护，§6.1 / §6.6）。
    #
    # 随后阶段：P3 文档（OpenAPI/docs）+ 认证（auth 插件/Jwt）。
    #
    # 复用（不改动，G8 边界内）：Net.TcpServer / Net.TcpStream / Net.HttpHeaders /
    #   Net.WebSocketStream / Coroutine / ByteBuffer。语言纪律：get/set/next/
    #   data/as/is/out/return 为关键字不作方法名与标识符；Function 字段先拷
    #   局部再传参（HttpHeaders 头注记先例）；子类实参经局部赋型上行
    #   （HttpTest 头注记先例）。
    # ============================================================================

    # 内部：请求解析结果（errorCode 0 = OK；400 / 413 / 431）
    class _HttpParseResult
    {
        Int32 _errorCode = 0
        string _method = ""
        string _path = ""
        string _rawQuery = ""
        bool _http10 = false
        Net.HttpHeaders _headers = null
        ByteBuffer _body = null
        # ── 请求侧流式（P5，§6.6）──
        # stopAtHead 形态：头区空行后停止预读，body 元信息经此带出
        Int64 _streamCl = 0
        bool _streamChunked = false
    }

    public class HttpServerCore
    {
        # P0 形态：模块级单例（全静态）——SERVER_DESIGN.md §1.2「单 VM 协程
        # 调度即全部并发」的 v1 服务器语义。实测跨模块类多实例化在 C VM
        # 存在实例态串扰（S2 连接读到 S1 的路由表，闭包零捕获 + 实参传值
        # 亦无法规避），静态化是最小可靠路径。门面 SLang.HttpServer 已转
        # 实例形态（构造带端口），全部经本类静态转发——单 VM 单服务器语义，
        # 多实例待 C VM 实例隔离修复。
        static ServerConfig _cfg = null
        static Net.TcpServer _server = null
        static bool _running = false
        static Task _acceptTask = null
        # 跨模块点分类型不能作泛型参数（Front：模板中不允许 . 连接符号）——
        # 连接表用 List<object> + as Net.TcpStream 转型
        static List<object> _conns = null
        # ── 多监听器（v1.1）：同进程多端口挂载 ──
        # 监听器表（主监听器 + listen() 扩展监听器；object + as 转型同
        # _conns 纪律），平行 tag / port 表——连接协程经 _tagOf/_portOf
        # 身份扫描反查（TcpServer 跨模块多实例安全：C 侧 sid 薄包装）。
        # 主监听器 tag 恒 = 1；扩展监听器由 _nextTag 分配 2,3,...
        static List<object> _servers = null
        static List<Int32> _serverTags = null
        static List<Int32> _serverPorts = null
        # listen() 待注册缓冲（未 running 时调用先缓存，start() 统一
        # bind；stop/reset 清空）
        static List<string> _pendHosts = null
        static List<Int32> _pendPorts = null
        static List<Int32> _pendTags = null
        # 监听器 tag 发生器（主监听器 = 1 固定；listen() 分配 2 起；
        # stop 重置 2）
        static Int32 _nextTag = 2
        # 监听参数构造期提取为单层静态字段（this._cfg.host 双层链求值坑规避）
        static string _listenHost = ""
        static Int32 _listenPort = 0
        # 文档路由开关（P3，§4.8 app.docs(false) 消费；start 挂载 /docs +
        # /openapi.json；reset 恢复默认开）
        public static bool _docsEnabled = true
        # app 级事件钩子（P6，§4.9：门面 set/get 访问器写读；
        # onStart/onStop = function()；onError = function( Request req,
        # Response res, Error e )——钩子零捕获（体内只能引用全局静态）；
        # reset 清空）
        public static Function _hookOnStart = null
        public static Function _hookOnStop = null
        public static Function _hookOnError = null

        # 便捷覆盖监听端口（Server.start(port)/run(port) 用；start 前生效）
        public static void setListenPort( Int32 port )
        {
            _listenPort = port
            if _cfg != null
            {
                _cfg.port = port
            }
        }

        # 初始化配置（构造替代；重复调用覆盖配置，start 前生效）
        public static void configure( ServerConfig cfg )
        {
            _cfg = cfg
            _listenHost = cfg.host
            _listenPort = cfg.port
            if _conns == null
            {
                _conns = new()
            }

            if _servers == null
            {
                _servers = new()
                _serverTags = new()
                _serverPorts = new()
            }

            if _pendHosts == null
            {
                _pendHosts = new()
                _pendPorts = new()
                _pendTags = new()
            }
        }

        # 清空路由表与中间件/插件（stop 后重新配置用；连接表由 stop 清理）；
        # app 级事件钩子一并清空（P6，§4.9）
        public static void reset()
        {
            Router.clear()
            _PluginHost.clear()
            _docsEnabled = true
            _hookOnStart = null
            _hookOnStop = null
            _hookOnError = null
            # 多监听器待注册缓冲清空（stop 后重新配置用）
            _pendHosts = new()
            _pendPorts = new()
            _pendTags = new()
        }

        # ── 中间件/插件（P2；SLang.Server.use 转发）──

        # 注册中间件（三参 Function(req,res,nx)；注册序即执行序）
        public static void use( Function middleware )
        {
            _PluginHost.addMiddleware( middleware )
        }

        # 注册插件（onInstall 立即执行；生命周期/WS 钩子由引擎广播）
        public static void use( ServerPlugin plugin )
        {
            plugin.onInstall()
            _PluginHost.addPlugin( plugin )
        }

        # ── 路由注册（P1 起经 Router；推荐用 SLang.HttpServer 门面——返回 RouteInfo 可写文档元数据）──

        # 原始形式（动态注册 / 方法变量）
        public static RouteInfo on( string method, string path, Function handler )
        {
            ret Router.add( method, path, handler )
        }

        public static RouteInfo onGet( string path, Function handler )
        {
            ret Router.add( "GET", path, handler )
        }

        public static RouteInfo onPost( string path, Function handler )
        {
            ret Router.add( "POST", path, handler )
        }

        public static RouteInfo onAny( string path, Function handler )
        {
            ret Router.add( "ANY", path, handler )
        }

        # WS 升级路由（SLang.WebSocketServer.websocket 同源）
        public static RouteInfo websocket( string path, Function handler )
        {
            ret Router.addWs( path, handler )
        }

        # ── WS 会话查询 / 组播（引擎级静态通道；门面 app.sessions /
        #    app.broadcast 实例方法同源转发）──
        # 闭包零捕获场景（waitCond 轮询判据 / WS 会话回调内组播等无
        # 实例引用可用的位置）经本组静态查询与组播，语义与门面实例
        # 形态完全一致（§4.6）。

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

        # 组播二进制（P6，§4.6 binary 重载；返回送达会话数）
        public static Int32 broadcast( string path, ByteBuffer payload )
        {
            ret _WsSessions.broadcastBinary( path, payload )
        }

        # 定向组播文本（P6，§4.6：只发带 tag 标签的会话——s.tag 打标；
        # 闭包零捕获场景经本静态通道，语义与门面一致）
        public static Int32 broadcastTag( string path, string tag, string text )
        {
            ret _WsSessions.broadcastTag( path, tag, text )
        }

        # 定向组播二进制（P6，§4.6）
        public static Int32 broadcastTag( string path, string tag, ByteBuffer payload )
        {
            ret _WsSessions.broadcastTagBinary( path, tag, payload )
        }

        # ── 生命周期 ──

        public static get bool isRunning()
        {
            ret _running
        }

        # 启动监听（立即返回；accept 循环进独立协程）
        public static void start() throws
        {
            if _running
            {
                throw ServerError.AlreadyRunning
            }

            if _listenPort <= 0 || _listenPort > 65535
            {
                throw ServerError.InvalidConfig
            }
            # 路由冲突检测（fail-fast，防静默覆盖；SERVER_DESIGN.md §6.2）
            string dup = Router.checkDuplicate()
            if dup != null
            {
                throw ServerError.DuplicateRoute
            }

            # 文档路由挂载（P3，§4.8/§6.10：start 时自动挂 /docs +
            # /openapi.json；用户已注册同路径则让位——用户优先）
            if _docsEnabled
            {
                Docs._mount()
            }
            string host = _listenHost
            Int32 lport = _listenPort
            # 跨模块 string 字段默认值初始化不可靠（实测消费侧读出空串/
            # null，Int32 正常）——空值兜底 "0.0.0.0"（本模块内字符串常量
            # 可靠，HttpClient 大量先例）
            if host == null
            {
                host = "0.0.0.0"
            }

            if SystemStringLength( host ) == 0
            {
                host = "0.0.0.0"
            }
            _server = Net.Tcp.listenAddress( host, lport )
            _running = true
            # 主监听器入表（tag 恒 = 1；多监听器 v1.1）
            if _servers == null
            {
                _servers = new()
                _serverTags = new()
                _serverPorts = new()
            }
            _servers.add( _server )
            _serverTags.add( 1 )
            _serverPorts.add( lport )
            # accept 循环协程：闭包零捕获（NetConcurrentTest.ef 先例），
            # 状态全走静态字段
            Net.TcpServer srv = _server
            function f = function( object a )
            {
                HttpServerCore._acceptLoop( a as Net.TcpServer )
            }
            _acceptTask = Coroutine.spawnClosure1( f, srv )
            # 启动 listen() 在 start 前登记的扩展监听器（缓冲消费；tag 用
            # 登记期分配值——用户已持 ServerListener 句柄打 scope，不可换号）
            Int32 pn = _pendHosts.length
            for Int32 i = 0, i < pn, i = i + 1
            {
                string ph = _pendHosts[i]
                Int32 pp = _pendPorts[i]
                Int32 pt = _pendTags[i]
                HttpServerCore._bindListener( ph, pp, pt )
            }
            _pendHosts.clear()
            _pendPorts.clear()
            _pendTags.clear()
            # 插件生命周期钩子（start 后、accept 循环已在跑——单协程调度
            # 下无竞态；§6.9）
            _PluginHost.notifyStart()
            # app 级 onStart 钩子（P6，§4.9；Function 字段先拷局部再调用
            # ——HttpHeaders 头注记纪律；异常吞——不拖垮启动）
            function hStart = _hookOnStart
            if hStart != null
            {
                label hs
                {
                    hStart()
                }
                catch { }
            }
        }

        # ── 多监听器（v1.1）：同进程扩展端口挂载 ──

        # 登记扩展监听器（SLang.HttpServer.listen 转发）。主监听器 = 1
        # 固定，本 API 分配 2,3,... 并返回 tag；未 running 时入缓冲
        # （start() 统一 bind，tag 不变），running 中立即 bind。
        public static Int32 listen( string host, Int32 port ) throws
        {
            if port <= 0 || port > 65535
            {
                throw ServerError.InvalidConfig
            }

            # host 空值兜底（缓冲存值与 bind 取值同源）
            if host == null
            {
                host = "0.0.0.0"
            }

            if SystemStringLength( host ) == 0
            {
                host = "0.0.0.0"
            }

            if _running
            {
                Int32 rt = _nextTag
                _nextTag = _nextTag + 1
                HttpServerCore._bindListener( host, port, rt )
                ret rt
            }

            if _pendHosts == null
            {
                _pendHosts = new()
                _pendPorts = new()
                _pendTags = new()
            }
            Int32 tag = _nextTag
            _nextTag = _nextTag + 1
            _pendHosts.add( host )
            _pendPorts.add( port )
            _pendTags.add( tag )
            ret tag
        }

        # 立即绑定一个扩展监听器并启动其 accept 循环（running 中 listen /
        # start() 缓冲消费共用；tag 由调用方给定——缓冲登记期分配值不可换）
        static void _bindListener( string host, Int32 port, Int32 tag ) throws
        {
            Net.TcpServer srv = Net.Tcp.listenAddress( host, port )
            if _servers == null
            {
                _servers = new()
                _serverTags = new()
                _serverPorts = new()
            }
            _servers.add( srv )
            _serverTags.add( tag )
            _serverPorts.add( port )
            # accept 循环协程（闭包零捕获；主监听器同款）
            Net.TcpServer s = srv
            function f = function( object a )
            {
                HttpServerCore._acceptLoop( a as Net.TcpServer )
            }
            Coroutine.spawnClosure1( f, s )
        }

        # 监听器身份 → tag（列表身份扫描；未命中兜底 1 = 主监听器）
        static Int32 _tagOf( Net.TcpServer srv )
        {
            if _servers != null
            {
                Int32 n = _servers.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    object so = _servers[i]
                    if so == srv
                    {
                        Int32 t = _serverTags[i]
                        ret t
                    }
                }
            }
            ret 1
        }

        # 监听器身份 → port（_tagOf 同款扫描；未命中兜底配置端口）
        static Int32 _portOf( Net.TcpServer srv )
        {
            if _servers != null
            {
                Int32 n = _servers.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    object so = _servers[i]
                    if so == srv
                    {
                        Int32 p = _serverPorts[i]
                        ret p
                    }
                }
            }
            ret _listenPort
        }

        # 停止：关监听 + 关全部在途连接（各连接协程随读失败/EOF 退出）
        public static void stop() throws
        {
            if !_running
            {
                throw ServerError.NotRunning
            }
            _running = false
            # 关全部监听器（主 + 扩展；各 accept 循环随 close 抛错退出）
            if _servers != null
            {
                Int32 sn = _servers.length
                for Int32 i = 0, i < sn, i = i + 1
                {
                    object so = _servers[i]
                    Net.TcpServer s = so as Net.TcpServer
                    label closeSrv
                    {
                        s.close()
                    }
                    catch { }
                }
                _servers.clear()
                _serverTags.clear()
                _serverPorts.clear()
            }
            _nextTag = 2
            if _server != null
            {
                _server.close()
                _server = null
            }
            Int32 n = _conns.length
            for Int32 i = 0, i < n, i = i + 1
            {
                Net.TcpStream c = _conns[i] as Net.TcpStream
                label closeOne
                {
                    c.close()
                }
                catch { }
            }
            _conns.clear()
            # 插件生命周期钩子（stop 收尾；§6.9）
            _PluginHost.notifyStop()
            # app 级 onStop 钩子（P6，§4.9；异常吞——不拖垮停止收尾）
            function hStop = _hookOnStop
            if hStop != null
            {
                label hp
                {
                    hStop()
                }
                catch { }
            }
        }

        # 挂起直至停止（等待 accept 循环协程收尾）
        public static void awaitStop() throws
        {
            if _acceptTask == null
            {
                throw ServerError.NotRunning
            }
            Task t = _acceptTask
            Coroutine.awaitTask( t )
        }

        # ── 内部：accept 循环（独立协程；每连接再派发一协程）──

        static void _acceptLoop( Net.TcpServer srv )
        {
            # label 只包单轮 accept（label 块内挂起 = HttpClient parseBlock 先例）
            bool run = true
            while run
            {
                label accOne
                {
                    Net.TcpStream client = srv.accept()
                    # 并发连接上限（P3，§4.9）：超出 503 + 优雅断连
                    #（协议层应答，§6.11；不进管道不占连接协程）
                    ServerConfig mcCfg = _cfg
                    if mcCfg != null && mcCfg.maxConnections > 0 && _conns.length >= mcCfg.maxConnections
                    {
                        HttpServerCore._writeSimple( client, 503, HttpServerCore._errorBody( 503 ) )
                        HttpServerCore._gracefulClose( client )
                    }
                    else
                    {
                        # 连接处理闭包零捕获（NetConcurrentTest.ef 先例）：
                        # client + 监听器身份均经实参传值（多监听器 v1.1：
                        # spawnClosure2 二实参——tag/port 由 _tagOf/_portOf
                        # 身份扫描反查），状态全走静态字段
                        function f = function( object a, object b )
                        {
                            HttpServerCore._runConn( a as Net.TcpStream, b as Net.TcpServer )
                        }
                        Coroutine.spawnClosure2( f, client, srv )
                    }
                }
                catch
                {
                    # 监听已关闭（stop）或 accept 失败：退出循环
                    run = false
                }
            }
        }

        # 连接收尾：从连接表移除 + 尽力关闭（幂等）
        static void _cleanupConn( Net.TcpStream c )
        {
            Int32 n = _conns.length
            for Int32 i = 0, i < n, i = i + 1
            {
                if _conns[i] == c
                {
                    _conns.removeRange( i, 1 )
                    break
                }
            }
            label closeConn
            {
                c.close()
            }
            catch { }
        }

        # 连接处理入口（连接协程体）：异常兜底静默（对端异常断开 / 写失败等）。
        # srv = 接入连接的监听器（多监听器 v1.1：tag/port 由身份扫描反查）
        static void _runConn( Net.TcpStream c, Net.TcpServer srv )
        {
            _conns.add( c )
            label connBlock
            {
                HttpServerCore._handleConnection( c, srv )
            }
            catch
            {
            }
            HttpServerCore._cleanupConn( c )
        }

        # ── 内部：连接处理（每连接一协程；keep-alive 循环）──

        static void _handleConnection( Net.TcpStream client, Net.TcpServer srv )
        {
            ServerConfig cfg = _cfg
            client.setReadTimeout( cfg.keepAliveTimeoutMs )
            if cfg.writeTimeoutMs > 0
            {
                # 流式写挂起超时（§6.6 背压与超时）：慢客户端 send 挂起超时
                # 抛 NetError.Timeout → 写侧异常上抛 → 引擎断连路径
                client.setWriteTimeout( cfg.writeTimeoutMs )
            }
            # 本连接所在监听器 tag / 端口（连接生命周期不变；多监听器 v1.1
            # ——路由可见性按 tag 过滤，req.localPort 供 handler 分流）
            Int32 tag = HttpServerCore._tagOf( srv )
            Int32 lport = HttpServerCore._portOf( srv )
            ByteBuffer buf = ByteBuffer()
            while true
            {
                # ---- 1) 解析请求（EOF / 空闲超时 / IO 异常 → 静默收连接）----
                # P5 §6.6：先只解析头（stopAtHead）——路由命中 streamBody
                # 即移交 handler 流式消费；未命中再原地补读 body（第二遍
                # _parse 全量形态，语义与 v1 完全一致）。预读缓冲共享，
                # 头区字节已在 buf 中消费，补读从残留/连接继续，零重复
                _HttpParseResult r = null
                bool failed = false
                label parseBlock
                {
                    Net.NetStream ns = client
                    r = HttpServerCore._parse( ns, buf, cfg, true )
                }
                catch
                {
                    failed = true
                }
                if failed
                {
                    break
                }

                if r == null
                {
                    break
                }

                if r._errorCode != 0
                {
                    # 协议层错误：应答后优雅断连（431/413/400）。
                    # 直接 close 在未读完入站 body 时会触发 RST，客户端读不到
                    # 响应——先停发（FIN）→ 短暂让出（客户端收响应）→ 丢弃式
                    # 收尾读 → close（_gracefulClose）
                    HttpServerCore._writeSimple( client, r._errorCode, HttpServerCore._errorBody( r._errorCode ) )
                    if r._body != null
                    {
                        r._body.release()
                    }
                    HttpServerCore._gracefulClose( client )
                    break
                }

                # ---- 1a) streamBody 路由判定（P5，§6.6）----
                # 命中 streamBody=true 的 HTTP 路由：跳过 body 预读，连接 +
                # 预读残留经 Request._bindStream 移交 handler；未命中（含
                # 404/405/WS）走第二遍全量解析补 body（见 1b）
                RouteInfo preRoute = Router.match( r._method, r._path, tag )
                if preRoute != null && preRoute.streamBody && HttpServerCore._isWsUpgrade( r ) == false
                {
                    r._body = null
                }
                else
                {
                    # ---- 1b) 非 streamBody：补读 body（全量解析第二遍，头区
                    # 已消费的部分由 _parse 重走——重复解析头但零额外 IO，
                    # 简化实现路径；buf 索引已在头区后，重解析从残留起）----
                    label parseFull
                    {
                        Net.NetStream ns2 = client
                        # 重置：重新构造完整解析结果（头区信息被第二遍重建）
                        r = HttpServerCore._parseHeadless( ns2, buf, cfg, r )
                    }
                    catch
                    {
                        failed = true
                    }
                    if failed || r == null || r._errorCode != 0
                    {
                        if r != null && r._errorCode != 0
                        {
                            HttpServerCore._writeSimple( client, r._errorCode, HttpServerCore._errorBody( r._errorCode ) )
                            if r._body != null
                            {
                                r._body.release()
                            }
                            HttpServerCore._gracefulClose( client )
                        }
                        break
                    }
                }

                # ---- 2) WS Upgrade 分流（§6.1：升级在路由/中间件管道之前）----
                # Upgrade: websocket + Connection 含 upgrade 且命中 WS 路由 →
                # 三参 accept（buf 预读残留直传，残留帧不丢失）→ 会话协程；
                # 未命中 WS 路由 → 400；握手失败 → 400。该连接退出 keep-alive 循环
                if HttpServerCore._isWsUpgrade( r )
                {
                    RouteInfo wsRoute = Router.findWs( r._path, tag )
                    if wsRoute == null
                    {
                        HttpServerCore._writeSimple( client, 400, HttpServerCore._errorBody( 400 ) )
                        if r._body != null
                        {
                            r._body.release()
                        }
                        HttpServerCore._gracefulClose( client )
                        break
                    }
                    HttpServerCore._runWsSession( client, wsRoute, r, buf )
                    # 会话结束 = 连接终结
                    break
                }

                # ---- 3) 路由匹配（HEAD 视同 GET；§6.2）----
                bool isHead = Net.Uri.eqFold( r._method, "HEAD" )
                bool keepAlive = HttpServerCore._wantKeepAlive( r )
                RouteInfo route = Router.match( r._method, r._path, tag )
                # 未命中判定（404 / 405）不再提前应答——统一经中间件管道
                # 尾环处理（P2：staticFiles / CORS 预检依赖未匹配请求同样
                # 过管道，§6.9）
                Int32 noRoute = 0
                if route == null
                {
                    RouteInfo pathHit = Router.findBest( r._path, tag )
                    if pathHit == null
                    {
                        noRoute = 404
                    }
                    else
                    {
                        noRoute = 405
                    }
                }

                # ---- 4) 构造上下文（SERVER_DESIGN.md §6.1）----
                Map<string,string> pathParams = Router.extractParams( route, r._path )
                Request req = Request( r._method, r._path, r._rawQuery, r._headers, r._body, client.remoteAddress, client.remotePort, pathParams )
                # 本请求进入的监听端口（多监听器 v1.1；构造签名不动，构造后赋值）
                req.localPort = lport
                # 请求侧流式绑定（P5，§6.6）：streamBody 路由把连接 + 预读
                # 残留移交 handler（bodyStream() 消费；收尾 drain 见 6a）
                if preRoute != null && preRoute.streamBody && req._body == null
                {
                    req._bindStream( client, buf, r._streamCl, r._streamChunked )
                }
                r._headers = null
                r._body = null
                Response res = Response()
                # 流式直写通道绑定（stream/sse/sendFile；§6.6）
                res._bind( client, keepAlive, r._http10 )

                # ---- 4a) multipart 即时解析（P1.5，§6.5 构造期语义）----
                # 单文件超 maxFileBytes → 413；boundary 缺失/格式坏 → 400；
                # 均协议层应答 + 优雅断连（§6.11，防 RST 同 413/431 路径）
                # P7：流式路由（streamBody）不做内存预解析——body 不驻留，
                # form()/file() 族不适用（multipartStream() 为其流式替代），
                # CT 有效性（boundary 缺失等）交 handler 经 multipartStream()
                # 返 null 自行裁决；引擎收尾由 6a 以流语义兜底排干
                if req.isStreamBody == false && req.bodyFormat == EBodyFormat.Multipart
                {
                    Int32 upErr = req._ensureMultipart()
                    if upErr != 0
                    {
                        HttpServerCore._writeSimple( client, upErr, HttpServerCore._errorBody( upErr ) )
                        HttpServerCore._releaseRequest( req )
                        if res._body != null
                        {
                            res._body.release()
                        }
                        HttpServerCore._gracefulClose( client )
                        break
                    }
                }

                # ---- 5) 管道执行（P2，§6.9：连接协程内联——中间件可 await，
                # onion 后置环在 handler 协程完成后自然回程；无中间件直通尾环）----
                bool pipeError = false
                bool connKilled = false
                label pipeBlock
                {
                    connKilled = HttpServerCore._runPipeline( client, cfg, route, noRoute, req, res, isHead, tag )
                }
                catch e
                {
                    pipeError = true
                    # app 级 onError 钩子（P6，§4.9）：管道/中间件/handler
                    # 异常先交钩子（钩子内可写响应自救——isResponded 后按
                    # 其响应写出）；未注册/未写响应则走下方既有 500 兜底
                    # 分支不变。
                    # e 经 catch 兜底块绑定直传（WebSocketClient._runLoop
                    # 同款形态——Error 不作静态方法形参类型）
                    function hErr = _hookOnError
                    if hErr != null
                    {
                        label hoc
                        {
                            hErr( req, res, e )
                        }
                        catch { }
                    }
                }

                # ---- 6) 响应写出（流式三态 + 缓冲，§6.6）----
                bool closeConn = false
                if pipeError
                {
                    if res.isStreaming
                    {
                        # 头已直发无法改 500：兜底终止块 + 断连
                        res._streamWriter._ensureClosed()
                        closeConn = true
                    }
                    elif res._direct
                    {
                        # sendFile 直写半截：断连
                        closeConn = true
                    }
                    elif res.isResponded
                    {
                        # 响应已缓冲完成：照常写出（首个响应胜出，P1 复盘 ⑧）
                        HttpServerCore._writeResponse( client, res, keepAlive, isHead )
                    }
                    else
                    {
                        # 管道/中间件/handler 异常未响应：500 + 断连
                        HttpServerCore._writeSimple( client, 500, HttpServerCore._errorBody( 500 ) )
                        closeConn = true
                    }
                }
                elif res.isStreaming
                {
                    # chunked 流式：兜底 close（handler 正常退出未调 close()；
                    # 幂等）——HTTP/1.0 close-delimited 发完即断
                    res._streamWriter._ensureClosed()
                    if res._http10
                    {
                        closeConn = true
                    }
                }
                elif res._direct
                {
                    # sendFile 全量直写完成（Content-Length 精确）→ keep-alive 继续
                }
                elif !res.isResponded
                {
                    # 管道正常返回但未写任何响应（契约违约）：500 + 断连
                    HttpServerCore._writeSimple( client, 500, HttpServerCore._errorBody( 500 ) )
                    closeConn = true
                }
                else
                {
                    HttpServerCore._writeResponse( client, res, keepAlive, isHead )
                }

                if connKilled
                {
                    # 尾环超时路径已自行收尾（504 应答 + 资源回收 + 断连）
                    break
                }

                # 请求级资源回收（body + multipart 文件内容缓冲，§6.5）
                HttpServerCore._releaseRequest( req )
                if res._body != null
                {
                    res._body.release()
                }

                # ---- 6a) 流式 body 收尾（P5 §6.6；P7 修正）----
                # handler 未消费完整（isStreamBody 且读取器未到 EOF）且
                # 连接拟 keep-alive 续用 → 丢弃式排干剩余 body（防下一条
                # 请求解析错位）；排干失败/超限 → 断连止损。排干量计入
                # 上限（复用读取器限额语义，防恶意滞留字节流拖垮连接）。
                # P7 修正一：读取器经 req.bodyStream() 缓存单实例——引擎
                # 与 handler 共享消费进度（修复此前每次新造实例按完整 CL
                # 起算导致的多吃错位）。P7 修正二：handler 已建 multipart
                # 解析器时先经 _drainTail 以 multipart 语义排干剩余结构
                # （_win 预读窗口残留由解析器闭环，防底层 drainer 按 CL
                # 余量排干时跳过 _win 数据错吃下一请求字节）
                if req.isStreamBody && keepAlive && closeConn == false
                {
                    bool drainOk = true
                    MultipartReader mpDrain = req._mpReader
                    if mpDrain != null
                    {
                        label mpDrainBlock
                        {
                            mpDrain._drainTail()
                        }
                        catch
                        {
                            drainOk = false
                        }
                    }

                    if drainOk
                    {
                        HttpBodyReader drainer = req.bodyStream()
                        label drainBlock
                        {
                            ByteBuffer drain = ByteBuffer( 65536 )
                            while true
                            {
                                Int32 n = drainer.read( drain )
                                if n <= 0
                                {
                                    break
                                }
                                drain.clear()
                            }
                            drain.release()
                        }
                        catch
                        {
                            drainOk = false
                        }
                        if drainOk && drainer.isDone == false
                        {
                            drainOk = false
                        }
                    }

                    if drainOk == false
                    {
                        # 排干失败（截断/超限/multipart 结构残缺）：断连止损
                        HttpServerCore._gracefulClose( client )
                        break
                    }
                }

                if closeConn || !keepAlive
                {
                    if closeConn
                    {
                        # 500 断连路径同走优雅收尾（防 RST）
                        HttpServerCore._gracefulClose( client )
                    }
                    break
                }
            }
            label bufRelease
            {
                buf.release()
            }
            catch { }
        }

        # ── 管道与尾环（P2，§6.9 / §6.1）──

        # 管道入口：无任何中间件（全局 + 路由级）直通尾环；有则 _Pipeline
        # 逐环（Next.go 链）。P10：路由级中间件参与判定——仅全局为空但
        # 路由级非空同样走 _Pipeline。
        # 返回 true = 尾环已自行断连收尾（handler 超时路径，调用方 break）
        static bool _runPipeline( Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead, Int32 tag ) throws
        {
            Int32 routeMw = 0
            if route != null
            {
                routeMw = route._mwCount()
            }

            if _PluginHost.middlewareCount() == 0 && routeMw == 0
            {
                ret HttpServerCore._tail( client, cfg, route, noRoute, req, res, isHead, tag )
            }
            _Pipeline pipe = _Pipeline( client, cfg, route, noRoute, req, res, isHead, tag )
            ret pipe._run()
        }

        # 尾环：handler 协程派发（§6.1）或 404/405 应答（经中间件后的终点；
        # res 终端写出由调用方统一处理）。
        # 返回 true = 超时路径已断连收尾（调用方 break）
        static bool _tail( Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead, Int32 tag ) throws
        {
            if route == null
            {
                if noRoute == 405
                {
                    # 路径命中但动词不符：405 + Allow（Allow 头列出可用动词）
                    res.status( 405 ).header( "Allow", Router.allowMethods( req.path, tag ) ).rawJson( HttpServerCore._errorBody( 405 ) )
                }
                else
                {
                    res.status( 404 ).rawJson( HttpServerCore._errorBody( 404 ) )
                }
                ret false
            }

            # handler 协程派发（SERVER_DESIGN.md §6.1）
            # Function 字段先拷局部再传参（HttpHeaders 头注记纪律）
            function h = route.handler
            if h == null
            {
                # 防御（P4）：预装载路由条目 handler 实例化失败
                #（SystemServerRouteHandler miss -> null 经 usePreloadRoutes
                # 已过滤，此处兜底动态注册的 null handler）→ 500
                res.status( 500 ).rawJson( HttpServerCore._errorBody( 500 ) )
                ret false
            }
            Task task = Coroutine.spawnClosure2( h, req, res )

            bool timedOut = false
            if cfg.handlerTimeoutMs > 0
            {
                timedOut = !Coroutine.waitTimeout( task, cfg.handlerTimeoutMs )
            }

            if timedOut
            {
                if res.isStreaming
                {
                    # 流式豁免（§6.1）：SSE/大文件长推送不受 handlerTimeoutMs
                    # 误杀——转无限等待；写侧由连接级 writeTimeoutMs 守护
                    # （慢客户端 send 超时 → handler 协程异常上抛 → 引擎断连）
                    Coroutine.awaitTask( task )
                    ret false
                }
                # 超时：协作式取消 + 优雅断连（杜绝未死协程的后续读写竞态；
                # 直接 close 会 RST 致客户端读不到 504 —— _gracefulClose）
                task.cancel()
                if res.isResponded
                {
                    # 已缓冲完成的响应照常写出（非流式单缓冲无半截风险）
                    HttpServerCore._writeResponse( client, res, false, isHead )
                }
                else
                {
                    HttpServerCore._writeSimple( client, 504, HttpServerCore._errorBody( 504 ) )
                }
                HttpServerCore._releaseRequest( req )
                if res._body != null
                {
                    res._body.release()
                }
                HttpServerCore._gracefulClose( client )
                ret true
            }

            Coroutine.awaitTask( task )
            ret false
        }

        # 优雅断连：停发（closeWrite = shutdown Write，NetCloseTest F1 先例）
        # → 让出 50ms（客户端收响应）→ 丢弃式收尾读（消费对端残余 body，
        # 防未读缓冲触发 RST）→ close。协程内 delay 挂起不阻塞调度；
        # 收尾读窗口 500ms，超时静默放弃
        static void _gracefulClose( Net.TcpStream client )
        {
            label shut
            {
                client.closeWrite()
            }
            catch { }
            Coroutine.delay( 50 )
            client.setReadTimeout( 500 )
            ByteBuffer drain = ByteBuffer( 4096 )
            while true
            {
                Int32 n = 0
                label drainRead
                {
                    n = client.read( drain )
                }
                catch
                {
                    break
                }
                if n <= 0
                {
                    break
                }
                drain.clear()
            }
            drain.release()
            client.setReadTimeout( 0 )
        }

        # 单文件上传上限（P1.5；Request 惰性 multipart 解析用；
        # 未配置时按 ServerConfig 默认 50MB）
        static Int32 _uploadFileLimit()
        {
            if _cfg == null
            {
                ret 52428800
            }
            ret _cfg.maxFileBytes
        }

        # 请求级资源回收：body 缓冲 + multipart 文件内容缓冲
        # （UploadedFile._data，§6.5 请求结束统一回收；幂等）
        static void _releaseRequest( Request req )
        {
            if req._body != null
            {
                req._body.release()
            }

            if req._mpFiles != null
            {
                Int32 n = req._mpFiles.length
                for Int32 i = 0, i < n, i = i + 1
                {
                    UploadedFile f = req._mpFiles[i]
                    f._release()
                }
            }
        }

        # ── WebSocket Upgrade 分流（§6.1 / §6.8）──

        # 升级请求判定：Upgrade 头含 websocket（大小写不敏感）
        static bool _isWsUpgrade( _HttpParseResult r )
        {
            string up = r._headers.getHeader( "Upgrade" )
            if up == null
            {
                ret false
            }
            ret HttpServerCore._containsFold( up, "websocket" )
        }

        # WS 会话：三参 accept（预读残留直传，残留帧不丢失）→ WsSession →
        # 会话回调（单参 Function(session)）→ 收尾注销注册表。
        # 握手失败 → 400；本方法返回 = 连接终结（由调用方 break）
        static void _runWsSession( Net.TcpStream client, RouteInfo wsRoute, _HttpParseResult r, ByteBuffer buf )
        {
            Net.WebSocketStream ws = null
            label hsBlock
            {
                # HTTP 解析已消费请求行+头（readerIndex 前进，原始字节不再
                # 可读）——accept 的握手重读必须喂一份重建的最小请求。用已
                # 解析值重组：请求行 + 四个 WS 关键头 + 空行，灌入 preRead
                # 缓冲（_acceptHandshake 从预读区取行，与 socket 残留同路）。
                string hs = "GET " + r._path
                if SystemStringLength( r._rawQuery ) > 0
                {
                    hs = hs + "?" + r._rawQuery
                }
                hs = hs + " HTTP/1.1\r\n"
                string wk = r._headers.getHeader( "Sec-WebSocket-Key" )
                string wv = r._headers.getHeader( "Sec-WebSocket-Version" )
                if wk == null || wv == null
                {
                    # 关键升级头缺失：与握手失败同路（400 + 断连；本方法未
                    # 声明 throws，不走 throw）
                    HttpServerCore._writeSimple( client, 400, HttpServerCore._errorBody( 400 ) )
                    HttpServerCore._gracefulClose( client )
                    ret
                }
                hs = hs + "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: " + wv + "\r\nSec-WebSocket-Key: " + wk + "\r\n\r\n"
                ByteBuffer pre = ByteBuffer.fromString( hs )
                ws = Net.WebSocketStream.accept( client, pre, null )
                pre.release()
            }
            catch
            {
                # 握手失败（非升级请求形态 / 头缺失）：400 后断连
                HttpServerCore._writeSimple( client, 400, HttpServerCore._errorBody( 400 ) )
                HttpServerCore._gracefulClose( client )
                ret
            }
            Map<string,string> pathParams = Router.extractParams( wsRoute, r._path )
            WsSession s = WsSession( ws, wsRoute.pattern, pathParams, r._rawQuery )
            _WsSessions.register( wsRoute.pattern, s )
            # 空闲心跳看门狗（P5，§6.8：wsIdleTimeoutMs > 0 时启动；
            # 空闲超时 close 会话 → handler receive 返回 null 自然收尾）
            ServerConfig hbCfg = _cfg
            if hbCfg != null && hbCfg.wsIdleTimeoutMs > 0
            {
                s._startHeartbeat( hbCfg.wsIdleTimeoutMs )
            }
            # 插件 WS 会话钩子（对所有插件广播，§6.9）
            _PluginHost.notifyWsOpen( s )
            # Function 字段先拷局部（HttpHeaders 头注记纪律）
            function h = wsRoute.handler
            label sessBlock
            {
                # 会话回调（单参；handler 内循环 s.receive()，null = 关闭）
                h( s )
            }
            catch
            {
                # 会话异常：静默收尾（不影响其他会话，§6.11）
            }
            _WsSessions.unregister( wsRoute.pattern, s )
            # 插件 WS 会话钩子（注销后广播，§6.8 收尾序）
            _PluginHost.notifyWsClose( s )
            ws.close()
        }

        # keep-alive 判定：Connection 头显式优先，否则 HTTP/1.1 默认开
        static bool _wantKeepAlive( _HttpParseResult r )
        {
            string conn = r._headers.getHeader( "Connection" )
            if conn != null
            {
                if HttpServerCore._containsFold( conn, "close" )
                {
                    ret false
                }

                if HttpServerCore._containsFold( conn, "keep-alive" )
                {
                    ret true
                }
            }
            ret r._http10 == false
        }

        # ── 响应编码 ──

        # 响应写出（Content-Length 恒精确；HEAD 不写 body；写毕由调用方回收 body）
        static void _writeResponse( Net.TcpStream client, Response res, bool keepAlive, bool isHead ) throws
        {
            Int32 status = res._status
            string head = "HTTP/1.1 " + status.toString() + " " + HttpServerCore._reason( status ) + "\r\n"
            head = head + "Content-Type: " + res._contentType + "\r\n"
            Int32 bodyLen = 0
            if res._body != null
            {
                bodyLen = res._body.readableBytes
            }
            head = head + "Content-Length: " + bodyLen.toString() + "\r\n"
            if keepAlive
            {
                head = head + "Connection: keep-alive\r\n"
            }
            else
            {
                head = head + "Connection: close\r\n"
            }
            Int32 n = res._headers.count
            for Int32 i = 0, i < n, i = i + 1
            {
                string hn = res._headers.nameAt( i )
                # 引擎管理头跳过（Content-Type/Length/Connection 由上方生成；
                # 自定义 Content-Type 请走 Response.contentType）
                if Net.Uri.eqFold( hn, "Content-Type" ) || Net.Uri.eqFold( hn, "Content-Length" ) || Net.Uri.eqFold( hn, "Connection" )
                {
                    continue
                }
                head = head + hn + ": " + res._headers.valueAt( i ) + "\r\n"
            }
            # Set-Cookie 逐条独立成行（P10：Set-Cookie 多行重复语义，
            # 不走 HttpHeaders 覆盖；res.setCookie 暂存）
            List<string> resCookies = res._cookies
            if resCookies != null
            {
                Int32 cn = resCookies.length
                for Int32 i = 0, i < cn, i = i + 1
                {
                    head = head + "Set-Cookie: " + resCookies[i] + "\r\n"
                }
            }
            head = head + "\r\n"
            client.write( ByteBuffer.fromString( head ) )
            if !isHead && bodyLen > 0
            {
                client.write( res._body )
            }
        }

        # 简单 JSON 错误响应（尽力写出，失败静默；恒 Connection: close）
        static void _writeSimple( Net.TcpStream client, Int32 status, string jsonBody )
        {
            HttpServerCore._writeSimple( client, status, jsonBody, "", "" )
        }

        # 带单附加头变体（如 405 的 Allow）
        static void _writeSimple( Net.TcpStream client, Int32 status, string jsonBody, string extraName, string extraValue )
        {
            label wBlock
            {
                string head = "HTTP/1.1 " + status.toString() + " " + HttpServerCore._reason( status ) + "\r\n"
                head = head + "Content-Type: application/json; charset=utf-8\r\n"
                Int32 bodyLen = SystemStringLength( jsonBody )
                head = head + "Content-Length: " + bodyLen.toString() + "\r\n"
                head = head + "Connection: close\r\n"
                if SystemStringLength( extraName ) > 0
                {
                    head = head + extraName + ": " + extraValue + "\r\n"
                }
                head = head + "\r\n"
                client.write( ByteBuffer.fromString( head + jsonBody ) )
            }
            catch { }
        }

        # ApiResult 形态错误体（键序 code → message → data；data 是关键字，
        # 框架手工组包，SERVER_DESIGN.md §6.7；ApiResult 类随 P1 落地）
        static string _errorBody( Int32 code )
        {
            string msg = "bad request"
            if code == 404
            {
                msg = "not found"
            }
            elif code == 405
            {
                msg = "method not allowed"
            }
            elif code == 413
            {
                msg = "payload too large"
            }
            elif code == 431
            {
                msg = "request header fields too large"
            }
            elif code == 500
            {
                msg = "internal error"
            }
            elif code == 504
            {
                msg = "handler timeout"
            }
            elif code == 503
            {
                msg = "service unavailable"
            }
            ret "{\"code\":" + code.toString() + ",\"message\":\"" + msg + "\",\"data\":null}"
        }

        # 状态码 reason（SERVER_DESIGN.md 附录 A 常用子集；未知码空串）
        static string _reason( Int32 code )
        {
            if code == 200
            {
                ret "OK"
            }

            if code == 201
            {
                ret "Created"
            }

            if code == 204
            {
                ret "No Content"
            }

            if code == 301
            {
                ret "Moved Permanently"
            }

            if code == 302
            {
                ret "Found"
            }

            if code == 304
            {
                ret "Not Modified"
            }

            if code == 400
            {
                ret "Bad Request"
            }

            if code == 401
            {
                ret "Unauthorized"
            }

            if code == 403
            {
                ret "Forbidden"
            }

            if code == 404
            {
                ret "Not Found"
            }

            if code == 405
            {
                ret "Method Not Allowed"
            }

            if code == 409
            {
                ret "Conflict"
            }

            if code == 413
            {
                ret "Payload Too Large"
            }

            if code == 415
            {
                ret "Unsupported Media Type"
            }

            if code == 416
            {
                ret "Range Not Satisfiable"
            }

            if code == 429
            {
                ret "Too Many Requests"
            }

            if code == 431
            {
                ret "Request Header Fields Too Large"
            }

            if code == 500
            {
                ret "Internal Server Error"
            }

            if code == 501
            {
                ret "Not Implemented"
            }

            if code == 503
            {
                ret "Service Unavailable"
            }

            if code == 504
            {
                ret "Gateway Timeout"
            }
            ret ""
        }

        # ── 请求解析（预读缓冲模式；HttpClient 响应解析的对称实现）──

        # 解析一条完整请求；对端干净关闭（EOF）返回 null；协议错误经
        # _errorCode 带出；读超时 / IO 异常原样上抛（连接层收尾）。
        # stopAtHead = true（P5 §6.6 请求侧流式）：解析到头区空行即停，
        # 不预读 body——body 元信息（Content-Length / chunked）存入
        # _streamCl/_streamChunked，连接 + 预读残留由调用方移交 handler
        static _HttpParseResult _parse( Net.NetStream s, ByteBuffer buf, ServerConfig cfg, bool stopAtHead ) throws
        {
            _HttpParseResult result = _HttpParseResult()

            # ---- 请求行：METHOD SP target SP version ----
            string line = HttpServerCore._readLine( s, buf )
            if line == null
            {
                ret null
            }
            line = HttpServerCore._stripEol( line )
            Int32 llen = SystemStringLength( line )
            if llen == 0
            {
                result._errorCode = 400
                ret result
            }
            Int32 sp1 = -1
            for Int32 i = 0, i < llen, i = i + 1
            {
                if SystemStringCharCodeAt( line, i ) == 32
                {
                    sp1 = i
                    break
                }
            }
            if sp1 <= 0
            {
                result._errorCode = 400
                ret result
            }
            Int32 sp2 = -1
            for Int32 i = sp1 + 1, i < llen, i = i + 1
            {
                if SystemStringCharCodeAt( line, i ) == 32
                {
                    sp2 = i
                    break
                }
            }
            if sp2 < 0 || sp2 == sp1 + 1
            {
                result._errorCode = 400
                ret result
            }
            result._method = SystemStringRange( line, 0, sp1 )
            string target = SystemStringRange( line, sp1 + 1, sp2 )
            string version = SystemStringRange( line, sp2 + 1, llen )
            if !HttpServerCore._startsWithFold( version, "HTTP/" )
            {
                result._errorCode = 400
                ret result
            }
            result._http10 = HttpServerCore._eqExact( version, "HTTP/1.0" )

            # ---- target 拆 path ? query ----
            Int32 tlen = SystemStringLength( target )
            if tlen == 0 || SystemStringCharCodeAt( target, 0 ) != 47
            {
                result._errorCode = 400
                ret result
            }
            Int32 qpos = -1
            for Int32 i = 0, i < tlen, i = i + 1
            {
                if SystemStringCharCodeAt( target, i ) == 63
                {
                    qpos = i
                    break
                }
            }
            if qpos >= 0
            {
                result._path = SystemStringRange( target, 0, qpos )
                result._rawQuery = SystemStringRange( target, qpos + 1, tlen )
            }
            else
            {
                result._path = target
                result._rawQuery = ""
            }

            # ---- 头循环（空行截止；行数 / 总字节双上限）----
            Net.HttpHeaders headers = Net.HttpHeaders()
            result._headers = headers
            Int32 headerBytes = llen
            Int32 headerCount = 0
            while true
            {
                string h = HttpServerCore._readLine( s, buf )
                if h == null
                {
                    result._errorCode = 400
                    ret result
                }
                h = HttpServerCore._stripEol( h )
                Int32 hl = SystemStringLength( h )
                if hl == 0
                {
                    break
                }
                headerCount = headerCount + 1
                headerBytes = headerBytes + hl
                if headerCount > 100 || headerBytes > cfg.maxHeaderBytes
                {
                    result._errorCode = 431
                    ret result
                }
                Int32 ci = -1
                for Int32 k = 0, k < hl, k = k + 1
                {
                    if SystemStringCharCodeAt( h, k ) == 58
                    {
                        ci = k
                        break
                    }
                }
                if ci <= 0
                {
                    result._errorCode = 400
                    ret result
                }
                Int32 vs = ci + 1
                while vs < hl && SystemStringCharCodeAt( h, vs ) == 32
                {
                    vs = vs + 1
                }
                headers.add( SystemStringRange( h, 0, ci ), SystemStringRange( h, vs, hl ) )
            }

            # ---- body 三态（chunked / Content-Length / 无）----
            # body 上限分流（P1.5，§6.4 第 5 步）：multipart 请求用
            # maxUploadBytes（multipart 请求总量上限），其余 maxBodyBytes
            Int32 bodyLimit = cfg.maxBodyBytes
            string ctHead = headers.getHeader( "Content-Type" )
            if ctHead != null
            {
                if BodyParser.isMultipart( ctHead )
                {
                    bodyLimit = cfg.maxUploadBytes
                }
            }
            string te = headers.getHeader( "Transfer-Encoding" )
            bool chunked = false
            if te != null
            {
                chunked = HttpServerCore._containsFold( te, "chunked" )
            }

            if stopAtHead
            {
                # P5 请求侧流式：头区即止——元信息带出，body 由 handler
                # 经 req.bodyStream() 消费（超大上传不驻留内存，§6.6）
                result._streamChunked = chunked
                result._streamCl = 0
                if chunked == false
                {
                    string cls2 = headers.getHeader( "Content-Length" )
                    if cls2 != null
                    {
                        Int64 cl2 = HttpServerCore._parseDec64( cls2 )
                        if cl2 >= 0
                        {
                            result._streamCl = cl2
                        }
                    }
                }
                ret result
            }

            if chunked
            {
                ByteBuffer body = ByteBuffer()
                Int32 ec = HttpServerCore._readChunked( s, buf, body, bodyLimit )
                if ec != 0
                {
                    body.release()
                    result._errorCode = ec
                    ret result
                }
                result._body = body
            }
            else
            {
                string cls = headers.getHeader( "Content-Length" )
                if cls != null
                {
                    Int64 cl = HttpServerCore._parseDec64( cls )
                    if cl < 0 || cl > 2000000000
                    {
                        result._errorCode = 400
                        ret result
                    }

                    if cl > bodyLimit
                    {
                        result._errorCode = 413
                        ret result
                    }

                    if cl > 0
                    {
                        Int32 need = cl.toInt32()
                        ByteBuffer body = ByteBuffer()
                        body.ensureWritable( need )
                        Int32 ec = HttpServerCore._readBytesChecked( s, buf, body, need )
                        if ec != 0
                        {
                            body.release()
                            result._errorCode = ec
                            ret result
                        }
                        result._body = body
                    }
                }
                # 无 CL 无 chunked：body 为空（keep-alive 下不可读 EOF）
            }
            ret result
        }

        # 补读 body（P5，§6.6）：stopAtHead 形态解析过头的请求，命中非
        # streamBody 路由时经此把 body 按三态读全（头区已消费，直接从
        # buf 残留/连接续读）。r 的头信息保留，仅填 _body / _errorCode
        static _HttpParseResult _parseHeadless( Net.NetStream s, ByteBuffer buf, ServerConfig cfg, _HttpParseResult r ) throws
        {
            Int32 bodyLimit = cfg.maxBodyBytes
            string ctHead = r._headers.getHeader( "Content-Type" )
            if ctHead != null
            {
                if BodyParser.isMultipart( ctHead )
                {
                    bodyLimit = cfg.maxUploadBytes
                }
            }
            string te = r._headers.getHeader( "Transfer-Encoding" )
            bool chunked = false
            if te != null
            {
                chunked = HttpServerCore._containsFold( te, "chunked" )
            }

            if chunked
            {
                ByteBuffer body = ByteBuffer()
                Int32 ec = HttpServerCore._readChunked( s, buf, body, bodyLimit )
                if ec != 0
                {
                    body.release()
                    r._errorCode = ec
                    ret r
                }
                r._body = body
                ret r
            }
            string cls = r._headers.getHeader( "Content-Length" )
            if cls != null
            {
                Int64 cl = HttpServerCore._parseDec64( cls )
                if cl < 0 || cl > 2000000000
                {
                    r._errorCode = 400
                    ret r
                }

                if cl > bodyLimit
                {
                    r._errorCode = 413
                    ret r
                }

                if cl > 0
                {
                    Int32 need = cl.toInt32()
                    ByteBuffer body = ByteBuffer()
                    body.ensureWritable( need )
                    Int32 ec = HttpServerCore._readBytesChecked( s, buf, body, need )
                    if ec != 0
                    {
                        body.release()
                        r._errorCode = ec
                        ret r
                    }
                    r._body = body
                }
            }
            ret r
        }

        # chunked 请求 body 聚合（hex size 行 -> 块 -> CRLF；0 终止 + trailer 空行）
        # 返回 0 = OK；400 = 协议错误 / EOF 截断；413 = 累计超限
        static Int32 _readChunked( Net.NetStream s, ByteBuffer buf, ByteBuffer dst, Int32 maxBytes ) throws
        {
            Int32 total = 0
            while true
            {
                string line = HttpServerCore._readLine( s, buf )
                if line == null
                {
                    ret 400
                }
                line = HttpServerCore._stripEol( line )
                Int32 size = HttpServerCore._chunkSize( line )
                if size < 0
                {
                    ret 400
                }

                if size == 0
                {
                    # trailer 头直到空行
                    while true
                    {
                        string t = HttpServerCore._readLine( s, buf )
                        if t == null
                        {
                            ret 400
                        }

                        if SystemStringLength( HttpServerCore._stripEol( t ) ) == 0
                        {
                            break
                        }
                    }
                    ret 0
                }
                total = total + size
                if total > maxBytes
                {
                    ret 413
                }
                dst.ensureWritable( size )
                Int32 ec = HttpServerCore._readBytesChecked( s, buf, dst, size )
                if ec != 0
                {
                    ret ec
                }
                # 块尾 CRLF
                ByteBuffer crlf = ByteBuffer()
                Int32 ec2 = HttpServerCore._readBytesChecked( s, buf, crlf, 2 )
                crlf.release()
                if ec2 != 0
                {
                    ret ec2
                }
            }
            ret 0
        }

        # 精确读 need 字节入 dst（先消费 buf 预读，不足再从流拉）；
        # EOF 截断返回 400（读超时 / IO 异常原样上抛）
        static Int32 _readBytesChecked( Net.NetStream s, ByteBuffer buf, ByteBuffer dst, Int32 need ) throws
        {
            while need > 0
            {
                if buf.readableBytes > 0
                {
                    Int32 take = buf.readableBytes
                    if take > need
                    {
                        take = need
                    }
                    buf.readBytes( dst, take )
                    need = need - take
                }
                else
                {
                    if buf.writableBytes < 4096
                    {
                        buf.discardReadBytes()
                        buf.ensureWritable( 4096 )
                    }
                    Int32 n = s.read( buf )
                    if n == 0
                    {
                        ret 400
                    }
                }
            }
            ret 0
        }

        # ── 文本 / 解析辅助（HttpClient 同款；Std 侧为模块内私有不便跨模块复用）──

        # 读一行（含 '\n'）：buf 有行直接取，否则从流拉；EOF 无行返回 null。
        # 单行上限 64KB（防无换行恶意行撑爆内存；头区另有 maxHeaderBytes 判定）
        static string _readLine( Net.NetStream s, ByteBuffer buf ) throws
        {
            string line = buf.readLine()
            while line == null
            {
                if buf.writableBytes < 4096
                {
                    buf.discardReadBytes()
                    buf.ensureWritable( 4096 )
                }
                Int32 n = s.read( buf )
                if n == 0
                {
                    ret null
                }

                if buf.readableBytes > 65536
                {
                    throw Net.HttpError.Protocol
                }
                line = buf.readLine()
            }
            ret line
        }

        # 去行尾 CRLF / LF
        static string _stripEol( string line )
        {
            Int32 len = SystemStringLength( line )
            if len > 0 && SystemStringCharCodeAt( line, len - 1 ) == 10
            {
                len = len - 1
            }

            if len > 0 && SystemStringCharCodeAt( line, len - 1 ) == 13
            {
                len = len - 1
            }
            ret SystemStringRange( line, 0, len )
        }

        # chunk size 行解析：hex 段到 ';' 前截止（忽略 chunk 扩展）
        static Int32 _chunkSize( string line )
        {
            Int32 len = SystemStringLength( line )
            Int32 hexEnd = len
            for Int32 i = 0, i < len, i = i + 1
            {
                if SystemStringCharCodeAt( line, i ) == 59
                {
                    hexEnd = i
                    break
                }
            }
            ret HttpServerCore._parseHex( SystemStringRange( line, 0, hexEnd ) )
        }

        # 十六进制解析（Int32 中转，> 2e9 返回 -1）
        static Int32 _parseHex( string s )
        {
            Int32 len = SystemStringLength( s )
            if len == 0
            {
                ret -1
            }
            Int64 v = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                Int32 d = -1
                if c >= 48 && c <= 57
                {
                    d = c - 48
                }
                elif c >= 65 && c <= 70
                {
                    d = c - 55
                }
                elif c >= 97 && c <= 102
                {
                    d = c - 87
                }
                else
                {
                    ret -1
                }
                v = v * 16 + d
                if v > 2000000000
                {
                    ret -1
                }
            }
            ret v.toInt32()
        }

        # 十进制解析（Content-Length 用；非法返回 -1）
        static Int64 _parseDec64( string s )
        {
            Int32 len = SystemStringLength( s )
            if len == 0
            {
                ret -1
            }
            Int64 v = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c < 48 || c > 57
                {
                    ret -1
                }
                v = v * 10 + ( c - 48 )
                if v > 2000000000
                {
                    ret -1
                }
            }
            ret v
        }

        # 全量程十进制解析（真 Int64，溢出判 -1）：pathInt64 专用。
        # _parseDec64 维持 2e9 上限（Int32 档调用方语义不变）。
        static Int64 _parseDec64Full( string s )
        {
            Int32 len = SystemStringLength( s )
            if len == 0
            {
                ret -1
            }
            Int64 v = 0
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c < 48 || c > 57
                {
                    ret -1
                }

                # 溢出守卫：v*10+d 不越 Int64 上限（9223372036854775807）
                if v > 922337203685477580
                {
                    ret -1
                }

                if v == 922337203685477580 && c > 55
                {
                    ret -1
                }
                v = v * 10 + ( c - 48 )
            }
            ret v
        }

        # 忽略大小写子串查找
        static bool _containsFold( string hay, string needle )
        {
            Int32 hl = SystemStringLength( hay )
            Int32 nl = SystemStringLength( needle )
            if nl == 0
            {
                ret true
            }

            if nl > hl
            {
                ret false
            }
            for Int32 i = 0, i <= hl - nl, i = i + 1
            {
                bool match = true
                for Int32 j = 0, j < nl, j = j + 1
                {
                    Int32 a = Net.Uri.fold( SystemStringCharCodeAt( hay, i + j ) )
                    Int32 b = Net.Uri.fold( SystemStringCharCodeAt( needle, j ) )
                    if a != b
                    {
                        match = false
                        break
                    }
                }
                if match
                {
                    ret true
                }
            }
            ret false
        }

        # 忽略大小写前缀匹配
        static bool _startsWithFold( string s, string prefix )
        {
            Int32 sl = SystemStringLength( s )
            Int32 pl = SystemStringLength( prefix )
            if pl == 0
            {
                ret true
            }

            if sl < pl
            {
                ret false
            }
            for Int32 i = 0, i < pl, i = i + 1
            {
                if Net.Uri.fold( SystemStringCharCodeAt( s, i ) ) != Net.Uri.fold( SystemStringCharCodeAt( prefix, i ) )
                {
                    ret false
                }
            }
            ret true
        }

        # 精确比对（不折叠大小写）
        static bool _eqExact( string a, string b )
        {
            Int32 la = SystemStringLength( a )
            Int32 lb = SystemStringLength( b )
            if la != lb
            {
                ret false
            }
            for Int32 i = 0, i < la, i = i + 1
            {
                if SystemStringCharCodeAt( a, i ) != SystemStringCharCodeAt( b, i )
                {
                    ret false
                }
            }
            ret true
        }
    }
}
