# SLang Server 设计 · 落地实录（原 §12–§28）

> 本文档由单文件 `SERVER_DESIGN.md` 拆分而来（2026-10-27），完整收录原 **§12–§28 各阶段落地实录**（代码实况与设计的差异记录，P0 → P10 及历次重构）；章节编号与正文内容保持原样、未作改动。
> 其余部分：总览与规划（§0–§3、§8–§11）见 [SERVER_DESIGN.md](SERVER_DESIGN.md) · 语法设计（§4）见 [SERVER_SYNTAX.md](SERVER_SYNTAX.md) · 模块与机制（§5–§7）见 [SERVER_MODULES.md](SERVER_MODULES.md)。

---

## §12 P0 落地实录（2026-10-17，代码实况与设计的差异记录）

**产物**：`Server.sl`（ServerConfig/ServerError P0 子集）+ `HttpServerCore.sl`（解析/编码/keep-alive/超时守护/P0 精确路由）+ `Request.sl`/`Response.sl`（P0 子集）+ `Server.jsonc`/`Server.sp`；Std 增量 `Websocket.sl` 三参 `accept(raw, preRead, opt)` 重载；验收用例 `test/Other/NetTest/{ServerProbeTest,ServerCoreTest}.sl`（S 组端口 19371–19374）。

**探针结论（风险 #1/#15/#19 ② 全部排雷通过）**：CallClosure 双参/三参直调、object 传参带值返回、Function 字段拷局部调用全部可用；`waitTimeout` 完成→true / 超时→false 方向正确；`awaitTask` 对已死/已 cancel Task 安全返回不挂起；`spawnClosure2` 双参派发 + await 可用——P1 起按双参签名推进，无需启用 §10 风险 1 的单参降级路径。

**与设计的偏差（均为实现细节，不改变 P1+ 设计）**：
1. **HttpServerCore 为模块级静态单例**（`configure(cfg)/reset()/start()/stop()/awaitStop()/onGet/onPost/onAny/on`），非 §3 的实例形态——C VM 对跨模块引用类多实例化的实例态隔离不可靠（连续 new 多实例时 S2 连接读到 S1 的路由表，闭包零捕获 + 实参传值亦无法规避；详复盘 [2026-10-17]）；v1 单服务器语义下无功能损失，P1 门面 `SLang.Server` 按单实例收口（2026-10-25 已按设计转实例门面——`new SLang.Server( port )` 缺省 80，引擎单例语义保留，见 §19 实录）。
2. **HttpServerCore 内置 P0 精确路由**（提前于 P1 Router 落地了 method+path 精确匹配 + ANY + HEAD 视同 GET + 404/405+Allow），因引擎验收需要路由才能测 404/405；P1 Router（`{param}`/分组/优先级）替换该内部表。
3. **413/431/504/500 走优雅断连** `_gracefulClose`（closeWrite FIN → delay 50ms → 丢弃式收尾读 → close）——直接 close 在入站 body 未读完时触发 RST，HttpClient 收不到响应（设计 §6.11 未提，经验补充）。
4. **`ServerConfig.host` 空值兜底 `"0.0.0.0"`**（跨模块 string 字段默认值消费侧丢失，Int32 正常）；用户工程写 `SLang.ServerConfig()` 后应显式 `cfg.host/cfg.port`（HttpClient 显式字段先例同款纪律）。
5. **`List<object>` + as 转型替代 `List<Net.TcpStream>`**（泛型参数位禁点分类型）；`ApiResult` 类未落地前错误体由 `_errorBody()` 手工组包（键序 code→message→data 与 §6.7 一致）。
6. jsonc 路径基准 = .sp 所在目录（`Lib/SLang/Server/` 深度 5 → `outputDir` 5 个 `..`、references `../../Core`/`../../Std`）；G8 白名单生效。

**下一步（P1）**：`SLang.Server` 门面（包装静态 HttpServerCore）+ `Router/RouteInfo/RouteGroup`（`{param}` 提取/优先级/冲突检测/DuplicateRoute）+ Request/Response 全表（pathParam/query 族 + json/jsonOk/jsonFail/redirect）+ `ApiResult` + BodyParser（json/form/bin 分流）+ WS 路由升级（`app.websocket` + `WebSocketStream.accept(c, preRead, opt)` 接线）+ `WsSession`/`WebSocketServer`；用例迁入 `test/ExpendTest/Server/`（§9）。

---

## §13 P1 落地实录（2026-10-17，代码实况与设计的差异记录）

**产物**：新增 `Router.sl`（RouteInfo/RouteGroup/Router 匹配引擎）、`ApiResult.sl`、`BodyParser.sl`、`WebSocketServer.sl`（独立形态 + WsSession/_WsSessions 注册表）；扩展 `Server.sl` 门面（on* 动词家族/websocket/use/run/start/stop/checkDuplicate）、`Request.sl`（pathParam 族/query 族/body 三形态/bodyJson）、`Response.sl`（链式 + jsonOk/jsonFail/html/redirect）；验收用例 `test/ExpendTest/Server/ServerP1Test.sl`（T1–T8，端口 19401–19408）+ `ProjectTest.jsonc`/`ProjectTest.sp` 登记（references 增 `out/export/SLangServer`）。

**验收**：ServerP1Test T1a–T8c 共 42 项全 OK；ExpendTest 全量 293/293 OK；NetTest 104/104 OK（C VM 网络层改动 P0 回归）。

**与设计的偏差 / 实况要点**：
1. **Router 匹配 = best-static 选择**（非设计 §6.2 的"注册序优先"）：同路径下静态段多者优先、同静态段数先注册优先；`{param}` 参数段以 `RouteInfo._paramSegIdx`（参数名→路径段下标对位表）提取，不依赖参数声明序。静态段优先保证 `/user/new` 不被 `/user/{id}` 抢走。
2. **DTO 序列化契约**：`req.body<T>()` / `SystemJsonFromData` 只展开 `@Serializable()` 标注类的成员——P1 用例 DTO 漏标注时 json 解析走 toString 嫁接（`"Object:92944154"`）假成功形态；文档须明示（`md/lib/Core/ProtocalBuffers.md` 先例）。
3. **WS 握手交接重建**：HttpServerCore 分流到 WS 路由时 HTTP 解析已消费请求行+头，`WebSocketStream.accept` 无法重读 socket——用已解析值重建最小握手请求（`GET <path>[?query] HTTP/1.1` + Upgrade/Connection/Version/Key 四头）灌 `preRead` 参数（§4.6 形态 A 接线点）。
4. **WebSocketServer 独立形态会话收尾**：`_runSession` 的 catch 路径（stop 强制关闭 / IO 异常）必须补 unregister + onClose 回调——漏掉则 `sessions` 计数泄漏、`onClose` 不触发（T7e 用例抓出）。
5. **C VM 修复：net_slot_alloc 单调推进分配**（`csimple_lang/src/lib/os/sys_net.c`）：原实现槽位下标即 sid、close 后立即复用——被 cancel_wait 唤醒的僵尸 accept 协程重执行系统调用时旧 sid 命中复用槽位上的新 socket，抢走新一代监听器连接（T7 连接被抢根因）。修复 = `g_net_slot_hint` 游标单调找空槽、全表满才回收；复盘见 `md/ai/troubleshooting/04-concurrent-net.md` [2026-10-17]。
6. **Front 修复：闭包形参泛型方法调用 NRE**（`MetaCallNode.cs` / `MetaMemberFunction.cs`）：handler 闭包形参作调用对象调 `req.body<T>()` 时 realMetaType 判空回退 + 泛型展开链 mc 兜底；复盘见 `md/ai/troubleshooting/01-front-compile.md` [2026-10-17]。
7. **SL 语言约束落地记录**：跨文件类型引用须带 `SLang.` 前缀（RouteGroup/WebSocketServer/Router）；`this.x` 不可直接作方法实参（须先赋局部别名）；`isnot` 关键字已有实现但无用例（本模块未用）。
8. **响应写出契约补充**：handler 已暂存响应后抛异常 → 引擎照常写出暂存响应（非 500）；未响应才 500（§6.11 语义细化）。

**下一步（P1.5 上传）**：multipart 解析器 + `UploadedFile`（saveAs/saveInto/安全剥离）+ `maxUploadBytes/maxFileBytes`；验收 = §8 P1.5 行。

---

## §14 P1.5 落地实录（2026-10-20，代码实况与设计的差异记录）

**产物**：新增 `Upload.sl`（UploadedFile 上传句柄）；扩展 `BodyParser.sl`（multipart/form-data RFC 7578 全量解析：boundary 提取 / part 头 / 普通字段并入 form 表 / 文件 part / filename 安全剥离 / `_MultipartBody` 内部结果类）、`Request.sl`（file/files/fileCount 文件族 + `_ensureMultipart` 惰性解析 + form 族并入 multipart 字段）、`HttpServerCore.sl`（body 上限分流 maxUploadBytes / multipart 派发前即时解析 400·413 / `_releaseRequest` 请求级资源回收）、`Server.sl`（ServerConfig 增 maxUploadBytes=100MB / maxFileBytes=50MB）；`Server.jsonc` 登记 Upload.sl + UploadedFile struct；验收用例 `test/ExpendTest/Server/ServerP15Test.sl`（T1–T7，端口 19411–19413，原始 TCP 手搓 multipart 构造——HttpClient body 为纯 string 不支持二进制，multipart 必须原始客户端）。

**验收**：ServerP15Test T1–T7 共 10 项全 OK；ServerP1Test T1–T8 共 42 项回归全绿（ExpendTest 全量零 FAIL）。

**与设计的偏差 / 实况要点**：
1. **multipart 即时解析时点 = handler 派发前**（引擎连接协程内 `req._ensureMultipart()`，§6.5「构造期」语义的等价落点——Request 构造发生在路由匹配后，引擎在 spawnClosure2 之前即时触发，保证单文件超限 413 / boundary 缺失 400 走协议层优雅断连，handler 永不见坏包）；`Request._ensureMultipart` 保持惰性幂等（重复调用返回缓存，非 multipart 格式恒 0）。
2. **form 族并入**：multipart 普通字段直接挂进 `_ensureForm` 的缓存表（值不解码，§6.4 直传语义），form/formInt/formBool/hasForm/formKeys 对 urlencoded 与 multipart 统一生效。
3. **`upload_<序号>` 序号 = 文件表下标**（`_safeFilename(raw, seq)` 的 seq 取 `result._files.length`）——多 part 请求中第 N 个空名文件生成 `upload_<N-1>`，非全局从 0 计。
4. **saveInto 目录拼接统一 `/`**（Windows 侧同样接受，不引 Path.combine 免跨模块点分调用）；重名改名 `stem(N)ext` 含点扩展保原大小写。
5. **SL 语言坑两枚**：① `data` / `base` 是关键字不能作参数/变量名（UploadedFile 构造参数 `data→content`、saveInto 局部 `base→dirBase`）；② `bool.toString()` 输出 **"True/False"**（C# 风格大写开头），测试断言小写 "true" 会假失败。
6. **Front 已知限制（记录备修）**：闭包方法体内 `List<SLang.UploadedFile>`（typealias 或点分类型均触发）在模板实例化链 NRE（`MetaClass.AddMetaTemplateClassByMetaClassAndMetaTypeList`，与 P1 复盘 6 同族）；**链式访问 `req.files("x").length` 正常**——测试侧以链式 + 字段区分规避，Front 修复后可补强逐元素用例（`ps[0].filename`）。
7. **宿主修复（附带产出，`CSimpleVMTest/Program.cs`）**：`CopyModuleIntoPackage` 增 `StageReferencedModules`——解析主模块 `moduleReferences`，非系统库引用（ExpendTest→SLangServer）的导出产物（两处标准导出树 `SlangAllInOne\out\export\<名>\` / `SlangAllInOne\SLangCore\out\export\<名>\`）连带拷入包 `<pkg>\<名>\`；Core/Std/Math 走包内 `<exe>\lib\` 直查不拷。**背景**：此前引用模块不跟随，C VM 对落空引用**静默 skip**（仅 VM.txt Warning、退出码 0），跨模块调用全部落到空壳方法——`ServerConfig` 字段全空 / `Server.start` no-op / 测试挂死后 VM 判定无在途 IO "成功"收尾，极具迷惑性（本次 P1.5 验收首跑即踩，最小复现 + 同一 slb 换目录运行二分定位 ~2 小时）；复盘见 `md/ai/troubleshooting/06-build-engineering.md` [2026-10-20]。

**下一步（P2 管道插件与流式）**：中间件管道（`SLang.Next` + nx.go()）+ `ServerPlugin` 基类 + logger/cors/staticFiles 内置插件 + 流式三件套（`StreamWriter` chunked / `SseWriter` SSE / `sendFile`）+ `wsEvents` 糖 + 通配路由 `{path*}`；验收 = §8 P2 行。

---

## §15 P2 落地实录（2026-10-20，代码实况与设计的差异记录）

**产物**：新增 `Plugin.sl`（`Next` 放行令牌 / `_Pipeline` 管道执行器 / `ServerPlugin` 插件基类（onInstall·onStart·onStop·onWsOpen·onWsClose 钩子）/ `_PluginHost` 静态宿主（`List<Function>` 中间件表 + `List<object>` 插件表 + 钩子广播））、`Plugins.sl`（`logger()/cors()/staticFiles(root)` 内置插件）、`StreamIo.sl`（`StreamWriter` chunked write·writeBytes·flush·close / `SseWriter` send·sendEvent·comment·close）；扩展 `Response.sl`（`stream()/sse()/sendFile()/file()` + `_direct` 直写通道 + `_streamWriter` 绑定）、`HttpServerCore.sl`（管道执行接入（§6.9）+ 流式三态写出分支 + 管道异常/契约违约 500 兜底）、`Router.sl`（`{path*}` 通配尾段——仅识别最后一段，匹配剩余全部段）、`Server.sl` 门面（`use(Function)`/`use(ServerPlugin)`/`wsEvents(path)`）；`Server.jsonc` 登记 Plugin/Plugins/StreamIo 三文件；验收用例 `test/ExpendTest/Server/ServerP2Test.sl`（T1–T4 共 24 项，端口 19421–19424，原始 TCP 手搓收发）。

**验收**：✅ 2026-10-20 全绿——ServerP2Test T1 管道 5 项（短路 401 / onion 序 + userData 传值 / 404 过管道 / onInstall 立即性 + onStart / onStop）、T2 内置插件 6 项（CORS 预检 204 / 静态 txt·html MIME / miss→404 带 CORS 头 / 穿越 403 / 路由+静态共存）、T3 流式 5 项（chunked 编码+终止块 / 引擎 close 回退 / keep-alive 续用 / SSE 线格式 / 流式连接超时豁免）、T4 5 项（sendFile 160KB 往返 / 缺失 404 / file() 附件头 / 通配多段·单段·空段 / wsEvents 开·收·关）全 OK；P1 42 项 + P1.5 10 项回归全绿（ExpendTest 全量零 FAIL、测试输出零调试残留）。

**与设计的偏差 / 实况要点**：
1. **onInstall() 无参**（设计 §4.7 `onInstall(app)` 传实例）——P1 起门面为静态形态（§12 复盘 ①），插件经 `SLang.Server.*` 静态调用注册；Plugin.sl 类头注记已载。
2. **onion 执行形态 = 连接协程内联同步嵌套**：`Next.go()` 直调 `_runFrom(idx+1)`，后置环在 handler 协程 `awaitTask` 返回后自然回程；中间件自身可 await（§4.7 契约兑现）。SL 无方法引用 → 框架持环索引逐环构造 `Next`（§6.9 设计原样落地）；`nx.go()` 幂等（重复调用 no-op 防双派发）。
3. **未匹配请求同样过管道**（404/405 = 尾环应答模式）——staticFiles/CORS 预检语义依赖此；管道正常返回但零响应 = 契约违约 500 + 断连；管道异常四分支：流式头已发→兜底终止块+断连 / sendFile 半截→断连 / 已缓冲完成→照常写出（首个响应胜出）/ 未响应→500。
4. 🔥 **C VM 修复（本次核心附带产出，`csimple_lang/src/vm/runtime/vm_runtime.c` OpCode_CastClass Step 6）**：管道首验 T1/T2 全 500，根因链——`_middlewares` 底层 `Array<Function>` 元素槽 etype=Class(20) → `List<T>._getItem_` 方法体 `ret SystemArrayGetValueThis(...) as T` 被 Front 内联发射 CastClass（目标 = 模板参数节点，运行期绑定 Core.Function）→ VM 侧 Step 6 的 etype 闸只认 `EVMType_Object`（**全库 30+ 处 Object||Class 并列检查的唯一例外**），Class etype 闭包引用被吃掉 push null → `mw==null` → no-response 500。**修复双改动**：① 闸放宽 `Object||Class`（Class etype 值必经类型化引用槽装载、持真实对象指针，非 scalar union 别名——闸本意只拦 raw scalar）；② 闭包对象特判：闭包载体是无绑定 RuntimeType 的裸 payload VMObject（`vm_object_get_runtime_type` 返回 NULL，extends 检查不可用），故 source_rt==NULL 时以 closure magic（'CLSR'/native FFI 两族）识别 + 目标类名双形态（`"Function"`/`"Core.Function"`——RuntimeClass 名带命名空间、与 payload 侧 def 类型名形态不同）放行。P1/P1.5 的 `List<RouteInfo>` 等真类实例全绿 = extends 路径本就正常，差异全在闭包无 rt；取证过程（IR 反查定位发射点 + 三层插桩对账）复盘见 `md/ai/troubleshooting/03-vm-runtime.md` [2026-10-20] 条。
5. **staticFiles 仅 GET 直出**（HEAD 放行——sendFile 直写路径未做 HEAD 摘除，已知限制，后续随 P5 打磨补）；MIME 按扩展名映射、未知名 `application/octet-stream`。
6. **流式连接豁免 `handlerTimeoutMs`**（T3e 专项验证）：chunked/SSE 连接不参与超时收割——否则长推送必被 400ms 级超时杀死；普通 handler 超时行为不变（P0 504 路径）。

**下一步（P3 文档+认证）**：`OpenApiBuilder` + `/docs` + `/openapi.json` + `importOpenApi`（未注册路径文档路由 501 → onGet 覆盖工作流）+ `bodyLimit/requestId/auth` 插件 + `SLang.Jwt.decode` + `maxConnections`；验收 = §8 P3 行（Apifox 实际导入 + securitySchemes 自动配 Auth）。

---

## §16 P3 落地实录（2026-10-21，代码实况与设计的差异记录）

**产物**：新增 `Docs.sl`（openapi.json 生成（探针法 schema：样例实例 → fromData → JSON 树 → 逐节点映射 string/integer/number/boolean/array/object/nullable；手工组 TreeNode 树 + BaseJson.fromTree 序列化）/ `/docs` 自包含 HTML 页面（零外链零 CDN，同源 fetch openapi.json 渲染 + GET try-it-out）/ `importOpenApi`（文档路由 isDocOnly·501 + 覆盖让位 + 元数据合并））、`Jwt.sl`（`JwtClaims`（claim/put/subject/expiresAt/expired）+ `Jwt.decode`（三段定位·base64url 反归一·payload 解析·Map 载体）；零新依赖）；扩展 `Router.sl`（`RouteInfo` 结构化文档元数据（docParams/docForms/docBodyText/docResponses/security/isDocOnly/isBuiltin + 链式 `param/requestBody/formField/uploadField/response/responseAs/security`）+ `RouteParam`/`RouteResp` 记录类 + `findExact` 精确查找 + `add` 文档路由让位继承）、`Plugins.sl`（`_BodyLimitPlugin`（contentLength 超限 413）/ `_RequestIdPlugin`（Guid → X-Request-Id）/ `_AuthPlugin`（三挂法单类：通用回调收 req·Bearer→Jwt.decode→req.auth=JwtClaims·API Key 自定义头；`.skip()` 白名单·`.ws(true)` token 接管（onWsOpen 查询参数校验失败关会话）；401 附 `WWW-Authenticate: Bearer`（RFC 6750，仅 Bearer 模式））+ 工厂 `bodyLimit/requestId/auth/authBearer/authApiKey`）、`Plugin.sl`（`ServerPlugin` 基类增 `skip/ws` 链式占位（子类 override，返回类型统一 ServerPlugin——跨模块链式调用按基类签名决议））、`HttpServerCore.sl`（start 挂载 /docs + /openapi.json（`_docsEnabled` 开关，reset 恢复默认开）+ maxConnections 超限 503 协议层应答 + `_errorBody` 503）、`Server.sl`（ServerConfig.maxConnections=1024 + 门面 `docs(bool)`/`importOpenApi(path)`）；`Server.jsonc` 登记 Docs/Jwt + struct 增 RouteParam/RouteResp/Jwt/JwtClaims；验收用例 `test/ExpendTest/Server/ServerP3Test.sl`（T1–T6 共 33 项，端口 19431–19435）。

**验收**：✅ 2026-10-21 全绿——T1 openapi 生成 7 项（3.0.3 骨架+servers / paths+summary+tags / path 参数 in/required/type / requestBody $ref+schema 复用+example / 嵌套 DTO properties / securitySchemes 双定义+operation security / form 字段 urlencoded）、T2 docs 3 项（自包含页 / 用户让位 / docs(false) 关闭）、T3 auth 10 项（Bearer 四态：缺失 401+头·坏 token·好 token claims 透传·skip 放行 / API Key 三态 / 通用回调三态）、T4 Jwt 5 项（claims 读取 / exp 未来 false·过去 true·缺失恒 false / 坏格式三连 null）、T5 importOpenApi 5 项（计数 / 501 / 共存 / 覆盖让位 / 元数据继承）、T6 1 项（maxConnections 首连接 200·次连接 503）全 OK；P1 45 + P1.5 10 + P2 24 回归全绿（ExpendTest 零 FAIL）。

**与设计的偏差 / 实况要点**：
1. **链式 .skip()/.ws() 上移基类**：静态工厂返回 `ServerPlugin`（跨模块子类上行赋型纪律，§12 复盘 ①）导致 `.skip()` 在基类上不可见（MetaCore 链解析失败）——`ServerPlugin` 基类加 no-op 占位、`_AuthPlugin` override（返回类型必须一致），非 auth 插件调用为 no-op。
2. **探针法 schema 键 = `Type.toString()`**：设计的 `SystemObjectGetType(sample).className` 实为 `Type.metaClass.className`（两跳，Meta 层不通过）——改用 `ty.toString()`（内含 className + 模板参数展开，DTO 无模板 = 纯类名）。
3. **`BaseJson.fromTree` 收 Tree 不收 TreeNode**：根节点需 `Tree.setRoot(node)` 包一层。
4. **importOpenApi 只回填轻量元数据**：summary/tags/desc/param/security（样例实例无法从 JSON 反推，requestBody/responses 不回填——v1 偏差已注记类头）；ANY 路由在 openapi.json 展开 7 动词同 op；WS 路由不进 openapi.json。
5. 🔥 **Front 三坑规避实录（本轮排障主战场，SL 侧全数绕开、未改 Front）**：
   - **`$` 是字符串插值前缀**（md/syntax/keywords.md §3.5）：字符串字面量**任何位置**出现 `$`（含 `"$"+` 拆分拼接）都会吞掉后续 token——`"$ref"` 键值对改 `Docs._dollar()`（ByteBuffer 构造 "$" 单字符）拼接，JS 侧 `sch.$ref` 改 `String.fromCharCode(36)+'ref'` 运行期生成；
   - **长字符串字面量 "+" 链求值截断**：`ret "段1" + "段2" + ...` 跨行链实测**仅首段字面量存活**（pageJs 21 字符 = 首段；变量链 5 段/局部累加 20 段均正常——字面量链特有）；`_htmlPage/_pageCss/_pageJs` 全部重写为 `StringBuilder.append` 逐段追加（一次通过）；
   - **关键字撞名**：`out`（变量定义名禁用；`string out = ...` 报 NodeStructParseN `'=' 后缺少赋值表达式`——报错信息与真实原因相距甚远）、`params`（变参关键字，作局部变量名同样炸）——改名 `res/paramsNode/bufOut`；
   - 另两处编译期纪律：`ret 方法调用()` 跨行续 `+` 链中段裸标识符会被误判类名（拆局部变量）；`for` 三段分隔符是**逗号**不是分号（`for i = 0; i < n; i++` 静默 NRE，无报错线索）。
6. **maxConnections 503 = 协议层应答**：accept 循环内 `_writeSimple(503) + _gracefulClose`，不进管道不占连接协程（§6.11 精神）；keep-alive 占住名额的连接在 stop/超时释放后恢复。

**下一步（P4.5 直接 await 糖）**：§7.5——`await` 后跟返回非 Task 的调用自动包 spawn 脱糖（判别下沉 IR/Meta 层，§7.3 调研项先行）；验收 = §8 P4.5 行（透传/聚合/Task 变量三条回归红线）。

---

## §17 P4 落地实录（2026-10-24，代码实况与设计的差异记录）

**产物**：C VM 新增 `vm/runtime/attribute/vm_route_attribute.c`（路由表：`s_route_append` 方法条目（verb 大写/path/method_id）+ `s_prefix_append` 类前缀表（class_id→prefix）+ `_enter_` join（method_id→RuntimeClass→前缀拼接→"verb|path|class|method" 行）+ 查询四接口（count/line/class_id/method_id，join 前一律空响应）+ 10 个 attribute handler（On 动词家族 8 共享 collect（名→verb 映射表）/ `@Route` 双参显式 verb（缺省 ANY·大写化，enter/exit 挂此条目）/ `@OnRoute` 类级 collect_class（六字段结构第五 NULL 教训：collect_class 必须显式写满））；`vm_runtime_attribute.c` 扩展 collect 方法级+类级双扫描（stage==Preload 且 handler 名匹配分发）+ `vm_runtime_attribute_reset` 集成路由表重置；`server_system_method.c` 三系统方法（`ServerGetPreloadRouteCount` / `ServerGetPreloadRouteLine` / `ServerBridgeCall`——new 控制器实例 + VM 级直调目标方法）；SL 层 `RouteAttrs.sl`（10 属性类收编自 Std/Net/Route.sl，原文件删除）+ `Server.sl` `usePreloadRoutes()`（拉表→RouteInfo→Router，重复调用幂等返回 0）+ `Server.jsonc` systemCalls/struct 三处登记；R6 CMakeLists+vcxproj 登记零错误零警告；验收用例 `test/ExpendTest/Server/ServerP4Test.sl`（T1–T3 共 13 项，端口 19441）。

**验收**：✅ 2026-10-24 全绿——T1 路由 9 项（preload count==6 / OnRoute prefix join / 每请求一实例（两次请求实例不同）/ @Route("DELETE") / plain OnGet / OnAny 两动词命中 / 动态注册共存 / 404 / 405+Allow）、T2 异步 2 项（await+delay 200 / 慢 handler 超时 504）、T3 幂等 2 项（二次拉取仍 6 条 / duplicate fail-fast）全 OK；ExpendTest 全量（P1 45 + P1.5 10 + P2 24 + P3 33 + P4 13 + 其余全套）回归零 FAIL、exit 0。

**与设计的偏差 / 实况要点**：

1. **🔥 根因定位链（R12 插桩纪律实录，11 FAIL → 0）**：首轮回归 11/13 FAIL。逐层排除：① Front 契约链实锤完好——导出 json 中类级 `@OnRoute`（stage=2 targets=1）与方法级 `@OnPost`（stage=2 targets=16、methodId 非零）全数正确，slb/json 同秒生成排除旧包，UVarInt 负数位模式编码往返无损（C# `(long)(uint)value` ↔ C `(int32)(uint32)(uint64)v` 对称）；② C VM 三处插桩（collect 统计/append 丢弃原因/enter 无条件）重建重跑——collect 完美（6 方法+1 类前缀全 matched=6/1，handlers=12）、append 零丢弃（routes=6 prefixes=1）、**enter joined=0**：断点锁定 `find_runtime_class_by_method_id` 恒 NULL。
2. **🔥 根因：`declaringTypeFullName` 短名 vs 类 `fullName` 全名**——Front 导出方法字段的 `declaringTypeFullName` 为**短名**（`"P4AdminController"`，甚至 Core.Object.refEquals 也是 `"Project"`——该字段整体不可靠），而类 `fullName` 带命名空间前缀（`"ProjectTest.P4AdminController"`）；`sl_runtime_assembly_find_class_by_full_name` 全等比较 → **owner_class 恒 NULL** → `method_entries[].runtime_class=NULL` → P4 join 全灭。现有调用链未炸的原因：方法调用走扁平 `method_id_hash`、类方法绑定走 `bind_class_methods`（类内嵌 `non_static_method_list[].id` 全名 id），均不依赖该字段——只有 P4 路由 join 首次消费它。
3. **修复：本模块短名回退**（`sl_runtime_assembly.c` 方法注册循环）：全名匹配失败且 declaringTypeFullName 非空时，**限定本模块 class_list** 按 `cls->name` 短名回退（Front 同模块类名唯一约束；不跨模块避免歧义）。仅救 NULL：已匹配成功的路径（如 Core 宿主类 "Project"）零影响。副作用边界核实：`runtime_class_add_method` 与 `bind_class_methods` 同表且 bind 先 clear 再 rebind（enter_all 之后跑），owner_class 唯一持久效果即 `method_entries[].runtime_class`——P4 join / array·ffi·coroutine 系统方法 host_rc 同获更正确数据。json 中另有的 `declaringClassId` 字段（数值正确，=-998246793 与类 id 一致）C 模型未解析，彻底根治需 Front 编码+C 解码双端扩字段并全量重编 slb，留作后续演进项。
4. **诊断插桩已收敛**：P4DBG 三处临时日志全部移除，保留 join 成功统计日志（joined_count>0 门控）。
5. **跑法备忘**：回归命令 `csimple_lang.exe run --no-banner <module.json>`（cwd=ExpendTest，Sqlite3Test 资源相对路径要求）；VM 日志在 `csimple_lang\build\logs\VM.txt`（cwd 相对）。

**下一步（P5 打磨）**：前缀树路由 / 请求侧流式（`r.streamBody` + `HttpBodyReader` 边收边落盘上传） / Range 断点续传 / 主动心跳 / `rateLimit` 插件 / `SLang.Jwt.sign/verify`（HS256，前置依赖 = 标准库 crypto 哈希原语）/ TLS 服务端评估；验收 = §8 P5 行（基准 + 压测）。

---

## §18 P4.5 落地实录（2026-10-25，代码实况与设计的差异记录）

**产物**：SL 层 `Lib/Core/Coroutine.sl` 增标记方法族（`__awaitCall( object )` 换绑标记 + `__awaitSpawn0..3( Function, object... )` 非直等执行体：`awaitTask( spawnClosureN( f, 实参 ) )`）；Front 三处——`Parse/StructParseToSyntax.cs` await 分支（操作数为调用形态且非函数值变量（判据与 spawn 分流一同源 `IsLocalScopeDefineName`）时发射 `Coroutine.__awaitCall( <调用原样> )`，其余形态维持 `awaitTask`）、`Core/MetaCallNode.cs`（internal `SetAwaitSugarBinding` 换绑 setter）、`Core/MetaCallLink.cs`（`TrySwapAwaitSugarMarker` 换绑核心 + `FindCoroutineMethodByArity`/`GetFirstParamMetaClass` 辅助，挂在 `AddVisitNodeList` 的 MemberFunctionName 分支顶部）；`Log/LID.cs` + `ErrorDefinitions.csv` 增 21480（糖不支持目标/超 3 参）；验收用例 `test/ExpendTest/Server/ServerP45Test.sl`（T1–T3 共 13 项）。

**验收**：✅ 2026-10-25 全绿——T1 直等 6 项（静态 0/1/3 参（`__awaitSpawn0..3` 全档）/ 实例方法（receiver→方法引用，this 绑定验证 mul=10×5）/ 目标体内 `delay(120)` 真挂起后取回 / void 目标副作用）、T2 三红线 3 项（返回 Task 的调用**透传不回归**（`makeSlowTask( 7 )` 与 `httpGetAsync` 同「调用形态 + Task 返回」类型学通道）/ 显式 spawn `waitAll2` 聚合不回归 / Task 变量基础形态不回归）、T3 边界 2 项（函数值变量调用保守路径（`function mkt = ServerP45Test.makeSlowTask` 方法引用 + 中间 Task 变量）/ 直等+透传+变量三形态混用）全 OK；ExpendTest 全量零 FAIL；BaseTest OK=679 FAIL=26 与 2026-10-23 既有基线（Monitor P5/P6 9 项 + CoroutineTest 5 项 + TupleTest 10 项 + P6 debug 2 项）**逐条完全一致零新增**；MathTest/NullFastTest/SpecialTest/BenchMark exit 0。

**与设计的偏差 / 实况要点**：

1. **实现形态 = 换绑标记，非设计倾向的 IR/Meta 判别下沉**：调研发现「方法引用」特性（2026-10-18）+ C VM `spawnClosure` 的方法引用专用通道（`vm_sys_coroutine_spawn_method_ref`，P4 落地时同源扩展）已提供全部建材——**零闭包合成**方案成立：parse 层发射单实参标记调用 → MetaCore 在 visit 构建前（类型已知点）换绑目标函数指针 + 重建实参集合。比设计的「提升无参包装闭包 + spawnClosure0」更优：实参在 **await 点立即求值**（原设计的包装闭包路径延迟到协程首跑），且无闭包合成成本。IR 层零改动。
2. **Task 判定基准 = `awaitTask` 首参类型**（`FindCoroutineMethodByArity` 权威查找 + `ReferenceEquals` 同 ref 壳实例比较 + 名字兜底），免按名查找的跨模块壳类失配。
3. **换绑幂等性**：只改 Meta 层绑定（`m_MetaFunction`/`m_MetaInputParamCollection`），词法/语法树不动——重解析时 `CreateCallNode` 从原始术语自然重建（标记重现，再次换绑）；换绑后不再是标记名，重复触发自然短路。
4. **spawn 分支的内层改造**：实参调用链 visit 列表**末位 MethodCall 原位换 MethodReference**（receiver visit 节点不动——实例引用 receiver 留栈供 `NewMethodRef` 弹出，静态引用前置 MetaClass 访问节点无栈值，与自然方法引用形态完全一致）；方法引用表达式以新壳 `MetaCallLinkExpressNode( innerLink )` 作为新实参集合首参（返回类型缓存从零重算 = 引用值类型 `FunctionSignatureMetaClass`）；原实参表达式（上游已解析）原样提升——IR 发射即在 await 点求值。
5. **边界与降级**：目标为 get/set/构造/模板方法或实参 > 3 → **编译期 Error 21480**（VM 方法引用 spawn v1 仅固定 0..3 参，变长形态拒绝）；实参非调用链 / 系统调用 / 类型未知 / 函数值变量调用 → **留标记兜底**（`__awaitCall` 函数体 = `awaitTask( v as Task )`，运行期语义与旧脱糖一致：同步求值 + 直等，null → awaitTask 报错路径不变）。函数值变量调用的静态签名类型（FunctionSignature）与 Task 形参不兼容是**类型系统既有局限**（`awaitTask` 严格 Task 匹配），非本糖回归——用例 T3a 已注记并用中间 Task 变量承载。
6. **C VM / IR / 导出格式零改动**：本阶段纯 Front（Parse + MetaCore）+ Core 库（Coroutine.sl，需重编 Core.module.slb 并刷新消费工程 lib）。ExpendTest lib 刷新 + 全量重编后 C VM 直接跑通。
7. **跑法备忘**：`compile-tests.ps1 -Tests a,b,c` 的 `-File` 传参只绑首个（PS5.1 数组参数限制）——多套件用 `-Command` 形式；MathTest/SpecialTest 的 TestMap Module 路径与实际导出目录（`test\<套件>\export\...`）失配致 fresh 检查误报 FAILED，产物实际已刷新（脚本层既有问题，非编译失败）。
8. **文档同步**：`md/syntax/coroutine.md` §4 关键字表 + §4.2 直接 await 糖节（三分支规则表 + 边界警示）重写；`md/syntax/function.md` VM 侧注更新（协程 spawn 例外——方法引用经专用通道支持，此前「不支持」表述已过时）；本文件 §8 P4.5 行打勾 + 本实录。

---

## §19 实例门面转换实录（2026-10-25，静态门面 → 设计目标实例形态）

**背景**：P0-P4 落地期间门面曾收口为静态形态（§12 复盘 ①），用户点名回归设计目标形态（§0/§4.1/§4.9）——`SLang.Server` 须 new 出来，构造带端口，缺省 80。本次为纯 API 形态重构，功能零增减。

**产物**：`Server.sl` 重写为实例门面（423 行）——双构造 `_init_()`（缺省 80）/ `_init_( Int32 port )`（构造期经 `HttpServerCore.configure` seed 默认配置，start 前可改）；`public get ServerConfig config()`（读引擎 `_cfg` 引用直返，start 前直改字段生效，null 兜底重 seed）；`configure( cfg )`（全量覆盖 + `this.port` 同步）；`start()/start( port )/run()/run( port )/stop()/awaitStop()/reset()/isRunning`；路由族 `onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny/on`（返回 RouteInfo）+ `group( prefix )`；`use( Function )/use( ServerPlugin )`；`websocket( path )/wsEvents( path )/sessions( path )/broadcast( path, text )`；`docs( bool )/importOpenApi( file )`。`HttpServerCore.sl` 增引擎级静态通道 `sessions( path )`/`broadcast( path, text )`（闭包零捕获纪律下协程内取会话/广播的唯一通道）；`Plugins.sl` 插件 onInstall 自注册改走 `HttpServerCore` 静态；`Plugin.sl`/`RouteAttrs.sl` 类头注记同步。

**验收**：✅ 2026-10-25 全绿——模块重导（`CompileStdlib` 显式工程路径模式 → `out\export\SLangServer\` slb+json 双产物，slb mtime fresh 核验）后 ServerTest 联合宿主全量：P0 探针 + P0 引擎 + P1 + P1.5 + P2 + P3 + P4 + P4.5 八套件全部 OK、零 FAIL、exit 0（用例明细见 §8 对应行）。

**与设计的偏差 / 实况要点**：

1. **实例门面是薄壳，引擎层维持模块级静态单例**：`Server` 实例仅持 `public Int32 port`，全部状态（配置/路由/中间件/WS 会话）仍在 `HttpServerCore` 模块级——C VM 多实例实例态隔离不可靠的结论（§12 复盘 ①）未变，v1 单 VM 单服务器语义，跨实例共享路由/中间件/会话；`this.port` 只作构造记忆与便捷覆盖的落位点。
2. **`reset()` 只清路由不清配置**（引擎原语义保留）——推论两条：① 同端口重新装配可省略重复 configure（`app.stop(); app.reset()` 后直接重注册路由再 start）；② 同方法内端口切换用重赋值重 seed：`app = SLang.Server( newPort ); app.reset()`（P3 t3Auth 三段端口切换即此形态）。
3. **测试改写五条转换模式**（P1 45 处 + P1.5 13 处 + P2 19 处 + P3 35 处编辑；P4 本就实例形态零改动）：
   - 纯配置段：`cfg = ServerConfig(); cfg.port = X; SLang.Server.configure( cfg ); reset` → `SLang.Server app = SLang.Server( X ); app.reset()`；
   - 带额外字段：`SLang.ServerConfig cfg = app.config; cfg.字段 = V`（getter 返回引擎 `_cfg` 引用，直改即生效）；
   - 路由/生命周期：`app.onXxx( path, fn ); app.start( PORT ); app.stop()`（**保留 `start( port )` 显式端口便捷形态**，测试用它自证端口语义）；
   - 闭包内取会话/广播：`SLang.HttpServerCore.sessions( path )` / `SLang.HttpServerCore.broadcast( path, text )`（闭包零捕获，不可引用 `app` 实例）；
   - 同端口重复 configure 块整体省略（推论 ① 的直接应用，P3 t2DocsPage T2b/T2c 段）。
4. **`config` getter 双形态调用**：`app.config`（无括号）与 `app.config()`（带括号）均合法，测试统一用无括号形态。
5. **发布树 `publish\release\SLangServer.module.slb` 未随本次刷新**（12:04 旧产物）——测试消费链走 `out\export\` → 宿主 `StageReferencedModules` 拷入包目录，本次已随测试运行自动刷新 `package\win32-debug\SLangServer\`；独立发布产物待下次 publish/pack 时重打。

**下一步（P5 打磨）**：同 §17（前缀树路由 / 请求侧流式 / Range / 心跳 / rateLimit / Jwt.sign·verify / TLS 评估）。

---

## §20 P5 落地实录（2026-10-26，代码实况与设计的差异记录）

**产物**：

- **前缀树路由**：`Router.sl` 重构——`_RouteNode`（静态边 `Map<string,object>` + 参数边 `_RouteNode _param` 共享 + 四表：`_routes`/`_wsRoutes`/`_wild`/`_wsWild`）替代 v1 双线性表；注册经 `_attach`/`_descendBuild` 挂树，匹配经 `_collect`（DFS 沿段下降，每层至多静态+参数两条分支）+ `_pickBest`（静态段多者优先 / 同数 `_seq` 注册序平局裁决）；`checkDuplicate` 改树遍历 `_dupScan`（同 pattern 必挂同节点，节点内双循环等价全表分组比较）；Docs 消费侧新增 `Router.allRoutes()` 树遍历快照。
- **Range 断点续传**：`Response.sendFileRange( path, rangeSpec )`（`sendFile` 委托其 null 形态）——"a-b"/"a-"/"-n" 三态解析（`_parseRange`：有效 → 206 + Content-Range + FileStream seek 定位 + 64KB 分块截取；start 越界/倒置 → 416 + `Content-Range: bytes */size`；畸形 → RFC 9110 允许忽略按全量 200）；恒发 `Accept-Ranges: bytes`；`staticFiles` 插件透传 req 的 Range 头；`_reason` 表补 416/429。
- **WS 空闲心跳**：`WsSession._startHeartbeat( idleMs )`（看门狗协程：步长 idle/4 钳制 [100,1000]ms 轮询 `_lastActive`，超时 `close` 会话 → handler receive 返回 null 自然收尾）；`receive()` 返回即刷新活跃时刻；`ServerConfig.wsIdleTimeoutMs`（<= 0 不启用，缺省关）+ 引擎升级分流/独立端口两形态接线。
- **rateLimit 插件**：`SLang.Plugins.rateLimit( max, windowMs )`——按客户端 IP 固定窗口；超限 429 + `Retry-After`（剩余秒向上取整）短路；桶表 `Map<string,object>` + as 转型（_WsSessions 纪律），每 256 次放行判定顺带清一遍过期桶。
- **C VM crypto 原语**：`src/core/sl_core_sha256.c/h`（SHA-256 FIPS 180-4 + HMAC-SHA256 RFC 2104，照 `sl_core_sha1.c` 纪律：纯 C / 无平台代码 / 两段 sizing；R4 零警告通过）；VM 适配 `vm_sys_sha256_digest` / `vm_sys_hmac_sha256`（`byte_buffer_system_method.c` Section 15）；R6 登记（CMakeLists + vm_lib vcxproj + filters）；R7 四处同步（SL 声明 `Std/Encoding/Sha256.sl`、`Std.jsonc` systemCalls 两条、C 实现与头、—— C# `ESystemMethodCall` 枚举经查证**无需登记**：SystemSha1 先例即无枚举条目，systemCalls 按名经 dlsym 动态解析）；标准测试向量验证（SHA-256("abc")=ba7816bf… / HMAC-SHA256("key","msg")=2d93cbc1…）。
- **Jwt HS256**：`Jwt.sign( claims, secret, expSec )`（iat 恒写 / exp>0 写；`MissingJwtSecret` 防御）+ `sign( claims, expSec )` 便捷形态（密钥取 `ServerConfig.jwtSecret`）+ `verify( token, secret )` / `verify( token )`——全量校验（三段 / **header.alg 必须字面 HS256**（拒绝 none 降级）/ 签名重算逐字节比对 / exp 过期拦截）；base64url 编码归一（`Base64.encodeToString` + '+'→'-'、'/'→'_'、剥 '='）与既有 `_normB64Url` 解码对称；`decode` 不验签语义独立保留。
- **请求侧流式**：`RouteInfo.streamBody = true` 注册期声明 → 引擎 `_parse` 增 `stopAtHead`（头区空行即停，CL/chunked 元信息经 `_HttpParseResult._streamCl/_streamChunked` 带出）→ 命中路由时 `Request._bindStream` 移交连接 + 预读缓冲 → `req.bodyStream()` 构造 `HttpBodyReader`（新文件 `HttpBodyReader.sl`：`read( dst )` CL 精确/chunked 感知/累计超限抛 `StreamBodyError.LimitExceeded`、`readAll()` 聚合；上限取 `cfg.maxBodyBytes`，multipart 放宽 `maxUploadBytes`）；未命中路由走 `_parseHeadless` 补读 body（v1 全量缓冲语义零变化）；handler 返回后引擎 `_releaseRequest` → 6a 收尾：未消费完整且拟 keep-alive → 引擎丢弃式排干（复用读取器），排干失败/超限 → graceful close 断连止损。
- **TLS 服务端评估**（结论性，不落代码）：mbedtls 3.6.7 已在树（`sys_tls.c` 客户端 session 形态含 `mbedtls_ssl_config_defaults(server)` 分支——即 conf 层已具备服务端骨架）；落地方案 = `Net.TlsServer.listen` + accept 后 `sys_tls_server_handshake`（装载 own_cert/own_key，PEM 文本经 SL 传入）+ `TlsStream` 包装既有双向；工作量集中在证书/私钥参数链路 + SL 层 API + `ServerConfig.tls` 段；**维持 P6+ 不在 P5 落地**的理由不变（生产标准解 = 前置反代，见 §1.2/§10 风险 6）——评估完成，决策：留待真实部署需求触发。
- **错误码**：`ServerError.MissingJwtSecret = 10` 接入（附录 D 最后一项归位）；`StreamBodyError` 新枚举（LimitExceeded=1）。

**验收**：✅ 2026-10-26 全绿——`ServerP5Test.sl` T1–T6 共 28 项全 OK（明细见 §8 P5 行）；ServerTest 全量 178/178（P0 探针 + P0 引擎 + P1~P4.5 + P5）；ExpendTest 250/250、NetTest 81/81 回归零 FAIL；BaseTest 26 FAIL = 2026-10-23 既有基线**逐条一致零新增**；MathTest / NullFast exit 0。

**与设计的偏差 / 实况要点**：

1. **路由树保留"收集后择优"而非树内单径**：`{path*}` 通配挂前缀节点 + 参数边共享意味着同一路径仍可能多候选（与 v1 线性扫描的候选集完全一致）——设计倾向的前缀树 O(段数) 单径裁剪需要"静态段全局优先注册序"约束，会改变语义；v1 语义保持优先，树化的收益落在**候选集收缩**（不相关分支不再评估），符合 §1.2「前缀树为优化项，非语义变更」的定界。
2. **流式请求的解析策略 = 先头后路由再补 body**：`stopAtHead` 首遍解析头 → 按路由判定 streamBody → 命中即移交 / 未命中 `_parseHeadless` 补读。非 streamBody 路径多一次头区"重解析"（buf 索引已在头区后，`_parseHeadless` 只做 body 三态，不重复 IO）——比"回滚 buf 索引重跑全量 _parse"简单且零成本，语义与 v1 完全一致。
3. **streamBody + maxUploadBytes 的耦合**：流式 multipart（boundary 跨块）v1 不做流式解析（§6.6 既定），`HttpBodyReader` 上限对 multipart Content-Type 自动放宽到 `maxUploadBytes`——handler 拿到原始流自行处理 boundary；`UploadedFile` 全内存形态与流式形态并行（设计原文照办）。
4. **Front 已知坑两条（新踩）**：① **下标访问禁用算术表达式**（`segs[n-1]` 报 21340 无行号——变量下标走 `GetMetaVariableByName` 快路、算术下标走 `_getItem_` 探测路径失败；P1~P4.5 代码从未用过此形态；拆局部 `Int32 last = n - 1` 规避）；② **`null` 检查后 `&&` 链式成员访问触发 File 层 NRE**（`back != null && back.subject == ...`——既有坑的新形态，P5 测试重踩；if 块内先取局部再判）。
5. **旧包 cvm 的静默陷阱**：宿主测试跑在 `package\win32-debug`（内嵌 cvm 快照），改 C VM 后必须刷新包内 `bin\`——本次 SHA256 符号缺失即此因（systemCalls 未注册 → 返回 0 → SL 抛错未捕获 → 主协程静默终止且 exit 0）。`release-local.ps1` 全链已内建该刷新，手工改 VM 时需单独拷贝。
6. **R7 第四处（C# `Define.cs`）查证免登记**：`ESystemMethodCall` 枚举已非按名消费通道（SystemSha1 2026-10 先例即无枚举条目）；`systemCalls` 经模块 "systemCalls" export → `vm_sysfunc_resolve_symbol` dlsym 按名解析。R7 文案后续维护时可将第四处标注为"按名解析通道免登记"。
7. **`jsonOk(纯数字串)` 序列化为数字**（`"300"` → `"data":300`）：`BaseJson.fromData` 对纯数字字符串按数值输出，既有语义非 P5 引入——测试断言按数字形态收口。

**下一步（P6+ 展望）**：TLS 服务端（评估已毕，待部署需求触发）/ ~~multipart 流式解析（boundary 跨块匹配）~~（**P7 已落地**，§24）/ 控制器池化与单例选项（风险 #17）/ 完整 Swagger UI 静态包（风险 #8）/ ~~BenchMark 压测矩阵~~（**P8 已落地**，§25——M1/M2 矩阵与实测数据）。

---

## §21 HttpServer / WebSocketServer 类拆分实录（2026-10-26，用户点名重构）

**背景**：用户点名——`SLang.Server` 一类承载 HTTP 与 WebSocket 双协议职责过宽，按协议拆为两类：`SLang.HttpServer`（仅 HTTP）与 `SLang.WebSocketServer`（WS 独立门面），HTTP 与 WebSocket 各一类、职责单一。

**产物**：

- `Server.sl`：`Server` 类改名 `HttpServer`（HTTP 门面，构造缺省 80 端口）；WS 四方法（`websocket/wsEvents/sessions/broadcast`）从门面迁出；L149-152 类头注记保留历史形态说明（P0–P4 曾以 `SLang.Server.configure` 静态形态落地，§19）。
- `WebSocketServer.sl`：静态引擎形态 → **实例双形态门面**——形态 A（构造不传端口 = 升级路由器，`websocket( path, fn ) → RouteInfo` / `wsEvents( path ) → WsEventBuilder` / `sessions( path )` / `broadcast( path, text ) → Int32`）+ 形态 B（构造传端口 = 独立端口服务器，`onMessage( fn )/onClose( fn )` / `run( port )/start()/stop()/awaitStop()` / `sessions()` / `broadcast( text ) → Int32`）；`idleTimeout( ms )` P5 WS 空闲心跳写口（写 `WebSocketServer._idleTimeoutMs` + 若 `HttpServerCore._cfg != null` 同步 `cfg.wsIdleTimeoutMs`；**形态 A 时序 = 先构造 HttpServer 再调用**）；`WsEventBuilder` 链式事件糖保留。
- `Server.jsonc`：struct 登记同步（37 项——`Server` → `HttpServer`，增 `WsEventBuilder/HttpBodyReader` 等）。
- 六个测试文件批量改写（Probe/Core/P1/P1.5/P2/P3/P4/P4.5/P5 的 `SLang.Server` → `SLang.HttpServer`，WS API 调用挂 `WebSocketServer` 实例）；库注释 9 处清理。
- 文档同步（R14）：`md/lib/Server.md` 全文重写（361 → 419 行 + WsCloseInfo 三字段补全）；本文档 §0–§5 现行设计章节同步（§12–§20 历史实录保持原样）。

**验收**：✅ SLangServer 库重编通过；ServerTest 全量回归 **178/178 OK**（Probe 11 + Core 12 + P1 43 + P1.5 8 + P2 21 + P3 31 + P4 13 + P4.5 11 + P5 28）；R17 收尾——`package\win32-debug` cvm 产物 `--clean-first` 全量重编至 0.0.38 并刷新 `bin\` 三产物，**回归复跑仍 178/178 OK**，两处 CLI（`slang.exe version` / `bin\csimple_lang.exe version`）版本一致（vsix 待 release-local.ps1 发布时刷新）。

**与设计的偏差 / 实况要点**：

1. **`ServerPlugin.onInstall()` 维持无参**（设计稿曾为 `onInstall( SLang.Server app )` 传门面）：SL 闭包零捕获纪律下插件内无法引用实例——注册走引擎级形态 `SLang.HttpServerCore.use( ... )`（与 `app.use(...)` 语义等价，v1 单 VM 单服务器语义）。
2. **`s.tag(...)`/`s.tagged(...)` 会话标签未实现**（设计项，定向广播 P6+ 评估）。→ **P6 已落地**（`tag/untag/tagged/tags` + `broadcastTag` 全家族，§23）。
3. **形态 B 回调注册为方法调用而非字段赋值**（`wss.onMessage( fn )`），且**形态 B 无 onOpen 注册**（onOpen 仅在 WsEventBuilder 链上）；无无参 `run()`（仅 `run( port )` / `start()`）。
4. **`broadcast` 仅文本重载**（→ Int32 送达数）——binary( ByteBuffer ) 重载未落地。→ **P6 已落地**（broadcast/broadcastTag 全家族各带二进制重载，§23）。
5. **`ServerConfig.showBanner` 未实现**（已从 §4.9 移除）；**app 级事件钩子 `onStart/onStop/onError` 未实现**（§4.9 已标注设计预留——生命周期钩子现仅有插件级 `ServerPlugin.onStart/onStop`）。→ 钩子三项 **P6 已落地**（字段赋值形态 set/get 访问器，§23；showBanner 维持移除状态不变）。
6. **构建基建坑（R17 收尾时发现）：Ninja 头依赖追踪失效——版本 bump 必须全量重编**：0.0.37→0.0.38 只改 `cli_version.h` 后，增量构建产出"缝合怪"二进制（exe banner 0.0.31 / `version` 命令 0.0.34，新旧混体）。根因：中文版 MSVC `/showIncludes` 输出前缀「注意： 包含文件：」未被 CMake/Ninja deps 过滤器识别（该行直接透传 stdout 即证据），`.ninja_deps` 不记头依赖 → **只改头文件永不触发重编**（touch `cli_version.h` 后增量构建实测 "no work to do"，对象 mtime 不变），只改 .c 才会重编。实验：设 `VSLANG=1033` 后 clean 重编日志仍为中文前缀、touch 测试仍失效——VSLANG 改不了 cl.exe 输出语言，**不进 common.ps1**。定案纪律：**版本 bump 后用 `cmake --build csimple_lang\build\Debug --clean-first -j 8` 全量重编**（629 步），再按 §20 偏差 ⑤ 把 `build\Debug\bin\` 三产物（`csimple_lang.exe` / `csimple_lang_dll.dll` / `csimple_lang_dll.pdb`）拷进 `package\win32-debug\bin\`；已同步进 PROJECTS.md §7 操作规则第 5 条。

**下一步（P6+ 展望）**：~~`s.tag/s.tagged` 定向广播 / `broadcast` binary 重载 / app 级事件钩子~~——三项均已随 **P6** 落地（§23）；~~multipart 流式解析~~已随 **P7** 落地（§24）；~~BenchMark 压测矩阵~~已随 **P8** 落地（§25）；剩余展望（TLS 服务端 / 控制器池化与单例选项 / 完整 Swagger UI 静态包）。

---

## §22 实参位置内联闭包编译器增强实录（2026-10-26，示例驱动，0.0.39）

**背景**：用户点名——`md/lib/Server.md` 示例区补写 `app.onPost( "xxx", function( Request req, Response res ) {...} )` 内联直传示例与 handler 内 await 示例。考据发现既有快速开始/路由两处示例（§0 时代即写入）正是实参位置内联闭包形态，而该形态编译器**不支持**（无任何拦截器认领，落普通表达式解析报 49 错）——属历史坏示例。用户拍板：**增强编译器支持该形态**（参照 `Isolate.run/spawn` 的闭包提升机制通用化到任意调用实参）。

**产物**（Front `StructParseToSyntax.cs`，零运行时改动，纯 Parse 层）：

- 新增通用变换器 `TransformInlineClosureArgNodes`（插在 `LiftIsolateClosure` 之后）：任意调用的实参段恰为 `[function 关键字, Par, Brace]` 三件套时，提升为具名闭包 `inlineClosureTmpN`（`AddParseSyntaxNodeInfo` 先于调用语句发射），原实参位置替换为名字引用节点；实参切段复用 `SplitIsolateArgSegments`，下钻规则与 `TransformIsolateCallNodes` 同构（Brace 跳过防双重处理 / parNode.childList / IdentifierLink 链扩展 DigLink / bracketNodeList）。
- 挂点双处（与 Isolate 变换器一一对应）：语句级（`TransformIsolateCallNodes` 之后）+ `ret`/`Transience` 表达式分支；`await/spawn` 专属糖在前级 `TransformCoroutineKeywordNodes` 已消化，本变换器兜底通用调用。
- 约束（编译错误拦截）：仅方法体内可用（需语句发射环境）；闭包体内禁用（闭包嵌套定义不支持，`m_ClosureBodyDepth` 防护）；`function( 参数 ) { 体 }` 必须单独作为一项实参。无匹配时零副作用（`GetInlineClosureSegKind` 全 0 直接 return 不动节点）。

**验收**：✅ 冒烟工程 `test/Other/ServerTest/_docsmoke/`（临时，验证后删除）A 系 7 例——A1 表单登录+缺字段 jsonFail / A2 DTO 201 / A3 path+query / A4 delay 挂起 / A5 直接 await 糖 / A6 void await / A7 Task 透传（httpGetAsync）全 OK；B 系 3 例——B1 `await spawn function(){...} as Int32` / B2 `await spawn 裸方法` / B3 两步并发（`Task t = spawn f()` + `await t as Int32`）全 OK（**`await spawn` 组合形态此前全仓零测试覆盖**，本例补齐）。全量回归见 §21 验收口径（178/178 + 版本锚点 0.0.39）。

**文档同步（R14）**：`md/lib/Server.md` 新增「内联 function 直传注册」「handler 内 await」两节（示例逐字取自冒烟验证通过的形态）；`md/syntax/function.md` 基本语法补实参位置内联闭包条目。

## §23 P6 落地实录（2026-10-26，app 级钩子 + WS 标签定向广播 + broadcast 二进制，0.0.40）

**背景**：用户指令「继续实现 未完成的 httpserver 的功能吧」——落地 §21 展望清单剩余三项设计预留：偏差② `s.tag/s.tagged` 会话标签 + `broadcastTag` 定向广播、偏差④ `broadcast` binary( ByteBuffer ) 重载、偏差⑤ app 级事件钩子 `onStart/onStop/onError`（§4.9 设计预留）。三项合并为 **P6** 一次交付。

**产物**（纯 SL 库层，零引擎改动）：

- `HttpServerCore.sl`：三钩子静态 `Function _hookOnStart/_hookOnStop/_hookOnError`（L89-94）；触发接线三处——`start` 末尾 onStart（L268，先拷局部 + null 守卫 + 异常吞）、`stop` 收尾 onStop（L307，同款）、管道 catch onError（L582：handler/中间件异常兜底，钩子内可写响应自救、未写则 500 ApiResult 兜底）；`reset` 清三钩子；引擎级静态通道 broadcast 文本/二进制 + broadcastTag 文本/二进制四转发（L187-208）。
- `WebSocketServer.sl`：`_WsSessions` 静态登记表扩标签族——`broadcast`(L127) / `broadcastBinary`(L146) / `broadcastTag`(L165) / `broadcastTagBinary`(L192) / `tagSession`(L223) / `untagSession`(L245)；`WsSession` 新增 `List<string> _tags` 字段（L332）+ 门面 `tag/untag/tagged/tags`（L472-494，`tags` 返回快照防外部篡改）；实例门面全家族 12 方法 = 两形态（组播 pattern / 实例自路径）× 文本/二进制 × 全量/定向（L645-653 / L778-786 等），全返回 Int32 送达数。
- `Server.sl`：`HttpServer` 六访问器 set/get × onStart/onStop/onError（L268-296，转发 HttpServerCore 静态——SL 字段不能存 Function，访问器中转）。
- `test/Other/ServerTest/ServerP6Test.sl`（497 行）：T1 钩子 7 断言（onStart/onStop 各一次、onError 自救 599、异常路径+错误对象可见、正常路由不受扰、静默钩子 500 兜底双触发）；T2 WS 标签 8 断言（两客户端上线、handler 内消息驱动打标 `login:vip`、broadcastTag 定向送达非目标零泄漏）；T3 形态 B 5 断言（`WebSocketServer` 实例直用，broadcastTag/broadcast 二进制）；辅助件：手搓 `P6WsClient`（raw socket + WS 帧编解码）+ `blowUp()`/`binOf()`。`ServerTest.sp` / `ServerTest.jsonc` 注册。

**验收**：✅ ServerTest **198/198**（178 既有 + 20 P6）；R17 版本 bump **0.0.40**（7 锚点：`cli_version.h` PATCH+STRING / `CommandExecutor.cs` / `CMakeLists` / vcxproj PostBuildEvent / csproj / package.json / package-lock.json）；C VM clean-first 重编 **629/629**，产物入 `version_0.0.40/`。**T4g `cfg secret + MissingJwtSecret` 首跑偶发 FAIL（197/198）**——初判 flaky 留档后复跑复发（~3/5 失败率），插桩裁决实锤根因（推翻 flaky 定案）：verify 签名段解码走 `Base64.decodeString`，其内嵌 NUL 截断语义在 HMAC-SHA256 值域含 0x00 时截断签名（单 token 概率 1-(255/256)³² ≈ 11.8%）→ 签名失配概率性验签失败（同轮 token 相同 → 轮内恒定；exp 变化 HMAC 重掷 → 轮盘随机）。修复 = verify dv 段改二进制安全链 `ByteBuffer.fromString + Base64.decode(ByteBuffer)`（全程字节句柄不经字符串化，NUL 截断从类型上消除）；T4g 同步强化为回归防线——20 rep × 独立 jti = 20 个独立 HMAC 样本，解码层回归 ~92% 概率当场抓获。修复后 8 轮 + 插桩回改后 3 轮均全绿 198/198。

**实况要点（SL 约束规避姿势，后续迭代参照）**：

1. 字段赋值右侧不能直接写闭包字面量 → 先存局部变量再赋值：`function hOnStart = function(){...}` → `app.onStart = hOnStart`（§4.9 示例已按此形态改写）。
2. 合成闭包无 throws 声明、闭包体内不能直接 throw → 经 `static void blowUp() throws` 方法传播（onError 测试异常源）。
3. 跨模块点分类型不能作泛型参数（`List<SLang.WsSession>` 触发 Front NRE，HttpServerCore.sl L79 权威注记）→ 测试观测槽改静态字段 + `List<string>`（内建类型参数安全）+ 链式 `sessions(...).length`。
4. `Error` 不能作静态方法形参类型 → onError 回调 `function(req,res,e)` 只能以 Function 动态调用、catch 绑定变量直传 `hErr( req, res, e )`。
5. 闭包零捕获 → 观测值经静态字段回传；闭包体内引用静态须类名限定（`ServerP6Test._evtStart`）。
6. WS 验收三手法：**首帧探测法**（静默客户端零驱动即零收帧、首帧必是自己的 echo——若定向广播泄漏则首帧为泄漏帧）；**消息驱动登记**（协程调度序无契约，连接序登记不可依赖）；`Coroutine.delay(100)` 时序屏障。
7. 环境记录：`Enter-VsDevShell` 非直接可调 cmdlet——须先 `Import-Module "...\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"` 再进 shell，否则 cl.exe 缺 INCLUDE/LIB 报 C1083；版本 bump 后 Ninja 头依赖失效（中文 MSVC 路径）→ 必须 `--clean-first`。

**文档同步（R14）**：`md/lib/Server.md` 四处——验收清单追加 ServerP6Test、WsSession 表补 `tag/untag/tagged/tags` 行、新增「广播与标签（P6）」小节（全家族 8 形态示例 + handler 内打标典型用法）、新增「app 级事件钩子（P6）」小节（三钩子示例 + 触发时序 + `reset()` 注释翻转）；本文 §1 G2 / §4.6 / §4.9 / §21 偏差②④⑤ / §21 展望清单同步翻转至 P6 已落地。

---

## §24 P7 落地实录（2026-10-26，multipart 流式解析 MultipartReader）

**背景**：用户指令「后边还有没实现的 http server 的设计吗？ 如果有，则继续实现」——展望清单查证（§20/§21 剩余四项）：TLS 服务端（维持留待部署需求触发）、multipart 流式解析、控制器池化与单例选项（风险 #17）、BenchMark 压测矩阵。裁决本轮 **P7 = multipart 流式解析**（§6.6 既定进阶项、风险 #4 的根治路径；池化涉语义变更待单独立项，压测依赖量化基线，TLS 按既定决策留待）。

**产物**：

- **`MultipartReader.sl`**（新文件，487 行）：
  - `MultipartPart`：元数据 `field`（字段名）/ `filename`（null = 普通字段，已剥路径）/ `contentType` / `isFile`；内容三形态——`read( ByteBuffer dst ) → Int32`（0 = 本 part 结束；句柄过期即 nextPart 推进后恒 0）、`readAll() → ByteBuffer`（新建归调用方，用后可 release）、`saveAs( path ) → bool`（**非 throws**：内部 label/catch 包 FileStream Create + flush + close，失败返 false 不炸 handler）；
  - `MultipartReader` 五状态机（0 找首 boundary / 1 part 头区 / 2 内容区 / 3 找次 boundary / 4 done）：`static of( reader, contentType )` 工厂——CT 非 multipart / boundary 参数缺失 → **返 null 且不读流**；`nextPart() → MultipartPart | null`——自动排干未读完的当前 part（`_drainContent`）、preamble 行容忍（state 0 非 boundary 行无状态转移继续循环）、终界 `--suffix--` → state 4 返 null；`isDone`（`_state == 4`）；boundary 跨块鲁棒——`\r\n--boundary` 匹配在缓冲边界处按需补读（`_fill`）完成，不受 TCP 分帧切分影响。
- **`Request.sl`**：`_streamReader` / `_mpReader` 缓存字段；`bodyStream()` 改**双形态缓存化**（同一请求恒返同一 `HttpBodyReader`——引擎收尾与 handler 共享消费进度）；`multipartStream()`——流式路由且 CT 合法 → `MultipartReader.of( 缓存 bodyStream, ct )` 并缓存返出，否则返 null（非流式路由用 form/file 内存族；boundary 缺失交 handler 裁决）。
- **`HttpServerCore.sl`** 引擎两处：
  - **4a 段流式豁免**（§6.5 构造期 multipart 即时解析）：条件改 `req.isStreamBody == false && req.bodyFormat == EBodyFormat.Multipart`。根因：`BodyParser.detect` 纯 Content-Type 基（multipart 判定与 bodyLen 无关）→ 流式路由 `_body == null` 时 bodyFormat 仍为 Multipart；而 `parseMultipart` 在 **boundary 缺失时先于 null-body 守卫即抛 400**（先查 boundary 后查 body）→ boundary 缺失的流式 multipart 请求会在 handler 前被引擎 400 误伤，剥夺 handler 经 `multipartStream()` 返 null 自行裁决的选择权；且流式路由 body 不驻留、`_ensureMultipart` 空转（form/file 恒空）——该分支唯一可观察效果是误伤，故跳过。
  - **6a 收尾段窥视式 multipart 排干**：`MultipartReader mpDrain = req._mpReader` **窥视缓存**（不调 `multipartStream()`——其内部 `bodyStream()` 缓存路径虽安全，但语义边界在"引擎不替 handler 决定 multipart 有效性"）→ 非 null → `_drainTail()` 以 multipart 语义排干剩余 part（解析器预读窗口闭环，防底层 drainer 按 CL 余量排干时跳过预读数据错吃下一请求字节）→ 后续沿用 P5 缓存 drainer 排 CL 余量；失败/超限 → gracefulClose 断连止损。
- **`Server.jsonc`**：compileFiles 登记 `MultipartReader.sl`（16 → 17 文件）。
- **`ServerP7Test.sl`**（~800 行，15 检查；19471-19472 双端口）+ `ServerTest.sp` / `ServerTest.jsonc` 注册：T1 基本读写（缓存单实例 / 字段 + 文件 / 2 parts + isDone）；T2 `saveAs` 300KB 落盘（size + head/mid/tail 三窗口字节校验）；T3 boundary 跨 TCP 分帧（手搓 `P7RawClient` 5 段确定性投递，切点落在 boundary 内部）；T4 空 multipart（仅终界）/ preamble 容忍；T5 混合语义（非流式路由 mp=null + form 正常 / 非 multipart CT 回落 bodyStream / boundary 缺失返 null 且同连接 keep-alive 存活——引擎 4a 豁免的回归防线）；T6 非流式路由 form/file 内存语义回归；T7 半读收尾（multipart 文件 part 读 100/5000 后 **break** + raw 流读 100/300 后返回 → 引擎排干 + 同连接 keep-alive 存活——定向验证 6a 闭环）。

**验收**：✅ ServerTest **213/213**（198 既有 + 15 P7），exit 0。

**实况要点**：

1. **P5 缺陷顺带根治（drainer 多吃错位）**：P5 引擎 6a 收尾每次新造 `HttpBodyReader`，CL 余量按完整 CL 重新起算 → handler 已消费字节被 drainer 重复排干（多吃）→ 下一请求解析错位风险。P7 将 `bodyStream()` 缓存化（单实例共享 `_remain`/`_total` 进度）+ 6a 经缓存实例排干——缺陷从构造上消除（T7a/T7b 双路回归覆盖）。
2. **`nextPart()` 自动排干当前 part**：handler 对文件 part 半读后 `break`（不再迭代）才能让引擎 `_drainTail` 有活可干——T7a 即按此定向设计；若迭代到底（nextPart 返 null）则引擎收尾只剩 CL 余量排空。
3. **流式判定与 CT 判定正交**：`bodyFormat` 是纯 Content-Type 判定（流式路由 `_body == null` 时仍为 Multipart）——是否流式由 `isStreamBody` 决定；故 4a 豁免条件必须双因子（非流式 && Multipart），单看 bodyFormat 会误伤流式路由。
4. **测试客户端形态**：P5 `P5RawClient` 复制为 `P7RawClient`（connect / 分段 send / readLine / readN / readResp / close）——raw socket 确定性分段投递是分帧鲁棒性测试（T3）的可靠手段。
5. **SL 约束规避（沿 P5/P6 姿势）**：助手以类名限定静态复用（`ServerP7Test.sfFind` 等）；闭包零捕获 → 观测经静态字段回传；非 throws 方法可直接调用 throws 方法（P5 `rawReq` 先例）；`readAll()` 归调用方 → 用后 release 防泄漏纪律进测试。

**文档同步（R14）**：`md/lib/Server.md` P5 流式上传节后新增「multipart 流式解析（P7）」节（示例取自 T1 已验证形态）；本文 §6.6 标题与请求侧小节翻转 + §10 风险 #4 对策更新 + §20/§21 展望清单翻转。

**下一步（P8 候选）**：控制器池化与单例选项（风险 #17，涉语义变更）/ ~~BenchMark 压测矩阵~~（**P8 已落地**，§25）/ 完整 Swagger UI 静态包（风险 #8）/ TLS 服务端（留待部署需求触发）。

---

## §25 P8 落地实录（2026-10-26，BenchMark 压测矩阵量化流式收益）

**背景**：用户指令「生成 BenchMark 压测矩阵以量化流式收益」——P5（请求侧流式）与 P7（multipart 流式解析）相继落地后，流式收益一直停留在定性论证（「不驻留全量 body」）；P8 以可复现基准补上量化基线，兑现 §20 展望中自 P5 起延后的「基准+压测」验收项。

**产物**（纯测试侧，零库/引擎改动）：

- **`test/Other/ServerTest/ServerBench.sl`**（751 行）+ `ServerTest.sp` / `ServerTest.jsonc` 注册（213 → 223 检查）。
- **矩阵设计（维度 × 指标）**：
  - **M1 上传解析矩阵**（端口 19481）：`{stream, memory} × {64KB, 512KB, 2MB, 8MB}` 共 8 格；指标 = 耗时 ms（min-of-3）/ 吞吐 MB/s / SL 堆分配计数增量。两路由 handler 语义对称（文件均落盘为同尺寸文件），唯一变量 = 引擎解析路径——stream 路由 `/bench/stream`（`rStream.streamBody = true`；handler 经 `req.multipartStream()` 逐 `nextPart()`，文件 part `saveAs("bench_stream.bin")`、字段 part `readAll()+release`，回 `sv=1`）；memory 路由 `/bench/memory`（引擎 4a 预解析；handler 经 `req.form("note")` + `req.file("blob")` 落盘 `bench_mem.bin`，回 `u=bench|sz=<size>|sv=1`）。
  - **M2 连接矩阵**（端口 19482）：`{keepalive, close} × 100 req` `GET /probe`（极小响应体）；指标 = 总耗时 / req-per-s / us-per-req。keepalive = 同连接循环 n 次；close = 每请求新建连接（请求头带 `Connection: close`）；10 次同连接预热在前。
- **计量纪律**：计时 3 次取最小——请求 buffer 深拷贝在计时窗外，窗 = connect→全量发送→读完整响应；每轮 `Memory.collect()` 摊平跨轮残留后以 `Memory.totalAllocated()` / `OS.Timer.clock()` 差值计；预热轮（不计时）兼正确性验证——响应内容 + 落盘尺寸 == size + 净荷头/中/尾三窗口各 16 字节校验（`dataWindowOk`，净荷 = "0123456789" 循环可预测）。**基准与回归合一**：模块自带 10 项 check（8 × 「M1 \<mode\> \<档位\> respond+save ok」+「M1 timed runs all ok」+「M2 200 responses ok」）。
- **辅助件**：`BenchRawClient`（raw socket：connect / send / sendBuf / readLine / readN / readResp / close——沿 P5/P7 确定性投递姿势）+ `BenchResp` 应答结构；multipart 拼装 `mpField/mpFile/mpFinish`（boundary=BNC，头+body 拼单 buffer 单次 write）；格式化 `fmtMbps`（`sizeBytes * 10000L / ( dms * 1048576L )` 定点 1 位小数）/ `fmtRps`（`n * 1000L / dms`）/ `fmtUspr`（`ms * 1000 / n`）；单格结果经静态字段 `gMinMs/gMinAlloc/gAllocValid/gAllOk` 回传（闭包零捕获约束，沿 P6/P7 姿势）。

**实测数据**（2026-10-26，win32-debug C VM，同机同进程；ratio 方向 = memory/stream）：

M1 上传矩阵（min-of-3；alloc = SL 堆分配计数增量）：

| 档位 | stream：ms / MB/s / alloc | memory：ms / MB/s / alloc | 时间比 | alloc 比 |
|---|---|---|---|---|
| 64KB | 18 / 3.4 / +136 | 20 / 3.1 / +143 | 1.1x | 1.0x |
| 512KB | 45 / 11.1 / +150 | 47 / 10.6 / +143 | 1.0x | 0.9x |
| 2MB | 142 / 14.0 / +196 | 136 / 14.7 / +143 | 0.9x | 0.7x |
| 8MB | 533 / 15.0 / +376 | 487 / 16.4 / +143 | 0.9x | 0.3x |

M2 连接矩阵（100 req）：

| 模式 | 总耗时 | 吞吐 | 单请求 |
|---|---|---|---|
| keepalive | 646ms | 154 req/s | 6460 us/req |
| close | 829ms | 120 req/s | 8290 us/req |

keepalive vs close：**时间 -22%（646 vs 829ms）、吞吐 +28%（154 vs 120 req/s）**——无 TLS 下纯 TCP 连接建立/拆除成本的直接实证，叠加 TLS 后该差距将进一步放大。

**数据解读（诚实口径）**：

1. **SL 堆分配计数是内存收益的下界证据而非全貌**：`Memory.totalAllocated()` 度量 SL 堆对象分配（客户端+服务端同进程活动的合计差值），**不含 ByteBuffer/native 内存**——两模式 body 字节均驻留 ByteBuffer，故「流式不驻留全量 body」的核心收益（native 内存峰值 O(块) vs O(body)）不在该计数器可见范围。可见部分：memory 模式 alloc 恒 +143（4a 预解析的 SL 侧对象开销为常数，body 字节不经 SL 堆）；stream 模式 136→376 随档位缓增（`MultipartPart` 与读块对象按 part 生命周期分配）。8MB 档 alloc 比 0.3x 的方向由此而来，但绝对量级小（均为百级计数）。
2. **时间维度**：小档 stream 占优（64KB 快 10%、512KB 快 4%），大档 stream 落后（2MB 慢 4%、8MB 慢 9%）——交叉点在 512KB-2MB 之间，流式的时间代价上限 ~9%（8MB 档，分块流式状态机的解析开销 vs 整块扫描；小档反超因 4a 预解析构造 UploadedFile 的固定开销在小 body 下占比更高）。
3. **吞吐绝对值**（3.4-16.4MB/s）为 debug 构建的保守值；流式的主收益维度（release 构建 + 32MB+ 档的 native 内存峰值对比）留待基准扩展。

**验收**：✅ ServerTest **223/223**（213 既有 + 10 ServerBench），exit 0；R18 版本 bump **0.0.42**（锚点沿 R17 七处 + PROJECTS.md 版本总表：`cli_version.h` PATCH+STRING / `CommandExecutor.cs` / 根 CMakeLists `SLVM_VERSION_DIR` / vcxproj PostBuildEvent / `project\cmake\CMakeLists.txt` / `SlangAllInOne.csproj` / package.json + package-lock.json）。

**实况要点**：

1. **局部变量命名必须避开关键字表**：初版 `string tr` / `string label` 分别撞 `ETokenType.Transience` 与 `ETokenType.Label`（`label cl { } catch { }` 语法字）——`tr = ...` 语句起始在词法层即切为关键字 Token（LexerParseToToken.cs L2412 关键字 switch），派发 `MetaTRStatements` 后表达式以 `=` 开头无法建树 → Front NRE（`MetaCoreParseFileExpressFailed root is Null`）。修复 = `tr`→`tRatio`、`label`→`lbl`（`ar` 经词法表证实安全保留）。教训：SLang 局部变量命名先查 LexerParseToToken.cs L2181-2505 关键字 switch（tr/label 均无局部变量先例）。
2. **先例检索判定语法合法性**：`( tr10 / 10 ).toString()` 曾疑需重构，经 NaNBench.sl L30 `( 9223372036854775807L - 1L ).toString()` 直接先例证实合法——省掉 3 处表达式重构；`10L/10000L` 字面量后缀同有先例（EqBench / QuickSort / NumberTest）。
3. **alloc 计数器防御**：`bestAlloc < 0` → 显示 "wrap"、ratio 显示 "n/a"（计数器回绕出口，本次实测未触发）。
4. **基准与回归合一**：预热轮兼正确性验证（respond + save + 三窗口字节校验），压测模块本身就是 10 项回归防线——不为基准另写第二套正确性代码。

**文档同步（R14）**：本次纯测试侧产物、无库 API 变更，`md/lib/Server.md` 不动；本文 §20/§21/§24 展望清单的 BenchMark 项翻转（已落地，§25）；§10 风险 #17 的「BenchMark 压测验证」缓解维持，待池化立项后直接复用本矩阵。

**下一步（P9 候选）**：控制器池化与单例选项（风险 #17，涉语义变更——落地后复用 ServerBench 矩阵量化池化收益）/ 完整 Swagger UI 静态包（风险 #8）/ TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 32MB+ 档 + 并发客户端维度，量化 native 内存峰值——流式的主收益证据）。

---

## §26 P9 落地实录（2026-10-26，@Singleton 单例控制器 + attribute 形态 3 重构；2026-10-27 @Singleton 收编为 Std @InstanceAttr）

P9 以两项交付收官（同日连续落地，全量回归 234 OK / 0 FAIL）：

### 26.1 @Singleton 单例控制器（§4.10 默认每请求一实例之上的显式 opt-in）

> **2026-10-27 收编退役**：`@Singleton`（本模块私有）收编为通用机制 **`@InstanceAttr`**（`Lib/Std/InstanceAttr.sl`，Std 库）——单实例从"注册中心表键"升级为"宿主类合成静态字段"（Front `AttributeManager.SynthesizeInstanceAttrMembers` 编译期合成 `static <宿主类> instance` / 自定义名字段，装配期 `InstanceAttr._enter_` 构造写入，`SystemAttributeSetStaticField/GetInstanceField` 两条通用系统方法通道），源代码 `ClassA.instance` / `ClassB.inst` 直接访问（类型即宿主类，免转型）；`registerPreload` 改经 `SystemAttributeGetInstanceField` 取实例绑 `hostMethodRefOf`（bind-once 语义不变）。RouteAttrs.sl 的 `Singleton` 类与 Server.sl 的 `registerSingleton/_plSingleton` 表删除。验收 = ServerP9Test T1h/T1i + ExpendTest InstanceAttrTest 九断言。

- **语义**：类级 `@InstanceAttr`（与 `@OnRoute` 可叠加）→ 装配期构造单实例（`hostClassNew()`），该类**全部方法路由**绑同一实例（`hostMethodRefOf(单实例)`，绑定实例 method-ref）；跨 handler 状态共享（T1e：POST reset 改写 → GET counter 读到归零后重计）。默认语义不变：无标注 = 每请求一实例（LATE 闭包，T1f/T1g 对照组恒 hits=1）。**单例作用域 = 宿主类合成静态字段（进程级）**——非"每 app 一单例"；SLang 事件循环单线程派发，无并发竞争。
- **池化裁决（拒绝）**：SLang 无字段枚举/无运行时反射 → 池无法重置实例字段 → 池化仅对无状态控制器安全；无状态场景下单例（1 实例）严格优于池（N 实例）——池化不立项，单例覆盖全部合法用例。

### 26.2 attribute 形态 3 重构（§7 现行方案，P4 原生收集通道整体退役）

按用户指令把 attribute 处理统一为四形态模型（编译中 / IR 导出 / **runtime 装载** / 执行期）：**VM 零 per-attribute C99 代码，逻辑全部写在各 Attribute 子类的 `_enter_` 里经通用调用机制执行**。形态 3 通道 + Core.Attribute 三宿主接口 + `HttpServer.shared()` 注册中心三项机制落地后，`@On*` 十一族全部改为 `_enter_` 自注册；`vm_route_attribute.c`（10 个 C 收集 handler）与 `server_system_method.c`（`SystemServerRoute*` 三系统方法）**整体删除**。派发路径零特判：单例路由 = 既有 bound method-ref 分支，非单例 = 既有 LATE 闭包分支。

### 26.3 调试复盘（两项机制级发现，均已治本）

1. **无帧 armed 入口与 native 子帧执行的坠入问题**：触发通道最初挂载 `cli_command.c`（vm_initialize 之后、scheduler 之前），此时入口字节码已武装但无帧——`vm_execute_method_by_id` 的子帧弹空后解释器**直接流入入口代码**，19 个 attribute 的 `_enter_` 执行与入口测试交错（现象：usePreloadRoutes 读到 null、Probe B1-B6 await 探针被啃出 no-coroutine-context）。正解 = 挂载 `vm_scheduler_enter` 根帧建立后（子帧 barrier 落根帧，弹回即停）。**教训：native 再入执行不可依赖"主循环尚未起跑"，必须确认帧链边界。**
2. **Front 跨模块 override 吞方法（误诊，2026-10-26 撤销）**：复核定案为误诊——override 重写导出正常（OnGet 最小复现槽位与指令体俱全）；真因是当时 Server.sl 编译错误（`Map.put`/索引左值）致方法链解析失败连带方法被丢。RouteAttrs 已全量恢复 override 并重导回归全绿（见 §7 误诊更正）。
3. **SL 语法踩坑（历史纪律新增）**：`default` 是关键字（方法名 `default()` 编译失败 → 改 `shared()`）；单行 if 连排需空行分隔；`Map` 无 `put`（用 `add(key,value)` 或索引写）；索引表达式不能直接作二元运算左值/实参（先落局部变量再使用）。

### 26.4 量化与验收

- **ServerP9Test 11 条全绿**：T1a 装配条数 ≥10 / T1b-T1e 单例四态（首请求、跨请求共享、字段改写、reset 后重计）/ T1f-T1g 每请求一实例对照 / T2 pre-reset + 异步单例两连击（协程 delay 内 bound method-ref 派发正常）。
- **ServerBench M3 控制器实例矩阵**（4 字段控制器 200 req keepalive）：singleton 68B/req vs fresh 69B/req——微响应场景实例化开销占比极小（实测印证 §10 风险 #17 的量级评估：控制器实例化非热点，单例价值在**状态共享语义**而非吞吐）；400 响应全对。
- **回归**：ServerTest 全量 234 OK / 0 FAIL（基线 223 + P9 新增 11）；ExpendTest 抽查全绿（AttributeRuntimeTest P7 机制无回归）。
- **版本**：0.0.43（R17/R18 四端七锚点 + C VM --clean-first 全量重编 + win32-debug 包刷新，hash 校验一致）。

**下一步（v1 收官候选）**：~~完整 Swagger UI 静态包（风险 #8）~~（**已随 SwaggerUI 插件落地**，§27）/ TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 并发客户端维度）/ ~~Front 跨模块 override 修复（26.3-2）后 RouteAttrs 恢复 override 关键字~~（**误诊撤销 + RouteAttrs 已全量恢复 override**，26.3-2）。

---

## §27 SwaggerUI 插件落地实录（2026-10-26，v1 收官 f4 · §10 风险 #8 闭环）

v1 收官候选清单末项：`SLang.Plugins.swaggerUI( distDir )` 内置插件，`docs` 自研只读文档（§4.8）之上的**完整 Swagger UI 交互调试台**。

### 27.1 设计（staticFiles 纪律复用 + /docs 同款让位）

- **双路由接管**：`GET /swagger` → 自研 index 页（外链 `dist` 资产 + `/openapi.json`，零自包含——bundle.js 1.68MB / swagger-ui.css 187KB 官方 dist 真实文件）；`GET /swagger/<file>` → dist 目录文件直出。
- **staticFiles 同款纪律**：仅 GET 直出；`'..'` 独立段 403；dist 未命中 → `nx.go()` 放行（尾环 404，不误吞其他路由）；`res.sendFileRange` 流式直出（MIME 随扩展名 + Range 断点续传透传）。
- **让位时序（与 /docs 的差异点）**：中间件先于路由执行，且用户可在插件安装后才注册路由 → 让位检查在 `_serve` **运行期**做 `Router.findExact( "GET", "/swagger" ) != null` → `nx.go()`（非 mount 期一次性检查）。
- **闭包零捕获**：dist 目录经静态字段 `_dist` 传递（v1 单实例，重复注册后者覆盖——与 staticFiles/_StaticFilesPlugin 同款纪律）。
- **SwaggerUIBundle 配置裁剪**：`presets:[...apis]` + `layout:"BaseLayout"`——官方 `swagger-ui-dist@5` 的 StandaloneLayout/DownloadUrl 会引用 `swagger-ui-standalone-preset.js`（自备 dist 可缺省不带），裁剪后仅依赖 bundle.js + css 两资产即可渲染。

### 27.2 实现

- **`_SwaggerUIPlugin`（`Plugins.sl` L159-301）**：`_init_(distDir)` 静态字段赋值 → `onInstall` 闭包转发 → `_serve` 静态方法（方法/前缀判定 → 让位 → 穿越防护 → 拼全路径 → 未命中放行 → `sendFileRange` 短路）。
- **门面**：`SLang.Plugins.swaggerUI( distDir )`（`Plugins.sl` L677）。
- **SL 语法约束落位**：index 页长字符串一律 `StringBuilder` 逐段追加（`+` 链截断）；页面 JS 不含 `$`（SL 插值前缀——如需须经 `String.fromCharCode(36)` 运行期生成）。
- **路径拼接坑（实测修复）**：`rel` 剥 `/swagger/` 前缀后**无前导斜杠**（staticFiles 的 `rel = req.path` 自带 `/`），`full = dirBase + rel` 会拼成 `distDir文件名` → 未命中放行 404——显式补 `"/"`：`full = dirBase + "/" + rel`（T7b/T7c 首跑 FAIL 的根因）。

### 27.3 测试与验收

- **ServerP3Test T7 七断言全绿**（port 19436）：T7a `/swagger` index 四引用（bundle.js/css/openapi.json/text-html）/ T7b css dist 直出（text/css）/ T7c bundle.js dist 直出（application/javascript）/ T7d `'..'` 穿越段 403 / T7e dist 未命中放行（尾环 404）/ T7f 普通路由不受影响（/ping 200 pong）/ T7g 用户已注册 `/swagger` 让位（用户应答 "mine"）。
- **fixture**：`SLangCore/test/Other/ServerTest/swagger-ui/`（官方 swagger-ui-dist@5 真实 dist 两文件）；**测试宿主 cwd = 测试工程目录**（宿主 Main 在 RunCVM 前切 `Environment.CurrentDirectory = projectDir`，`p2_hooks.txt` 等相对路径产物落此为证）→ dist 用裸相对路径 `"swagger-ui"`。
- **回归**：ServerTest 全量 **241 OK / 0 FAIL**（基线 234 + T7 新增 7）。
- **版本**：0.0.43（纯 SL 侧改动，无 C VM/锚点变更，无需 bump）。

**下一步（v1 收官后展望）**：TLS 服务端（留待部署需求触发）/ 基准扩展（release 构建 + 32MB+ 档 + 并发客户端维度）/ 控制器池化裁决维持拒绝（§26.1）。

---

## §28 P10 落地实录（2026-10-27，P3 裁剪三项补齐）

P3 裁剪的三项收尾：**Response.setCookie / Request.cookie**（会话侧读写对）、**Request.formAll**（同名多值）、**路由级中间件**（RouteInfo.use + params 尾参注册）。端口约定 19501–19502。

### 28.1 setCookie / cookie（会话侧读写对）

- **写侧 `Response.setCookie` 两形态**：`setCookie( name, value )` 裸对；属性形态 `setCookie( name, value, path, maxAge, secure, httpOnly, sameSite )`（六属性全显式传参，SL 无可选参/属性语法——属性形态签名与 §4.4 表一致）。`path/maxAge/sameSite` 空串直落三属性；`secure/httpOnly` 按 bool 直落；**SameSite=None 自动补 Secure**（浏览器强制约束，§4.4 语义）。
- **Set-Cookie 唯一头写出语义**：唯一"允许逐行重复、禁止逗号合并"的头——三条头写出路径（`send`/`sendText` 编码、`end` 编码、`sendFile` 头侧车）均从 `_setCookies` 表逐条独立写 `Set-Cookie:` 行（同名两次 = 两条独立头行，多值语义合法）。
- **读侧 `Request.cookie( name )`**：Cookie 头惰性解析（首次访问触发 `_parseCookies`，缓存至 `_cookiesParsed`）；**多条 Cookie 头合并处理**（`headerAll` 遍历，分号切段）；值两端空白剥离；键重复后者覆盖。配套 `hasCookie( name ) → bool` 与 `cookieKeys() → List<string>`（无 cookie 头：`cookie()` 返回 null + 空键表 + `hasCookie` false）。

### 28.2 路由级中间件 + 🔥 SL params 装箱语义实锤（关键复盘）

- **设计形态**（§6.9）：`app.onGet( path, handler, mw1, mw2 )` params 尾参注册 / `RouteInfo.use( mw )` 链式登记（`r1.use(mwA).use(mwB)`）/ 组前缀同款 `group.onGet( path, handler, mws… )`。执行序 = **全局中间件 onion → 路由级中间件（登记序）→ handler**；路由级 mw 短路（写 403 后不 `nx.go()`）即止，handler 不执行。
- **首跑 4 FAIL 根因实锤**（T5a/T5b/T6b mw 全部未执行 + T4b 语义误判）：**SL `params` 无 C# 式"尾实参数组透传"语义**——Front `MetaVisitCall`（`MetaVisitCall.cs` params 分支）把"逐个多余位置实参"用 `MetaBraceAssignStatements` 装进 `object[]` 数组作为单实参传递；`MetaParam.cs` 中存在被注释掉的"尾实参是数组则透传"草稿 = **从未实现**；`md/syntax/function.md` L61 亦只承诺"把传入的若干实参封装为数组"。→ 库内把现成数组作为尾实参传给 params 形参（`Router.add(verb, path, fn, mws)`、`useAll(params Function[])`）时被**再包一层**（长度 1、元素为数组），遍历元素调用 Function 静默失败。
- **修复（SL 侧规避，不改 Front 语义）**：
  1. `RouteInfo.useAll` 形参从 `params Function[]` 改**显式 `Function[]`**（数组引用直传安全）；
  2. `Server.sl` HttpServer on* 全家族九个 params 版（onGet/onPost/onPut/onDelete/onPatch/onHead/onOptions/onAny/on）与 `Router.sl` RouteGroup on* 七个 params 版改**两步转发**：`RouteInfo r = Router.add( verb, path, handler )` + `ret r.useAll( mws )`（mws 为 params 形参收到的装箱数组，引用直传不再嵌套）；
  3. `Router.add` params 版保留（独立实参形态 `Router.add("GET", path, fn, mw1, mw2)` 有效），内部 `r.useAll( mws )` 随签名修复自动归位；注释显著标注"直传数组请用三参 add + useAll(数组)"。
- **T4b form 语义裁决**：§6.4 L1219 明文"键重复后者覆盖前者"→ `form()` **末值语义 = v1 正确行为**；P10 实现期曾误写"form = formAll 首值"注释与测试预期（first=a），对照设计文档修正为 first=c（Request.sl 注释同步）；`formAll` = 出现序全收集（urlencoded `collectFormMulti` 逐段扫描 + multipart 普通字段并入平行表）。**已知限制**：multipart 同名多字段在 formAll 当前仅并入单值（`_mpFields` 覆盖语义表取 1 值）——urlencoded 场景全量正确，multipart 同名多字段留待后续（v1 无常规场景）。

### 28.3 测试与验收

- **`test/Other/ServerTest/ServerP10Test.sl` T1–T6 共 17 断言全绿**（port 19501–19502）：T1 Set-Cookie 头行出现/同名两次两条独立头行/头行总数 / T2 属性逐项（Path/Max-Age/Secure/HttpOnly/SameSite=Strict）/SameSite=None 自动补 Secure / T3 cookie 读回+hasCookie+cookieKeys/无 cookie 头三态/多条 Cookie 头合并 / T4 formAll 出现序取全（a,b,c）+ form() 覆盖末值（first=c）+ 无字段空表 / T5 执行序（全局→路由级1→路由级2→handler）/路由级短路 403 handler 不执行/无路由级 mw 路由不受影响 / T6 RouteInfo.use 链式（A→B→handler）/RouteGroup.onGet 尾参形态（前缀拼接+mw 执行）。
- **回归**：ServerTest 全量 **259 OK / 0 FAIL**（P0–P10 + SwaggerUI 全套件，12 组 all done），ExpendTest/NetTest 不受影响（不引 SLangServer）。
- **登记**：`ServerTest.jsonc` compileFiles 增 `ServerP10Test.sl` 条目；`ServerTest.sp` 挂 `_test_` 调度（与其他 P* 用例同构）。
- **版本**：0.0.45（R17 四端同步——本阶段含 SL 库 API 行为修正，锚点 bump）。

---

## §29 多监听器落地实录（2026-10-28，一工程多端口 + 路径隔离，v1.1）

**背景**：用户需求"一个工程监听两个端口、使用不同路径"——HttpServerCore 为模块级静态单例（§12 偏差 1，跨模块多实例化实例态串扰），多实例路线不可行；故**保持静态架构、实现引擎多监听器**：监听器 tag 贯穿连接链，路由按 scope 过滤，达成"单静态引擎 × N 监听端口 × 路由视图隔离"。

**产物**：
- `HttpServerCore.sl`：`_servers/_serverTags/_serverPorts` 三平行表 + `listen( host, port )`（tag 分配 / running 态立即 bind / 未启动入缓冲）+ `_bindListener` + `_tagOf/_portOf`（TcpServer 身份扫描）+ accept 派发改 `spawnClosure2( f, client, srv )`、`_runConn/_handleConnection` 携 srv + `req.localPort` 构造后绑定 + `stop()` 遍历关全部监听器；
- `Server.sl`：`HttpServer.listen( port )` / `listen( host, port )` 门面（返回 `ServerListener`）+ 新公共类 **ServerListener**（模块内构造，RouteGroup 同款模式；`tag/port/host` 元数据 + on* 全家族含 params 尾参变体 + `websocket`）；
- `Router.sl`：`RouteInfo.scope`（0 = 所有监听器可见 / N = 仅监听器 N）+ `_scopeOk` 过滤 + `match/findBest/findWs/allowMethods` 加 tag 重载（旧签名转发 tag=0）+ `_pickBest` 同静态段数时本监听器专属路由（scope==tag≠0）优先 + `_dupScan` 判重带 scope（跨监听器同名 pattern 合法）；
- `Plugin.sl`：`_Pipeline` 构造加 `Int32 tag` 形参，`_run` 尾环 `_tail(..., tag)` 透传；
- `Request.sl`：`_localPort` 字段 + `localPort` get/set 访问器；
- 验收用例 `test/Other/ServerTest/ServerMultiListenTest.sl`（M0–M2d，端口 19521–19523）+ `ServerTest.jsonc`/`ServerTest.sp` 登记。

**验收**：ServerMultiListenTest M0/M1a–M1g/M2a–M2d 共 12 项全 OK（M0 tag/port 元数据；M1a-b 全局路由双端口可见；M1c-d 监听器路由仅本端口；M1e req.localPort；M1f 监听器视图覆盖全局同名；M1g 监听器视图 405+Allow；M2a running 态动态 listen 立即 bind；M2b-c 动态端口路由 scope；M2d stop 后 Net.Tcp.connect 探测断连）；ServerTest 全量回归除 2 项 swagger dist 资产缺失（T7b/T7c 存量环境问题，与本阶段无关）外全绿。

**实况要点 / 语言坑**：
1. **tag 身份扫描而非句柄表直查**：`_tagOf/_portOf` 对 `_servers` 表逐元素引用比对——srv 实参经 `spawnClosure2` 跨协程传值后引用相等性可靠（P0 探针结论同源）；未命中兜底 tag=1 / `_listenPort`（防御性，正常路径不可达）。
2. **`req.localPort` 走 set 访问器**（`public set void localPort( Int32 p )`，ByteStream 同款语法）——请求构造签名保持 §6.1 十参形态不动，`_handleConnection` 构造后赋值；对只有 get 的访问器直接赋值在 Front 报 `MetaCoreParseCallNodeNotFoundInClass`（节点未找到）。
3. **Front 新检查 `NodeStructParseIfNextNoBlankLine`**（"if语句与下一个if语句之间必须空一行(防止读取错误)"）对全模块生效且含存量文件，本次顺带清理：SLangServer 模块（Jwt/Docs/WebSocketServer/Plugins/Plugin/HttpBodyReader/MultipartReader 等 9 文件）与 ServerTest 模块（12 文件 44 处）批量补空行。精确规则：`}` 后必须**紧跟空行**再接 if（`}` + 注释 + if 亦违规、`}` + 注释 + 空行 + if 亦违规——空行必须紧跟 `}`）；`}` + 空行 + 注释 + if 合法；elif/else 挂接不受影响。
4. **Front 行首 `&&` 裸续行不再可用**（`解析发现没有该节点!!Lex: &&`，ServerP3Test/ServerBench/ServerP7Test 共五处存量报错）——**括号包裹**的多行布尔表达式仍合法，裸续行须合并单行；错误行列号不可按字面定位（col 常超行宽），按"哪个 token 在哪行"排查。
5. **监听器 tag 分配**：主监听器恒 = 1（`start()` 的配置端口）；`listen()` 自 2 递增（`_nextTag`，`stop()` 重置）。`start()` 前登记的 `listen()` 进缓冲（`_pendHosts/_pendPorts/_pendTags`），start 消费缓冲统一 bind；running 态 `listen()` 立即 bind 并 spawn accept（M2a）。
6. **路由匹配序**：`_pickBest` 平局判定（同静态段数）依次为 本监听器专属路由（rHit）> 全局路由（bHit）> `_seq` 注册序（M1f 实测覆盖语义）；`allowMethods` 同样按 tag 过滤——监听器视图 405 的 Allow 头只列本视图允许的方法（M1g）。
7. **存量测试批量补空行用脚本完成**（PowerShell 扫描 `}` 行后非空行直连 if 的模式，从后往前插空行；`}` 行判定必须 `Trim()`——`TrimEnd()` 对缩进行恒不等导致首轮零匹配踩坑）。
