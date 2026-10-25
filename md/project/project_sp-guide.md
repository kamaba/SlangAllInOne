# Core.sp 说明文档

> 对应工程入口：`Core.sp`
> 
> 对应配置文件：`Core.jsonc`

## 0. `.sp` 非必需（2026-10-25 起）

同名 `<ProjectName>.jsonc` 存在即认定为合法工程锚点；`.sp` 存在时行为完全不变，缺失时自动按**非 main 入口（库）工程**编译：

- 无 `Project{}` 类——本文档所述 `_main_` / `_test_` 入口、`_before_` / `_after_` 钩子、`global.xxx` 整合面（§2）均不复存在
- 无 global 块与工程级 typealias（两者均锚定 `.sp`）
- 导出 `entryMethodId` 为 null（C VM 视作库模块装载，不从本工程启动）
- jsonc 的 `global.data` / `global.macro` 数据注入、`compileFiles` 清单、`references` 引用等配置面照常生效（不依赖 `.sp`）

工程定位顺序：目录扫描优先 `.sp`，无 `.sp` 时回落同名 `.jsonc`（跳过插件清单 `plugin\<id>\plugin.jsonc`）；CLI `-p <path.sp|path.jsonc>`、裸参数、宿主 `slang new`、LSP、VSCode 插件均支持两种锚点。

## 1. 入口函数约定

### `_main_`
运行入口函数。正常执行时从这里开始。

### `_test_`
测试入口函数。启用测试模式时走这里。

### `_before_`
编译前钩子（位于 `Project` 类中）。在编译前调用，用于编译前预处理。

### `_after_`
编译后钩子（位于 `Project` 类中）。在编译完成后、导出 IR 前调用，用于编译后处理。

---

## 2. `global` 与 `Project{}` 的整合

当前前端语义中，`global.xxx` / `global.func()` 的来源已切换为 `Project{}`。

也就是说：

- `global.var` -> 读取 `Project` 中对应静态成员
- `global.fun()` -> 调用 `Project` 中对应函数

---

## 3. `global.data`（来自 `Core.jsonc`）

可以在 `Core.jsonc` 中配置：

```jsonc
"global": {
  "data": {
    "var1": 12,
    "vardata2": {
      "a": 10,
      "b": 20
    }
  }
}
```

注入规则：

1. 普通值（`int32` / `string` / `float`）
   - 直接注册到 `Project` 的静态成员
   - 可直接访问：`global.var1`

2. 对象值（JSON object）
   - 转换为 `MetaData` 结构
   - 子字段按 `name -> value` 递归注册
   - 可访问：`global.vardata2.a`、`global.vardata2.b`

---

## 4. 建议

- 工程入口逻辑放在 `_main_`
- 测试逻辑放在 `_test_`
- 配置常量与结构化数据优先放在 `Core.jsonc -> global.data`

## 5. 对应用例

- 语法/集成用例：`test/BaseTest/GlobalTest.sl`
- 覆盖范围：
  - `global.Pi`、`global.print(...)`、`global.println(...)`（来自 `.sp` 的 `Project{}`）
  - `global.var1`、`global.arrvar1[i]`、`global.vardata2.a/b`（来自 `jsonc` 的 `global.data`）
