# ApiResult.sl

> 源文件：`ApiResult.sl`

## class `ApiResult`

- **说明**：SLang/Server/ApiResult.sl — 统一 JSON 返回体（P1） 设计契约：SERVER_DESIGN.md §4.3 / §6.7 输出形态：{"code":0,"message":"ok","data":{...}} 注意：类字段名 payload（data 是关键字），输出 JSON 键名固定 "data"—— 组包一律走 toJson() 手工组树（键序 code→message→data 稳定，不依赖 fromData 对本类字段名的序列化）；嵌套 payload 经 BaseJson.fromData 递归。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 code = 0` | 0 = 成功；非 0 业务错误码（用户自定义段 ≥ 1000） |
| 字段 | `public string message = "ok"` | 描述文本 |
| 字段 | `public object payload = null` | 任意负载（Serializable 对象 / null；data 是关键字故字段名用 payload） |
| 构造 | `_init_()` | 无参构造显式落默认值（跨模块 string 字段默认值消费侧不可靠， [2026-10-17] 复盘 ②；本类多经 ok/fail 工厂构造，此处兜底） |
| 方法 | `ApiResult ok(object payload)` | 成功封装（payload 可为 null） |
| 方法 | `ApiResult fail(Int32 code, string message)` | 失败封装（code 业务码；message 描述） |
| 方法 | `string toJson()` | 序列化（键序 code → message → data；payload 经 fromData 递归） |
