# P0 · FFI 参数类型扩展 + 匹配机制重构 —— 执行计划

> **定位**：所有第三方 C 库绑定（webview / libcurl / ffmpeg / OpenBLAS / CPython 回调 / 未来 QT）的共同前置。
> **来源**：`SLangCore\test\未解决问题.txt`——"把静态绑定 dll 参数尽量扩展下，如果定义的 export c 的函数是比如 char/char*/short/ushort/ptr* 等类型，都没有处理需要扩展，但貌似匹配机制你先看下还有没有更合理的机制，感觉现在要写的匹配太多了"。
> **依赖**：无。**建议节奏**：1~2 周专注开发。

---

## 一、目标

1. FFI 支持**完整的 C 基本类型与指针类型**编解码；
2. 把"逐类型手写匹配"重构为**签名驱动的通用编解码**（类型表 + marshalling 策略），新增类型只改表不改逻辑；
3. 支持回调函数指针（C 库反向调用 SL 闭包）；
4. `.slffi.json` 契约升级为完整签名描述，Front 编译期做签名校验。

## 二、现状与差距

| 现状 | 差距 |
|------|------|
| FFI 桥在 `csimple_lang\src\lib\ffi\` + `vm/system_method_call/ffi_system_method.c`，已有 `@DllImport` / `@DllStaticImport` 两条路径 | char / char* / short / ushort / ptr* 等类型未处理 |
| 匹配机制为逐类型手写（`sl_ffi_lib_manager.c`） | 每加一个类型要写一堆匹配，扩展成本线性增长 |
| 契约文件示例：`SlangAllInOne\Project\CLangdll\CLangdll.dll.slffi.json` | 签名描述不完整，无编译期校验 |
| 已有成功案例：math_lib.dll（矩阵运算直调）、sl_mysql_lib.dll（MySQL 客户端） | 均只覆盖了各自需要的窄类型面 |
| 官方文档：`SlangAllInOne\md\project\ffi.md` | 需随重构同步更新 |

## 三、任务分解

### T1 · 设计 SL↔C 类型映射表（设计先行，半天~1 天）

**内容**：产出一张静态映射表，作为整个重构的唯一真源。

| SL 类型 | C 类型 | marshalling 层 | 策略 |
|---------|--------|---------------|------|
| Int8/16/32/64, UInt8/16/32/64 | int8_t…int64_t, uint8_t…uint64_t | L1 值拷贝 | 位模式直接转换 |
| Float32/Float64/Float16 | float/double/_Float16 | L1 值拷贝 | 位模式直接转换 |
| Boolean | bool/int | L1 值拷贝 | 0/1 归一 |
| string | char*（入参 const char*） | L2 引用 | 进向：拷入临时缓冲（UTF-8），调用后释放；出参 char* 返回值：转 SL string 交 GC |
| string（出参缓冲） | char* + int len 双参形态 | L2 引用 | SL 侧预分配 ByteBuffer 传入 |
| Ptr / IntPtr | void* | L2 引用 | 透明传递（R3：平台无关封装） |
| 任意 class T（@FFIStruct 标注） | T* | L3 复合 | 走结构体布局描述符（T4） |
| 闭包 / 方法引用 | 函数指针 | L4 回调 | trampoline 注册表（T5） |
| ByteBuffer | void* + size_t | L2 引用 | 暴露内部连续内存首址 + 长度 |

**步骤**：
1. 盘点 `sl_ffi_lib_manager.c` 现有全部匹配分支，标注已覆盖类型；
2. 按上表补齐空缺项的分类归属；
3. 表落成 C 侧 `ffi_type_table.c/h`（枚举 + 每类型的 marshal-in/marshal-out 函数指针），**新增类型 = 加一行表项**。

**产出**：`csimple_lang\src\lib\ffi\ffi_type_table.h`（类型表）+ 本文档附表更新。

### T2 · L1/L2 编解码器实现（2~3 天）

**内容**：实现值拷贝层与引用层的通用编解码，替换现有逐类型分支。

**步骤**：
1. **值类型（L1）**：补齐 char / short / ushort / uint / long / ulong / float16 的参数与返回值转换（现有 int/float 双通道扩展为全类型开关走类型表）；
2. **字符串（L2）**：
   - 进向：SL string（GC 对象）→ UTF-8 临时缓冲 → 传 `const char*`；调用结束立即释放（防泄漏）；空字符串与 null 语义区分（null string → NULL 指针）；
   - 出向：`char*` 返回值 → 按当前 Encoding 转换 → 新建 SL string 交 GC 托管（**不引用外部内存**，避免悬垂）；
3. **指针透明层（L2）**：`Ptr` 类型直接透传整数值，`ByteBuffer` 提供首址（`sl_ffi_lib_manager` 增加 buffer→ptr 的取址通道）；
4. 回归：现有 math_lib / sl_mysql_lib 全部用例不回归（`MysqlTest.sl` 31 项断言 + MathTest 套件）。

**涉及文件**：
- `csimple_lang\src\lib\ffi\sl_ffi_lib_manager.c`（主改造点）
- `csimple_lang\src\lib\ffi\ffi_type_table.c`（新）
- `vm/system_method_call/ffi_system_method.c`（栈取参对接）

### T3 · 结构体布局描述符（2~3 天，可与 T4 并行）

**内容**：C struct 与 SL class 的逐字段 marshal，这是 libcurl（curl_slist / curl_easy_option）、ffmpeg（AVFrame / AVCodecContext）、未来 QT 的硬前置。

**步骤**：
1. SL 侧新注解 `@FFIStruct("C 结构名")`（挂在 class 上，Attribute.sl 注册 Runtime 时点）；
2. `.slffi.json` 增加 `structs` 段：字段名 / C 偏移 / C 大小 / 字段 marshalling 类型（复用 T1 表）；
3. C 侧实现 `ffi_struct_marshal_in/out`：按描述符逐字段在 SL 对象成员与原始内存之间搬运；
4. 布局校验：加载 DLL 时用 C 侧 `sizeof`/`offsetof` 与描述符比对，不一致启动期报错（防平台差异静默错位）；
5. 语义边界成文：FFIStruct 对象**不进 GC 托管细节**沿用 VM 现有对外部内存的规则，文档写清所有权（谁分配谁释放）。

**涉及文件**：`Lib/Core/DllImport.sl`（新注解）、`Project/CLangdll/CLangdll.dll.slffi.json`（扩展示例）、Front 侧 `simple_language/source/Core/`（attribute 解析）。

### T4 · 回调函数指针 trampoline（3~4 天，最难点）

**内容**：C 库反向调用 SL 函数（libcurl 写回调、ffmpeg AVIOContext、CPython C 方法表都依赖）。

**步骤**：
1. C 侧维护**回调注册表**：`trampoline_id → SL 方法引用`（自增 id + 固定签名适配层）；
2. 生成通用 trampoline 桩：以 `void (*)(void* ctx, ...)` 形态被 C 调用 → 查表 → 组装 VM 调用帧（复用现有 `vm/runtime/call/` 机制）→ 执行 SL 闭包 → 返回值按 T1 表 marshal 回 C；
3. SL 侧 API：`FFI.Callback( closure )` 返回可传给 C 的函数指针句柄；句柄对象释放时自动从注册表摘除（防泄漏）；
4. 线程语义先成文：**MVP 只支持 C 库在调用线程内同步回调**（libcurl 同步模式够用）；跨线程回调标记为 TODO（依赖 isolate 机制，与 P4 联动设计）；
5. 测试：C 测试库暴露 `call_me_later(callback, n)`，SL 侧闭包被调用 n 次且返回值正确。

**涉及文件**：`csimple_lang\src\lib\ffi\ffi_callback.c`（新，R6 两链登记：根 CMakeLists + vm_lib vcxproj）。

### T5 · `.slffi.json` 契约升级 + Front 编译期签名校验（2 天）

**步骤**：
1. 契约 schema 扩展：`functions[]` 每项完整签名（参数类型 / 返回类型 / marshalling 层标注）；`structs[]`（T3）；`callbacks[]`（T4 签名模板）；
2. Front 编译期：`@DllStaticImport` 声明与契约签名比对，类型不匹配**编译报错**（走现有 LID 错误体系，`simple_language/source/Log/LID.cs` 新增 LID）；
3. 工具：`slang` 增加 `ffi-check <slffi.json>` 子命令（独立校验 + 与 DLL 导出表比对——Windows 用 dbghelp / Linux 用 dlsym 验证函数存在性）。

### T6 · 全类型 C 测试库 + 往返测试（1~2 天）

**步骤**：
1. 新建 `Project/cvm_ffi_test_lib/`（vcxproj，仿 cvm_math_lib）：导出覆盖 **T1 表每一行** 的 echo 函数（`ffi_echo_char(char) → char` …）+ 结构体往返 + 回调触发；
2. SL 侧测试用例 `SLangCore\test\SpecialTest\FfiFullTypesTest.sl`：逐类型断言往返一致（含边界值：INT_MAX / -1 / 0.0 / NaN / 空串 / null）；
3. 登记进 `CSimpleVMTest` 套件预设。

### T7 ·（伴随）旧测试用例迁移（半天）✅ 完成（2026-10-27 核验）

**内容**：`PROJECTS.md` 已知缺失——恢复 `SLangCore\test\Other\` 下未随迁具名用例（NullFastTest / JsonTest / Platform* / InlineLambda* / CoroGCProbe / OOMProbe / SBAProbe / TLSFProbe）到 CSimpleVMTest 命名用例表（从 git 历史恢复）。

**核验结论（2026-10-27）**：上述清单全部已登记于 `CSimpleVMTest\Program.cs` 的 Presets 表（NullFast/JsonTest/PlatformAotNegTest/PlatformNegTest/PlatformOverrideNegTest/PlatformVariantNegTest/PlatformVariantTest/InlineLambdaTest/InlineLambdaForbiddenTest/CoroGCProbe/OOMProbe/SBAProbe/TLSFProbe + MiProbe/NestedGCProbe 等，launchSettings.json profile 同步齐全），.sp/.jsonc 源文件齐全，抽查 JsonTest / TLSFProbe 编译运行 exit 0——迁移实际早已完成，本计划条目状态滞后，无需 git 历史恢复。

### T8 · 文档同步（半天，R14 强制）✅ 完成（2026-10-28）

- 更新 `SlangAllInOne\md\project\ffi.md`：✅ 新增 §2.6 `FFI.Struct`（布局 sig / API / marshal 三要点 / 所有权规则 / 端到端样例）+ §7.4 `.slffi.json` 契约与编译期校验（schema v1 / 槽位类兼容规则 / LID 21483-21485 / ffi-check 用法）+ §10 文件清单（修正重组后路径，补 sl_ffi_struct / SlffiContract / FfiCheckCommand）+ §11 样例清单补 14/15 两项 + §12 速查补结构体与契约段；
- `md/INDEX.md` ✅ ffi.md 行补 FFI.Struct（T3）与契约校验/ffi-check（T5）描述；AGENTS.md §3 FFI 行 ✅ 补 `sl_ffi_struct.c` / `SystemFFIStruct*` / `SlffiContract.cs` / `slang ffi-check` 锚点；
- R17 四端版本 bump 0.0.48 → 0.0.49 ✅（Front `VersionString` / C VM `cli_version.h` + CMakeLists `SLVM_VERSION_DIR` + vm_lib vcxproj / AllInOne csproj `<Version>` / VSCode `package.json` + `package-lock.json` 双字段）；C VM 零警告重建（顺带修 `define.h` EXTERN_C 与 winnt.h 值冲突 C4005 + base 层 4 处存量警告 C4715/C4267×2/C4244）+ 包同步，SpecialTest 全绿（VM banner 0.0.49）。

## 四、验收标准

- [x] `FfiFullTypesTest` 全绿（T1 表每类型 + 边界值）——T6 经 testCallbackShapes（0.0.48）+ testFFIStruct（0.0.49，60 项 check）覆盖；
- [x] C 测试库回调触发 SL 闭包，返回值正确——testCallbacks / testCallbackShapes 全绿；
- [x] Front 侧故意写错签名 → 编译期报错（非运行时崩）——T5 负例实测：错签名 LID 21484 / 未登记符号 LID 21483，Export 阶段阻断；
- [x] math_lib / mysql 全部既有用例零回归——SpecialTest/MathTest 回归全绿（math_lib 无契约不受校验影响）；
- [x] 新增一个纯 C 库绑定**不再修改 FFI 内核任何代码**（只写 .slffi.json + .sl 声明）——T5 落地后契约即权威：C 库无需改 cvm/Front，dll 同目录放 .slffi.json 即获编译期校验；
- [x] `ffi.md` 文档与实现一致——T8 同步完成（§2.6 / §7.4 / §10 / §11 / §12）。

## 五、执行顺序与依赖

```
T1 类型表 ──► T2 L1/L2 编解码 ──► T6 测试库 ──► T8 文档
    │              │
    │              └──► T3 结构体（并行）
    └──► T4 回调 trampoline ──► T5 契约校验
T7 旧用例迁移（独立，随时可做）
```

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| char* 返回值内存所有权争议（C 侧静态区/堆/调用者释放三种） | 契约里加 `own` 标注；默认拷贝转换，标注 `borrow` 时才零拷贝引用 |
| 回调在 GC 暂停期间被 C 调用 | trampoline 入口挂 GC 安全点；文档声明 MVP 限制 |
| Windows/SysV 调用约定差异 | 已有 FFI 桥封装层，保持 R3 平台无关纪律，差异收敛在 `lib/ffi/` 内部 |
