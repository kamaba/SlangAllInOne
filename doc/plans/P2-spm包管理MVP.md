# P2 · spm 包管理 MVP —— 执行计划

> **定位**：生态地基。`modules\` 用户包目录与装载查找链（`lib\ → modules\`）已预留，缺 CLI 落地。
>
> **落地进度（2026-10-30 更新）**：spm 已**独立成专用工程 `SlangAllInOne\Project\Spm\`**
> （产物 `spm.exe`，slang 同目录直接 `spm <命令>` 驱动；2026-10-29 先以宿主子命令
> `slang spm` 落地、30 日独立）。已实现：`spm install <url|包名>`（URL 直拉 zip /
> 按名三级：工程已装 → 语言目录移动 → 服务器元数据下载；`-g` 全局装位）、
> `spm search` 按名查包、`spm list`（含本地版本）、`spm outdated` 与服务器版本对比
> （本地 `modules\<名>\spm.json` 清单）、`spm remove`、`spm config registry`；
> **插件命令组** `spm plugin list|search|probe|install|remove`（环境探测 = 服务器
> platforms vs 本机 os-arch，装到 `<lang>\plugin\<id>\`）。**服务器协作**按官网
> 门户 API 约定（doc/18 §9：`GET /api/packages/<名>` 等；doc/09 §5 插件同构），
> 静态文件服务器回落（`<reg>/<名>.json` + zip）兼容。registry 三级优先
> `--registry` > jsonc `"spm"."registry"`（spm 自解析）> `<lang>\spm.json`。
> 装载三级搜索链（Front Strategy 4 与 C VM ④ 同源）+ `slang publish` 携带工程
> `modules\` 已就绪（详见 `md/project/package-layout.md` §四）；🔥 release 发布链
> **PackSpm** target 已集成（2026-10-30）：打 release 包自动对 Spm.csproj 跑
> Native AOT，`spm.exe` 单文件落包根 = slang 同目录。**本计划剩余**：
> T1 `.spkg` 容器、T3 索引与依赖解析/版本约束（当前 outdated 仅对比不自动升级）、
> T4 pack/publish、T5 update、T6 首发包与官网联动。
> **参照设计**：官网 `SLangOfficialWebsite\doc\18-包管理中心spm设计.md`（P1 指引期已诚实标注"spm 未落地"）+ `SlangAllInOne\md\project\package-layout.md`。
> **依赖**：P1（若依拆包作为第一个真实包验证）。**建议节奏**：2~4 周。

---

## 一、目标

1. spm 最小命令闭环：`install / remove / list / publish / update`；
2. `.spkg` 包容器格式落地（spm.json + slb + 可选平台原生库）；
3. 分发通道：**GitHub 仓库 + raw 索引起步，不建服务端**（crates.io 早期同模式）；
4. 官网包中心从"指引形态"升级"registry 联动形态"（doc/18 P2 期判据）。

## 二、现状与差距

| 现状 | 差距 |
|------|------|
| `modules\` 目录预留、装载查找链 `lib\ → modules\` 已就绪（PROJECTS.md §4.4，Front Strategy 4 + C VM `sl_load_references` ④） | 无安装工具把包放进去 |
| `.spkg` 容器有草案（doc/18 §2 P3：spm.json + slb + `lib\<平台>\` 原生库） | 未实现 |
| 官网包中心 P1 指引页设计完成（doc/18 §4） | 等 spm MVP 才能升 P2 |
| 网络库齐备（HTTP/TLS 现成） | spm 自身可用 SLang 写（自举加分项）或 C# 宿主内实现 |

**实现载体决策**：建议 `slang spm <cmd>` 子命令（C# 宿主内实现，复用 `SlangAllInOne\Program.cs` 命令路由 + .NET HttpClient；下载/解压/校验逻辑简单，且随宿主 AOT 发布零额外分发）。备选：独立 spm.exe。**先用宿主子命令，生态大了再拆**。

## 三、任务分解

### T1 · `.spkg` 容器格式规范（1 天）

**格式定义**（zip 容器，扩展名 `.spkg`）：

```
<name>-<version>.spkg
├── spm.json              # 包清单（唯一必需）
│     name / version / description / homepage
│     slangVersion        # 兼容的语言版本区间 "^0.0.45"
│     dependencies        # { "jsonx": "1.2.0", "webview": "^0.1" }
│     platforms           # { "windows": ["lib/windows/webview.dll"], ... }
│     entry               # 主模块名（对应 <name>.module.slb）
├── <name>.module.slb     # 编译产物（必需）
├── <name>.module.json    # 调试副本（可选）
├── lib\<平台>\*.dll|so   # 原生库（可选，P3 webview 包需要）
└── md\*.md               # 包文档（可选）
```

**安装布局**（落 `<slang>\modules\<name>\`，与查找链对齐）：

```
<slang>\modules\<name>\
├── spm.json
├── <name>.module.slb
└── lib\<平台>\*.dll      # 原生库；C VM 关联 dll 预装载序已有
                             lib\<平台>\ 探测逻辑（sl_preload_associated_dlls），复用
```

**产出**：`md/project/spm.md`（规范文档，R14）。

### T2 · 命令骨架 + list/remove（2 天）

**步骤**：
1. `SlangAllInOne\` 新增 `Spm\SpmCommand.cs`（仿 `New\NewCommand.cs` / `Publish\PublishCommand.cs` 结构），Program.cs 注册 `spm` 路由；
2. `spm list`：扫 `modules\*\spm.json` 汇总输出（名/版本/依赖）；
3. `spm remove <name>`：删 `modules\<name>\`（引用中的包提示但不阻断，MVP 不做引用图反查）；
4. `spm list --outdated`：对比索引显示可升级项。

### T3 · `spm install` + 依赖解析（4~5 天，核心）

**步骤**：
1. **索引获取**：拉取 GitHub raw 的 `packages.json`（`https://raw.githubusercontent.com/<org>/spm-registry/main/packages.json`），本地缓存 `<slang>\modules\.index.json`（TTL 一天）；
2. **依赖解析（MVP 线性版）**：
   - 版本约束语法：精确 `1.2.0` / 兼容 `^1.2.0`（同主版本内最新）；
   - 算法：递归展开依赖树 → 已安装且满足约束则跳过 → 不满足则升级 → 版本冲突直接报错（**不做 SAT 求解**，冲突信息列出路径即可）；
3. **下载安装**：按索引 URL 下载 `.spkg` → 校验（SHA256，索引里带哈希）→ 解压到 `modules\<name>\` → 原生库按 `platforms` 段校验落位；
4. **工程级安装**：`spm install`（无参，在工程目录）读工程 `.jsonc` 的 `spmDependencies` 段（新增字段）批量装；装完提示把包名加进 `references`；
5. **langVersion 检查**：`slangVersion` 约束与当前宿主版本比对，不满足警告。

**验收**：两包 A→B 依赖链，`spm install A` 自动带上 B；改 B 版本约束触发升级；冲突报错信息可读。

### T4 · `spm publish` + 打包（2 天）

**步骤**：
1. `spm pack`：读工程 `.jsonc`（新增 `spm` 段：name/version/description/platforms）→ 编译工程出 slb → 按 T1 结构组 `.spkg` → 本地校验（spm.json schema + slb 存在 + 引用可解析）；
2. `spm publish`：MVP 形态 = 输出提交指引（把 `.spkg` + 索引 PR 提交到 spm-registry 仓库——GitHub PR 即审核）；**不做服务端上传**；
3. 发布前检查：包名规则 `[a-z][a-z0-9_-]{1,30}`（doc/18 §3）、不与官方库（Core/Std/Math）重名。

### T5 · `spm update`（1 天）

- `spm update`：全量按索引刷新；`spm update <name>`：单包升级 + 依赖联升。

### T6 · 官方首发包 + 官网联动（3~4 天）

1. **建 `spm-registry` 仓库**：`packages.json` 索引 + 仓 README 规范；
2. **首发三包**：
   - `slang-ruoyi`（或拆 `ruoyi-auth` / `ruoyi-rbac`）——P1 产出拆包，**第一个真实大包**；
   - `hello-spm` 官方示例包（doc/18 P2 上线判据）；
   - `webview`（P3 完成后补入，验证多平台原生库容器）；
3. **官网 P2 联动**（doc/18 §4.2→P2 形态）：列表页读 packages.json 生成 + 包详情页 + `spm install <name>` 命令块与 CLI 实测一致（上线判据）；
4. 官网后管包管理模块（doc/18 §10）后置，不做进 MVP。

### T7 · 文档与流程闭环（1 天）

- `md/project/spm.md`：容器规范 + 命令手册 + 发布流程；
- 官网 doc/18 更新状态条（指引期 → registry 期）；
- AGENTS.md §3 加 spm 锚点；README 命令表加 `spm` 行。

## 四、验收标准

- [ ] `spm install hello-spm` 在干净环境一键成功，工程引用即用；
- [ ] 依赖链 A→B 自动安装、版本约束升级、冲突报错路径清晰；
- [ ] `spm pack` 打出的 `.spkg` 经 `spm install` 原样可用（自洽往返）；
- [ ] 若依系统作为包可安装运行；
- [ ] 官网包中心命令块与 CLI 实测一致（doc/18 P2 判据）；
- [ ] 原生库多平台包（webview）安装后关联 DLL 自动预装载。

## 五、执行顺序

```
T1 容器规范 ──► T2 骨架(list/remove) ──► T3 install+依赖解析 ──► T6 首发包+官网
                        │                        │
                        └──► T4 pack/publish ────┘──► T5 update
```

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| 索引仓库冷启动无包 | 官方带头：若依 + 示例包 + webview 全走 spm 分发 |
| GitHub raw 国内可达性 | 索引 URL 做成可配置（`spm config registry <url>`），支持镜像 |
| 依赖解析复杂度膨胀 | MVP 严守线性解析 + 冲突即报错；SAT/lockfile 记入远期（doc/18 P3） |
| 版本锚点四端规则与包版本混淆 | spm 包版本独立于语言四端版本，仅 `slangVersion` 字段做兼容约束 |
