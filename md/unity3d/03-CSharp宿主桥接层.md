# 03 · C# 宿主桥接层（SlangUnityBridge）

> Unity C# 侧如何驱动 C VM 原生插件。封装 `csimple_lang_dll` 的宿主 API
> （`csimple_lang/src/cli/cli.h`、`csimple_lang/md/cli.md`），处理 P/Invoke / IL2CPP `extern "C"`、
> UTF-8 字符串、flags 与生命周期。

---

## 1. 宿主 API 速查（直接复用，不新写 VM 入口）

`csimple_lang_dll` 已导出两个进程内入口（`csimple_lang/md/cli.md` 宿主 API 段）：

| 导出函数 | 用途 |
|----------|------|
| `cli_main(int argc, char* argv[])` | 经典 argv 方式，等价命令行（`run`/`info`/`version`/`help`） |
| `cli_run_module_in_memory(const char* json_text, const char* base_dir, int flags, const char** program_args, int program_arg_count)` | **编译即运行**：直接收 SLIR 包 JSON 文本，跳过 module.json 写盘/读盘 |

本整合主用 `cli_run_module_in_memory`（内存链路，见 `01` §2.2）——Unity 侧拿 Front 编译出的 JSON 文本直接喂给 VM。

### flags（`SLVM_MEM_FLAG_*` 位或）
| flag | 值 | 等价 CLI 选项 |
|------|----|---------------|
| `SLVM_MEM_FLAG_NO_BANNER` | 0x01 | `--no-banner` |
| `SLVM_MEM_FLAG_QUIET` | 0x02 | `--quiet` |
| `SLVM_MEM_FLAG_DEBUG` | 0x04 | `--debug` |
| `SLVM_MEM_FLAG_FORCE_RUN` | 0x08 | `--force-run` |
| `SLVM_MEM_FLAG_STRICT_PLUGINS` | 0x10 | `--strict-plugins` |
| `SLVM_MEM_FLAG_TEST` | 0x20 | `--test`（占位） |

> **IL2CPP/iOS 强制关 JIT**：flags 不直接带 JIT 开关；JIT 经环境变量 `SL_JIT=0` 或 `--no-jit` 关（见 `08`）。dll 宿主无 CLI 通道时，`SL_JIT=0` 是关闭手段（`JIT_DESIGN.md` §6.1 规则 4）。

---

## 2. P/Invoke 声明（Mono / Editor / Development）

```csharp
// SlangUnityBridge.cs （伪代码，展示契约，非最终实现）
internal static class SlangNative
{
    const string Dll = "csimple_lang";

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    public static extern int cli_main(int argc, IntPtr argv);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    public static extern int cli_run_module_in_memory(
        IntPtr json_text,        // UTF-8 NUL 结尾，借用
        IntPtr base_dir,         // UTF-8 NUL 结尾，NULL/空回退 CWD
        int flags,
        IntPtr program_args,     // char** ，NULL 表示无
        int program_arg_count);
}
```

要点（对照 `csimple_lang/md/cli.md` 契约）：
- 字符串**借用、UTF-8、NUL 结尾**，调用期间须保持有效 → C# 侧用 `Marshal.StringToCoTaskMemUTF8` / `Encoding.UTF8.GetBytes` + `Marshal.AllocHGlobal` 组参（参照宿主 `SlangAllInOne` 的手动 UTF-8 + `Marshal.AllocHGlobal` 做法，`cli.md` 末段）。
- `base_dir`：SLIR 包内 `moduleReferences` / 插件 lib 相对它解析；`NULL` 回退 CWD。Unity 侧通常传 `Application.streamingAssetsPath` 或包内 `lib/` 目录。
- `program_args` / `program_arg_count`：`--` 后参数，填入 `Project._inputArgs`（同命令行）。
- 返回值：0 成功，非零失败（退出码同 `cli.md` 末表）。

---

## 3. IL2CPP 注意事项（Standalone / iOS / Android IL2CPP）

IL2CPP **不支持运行期反射式 P/Invoke 的动态解析**，但支持**静态 `DllImport` / `extern`**——
因此上面的 `[DllImport]` 在 IL2CPP 下**照常可用**（只要库名与平台文件名匹配）。

额外约束：
1. **JIT 必须关**（硬性，见 `08`）：IL2CPP/iOS 不能运行时生成代码，设 `SL_JIT=0`。
2. **字符串编码**：IL2CPP 下 `Marshal` UTF-8 行为一致，仍须显式 UTF-8（勿用 `string` 默认 ANSI 封送）。
3. **线程**：Unity 主线程调 VM 为主；若 SL 用协程/isolate 多线程（`vm_isolate.h` 1:1 OS 线程），需 `mono_thread_attach` 类比——但 Unity 不让原生线程随意调回 C#，故 Unity 回调（绑定层）应限制在**主线程**或显式 `UnitySynchronizationContext`（`05`/`06` 详述）。

---

## 4. 桥接层职责拆分

| 模块 | 职责 |
|------|------|
| `SlangUnityBridge` | 封装 `cli_run_module_in_memory`；管理 VM 实例句柄、flags、UTF-8 组参 |
| `SlangModuleLoader` | 装载 SLB / 内存 JSON；mtime 监视触发热重载（`04`） |
| `SlangHostCallbacks` | 把 Unity 引擎 API 注册为 VM 的 host function table（绑定层，`05`） |
| `SlangLifecycle` | 接 Unity `Awake/Start/Update/FixedUpdate/OnDestroy` 转发（`06`） |
| `SlangLogger` | 桥接 VM 日志到 `Debug.Log`（`07`） |

> **host function table 类比**：C VM 已有 `SLVmExtVm` / `SLPluginHost` 前缀镜像 ABI（`JIT_DESIGN.md` F9、`MONO_INTEGRATION_DESIGN.md` §4.3 的 V7/V8 host 字段）。Unity 桥接层应复用同一套 host 回调机制，让 SL 经 systemCall 调回 Unity C#。新增 host 字段**只能追加到结构体尾部**（F9 纪律），否则破坏 ABI 兼容。

---

## 5. 内存管理边界

- `json_text` / `base_dir` / `program_args` 由 C# 侧分配、**调用返回后即可释放**（VM 内部会拷贝所需数据）。
- VM 内部对象由 C VM 自己的 GC（手动内存 + 引用计数，`GC_DESIGN.md`）管理；跨边界 Unity 对象走绑定层 handle 表（`05` §6），**不**由 Unity GC 直接回收。
- 不要在托管侧长期持有裸 `IntPtr` 指向 VM 内部对象——只传不透明 id（类比 `MonoIntegration` 的 GCHandle 句柄表）。

---

## 6. 验收清单（本步交付判据）

- [ ] `SlangUnityBridge` 在 Unity Editor（Mono）下调 `cli_run_module_in_memory` 跑通一个最简 SL 模块，打印到 `Debug.Log`。
- [ ] IL2CPP Standalone 构建下同一桥接通过（无 P/Invoke 报错）。
- [ ] `SL_JIT=0` 环境变量在 IL2CPP 构建下生效，VM 走解释执行（`08` 联动）。
- [ ] UTF-8 中文模块名 / 字符串无乱码（R16）。
