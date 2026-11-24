# Debug/FrameData.sl

> 源文件：`Debug/FrameData.sl`（namespace SLang；自 Core/Data/FrameData.sl 空壳 stub 迁入 Std/Debug 并重构）

## class `SLang.FrameData`

- **说明**：帧数据变化记录基类：每次值变化记录「时间点（Unix 毫秒）+ frameCount（全局帧号）」两个数；环形历史缓冲保存最近 N 次变化；全局帧计数器由所有实例共享。泛型值包装请用 `FrameData<T>`。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `static Int64 _globalFrame = 0` | 全局帧计数（所有 FrameData 实例共享） |
| 方法 | `static void tickFrame()` | 全局帧号 +1（宿主主循环每帧调用一次） |
| 方法 | `static void setFrameCount(Int64 frame)` | 直接设置全局帧号（与外部帧号对齐时用） |
| 方法 | `static Int64 frameCount()` | 当前全局帧号 |
| 方法 | `void _init_()` | 空构造：无名，默认历史容量 64 |
| 方法 | `void _init_(string name)` | 带名构造：默认历史容量 64 |
| 方法 | `void _init_(string name, Int32 historyLength)` | 带名 + 历史容量构造（<=0 归 64） |
| 方法 | `string name()` / `void setName(string)` | 名称（便于管理类按名索引与输出） |
| 方法 | `Int32 historyLength()` | 历史容量（最多保留多少次变化） |
| 方法 | `Int64 changeCount()` | 累计变化次数（含已被环形覆盖掉的） |
| 方法 | `Int32 historyCount()` | 现存历史条数（<= 历史容量） |
| 方法 | `Int64 changeTime(Int32 idx)` | 第 idx 条变化的时间点（idx 从 0 起 = 最旧一条；越界返回 0） |
| 方法 | `Int64 changeFrame(Int32 idx)` | 第 idx 条变化的全局帧号（idx 从 0 起 = 最旧一条；越界返回 0） |
| 方法 | `Int64 lastChangeTime()` | 最近一次变化的时间点（从未变化返回 0） |
| 方法 | `Int64 lastChangeFrame()` | 最近一次变化的全局帧号（从未变化返回 0） |
| 方法 | `void clearHistory()` | 清空历史（累计计数一并归零；当前值不动） |
| 方法 | `void setHistoryLength(Int32 n)` | 调整历史容量：保留最近 min(n, 现存条数) 条记录 |

## class `SLang.FrameData<T>` extends `SLang.FrameData`

- **说明**：泛型值包装：`update(v)` 传入任意类型的值，值变化时自动记录「时间点 + frameCount」两个数。首次传入 = 初始化基线（不记录）；后续同值不记录（== 为值比较：数值/字符串/布尔按值，类按 equals 语义）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool update(T v)` | 传入新值。返回 true = 值发生变化且记录了一次历史；首次传入与同值重复传入返回 false |
| 方法 | `T currentValue()` | 当前值（未初始化时为 null） |
| 方法 | `bool hasValue()` | 是否已建立基线 |

## class `SLang.FrameDataManager`

- **说明**：FrameData 管理类：注册一批 FrameData（任意 T 的实例以基类引用收纳）后统一设置历史长度、按名查找、汇总统计与文本报表。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `void register(FrameData fd, string name)` | 注册（同名不覆盖，find 返回先注册者） |
| 方法 | `Int32 count()` | 已注册数量 |
| 方法 | `FrameData at(Int32 idx)` | 按序号取（越界返回 null） |
| 方法 | `FrameData find(string name)` | 按名查找（未找到返回 null） |
| 方法 | `bool remove(string name)` | 按名移除（返回是否找到并移除） |
| 方法 | `void setHistoryLength(Int32 n)` | 全部已注册项的历史容量统一调整（如 100 = 各保留最近 100 次变化） |
| 方法 | `bool setHistoryLength(string name, Int32 n)` | 单项调整历史容量（未找到返回 false） |
| 方法 | `Int64 totalChangeCount()` | 所有已注册项的累计变化次数总和 |
| 方法 | `void clear()` | 清空注册表（不改动各 FrameData 自身历史） |
| 方法 | `string report()` | 文本报表：每项一行（名称 / 累计变化 / 现存历史 / 最近变化帧号） |

## 用法

```slang
import Std;

SLang.FrameData<Int32> hp = SLang.FrameData<Int32>( "playerHp", 100 )
SLang.FrameDataManager mgr = SLang.FrameDataManager()
mgr.register( hp, "playerHp" )
mgr.setHistoryLength( 100 )          # 每个已注册项只保留最近 100 次变化
SLang.FrameData.tickFrame()          # 游戏主循环每帧推进一次
hp.update( 95 )                      # 值变化：记录 (时间点, frameCount)
Int64 t1 = hp.lastChangeTime()        # 最近一次变化的时间点（Unix 毫秒）
Int64 f1 = hp.lastChangeFrame()       # 最近一次变化的全局帧号
Int32  n  = hp.historyCount()         # 现存历史条数（<= 100）
Int64 t0 = hp.changeTime( 0 )          # 第 0 条 = 最旧一条
```

## 验证

- 验收测试：`SLangCore/test/Other/FrameDataProbe/`（F1~F10 共 49 项断言，Release VM 全部 PASS）。
- 注意：原计划挂 namespace `Data`，与 Core 根类 `Data` 同名——调用链解析 `Data.XXX` 会命中 `Core.Data` 类导致 FrameData 不可见，故归入 Debug 家族 `SLang` 命名空间（同 Log/Profiling/Trace 先例）。
