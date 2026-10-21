import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Plugin.sl — 中间件管道与插件模型（P2）
    # 设计契约：SERVER_DESIGN.md §4.7 / §6.9
    #
    # 模型：
    #   - 中间件 = 单个三参 Function：function( SLang.Request req,
    #     SLang.Response res, SLang.Next nx )——next 是关键字 → SLang.Next
    #     类型令牌 + nx.go() 放行（§2.3 语言约束）；
    #   - 插件 = ServerPlugin 子类（可携带多条注册），onInstall 在 use() 时
    #     立即执行（§6.9）；
    #   - 管道：连接协程内联执行（onion 同步嵌套——后置环在 handler 协程
    #     awaitTask 返回后自然回程；中间件自身可 await，§4.7）；最内环 =
    #     handler 协程派发（或 404/405 尾环应答——未匹配请求同样过管道，
    #     staticFiles/CORS 预检依赖此语义）；
    #   - 幂等：nx.go() 重复调用 no-op（防双派发）；未调 go() = 短路
    #     （中间件必须经 res.* 写响应或短路，§6.9 规则）。
    # 与设计的偏差：onInstall() 无参（设计的 onInstall(app) 传实例——P1 起
    #   门面 SLang.Server 为静态形态（§12 复盘 ①），插件经静态调用注册）。
    # ============================================================================

    # ============================================================================
    # Next — 中间件放行令牌（模块内构造；用户侧只调 nx.go()）
    # ============================================================================
    public class Next
    {
        _Pipeline _pipe = null
        Int32 _idx = 0
        bool _gone = false

        _init_( _Pipeline pipe, Int32 idx )
        {
            this._pipe = pipe
            this._idx = idx
            this._gone = false
        }

        # 放行进下一环；最内环 = handler 派发（或 404/405 应答）。
        # 幂等：已放行后的重复调用 no-op
        public void go() throws
        {
            if this._gone
            {
                ret
            }
            this._gone = true
            _Pipeline p = this._pipe
            p._runFrom( this._idx )
        }
    }

    # ============================================================================
    # ServerPlugin — 插件基类（钩子默认空实现；子类 override 重写——
    # SL 无 virtual 关键字，成员方法默认可被子类重写，§2.3 ⑧）
    # ============================================================================
    public class ServerPlugin
    {
        # 注册中间件/路由/钩子的唯一入口（use(plugin) 时立即执行）
        public void onInstall()
        {
        }

        # start 后、accept 前
        public void onStart()
        {
        }

        # stop 收尾
        public void onStop()
        {
        }

        # WS 会话级钩子（对所有插件广播调用，§6.9）
        public void onWsOpen( WsSession s )
        {
        }

        public void onWsClose( WsSession s )
        {
        }

        # ── 链式配置占位（P3，§4.11）：基类返回自身 no-op，子类 override──
        # 静态工厂返回类型是 ServerPlugin（跨模块子类上行赋型纪律），
        # 链式 .skip()/.ws() 须经基类签名可见；auth 之外插件调用为 no-op。
        public ServerPlugin skip( string path )
        {
            ret this
        }

        public ServerPlugin ws( bool on )
        {
            ret this
        }
    }

    # ============================================================================
    # _Pipeline — 管道执行器（内部；连接协程内联）
    # 每环框架构造 Next 实例（内持下一环索引，§6.9——SL 无方法引用，
    # 框架持索引逐环构造）；尾环透传引擎 _tail（handler 派发 / 404 / 405）。
    # 返回值透传 _tail：true = 连接已收尾（超时断连路径，外层 break）
    # ============================================================================
    class _Pipeline
    {
        Net.TcpStream _client = null
        ServerConfig _cfg = null
        RouteInfo _route = null
        # 0 = 有 handler；404 / 405 = 尾环应答模式
        Int32 _noRoute = 0
        Request _req = null
        Response _res = null
        bool _isHead = false
        Int32 _mwCount = 0

        _init_( Net.TcpStream client, ServerConfig cfg, RouteInfo route, Int32 noRoute, Request req, Response res, bool isHead )
        {
            this._client = client
            this._cfg = cfg
            this._route = route
            this._noRoute = noRoute
            this._req = req
            this._res = res
            this._isHead = isHead
            this._mwCount = _PluginHost.middlewareCount()
        }

        # 管道入口（第 0 环起）
        bool _run() throws
        {
            ret this._runFrom( 0 )
        }

        # 从第 idx 环继续（Next.go 入口）；idx == 中间件数 → 尾环
        bool _runFrom( Int32 idx ) throws
        {
            if idx < this._mwCount
            {
                # Function 取值先拷局部再调用（HttpHeaders 头注记纪律）
                function mw = _PluginHost.middlewareAt( idx )
                Next nx = Next( this, idx + 1 )
                mw( this._req, this._res, nx )
                ret false
            }
            Net.TcpStream c = this._client
            ServerConfig cf = this._cfg
            RouteInfo rt = this._route
            Request rq = this._req
            Response rs = this._res
            Int32 nr = this._noRoute
            bool ih = this._isHead
            ret HttpServerCore._tail( c, cf, rt, nr, rq, rs, ih )
        }
    }

    # ============================================================================
    # _PluginHost — 中间件/插件宿主（内部静态；HttpServerCore 生命周期联动）
    # 单 VM 协程调度无锁（§3 并发模型不变量）
    # ============================================================================
    class _PluginHost
    {
        # 中间件表（注册序即执行序）
        static List<Function> _middlewares = null
        # 插件表（生命周期/WS 钩子广播）
        static List<object> _plugins = null

        static void _ensure()
        {
            if _middlewares == null
            {
                _middlewares = new()
            }
            if _plugins == null
            {
                _plugins = new()
            }
        }

        static void addMiddleware( Function mw )
        {
            _PluginHost._ensure()
            _middlewares.add( mw )
        }

        static void addPlugin( ServerPlugin p )
        {
            _PluginHost._ensure()
            _plugins.add( p )
        }

        # 清空（HttpServerCore.reset 联动——stop 后重新配置场景）
        static void clear()
        {
            _middlewares = new()
            _plugins = new()
        }

        static Int32 middlewareCount()
        {
            if _middlewares == null
            {
                ret 0
            }
            ret _middlewares.length
        }

        static Function middlewareAt( Int32 i )
        {
            ret _middlewares[i]
        }

        # ── 钩子广播（单插件异常吞——不拖垮服务，§6.11 精神）──

        static void notifyStart()
        {
            if _plugins == null
            {
                ret
            }
            Int32 n = _plugins.length
            for Int32 i = 0, i < n, i = i + 1
            {
                object po = _plugins[i]
                ServerPlugin p = po as ServerPlugin
                label one
                {
                    p.onStart()
                }
                catch { }
            }
        }

        static void notifyStop()
        {
            if _plugins == null
            {
                ret
            }
            Int32 n = _plugins.length
            for Int32 i = 0, i < n, i = i + 1
            {
                object po = _plugins[i]
                ServerPlugin p = po as ServerPlugin
                label one
                {
                    p.onStop()
                }
                catch { }
            }
        }

        static void notifyWsOpen( WsSession s )
        {
            if _plugins == null
            {
                ret
            }
            Int32 n = _plugins.length
            for Int32 i = 0, i < n, i = i + 1
            {
                object po = _plugins[i]
                ServerPlugin p = po as ServerPlugin
                label one
                {
                    p.onWsOpen( s )
                }
                catch { }
            }
        }

        static void notifyWsClose( WsSession s )
        {
            if _plugins == null
            {
                ret
            }
            Int32 n = _plugins.length
            for Int32 i = 0, i < n, i = i + 1
            {
                object po = _plugins[i]
                ServerPlugin p = po as ServerPlugin
                label one
                {
                    p.onWsClose( s )
                }
                catch { }
            }
        }
    }
}
