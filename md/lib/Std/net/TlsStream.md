# Net/TlsStream.sl

> 源文件：`Net/TlsStream.sl`

## class `TlsOptions`

- **说明**：TlsOptions — TLS 会话参数（可变配置对象，字段直接赋值）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `string caPem = ""` | CA 证书链 PEM 文本（用于验证对端）。空串 = 跳过验证 （信任所有对端，仅建议自签 / 内网测试场景使用） |
| 字段 | `string certPem = ""` | 本端证书 PEM 文本（服务端必填；客户端双向认证时提供） |
| 字段 | `string keyPem = ""` | 本端私钥 PEM 文本（与 certPem 配对） |
| 字段 | `string hostname = ""` | 主机名（客户端：SNI 发送 + 证书主机名校验；空串 = 不发送也不校验） |

## class `TlsStream`

- **说明**：TlsStream — TLS 双向流（一般经 wrap / accept 获取，勿直接构造）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `TcpSocket _socket = null` | 字段 _socket（类型见签名）。 |
| 字段 | `Int64 _tlsSid = 0` | 字段 _tlsSid（类型见签名）。 |
| 构造 | `_init_(TcpStream raw, Int64 tlsSid)` | raw 的所有权转移到本流（_socket / _sid 均从 raw 接管） |
| 方法 | `TlsStream wrap(TcpStream raw, TlsOptions opt)` | 客户端握手：在已连接的 TcpStream 上发起 TLS（证书 / SNI / 主机名校验） |
| 方法 | `TlsStream accept(TcpStream raw, TlsOptions opt)` | 服务端握手：在已 accept 的 TcpStream 上等待并完成 TLS （opt.certPem / opt.keyPem 提供本端证书） |
| 方法 | `TlsStream _handshake(TcpStream raw, TlsOptions opt, bool isServer)` | 会话创建 + 握手（挂起由 C VM 侧透明处理，此处只见终局） |
| 方法 | `Int32 read(ByteBuffer dst)` | 解密读：写入 dst 可写区；返回 0 = EOF（对端关闭）置位 _eof |
| 方法 | `void write(ByteBuffer src)` | 加密写：全量写出（写背压由 C 层挂起透明处理） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
| 方法 | `void close()` | 不覆写 closeRead / closeWrite：TLS 的 close_notify 是双向收尾， 无半关闭 syscall（基类默认仅置位封口，不动底层会话） 完全覆写：先销毁 TLS 会话（向对端发 close_notify），再关底层 TCP |
