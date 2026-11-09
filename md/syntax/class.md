## 类的定义

类定义用于声明对象的结构（字段）与行为（方法）。S 语言允许在顶层、`namespace` 内或其它类中嵌套定义类。

语法示例：

```s
# 简写形式
MyClass {
    # fields
    Int32 x = 0;
    String name = "";

    _init_()
    {
    }
}

# S 语言的类（class）

当你定义一个类时，你定义了一个数据类型的集合。类本身描述了对象的结构（成员变量/字段）、行为（成员函数/方法）、可见性、继承关系等。对象是类的实例。

---

## 一、类的定义与基本结构

S 语言支持多种形式定义类：

```s
# 简写形式
MyClass {
    Int32 x = 0;           // 成员变量（字段）
    String name = "";

    // 构造函数
    _init_(Int32 a) { this.x = a; }

    // 实例方法
    Int32 getX() { ret this.x; }

    // 静态方法
    static Int32 Zero() { ret 0; }
}

// 显式 class 关键字
class OtherClass { }
```

### 1.1 成员变量（字段）
- 支持基本类型、对象、数组、泛型等
- 可加访问修饰符（public/private/protected）
- 支持静态字段（static）

```s
public Int32 id = 0;
private String name = "";
static Float32_3 zero = new(0.0f, 0.0f, 0.0f);
```

### 1.2 成员函数（方法）
- 普通成员方法、静态方法（static）；子类替换父类方法须显式 `override` 重写（语言无 `virtual` 关键字，`interface` 不能用作类内函数修饰符）
- 支持重载、默认参数

```s
public void scale(Float32_3 s) { ... }
static Print(String msg, int v1 = 10) { ... }
override string toString() { ret "MyClass"; }
```

### 1.3 构造函数
- 统一用 _init_ 命名，可重载

```s
_init_() { ... }
_init_(Int32 a) { this.x = a; }
_init_(Float32[] arr) { ... }
```

### 1.4 静态成员
- 用 static 修饰，属于类本身

```s
public static Float32_3 one = new(1.0f, 1.0f, 1.0f);
static _main_() { ... }
```

### 1.5 访问修饰符
- public：公开（默认）
- private：仅类内可见
- protected：特殊作用域（标准库 Attribute.sl 即用 `protected` 修饰字段）

#### 1.5.1 类的导出权限（extern 标记）

类是否随模块包导出，由**类级显式标记**与工程配置共同决定：

- `extern class` / `extern data` / `extern enum`：显式导出标记，不受配置影响**恒导出**
- `public class` 与无标记 `class`：按工程配置决定是否导出（默认导出）
- `private` / `protected`：恒不导出
- 旧语法 `export class` / `export data` / `export enum` 的 `export` 关键字已不再表示导出权限，统一改用 `extern` 声明

```s
extern class LibApi { }        # 显式导出：恒导出
public class Helper { }        # 按配置
class Internal { }             # 按配置
private class Hidden { }       # 恒不导出
```

导出开关的工程配置详见工程配置文档。

### 1.6 继承与 final
- 继承：`class Child extends Parent {}`
- final：禁止被继承或重写

```s
final Application.MyClass2 { }
class MyChild extends MyClass { }
```

#### final 类与 final 方法（2026-10-02 已实现）

**final 类**：
- 语法：`final class X { ... }` 或 `final X { ... }`（final 置于 class 关键字/类名之前）
- 语义：final 类不允许被任何类 `extends` 继承；final 类本身可正常实例化、调用其成员
- final 仅允许用于 `class`；用于 `data` / `enum` / `interface` 会报错
- `abstract final` 组合无意义，会报错
- 跨模块同样约束：引用其它模块导出的 final 类时也无法继承

**final 方法**（详见 md/syntax/function.md）：
- 语法：`final int locked() { ... }`
- 语义：子类不允许 `override` 父类的 final 方法

```s
# final 类：禁止继承
final class SealedBase 
{
    int v = 0;
    int getV()
    {
        ret this.v
    }
    final int sealedGet()      # final 方法：禁止 override
    {
        ret this.v * 10
    }
}

# class SealedChild extends SealedBase { }   # 编译错误：不能继承 final 类

class MethodBase
{
    final int locked()
    {
        ret 100
    }
}

class MethodChild extends MethodBase
{
    # override int locked() { ret 200 }      # 编译错误：不能重写 final 方法
}
```

测试用例：`test/Other/FinalProbe/`（FinalLib 正向 / FinalProbe 拦截 / FinalCross 跨模块）。

### 1.6.1 类级修饰符使用范围（2026-10-11 FileMetaClass 解析期校验）

类型声明头部的修饰符按类型种类限定，非法组合会在编译期报错：

| 修饰符 | class | interface | data | enum |
|--------|-------|-----------|------|------|
| `abstract` | ✅ | ❌ | ❌ | ❌ |
| `final` | ✅ | ❌ | ❌ | ❌ |
| `static` | ❌ | ❌ | ✅（静态数据单例） | ❌ |
| `const` | ❌ | ❌ | ✅（只读数据） | ✅（只读枚举） |

- `static` 仅允许 `data`：`static data X { }` 表示静态数据单例（成员直接经类型名访问；data.md §3.4）；类成员的静态性用**成员级** `static` 修饰，不允许写在类型头
- `const` 仅允许 `data` / `enum`：`const data` 只读数据、`const enum` 只读枚举；class/interface 上使用会报错
- `abstract + final` 互斥：会报错
- 同一修饰符重复（如 `static static data`）会报错

### 1.7 泛型与嵌套类
- 泛型：`List<T> extends Object { ... }`
- 支持类中嵌套类、匿名对象、数组等

```s
class List<T> extends Object {
    T[] _items = new();
    add(T t) { ... }
}
```

### 1.8 接口实现与 override
- `interface` 写在类头（`extends` 之后）声明实现的接口：`class C extends P interface I1, I2 {}`
- 子类替换父类/接口方法必须显式 `override`（语言无 `virtual` 关键字）

```s
class C22 extends Application.CI2 {
    override int getback() { ret 100; }
}
```

### 1.9 this 关键字

`this` 指当前实例，可用于实例方法中访问成员、调用方法、作为实参传递等：

| 场景 | 示例 |
|------|------|
| 成员读/写 | `this.x` / `this.x = v`（含 get/set 访问器内） |
| 方法调用 | `this.method()` |
| 属性式 getter | `this.geta`（无括号） |
| 构造函数 `_init_` 内 | 与 `base._init_(...)` 混用 |
| `this?.x` 安全访问 | 当 this 可能为空时安全读取成员 |
| `ret this` 链式 | `this.add(1).add(2)` |
| this 作方法实参 | `Cls.staticFn(this, other)` |
| 协程 | `spawn this.方法` |
| 隐式 this | 在实例方法体内可直接写成员名，等价于 `this.xxx` |

**禁止/受限场景**：

- 静态方法（及静态方法中定义的闭包）内不能使用 `this`，会报错
- `this()` 这种构造器委托写法不支持，只能用 `base._init_(...)` 调用父类构造
- `this` 只能出现在访问链的开头
- `this` 不能作为变量名或参数名

**已知限制**：嵌套闭包的内层闭包不能直接引用外层捕获的变量与 `this`；内层闭包只能使用自身参数。


---

## 二、典型语法与用法示例

### 2.1 嵌套与命名空间

```s
namespace Application {
    MyClass {
        MyChildClass { }
    }
}

var amc = Application.MyClass();
var amcc = Application.MyClass.MyChildClass();
```

### 2.2 静态成员与静态方法

```s
public static Float32_3 zero = new(0.0f, 0.0f, 0.0f);
static Print(String msg) { ... }
```

### 2.3 构造与初始化

```s
var a = MyClass();
var b = MyClass(){ x = 10, name = "abc" };
```

### 2.4 继承、接口、多重继承

```s
class C22 extends Application.CI2 {
    override int getback() { ret 100; }
}
class C23 extends C22 {
    ...
}
Applicaction.C3 extends C22 interface Application.CI2, CI3 {
    ...
}
```

### 2.5 成员访问与链式操作

```s
obj.field = 10;
obj.method();
obj.child.field;
obj.array[0].field;
```

### 2.6 数据成员、匿名对象、数组

```s
data Profile {
    grade = 3;
    address = { city = "Shenzhen", zip = 518000 };
    tags = ["math", "final"];
}
```

### 2.7 枚举与常量

```s
enum DataKind { Base = 1, Advanced = 2 }
const data ScoreRule { passLine = 60, excellentLine = 90 }
```

---

## 三、特殊说明

- 支持 partial class、override 重写、接口、泛型、嵌套、匿名对象、静态/动态成员、数据成员、数组、枚举等
- 支持多种初始化方式（new、字面量、构造函数）
- 支持链式成员访问、静态成员直接访问、静态方法调用
- 支持多重继承（接口）、final 限定、访问修饰符
- 支持泛型集合、数组、对象数组、匿名对象数组
- 支持静态/动态成员混用

---

## 四、综合示例

```s
public class Float32_3 {
    public float[3] _value = new();
    public static Float32_3 zero = new(0.0f, 0.0f, 0.0f);
    public get Float32 x() { ret this._value[0]; }
    _init_() { ... }
    _init_(Float32 _x, Float32 _y, Float32 _z) { ... }
    void scale(Float32_3 _scale) { ... }
    static fun() { ... }
}

class List<T> extends Object {
    T[] _items = new();
    add(T t) { ... }
    remove(T t) { ... }
    clear() { ... }
}

// 继承、接口、final
final class MyFinalClass { }
class Child extends Parent { }
class MultiImpl extends Base interface IA, IB { }
```

---

## 五、常见用法速查

- 定义类：`class MyClass { ... }` 或 `MyClass { ... }`
- 静态成员：`static` 修饰
- 构造函数：`_init_`，可重载
- 继承：`class Child extends Parent {}`
- 接口实现：类头 `interface I1, I2` 标记
- final：`final class` 或 `final` 成员
- 访问修饰符：`public`/`private`/`protected`
- 类级导出标记：`extern class`/`extern data`/`extern enum`（恒导出，见 1.5.1）
- 泛型：`class List<T> { ... }`
- 嵌套类/命名空间：`namespace X { class Y { ... } }`
- 数据成员/匿名对象/数组/枚举：均支持

---

（如需更详细语法或特殊用法，请参考测试用例和源码实现）
