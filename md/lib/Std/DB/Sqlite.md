# DB/Sqlite.sl

> 源文件：`DB/Sqlite.sl`

## class `Row`

- **说明**：Row - 行数据，仿 Python sqlite3.Row

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Array&lt;object&gt; _values = null` | 字段 _values（类型见签名）。 |
| 字段 | `int _count = 0` | 字段 _count（类型见签名）。 |
| 构造 | `_init_(int columnCount)` | 构造方法，初始化本类型实例。 |
| 方法 | `void _set(int index, object val)` | 内部：设置列值 |
| 方法 | `object _getItem_(int index)` | 下标读取：row[0], row[1] ... |
| 属性 | `get int length()` | 获取 length 的值。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Cursor`

- **说明**：Cursor - 游标，仿 Python sqlite3.Cursor

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _dbHandle = 0` | 字段 _dbHandle（类型见签名）。 |
| 字段 | `Int64 _stmtHandle = 0` | 字段 _stmtHandle（类型见签名）。 |
| 字段 | `int _columnCount = 0` | 字段 _columnCount（类型见签名）。 |
| 字段 | `bool _closed = false` | 字段 _closed（类型见签名）。 |
| 构造 | `_init_(Int64 dbHandle)` | 构造方法，初始化本类型实例。 |
| 方法 | `Cursor execute(string sql)` | execute(sql) - 执行 SQL（无参数），返回 this 便于链式调用 |
| 方法 | `Cursor execute(string sql, Tuple args)` | execute(sql, args) - 执行带参数 SQL，args 为 Tuple |
| 方法 | `void _prepareAndBind(string sql, Tuple args)` | 内部：准备语句 + 绑定参数 + DML 自动 step |
| 方法 | `void _bindParams(Tuple args)` | 内部：将 Tuple 中的参数逐个绑定到预编译语句 SQLite 类型亲和性会自动将文本 "42" 转为整数 42 |
| 方法 | `Row fetchone()` | fetchone() - 取一行，无数据返回 null |
| 方法 | `Array&lt;Row&gt; fetchall()` | fetchall() - 取所有行，返回 Array&lt;Row&gt; |
| 方法 | `Row _readRow()` | 内部：从当前行读取各列数据，构造 Row |
| 方法 | `int changes()` | 获取最近一次 DML 影响的行数 |
| 方法 | `Int64 lastInsertRowid()` | 获取最近插入的 rowid |
| 方法 | `void close()` | 关闭游标，释放语句 |

## class `Command`

- **说明**：Command - 命令对象（ADO.NET 风格辅助类，保留已有定义）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _dbHandle = 0` | 字段 _dbHandle（类型见签名）。 |
| 字段 | `string _sql = ""` | 字段 _sql（类型见签名）。 |
| 构造 | `_init_(Int64 dbHandle, string sql)` | 构造方法，初始化本类型实例。 |
| 方法 | `int executeNonQuery()` | 执行非查询 SQL（INSERT/UPDATE/DELETE/DDL），返回 SQLite 结果码 |

## class `Connection`

- **说明**：Connection - 数据库连接，仿 Python sqlite3.Connection

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _dbHandle = 0` | 字段 _dbHandle（类型见签名）。 |
| 字段 | `bool _isClosed = false` | 字段 _isClosed（类型见签名）。 |
| 构造 | `_init_(Int64 dbHandle)` | 构造方法，初始化本类型实例。 |
| 方法 | `Cursor cursor()` | 创建游标 |
| 方法 | `Cursor execute(string sql)` | 便捷方法：创建游标并执行 SQL |
| 方法 | `Cursor execute(string sql, Tuple args)` | 便捷方法：创建游标并执行带参数 SQL |
| 方法 | `Command createCommand(string sql)` | 创建 Command 对象 |
| 方法 | `void commit()` | 提交事务（SQLite 默认自动提交，此处为兼容 Python 接口） |
| 方法 | `void lock()` | 执行 lock()。 |
| 方法 | `void unlock()` | 执行 unlock()。 |
| 方法 | `int changes()` | 获取最近一次 DML 影响的行数 |
| 方法 | `Int64 lastInsertRowid()` | 获取最近插入的 rowid |
| 方法 | `string errorMessage()` | 获取最近一条错误信息 方法名 errorMessage：errmsg 为 Result 语义保留名，类成员名须避让 |
| 方法 | `void close()` | 关闭连接 |

## class `Sqlite3`

- **说明**：Sqlite3 - 入口类，connect() 连接数据库（仿 Python sqlite3.connect）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Connection connect(string databasepath)` | 执行 connect(databasepath)，行为详见源实现。 |
