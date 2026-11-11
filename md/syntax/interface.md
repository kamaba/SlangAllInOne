# 接口（interface）

`interface` 用于定义一组方法 / 数据成员的契约。实现该接口的类必须提供这些成员，从而让「不同类型」以统一的方式被调用。

## 1. 定义接口

接口里只写「签名」：方法不写函数体，数据成员只声明类型。也可以给方法一个**默认实现**，实现类可以选择覆盖它。

```sl
interface IFly
{
    # 方法签名（无实现）
    void fly()

    # 带默认实现的方法；实现类可覆盖
    int maxAltitude()
    {
        ret 100
    }
}
```

- 接口本身是抽象契约，不能直接 `new` 出来；它描述「能做什么」。
- 方法默认实现是可选的；一旦写了函数体，就是对实现类给出的缺省行为。

## 2. 实现接口

类用 `: 接口名` 声明「实现该接口」，并把接口要求的成员全部补上。

```sl
class Bird extends IFly
{
    int version = 1

    void fly()
    {
        Console.println("bird is flying")
    }

    # maxAltitude 接口已有默认实现，这里选择覆盖
    override int maxAltitude()
    {
        ret 500
    }
}
```

- 接口要求的**抽象方法**必须实现；**有默认实现的方法**可以不写（沿用缺省），也可以 `override` 覆盖。
- 一个类**只能实现一个接口**（单继承）。

## 3. 使用接口（多态调用）

把实现类实例当作接口类型来使用，靠 `as` 转换：

```sl
function main()
{
    Bird b = new()
    IFly f = b as IFly      # 以接口视角看待这个对象
    f.fly()                 # 调用 Bird 的实现
    Console.println(f.maxAltitude())
}

main()
```

> 这样写的好处：只要类型实现了 `IFly`，就能放进同一个 `IFly` 参数 / 变量里，调用方无需关心具体类型。

## 4. 接口继承

一个接口可以继承多个接口，把多组契约合并：

```sl
interface IAnimal
{
    void eat()
}

interface IFly extends IAnimal
{
    void fly()
}

class Bird extends IFly
{
    void eat()  { Console.println("bird eating") }
    void fly()  { Console.println("bird flying") }
}
```

## 5. 完整示例

```sl
interface IShape
{
    double area()
}

class Circle extends IShape
{
    double r = 0.0d
    void _init_(double r) { this.r = r }
    double area() { ret 3.14159d * r * r }
}

class Square extends IShape
{
    double side = 0.0d
    void _init_(double side) { this.side = side }
    double area() { ret this.side * this.side }
}

function printArea(IShape s)
{
    Console.println(s.area())
}

function main()
{
    printArea(Circle(2.0))
    printArea(Square(3.0))
}

main()
```

## 6. 常见写法与注意点

- **不能直接实例化接口**：`new IFly()` 不合法；要 `new` 实现类，再用 `as` 转成接口类型。
- **单继承**：一个类只能实现一个接口；需要多组能力时，让接口去继承多个接口（见 §4）。
- **成员必须全部满足**：抽象方法漏实现会编译报错。
- 接口非常适合做「插件式」设计：核心逻辑只依赖接口，具体类型可自由替换。
