# Net/UdpSocket.sl

> 源文件：`Net/UdpSocket.sl`

## class `UdpSocket`

- **说明**：Net/UdpSocket.sl — UDP 套接字 设计契约：csimple_lang/md/design/NETSTREAM_DESIGN.md §6.6 用法: import Std; var s = Net.Udp.open( 9000 )                    # 绑定端口得 UdpStream s.sendTo( buf, "127.0.0.1", 9001 )              # 定向发送 var n = s.read( dst )                           # 挂起收一报写入 dst var dgs = s.datagrams()                         # 报文流（Stream 体系直连） 语义要点（与设计文档对应）: - recvFrom 挂起直到有数据报（Option A 指令重执行），一次收一报写入 dst 可写区，超出 dst 容量的报文尾部由 C 侧丢弃 - 来源地址不随返回值带出：经 C 侧 last-from 槽位查询 （lastFromAddress / lastFromPort） - sendTo 全量写出：写出多少推进 src.readerIndex 多少 - 失败 = 哨兵值 + last_error 可查，SL 层负责 throw UdpSocket — 裸 socket 包装（一般经 Udp.bind 获取，勿直接构造）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _sid = 0` | 字段 _sid（类型见签名）。 |
| 构造 | `_init_(Int64 sid)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int32 recvFrom(ByteBuffer dst)` | 挂起直到有数据报：一次收一报写入 dst 可写区，返回本报字节数； 空数据报返回 0（UDP 合法报文，非错误）。 setReadTimeout 配置超时后，等待超过窗口抛 NetError.Timeout |
| 方法 | `void setReadTimeout(Int32 timeoutMs)` | 读超时毫秒（&lt;= 0 = 取消超时，无限等待）。作用于 recvFrom 的挂起 等待（sendTo 无挂起等待，不受影响） |
| 方法 | `void sendTo(ByteBuffer src, string address, Int32 port)` | 全量发送：写出多少推进 src.readerIndex 多少（重挂起由 C 层透明处理） |
| 属性 | `get string lastFromAddress()` | 最近一次 recvFrom 的来源地址（C 侧 last-from 槽位） |
| 属性 | `get Int32 lastFromPort()` | 最近一次 recvFrom 的来源端口 |
| 方法 | `void close()` | 关闭并释放句柄；C 侧会取消挂在该 sid 上的全部在途等待 |

## class `Udp`

- **说明**：Udp — 外观类（SL 命名空间不能放裸函数 -> 静态工厂收口）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `UdpStream open(Int32 port)` | IO 读写 / 流控制（open）。 |
| 方法 | `UdpStream openAddress(string host, Int32 port)` | IO 读写 / 流控制（openAddress）。 |

## class `UdpDatagram`

- **说明**：UdpDatagram — 数据报值对象（datagrams() 流的元素）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `ByteBuffer _data = null` | 字段 _data（类型见签名）。 |
| 字段 | `string _address = ""` | 字段 _address（类型见签名）。 |
| 字段 | `Int32 _port = 0` | 字段 _port（类型见签名）。 |
| 构造 | `_init_(ByteBuffer payload, string address, Int32 port)` | 构造方法，初始化本类型实例。 |
| 属性 | `get ByteBuffer payload()` | 报文负载（收报后 readerIndex 从 0 起，直接按 ByteBuffer 读取） |
| 属性 | `get string address()` | 获取 address 的值。 |
| 属性 | `get Int32 port()` | 获取 port 的值。 |
