# Tensora API 参考

> Tensor 核心类与神经网络层 API 详细参考：签名、参数语义、返回值、设备支持、示例与分派语义。
> 方法总览见 [TensoraMethods.md](TensoraMethods.md)；平台层见 [Cvm/CvmApi.md](Cvm/CvmApi.md)、[Backends/BackendsApi.md](Backends/BackendsApi.md)。

## 目录

1. [快速上手](#1-快速上手)
2. [调用约定](#2-调用约定)
3. [Tensor 构造与工厂](#3-tensor-构造与工厂)
4. [设备迁移与影子缓冲](#4-设备迁移与影子缓冲)
5. [GPU 算子分派与 PTX op 表](#5-gpu-算子分派与-ptx-op-表)
6. [算术 / 矩阵 / 归约 API](#6-算术--矩阵--归约-api)
7. [逐元素数学 / 激活 / 比较 API](#7-逐元素数学--激活--比较-api)
8. [形状操作 API](#8-形状操作-api)
9. [TensorMath 标量 API](#9-tensormath-标量-api)
10. [Shape / Device / Dtype / Rng API](#10-shape--device--dtype--rng-api)
11. [Backends 开关 API](#11-backends-开关-api)
12. [神经网络层 API](#12-神经网络层-api)
13. [常见用法示例集](#13-常见用法示例集)
14. [注意事项与已知差异](#14-注意事项与已知差异)

---

## 1. 快速上手

```slang
import Tensora

# CPU 基础流
Tensor x = Tensor.arange( 0, 6, 1 ).reshape( Shape.matrix( 2, 3 ) )
Tensor y = x.mul( 2.0f ).add( 1.0f )          # 广播算术
Tensor z = x.matmul( y.transpose() )           # 矩阵乘
Float32 s = z.sum()
Mem.inspect( z, "z" )                          # 打印内容

# GPU 流（CUDA 可用时）
Backends.setCudaEnabled( true )
if Backends.available( EDeviceKind.GPU )
{
    Device dev = Device.gpu( 0 )
    Tensor g = x.to( dev )                     # 上卡（零拷贝上传，出口 S2）
    Tensor r = g.matmul( g.transpose() )       # 设备上直接算
    Tensor back = r.cpu()                      # 下载回 CPU（源不动）
    Mem.inspect( back, "gpu result" )
}
```

## 2. 调用约定

| 约定 | 内容 |
|---|---|
| 导入 | `import Tensora`（模块内所有类全局可见） |
| 昵称 | `TensorMath`→`TMath`、`Activation`→`Act`、`Dense`→`Linear`、`Sequential`→`Seq`、`Rng`、`Module`、`Layer` 等（`@Nickname`） |
| 方法调用 | 实例方法一律 `this.` 显式风格：`x.add( y )`；静态方法 `Tensor.zeros(...)`、`TMath.sigmoid(...)` |
| 属性访问 | 无括号：`x.rows`、`x.shape`、`x.storage` |
| 保留字规避 | `get` / `data` 是保留字：取值统一 `at` 家族，底层数组叫 `storage` |
| 返回 | `ret` 语句（非 return） |
| 语句结尾 | 无分号 |
| for 循环 | 头部全逗号：`for i = 0, i < n, i++`（**误写分号会令解析器 NRE 崩溃**） |
| 异常 | 设备迁移类方法带 `throws`，调用方需在可抛上下文 |
| 类型 | `Float32` / `Int32` 与 `float` / `int` 同类混用 |

## 3. Tensor 构造与工厂

### 3.1 构造器

```slang
Tensor()                             # 标量 0
Tensor( Shape shape )                # 零填充
Tensor( Shape shape, Float32 fill )  # 指定值填充
Tensor( Array<Float32> v, Shape s )  # 数组 + 形状（拷贝）
Tensor( Int32 rows, Int32 cols )     # 2D 零矩阵
```

注意：**无单 Int32 构造**。一维长度 n 用 `Tensor( Shape.vector( n ) )`。

### 3.2 静态工厂

| 签名 | 返回 | 说明 |
|---|---|---|
| `zeros(Shape)` / `ones(Shape)` / `full(Shape, v)` | Tensor | 填充构造 |
| `scalar(Float32)` | Tensor | 标量 |
| `vector(Array<Float32>)` | Tensor | 1D |
| `matrix(Array<Float32>, rows, cols)` | Tensor | 2D |
| `identity(n)` / `eye(n)` | Tensor | n×n 单位阵 |
| `random(Shape)` / `randn(Shape)` | Tensor | 均匀 [0,1) / 正态 N(0,1) |
| `zerosLike(x)` / `onesLike(x)` | Tensor | 同形状 |
| `arange(n)` | Tensor | [0, n) 步长 1 |
| `arange(start, end, step)` | Tensor | 闭开区间；step=0 返回空张量；step 符号决定方向 |
| `linspace(start, end, steps)` | Tensor | 等差含两端；steps=1 返回 [start]；steps<=0 返回空 |
| `where(cond, a, b)` | Tensor | 逐元素选择（cond 非 0 取 a；三者广播） |

## 4. 设备迁移与影子缓冲

设计文档 §5：每个张量可持有"主机影子 + 设备影子"双缓冲，合法状态 S0（同步）/ S1（主机权威，待上传）/ S2（设备权威，待下载）。

### 4.1 迁移 API

| 签名 | 语义 |
|---|---|
| `Tensor to( Device target ) throws` | **唯一跨设备移动入口**。CPU→GPU：预检（kind/available/F32）→ `allocDevRaw` 立即分配 → `uploadInto` 数组指针直传 H2D（OQ-1 零拷贝，无主机复制循环）→ 出口 S2（`_data` 为占位，首次读值 D2H 直写填充）。GPU→CPU：下载进**新张量**，源影子不动。同设备：no-op 返回自身。CPU→CPU：返回自身。非法目标抛 `BackendError`（UnsupportedOp / Unavailable） |
| `Tensor cpu() throws` | `to( Device.cpu() )` |
| `void freeDevice()` | 释放设备侧影子（`freeDevRaw` + 记账回收），状态归 CPU 纯净。**SL 无析构钩子，长驻进程必须显式调用**（OQ-8） |
| `bool onGpu()` | 位置驱动判定：已上设备的张量不受 `Backends.setCudaEnabled` 影响 |
| `bool sameGpuDevice( Tensor other )` | 双侧同 GPU 同卡（设备二元算子前置） |

### 4.2 状态自省（属性）

`device` / `dtype` / `isHostDirty` / `isDevDirty` / `hasDeviceBuffer`。

### 4.3 回落语义（重要）

设备算子的统一模式：

```slang
# ① GPU 快路径：双侧同卡 + F32 → 设备 kernel
if this.onGpu() && this._dtype == EDtype.F32 {
    Tensor g = CudaBackend.unaryGpu( this, op )
    if g != null { ret g }
}
# ② CPU 回落：读迫同步（S2 触发下载）→ 标量循环
this.ensureHostFresh()
...
ret this._tagOut( r )   # 输出挂源设备、主机权威（S1）
```

- 输出设备 = 输入设备（§5.2.5）：GPU 张量走 CPU 合并时结果仍挂 GPU（S1，devBlock=0 惰性上传），值正确。
- 设备分支失败（如 kernel 未就绪）自动回落 CPU，不抛错。

## 5. GPU 算子分派与 PTX op 表

### 5.1 t_unary 单 kernel 多 op 表（`CudaBackend.unaryGpu( t, op )`）

| op | Tensor 方法 | PTX 指令 | 精度 |
|---|---|---|---|
| 0 | `relu()` | 比较语义 | 位级 |
| 1 | `sigmoid()` | ex2 近似换算 | 容差 |
| 2 | `tanh()` | 近似 | 容差 |
| 3 | `exp()` | ex2.approx | 容差 |
| 4 | `reciprocal()` | div.rn | 位级（x=0 边缘除外） |
| 5 | `sqrt()` | sqrt.rn | 位级 |
| 6 | `rsqrt()` | rsqrt.approx | 容差 |
| 7 | `log2()` | lg2.approx | 容差 |
| 8 | `exp2()` | ex2.approx | 容差 |
| 9 | `abs()` | 符号位清零 | 位级 |
| 10 | （neg，PTX 已留） | — | 未接 Tensor.neg |
| 11 | `floor()` | cvt.rm | 位级 |
| 12 | `ceil()` | cvt.rp | 位级 |
| 13 | `round()` | cvt.rni | 位级 |
| 14 | `sign()` | 比较语义 | 位级 |
| 15 | `square()` | mul | 位级 |
| 16 | `silu()` | 组合 | 容差 |
| 17 | `gelu()` | 组合（tanh 近似） | 容差 |

### 5.2 elemwise 二元 op 表（`CudaBackend.elemwise( a, b, op, blen )`）

| op | Tensor 方法 | 广播（blen = b 元素数） |
|---|---|---|
| 0 | `add(b)` | 同形（blen==n）/ 行向量（blen==cols）/ 标量（blen==1） |
| 1 | `sub(b)` | 同上 |
| 2 | `mul(b)` | 同上 |
| 3 | `div(b)` | 同上 |
| 4 | `minimum(b)` | 同上 |
| 5 | `maximum(b)` | 同上 |

### 5.3 其余设备 kernel

| CudaBackend 方法 | Tensor 方法 | 精度策略 |
|---|---|---|
| `matmulGpu(a, b, m, k, n)` | `matmul(b)` | 每线程一输出、p 序标量累加、禁 fma → **与 CPU 位级一致** |
| `sumGpu(a)` | `sum()` | 单线程标量序累加 → 位级一致 |
| `softmaxGpu(a, rows, cols)` | `softmax()` | 每线程一行，max→exp-sum→归一三遍标量序（exp 容差） |
| `scaleGpu(a, k)` | `scale(k)` | 位级 |
| `fillGpu(t, v)` / `scaleInPlaceGpu(t, k)` | 内部 | 填充 / 原地缩放 |

### 5.4 位级 vs 容差验收约定（§6.2）

- **位级**：matmul / sum / scale / sqrt / abs / floor / ceil / round / sign / square / relu / reciprocal(非零) / maximum / minimum —— 测试用 `==` 逐位比较。
- **容差**：exp / sigmoid / tanh / silu / gelu / rsqrt / log2 / exp2 / softmax —— GPU 用 `.approx` 指令，测试用容差（一般 1e-3 ~ 1e-6）。

## 6. 算术 / 矩阵 / 归约 API

### 6.1 算术（广播）

| 签名 | 设备 | 说明 |
|---|---|---|
| `Tensor add(Tensor b)` | CUDA+SIMD+L0 | 广播加 |
| `Tensor sub(Tensor b)` | CUDA+SIMD+L0 | 广播减 |
| `Tensor mul(Tensor b)` | CUDA+SIMD+L0 | 广播乘 |
| `Tensor div(Tensor b)` | CUDA+SIMD+L0 | 广播除 |
| `Tensor scale(Float32 k)` | CUDA+L0 | 标量乘 |
| `Tensor addScalar(Float32 k)` | L0 | 标量加 |
| `Tensor neg()` | L0 | 取负 |
| `void addInPlace(Tensor b)` / `subInPlace` / `mulInPlace` / `scaleInPlace(k)` | L0 | 原地版 |

广播规则：`b` 与本张量同形，或 `b` 为行向量（长度 == cols），或 `b` 为标量（size==1）。

### 6.2 矩阵 / 代数

| 签名 | 设备 | 说明 |
|---|---|---|
| `Tensor matmul(Tensor b)` | CUDA+SIMD+L0 | 2D×2D：`(m,k)×(k,n)→(m,n)`；GPU 前置 `sameGpuDevice` + 双 F32 |
| `Float32 dot(Tensor b)` | L0 | 1D 点积 |
| `Tensor outer(Tensor b)` | L0 | 1D 外积 → (n, m) |

### 6.3 归约

| 签名 | 说明 |
|---|---|
| `Float32 sum()` / `mean()` / `max()` / `min()` | 全量标量归约（sum 有 GPU/SIMD） |
| `int argmax()` / `argmin()` | 全局极值首个扁平下标 |
| `Float32 prod()` / `variance()` / `std()` / `norm()` | 连乘 / 方差 / 标准差 / L2 范数 |
| `bool anyNonZero()` / `allNonZero()` | 判定 |
| `Int32 countNonZero()` | 非零计数 |
| `Tensor sumAlong(axis)` 等 ×5 | 沿轴归约（sum/mean/max/min/argmax），结果降维 |
| `Tensor sumDim(axis)` 等 ×4 | 沿轴归约 keepdim（sum/mean/max/min） |
| `Tensor prodAlong(axis)` / `varAlong(axis)` / `stdAlong(axis)` | 沿轴连乘 / 方差 / 标准差 |
| `Tensor cumsumAlong(axis)` / `cumprodAlong(axis)` | 沿轴前缀和 / 前缀积 |
| `Tensor cumprod()` | 一维前缀积 |

## 7. 逐元素数学 / 激活 / 比较 API

### 7.1 逐元素数学

| 签名 | 设备 | 精度 | 语义 |
|---|---|---|---|
| `Tensor exp()` | CUDA+L0 | 容差 | e^x |
| `Tensor log()` | L0 | — | ln x（safeLog，x<Eps 钳到 Eps） |
| `Tensor sqrt()` | CUDA+L0 | 位级 | √x |
| `Tensor abs()` | CUDA+L0 | 位级 | \|x\| |
| `Tensor reciprocal()` | CUDA+L0 | 位级* | 1/x（CPU x=0→0；GPU x=0→+inf） |
| `Tensor rsqrt()` | CUDA+L0 | 容差 | 1/√x（CPU 加 Eps） |
| `Tensor square()` | CUDA+L0 | 位级 | x² |
| `Tensor exp2()` | CUDA+L0 | 容差 | 2^x |
| `Tensor log2()` | CUDA+L0 | 容差 | log₂x |
| `Tensor floor()` / `ceil()` / `round()` | CUDA+L0 | 位级 | 取整 |
| `Tensor sign()` | CUDA+L0 | 位级 | 符号 |
| `Tensor pow(Float32 p)` | L0 | — | x^p |
| `Tensor clamp(Float32 lo, Float32 hi)` | L0 | — | 裁剪 |
| `Tensor frac()` | L0 | — | x−⌊x⌋ |
| `Tensor expm1()` / `log1p()` | L0 | — | 数值稳定版 |
| `Tensor fmod(Tensor b)` | L0 | — | C fmod 语义（符号随被除数），广播 |
| `Tensor sin()` / `cos()` / `tan()` / `sinh()` / `cosh()` | L0 | — | 三角 / 双曲 |

### 7.2 激活

| 签名 | 设备 | 精度 |
|---|---|---|
| `Tensor relu()` | CUDA+L0 | 位级 |
| `Tensor sigmoid()` | CUDA+L0 | 容差 |
| `Tensor tanh()` | CUDA+L0 | 容差 |
| `Tensor silu()` | CUDA+L0 | 容差 |
| `Tensor gelu()` | CUDA+L0 | 容差（tanh 近似式） |
| `Tensor softplus()` / `leakyRelu(a)` / `elu(a)` / `mish()` | L0 | — |
| `Tensor softmax()` | CUDA+SIMD+L0 | 容差（行 max 平移防溢出） |
| `Tensor logSoftmax()` | L0 | — |

### 7.3 比较

| 签名 | 说明 |
|---|---|
| `Tensor eq(b)` / `ne(b)` / `gt(b)` / `lt(b)` / `ge(b)` / `le(b)` | 逐元素比较 → 1.0/0.0 张量（广播） |
| `Tensor maximum(b)` / `minimum(b)` | 逐元素取大/小（CUDA+L0，广播） |

## 8. 形状操作 API

| 签名 | 说明 |
|---|---|
| `Tensor reshape(Shape)` | 重排形状（不校验元素数的轻量路径；先 `canReshape` 更稳） |
| `Tensor flatten()` | → 1D |
| `Tensor transpose()` | 2D 转置 |
| `Tensor transpose(Array<Int32> axes)` | 通用轴置换 |
| `Tensor slice(Int32 start, Int32 count)` | 1D 切片拷贝 |
| `Tensor row(Int32 r)` / `void setRow(Int32 r, Tensor v)` | 行读写 |
| `Tensor squeeze(Int32 axis)` | 压 1 轴（axis 越界或非 1 返回 clone） |
| `Tensor unsqueeze(Int32 axis)` | 插 1 轴（0..rank） |
| `Tensor flip(Int32 axis)` | 翻转（1D 全翻；2D 仅 axis 0/1） |
| `static Tensor cat(Array<Tensor> ts, Int32 axis)` | 拼接（1D axis0；2D axis0 纵拼 / axis1 横拼） |
| `Tensor clone()` | 深拷贝（同 GPU 走 D2D） |
| `void copyFrom(Tensor src)` | 原地拷入 |
| `void fillValue(Float32 v)` / `zero()` | 填充 |

## 9. TensorMath 标量 API

`TMath.xxx(...)` 全 static。分组速览（详见 TensoraMethods.md §2）：

```slang
# 基础
TMath.exp( x )  TMath.log( x )  TMath.safeLog( x )  TMath.sqrt( x )
TMath.rsqrt( x )   # 1/√(x+Eps)
TMath.pow( x, p )  TMath.abs( x )  TMath.sign( x )
TMath.clamp( v, lo, hi )  TMath.lerp( a, b, t )
TMath.safeDiv( a, b )     # a/(b+Eps)
TMath.isClose( a, b, eps )

# 激活（含成对导数）
TMath.sigmoid( x )     TMath.sigmoidDeriv( s )    # s 为 sigmoid 输出
TMath.tanh( x )        TMath.tanhDeriv( t )
TMath.relu( x )        TMath.reluDeriv( x )
TMath.leakyRelu( x, a )  TMath.elu( x, a )  TMath.softplus( x )
TMath.gelu( x )  TMath.silu( x )  TMath.mish( x )

# 概率
TMath.erf( x )
TMath.normPdf( x, mean, std )  TMath.normCdf( x, mean, std )
TMath.logSumExp( arr )

# 算子补全
TMath.reciprocal( x )  TMath.square( x )  TMath.exp2( x )  TMath.log2( x )
TMath.expm1( x )  TMath.log1p( x )  TMath.fmod( a, b )  TMath.fract( x )

# 反双曲
TMath.asinh( x )  TMath.acosh( x )  TMath.atanh( x )

# 常量
TMath.Pi  TMath.E  TMath.Eps   # 1e-7
```

## 10. Shape / Device / Dtype / Rng API

### 10.1 Shape

```slang
Shape()                        # 标量
Shape( Array<Int32> dims )
Shape( d0 )  Shape( d0, d1 )  Shape( d0, d1, d2 )  Shape( d0, d1, d2, d3 )
Shape.scalar   Shape.vector( n )   Shape.matrix( r, c )
Shape.cube( d0, d1, d2 )      Shape.from( Array<Int32> )
s.rank  s.size  s.isScalar  s.isVector  s.isMatrix
s.dim( axis )     s.setDim( axis, v )
s.strides()       s.offset( Array<Int32> index )
s.unflatten( flatIndex )      s.equals( other )
s.clone()         s.canReshape( Array<Int32> newDims )
Shape.broadcastShape( a, b )  # 静态：广播推导
```

### 10.2 Device

```slang
Device( Int32 kind, Int32 id )
Device.cpu()  Device.gpu( 0 )  Device.npu( 0 )  Device.rocm( 0 )  Device.tpu( 0 )
dev.isCpu()  dev.isGpu()  dev.isNpu()  dev.isRocm()  dev.isTpu()
dev.sameDevice( other )       Device.bothCpu( a, b )
Device.kindName( kind )
dev.alloc( bytes )  dev.free( bytes )   # 全局设备内存记账
# EDeviceKind: CPU / GPU / NPU / ROCM / TPU
```

### 10.3 Dtype

```slang
Dtype.bytesOf( dtype )      # 每元素字节数
Dtype.nameOf( dtype )       # "f32"/"f16"/"bf16"/"i32"/"i64"/"bool"
Dtype.defaultDtype()        # EDtype.F32
# EDtype: F32 / F16 / BF16 / I32 / I64 / BOOL（运算通道当前为 F32）
```

### 10.4 Rng

```slang
Rng r = Rng( 42 )            # 或 Rng.current() 全局实例 / Rng.withSeed( seed )
r.setSeed( s )
r.nextInt32()   r.nextFloat()          # [0,1)
r.uniform( lo, hi )   r.randInt( n )
r.nextNormal()   r.normal( mean, std ) # Box-Muller
r.bernoulli( p )   r.gumbel()
r.permutation( n )   r.shuffle( arr )
```

## 11. Backends 开关 API

```slang
Backends.setCudaEnabled( true )    # GPU 通道总开关（其余：setRocmEnabled / setNpuEnabled / setTpuEnabled）
bool ok = Backends.available( EDeviceKind.GPU )   # 硬件探测（dll + 设备数>0）
Backends.setFallbackToCpu( true )  # 设备不可用时回落 CPU
Backends.isFallbackToCpu()

Backends.setSimdEnabled( true )    # CPU SIMD 总开关
Backends.isSimdEnabled()
Backends.simdIsaName()             # 如 "AVX2"
Backends.simdMatmulOn( m, k, n )   # 阈值判定：形状超过阈值才走 SIMD
Backends.simdSumOn( n )   Backends.simdSoftmaxOn( rows, cols )
Backends.simdConv2dOn( c, outH, outW, k )
Backends.checkPair( devA, devB )   # 二元设备算子前置校验（throws）
```

开关只影响**入口**（`to()` 是否允许上卡）；已上设备的张量按位置驱动继续走 GPU。

## 12. 神经网络层 API

### 12.1 Layer / Module / Sequential

```slang
# Layer 基类（所有层继承）
layer.ensureParams()          # 参数惰性初始化钩子
layer.addParam( Tensor p )    # 登记参数（进入参数表）
layer.train( true )  layer.eval()

# Module 容器
Module m = Module( "net" )
m.add( layer )
m.forward( x )          # 前向（子类实现）
m.backward( grad )      # 反向
m.parameters()          # 聚合全部参数张量
m.gradients()  m.zeroGrad()   m.update( lr )
m.summary()

# Sequential（最常用）
Sequential net = Sequential()
net.append( Dense( 784, 128 ) )
net.append( Act.relu /* 或 Activation kind */ )
Tensor y = net.forward( x )
```

### 12.2 常用层构造

```slang
Dense( inFeatures, outFeatures )               # @Nickname "Linear"
Dense( inFeatures, outFeatures, activationKind )
Conv2D( ... )                                  # @Nickname "Conv2d"
MaxPool2D( ... )   AvgPool2D( ... )            # "MaxPool" / "AvgPool"
BatchNorm( ... )   LayerNorm( ... )
Embedding( ... )   Dropout( p )   Flatten()
MultiHeadAttention( ... )                      # "MHA"
PositionalEncoding( ... )                      # "PosEnc"
RNNCell( ... )  LSTMCell( ... )  GRUCell( ... )
RNN( ... )
TransformerBlock( ... )                        # "TransformerBlock"
Transformer( ... )                             # extends Module
SeqPool( ... )
TransformerClassifier( ... )
```

### 12.3 Activation（@Nickname "Act"）静态族

```slang
Act.relu( x )          Act.reluGrad( x, gradOut )
Act.sigmoid( x )       Act.sigmoidGrad( outV, gradOut )   # outV = 前向输出
Act.tanh( x )          Act.tanhGrad( outV, gradOut )
Act.leakyRelu( x, a )  Act.elu( x, a )
Act.softplus( x )  Act.gelu( x )  Act.silu( x )  Act.mish( x )
Act.softmax( x )       Act.softmaxGrad( outV, gradOut )
Act.logSoftmax( x )
Act.apply( x, kind )         # 按 kind 分派前向
Act.applyGrad( kind, src, gradOut )
```

### 12.4 自动求导（Autograd）

```slang
# Variable（@Nickname "Variable"）：计算图节点 = Tensor + 梯度 + 反向闭包
# Graph：前向记录，backward() 按拓扑序求导（AutogradTest 覆盖）
```

### 12.5 优化器 / 调度器 / 训练

```slang
SGD( lr )   Adam( lr )   AdamW( lr )   RMSProp( lr )   Adagrad( lr )
opt.step( params, grads )   opt.zeroGrad()

StepLR( ... )   ExponentialLR( ... )   CosineLR( ... )
WarmupLR( ... )   ReduceLROnPlateau( ... )
sched.step()   sched.getLR()

# 数据
Dataset( ... )   DataLoader( dataset, batchSize, shuffle )
Normalizer( ... )   # fit / transform / inverse
Vocab( ... )   Tokenizer( ... )

# 训练循环
Trainer( model, lossFn, optimizer )   # fit(...) + History 曲线
History( ... )                        # epoch 损失/指标记录
```

## 13. 常见用法示例集

### 13.1 GPU 对照测试模式（TensorOpsTest 范式）

```slang
Backends.setCudaEnabled( true )
if Backends.available( EDeviceKind.GPU )
{
    Device dev = Device.gpu( 0 )
    Tensor a = Tensor.vector( ... )            # CPU 基准
    Tensor g = a.to( dev )                     # 上卡
    Tensor gr = g.sqrt()                       # 设备算子
    Tensor back = gr.cpu()                     # 下载
    # 位级算子：直接 ==
    bool same = true
    for i = 0, i < back.storage.length, i++
    {
        if back.storage[i] != cpuRef.storage[i] { same = false }
    }
    # 容差算子：|diff| <= tol
}
```

### 13.2 ONNX 权重直读

```slang
Onnx m = Onnx.open( "mnist-8.onnx" )            # 实例（内嵌 Int64 _handle）
if m.ok()                                       # 打开成功判定
Int32 cnt = m.count()
for i = 0, i < cnt, i++
{
    string nm = m.name( i )
    Int64 p = m.dataPtr( i )                    # 零拷贝指针
    Float32 w0 = Mem.hostRead( p, 0 )           # 指针直读
    Tensor w = m.loadTensor( i )                # 或整体物化
}
m.close()                                       # 幂等，关闭后 _handle 置 0
```

### 13.3 拼接 / 形状流

```slang
Tensor a = Tensor.arange( 0, 3, 1 )          # [0,1,2]
Tensor b = Tensor.arange( 3, 6, 1 )          # [3,4,5]
Tensor c = Tensor.cat( [a, b], 0 )           # [0,1,2,3,4,5]
Tensor m = c.reshape( Shape.matrix( 2, 3 ) )
Tensor t = m.transpose()                     # (3,2)
Tensor u = t.unsqueeze( 0 )                  # (1,3,2)
Tensor v = u.squeeze( 0 )                    # (3,2)
```

## 14. 注意事项与已知差异

| # | 事项 |
|---|---|
| 1 | **Eps 防护**：`rsqrt` CPU 路径 = 1/√(x+1e-7)，完美平方有 ~6e-8 偏差（设计内）；GPU `rsqrt.approx` 为容差语义 |
| 2 | **fmod 双语义**：本库 `fmod` = C fmod / torch.fmod（符号随被除数，fmod(-5,2)=-1）；torch.remainder 的 floor-mod 语义用 `a - b*floor(a/b)` 自行组合 |
| 3 | **reciprocal 边缘**：CPU x=0 返回 0（防 VM 除零）；GPU div.rn x=0 → +inf；非零值两路位级一致 |
| 4 | **exp/log 无双射**：GPU exp 走 ex2.approx（容差）；log 仅 CPU（GPU 用 log2 换底） |
| 5 | **SL for 头分号坑**：`for i = 0; i < n; i++` 会令解析器 NRE 崩溃（报"Object reference not set"而非语法错误），必须全逗号 |
| 6 | **保留字**：`get`/`data` 不可作方法名 → `at` 家族 / `storage` |
| 7 | **无单 Int32 构造**：`Tensor( n )` 不存在，1D 用 `Tensor( Shape.vector( n ) )` |
| 8 | **freeDevice 必须显式**：SL 无析构钩子，GPU 张量长驻进程需手动 `t.freeDevice()` |
| 9 | **进程锁**：运行中的 slang 进程会锁 `out\export\Tensora`，重编译前先结束测试进程（LSP 的 `slang.exe lsp --stdio` 无害） |
| 10 | **jsonc 槽位**：测试工程新增类必须追加到 ProjectTest.jsonc struct **末尾**（VM 槽位坑） |
| 11 | **编码约定**：Tensora 工程源文件 UTF-8 BOM；测试工程 .sl/.jsonc 无 BOM + LF；ProjectTest.sp 无 BOM + CRLF |
| 12 | **GPU 张量读值**：`at`/`storage` 自动触发下载同步（ensureHostFresh），性能敏感路径避免混用 |
