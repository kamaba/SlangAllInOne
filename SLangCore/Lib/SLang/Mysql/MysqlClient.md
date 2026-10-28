# MysqlClient（SLangMysql 模块）库说明

- Project Entry File: `MysqlClient.sp`
- Project Config File: `MysqlClient.jsonc`
- 模块名（export.moduleName）：`SLangMysql` → 产物 `SlangAllInOne\out\export\SLangMysql\`

MySQL 客户端库（Python DB-API 2.0 / PyMySQL 风味），namespace `SLang` 下四类：
`Mysql`（入口 + 原生绑定）/ `MysqlConnection` / `MysqlCursor` / `MysqlRow`。
错误处理以返回值表达（connect 失败返回 null、其余失败返回 false，原因经
`conn.errorCode()` / `conn.errorMessage()` 取得），与 `Std/DB/Sqlite.sl` 同风格。

## 用法示例

```csharp
import Std;
import SLangMysql;

SLang.MysqlConnection conn = SLang.Mysql.connect( "127.0.0.1", "root", "123456", "test" )
if ( conn == null ) { return }

SLang.MysqlCursor cur = conn.cursor()
cur.execute( "INSERT INTO user(name, age) VALUES (?, ?)", Tuple("alice", 18) )
conn.commit()

cur.execute( "SELECT * FROM user" )
var rows = cur.fetchall()          # List<SLang.MysqlRow>
for i = 0, i < rows.length, i++
{
    Console.println( rows._getItem_(i).toString() )
}

cur.close()
conn.close()
```

## 原生链路（FFI 静态绑定）

```
MysqlClient.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_mysql_lib.dll
                ──静态链接──────────────────────> MySQL Connector/C（mysqlclient.lib）
```

`sl_mysql_lib.dll` 把 MYSQL / MYSQL_RES 收敛为 Int64 句柄、数据收敛为
bool / Int32 / Int64 / string，可完全静态绑定直调。jsonc `dllImports` 用
**平铺 basename** 形态（`{ "path": "sl_mysql_lib.dll", "static": "sl_mysql_lib" }`）：
cvm 装载模块即预载该库并注册 FFI 静态绑定表，绑定失败回退 SL 函数体兜底
（`clientVersion() <= 0` 即兜底征兆）。FFI 运行期按三重回退链定位：
`pkg_dir/path` → `pkg_dir/<平台>/basename` → `pkg_dir/basename`。

⚠️ GPL-2.0 红线：`sl_mysql_lib.dll` 静链 MySQL Connector/C 6.1.11（GPL-2.0），
不随官方发布包分发。

## 测试与集成

- 端到端用例集：`SlangAllInOne\SLangCore\test\Other\MysqlTest\`（主流程 T01~T31 + API 细节 A01~A26，说明见其 `ProjectTest.md`）
- HTTP handler 内集成：`SlangAllInOne\SLangCore\test\Other\ServerTest\ServerMysqlTest.sl`（端口 19511，说明见 `ServerTest.md`）
