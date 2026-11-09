# Cuda（SLangCuda 模块）库说明

- Project Entry File: `Cuda.sp`
- Project Config File: `Cuda.jsonc`
- 模块名（export.moduleName）：`SLangCuda` → 产物 `SlangAllInOne\out\export\SLangCuda\`

CUDA GPU 计算库（NVIDIA **驱动 API** 风味），namespace `SLang` 下七类：
`Cuda`（入口 + 原生绑定）/ `CudaDevice`（设备信息）/ `CudaBuffer`（设备内存）/
`CudaStream`（异步流）/ `CudaEvent`（事件计时）/ `CudaKernel`（PTX 内核）/
`CudaKernelArgs`（内核参数组装器）。
错误处理以返回值表达（null / false / 0），原因经 `Cuda.lastError()` /
`Cuda.errorString()` 取得，与 `SLangMysql` 同风格。

## 用法示例

```csharp
import Std;
import SLangCuda;

SLang.Cuda.initialize()                            # cuInit，幂等
SLang.CudaDevice dev = SLang.Cuda.device( 0 )      # 查询设备
Console.println( dev.toString() )                  # 名字 / cc / SM 数 / 显存
dev.makeCurrent()

# ── 设备内存 + 主机原生块搬运 ──────────────────────────────────
int n = 1024
SLang.CudaBuffer buf = SLang.CudaBuffer.alloc( n * 4 )   # 显存
Int64 host = Memory.allocArray( n, "f32" )               # 主机原生块
Memory.writeF32( host, 0, 1.5 )
buf.upload( host, n * 4 )                                # H2D
buf.download( host, n * 4 )                              # D2H
Console.println( Memory.readFloat32( host, 0 ).toString() )
buf.free()
Memory.free( host )

# ── PTX 内核启动（vec_add: out[i] = a[i] + b[i]）──────────────
SLang.CudaKernel k = SLang.CudaKernel.fromPtx( PTX_TEXT, "vec_add" )
SLang.CudaKernelArgs args = SLang.CudaKernelArgs( 4 )
args.addPtr( a.devicePointer() )
args.addPtr( b.devicePointer() )
args.addPtr( out.devicePointer() )
args.addI32( n )
k.launch1D( n, 256, null, args )                  # null = 默认流
SLang.Cuda.synchronize()
args.free()
k.destroy()
```

## 原生链路（FFI 静态绑定 + 驱动动态解析）

```
Cuda.sl ──@DllStaticImport(CallFFIStatic 77)──> sl_cuda_lib.dll
          ──运行期 LoadLibrary("nvcuda.dll")──> CUDA 驱动 API（cu*）
```

- `sl_cuda_lib.dll` 是驱动 API 的扁平 C ABI 包装（`slc_*`）：上下文 / 流 /
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
  `cuModuleLoadData(PTX)` 会报 218。`sl_cuda_lib.dll` 在加载 nvcuda 前
  自动把含该 DLL 的 DriverStore 目录补进**进程 PATH**（并按完整路径预载，
  双保险；仅改本进程环境，零系统侵入）。

jsonc `dllImports` 用**平铺 basename** 形态（`{ "path": "sl_cuda_lib.dll",
"static": "sl_cuda_lib" }`）：cvm 装载模块即预载该库并注册 FFI 静态绑定表，
绑定失败回退 SL 函数体兜底（`driverVersion() <= 0` 即兜底征兆）。FFI 运行期
按三重回退链定位：`pkg_dir/path` → `pkg_dir/<平台>/basename` →
`pkg_dir/basename`。

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

## 与 Tensora 的关系

`Tensora/Device.sl` 的 `EDeviceKind.GPU` 预留了设备抽象（"GPU 走后续后端
接入"）。本模块即 GPU 后端的第一块拼图：设备枚举 / 显存管理 / 内核启动。
后续 Tensora 算子可按 `Device.kind` 分派：CPU 走现有 SL 实现，GPU 走
`CudaBuffer` + 预编译 PTX（或 NVRTC 在线编译，待扩展 `slc_*` 符号）。

## 测试与集成

- 端到端用例集：`SlangAllInOne\SLangCore\test\Other\CudaTest\`
  （设备 / 显存 / 拷贝 / 流 / 事件 / vec_add 与 vec_scale 内核，说明见其
  `ProjectTest.md`）
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
