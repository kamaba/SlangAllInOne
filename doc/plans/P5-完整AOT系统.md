# P5 · 完整 AOT 系统（MLIR / LLVM 全链路）—— 执行计划

> **定位**：性能敏感场景（渲染 / Tensora 真实跑分 / 嵌入式 ESP32-P4）的基建。JIT 已默认开启（Release），日常性能够用，故不挡在若依 / spm 之前。
> **现状**：AOT Exporter 已有原型（`md/project/exporter.md`：IR → LLVM IR `.ll` 占位实现）；MLIR 工具链已随发布包分发（`bin\`：llc / mlir-opt / mlir-translate，csproj `PackMlirTools`）；`out\export\PlatformAotPosTest\` 可见 aot.ll / aot.mlir / aot.obj 产物链。
> **依赖**：三道 RFC 设计题定稿（T1–T3）。**节奏**：长线，M1 → M3 里程碑推进。

---

## 一、目标

1. 定稿三道核心设计题（hashCode / GC 边界 / MLIR struct 元信息）——来自 `未解决问题.txt`；
2. **M1**：单文件无依赖工程 → 独立原生 `.exe`；
3. **M2**：整库标准库可 AOT；
4. **M3**：AOT ↔ VM 混跑（jsonc `AOT / Mix / PureCVM` 三态）；
5. BenchMark 三方数据（AOT vs JIT vs 纯 VM）进官网。

## 二、三道 RFC 设计题（T1–T3，先定稿再动手）

### T1 · RFC：对象 hashCode 设计

**问题**（未解决问题.txt 原文）：AOT 中 LLVM 生成的数据转 VMObject 时需先查 VM 有无此对象；现用**指针做 hash**，跨边界（AOT 内存 ↔ VM 堆）不可靠。

**决策项**：
1. `Object.sl` 是否增加 `int _hashCode` 概念字段？
2. id 分配方：AOT 侧静态分配（编译期编入）vs VM 侧首见时分配（运行期注册表）；
3. 哈希表：VM 侧维护 `aot_id → VMObject` 全局映射，装载期建表。

**建议方案**：编译期为每个 AOT 结构体实例分配稳定 64 位 id（模块内唯一 + 模块哈希混合），`llvm.struct` 首字段携带；VM 侧 `sl_aot_object_registry` 查表，命中复用 / 未命中创建并登记。**禁止指针 hash**（ASLR/重定位下不稳定）。

**产出**：`csimple_lang\md\design\AOT_OBJECT_IDENTITY.md`（RFC 文档，含否决方案记录）。

### T2 · RFC：GC 托管边界

**问题**（未解决问题.txt 原文）：`sl_aot_skeleton_new_inner` 的 LLVM 侧对象是否复用转换类 member_data、且 VMObject 不进 GC 托管。

**决策项**：
1. **AOT 内存属 AOT，VM 内存属 VM**——分界线成文：
   - AOT 侧分配的对象（全局/静态/栈）由 AOT 代码自管（引用计/arena），VM GC **不扫不拖**；
   - VMObject 包装层（桥接对象）进 GC，但 finalize 只摘注册表条目、**不 free AOT 内存**；
2. member_data 复用规则：转换类共享同一 member_data 布局（避免双份拷贝），字段访问偏移由 T3 的 struct 描述符保证；
3. 循环引用边界：AOT 对象引用 VMObject 时（字段为 class 类型），VM GC 需可经描述符**穿透标记**——扫描回调注册给 GC（`vm_gc` 增加外来根扫描钩子）。

**产出**：`csimple_lang\md\design\AOT_GC_BOUNDARY.md`。

### T3 · RFC：MLIR struct 元信息

**问题**（未解决问题.txt 原文）：class / data / enum → `llvm.struct` 转换时要带类 id、名称；模板类成员转指针（Int64）+ 描述字段。

**设计**：

```
%sl.class.<Name> = llvm.struct <
    i64  classId,          # 类 id（T1 稳定 id）
    i8*  className,        # 名称字符串（静态区）
    i32  flags,            # class/data/enum/template 标志位
    i64  templateMeta,     # 模板元信息指针（非模板 = 0）
    ... 实际字段            # member_data 布局
>
```

**要点**：
1. Front 侧 MLIR 发射器（`simple_language/source/Export/MLIR/`，参照 `MLIR_AOT_实现与待办.md`）在 struct 转换时注入头部四元组；
2. VM 装配期（`vm/runtime/aot/`）经头部反查类型（id → 类型表 → runtime_type_manager 注册）；
3. 模板实例：templateMeta 指向模板参数描述（成员类型 id 数组），支持 `List<Int32>` / `List<String>` 区分；
4. **非模板类零开销原则**：flags 标注后，纯数据场景可发射无头紧凑布局（描述符外置 side-table）——性能敏感路径不背元信息包袱（编译开关控制）。

**产出**：`csimple_lang\md\design\AOT_MLIR_STRUCT_META.md` + MLIR 方言 `.td` 定义。

### T0 · RFC 评审关卡

三份 RFC 写完统一评审（自评审 + AI 交叉审），**定稿前不写实现代码**（避免返工——历史教训：AOT 曾多次推倒）。

## 三、里程碑实现

### M1 · 单文件独立 exe（2~3 周）

**范围**：无外部引用的工程（纯语言特性 + Print）→ `.ll` → `llc` → 链接 → 独立可执行。

**步骤**：
1. **IR 全指令降级覆盖**：现 exporter 只降级了部分指令（exporter.md 自述"占位 + 小函数"）——按 `IROpEnum.cs` 全集逐项补 LLVM IR 发射（算术/比较/跳转/调用/对象创建走 runtime intrinsic）；
2. **运行时 intrinsic 层**：AOT 侧对象操作（new/gc-alloc/类型检查/虚分派）编译为对 `sl_aot_runtime` C 函数的调用——**复用 C VM 同源实现**（`vm/runtime/aot/` 既有骨架），保证语义一致；
3. **链接管线**：`slang aot <工程>` 子命令：编译 → `.ll` → llc 出 `.obj` → 链接 sl_aot_runtime 静态库 → exe（Windows link.exe / Linux clang）；
4. **测试集**：BaseTest 精选（循环/递归/字符串/数组/类/虚方法）单文件版全过。

**验收**：`slang aot` 产出的 exe 脱离 slang 安装目录独立运行，输出与 VM 执行一致。

### M2 · 标准库 AOT（3~4 周）

1. **引用模块 AOT 化**：Core/Math/Std 模块编译为 AOT 静态库（`.a` / `.lib`）+ 元数据（类型表/方法符号）；
2. **跨模块链接**：用户工程 AOT 时链接标准库 AOT 库；系统方法（下沉 C 实现的）直接链 C 符号；
3. **泛型实例化**：模板类按用点实例化发射（复用 Front 既有实例化机制，AOT 侧只发射实例）；
4. **产物缓存**：标准库 AOT 库随发布包分发（`bin\` 旁），用户编译零等待。

**验收**：若依系统（P1）可 AOT 为独立 exe 运行（**P1 与 P5 的汇合点**）。

### M3 · AOT/VM 混跑三态（3~4 周）

1. **jsonc 三态**（未解决问题.txt 已有规划）：`"aot": "AOT" | "Mix" | "PureCVM"`；
   - AOT：全量原生；
   - Mix：热点模块 AOT + 冷模块 VM 动态装载（插件/脚本场景）；
   - PureCVM：现状（JIT 可开）；
2. **互操作桥**：VM 调 AOT 函数（经符号表 + 调用约定适配）/ AOT 调 VM 模块（回调进 VM 主循环——复用 P0 trampoline 思想）；
3. **边界数据**：T1/T2 的 id 注册表与 GC 穿透在此落地联调。

**验收**：Mix 模式下热路径 AOT + 运行时 spm 装载的 VM 包互调成功。

### M4 ·（收尾）基准与发布

1. BenchMark 套件三方数据（AOT / JIT / 纯 VM）矩阵成文，进官网性能页（与 P1-E1 汇合）；
2. `md/project/exporter.md` 重写为完整用户文档；AGENTS.md §3 AOT 行更新；
3. **ESP32-P4 预研**（target.md 长期项）：AOT 交叉编译到 Xtensa/RIscV + 最小运行时裁剪——单独立项，前置 = M3 稳定。

## 四、验收标准（总）

- [ ] 三份 RFC 定稿且实现与文档一致；
- [ ] M1：BaseTest 精选集 AOT 独立运行，输出与 VM 逐字节一致；
- [ ] M2：若依 AOT 单 exe 运行；
- [ ] M3：Mix 模式热/冷模块互调，AOT↔VM 对象跨边界无泄漏（id 注册表/GC 穿透验证）；
- [ ] BenchMark 三方对比数据发布。

## 五、执行顺序

```
T1/T2/T3 三份 RFC（并行写）──► T0 评审定稿
                                   │
        ┌──────────────────────────┤
        ▼                          ▼
   M1 单文件 exe ──► M2 标准库 ──► M3 混跑 ──► M4 基准/发布 ──►（远期）ESP32-P4
```

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| 设计反复推倒（历史教训） | RFC 评审关卡强制：定稿前禁写实现；否决方案留档 |
| 指令降级工作量失控 | M1 按指令族分批（先算术/控制流 → 对象 → 泛型），每批配测试 |
| AOT 与 VM 语义漂移 | 同源运行时（intrinsic 复用 C VM 实现）+ 一致性测试（同用例双跑 diff） |
| 混跑死锁/泄漏 | M3 联调用 CoroGCProbe/OOMProbe 风格探针用例（P0-T7 恢复的探针正好复用） |
