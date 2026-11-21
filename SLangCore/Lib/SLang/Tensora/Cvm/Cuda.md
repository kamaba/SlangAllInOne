# Cuda（cvm 的 NVIDIA GPU 平台）库说明

- 属于 Tensora 模块（`Lib\SLang\Tensora\Tensora.jsonc`），SL 层 `Cvm\Cuda.sl`
- 原生层：`Cvm\cvm_sl_tensora_lib\cvm_sl_tensora_lib.vcxproj` 合一工程的
  CUDA 部分（`sl_cuda_lib.c` / `vm_sl_cuda.h`），产物 `sl_tensora_lib.dll`
  随 `out\export\Tensora\` 分发（Tensora.jsonc vmDlls 构建 / dllImports 预载）
- 自原独立模块 SLangCuda（`Lib\SLang\Cuda\`，已删除）整编而来：七类 API
  原样保留，namespace 由 `SLang` 改为 `Tensora`

CUDA GPU 计算库（NVIDIA **驱动 API** 风味），namespace `Tensora` 下七类：
`Cuda`（入口 + 原生绑定）/ `CudaDevice`（设备信息）/ `CudaBuffer`（设备内存）/
`CudaStream`（异步流）/ `CudaEvent`（事件计时）/ `CudaKernel`（PTX 内核）/
`CudaKernelArgs`（内核参数组装器）。
错误处理以返回值表达（null / false / 0），原因经 `Cuda.lastError()` /
`Cuda.errorString()` 取得，与 `SLangMysql` 同风格。

## 用法示例

```csharp
import Std;
import Tensora;

Tensora.Cuda.initialize()                            # cuInit，幂等
Tensora.CudaDevice dev = Tensora.Cuda.device( 0 )    # 查询设备
Console.println( dev.toString() )                    # 名字 / cc / SM 数 / 显存
dev.makeCurrent()

# ── 设备内存 + 主机原生块搬运 ──────────────────────────────────
int n = 1024
Tensora.CudaBuffer buf = Tensora.CudaBuffer.alloc( n * 4 )   # 显存
Int64 host = Memory.allocArray( n, "f32" )                   # 主机原生块
Memory.writeF32( host, 0, 1.5 )
buf.upload( host, n * 4 )                                    # H2D
buf.download( host, n * 4 )                                  # D2H
Console.println( Memory.readFloat32( host, 0 ).toString() )
buf.free()
Memory.free( host )

# ── PTX 内核启动（vec_add: out[i] = a[i] + b[i]）──────────────
Tensora.CudaKernel k = Tensora.CudaKernel.fromPtx( PTX_TEXT, "vec_add" )
Tensora.CudaKernelArgs args = Tensora.CudaKernelArgs( 4 )
args.addPtr( a.devicePointer() )
args.addPtr( b.devicePointer() )
args.addPtr( out.devicePointer() )
args.addI32( n )
k.launch1D( n, 256, null, args )                    # null = 默认流
Tensora.Cuda.synchronize()
args.free()
k.destroy()
```

## 原生链路（FFI 静态绑定 + 驱动动态解析）

```
Cvm\Cuda.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_tensora_lib.dll（slc_*）
              ──运行期 LoadLibrary("nvcuda.dll")──> CUDA 驱动 API（cu*）
```

- `sl_tensora_lib.dll` 的 CUDA 部分（`slc_*`）是驱动 API 的扁平 C ABI 包装：
  上下文 / 流 /
  事件 / 模块 / 内核句柄一律收敛为 Int64，`CUdeviceptr` 以 Int64 位模式承载。
- **零 CUDA-Toolkit 依赖**：`nvcuda.dll` 随 NVIDIA 显卡驱动安装于 System32，
  构建期（MSBuild，无 cuda.h / 无 .lib）与运行期都不需要装 Toolkit；
  只装了 N 卡驱动的机器即可用。
- 主机大块数据不走 FFI 传值：先经 Core 的 `Memory.alloc / writeF32 / allocArray`
  组原生块，`upload / download` 以 `ptr` 整块搬运（含 `xxxAsync` 流式版）。
- 上下文隐式建立：首个需要上下文的调用自动 retain 默认设备（`setDevice` 可
  切换，初始 0 号）的 primary context 并置为当前，与 Runtime API 行为对齐。
- 内核走 **PTX JIT**：`CudaKernel.fromPtx(ptxText, entryName)` → 驱动即时
  编译；启动参数经 `CudaKernelArgs` 组装（每参 8 字节值槽 + 指针数组），
  参数宽度由内核签名决定，驱动按签名读取。
- **PTX JIT 编译器定位**（R570+ 驱动实测）：新驱动把 JIT 从 nvcuda.dll 拆分
  为独立的 `nvptxJitCompiler64.dll`，且部分驱动包只把它放在
  `DriverStore\FileRepository\<驱动包>\` 而不落 System32——直接裸调
  `cuModuleLoadData(PTX)` 会报 218。`sl_tensora_lib.dll` 在加载 nvcuda 前
  自动把含该 DLL 的 DriverStore 目录补进**进程 PATH**（并按完整路径预载，
  双保险；仅改本进程环境，零系统侵入）。

Tensora.jsonc `dllImports` 用**平铺 basename** 形态（`{ "path":
"sl_tensora_lib.dll", "static": "sl_tensora_lib" }`，CPU/CUDA 合一库）：cvm
装载模块即预载该库并注册 FFI 静态绑定表，绑定失败回退 SL 函数体兜底
（`driverVersion() <= 0` 即兜底征兆）。FFI 运行期按三重回退链定位：
`pkg_dir/path` → `pkg_dir/<平台>/basename` → `pkg_dir/basename`。

## PTX 编写要点（实测，驱动 13.3 / RTX 2080 sm_75）

- `.version` 窗口：本机驱动接受 PTX ISA **7.0–9.0**；≥10.0 报 222
  （`CUDA_ERROR_UNSUPPORTED_PTX_VERSION`）。推荐写 8.0。
- 218 = `CUDA_ERROR_INVALID_PTX`（"a PTX JIT compilation failed"）——
  既是 JIT 库定位失败的报错，也是 PTX 自身编译错的报错，排查时先分清
  （最小 `ret;` 内核能过 = JIT 链路 OK，问题在 PTX 文本）。
- 寄存器组按 `<N>` 声明 **N 个**（`%f<3>` = %f0..%f2），用越界寄存器
  （如 %f3）是 218 的常见来源。
- 多 block 启动时全局线程号必须自行计算：
  `gid = %ctaid.x * %ntid.x + %tid.x`，只取 `%tid.x` 时每个 block 都只写
  自己那一段的前 N 个元素。
- **f64/s64 域指令链触发 JIT 失败（驱动 13.3 实测，P2A 排查记录）**：
  `cvt.rn.f64.f32` 单条即挂（去 `.rn` 写 `cvt.f64.f32` 可过），但
  `mul.rn.f64`/`cvt.rni.s64.f64` 等 f64 域组合仍有未定位的第二触发点
  （微 kernel 二分见 CudaBackendTest 探针记录）。**结论：GPU kernel 内
  避开 f64 域**——超越函数用 `__expf` 同构实现（`mul.rn.f32 x·log2e` +
  `ex2.approx.f32`，见 CudaBackend.sl ptxExp），f32 域 `.rn` 后缀无碍。
- **参数表末参后不可带逗号**：`.param .u32 n,\n)` 是 218 的来源之一
  （CudaBackend 首轮 10 kernel 全挂的共同根因）；SL 侧生成 PTX 时
  行尾逗号与 `)` 分行写。

## 与 Tensora 的关系

本文件即 cvm 平台的 GPU 部分。**P2A 已接入算子层**：
`Tensora\Backends\CudaBackend.sl` 在 CudaBuffer/CudaKernel 之上实现
TensoraBackend.md §6.2 的首批 kernel 表（10 个 PTX entry / 13 opId：
t_add/t_sub/t_mul/t_div/t_scale/t_unary/t_sum/t_mmul/t_smx/t_fill
+ D2D/memset 库级原语）与 §5 staging 协议（uploadFlow/downloadFlow/
stageOut/分配预检记账）；Tensor 算子（add/sub/mul/div/scale/matmul/
sum/exp/relu/sigmoid/tanh/softmax + 设备原地 zero/fillValue/
scaleInPlace/clone/copyFrom）按驻留位置分派。算术类与 L0 逐位一致
（p 序标量累加、禁 fma），超越类（exp 系）按 1e-6 容差验收（__expf
同构实现）。端到端验证：`test\TensoraTest\CudaBackendTest.sl`
（48 项断言全过：I1-I4 状态机 / 记账 / 一致性 / 广播回落 / OQ-1）。

**OQ-1 已落地（§5.7 基准驱动）**：`CudaBackend.arrayDataPtr` 经
SystemPtrFromObject + SystemPtrReadInt64 直读 VMArray.data（偏移 48，
csimple_lang vm_array.h），DMA 直接消费 SL 数组裸缓冲——P1/P4 逐元素
循环全消（uploadInto/downloadFlow/to() 零复制，to() 出口 S2 懒填充）。
1024² matmul 全链 6.4s → 12ms（vs CPU SIMD 281x，位级一致；见
out\probe\h2d_bench.txt）。CPU 侧同受益：Cvm.pinF32 + Backends 四个
SIMD executor 零拷贝化。布局防漂移：CudaBackendTest 固化断言
data@48/length@32 + 位模式；GC 安全前提 = v1 全同步（v2 异步前须真 pin）。

**t_mmul 为 16×16 共享内存分块版**（naive 4.5s → 1ms，位级一致保持；
边界三坑见 CudaBackend.sl 注释：lim 取 min、越界线程不提前退出、
条件跳过不填 0）。

## 测试与集成

- 端到端用例集：`SlangAllInOne\SLangCore\test\Other\CudaTest\`
  （设备 / 显存 / 拷贝 / 流 / 事件 / vec_add 与 vec_scale 内核，已改为
  引用 Tensora 模块，说明见其 `ProjectTest.md`）
- 实测结果：`===== CudaTest end PASS=47 FAIL=0 =====`（RTX 2080 / 驱动 13.3）

## 已知取舍（v1）

- primary context 只 retain 不 release：SL 侧无析构钩子，泄漏仅为每卡一份
  引用，进程退出由驱动回收（见 `sl_cuda_lib.c` 注释）。
- `slc_stream_create / slc_event_create` 返回 0 可能是默认流语义，失败以
  `Cuda.lastError()` 是否非零分辨（每次原生入口先清粘性码）。
- 统一内存（`allocManaged`）在旧驱动 / 特定 WDDM 场景可能失败，错误码经
  `errorString()` 透出；常规路径用 `alloc` + `upload/download`。
- 事件计时是默认行为：`cuEventCreate(flags=0)` 即可配 `elapsedMs`；
  flags 0x2 是 `CU_EVENT_DISABLE_TIMING`，置位后计时事件会报 400
  （invalid resource handle）。`CudaEvent.createTiming()` 已按 0 创建。
- 设备上限 16 卡（`SLC_MAX_DEVICES`），超出的 ordinal 报参数错。
