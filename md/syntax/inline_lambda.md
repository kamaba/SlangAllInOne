# 内联 Lambda（inline lambda）

内联 lambda 是「写在某函数体内部的匿名函数」，可以当作值传递、被立即或稍后调用，并捕获外层局部变量。它与普通 `function` 的关键区别在于：**lambda 完全活在「外层函数的作用域」里**，因此 `return` / `goto` 只能作用于自身，不能跳出外层函数。

## 1. 两种写法

```sl
# 语句块形式
var f = function(x, y)
{
    ret x + y
}

# 表达式（箭头）形式
var g = (x, y) => x + y
```

- 语句块形式用 `function(参数) { ... }`，内部用 `ret` 返回。
- 箭头形式用 `(参数) => 表达式`，表达式的值即返回值。
- 参数可省略类型（按调用处推导），也可写强制类型：`(int x, int y) => x + y`。

## 2. 调用

```sl
var f = (x, y) => x + y
var r1 = f(1, 2)          # 3

# 也可以「定义即调用」
var r2 = ((x) => x + 1)(5) # 6
```

## 3. 闭包（捕获外层变量）

lambda 可以读写外层函数的局部变量：

```sl
function counter()
{
    int n = 0
    var inc = function()
    {
        n = n + 1          # 捕获并改写外层局部变量 n
        ret n
    }
    Console.println(inc())  # 1
    Console.println(inc())  # 2
}

counter()
```

> 捕获的是**变量本身**（引用语义），而非取值快照；在 lambda 内修改会影响外层。

## 4. 作为回调 / 参数

lambda 常用作回调、排序比较器等：

```sl
# 作为比较器传给排序
var list = [3, 1, 2]
sort(list, (a, b) => a - b)

# 作为事件 / 任务体
var task = () => Console.println("running")
task()
```

## 5. 与泛型、接口、匿名类配合

```sl
# 作为接口方法的实现传入
interface ICalc
{
    int run(int x)
}

function use(ICalc c)
{
    Console.println(c.run(10))
}

```

## 6. 限制（重要）

内联 lambda 必须和外层函数处于**同一个函数作用域**，因此有以下约束：

- **不能用 `return` 跳出外层函数**：lambda 里的 `return` 只从 lambda 自身返回。
- **不能用 `goto` 跳出外层函数**：lambda 里的 `goto` 只作用于其内部标签。
- **不能调用外层函数的标签**：即便用 `外层.函数.标签` 限定名，lambda 内也不允许 `goto` 到外层标签。
- **`this` 不在捕获列表里**：在实例方法里写 lambda 要用 `this` 时，先把它捕获到一个局部变量再使用：

```sl
class Box
{
    int value = 10
    void demo()
    {
        var self = this          # 先捕获
        var read = () => self.value
        Console.println(read())
    }
}
```

## 7. 与具名 function 的差异

| 维度 | 内联 lambda | 具名 `function` |
|------|-------------|-----------------|
| 定义位置 | 函数体内部 | 文件 / 类作用域 |
| `return` / `goto` | 仅作用于自身 | 可跳出 / 跳转外层 |
| 跨作用域 | 不行，必须同函数 | 可跨函数（配合标签限定名） |
| 典型用途 | 回调、闭包、临时逻辑 | 复用逻辑、需要复杂控制流 |

## 8. 完整示例

```sl
function makeAdder(int base)
{
    # 返回一个「加 base」的闭包
    var add = function(int x)
    {
        ret x + base
    }
    ret add
}

function main()
{
    var add10 = makeAdder(10)
    Console.println(add10(5))     # 15

    var nums = [5, 2, 8, 1]
    sort(nums, (a, b) => a - b)
    Console.println(nums)         # [1, 2, 5, 8]
}

main()
```

## 9. 常见错误

- 在内联 lambda 里写 `return` 想跳出外层函数 —— 编译报错（return 只作用于 lambda 自身）。
- 在内联 lambda 里写 `goto` 想跳出外层函数、或 `goto` 到外层标签 —— 编译报错。
- lambda 写在了外层函数作用域之外（如单独成文件顶层、跨函数引用） —— 编译报错。
- 实例方法里的 lambda 直接使用 `this` —— 先捕获到局部变量再使用。
