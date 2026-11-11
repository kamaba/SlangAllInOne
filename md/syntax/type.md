# 类型（Type）

S 语言提供强类型系统，包括基本类型与用户定义类型。每个值在运行时都可以通过 `.type` 取得对应的**类型对象**（`Core.Type`），用于反射判断、类型比较与类型信息读取。

基础类型（括号内为等价别名，见 `CoreMetaClassManager.GetSelfMetaName`）：
- 整数：`Int8/Int16/Int32/Int64`（别名 `sbyte`/`short`/`int`/`long`）
- 无符号整数：`UInt8/UInt16/UInt32/UInt64`（别名 `byte`/`ushort`/`uint`/`ulong`；另有内置全局别名 `Byte`→`UInt8`、`SByte`→`Int8`）
- 浮点：`Float32`、`Float64`（别名 `float`、`double`）
- 布尔：`Boolean`（别名 `bool`，`true` / `false`）
- 字符串：`String`（别名 `string`）

用户类型：
- `class`：引用类型，支持继承与方法重写
- `data`：记录/结构体样式的轻量数据类型
- `enum`：枚举类型
- `interface`：接口

泛型（模板）示例：

```s
List<Int32> list = List<Int32>(10);
fun<T> id(T x) { ret x; }
```

## `.type`：获取类型对象

任何变量、表达式、类名都可以通过 `.type` 取得运行时类型对象。`.type` 是自动调用语义，写 `x.type` 等价于 `x.type()`（与 `x.hashCode` 同机制）。

四种获取方式：

```s
# 1. 变量 / 表达式的运行时类型
Int32 i = 10
t1 = i.type                # Int32
t2 = (1 + 2.5).type        # Float64（表达式结果类型）

# 2. 类名的类型对象（含基础类型与用户类型）
t3 = Int32.type
t4 = String.type
t5 = Myclass.type          # 用户自定义类

# 3. 泛型形参 T 的实例化类型
fun<T> check(T x)
{
    tt = T.type            # 运行时按调用帧模板绑定解析出实例化类型
}

# 4. null 条件链上取类型（前置可能为 null 时）
Str s = null
t6 = s?.type               # s 为 null 时结果为 null，不抛错
```

对字面量同样适用，可用于确认后缀/进位字面量的实际类型：

```s
global.println(123i.type.toString())    # Int32
global.println(1.25f.type.toString())   # Float32
global.println(0x1A.type.toString())    # Int32
```

## Type 类型对象的成员

类型对象的定义见 `Lib/Core/Type.sl`，成员如下：

| 成员 | 签名 | 说明 |
|------|------|------|
| `eType` | `get int eType()` | 底层运行时类型枚举值（int）。见下方枚举表。 |
| `metaClass` | `get MetaClass metaClass()` | 元类对象，承载命名空间与类名信息。 |
| `metaClass.className` | `get string className()` | 类型名（不含命名空间前缀）。 |
| `typelist` | `public Type[] typelist` | 泛型实参的类型对象列表；非泛型类型为 `null`。 |
| `toString()` | `override string toString()` | 类型名字符串，泛型形如 `Level1<Int32><Int32Int64>` 样式拼接。 |

`MetaClass` 还提供 `_namespaceName`（命名空间），通过 `metaClass` 反射可读取：

```s
t = Int32.type
global.println(t.toString())              # Int32
global.println(t.eType.toString())        # 7
global.println(t.metaClass.className)     # Int32
```

### eType 枚举值

`eType` 返回 VM 内部运行时类型枚举（定义见 VM 的 `evm_type.h`），常用取值：

| 类型 | eType | 类型 | eType |
|------|-------|------|-------|
| Null | 0 | UInt32 | 8 |
| Void | 1 | Int64 | 9 |
| Boolean | 2 | UInt64 | 10 |
| UInt8 | 3 | Float32 | 15 |
| Int8 | 4 | Float64 | 16 |
| Int16 | 5 | Num | 17 |
| UInt16 | 6 | String | 18 |
| Int32 | 7 | Object/Class | 19/20 |

数组类型为 22（`EVMType_Array`）；用户自定义 class 均为 20（`EVMType_Class`）。eType 属于 VM 内部实现细节，业务判断优先用类型比较（`==`）而不是硬编码数值。

## 类型比较（`==` / `!=`）

类型对象支持相等比较，等价于判断两个值的运行时类型是否相同：

```s
fun<T> dump(T x)
{
    if x.type == int.type          # 泛型场景下判断实例化类型
    {
        ret "int32"
    }
    ret x.toString()
}
```

```s
Num f = 12.75
Int32 i = f as Int32
t1 = f.type
t2 = i?.type
global.println((t1 == t2).toString())    # false（Float64 vs Int32）
```

典型用途是泛型方法 / `toString()` 重写里按实际类型分支，以及数值混合运算后的类型提升验证：

```s
a = 1 + 2          # Int32
b = 1 + 2.2        # Float64
c = 1i + 2ui       # Int32
d = 1L + 2         # Int64
global.println(a.type.toString())        # Int32
global.println(b.type.toString())        # Float64
global.println(d.type.toString())        # Int64
```

## `.type` 与 `is` / `as` 的区别

- `x.type`：返回类型对象，可保存到变量、打印、比较；适合"拿到类型信息再处理"的场景。
- `x is T` / `x isnot T`：直接返回 Boolean 的类型归属判断，适合条件分支；`is` 会沿继承链向上匹配。
- `x as T`：运行时转换，失败得 `null`。

三者可以组合使用：

```s
if obj is Myclass
{
    global.println(obj.type.toString())     # Myclass
}

if obj.type == Myclass.type                 # 与 is 等价的写法（不含继承语义）
{
    ...
}

var s = obj as String                       # 转换，失败为 null
```

注意：`is` 沿继承链匹配父类，而 `x.type == T.type` 是严格的运行时类型相等，二者在继承场景下结果可能不同。

## 保留限制

- `type` 是 `Object` 的保留成员（final），用户类不能声明名为 `type` 的成员变量或方法，否则与内建 `.type` 冲突。
- 泛型嵌套深层的静态成员访问 VM 尚未完全支持，`.type` 在泛型形参上的解析依赖调用帧的模板绑定表，需在实例化上下文中使用。

完整转换规则（`as`/`is`/`isnot`）见 cast 章节。
