# md/ai 文档索引

全仓库 Markdown 总目录（语法、工程、VM、日志等）见 **`[md/INDEX.md](../INDEX.md)`**。

> **文档写作约定（R21，2026-11-06 用户定稿）**：写「使用文档」（`md/syntax/` 语法篇、`md/lib/` 库篇、工程/配置/命令使用说明等）时，**只写规则说明、使用用例、可用方法、使用技巧与已知坑**；禁止分析源码、讲 FrontEnd / C VM 内部处理、贴源码路径与行号、列实现细节或测试用例索引。实现性内容只放 `md/ai/`、`csimple_lang/md/design/`、troubleshooting 等 AI/设计/复盘文档。完整规则见根目录 `AGENTS.md` §2 R21。

| 文件 | 用途 |
|------|------|
| `故障排查流程.md` | **默认首选（统一主文档）**：整项目问题定位顺序 + Front 代码解析流程 + 语法规则备忘 + 复盘分片路由索引与追加模板（复盘正文在 [troubleshooting/](./troubleshooting/) 8 个分片） |
| `EXPORT_PATHS.md` | **默认 SLIR 导出目录**（`out/export/module.package.json`）与根 JSON 形态（`entryModule` + `moduleList`） |
| `PROJECT_MAP.md` | **推荐首选**：解决方案工程、数据流、`Front`/`VM` 目录职责表、按任务书签、与测试/文档路径对照 |
| `CODEBASE_OVERVIEW.md` | 英文简版总览，与 `PROJECT_MAP.md` 互补 |
| `代码解析流程.md` | 已并入 `故障排查流程.md`（保留跳转说明） |
| `AI_GUIDE.md` | AI 协作与仓库约定 |
| `AI_PROMPTS.md` | 提示词/场景模板 |
| `MLIR_AOT_DESIGN.md` | **MLIR AOT 设计文档**：SLIR→MLIR→LLVM→exe 全链路设计、指令映射表、运行时 ABI、工具链与落地路线图 |
| `CONTRIBUTING_GUIDE.md` | 贡献说明 |
| `语法规则.md` | 已并入 `故障排查流程.md`（保留跳转说明） |

阅读顺序建议：先 **`故障排查流程.md`**，再看 **`PROJECT_MAP.md`**，需要阶段细节时看 **`代码解析流程.md`**。
