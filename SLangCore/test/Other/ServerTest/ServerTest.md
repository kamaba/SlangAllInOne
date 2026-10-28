# ServerTest Project Guide

- Project Entry File: `ServerTest.sp`
- Project Config File: `ServerTest.jsonc`

SLangServer（HTTP/WS 服务框架）验收用例集：P0 前置探针 + P0 引擎 + P1/P1.5/P2/P3/P4/P4.5
+ P5/P6/P7 + P9 单例 + SwaggerUI + P10 + Mysql 集成 + Bench（2026-10-25 自 NetTest / ExpendTest 迁出
独立；设计契约见 `Lib/SLang/Server/SERVER_DESIGN.md` §8；2026-10-27 §4.10 双形态修订后全量
269 OK / 0 FAIL——P4 新增 T1j 非 static 拒绝负例、ServerMysqlTest 9 项全绿；此前 P9 singleton
4 项既有 FAIL 经全链重编（Core→Std→SLangServer→包）恢复全绿（陈旧构建状态所致，非真 bug））。

前置：先导出 SLangServer 模块（非系统库，compile-stdlib 三件套不覆盖）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Server\Server.sp --format binary+json --no-banner
```

运行（联合测试宿主选择器）：`dotnet run --project SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- ServerTest`

## Project Entry Conventions

### `_main_`

Primary runtime entry. Normal execution starts here.

### `_test_`

Test entry. Used when test mode is enabled.

### `_before_`

Compile pre-hook entry (Project class). Executed before compilation.

### `_after_`

Compile post-hook entry (Project class). Executed after compilation, before IR export.

## ServerMysqlTest —— HTTP handler 内 MySQL 查询集成（端口 19511）

HTTP 路由 handler 内执行 MySQL 查询的端到端集成用例（2026-10-27 新增，9 断言）。非分期项：
MySQL 引用由**用例集 jsonc** 承担，SLangServer 模块自身仍只引 Core/Std（SERVER_DESIGN.md G8）。

- **依赖**：`references` 需 `out/export/SLangMysql/`（先编译
  `SlangAllInOne\SLangCore\Lib\SLang\Mysql\MysqlClient.sp`，非系统库、compile-stdlib 三件套不覆盖）；
  原生 DLL `sl_mysql_lib.dll` 由测试宿主 `StageNativeDlls` 自动从源导出树补拷到 staged 模块目录。
- **连接参数**：`ServerTest.jsonc` 的 `global.data` 段注入，运行时 `global.<name>` 读取——
  `mysqlHost` / `mysqlPort` / `mysqlUser` / `mysqlPassword` / `mysqlDatabase`（初始连接库，只读）/
  `mysqlTestDb`（用例自建自清的测试库）/ `mysqlCharset`。
  ⚠️ data 段为真实账号密码，仅限本机开发测试，勿提交公共仓库。
- **用例**：

| 组 | 用例 | 覆盖点 |
| --- | --- | --- |
| T0 探针 | T0a–T0c | `clientVersion() > 0`（`@DllStaticImport` FFI 静态预载生效、非 SL 兜底）/ connect / 建库建表插 3 行 |
| T1 查询 | T1a–T1c | handler 内 SELECT `columnCount`（cols=4）/ 查询行数（rows=3）/ 行数据经 HTTP 往返（alice/bob/carol） |
| T2 绑定 | T2a–T2b | 路径参数 + `?` 绑定 + `fetchone`（bob 行完整返回）/ 未命中行 → 404 |
| TC1 清理 | TC1 | `DROP DATABASE` 测试库（跑完即清理） |

- **降级语义**（设计如此）：`clientVersion <= 0` 或 connect 返回 null → 打印 skip 提前返回，
  无 MySQL 环境时不产生环境依赖 FAIL。
- 实测（2026-10-27）：9 断言全绿，套件 all done。
