# bind 关键字

`bind` 用于把一个或多个 `data` 绑定到 `class` 或 `interface` 上，在编译阶段自动展开为成员变量、字段访问器（get/set）、数据访问器和 `_init_` 重载。

绑定后的效果可以理解为：给类型增加一组受约束的数据字段与访问入口，便于统一数据组织和处理。

> 限制：`bind` 只能用于 `class` 和 `interface`，不能用于 `data` 或 `enum` 定义上（会报错）。

---

## 1. 基本语法

`bind` 后面必须跟 `data` 类型名，支持多个，以逗号分隔（逗号前后可加空格也可不加）。`data` 可以是普通 `data`，也可以是 `const data`。

`bind` 子句放在类型名之后、基类/接口子句之前或之后均可，与 `interface` 关键字可自由组合：

```sl
data DataA
{
    a = 20
}
data DataB
{
    b = 100
}
class ClassName bind DataA, DataB
{
    # class body
}

interface InterfaceName bind DataA, DataB
{
    # interface body
}

const data ConfigData
{
    port = 8080
}

# bind 与 interface 组合，顺序不限
class Service bind ConfigData interface SomeInf
{
}
class Service2 interface SomeInf bind ConfigData
{
}
```

使用：

```sl
class LogicC
{
    static fun()
    {
        ClassName cn = new()

        cn.DataA.a = 100
        int b = cn.DataB.b
        b2 = cn.b               # 直接访问
        var db = cn.DataB        # 直接访问 DataB 的定义
    }
}
```

要点：

- 一个类型可以 `bind` 任意多个 `data`，数量没有上限（仅受继承链深度约束，见 §6）。
- 被 `bind` 的 `data` 必须在当前工程内可访问（同命名空间或已 `using`）。
- `const data` 同样可以 `bind`，绑定后的字段访问/赋值行为与普通 `data` 一致。

---

## 2. 绑定到 class 的展开语义

当 `class` 绑定了 `data` 后，编译器自动在类内注入以下合成成员：

### 2.1 成员变量

为每个被绑定的 data 生成一个内部成员变量：

```sl
data DA { a = 20; b = 30 }
data DB { a2 = 100; b2 = 100 }

class CA bind DA, DB
{
}

#! 等价于自动注入：
class CA
{
    DA _DA = new()
    DB _DB = new() 
}
!#
```

### 2.2 字段访问器（get/set）

为每个 data 的字段生成 get/set 代理方法：

```sl
#! 自动注入等价于：
class CA
{
    get int a() { ret this.DA.a }
    set void a( int _a ) { this.DA.a = _a }
    get int b() { ret this.DA.b }
    set void b( int _b ) { this.DA.b = _b }
    get int a2() { ret this.DB.a2 }
    set void a2( int _a2 ) { this.DB.a2 = _a2 }
    get int b2() { ret this.DB.b2 }
    set void b2( int _b2 ) { this.DB.b2 = _b2 }
}
!#
```

因此可以：

```sl
CA c = new()

# 绑定名访问
int v1 = c.DA.a
int v2 = c.DB.a2

# 直访（由 get/set 代理）
int v3 = c.a
int v4 = c.a2

# 直访写入
c.a = 50
c.a2 = 500
```

### 2.3 数据访问器

为每个绑定的 data 生成数据访问器，可通过 `类名Data()` 方法直接访问内部 data 实例：

```sl
#! 自动注入等价于：
class CA
{
    get DA DAData() { ret this.DA }
    set void DAData( DA _data ) { this.DA = _data }
    get DB DBData() { ret this.DB }
    set void DBData( DB _data ) { this.DB = _data }
}
!#
```

### 2.4 _init_ 重载

自动为 1 到 N 个参数（N 为绑定的 data 个数）生成 `_init_` 重载：

```sl
class CA bind DA, DB
{
}

#! 自动注入等价于：
class CA
{
    _init_( DA _t1 ) { this.DA = _t1 }
    _init_( DA _t1, DB _t2 ) { this.DA = _t1; this.DB = _t2 }
}
!#

# 使用
CA c1 = CA(daInstance)
CA c2 = CA(daInstance, dbInstance)
```

若类已有相同参数数量的 `_init_`，则自动跳过（不覆盖）。

---

## 3. 两种访问方式详解

绑定后每个 data 字段都同时拥有两种访问入口，可任选其一：

| 访问方式 | 写法 | 说明 |
|----------|------|------|
| 绑定名访问 | `obj.DataName.field` | 显式指定来自哪个 data，语义清晰、无歧义 |
| 字段直访 | `obj.field` | 由生成的 get/set 代理，写起来更简洁 |

```sl
BookC bc = new()

# 直访
bc.name = "hahah"
int p = bc.price

# 绑定名访问（等价于上面的底层数据）
bc.BookData.name = "hahah"
int p2 = bc.BookData.price
```

两种写法指向的是同一份底层数据，改动互相可见：

```sl
BookC bc = new()
bc.BookData.name = "bind-name-access"
global.println(bc.name)          # "bind-name-access"（与绑定名访问同步）
```

**何时优先用绑定名访问**：当存在同名字段冲突、或需要强调字段归属（例如来自不同 data 的同名字段）时，用 `obj.DataName.field` 能明确区分来源，避免歧义。

数据访问器（`obj.DataName`，即 §2.3 的 `DAData()` 等方法）返回的是内部 data 实例本身，可以整体替换、传递给方法，或读取其全部字段：

```sl
BookC bc = new()
BookData snapshot = bc.BookData   # 拿到内部 data 实例
bc.BookData = newBookData         # 整体替换为新实例
```

---

## 4. 同名字段冲突与重写

如果多个绑定 `data` 中存在同名成员，或与 `class` 自身成员重名，编译器会跳过自动生成该字段的 get/set（输出告警），需要开发者手动实现。

```sl
data DA { a = 20 }
data DB { a = 30 }

class CA bind DA, DB
{
    # 冲突重写策略：统一优先映射到 DA.a
    get a() { ret this.DA.a }
    set a( int v ) { this.DA.a = v }
}

CA c = new()
global.println(c.a)     # 20（DA.a 的值）
c.a = 99
global.println(c.DA.a)  # 99
```

如果类自身已定义了同名字段或同名函数，自动注入也会静默跳过，由开发者决定映射逻辑。

> 建议：冲突字段务必手动实现 get/set，并在注释中说明映射到的目标 data，方便后续维护。

---

## 5. 绑定到 interface 的语义

`interface` 也可以绑定 `data`，展开为**抽象** get/set（无函数体）：

```sl
data DA { a = 20, b = 30 }

interface INF bind DA
{
    # 自动注入抽象访问器等价于：
    # int get a()
    # void set a( int _a )
    # int get b()
    # void set b( int _b )
}
```

接口中的默认方法可以直接访问绑定数据成员：

```sl
public interface CalcPrice bind BookData
{
    float calc()
    {
        ret this.price * 1
    }
}
```

> 注意：接口绑定后，其默认方法体里可以直接写 `this.price` 这样的绑定字段访问；实现类也必须绑定同一 data 才能通过编译（见 §6）。

---

## 6. 接口约束

当接口 `bind` 了某 `data`，实现该接口的类也必须 `bind` 同一 `data`（直接或等价方式），否则编译报错。

```sl
const data BookData
{
    name = "ABC"
    price = 20
}

public interface CalcPrice bind BookData
{
    float calc() { ret this.price * 1 }
}

public class SeltBookData bind BookData interface CalcPrice
{
    public int count = 20

    override float calc()
    {
        ret this.price * this.count
    }
}
```

这样接口方法内可以直接使用 `this.price`，因为接口和实现类都绑定了 `BookData`。

完整可运行示例（接口与类都 `bind` 同一 `data`，接口方法对绑定字段做计算）：

```sl
data VecData2 { x = 0.0f, y = 0.0f }

interface IVector2 bind VecData2
{
    float addVector(VecData2 other);
    float length();
}

class Vector2 interface IVector2 bind VecData2
{
    override float addVector(VecData2 other)
    {
        ret this.x + other.x + this.y + other.y;
    }
    override float length()
    {
        ret (this.x * this.x) + (this.y * this.y);
    }
}

local
{
    Vector2 a = new()
    a.x = 1.0f
    a.y = 2.0f
    Vector2 c = new()
    c.x = 5.0f
    c.y = 6.0f
    global.println("len=" + a.length())        # 5.0 (1+4)
    global.println("sum=" + a.addVector(c))     # 14.0 (1+5+2+6)
}
```

---

## 7. 继承链中的 bind

如果类有继承关系，编译器会递归收集祖先链上的所有 bind（最大深度 32 层），去重后统一展开。子类不会重复生成祖先已绑定的 data 成员。

```sl
data BaseData { id = 0 }
data ExtraData { tag = "" }

class Base bind BaseData
{
}

class Derived bind ExtraData : Base
{
    # 同时拥有 BaseData.id 与 ExtraData.tag
}

Derived d = new()
d.id = 1            # 来自基类绑定的 BaseData
d.tag = "x"         # 来自自身绑定的 ExtraData
```

---

## 8. 综合示例

```sl
const data BookData
{
    name = "ABC"
    pageCount = 20
    price = 20
}

data BP
{
    width = 30
    height = 40
}

# 类 bind 多个 data
BookC bind BookData, BP
{
}

# 接口 bind data
public interface CalcPrice bind BookData
{
    float calc() { ret this.price * 1 }
}

# 类 bind + 接口
public class SeltBookData bind BookData interface CalcPrice
{
    public int count = 20
    override float calc() { ret this.price * this.count }
}

# 冲突重写
data DA2 { a = 1 }
data DB2 { a = 2 }

BindConflictClass bind DA2, DB2
{
    get a() { ret this.DA2.a }
    set a( int v ) { this.DA2.a = v }
}

# 使用
BookC bc = new()
bc.name = "hahah"              # 直访 BookData.name
bc.width = 20                  # 直访 BP.width
bc.height = 40                 # 直访 BP.height

# 绑定名访问
bc.BookData.name = "bind-name-access"
bc.BP.width = 101
bc.BP.height = 202
```

---

## 9. 使用技巧与注意事项

1. **优先用 `bind` 替代"手写数据搬运类"**：当你需要把一个 `data` 的字段直接暴露成一个类的字段时，`bind` 能省掉大量重复的 get/set 样板代码。典型场景：把配置 `data`（`const data`）、DTO、状态结构直接挂到业务类上。

2. **配置中心模式**：把一组常量配置定义成 `const data`，再 `bind` 到需要用到它的服务类，即可像访问普通字段一样读取配置，又保持了配置集中定义。

   ```sl
   const data DbConfig
   {
       host = "127.0.0.1"
       port = 3306
   }
   class Repository bind DbConfig
   {
       void connect()
       {
           global.println("connect to " + this.host + ":" + this.port)
       }
   }
   ```

3. **字段直访 vs 绑定名访问的选择**：无冲突、追求简洁时用 `obj.field`；存在同名字段、或想强调字段来源时用 `obj.DataName.field`，可读性和无歧义性更好。

4. **冲突字段一定要手动实现**：同名冲突只会告警并跳过自动生成，若不在类里手动补 get/set，访问该字段会编译失败。务必明确映射目标（例如固定映射到第一个 data）。

5. **接口约束要成对出现**：只要接口 `bind` 了某 `data`，所有实现类都必须 `bind` 同一 `data`，否则编译报错。把"数据约束"通过接口传递，可以保证实现类一定具备所需字段。

6. **`_init_` 重载不会覆盖已有构造**：如果你已经手写了对应参数数量的 `_init_`，编译器会自动跳过生成，不会覆盖你的实现。

7. **内部 data 实例可被整体替换**：通过数据访问器（`obj.DataName = newData`）可以把绑定 data 整体换成新实例，适合需要重置或切换数据源的场景。

---

## 10. 设计目的

`bind` 的主要价值：

1. **数据结构绑定**：将 `data` 的字段自动注入到类中，避免手写大量样板代码。
2. **统一访问入口**：提供绑定名访问（`c.DataName.field`）和字段直访（`c.field`）两种方式。
3. **接口约束传播**：通过接口绑定，把"数据约束"提升为类型约定，确保实现类具备所需数据字段。
4. **冲突可重写**：同名字段冲突时由开发者手动决定映射策略，保证灵活性。

---

## 11. 对照测试

可参考测试样例：

- [SLangCore/test/BaseTest/BindDataTest.sl](../../SLangCore/test/BaseTest/BindDataTest.sl) — 多 data 绑定、字段直访、绑定名访问、冲突重写、接口 bind + 类 bind
- [SLangCore/test/BaseTest/InterfaceDataAndBindData.sl](../../SLangCore/test/BaseTest/InterfaceDataAndBindData.sl) — 接口和实现类都 bind 同一 data、接口默认方法访问绑定字段的标准用法
