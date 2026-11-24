# RData.RTable —— data.frame 风格列式数据表

CSV 入口 + 列式视图：数值列用 `RVector` 保存，文本列按需解析成 `RFactor`。
适合把外部数据接进图表。

## 构造

| 方法 | 签名 | 说明 |
|------|------|------|
| `create` | `static RTable create(List<string> names)` | 建空表，列名由列表给出，各列为空 `RVector`。 |
| `fromCsvText` | `static RTable fromCsvText(string text)` | 解析 CSV 文本；列名取首行，所有列按数值解析。 |
| `fromCsvFile` | `static RTable fromCsvFile(string path)` | 读取文件后调用 `fromCsvText`。 |

```slang
import Std;

string csv = "city,sales,profit\nBeijing,120,30\nShanghai,150,40\n"
RData.RTable t = RData.RTable.fromCsvText( csv )

RData.RVector sales = t.columnByName( "sales" )
RData.RFactor city = t.factorByName( "city" )
string firstCity = t.stringAt( 0, 0 )
```

## 列与单元格

| 方法 | 签名 | 说明 |
|------|------|------|
| `columnCount` | `Int32 columnCount()` | 列数。 |
| `rowCount` | `Int32 rowCount()` | 行数（取第一列长度）。 |
| `nameAt` | `string nameAt(Int32 index)` | 列名；越界返回空串。 |
| `columnIndex` | `Int32 columnIndex(string name)` | 列名下标；找不到返回 -1。 |
| `has` | `bool has(string name)` | 是否含该列。 |
| `column` | `RVector column(Int32 index)` | 按列号取数值列；越界返回 null。 |
| `columnByName` | `RVector columnByName(string name)` | 按列名取数值列。 |
| `stringAt` | `string stringAt(Int32 col, Int32 row)` | 原始 CSV 单元格文本；越界返回空串。 |
| `stringsOf` | `List<string> stringsOf(Int32 col)` | 整列文本副本。 |

## 分类列与改写

| 方法 | 签名 | 说明 |
|------|------|------|
| `factor` | `RFactor factor(Int32 index)` | 把某列文本转为因子。 |
| `factorByName` | `RFactor factorByName(string name)` | 按列名转因子。 |
| `setNumericColumn` | `void setNumericColumn(Int32 index, RVector values)` | 替换某列的数值向量。 |
| `head` | `RTable head(Int32 count)` | 返回只含前 count 行的新表。 |

## 使用技巧 / 注意事项

- `fromCsvText` 把所有列都当数值解析（无法解析的单元格取 0）；文本列请
  用 `stringsOf` / `factor` 从原始 CSV 文本读取，不要当数值列用。
- `head` 输出的新表保留原始 CSV 文本，因此 `stringAt/stringsOf` 仍返回
  完整旧内容；数值列才是截断后的。
- `columnIndex` / `columnByName` 找不到时分别返回 `-1` / `null`，使用前
  先用 `has()` 判断更安全。
- `rowCount` 以第一列为准；如各列长度不一致，以创建时的首列为准。
