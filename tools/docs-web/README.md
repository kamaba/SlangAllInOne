# tools/docs-web — Markdown 文档转网页 + API 索引生成器

| 文件 | 职责 |
|------|------|
| `build-docs-web.js` | 主生成器：扫描 `md/lib` 全部 `.md` → 静态站点（首页 / 入门 / 示例 / 关于 / 后管 / API 索引 / 每篇一页）+ 索引文件 `api/index.json`（含分组件 `versions`） |
| `admin-server.js` | **后管平台服务**（默认 8932）：静态托管 + `/admin` 控制台 + 版本管理/站点数据/重建 API |
| `version-scan.js` | 版本锚点扫描与写回共享模块（本体 / VSCode / 插件 / 包 分组件，分开管理） |
| `version-history.json` | 版本变更历史（后管写回自动留痕） |
| `site-data.jsonc` | 站点可变数据（友情链接 / 社区六大分类 / 自举句）：后管在线编辑或直改重跑 |
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
