# 关键字与语法糖总表

本文汇总 SLang 的关键字、保留字、运算符与语法糖，并给出「写错时的正确写法」。配套代码规范（关键字与 Core 库使用约束）见工程内的代码规范文档。

---

## 1) 关键字总表

以下关键字在词法层直接映射为专用 token，**禁止用作变量名、方法名、类名等任何标识符**。

### 1.1 声明与结构

| 关键字 | 用途 | 详见 |
|--------|------|------|
| `typealias` | 类型别名 | [typealias.md](./typealias.md) |
| `import` / `as` | 导入模块 / 导入别名 | [namespace.md](./namespace.md) |
| `is` / `isnot` | 类型判断 | [express.md](./express.md) |
| `namespace` | 命名空间 | [namespace.md](./namespace.md) |
| `class` / `extends` | 类 / 继承 | [class.md](./class.md)、[extend.md](./extend.md) |
| `interface` | 接口 | [interface.md](./interface.md) |
| `abstract` | 抽象类/方法 | [class.md](./class.md) |
| `enum` | 枚举 | [enum.md](./enum.md) |
| `data` | data 数据类 | [data.md](./data.md) |
| `dynamic` | 动态类型 | [type.md](./type.md) |
| `void` | 无返回 | [function.md](./function.md) |
| `extern` | 外部声明（FFI 体系）；类级显式导出标记（`extern class/data/enum`，恒导出） | [../project/ffi.md](../project/ffi.md)、[class.md](./class.md) §1.5.1 |
| `bind` | 绑定 | [bind.md](./bind.md) |
| `label` | 标签 | [labelgoto.md](./labelgoto.md) |

### 1.2 修饰符

| 关键字 | 用途 |
|--------|------|
| `public` / `protected` / `private` | 访问级别 |
| `const` | 常量 |
| `mut` | 可变标注 |
| `final` | 终态（不可继承/覆盖） |
| `static` | 静态（也是编译期条件前缀，见 §3.3） |
| `inline` | 内联标记（函数修饰符） |
| `partial` | 分部类 |
| `override` | 覆写 |
| `params` | 变长参数（如 `waitAll(params Array<Task>)`） |
| `tr` | Transience（保留字；当前无文档与测试用例，同样禁止作标识符） |

### 1.3 控制流

| 关键字 | 用途 | 详见 |
|--------|------|------|
| `if` / `elif` / `else` | 条件 | [if.md](./if.md) |
| `while` / `dowhile` / `for` / `in` | 循环与遍历 | [forwhiledowhile.md](./forwhiledowhile.md) |
| `out` | 泛型协变标注（`IIterator<out T>`）；`in` 兼作逆变标注 | [template.md](./template.md) |
| `switch` / `case` / `default` | 分支 | [switch.md](./switch.md) |
| `next` | 循环内 = continue；switch case 体内 = 显式贯穿 fall-through | [switch.md](./switch.md) |
| `continue` / `break` | 循环控制 | [forwhiledowhile.md](./forwhiledowhile.md) |
| `goto` | 跳转（配合 `label`） | [labelgoto.md](./labelgoto.md) |
| `ret` | 返回语句（见 §3.1；`return` 不是关键字，词法层拦截报错，见 §1.8） | — |

```sl
function max(int a, int b)
{
    if (a > b)
    {
        ret a          # 用 ret 返回，不要写 return
    }
    ret b
}
```

### 1.4 异常

| 关键字 | 用途 | 详见 |
|--------|------|------|
| `try` / `catch` / `finally` | 异常捕获 | [try.md](./try.md) |
| `throw` / `throws` | 抛出 / 函数异常声明 | [try.md](./try.md) |
| `checked` / `unchecked` | 溢出检测上下文 | [try.md](./try.md) |

### 1.5 对象、值与协程

| 关键字 | 用途 |
|--------|------|
| `new` | 实例化 |
| `var` | 类型推断声明 |
| `this` / `base` | 当前实例 / 基类 |
| `null` / `true` / `false` | 字面量 |
| `get` / `set` | 属性访问器。**禁止用作成员名 / 方法名**（词法即报错） |
| `function` | 函数 / 闭包表达式 |
| `await` / `spawn` / `yield` | 协程语法糖（见 §3.2） |

### 1.6 类型关键字（保留类型词）

以下词是保留类型词，与 Core 类型类的对应关系如下：

| 类型词 | 实际类型 | 类型词 | 实际类型 |
|--------|----------|--------|----------|
| `object` / `Object` | `Object` | `long` | `Int64` |
| `byte` | `UInt8` | `ulong` | `UInt64` |
| `sbyte` | `Int8` | `bool` | `Boolean` |
| `short` | `Int16` | `half` | `Float16` |
| `ushort` | `UInt16` | `float` | `Float32` |
| `int` | `Int32` | `double` | `Float64` |
| `uint` | `UInt32` | `string` | `String` |

### 1.7 非词法保留（可作标识符，但有使用限制）

| 词 | 说明 |
|----|------|
| `map` `list` `stack` `hashset` `queue` `tuple` `array` `range` | 小写容器构造糖（见 §3.8）。词法按普通标识符处理：可作局部变量/参数名；**禁止作类成员声明名**（字段/方法/getter/setter，编译报错） |
| `error` `errmsg` | Result 机制保留名，同上禁止作类成员声明名（见 [result.md](./result.md) §7） |
| `async` | 已禁用，按普通标识符处理 |

### 1.8 非本语言关键字（词法层拦截报错）

以下词是其他语言（C/C#/Java/Go/Python/Rust 等）的关键字，但 **SL 没有对应语法**。词法层识别到即报 **Error 并阻断编译**，报错信息会给出改写指引；不会像普通标识符那样流入语义层产生 `Name:xxx not found!` 等误导性报错。

| 拦截词 | SL 正确写法 |
|--------|------------|
| `return` | `ret;` / `ret 表达式;`（[function.md](./function.md)） |
| `foreach` | `for ( x in collection )`（[forwhiledowhile.md](./forwhiledowhile.md)） |
| `using` / `include` | `import`（[namespace.md](./namespace.md)） |
| `elseif` | `elif` |
| `struct` | `data` / `class`（[data.md](./data.md)） |
| `let` | `var` 或显式类型声明（[variable.md](./variable.md)） |
| `raise` | `throw`（[try.md](./try.md)） |
| `lambda` | `function` 表达式或 `x => expr`（§3.4） |
| `def` | 函数直接以名称声明（[function.md](./function.md)） |
| `package` | `namespace`（[namespace.md](./namespace.md)） |
| `impl` | `class` + `extends` / `interface` |
| `trait` | `interface`（[interface.md](./interface.md)） |
| `pub` | `public` |
| `unless` | `if not ( ... )` |
| `until` | `while not ( ... )` |

> `@csharp(){}` 等内嵌语言块体内的 `using` / `return` 等**不受上述拦截影响**（块体按原样捕获）。

---

## 2) 运算符与特殊符号

常规算术 / 比较 / 逻辑运算符见 [operator.md](./operator.md)。特殊符号：

| 符号 | 用途 |
|------|------|
| `??` | 空合并：左值为 null 取右值 |
| `?.` | 空条件访问：对象为 null 时短路返回 null |
| `..` | 区间语法糖，构造 `Range`（见 [range.md](./range.md)） |
| `=>` | lambda 表达式（见 §3.4） |
| `===` / `!==` | 值等 / 值不等比较（内容比较） |
| `? :` | 三元条件 |
| `@` | 属性前缀：`@Nickname`、`@DllImport` 等（见 [attribute.md](./attribute.md)） |
| `$` | 字符串插值前缀（见 §3.5） |
| `#` | 行注释 |
| `#! ... !#` | 块注释 |

---

## 3) 语法糖

### 3.1 语句与控制流糖

| 糖 | 语义 |
|----|---------------|
| `ret` | 从函数返回 |
| `next`（switch case 体内） | 显式贯穿到下一个 case（不写则隐式 break） |
| `tr` | Transience（保留，当前无实际用例） |

### 3.2 协程三件套（前端展开为 `Coroutine` 调用）

| 糖 | 展开为 |
|----|--------|
| `yield;` | `Coroutine.yieldNow()` |
| `await expr` | `Coroutine.awaitTask(expr)` |
| `spawn f(实参...)` | `Coroutine.spawnClosureN(...)`（挂起当前协程，异步执行 f） |

详见 [coroutine.md](./coroutine.md)。

### 3.3 编译期条件 `static if`（已废弃）

> **已废弃**（attribute 重构，旧隔离机制收编）：现在写 `static if` 报 **Error**，该语句按普通 `if` 继续解析（退化为运行期逻辑）。
> 迁移：成员/类裁剪用 `@Exclude` attribute（标注即不参与编译）；整文件剔除用 jsonc `compileFiles.ignore`；配置值保留 `global.macro.X` 运行期只读访问。详见 [static-if.md](../project/static-if.md)。

### 3.4 表达式糖

| 糖 | 语义 |
|----|------|
| `try? expr` / `try! expr` | try 的表达式前缀形式（详见 [try.md](./try.md)） |
| `a ?? b` | a 为 null 时取 b |
| `a?.member` | a 为 null 时短路返回 null |
| `a..b` | 构造 `Range`（`NumberArrayLink`） |
| `x => expr` | lambda |
| `a === b` / `a !== b` | 值等 / 值不等（区别于引用等的 `==`） |

### 3.5 字符串插值

```sl
a = "print a=$a4";          # $var
b = "print c1.a1=$c1.a1";   # $obj.member
c = "sum=${ a + b }";       # ${expr}
d = f"""x=${ a + 1 }""";    # 三引号 f 形式仅支持 ${expr}
```

详见 [string.md](./string.md)。

### 3.6 注释

```sl
# 行注释
#! 块注释
   可跨行
!#
```

### 3.7 @Nickname 别名

在 Core 内通过 `@Nickname` 注册短别名（编译时在父命名空间注册别名节点）：

| 别名 | 实际类 |
|------|--------|
| `coro` | `Coroutine` |
| `Float8_E4M3` | `Float8` |

### 3.8 小写容器构造糖

`map(...)` / `list(...)` / `stack(...)` / `hashset(...)` / `queue(...)` / `tuple(...)` / `array(...)` / `range(...)` 作为**链首裸调用**时，会被展开为对应容器构造（`Map(...)` / `List(...)` …）：

```sl
var nums = list(1, 2, 3)              # 展开为 List(1, 2, 3)
var kv = map("a", 1, "b", 2)         # 展开为 Map("a", 1, "b", 2)
var r = range(0, 10)                 # 展开为 Range
```

由此带来的命名约束（编译期检查，编译报错）：

1. 这 8 个糖名**禁止作类成员声明名**（字段/方法/getter/setter）——例如成员方法 `map(...)` 的裸调用形式会被糖劫持，永远无法被正常调用，声明即报错；
2. `error` / `errmsg` 是 Result 机制保留名（见 [result.md](./result.md) §7），同样禁止作类成员声明名；
3. 局部变量与参数不受限制（糖只劫持链首裸调用，不影响成员访问 `obj.map(...)` 与变量引用）。

### 3.9 成员变量定义期名称冲突自检

编译器在定义期会对成员名做名称冲突检查，成员名需避开两类名称：

1. **语言关键字**（含基本类型关键字 `int` / `string` / `object` 等）：成员名必须是普通标识符；
2. **当前文件 `import` 下可索引到的类名 / 命名空间名称**：裸名解析时 import 平面先于类成员命中，重名成员会被遮蔽产生歧义。例如 `import Std;` 后成员名不能用 `Std`，`import Std:IO;` 后不能用 `IO` 及 Std 根下的顶层名称。

> jsonc 注入成员（`global.data` / `global.macro` / `dllImports`）走限定名访问（如 `global.dllImport.<alias>`），不参与裸名解析，不受此约束。

---

## 4) 引用 Core 后直接可用的类型

### 4.1 可见性规则

工程 `.jsonc` 通过 `references` 引用 Core（编译包模式，`out/export/Core`）后：

1. **Core 模块根下的类型（含顶层 .sl 声明与 Core 命名空间登记的类）裸短名直接使用，无需 import**——如 `List<Int32>`、`Object`、`Stream<T>`；
2. `Core.` 前缀限定名总是可用，无需 import——如 `Core.List<T>`、`Core.IIterable<T>`；
3. **嵌套命名空间**（Environment）需限定名 `Core.Environment.env`，或 `import Core;` 后写 `Environment.env`（裸 `env` 不可用）；
4. **非 Core 模块**（Std / Math / Tensora 等）的类短名必须 `import`，限定名（如 `Std.Console.X`）可直接用。

### 4.2 基础与值类型

| 分类 | 类型 |
|------|------|
| 根 | `Object`、`Void`、`Boolean`、`Type`、`MetaClass`、`Member`、`Data`(abstract)、`Num`(abstract) |
| 整数 | `Int8`、`Int16`、`Int32`、`Int64`、`UInt8`、`UInt16`、`UInt32`、`UInt64` |
| 浮点 | `Float8`(别名 `Float8_E4M3`)、`Float8_E5M2`、`Float16`、`Float16_Brain`、`Float32`、`Float64` |
| 其他 | `String`、`Range<T:Num>`、`Guid`、`Random`、`Ptr`、`Ptr<T>`、`Memory`、`Result`、`Result<T>`、`Tuple`(共 9 个变体：无参 + T1..T8) |

### 4.3 容器与数据结构

| 分类 | 类型 |
|------|------|
| 容器 | `Array<T>`、`List<T>`、`Map<T1,T2>`、`HashSet<T>`、`Queue<T>`、`Stack<T>`、`LinkedList<T>`、`StringBuilder` |
| 树/表 | `Tree<T>`、`TreeNode<T>`、`BinaryTree<T>`、`BinarySearchTree<T>`、`BinaryNode<T>`、`Table` |
| 文本/序列化 | `BaseJson`、`JsonValue`、`Json`、`BaseCsv`、`BaseToml`、`BaseYaml`、`Serialize`、`Utf8Codec`、`JsonCodec<T>`、`BinaryCodec`、`ProtocalBuffers`（Pb 系）、`Lz4` |
| 接口 | `IClone`、`IClone<T>`、`IIterator`、`IIterable`、`IIterator<out T>`、`IIterable<T>`、`IList<T>`、`IMap<T1,T2>`、`Iterater`、`Iterater<T>` |

### 4.4 协程与并发

| 类型 | 说明 |
|------|------|
| `Coroutine`（别名 `coro`） | 协程管理器（spawn/waitAll/waitAny…） |
| `Task` | 协程对象（handle/awaitTask/cancel/status/isDead） |
| `CoroutineStatus` | 状态枚举（0=Created…4=Dead） |
| `CoroutineBlockReason` | 阻塞原因枚举（0=None…5=IO） |
| `Channel` / `Channel<T>` | 通道 |

### 4.5 IO 与 Stream

| 分类 | 类型 |
|------|------|
| 字节 | `ByteBuffer`、`ByteStream`(abstract)、`MemoryStream`、`LengthPrefix` |
| Stream | `Stream`(abstract)、`Stream<T>`(abstract)、`StreamIterator<T>`、`StreamSubscription`、`StreamController<T>`、`StreamSink<T>`、`StreamTransformer<S,T>` |
| Codec | `ChunkedConversionSink`、`Converter<S,T>`、`Codec<S,T>`、`ProtoCodec` / `ProtoCodec<T>` |

### 4.6 其他

`Attribute`、`Nickname`、`AOT`、`Error` 及 `CoreError` / `MathOpError` / `BufferError` / `StreamIOError` / `SeekOrigin` / `Lz4Error` 等错误枚举。

> 注意：`_` 下划线开头的实现类（如 `_MapStream<T>`）是 Core 内部私有类，不应在业务代码中使用。

---

## 5) 命名空间

### 5.1 `Core`（模块根）

`Object`、`List<T>` 等直接挂在模块根下，引用后**裸短名直接可用**（见 §4.1）。

### 5.2 `Core.Environment`

| 成员 | 说明 |
|------|------|
| `current` | 当前平台环境 |
| `env` / `custom` / `sys` / `legacy` | 环境变量体系 |
| `OSVersionNumber` | 版本号 |
| `probe` / `Probe*` 系列 | 探测器（ProbeOSVersion / ProbeCpu / ProbeRender…） |
| `Cpu` / `Ai` / `Render` / `Network` / `Script` / `Embedded` / `Device` / `DeviceInfo` / `Override` | 环境域对象 |

详见 [../project/environment-guide.md](../project/environment-guide.md)。

### 5.3 `Core.Environment.Platform`

编译期平台定义枚举与常量：`os` / `osVersion` / `form` / `arch` / `cpu` / `isa` / `device` / `ai` / `render` / `shaderModel` / `network` / `link` / `embedded` / `rtos` / `runtime` / `build` / `endian`（枚举），以及 `DefItem` / `DefKind` / `defs`（定义表）。
jsonc `platform` 段关键字全表见 [../project/environment-guide.md](../project/environment-guide.md)。

---

## 6) 系统方法

`println` / `print` 等系统方法由 Core 标准库注册（涵盖转换、协程、字节缓冲、通道、内存、JSON、Lz4 等数百个），语言侧统一通过全局调用使用。使用说明见 [system_method.md](./system_method.md)。
