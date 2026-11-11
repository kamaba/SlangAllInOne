# SimpleLanguage 文档总索引

> 文档根：`SlangAllInOne\md\`。本索引按 2026-11-11 实际文件清单维护；
> 新增 / 删除 / 移动文档时请同步更新本文件。
> 语法文档逐篇详解见《[SL 语法与编码规范总表](SL语法与编码规范总表.md)》；
> CLI 命令全集见《[CLI 指令说明](CLI.md)》。

## 1. 目录总览

```
md\
├── INDEX.md                      # 本索引
├── code.md                       # 编码规范
├── CLI.md                        # CLI 指令说明（slang / spm / csimple_lang）
├── SL语法与编码规范总表.md        # 语法逐篇详解总表
├── project\                      # 用户向：工程配置 / 发布 / FFI / spm / LSP
├── syntax\                       # 用户向：语言语法逐篇详解
├── lib\                          # 用户向：标准库 API 文档（Core / Math / Std / HttpServer / WebUI）
├── log\                          # 用户向：日志系统
├── ai\                           # AI 协作与排障流程（内部）
└── unity3d\                      # U3D 生态绑定（内部）
```

## 2. 入门（工程根）

| 文档 | 说明 |
|------|------|
| [README.md](../README.md) / [README_EN.md](../README_EN.md) | 语言与生态总览（中 / 英） |
| [PROJECTS.md](../PROJECTS.md) | 六工程构成 / 版本联动 / 仓库布局 |
| [RELEASE.md](../RELEASE.md) | 发版与分发包流程 |
| [code.md](code.md) | 编码规范 |

## 3. 用户向文档

### 3.1 project\ —— 工程配置与生态（17 篇）

| 文档 | 说明 |
|------|------|
| [project.md](project/project.md) | 工程总览 |
| [project-config-jsonc-guide.md](project/project-config-jsonc-guide.md) | jsonc 配置全解：project / source / compile / compileFiles / references / global.data / global.macro / struct / export / publish |
| [project_sp-guide.md](project/project_sp-guide.md) | `.sp` 工程文件指南 |
| [project-module.md](project/project-module.md) | 工程 / 模块结构 |
| [project_arguments.md](project/project_arguments.md) | 程序参数（`--` 透传与 `_inputArgs`） |
| [project-system-method-call-guide.md](project/project-system-method-call-guide.md) | System 方法调用指南 |
| [static-if.md](project/static-if.md) | global.macro 宏 + static if 编译期条件编译 + `_before_` 钩子 + CLI/环境变量注入 |
| [environment-guide.md](project/environment-guide.md) | Environment 运行环境 / 平台分支 |
| [exporter.md](project/exporter.md) | 导出器（module.json / SLB） |
| [publish-guide.md](project/publish-guide.md) | `slang publish` 发布指南 |
| [package-layout.md](project/package-layout.md) | 发行包目录布局 |
| [spm-registry.md](project/spm-registry.md) | spm 包/插件管理器与 registry |
| [ffi.md](project/ffi.md) | FFI 契约（`.slffi.json` / ffi-check） |
| [lsp-code-index.md](project/lsp-code-index.md) | LSP 代码索引 |
| [docs-web.md](project/docs-web.md) | 文档站（官网文档部署） |
| [optimization.md](project/optimization.md) | 优化指南 |
| [test-guide.md](project/test-guide.md) | 测试指南 |

### 3.2 syntax\ —— 语言语法逐篇详解（37 篇）

入门与词法：[introduction.md](syntax/introduction.md)、[keywords.md](syntax/keywords.md)、[marco.md](syntax/marco.md)、[attribute.md](syntax/attribute.md)、[namespace.md](syntax/namespace.md)、[comment 详见 introduction](syntax/introduction.md)、[semicolon 详见总表](SL语法与编码规范总表.md)

变量与作用域：[variable.md](syntax/variable.md)、[local.md](syntax/local.md)、[global.md](syntax/global.md)、[typealias.md](syntax/typealias.md)、[float8_16.md](syntax/float8_16.md)

类型：[type.md](syntax/type.md)（基础类型 + `.type` 类型对象反射）、[number.md](syntax/number.md)、[string.md](syntax/string.md)、[object.md](syntax/object.md)、[array.md](syntax/array.md)、[range.md](syntax/range.md)、[data.md](syntax/data.md)、[class.md](syntax/class.md)、[interface.md](syntax/interface.md)、[enum.md](syntax/enum.md)、[cast.md](syntax/cast.md)

表达式与运算：[express.md](syntax/express.md)、[operator.md](syntax/operator.md)、[bind.md](syntax/bind.md)（属性绑定）

流程控制：[if.md](syntax/if.md)、[switch.md](syntax/switch.md)、[try.md](syntax/try.md)、[forwhiledowhile.md](syntax/forwhiledowhile.md)、[labelgoto.md](syntax/labelgoto.md)

函数与高级特性：[function.md](syntax/function.md)、[template.md](syntax/template.md)、[inline_lambda.md](syntax/inline_lambda.md)、[coroutine.md](syntax/coroutine.md)、[isolate.md](syntax/isolate.md)、[extend.md](syntax/extend.md)、[result.md](syntax/result.md)、[system_method.md](syntax/system_method.md)

### 3.3 lib\ —— 标准库 API 文档

每个目录先看 `README.md`（职责边界与依赖顺序）。Core → Std → Math 为编译顺序；
HttpServer / WebUI 为独立 module 包。

- **[lib/Core](lib/Core/README.md)** —— 语言内建与核心运行库：数值类型全家桶（Int8~64 / UInt8~64 / Float8~64 / Num / Boolean）、[String](lib/Core/String.md)、[Array](lib/Core/Array.md)、[Type](lib/Core/Type.md)（`.type` 类型对象反射）、[Object](lib/Core/Object.md)、[Environment](lib/Core/Environment.md)（+ `Environment/Platform_*` 5 篇）、容器 `Container/`（List / Map / HashSet / LinkedList / Queue / Stack / Channel / Tuple / IList / IMap）、IO `IO/`（ByteStream / ByteBuffer / Serialize / JsonCodec / ProtoCodec / BinaryCodec / Encoding / LengthPrefix / Stream / Codec）、文本 `Text/`（BaseJson / BaseXml / BaseYaml / BaseToml / BaseConfigFormat / JsonValue / StringBuilder / Lz4 / ProtocalBuffers）、[Data](lib/Core/Data.md)（+ `Data/FrameData`）、`DataStruct/`（[BaseCsv](lib/Core/DataStruct/BaseCsv.md) / [Table](lib/Core/DataStruct/Table.md) / [Tree](lib/Core/DataStruct/Tree.md)）、[Coroutine](lib/Core/Coroutine.md)、[IteratorInterface](lib/Core/IteratorInterface.md)、[Result](lib/Core/Result.md)、[Error](lib/Core/Error.md)、[Ptr](lib/Core/Ptr.md)、[Memory](lib/Core/Memory.md)、[Monitor](lib/Core/Monitor.md)、[Random](lib/Core/Random.md)、[Guid](lib/Core/Guid.md)、[Range](lib/Core/Range.md)、[Nickname](lib/Core/Nickname.md)、[AOT](lib/Core/AOT.md)、[Attribute](lib/Core/Attribute.md)、[Exclude](lib/Core/Exclude.md)、[DllImport](lib/Core/DllImport.md) / [DllStaticImport](lib/Core/DllStaticImport.md)、[CloneIterface](lib/Core/CloneIterface.md)、[IterateVariable](lib/Core/IterateVariable.md)、[Member](lib/Core/Member.md)、[Void](lib/Core/Void.md)
- **[lib/Math](lib/Math/README.md)** —— 数学库：标量（Mathf / Mathd / Mathh）、大数（BigNumber / BigDecimal / Factor）、向量矩阵（Float16_2 ~ Float64_4x4 共 18 篇、Int32_2 / Int32_3、Matrix、Quaternion）、[Rect](lib/Math/Rect.md)
- **[lib/Std](lib/Std/README.md)** —— 系统与生态库：[Component](lib/Std/Component.md)、IO `IO/`（Console / File / FileStream / Directory / Path / StdStream）、文本 `Text/`（Json / Csv / Xml / Toml / Yaml / Codecs / RegExp）、网络 `net/`（TcpSocket / UdpSocket / NetStream / TlsStream / HttpClient / Websocket / Mqtt / Uri / IpProtocal）、[DB/Sqlite](lib/Std/DB/Sqlite.md)、[Cache/Redis](lib/Std/Cache/Redis.md)、调试 `Debug/`（Log / Profiling / Trace）、编码 `Encoding/`（Base64 / Encoding / Md5 / Sha1 / Sha256）、压缩 `Zip/`（Zip / GZip）、[GPU/GPU](lib/Std/GPU/GPU.md)、FFI `FFI/`（Library / Struct）、[Isolate](lib/Std/Isolate/Isolate.md)（Capability / 端口 / 组 / 状态 / StreamBridge / TransferableData 等 10 篇）、`OS/`（DateTime / Process / Timer）、[InstanceAttr](lib/Std/InstanceAttr.md)、[Server](lib/Std/Server.md)
- **[lib/HttpServer](lib/HttpServer/README.md)** —— 内置 HTTP 服务端框架（独立 module，17 篇）：HttpServerCore / Server / Router / RouteAttrs / Request / Response / BodyParser / HttpBodyReader / MultipartReader / StreamIo / Upload / Jwt / ApiResult / WebSocketServer / Plugin / Plugins / Docs
- **[lib/WebUI](lib/WebUI/README.md)** —— SLangWebUI 界面包（独立 module）

### 3.4 log\ —— 日志系统

| 文档 | 说明 |
|------|------|
| [log/log-system-guide.md](log/log-system-guide.md) | 日志系统指南 |
| [log/log-debug-usage.md](log/log-debug-usage.md) | 日志调试用法 |

错误码（LID）权威来源为源码 [ErrorDefinitions.csv](../../simple_language/source/Log/ErrorDefinitions.csv)
与 [LID.cs](../../simple_language/source/Log/LID.cs)；错误消息规范见
[project/error 段](project/project.md)。

## 4. AI 协作（内部）

| 文档 | 说明 |
|------|------|
| [ai/AI_GUIDE.md](ai/AI_GUIDE.md) | AI 协作总入口 |
| [ai/INDEX.md](ai/INDEX.md) | AI 文档索引 |
| [ai/PROJECT_MAP.md](ai/PROJECT_MAP.md) | 代码地图 |
| [ai/EXPORT_PATHS.md](ai/EXPORT_PATHS.md) | 导出路径说明 |
| [ai/DEBUG_WORKFLOW.md](ai/DEBUG_WORKFLOW.md) | 调试工作流 |
| [ai/故障排查流程.md](ai/故障排查流程.md) | 故障排查 SOP |
| `ai/troubleshooting/`（8 篇） | 分场景排查手册（AI 无响应 / 编辑器 / VSCode / CLI 等） |

## 5. unity3d\（内部）

| 文档 | 说明 |
|------|------|
| [unity3d/SLANG_INTEGRATION.md](unity3d/SLANG_INTEGRATION.md) | U3D 集成方案 |
| [unity3d/VM-BINDING-PLAN.md](unity3d/VM-BINDING-PLAN.md) | VM 绑定计划 |
| [unity3d/VM-BINDING-TEST-PLAN.md](unity3d/VM-BINDING-TEST-PLAN.md) | 绑定测试计划 |
| [unity3d/VM-BINDING-REVIEW.md](unity3d/VM-BINDING-REVIEW.md) | 绑定评审 |
| [unity3d/VM-CALL-SPEC.md](unity3d/VM-CALL-SPEC.md) | VM 调用规约 |
| 生态入口 | [unity/README.md](../unity/README.md) |

## 6. 外部工程文档（simple_language / csimple_lang）

| 文档 | 说明 |
|------|------|
| [SLB_DESIGN.md](../../csimple_lang/md/design/SLB_DESIGN.md) | SLB 模块包格式设计 |
| [ATTRIBUTE_DESIGN.md](../../csimple_lang/md/design/ATTRIBUTE_DESIGN.md) | attribute 系统设计 |
| [PROCESS_DESIGN.md](../../csimple_lang/md/design/PROCESS_DESIGN.md) | 编译流程设计 |
| [NET_DESIGN.md](../../csimple_lang/md/design/NET_DESIGN.md) | C VM 网络栈设计 |
| [DEBUG_PROTOCOL_DESIGN.md](../../csimple_lang/md/design/DEBUG_PROTOCOL_DESIGN.md) | SLDP 调试协议设计 |
| [X86_ASM_FASTPATH_DESIGN.md](../../csimple_lang/md/design/X86_ASM_FASTPATH_DESIGN.md) | x86 ASM 快路径设计 |
| [MONO_DESIGN.md](../../csimple_lang/md/design/MONO_DESIGN.md) | Mono 互操作设计 |
| [MLIR_AOT_实现与待办.md](../../simple_language/source/Export/MLIR/MLIR_AOT_实现与待办.md) | MLIR AOT 后端 |
| [Core.md](../SLangCore/Lib/Core/Core.md) | 标准库源码（Core.sl）配套说明 |
