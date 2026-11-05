# SPM 注册中心接口与 md5 校验/重下载机制

> 适用范围：后管平台（csharp-server 门户，`SLANG_API_BASE`，默认 `http://localhost:35221`）对外提供的「发布内容查询 / 解析」接口，以及 spm 客户端据此实现的 **md5 比对 + 按需重下载** 机制。
> 关联：`SLangAllInOne/Project/Spm/RegistryClient.cs`、`SLangAllInOne/Publish/PublishCommand.cs`、官网 `SLangOfficialWebsite/web/`（下载中心与详情页实时查询，见 doc/18 §9）。

---

## 1. 总览

- 后管平台是插件 / 包的**唯一真源**：发布内容（元数据 + 编译产物下载地址 + md5）由它托管。
- 官网（Astro 静态站）**不再内置假数据**：下载中心的「插件 / 包中心」与各详情页在浏览器端向后管平台拉取，渲染实时发布内容（实现见 `web/src/lib/hub.ts`、`web/src/pages/download.astro` 的 `loadHub()`）。
- spm 安装/更新某条目时，先向后管平台「解析」得到该（类型, 名称, 版本）对应的 **md5 校验码 + 下载地址 url**，再用 md5 比对本地已缓存文件；不一致就按 url 重新下载，下载后再次校验 md5，确保文件完整。

---

## 2. 对外解析接口（spm 用）

### 2.1 请求

```
GET /api/registry/resolve?type=<类型>&name=<名称>&version=<版本>
```

| 参数 | 说明 | 取值 |
|------|------|------|
| `type` | 条目类型 | `本体包` / `vscode` / `插件` / `包`（映射见 §5） |
| `name` | 条目名称（插件 id / 包 id / 本体名 / vscode 扩展 id） | 字符串 |
| `version` | 版本号 | 语义化版本，如 `1.0.0`；可传 `latest` 取最新 |

> 端口/前缀说明：官网经 `web/src/pages/api/registry/resolve.ts` 同源转发到 `SLANG_API_BASE + /api/registry/resolve`，调用方（spm CLI / 官网）统一走 `/api/registry/resolve`。

### 2.2 响应

```json
{
  "code": 200,
  "data": {
    "type": "插件",
    "name": "echo",
    "version": "1.0.0",
    "md5": "3e25960a79dbc69b674cd4ec67a72c62",
    "url": "https://pkg.slang.dev/plugins/echo/1.0.0/echo.slb"
  }
}
```

| 字段 | 含义 |
|------|------|
| `md5` | 该版本产物文件的 **MD5 校验码**（32 位十六进制），用于本地文件比对 |
| `url` | 产物文件（`.slb` / `.vsix` / 归档包等）的**下载地址**；md5 不一致时按此重下载 |
| `version` / `name` / `type` | 回显，便于调用方确认解析结果 |

错误时返回 `{ "code": 404, "msg": "not found" }` 或 `{ "code": 500, "msg": "..." }`（后端不可达），调用方应视为「无法解析」并提示用户。

---

## 3. spm md5 比对 / 重下载机制

spm 在执行「安装 / 更新 / 运行前校验」时，对每个依赖条目按如下流程处理：

```
1. 解析：GET /api/registry/resolve?type&name&version → { md5, url }
2. 本地命中：若本地已缓存该 (type,name,version) 的产物文件：
     a. 计算本地文件 md5
     b. 与解析返回的 md5 比对
        - 一致   → 直接使用，跳过下载（省流量）
        - 不一致 → 跳转 3（重下载）
   若本地未缓存 → 跳转 3
3. 重下载：按 url 下载产物到本地缓存
4. 校验：计算下载文件 md5，与解析 md5 比对
     - 一致   → 安装/解包完成
     - 不一致 → 判定文件损坏/被篡改，删除缓存并【报错退出】（不静默使用），可选提示 `--retry`
5. 记录：把 (type,name,version) → 本地路径 + md5 写入 spm 锁文件（如 `slang.lock` / `modules/.spm-cache.json`）
```

**为什么用 md5**：md5 是后管平台在「发布」时随产物一并算出的内容指纹；spm 用它判断「本地文件是否就是平台发布的那个版本」。一旦内容有变（重新发布、传输损坏、缓存被改），md5 必然不一致，spm 即触发 `url` 重下载并二次校验，形成「发布即可信、缓存可校验、异常可回滚」的闭环。

> 设计点：md5 仅做**完整性/一致性**校验，不替代签名。若未来需要防篡改，可在 `data` 中附加 `signature` 字段由 spm 做签名校验（本接口预留扩展）。

---

## 4. 列表 / 详情接口（官网实时查询用）

官网下载中心与各详情页消费以下接口（均由 `SLANG_API_BASE` 提供，官网同源代理于 `web/src/pages/api/*`）：

| 接口 | 用途 | 返回 |
|------|------|------|
| `GET /api/plugins` | 插件列表 | `{ code, data: [PluginDTO...] }`（或裸数组） |
| `GET /api/plugins/:id` | 单个插件 | `{ code, data: PluginDTO }` |
| `GET /api/packages` | 包列表 | `{ code, data: [PackageDTO...] }` 或 `{ packages: [...] }` |
| `GET /api/packages/:name` | 单个包 | `{ code, data: PackageDTO }` |

**DTO 约定**：复用官网既有本地快照的字段（`web/src/data/plugins/*.json` 与 `web/src/data/packages/*.json`），即后端返回的 PluginDTO / PackageDTO 字段与这些 JSON 完全一致（如插件：`id, version, vendor, official, short, description, platforms, capabilities, compat, license, updatedAt, downloads, bundled, demo, repo, meta, versions, readme`；包：`id, version, description, category, author, license, minSlang, updatedAt, downloads, isExample, repo, dependencies`）。这样官网 `web/src/lib/hub.ts` 的渲染逻辑无需为后端数据另写适配层。

> 部署提示：`web` 为 `output: 'static'`，详情页在 build 期按本地快照枚举路由；要让「后端新发布的条目」也拥有可直达的详情页，需在发布后重新 `astro build`，或改用按需渲染（adapter）。列表/中心面板本身为浏览器端实时拉取，不受此限制。

---

## 5. 类型映射

`type` 入参的四种取值与内部 registry 种类的对应（实现侧参考 `RegistryClient.cs`）：

| 对外中文标签 | registry 种类 | 产物形态 | 典型 url 后缀 |
|--------------|--------------|----------|---------------|
| `本体包` | core | SLang 本体 / 语言分发 | `.../core/<ver>/slang.zip` |
| `vscode` | vscode | VS Code 扩展 `.vsix` | `.../vscode/<name>/<ver>.vsix` |
| `插件` | plugin | 插件 `.slb` / 元数据包 | `.../plugins/<id>/<ver>/<id>.slb` |
| `包` | package | 模块包 `*.module.slb` | `.../packages/<name>/<ver>/<name>.module.slb` |

调用方（spm / 官网）按用户选择的中文标签传 `type`；后端解析时映射到内部种类，再定位 `md5` 与 `url`。

---

## 6. 验收 checklist

- [ ] `GET /api/registry/resolve?type=插件&name=echo&version=1.0.0` 返回 `{ md5, url }`
- [ ] 返回 md5 与 `url` 指向文件实际 md5 一致
- [ ] spm 本地缓存 md5 一致时**不重新下载**
- [ ] 本地文件被改 / 缺失时，spm 按 `url` 重下载并二次校验 md5
- [ ] 官网下载中心「插件 / 包中心」显示后端实时内容（非本地假数据）
- [ ] 插件 / 包详情页加载后展示后端实时内容
