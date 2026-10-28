import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/RouteAttrs.sl — 预装载路由 attribute 家族（P4 / P9 §26）
    # 设计契约：SERVER_DESIGN.md §4.10（控制器语法）/ §7（P4）/ §26（形态 3）
    #
    # 机制（attribute 四形态之「形态 3 · runtime 装载」）：VM 只提供通用
    # 通道——类装配完成后（静态字段就绪、入口调度前）扫描全部 Preload
    # attribute，实例化（args → _init_ 重载按参数个数匹配）并注入宿主名
    # （_ownerClassName / _ownerMemberName）后调用 _enter_。全部装配逻辑
    # 写在各 attribute 的 _enter_ 里（隐式默认 Server 注册），VM 不写
    # per-attribute 的 C 代码。
    #
    # 宿主素材经 Core.Attribute 基类接口获取：
    #   hostMethodRef()        双形态（§4.10，2026-10-27）：static 方法 →
    #                          静态 method-ref（不实例化）；实例方法 → LATE
    #                          实例闭包（每请求 new 宿主实例）
    #   hostMethodIsStatic()   宿主方法是否 static（形态 2 判定）
    #   hostMethodRefOf(i)     绑定实例 method-ref（单例全程复用，§26）
    #   hostClassNew()         构造宿主类新实例
    #   ownerClassName()       宿主类全名（类级标记登记键）
    #
    # 用法（§4.10 双形态 / §26）：
    #   形态 1 · 实例控制器（类级 @OnRoute，方法可为实例方法——每请求
    #   自动 new 实例；@InstanceAttr 则单例）：
    #   @OnRoute( "/admin" )
    #   class AdminController
    #   {
    #       @OnPost( "/user" )                  # -> POST /admin/user
    #       public void saveUser( Request req, Response res ) throws { ... }
    #
    #       @Route( "/user/{id}", "delete" )    # -> DELETE /admin/user/{id}
    #       public void delUser( Request req, Response res ) throws { ... }
    #   }
    #   形态 2 · 静态直挂（类上无 @OnRoute → 必须绑定 static 函数，
    #   参数仍为 ( Request, Response )，不实例化）：
    #   class PlainController
    #   {
    #       @OnGet( "/ping" )                   # -> GET /ping
    #       public static void ping( Request req, Response res ) throws { ... }
    #   }
    #   @InstanceAttr                         # 类级单例标记（Std 通用）：首次
    #   @OnRoute( "/counter" )                 # 装配构造，写入合成静态字段
    #   class CounterController { ... }         # （Class.instance 直接可访问）
    # 接线：app.usePreloadRoutes()（configure 之后、start 之前）把默认
    # Server 上缓冲的装配期路由并入本 app 的 Router。
    # ============================================================================

    # @OnGet("/hello") — GET 路由（方法级）
    public class OnGet extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        # 装配期触发：隐式默认 Server 上注册路由
        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "GET", this._path, this )
            ret this
        }
    }

    # @OnPost("/save") — POST 路由（方法级）
    public class OnPost extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "POST", this._path, this )
            ret this
        }
    }

    # @OnPut("/item") — PUT 路由（方法级）
    public class OnPut extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "PUT", this._path, this )
            ret this
        }
    }

    # @OnDelete("/item/{id}") — DELETE 路由（方法级）
    public class OnDelete extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "DELETE", this._path, this )
            ret this
        }
    }

    # @OnPatch("/item/{id}") — PATCH 路由（方法级）
    public class OnPatch extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "PATCH", this._path, this )
            ret this
        }
    }

    # @OnHead("/info") — HEAD 路由（方法级；Router 侧 HEAD 视同 GET）
    public class OnHead extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "HEAD", this._path, this )
            ret this
        }
    }

    # @OnOptions("/info") — OPTIONS 路由（方法级；CORS 预检）
    public class OnOptions extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "OPTIONS", this._path, this )
            ret this
        }
    }

    # @OnAny("/echo") — 全动词路由（方法级；接受全部 HTTP 动词）
    public class OnAny extends Attribute
    {
        private string _path = ""

        _init_( string path )
        {
            this._path = path
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( "ANY", this._path, this )
            ret this
        }
    }

    # @Route("/x", "POST") — 显式动词通用形式（方法级）。
    # verb 缺省（单参形态）= "ANY"；registerPreload 内大写规整
    public class Route extends Attribute
    {
        private string _path = ""
        private string _verb = ""

        _init_( string path )
        {
            this._path = path
            this._verb = "ANY"
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        _init_( string path, string verb )
        {
            this._path = path
            this._verb = verb
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Method
        }

        public get string path()
        {
            ret this._path
        }

        public get string verb()
        {
            ret this._verb
        }

        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPreload( this._verb, this._path, this )
            ret this
        }
    }

    # @OnRoute("/api") — 类级路由前缀（Spring RequestMapping 形态）。
    # 该类内全部方法级路由的 pattern 拼接 prefix 后入表
    #（prefix "/admin" + 方法 "/user" -> "/admin/user"）
    public class OnRoute extends Attribute
    {
        private string _prefix = ""

        _init_( string prefix )
        {
            this._prefix = prefix
            this._attributeStage = EAttributeStage.Preload
            this._attributeTargets = EAttributeTarget.Class
        }

        public get string prefix()
        {
            ret this._prefix
        }

        # 类级先于方法级触发：前缀表就绪后方法级 _enter_ 才拼接
        public override Attribute _enter_()
        {
            SLang.HttpServer.shared().registerPrefix( this._prefix, this.ownerClassName() )
            ret this
        }
    }

    # 单例控制器标记已收编为通用机制 @InstanceAttr（Std/InstanceAttr.sl，
    # 2026-10-27 退役本模块私有 @Singleton）：装配期构造单实例写入 Front
    # 编译期合成的静态字段（缺省名 instance / @InstanceAttr("inst") 自定义），
    # 源码直接 ClassA.instance 访问；registerPreload 经
    # SystemAttributeGetInstanceField 取同一实例绑 hostMethodRefOf
    #（bind-once，跨 handler 状态共享，SERVER_DESIGN.md §26 语义不变）。
}
