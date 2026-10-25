import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/RouteAttrs.sl — 预装载路由 attribute 家族（P4）
    # 设计契约：SERVER_DESIGN.md §4.10（控制器语法）/ §7（P4 方案）
    #
    # 机制：SLB 中的 attribute 契约在 C VM 装配期（Preload）经
    # vm_route_attribute.c 收集——方法级条目按动词入路由表，类级 OnRoute 记
    # 前缀；装配完成后 join 出 "verb|path|class|method" 行，经系统方法
    #（SystemServerRouteCount/Line/Handler）暴露给 SL 层，
    # SLang.Server.usePreloadRoutes() 拉取并入 Router。
    # handler 为 LATE 实例闭包（class_id/method_id 藏于闭包上下文）：
    # 每请求实例化全新控制器实例（§4.10 每请求一实例）。
    #
    # 类名与 C 侧注册表精确匹配（vm_route_attribute.c s_handlers）：
    #   方法级：OnGet/OnPost/OnPut/OnDelete/OnPatch/OnHead/OnOptions/OnAny
    #           （单参 path）；Route（path[, verb]，verb 缺省 = ANY 大写化）
    #   类级　：OnRoute（prefix，Spring RequestMapping 形态）
    # 契约：stage = Preload；方法级 targets = Method，类级 targets = Class。
    #
    # 用法（§4.10）：
    #   @OnRoute( "/admin" )
    #   class AdminController
    #   {
    #       @OnPost( "user" )                  # -> POST /admin/user
    #       public void saveUser( Request req, Response res ) throws { ... }
    #
    #       @Route( "user/{id}", "DELETE" )    # -> DELETE /admin/user/{id}
    #       public void delUser( Request req, Response res ) throws { ... }
    #   }
    # 装配后一次性接线：SLang.Server.usePreloadRoutes()（configure 之后、
    # start 之前）。
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
    }

    # @Route("/x", "POST") — 显式动词通用形式（方法级）。
    # verb 缺省 / 空串 = "ANY"（全动词），C 侧统一大写化
    public class Route extends Attribute
    {
        private string _path = ""
        private string _verb = ""

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
    }

    # @OnRoute("/api") — 类级路由前缀（Spring RequestMapping 形态）。
    # 该类内全部方法级路由的 path 拼接 prefix 后入表
    #（prefix "/admin" + 方法 "user" -> "/adminuser"，故方法 path 应带
    # 前导 '/'：@OnPost( "/user" ) -> "/admin/user"）
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
    }
}
