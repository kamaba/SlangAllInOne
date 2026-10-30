# DataStruct/Table.sl

> 源文件：`DataStruct/Table.sl`

## class `Table`

- **基类**：Object
- **说明**：二维表容器：CSV / Excel / 数据库结果集的中间数据层（仿 DataTable / pandas DataFrame 的精简版）。 核心数据结构： _columns   -- 列名表头 List<string>（列的唯一权威定义） _rows      -- 数据行 List<Array<Object>>，每行为与列宽等长的定宽数组 _hasHeader -- CSV 序列化时是否输出表头行（解析时由入口指定，不影响行存储） 单元格为 Object（string / 数值标量 / 布尔 / null 皆可），读取时经 getXxx 族做健壮类型转换。 性能设计：克隆、合并、查找、排序、去重、CSV 解析/序列化、预览等遍历与比较的耗时操作 全部通过 SystemTable* 系统调用映射到 CVM 原生实现（table_system_method.c）， SL 层仅负责表头/行的结构性维护与类型化取值入口。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `bool _hasHeader = true` | 字段 _hasHeader（类型见签名）。 |
| 字段 | `int _index = -1` | --- 迭代器字段 --- |
| 字段 | `Array&lt;Object&gt; _current = null` | 字段 _current（类型见签名）。 |
| 方法 | `override _init_()` | 默认构造：无列无行，列名在使用时动态补充 |
| 方法 | `void _init_(Array&lt;string&gt; columns)` | 按列名构造（null 名自动补 "col{n}"） |
| 方法 | `void _init_(Array&lt;string&gt; columns, int _rowCount)` | 按列名 + 预建空行数构造 |
| 方法 | `void _init_(Table other)` | 克隆构造：单元格值语义深拷贝（VM 层单次调用完成） |
| 属性 | `get int rowCount()` | ---- 基础属性 ---- 数据行数 |
| 属性 | `get int columnCount()` | 列数 |
| 属性 | `get bool isEmpty()` | 获取 isEmpty 的值。 |
| 属性 | `get bool isNotEmpty()` | 获取 isNotEmpty 的值。 |
| 属性 | `get bool hasHeader()` | 序列化时是否输出表头行 |
| 属性 | `set void hasHeader(bool value)` | 设置 hasHeader 的值。 |
| 方法 | `Array&lt;string&gt; columnNames()` | 列名数组拷贝（修改返回值不影响表头） |
| 属性 | `get Array&lt;Object&gt; first()` | 首行 / 末行（空表返回 null；返回的是行数组活引用） |
| 属性 | `get Array&lt;Object&gt; last()` | 获取 last 的值。 |
| 方法 | `Array&lt;Object&gt; _getItem_(int row)` | ---- 行索引器（返回行数组活引用，越界返回 null）---- |
| 方法 | `void _setItem_(int row, Array&lt;Object&gt; value)` | 整行替换（经规整对齐当前列宽，非法索引忽略） |
| 方法 | `void addColumn(string name)` | ---- 表头维护 ---- 追加列（null 名自动补 "col{n}"；已有行末尾补 null 单元格） |
| 方法 | `void insertColumn(int colIndex, string name)` | 在 colIndex 处插入列（越界时退化为末尾追加；已有行在 colIndex 处插入 null 单元格） |
| 方法 | `bool removeColumn(string name)` | 按名删除列（返回是否删除成功） |
| 方法 | `bool removeColumnAt(int colIndex)` | 按下标删除列（所有行同步删除对应单元格） |
| 方法 | `bool renameColumn(string oldName, string newName)` | 列重命名（列不存在返回 false） |
| 方法 | `bool containsColumn(string name)` | 是否包含指定列 |
| 方法 | `int getColumnIndex(string name)` | 列名 -&gt; 列下标（不存在返回 -1） |
| 方法 | `string getColumnName(int colIndex)` | 列下标 -&gt; 列名（越界返回 null） |
| 方法 | `List&lt;Object&gt; getColumnValues(string name)` | 取整列值（列不存在返回空列表） |
| 方法 | `int newRow()` | ---- 行维护 ---- 新建一行全 null 行并返回行号 |
| 方法 | `int addRow(Array&lt;Object&gt; row)` | 追加一行（行宽超过列数时自动扩列补名；返回新行行号） |
| 方法 | `int insertRow(int row, Array&lt;Object&gt; rowData)` | 在 row 处插入一行（越界忽略返回 -1；行宽超过列数时自动扩列补名） |
| 方法 | `bool removeRowAt(int row)` | 按下标删除行（返回是否删除成功） |
| 方法 | `int removeRowsWhere(string columnName, Object value)` | 删除指定列上值匹配的所有行（返回删除行数；查找在 VM 层完成） |
| 方法 | `void clear()` | 清空数据行（保留表头，迭代器复位） |
| 方法 | `void clearAll()` | 全部清空（表头 + 数据行） |
| 方法 | `Array&lt;Object&gt; normalizeRow(Array&lt;Object&gt; row)` | ---- 内部维护 ---- 规整行宽：返回与当前列数等长的新数组（不足补 null，超出截断；null 行返回全 null 行） |
| 方法 | `void expandRows(int width)` | 扩列到 width：新列名默认 "col{n}"，已有行重建为等宽数组（末尾补 null） |
| 方法 | `Object getValue(int row, int col)` | ---- 单元格读写 ---- 原始 Object 取值（越界 / null 单元格返回 null） |
| 方法 | `Object getValueByName(int row, string columnName)` | 执行 getValueByName(row, columnName)，行为详见源实现。 |
| 方法 | `void setValue(int row, int col, Object value)` | 原始 Object 写值（越界忽略） |
| 方法 | `void setValueByName(int row, string columnName, Object value)` | 执行 setValueByName(row, columnName, value)，行为详见源实现。 |
| 方法 | `int getInt(int row, int col)` | 类型化取值（健壮转换在 VM 层完成：null / 越界 / 无法解析返回默认值） |
| 方法 | `int getInt(int row, int col, int defaultValue)` | 执行 getInt(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `int getIntByName(int row, string columnName, int defaultValue)` | 执行 getIntByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloat(int row, int col)` | 执行 getFloat(row, col)，行为详见源实现。 |
| 方法 | `Float64 getFloat(int row, int col, Float64 defaultValue)` | 执行 getFloat(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `Float64 getFloatByName(int row, string columnName, Float64 defaultValue)` | 执行 getFloatByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBool(int row, int col)` | 执行 getBool(row, col)，行为详见源实现。 |
| 方法 | `bool getBool(int row, int col, bool defaultValue)` | 执行 getBool(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `bool getBoolByName(int row, string columnName, bool defaultValue)` | 执行 getBoolByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `string getStr(int row, int col)` | 字符串取值（null / 越界返回 ""；数值单元格转最短字面量） |
| 方法 | `string getStr(int row, int col, string defaultValue)` | 执行 getStr(row, col, defaultValue)，行为详见源实现。 |
| 方法 | `string getStrByName(int row, string columnName, string defaultValue)` | 执行 getStrByName(row, columnName, defaultValue)，行为详见源实现。 |
| 方法 | `Table clone()` | ---- 克隆 ---- 值语义深拷贝（行数组与单元格重建，字符串对象共享引用） |
| 方法 | `Table cloneStructure()` | 结构克隆：只保留表头，不携带数据行 |
| 方法 | `Table cloneRange(int rowStart, int rowCount, int colStart, int colCount)` | 区间克隆：行 [rowStart, rowStart+rowCount) x 列 [colStart, colStart+colCount)（越界自动截断） |
| 方法 | `Table cloneRows(Array&lt;int&gt; rowIndices)` | 行挑选克隆：按行号数组抽取行（非法行号跳过） |
| 方法 | `bool merge(Table other)` | ---- 合并 ---- 纵向合并：other 的行按列名对齐追加（缺失列自动补建并 pad null；返回是否成功） |
| 方法 | `Table union(Table other)` | 纵向合并的新表版本：返回 this 与 other 合并后的新表 |
| 方法 | `Table join(Table other, string keyColumn)` | 内连接：以 keyColumn 为键，右表列（键列除外）拼接到左侧行后；右表重名列加 "_2" 后缀。 表头构建、键倒排索引与行匹配拼接全部在 VM 层完成（table_system_method.c），键为单元格字符串形式。 |
| 方法 | `Array&lt;int&gt; findRows(string columnName, Object value)` | ---- 查询 ---- 查找指定列上值匹配的全部行号（升序数组；列不存在返回空数组；查找在 VM 层完成） |
| 方法 | `void sortBy(string columnName)` | 按列排序（升序；稳定排序在 VM 层完成） |
| 方法 | `void sortBy(string columnName, bool ascending)` | 比较 / 排序 / 相等判定（sortBy）。 |
| 方法 | `void sortByAt(int colIndex, bool ascending)` | 按列下标排序（数值按数值序，字符串按字典序，null 最前） |
| 方法 | `int distinctRows()` | 整行去重（保留首次出现；返回删除行数，比较在 VM 层完成） |
| 方法 | `Float64 min(string columnName)` | ---- 统计（非 null 单元格参与；无法解析为数值的按 0 计）---- |
| 方法 | `Float64 max(string columnName)` | 比较：返回较小 / 较大值（max）。 |
| 方法 | `Float64 sum(string columnName)` | 算术：返回两数之和（sum）。 |
| 方法 | `Float64 avg(string columnName)` | 执行 avg(columnName)，行为详见源实现。 |
| 方法 | `Table fromCsv(string csvText)` | ---- CSV ---- 解析 CSV 文本（首行为表头） |
| 方法 | `Table fromCsvNoHeader(string csvText)` | 解析无表头 CSV（列名自动补 col{n}） |
| 方法 | `string toCsv()` | 序列化为 CSV（含转义：分隔符/引号/换行触发引号包裹，"" 转义内嵌引号） |
| 方法 | `string toCsvDelimited(string delimiter)` | 转换 / 序列化 / 格式化（toCsvDelimited）。 |
| 方法 | `string preview(int maxRows)` | ---- 显示 ---- markdown 风格预览（默认前 10 行，VM 层完成） |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |
| 方法 | `void reset()` | ---- 迭代器（foreach 直接遍历数据行数组）---- |
| 方法 | `bool moveNext()` | 执行 moveNext()。 |
| 属性 | `get Array&lt;Object&gt; current()` | 获取 current 的值。 |
