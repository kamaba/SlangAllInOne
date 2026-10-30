# IO/FileStream.sl

> 源文件：`IO/FileStream.sl`

## class `FileStream`

- **说明**：SLang 标准库类型 FileStream（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _handle = 0` | 字段 _handle（类型见签名）。 |
| 字段 | `string _path = null` | 字段 _path（类型见签名）。 |
| 构造 | `_init_(string path, FileMode mode)` | ── 构造 ── |
| 构造 | `_init_(string path, FileMode mode, FileAccess access)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string path()` | ── 路径 ── |
| 属性 | `get Int64 position()` | ── 位置 ── |
| 属性 | `set void position(Int64 pos)` | 设置 position 的值。 |
| 属性 | `get Int64 length()` | 获取 length 的值。 |
| 方法 | `Int64 seek(Int64 offset, SeekOrigin origin)` | IO 读写 / 流控制（seek）。 |
| 方法 | `Int32 read(ByteBuffer dst)` | ── 核心读写 ── |
| 方法 | `void write(ByteBuffer src)` | IO 读写 / 流控制（write）。 |
| 方法 | `void flush()` | ── 冲刷 ── |
| 方法 | `void flushToDisk()` | 强制落盘（fsync / _commit） |
| 方法 | `void close()` | ── 生命周期 ── 完全覆写：直接释放句柄并封口两个方向 （不走基类 close -&gt; closeWrite -&gt; flush 链，只读流会误触 flush） |
