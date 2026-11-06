# 变量（variable）

> 本文按当前 Front 实现（`simple_language/source/`）与 `SLangCore/test/` 用例重新整理（2026-11-06）。
> 语言侧总述见 [introduction.md](./introduction.md)，关键字全表见 [keywords.md](./keywords.md)，文档索引见 [../INDEX.md](../INDEX.md)。

变量是「某个类型的值在运行期的名称」。S 语言**没有自由全局作用域**，所有变量都落在下面四层之一；这份文档按「声明形式 → 四类变量 → const → 命名规则 → 错误码」组织。

---

## 1. 四类变量与四层作用域

| 类别 | 声明位置 | 访问方式 | 说明 |
|------|----------|----------|------|
| 类成员变量（实例 / 静态） | 类体（含 `data` / `enum` 成员） | `obj.x` / `this.x` / `类名.x` | 旧称「对象变量」「对象静态变量」，见 §3 |
| 局部变量、形参 | 函数 / 方法体、块 `{}`、`for` 头 | 裸名，或 `this.x` 显式限定 | 见 §4 |
| 文件级成员 | `local { ... }` 块 | `local.x` | 编译器生成 `<FileName>_Local` 类并把变量提升为实例成员，见 [local.md](./local.md) |
| 工程级成员 | `.sp` 的 `Project{}` + 同名 `.jsonc` 的 `global.data` | `global.x` / `global.fun()` | 旧称「全局变量」，见 §5 |

实现侧对应关系：`EVariableFrom`（`Core/MetaVariable.cs`）区分 `ClassMember` / `DataMember` / `EnumMember` / `Argument` / `LocalStatement` / `Global` / `Static` / `ClosureContext` 等来源；`isExplicitConst` 就是靠这个来源判定哪些 `const` 需要拦截赋值（见 §6）。

**共同规则**

- 变量必须先定义再使用；名字在自身可见范围内唯一。
- 声明即初始化：等号与右值表达式不可省略（见 §2.3）。
- 变量不是类型声明；类型词、字面量、模板等见 [type.md](./type.md)、[number.md](./number.md)、[template.md](./template.md)。

---

## 2. 声明语法

### 2.1 基本形态

| 写法 | 语义 | 示例 |
|------|------|------|
| `类型 名称 = 表达式` | 显式类型，右值按声明类型校验 / 转换 | `Int32 count = 0` |
| `var 名称 = 表达式` | 显式「类型推断」声明 | `var count = 0` |
| `名称 = 表达式` | 无前缀：名称在当前可见范围未定义时视为局部变量定义，类型由右值推导；已定义则是赋值 | `count = 0` |
| `const [类型] 名称 = 表达式` | 只读变量，见 §6 | `const Int32 MAX = 10` |
| `static [类型] 名称 = 表达式` | 类静态成员（类体内） | `static Int32 hits = 0` |

专用声明形态（各有专题）：

| 写法 | 用途 | 详见 |
|------|------|------|
| `dynamic 名称 = ...` | 动态类型变量 | [type.md](./type.md) |
| `data 名称 = { ... }` | 匿名 / 具名 data 变量 | [data.md](./data.md) |
| `function 名称 = ...`、`var f = function(...) { }` | 函数值 / 闭包 | [function.md](./function.md) |
| `var f = (a, b) => a + b` | 内联 lambda 变量 | [inline_lambda.md](./inline_lambda.md) |

`类型` 可以是基本类型词（`int` / `string` / `bool` / `float` / `long` …）、Core 类型名（`Int32` / `String` / `Array<Int32>` …）或自定义类 / 模板类型。

### 2.2 成员变量声明头

```sl
class Counter
{
    public Int32 value = 0            # [权限] [类型] 名称 = 初值
    private static Int32 total = 0    # [权限] [static] [类型] 名称 = 初值
    public static const Int32 MAX = 100
}
```

头部可组合：权限（`public` / `private` / `protected`）、`static`、`const`、`extern`（导出标记，见 [class.md](./class.md) §1.5.1）、类型、名称。顺序无强制要求，但同一修饰符重复会报错（如 `static static`）。

> `mut` 是保留关键字，当前只在 `enum` 成员上表示「可变（非 const）」；**不要**用它声明普通变量。类级 `static` / `const` 修饰只允许写在 `data` / `enum` 头（见 [class.md](./class.md) §1.6.1）。

### 2.3 初始化是硬要求

- **成员变量必须初始化**：不支持 `int v;`，必须写 `int v = 0;`（或 `v = 0`）。违反报 `MetaCoreMemberVariableRequireInit` (21472)；此前误报的 `MetaCoreExpressIsNull` 已修正。
  - 例外：`local{}` 生成的 `_Local` 类合成占位成员（由 `__local_init__()` 隐式 `this.x = x` 写入），以及 `@InstanceAttr` 等编译期合成注入成员，无源码初始化表达式，不受此条约束。
- **局部变量同样要带 `= 表达式`**：`int a;` 会在 MetaCore 阶段因「表达式返回类型为空」报错 (21395)。
- **`=` 右值必须与 `=` 同行**：`name =\n{}`、`=` 后先换行 / 先注释再写值都会在 Node 解析层报错（`'=' 后未找到同一行右值表达式`），见 [data.md](./data.md) §10.3。
- 语句末尾分号可写可不写（仓库示例两种都有）；是否强制由工程 `.jsonc` 的分号策略决定。

---

## 3. 类成员变量（对象变量）

### 3.1 实例成员与静态成员

```sl
class Class0
{
    Int32 Variable0 = 0
}

class Class1 extends Class0
{
    Int32 Variable1 = 0
    String Variable2 = "abcd"
    static Float32 Variable3 = 2.0f
}

class VarDemo
{
    static void run()
    {
        Class1 c = Class1()
        Int32 v0 = c.Variable0        # 继承自父类的实例成员，经子类对象访问
        c.Variable1 = 20              # 改写 c 内部的 Variable1
        String x = c.Variable2
        Float32 xx = Class1.Variable3 # 静态成员：类名.成员名
    }
}
```

规则：

1. **实例成员**：对象创建时自动拥有本类及继承链上的全部非静态成员；编译器按继承链分配成员索引并计算对象布局。每个对象的实例成员互相独立（用例 `MemberVariable1Test.sl` 的 `testInstanceIsolation`）。
2. **继承链禁止重名**：父类（含祖先）已定义的成员名，子类不得再定义；实现在 `MetaClass.HandleExtendMemberVariable()`，违反报 21139–21142。命名时请避开父类已有名称，不要依赖「覆盖 / 遮蔽」。
3. **静态成员**：用 `类名.成员名` 读写；**非 const 的**实例成员不能经类名限定访问（`MetaCoreCallSMemberVariable` 21103），静态成员也不应经实例 / `this` 访问（`MetaCoreCallShuldNotStatic` 21100）。
4. **静态成员的继承语义（重要）**：静态成员经继承扁平化后，**每个类持有自己的静态槽副本**。经子类名访问祖先静态成员是合法的，但经 `子类名.成员 = ...` 写入只改子类自己的槽，父类槽保持独立——见 `MemberVariable1Test.sl` 的 `testGrandStatic`。需要共享值时始终用「定义该成员的类名」访问。
5. **成员名额外约束**：除关键字外，还要避开定义文件 `import` 下可索引的类名 / 命名空间名（23017）与容器构造糖名（11042），见 §7。
6. `data` / `enum` 成员是另外两套变量体系，规则见 [data.md](./data.md) 与 [enum.md](./enum.md)。

### 3.2 初始化顺序

编译器按 `parseLevel`（`Core/MetaVariable.cs`）排序执行成员初始化表达式：

| 顺序 | 类别 | parseLevel |
|------|------|-----------|
| 1 | `const` 成员 | `s_ConstLevel` = 100000 |
| 2 | `static` + 显式定义类型 | `s_StaticDefLevel` = 200000 |
| 3 | `static` + 无定义类型 | `s_StaticNonDefLevel` = 300000 |
| 4 | 普通成员表达式 | 500000 |
| 5 | 各文件 `local{}` 的 `__local_init__()` | 注入到 `_main_()` 前部，按 `compileFiles.files.priority`（数值小先执行） |

静态成员初值可引用先解析的静态成员（用例 `MVStaticRef`）；表达式间依赖会由 `ParseMetaExpress()` 递归提前解析并分配顺序。

---

## 4. 局部变量与作用域

```sl
class ScopeDemo
{
    static void run()
    {
        var1 = 20
        {
            var2 = "aaa"      # 仅在内层块可见
        }
        var1 = 30            # 外层变量继续可用
        # var2 ...           # 错误：超出 var2 的作用域
    }
}
```

规则：

- `{}` 定义块级作用域：内层可读写外层变量，外层不可见内层变量。实现见 `Core/Statements/MetaBlockStatements.cs` 的 `GetMetaVariableByName(name, isFromParent)`——查找沿 `parentBlockStatements` 向上递归，不会向下渗透。
- **不允许重复定义**：同一函数内重复定义同名，或名字与形参、类成员、`import` 平面等已有节点冲突，报 `MetaCoreDefineVarStatementDuplicate` (21391 / 21393)。
- 形参也是局部变量（来源 `Argument`），支持 `const` 修饰与默认值；`for (x in ...)` 的迭代变量是编译器生成的迭代器变量，见 [forwhiledowhile.md](./forwhiledowhile.md)。
- 闭包可捕获宿主局部变量与 `this`（`ClosureContext`）；**嵌套闭包的内层不能引用外层捕获变量与 this**，见 [function.md](./function.md) 与 [class.md](./class.md) §1.9。
- `local{}` 的 init 上下文是特例：裸名字等价于隐式 `this.成员`，详见 [local.md](./local.md) §「init 内裸名字访问」。

---

## 5. 工程级变量（`global`）

所谓「全局变量」只有两个来源，**业务类里不能自行声明新的全局变量**；`global` 是访问前缀，不是声明语法。

**来源一：同名 `.jsonc` 的 `global.data`**（编译期注入为 `Project` 静态成员）

```jsonc
"global": {
    "imports": [ "Std.Console" ],
    "data": {
        "var1": 12,
        "arrvar1": [1, 2, 3, 4, 5],
        "vardata2": { "a": 10, "b": 20.1 }
    }
}
```

**来源二：`.sp` 的 `Project{}` 内静态成员与函数**

```sl
import Std

Project
{
    println( txt )
    {
        Console.println( txt )
    }

    _main_()
    {
        Int32 gv = global.var1
        Int32 aa = global.vardata2.a
        global.println( "value=" + aa.toString() )
    }
}
```

访问形式：`global.var1`（标量）、`global.arrvar1[0]`（数组）、`global.vardata2.a`（对象链，内部转成 `MetaData` 树）、`global.println(...)`（函数）、`global._inputArgs`（系统集成的 CLI 入参，`Array<Object>`）。

> 注意：`global.data` 注入成员带的 `const` 是「初始值折叠」标记，不是用户 `const` 承诺，不参与 §6 的赋值拦截与传参约束（isolate 场景下改写 `global.var1` 属既有语义）。

详见 [global.md](./global.md)、[../project/project_sp-guide.md](../project/project_sp-guide.md) 与用例 `test/BaseTest/GlobalTest.sl`。

---

## 6. `const` 只读变量（2026-10-02 实装）

`const` 声明初始化后只能读取，不允许再赋值 / 修改。三种使用位置：

### 6.1 类成员 const

```sl
class Class0
{
    const Int32 CF = 10           # 实例 const 成员
    static const Int32 SCF = 20   # 静态 const 成员
}

# Class0 c = Class0()
# c.CF = 100       # 错误 21372
# Class0.SCF = 5   # 错误 21372
```

const 标记随 SLIR 导出（成员 `flags` 的 const 位 **值 16 / 0x10**；static 位为 32 / 0x20，见 `Export/SLIR/SLModulePackageWriter.cs`）。**跨模块**导入的类，其 const 成员同样被拦截，只读访问不受影响：

```sl
# 引用其它模块导出的 ConstLib 后
Int32 r = ConstLib.SCF     # 正确：跨模块只读
# ConstLib.SCF = 5        # 错误 21372：跨模块 const 成员赋值同样拦截
```

### 6.2 局部 const（语句）

```sl
static void run()
{
    const Int32 la = 10
    const lb = 30           # 无类型形态，由初始值推断
    # la = 20              # 错误 21372
    # lb = 40              # 错误 21372：无类型 const 同样拦截
    Int32 r = la + lb      # 正确：只读访问
}
```

### 6.3 const 形参

```sl
static Int32 takeConst( const Int32 a )
{
    # a = 100       # 错误 21372：const 形参在函数体内不允许赋值
    ret a + 1       # 正确：只读使用
}
```

形参的 `isConst` 随 SLIR 导出，跨模块调用同样生效。

### 6.4 const 传参约束

const 修饰的**实参**只能传给带 `const` 标记的形参（含跨模块引用的方法）；类型匹配成立后才检查，重载决议的精确 / 宽松两条路径都会检查：

```sl
const Int32 la = 10
takeConst( la )     # 正确：const 实参 -> const 形参
takeConst( 5 )      # 正确：字面量 / 编译期常量不受限制
# takeNormal( la )  # 错误 21468：const 实参传给了非 const 形参
```

### 6.5 不参与约束的场景

以下 `const` 属于类型系统常量或机制内部标记，**不触发**赋值拦截与传参约束：

| 场景 | 示例 | 说明 |
|------|------|------|
| enum 枚举值 | `FileStream(path, FileMode.Read, FileAccess.Read)` | 枚举值天然只读，等同字面量 |
| const 静态类成员传参 | `Mathd.min(x, BigNumber.CAPACITY)` | 编译期常量可传普通形参（赋值拦截仍生效） |
| `const data` 容器成员 | bind 宿主经 setter 写底层 data 实例成员 | 容器级只读是独立特性，见 [data.md](./data.md) |
| jsonc `global.data` 注入变量 | `global.var1 = 99`（isolate 隔离语义） | 注入 const 是初始值折叠标记，非只读承诺 |

判定实现：`MetaVariable.isExplicitConst` 只认来源为 `LocalStatement` / `Argument` / 源码或 ref module 导入的 `ClassMember`。

探针用例：`test/Other/ConstProbe/`（ConstLib 导出 / ConstProbe 负例 / ConstLocal 正例 / ConstCross 跨模块）。

---

## 7. 变量命名规则

适用于所有变量定义（成员变量、局部变量、`for` 循环变量）以及函数 / 闭包 / lambda 参数名。

```sl
# var new = 5       # 错误 20287：new 是关键字
# string string = "x"  # 错误 20287：string 是基本类型关键字
# var var = 5       # 错误 20287：var 是关键字
# int global = 5    # 错误 20287：global 是关键字
# static f( int if ) # 错误：参数名 if 是关键字
var ok = 1          # 正确
```

1. **关键字与基本类型词禁用**：`if` / `new` / `static` / `this` … 与 `int` / `string` / `object` / `bool` / `float` / `double` / `byte` / `short` / `long` 等全部是关键字，Node 解析层直接报 `NodeStructParseNameIsKeyword` (20287)。全表见 [keywords.md](./keywords.md) §1。
2. **限定前缀是合法用法**：`this._value = b`、`base.x`、`local.a`、`global.x = 5` 里的这些词是前缀（后跟成员访问链），不是变量名；单独写成 `int global = 5` 才报错。
3. **非本语言关键字直接拦截**：`let` / `def` / `lambda` / `return` / `foreach` … 在词法层报错并给出改写指引（20118 / 20119），例如 `let` 应写 `var` 或显式类型声明，见 [keywords.md](./keywords.md) §1.8。
4. **类成员名的额外两条**（局部 / 参数名不受此限）：
   - 不得与定义文件 `import` 下可索引的类名 / 命名空间名冲突（`MetaCoreMemberNameImportConflict` 23017，裸名解析时 import 平面会遮蔽成员）；
   - 不得使用小写容器构造糖名（`map` / `list` / `stack` / `hashset` / `queue` / `tuple` / `array` / `range`）与 Result 保留名 `error` / `errmsg`（11042）。
5. **标识符形态**：字母或下划线开头，后续字母 / 数字 / 下划线，区分大小写。`$` 属于字符串插值（`$name` / `${expr}`）与访问变量语法，不要用它给普通变量起名。

---

## 8. 错误码速查

| LID | 名称 | 触发场景 |
|-----|------|----------|
| 20287 | `NodeStructParseNameIsKeyword` | 变量名 / 参数名 / 成员名用了关键字或类型词 |
| 20118 / 20119 | 非本语言关键字拦截 | `return` / `let` / `def` / `lambda` 等误用 |
| 11042 | 类成员保留名冲突 | 成员名用容器糖名 / `error` / `errmsg` |
| 21100 | `MetaCoreCallShuldNotStatic` | 静态成员经实例 / `this` 访问 |
| 21103 | `MetaCoreCallSMemberVariable` | 非 const 实例成员经类名限定访问 |
| 21139–21142 | `MetaCoreClassExtend3..6` | 子类与继承链父类成员重名 |
| 21305 | `MetaCoreMemberVariableVariableExpressMember` | Create 阶段缺初始化表达式（「必须需要有等号及后续的表达式」） |
| 21372 | `MetaCoreAssignStatementConst` | const 左值再赋值（含 `=`、`+=` 等复合赋值、`++` / `--`） |
| 21391 / 21393 | `MetaCoreDefineVarStatementDuplicate(2)` | 局部变量重复定义 / 名字冲突 |
| 21395 | `MetaCoreDefineVarStatementIsNullTypeVariable` | 局部定义缺少初值，表达式返回类型为空 |
| 21468 | `MetaCoreParamConstToNonConst` | const 实参传给非 const 形参 |
| 21472 | `MetaCoreMemberVariableRequireInit` | 成员变量声明未初始化（如 `int v;`） |
| 23017 | `MetaCoreMemberNameImportConflict` | 成员名与 `import` 可索引名称重名 |

---

## 9. 实现锚点与测试用例

> 路径约定：Front 源码相对仓库根 `D:/project/lang/`；测试用例相对 `SlangAllInOne/`。

| 关注点 | 源码 / 用例 |
|--------|-------------|
| 变量基类、`EVariableFrom`、`isExplicitConst`、parseLevel | `simple_language/source/Core/MetaVariable.cs` |
| 成员定义、名称冲突自检、必须初始化 | `simple_language/source/Core/MetaMemberVariable.cs` |
| 继承链成员扁平化与重名检查 | `simple_language/source/Core/MetaClass.cs` (`HandleExtendMemberVariable`) |
| 局部定义、类型推导、重复定义 | `simple_language/source/Core/Statements/MetaDefineVarStatements.cs` |
| 块作用域字典与向上查找 | `simple_language/source/Core/Statements/MetaBlockStatements.cs` |
| 赋值语句与 const 左值拦截 | `simple_language/source/Core/Statements/MetaAssignStatements.cs` |
| const 传参约束 / 形参 const | `simple_language/source/Core/MetaParam.cs` |
| 定义语句解析、关键字校验、同行右值 | `simple_language/source/Parse/StructParseToSyntax.cs` |
| `flags` 16=const / 32=static 导出 | `simple_language/source/Export/SLIR/SLModulePackageWriter.cs` |
| 成员 / 继承 / 静态槽用例 | `SLangCore/test/BaseTest/MemberVariable1Test.sl`、`MemberVariable2Test.sl` |
| `global` 用例 | `SLangCore/test/BaseTest/GlobalTest.sl` |
| const 用例 | `SLangCore/test/Other/ConstProbe/`（ConstLib / ConstProbe / ConstLocal / ConstCross） |
| `local{}` 作用域用例 | `SLangCore/test/BaseTest/LocalTest1.sl`、`LocalTest2.sl` |

**相关文档**：[keywords.md](./keywords.md)（关键字）、[class.md](./class.md)（类 / this / 继承）、[object.md](./object.md)（对象创建）、[local.md](./local.md)（文件级）、[global.md](./global.md)（工程级）、[data.md](./data.md)（data 成员）、[function.md](./function.md)（形参与闭包）、[type.md](./type.md)（类型系统）、[../SL语法与编码规范总表.md](../SL语法与编码规范总表.md) §4.2（四层作用域速查）。
