# local（文件级初始化 + 文件私有成员）

## 概述

`local { ... }` 用于在**单个源文件**内声明「文件级初始化逻辑」和「文件私有成员（变量 / 函数）」。你可以把它理解为「只对本文件可见的一段模块级状态与逻辑」。

核心特性：

- `local{}` 内的成员通过 `local.xxx` 在**当前文件**内访问。
- 多个文件都可以写 `local{}`，且可以**重复定义同名成员**，互不冲突（各自只认自己文件的 `local`）。
- `local{}` 的执行顺序由工程 `.jsonc` 配置里 `compileFiles.files.priority` 决定，priority 数值小的先执行。
- 执行时机：在类静态成员与 const 变量初始化完成之后、`_main_` 主逻辑之前执行。

常见用途：

- 本文件内的资源初始化（配置、缓存、连接等）。
- 本文件内可复用的工具函数（仅该文件可见）。

---

## 位置约束

`local{}` 只能放在**任何类（`class` / `data` / `interface` / `enum`）前边**。

在 `local{}` 之前，**只允许**放以下内容：

- `import` 语句
- `typealias` 语句
- 注释

其它任何内容都不允许放在 `local{}` 之前。

正确：

```sl
import Std;

local { a = 1 }

class A { }
```

错误：

```sl
class A { }
local { a = 1 }  # 不允许：local{} 必须在类之前
```

```sl
data D { x = 0 }
local { a = 1 }  # 不允许：data 定义在 local{} 前边
```

---

## 语法与规则

### 基本语法

```sl
local
{
    a = 1
    int Add(x)
    {
        ret x + local.a
    }
}
```

约束：

- `local` 后必须跟 `{}`。
- 同一文件只允许出现一个 `local{}`。
- `local{}` 中定义的函数**不允许**带 `static`。

### init 内裸名字访问（隐式 this）

`local{}` 初始化体内，裸名字（不带 `local.` 前缀）等价于隐式引用本文件的 `local` 成员，即直接读写对应的成员：

```sl
local
{
    a = new Vector2(){ x = 1.0f, y = 2.0f }
    float len = a.length()   # 定义局部变量 len；末尾自动同步为 this.len 成员
}
```

- `a = expr`（无类型前缀）：按成员赋值 `this.a = expr` 解析，成员类型由右值类型推导。
- `Type name = expr`（带类型前缀）：按局部变量定义解析，并在语句末尾自动同步为该 `local` 成员，成员类型取局部变量类型。
- 后续语句中对裸名字的链式调用（如 `a.length()`）按成员的**实际类型**解析。

### 语句与函数混排规则（重要）

1. 在 `local{}` 内，前边允许放语句。如果是定义变量，也可以直接写（如 `a = 1` 或 `float len = a.length()`）。
2. **一旦出现函数定义，在函数定义后边不允许再放任何语句**。也就是说，函数定义之后只能继续定义函数，不能再写初始化语句或变量定义。

正确：

```sl
local
{
    a = 1           # 语句：变量定义
    b = 2           # 语句：变量定义
    int Add(x)      # 函数定义
    {
        ret x + local.a
    }
    int Sub(x)      # 函数定义（允许在函数后继续定义函数）
    {
        ret x - local.a
    }
}
```

错误：

```sl
local
{
    a = 1
    int Add(x)
    {
        ret x + local.a
    }
    b = 2           # 错误：函数体后边不允许再放语句
}
```

---

## 访问规则（文件私有）

### local 成员只在当前文件可见

- 在 `FileA.sl` 里：`local.xxx` 只能访问 `FileA.sl` 自己的 `local{}`。
- 在 `FileB.sl` 里：`local.xxx` 只能访问 `FileB.sl` 自己的 `local{}`。

不同文件即使成员同名，也互不影响（即 `local.xxx` 永远指向本文件自己的 `local{}`，不会跨文件串扰）。

---

## 执行顺序（按 priority 顺序）

文件的执行顺序由 `.jsonc` 配置中 `compileFiles.files.priority` 的值决定。**priority 数值小的先执行**，相同 priority 按配置文件中的出现顺序执行（稳定排序）。

当工程 `.jsonc` 配置为：

```jsonc
"compileFiles": {
    "files": [
        { "path": "LocalTest1.sl", "priority": 1 },
        { "path": "LocalTest2.sl", "priority": 2 }
    ]
}
```

则执行顺序为：

1. `LocalTest1.sl` 的 `local{}` 初始化
2. `LocalTest2.sl` 的 `local{}` 初始化

**执行时机**：上述 `local{}` 初始化发生在 `_main_()` 主逻辑之前，且晚于所有类的静态成员变量与 const 变量的初始化。这保证了 local 逻辑可以安全地引用已初始化的静态成员。

---

## 完整示例（顺序与隔离）

下面两个文件各自写一份 `local{}`，演示顺序与隔离：

### `LocalTest1.sl`

```sl
local
{
    a = 1
    order = "L1"

    int Add(x)
    {
        ret x + local.a
    }

    PrintLocal()
    {
        global.println("LocalTest1 local.a=" + local.a)
        global.println("LocalTest1 local.order=" + local.order)
    }
}

class LocalTest1
{
    static Test()
    {
        local.a = local.a + 10
        var v = local.Add(5)
        global.println("LocalTest1 v=" + v)
        local.PrintLocal()
    }
}
```

### `LocalTest2.sl`

```sl
local
{
    # 与 LocalTest1 重复定义同名 a，不冲突
    a = 100
    order = "L2"

    int Add(x)
    {
        ret x + local.a
    }

    PrintLocal()
    {
        global.println("LocalTest2 local.a=" + local.a)
        global.println("LocalTest2 local.order=" + local.order)
    }
}

class LocalTest2
{
    static Test()
    {
        local.a = local.a + 1
        var v = local.Add(5)
        global.println("LocalTest2 v=" + v)
        local.PrintLocal()
    }
}
```

观察点：

- 若 `LocalTest1.sl` 的 priority=1、`LocalTest2.sl` 的 priority=2，则初始化顺序也是这个顺序。
- `LocalTest1.sl` 的 `local.a` 和 `LocalTest2.sl` 的 `local.a` 相互独立。

---

## 常见错误

- 位置错误：`Error local can only be used at first position` —— `local` 必须在文件前部（任何类之前）。
- 位置错误：`Error current file does not define local{}, cannot use local.xxx` —— 当前文件没有定义 `local{}` 却使用了 `local.xxx`。
- 重复定义：`Error local被定义了两次，在一个文件中，只允许在前排放置1个local` —— 同一文件只允许一个 `local{}`。
- 语法错误：`Error local后边应该有{}的语法` —— `local` 后必须跟 `{}`。
- local 函数使用 static：`Error local{} functions cannot use static keyword`。
- 生成类名冲突：`Error local{} generated class name conflict` —— 不同文件若最终算出同名局部类会冲突（通常因文件名导致），调整文件名即可。
