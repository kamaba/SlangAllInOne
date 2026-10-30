# Net/NetStream.sl

> 源文件：`Net/NetStream.sl`

## class `TcpStream`

- **说明**：TcpStream — TCP 双向流

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `TcpSocket _socket = null` | 字段 _socket（类型见签名）。 |
| 构造 | `_init_(TcpSocket socket)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int32 read(ByteBuffer dst)` | 非阻塞读：写入 dst 可写区；返回 0 = EOF（对端关闭）置位 _eof |
| 方法 | `void write(ByteBuffer src)` | 全量写出（写背压由 C 层挂起透明处理） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
| 方法 | `void closeRead()` | 半关闭：停收（对端再写会收到连接重置） |
| 方法 | `void closeWrite()` | 半关闭：停发（先冲刷再 shutdown，对端 read 将见 EOF） |
| 方法 | `void close()` | 完全覆写：直接释放句柄并封口两个方向 （不走基类 close -&gt; closeWrite -&gt; flush 链，FileStream 同款） |

## class `UdpStream`

- **说明**：UdpStream — UDP 报文流

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `UdpSocket _socket = null` | 字段 _socket（类型见签名）。 |
| 构造 | `_init_(UdpSocket socket)` | 报文语义：无固定对端（_canWrite = false，定向发送走 sendTo） |
| 方法 | `Int32 read(ByteBuffer dst)` | 数据报读取：一次 read 收一报写入 dst（超出 dst 容量的尾部由 C 侧丢弃） |
| 方法 | `void write(ByteBuffer src)` | Phase 1 无 connect(对端) 语义：固定对端写入不支持（守卫抛 NotSupported） |
| 方法 | `void flush()` | IO 读写 / 流控制（flush）。 |
| 方法 | `void sendTo(ByteBuffer src, string address, Int32 port)` | 定向发送（UDP 专属，不经 write 的固定对端守卫） |
| 方法 | `Stream&lt;UdpDatagram&gt; datagrams()` | 数据报流（Stream 体系直连）：引流协程循环收报灌进 controller， 消费方经 Stream&lt;UdpDatagram&gt; 逐报读取；close / 底层出错时 ctrl.close() 收尾。 闭包内直接走系统调用（系统调用不抛异常，哨兵值判定）， 不经 this.read（throws 语义在闭包内不可用）。 |
| 方法 | `void close()` | 完全覆写：直接释放句柄并封口两个方向（TcpStream 同款） |
