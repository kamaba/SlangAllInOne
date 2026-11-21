# Backends 后端 API 参考

> `Backends`（BackendRegistry.sl）：设备通道开关 / 可用性探测 / SIMD 阈值门控。
> `CudaBackend`（CudaBackend.sl）：CUDA 设备算子 + PTX JIT kernel 表 + 设备内存。
> 总览见 [../TensoraMethods.md](../TensoraMethods.md)，分派语义见 [../TensoraApi.md](../TensoraApi.md) §5。

## 1. Backends（BackendRegistry.sl）

全部 static。

### 1.1 设备通道开关

| 签名 | 说明 |
|---|---|
| `static void setCudaEnabled( bool v )` | CUDA 通道总开关 |
| `static void setRocmEnabled( bool v )` | ROCm 通道（预留） |
| `static void setNpuEnabled( bool v )` | NPU 通道（预留） |
| `static void setTpuEnabled( bool v )` | TPU 通道（预留） |

开关只门 `Tensor.to()` 上卡入口；**已上设备的张量按位置驱动继续走 GPU**，不受开关影响。

### 1.2 可用性与回落

| 签名 | 说明 |
|---|---|
| `static bool available( Int32 kind )` | 硬件探测（CUDA：dll 加载 + 设备数 > 0；CPU 恒 true） |
| `static void setFallbackToCpu( bool v )` / `static bool isFallbackToCpu()` | 设备不可用时的回落策略 |
| `static void checkPair( Device a, Device b ) throws` | 二元设备算子前置校验（混合设备抛异常） |

### 1.3 SIMD 开关与阈值

| 签名 | 说明 |
|---|---|
| `static void setSimdEnabled( bool v )` / `static bool isSimdEnabled()` | CPU SIMD 总开关 |
| `static string simdIsaName()` | 当前生效 ISA（如 "AVX2"） |
| `static bool simdMatmulOn( Int32 m, Int32 k, Int32 n )` | 形状阈值判定：够大才值得走 SIMD（免小形状调度开销） |
| `static bool simdSumOn( Int32 n )` | 同上 |
| `static bool simdSoftmaxOn( Int32 rows, Int32 cols )` | 同上 |
| `static bool simdConv2dOn( Int32 c, Int32 outH, Int32 outW, Int32 k )` | 同上 |

### 1.4 SIMD 执行器（kernel 装配层）

| 签名 | 说明 |
|---|---|
| `static Array<Float32> simdMatmulArray( Array<Float32> a, Array<Float32> b, ... )` | 裸数组 SIMD 矩阵乘 |
| `static Array<Float32> simdSumArray( Array<Float32> x )` | 裸数组 SIMD 求和 |
| `static Array<Float32> simdSoftmaxArray( Array<Float32> x, ... )` | 裸数组 SIMD softmax |
| `static Array<Float32> simdConv2dArray( Array<Float32> input, Array<Float32> kernel, ... )` | 裸数组 SIMD 卷积 |

Tensor 算子内部经阈值判定后调用这些执行器 → `Cpu_x64` FFI。

## 2. CudaBackend（CudaBackend.sl）

Tensor 设备分支的落点。全部 static，均要求张量已 `.to(gpu)` 且 F32。

### 2.1 探测

| 签名 | 说明 |
|---|---|
| `static bool cudaOk()` | CUDA 基础可用（dll + 初始化） |
| `static bool kernelsReady()` | PTX kernel 表 JIT 完成 |

### 2.2 设备算子（Tensor 方法 → 此处）

| 签名 | Tensor 方法 | 说明 |
|---|---|---|
| `static Tensor elemwise( Tensor a, Tensor b, Int32 op, Int32 blen )` | add/sub/mul/div/maximum/minimum | op 表：0=add 1=sub 2=mul 3=div 4=min 5=max；blen = b 元素数（同形/行向量/标量广播） |
| `static Tensor unaryGpu( Tensor a, Int32 op )` | relu/sigmoid/tanh/exp/reciprocal/sqrt/rsqrt/log2/exp2/abs/floor/ceil/round/sign/square/silu/gelu | t_unary 单 kernel 多 op（op 表见下 §3.1） |
| `static Tensor scaleGpu( Tensor a, Float32 k )` | scale(k) | 标量乘 |
| `static Array<Float32> sumGpu( Tensor a )` | sum() | 单线程标量序累加（位级一致） |
| `static Tensor matmulGpu( Tensor a, Tensor b, Int32 m, Int32 k, Int32 n )` | matmul(b) | 每线程一输出、p 序累加禁 fma（位级一致） |
| `static Tensor softmaxGpu( Tensor a, Int32 rows, Int32 cols )` | softmax() | 每线程一行三遍标量序 |
| `static bool fillGpu( Tensor t, Float32 v )` | — | 设备填充 |
| `static bool scaleInPlaceGpu( Tensor t, Float32 k )` | — | 设备原地缩放 |

### 2.3 传输（§5 staging 协议）

| 签名 | 说明 |
|---|---|
| `static bool uploadFlow( Tensor t )` | S1 惰性上传：主机权威 → 设备 |
| `static bool downloadFlow( Tensor t )` | S2 下载协议：P3 全同步 + P4 循环回填（`ensureHostFresh` 触发） |
| `static bool uploadInto( Int64 devPtr, Array<Float32> values, Int32 bytes )` | 数组指针直传 H2D（OQ-1 零拷贝，`to()` 内部用） |
| `static bool stageOut( Tensor t )` | 出口张量置 S2（设备权威） |

### 2.4 设备内存

| 签名 | 说明 |
|---|---|
| `static Int64 allocDevRaw( Int64 bytes, Device dev )` | 原始设备分配（带全局记账） |
| `static void freeDevRaw( Int64 ptr, Int64 bytes, Device dev )` | 释放（记账回收） |
| `static Int64 arrayDataPtr( Array<Float32> a )` | SL 数组数据首地址（DMA 直传用） |

### 2.5 kernel 装配（PTX JIT）

| 签名 | 说明 |
|---|---|
| `static Int64 jit( string ptx, string entry )` | PTX 源码 → 模块 → 函数句柄 |
| `static bool launchFlat( Int64 func, Int32 total, Int32 block, Int64 argsPtr )` | 一维网格发射 |
| `static bool launch2D( Int64 func, Int32 gx, Int32 gy, Int32 bx, Int32 by, ... )` | 二维网格发射 |
| `static Tensor deviceTensor( Shape shp, Device dev, Int64 ptr )` | 包装设备张量（挂 ptr + S2） |

### 2.6 PTX 源码生成（内部）

`ptxHead` / `ptxExp` / `ptxBin` / `ptxScale` / `ptxUnary` / `ptxSum` / `ptxMmul` / `ptxSmx` / `ptxFill` —— 编译期拼装 PTX 字符串的生成器，业务代码不直接调用。

## 3. PTX op 表

### 3.1 t_unary（unaryGpu 单 kernel 多 op 分派）

| op | 算子 | PTX | 分支 |
|---|---|---|---|
| 0 | relu | 比较语义 | UOLD |
| 1 | sigmoid | ex2 换算 | UOLD |
| 2 | tanh | 近似 | UOLD |
| 3 | exp | ex2.approx | UOLD |
| 4 | reciprocal | div.rn | UNEW |
| 5 | sqrt | sqrt.rn | UNEW |
| 6 | rsqrt | rsqrt.approx | UNEW |
| 7 | log2 | lg2.approx | UNEW |
| 8 | exp2 | ex2.approx | UNEW |
| 9 | abs | 符号位清零 | UBIT |
| 10 | neg（预留） | — | UBIT |
| 11 | floor | cvt.rm | UBIT |
| 12 | ceil | cvt.rp | UBIT |
| 13 | round | cvt.rni | UBIT |
| 14 | sign | 比较语义 | UBIT |
| 15 | square | mul | UBIT |
| 16 | silu | 组合 | USILU |
| 17 | gelu | tanh 近似组合 | UGELU |

分支跳转：op<4 → UOLD，op<9 → UNEW，op<16 → UBIT，16 → USILU，17 → UGELU。

### 3.2 elemwise（二元）

| op | 算子 |
|---|---|
| 0 | add |
| 1 | sub |
| 2 | mul |
| 3 | div |
| 4 | min（Tensor.minimum） |
| 5 | max（Tensor.maximum） |

广播由 `blen`（= `b._data.length`）判定：`blen == n` 同形 / `blen == cols` 行向量 / `blen == 1` 标量。

## 4. 使用示例

```slang
# Tensor 层（推荐入口，自动走 CudaBackend）
Backends.setCudaEnabled( true )
if Backends.available( EDeviceKind.GPU )
{
    Tensor g = x.to( Device.gpu( 0 ) )
    Tensor r = g.mul( 2.0f ).sqrt()      # elemwise op2 + unaryGpu op5
    Tensor back = r.cpu()
}

# 直接 JIT 自定义 kernel（高级）
Int64 f = CudaBackend.jit( myPtx, "my_kernel" )
CudaBackend.launchFlat( f, n, 256, argsPtr )
```
