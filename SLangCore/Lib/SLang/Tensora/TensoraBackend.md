# Tensora 跨平台跨硬件算子计算架构设计（TensoraBackend）

版本：v3（2026-11-20；v2 新增 §5 内存与显存管理协议；v3 新增 §6.1 CPU 原生 SIMD 加速层与分级验收）
状态：设计稿，供评审；本文档为 Phase 0 交付物，后续实现按 §9 阶段计划推进。

约定：本文档所有"现状"描述均标注源码出处（文件:行号），未验证内容一律标注为
"开放问题"。测试与运行环境：SLang release 包（不跑 wasm）。

---

## 1. 目标与非目标

### 1.1 目标

仿照 PyTorch 的分层方式，把 Tensora 从"CPU 单后端、Float32 单类型"的算子库，
演进为**跨平台（Windows/Linux）、跨硬件（CPU / CUDA GPU / ROCm GPU / NPU / TPU）**
的算子计算框架：

1. `Tensor` 携带 dtype 与 device，算子按设备自动分发（等价 PyTorch 的
   Tensor + Dispatcher + Backend 三层）；
2. 每个 GPU/NPU 算子与 CPU 参考实现**逐位一致**（bitwise parity），
   测试以 CPU 实现为黄金基准；
3. 主机内存 ↔ 设备显存之间的**传值与操作协议**是一等公民：搬运通路、
   脏状态机、显存分配/释放/记账、跨设备运算语义全部显式定义（§5）；
4. 各硬件后端以独立桥模块接入（复用 `Lib\SLang\Cuda` 已验证的
   `sl_*_lib.dll + @DllStaticImport + vmDlls` 工程模式），Tensora 本体不感知
   原生细节；
5. CPU 同样是"后端"：SL 解释层参考实现之上提供**原生 SIMD 加速层**
   （x64：SSE2 基线→AVX2→AVX-512 运行期检测分派；ARM64：NEON 基线），
   覆盖计算密集算子（§6.1）；
6. 后端不可用时**显式报错**，不做隐式回落（错误可见，语义与 PyTorch 一致）；
   可选的回落开关默认关闭，仅在 jsonc 显式开启后生效。

### 1.2 非目标（本期不做）

- 自动微分设备的自动跟随：v1 的 Autograd 仍要求前向/反向在同一设备执行；
- 异步流（stream）并行与多流重叠：v1 全部同步语义（§5.5 定义约束与
  启用条件）；
- 分布式（多卡 all-reduce 等）；
- 零拷贝 view / stride 共享存储（见 §10 开放问题 OQ-2）；
- 内核自动调优（autotune）、cuDNN/cuBLAS 级别的手工库接入。

---

## 2. 现状盘点

### 2.1 模块构成

Tensora 位于 `SLangCore\Lib\SLang\Tensora\`，29 个编译源文件
（Tensora.jsonc compileFiles），引用 `../Core`、`../Std`、`../Math`
（Tensora.jsonc references 段）。测试项目 `SLangCore\test\TensoraTest\`
（ProjectTest.jsonc，引用 `out/export/Tensora/Tensora.module.json`）。

| 源文件 | 职责 |
|---|---|
| Shape.sl | 维度/步长/偏移换算/广播推导 |
| Tensor.sl | Float32 张量：构造、索引、逐元素、matmul、归约、数学、工厂 |
| Math.sl (TensorMath) | 标量数学：AI 激活/概率函数补充 Mathf |
| Random.sl (Rng) | 可复现随机（LCG + Box-Muller） |
| Init.sl | 权重初始化（Xavier/He/正交） |
| Ops.sl | 高层算子：im2col/conv2d/pool/concat/topK/reduceTo 等 |
| Autograd.sl | Variable/Graph 反向模式自动微分 |
| Layer.sl 及 11 个层文件 | Dense/Conv2D/Pool/BatchNorm/LayerNorm/Dropout/Flatten/Embedding/RNN/LSTM/GRU/Attention/MHA/TransformerBlock/Transformer |
| Optimizer/ Scheduler/ Metrics/ Dataset/ Tokenizer/ Trainer | 训练栈 |
| Device.sl | 设备枚举 + 记账类（**当前无任何其他文件引用**，见 2.3） |

### 2.2 已有能力核对（关键行号）

- 存储：`Tensor._data: Array<Float32>` + `Shape` + `strides`，行主序扁平
  （Tensor.sl:12-14）。**Float32 单类型**。
- 逐元素广播：add/sub/mul/div（Tensor.sl:321-367），广播取值 `pick`
  （Tensor.sl:158-183），形状广播 `Shape.broadcastShape`（Shape.sl:193-235，
  不可广播返回 null）。
- matmul：**仅 2D×2D**（Tensor.sl:395-414）。
- 原地运算：addInPlace/subInPlace/mulInPlace/scaleInPlace/copyFrom
  （Tensor.sl:196-215, 417-447）。
- 归约：全量 sum/mean/max/min/argmax/argmin（Tensor.sl:450-519）；
  按轴归约 `reduceAlong` **仅支持 2D 且 axis∈{0,1}**，内部直接取
  `dims[0]/dims[1]`（Tensor.sl:538-603），rank≠2 时行为未定义。
- 数学逐元素：exp/log/sqrt/abs/pow/clamp/relu/sigmoid/tanh
  （Tensor.sl:606-694）；softmax/logSoftmax 逐行（Tensor.sl:697-752）。
- 形状：reshape（恒复制，Tensor.sl:223-231）、flatten、transpose 2D
  （Tensor.sl:239-252）、通用轴置换 transpose(axes)（Tensor.sl:254-276）、
  **slice 仅第 0 维**（Tensor.sl:279-297）、row/setRow。
- Ops：im2col（Ops.sl:13-58）、**conv2d 单输出通道**
  （输入[C,H,W]×核[C,k,k]→[1,outH,outW]，Ops.sl:60-103；多输出通道由
  Conv2D 层逐输出通道循环调用拼装，Conv.sl:71-95）、maxPool2d/avgPool2d
  （Ops.sl:105-166）、**concat 仅 2D 且 axis∈{0,1}**（Ops.sl:170-226）、
  stackTensors 仅堆成一维行（Ops.sl:229-242）、oneHot、topK
  （仅返回下标，选择排序 O(nk)，Ops.sl:255-279）、cosine/normalize/
  standardize、reduceTo（广播梯度还原，Ops.sl:382-414）。
- Autograd：Variable 记录 op/parents，Graph DFS 拓扑排序，反传覆盖
  add/sub/mul/div/matmul/scale/relu/sigmoid/tanh/exp/log/pow/sum/mean/
  softmax/reshape/transpose 共 16 个算子（Autograd.sl:252-377）。
- 测试：TensorTest 覆盖 Shape/构造/广播/matmul/归约/数学
  （TensoraTest\TensorTest.sl:19-100+），另有 AutogradTest/CnnTest/NnTest/
  ClassicMlTest/DataTest/TtsTest/TransformerModelTest 共 8 个测试套
  （ProjectTest.jsonc compileFiles）。

### 2.3 设备抽象现状：空壳

`EDeviceKind{CPU=0,GPU,NPU}` 与 `Device` 类（Device.sl:5-87）只有
kind/id/name/available/bytesUsed 五个记账字段，`alloc/free` 仅做字节统计。
**全库 grep 确认：没有任何其他源文件引用 Device**——它是一个预留桩。
Tensor 没有设备字段，所有算子固定跑在 CPU（SL 解释层）。

### 2.4 可复用的原生通路资产（后端接入的地基）

1. **SLangCuda 模块**（`Lib\SLang\Cuda\`）——已完整验证的驱动级 GPU 通路：
   - `sl_cuda_lib.dll`：NVIDIA 驱动 API（nvcuda.dll）运行期 LoadLibrary 解析，
     零 CUDA Toolkit 依赖（vm_sl_cuda.h:5-22；Cuda.jsonc vmDlls 段）；
   - SL 绑定全走 `@DllStaticImport("sl_cuda_lib","slc_*", sig)` 静态直调，
     DLL 缺失时回退 SL 兜底函数体（Cuda.jsonc dllImports 段注释；
     Cuda.sl:72-278）；
   - 设备内存：`CudaBuffer.alloc / allocManaged / free`，`upload / download`
     （H2D/D2H 整块 memcpy），`uploadAsync / downloadAsync`（流式异步），
     `memset8`（按字节填充）（Cuda.sl:499-647）；
   - 设备内拷贝：`libMemcpyD2D`（Cuda.sl:178-180，对应
     slc_memcpy_d2d，vm_sl_cuda.h:147）——**CudaBuffer 未包装，仅库级**；
   - 内核：`CudaKernel.fromPtx`（PTX 文本 JIT，Cuda.sl:935-949）+
     `launch1D`（Cuda.sl:986-994），参数经 `CudaKernelArgs`（8 字节值槽 +
     指针槽双块布局，Cuda.sl:787-899）；
   - 流/事件：`CudaStream`、`CudaEvent`（计时事件必须 flags=0 创建，
     Cuda.sl:62-68 注释——DISABLE_TIMING 会导致 elapsedMs 返回 -1）；
   - 显存余量：`Cuda.memFreeBytes / memTotalBytes`（Cuda.sl:356-399，
     slc_mem_info，vm_sl_cuda.h:155-157）。
2. **Core.Memory 原生块**（`Lib\Core\Memory.sl`）：
   `alloc/free/allocArray` + `read*/write*` 全系（Memory.sl:328-593）；
   **类型宽度表**：bool/i8/u8/f8=1，i16/u16/f16=2，i32/u32/f32=4，
   i64/u64/f64/ptr/utf8=8（Memory.sl:341-346）。注意：SL 托管
   `Array<Float32>` **没有裸指针出口**，上 GPU 必须经 Memory 原生块中转
   （§5.2 三段式通路）。
3. **jsonc 机制**：`vmDlls`（导出模块时 MSBuild 编译 vcxproj 并随模块分发
   DLL，Cuda.jsonc:33-35）；`systemCalls`（Tensora.jsonc:14-17 已预留注释
   "后续接 GPU 后端时在此登记"，本设计优先走 DLL 桥，不走 systemCalls，
   理由见 §3.3-D3）。
4. **类型系统**：SL 已有 Float16（`half`）、Float16_Brain（`bf16`）、Float8、
   Int8/16/32/64、Float32/64 全谱（Lib\Core\Float16.sl:1-9、
   Float16_Brain:80-96、Int8.sl、Int64.sl 等），dtype 枚举可一一映射。
5. **生命周期事实**：SL 核心库 grep 确认**无 `_del_`/`_dispose_`/`_finalize_`
   析构钩子**——设备显存不能依赖对象销毁回收，必须显式释放协议（§5.4）。

### 2.5 与 PyTorch 的算子缺口总表

| 类别 | PyTorch 对应 | Tensora 现状 | 缺口 |
|---|---|---|---|
| 类型 | f16/bf16/f32/f64/i8..i64/bool | 仅 f32 | 全缺（dtype 字段+存储+转换） |
| 创建 | tensor/zeros/…/randperm | zeros/ones/full/scalar/vector/matrix/identity/random/randn（Tensor.sl:755-827） | randperm、f16/bf16 变体 |
| 形状 | squeeze/unsqueeze/expand/repeat/pad/cat(任意维)/stack/split/chunk/narrow/flip/roll | reshape/flatten/transpose/slice(轴0) | squeeze/unsqueeze/expand/repeat/pad/cat(≥3D)/stack(新轴)/split/chunk/narrow/flip |
| 索引 | index_select/masked_fill/gather/scatter/where/nonzero | get/set 1~4 维 + pick | index_select/masked_fill/gather/scatter/where(张量级)/nonzero |
| 比较 | eq/ne/gt/…、maximum/minimum、sort/topk(带值) | 无张量化比较；topK 仅下标（Ops.sl:255-279） | 张量化比较/maximum/minimum/sort/argsort/topk 值+下标 |
| 归约 | prod/std/var/norm/any/all/cumsum/任意轴/keepdim | 全量归约 + 2D 轴 0/1（Tensor.sl:450-603） | prod/std/var/norm/any/all/cumsum/任意轴泛化（去 2D 限制） |
| matmul | bmm/批量 matmul/einsum/dot/outer | 2D×2D（Tensor.sl:395-414） | 3D+ 批量 matmul/dot/outer/einsum |
| 逐元素 | floor/ceil/round/sin/cos/reciprocal/fmod/frac | exp/log/sqrt/abs/pow/clamp（Tensor.sl:606-654） | floor/ceil/round/sin/cos/reciprocal/fmod/frac |
| 随机 | uniform_/normal_/multinomial | Rng 标量级（Random.sl）+ Tensor.random/randn | multinomial、张量级 in-place 填充已有 fillUniform/fillNormal（Init.sl:90-106）可复用 |
| 卷积 | conv2d [B,C,H,W]×[O,C,k,k] | Ops.conv2d 单输出通道（Ops.sl:60-103），层内循环拼装（Conv.sl:80-91） | 批维/多输出通道一体化算子、dilated/groups |
| softmax | softmax/log_softmax(带 dim) | 逐行固定最后维（Tensor.sl:697-752） | 任意 dim |
| 设备/传值 | to(device)/cuda()/cpu()/copy_/pin_memory | 无（Device 空壳，§2.3；无任何 H2D/D2H 使用） | 全部（§5） |
| CPU 加速 | at::vec::Vectorized / oneDNN / MKL（运行期 ISA 分派） | SL 解释层逐元素循环，无 SIMD/多核 | sl_cpu_lib.dll SIMD 加速层：SSE2/AVX2/AVX-512/NEON + cpuid 分派（§6.1） |

> 结论：缺口分两层——**CPU 算子层**（类型/形状/索引/比较/归约/matmul 泛化，
> 纯 SL 可完成、立即可测）与**设备层**（搬运/分发/各硬件 kernel）。据此排
> Phase 1（补 CPU）与 Phase 2+（接设备）。

---

## 3. 总体架构（仿 PyTorch）

### 3.1 概念映射

| PyTorch | Tensora 对应 | 落点 |
|---|---|---|
| torch.Tensor | `Tensor`（扩展现有类） | Tensor.sl 加 `_dtype/_device/_devBlock` 字段 |
| torch.dtype | `EDtype` 枚举 | 新文件 Dtype.sl |
| torch.device | `Device`（激活现有空壳） | Device.sl 扩展 |
| ATen 算子 | Tensor 实例方法 + `Ops` 静态类 | 现有模式不变 |
| Dispatcher | **方法体内按 `this._device.kind` 路由** | Tensor.sl 各算子头部 |
| CPU 后端 (aten CPU) | 现有 SL 实现 = 参考实现（黄金基准） | 代码原地保留 |
| CUDA 后端 | `Backends/CudaBackend.sl` + 桥模块 SLangCuda | 复用 Lib\SLang\Cuda |
| CPU SIMD（≈at::vec::Vectorized + runtime dispatch） | `sl_cpu_lib.dll` + cpuid 特性检测 + 函数表分派 | §6.1 |
| ROCm 后端 | `Backends/RocmBackend.sl` + 桥模块 SLangRocm（新建） | 同构 sl_rocm_lib.dll |
| NPU/TPU 后端 | 插件规约（§6.4/§6.5） | 后续阶段 |
| .to(device) / .cuda() | `Tensor.to(device)` | 语义 §5.3 |
| copy_ / clone 跨设备 | `Tensor.to` 复制语义 + 设备内 TCOPY | §5.2 |
| torch.cuda.is_available() | `Backends.available(kind)` | §4.5 |
| 显存管理（caching allocator） | 影子缓冲 + 显式释放 + 记账 | §5 |

### 3.2 分层图

```
┌────────────────────────────────────────────────────────────┐
│  用户层：Trainer / Layers(Dense/Conv/MHA…) / Autograd      │
│          （调用 t.add()/t.matmul() …，完全不感知设备）      │
├────────────────────────────────────────────────────────────┤
│  API 层：Tensor 方法（现有签名不变）                        │
│   add(): if this._device.kind==CPU → CPU 参考实现           │
│           else → Backends.route(kind, opId, …)              │
├────────────────────────────────────────────────────────────┤
│  分发层：Backends/BackendRegistry（SL 类，纯 SLang）        │
│   - available(kind) 探测   - opId → kernel 表               │
│   - 影子缓冲状态机 + staging（§5.1/§5.2）                   │
├──────────────────┬──────────────────┬──────────────────────┤
│ CPU 后端          │ CUDA 桥           │ ROCm 桥 …            │
│ L0 SL 参考实现    │ SLangCuda 模块    │ SLangRocm 模块        │
│ （黄金基准）       │ sl_cuda_lib.dll   │ sl_rocm_lib.dll       │
│ L1 SIMD 加速层    │ PTX JIT 内核      │ code object 内核      │
│ sl_cpu_lib.dll   │ nvcuda.dll        │ amdhip64 (HIP)       │
│ SSE2/AVX2/512    │                  │                      │
│ 运行期检测分派    │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
```

### 3.3 硬性决策

- **D1 入口不变**：分发埋在 Tensor 方法体内，不改公开签名。理由：Autograd、
  全部 Layer、Trainer、TensoraTest 8 个套件直接调用 `t.add()` 等（如
  Dense.sl:51-78、Autograd.sl:264-292）；新增 OpsDispatch 门面会让所有
  调用点迁移，收益为零。
- **D2 后端桥独立模块化**：每类硬件一个 `Lib\SLang\<X>\` 桥模块（含原生
  DLL 的 vcxproj + SL 绑定），Tensora 经 references 引用。理由：SLangCuda
  已验证该结构（Cuda.jsonc），且原生依赖（nvcuda/hip/acl 各自的运行库）
  按需分发、互不传染；Tensora 本体保持纯 SL 可在无卡环境编译。
- **D3 不走 systemCalls**：Tensora.jsonc:14-17 预留了 systemCalls 登记位，
  但 cvm 内建符号需改 C VM 源码并重新发版；而 `@DllStaticImport` 静态绑定
  已在 SLangCuda 全量落地（opcode 77 直调，无 Adaptor 开销）。v1 全部后端
  走 DLL 桥；仅当出现"必须访问 VM 内部结构"的需求（如 SL Array 裸指针，
  OQ-1）才启用 systemCalls 通道。
- **D4 显式失败**：目标后端不可用/算子未实现 → `BackendError` 抛出（沿
  SLang 异常惯例），不静默回落 CPU；`Backends.fallbackToCpu` 开关默认
  false，jsonc `data.tensorsFallbackCpu` 显式置 true 才生效
  （遵循"新增开关默认关闭"工程规约）。
- **D5 CPU 参考实现是唯一黄金基准（分级验收）**：任何后端 kernel 与 CPU
  实现的一致性分两级——Tier-1 算子（add/sub/mul/div/scale/relu/clamp/
  max/min/sum/mean/matmul/softmax 等**纯 IEEE754 运算**）要求**位级一致**
  （Float32 位级对比，沿"RHI 跨后端逐字节一致"项目铁律）；Tier-2 算子
  （exp/log/sigmoid/tanh/gelu 等超越函数——不同算法实现不可能逐位相同）
  要求 ULP 级容差验收并显式标注。性能路径若改变浮点结合语义（FMA 融合、
  多核分块求和）一律独立函数 + 开关**默认关**（§6.1.4/§6.1.5），位级
  验收只约束默认路径。
- **D6 传值协议显式化**：主机↔设备的每一次搬运必须经由 §5 定义的统一
  原语（stageOut/stageIn/uploadFlow/downloadFlow），禁止算子实现内私拼
  Memory 原生块直接调 memcpy——保证成本可计量、状态机可推理、后端可替换。

---

## 4. 核心机制设计

### 4.1 Dtype 系统

新增 `Dtype.sl`：

```
enum EDtype            # 枚举成员显式赋值（SL 约束，全 0 缺陷）
{
    F32 = 0
    F16 = 1
    BF16 = 2
    I32 = 3
    I64 = 4
    BOOL = 5
}
```

- `Tensor` 增加 `EDtype _dtype = EDtype.F32` 字段与 `dtype()` 属性；
- SL 类型映射：F32→Array<Float32>，I32→Array<Int32>，BOOL→Array<bool>，
  F16→Array<Float16>（`half`，Core\Float16.sl），BF16→Array<Float16_Brain>
  （Core\Float16.sl:80-96）。存储类 F16/BF16 在 CPU 侧计算仍按 F32 中转
  （load→F32 计算→store 截断），GPU 侧用原生 f16/bf16 PTX 指令；
- **元素宽度表**（搬运计费与显存分配共用，出处 Memory.sl:341-346）：
  BOOL=1，F16/BF16=2，F32/I32=4，F64/I64=8 字节；
- 阶段支持范围：**Phase 1 仅 F32（现状不动）+ I32（索引/mask/label 张量）**
  ；F16/BF16 留待 Phase 2+（SL 层 Float16 算术语义需先验证，OQ-3）；
- 类型转换：`Tensor.toDtype(EDtype)` 返回新张量（复制语义），
  同名 in-place 版不提供（避免精度静默丢失）。

### 4.2 Tensor 设备绑定与影子缓冲（字段）

`Tensor` 增加四个私有字段（CPU 张量恒为默认值，零成本）：

```
Device _device = null          # null ≡ Device.cpu()，避免默认构造开销
Int64  _devBlock = 0           # 设备侧影子缓冲句柄（CudaBuffer 句柄；0=未分配）
bool   _hostDirty = true       # true: _data 是权威副本，影子过期
bool   _devDirty = false       # true: 影子是权威副本，_data 过期
```

状态机、转换规则与不变式见 §5.1；`to(device)` 语义见 §5.3。

`Device` 扩展：`backendKind`（ECpu/ECuda/ERocm/ENpu/ETpu…，替代现有
仅 3 值的 EDeviceKind——保留旧枚举兼容，新增映射函数），`Device.cuda(id)` /
`Device.rocm(id)` / `Device.npu(id)` 工厂。

### 4.3 算子分发协议

每个可分发算子按统一四步接入（以 `add` 为例）：

1. **形状推导**：`Shape.broadcastShape`（Shape.sl:193-235，CPU/设备共用，
   推导永远在 CPU 侧）；
2. **staging**：两侧输入张量经 `Backends.stageOut` 保证设备缓冲最新
   （§5.2 上传协议，含惰性分配与上限预检）；
3. **launch**：`Backends.route(kind, opId, args…)` → 后端 kernel 执行
   （CUDA 经 `CudaKernel.launch1D`，Cuda.sl:986-994）；
4. **回收**：输出张量绑定目标设备 + `_devDirty=true, _hostDirty=false`，
   仅当调用方读值时才 `stageIn`（读迫同步，§5.2）。

未实现设备算子的 opId 落入 `Backends.unsupported(opId)` → 抛
BackendError（D4）。

### 4.4 后端注册与能力探测

新文件 `Backends/BackendRegistry.sl`：

- `Backends.available(EDeviceKind)`：按 kind 查询桥模块（如 CUDA =
  `Cuda.initialize() && Cuda.deviceCount() > 0`，Cuda.sl:283-333 已有）；
- jsonc 开关（**全部默认关闭**，符合工程规约）：
  `data.tensoraCudaEnabled / tensoraRocmEnabled / tensoraNpuEnabled`，
  显式置 true 后 `Backends.route` 才会尝试非 CPU 路径；
- 首批 kernel 表：CUDA 12 opId + 2 库级原语（§6.2 清单）。

---

## 5. 内存与显存管理协议（传值与操作，重点章）

本章定义 Tensora 的数据在**三个存储位置**之间如何搬运、何时搬运、谁负责
搬运，以及显存的分配/释放/记账规则。所有算子实现（§4.3 四步协议）与
后端接入（§6）必须且只能使用本章原语。

### 5.0 存储分层模型：三位置六原语

**三个存储位置**：

| 位置 | 载体 | 角色 | 生命周期 |
|---|---|---|---|
| A：SL 托管堆 | `Tensor._data : Array<Float32>` | 权威数据源；CPU 参考实现的计算介质 | 随 Tensor 对象 |
| B：主机原生块 | `Memory.alloc` 块（malloc 语义，Memory.sl:328-331） | FFI 中转块：A↔C 搬运的字节缓冲 | **单次搬运内**（即取即还） |
| C：设备显存 | `CudaBuffer`（slc_mem_alloc，vm_sl_cuda.h:128） | 设备算子的计算介质（影子缓冲） | 惰性分配（§5.3），显式释放 |

**六类传值原语**（全部已存在于现有代码，本章只做协议化收口）：

| 编号 | 通路 | 原语 | 语义 | 每元素成本构成 |
|---|---|---|---|---|
| P1 | A→B | `Memory.writeF32` 等循环写（Memory.sl:572） | SL 数组 → 原生块 | n 次函数调用 |
| P2 | B→C | `CudaBuffer.upload` → slc_memcpy_h2d（vm_sl_cuda.h:141） | 整块 DMA 上传 | 1 次 DMA（4n 字节，f32） |
| P3 | C→B | `CudaBuffer.download` → slc_memcpy_d2h（vm_sl_cuda.h:144） | 整块 DMA 下载 | 1 次 DMA |
| P4 | B→A | `Memory.readFloat32` 等循环读（Memory.sl:519） | 原生块 → SL 数组 | n 次函数调用 |
| P5 | C→C | `libMemcpyD2D`（Cuda.sl:178-180）/ `CudaBuffer.memset8`（Cuda.sl:625-642） | 设备内拷贝/填充，**不过主机** | 1 次 DMA |
| P6 | 异步族 | `uploadAsync/downloadAsync` → slc_memcpy_*_async（vm_sl_cuda.h:150-153） | 流式异步搬运 | v2 启用（§5.6） |

> 结论性事实：A↔B 是逐元素函数调用（P1/P4），B↔C 是整块 DMA（P2/P3）。
> 可疑瓶颈在 P1/P4 而非 DMA——Phase 2 第一个基准就是分段实测（§5.7），
> 若瓶颈成立则触发 OQ-1（cvm SystemArrayPin 裸指针出口）。

### 5.1 影子缓冲状态机

`_hostDirty/_devDirty` 组合出三个合法状态 + 一个禁止状态：

| 状态 | hostDirty | devDirty | 含义 |
|---|---|---|---|
| S0 SYNCED | false | false | 两侧一致（to() 完成后、设备原地操作后） |
| S1 HOST 权威 | true | false | _data 新，影子过期（CPU 写后） |
| S2 DEV 权威 | false | true | 影子新，_data 过期（设备算子出口） |
| — 禁止 | true | true | **不允许出现**：两侧都自称新 |

**不变式**（BackendRegistry 单元测试逐条断言）：

- I1：任何设备算子入口，全部输入张量处于 hostDirty=false（即 S0/S2，
  由 stageOut 保证）；
- I2：任何算子出口（CPU 路径或设备路径），恰好一侧 dirty；
- I3：`_devBlock == 0` ⇒ `_devDirty == false`（无影子则影子不可能权威）；
- I4：CPU 路径（读 _data 写 _data 的现有实现）出口 = S1（写类）或 S1→S0
  不变（纯读类，读不置位）。

**状态转换表**（谁在什么时机触发）：

| 动作 | 前置 | 转换 | 触发者 |
|---|---|---|---|
| `Tensor.to(device)` 上传 | 任意 | → S0（devBlock 分配+P1+P2） | to() 自身（§5.3） |
| 设备算子 stageOut 输入 | S1 | → S0（P1+P2） | Backends.stageOut（§4.3-步2） |
| 设备算子产出输出 | — | → S2（新张量 _devBlock 直接有效） | Backends.route 出口 |
| 读值前 stageIn | S2 | → S0（P3+P4） | ensureHostFresh（§5.2） |
| CPU 原地写（set/zero/addInPlace…） | S2 | 先 stageIn→S0，写完 → S1 | 写值钩子（§5.2） |
| 设备原地操作（scaleInPlace 设备版/zero 设备版） | S1 | 先 stageOut→S0，操作后 → S2 | 设备原地路径 |
| 显式释放 freeDevice() | 任意 | → CPU 张量（devBlock=0，S1） | 用户/Module 清理（§5.4） |

**重要语义决策——"读迫同步"而非"写迫上传"**：设备算子出口保持 S2，
不立即回传；只有当 CPU 侧真正读值（`get/at/data()/sum()/toString()` 等，
§5.2 读方法清单）才发生 P3+P4。理由：训练循环中张量长期驻留 GPU
（前向→反向→更新全链在设备侧），读迫同步让回传只发生在 Trainer 打印
指标/取 loss 的时刻，避免每步白搬一趟。

### 5.2 传值操作协议（逐方法收口）

#### 5.2.1 上传协议 `Backends.uploadFlow(Tensor t)`（S1→S0）

```
1. 校验：t._device 非 CPU 且 Backends.available(kind)（否则 BackendError）
2. 若 t._devBlock == 0：惰性分配（§5.3 分配协议）
3. 若 t._hostDirty == false：直接返回（已是 S0/S2）
4. 组 B 块：Int64 blk = Memory.alloc( n * dtypeBytes )   // f32: n*4
5. P1：for i in [0,n): Memory.writeF32( blk, i*4, t._data[i] )
6. P2：CudaBuffer.upload( blk, n*dtypeBytes )（或后端等价物）
7. 还 B 块：Memory.free( blk )
8. 置位：_hostDirty=false（devDirty 保持 false）→ S0
```

失败处理：步骤 2/6 任一失败抛 BackendError（带 `Cuda.errorString()` 文本，
Cuda.sl:401-419），B 块在失败分支也必须 free（防泄漏）。

#### 5.2.2 下载协议 `Backends.downloadFlow(Tensor t)`（S2→S0）

```
1. 校验：_devBlock != 0 且 _devDirty == true（否则无需下载）
2. P3 前先 synchronize（v1 全同步语义，§5.6）
3. 组 B 块：Memory.alloc( n * dtypeBytes )
4. P3：CudaBuffer.download( blk, n*dtypeBytes )
5. P4：for i in [0,n): t._data[i] = Memory.readFloat32( blk, i*4 )
6. 还 B 块
7. 置位：_devDirty=false → S0
```

#### 5.2.3 读值钩子 `ensureHostFresh()`（Tensor 内部私有方法）

以下**读方法**头部统一插入 `this.ensureHostFresh()`（S2 时触发下载协议）：

- 元素读：`at`（Tensor.sl:97）、`get` 全部 5 个重载（:107-155）、`pick`
  （:158）、`row`（:300）；
- 归约读：`sum/mean/max/min/argmax/argmin`（:450-519）、
  `sumAlong/meanAlong/maxAlong/reduceAlong`（:522-603）；
- 导出读：`data()`（:86）、`toString()`（:829）、`sameShape`（:217，只读
  形状不读值，**不插钩子**）。

以下**写方法**头部统一插入 `ensureHostFresh()` + 尾部置 `_hostDirty=true`：

- `set/setAt` 全部重载、`setRow`、`copyFrom`、`fillValue`、`zero`、
  `addInPlace/subInPlace/mulInPlace/scaleInPlace`（Tensor.sl:112-215,
  417-447）。

> 例外：设备专用的原地路径（§5.2.4）命中时不走 CPU 写钩子。

#### 5.2.4 设备原地操作（不落主机）

部分原地算子可**纯设备执行**（输入输出同一显存块，零搬运）：

| Tensor 方法 | 设备实现 | 原语 |
|---|---|---|
| `zero()` | memset8(0)（f32 的 0 即字节 0） | P5，CudaBuffer.memset8（Cuda.sl:625-631） |
| `fillValue(v≠0)` | TFILL kernel（新 opId） | launch |
| `scaleInPlace(k)` | ESCALE kernel 原地版（dst==src） | launch |
| `clone()`（同设备） | 设备内拷贝 | P5，libMemcpyD2D（Cuda.sl:178-180） |
| `copyFrom(src)`（同设备同形状） | 设备内拷贝 | P5 |

设备原地操作出口：`_devDirty=true, _hostDirty=false`（S2），与设备算子
一致。**前提**：`_devBlock != 0` 且操作数同设备；否则回落 CPU 写钩子路径。

#### 5.2.5 跨设备运算矩阵

二元算子（add/matmul/…）的输入设备组合处理（对齐 PyTorch：不隐式搬移）：

| 左操作数 | 右操作数 | 处理 |
|---|---|---|
| cpu | cpu | CPU 参考实现（现状路径） |
| cpu | cuda:X / cuda:X | cpu | **BackendError**（提示显式 .to()；`tensorsFallbackCpu` 开关开启时按 D4 回落 CPU 并打 warning 一次） |
| cuda:X | cuda:X | CUDA kernel，输出驻留 cuda:X |
| cuda:X | cuda:Y (X≠Y) | **v1 BackendError**（无 peer copy 原语，OQ-9） |
| 任一 | npu/tpu/rocm 混合 | 同上规则按 kind 严格相等执行 |

输出设备 = 输入设备（输入不一致时已报错）；`Tensor.to` 是唯一的跨设备
数据移动入口。

#### 5.2.6 典型算子数据流（协议样例）

**训练单步（数据不回主机）**：

```
batch(cpu) ──to(cuda)──▶ [S0] ──forward──▶ logits[S2] ──loss──▶ l[S2]
l.grad 等 ──backward──▶ grads[S2] ──optimizer.step(设备原地)──▶ 权重[S2]
仅 Trainer 打印 loss 时：l.ensureHostFresh() → 一次 P3+P4
```

**add（广播）**：形状推导（CPU）→ stageOut(a)、stageOut(b)（各一次
P1+P2，若 S1）→ EADD launch → out=S2。广播张量 b（如偏置 [1,n]）的
**影子按其自身元素数分配**（非广播后大小），kernel 内按下标映射取 b
（等价 CPU `pick` 的设备版）——小张量不重复存储，也免除上传期广播展开。

**matmul**：stageOut(a,b) → MMUL launch（M,K,N 参数）→ out=S2。
反向 `grad.matmul(b.transpose())` 中 transpose 产出 S2 临时张量，连续设备
算子链路全程零主机往返。

### 5.3 设备分配协议（显存的分配/搬运时机）

- **分配时机**：`Tensor.to(device)` 立即分配并完成上传（→S0）。决策理由：
  to() 调用点即数据准备点，分配/上传失败应即时暴露（对齐 PyTorch `t.cuda()`
  即刻报错的语义），而非延迟到首次算子；设备算子的 stageOut 只负责补传
  （S1→S0），不负责首次分配（不变式 I3 保证无重复分配）。
- **分配大小**：`n * dtypeBytes`（宽度表 §4.1；f32 即 4n 字节）。
- **上限预检**：分配前查 `Cuda.memFreeBytes()`（Cuda.sl:356-375），不足则
  BackendError（含"requested X, free Y"文本），**不做静默换页/换设备**。
- **记账**：分配成功调 `Device.alloc(bytes)`、释放调 `Device.free(bytes)`
  ——激活 Device.sl:72-81 现有记账字段，`Device.bytesUsed` 即时可见
  （训练脚本可打印显存占用）。
- **释放协议**（SL 无析构钩子，§2.4-5 事实）：
  - `Tensor.freeDevice()`：显式释放影子（`CudaBuffer.free`），张量回到
    纯 CPU 态（devBlock=0, S1）；
  - 上层清理入口：`Module.freeDevice()` 遍历全部 parameters/gradients
    （Layer.sl:88-106 已有聚合方法）批量释放；`Trainer` 结束时对
    inputCache/outputCache/outputCache/loss 显式释放；
  - 未显式释放的影子缓冲由进程退出时驱动回收（vm_sl_cuda.h:52-54 已声
    明 primary context 不 release、退出回收的原生层策略）——**长期驻留
    进程**（如 WebUI 服务）必须使用 freeDevice 协议，写入 Trainer 收尾
    文档。
- **v2 方向（本期不设计细节）**：按尺寸分桶的显存块池（对标 PyTorch
  caching allocator 的动机：避免反复 cudaMalloc）；启用前提 = Phase 2
  实测显示分配开销可感知。

### 5.4 统一内存（managed）评估

`slc_mem_alloc_managed` 已存在（vm_sl_cuda.h:130-132，Cuda.sl:148-150），
可在分配时直接获得主机可解引用的统一内存，省去 B 块中转（A→B→C 变成
A→C 单段）。

- **v1 决策：不使用**。理由：(a) managed 页面迁移开销在训练热点路径上
  不可控（首触缺页 + SM 迁移惩罚），与 D5 逐位一致基准测试的稳定性冲突；
  (b) 三段式协议统一所有后端语义，managed 是 CUDA 特有能力，提前引入会
  破坏后端可替换性（ROCm 的 managed 支持面不同）；
- v2 可作为**基准对照选项**（开关默认关）参与 §5.7 分段实测，用数据
  决定是否为"小张量频繁往返"场景（如偏置/标量 loss）开 managed 旁路。

### 5.5 异步与流（v2 方向，仅立约束）

- v1 全同步语义：每个设备算子 = stageOut（同步）→ launch → 出口保持 S2；
  下载协议在 P3 前显式 `Cuda.synchronize()` 或 stream 级
  `CudaStream.synchronize()`（Cuda.sl:683-687）；
- **位级一致测试在异步下不可定义**——一致性验收（§8）必须在同步语义下
  通过后才允许引入异步；
- 异步启用前提（v2）：影子缓冲状态机扩展"在途"状态（P6 async 搬运挂起
  时读值必须先 `CudaEvent.synchronize`，事件原语已备：Cuda.sl:701-778）；
  流水线 stageOut(nextBatch) ∥ launch(curBatch) 的重叠收益需先有 §5.7
  分段数据支撑；
- **禁止事项**：任何算子出口不得存在未同步的在途搬运（I2 在异步扩展后
  仍必须成立——在途视同未完成，不算权威侧）。

### 5.6 显存/内存操作原语总表（Tensor 公开接口收口）

| 用户意图 | Tensora 入口 | 生效通路 |
|---|---|---|
| 张量上设备 | `t.to(Device.cuda(0))` | 分配+P1+P2（§5.3） |
| 张量回 CPU | `t.cpu()`（=to(Device.cpu())） | P3+P4 + 释放影子 |
| 同设备复制 | `t.clone()` / `dst.copyFrom(src)` | P5（设备内）或 CPU 复制 |
| 设备清零 | `t.zero()`（设备态） | memset8（P5） |
| 读单个值 | `t.get(...)` / `t.at(i)` | 读迫同步（§5.2.3） |
| 取全量主机数组 | `t.data()`（内部先 ensureHostFresh） | P3+P4 |
| 显存占用查询 | `t.device().bytesUsed` / `Cuda.memFreeBytes()` | 记账（Device.sl:72-81） |
| 释放显存 | `t.freeDevice()` / `Module.freeDevice()` | §5.3 释放协议 |

### 5.7 传值成本结构与分段基准（Phase 2 首个任务）

不做数值预估（项目规约），只定义成本构成与实测方案：

**成本构成（f32，n 元素）**：
- 上传一次 = n×writeF32 调用 + 1 次 4n 字节 DMA；
- 下载一次 = 1 次 4n 字节 DMA + n×readFloat32 调用；
- 设备内拷贝/清零 = 1 次 DMA/memset（无逐元素调用）。

**分段基准（落盘 `out/tensora/h2d_bench.txt`）**：
1. 输入规模阶梯：16K / 256K / 1M / 4M / 16M 元素（f32）；
2. 分段计时：P1 循环耗时、P2 DMA 耗时、P4 循环耗时、设备端 memset 耗时
   （计时手段：CPU 侧 SL 计时循环；GPU 侧 `CudaEvent.createTiming` +
   `elapsedMs`，**事件必须 flags=0 创建**，Cuda.sl:62-68 教训）；
3. 对比项：三段式 vs managed 旁路（§5.4 的对照开关，默认关）；
4. 判定规则：若 P1+P4 占单次上下传总耗时 > 50%，启动 OQ-1
   （cvm SystemArrayPin）立项；否则维持三段式；
5. **CPU SIMD 净收益对照**（P2B 用）：同一 P1/P4 成本计入后，L1 的
   matmul/sum/softmax 相对 L0（SL 循环）的净加速比；据此把各算子的
   L1 启用阈值写入分派表（§6.1.3，不预估、以实测为准）。

---

## 6. 硬件后端接入规约

### 6.0 通用规约（以 sl_cuda_lib 为蓝本，逐条对应）

每个硬件后端 = 一个 SLang 桥模块 `Lib\SLang\<X>\`，包含：

1. **原生 DLL** `sl_<x>_lib.dll`（C ABI，导出前缀 `sl<x>_`），全部厂商
   驱动/运行库符号**运行期 LoadLibrary + GetProcAddress 解析**，构建期零
   厂商 SDK 依赖（对应 sl_cuda_lib 对 nvcuda.dll 的做法，vm_sl_cuda.h:12-13）；
2. **句柄收敛**：上下文/流/模块/内核/缓冲句柄收敛为 `Int64`，0 恒为无效
   （vm_sl_cuda.h:16-17）；
3. **错误粘性**：每次入口先清 last_error，失败原因 `last_error/error_string`
   取回；bool 导出 1=成功 0=失败（vm_sl_cuda.h:32-44）——**FFI 布尔语义
   与 C 端严格对应**（项目教训：CUDA 0=false，SL 侧统一 `ok(rc)` 出口）；
4. **参数上限 6**（`SL_FFI_MAX_ARGS`，vm_sl_cuda.h:30）：超过的用
   描述块（Memory.alloc 组装，参照启动描述块 40 字节布局 vm_sl_cuda.h:198-206）；
5. **传值原语面（§5.0 六原语的后端等价物必须齐全）**：alloc/free/upload/
   download/memset/peek（memcpy_d2d）——缺一即无法满足 §5 协议，后端
   不可注册；
6. **jsonc 配置**：`dllImports`（static 注册名）+ `vmDlls`（vcxproj 路径）
   两个段齐全（Cuda.jsonc:20-35）；
7. **主机大块数据不走 FFI 传值**：一律原生块整块 memcpy
   （vm_sl_cuda.h:23-25）。

### 6.1 CPU 后端（L0 参考实现 + L1 SIMD 加速层）

#### 6.1.0 L0：SL 参考实现（Phase 1，黄金基准）

现有 SL 实现原地保留，零改动即可作为分发目标与一致性基准。Phase 1 同时
补齐 §2.5 缺口表中的 CPU 算子（优先级：索引/比较/归约泛化 > 形状变换 >
matmul 批量 > 其他），每补一个算子必须同步：TensorTest 断言 + Autograd
反传（若可微）+ Ops 静态入口（若属高层算子）。

#### 6.1.1 L1：原生 SIMD 加速层（Phase 2B，桥模块 SLangCpu）

| 层 | 实现 | 角色 |
|---|---|---|
| L0 | 现有 Tensor/Ops SL 循环 | 黄金基准 + 小张量路径 |
| L1 | `sl_cpu_lib.dll`（前缀 `slcp_`，桥模块 `Lib\SLang\Cpu\`，新建） | 大张量/计算密集算子加速 |

- L1 工程与 sl_cuda_lib 完全同构（vcxproj + vmDlls + @DllStaticImport，
  §6.0 全部条目），差异仅一点：CPU 特性检测后**直接调用本 DLL 导出函数**，
  无运行期 LoadLibrary（DLL 自身就是实现）；
- 分派入口在 BackendRegistry 的 CPU 路径：查"算子×规模"阈值表
  （§6.1.3），小于阈值走 L0（SL 循环，避开 FFI 固定调用开销），大于阈值
  走 L1（staging + 原生 kernel，§5 协议完全适用——CPU kernel 同样只能
  操作 B 块，staging 成本与 GPU 同构）；
- jsonc 开关 `tensoraSimdEnabled`（默认关）：L1 全局总开关。

#### 6.1.2 SIMD 指令集矩阵与运行期分派

| ISA | 寄存器 | f32 通道/指令 | 平台覆盖 |
|---|---|---|---|
| SSE2 | xmm 128-bit | 4 | x64 基线（所有 x64 CPU 必有；编译保底路径） |
| AVX2 + FMA3 | ymm 256-bit | 8 | 运行期检测启用 |
| AVX-512F/VL/DQ | zmm 512-bit | 16 | 运行期检测启用 |
| NEON | 128-bit | 4 | ARM64 基线（Linux 跨平台）；SVE 不做 |

- **检测**：x64 用 `__cpuid/__cpuidex`（leaf 1 的 OSXSAVE/AVX 位、
  leaf 7 的 EBX 位 AVX2/AVX512F/AVX512VL/AVX512DQ，并校验 XCR0 使能
  ——AVX/AVX-512 需 OS 保存上下文，仅 CPUID 置位不充分）；ARM64 NEON
  视为基线免检；
- **分派**：每个 SIMD 算子按 ISA 各一版 .c 文件（如 slcp_mmul_sse2.c /
  slcp_mmul_avx2.c / slcp_mmul_avx512.c），MSVC **按文件**设编译开关
  （/arch:AVX2、/arch:AVX512）；DLL 首次调用惰性检测并填函数指针表
  `slcp_pick(opId, isa)`，此后调用直达目标实现（每调用零检测开销）；
- **对齐与尾部**：不假设 SL Array / Memory 块对齐，SIMD 一律 unaligned
  load/store（`_mm512_loadu_ps` / `_mm_storeu_ps` / `vld1q_f32`）；
  尾部：AVX-512 用 mask 寄存器（`_mm512_mask_add_ps`），SSE2/AVX2/NEON
  用标量余段循环——杜绝越界读写。

#### 6.1.3 staging 成本矛盾与算子选择（关键诚实结论）

CPU 原生路径每次调用 = P1（n 次写调用）+ kernel + P4（n 次读调用），
staging 与 GPU 完全同构（§5.2），且 SL→FFI 调用本身有固定开销。由此推导
净收益边界：

| 算子类 | 计算/元素 | staging/元素 | 无 SystemArrayPin 时 L1 净收益 |
|---|---|---|---|
| add/relu 等 elementwise | 1 次运算 | 2 次调用（P1+P4） | **可能为负**：SIMD 只省 n→n/16 次运算，staging 付 2n 次调用 |
| sum/mean 等 reduce | 1 次运算 | 1 次调用（输出 1 元素） | 边际，需实测 |
| matmul(M,K,N) | 2MNK | 2(MK+KN)+MN | **显著正收益**：staging/计算比随规模 → 0 |
| conv2d（im2col+GEMM）/softmax | 计算密集 | 低占比 | 正收益 |

**结论与策略**：
1. L1 首批**只覆盖计算密集算子**：matmul（分块 packing + SIMD kernel）、
   conv2d（im2col 复用 Ops.sl:13-58 展开逻辑 + GEMM）、softmax、大数组
   sum。elementwise SIMD **不做**——待 OQ-1（SystemArrayPin）落地后
   kernel 直读 SL Array、staging 消失，再行覆盖；
2. **阈值分派**：每个 L1 算子设启用阈值（如 matmul M*K*N > T_mmul），
   阈值由 §5.7-5 基准实测后写入表，**不预估**；
3. OQ-1 的价值因此加倍：同时解锁 GPU 传输瓶颈与 CPU elementwise SIMD
   两个场景。

#### 6.1.4 位级一致分级（D5 落地）

| 级 | 算子 | SIMD 实现要点 | 验收标准 |
|---|---|---|---|
| Tier-1 | add/sub/mul/div/scale/relu/clamp/max/min/sum/mean/matmul/softmax | 仅用 IEEE 单舍入指令（`_mm512_add_ps/_mm512_mul_ps/_mm512_div_ps`/`vaddq_f32`…），与 SL 逐元素运算**逐位相同**；**禁用 FMA**（`_mm512_fmadd_ps` 单次舍入，与参考实现的 mul 后 add 两次舍入不同 → 位级偏差） | **位级一致**（逐位断言） |
| Tier-2 | exp/log/sigmoid/tanh/gelu/erf | 超越函数不同算法实现不可能逐位一致（TensorMath.exp 走 Mathf.exp 的 SL 实现，Math.sl:18-36；C 端多项式逼近各异） | 相对误差 ≤ 1e-6 的 ULP 级容差，测试报告显式标注 Tier-2 |
| sqrt | sqrt | `vsqrtps`/`vsqrtq_f32` 是 IEEE 精确舍入，理论可位级，但是否与 SL Mathf.sqrt 底层逐位相同未核对（OQ-12） | 实现前先跑标量探针定级再归 Tier |
| FMA 旁路 | matmul/softmax | 融合版独立函数（如 slcp_mmul_fma） | jsonc `tensoraFmaEnabled` **默认关**；开启后验收降为 1-2 ULP 容差并在报告标注 |

#### 6.1.5 多核与 BLAS（方向，v1 不做）

- **多核**：v1 L1 全部单线程；多核方向 = sl_cpu_lib 内部自建线程池
  （Win32 Thread / Linux pthread，**不引 OpenMP**——vcomp 运行库随模块
  分发违背零依赖原则），按行分块 + barrier 合并；注意**并行分块求和
  改变加法结合顺序 → 与单线程位级不一致**，并行版必须与 FMA 同级处理
  （独立函数 + 开关默认关 + 容差验收）；
- **BLAS 评估**（OQ-13）：OpenBLAS（BSD-3，许可合规）可达工业级 GEMM，
  但引入数十 MB 动态库分发与构建链复杂度；v1 手写 SIMD GEMM（目标
  "显著快于 L0 解释层"，**不承诺接近 OpenBLAS/cuBLAS**），BLAS 接入待
  §5.7 基准数据齐备后评估。

### 6.2 CUDA 后端（Phase 2）

**通路**：全部复用 SLangCuda 既有能力，Tensora 只写 `Backends/CudaBackend.sl`
（kernel 封装 + §5 staging 协议实现），Tensora.jsonc 增加
`references: { "path": "../Cuda", "name": "SLangCuda" }`
（模块引用写法与现有一致，遵循 spm type=module 条目规约）。

**内核产出物**：PTX 文本（手写），`CudaKernel.fromPtx` JIT 加载
（Cuda.sl:935-949）。首批 opId 清单与参数布局（CudaKernelArgs 槽序）：

| opId | entry | 参数布局 | 对应 §5 能力 |
|---|---|---|---|
| EADD | t_add | dst, a, b, n（广播经下标映射，§5.2.6） | add |
| ESUB/EMUL/EDIV | 同构 | 同上 | sub/mul/div |
| ESCALE | t_scale | dst, a, k(f32), n | scale / scaleInPlace 原地版 |
| ERELU/ESIGMOID/ETANH/EEXP | t_unary | dst, a, n, op(i32) | 逐元素数学 |
| RSUM | t_sum | dst(1 槽), a, n（块内归约+原子加尾块） | sum |
| MMUL | t_mmul | dst, a, b, M, K, N（naive 分块起步） | matmul |
| SMAX | t_softmax | dst, a, rows, cols（行 max→exp→归一，Phase 2 三 kernel 版） | softmax |
| TFILL | t_fill | dst, value(f32), n | fillValue 设备版（§5.2.4） |
| （无 kernel） | — | `libMemcpyD2D`（Cuda.sl:178-180） | 同设备 clone/copyFrom |
| （无 kernel） | — | `CudaBuffer.memset8`（Cuda.sl:625-631） | zero 设备版 |

**PTX 示例骨架**（t_add，一维 grid-stride，逐条遵循已验证教训）：

```
.visible .entry t_add(
    .param .u64 dst, .param .u64 a, .param .u64 b, .param .u32 n)
{
    // gid 必须含块偏移：%ctaid.x * %ntid.x + %tid.x（缺此公式的已踩坑记录）
    // 每线程循环 stride = gridDim*blockDim 直至 >= n（尾部正确性已踩坑）
    // 浮点用 add.rn.f32 / mul.f32，与 CPU 参考 Float32 语义对齐
}
```

**已验证教训清单**（实现期强制核对，均来自项目记录）：
- gid 块偏移公式缺一不可，否则尾部元素结果为 0；
- JIT 错误码 218 双语义（JIT dll 未加载 **或** PTX 语法/寄存器越界）；
- 加载 nvcuda.dll 前把 nvptxJitCompiler64.dll 的 DriverStore 目录加入
  进程 PATH；
- 计时事件 flags=0 创建（DISABLE_TIMING → elapsedMs=-1）；
- nvcuda.dll 仅导出无 `_v2` 的 cuDevicePrimaryCtxRetain；
- C 端返回 0=成功，SL 判 0=false → 统一 `ok(rc)` 出口。

**验收**：首批 12 opId + 2 库级原语与 CPU 参考实现按位一致（§8）；
§5.7 分段基准落盘。

### 6.3 ROCm 后端（Phase 3）

- 桥模块 `SLangRocm`：`sl_rocm_lib.dll`（前缀 `slr_`）运行期解析
  amdhip64（HIP 运行库），导出面与 slc_* **逐一同构**（device/buf/stream/
  event/module/kernel/launch + §6.0-5 全部传值原语），SL 绑定类
  RocmBuffer/RocmKernel… 与 Cuda.sl 镜像，Tensora 侧 `Backends/RocmBackend.sl`
  仅换路由目标；
- **内核产出物不同**：HIP 无 PTX 等价的跨代 JIT，kernel 用 hipcc 离线编译
  为 code object（.co），构建期产出入库，运行期 `hipModuleLoadData` 加载
  （对应 CUDA `slc_module_load_data`，vm_sl_cuda.h:190）。即：**CUDA 走
  运行期 JIT，ROCm 走构建期编译**，kernel 源（SL 侧 PTX 字符串 vs 构建期
  .cuh 编译产物）不共享——归一方案列入 OQ-4；
- 平台事实（如实陈述，不扩大承诺）：HIP Windows 官方仅支持部分 RDNA3
  消费卡且为预览性质；Linux 为第一目标平台。CI 无 AMD 卡时该阶段验收以
  Linux 实机为准，`Backends.available(ERocm)` 返回 false 走 D4 报错路径。

### 6.4 NPU 后端（Phase 4，插件规约）

- 首选参考通路：昇腾 ACL（aclrtMalloc/aclrtMemcpy + aclop 单算子下发或
  AscendC 离线算子），封装为 `sl_npu_acl_lib.dll`（前缀 `sln_`）；
- §6.0-5 传值原语在 ACL 的映射：alloc→aclrtMalloc、upload/download→
  aclrtMemcpy（H2D/D2H 方向参数）、memset→aclrtMemset、peek→
  aclrtMemcpy(device→device)；
- 平台事实：CANN 运行时面向 Linux，Windows 无官方 ACL → 本后端 Linux-only；
- **厂商中立插件规约**：任何 NPU 厂商实现 §6.0 全部条目 + §6.0-5 三个
  最小传值能力即可注册为 `ENpu` 后端，Tensora 不绑定具体厂商 SDK；
- 前置条件：CI/开发环境有可访问的 NPU 硬件与厂商驱动，否则本阶段不启动
  （不写无法验证的代码——项目规约：未验证假设一律不落库）。

### 6.5 TPU 及其他加速器（Phase 5）

- 归类为"编译型厂商 SDK"后端：算子经厂商工具链（如算能 TPU-MLIR/BMLang）
  离线编译为模型/算子镜像，运行期经厂商运行库（bmlib 等）加载执行；
- 接入仍走 §6.0 规约（LoadLibrary 解析 + Int64 句柄 + 原生块搬运）；
- 同 6.4 前置条件：目标硬件可访问。

### 6.6 跨平台支持矩阵

| 后端 | Windows | Linux | 说明 |
|---|---|---|---|
| CPU L0（SL 参考实现） | ✅（已有，TensoraTest 8 套件） | ✅（AOT 管线已含 Linux） | 黄金基准 |
| CPU L1（SIMD 加速层） | ✅ P2B（SSE2 保底；AVX2/AVX-512 运行期检测） | ✅ P2B（x64 同左；ARM64 NEON 基线） | 仅计算密集算子，阈值分派（§6.1.3） |
| CUDA | ✅ Phase 2 | ✅ Phase 2 | nvcuda 随驱动分发 |
| ROCm | ⚠️ 部分 RDNA3 预览 | ✅ Phase 3 | 首选 Linux |
| NPU(昇腾) | ❌ 无官方运行时 | ✅ Phase 4 | 需实机 |
| TPU | 视厂商 | 视厂商 | 需实机 |

---

## 7. SL 语言与工程约束清单（实现期防坑）

以下均为项目已实证的约束，代码评审逐条过：

1. 实例成员访问必须 `this.` 前缀，静态成员可裸写；
2. 方法名禁用 get/set/as/data/label/half 等保留字（会被解析为特殊语法）；
3. 数组下标不能直接用成员访问链，必须先赋局部变量
   （如 `int d0 = s.dims[0]` 再用）；
4. if 条件的 `||` 链最多 2 个运算符；
5. 类级 const 必须 `static const`，否则运行期取值无效；
6. 枚举成员逐成员显式赋值（未赋值默认全 0）；
7. 跨 namespace 引用必须显式 import；方法签名必须单行
   （Cuda.sl:953 注释实证：跨行参数表会把续行当独立语句）；
8. 多行文本仅识别 `"""` 三引号（PTX 字符串必须用此风格嵌入）；
9. FFI 布尔语义与 C 端返回值严格对应，禁止语义倒置；
10. DLL 公开导出必须显式 `__declspec(dllexport)`；
11. 手写常量表（GLATTR/CUdevice_attribute 等）逐值核对官方头文件；
12. 新增 jsonc 开关一律默认关闭，显式开启才生效（D4 的 fallback 开关、
    各后端 enabled 开关、managed 对照开关均遵守）；
13. §5.2 传值原语之外**禁止**算子实现内私拼 Memory 块直接调 memcpy（D6），
    保证状态机可推理；
14. 释放路径（freeDevice/uploadFlow 失败分支）必须无泄漏，原生块
    free 置零防双 free。

---

## 8. 测试与验收

1. **状态机单元断言**：BackendRegistry 测试对 §5.1 四不变式（I1-I4）
   与状态转换表逐条断言（构造 S0/S1/S2 张量，验证各钩子行为）；
2. **一致性（核心验收，按 D5 分级）**：新测试套 `BackendTest.sl` 加入
   TensoraTest 项目；每个算子跑同一随机输入（Rng.withSeed 固定种子，
   Random.sl 可复现），CPU 结果与各后端（GPU / CPU-L1）结果按 §6.1.4
   分级判定——Tier-1 用**逐位相等断言**（`TensorMath.isClose` 不适用于
   验收判定），Tier-2 用 ULP 级容差并标注等级；输出 PASS/FAIL 计数行；
3. **传值分段基准**：§5.7 方案执行，数据落盘
   `out/tensora/h2d_bench.txt`，作为 OQ-1 判定依据；
4. **回归**：现有 8 个测试套（TensorTest/AutogradTest/CnnTest/NnTest/
   ClassicMlTest/DataTest/TtsTest/TransformerModelTest）在每次 Tensora
   重建后全量通过——Tensor 方法签名不变（D1）保证零迁移；
5. **基准**：matmul/softmax/sum 记录 CPU vs CUDA 耗时
   （`CudaEvent.createTiming` + `elapsedMs`，flags=0；CPU 侧用
   现有 BenchMark 项目模式），数据落 `out/` 目录文本，不做无实测的估算；
6. **环境**：release 包运行，不跑 wasm（用户约束）；
7. **每阶段验收标准见 §9**。

---

## 9. 实施阶段计划

| 阶段 | 内容 | 交付物 | 验收标准 |
|---|---|---|---|
| P0（本文档） | 架构设计定稿 | TensoraBackend.md | 评审通过 |
| P1 CPU 补齐 | EDtype/Dtype.sl；Tensor 设备字段（默认 CPU 不动行为）；Device 激活 + backendKind；§2.5 缺口表 CPU 算子分批补齐（索引/比较/归约泛化优先）；BackendRegistry 骨架 + §5.1 状态机（CPU 路径下 I1-I4 恒成立即可测试） | Dtype.sl/Device.sl 改造/Backends 目录/扩 TensorTest | TensoraTest 全绿（含状态机断言）；现有 8 套件零回归 |
| P2 CUDA | Tensora 引用 SLangCuda；§5 传值协议全量实现（uploadFlow/downloadFlow/读迫同步/设备原地/显存记账与释放）；首批 12 opId PTX kernel + CudaBackend.sl；§5.7 分段基准；jsonc 开关 tensoraCudaEnabled（默认关） | CudaBackend.sl + kernel 表 + BackendTest + h2d_bench.txt | 12 算子位级一致；状态机 I1-I4 断言全过；matmul ≥1024² 在本机 GPU 显著快于 CPU（实测数据落盘） |
| P2B CPU SIMD（可与 P2 并行） | SLangCpu 桥模块（sl_cpu_lib.dll：SSE2/AVX2/AVX-512/NEON 四路 kernel + cpuid 检测 + 函数表分派，§6.1.1-6.1.2）；Tier-1 首批 kernel：matmul/sum/softmax/conv2d（§6.1.3 清单，elementwise 不做）；阈值分派表实测写入（§5.7-5）；jsonc tensoraSimdEnabled / tensoraFmaEnabled 默认关 | SLangCpu 模块 + CpuAccelerator.sl + 阈值表 + slcp 一致性测试 | Tier-1 位级一致全过（三档 ISA 同输入同结果）；matmul ≥1024² 较 L0 净加速实测落盘（计入 staging 成本） |
| P3 ROCm | SLangRocm 桥模块 + RocmBackend.sl + hipcc 产物管线 | sl_rocm_lib.dll + 镜像 SL 绑定 | Linux 实机 12 算子位级一致 |
| P4 NPU | ACL 通路（Linux）+ 厂商中立插件规约文档化 | sl_npu_acl_lib（或厂商实现） | 昇腾实机首批算子一致 |
| P5 TPU/其他 | 厂商 SDK 通路按规约接入 | 同上 | 目标实机验收 |

依赖关系：P2 依赖 P1 的 dtype/device/registry/状态机；P3-P5 互相独立，可按
硬件可用性调序。每阶段结束同步重建 Tensora 模块分发件（zip 与编译产物
一致，防"本地分发件过期"教训）。

---

## 10. 风险与开放问题

| 编号 | 问题 | 影响 | 处置 |
|---|---|---|---|
| OQ-1 | SL Array 无裸指针出口，H2D/D2H 三段式每元素循环搬运（P1/P4） | 大张量传输瓶颈 | §5.7 分段基准先实测；P1+P4 > 50% 才立项 cvm SystemArrayPin 系统调用（走 systemCalls 通道，D3 的唯一例外触发条件） |
| OQ-2 | SL Array 不共享底层存储 → reshape 恒复制、无法实现 PyTorch view 零拷贝 | 内存翻倍场景受限 | v1 明确文档化"无 view"；张量存储结构改造（data 指向共享块 + offset）列为长期项，需 cvm 层配合 |
| OQ-3 | SL Float16/Float16_Brain 的算术运算语义（运算符/精度行为）未验证 | f16/bf16 dtype 排期 | Phase 1 末补一个 Float16 运算验证用例后再排期 |
| OQ-4 | CUDA(PTX 源) 与 ROCm(.cuh 源) kernel 源码不共享 | 双份维护 | 评估构建期模板生成（同一算子描述生成两种后端源）；v1 接受双份 |
| OQ-5 | 昇腾/TPU 硬件在开发/CI 环境不可用 | P4/P5 无法验证 | 硬性前置条件（§6.4/§6.5），不满足不启动，不留假实现 |
| OQ-6 | HIP Windows 仅部分 RDNA3 预览支持 | Windows AMD 用户 | 矩阵如实标注（§6.6），Linux 为主平台 |
| OQ-7 | reduceAlong 等现有实现隐含 2D 假设（Tensor.sl:538-603 直接取 dims[0]/dims[1]） | 高维张量误用产生错误结果 | Phase 1 重写为任意轴归约时加入 rank 校验，防静默错值 |
| OQ-8 | SL 无析构钩子（§2.4-5 已验证），长期驻留进程的影子缓冲只能显式释放 | 显存泄漏依赖用户自觉 | v1 以 freeDevice 协议 + Module/Trainer 收尾收口；长期项：cvm 弱引用/回调钩子评估 |
| OQ-9 | 跨 GPU（cuda:0 × cuda:1）无 peer 传送原语（sl_cuda_lib 未封装 cuMemcpyPeer） | 多卡场景 v1 不可用 | v1 直接 BackendError；多卡需求出现时在 sl_cuda_lib 增补 slc_memcpy_peer 再设计 |
| OQ-10 | 异步（§5.5）引入"在途"状态后，读迫同步需事件等待链 | 状态机复杂度上升 | v2 前置：同步语义位级验收全绿 + 分段基准数据证明重叠收益，二者缺一不启动 |
| OQ-11 | FMA 融合与多核分块求和改变浮点结合语义，与位级一致铁律冲突 | 性能路径与一致性冲突 | 双轨制：融合/并行版独立函数 + 开关默认关（§6.1.4/§6.1.5），位级验收只约束默认路径 |
| OQ-12 | SL Mathf.sqrt/exp 等底层舍入行为未逐条核对（vsqrtps 是否与 Mathf.sqrt 逐位相同；Math 库实现源码未核对） | Tier-1/Tier-2 分级准确性 | P2B 实现前先写标量探针用例（sqrt/exp/log/tanh 逐个 vs SIMD 版比对）定级后再归 Tier |
| OQ-13 | BLAS（OpenBLAS，BSD-3 许可合规）接入的体积/构建代价 vs 手写 SIMD GEMM 性能上限 | 大矩阵 CPU 性能天花板 | §5.7/P2B 基准数据齐备后评估；v1 手写，不承诺接近 OpenBLAS |
| OQ-14 | AVX-512 在部分消费级机型存在降频（license/offset）争议 | AVX-512 实际收益不稳定 | 检测只认 F/VL/DQ 位齐全；§5.7-5 基准逐机型记录，收益为负的机型自动走 AVX2（函数表分派天然支持） |

---

## 附：PyTorch 语义对齐备忘

- `to(device)` 返回新张量，源不动（对齐 torch.Tensor.to）；Tensora 额外
  提供 `freeDevice()`/`cpu()` 的就地释放语义（SL 无 GC 弱引用，显式管理）；
- 读值触发设备→主机同步（对齐 torch 的隐式同步读：`.item()`/打印）；
- 设备算子产出驻留设备（对齐 torch：中间量留在 GPU，仅显式读值回传）；
- 广播规则对齐（从尾维对齐，1 可扩，不可广播报错——现有
  `broadcastShape` 返回 null 的行为改为抛错）；
- 跨设备运算报错（对齐 torch：`Expected all tensors to be on the same
  device`），不做隐式搬移；
- 后端不可用报错对齐 `torch.cuda.is_available()==false` 时的显式异常风格，
  不做隐式回落。
