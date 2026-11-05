# 模板（Templates / Generics)

S 语言支持模板（泛型）用于类和函数，允许在定义时参数化类型，从而在编译期间为不同类型生成具体实现。

主要特性：
- 模板类（`class<T>`）在实例化时替换类型参数生成具体类。
- 模板函数（`RetType Name<T>(...)`，类型参数表跟在函数名后）在调用时根据类型参数生成具体函数实例。
- 支持模板约束（`extends` / `in` 样式），用于限制模板参数必须满足的基类或接口。
- 模板类型的成员变量**必须显式初始化**：定义期类型参数还没有具体类型，初始值只能写 `= null` 或 `= new()`，不能省略、也不能写字面量。

模板类示例：

```s
class Box<T> {
    T value = null;
    _init_(T v) { this.value = v; }
}

// 使用：Box<Int32> 在编译/元模型阶段生成具体 Box<Int32>
var b = Box<Int32>(10);
```

模板类继承与嵌套：

```s
class Pair<T1, T2> {
    T1 first = null;
    T2 second = new();
}

class PairList<T> extends List<Pair<T, T>> { }

var pl = PairList<Int32>();
```

> **模板字段初始化必写，且只能用 `null` / `new()`**：`T1 first;` 这种省略 `= 初始值` 的写法不通过编译（LID 21472 `MetaCoreMemberVariableRequireInit`）。模板参数在定义期还没有具体类型，字段初始值只能写 `null`（空引用）或 `new()`（按字段类型创建实例）；`Pair` 的 `first` / `second` 分别示范了这两种写法。

模板函数示例：

```s
T identity<T>(T x) { ret x; }

var a = identity<Int32>(10);
```

模板约束：

```s
T sumAll<T extends Number>(List<T> vals) { /* ... */ }
```

实现细节（元模型相关）：
- 模板参数可以带约束，编译器在 `MetaTemplate` 层面记录这些约束，并在实例化时校验。
- 模板函数与模板类的生成会影响 parseLevel 与绑定顺序（模板优先、类模板次之、普通函数最后）。