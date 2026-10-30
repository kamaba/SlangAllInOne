# GPU/GPU.sl

> 源文件：`GPU/GPU.sl`

## class `GPU`

- **说明**：SLang 标准库类型 GPU（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private Int32 _tileSizeWidth = 16` | GPU（Device Compute）属性 - 标注方法为 GPU kernel 用法: @GPU()                        使用全部默认值 @GPU( 32, 32 )                指定 tile 尺寸 @GPU( 32, 32, 4, 0 )          tile 尺寸 + tileNum + groupId @GPU( 32, 32, 4, 0, 16, 16, 1, 256, 1, 1, 0, 0, "kernel" )  全参 编译中（Compiling）生效: 标注在成员函数上, 由 MLIRExporter 发射 gpu.module/gpu.func, host 侧发射 gpu.launch 调度逻辑 ---- Tile 分块参数（矩阵分块计算） ---- tile 宽度（列方向元素数） |
| 字段 | `private Int32 _tileSizeHeight = 16` | tile 高度（行方向元素数） |
| 字段 | `private Int32 _tileNum = 0` | tile 总数（一维展开的 tile 编号上限，0 = 按 grid*block 自动推导） |
| 字段 | `private Int32 _groupId = 0` | 工作组 id（多 kernel 协作时的分组编号，0 = 默认组） |
| 字段 | `private Int32 _gridDimX = 1` | ---- Launch 网格参数（CUDA grid/block 语义） ---- grid 维度（block 数量） |
| 字段 | `private Int32 _gridDimY = 1` | 字段 Int32（类型见签名）。 |
| 字段 | `private Int32 _gridDimZ = 1` | 字段 Int32（类型见签名）。 |
| 字段 | `private Int32 _blockDimX = 256` | block 维度（每 block 线程数） |
| 字段 | `private Int32 _blockDimY = 1` | 字段 Int32（类型见签名）。 |
| 字段 | `private Int32 _blockDimZ = 1` | 字段 Int32（类型见签名）。 |
| 字段 | `private Int32 _sharedMemorySize = 0` | 每 block 动态共享内存字节数 |
| 字段 | `private Int32 _deviceId = 0` | 目标设备编号（多 GPU 时选择） |
| 字段 | `private string _kernelName = ""` | kernel 符号名（空 = 使用方法名） |
| 方法 | `override _init_()` | 无参构造: @GPU() 使用全部默认值 |
| 属性 | `get Int32 tileSizeWidth()` | ---- Tile 参数 getter ---- |
| 属性 | `get Int32 tileSizeHeight()` | 获取 tileSizeHeight 的值。 |
| 属性 | `get Int32 tileNum()` | 获取 tileNum 的值。 |
| 属性 | `get Int32 groupId()` | 获取 groupId 的值。 |
| 属性 | `get Int32 gridDimX()` | ---- Launch 网格参数 getter ---- |
| 属性 | `get Int32 gridDimY()` | 获取 gridDimY 的值。 |
| 属性 | `get Int32 gridDimZ()` | 获取 gridDimZ 的值。 |
| 属性 | `get Int32 blockDimX()` | 获取 blockDimX 的值。 |
| 属性 | `get Int32 blockDimY()` | 获取 blockDimY 的值。 |
| 属性 | `get Int32 blockDimZ()` | 获取 blockDimZ 的值。 |
| 属性 | `get Int32 sharedMemorySize()` | 获取 sharedMemorySize 的值。 |
| 属性 | `get Int32 deviceId()` | 获取 deviceId 的值。 |
| 属性 | `get string kernelName()` | 获取 kernelName 的值。 |
