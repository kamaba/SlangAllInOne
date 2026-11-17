# C VM 虚拟机（csimple_lang）

> 项目定位：SLang 的**运行时**。装载 Front 产出的 SLIR 包，装配符号/方法，执行指令，承载 FFI/插件/协程/GC/调试。
> 源码根：`d:/project/lang/csimple_lang/src/`（入口 `main.c`）。
> 工程：`csimple_lang/project/vs/vm_lib/csimple_lang_lib.vcxproj`（→ P/Invoke dll）、`project/vs/vm_exe/...`（→ 独立 exe）；CMake 为主构建路径。
> ⚠ C VM 行为以**本项目 C 源码自身**为语义真源，不参考已废弃的 `simple_language/vm/VM.zip`（见根 `AGENTS.md` R1）。

---

## 1. 源码目录职责

| 目录 | 职责 | 关键文件（`src/` 下） |
|------|------|----------------------|
| 根 | 入口与全局定义 | `main.c`、`define.h`、`global.h`、`version.h` |
| `cli/` | 命令行解析、run 子命令、磁盘/内存运行入口、日志、应用载荷 | `cli.c`、`cli_command.c`、`cli_app_payload.c`、`cli.h` |
| `base/` | 基础数据结构/内存/字符串 | `mem.c`、`hash_map.c`、`posix/file.c` |
| `vm/load/` | SLB 解码、JSON 装载、引用递归、运行期 LoadModel | `slb_decoder.c`、`slir_json_module_loader.c`、`slir_runtime_loader.c` |
| `vm/parse/` | SLIR 模块解析、字符串池、模块注册表 | `slir_module_parse.c`、`sl_runtime_module_registry.c` |
| `vm/assembly/` | 程序集构建（类/方法/静态成员装配、CallVirt 绑定、DllStaticImport 重写、vmDll/FFI 预装载） | `sl_runtime_assembly.c`（核心，约 79KB）、`slir_assembly_data.c` |
| `vm/runtime/` | VM 核心（主循环、调用/帧栈、协程、属性、isolate、AOT、JIT 桥） | `vm_runtime.c`（约 222KB）、`call/runtime_call.c`、`call/vm_call_frame.c`、`coroutine/vm_coroutine.c`、`method/runtime_method.c`、`attribute/vm_runtime_attribute.c` |
| `vm/system_method_call/` | SystemMethod 实现与符号注册表 | `system_method_registry.c`、`ffi_system_method.c`、`coroutine_system_method.c` |
| `vm/memory/` | GC（标记-清扫）、TLSF/mimalloc/SBA 分配器 | `vm_gc.c`、`vm_memory.c`、`vm_tlsf.c` |
| `vm/debugger/` | SLDP 调试协议（TCP/NDJSON）、断点、求值 | `sl_debugger.c`、`sl_debugger_protocol.c`、`sl_debugger_breakpoints.c` |
| `vm/plugin/` `vm/platform/` `vm/jit/` | 插件宿主/管理器、平台需求检查、x64 JIT | `sl_plugin_manager.c`、`jit_manager.c`、`jit_entry.c` |
| `lib/ffi/` | FFI 核心（库管理、调用计划、回调桩） | `sl_ffi_lib_manager.c`、`sl_ffi_call.c`、`sl_ffi_callback_stubs.c` |
| `lib/os/` `lib/io/` `lib/thread/` `lib/time/` `lib/jit/` `lib/cjson/` | 系统 NOS / 控制台 / 线程 / 时间 / JIT 内存 / JSON | `sys_net.c`、`console.c` 等 |
| `core/` | 内建 SystemCall（编码/压缩/哈希） | `sl_core_encoding.c`、`sl_core_zlib.c` |

---

## 2. 生命周期（浓缩）

完整时间序见 [02-虚拟机生命周期](02-虚拟机生命周期.md)。主干：

```
main → cli_main（init_platform / 分派 / 日志）
     → cli_cmd_run | run_memory | run_memory_binary
     → run_vm_with_load_model   ★ 汇聚点（cli_command.c:326）
         ├─ 装载：slir_json_load_package / sl_load_references（引用 4 级探测）
         ├─ 装配：vm_set_runtime_load_model → sl_runtime_assembly_build_from_load_model
         ├─ 初始化：入口定位 + 内联字节码 + 静态成员
         ├─ 执行：vm_create → vm_initialize → vm_run（while is_running + opcode 分派）
         ├─ 副线：协程调度 vm_scheduler_enter / GC vm_gc_collect / SLDP 调试
         └─ 销毁：debugger_close → attribute_exit → isolate_shutdown → vm_destroy
```

---

## 3. 三条外部函数通道

| 通道 | 声明来源 | 装配期铺路 | 执行期分派 |
|------|---------|-----------|-----------|
| systemCalls 注册表 | `systemCalls[].cvmFunction` | `sl_runtime_assembly_register_system_calls`（`:899`）→ `vm_system_func_dynamic_register`（`system_method_registry.c:703`）；失败留 NULL 占位，调用期惰性重解析 | `CallSystemMethod`（`vm_runtime.c:3451`）按 ID 取函数指针 |
| vmDll 预装载 | `vmDlls[]` | `vm_system_func_preload_ext_lib`（`system_method_registry.c:230`）LoadLibrary 进 ext-lib 缓存 | 供 `DllName!symbol` 形式解析 |
| FFI | `dllImports[].static` / `@DllImport` | `vm_sys_ffi_static_lib_register`（`ffi_system_method.c:777`）→ `sl_ffi_lib_load`；`@DllStaticImport` 重写为 `CallFFIStatic` | 静态：`CallFFIStatic`（`:4181`）静态绑定表直调；动态：`SystemFFICall* → sl_ffi_call`（`sl_ffi_call.c:582`） |

- C 库导出宏 `SLR_API`（`SlangAllInOne/SLangCore/Lib/SLang/Render/cvm_render_lib/vm_sl_render.h`，Windows `__declspec(dllexport)`），导出 `slr_*` 函数。
- ⚠ 实战坑：C 导出函数必须在头文件声明表登记（漏登记 = dll 无符号 = FFI 静默返回 false；用 `dumpbin /exports` 验证）；多参数 FFI（>5）需拆分导出。

---

## 4. 主循环与分派

`vm_run(VM*)`（`vm_runtime.c:1978`）主循环 `while (vm->is_running)`：epoch 缓存/JIT 接管点，隐式 Ret = `vm_execute_return()`。

opcode 分派（均在 `vm_runtime.c`）：`CallSystemMethod`(:3451) / `CallStatic`(:3547) / `CallDynamic`(:3686，含 for-in 快路径 `SLVM_FAST_FORIN`) / `CallVirt`(:3949) / `CallFFIStatic`(:4181) / `CallAtSignLabel`(:4326) / `CallClosure`(:6264)。调用辅助 `vm_execute_method_by_id`（`runtime_call.c:918`），帧管理 `vm_call_frame.c`。

---

## 5. 协程 / GC / 调试

- **协程**：`vm_scheduler_enter`（`vm_coroutine.c:1023`，根协程 + ready/timer 队列排空）为唯一调度驱动点；主循环经 epoch 失效处理切换/续跑。
- **GC**：`vm_gc_collect`（`vm_gc.c:1019`），根标记覆盖 stack/coroutine/channel/manual roots；`vm_gc_state_destroy` 于销毁阶段调用。
- **SLDP 调试**：`--debug-server` 开启 `sl_debugger_session_open`（TCP 阻塞握手），运行中 `sl_debugger_pump_step` 处理断点/单步/evaluate；**启用时禁用 JIT**。`--debug` 是 verbose 跟踪（不同通道）。

---

## 6. FFI 原生库样例：sl_render_lib

以渲染库说明「原生库如何被 VM 加载」（证据最完整的样例）：

1. 声明（`SlangAllInOne/SLangCore/Lib/SLang/Render/SLangRender/Render.jsonc`）：`dllImports`（`sl_render_lib.dll`，static）+ `vmDlls`（MSBuild 编译 `cvm_sl_render_lib.vcxproj`）+ `systemCalls: []`（能力全走 `@DllStaticImport`）。
2. 装配期 `vm_sys_ffi_static_lib_register("sl_render_lib", ...)` → `sl_ffi_lib_load` 注册进 `FFI.StaticLibrary`；`@DllStaticImport` 重写为 `CallFFIStatic`。
3. 执行期 `CallFFIStatic` → 静态绑定表 → `slr_*` C 函数（`SLR_API` 导出）。
4. C 实现 `cvm_render_lib/sl_render_lib.c`（13 段渲染管线）+ `RHI/` 多后端（`sl_rhi_gl.c` / `sl_rhi_d3d11.cpp` / `sl_rhi_vk.cpp` / `sl_rhi_gles.c`），`slr_init_backend("gl|d3d11|vk|gles")` 选择后端；绑定失败回退 SL 函数体（`initialize()==false` 为征兆）。

---

## 7. 构建要点

- 主构建：`powershell -File scripts/build-vm-win.ps1 -Config Release`（CMake + MSVC/Ninja）。
- ⚠ **版本 bump 后必须 `--clean-first` 全量重编**：中文版 MSVC `/showIncludes` 前缀不被 Ninja deps 过滤，`.ninja_deps` 不记头依赖，增量构建会产出「缝合怪」二进制（banner 与 Version 不一致）。Release 树同样适用。验收锚点：包内 `bin/csimple_lang.exe version` 两行版本一致。
- 版本锚点：`src/cli/cli_version.h`（`SLVM_VERSION_*`），另同步根 `CMakeLists.txt` 的 `SLVM_VERSION_DIR` 与 vcxproj PostBuildEvent 的版本目录。
- 平台约束（根 `AGENTS.md` R3）：`src/vm/**` 禁平台代码；平台逻辑放 `src/lib/{os,time,thread,windows}/`。新增 `.c` 文件三处登记（R6）。

---

## 8. 关键文件索引

| 主题 | 文件（`csimple_lang/src/` 下） |
|------|------------------------------|
| 入口/CLI | `main.c`、`cli/cli.c`、`cli/cli_command.c`、`cli/cli_app_payload.c`、`cli/cli.h` |
| 装载 | `vm/load/slir_json_module_loader.c`、`vm/load/slb_decoder.c` |
| 装配 | `vm/assembly/sl_runtime_assembly.c` |
| 主循环/调用 | `vm/runtime/vm_runtime.c`、`vm/runtime/call/runtime_call.c`、`vm/runtime/call/vm_call_frame.c` |
| 系统方法 | `vm/system_method_call/system_method_registry.c`、`vm/system_method_call/ffi_system_method.c` |
| 协程/GC/调试 | `vm/runtime/coroutine/vm_coroutine.c`、`vm/memory/vm_gc.c`、`vm/debugger/sl_debugger.c` |
| FFI | `lib/ffi/sl_ffi_lib_manager.c`、`lib/ffi/sl_ffi_call.c`、`lib/ffi/sl_ffi_callback_stubs.c` |
