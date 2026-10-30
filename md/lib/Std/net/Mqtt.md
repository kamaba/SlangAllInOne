# Net/Mqtt.sl

> 源文件：`Net/Mqtt.sl`

## class `MqttMessage`

- **说明**：MqttMessage — 一条收到的 PUBLISH 消息

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string topic = ""` | 主题 |
| 字段 | `public ByteBuffer payload = null` | 载荷（归属本消息；消费完调 release 归还，勿外部持有引用跨越 release） |
| 字段 | `public Int32 qos = 0` | 服务端授予的 QoS（0 / 1） |
| 字段 | `public Int32 packetId = 0` | QoS 1 时的报文标识符 |
| 字段 | `public bool retain = false` | retain 标志 |
| 构造 | `_init_(string topic, ByteBuffer payload, Int32 qos, Int32 packetId, bool retain)` | 构造方法，初始化本类型实例。 |
| 属性 | `get Int32 size()` | 获取 size 的值。 |
| 方法 | `string text()` | 载荷按 UTF-8 解码为文本（内嵌 NUL 截断语义同 ByteBuffer.toString） |
| 方法 | `void release()` | 执行 release()。 |

## class `MqttConnectOptions`

- **说明**：MqttConnectOptions — CONNECT 报文参数

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string clientId = "slmqtt"` | 客户端标识（UTF-8 编码后 &lt;= 65535 字节由 _writeMqttString 自然截断/校验） |
| 字段 | `public bool cleanSession = true` | 清除会话标志（CONNECT flags bit1） |
| 字段 | `public Int32 keepAliveSeconds = 60` | 保活间隔（秒，0 = 不保活） |
| 字段 | `public string username = ""` | 用户名（空串 = 不携带） |
| 字段 | `public string password = ""` | 密码（空串 = 不携带） |
| 字段 | `public Int32 connectTimeoutMs = 10000` | TCP 建连 + 握手（CONNACK 等待）超时毫秒 |

## class `_MqttPacket`

- **说明**：_MqttPacket — 内部已解析包（固定头 + 载荷，不对外注册）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 type = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 flags = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public ByteBuffer payload = null` | 字段 ByteBuffer（类型见签名）。 |
| 方法 | `void release()` | 执行 release()。 |

## class `MqttCodec`

- **说明**：MqttCodec — 编解码（全静态）

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `Int32 remainingLengthSize(Int32 value)` | 剩余长度 varint 剩余长度编码后占几字节（1..4）；非法值（&lt;0 或 &gt;268435455）抛 Protocol |
| 方法 | `ByteBuffer encodeRemainingLength(Int32 value)` | 剩余长度编码（每字节低 7 位、最高位延续、最多 4 字节） |
| 方法 | `Int32 decodeRemainingLength(ByteBuffer buf)` | 剩余长度解码（从 buf 当前读位起）： &gt;=0 成功（已消费 varint 字节）；-1 数据不足（回滚读位）； -2 非法（超过 4 字节上限，回滚读位） |
| 方法 | `void _writeMqttString(ByteBuffer outBuf, string text)` | MQTT 字符串（U16 长度前缀 + UTF-8） 写入 U16 前缀 + UTF-8 字节（长度天然按字节计） |
| 方法 | `string readMqttString(ByteBuffer buf)` | 读取 U16 前缀 + UTF-8 字节；长度前缀或字节数不足抛 Protocol |
| 方法 | `ByteBuffer _frame(Int32 ptype, Int32 flags, ByteBuffer body)` | 组帧：固定头第 1 字节 + 剩余长度 + body（body 归属本方法，消费后释放） |
| 方法 | `ByteBuffer encodeConnect(MqttConnectOptions opt)` | 各控制包编码 CONNECT（MQTT 3.1.1：协议名 MQTT / level 4） |
| 方法 | `ByteBuffer encodePublish(string topic, ByteBuffer payload, Int32 qos, Int32 packetId, bool retain)` | PUBLISH：flags = qos*2 + retain（DUP 恒 0）；payload 经 slice() 视图 零拷贝写入（视图索引独立，不推进源） |
| 方法 | `ByteBuffer encodeSubscribe(Int32 packetId, string topic, Int32 qos)` | SUBSCRIBE（固定头 flags 固定 0b0010）；body = packetId + 主题过滤器 + QoS |
| 方法 | `ByteBuffer encodeUnsubscribe(Int32 packetId, string topic)` | UNSUBSCRIBE（固定头 flags 固定 0b0010）；body = packetId + 主题过滤器 |
| 方法 | `ByteBuffer encodePingReq()` | PINGREQ（无载荷，固定 2 字节 c000） |
| 方法 | `ByteBuffer encodePingResp()` | PINGRESP（无载荷，固定 2 字节 d000） |
| 方法 | `ByteBuffer encodeDisconnect()` | DISCONNECT（无载荷，固定 2 字节 e000） |
| 方法 | `ByteBuffer encodeAck(Int32 ptype, Int32 packetId)` | PUBACK（type=4）/ UNSUBACK（type=11）通用应答：body = packetId |
| 方法 | `ByteBuffer encodeConnack(bool sessionPresent, Int32 returnCode)` | CONNACK（服务端用）：sessionPresent + returnCode |
| 方法 | `ByteBuffer encodeSuback(Int32 packetId, Int32 grantedQos)` | SUBACK（服务端用）：packetId + 授予 QoS（单主题） |
| 方法 | `_MqttPacket parsePacket(ByteBuffer buf)` | 解析 从 buf 当前读位起解析一个完整包： 非 null 成功（已消费对应字节，payload 为独立拷贝）； null 数据不足（读位回滚，等更多数据）； 非法（type==0 / 剩余长度超限）抛 Protocol 并回滚 |
| 方法 | `_MqttPacket readPacket(NetStream s, ByteBuffer buf)` | 从流读一个完整包（buf 为残留缓冲，_fill 补数据）； 返回 null = 对端关闭（EOF） |
| 方法 | `MqttMessage parsePublish(_MqttPacket pkt)` | 解析 PUBLISH 载荷为 MqttMessage（载荷为独立拷贝， 调用方随后应对原包调 release） |
| 方法 | `bool _fill(NetStream s, ByteBuffer buf, Int32 need)` | 补数据直到 buf 可读字节 &gt;= need；返回 false = 对端关闭（EOF）。 满则先压缩再按需扩容（Websocket._fill 同款） |

## class `MqttClient`

- **说明**：MqttClient — MQTT 3.1.1 客户端（QoS 0 / 1）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `NetStream _stream = null` | 字段 _stream（类型见签名）。 |
| 字段 | `ByteBuffer _recvBuf = null` | 字段 _recvBuf（类型见签名）。 |
| 字段 | `Int32 _nextPacketId = 1` | 字段 _nextPacketId（类型见签名）。 |
| 字段 | `bool _connected = false` | 字段 _connected（类型见签名）。 |
| 属性 | `get bool isConnected()` | 获取 isConnected 的值。 |
| 方法 | `MqttClient connect(string host, Int32 port)` | 接入 |
| 方法 | `MqttClient connect(string host, Int32 port, MqttConnectOptions opt)` | 执行 connect(host, port, opt)，行为详见源实现。 |
| 方法 | `void _connectHandshake(MqttConnectOptions opt)` | 握手：发 CONNECT -&gt; 等 CONNACK；returnCode != 0 抛 ConnackRejected |
| 方法 | `MqttMessage receive()` | 收发 收一条 PUBLISH（null = 对端 DISCONNECT 或断开）； QoS 1 自动回 PUBACK；先弹 _waitPacket 期间缓存的消息 |
| 方法 | `void publish(string topic, string text)` | 发布文本（QoS 0） |
| 方法 | `void publish(string topic, string text, Int32 qos)` | 发布文本（qos 仅支持 0 / 1；QoS 1 同步等 PUBACK） |
| 方法 | `Int32 subscribe(string topic, Int32 qos)` | 订阅主题过滤器，返回服务端授予的 QoS |
| 方法 | `void unsubscribe(string topic)` | 退订主题过滤器（同步等 UNSUBACK） |
| 方法 | `void ping()` | 心跳（同步等 PINGRESP） |
| 方法 | `void disconnect()` | 主动断开：尽力发 DISCONNECT -&gt; 关流 -&gt; 复位；任一步失败不抛 |
| 方法 | `_MqttPacket _waitPacket(Int32 wantType)` | 内部 等待指定类型包；途中收到的 PUBLISH 解析入队（稍后 receive 弹出）， 其余包释放忽略；对端断开 / DISCONNECT 返回 null |
| 方法 | `void _ackPublish(MqttMessage msg)` | QoS 1 消息自动回 PUBACK |
| 方法 | `Int32 _allocPacketId()` | 报文标识符分配（1..65535 循环） |
