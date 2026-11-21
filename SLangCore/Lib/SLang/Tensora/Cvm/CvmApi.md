# Cvm 平台中间层 API 参考

> Cvm 是 Tensora 的跨平台 FFI 聚合层，底层为 `sl_tensora_lib.dll`（cvm_sl_tensora_lib.vcxproj，CPU+CUDA 合一工程）。
> 上层 Tensor / Backends 通过本层访问平台算子、内存与 CUDA 原生 API。
> 总览见 [../TensoraMethods.md](../TensoraMethods.md)，架构见 [../TensoraBackend.md](../TensoraBackend.md)。

## 目录

1. [Cvm 聚合门面](#1-cvm-聚合门面)
2. [Cpu_x64 x64 平台 FFI](#2-cpu_x64-x64-平台-ffi)
3. [Cpu_arm64 / Tpu / Npu 占位接口](#3-cpu_arm64--tpu--npu-占位接口)
4. [Mem 跨平台内存管理](#4-mem-跨平台内存管理)
5. [Onnx 模型读取](#5-onnx-模型读取)
6. [Cuda 原生 API 类族](#6-cuda-原生-api-类族)

---

## 1. Cvm 聚合门面

`Cvm` 为静态门面，全部方法 1:1 委托 `Cpu_x64` 同名方法（当前唯一实装平台；ARM64 构建启用后切至 Cpu_arm64）。

```slang
# 初始化 / 版本
Cvm.initialize()            # C 库握手（幂等）
Cvm.version()               # Int32 版本号
Cvm.lastError()             # Int32 错误码
Cvm.errorString()           # string 错误信息

# ISA 探测 / 控制
Cvm.isaId()                 # 当前生效 ISA 枚举（ISA_SSE2/ISA_AVX/ISA_AVX2/ISA_AVX512/ISA_NEON）
Cvm.isaName()               # 如 "AVX2"
Cvm.forceIsa( isa )         # 强制指定 ISA（调试 / 基准用），返回设置后的 isaId
Cvm.hasFma()                # 是否 FMA 可用

# SIMD 算子（裸指针 kernel 装配层，业务代码请走 Tensor API）
Cvm.matmul( aBlk, bBlk, oBlk, m, k, n )
Cvm.sum( xBlk, oBlk, n )
Cvm.softmax( xBlk, oBlk, rows, cols )
Cvm.conv2d( inBlk, wtBlk, oBlk, ... )

# 主机内存
Cvm.uploadF32( values )     # 数组 → 主机块（分配 + 拷贝），返回地址
Cvm.pinF32( values )        # 数组锁页（返回原数组首地址，DMA 直达）
Cvm.downloadF32( addr, count )  # 主机块 → SL 数组
Cvm.freeBlock( addr )       # 释放 uploadF32 分配的主机块
```

## 2. Cpu_x64 x64 平台 FFI

x64 构建（SSE2/AVX/AVX2/AVX-512 kernel，`slcp_*` 符号面）的直连绑定。

### 2.1 高层门面（业务推荐）

与 Cvm 同名同义（见上节），另含：

| 签名 | 说明 |
|---|---|
| `static bool initialize()` | 加载 dll + ISA 探测 |
| `static Int32 isaId()` / `static string isaName()` | 运行期 CPU 特性 |
| `static Int32 forceIsa( Int32 isa )` | 强制 ISA |
| `static bool hasFma()` | FMA 支持 |
| `static Int32 version()` / `lastError()` / `errorString()` | 版本 / 错误 |
| `static bool matmul( Int64 aBlk, Int64 bBlk, Int64 oBlk, Int32 m, Int32 k, Int32 n )` | SIMD 矩阵乘 |
| `static bool sum( Int64 xBlk, Int64 oBlk, Int32 n )` | SIMD 求和 |
| `static bool softmax( Int64 xBlk, Int64 oBlk, Int32 rows, Int32 cols )` | SIMD 行 softmax |
| `static bool conv2d( Int64 inBlk, Int64 wtBlk, Int64 oBlk, ... )` | SIMD 2D 卷积 |
| `static Int64 uploadF32( Array<Float32> values )` | 数组上传主机块 |
| `static Int64 pinF32( Array<Float32> values )` | 数组锁页 |
| `static Array<Float32> downloadF32( Int64 addr, Int32 count )` | 主机块下载 |
| `static void freeBlock( Int64 addr )` | 释放主机块 |

### 2.2 原始绑定（lib* 直调层，业务勿用）

`libInit` / `libIsaId` / `libIsaName` / `libForceIsa` / `libHasFma` / `libVersion` / `libLastError` / `libErrorString` / `libMatmul` / `libSum` / `libSoftmax` / `libConv2D` —— C 导出函数 1:1 绑定（`@DllStaticImport`），高层门面即它们的包装。

## 3. Cpu_arm64 / Tpu / Npu 占位接口

平台接口已按命名拆分，等待对应硬件实装：

| 类 | 状态 | 方法 |
|---|---|---|
| `Cpu_arm64` | 预留骨架（NEON kernel 已在 C 工程内，vcxproj 未配 ARM64 平台） | `available()`（x64 构建下恒 false）/ `toString()` |
| `Tpu` | 预留骨架 | `available()` 恒 false / `toString()` |
| `Npu` | 预留骨架（昇腾 ACL / QNN / ANE 方向，按 §6.4 插件规约） | `available()` 恒 false / `toString()` |

## 4. Mem 跨平台内存管理

CPU↔GPU（及未来硬件）数据传输 / 查看 / 手动管理。全部 static。

### 4.1 拷贝类（源保留）

| 签名 | 说明 |
|---|---|
| `static Int64 copyToDevice( Array<Float32> values, Device dev )` | 数组拷贝式上设备（源数组保留），返回设备指针 |
| `static bool copyToHost( Int64 devPtr, Array<Float32> dst, Device dev )` | 设备 → 主机数组（拷贝） |
| `static bool copyDevice( Int64 dstPtr, Int64 srcPtr, Int64 bytes, Device dev )` | 设备内 D2D |
| `static bool copyHost( Int64 dst, Int64 src, Int64 bytes )` | 主机内存拷贝 |
| `static bool copyArray( Array<Float32> dst, Array<Float32> src )` | SL 数组间拷贝 |

### 4.2 移动类（源让渡，速度优先）

| 签名 | 说明 |
|---|---|
| `static Int64 moveToDevice( Array<Float32> values, Device dev )` | 移动式上设备（避免一次主机复制） |
| `static Int64 moveFromDevice( Tensor t )` | 张量数据移动式下载 |

### 4.3 锁页 / 释放

| 签名 | 说明 |
|---|---|
| `static Int64 pin( Array<Float32> values )` | 数组锁页（返回主机指针，GPU DMA 直达，免中转拷贝） |
| `static bool free( Int64 devPtr, Int64 bytes, Device dev )` | 释放设备内存 |
| `static bool freeHost( Int64 addr )` | 释放主机内存 |

### 4.4 查看 / 直读

| 签名 | 说明 |
|---|---|
| `static Float32 hostRead( Int64 ptr, Int32 i )` | 主机指针读第 i 个 Float32（ONNX 权重抽查） |
| `static Int32 hostReadI( Int64 ptr, Int32 byteOffset )` | 主机指针按字节偏移读 Int32 |
| `static void inspect( Tensor t, string tag )` | 打印张量全量（自动设备同步） |
| `static void inspect( Tensor t, string tag, Int32 head )` | 打印前 head 个 |
| `static void inspectDevice( Int64 devPtr, Int32 count, Device dev, string tag )` | 打印设备指针内容（内部下载） |

### 4.5 原始绑定

`static Int32 libMemcpy( Int64 dst, Int64 src, Int64 bytes )` —— C memcpy 1:1。

### 4.6 使用示例

```slang
# 拷贝式（源保留）
Int64 dp = Mem.copyToDevice( arr, Device.gpu( 0 ) )
Array<Float32> back = Array<Float32>( arr.length )
Mem.copyToHost( dp, back, Device.gpu( 0 ) )
Mem.free( dp, arr.length * 4, Device.gpu( 0 ) )

# 锁页 DMA（零中转）
Int64 pinned = Mem.pin( bigArray )      # GPU DMA 可直达此地址

# 张量查看
Mem.inspect( t, "weights", 8 )          # 前 8 个 + 形状信息
```

## 5. Onnx 模型读取

ONNX C 底层解析（sl_onnx.c）：解析在 C 层完成，SL 层只拿数据指针（零拷贝直读）。实例风格：`Onnx.open()` 返回实例，内部持有 `Int64 _handle`，方法经实例调用。

### 5.1 高层 API（业务推荐）

| 签名 | 返回 | 说明 |
|---|---|---|
| `static Onnx open( string path )` | Onnx 实例 | 构造即打开并解析（失败实例 `_handle == 0`，`ok()` 为 false） |
| `bool ok()` | bool | 是否持有有效句柄（打开成功且未 close） |
| `bool close()` | bool | 关闭释放；幂等，关闭后 `_handle` 置 0（防悬挂） |
| `Int32 count()` | Int32 | initializer（权重）个数 |
| `string name( Int32 idx )` | string | 权重名（如 "Parameter193"） |
| `Int32 rank( Int32 idx )` | Int32 | 维度数 |
| `Int32 dim( Int32 idx, Int32 axis )` | Int32 | 指定维尺寸 |
| `Int32 elemCount( Int32 idx )` | Int32 | 元素总数 |
| `Int32 dataType( Int32 idx )` | Int32 | ONNX 类型码（1 = FLOAT） |
| `Int64 dataPtr( Int32 idx )` | Int64 | **权重数据主机指针**（配合 `Mem.hostRead` 直读） |
| `static Int32 lastError()` | Int32 | 错误码 |
| `static string errorString()` | string | 错误信息 |
| `Tensor loadTensor( Int32 idx )` | Tensor | 权重物化为 Tensor（pin + 一次 memcpy，形状自动还原） |
| `static bool makeTestModel( string path )` | bool | 生成最小测试模型（自检） |

### 5.2 原始绑定（lib*）

`libOpen` / `libClose` / `libCount` / `libName` / `libRank` / `libDim` / `libElemCount` / `libDataType` / `libDataPtr` / `libCopyF32(model, idx, dstPtr)` / `libLastError` / `libErrorString` / `libMakeTestModel` —— C 导出 1:1。

### 5.3 完整示例（mnist-8）

```slang
Onnx m = Onnx.open( "mnist-8.onnx" )            # 实例（内嵌 Int64 _handle）
if m.ok()
{
    Int32 cnt = m.count()
    for i = 0, i < cnt, i++
    {
        global.println( m.name( i ) + " rank=" + m.rank( i ).toString() )
        Int64 p = m.dataPtr( i )
        Float32 w0 = Mem.hostRead( p, 0 )        # 指针直读抽查
    }
    Tensor w = m.loadTensor( 0 )                 # 物化为 Tensora 张量
    Mem.inspect( w, "w0" )
    m.close()                                    # 幂等，关闭后 _handle 置 0
}
```

## 6. Cuda 原生 API 类族

CUDA Runtime/Driver 直通层（`slc_*` 符号，运行期 LoadLibrary 解析 nvcuda/cudart——构建期零 CUDA SDK 依赖）。

### 6.1 Cuda（静态入口）

| 签名 | 说明 |
|---|---|
| `static bool initialize( Int32 flags )` → 门面 `initialize()` | CUDA 初始化 |
| `static Int32 driverVersion()` / `driverVersionText()` | 驱动版本（数字 / "12.4" 文本） |
| `static Int32 deviceCount()` | 设备数 |
| `static CudaDevice device( Int32 ordinal )` / `defaultDevice()` | 设备对象 |
| `static bool setDevice( Int32 ordinal )` / `static Int32 currentDevice()` | 当前设备切换 / 查询 |
| `static bool synchronize()` | 全设备同步 |
| `static Int64 memFreeBytes()` / `memTotalBytes()` | 显存空闲 / 总量 |
| `static Int32 lastError()` / `errorString()` / `errorStringOf( err )` | 错误查询 |

### 6.2 CudaDevice

| 签名 | 说明 |
|---|---|
| `string computeCapability()` | 如 "8.6" |
| `Int32 attr( Int32 attrId )` | 设备属性 |
| `bool makeCurrent()` | 设为当前设备 |
| `bool synchronize()` | 同步该设备 |

### 6.3 CudaBuffer

| 签名 | 说明 |
|---|---|
| `static CudaBuffer alloc( Int64 bytes )` | 设备内存分配 |
| `static CudaBuffer allocManaged( Int64 bytes )` | 统一内存分配 |
| `bool upload( Int64 srcPtr, Int64 bytes )` / `upload( srcPtr )` | H2D（同步） |
| `bool download( Int64 dstPtr, Int64 bytes )` / `download( dstPtr )` | D2H（同步） |
| `bool uploadAsync( srcPtr, bytes, CudaStream )` / `downloadAsync(...)` | 异步版本 |
| `bool memset8( Int32 value )` / `memset8( value, bytes )` | 填充 |
| `void free()` | 释放 |

### 6.4 CudaStream / CudaEvent

| 签名 | 说明 |
|---|---|
| `static CudaStream create()` | 创建流 |
| `bool synchronize()` / `void destroy()` | 同步 / 销毁 |
| `static CudaEvent create()` / `createTiming()` | 创建事件（后者可计时） |
| `bool record( CudaStream )` / `bool synchronize()` / `void destroy()` | 记录 / 等待 / 销毁 |
| `static Float64 elapsedMs( CudaEvent start, CudaEvent end )` | 两事件间毫秒 |

### 6.5 CudaKernelArgs / CudaKernel（PTX JIT）

| 签名 | 说明 |
|---|---|
| `void clear()` | 清空参数 |
| `void addPtr( Int64 )` / `addI64` / `addI32` / `addF32` / `addF64` | 按类型追加 kernel 实参 |
| `static CudaKernel fromPtx( string ptx, string entryName )` | PTX 源码 JIT 编译 + 入口定位 |
| `bool launch( gx, gy, gz, bx, by, bz, sharedBytes, CudaStream, CudaKernelArgs )` | 通用发射 |
| `bool launch1D( Int32 total, Int32 blockSize, CudaStream, CudaKernelArgs )` | 一维网格快捷发射 |
| `void destroy()` | 卸载模块 |

### 6.6 原始绑定（lib*）

`libInit` / `libDriverVersion` / `libDeviceCount` / `libDeviceName` / `libDeviceTotalMem` / `libDeviceAttr` / `libDeviceSet` / `libDeviceGet` / `libCtxSync` / `libMemAlloc` / `libMemAllocManaged` / `libMemFree` / `libMemset8` / `libMemcpyH2D` / `libMemcpyD2H` / `libMemcpyD2D` / `libMemcpyH2DAsync` / `libMemcpyD2HAsync` / `libMemInfo` / `libStreamCreate` / `libStreamDestroy` / `libStreamSync` / `libEventCreate` / `libEventDestroy` / `libEventRecord` / `libEventSync` / `libEventElapsedMs` / `libModuleLoadData` / `libModuleUnload` / `libModuleGetFunction` / `libKernelLaunch` / `libLastError` / `libErrorString`。
