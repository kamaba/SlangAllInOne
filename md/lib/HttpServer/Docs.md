# Docs.sl

> 源文件：`Docs.sl`

## class `Docs`

- **说明**：SLang/Server/Docs.sl — OpenAPI 文档 + /docs 页面 + importOpenApi（P3） 设计契约：SERVER_DESIGN.md §4.8 / §6.10 实现要点（§6.10 实例探针法）： - 样例实例 → BaseJson.fromData → JSON 树 → 逐节点映射 OpenAPI schema （string/integer/number/boolean/array/object/nullable；零反射， schema 键 = SystemObjectGetType(sample).className）； - openapi.json 手工组 TreeNode<string> 树（弱类型映射：object 节点 _value="{}"、array 节点 _value="[]"、名字为孩子键）→ BaseJson.fromTree(...).toJson() 序列化； - /docs 页面 = 自包含单文件 HTML（零外链零 CDN，wasm/playground.html 同款离线策略），读同源 /openapi.json 渲染 + GET try-it-out； - /docs 与 /openapi.json 在 start 时挂载（用户已注册同路径则让位， §6.10"用户优先"），isBuiltin 标记（不进 openapi.json 自身）； - importOpenApi：paths → 未注册 (method, pattern) 建文档路由 （isDocOnly，命中 501 ApiResult）；已注册者合并轻量元数据 （summary/tags/desc/param/security）；Router.add 对 isDocOnly 同 (method,pattern) 自动让位 + 元数据继承（§4.8 覆盖工作流）。 与设计的偏差（§16 实录）：导入的文档路由不回填 requestBody/responses 样例（样例实例无法从 JSON 反推，v1 仅轻量元数据）；ANY 路由在 openapi.json 展开 7 动词同 op；WS 路由不进 openapi.json。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static bool _hasSecurity = false` | 字段 bool（类型见签名）。 |
| 方法 | `string _dollar()` | ── "$" 单字符经 ByteBuffer 构造（"$" 是插值前缀，字面量任何 位置出现都会吞掉后续 token；36 = '$' 的 UTF-8/ASCII 码位）── |
| 方法 | `string _typeNameOf(object sample)` | ── 样例类型名（探针法 schema 键；无反射替代：系统方法取 Type）── Type.toString() = metaClass.className + 模板参数（DTO 无模板 = 纯类名） |
| 方法 | `TreeNode&lt;string&gt; _obj()` | ── 组树基元（弱类型映射：object "{}"、array "[]"、标量 = 文本）── |
| 方法 | `TreeNode&lt;string&gt; _objChild(TreeNode&lt;string&gt; parent, string key)` | 执行 _objChild(parent, key)，行为详见源实现。 |
| 方法 | `TreeNode&lt;string&gt; _arrChild(TreeNode&lt;string&gt; parent, string key)` | 执行 _arrChild(parent, key)，行为详见源实现。 |
| 方法 | `void _kv(TreeNode&lt;string&gt; parent, string key, string val)` | 执行 _kv(parent, key, val)，行为详见源实现。 |
| 方法 | `TreeNode&lt;string&gt; _probeText(string sampleJsonText)` | ── schema 探针（样例 JSON 文本 → OpenAPI schema 节点）── 样例 JSON 文本 → 独立 schema 节点（不挂接） |
| 方法 | `void _fillSchema(JsonValue v, TreeNode&lt;string&gt; s)` | 把 JSON 值的 schema 形态填进已建 schema 节点（object 标记节点） |
| 方法 | `void _registerSchema(string cls, string sampleJsonText)` | schema 登记（类名去重；首次样本胜出）；同时登记到 _schemas |
| 方法 | `string openApiJson()` | ── openapi.json 全文生成（OpenAPI 3.0.3，§6.10 骨架）── |
| 方法 | `void _opInto(RouteInfo r, TreeNode&lt;string&gt; pathObj, string verbKey)` | 单路由 → operation 节点（挂进路径对象的 verb 键下） |
| 方法 | `void _attachRequestBody(TreeNode&lt;string&gt; op, RouteInfo r, string mediaType, string sampleText, string sampleClass)` | JSON body：content/media → schema（$ref 或内联探针）+ example |
| 方法 | `void _attachFormBody(TreeNode&lt;string&gt; op, RouteInfo r, string mediaType, bool multipart)` | form / multipart body：object schema（file 字段 type:string+format:binary） |
| 方法 | `void _attachExample(TreeNode&lt;string&gt; media, string sampleJsonText)` | example 节点：样例 JSON 文本重解析 → 根改名 example → 挂进 media |
| 方法 | `void _mount()` | ── /docs 与 /openapi.json 挂载（start 时调；用户已注册同路径让位）── |
| 方法 | `void _serveDocs(SLang.Request req, SLang.Response res)` | 执行 _serveDocs(req, res)，行为详见源实现。 |
| 方法 | `void _serveOpenApi(SLang.Request req, SLang.Response res)` | 执行 _serveOpenApi(req, res)，行为详见源实现。 |
| 方法 | `void _serveNotImplemented(SLang.Request req, SLang.Response res)` | 文档路由 501 应答（importOpenApi 登记；被真实注册覆盖后不再触达） |
| 方法 | `Int32 importOpenApi(string jsonPath)` | ── importOpenApi（Apifox 导出 OpenAPI json → 路由骨架，§4.8）── 返回新建文档路由数；已注册 (method,pattern) 仅合并轻量元数据 （summary/tags/desc/param/security），requestBody/responses 样例 不反推（实例不可得，v1 偏差见类头） |
| 方法 | `void _mergeMeta(RouteInfo r, JsonValue op, string pattern)` | OpenAPI op JSON → RouteInfo 轻量元数据合并 |
| 方法 | `string _verbAt(Int32 i)` | 导入扫描的 7 动词表 |
| 方法 | `string _toLower(string s)` | 大小写折叠（标准库暂无 toUpper/toLower——Upload.sl 同款逐字节， ByteBuffer.writeU8 + toString） |
| 方法 | `string _toUpper(string s)` | 执行 _toUpper(s)，行为详见源实现。 |
| 方法 | `Int32 _sfFind(string text, string sub)` | 子串查找（测试助手同款；openapi 断言复用） |
| 方法 | `string _htmlPage()` | ── /docs 页面（自包含 HTML；零外链零 CDN）── |
| 方法 | `string _pageCss()` | 注意：超长字符串字面量 "+" 链在 Front/VM 求值中会截断（实测 ret 后仅首段字面量存活）——一律 StringBuilder.append 逐段追加 |
| 方法 | `string _pageJs()` | 注：①JS 代码字符串里的 "$"（如 $ref）经 String.fromCharCode(36) 运行期生成——"$" 是 SL 字符串插值前缀，字面量任何位置出现都会 吞掉后续 token；②长字面量 "+" 链会截断——StringBuilder 逐段追加 |
