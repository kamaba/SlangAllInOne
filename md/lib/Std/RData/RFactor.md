# RData.RFactor —— 分类变量（levels + 整数编码）

把一列文本标签映射为离散类别：保存 levels（类别名）和每个元素的整数
编码，常用于柱状图、分组统计和 CSV 分类列。

## 构造

| 方法 | 签名 | 说明 |
|------|------|------|
| `fromStrings` | `static RFactor fromStrings(List<string> labels)` | 按首次出现顺序建立 levels，逐元素编码。 |
| `fromCodes` | `static RFactor fromCodes(List<Int32> codes, List<string> levels)` | 由既有编码与 levels 直接构造。 |

```slang
import Std;

List<string> city = List<string>()
city.add( "Beijing" )
city.add( "Shanghai" )
city.add( "Beijing" )

RData.RFactor f = RData.RFactor.fromStrings( city )
Int32 code = f.codeAt( 0 )        // 0
string lab = f.labelAt( 1 )       // "Shanghai"
```

## 读取与统计

| 方法 | 签名 | 说明 |
|------|------|------|
| `length` | `Int32 length()` | 元素个数。 |
| `levelCount` | `Int32 levelCount()` | 类别数。 |
| `codeAt` | `Int32 codeAt(Int32 index)` | 第 index 个元素的编码；越界返回 -1。 |
| `levelAt` | `Int32 levelAt(Int32 index)` | 第 index 个类别名；越界返回空串。 |
| `labelAt` | `string labelAt(Int32 index)` | 第 index 个元素的类别名。 |
| `countOf` | `Int32 countOf(Int32 level)` | 某编码出现次数。 |
| `counts` | `List<Int32> counts()` | 各类别频数，顺序与 `levels()` 一致。 |
| `levels` | `List<string> levels()` | 类别名列表副本。 |

## 使用技巧 / 注意事项

- `fromStrings` 的 levels 按**首次出现顺序**生成；`counts()` 的顺序与之一致，
  可直接作为柱状图的高度与标签。
- `fromCodes` 不校验编码范围；若 `codeAt` 超出 levels 数量，`labelAt`
  返回空串。
- 从 CSV 里取分类列更方便：`RData.RTable.factorByName("city")`。
