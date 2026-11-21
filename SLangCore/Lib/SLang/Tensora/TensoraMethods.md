# Tensora 方法说明

> 仿 PyTorch 的跨平台跨硬件算子框架（SL 语言实现）。
> 本文档覆盖 Tensora 全部模块的公开方法，逐条中文说明。
> API 签名 / 设备支持 / 示例代码详见同目录 [TensoraApi.md](TensoraApi.md)；
> 平台中间层详见 [Cvm/CvmApi.md](Cvm/CvmApi.md)，后端详见 [Backends/BackendsApi.md](Backends/BackendsApi.md)。

## 目录结构与模块地图

```
Tensora/
├── Tensor.sl            # Tensor 张量类（130+ 方法，GPU 分支优先 → CPU L0 回落）
├── Math.sl              # TensorMath（@Nickname "TMath"）标量数学
├── Shape.sl             # Shape 形状类
├── Device.sl            # Device 设备类 + EDeviceKind
├── Dtype.sl             # Dtype + EDtype 类型枚举
├── Random.sl            # Rng（@Nickname "Rng"）随机数
├── Ops.sl               # Ops 算子注册表
├── Layer.sl             # Layer 神经网络层基类
├── Module.sl            # Module / Sequential 容器
├── Activation.sl        # Act 激活函数集（前向 + 反向）
├── Dense.sl             # Linear 全连接层
├── Conv.sl              # Conv2d 卷积层
├── Pooling.sl           # MaxPool / AvgPool 池化层
├── Normalization.sl     # BatchNorm / LayerNorm
├── Embedding.sl         # Embedding 嵌入层
├── Dropout.sl           # Dropout
├── Flatten.sl           # Flatten
├── Attention.sl         # Attention / MHA / PosEnc
├── Recurrent.sl         # RNNCell / LSTMCell / GRUCell / RNN
├── Transformer.sl       # TransformerBlock / Transformer
├── TransformerModel.sl  # SeqPool / TransformerClassifier
├── Autograd.sl          # Variable / Graph 自动求导
├── Loss.sl              # Loss 损失函数
├── Metrics.sl           # Metrics 评估指标
├── Optimizer.sl         # Optimizer / SGD / Adam / AdamW / RMSProp / Adagrad
├── Scheduler.sl         # LRScheduler 族（Step/Exp/Cosine/Warmup/Plateau）
├── Dataset.sl           # Batch / Dataset / DataLoader / Normalizer
├── Tokenizer.sl         # Vocab / Tokenizer
├── Trainer.sl           # History / Trainer 训练循环
├── Backends/
│   ├── BackendRegistry.sl  # Backends 后端注册/开关/SIMD 阈值
│   └── CudaBackend.sl      # CudaBackend：PTX JIT kernel 表 + 设备算子
└── Cvm/
    ├── Cvm.sl         # 平台聚合门面（委托 Cpu_x64 等）
    ├── Cpu_x64.sl     # x64 CPU 平台 FFI（SIMD 算子 + 内存）
    ├── Cpu_arm64.sl   # arm64 CPU 平台 FFI（占位）
    ├── Tpu.sl         # TPU 平台 FFI（占位）
    ├── Npu.sl         # NPU 平台 FFI（占位）
    ├── Cuda.sl        # CUDA 原生 API 类族（Device/Buffer/Stream/Event/Kernel）
    ├── Mem.sl         # Mem 跨平台内存管理（CPU↔GPU 传输/查看/手动释放）
    └── Onnx.sl        # Onnx 模型读取（C 底层解析 + 指针直读 + loadTensor）
```

## 设备支持标注约定

| 标注 | 含义 |
|---|---|
| L0 | Tensor.sl 内基础 CPU 实现（标量循环，全程可用） |
| SIMD | Cpu_x64 AVX/FMA 加速（`Backends.simd*On` 阈值门控自动派发） |
| CUDA | GPU PTX JIT kernel（`CudaBackend`，张量已 `.to(gpu)` 且 F32 时生效） |
| 位级 | GPU 与 CPU 结果逐位一致（同算法结构 / 精确指令） |
| 容差 | GPU 用 approx 指令（如 `__expf`/`rsqrt.approx`），需容差对照 |

---

## 1. Tensor 类（Tensor.sl）

### 1.1 构造器

| 构造器 | 说明 |
|---|---|
| `Tensor()` | 标量 0（shape 为 scalar） |
| `Tensor(Shape)` | 按形状分配，零填充 |
| `Tensor(Shape, Float32)` | 按形状分配，填充指定值 |
| `Tensor(Array<Float32>, Shape)` | 从一维数组 + 形状构造（拷贝数据） |
| `Tensor(Int32 rows, Int32 cols)` | 二维矩阵构造，零填充 |

### 1.2 属性

| 属性 | 说明 |
|---|---|
| `shape` | 形状（Shape 对象） |
| `rank` | 维度数 |
| `size` | 元素总数 |
| `rows` / `cols` | 首维 / 末维尺寸 |
| `storage` | 底层一维 Float32 数组（读取前触发设备→主机同步） |
| `device` | 所在设备（未上设备时返回 CPU） |
| `dtype` | 数据类型（EDtype，当前运算通道为 F32） |
| `isHostDirty` / `isDevDirty` | 影子缓冲状态机自省（S0/S1/S2） |
| `hasDeviceBuffer` | 是否持有设备侧缓冲 |

### 1.3 静态构造工厂

| 方法 | 说明 |
|---|---|
| `zeros(Shape)` / `ones(Shape)` / `full(Shape, v)` | 零 / 一 / 指定值填充 |
| `scalar(Float32)` | 标量张量 |
| `vector(Array<Float32>)` | 一维向量 |
| `matrix(Array<Float32>, rows, cols)` | 二维矩阵 |
| `identity(n)` / `eye(n)` | 单位矩阵 |
| `random(Shape)` / `randn(Shape)` | 均匀 / 正态随机（走 Rng.current()） |
| `zerosLike(x)` / `onesLike(x)` | 按同形状构造 |
| `arange(n)` | 0..n-1 步长 1 |
| `arange(start, end, step)` | 闭开区间步进序列（step 为 0 时返回空） |
| `linspace(start, end, steps)` | 等差序列（含两端，steps 为 1 时返回 [start]） |

### 1.4 设备与双缓冲（§5 影子缓冲状态机）

| 方法 | 设备 | 说明 |
|---|---|---|
| `to(Device)` | — | 唯一跨设备移动入口：CPU→GPU 立即分配+零拷贝上传（出口 S2）；GPU→CPU 下载进新张量（源不动）；同设备 no-op 返回自身；非 GPU kind / 未启用 / 非 F32 抛异常 |
| `cpu()` | — | `to(Device.cpu())` 快捷方式 |
| `freeDevice()` | — | 释放设备侧影子缓冲；CPU 张量空操作。SL 无析构钩子，长期进程需显式调用 |
| `onGpu()` | — | 是否驻留 GPU（位置驱动，已上设备的张量不受 Backends 开关影响） |
| `sameGpuDevice(Tensor)` | — | 双侧同 GPU 同卡驻留（设备算子前置判定） |
| `ensureHostFresh()` | 内部 | 读迫同步钩子：S2 时触发下载协议；CPU 张量空操作 |
| `_tagOut(Tensor)` | 内部 | 设备算子的 CPU 合并回落出口：结果挂源设备、主机权威（S1） |

### 1.5 索引访问（at 家族；`get`/`data` 为保留字故有此命名）

| 方法 | 说明 |
|---|---|
| `offset(Array<Int32>)` | 多维索引 → 扁平偏移 |
| `at(flatIndex)` / `setAt(flatIndex, v)` | 扁平索引读写 |
| `at(Array<Int32>)` / `setAt(Array<Int32>, v)` | 多维索引读写 |
| `at(i, j)` / `at(i, j, k)` / `at(i, j, k, l)` 及对应 `setAt` | 2/3/4 维坐标读写（按 strides 计算） |
| `pick(Array<Int32>)` | 广播取值：把目标形状索引映射回本张量（大小为 1 的维取 0） |

### 1.6 拷贝 / 填充

| 方法 | 设备 | 说明 |
|---|---|---|
| `clone()` | CUDA | 深拷贝；同设备走 D2D（不过主机），出口 S2 |
| `copyFrom(Tensor)` | L0 | 原地拷入源数据（供优化器 / 反向传播原地更新） |
| `fillValue(Float32)` | L0 | 全量填充 |
| `zero()` | L0 | 清零 |
| `sameShape(Tensor)` | — | 形状比较 |

### 1.7 形状操作

| 方法 | 说明 |
|---|---|
| `reshape(Shape)` | 变形（数据不动，仅改 shape/strides） |
| `flatten()` | 展平为一维 |
| `transpose()` | 二维转置 |
| `transpose(Array<Int32> axes)` | 按轴序重排（通用置换） |
| `slice(start, count)` | 一维切片（取前 count 个） |
| `row(r)` / `setRow(r, v)` | 取 / 写某一行（返回一维视图拷贝） |
| `squeeze(axis)` | 压掉大小为 1 的轴 |
| `unsqueeze(axis)` | 插入大小为 1 的轴 |
| `flip(axis)` | 沿轴翻转（1D 全翻；2D axis 0/1） |
| `cat(Array<Tensor>, axis)` 静态 | 沿轴拼接（1D axis0；2D axis 0/1） |

### 1.8 算术（支持广播：同形 / 行向量 / 标量）

| 方法 | 设备 | 说明 |
|---|---|---|
| `add(b)` / `sub(b)` / `mul(b)` / `div(b)` | CUDA+SIMD+L0 | 广播四则（GPU elemwise op 0/1/2/3） |
| `scale(k)` | CUDA+L0 | 乘标量（GPU scaleGpu） |
| `addScalar(k)` | L0 | 加标量 |
| `neg()` | L0 | 取负 |
| `addInPlace(b)` / `subInPlace(b)` / `mulInPlace(b)` / `scaleInPlace(k)` | L0 | 原地版本（优化器 / 反向传播用） |

### 1.9 矩阵 / 代数

| 方法 | 设备 | 说明 |
|---|---|---|
| `matmul(b)` | CUDA+SIMD+L0 | 2D×2D 矩阵乘（GPU：每线程一输出、p 序标量累加禁 fma → 与 L0 逐位一致） |
| `dot(b)` | L0 | 一维点积（返回标量） |
| `outer(b)` | L0 | 一维外积（返回二维） |

### 1.10 归约

| 方法 | 设备 | 说明 |
|---|---|---|
| `sum()` | CUDA+SIMD+L0 | 全量和（GPU 单线程标量序累加 → 逐位一致） |
| `mean()` / `max()` / `min()` | L0 | 均值 / 最大 / 最小 |
| `argmax()` / `argmin()` | L0 | 最大 / 最小值首个扁平下标 |
| `sumAlong(axis)` / `meanAlong(axis)` / `maxAlong(axis)` / `minAlong(axis)` / `argmaxAlong(axis)` | L0 | 沿轴归约（结果降维） |
| `sumDim(axis)` / `meanDim(axis)` / `maxDim(axis)` / `minDim(axis)` | L0 | 沿轴归约 keepdim 版本（结果保留长度 1 的轴） |
| `prodAlong(axis)` | L0 | 沿轴连乘 |
| `varAlong(axis)` / `stdAlong(axis)` | L0 | 沿轴方差 / 标准差 |
| `prod()` / `variance()` / `std()` / `norm()` | L0 | 全量连乘 / 方差 / 标准差 / L2 范数 |
| `anyNonZero()` / `allNonZero()` | L0 | 存在非零 / 全非零判定 |
| `cumsumAlong(axis)` | L0 | 沿轴前缀和 |
| `cumprod()` / `cumprodAlong(axis)` | L0 | 前缀积（一维 / 沿轴） |
| `countNonZero()` | L0 | 非零元素计数 |
| `reduceAxis(axis, mode, keepdim)` | 内部 | 通用沿轴归约内核（各 *Along/*Dim 复用） |

### 1.11 逐元素数学（unary）

| 方法 | 设备 | 精度 | 说明 |
|---|---|---|---|
| `exp()` | CUDA+L0 | 容差 | e^x（GPU `ex2.approx` 换算） |
| `sqrt()` | CUDA+L0 | 位级 | √x（GPU `sqrt.rn`） |
| `abs()` | CUDA+L0 | 位级 | 绝对值（符号位清零） |
| `reciprocal()` | CUDA+L0 | 位级* | 1/x（CPU：x=0 返回 0 防炸；GPU `div.rn`：x=0 → +inf；非零值两路逐位一致） |
| `rsqrt()` | CUDA+L0 | 容差 | 1/√x（GPU `rsqrt.approx`；CPU 加 Eps 防完美平方开方余差） |
| `square()` | CUDA+L0 | 位级 | x² |
| `exp2()` | CUDA+L0 | 容差 | 2^x |
| `log2()` | CUDA+L0 | 容差 | log₂x（GPU `lg2.approx`） |
| `floor()` / `ceil()` / `round()` | CUDA+L0 | 位级 | 下取整 / 上取整 / 四舍五入（GPU `cvt.rm/.rp/.rni`） |
| `sign()` | CUDA+L0 | 位级 | 符号（-1/0/1） |
| `log()` | L0 | — | 自然对数（safeLog 防零） |
| `pow(p)` | L0 | — | 幂 |
| `clamp(lo, hi)` | L0 | — | 区间裁剪 |
| `frac()` | L0 | — | 小数部分 x−⌊x⌋ |
| `expm1()` | L0 | — | e^x−1（小 x 数值稳定） |
| `log1p()` | L0 | — | ln(1+x)（小 x 数值稳定） |
| `fmod(b)` | L0 | — | 浮点取余（C fmod / torch.fmod 语义：符号随被除数；支持广播） |
| `sin()` / `cos()` / `tan()` | L0 | — | 三角函数 |
| `sinh()` / `cosh()` | L0 | — | 双曲函数 |

### 1.12 激活

| 方法 | 设备 | 精度 | 说明 |
|---|---|---|---|
| `relu()` | CUDA+L0 | 位级 | max(0, x) |
| `sigmoid()` | CUDA+L0 | 容差 | 1/(1+e^−x) |
| `tanh()` | CUDA+L0 | 容差 | 双曲正切 |
| `silu()` | CUDA+L0 | 容差 | x·sigmoid(x)（Swish） |
| `gelu()` | CUDA+L0 | 容差 | GELU tanh 近似 |
| `softplus()` | L0 | — | log(1+e^x) |
| `leakyRelu(alpha)` | L0 | — | 泄漏 ReLU |
| `elu(alpha)` | L0 | — | ELU |
| `mish()` | L0 | — | x·tanh(softplus(x)) |
| `softmax()` | CUDA+SIMD+L0 | 容差 | 行 softmax（max 平移防溢出；GPU 每线程一行三遍标量序） |
| `logSoftmax()` | L0 | — | log-softmax |

### 1.13 比较 / 选择

| 方法 | 设备 | 说明 |
|---|---|---|
| `eq(b)` / `ne(b)` / `gt(b)` / `lt(b)` / `ge(b)` / `le(b)` | L0 | 逐元素比较（返回 1.0/0.0 张量，支持广播） |
| `maximum(b)` / `minimum(b)` | CUDA+L0 | 逐元素取大 / 取小（GPU elemwise op 5/4，支持广播） |
| `where(cond, a, b)` 静态 | L0 | 条件选择（cond 非 0 取 a 否则 b，广播） |

---

## 2. TensorMath（@Nickname "TMath"，Math.sl）

标量数学库（Mathf 之上的 AI 补充）。所有方法 static，逐元素运算由 Tensor 调用。

| 分组 | 方法 | 说明 |
|---|---|---|
| 常量 | `Pi` / `E` / `Eps` | 圆周率 / 自然常数 / 数值稳定极小值 1e-7 |
| 基础 | `exp` / `log` / `safeLog` / `sqrt` / `rsqrt` / `pow` / `abs` / `sign` | 标量版基础数学（safeLog 钳 Eps 防 log(0)） |
| 基础 | `clamp(v, lo, hi)` / `lerp(a, b, t)` / `safeDiv(a, b)` / `isClose(a, b, eps)` | 裁剪 / 线性插值 / 防零除 / 近似相等 |
| 激活 | `sigmoid` / `sigmoidDeriv(s)` / `tanh` / `tanhDeriv(t)` / `relu` / `reluDeriv(x)` | 前向 + 由输出值直接求导的反向 |
| 激活 | `leakyRelu(x, a)` / `elu(x, a)` / `softplus` / `gelu` / `silu` / `mish` | 激活函数标量版 |
| 概率 | `erf` | 误差函数（Abramowitz-Stegun 7.1.26 近似） |
| 概率 | `normPdf(x, μ, σ)` / `normCdf(x, μ, σ)` / `logSumExp(v)` | 正态密度 / 正态 CDF（erf 实现）/ 稳定 log-sum-exp |
| 算子补全 | `reciprocal` / `square` / `exp2` / `log2` / `expm1` / `log1p` / `fmod` / `fract` | PyTorch 基础逐元素标量版（fmod 为真 C 语义） |
| 反双曲 | `asinh` / `acosh` / `atanh` | log 表达式实现（边界裁剪防 log(0)） |

---

## 3. Shape（Shape.sl）

| 方法 | 说明 |
|---|---|
| `Shape()` / `Shape(Array<Int32>)` / `Shape(d0)` / `Shape(d0, d1)` / `Shape(d0, d1, d2)` / `Shape(d0..d3)` | 0~4 维构造 |
| `rank` / `size` / `isScalar` / `isVector` / `isMatrix` | 属性：维度数 / 元素数 / 形态判定 |
| `dim(axis)` / `setDim(axis, v)` | 读 / 写某一维 |
| `strides()` | 行主序步长数组 |
| `offset(Array<Int32>)` | 多维索引 → 扁平偏移 |
| `unflatten(flatIndex)` | 扁平偏移 → 多维索引 |
| `equals(Shape)` | 形状相等 |
| `clone()` | 深拷贝 |
| `canReshape(Array<Int32>)` | 元素数一致性检查 |
| `broadcastShape(a, b)` 静态 | 广播形状推导（右对齐，1 可扩展） |
| `scalar` / `vector(n)` / `matrix(r, c)` / `cube(d0, d1, d2)` / `from(Array<Int32>)` 静态工厂 | 快捷构造 |

## 4. Device（Device.sl）与 EDeviceKind

| 方法 | 说明 |
|---|---|
| `Device(kind, id)` | 按类型 + 卡号构造 |
| `isCpu()` / `isGpu()` / `isNpu()` / `isRocm()` / `isTpu()` | 类型判定 |
| `sameDevice(other)` | 同类型同卡 |
| `bothCpu(a, b)` 静态 | 双方均为 CPU |
| `cpu()` / `gpu(id)` / `npu(id)` / `rocm(id)` / `tpu(id)` 静态工厂 | 常用设备单例式构造 |
| `kindName(kind)` 静态 | 类型枚举 → 名称字符串 |
| `alloc(bytes)` / `free(bytes)` | 设备内存记账（挂到全局预算） |

`EDeviceKind`：`CPU` / `GPU` / `NPU` / `ROCM` / `TPU`。

## 5. Dtype（Dtype.sl）与 EDtype

| 方法 | 说明 |
|---|---|
| `bytesOf(dtype)` | 每元素字节数 |
| `nameOf(dtype)` | 类型名（"f32"/"f16"/"bf16"/"i32"/"i64"/"bool"） |
| `defaultDtype()` | 默认类型（F32） |

`EDtype`：`F32` / `F16` / `BF16` / `I32` / `I64` / `BOOL`。当前运算通道为 F32。

## 6. Rng（@Nickname "Rng"，Random.sl）

| 方法 | 说明 |
|---|---|
| `Rng()` / `Rng(seed)` | 默认种子 / 指定种子构造 |
| `setSeed(seed)` | 重置种子 |
| `nextInt32()` / `nextFloat()` | 32 位整数 / [0,1) 均匀浮点 |
| `uniform(lo, hi)` | 区间均匀采样 |
| `randInt(n)` | [0, n) 随机整数 |
| `nextNormal()` / `normal(μ, σ)` | Box-Muller 正态采样 |
| `bernoulli(p)` | 伯努利试验 |
| `gumbel()` | Gumbel 噪声（Gumbel-Softmax / 采样用） |
| `permutation(n)` / `shuffle(arr)` | 随机排列 / 原地洗牌 |
| `current()` / `withSeed(seed)` 静态 | 全局默认实例 / 带种子临时实例 |

---

## 7. Backends（Backends/BackendRegistry.sl）

后端注册与开关、SIMD 阈值门控。详见 [Backends/BackendsApi.md](Backends/BackendsApi.md)。

| 分组 | 方法 | 说明 |
|---|---|---|
| 设备开关 | `setCudaEnabled` / `setRocmEnabled` / `setNpuEnabled` / `setTpuEnabled` | 各硬件通道总开关（只门 `to()` 入口，不影响已上设备的张量） |
| 回落策略 | `setFallbackToCpu` / `isFallbackToCpu` | 设备不可用时是否回落 CPU |
| 可用性 | `available(kind)` | 硬件探测（CUDA 走 dll 探测 + 设备数 > 0） |
| 配对检查 | `checkPair(a, b)` | 双设备算子前置校验（不匹配抛异常） |
| SIMD 开关 | `setSimdEnabled` / `isSimdEnabled` / `simdIsaName` | SIMD 总开关 / 当前 ISA 名（如 AVX2） |
| SIMD 阈值 | `simdMatmulOn(m,k,n)` / `simdSumOn(n)` / `simdSoftmaxOn(r,c)` / `simdConv2dOn(c,oh,ow,k)` | 形状阈值判定：超过阈值才走 SIMD |
| SIMD 执行 | `simdMatmulArray` / `simdSumArray` / `simdSoftmaxArray` / `simdConv2dArray` | 直接调 Cpu_x64 的裸数组 SIMD 算子（kernel 装配层用） |

## 8. CudaBackend（Backends/CudaBackend.sl）

CUDA 后端：PTX JIT kernel 表 + 设备算子 + 设备内存。详见 [Backends/BackendsApi.md](Backends/BackendsApi.md)。

| 分组 | 方法 | 说明 |
|---|---|---|
| 探测 | `cudaOk()` / `kernelsReady()` | CUDA 可用性 / kernel 表就绪 |
| 设备算子 | `elemwise(a, b, op, blen)` / `scaleGpu` / `unaryGpu(a, op)` / `sumGpu` / `matmulGpu` / `softmaxGpu` / `fillGpu` / `scaleInPlaceGpu` | Tensor 设备分支的落点（op 表见 TensoraApi.md §5） |
| 传输 | `uploadFlow(t)` / `downloadFlow(t)` / `uploadInto` | S1 惰性上传 / S2 下载协议 / 数组直传 H2D（OQ-1 零拷贝） |
| 设备内存 | `allocDevRaw` / `freeDevRaw` / `arrayDataPtr` | 原始设备分配 / 释放 / SL 数组首地址 |
| kernel 装配 | `jit(ptx, entry)` / `launchFlat` / `launch2D` / `deviceTensor` / `stageOut` | PTX JIT 编译 / 一维二维发射 / 设备张量包装 / 出口置 S2 |
| PTX 生成 | `ptxUnary` / `ptxSum` / `ptxMmul` / `ptxSmx` / `ptxFill` / `ptxScale` / `ptxBin` | 内置 PTX kernel 源码表（编译期拼装） |

## 9. Cvm 平台中间层（Cvm/）

跨平台 FFI 聚合层，底层为 `sl_tensora_lib.dll`（cvm_sl_tensora_lib 工程）。详见 [Cvm/CvmApi.md](Cvm/CvmApi.md)。

### 9.1 Cvm（聚合门面）

静态委托 `Cpu_x64` 同名方法：`initialize` / `isaId` / `isaName` / `forceIsa` / `hasFma` / `version` / `matmul` / `sum` / `softmax` / `conv2d` / `uploadF32` / `pinF32` / `downloadF32` / `freeBlock`。

### 9.2 Cpu_x64（x64 平台 FFI）

| 分组 | 方法 | 说明 |
|---|---|---|
| 初始化 | `initialize()` / `version()` | C 库握手 / 版本号 |
| ISA | `isaId()` / `isaName()` / `forceIsa(isa)` / `hasFma()` | 运行时 CPU 特性探测（AVX2/AVX512 等）/ 强制指定 / FMA 支持 |
| 算子 | `matmul(aBlk, bBlk, oBlk, m, k, n)` / `sum(xBlk, oBlk, n)` / `softmax(xBlk, oBlk, rows, cols)` / `conv2d(...)` | 裸指针 SIMD 算子（kernel 装配层用） |
| 内存 | `uploadF32(values)` / `pinF32(values)` / `downloadF32(addr, count)` / `freeBlock(addr)` | 主机侧固定内存：上传 / 锁页 / 下载 / 释放 |
| 原始绑定 | `libInit` / `libIsaId` / `libMatmul` / `libSum` / `libSoftmax` / `libConv2D` / `libLastError` / `libErrorString` 等 | C 导出函数 1:1 绑定（直调层，业务勿用） |

### 9.3 Cpu_arm64 / Tpu / Npu（占位）

平台接口已拆分，等待对应硬件后端实现。

### 9.4 Cuda（Cvm/Cuda.sl，CUDA 原生 API 类族）

| 类 | 说明 |
|---|---|
| `Cuda` | CUDA Runtime 直通：设备枚举 / 内存分配拷贝 / 错误处理 |
| `CudaDevice` | 设备属性封装 |
| `CudaBuffer` | 设备缓冲（分配 / 释放 / 拷贝） |
| `CudaStream` / `CudaEvent` | 流与事件（异步执行 / 计时同步） |
| `CudaKernelArgs` / `CudaKernel` | kernel 参数打包 / 模块加载发射 |

### 9.5 Mem（Cvm/Mem.sl，跨平台内存管理）

CPU↔GPU（及未来其它硬件）数据传输、查看、手动管理。

| 方法 | 说明 |
|---|---|
| `libMemcpy(dst, src, bytes)` | C memcpy 原始绑定 |
| `pin(values)` | 数组锁页（返回主机指针，GPU DMA 用） |
| `copyHost(dst, src, bytes)` | 主机内存拷贝 |
| `copyArray(dst, src)` | SL 数组间拷贝 |
| `copyToDevice(values, dev)` | 拷贝式上设备（原数组保留） |
| `copyToHost(devPtr, dst, dev)` | 设备 → 主机数组拷贝 |
| `copyDevice(dstPtr, srcPtr, bytes, dev)` | 设备内 D2D 拷贝 |
| `moveFromDevice(t)` | 张量数据移动式下载（源失效语义） |
| `moveToDevice(values, dev)` | 移动式上设备（源数组让渡） |
| `free(devPtr, bytes, dev)` / `freeHost(addr)` | 设备 / 主机内存释放 |
| `hostRead(ptr, i)` / `hostReadI(ptr, byteOffset)` | 主机指针直读 Float32 / Int32（ONNX 权重抽查用） |
| `inspect(t, tag)` / `inspect(t, tag, head)` | 张量内容打印（全量 / 前 head 个，自动同步设备） |
| `inspectDevice(devPtr, count, dev, tag)` | 设备指针内容打印（内部下载抽样） |

### 9.6 Onnx（Cvm/Onnx.sl，模型读取）

ONNX C 底层解析（sl_onnx.c），上层只拿数据指针。

| 方法 | 说明 |
|---|---|
| `open(path)` / `close(model)` | 打开 / 关闭模型（返回句柄） |
| `count(model)` | initializer（权重）个数 |
| `name(m, i)` / `rank(m, i)` / `dim(m, i, axis)` / `elemCount(m, i)` | 权重名 / 维度数 / 各维尺寸 / 元素数 |
| `dataType(m, i)` | ONNX 数据类型（1 = FLOAT） |
| `dataPtr(m, i)` | 权重数据主机指针（零拷贝直读入口） |
| `lastError()` / `errorString()` | 错误码 / 错误信息 |
| `loadTensor(m, i)` | 权重物化为 Tensor（pin + 一次 memcpy） |
| `makeTestModel(path)` | 生成最小测试模型（自检用） |
| `libOpen` / `libClose` / `libCount` / `libName` / `libRank` / `libDim` / `libElemCount` / `libDataType` / `libDataPtr` / `libCopyF32` / `libLastError` / `libErrorString` / `libMakeTestModel` | C 导出 1:1 原始绑定（直调层） |

---

## 10. 神经网络层（根目录平铺）

### 10.1 基类与容器

| 类 | 关键方法 | 说明 |
|---|---|---|
| `Layer`（@Nickname "Layer"） | `_init_()` / `_init_(name)` / `ensureParams()` / `addParam(Tensor)` / `train(mode)` / `eval()` | 层基类：参数表管理 + 训练/推理模式；子类实现 `forward` / `backward` |
| `Module`（@Nickname "Module"） | `add(Layer)` / `layers()` / `forward(x)` / `backward(grad)` / `parameters()` / `gradients()` / `zeroGrad()` / `update(lr)` / `train(mode)` / `eval()` / `summary()` | 多层容器：前向编排 + 梯度聚合 + 参数更新 |
| `Sequential`（@Nickname "Seq"） | `append(Layer)` + Module 全部 | 顺序堆叠模型（最常用） |

### 10.2 核心层

| 类 | 构造 | 说明 |
|---|---|---|
| `Dense`（@Nickname "Linear"） | `(inFeatures, outFeatures)` / `(in, out, activationKind)` | 全连接层（可带激活） |
| `Conv2D`（@Nickname "Conv2d"） | 卷积层 | 2D 卷积（SIMD conv2d 派发） |
| `MaxPool2D`（"MaxPool"）/ `AvgPool2D`（"AvgPool"） | 池化层 | 最大 / 平均池化 |
| `BatchNorm`（"BatchNorm"）/ `LayerNorm`（"LayerNorm"） | 归一化层 | 批归一化 / 层归一化 |
| `Embedding`（"Embedding"） | 嵌入层 | 稀疏索引 → 稠密向量 |
| `Dropout`（"Dropout"） | 丢弃层 | 训练时随机置零（eval 关闭） |
| `Flatten`（"Flatten"） | 展平层 | 多维 → 一维 |

### 10.3 激活函数集（Activation，@Nickname "Act"）

全部 static，前向 + 反向成对：

| 方法 | 说明 |
|---|---|
| `relu(x)` / `reluGrad(x, gradOut)` | ReLU 及其反向 |
| `leakyRelu(x, a)` / `elu(x, a)` | 泄漏 ReLU / ELU |
| `sigmoid(x)` / `sigmoidGrad(outV, gradOut)` | sigmoid（反向由输出值直接计算） |
| `tanh(x)` / `tanhGrad(outV, gradOut)` | tanh（同上） |
| `softplus(x)` / `gelu(x)` / `silu(x)` / `mish(x)` | 平滑激活 |
| `softmax(x)` / `softmaxGrad(outV, gradOut)` / `logSoftmax(x)` | softmax 家族 |
| `apply(x, kind)` / `applyGrad(kind, src, gradOut)` | 按 kind 枚举分派（层内使用） |

### 10.4 注意力与序列

| 类 | 说明 |
|---|---|
| `Attention`（"Attention"） | 缩放点积注意力（静态工具） |
| `MultiHeadAttention`（"MHA"） | 多头注意力层（extends Layer） |
| `PositionalEncoding`（"PosEnc"） | 正弦位置编码 |
| `RNNCell` / `LSTMCell` / `GRUCell` | 循环单元 |
| `RNN` | 按 Cell 展开的循环网络 |
| `TransformerBlock`（"TransformerBlock"） | 注意力 + FFN 残差块 |
| `Transformer`（"Transformer"） | 编码器式 Transformer（extends Module） |
| `SeqPool`（"SeqPool"） | 序列池化 |
| `TransformerClassifier`（"TransformerClassifier"） | Transformer 分类头模型 |

### 10.5 自动求导（Autograd.sl）

| 类 | 说明 |
|---|---|
| `Variable`（@Nickname "Variable"） | 计算图节点：包装 Tensor + 梯度 + 反向函数 |
| `Graph` | 计算图：前向记录 + 反向拓扑序求导 |

### 10.6 损失与指标

| 类 | 说明 |
|---|---|
| `Loss`（"Loss"） | 损失函数集（MSE / 交叉熵等） |
| `Metrics`（"Metrics"） | 评估指标（准确率等） |

### 10.7 优化器（Optimizer.sl）

| 类 | 说明 |
|---|---|
| `Optimizer`（基类） | step / zero_grad 协议 |
| `SGD` / `Adam` / `AdamW` / `RMSProp` / `Adagrad` | 常用优化器族（AdamW extends Adam） |

### 10.8 学习率调度（Scheduler.sl）

`LRScheduler` 基类 + `StepLR`（阶梯）/ `ExponentialLR`（指数）/ `CosineLR`（余弦退火）/ `WarmupLR`（预热）/ `ReduceLROnPlateau`（平台检测降 lr）。

### 10.9 数据与训练

| 类 | 说明 |
|---|---|
| `Batch`（"Batch"） | 一批样本（x / y 张量对） |
| `Dataset`（"Dataset"） | 样本集抽象 |
| `DataLoader`（"DataLoader"） | 分批 + 打乱迭代 |
| `Normalizer`（"Normalizer"） | 标准化 / 反标准化 |
| `Vocab`（"Vocab"）/ `Tokenizer`（"Tokenizer"） | 词表与分词 |
| `History`（"History"）/ `Trainer`（"Trainer"） | 训练曲线记录 / 训练循环（fit + 验证 + 早停） |

---

## 11. Ops（Ops.sl，@Nickname "Ops"）

算子注册表：算子名 / kind 枚举 / 派发表（L0/SIMD/CUDA 路由元数据）。层与自动求导通过它查算子。

---

## 相关文档

- [TensoraApi.md](TensoraApi.md) —— Tensor 核心与 nn 层 API 参考（签名 / 设备支持 / 示例 / PTX op 表）
- [Cvm/CvmApi.md](Cvm/CvmApi.md) —— 平台中间层 API（Mem / Onnx / Cpu_x64 / Cuda 类族）
- [Backends/BackendsApi.md](Backends/BackendsApi.md) —— 后端注册与 CUDA 后端 API
- [TensoraBackend.md](TensoraBackend.md) —— 架构设计文档（§5 双缓冲状态机 / §6 算子分派 / §9 阶段规划）
- [Tensora.md](Tensora.md) —— 工程入口约定（_main_/_test_ 等）
