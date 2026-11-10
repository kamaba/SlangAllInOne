# 标签与跳转（label / goto）

`label` 用于给一个位置命名，`goto` 用于跳转到该位置。二者通常成对出现，用来在普通顺序控制流之外做定向跳转（例如跳出深层嵌套、集中收尾、异常兜底）。

## 1. 基本用法

- `label 名称;` 声明一个标签（不带动任何代码，单独成句）。
- `goto 名称;` 跳转到同函数内该标签所在位置。
- 标签名与变量名同名规则一致（字母 / 数字 / 下划线，不以数字开头，不能是关键字）。

```sl
function process()
{
    for (int i = 0, i < 10, i = i + 1)
    {
        for (int j = 0, j < 10, j = j + 1)
        {
            if (i * j > 20)
            {
                # 内层条件满足时，直接跳出两层循环
                goto done
            }
        }
    }
label done;
    Console.println("done")
}

process()
```

> 说明：`goto done` 只能跳到**同名标签所在位置**。因为 `done` 定义在函数末尾，这里实现的是「满足条件就直接结束循环并收尾」的效果。

## 2. 跨函数跳转（限定名）

同一函数内的标签可直接用名字跳转；要跳到**别的全局函数里的标签**，需要写全限定名：`命名空间.类.函数.标签名`。

```sl
# 在另一个函数里跳回全局函数 MyTool.cleanup 的标签
function main()
{
    # ... 处理过程中遇到致命错误 ...
    goto MyTool.cleanup
}

namespace MyTool
{
    function cleanup()
    {
        # 统一的收尾逻辑
        Console.println("cleanup")
    label cleanup;
    }
}

main()
```

> 约定：限定名按 `命名空间.类.函数.标签名` 顺序写。类与命名空间可省略（当函数处在对应作用域时）；标签名永远写在最后。

## 3. 块形式标签（try / finally 捕获）

标签不仅能单独成句，也能包住一段代码块：

```sl
label exit
{
    # 这块代码里的执行路径都可以用 goto exit 提前离开
    if (arg == null)
    {
        goto exit
    }
    # ... 正常处理 ...
}
# 离开块之后从这里继续
```

块形式标签最典型的用途是和 `try / finally` 配合，确保异常发生时也能执行收尾：

```sl
function load()
{
label finallyBlock;
    try
    {
        # 可能抛异常的逻辑
        openResource()
    }
    catch (Exception e)
    {
        Console.println(e.message)
        goto finallyBlock      # 把异常路径也引向同一段收尾
    }
    finally
    {
finallyBlock:
        closeResource()        # 正常 / 异常都会执行到
    }
}

load()
```

## 4. 常见写法与注意点

- **`goto` 只接受标签名**，后面跟 `;`，例如 `goto retry;`。不能写成 `goto(名称)` 或 `goto 表达式`。
- **标签作用域以函数为界**：同函数内用短名即可；跨函数必须写 `命名空间.类.函数.标签名`。
- **不要跳进作用域内部**：`goto` 的目标标签必须位于当前函数的合法控制流可达位置（不能从函数外跳入某个局部变量仍未初始化的块里）。
- **函数内裸块 `{}` 不再支持**：想给一段代码命名收尾，请用 `label 名称 { ... }` 块形式，而不是裸 `{}`。
- 与 `for` / `while` / `switch` 自带的中断语句不同：`label`/`goto` 是更底层的定向跳转，适合「多层 `break` 做不到」的场景；普通循环请用 `break` / `continue`，可读性更好。

## 5. 完整示例

```sl
# 读取直到遇到空行或达到上限，两种退出都走同一段收尾
function readLines(int maxCount)
{
    int count = 0
    for (int i = 0, i < maxCount, i = i + 1)
    {
        var line = nextLine()
        if (line == "")
        {
            goto finish
        }
        Console.println(line)
        count = count + 1
    }
label finish;
    Console.println("read " + count + " lines")
}

readLines(5)
```

> 库参考：标准库 `System` 命名空间下的异常 / 资源相关类型（如 `Exception`）配合 `try / catch / finally` 使用，详见 [`../lib/Core/`](../lib/Core/) 对应文档。
