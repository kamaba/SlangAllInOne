import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Docs.sl — OpenAPI 文档 + /docs 页面 + importOpenApi（P3）
    # 设计契约：SERVER_DESIGN.md §4.8 / §6.10
    #
    # 实现要点（§6.10 实例探针法）：
    #   - 样例实例 → BaseJson.fromData → JSON 树 → 逐节点映射 OpenAPI schema
    #     （string/integer/number/boolean/array/object/nullable；零反射，
    #     schema 键 = SystemObjectGetType(sample).className）；
    #   - openapi.json 手工组 TreeNode<string> 树（弱类型映射：object 节点
    #     _value="{}"、array 节点 _value="[]"、名字为孩子键）→
    #     BaseJson.fromTree(...).toJson() 序列化；
    #   - /docs 页面 = 自包含单文件 HTML（零外链零 CDN，wasm/playground.html
    #     同款离线策略），读同源 /openapi.json 渲染 + GET try-it-out；
    #   - /docs 与 /openapi.json 在 start 时挂载（用户已注册同路径则让位，
    #     §6.10"用户优先"），isBuiltin 标记（不进 openapi.json 自身）；
    #   - importOpenApi：paths → 未注册 (method, pattern) 建文档路由
    #     （isDocOnly，命中 501 ApiResult）；已注册者合并轻量元数据
    #     （summary/tags/desc/param/security）；Router.add 对 isDocOnly
    #     同 (method,pattern) 自动让位 + 元数据继承（§4.8 覆盖工作流）。
    # 与设计的偏差（§16 实录）：导入的文档路由不回填 requestBody/responses
    #     样例（样例实例无法从 JSON 反推，v1 仅轻量元数据）；ANY 路由在
    #     openapi.json 展开 7 动词同 op；WS 路由不进 openapi.json。
    # ============================================================================

    class Docs
    {
        # ── 构建态（openApiJson 一次构建内有效）──
        # schema 去重表：类名 → schema 树节点
        static Map<string, TreeNode<string>> _schemas = null
        static bool _hasSecurity = false

        # ── "$" 单字符经 ByteBuffer 构造（"$" 是插值前缀，字面量任何
        #    位置出现都会吞掉后续 token；36 = '$' 的 UTF-8/ASCII 码位）──
        static string _dollar()
        {
            ByteBuffer b = ByteBuffer( 8 )
            b.writeU8( 36 )
            string s = b.toString()
            b.release()
            ret s
        }

        # ── 样例类型名（探针法 schema 键；无反射替代：系统方法取 Type）──
        # Type.toString() = metaClass.className + 模板参数（DTO 无模板 = 纯类名）
        static string _typeNameOf( object sample )
        {
            if sample == null
            {
                ret ""
            }

            string nm = ""
            label t
            {
                Type ty = SystemObjectGetType( sample ) as Type
                if ty != null
                {
                    nm = ty.toString()
                }
            }
            catch
            {
            }
            ret nm
        }

        # ── 组树基元（弱类型映射：object "{}"、array "[]"、标量 = 文本）──

        static TreeNode<string> _obj()
        {
            TreeNode<string> n = TreeNode<string>()
            n.value = "{}"
            ret n
        }

        static TreeNode<string> _objChild( TreeNode<string> parent, string key )
        {
            TreeNode<string> n = parent.addChild( key, "{}" )
            ret n
        }

        static TreeNode<string> _arrChild( TreeNode<string> parent, string key )
        {
            TreeNode<string> n = parent.addChild( key, "[]" )
            ret n
        }

        static void _kv( TreeNode<string> parent, string key, string val )
        {
            parent.addChild( key, val )
        }

        # ── schema 探针（样例 JSON 文本 → OpenAPI schema 节点）──

        # 样例 JSON 文本 → 独立 schema 节点（不挂接）
        static TreeNode<string> _probeText( string sampleJsonText )
        {
            TreeNode<string> s = Docs._obj()
            if sampleJsonText == null || SystemStringLength( sampleJsonText ) == 0
            {
                ret s
            }

            BaseJson j = BaseJson.parse( sampleJsonText )
            if j.isEmpty
            {
                ret s
            }

            Docs._fillSchema( j.value, s )
            ret s
        }

        # 把 JSON 值的 schema 形态填进已建 schema 节点（object 标记节点）
        static void _fillSchema( JsonValue v, TreeNode<string> s )
        {
            if v.isString
            {
                Docs._kv( s, "type", "string" )
                ret
            }

            if v.isBool
            {
                Docs._kv( s, "type", "boolean" )
                ret
            }

            if v.isNumber
            {
                string raw = v.asString()
                bool isInt = true
                Int32 len = SystemStringLength( raw )
                for Int32 i = 0, i < len, i = i + 1
                {
                    Int32 c = SystemStringCharCodeAt( raw, i )
                    if c == 46 || c == 101 || c == 69
                    {
                        isInt = false
                        break
                    }
                }
                Docs._kv( s, "type", isInt ? "integer" : "number" )
                ret
            }

            if v.isNull
            {
                Docs._kv( s, "nullable", "true" )
                ret
            }

            if v.isArray
            {
                Docs._kv( s, "type", "array" )
                Array<JsonValue> ch = v.children()
                if ch != null && ch.length > 0
                {
                    TreeNode<string> items = Docs._arrChild( s, "items" )
                    TreeNode<string> first = items.addChild( "", "{}" )
                    Docs._fillSchema( ch[0], first )
                }
                ret
            }

            if v.isObject
            {
                Docs._kv( s, "type", "object" )
                TreeNode<string> props = Docs._objChild( s, "properties" )
                Array<string> ks = v.keys()
                if ks != null
                {
                    Int32 n = ks.length
                    for Int32 i = 0, i < n, i = i + 1
                    {
                        string k = ks[i]
                        TreeNode<string> ps = props.addChild( k, "{}" )
                        Docs._fillSchema( v._getItem_( k ), ps )
                    }
                }
                ret
            }
        }

        # schema 登记（类名去重；首次样本胜出）；同时登记到 _schemas
        static void _registerSchema( string cls, string sampleJsonText )
        {
            if cls == null || SystemStringLength( cls ) == 0
            {
                ret
            }

            if sampleJsonText == null || SystemStringLength( sampleJsonText ) == 0
            {
                ret
            }

            if Docs._schemas.containsKey( cls )
            {
                ret
            }
            TreeNode<string> sc = Docs._probeText( sampleJsonText )
            Docs._schemas.add( cls, sc )
        }

        # ── openapi.json 全文生成（OpenAPI 3.0.3，§6.10 骨架）──

        static string openApiJson()
        {
            Docs._schemas = new()
            Docs._hasSecurity = false

            # ---- pass 1：登记 schema（body + responses 样例类）----
            List<RouteInfo> routes = Router.allRoutes()
            Int32 rn = routes.length
            for Int32 i = 0, i < rn, i = i + 1
            {
                RouteInfo r = routes[i]
                if r.isBuiltin || Net.Uri.eqFold( r.method, "WS" )
                {
                    continue
                }

                if r.security != ""
                {
                    Docs._hasSecurity = true
                }
                Docs._registerSchema( r.docBodyClass, r.docBodyText )
                if r.docResponses != null
                {
                    Int32 rn2 = r.docResponses.length
                    for Int32 k = 0, k < rn2, k = k + 1
                    {
                        RouteResp rr = r.docResponses[k]
                        Docs._registerSchema( rr.sampleClass, rr.sampleText )
                    }
                }
            }

            # ---- 根骨架 ----
            TreeNode<string> root = Docs._obj()
            Docs._kv( root, "openapi", "3.0.3" )
            TreeNode<string> info = Docs._objChild( root, "info" )
            Docs._kv( info, "title", "SLang Server" )
            Docs._kv( info, "version", "1.0.0" )
            TreeNode<string> servers = Docs._arrChild( root, "servers" )
            TreeNode<string> srv = servers.addChild( "", "{}" )
            Docs._kv( srv, "url", "http://" + HttpServerCore._listenHost + ":" + HttpServerCore._listenPort.toString() )

            # ---- paths（注册序保序：pattern 键 + 路径对象节点）----
            TreeNode<string> paths = Docs._objChild( root, "paths" )
            List<string> patKeys = new()
            List<TreeNode<string>> patObjs = new()
            for Int32 i = 0, i < rn, i = i + 1
            {
                RouteInfo r = routes[i]
                if r.isBuiltin || Net.Uri.eqFold( r.method, "WS" )
                {
                    continue
                }
                # 路径对象定位/新建（保序）
                TreeNode<string> po = null
                Int32 kn = patKeys.length
                for Int32 ki = 0, ki < kn, ki = ki + 1
                {
                    if patKeys[ki] == r.pattern
                    {
                        po = patObjs[ki]
                        break
                    }
                }
                if po == null
                {
                    po = Docs._objChild( paths, r.pattern )
                    patKeys.add( r.pattern )
                    patObjs.add( po )
                }

                # 动词键（ANY 展开 7 动词同 op；小写 OpenAPI 约定）
                if Net.Uri.eqFold( r.method, "ANY" )
                {
                    Docs._opInto( r, po, "get" )
                    Docs._opInto( r, po, "post" )
                    Docs._opInto( r, po, "put" )
                    Docs._opInto( r, po, "delete" )
                    Docs._opInto( r, po, "patch" )
                    Docs._opInto( r, po, "head" )
                    Docs._opInto( r, po, "options" )
                }
                else
                {
                    Docs._opInto( r, po, Docs._toLower( r.method ) )
                }
            }

            # ---- components ----
            if Docs._schemas.isNotEmpty
            {
                TreeNode<string> comps = Docs._objChild( root, "components" )
                TreeNode<string> schemas = Docs._objChild( comps, "schemas" )
                List<string> ks = Docs._schemas.keys
                Int32 kn = ks.length
                for Int32 i = 0, i < kn, i = i + 1
                {
                    string k = ks[i]
                    TreeNode<string> sc = Docs._schemas._getItem_( k )
                    sc.name = k
                    schemas.attach( sc )
                }
                # securitySchemes（任一路由声明过 → 两定义固定生成，§6.10）
                if Docs._hasSecurity
                {
                    TreeNode<string> ss = Docs._objChild( comps, "securitySchemes" )
                    TreeNode<string> bearer = Docs._objChild( ss, "bearerAuth" )
                    Docs._kv( bearer, "type", "http" )
                    Docs._kv( bearer, "scheme", "bearer" )
                    Docs._kv( bearer, "bearerFormat", "JWT" )
                    TreeNode<string> apiKey = Docs._objChild( ss, "apiKeyAuth" )
                    Docs._kv( apiKey, "type", "apiKey" )
                    Docs._kv( apiKey, "in", "header" )
                    Docs._kv( apiKey, "name", "X-API-Key" )
                }
            }

            Tree<string> docTree = Tree<string>()
            docTree.setRoot( root )
            BaseJson doc = BaseJson.fromTree( docTree )
            ret doc.toJson()
        }

        # 单路由 → operation 节点（挂进路径对象的 verb 键下）
        static void _opInto( RouteInfo r, TreeNode<string> pathObj, string verbKey )
        {
            TreeNode<string> op = Docs._objChild( pathObj, verbKey )
            if SystemStringLength( r.summary ) > 0
            {
                Docs._kv( op, "summary", r.summary )
            }

            if SystemStringLength( r.desc ) > 0
            {
                Docs._kv( op, "description", r.desc )
            }

            if SystemStringLength( r.tags ) > 0
            {
                TreeNode<string> tags = Docs._arrChild( op, "tags" )
                # 逗号分隔多标签（§4.8）
                Int32 len = SystemStringLength( r.tags )
                Int32 start = 0
                for Int32 i = 0, i <= len, i = i + 1
                {
                    if i == len || SystemStringCharCodeAt( r.tags, i ) == 44
                    {
                        if i > start
                        {
                            tags.addChild( "", SystemStringRange( r.tags, start, i ) )
                        }
                        start = i + 1
                    }
                }
            }

            # parameters（path/query；in 按 pattern 是否含 {name} 推导）
            if r.docParams != null && r.docParams.length > 0
            {
                TreeNode<string> paramsNode = Docs._arrChild( op, "parameters" )
                Int32 pn = r.docParams.length
                for Int32 i = 0, i < pn, i = i + 1
                {
                    RouteParam p = r.docParams[i]
                    TreeNode<string> pn2 = paramsNode.addChild( "", "{}" )
                    Docs._kv( pn2, "name", p.name )
                    Docs._kv( pn2, "in", SystemStringLength( p.name ) > 0 && Docs._sfFind( r.pattern, "{" + p.name + "}" ) >= 0 ? "path" : "query" )
                    Docs._kv( pn2, "required", p.required ? "true" : "false" )
                    if SystemStringLength( p.desc ) > 0
                    {
                        Docs._kv( pn2, "description", p.desc )
                    }

                    if SystemStringLength( p.type ) > 0
                    {
                        TreeNode<string> ps = Docs._objChild( pn2, "schema" )
                        Docs._kv( ps, "type", p.type )
                    }
                }
            }

            # requestBody（JSON / urlencoded / multipart；§6.10 form 形态）
            bool hasFile = false
            bool hasForm = false
            if r.docForms != null
            {
                Int32 fn = r.docForms.length
                for Int32 i = 0, i < fn, i = i + 1
                {
                    RouteParam dfl = r.docForms[i]
                    if dfl.kind == "file"
                    {
                        hasFile = true
                    }
                    else
                    {
                        hasForm = true
                    }
                }
            }

            if SystemStringLength( r.docBodyText ) > 0
            {
                Docs._attachRequestBody( op, r, "application/json", r.docBodyText, r.docBodyClass )
            }
            elif hasFile || hasForm
            {
                # 含文件字段 → multipart（普通字段并入）；纯 form → urlencoded
                if hasFile
                {
                    Docs._attachFormBody( op, r, "multipart/form-data", true )
                }
                else
                {
                    Docs._attachFormBody( op, r, "application/x-www-form-urlencoded", false )
                }
            }

            # responses
            if r.docResponses != null && r.docResponses.length > 0
            {
                TreeNode<string> resps = Docs._objChild( op, "responses" )
                Int32 rsn = r.docResponses.length
                for Int32 i = 0, i < rsn, i = i + 1
                {
                    RouteResp rr = r.docResponses[i]
                    TreeNode<string> rn2 = Docs._objChild( resps, rr.status.toString() )
                    TreeNode<string> content = Docs._objChild( rn2, "content" )
                    TreeNode<string> media = Docs._objChild( content, rr.mediaType )
                    if SystemStringLength( rr.sampleClass ) > 0 && Docs._schemas.containsKey( rr.sampleClass )
                    {
                        TreeNode<string> sch = Docs._objChild( media, "schema" )
                        Docs._kv( sch, Docs._dollar() + "ref", "#/components/schemas/" + rr.sampleClass )
                    }
                    elif SystemStringLength( rr.sampleText ) > 0
                    {
                        TreeNode<string> sch = Docs._objChild( media, "schema" )
                        Docs._fillSchema( BaseJson.parse( rr.sampleText ).value, sch )
                    }
                    Docs._attachExample( media, rr.sampleText )
                }
            }

            # security（operation 级，§6.10）
            if SystemStringLength( r.security ) > 0
            {
                TreeNode<string> sec = Docs._arrChild( op, "security" )
                TreeNode<string> one = sec.addChild( "", "{}" )
                one.addChild( r.security, "[]" )
            }
        }

        # JSON body：content/media → schema（$ref 或内联探针）+ example
        static void _attachRequestBody( TreeNode<string> op, RouteInfo r, string mediaType, string sampleText, string sampleClass )
        {
            TreeNode<string> rb = Docs._objChild( op, "requestBody" )
            Docs._kv( rb, "required", "true" )
            TreeNode<string> content = Docs._objChild( rb, "content" )
            TreeNode<string> media = Docs._objChild( content, mediaType )
            if SystemStringLength( sampleClass ) > 0 && Docs._schemas.containsKey( sampleClass )
            {
                TreeNode<string> sch = Docs._objChild( media, "schema" )
                Docs._kv( sch, Docs._dollar() + "ref", "#/components/schemas/" + sampleClass )
            }
            else
            {
                TreeNode<string> sch = Docs._objChild( media, "schema" )
                Docs._fillSchema( BaseJson.parse( sampleText ).value, sch )
            }
            Docs._attachExample( media, sampleText )
        }

        # form / multipart body：object schema（file 字段 type:string+format:binary）
        static void _attachFormBody( TreeNode<string> op, RouteInfo r, string mediaType, bool multipart )
        {
            TreeNode<string> rb = Docs._objChild( op, "requestBody" )
            TreeNode<string> content = Docs._objChild( rb, "content" )
            TreeNode<string> media = Docs._objChild( content, mediaType )
            TreeNode<string> sch = Docs._objChild( media, "schema" )
            Docs._kv( sch, "type", "object" )
            TreeNode<string> props = Docs._objChild( sch, "properties" )
            Int32 fn = r.docForms.length
            for Int32 i = 0, i < fn, i = i + 1
            {
                RouteParam p = r.docForms[i]
                TreeNode<string> ps = props.addChild( p.name, "{}" )
                Docs._kv( ps, "type", "string" )
                if p.kind == "file"
                {
                    Docs._kv( ps, "format", "binary" )
                }

                if SystemStringLength( p.desc ) > 0
                {
                    Docs._kv( ps, "description", p.desc )
                }
            }
        }

        # example 节点：样例 JSON 文本重解析 → 根改名 example → 挂进 media
        static void _attachExample( TreeNode<string> media, string sampleJsonText )
        {
            if sampleJsonText == null || SystemStringLength( sampleJsonText ) == 0
            {
                ret
            }
            label e
            {
                BaseJson j = BaseJson.parse( sampleJsonText )
                if j.isNotEmpty
                {
                    j.root.name = "example"
                    media.attach( j.root )
                }
            }
            catch
            {
            }
        }

        # ── /docs 与 /openapi.json 挂载（start 时调；用户已注册同路径让位）──

        static void _mount()
        {
            if Router.findExact( "GET", "/docs" ) != null
            {
                ret
            }
            function fDocs = function( SLang.Request req, SLang.Response res )
            {
                Docs._serveDocs( req, res )
            }
            RouteInfo d = Router.add( "GET", "/docs", fDocs )
            d.isBuiltin = true
            d.summary = "API 文档页面"

            if Router.findExact( "GET", "/openapi.json" ) != null
            {
                ret
            }
            function fApi = function( SLang.Request req, SLang.Response res )
            {
                Docs._serveOpenApi( req, res )
            }
            RouteInfo o = Router.add( "GET", "/openapi.json", fApi )
            o.isBuiltin = true
            o.summary = "OpenAPI 3.0.3 规范"
        }

        static void _serveDocs( SLang.Request req, SLang.Response res )
        {
            res.html( Docs._htmlPage() )
        }

        static void _serveOpenApi( SLang.Request req, SLang.Response res )
        {
            res.contentType( "application/json" ).text( Docs.openApiJson() )
        }

        # 文档路由 501 应答（importOpenApi 登记；被真实注册覆盖后不再触达）
        static void _serveNotImplemented( SLang.Request req, SLang.Response res )
        {
            res.jsonFail( 501, "not implemented", 501 )
        }

        # ── importOpenApi（Apifox 导出 OpenAPI json → 路由骨架，§4.8）──
        # 返回新建文档路由数；已注册 (method,pattern) 仅合并轻量元数据
        # （summary/tags/desc/param/security），requestBody/responses 样例
        # 不反推（实例不可得，v1 偏差见类头）
        static Int32 importOpenApi( string jsonPath ) throws
        {
            string text = File.readAllText( jsonPath )
            BaseJson j = BaseJson.parse( text )
            if j.isEmpty
            {
                ret 0
            }

            JsonValue paths = j.value._getItem_( "paths" )
            if paths.isNull || paths.isObject == false
            {
                ret 0
            }

            Array<string> pats = paths.keys()
            if pats == null
            {
                ret 0
            }

            Int32 added = 0
            Int32 pn = pats.length
            for Int32 pi = 0, pi < pn, pi = pi + 1
            {
                string pattern = pats[pi]
                JsonValue po = paths._getItem_( pattern )
                if po.isNull || po.isObject == false
                {
                    continue
                }

                Int32 vn = 7
                for Int32 vi = 0, vi < vn, vi = vi + 1
                {
                    string verb = Docs._verbAt( vi )
                    JsonValue op = po._getItem_( verb )
                    if op.isNull || op.isObject == false
                    {
                        continue
                    }

                    string method = Docs._toUpper( verb )
                    RouteInfo exist = Router.findExact( method, pattern )
                    if exist != null
                    {
                        Docs._mergeMeta( exist, op, pattern )
                    }
                    else
                    {
                        function f = function( SLang.Request rq, SLang.Response rs )
                        {
                            Docs._serveNotImplemented( rq, rs )
                        }
                        RouteInfo r = Router.add( method, pattern, f )
                        r.isDocOnly = true
                        Docs._mergeMeta( r, op, pattern )
                        added = added + 1
                    }
                }
            }
            ret added
        }

        # OpenAPI op JSON → RouteInfo 轻量元数据合并
        static void _mergeMeta( RouteInfo r, JsonValue op, string pattern )
        {
            JsonValue sv = op._getItem_( "summary" )
            if sv.isString && SystemStringLength( r.summary ) == 0
            {
                r.summary = sv.asString()
            }

            JsonValue dv = op._getItem_( "description" )
            if dv.isString && SystemStringLength( r.desc ) == 0
            {
                r.desc = dv.asString()
            }

            JsonValue tv = op._getItem_( "tags" )
            if tv.isArray && SystemStringLength( r.tags ) == 0
            {
                Array<JsonValue> ts = tv.children()
                if ts != null
                {
                    Int32 tn = ts.length
                    for Int32 i = 0, i < tn, i = i + 1
                    {
                        if ts[i].isString
                        {
                            if SystemStringLength( r.tags ) > 0
                            {
                                r.tags = r.tags + ","
                            }
                            r.tags = r.tags + ts[i].asString()
                        }
                    }
                }
            }

            JsonValue pv = op._getItem_( "parameters" )
            if pv.isArray
            {
                Array<JsonValue> ps = pv.children()
                if ps != null
                {
                    Int32 pn = ps.length
                    for Int32 i = 0, i < pn, i = i + 1
                    {
                        JsonValue p = ps[i]
                        if p.isObject == false
                        {
                            continue
                        }
                        JsonValue nm = p._getItem_( "name" )
                        if nm.isString == false
                        {
                            continue
                        }
                        string type = "string"
                        JsonValue sch = p._getItem_( "schema" )
                        if sch.isObject
                        {
                            JsonValue ty = sch._getItem_( "type" )
                            if ty.isString
                            {
                                type = ty.asString()
                            }
                        }
                        bool req = false
                        JsonValue rv = p._getItem_( "required" )
                        if rv.isBool
                        {
                            req = rv.asBool()
                        }
                        string pdesc = ""
                        JsonValue dsc = p._getItem_( "description" )
                        if dsc.isString
                        {
                            pdesc = dsc.asString()
                        }
                        r.param( nm.asString(), type, pdesc, req )
                    }
                }
            }

            if SystemStringLength( r.security ) == 0
            {
                JsonValue se = op._getItem_( "security" )
                if se.isArray
                {
                    Array<JsonValue> ses = se.children()
                    if ses != null && ses.length > 0 && ses[0].isObject
                    {
                        Array<string> ks = ses[0].keys()
                        if ks != null && ks.length > 0
                        {
                            string scheme = ks[0]
                            if scheme == "bearerAuth" || scheme == "apiKeyAuth"
                            {
                                r.security = scheme
                            }
                        }
                    }
                }
            }
        }

        # 导入扫描的 7 动词表
        static string _verbAt( Int32 i )
        {
            if i == 0
            {
                ret "get"
            }

            if i == 1
            {
                ret "post"
            }

            if i == 2
            {
                ret "put"
            }

            if i == 3
            {
                ret "delete"
            }

            if i == 4
            {
                ret "patch"
            }

            if i == 5
            {
                ret "head"
            }

            ret "options"
        }

        # 大小写折叠（标准库暂无 toUpper/toLower——Upload.sl 同款逐字节，
        # ByteBuffer.writeU8 + toString）
        static string _toLower( string s )
        {
            if s == null
            {
                ret ""
            }
            Int32 len = SystemStringLength( s )
            ByteBuffer b = ByteBuffer( len + 8 )
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c >= 65 && c <= 90
                {
                    c = c + 32
                }
                b.writeU8( SystemConvertUInt8( c ) )
            }
            string res = b.toString()
            b.release()
            ret res
        }

        static string _toUpper( string s )
        {
            if s == null
            {
                ret ""
            }
            Int32 len = SystemStringLength( s )
            ByteBuffer b = ByteBuffer( len + 8 )
            for Int32 i = 0, i < len, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( s, i )
                if c >= 97 && c <= 122
                {
                    c = c - 32
                }
                b.writeU8( SystemConvertUInt8( c ) )
            }
            string res = b.toString()
            b.release()
            ret res
        }

        # 子串查找（测试助手同款；openapi 断言复用）
        static Int32 _sfFind( string text, string sub )
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

        # ── /docs 页面（自包含 HTML；零外链零 CDN）──

        static string _htmlPage()
        {
            string js = Docs._pageJs()
            string css = Docs._pageCss()
            string nl = "\n"
            # 长链一律 StringBuilder（"+" 字面量链截断坑，见 _pageJs 注）
            StringBuilder sb = StringBuilder()
            sb.append( "<!DOCTYPE html>" )
            sb.append( nl )
            sb.append( "<html lang=\"zh\">" )
            sb.append( nl )
            sb.append( "<head>" )
            sb.append( nl )
            sb.append( "<meta charset=\"utf-8\">" )
            sb.append( nl )
            sb.append( "<title>SLang Server API</title>" )
            sb.append( nl )
            sb.append( "<style>" )
            sb.append( css )
            sb.append( "</style>" )
            sb.append( nl )
            sb.append( "</head>" )
            sb.append( nl )
            sb.append( "<body>" )
            sb.append( nl )
            sb.append( "<header><h1>SLang Server API</h1><div id=\"meta\"></div></header>" )
            sb.append( nl )
            sb.append( "<div id=\"wrap\"><nav id=\"nav\"></nav><main id=\"detail\">选择左侧接口查看详情</main></div>" )
            sb.append( nl )
            sb.append( "<script>" )
            sb.append( js )
            sb.append( "</script>" )
            sb.append( nl )
            sb.append( "</body>" )
            sb.append( nl )
            sb.append( "</html>" )
            string res = sb.toString()
            sb.release()
            ret res
        }

        # 注意：超长字符串字面量 "+" 链在 Front/VM 求值中会截断（实测
        # ret 后仅首段字面量存活）——一律 StringBuilder.append 逐段追加
        static string _pageCss()
        {
            StringBuilder sb = StringBuilder()
            sb.append( "body{font-family:system-ui,sans-serif;margin:0;background:#f6f7f9;color:#222}" )
            sb.append( "header{padding:14px 20px;background:#1a2332;color:#fff}" )
            sb.append( "header h1{margin:0;font-size:18px}" )
            sb.append( "#meta{font-size:12px;opacity:.7;margin-top:4px}" )
            sb.append( "#wrap{display:flex;min-height:90vh}" )
            sb.append( "#nav{width:270px;background:#fff;border-right:1px solid #e2e5ea;overflow:auto}" )
            sb.append( "#detail{flex:1;padding:18px 24px;overflow:auto}" )
            sb.append( ".grp{padding:8px 12px;font-size:12px;color:#8a919e;background:#eef1f5;position:sticky;top:0}" )
            sb.append( ".ep{display:block;padding:8px 12px;cursor:pointer;border-bottom:1px solid #f0f2f5;font-size:13px}" )
            sb.append( ".ep:hover{background:#f4f7fb}.ep.sel{background:#e8f0fe}" )
            sb.append( ".m{display:inline-block;min-width:52px;text-align:center;font-size:11px;font-weight:700;color:#fff;border-radius:3px;padding:2px 5px;margin-right:6px}" )
            sb.append( ".m.get{background:#2e8b57}.m.post{background:#e07b39}.m.put{background:#8a2be2}" )
            sb.append( ".m.delete{background:#d33}.m.patch{background:#b8860b}.m.head,.m.options{background:#555}" )
            sb.append( "h2{font-size:15px;margin:10px 0 6px}" )
            sb.append( "table{border-collapse:collapse;width:100%;margin:6px 0 14px;background:#fff;font-size:13px}" )
            sb.append( "th,td{border:1px solid #e2e5ea;padding:6px 10px;text-align:left}" )
            sb.append( "th{background:#f3f5f8}" )
            sb.append( "pre{background:#fff;border:1px solid #e2e5ea;padding:10px;overflow:auto;font-size:12px;border-radius:4px}" )
            sb.append( ".try{margin-top:8px}button{padding:5px 14px;cursor:pointer}" )
            sb.append( "code.path{font-family:ui-monospace,monospace;background:#eef1f5;padding:2px 6px;border-radius:3px}" )
            string res = sb.toString()
            sb.release()
            ret res
        }

        # 注：①JS 代码字符串里的 "$"（如 $ref）经 String.fromCharCode(36)
        # 运行期生成——"$" 是 SL 字符串插值前缀，字面量任何位置出现都会
        # 吞掉后续 token；②长字面量 "+" 链会截断——StringBuilder 逐段追加
        static string _pageJs()
        {
            StringBuilder sb = StringBuilder()
            sb.append( "var SPEC=null,OPS=[];" )
            sb.append( "document.addEventListener('click',function(ev){var t=ev.target;" )
            sb.append( "if(t.className==='ep'&&t.getAttribute('data-k')){show(t.getAttribute('data-k'));}" )
            sb.append( "if(t.tagName==='BUTTON'&&t.getAttribute('data-p')){tryOut(t.getAttribute('data-p'));}});" )
            sb.append( "fetch('/openapi.json').then(function(r){return r.json()}).then(function(s){SPEC=s;render();}).catch(function(e){" )
            sb.append( "document.getElementById('detail').textContent='openapi.json 加载失败: '+e;});" )
            sb.append( "function render(){var m=document.getElementById('meta');" )
            sb.append( "m.textContent=(SPEC.info&&SPEC.info.title||'API')+' '+(SPEC.info&&SPEC.info.version||'')+'  openapi '+(SPEC.openapi||'');" )
            sb.append( "var groups={};OPS=[];" )
            sb.append( "Object.keys(SPEC.paths||{}).forEach(function(p){Object.keys(SPEC.paths[p]).forEach(function(v){" )
            sb.append( "var op=SPEC.paths[p][v];var g=(op.tags&&op.tags[0])||'默认';" )
            sb.append( "if(!groups[g])groups[g]=[];groups[g].push({p:p,v:v,op:op});OPS.push({p:p,v:v,op:op});});});" )
            sb.append( "var nav=document.getElementById('nav');var html='';" )
            sb.append( "Object.keys(groups).forEach(function(g){html+='<div class=\"grp\">'+g+'</div>';" )
            sb.append( "groups[g].forEach(function(e,idx){html+='<div class=\"ep\" data-k=\"'+e.p+'|'+e.v+'\">'" )
            sb.append( "+'<span class=\"m '+e.v+'\">'+e.v.toUpperCase()+'</span><code>'+e.p+'</code></div>';});});" )
            sb.append( "nav.innerHTML=html;}" )
            sb.append( "function show(key){document.querySelectorAll('.ep').forEach(function(n){n.classList.remove('sel')});" )
            sb.append( "var parts=key.split('|');var e=OPS.filter(function(o){return o.p===parts[0]&&o.v===parts[1]})[0];if(!e)return;" )
            sb.append( "var op=e.op;var h='<h2><span class=\"m '+e.v+'\">'+e.v.toUpperCase()+'</span> <code class=\"path\">'+e.p+'</code></h2>';" )
            sb.append( "if(op.summary)h+='<p>'+op.summary+'</p>';if(op.description)h+='<p>'+op.description+'</p>';" )
            sb.append( "if(op.parameters&&op.parameters.length){h+='<h2>参数</h2><table><tr><th>名称</th><th>位置</th><th>类型</th><th>必填</th><th>说明</th></tr>';" )
            sb.append( "op.parameters.forEach(function(p){h+='<tr><td>'+p.name+'</td><td>'+(p.in||'')+'</td><td>'+(p.schema&&p.schema.type||'')+'</td><td>'+(p.required?'是':'否')+'</td><td>'+(p.description||'')+'</td></tr>';});h+='</table>';}" )
            sb.append( "if(op.requestBody){h+='<h2>请求体</h2>';var c=op.requestBody.content||{};" )
            sb.append( "Object.keys(c).forEach(function(mt){var media=c[mt];" )
            sb.append( "if(media.schema)h+='<div>'+mt+'</div><pre>'+JSON.stringify(resolve(media.schema),null,2)+'</pre>';" )
            sb.append( "if(media.example!==undefined)h+='<div>示例</div><pre>'+JSON.stringify(media.example,null,2)+'</pre>';});}" )
            sb.append( "if(op.responses){h+='<h2>响应</h2>';Object.keys(op.responses).forEach(function(st){var resp=op.responses[st];" )
            sb.append( "h+='<div>'+st+'</div>';var c2=(resp.content||{});Object.keys(c2).forEach(function(mt){var media=c2[mt];" )
            sb.append( "if(media.schema)h+='<pre>'+JSON.stringify(resolve(media.schema),null,2)+'</pre>';" )
            sb.append( "if(media.example!==undefined)h+='<div>示例</div><pre>'+JSON.stringify(media.example,null,2)+'</pre>';});});}" )
            sb.append( "if(op.security)h+='<h2>认证</h2><p>'+op.security.map(function(s){return Object.keys(s)[0]}).join(' / ')+'</p>';" )
            sb.append( "if(e.v==='get'){h+='<h2>试一试</h2><div class=\"try\"><button data-p=\"'+e.p+'\">发送</button></div><pre id=\"tryout\"></pre>';}" )
            sb.append( "document.getElementById('detail').innerHTML=h;}" )
            sb.append( "function resolve(sch,depth){if(!sch||depth>6)return sch;var rf=String.fromCharCode(36)+'ref';if(sch[rf]){var p=sch[rf].replace('#/','').split('/');var cur=SPEC;" )
            sb.append( "for(var i=0;i<p.length;i++)cur=cur[p[i]];return resolve(cur,depth+1);}return sch;}" )
            sb.append( "function tryOut(path){fetch(path).then(function(r){return r.text().then(function(t){" )
            sb.append( "document.getElementById('tryout').textContent='HTTP '+r.status+String.fromCharCode(10)+t;});}).catch(function(e){" )
            sb.append( "document.getElementById('tryout').textContent='请求失败: '+e;});}" )
            string res = sb.toString()
            sb.release()
            ret res
        }
    }
}


