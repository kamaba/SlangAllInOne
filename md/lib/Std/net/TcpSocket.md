# Net/TcpSocket.sl

> 源文件：`Net/TcpSocket.sl`

## class `TcpSocket`

- **说明**：TcpSocket — 裸 socket 包装（一般经 Tcp / TcpServer 获取，勿直接构造）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _sid = 0` | 字段 _sid（类型见签名）。 |
| 字段 | `bool _open = false` | 字段 _open（类型见签名）。 |
| 构造 | `_init_(Int64 sid)` | 构造方法，初始化本类型实例。 |
| 属性 | `get bool isOpen()` | 获取 isOpen 的值。 |
| 属性 | `get string remoteAddress()` | 获取 remoteAddress 的值。 |
| 属性 | `get Int32 remotePort()` | 获取 remotePort 的值。 |
| 属性 | `get string localAddress()` | 获取 localAddress 的值。 |
| 属性 | `get Int32 localPort()` | 获取 localPort 的值。 |
| 方法 | `Int32 recv(ByteBuffer dst)` | 非阻塞 recv：写入 dst 可写区，返回本次读入字节数；0 = EOF（对端关闭） setReadTimeout 配置超时后，等待超过窗口抛 NetError.Timeout |
| 方法 | `void send(ByteBuffer src)` | 全量发送：写出多少推进 src.readerIndex 多少（重挂起由 C 层透明处理） setWriteTimeout 配置超时后，等待超过窗口抛 NetError.Timeout |
| 方法 | `void setReadTimeout(Int32 timeoutMs)` | 读超时毫秒（&lt;= 0 = 取消超时，无限等待）。作用于 recv 的挂起等待， 窗口自 recv 首次挂起时锚定（跨挂起重执行不重置） |
| 方法 | `void setWriteTimeout(Int32 timeoutMs)` | 写超时毫秒（&lt;= 0 = 取消超时，无限等待）。作用于 send 的挂起等待 |
| 方法 | `void setNoDelay(bool enabled)` | 执行 setNoDelay(enabled)，行为详见源实现。 |
| 方法 | `void shutdown(SocketShutdown how)` | 执行 shutdown(how)，行为详见源实现。 |
| 方法 | `void close()` | 关闭并释放句柄；C 侧会取消挂在该 sid 上的全部在途等待 |

## class `Tcp`

- **说明**：Tcp — 外观类（SL 命名空间不能放裸函数 -> 静态工厂收口）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `TcpStream connect(string host, Int32 port)` | 执行 connect(host, port)，行为详见源实现。 |
| 方法 | `TcpStream connectTimeout(string host, Int32 port, Int64 timeoutMs)` | 连接超时毫秒；失败码位细分：3 = 域名解析失败，其余按阶段归类 |
| 方法 | `TcpServer listen(Int32 port)` | 迭代器 / 订阅控制（listen）。 |
| 方法 | `TcpServer listenAddress(string host, Int32 port)` | 迭代器 / 订阅控制（listenAddress）。 |
| 方法 | `TcpStream streamOf(TcpSocket socket)` | 裸 socket 升级为流（acceptSocket / 手动精细控制后接入 Stream 体系） |

## class `TcpServer`

- **说明**：TcpServer — 服务端监听器

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _listenSid = 0` | 字段 _listenSid（类型见签名）。 |
| 构造 | `_init_(Int64 listenSid)` | 构造方法，初始化本类型实例。 |
| 方法 | `TcpStream accept()` | 挂起直到新连接（无连接时协程挂起，不阻塞 VM 线程）； 接入连接默认开 NoDelay |
| 方法 | `TcpSocket acceptSocket()` | setAcceptTimeout 配置超时后，等待超过窗口抛 NetError.Timeout |
| 方法 | `void setAcceptTimeout(Int32 timeoutMs)` | accept 挂起等待的超时毫秒（&lt;= 0 = 取消超时，无限等待） |
| 方法 | `void onConnection(Function fn)` | 回调形态（Phase 1 由协程组合模拟，设计 §6.7）： fn 为单参闭包，参数为接入的 TcpStream；每个连接一条协程 |
| 属性 | `get Int32 port()` | 获取 port 的值。 |
| 方法 | `void close()` | IO 读写 / 流控制（close）。 |
