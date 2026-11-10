# 宏（macro）

`macro` 是**编译期**确定的全局只读配置。你在工程里声明一组键值，编译时这些值被注入代码；运行时代码像读取普通全局变量一样使用它们，常用于「同一份源码，按工程切换行为 / 版本 / 开关」。

## 1. 核心概念

- `macro` 来自**工程配置**（`.jsonc` 文件里的 `macro` 段），不是运行时变量。
- 编译完成后，代码里引用的 `global.macro.名称` 已经是编译期代入的具体值。
- 运行时它表现为一个**只读全局对象**：可读，不可改。

## 2. 定义 macro

在工程的 `.jsonc` 配置里加一个 `macro` 段：

```jsonc
{
  "name": "MyApp",
  "macro": {
    "useFastMath": true,
    "appVersion": "1.2.3",
    "maxRetry": 3
  }
}
```

## 3. 使用 macro

在代码里通过 `global.macro.名称` 读取，**像普通变量一样参与表达式与判断**：

```sl
# 编译期已代入具体值，运行时直接当作只读全局使用
if (global.macro.useFastMath)
{
    Console.println("using fast math")
}
else
{
    Console.println("using precise math")
}

Console.println("version = " + global.macro.appVersion)
```

- 因为是只读全局，直接读取即可，**不需要也不能**用条件编译语法去「选择是否编译某段代码」。
- 值类型支持布尔 / 数字 / 字符串等；读取后按对应类型使用。

## 4. 完整示例

`app.jsonc`：

```jsonc
{
  "name": "MyApp",
  "macro": {
    "enableLog": true,
    "buildTag": "release"
  }
}
```

`app.sl`：

```sl
function log(string msg)
{
    if (global.macro.enableLog)
    {
        Console.println("[${global.macro.buildTag}] " + msg)
    }
}

function main()
{
    log("start")
    # ... 业务逻辑 ...
    log("done")
}

main()
```

- 同一份 `app.sl`，把 `enableLog` 改成 `false` 重新编译，日志分支即被关闭——无需改动业务代码。

## 5. 常见写法与注意点

- **只读**：`global.macro.x = ...` 不合法；macro 是编译期定值，运行期不可改写。
- **区分大小写**：`global.macro.useFastMath` 与 `global.macro.usefastmath` 不是同一个键。
- **必须先声明**：引用了工程 `.jsonc` 里没定义的 `macro` 键会编译报错。
- **适合做什么**：功能开关、版本号、平台 / 构建标签、容量上限等「编译期可知」的配置。运行期才确定的值请用普通变量 / 配置读取，不要用 macro。
- 调试时可在代码里 `Console.println(global.macro.键名)` 打印代入后的值，确认编译期注入是否符合预期。
