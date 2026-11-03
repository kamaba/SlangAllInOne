# docs-web — Markdown 文档转网页 + API 索引（md/lib → 静态站点）

> **一句话**：把 `md/lib` 全部 Markdown 一键转成带样式的静态网页站（首页 / API 索引 / 每篇一页），
> 同时产出机器可读索引文件 `api/index.json`——**后管平台按该索引文件即可在官网自动挂接「API 文档」入口**，
> 点进去可按分组浏览具体类与成员（字段 / 构造 / 方法 / 属性），并跳转详情页。

- 工具位置：`SlangAllInOne/tools/docs-web/`（Node 零依赖，无 npm install）
- 产物根（R9）：`SlangAllInOne/out/docs_web/`
- 首批数据源：`SlangAllInOne/md/lib`（Core / HttpServer / Math / Std / WebUI + 根级 Server.md，共 180 篇）

---

## 1. 快速开始

```powershell
# 生成（默认 md/lib → out/docs_web）
node tools/docs-web/build-docs-web.js

# 本地预览（http://127.0.0.1:8931/，Ctrl+C 停止）
node tools/docs-web/serve.js
# 或
powershell -File tools/docs-web/preview-docs-web.ps1

# 换源 / 换输出 / 换站名
node tools/docs-web/build-docs-web.js --src md/lib --out out/docs_web --site-name "SLang 标准库文档"
```

官网部署：把 `out/docs_web/` 整目录发布到任意静态服务器（Nginx / OSS / 后管静态托管均可），入口 `index.html`。

## 2. 后管平台（admin-server，可操作）

```powershell
node tools/docs-web/admin-server.js 8932     # 控制台 http://127.0.0.1:8932/admin（站点同端口根路径）
```

三合一服务：静态托管文档站 + 后管控制台 `/admin` + 管理 API。控制台三大块：

| 块 | 能力 | 落点 |
|----|------|------|
| **版本管理** | **本体（Front / C VM / 宿主）/ VSCode / 插件 / 包 分组件独立展示与改写**——扫描值实时读自仓库锚点，保存即写回锚点文件并留痕 | `version-scan.js`（扫描+写回）· `version-history.json`（变更历史） |
| 站点数据 | site-data.jsonc 在线编辑（友情链接 / 社区资讯 / 自举句），保存前校验 | `POST /api/site-data` |
| 一键重建 | 执行 build-docs-web.js 并回传日志尾 | `POST /api/rebuild` |

API：`GET /api/versions`（分组版本+历史）/ `POST /api/version/set {key,value}` / `GET|POST /api/site-data` / `POST /api/rebuild`。仅监听本机；静态托管官网时 admin 页自动降级为只读展示（数据来自生成期快照）。

### 版本分开管理（2026-11-03 用户改版，废止「四端同步 +1」）

| 组 | 版本源锚点 | 现值示例 |
|----|-----------|---------|
| 本体 | Front `CommandExecutor.VersionString` / C VM `SLVM_VERSION_STRING` / 宿主 csproj `<Version>` | `0.0.68`（三锚点联动，本体内部仍一起动） |
| VSCode | `package.json` + `package-lock.json` 双字段 | `0.0.67`（独立演进） |
| 插件 | `plugin/<id>/plugin.jsonc` → `plugin.version` | csharp_mono `0.1.0` 等 4 个 |
| 包 | `SLangCore/Lib/**/*.jsonc` → `project.main/sub/buildVersion` | Core `0.1.1`、Math `0.2.0` 等 9 个 |

分组件版本同时写入 `api/index.json` 的 `versions` 字段并展示在每页页脚（`本体 v0.0.68 · VSCode v0.0.67`），官网/后管直接消费。

## 2.1 后管平台自动生成（集成方式）

1. **触发**：后管平台定时 / 手动触发执行 `node tools/docs-web/build-docs-web.js`（工作目录任意，内部按脚本位置定位仓库根）；
2. **消费索引文件**：读取 `out/docs_web/api/index.json`（结构见 §4），按 `groups → docs / classes → members` 三级在后台挂接「API 文档」入口；
3. **两条展示路径**（可并存）：
   - **托管整站**：直接静态托管 `out/docs_web/`，后管只需挂一个入口链接到 `index.html`（首页）或 `api/index.html`（API 索引）；
   - **后管自渲染**：后管读 `api/index.json` 自行渲染页面（不必用生成的 HTML）。
4. 全流程无人工干预：md 更新 → 重跑脚本 → 站点与索引全量重建（默认 `--clean` 清空产物目录后重生成）。

## 3. 产物结构

| 路径（相对 `out/docs_web/`） | 内容 |
|------|------|
| `index.html` | 站点首页：统计（文档/类/成员数）+ 分组卡片（每组文档列表）+ 入门/API 索引/关于入口 + 后管平台说明；**自举句以 HTML 注释形态嵌入**（按用户要求先注释掉，不上屏） |
| `getting-started.html` | **入门页（使用示例专位）**：可运行声明横幅 + 快速开始（Release / 源码构建）+ 第一个程序三件套（`.sl`/`.sp`/`.jsonc` 源码直读磁盘）+ 编译运行命令 + 实测输出 + MDExample 语法示例（一键工程 `MDExamples.sp`）+ 示例源码索引表（含实测状态） |
| `examples.html` | **示例库页（使用示例全量展示）**：10 例逐例源码（直读磁盘）+ 实测输出（逐字引用）+ 搜索框 + 「自举实验树」清单（231 文件历史手稿，单列说明不在可运行声明内） |
| `about.html` | **关于页（社区资讯大分类）**：社区介绍 / 代码仓库 / 版权信息 / 提案（RFC） / 节点记要 / 赞助 + **友情链接**卡片与申请收录说明 |
| `api/index.html` | **API 索引页**：全部类/枚举卡片 + 顶部搜索框（类名/方法/签名/说明，纯前端过滤）+ 分组/成员种类筛选，点击类名跳详情页锚点 |
| `api/index.json` | **索引文件（后管平台消费的契约）**，见 §4 |
| `<分组>/<文档>.html` | 每篇 md 一页：面包屑、页内目录（TOC 粘性侧栏）、代码高亮、API 表（种类徽章）、类锚点（`#cls-类名`）、API 快跳 chips |
| `assets/style.css` | 全站样式（亮/暗自适应） |

页面导航关系：顶栏五入口「首页 / 入门 / API 索引 / 库目录 / 关于」（即"文档里增加 API 的入口"）；API 索引页与首页分组卡反向链回各文档页。

## 3.1 站点数据外置（`tools/docs-web/site-data.jsonc`）

关于页与首页可变文案**外置**在 `tools/docs-web/site-data.jsonc`（jsonc，支持 `//` 注释），**后管平台直接改此文件再重跑生成器即全站生效**，无需动生成器代码：

| 字段 | 用途 |
|------|------|
| `site.name` | 站点名（CLI `--site-name` 可覆盖） |
| `bootstrapNote` | 自举句——当前按用户要求**注释化**（首页以 `<!-- … -->` 嵌入不上屏；启用时由后管插桩展示） |
| `friendLinks[]` | 友情链接卡片（name/url/desc；申请收录审核后在此追加） |
| `community.intro/repos/copyright/proposal/minutes/sponsor` | 社区介绍 / 代码仓库 / 版权信息 / 提案（RFC） / 节点记要 / 赞助 六大分类文案（缺省值复用 README/LICENSE，未有大项为新增占位） |

文件缺失/损坏时生成器回落内置默认并告警，不阻塞出站。

## 4. 索引文件契约（`api/index.json`）

```jsonc
{
  "generator": "docs-web", "generatorVersion": "1.0.0",
  "generatedAt": "2026-11-03T…Z", "source": "md/lib",
  "site": { "name": "…", "entry": "index.html", "apiIndex": "api/index.html", "indexFile": "api/index.json" },
  "stats": { "docs": 180, "groups": 6, "classes": 333, "members": 5132 },
  "groups": [ { "name": "Core", "label": "Core", "path": "md/lib/Core",
                "readme": "Core/README.html", "docs": 79, "clsCount": 155 } ],
  "docs":   [ { "file": "md/lib/Core/String.md", "page": "Core/String.html", "group": "Core",
                "title": "String.sl", "type": "api|guide|index",
                "classes": ["String"], "headings": [ { "lvl": 2, "text": "String", "anchor": "cls-String" } ] } ],
  "classes":[ { "name": "String", "kind": "class", "group": "Core", "module": "String.sl",
                "file": "md/lib/Core/String.md", "page": "Core/String.html", "anchor": "cls-String",
                "summary": "…",
                "members": [ { "kind": "方法", "name": "front",
                               "signature": "string front(int index)", "desc": "…" } ] } ]
}
```

- `page` / `readme` 为站点根相对路径；`anchor` 即详情页内 `id`，官网/后管拼 `page + '#' + anchor` 直达类详情。
- `members.kind ∈ 字段 | 构造 | 方法 | 属性`。

## 5. API 提取规则（依赖文档形态）

`md/lib` 为自动提取的 API 参考文档（真源 = `SLangCore/Lib` 各 `.sl`），生成器按以下形态解析：

1. H1 = 模块名（`Xxx.sl`）；
2. `## class \`X\`` / `## enum \`X\`` → 类分节（锚点 `cls-X`），节内首个 `- **说明**：…` 作为类摘要；
3. `| 类型 | 签名 | 说明 |` 三列表 → 成员表（首列 种类徽章，签名进 JSON `signature`）；
4. 无类分节的文档（README 索引 / 指南页）正常转网页，`type` 标为 `index` / `guide`，不产 API 条目。

新增库文档沿用上述形态即可被自动收录；其他目录（如 `md/syntax`）后续接入只需 `--src` 指向对应目录（或扩展脚本多源循环，暂未做多源合并）。

## 6. 实现要点 / 约束

- 纯 Node 标准库，**零 npm 依赖**；`build-docs-web.js` 单文件含 md 解析器、轻量代码高亮、页面模板与内嵌前端搜索脚本；
- HTML 转义保留源文本已有实体（lib 文档签名含 `&lt;` 等），不双重转义；
- 产物一律 UTF-8（R16）；只写 `out/`（R9）；
- 重建即全量（`--no-clean` 可保留旧产物增量覆盖）。

## 7. 验收记录

| 项 | 结果 |
|----|------|
| `node build-docs-web.js` | ✅ 180 篇 · 6 分组 · 333 类/枚举 · 5132 成员，无警告 |
| 详情页（`Core/String.html`） | ✅ API chips / 类锚点 / 种类徽章 / TOC / 面包屑（relRoot 正确） |
| 跨文档链接 | ✅ README 类索引表 `Xxx.md` 链接自动改写为对应 `.html` |
| API 索引页 | ✅ 内嵌索引数据 + 搜索/分组/种类过滤脚本 |
| `serve.js` 本地预览 | ✅ 首页与 API 索引页在 IDE 内置浏览器打开正常 |
| `api/index.json` | ✅ 结构化索引（§4 契约）|
| **HelloWorld 示例实测（2026-11-03）** | ✅ 新增 `samples/HelloWorld/HelloWorld.sp` + `HelloWorld.jsonc`（原目录缺工程文件，旧 `test1.sp` 为遗留未动）——`dotnet run --project SlangAllInOne -- …/HelloWorld.sp` 编译 → C VM 执行输出 `Hello World` |
| **可运行集合全量实测（2026-11-03 二轮）** | ✅ 10/10：① 根级 4 个脚本示例现代化重写并各配工程对（`Fibonacci`/`NineTable`/`DelayPrint`/`MergeLetters.sp+.jsonc`）——修复 `import Std` 缺失、`next` 保留字、`${表达式}` 插值、List 下标写、保留字 `out` 五类旧语法问题，输出逐字核对（`11235813213455` / 九九表 9 行 / `cost=204ms` / `merged: acebd`）；② `samples/MDExample/MDExamples.sp+.jsonc` 一键工程（5 例合并 + jsonc `global.data.var1=42` 注入）+ `Doc01` toString 补 `string` 返回类型——输出 `Rectangle(10 x 4)`…`var1=42` 全 10 行核对 |
| **自举实验树定性（2026-11-03）** | `samples/SLang/source/` 231 个 .sl 为 C# 风格历史手稿（`using`/`return` 旧语法），整库编译验证一轮确认不兼容现行语法——示例库页单列「历史参考 · 未接入编译验证」，不进可运行声明；生成的 `SLangFeatures.sp/.jsonc` 已撤销 |
| 入门页 / 示例库页 / 关于页 | ✅ 顶栏六入口（首页/入门/示例/API 索引/库目录/关于）；示例源码直读 `SLangCore/samples`（与仓库同步）；关于页六大社区分类 + 友情链接卡片 |
| 自举句 | ✅ 按用户要求以 HTML 注释嵌入首页（不上屏），文案源 = `site-data.jsonc` `bootstrapNote` |
