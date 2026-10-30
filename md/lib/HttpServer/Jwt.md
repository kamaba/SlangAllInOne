# Jwt.sl

> 源文件：`Jwt.sl`

## class `JwtClaims`

- **说明**：SLang/Server/Jwt.sl — JWT claims 读取 + HS256 签验（P3 decode → P5 sign/verify） SLang.Jwt.decode：不验签（P0-P3 形态保留——仅解 payload）； SLang.Jwt.sign( claims, secret, expiresInSeconds )：HS256 签发 （RFC 7518 §3.2：HMAC-SHA256(key, header.payload)，base64url 无填充）； SLang.Jwt.verify( token, secret )：全量验签（header.alg 必须 HS256 + 签名逐字节比对 + 过期检查），通过返回 JwtClaims、失败返回 null。 哈希原语 = Std.Encoding.Sha256.hmac（C VM core_sha256.c，P5 落地—— 此前「P0-P3 不自造哈希」的封锁解除）。 base64url 编码复用 Base64.encodeToString + 归一（'+'→'-'、'/'→'_'、 去 '='）；解码侧 _normB64Url 反向（P3 已有）。 claims 载体 = Map<string,string>（JwtClaims.put 写入）；方法名 claim/put 避开 get/set 关键字（HttpClient 改名同款纪律）。 使用纪律（设计 §4.11）：decode 仍仅用于己方签发且签验发生在别处的 同源身份读取；第三方 token 验真用 verify。 JWT claims 视图（decode 产物；sub/exp 标准化 + 自定义 claim 直读）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string claim(string name)` | 任意自定义 claim（缺失 null；嵌套对象/数组 claim 存其 JSON 文本） |
| 方法 | `void put(string name, string val)` | 写入（sign 场景预备，P5+；运行期一般只读） |
| 属性 | `get string subject()` | "sub" 标准 claim（缺失 null） |
| 属性 | `get Int64 expiresAt()` | "exp" → Int64 秒级时间戳（缺失/非数字 = 0） |
| 属性 | `get bool expired()` | 现时 &gt; exp（exp 缺失恒 false）——decode 不自动拒，业务自行判（§4.11） |

## class `Jwt`

- **说明**：SLang 标准库类型 Jwt（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `JwtClaims decode(string token)` | 解码 JWT（不验签）；格式非法（非三段 / base64 坏 / 非法 JSON / payload 非对象）→ null |
| 方法 | `string _normB64Url(string s)` | base64url → 标准字母（'-'→'+'、'_'→'/'）+ 补 '=' 填充至 4 倍长 |
| 方法 | `string sign(JwtClaims claims, Int64 expiresInSeconds)` | ── HS256 签发 / 验签（P5，§4.11）── 签发 JWT（便捷形态：密钥取 ServerConfig.jwtSecret——未配置抛 ServerError.MissingJwtSecret） |
| 方法 | `JwtClaims verify(string token)` | 验签 JWT（便捷形态：密钥取 ServerConfig.jwtSecret——未配置恒 null） |
| 方法 | `string sign(JwtClaims claims, string secret, Int64 expiresInSeconds)` | 签发 JWT（HS256）： claims = 待写入的声明（sub/exp 由参数显式管理，其余经 put 自填）； secret = HMAC 密钥；expiresInSeconds &gt; 0 时自动写入 "exp" （Int64 秒级时间戳 = now + n），&lt;= 0 不写 exp（永不过期——业务自慎）； "iat"（签发时刻）恒写入。 输出 = base64url(header).base64url(payload).base64url(hmac)。 secret null/空串 → 抛 ServerError（协议防御：无密钥签发无意义） |
| 方法 | `JwtClaims verify(string token, string secret)` | 验签 JWT（HS256）： 全量校验 = 三段格式 + header.alg=="HS256" + 签名逐字节比对 + exp 过期检查（exp 已过 → null）。 任一环节失败返回 null（不抛——调用方按未认证处理）。 注意：decode 的「不验签读取」语义独立保留；本方法才是对 第三方 token 验真的正确入口。 |
| 方法 | `string _claimsToJson(JwtClaims c)` | claims → 紧凑 JSON 文本（{"k":"v",...}；值含引号/反斜杠时转义） |
| 方法 | `string _escapeJson(string s)` | JSON 字符串转义（引号 / 反斜杠 / 控制字符按 \u00XX） |
| 方法 | `Int32 _hexDigit(Int32 v)` | 0-15 → '0'..'f' 小写十六进制字符码 |
| 方法 | `string _encodeB64Url(string s)` | 文本 → base64url（标准编码后归一：'+'→'-'、'/'→'_'、剥 '='） |
| 方法 | `string _encodeB64UrlBytes(ByteBuffer src)` | 缓冲 → base64url（同上归一；消费后由调用方释放 mac） |
| 方法 | `bool _bytesEqual(ByteBuffer a, ByteBuffer b)` | 逐字节相等（长度不等调用方已排除；读视图推进独立于源） |
