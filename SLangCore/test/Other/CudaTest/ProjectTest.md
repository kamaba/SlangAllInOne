# CudaTest —— SLangCuda 端到端测试工程

对 `SlangAllInOne\SLangCore\Lib\SLang\Cuda\`（SLangCuda 模块，namespace `SLang`）
做真实环境验证：本机 NVIDIA GPU 上完成设备枚举、显存管理、主机↔设备拷贝、
流/事件、PTX JIT 内核启动（vec_add / vec_scale）与错误路径。

## 目录

```
test/Other/CudaTest/
├── ProjectTest.jsonc     # 工程配置（references 里引了 SLangCuda 模块）
├── ProjectTest.sp         # _main_ 入口：跑 CudaTest.fun()
├── CudaTest.sl           # 用例 T01~T47 + 两个 PTX 内核生成器
└── ProjectTest.md        # 本文档
```

## 编译

前置依赖（`references`）：

| 模块 | 说明 |
| --- | --- |
| `./lib/Core.module.slb` / `./lib/Std.module.slb` | 系统库（工程内落空自动回落官方库直查） |
| `out/export/SLangCuda/SLangCuda.module.json` | 被测库，未命中即报错中止 |

被测库 SLangCuda 需先编译一次（非系统库，compile-stdlib 三件套不覆盖）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Cuda\Cuda.sp --format binary+json --no-banner
```

再编译本工程（产物落 `SlangAllInOne\out\export\CudaTest\`）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\test\Other\CudaTest\ProjectTest --format binary+json --no-banner
```

## 运行（联合测试宿主）

```powershell
dotnet run --project SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- SlangAllInOne\SLangCore\test\Other\CudaTest\ProjectTest
```

宿主把产物 stage 进发布包 `<package>\CudaTest\` 并**联动拷贝引用模块
`SLangCuda\`**（`StageReferencedModules`），其中原生 DLL `sl_cuda_lib.dll`
由 `StageNativeDlls` 读模块 json `dllImports[].path` 自源导出树平铺补拷，
再经包内 `slang.exe` 执行。无 CUDA 设备的机器上：T04 后跳过、打印统计。

## 用例清单（T01~T47）

| 组 | 用例 | 覆盖点 |
| --- | --- | --- |
| 原生层 | T01~T03 | `initialize()` / `driverVersion` / `driverVersionText` 非 fallback，证明 `@DllStaticImport` 直调生效且 nvcuda 解析成功 |
| 设备 | T04~T13 | `deviceCount` / `device(0)` 属性（cc / SM / warp / 显存）/ `makeCurrent` / `currentDevice` |
| 显存余量 | T14~T16 | `memTotalBytes` / `memFreeBytes` |
| 设备内存 | T17~T25 | `CudaBuffer.alloc` / `upload` / `download` f32 往返 / `memset8` 0x05 填充 |
| 流 | T26~T30 | `CudaStream` 创建 / `uploadAsync` / `downloadAsync` / `synchronize` |
| 事件 | T31~T35 | 计时事件创建 / `record` / `sync` / `elapsedMs`（flags=0，见 Cuda.md 已知取舍） |
| PTX 内核 | T36~T40 | `fromPtx(vec_add)` JIT 加载 / `CudaKernelArgs` 4 参（3 指针 + i32）/ `launch1D` 多 block 全覆盖 `3*i` |
| PTX 内核 | T41~T44 | `vec_scale`（f32 标量参数）/ 首尾元素校验（多 block `gid` 正确性） |
| 错误路径 | T45~T46 | 坏 PTX 返回 null / `errorString()` 驱动原文（"a PTX JIT compilation failed"） |
| 清理 | T47 | buffer `isValid == false` after free |

两个 PTX 内核均为 `.version 8.0 / .target sm_75`，驱动侧 JIT 编译（见
Cuda.md「PTX 编写要点」：版本窗口、寄存器组、全局线程号 `gid =
%ctaid.x * %ntid.x + %tid.x`）。

## 实测结果

```
===== CudaTest end PASS=47 FAIL=0 =====
```

环境：NVIDIA GeForce RTX 2080（sm_75，46 SMs，8GB）/ 驱动 13.3（13030）。

## 关联

- 库说明：`SlangAllInOne\SLangCore\Lib\SLang\Cuda\Cuda.md`
- 原生层：`SlangAllInOne\SLangCore\Lib\SLang\Cuda\cvm_sl_cuda_lib\`
  （`sl_cuda_lib.c` / `vm_sl_cuda.h`，零 Toolkit 依赖，运行期解析
  nvcuda.dll 驱动 API；PTX JIT 编译器定位见 Cuda.md）

## 排查备忘（开发期踩坑实录）

| 现象 | 根因 |
| --- | --- |
| `driverVersion=0` 但 `deviceCount=1` | bool 语义反转：C 返回码 0=成功被 SL bool 当 false；`slc_*` 统一改 `ok(rc)` 出口 |
| 进程崩溃（T12 后 AV） | nvcuda 无 `cuDevicePrimaryCtxRetain_v2` 导出（只有无后缀名），解析失败置 `s_load_failed` 后仍解引用 NULL |
| PTX 报 218（连空内核都挂） | 驱动把 JIT 拆到 `nvptxJitCompiler64.dll` 且未落 System32；C 层先补进程 PATH（DriverStore）再加载 nvcuda |
| PTX 报 218（空内核过、vec_add 挂） | 测试内核寄存器越界：`%f<3>` 只声明 %f0..%f2 却用了 %f3（218 同时覆盖 JIT 缺失与 PTX 编译错，易混淆） |
| `out[4095]=0`（首块之后全 0） | 内核只取 `%tid.x` 没算块偏移，16 个 block 都写同一段；须 `gid = %ctaid.x * %ntid.x + %tid.x` |
| `elapsedMs=-1`（err 400） | 事件用 flags=0x2 创建——那是 `CU_EVENT_DISABLE_TIMING`；计时事件应 flags=0 |
| `errorString()` 返回 "success" | 句柄类失败路径没写粘性 `t_last`；`fail_h()` 统一透传后恢复驱动原文 |
