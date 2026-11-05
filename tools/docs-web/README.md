# tools/docs-web — Markdown 文档转网页 + API 索引生成器

| 文件 | 职责 |
|------|------|
| `build-docs-web.js` | 主生成器：扫描 `md/lib` 全部 `.md` → 静态站点（首页 / 入门 / 示例 / 关于 / 后管 / API 索引 / 每篇一页）+ 索引文件 `api/index.json`（含分组件 `versions`） |
| `admin-server.js` | **后管平台服务**（默认 8932）：静态托管 + `/admin` 控制台 + 版本管理/站点数据/重建 API |
| `version-scan.js` | 版本锚点扫描与写回共享模块（本体 / VSCode / 插件 / 包 分组件，分开管理） |
| `version-history.json` | 版本变更历史（后管写回自动留痕） |
| `site-data.jsonc` | 站点可变数据（友情链接 / 社区六大分类 / 自举句 / **`about` 关于页 Tab 内容 + 赞助二维码位**）：后管在线编辑或直改重跑 |
| `stories.json` | 「我的故事」数据源（数组：`id / label / content / createdAt`），后管「我的故事」菜单维护，关于页「我的故事」Tab 分页展示 |
| `assets/sponsor/*.svg` | 赞助入口的二维码占位图（微信赞赏 / 支付宝），可在 `site-data.jsonc` 的 `about.sponsor.qrcodes` 替换真实图片路径 |
| `serve.js` | 纯静态预览服务器（零依赖，默认 `http://127.0.0.1:8931/`） |
| `preview-docs-web.ps1` | 一键：生成 + 起预览服务器 + 打开浏览器 |

## 用法

```powershell
node build-docs-web.js                    # md/lib → out/docs_web（默认路径）
node admin-server.js 8932                 # 后管平台：http://127.0.0.1:8932/admin（版本管理/站点数据/重建）
node serve.js 8931                        # 纯静态预览
.\preview-docs-web.ps1                    # 生成 + 预览一条龙
```

- 零 npm 依赖；产物只写 `SlangAllInOne/out/docs_web/`（R9），全部 UTF-8（R16）。
- 官网 / 后管平台集成、`api/index.json` 契约、入门/关于页、站点数据外置：**权威文档 = `md/project/docs-web.md`**。
- 首批生成结果（2026-11-03）：180 篇文档 · 6 分组 · 333 类/枚举 · 5132 成员；**可运行示例 10/10 实测通过**（HelloWorld + 根级 4 脚本 + MDExample 5 例，逐字输出核对），自举实验树 231 文件单独标注为历史手稿。

## 关于页（Tab 切换）与「我的故事」

`about.html` 顶部为 Tab 切换栏，栏目：**项目故事 / 技术加载 / 设计取舍 / 路线图 / 案例 / 许可证社区 / 我的故事**。
前六个栏目内容来自 `site-data.jsonc` 的 `about.<tabId>`（`title` + `body`，`mdInline` 支持行内 `code`）；
页脚固定一个「赞助入口」区块，渲染 `about.sponsor.qrcodes` 中的两张二维码（当前为 `assets/sponsor/*.svg` 占位图，可替换真实路径）。

「我的故事」Tab 由后管维护：

1. 后管平台 `admin.html` 顶部菜单「我的故事」→ 填写**小标签** + **故事内容** → 添加（删除同理）；
2. 写入 `tools/docs-web/stories.json`（`id / label / content / createdAt`），需经 `admin-server` 启动方可写，静态预览仅展示快照；
3. 点「重建站点」后，`about.html` 构建期将故事嵌入 `window.__STORIES__`，「我的故事」Tab 以每页 4 条**分页**展示；若后管服务在线，页面会实时 `/api/stories` 拉取最新数据。

### 后管 API（admin-server.js）

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/versions` | GET | 各组件版本扫描值 + 历史 |
| `/api/version/set` | POST | 写回某组件版本锚点 |
| `/api/site-data` | GET/POST | 读取 / 保存 `site-data.jsonc` |
| `/api/stories` | GET/POST | 列出 / 新增「我的故事」（`label`+`content`） |
| `/api/stories?id=` | DELETE | 按 `id` 删除一条故事 |
| `/api/rebuild` | POST | 执行 `build-docs-web.js` 并回传日志尾 |
