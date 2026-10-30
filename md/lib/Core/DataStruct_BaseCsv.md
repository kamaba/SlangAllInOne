# DataStruct/BaseCsv.sl

> 源文件：`DataStruct/BaseCsv.sl`

## class `BaseCsv`

- **说明**：CSV 文件门面：基于 Table 二维表容器实现的 CSV 读写工具。 Table 承载列名表头、定宽数据行、类型化取值与查询统计能力（解析/序列化在 VM 层完成）， 本类负责 CSV 文本的进出与配置（表头开关、分隔符），并把 Table 的行/列/单元格/查询/统计接口透传出来。 典型用法：Csv c = Csv("name,age\nalice,30") -> c.getInt(0, "age") / c.toString()。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string _delimiter = ","` | 字段分隔符（构造时指定，默认逗号；序列化时使用） |
| 方法 | `override _init_()` | 默认构造：空表（表头模式，逗号分隔） |
| 方法 | `void _init_(string csvText)` | 按 CSV 文本构造（首行为表头，逗号分隔；解析在 VM 层完成） |
| 方法 | `void _init_(string csvText, bool hasHeader, string delimiter)` | 按 CSV 文本构造（可指定表头开关与分隔符；解析在 VM 层完成） |
| 方法 | `void _init_(Table table)` | 包装既有 Table（共享同一表对象，对 Csv 的修改即对 Table 的修改） |
| 方法 | `BaseCsv parse(string csvText)` | ---- 静态工厂 ---- 解析 CSV 文本（首行为表头） |
| 方法 | `BaseCsv parseNoHeader(string csvText)` | 解析无表头 CSV（列名自动补 col{n}） |
| 方法 | `BaseCsv parseDelimited(string csvText, bool hasHeader, string delimiter)` | 解析 CSV 文本（自定义表头开关与分隔符） |
| 属性 | `get Table table()` | ---- 基础属性 ---- 内部表活引用（可直接使用 Table 全部能力） |
| 属性 | `get int rowCount()` | 获取 rowCount 的值。 |
| 属性 | `get int columnCount()` | 获取 columnCount 的值。 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get bool hasHeader()` | 序列化时是否输出表头行 |
| 属性 | `set void hasHeader(bool value)` | 设置 hasHeader 的值。 |
| 属性 | `get string delimiter()` | 当前分隔符 |
| 方法 | `Array&lt;Object&gt; _getItem_(int row)` | ---- 行索引器（返回行数组活引用，越界返回 null）---- |
| 方法 | `void addColumn(string name)` | ---- 表头维护（透传 Table）---- |
| 方法 | `void insertColumn(int colIndex, string name)` | 执行 insertColumn(colIndex, name)，行为详见源实现。 |
| 方法 | `bool removeColumn(string name)` | 执行 removeColumn(name)，行为详见源实现。 |
| 方法 | `bool removeColumnAt(int colIndex)` | 执行 removeColumnAt(colIndex)，行为详见源实现。 |
| 方法 | `bool renameColumn(string oldName, string newName)` | 执行 renameColumn(oldName, newName)，行为详见源实现。 |
| 方法 | `bool containsColumn(string name)` | 判断 / 校验是否（containsColumn）。 |
| 方法 | `int getColumnIndex(string name)` | 执行 getColumnIndex(name)，行为详见源实现。 |
| 方法 | `string getColumnName(int colIndex)` | 执行 getColumnName(colIndex)，行为详见源实现。 |
| 方法 | `Array&lt;string&gt; columnNames()` | 执行 columnNames()。 |
| 方法 | `List&lt;Object&gt; getColumnValues(string name)` | 执行 getColumnValues(name)，行为详见源实现。 |
| 方法 | `int newRow()` | ---- 行维护（透传 Table）---- |
| 方法 | `int addRow(Array&lt;Object&gt; row)` | 执行 addRow(row)，行为详见源实现。 |
| 方法 | `int insertRow(int row, Array&lt;Object&gt; rowData)` | 执行 insertRow(row, rowData)，行为详见源实现。 |
| 方法 | `bool removeRowAt(int row)` | 执行 removeRowAt(row)，行为详见源实现。 |
| 方法 | `int removeRowsWhere(string columnName, Object value)` | 删除指定列上值匹配的所有行（返回删除行数） |
| 方法 | `void clear()` | 清空数据行（保留表头） |
| 方法 | `void clearAll()` | 全部清空（表头 + 数据行） |
| 方法 | `Object getValue(int row, int col)` | ---- 单元格读写（透传 Table）---- |
| 方法 | `Object getValueByName(int row, string columnName)` | 执行 getValueByName(row, columnName)，行为详见源实现。 |
| 方法 | `void setValue(int row, int col, Object value)` | 执行 setValue(row, col, value)，行为详见源实现。 |
| 方法 | `void setValueByName(int row, string columnName, Object value)` | 执行 setValueByName(row, columnName, value)，行为详见源实现。 |
| 方法 | `int getInt(int row, int col)` | ---- 类型化取值（null / 越界 / 无法解析返回默认值）---- |
| 方法 | `int getInt(int row, int col, int defaultValue)` | 执行 getInt(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `int getIntByName(int row, string columnName, int defaultValue)` | 执行 getIntByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(int row, int col)` | 执行 getFloat(row, col)，行为详见源实现。 |
| 方法 | `Float64 getFloat(int row, int col, Float64 defaultValue)` | 执行 getFloat(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloatByName(int row, string columnName, Float64 defaultValue)` | 执行 getFloatByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBool(int row, int col)` | 执行 getBool(row, col)，行为详见源实现。 |
| 方法 | `bool getBool(int row, int col, bool defaultValue)` | 执行 getBool(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBoolByName(int row, string columnName, bool defaultValue)` | 执行 getBoolByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `string getStr(int row, int col)` | 执行 getStr(row, col)，行为详见源实现。 |
| 方法 | `string getStr(int row, int col, string defaultValue)` | 执行 getStr(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `string getStrByName(int row, string columnName, string defaultValue)` | 执行 getStrByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `BaseCsv clone()` | ---- 克隆 / 合并 / 连接（透传 Table）---- 值语义深拷贝 |
| 方法 | `BaseCsv cloneStructure()` | 结构克隆：只保留表头，不携带数据行 |
| 方法 | `BaseCsv cloneRange(int rowStart, int rowCount, int colStart, int colCount)` | 区间克隆（越界自动截断） |
| 方法 | `bool merge(Table other)` | 纵向合并（other 的行按列名对齐追加，缺失列补 null） |
| 方法 | `bool mergeCsv(BaseCsv other)` | 执行 mergeCsv(other)，行为详见源实现。 |
| 方法 | `Table join(Table other, string keyColumn)` | 内连接：以 keyColumn 为键 |
| 方法 | `Table joinCsv(BaseCsv other, string keyColumn)` | 执行 joinCsv(other, keyColumn)，行为详见源实现。 |
| 方法 | `Array&lt;int&gt; findRows(string columnName, Object value)` | ---- 查询（透传 Table，查找/排序/去重在 VM 层完成）---- |
| 方法 | `void sortBy(string columnName)` | 比较 / 排序 / 相等判定（sortBy）。 |
| 方法 | `void sortBy(string columnName, bool ascending)` | 比较 / 排序 / 相等判定（sortBy）。 |
| 方法 | `void sortByAt(int colIndex, bool ascending)` | 比较 / 排序 / 相等判定（sortByAt）。 |
| 方法 | `int distinctRows()` | 执行 distinctRows()。 |
| 方法 | `Float64 min(string columnName)` | ---- 统计（透传 Table）---- |
| 方法 | `Float64 max(string columnName)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Float64 sum(string columnName)` | 算术：返回两数之和（sum）。 |
| 方法 | `Float64 avg(string columnName)` | 执行 avg(columnName)，行为详见源实现。 |
| 方法 | `string toCsv()` | ---- 序列化 ---- 序列化为 CSV（按当前表头开关，逗号分隔；转义在 VM 层完成） |
| 方法 | `string toCsvDelimited()` | 序列化为 CSV（使用构造时指定的分隔符） |
| 方法 | `string toCsvDelimited(string delimiter)` | 序列化为 CSV（显式指定分隔符） |
| 方法 | `string toCsvNoHeader()` | 无表头序列化（一次性开关，不改变表状态） |
| 方法 | `string preview(int maxRows)` | ---- 显示 ---- markdown 风格预览（默认前 10 行，VM 层完成） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
