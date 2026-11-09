# global 关键字

`global` 用于访问工程级的全局能力。当前语义由两部分组成：

- `global.xxx` / `global.func()`：映射到 `.sp` 里的 `Project{}` 静态成员与函数
- `global.data`：来自工程 `jsonc` 配置中的 `global.data` 注入数据

## 1. `.sp` 中 `Project{}` 成员调用

示例（`test/BaseTest/ProjectTest.sp`）：

```s
import Std

Project
{
    println( txt )
    {
        Console.println( txt )
    }
    print( text )
    {
        Console.print( text )
    }
}
```

在任意业务类中可直接用 `global` 调用：

```s
GlobalTest
{
    static fun()
    {
        global.println("========== GlobalTest (start) ==========")
        global.print("hello from global.print")
    }
}
```

## 2. `jsonc` 的 `global.data` 注入

示例（`test/BaseTest/ProjectTest.jsonc`）：

```jsonc
"global": {
  "data": {
    "var1": 12,
    "arrvar1": [1, 2, 3, 4, 5],
    "vardata2": {
      "a": 10,
      "b": 20.1
    }
  }
}
```

访问方式：

- 基础值：`global.var1`
- 数组：`global.arrvar1[0]`
- 对象：`global.vardata2.a`

## 3. 跨模块调用（import 引入后的方式）

`global` **只绑定当前编译目标工程**自己的 `Project{}`。引用模块（Core / Std /
SLangCuda 等）虽然也各自导出自己的 Project 类，但会被编译器按模块来源过滤，
`global.xxx` 永远不会命中它们——引用方的 `global.data` / `Project{}` 与被引
用模块的互不串台。

模块 `Project{}` 里的静态成员会并入该模块的命名空间，引用方通过
**`模块名.成员`** 限定访问（与访问模块下的类型同一形式）。

被引用模块侧（如 `Lib/Std/Std.sp`）：

```s
Project
{
    # 模块级静态成员变量：引用方通过 Std.name 限定访问
    # 注意：成员名不允许与模块下定义的 namespace/data/class/enum 同名
    Float64 Pi = 3.14159265358979
    Int32 MaxThreadCount = 8

    # 模块级静态成员函数：引用方通过 Std.name() 限定调用
    Int32 Add(Int32 a, Int32 b)
    {
        ret a + b
    }

    Float64 CircleArea(r)
    {
        ret Pi * r * r          # 模块内部自己调用可省略前缀
    }
}
```

引用方工程（jsonc `references` 指向该模块 + `import Std`）：

```s
import Std;

ModuleGlobalTest
{
    static fun()
    {
        Console.println( Std.Pi.toString() )        # 读模块静态变量
        Console.println( Std.Add(3, 4).toString() ) # 调模块静态函数
        Float64 area = Std.Pi * 1.5 * 1.5           # 参与表达式
    }
}
```

要点：

- 跨模块**只能** `Std.name` 限定访问，没有 `global.` 直达其它模块的形态；
- 模块内 `Project{}` 成员互调（如 `CircleArea` 调 `Pi`）可省略模块名前缀；
- 模块 `Project{}` 成员名不得与该模块下已定义的 namespace / data / class /
  enum 同名（编译期报重名）；
- 同工程内其它类访问本工程全局，仍走第 1 节的 `global.xxx`，二者是两条
  独立解析链路，可混用（见 `test/ExpendTest/ModuleGlobalTest.sl`）。

## 4. 推荐测试用例

仓库内已提供 `test/BaseTest/GlobalTest.sl`，覆盖：

- `.sp Project{}` 暴露成员：`global.print`、`global.println`
- `jsonc global.data` 基础值：`global.var1`
- `jsonc global.data` 数组：`global.arrvar1`
- `jsonc global.data` 对象：`global.vardata2.a`、`global.vardata2.b`
- `global._inputArgs`：系统集成的 CLI 程序入参（`Array<Object>`）

跨模块（import）调用另有 `test/ExpendTest/ModuleGlobalTest.sl` 专项覆盖：
`Std.Pi` / `Std.E` 静态变量读、`Std.Add` / `Std.CircleArea` / `Std.Hello`
静态函数调、静态成员参与表达式、与模块类型限定访问混用四条链路。

## 5. 常见注意点

- 访问 `global.xxx` 前，需确保对应字段在 `Project{}` 或 `global.data` 已定义。
- `global.data` 的对象会转换为内部数据结构，支持链式访问。
- 若工程内多个配置文件同名项冲突，以当前编译目标工程的配置为准。
- 引用模块的 Project 成员**不能**用 `global.` 访问（会被编译器按模块来源
  过滤，`global.` 只认本工程自己的 `Project{}`），必须用 `模块名.成员`。
