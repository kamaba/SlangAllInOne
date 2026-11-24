# RData.RTimeSeries —— 时间序列容器

值 + 起点 + 采样频率，类似 R 的 `ts`。提供时间轴换算与 `lag` / `diff` /
`window`，是预测数据的时间底座。

## 构造

| 方法 | 签名 | 说明 |
|------|------|------|
| `create` | `static RTimeSeries create(RVector values, Float32 start, Float32 frequency)` | 由向量构造；频率 ≤ 0 时按 1 处理。 |
| `fromList` | `static RTimeSeries fromList(List<Float32> values, Float32 start, Float32 frequency)` | 由数值列表构造。 |

```slang
import Std;

List<Float32> q = List<Float32>()
q.add( 10.0f ); q.add( 12.0f ); q.add( 11.0f ); q.add( 14.0f )

RData.RTimeSeries ts = RData.RTimeSeries.fromList( q, 2024.0f, 4.0f )
Float32 t0 = ts.timeAt( 0 )   // 2024
Float32 t1 = ts.timeAt( 1 )   // 2024.25
```

## 读取

| 方法 | 签名 | 说明 |
|------|------|------|
| `length` | `Int32 length()` | 采样点数。 |
| `at` | `Float32 at(Int32 index)` | 第 index 个采样值（NA 位置为 0）。 |
| `start` | `Float32 start()` | 起点时间。 |
| `frequency` | `Float32 frequency()` | 每年采样数。 |
| `timeAt` | `Float32 timeAt(Int32 index)` | 时间 = `start + index / frequency`。 |
| `values` | `RVector values()` | 内部值向量。 |

## 变换

| 方法 | 签名 | 说明 |
|------|------|------|
| `lag` | `RTimeSeries lag(Int32 k)` | 滞后 k 期：前 k 项补 0，其余整体右移。 |
| `diff` | `RTimeSeries diff()` | 一阶差分，长度减 1；起点/频率不变。 |
| `window` | `RTimeSeries window(Int32 from, Int32 count)` | 截取窗口；新起点 = `timeAt(from)`。 |

## 使用技巧 / 注意事项

- `frequency` 是“每单位时间的采样数”，季度数据传 `4`、月度传 `12`；
  `timeAt` 因此得到 2024.25 这类小数时间。
- `lag` 前 k 项补的是 `0`，不是 NA；做残差/相关性统计时请留意这段
  人为补零。
- `diff` 保留原 `start`，所以第一个点对应的时间语义会前移一期。
- `window` 的 `from` 越界时由 `RVector.slice` 截断，结果可能为空向量。
