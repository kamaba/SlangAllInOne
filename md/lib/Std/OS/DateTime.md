# OS/DateTime.sl

> 源文件：`OS/DateTime.sl`

## class `DateTime`

- **说明**：DateTime 日期时间类型，API 参照 C# 的 System.DateTime 设计 内部表示：Unix 纪元毫秒（Int64）+ 是否按 UTC 解释（bool） 用法: import Std; OS.DateTime now = OS.DateTime.now() Console.println(now.toString())                     # 2026-08-25 14:30:00 Console.println(now.toString("yyyy/MM/dd"))         # 2026/08/25 OS.DateTime dt = OS.DateTime(2024, 2, 29, 12, 0, 0) # 指定分量构造（本地时区） OS.DateTime p = OS.DateTime.parse("2024-02-29T12:00:00") Console.println(dt.addDays(1).toString())           # 2024-03-01 12:00:00 Console.println(OS.DateTime.daysInMonth(2024, 2))   # 29 Console.println(OS.DateTime.isLeapYear(2024))       # true 说明: - dayOfWeek 取值 0..6，0=周日，与 C# DayOfWeek 枚举一致 - parse 失败时得到 DateTime.MinValue（isValid 为 false），不抛异常 - add* 系列返回新实例，不修改自身（与 C# 一致） - addMonths/addYears 遵循 C# 语义：目标月不足时"日"截断到月末

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _unixMillis = 0` | Unix 纪元毫秒（内部唯一时刻状态） |
| 字段 | `bool _isUtc = false` | 是否按 UTC 解释分量（false 时按本地时区，类似 C# DateTimeKind） |
| 字段 | `bool _isValid = false` | 是否为有效值（字符串解析失败时为 false） |
| 方法 | `override _init_()` | 构造函数 无参构造：DateTime.MinValue（0001-01-01 00:00:00） |
| 方法 | `void _init_(Int64 unixMillis)` | 从 Unix 毫秒构造（本地时区语义） |
| 方法 | `void _init_(Int64 unixMillis, bool isUtc)` | 从 Unix 毫秒构造并指定是否 UTC |
| 方法 | `void _init_(string text)` | 从字符串解析构造（格式 "yyyy-M-d[ H:m:s[.fff]]"，也接受 'T' 分隔） 解析失败得到 MinValue 且 isValid 为 false |
| 方法 | `void _init_(int year, int month, int day)` | 从年月日构造（本地时区零点） |
| 方法 | `void _init_(int year, int month, int day, int hour, int minute, int second)` | 从年月日时分秒构造（本地时区） |
| 方法 | `void _init_(int year, int month, int day, int hour, int minute, int second, int millisecond)` | 从年月日时分秒毫秒构造（本地时区） |
| 方法 | `DateTime now()` | 静态工厂 / 静态方法 当前本地时间 类似 C# DateTime.Now |
| 方法 | `DateTime utcNow()` | 当前 UTC 时间（与 now() 表示同一时刻，分量按 UTC 换算） 类似 C# DateTime.UtcNow |
| 方法 | `DateTime today()` | 今天零点（本地时区） 类似 C# DateTime.Today |
| 方法 | `DateTime fromUnixTimeMillis(Int64 millis)` | 从 Unix 毫秒构造（本地时区语义） |
| 方法 | `DateTime parse(string text)` | 解析字符串，失败返回 MinValue（isValid 为 false） 类似 C# DateTime.Parse（此处不抛异常） |
| 方法 | `bool tryParse(string text)` | 尝试解析字符串 类似 C# DateTime.TryParse |
| 方法 | `DateTime minValue()` | 最小值 0001-01-01 00:00:00（类似 C# DateTime.MinValue） |
| 方法 | `DateTime maxValue()` | 最大值 9999-12-31 23:59:59.999（类似 C# DateTime.MaxValue） |
| 方法 | `int daysInMonth(int year, int month)` | 某年某月的天数 类似 C# DateTime.DaysInMonth |
| 方法 | `bool isLeapYear(int year)` | 是否闰年 类似 C# DateTime.IsLeapYear |
| 属性 | `get Int64 unixTimeMillis()` | 属性 Unix 纪元毫秒 |
| 属性 | `get Int64 unixTimeSeconds()` | Unix 纪元秒 |
| 属性 | `get bool isUtc()` | 是否按 UTC 解释分量 |
| 属性 | `get bool isValid()` | 是否有效值（字符串解析失败时为 false） |
| 属性 | `get int year()` | 年 |
| 属性 | `get int month()` | 月（1..12） |
| 属性 | `get int day()` | 日（1..31） |
| 属性 | `get int hour()` | 时（0..23） |
| 属性 | `get int minute()` | 分（0..59） |
| 属性 | `get int second()` | 秒（0..59） |
| 属性 | `get int millisecond()` | 毫秒（0..999） |
| 属性 | `get int dayOfWeek()` | 星期几（0=周日 1=周一 ... 6=周六，与 C# DayOfWeek 枚举一致） |
| 属性 | `get string dayOfWeekName()` | 星期几英文名 |
| 属性 | `get int dayOfYear()` | 一年中的第几天（1..366） |
| 属性 | `get DateTime date()` | 当天零点（保留时区语义） 类似 C# DateTime.Date |
| 方法 | `DateTime addYears(int years)` | 加减运算（返回新实例，不修改自身） 加年（负数为减） |
| 方法 | `DateTime addMonths(int months)` | 加月（负数为减；目标月天数不足时"日"截断到月末，与 C# 一致） |
| 方法 | `DateTime addDays(int days)` | 加天（负数为减） |
| 方法 | `DateTime addHours(int hours)` | 加小时（负数为减） |
| 方法 | `DateTime addMinutes(int minutes)` | 加分钟（负数为减） |
| 方法 | `DateTime addSeconds(int seconds)` | 加秒（负数为减） |
| 方法 | `DateTime addMilliseconds(Int64 millis)` | 加毫秒（负数为减） |
| 方法 | `Int64 compareTo(DateTime other)` | 比较 / 输出 比较两个时刻：小于返回 -1，相等返回 0，大于返回 1 类似 C# DateTime.CompareTo |
| 方法 | `string toString()` | 默认格式化：yyyy-MM-dd HH:mm:ss |
| 方法 | `string toString(string format)` | 自定义格式化 支持 token: yyyy yy MM M dd d HH H hh h mm m ss s fff ff f tt 单字母标准格式: d D t T f F g G s u o R（简化映射，见文档） |
| 方法 | `string toDateString()` | 日期部分：yyyy-MM-dd |
| 方法 | `string toTimeString()` | 时间部分：HH:mm:ss |
| 方法 | `Int32 utcFlag()` | 内部辅助 _isUtc 转 Int32 标志（系统调用参数用） |
