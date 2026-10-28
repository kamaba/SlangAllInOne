# P4 · CPython 互操作插件 —— 执行计划

> **定位**：关键改道——自己写 torch 是数年级工程且生态无法竞争；CPython 互操作 = 直接用 numpy / pytorch / pandas 生态。SLang 短期即获得 ML 能力展示，Tensora（P6-B）长线再补。
> **模板基础**：插件机制已验证两轮（csharp_mono / java_hotspot 均为原生 C DLL 三导出 ABI `sl_frontend_*`，标准模板 `md/plugins/PLUGIN_TEMPLATE.md`，插件包布局 2026-10-25 已定稿）。
> **依赖**：P0（回调 trampoline——CPython 的 C 方法表是函数指针数组）。**建议节奏**：3~4 周。

---

## 一、目标

1. `@python(){}` 内联块：SLang 工程内直接写 Python 代码并执行；
2. SL ↔ Python 值双向转换（int/float/string/list/dict/Tensor↔ndarray）；
3. GIL 与 SL isolate 线程模型对齐，多 isolate 并发调用无死锁；
4. 端到端 Demo：SLang 脚本调 PyTorch 训练模型并回传指标。

## 二、现状与差距

| 现状 | 差距 |
|------|------|
| 插件三工程结构成熟：`frontend/`（AtSignLabel 承载）+ `cvm/`（C99 运行时）+ `slang/`（ref module） | 参照物是 Mono/JVM，CPython 的 GIL/引用计数是新模式 |
| 三导出 ABI `sl_frontend_*` Parse/Build 单 JSON 契约 | CPython 侧需实现同契约 |
| 插件包布局定稿：产物导出 `<插件根>\package\{windows\|linux}\` + slb 平铺 | 无 |
| isolate 线程模型（端口消息/零拷贝转移） | GIL 获取/释放与 isolate 线程对齐未设计 |

## 三、任务分解

### T1 · 三工程骨架搭建（2 天）

**步骤**（完全复制 csharp_mono 模式）：
1. `plugin\python\` 新建插件目录：`plugin.jsonc`（frontendNative 段声明）+ `frontend/`（vcxproj，导出 `sl_frontend_*` 三 ABI）+ `cvm/`（vcxproj，嵌 CPython）+ `slang/`（ref module 声明 `Py` 名空间）+ `cvm\build-python.ps1`（一键三产物）；
2. Front 侧 `PluginFrontendParser` / `PluginManager` 按既有 `<插件根>\package\<平台>` 探测（2026-10-25 布局），理论上零改动——验证"新插件零内核改动"；
3. Python 发行版决策：**动态链接宿主 Python**（`python3.dll` / `libpython3.so`，用户自装）为主形态——静态嵌 python 受 LGPL 与体积制约；探测序：`<包>\lib\<平台>\` → 系统 PATH → PYTHONHOME 环境变量。

### T2 · cvm 侧嵌入 CPython（4~5 天，核心）

**步骤**：
1. **生命周期**：`Py_InitializeEx(0)`（首次 @python 块惰性初始化）/ `Py_FinalizeEx`（VM 退出钩子）；初始化失败给可读错误（提示安装 Python）；
2. **GIL 管理**：
   - VM 主线程首次进入 Python 前 `PyEval_InitThreads` 语义（Python 3.9+ 自动）；
   - **每 isolate 线程**进入前 `PyGILState_Ensure()` / 退出后 `PyGILState_Release()`——封装在调用包装器统一处理；
   - 长计算期间主动 `Py_BEGIN_ALLOW_THREADS` 让渡（防 SL 侧饿死）；
3. **执行通道**：`PyRun_String`（内联块字符串）+ `PyImport_ImportModule`（import 桥）；stdout/stderr 重定向到 SL Console（`PySys_SetObject` 替换 sys.stdout 为 C 回调 → P0 trampoline 或直接 C 层转发）；
4. **错误面**：Python 异常 → `PyErr_Fetch` → 转换为 SL Error（traceback 进 message），走 SL try/catch。

### T3 · 值转换边界（4~5 天，难点）

| SL 侧 | Python 侧 | 策略 |
|--------|-----------|------|
| Int32/64, Float32/64 | PyLong / PyFloat | 值拷贝 |
| string | PyUnicode (UTF-8) | 拷贝 |
| Boolean | PyBool | 值拷贝 |
| List / Array | PyList / PyTuple | 逐元素递归转换 |
| Map / Table | PyDict | 键值递归 |
| **Tensor（Tensora）** | **numpy ndarray** | **P6-B 落地后走缓冲区协议零拷贝**；MVP 先 List 嵌套转换（慢但正确） |
| 任意 SL class | PyObject capsule | 不透明句柄（进 Python 后只能传回 SL，不能解构） |
| 任意 PyObject | SL PyObject 包装类 | 引用计数 `Py_IncRef/DecRef`，SL 侧 GC finalize 时释放 |

**步骤**：
1. cvm 侧 `py_value_bridge.c`：`sl_to_py / py_to_sl` 双向递归转换器（深度上限防循环引用）；
2. SL 侧包装类 `Py.Object`（持有 PyObject* 句柄，_del_ 钩子 `Py_DecRef`）；
3. ref module 声明：`plugin\python\slang\` 提供 `Py.eval( string )` / `Py.call( string module, string func, ... )` / `Py.Object` 等最小 API。

### T4 · `@python(){}` 内联块（3 天）

**步骤**：
1. Front 侧：`@python(){ … }` 块由 frontend 段（T1）在 Parse 时捕获为字符串字面量，Build 契约返回"包装为 Py.eval 调用"的注入（复用 csharp_mono 的 AtSignLabel 通道）；
2. 数据面：内联块内 `sl_get("name") / sl_set("name", value)` 魔法函数 ↔ SL 侧变量上下文（MVP：块级共享 Map）；
3. 示例：

```sl
List<float> losses = List<float>();
@python(){
    import torch
    model = torch.nn.Linear( 4, 1 )
    opt = torch.optim.SGD( model.parameters(), lr = 0.01 )
    for i in range( 100 ):
        loss = model( torch.randn( 8, 4 ) ).pow( 2 ).mean()
        opt.zero_grad(); loss.backward(); opt.step()
        sl_set( "finalLoss", float( loss ) )
}
Console.println( "finalLoss = $finalLoss" );
```

### T5 · 并发与稳定性测试（2~3 天）

1. 多 isolate 并发调 Python（GIL 对齐验证：无死锁、无崩溃）；
2. Python 异常 → SL catch 链路；
3. 内存：长循环创建/销毁 PyObject 观察引用计数泄漏；
4. 重入：SL → Python → 调回 SL（经 capsule 句柄）。

### T6 · 端到端 Demo + 文档（2 天）

1. `SLangCore\test\Other\PythonTest\`：值转换矩阵 + PyTorch 训练 Demo（T4 示例落地）+ pandas 读 CSV → SL Table；
2. `md/plugins/Python.md`（仿 CSharp_Mono.md）：安装（Python 依赖说明）/ API / 线程语义 / 局限（MVP 无跨线程回调）；
3. 官网插件中心（doc/08/09）登记 python 插件。

### T7 ·（后续，不进 MVP）quickjs / node.js / clang 插件

- **quickjs**：轻量 JS 嵌入，同模式复制（价值：脚本配置/热更；优先级低于 python）；
- **node.js**：`未解决问题.txt` 有"贴合 nodejs 服务"构想——本质是把 C VM 做成 node addon（方向反置：SLang 嵌入 node 而非 node 嵌入 SLang），单独立项评估；
- **clang 插件**：libclang 绑定 → **为 P3/P6 的 QT、libcurl、bgfx 绑定自动生成脚手架**，与绑定工程合并做，不做独立用户级插件。

## 四、验收标准

- [ ] `@python(){}` 内联块执行，sl_get/sl_set 双向取值；
- [ ] `Py.call` 从 SL 调任意 Python 模块函数，六类值类型往返一致；
- [ ] PyTorch 训练 Demo 端到端（SL 发起 → Python 训练 → 指标回 SL 打印）；
- [ ] 4 isolate 并发 Python 调用 1000 轮无死锁无崩溃；
- [ ] Python 异常正确转为 SL 异常（含 traceback）；
- [ ] 插件三工程零 Front/CVM 内核改动接入（验证插件 ABI 成熟度）。

## 五、执行顺序

```
T1 骨架 ──► T2 cvm 嵌入(GIL) ──► T3 值转换 ──► T4 内联块 ──► T5 并发测试 ──► T6 Demo+文档
（P0 回调 trampoline 需就绪 ──▲）
```

## 六、风险与对策

| 风险 | 对策 |
|------|------|
| GIL 与 isolate 死锁 | 全部 Python 入口统一走 `PyGILState_Ensure` 包装器；MVP 禁 Python 侧再调 SL（除 capsule 传回） |
| Python 版本碎片（3.8~3.13 ABI 差异） | 动态链接 + Stable ABI（Py_LIMITED_API）编译；版本探测进错误信息 |
| 引用计数泄漏难查 | 提供 `Py.debugRefCount()` 诊断接口；测试用例带泄漏断言 |
| numpy 零拷贝依赖 Tensora（P6-B） | MVP 用嵌套 List 转换，性能路径记录为 P6-B 联动项 |
