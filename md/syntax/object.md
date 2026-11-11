# 类与对象（class / object）

`class` 是组织状态（字段）与行为（方法）的基本单元；`object` 泛指运行时的实例。本文讲如何定义类、构造对象、使用属性与方法、做类型判断与转换。

## 1. 定义类与字段

```sl
class Point
{
    int x = 0
    y = 0
}
```

- 字段在类体内声明，可在声明处直接赋初值：`int x = 0`。
- 字段默认带访问控制（见 §5），未显式声明时按默认可见性。

## 2. 构造函数 `_init_`

构造逻辑写在名为 `_init_` 的方法里；调用时通过 `new 类名(实参)` 触发。

```sl
class Point
{
    x = 0
    y = 0

    void _init_(int x, int y)
    {
        this.x = x
        this.y = y
    }
}

function main()
{
    Point p = new(10, 20)   # 必须写 new
    Console.println(p.x)
}

main()
```

- 不写 `_init_` 时会有默认无参构造。
- `this` 指向当前对象，用于区分同名字段与参数。

## 3. 创建对象

- **必须写 `new`**：`Point(10, 20)` 合法；`Point(10, 20)` 不合法。
- **字面初始化**：构造后立刻给字段赋值，用 `{ 字段 = 值 }`：

```sl
Point p2 = new(0, 0){ x = 5 }
```

- **空对象**：`new Object()` 得到一个无字段的基类对象，可后续当字典用。

## 4. 属性（get / set）

用 `get` / `set` 把「读写某个值」包装成方法，调用时像字段一样自然：

```sl
class Counter
{
    int _n = 0

    int get count() { ret this._n }
    void set count(int v)
    {
        if (v >= 0) { this._n = v }
    }
}

function main()
{
    Counter c = new Counter()
    c.count = 3          # 实际调用 set count
    Console.println(c.count)   # 实际调用 get count
}

main()
```

- `get` / `set` 是**保留方法名**，不能当作普通成员名（见 [keywords.md](./keywords.md)）。
- 只读属性只写 `get` 即可；只写 `set` 则是只写属性。

## 5. 方法与方法重写

```sl
class Animal
{
    void speak()
    {
        Console.println("some sound")
    }
}

class Dog : Animal
{
    override void speak()
    {
        Console.println("woof")
    }
}

function main()
{
    Dog d = new()
    d.speak()            # 输出 woof
}

main()
```

- 子类覆盖父类方法要加 `override`。
- 没有 `virtual` 关键字：`override` 本身就是覆盖声明。

## 6. 访问控制

字段 / 方法可加可见性前缀（如 `public` / `private` 等，按工程约定）。常见用法：

```sl
class Account
{
    private int balance = 0

    public void deposit(int amount)
    {
        this.balance = this.balance + amount
    }

    public int getBalance() { ret this.balance }
}
```

> 具体可见性关键字以工程配置为准；未显式声明时按默认规则生效。

## 7. 类型判断与转换（is / as）

```sl
Object obj = new(1, 2)

if (obj is Point)
{
    Point p = obj as Point      # 转换成功后按目标类型使用
    Console.println(p.x)
}
```

- `is` 判断对象是否属于某类型（也可配合模式 `is int n` 直接取出值）。
- `as` 把对象转成目标类型；类型不匹配时为 `null`，使用前请先做 `is` 判断。

## 8. 嵌套类与命名空间

类可以放在 `namespace` 下，也可以嵌套：

```sl
namespace Geometry
{
    class Point
    {
        x = 0
        y = 0
    }
}

# 使用带命名空间的全名
Geometry.Point p = new(1, 2)
```

## 9. 常见写法与注意点

- **构造必须 `new`**：这是本语言与部分语言的不同之处，省略 `new` 会编译报错。
- `this` 只在实例方法 / 构造 / 属性里可用，用于区分同名参数与字段。
- 所有对象都派生自 `Object`，因此 `Object` 上的通用方法（如 `equals`、`toString`、`getTypeName`、`hashCode`）都可调用：

```sl
Point p = Point(1, 2)
Console.println(p.toString())
Console.println(p.getTypeName())
```
