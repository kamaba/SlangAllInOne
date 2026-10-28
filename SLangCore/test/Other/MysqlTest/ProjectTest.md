# MysqlTest —— SLangMysql 端到端测试工程

对 `SlangAllInOne\SLangCore\Lib\SLang\Mysql\`（SLangMysql 模块，namespace `SLang`）
做真实环境验证：连接远端 MySQL、建库建表、CRUD、参数绑定、NULL、事务、
错误处理、结果集读取。

## 目录

```
test/Other/MysqlTest/
├── ProjectTest.jsonc     # 工程配置（references 里引了 SLangMysql 模块）
├── ProjectTest.sp        # _main_ 入口：依次跑 MysqlTest / MysqlApiTest
├── MysqlTest.sl          # 主流程用例 T01~T31
├── MysqlApiTest.sl       # API 细节用例 A01~A26
└── ProjectTest.md        # 本文档
```

## 连接参数

写在 `ProjectTest.jsonc` 的 `"data"` 段，运行时按 `global.<name>` 读取：

| key | 说明 |
| --- | --- |
| `mysqlHost` | 主机 |
| `mysqlPort` | 端口 |
| `mysqlUser` / `mysqlPassword` | 账号 |
| `mysqlDatabase` | 初始连接库（正式库，测试过程只读不写） |
| `mysqlTestDb` | 测试专用库名（用例内建库/删库） |
| `mysqlCharset` | 字符集 |

> ⚠️ `data` 段里是真实账号密码，仅限本机开发测试使用，请勿提交到公共仓库；
> 迁移到正式环境请改为环境变量或本地未纳入版本管理的配置文件。

测试库 `mysqlTestDb`（默认 `sl_mysql_test`）由用例自己
`CREATE DATABASE` / `DROP DATABASE`，跑完即清理，不会污染正式库。

## 编译

前置依赖（`references`）：

| 模块 | 说明 |
| --- | --- |
| `./lib/Core.module.slb` / `./lib/Std.module.slb` | 系统库（工程内落空自动回落官方库直查） |
| `out/export/SLangMysql/SLangMysql.module.json` | 被测库，未命中即报错中止 |

被测库 SLangMysql 需先编译一次（非系统库，compile-stdlib 三件套不覆盖）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Mysql\MysqlClient.sp --format binary+json --no-banner
```

再编译本工程（产物落 `SlangAllInOne\out\export\MysqlTest\`）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\test\Other\MysqlTest\ProjectTest --format binary+json --no-banner
```

## 运行（联合测试宿主）

```powershell
dotnet run --project SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- SlangAllInOne\SLangCore\test\Other\MysqlTest\ProjectTest
```

宿主把产物 stage 进发布包 `<package>\MysqlTest\` 并**联动拷贝引用模块
`SLangMysql\`**（`StageReferencedModules`），其中原生 DLL `sl_mysql_lib.dll`
由 `StageNativeDlls` 读模块 json `dllImports[].path`（`static` 非空的 FFI
绑定条目）自源导出树平铺补拷，再经包内 `slang.exe run` 执行。

## 原生 DLL 定位（dllImports 平铺形态）

`MysqlClient.jsonc` 的 `dllImports` 用**平铺 basename** 形态：
`{ "path": "sl_mysql_lib.dll", "static": "sl_mysql_lib" }`——cvm 装载模块即
预载该库并注册 FFI 静态绑定表（`vmDllImports` 平铺拼路径 LoadLibrary +
`vm_sys_ffi_static_lib_register`），FFI 运行期按三重回退链定位：
`pkg_dir/path` → `pkg_dir/<平台>/basename` → `pkg_dir/basename`。
绑定失败回退 SL 函数体兜底（`clientVersion() <= 0` 即兜底征兆）。

## 用例清单

### MysqlTest.sl（T01~T31）主流程

| 组 | 用例 | 覆盖点 |
| --- | --- | --- |
| 原生层 | T01~T02 | `clientVersion()` / `clientInfo()` 非 fallback，证明 `@DllStaticImport` 直调生效 |
| 连接 | T03~T06 | `connect` / `errorCode` / `ping` / `isClosed` |
| 建库 | T07~T08 | `DROP/CREATE DATABASE`、`selectDatabase` |
| 建表 | T09~T10 | `CREATE TABLE`、`SHOW TABLES` |
| 写入 | T11~T13 | `INSERT` + `affectedRows` + `insertId` |
| 读取 | T14~T23 | `columnCount` / `rowCount` / `columnName(s)` / `fetchall` / `MysqlRow` 取值 |
| 更新 | T24~T26 | `UPDATE` + 回查 + `fetchone` 读完返回 null |
| 删除 | T27~T28 | `DELETE` + `COUNT(*)` 校验 |
| 清理 | T29~T31 | `DROP TABLE` / `close` / `DROP DATABASE` |

### MysqlApiTest.sl（A01~A26）API 细节

| 组 | 用例 | 覆盖点 |
| --- | --- | --- |
| 转义 | A04~A05 | 单引号 / 中文 / `%` / `_` 经 `?` 绑定后原样取回 |
| NULL | A06~A09 | SQL NULL 写入、`isNull()`、NULL 列 `getString()` 返回空串 |
| 取行 | A10~A15 | `fetchone` / `fetchmany(n)` / `fetchall` / 空结果集 |
| 事务 | A16~A18 | `autocommit(false)` + `rollback` 丢弃 + `commit` 落库 |
| 错误 | A19~A21 | 错误 SQL 的 `errorCode`/`errorMessage`，且出错后连接仍可用 |
| 转义工具 | A22~A24 | `Mysql.escape` / `Mysql.literal`（含 `null` → `NULL`） |
| 清理 | A25~A26 | `DROP TABLE` / `DROP DATABASE` |

## 实测结果

```
===== MysqlTest end PASS=31 FAIL=0 =====
===== MysqlApiTest end PASS=26 FAIL=0 =====
```

2026-10-27 重编复验：MysqlApiTest 16 处 `SL.` → `SLang.` 修正后
`export module success` 双产物（slb+json），Error 清零。

## 关联

- 库说明：`SlangAllInOne\SLangCore\Lib\SLang\Mysql\MysqlClient.md`
- HTTP handler 内集成用例：`SlangAllInOne\SLangCore\test\Other\ServerTest\ServerMysqlTest.sl`（端口 19511）

## 已知取舍

- `?` 占位符统一按「字符串转义 + 加引号」绑定（走 `mysql_real_escape_string`），
  MySQL 会按列类型自动转换，数值同样能正确落库；代价是字符串字面量内部的
  `?` 也会被替换。
- `MysqlRow.getString(i)` 对 SQL NULL 返回空串，判空请用 `isNull(i)`。
- SL 前端不支持跨模块类型作泛型实参（如 `List<SLang.MysqlRow>` 会让
  `MetaClass.AddMetaTemplateClassByMetaClassAndMetaTemplateMetaTypeList` 抛
  空引用），测试里统一用 `var` 让类型推断接管。
