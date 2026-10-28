# P1 · 若依系统 SLang 重写 + 官网完善 —— 执行计划

> **定位**：吃自己的狗粮（dogfooding）—— 打磨语言最快的手段 + 语言实力的展示橱窗。
> **理由**：HttpServer 已到 P10 + Mysql 全绿 + Sqlite/Redis/Log 就绪，后端技术栈 90% 现成；若依体量会把字符串/JSON/并发/持久层全部真实暴露，每个 bug 都是改进清单。
> **依赖**：无（可与 P0 并行）。**建议节奏**：1~2 个月，分四阶段。

---

## 一、目标

1. 若依 RuoYi 核心功能全部用 SLang 实现，与现有 `SLangOfficialWebsite\csharp-server`（.NET 版）功能对齐；
2. 产出性能对比数据（SLang vs .NET 版，同一 BenchMark 矩阵）；
3. 官网完善：运行页接 WASM Playground、若依在线 Demo、文档站挂载。

## 二、现状与差距（可直接复用的资产）

| 资产 | 位置 | 若依对应需求 |
|------|------|--------------|
| HTTP 服务框架 P0–P10 | `SLangCore\Lib\SLang\Server\`（SERVER_DESIGN.md §12–§28） | 路由/中间件/上传/Jwt/rateLimit/OpenAPI/SwaggerUI 全有 |
| MySQL 客户端 | `SLangCore\Lib\SLang\Mysql\`（MysqlTest.sl 31 断言全绿） | 主存储 |
| Sqlite / Redis | Std 库 | 缓存（验证码/会话）、轻量场景 |
| Jwt（sign/verify HS256） | Server 框架内 | 登录鉴权 |
| 日志系统 | Std（Log/Logger/Profiling/Trace/Monitor） | 操作日志底层 |
| 定时/协程 | Timer + spawn/await + isolate | 定时任务 |
| .NET 版参照实现 | `SLangOfficialWebsite\csharp-server\`（完整若依） | 移植对照真源 |
| 前端 | `SLangOfficialWebsite\admin-ruoyi-ui\`（Vue 版若依前端，可直接复用） | 管理界面零改动 |
| 官网框架 | `SLangOfficialWebsite\web\`（Astro）+ doc 设计稿 00–18 | 发布载体 |
| 性能基线 | ServerBench M1/M2（SERVER_DESIGN.md §25） | 对比矩阵方法 |

**差距**：无完整 ORM/查询构造器（先手写 SQL）、无验证码生成（Base64/Sha1 有，可拼）、若依的代码生成器需自研（正好验证 SLang 字符串/模板能力）。

## 三、任务分解

### 阶段 A · 登录与用户管理（第 1~2 周）

**A1 工程骨架**
- 新建 `SLangRuoYi` 工程（`slang new project SLangRuoYi`），目录建议 `d:\project\lang\SLangRuoYi\`（与官方库分离，references 引 `Core/Std/Math/SLangServer/SLangMysql`）；
- 数据库初始化脚本：从 csharp-server 版 SQL（建表 user/role/menu/dept…）直接复用。

**A2 登录链路**
- `POST /login`：用户名密码校验（BCrypt 摘要——Std 缺则先用 Sha1+盐过渡，缺口记录）→ 签发 Jwt；
- 图形验证码：Canvas 绘 SL 侧生成（samples/GUI 已有 Canvas 基础）或 Redis 存储 token 方案；
- 中间件链：logger → rateLimit（登录防爆破）→ auth。

**A3 用户管理 CRUD**
- 用户列表（分页——HttpServer 分页约定）/ 新增 / 修改 / 删除 / 重置密码 / 状态启停；
- 全部手写 SQL + Mysql cursor + `?` 绑定（现成模式，参照 MysqlTest）。

**验收**：admin-ruoyi-ui 前端不改动，指向 SLang 后端能登录并跑通用户管理页。

### 阶段 B · RBAC 权限模型（第 3~4 周）

**B1 三表模型**：用户–角色–菜单，角色–菜单，用户–角色关联 + 部门表（树形，复用 Std Tree 容器）；
**B2 菜单/路由接口**：`GET /getRouters` 按角色动态下发前端路由树（JSON 深组装——真实考验 JsonValue 能力）；
**B3 权限注解**：`@RequirePerms("system:user:list")` 挂在控制器方法上，中间件统一签验（attribute + 中间件管道，SERVER_DESIGN §26 已有 @InstanceAttr 单例底座）；
**B4 角色管理 / 菜单管理 / 部门管理页面接口**。

**验收**：不同角色登录看到不同菜单；无权限接口 403。

### 阶段 C · 日志与监控（第 5 周）

- **C1 操作日志**：AOP 式中间件记录请求（方法/URL/入参/耗时/操作人），异步落库（spawn 写入不阻塞响应）；
- **C2 登录日志**：登录成功/失败记录 + IP；
- **C3 在线用户**：Redis 会话 + 强退；
- **C4 服务监控**：`/monitor/server` 返回 CPU/内存（Environment 库 + Monitor 库拼装）。

### 阶段 D · 定时任务与代码生成器（第 6~8 周）

- **D1 定时任务**：cron 表达式解析（SL 自研，考验字符串）→ Timer + isolate 并行执行任务 → 任务管理页（启停/立即执行/日志）；
- **D2 代码生成器**：读 information_schema 表结构 → 模板生成 .sl 控制器/服务/SQL/前端 vue 文件——**这是 SLang 自举能力的最佳展示**（生成目标就是 SLang 代码本身）；
- **D3 通知公告 / 字典管理 / 参数配置**（简单 CRUD，收尾）。

### 阶段 E · 性能对比与发布（第 9~10 周）

- **E1 性能矩阵**：SLang 版 vs csharp-server 版跑 ServerBench 同矩阵（登录接口 / 列表分页 / 并发压测），记录 QPS/P99/内存；
- **E2 在线 Demo 部署**：服务器部署 SLang 版（deploy/ 脚本已有 nginx 配置可复用），官网挂"在线体验"入口；
- **E3 对比数据上官网**：下载页/关于页引用（"本系统由 SLang 编写"）。

### 阶段 F · 官网完善（并行推进，依赖 E2）

| 任务 | 内容 | 依赖 |
|------|------|------|
| F1 运行页接 Playground | `csimple_lang\wasm\playground.html`（浏览器写 SL → 编译 → 执行）接入官网"运行页"（doc/06 设计已有） | 无，**最先做** |
| F2 文档站 | md/ 93 篇文档挂 Astro 站点（doc/14 i18n 方案已有） | 无 |
| F3 若依在线 Demo | E2 产出挂官网 | E2 |
| F4 性能数据页 | E1 数据可视化 | E1 |

## 四、工作流约定（重要）

1. **缺陷清单工作流**：移植中发现的每个语言/库缺陷，按 R10 追加到 `md/ai/troubleshooting/` 对应分片，并登记到新文件 `SLangRuoYi\DEFECTS.md`（列：现象/最小复现/严重度/状态）——**非阻塞项记录不立即修**，每周集中清一次；
2. **四端版本锚点**：每个阶段完成即 Z+1（R17）；
3. **不自研 ORM**：阶段 A~D 全部手写 SQL；查询构造器（query builder）作为若依完成后的独立小项评估。

## 五、验收标准

- [ ] admin-ruoyi-ui 前端零改动接入，登录/RBAC/用户角色菜单部门/日志/定时任务/代码生成全链路可用；
- [ ] SLang vs .NET 性能对比矩阵（≥3 接口 × 并发梯度）成文可查；
- [ ] 在线 Demo 稳定运行一周无重启；
- [ ] `DEFECTS.md` 中 P0/P1 级缺陷全部闭环，其余有排期；
- [ ] 官网运行页 Playground 上线（F1）。

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| 移植暴露缺陷过多导致工期失控 | 阶段切分独立验收；缺陷分级，P2/P3 级记录不立即修 |
| BCrypt/验证码等库缺口 | 缺口走"过渡方案 + DEFECTS 登记"，不中断主线 |
| 前端接口契约偏差 | 以 csharp-server 版响应 JSON 为对照真源，逐接口 diff |
