# FFI 外部函数接口（Foreign Function Interface）

> 本文描述 SimpleLanguage **当前已落地** 的 FFI 机制：普通的动态库加载与调用、`FFI.Library` /
> `FFI.StaticLibrary` 两个封装类、`project.jsonc` 的 `dllImports` 配置、`@DllImport` 与
> `@DllStaticImport` 两个声明式 attribute（两者均为 Preload 时点 attribute、cvm 装配期绑定，
> P10 起 `@DllStaticImport` 不再由 Front 编译期发射 77），以及各层内部实现原理。
>
> 设计草案（部分未落地）见 [design/ffi-design.md](../design/ffi-design.md)；本文以**实现**为准。
> 端到端可运行样例见 [test/SpecialTest/FFITest.sl](../../test/SpecialTest/FFITest.sl)。

---

## 0. 总览：三条调用路径

SL 的 FFI 按"绑定时机 + 运行期开销"分成三条路径，共用同一套底层（`cvm` 的 `src/lib/ffi/`）：

| 路径 | 写法 | 绑定时机 | 运行期开销 | 回退 |
|---|---|---|---|---|
| **① 命令式（普通 FFI）** | `FFI.Library(path).getFunction(...)` / `SystemFFICallXxx(...)` | 运行期，每次 `LoadLibrary` + `GetSymbol` | 一次库查表 + 函数值闭包调用 | 无（自己判 null） |
| **② `@DllImport` 声明式** | `@DllImport("lib","sym")` + 函数定义 | **cvm assembly build 期**（run 前，运行时 attribute 处理器） | **零 SL 帧**，直调 native | 运行期按 `methodId` 回退函数体 |
| **③ `@DllStaticImport` 静态绑定** | `@DllStaticImport("静态名","sym")` + 函数定义 | **cvm assembly build 期**（进程级一次性） | **零 SL 帧**，直调 native | 运行期按 `methodId` 回退函数体 |

分层：

```
SL 源码
  │ FFI.Library / FFI.StaticLibrary / @DllImport / @DllStaticImport
  ▼
编译层 Front(C#)
  │ 普通调用         -> CallStatic / CallClosure
  │ @DllImport       -> 普通静态调用 CallStatic(73)；attribute 数据（lib/symbol/sig）
  │                    随 module.json 方法级 attributeList 导出，不做代码注入
  │ @DllStaticImport -> 同上（P10 起与 DllImport 同款：恒发 CallStatic(73)，
  │                    attribute 数据随 attributeList 导出，装配期改写 73 -> 77）
  ▼
cvm 运行层(C)
  ├─ assembly build 期：静态库预载 + 符号解析 + payload 改写为 4 字节索引；
  │   attribute 处理器（src/vm/runtime/attribute/）遍历 stage=Preload 的方法级
  │   attributeList（@DllImport / @DllStaticImport）-> FFI 绑定器建静态绑定
  │   并改写 CallStatic(73) -> CallFFIStatic(77)
  ├─ lib 层  src/lib/ffi/ ：签名解析 / 库加载去重引用计数 / x64 ABI 派发
  └─ VM 层   src/vm/system_method_call/ffi_system_method.c ：弹参压结果的适配
  ▼
原生 C 动态库（.dll / .so）
```

---

## 1. `project.jsonc` 的 `dllImports` 配置

所有"按名字引用库"的能力都来自这段配置（`ProjectConfig.DllImports`）：

```jsonc
"dllImports": [
  {
    "path": "../../source/CLangdll/x64/Debug/CLangdll.dll",
    "name": "CLangdll",
    "alias": "CLangdll",
    "static": "CLangdll",
    "functions": [
      { "name": "libaddfunc", "symbol": "simplelanguage_addtest", "sig": "i32,i32->i32" }
    ]
  },
  { "path": "../../source/CLangdll/x64/Debug/CLangdll.dll", "name": "CLangdll", "alias": "cl" }
]
```

| 字段 | 作用 |
|---|---|
| `path` | 库文件相对路径（相对工程文件；cvm 侧按进程 CWD 规范化为绝对路径） |
| `name` | 库名 |
| `alias` | 别名。`global.dllImport.<alias>` 按 `alias / name / path` 三者查表（`ProjectConfig.ResolveDllImportPath`）；`@DllImport("别名", ...)` 在 cvm 装配期按模块 `dllImports` 段的 `alias` / `name` 匹配 |
| `static` | **静态绑定名**。非空时该库在 cvm 加载模块时预载，句柄持续到进程退出；是 `@DllStaticImport` 与 `FFI.StaticLibrary.GetStaticLib` 的键 |
| `functions` | 库函数变量列表，注入为 `global.<name>(...)` 可直接调用 |

配置带来的两个注入产物：

```sl
// 1) global.dllImport.<alias> —— FFI.Library 实例（免写长路径）
var lib = global.dllImport.CLangdll
var add = lib.lookupFunction<int,int,int>( "simplelanguage_addtest" )

// 2) global.<funcName> —— functions 段注入的库函数变量
var r = global.libaddfunc( 20, 22 )     // == 42
```

> `dllImports` 会随模块导出（`module.json` 的同名段），引用方加载本模块时自动合并别名，
> 本地已配置的同名 alias 优先（不覆盖）。

---

## 2. 路径①：普通 FFI 调用（命令式）

### 2.1 加载库并取符号

```sl
var lib = FFI.Library( "../../source/CLangdll/x64/Debug/CLangdll.dll" )
if ( lib.isValid )
{
    Int64 addfn = lib.getSymbol( "simplelanguage_addtest" )
    Int64 r = SystemFFICallI32( addfn, "i32,i32->i32", 20, 22 )   // 42
    lib.release()
}
```

### 2.2 变参调用 `SystemFFICallXxx`

统一形态 `SystemFFICallXxx( Int64 fn, string sig, ...实参 )`，`sig` 描述 C 侧真实签名：

```sl
SystemFFICallVoid ( fn, "u8,ptr->void", 60, p )
SystemFFICallI32  ( addfn, "i32,i32->i32", 20, 22 )
SystemFFICallI64  ( fn,    "i64,i64->i64", 11, 31 )
SystemFFICallF64  ( fn,    "u8,i16,u32,i64,f32,f64->f64", 200, -1000, u32v, i64v, 2.5f, 1.25 )
SystemFFICallUtf8 ( fn,    "utf8->utf8", "hello ffi" )
SystemFFICallF8E4M3( fn,   "f8e4m3->f8e4m3", 1.5fe4 )
SystemFFICallBool ( fn,    "bool->bool", true )
SystemFFICallF32  ( fn,    "f32->f32", 1.5f )
SystemFFICallF8E5M2( fn,   "f8e5m2->f8e5m2", 2.0fe5 )
```

**返回类型必须与 sig 的返回类型相容**，否则 cvm 告警并压该变体的零值（不中断 VM）：

| 变体 | sig 允许的返回类型 |
|---|---|
| `Void` | `void` |
| `Bool` | `bool, i8, u8, i16, u16, i32, u32` |
| `I32` | `i8, u8, i16, u16, i32, u32` |
| `I64` | `i64, u64, ptr, utf8` |
| `F32` | `f32, f16, bf16` |
| `F64` | `f64` |
| `Utf8` | `utf8, ptr` |
| `F8E4M3` / `F8E5M2` | 仅对应 `f8e4m3` / `f8e5m2` |

### 2.3 函数值：`getFunction` / `lookupFunction`（Dart `lookupFunction` 风格）

把符号地址包装成可直接调用的 SL 函数值：

```sl
var lib = FFI.Library( path )

// 显式 sig
Func<int,int,int> addf = lib.getFunction( "simplelanguage_addtest", "i32,i32->i32" )

// 只传 name —— 编译期从左侧函数类型定义推导 sig 并注入
Func<int,int,int> addg = lib.getFunction( "simplelanguage_addtest" )
AddFuncTA         addta = lib.getFunction( "simplelanguage_addtest" )   // typealias 同样可推导

// 模板形态：lookupFunction<Ret, P...>( name ) -> 内部改写为 getFunction
var addl = lib.lookupFunction<Int64,Int64,Int64>( "sl_add" )
Func<Int64,string> strlenf = lib.lookupFunction<Int64,string>( "sl_strlen_utf8" )

addf( 20, 22 )      // 42
```

> `getSymbol` 返回裸地址；当它被赋给函数类型变量时，前端同样改写为 `getFunction` 并注入推导 sig。

### 2.4 回调：把 SL 静态方法交给 native 调用（任意签名形状，0.0.48 起 v2 通用桩）

```sl
# INT 类（经典形态）
Int64 cb = FFI.StaticLibrary.createCallback(
    "SpecialTest.FFICallbacks.OnAdd_2_Core.Int64_Core.Int64", "i64,i64->i64" )
Int64 r = SystemFFICallI64( callCb, "ptr,i64->i64", cb, 20 )   # C 侧回调回 SL
FFI.StaticLibrary.freeCallback( cb )

# 浮点参数 + 浮点返回
Int64 cbF = FFI.StaticLibrary.createCallback( "OnFpAdd", "f32,f32->f32" )
Float32 fr = SystemFFICallF32( fpAdd, "ptr,f32,f32->f32", cbF, 1.5f, 2.25f )

# 混合参数（INT/DBL/utf8）与字符串返回
Int64 cbM = FFI.StaticLibrary.createCallback( "OnMixArgs", "i64,f64,utf8->i64" )
Int64 mr = SystemFFICallI64( mixArgs, "ptr,i64,f64,utf8->i64", cbM, 3, 2.0, "abcd" )

Int64 cbU = FFI.StaticLibrary.createCallback( "OnUtf8Echo", "utf8->utf8" )
string us = SystemFFICallUtf8( utf8Echo, "ptr,utf8->utf8", cbU, "world" )  # "cb:world"
```

约束（v2 通用桩：参数类 base-3 形状全展开，与调用侧对称）：

- **签名任意形状**：参数 ≤ 6，INT/DBL 类任意混合；返回 `void` / INT 类 / DBL 类 / `utf8` 均可；
- **utf8 进出**：`utf8` 参数转为 SL `string`（NULL 宽容为空串）；`utf8` 返回值拷入槽静态缓冲（4KB，**下一次同槽回调前有效**，C 侧需即取即用）；
- ⚠ **C 侧回调形参必须全宽**：整数一律 `int64_t` / `long long`（sig 写 `i64` / `u64`），浮点 `float` / `double`（`f32` / `f64`）。窄整型（`short` / `char` / `int`）形参在寄存器/栈上**只写窄字节**，桩按 int64 读取会混入高位垃圾——Windows x64 ABI 要求跨边界形参类型精确一致。窄类型回调（如 `qsort` 的 `int (*)(const void*, const void*)`）需在 C 侧包一层全宽适配函数；
- 槽位 8 个（进程级）；`method` 可传完整 method id 或短方法名（按参数个数匹配）；
- 低精度浮点（f16/bf16/f8）回调形参按 `float` 通道传递（与调用侧约定一致，sig 写 `f16` 等、C 侧形参 `float`）。

### 2.5 配套：原生内存 `Memory` / `SystemPtr*`

FFI 常与原生内存配合。核心原生内存 API 已迁入 `Core/Memory`（`Memory.alloc / allocArray / readXxx / writeXxx / sizeOf / structSize / structFieldOffset / newStruct / newUtf8 / copyUtf8 / freeNative`），另有底层 `SystemPtrAlloc / SystemPtrFree / SystemPtrReadInt32 / SystemPtrWriteFloat64 ...`，以及 `data` ↔ C struct 互转：

```sl
Int64 p  = Memory.alloc( 64 )
Memory.writeI32( p, 0, -100 );  Memory.writeI64( p, 8, 9000000000 )
Float64 total = SystemFFICallF64( structSum, "ptr->f64", p )
Memory.freeNative( p )

Int64 addr = Memory.dataToNativeStruct<FFICBook>( "SLBookStruct", book )   // data -> C struct
FFICBook b = Memory.nativeStructToData<FFICBook>( addr )                   // C struct -> data
```

### 2.6 结构体布局与双向 marshal：`FFI.Struct`（0.0.49 / P0-T3）

`Memory.dataToNativeStruct` 按 **C 声明模板**整块转换；`FFI.Struct` 则是 **C 结构体布局**的
SL 封装（Dart FFI Struct 风格）：先用**布局 sig** 注册布局（字段名即 SL 对象成员名），
之后 alloc 出 native 内存块，并可把 SL 对象与 native 块**按字段名双向搬运**。

源码：`SLangCore/Lib/Std/FFI/Struct.sl`；lib 层 `csimple_lang/src/lib/ffi/sl_ffi_struct.{h,c}`；
VM 适配 `src/vm/system_method_call/ffi_system_method.c`（6 个 `SystemFFIStruct*` 系统方法，
经 `Std.jsonc` 的 `systemCalls[].cvmFunction` 登记）。

**布局 sig**（与 C 侧自然对齐一致；`packed:` 前缀取消对齐）：

```sl
Int32 id = FFI.Struct.define( "i32 width, i32 height, f64 ratio, utf8 name" )
// 同 sig 二次 define 幂等返回同一 id；SL 类型名（Int32...）与空串解析失败返回 <=0
// 推导（x64）：width@0 height@4 ratio@8 name@16，total_size 24（与 C sizeof 一致）
```

**API 一览**（静态 + 实例两形态）：

```sl
// 静态
Int32 FFI.Struct.define( string sig )         // 布局注册（幂等），<=0 失败
Int32 FFI.Struct.size( Int32 id )             // sizeof；-1 未注册
Int64 FFI.Struct.alloc( Int32 id )            // 分配 native 块，0 失败
bool  FFI.Struct.free( Int64 addr )           // 释放本分配器产出的块
Int64 FFI.Struct.marshalOut( object src, Int32 id )   // SL 对象 -> 新 native 块
bool  FFI.Struct.marshalIn( Int64 addr, Int32 id, object target )  // native 块 -> SL 对象

// 实例（_init_(id) 即分配）
var blk = FFI.Struct( id )
blk.address        // Int64：块地址（free 后归 0）
blk.layoutId       // Int32：布局 id
blk.marshalOut( obj )      // 产【新块】并返回其地址（不写本块！须单独 free）
blk.marshalIn( obj )       // 从本块 this.address 读入
blk.free()                 // 成功后 address == 0，重复 free 返回 false
```

**marshal 语义三要点**：

1. **按字段名匹配**：布局字段名即 SL 对象成员名（`vm_object_find_member_index`）；
   SL 侧未声明同名字段时**跳过**（不视为失败）——FFIHoldClass 这类无关对象也能空转成功。
2. **utf8 走附属字符串池**：marshalOut 三阶段（快照字段 → 按 utf8 总长一次分配 →
   逐字段写），串体进块尾附属池、指针槽存池内地址（**槽内存地址不存内容**）；
   块存活期指针有效，块 free 即失效。marshalIn 经 `vm_object_new_string` 建 SL 字符串；
   native NULL ↔ SL null 字符串。
3. **实例 `marshalOut` 产新块**：`blk.marshalOut(obj)` 返回**新分配块**的地址
   （不写入 `blk` 自身）——与静态 `marshalOut(obj,id)` 同义，须单独 `FFI.Struct.free(新块)`。

**所有权规则（内存安全边界）**：

| 块的来源 | 释放方式 | 说明 |
|---|---|---|
| `FFI.Struct.alloc` / `marshalOut` 产物 | `FFI.Struct.free(addr)` 或 `blk.free()` | 块头带 magic + 布局 id，误传普通指针拒释放 |
| native 侧 `malloc`（如 C 库 alloc 函数） | **必须由 C 侧 free 函数释放** | 两条分配链不可混用（与 `Memory.freeNative` 同律） |
| SL 声明侧 | 无需管理 | marshalIn 读出的 string/对象由 GC 管理 |

utf8 跨调用注意：FFI 调用的 utf8 **实参缓冲仅调用期有效**——C 侧把该指针存入结构体后
（如 `sl_size_make`），跨调用 `marshalIn` 回读 name 会读失效内存；跨调用回读须用 C 静态串
（`fill_const`）或 C 侧 `strdup` 自持（`alloc`）。

**端到端样例**（对照 `CLangdll.cpp` 9c 节 `SLSizeStruct`；完整 60 项断言见
`test/SpecialTest/FFITest.sl` 的 `testFFIStruct`）：

```sl
# 1) SL 对象 -> native 块（数值/字符串全量写出）
Int32 id1 = FFI.Struct.define( "i32 width, i32 height, f64 ratio, utf8 name" )
FFIWndInfo w = new()          # class：ratio 须显式 Float64（data 推导恒 f32）
w.width = 800;  w.height = 600;  w.ratio = 800.0d / 600.0d;  w.name = "wnd-out"
Int64 out1 = FFI.Struct.marshalOut( w, id1 )
SystemFFICallI64( s_sizeArea, "ptr->i64", out1 )       # C 读字段：480000

# 2) native 块 -> SL 对象（按字段名回填）
FFIWndInfo back = new()
FFI.Struct.marshalIn( out1, id1, back )                # back 全字段还原
FFI.Struct.free( out1 )
```

> 注意：marshal 双向搬运要求 SL 成员类型与布局槽位兼容（f64 槽需真 `Float64` 成员）；
> `data` 成员类型从小数字面量推导恒为 Float32（`d` 后缀不参与推导），f64 字段请用
> class 显式类型声明。

---

## 3. `FFI.Library` 类

源码：[source/Front/Lib/Std/FFI/Library.sl](../../source/Front/Lib/Std/FFI/Library.sl)

动态库句柄封装：加载 / 符号解析 / 引用计数 / 释放。**同路径共享同一份底层句柄（去重缓存）**，每次加载引用计数 +1。

```sl
public class FFI.Library extends Object
{
    Int64 _handle = 0

    public void _init_()                    // 空句柄
    public void _init_( string path )       // 按路径加载（引用计数 +1），失败句柄为 0
    public void _init_( Int64 handle )      // 以已有句柄包装（@DllStaticImport 静态绑定辅助）

    get Int64 handle()                      // 句柄（诊断用）
    get bool  isValid()                     // 句柄 != 0

    public Int64 getSymbol( string name )                    // 符号地址，0 = 未找到
    public Function getFunction( string name, string sig )   // 包装为可调用 Function 值，失败 null
    public Int32 addRef()                                    // 引用 +1，返回新计数
    public Int32 refcount()                                  // 当前计数，-1 = 句柄无效
    public bool release()                                    // 引用 -1
}
```

要点：

- `release()` 返回 `false` 表示**句柄无效**；仅当本次是最后一个引用（真正卸载）时才把 `_handle` 清 0，否则句柄仍有效。
- 对死句柄（加载失败 / 已卸载）调用 `release()` 返回 `false`，不报错。
- `getFunction(name)` 省略 `sig` 时，前端按声明目标（`Func<Ret,P...>` 或函数 `typealias`）推导并注入。

### 库生命周期实测语义

```sl
var lib  = FFI.Library( path )
int r0   = lib.refcount()          // 已有静态引用时 r0 >= 1
lib.addRef()                       // -> r0+1
var lib2 = FFI.Library( path )     // 同路径去重：共享句柄，refcount -> r0+2
lib2.release()                     // -> r0+1，lib2 仍 isValid
lib.release()                      // -> r0，句柄保持有效

var bad = FFI.Library( "no_such_library_zzz.dll" )
bad.isValid == false ; bad.release() == false
```

---

## 4. `FFI.StaticLibrary` 类

源码同上文件尾部。承载**不依赖具体句柄**的全局能力：静态绑定库缓存、全局统计、回调注册、`@DllImport` 绑定辅助。

```sl
public class FFI.StaticLibrary extends Object
{
    static List<Library> s_staticLibs = List<Library>()

    public static Int32 libraryCount()                                  // 当前已加载（未卸载）库个数
    public static Library GetStaticLib( string name )                   // 按静态名取预载库，未注册 null
    public static Int64 createCallback( string method, string sig )     // SL 静态方法 -> trampoline 地址
    public static bool freeCallback( Int64 addr )                       // 释放回调槽
    public static Function bindFunction( string path, string symbol, string sig )   // @DllImport 辅助
}
```

### `GetStaticLib( name )`

按 `project.jsonc` 的 `"static"` 字段名取**已预载**的库，返回 `FFI.Library` 包装：

```sl
var lib  = FFI.StaticLibrary.GetStaticLib( "CLangdll" )
var lib2 = FFI.StaticLibrary.GetStaticLib( "CLangdll" )   // 同一实例（内部 List 去重）
FFI.StaticLibrary.GetStaticLib( "no_such_static_lib" )    // null
```

静态名必须在 `dllImports` 里配了 `"static"`，否则返回 `null`。

### `bindFunction( path, symbol, sig )`

通用绑定辅助，等价于：

```sl
ret FFI.Library( path ).getFunction( symbol, sig )
```

库按 C# `DllImport` 语义**进程级常驻**（去重缓存共享句柄，不 release）。

> `@DllImport` 旧编译期注入（隐藏字段 `__dll_<name>` 初值即本方法）已退役；现在 `@DllImport` 的绑定由 cvm 装配期处理器直连 lib 层完成（见 §5 / §8.7），不再经过本方法。保留供 SL 侧手动绑定使用。

---

## 5. 路径②：`@DllImport` 声明式绑定

C# `[DllImport("lib")] static extern ...` 风格的**运行时 attribute**（handleType=Runtime=1，对标 CLR 在模块加载期读元数据完成 P/Invoke 绑定）。**必须带函数体**——dll 绑定不可用时执行函数体（fallback 本体）。

```sl
@DllImport( "../../source/CLangdll/x64/Debug/CLangdll.dll", "simplelanguage_addtest" )
static int s_dllAdd( int a, int b )
{
    ret a + b           // fallback：与 dll 等价的 SL 实现
}

@DllImport( "CLangdll", "sl_mul2", "i64->i64" )      // 第 1 实参可用 dllImports 别名
static Int64 s_dllMul2( Int64 v ) { ret v * 2 }

@DllImport( "CLangdll", "sl_book_alloc", "i32,f32,i32,utf8->ptr" )   // Ptr 不可推导 -> 手写 sig
static Int64 s_bookAlloc( int id, float price, int pages, string title ) { ret 0 }
```

**实参**：`( 库路径或别名, 符号名 [, sig] )`。`sig` 缺省时由导出层从函数签名推导补全（含 `Ptr` 等不可映射类型时推导失败不追加，cvm 侧按绑定失败回退）。

### Front 做了什么 / 不做什么

Front **不做任何代码注入**（旧“隐藏字段 + 链头 `if` 分派”机制已退役），函数原样编译为普通静态方法、调用点发射 `CallStatic(73)`；仅将 attribute 数据随 module.json 方法级 `attributeList` 导出：

```json
"attributeList": [ { "name": "DllImport", "args": ["<lib>", "<symbol>", "<sig>"], "handleType": 1 } ]
```

导出层（`SLModulePackageWriter`）在 `args.Count == 2` 时用 `BuildFFIFunctionSigFromMetaFunction` 推导 sig 追加为第 3 实参（手写第 3 实参时不覆盖）。

### cvm 装配期做了什么（run 前）

cvm 加载 module.json 后、执行前的 assembly build 阶段，运行时 attribute 处理器（`src/vm/runtime/attribute/vm_runtime_attribute.c`）按 name 路由到 DllImport 绑定器，分两阶段：

1. **collect（收集）**：遍历方法级 `attributeList`，`handleType == 1` 且 name 为 `DllImport` 的条目收集绑定素材——lib 三级解析（jsonc `static` 静态名 → `dllImports` 段 `alias` / `name` 匹配 → lib 本身即路径）→ `sl_ffi_lib_resolve` 解析符号 → sig 解析为调用计划 → 登记静态绑定表（进程级常驻）；
2. **rewrite（改写）**：全量扫描指令，凡 `CallStatic(73)` 命中已绑定 `methodId` 的调用点，就地改写为 `CallFFIStatic(77)` + 4 字节绑定索引——**复用路径③的全部执行链路**。

绑定失败（lib 三级均未命中 / 符号缺失 / sig 非法）的调用点保持 73 原样，运行期回退执行 SL 函数体。

> handleType 判定规则、注册表扩展方式、inline 约束等机制总览见 [syntax/attribute.md](../syntax/attribute.md)「处理时机」一节。

---

## 6. 路径③：`@DllStaticImport` 静态绑定快速调用（新机制）

### 6.1 是什么

`@DllStaticImport` 让被标注的**静态函数**的调用点由 **cvm 装配期改写**为专用指令
`CallFFIStatic(77)`（P10 起，与 `@DllImport` 同款机制；Front 恒发 `CallStatic(73)`，
不做任何编译期调用点改写）：

- 库在 **cvm 加载模块（assembly build 期）** 就按 `"static"` 名预载，符号**只解析一次**；
- 指令 payload 从 JSON 改写为 **4 字节绑定表索引**；
- 运行期 handler 直接整合栈上参数调用 native —— **不进 SL 帧、不走 `Library.Load` 链路**；
- 绑定失败（静态名未注册 / 符号缺失 / sig 非法）时**运行期回退执行函数体**（SL 实现的等价逻辑）。

### 6.2 用法

前置条件：`project.jsonc` 中该库必须配 `"static"` 字段。

```jsonc
{ "path": "../../source/CLangdll/x64/Debug/CLangdll.dll",
  "name": "CLangdll", "alias": "CLangdll", "static": "CLangdll" }
```

```sl
# 第 1 实参 = jsonc "static" 字段的静态名；第 3 实参 sig 可省略（从签名推导）
@DllStaticImport( "CLangdll", "simplelanguage_addtest" )
static int s_statAdd( int a, int b )
{
    ret a + b                       # 绑定失败时的 fallback 体
}

@DllStaticImport( "CLangdll", "sl_mul2", "i64->i64" )
static Int64 s_statMul2( Int64 v ) { ret v * 2 }

@DllStaticImport( "CLangdll", "sl_strlen_utf8" )
static Int64 s_statStrlen( string s ) { ret s.length }

# 静态名未注册 -> 绑定失败 -> 回退函数体
@DllStaticImport( "no_such_static_lib", "no_such_symbol" )
static int s_statFbAdd( int a, int b ) { ret a + b }
```

调用点就是普通静态函数调用，无感知：

```sl
check( "static add(20,22)==42", s_statAdd( 20, 22 ) == 42 )
check( "static strlen('abc123')==6", s_statStrlen( "abc123" ) == 6 )
```

### 6.3 与 `@DllImport` 的关键差异

两者的运行期执行链路**完全相同**（assembly build 期绑定、零 SL 帧、`CallFFIStatic(77)`、按 `methodId` 回退），差异集中在 **lib 解析**（P10 后驱动方式也统一为装配期 attribute 处理器）：

| | `@DllImport` | `@DllStaticImport` |
|---|---|---|
| 处理时机 | Preload 时点 attribute，cvm 装配期处理器消费 | 同左（P10 起同款注册表机制） |
| 第 1 实参语义 | 库**路径**或 dllImports `alias` / `name`（三级解析，`static` 名亦可命中） | jsonc **`"static"` 静态名**（**不做别名查表**，只认预载注册名） |
| 调用指令来源 | 调用点先发射 `CallStatic(73)`，cvm 装配期改写为 77 | 同左（P10 前 Front 直接发射 77，已退役） |
| 绑定时机 | **cvm assembly build 期**（run 前） | **cvm assembly build 期**（run 前） |
| 库生命周期 | 进程级常驻（静态库表，永不 release） | 预载 + `addRef`，**永不 release**，持续到进程退出 |
| 成功路径开销 | **零 SL 帧**，直接 marshalling 后调 native | **零 SL 帧**，直接 marshalling 后调 native |
| 回退判定 | 运行期：绑定项 `native_fn == NULL`（改写未发生的调用点直接走 73） | 运行期：绑定项 `native_fn == NULL` |
| 回退目标 | `methodId` 指定的原 SL 方法（元数据级） | `methodId` 指定的原 SL 方法（元数据级） |
| 额外编译期回退 | 无（sig 推导失败 = 导出层不追加 sig → 装配期绑定失败回退） | 无（同左；Front 校验 handler 仅打日志） |

### 6.4 选择建议

两者运行期性能等价，按**配置形态**选择：

- 库未配 `"static"` 字段、或想直接写路径 / 别名 → `@DllImport`（第 1 实参解析更宽松，三级兜底）。
- 库已配 `"static"` 静态名（第 1 实参即静态注册名，不做别名/路径查表） → `@DllStaticImport`。
- 需要动态决定库路径、或运行时多次装卸 → 普通 `FFI.Library` 命令式。

---

## 7. FFI 签名字符串（sig）

格式：`"参数类型,参数类型,...->返回类型"`，与 cvm `sl_ffi_sig_parse` 一致。

### 7.1 类型表

| FFI 短名 | C 类型 | 传参分类 | SL 类型名（运行期可写） |
|---|---|---|---|
| `void` | `void` | — | `void` |
| `bool` | `bool`(C) | INT | `bool` / `boolean` |
| `i8` / `u8` | `int8_t` / `uint8_t` | INT | `Int8` / `UInt8` / `byte` |
| `i16` / `u16` | `int16_t` / `uint16_t` | INT | `Int16` / `UInt16` / `short` |
| `i32` / `u32` | `int32_t` / `uint32_t` | INT | `int` / `Int32` / `UInt32` / `uint` |
| `i64` / `u64` | `int64_t` / `uint64_t` | INT | `long` / `Int64` / `UInt64` |
| `f32` | `float` | DBL | `float` / `Float32` |
| `f64` | `double` | DBL | `double` / `Float64` |
| `f16` / `bf16` | half / bfloat16 | DBL | `Float16` / `Float16_Brain` |
| `f8e4m3` / `f8e5m2` | FP8 E4M3 / E5M2 | DBL | `Float8` / `Float8_E5M2` |
| `ptr` | `void*` | INT | `ptr` / `Ptr` |
| `utf8` | `char*` | INT | `string` / `String` |

### 7.2 语法规则

1. **必须含 `->`**；返回段可省略（视为 `void`）。
2. 零参写 `"->i32"`；但 **`"->void"` 非法**。
3. 逗号分隔，前后空白与尾随逗号容忍。
4. **参数个数 ≤ 6**（`SL_FFI_MAX_ARGS`）——x64 寄存器传参上限，不支持栈传参。
5. 未知类型名 → 解析失败。

### 7.3 编译期推导 vs 运行期解析（重要不对称）

- **编译期推导**（`@DllStaticImport` / `getFunction` 省略 sig / `lookupFunction<T>`；`@DllImport`
  推迟到导出层 `BuildFFIFunctionSigFromMetaFunction`）由 `MetaDefineVarStatements.FFISigNameOfMetaType`
  完成，**`Ptr` 被保守排除**——带指针参数/返回的函数必须**手写第 3 实参 sig**。
- **运行期解析**（`SystemFFICallXxx` / `SystemFFIMakeFunction` / `createCallback`）
  会先做 **SL 名 → FFI 短名**映射（`vm_ffi_sl_name_to_ffi`），未登记的名字原样直传。
- **静态绑定路径例外**：assembly build 期直接 `sl_ffi_sig_parse(sig, &plan)`，**不做 SL 名映射**，
  因此 `@DllStaticImport` 的 sig 必须写 FFI 短名（`"i32,i32->i32"` 而非 `"Int32,Int32->Int32"`）。

### 7.4 `.slffi.json` 契约与编译期校验（0.0.49 / P0-T5）

**契约即权威**：动态库同目录放一份 `<dll文件名>.slffi.json`（如 `CLangdll.dll` 旁的
`CLangdll.dll.slffi.json`），Front 编译期即对 `@DllImport` / `@DllStaticImport` 声明做
**签名校验**——符号拼错、类型类写错在**编译期报错**（不再运行期静默回退）。契约不存在
则不校验（math_lib 等既有库零影响）。

**schema v1**（范本 `SlangAllInOne/Project/CLangdll/CLangdll.dll.slffi.json`）：

```jsonc
{
  "version": 1,
  "baseNamespace": "Native",
  "functionList": [            // 编译期校验的依据（按 entryPoint 索引）
    { "publicName": "Native.add", "entryPoint": "simplelanguage_addtest",
      "callingConvention": "Cdecl",
      "returnType": "I32", "parameterTypeList": ["I32", "I32"] }
  ],
  "structs": [                // T3 结构体布局（ffi-check / 文档消费）
    { "name": "SLSizeStruct", "size": 24,
      "layoutSig": "i32 width, i32 height, f64 ratio, utf8 name",
      "fields": [ { "name": "width", "type": "I32", "offset": 0 } ] }
  ],
  "callbacks": [              // T4 回调签名模板
    { "name": "add2", "sig": "i64,i64->i64" }
  ]
}
```

类型名用导出清单同款 Pascal 名（`I32/I64/F32/F64/Bool/Utf8String/Ptr/Void/F16/BF16/
F8E4M3/F8E5M2/I8/U8/...`）。

**校验规则（x64 槽位语义，类兼容而非逐字相等）**：

| 维度 | 规则 |
|---|---|
| 符号 | `entryPoint` 必须登记在 `functionList`——未登记 → **LID 21483** |
| 参数个数 | 必须一致 |
| 整型/指针 | `i8..u64/bool/ptr` 同为 64 位整槽**可互换**（宽窄/符号语义由 SL 侧自负，兼容 byte 形参传 C int 槽的既有用法） |
| 浮点 | `f32/f64/f16/bf16/f8e4m3/f8e5m2` 须**精确一致**（XMM 槽宽不可混） |
| utf8 / void | 须**精确一致** |
| 生效 sig | `@DllImport` 第 3 实参手写 sig，缺省用编译期从函数签名推导的 sig；推导失败（含 Ptr）不校验（运行期回退） |

签名不匹配 → **LID 21484**；契约 JSON 坏损/schema 非法 → **LID 21485**。三者均为
`Error`（pass=FALSE）计入 errorCount，**阻断导出阶段**（module.json 不落盘）。

**触发面**：仅当契约文件存在且该 `@DllImport`/`@DllStaticImport` 的库路径（经 jsonc
`dllImports` 别名解析 + 工程目录相对展开）旁有契约时生效。C 侧无需任何改动——把契约
放在 dll 旁边即可让声明获得编译期保护。

**独立校验工具**：`slang ffi-check <contract.slffi.json> [--dll <lib.dll>]`
（宿主 `SlangAllInOne/Ffi/FfiCheckCommand.cs`）：

```
slang ffi-check SlangAllInOne\x64\Debug\CLangdll.dll.slffi.json
```

schema 自检（version / functionList 必填项 / 类型名合法 / entryPoint 去重 / structs
layoutSig / callbacks sig）+ DLL 导出表比对（缺省按 `X.dll.slffi.json -> X.dll` 推导
dll，`NativeLibrary` 装载逐 entryPoint 验证符号存在性）；任一失败 exit 1（CI 友好）。

---

## 8. 内部原理

### 8.1 分层

| 层 | 位置 | 职责 |
|---|---|---|
| lib 层（不依赖 VM） | `csimple_lang/src/lib/ffi/` | `sl_ffi_types`（类型/签名解析）、`sl_ffi_lib_manager`（加载/去重/引用计数/卸载）、`sl_ffi_call`（x64 ABI 派发，由 `gen_sl_ffi_call.py` 生成） |
| VM 适配层 | `src/vm/system_method_call/ffi_system_method.c` | `SystemFFI*` 系统方法：弹参 → 装载 `SLFFIArg` → lib 层调用 → 压结果；回调 trampoline 重入 VM；静态绑定表 |
| 汇编/加载层 | `src/vm/load/slir_json_module_loader.c`、`src/vm/assembly/sl_runtime_assembly.c` | 解析 `dllImports`、assembly build 期预载静态库 + 解析符号 + 改写 payload |
| 解释执行 | `src/vm/runtime/vm_runtime.c` | `case OpCode_CallFFIStatic`、`case OpCode_CallClosure` 的 native 闭包分支 |

系统方法绑定方式：Front 在 `Std.jsonc` 用 `cvmFunction` 字段写 C 符号名，VM 运行期按符号地址解析，
**没有硬编码 name→函数映射表**。

### 8.2 `sl_ffi_lib_manager`：去重与引用计数

```c
typedef struct _SLFFILibHandle {
    void* dl_handle; int32 refcount; int32 slot; char path[512];
} SLFFILibHandle;
static SLFFILibHandle* s_libs[32];      // 上限 32 个库
```

`sl_ffi_lib_load` 流程：

1. 相对路径 → **规范化为基于进程 CWD 的绝对路径**（避免宿主 `SetDllDirectory` 干扰搜索序）；
2. 按规范化路径**去重**（Windows `_stricmp` / Unix `strcmp`），命中则 `++refcount` 返回同一句柄；
3. 依次尝试：规范化路径 → **可执行文件所在目录 + 裸文件名**；
4. 新建句柄 `refcount = 1`。

`sl_ffi_lib_release`：`--refcount`，归零才真正 `FreeLibrary/dlclose`，并用表尾元素填补空洞保持紧凑。
`sl_ffi_lib_add_ref` 返回新计数；`sl_ffi_lib_refcount` 对无效句柄返回 `-1`。

### 8.3 `sl_ffi_call`：不用 libffi 的 x64 ABI 派发

调用形状 = `argc(0..6) × fp_mask(2^argc)`，由脚本**静态展开成 127 个 case**：

```c
case 2:  /* sl_ffi_call.c */
  case 0: return ((int64(*)(int64,int64))fn)(gi[0], gi[1]);
  case 1: return ((int64(*)(double,int64))fn)(gd[0], gi[1]);
  ...
```

参数分两类：INT 类（bool/i8..u64/ptr/utf8，统一 int64 走通用寄存器）、DBL 类
（f32/f64/f16/bf16/f8*，统一 double 走 XMM，f32 位模式放低 32 位）。返回按类型三分派：
Void / F64 类（读 XMM0 全 64 位）/ F32 类（读 XMM0 低 32 位）/ 默认 INT 类（读 RAX）。

> 因此**仅支持 x64**，且**不支持 >6 参**（栈传参）。

### 8.4 `SystemFFICallXxx` 的执行流程（`vm_ffi_call_core`）

```
1. argc = param_count - 2                       （去掉 fn 与 sig 两个前置参数）
2. 从栈顶向右到左弹出 argc 个实参               （最后一个实参在栈顶）
3. 弹 sig 字符串 -> vm_ffi_sig_rewrite_sl_names （SL 名 -> FFI 短名，缓冲 160 字节）
4. 弹 fn 地址
5. sl_ffi_sig_parse( sig, &plan )
6. 校验：param_count 匹配 / 返回类型与变体相容 / fn != 0   -> 任一失败：告警 + 压零值
7. vm_ffi_load_arg：VMRuntimeValue -> SLFFIArg
8. sl_ffi_call( fn, &plan, argc, args, &ret )
9. vm_ffi_push_result：按 plan.ret 压回 VM 栈
```

失败语义统一为「日志 warning + 压该变体的零值默认」，**不中断 VM**。

### 8.5 `SystemFFIMakeFunction`：native 闭包

两种形态：

```sl
SystemFFIMakeFunction( fn, "i32,i32->i32" )          // 含 "->" -> s1 即完整 sig
SystemFFIMakeFunction( fn, "Int32", "Int32", "Int32" ) // 分离形态：返回类型 + 各参数类型
```

生成的对象带 magic `'NATF'`；解释器的 `CallClosure` 分支先逆序保存实参、弹闭包对象，
命中 native 闭包后同样走 `vm_sys_ffi_invoke_native_closure`（失败才按普通 SL 闭包处理）。

### 8.6 回调 trampoline（v2 通用签名桩）

`createCallback` 按签名的**参数类形状**（每参归三类：INT→`int64` 走 GR、F32 类→`float` 走 XMM、F64→`double` 走 XMM，base-3 编码）从静态桩表选桩——形状空间 `argc(0..6) × 3^argc` 共 1093 种 × 槽 8 × 返回两类（int64 / double）= **17488 个桩全静态展开**（`sl_ffi_callback_stubs.c`，由 `gen_sl_ffi_callback_stubs.py` 生成，与调用侧 `sl_ffi_call.c` 的 127 形状对称）。

桩把 C 调用方实参打包为 `SLFFICbRawArgs`（gi/gd 分桶 + fp_mask），经 VM 层注册的 dispatcher（`vm_ffi_cb_dispatch`）**重入 VM**：查槽 → 压实参（utf8 转 string、低精度浮点换算位模式）→ `vm_execute_method_by_id` → 弹返回值按桩返回通道转换（INT→RAX 语义 / DBL→位模式经 double 桩走 XMM0 / utf8→槽静态缓冲地址）。

**base-3 而非 base-2 的原因**：C 调用方按 `float` 形参传参时只写 XMM 低 32 位（movss），高 32 位是垃圾——桩形参声明 `float` 才能可靠收值（cvtss2sd），`double` 形参则读全 64 位，两类必须分开生成。

异常/失败返回 0 并丢弃栈上实参。

### 8.7 `@DllImport` 的完整流水线（导出 + 装配期绑定）

```
[File/Token] 无源码改写——`@DllImport(...)` 是普通 attribute 行，函数定义原样解析
[MetaCore]   ParseAttributes 步：MetaAttribute.Parse 解析 name/args，
             ResolveHandleType 判定 handleType=1（Runtime）
[IR]         函数原样编译，调用点发射 CallStatic(73)（payload 含 methodId）
[Export]     SLModulePackageWriter：方法级 attributeList 导出
             { name:"DllImport", args:[lib, symbol, sig], handleType:1 }；
             args==2 时 BuildFFIFunctionSigFromMetaFunction 推导 sig 追加
             （含 Ptr 等不可映射类型推导失败则不追加）
[cvm load]   slir_json_module_loader：方法级 attribute_list 解析（含 stage/targets）
[cvm build]  vm_runtime_attribute_process（run 前，方法注册之后）：
   ├─ Phase1 collect：遍历 stage==Preload 且 name=="DllImport" 的方法 attribute
   │    ├─ lib 三级解析：静态库表 static 名 -> dllImports 段 alias/name -> lib 即路径
   │    ├─ sl_ffi_lib_resolve( handle, symbol ) 解析符号
   │    ├─ sig 为空或 sl_ffi_sig_parse 失败 -> native_fn = NULL
   │    └─ vm_sys_ffi_static_binding_add 登记绑定表（同方法重复标记取首条）
   └─ Phase2 rewrite：全量扫描指令，CallStatic(73) 且 payload methodId 命中绑定表
        -> memcpy 4 字节索引 + op_code 改写为 CallFFIStatic(77)
[运行期]     CallFFIStatic(77) handler（与 @DllStaticImport 同一条链路，见 8.10）；
             未被改写的调用点保持 73 原样 -> 执行 SL 函数体 fallback
```

> 装配期挂接顺序（`sl_runtime_assembly.c`）：方法注册 → 77 payload 改写（存量兼容，
> 新模块已无 77 JSON payload）→ atsign 改写 → `vm_runtime_attribute_process`
> （73→77 attribute 改写，@DllImport / @DllStaticImport 共用）。带 `@DllImport` 的方法
> **不参与自动 inline**（`AutoInlineMarkFunctions` 排除），保证调用点存活供改写
> （对标 C# P/Invoke 不可内联）。

### 8.8 `@DllStaticImport` 的完整编译流水线（P10 起）

```
[File]       无源码改写（函数定义原样保留）
[MetaCore]   MetaMemberFunction 收集 attribute 到 m_AttributeList
[MetaCore]   AttributeManager "DllStaticImport" handler：仅校验 + 日志
[IR]         IRCall.Parse（callType == 0，即静态调用）：恒发 CallStatic(73)，
             与普通静态调用完全一致（P10 前 Front 发射 77 + payload，已退役）
[Export]     attribute 数据（lib/symbol/sig）随方法级 attributeList 导出；
             sig 缺省时 BuildFFIFunctionSigFromMetaFunction 推导追加（2 参形式）
[cvm build]  vm_runtime_attribute_process（与 DllImport 同一入口）：
   ├─ Phase1 collect（s_dllstaticimport_collect）：静态库表 find(lib) ->
   │    sl_ffi_lib_resolve(handle, symbol) -> sig 解析 -> 登记共享收集表
   └─ Phase2 rewrite（与 DllImport 共用 s_dllimport_rewrite_call）：
        CallStatic(73) 命中收集表 -> 改写 CallFFIStatic(77) + 4 字节绑定索引
[运行期]     CallFFIStatic handler（见 8.10）；未改写调用点保持 73 -> SL fallback
```

> P10 前的旧链路（Front 发射 77 + `SLFFIStaticCallPackage` payload +
> `sl_assembly_rewrite_ffi_static_calls` 装配期 payload 改写）已退役——
> `SLFFIStaticCallPackage` POCO 与 Front 侧二进制编码已删除；C VM 的 77 payload
> 双格式解码（`vm_payload_parse_ffi`）保留仅为兼容存量 module.json，新导出模块
> 的 77 指令 payload 恒为 4 字节绑定索引。

### 8.9 assembly build 期：静态库预载与 payload 改写

**预载**（`sl_runtime_assembly.c`，在 class/method 注册之前）：

```c
for (pi...) for (mi...) for (i = 0; i < module->dll_imports_count; ++i) {
    SLDllImportPackage* di = &module->dll_imports[i];
    if (di->static_name == NULL || di->static_name[0] == '\0') continue;
    vm_sys_ffi_static_lib_register(di->static_name, di->path, pkg_dir);
}
```

`vm_sys_ffi_static_lib_register` 幂等：已注册直接返回；否则 `sl_ffi_lib_load`
（先按原路径，相对路径失败再拼 `pkg_dir/path`），成功后**再 `addRef` 一次且永不 release**，
保证进程级常驻。

**指令改写**（`sl_assembly_rewrite_ffi_static_instruction`，P10 起仅存量兼容——新模块
不含 Front 发射的 77 JSON payload，改写主力是 attribute 处理器的 Phase 2）：

```
1. 解析 payload JSON -> lib / symbol / sig / methodId / paramCount / tryCatch
2. vm_sys_ffi_static_lib_find( lib ) -> sl_ffi_lib_resolve( handle, symbol )
       库未预载 / 符号缺失 -> 告警，native_fn 保持 NULL
3. native_fn != NULL 时 sl_ffi_sig_parse( sig, &plan )
       解析失败 -> native_fn = NULL（快速路径不可用）
4. target_rt = 按 methodId 预解析回退帧的类型上下文
5. index = vm_sys_ffi_static_binding_add( native_fn, &plan, methodId, param_count, try_catch, target_rt )
6. 就地改写：memcpy( payload, &index_le, 4 );  payload_length = 4
```

**全量扫描**：遍历所有 package → module → 方法的 `instruction_list` 与类字段的 `express_list`，
凡 `op_code == OpCode_CallFFIStatic` 即改写。字段初始化表达式与方法指令共享 payload，改写自动传播。

绑定表条目：

```c
typedef struct _VMFFIStaticBinding {
    void*        native_fn;    // NULL = 回退 SL 方法体
    SLFFICallPlan plan;
    char*        method_id;    // 回退目标
    int32        param_count;
    int32        try_catch;
    RuntimeType* target_rt;    // 回退帧类型上下文（预解析缓存）
} VMFFIStaticBinding;
```

两张表（静态库表 + 绑定表）均为**进程级常驻**，`vm_sys_ffi_cleanup` 不清绑定表（同进程多 VM 场景下
索引仍有效），只在进程/根 VM 退出时统一卸载动态库。

### 8.10 运行期：`OpCode_CallFFIStatic`(77) handler

栈约定：调用前 `[..., arg0, ..., arg_{M-1}]`（**栈顶是最后一个实参**），无 this、无闭包对象。

```
指令外层格式 [op:1][plen:4][payload:plen]
   ├─ plen == 4  -> 已绑定：memcpy 出 uint32 索引 -> vm_sys_ffi_static_binding_get(idx)
   │                entry == NULL -> error_code = -54，停止 VM
   └─ plen != 4  -> 未改写（OOM 兜底）：解析 JSON 取 methodId/paramCount/tryCatch
                    -> vm_frame_push_call（实参留在栈上，等同 CallStatic）

entry->native_fn != NULL（快速路径）:
    base_malloc0( param_count * sizeof(VMRuntimeValue) )      // 失败 -> error_code = -53
    for (ai = param_count-1; ai >= 0; --ai)                   // 逆序弹参还原声明序
        vm_pop_stack_top_to_vmvalue( vm, &saved_args[ai] )    // 下溢 -> null + warning
    vm_sys_ffi_invoke_native_closure( vm, native_fn, &plan, saved_args, param_count )
        └─ vm_ffi_load_arg 逐参装载 -> sl_ffi_call -> vm_ffi_push_result 压栈
    base_free( saved_args )

entry->native_fn == NULL（回退路径）:
    vm_frame_push_call( vm, method_id, target_rt, NULL, 0, try_catch )
    // 失败或无 methodId -> 丢弃实参保持栈平衡 / error_code = -54
```

错误码：`-53` 参数缓冲分配失败；`-54` 绑定索引越界或无回退 methodId。

### 8.11 生命周期与清理

| 时机 | 动作 |
|---|---|
| 每 VM 结束 | `vm_sys_ffi_callback_registry_clear_vm(vm)`（对象池释放前，防悬空 `VM*`） |
| 根 VM（`level == 0`）结束 | `vm_sys_ffi_cleanup()`：清回调槽 + `sl_ffi_lib_manager_clear` 卸载全部动态库 |
| 模块卸载 | `dll_imports` 镜像字符串释放；**预载静态库不卸载** |
| 静态绑定表 | 进程级常驻，**不随 VM 重建清理** |

---

## 9. 限制与已知边界

| 项 | 说明 |
|---|---|
| 架构 | 仅 **x64**（`sl_ffi_call` 静态展开 x64 ABI） |
| 参数个数 | ≤ 6（`SL_FFI_MAX_ARGS`），不支持栈传参 |
| 变参 C 函数 | 不支持 `printf` 类 varargs（与 Dart FFI 一致） |
| 库个数 | ≤ 32（`SL_FFI_LIB_TABLE_MAX`） |
| 回调槽 | ≤ 8；签名任意形状（INT/DBL 混合参数 ≤ 6，返回 void/INT/DBL/utf8，0.0.48 起 v2 通用桩）；⚠ C 侧回调形参必须全宽（int64_t/float/double），窄整型只写窄字节会被宽读混入垃圾 |
| 静态绑定 sig | 必须是 FFI 短名，不接受 SL 类型名（build 期不做映射） |
| `Ptr` 推导 | 编译期 sig 推导排除 `Ptr`，须手写 sig |
| `->void` | 非法写法 |
| 回调 method id | ≤ 191 字符 |
| C++ / 类成员函数 | 仅支持 `extern "C"` 扁平 ABI |
| 静态名校验 | 前端**不校验**静态名是否已注册，写错只在运行期表现为"回退函数体" |
| `@DllImport` inline | 带 `@DllImport` 的方法**不参与自动 inline**（调用点是装配期改写锚点，对标 C# P/Invoke 不可内联） |

---

## 10. 相关文件清单

**SL 侧**（2026-10-17 重组后：Front 工程 = `simple_language/source/`，标准库 = `SlangAllInOne/SLangCore/Lib/`）

| 文件 | 说明 |
|---|---|
| `SLangCore/Lib/Std/FFI/Library.sl` | `FFI.Library` / `FFI.StaticLibrary` |
| `SLangCore/Lib/Std/FFI/Struct.sl` | `FFI.Struct`（布局注册 / native 块 / 双向 marshal，T3） |
| `SLangCore/Lib/Std/Std.jsonc` | `SystemFFI*` / `SystemPtr*` / `SystemFFIStruct*` 系统方法声明与 `cvmFunction` 绑定 + `FFI/Struct.sl` 编译登记 |
| `simple_language/source/Core/AttributeManager.cs` | 挂点注册表（`@Nickname` / `@DllStaticImport` 等编译期 attribute 校验分派）+ Runtime Hooks |
| `simple_language/source/Core/MetaAttribute.cs` | attribute 解析与 handleType 判定（`ResolveHandleType`） |
| `simple_language/source/Core/MetaMemberVariable.cs` / `MetaMemberFunction.cs` | 调用点：express 为空 / ParseStatements 时走 `AttributeManager` 通用分派（挂点机制保留，`@DllImport` 已不再注册） |
| `simple_language/source/Core/Statements/MetaDefineVarStatements.cs` | sig 推导（`BuildFFIFunctionSig*`） |
| `simple_language/source/Project/ProjectCompile.cs` | `AutoInlineMarkFunctions`：运行时 attribute 方法排除自动 inline |
| `simple_language/source/IR/IRCall.cs` | 调用指令发射（CallStatic/CallVirt/CallDynamic；P10 起不再发射 77） |
| `simple_language/source/IROpEnum.cs` | opcode 定义 |
| `simple_language/source/Export/SLIR/SLIRTypes.cs` | `SLDllImportPackage` / `SLAttributePackage`（`SLFFIStaticCallPackage` P10 已删） |
| `simple_language/source/Export/SLIR/SLModulePackageWriter.cs` | 方法级 `attributeList` 导出 + `@DllImport` sig 推导补全 + **契约校验挂钩（T5）** |
| `simple_language/source/Export/SLIR/SlffiContract.cs` | **.slffi.json 契约加载/解析 + 签名类兼容校验（T5）** |
| `simple_language/source/Project/ProjectConfig.cs`、`ProjectJsoncLoader.cs`、`ProjectOutputEnvironment.cs` | `dllImports` 配置、别名解析（`ResolveDllImportPath`）、工程目录基准（契约路径展开） |
| `simple_language/source/Project/PorjectClass.cs` | `global.dllImport.<alias>` / `global.<funcName>` 注入 |
| `simple_language/source/Log/LID.cs` / `ErrorDefinitions.csv` | 契约校验错误码 21483/21484/21485（T5） |
| `SlangAllInOne/Ffi/FfiCheckCommand.cs` | `slang ffi-check` 子命令（schema 自检 + DLL 导出表比对，T5） |
| `SlangAllInOne/Project/CLangdll/CLangdll.dll.slffi.json` | 契约范本（v1：functionList 37 项 + structs + callbacks；vcxproj PostBuild 部署到 dll 同目录） |

**cvm 侧（`csimple_lang`）**

| 文件 | 说明 |
|---|---|
| `src/lib/ffi/sl_ffi_types.{h,c}` | 类型表、sig 解析 |
| `src/lib/ffi/sl_ffi_lib_manager.{h,c}` | 加载 / 去重 / 引用计数 / 卸载 |
| `src/lib/ffi/sl_ffi_call.{h,c}`（+ `gen_sl_ffi_call.py`） | x64 ABI 派发 |
| `src/lib/ffi/sl_ffi_callback_stubs.{h,c}`（+ `gen_sl_ffi_callback_stubs.py`） | 回调桩表（base-3 形状 × 槽 × 返回通道，17488 桩） |
| `src/lib/ffi/sl_ffi_struct.{h,c}` | **结构体布局注册表 + native 内存块（T3：sig 解析 / 自然对齐 / packed / magic 头）** |
| `src/vm/system_method_call/ffi_system_method.{h,c}` | `SystemFFI*`、回调 trampoline、静态绑定表、**`SystemFFIStruct*` 6 系统方法（T3，含双向 marshal 实现）** |
| `src/vm/runtime/attribute/vm_runtime_attribute.{c,h}` | 运行时 attribute 处理器注册表 + `@DllImport` 绑定器（collect / rewrite 两阶段，73→77 改写） |
| `src/vm/assembly/sl_runtime_assembly.c` | 静态库预载 + payload 改写 + `vm_runtime_attribute_process` 挂接 |
| `src/vm/assembly/slir_assembly_data.h` | `SLDllImportPackage`（含 `static_name`）、`SLAttributePackage` 镜像 |
| `src/vm/load/slir_json_module_loader.c` | `dllImports`（含 `"static"`）与字段/方法/类三级 `attributeList` 解析 |
| `src/vm/vm.h` | `OpCode_CallFFIStatic = 77`（紧随 `OpCode_CallSystemMethod = 76`） |
| `src/vm/runtime/vm_runtime.c` | opcode 77 handler、`CallClosure` native 分支、cleanup |

---

## 11. 可运行样例

`test/SpecialTest/FFITest.sl`（工程配置 `test/SpecialTest/ProjectTest.jsonc`）覆盖：

1. 库生命周期（加载 / addRef / 同路径去重 / 释放 / 引用计数）
2. 基础标量调用（i32 / i64）
3. 多宽度标量混合（`u8,i16,u32,i64,f32,f64->f64`）
4. Float8 / Float16 与 struct 位域分解、roundtrip
5. 混合标量打包进 struct + 指针读回/改写
6. 函数指针（native 返回函数指针、ptr 形参调用）
7. 回调（含嵌套重入 / 双回调）
7b. **全形状回调**（testCallbackShapes）：f32/f64 参数与返回、float 进 double 出、void 返回、INT/DBL/utf8 混合参数、utf8 进出、6 参满配 INT/DBL 交错、同槽重复触发 100 次
8. Utf8 字符串进出
9. 函数值（`Func<>` / typealias / `lookupFunction<T>`）
10. `Memory` 原生内存、`data` ↔ C struct 互转
11. `@DllImport`（路径 / 别名 / C# P/Invoke 风格 / fallback）
12. `dllImports` 配置与 `global.dllImport.<alias>`、`global.<funcName>`
13. **`@DllStaticImport` 与 `FFI.StaticLibrary.GetStaticLib`**
14. **`FFI.Struct` 结构体布局与双向 marshal**（testFFIStruct，60 项断言）：define 幂等 /
    C sizeof/offsetof 对齐 / marshalOut + C 侧读校验 / native malloc 块 marshalIn /
    实例形态（marshalOut 产新块）/ C 直写 VM 块（make/fill_const）/ 错误路径与
    无同名字段跳过
15. **`.slffi.json` 契约编译期校验**：正例（37 声明全过）+ 负例（错签名 21484 /
    未登记符号 21483 → 编译阻断）；`slang ffi-check` 独立校验

---

## 12. 速查

```sl
// ── 命令式 ─────────────────────────────────────────────
var lib = FFI.Library( path )
Int64 fn = lib.getSymbol( "sym" )
Int64 r  = SystemFFICallI32( fn, "i32,i32->i32", 20, 22 )
Func<int,int,int> f = lib.getFunction( "sym" )          // sig 编译期推导
lib.release()

// ── 全局能力 ───────────────────────────────────────────
FFI.StaticLibrary.libraryCount()
FFI.StaticLibrary.GetStaticLib( "静态名" )               // 预载库，未注册 null
FFI.StaticLibrary.createCallback( "methodId", "i64,i64->i64" )
FFI.StaticLibrary.freeCallback( addr )

// ── 声明式 ─────────────────────────────────────────────
@DllImport( "别名或路径", "符号" [, "sig"] )
static int f( int a, int b ) { ret a + b }              // 函数体 = fallback

@DllStaticImport( "静态名", "符号" [, "sig"] )
static int g( int a, int b ) { ret a + b }              // 函数体 = fallback

// ── 配置驱动 ───────────────────────────────────────────
global.dllImport.<alias>        // FFI.Library 实例
global.<funcName>( ... )        // dllImports functions 段注入的库函数

// ── 结构体布局（T3）───────────────────────────────────
Int32 id = FFI.Struct.define( "i32 width, f64 ratio, utf8 name" )
Int64 blk = FFI.Struct.alloc( id )                    // 或 var blk = FFI.Struct( id )
Int64 out = FFI.Struct.marshalOut( obj, id )          // SL -> 新 native 块（单独 free）
FFI.Struct.marshalIn( blk, id, obj )                  // native -> SL（按字段名）
FFI.Struct.free( out );  blk.free()

// ── 契约校验（T5）─────────────────────────────────────
slang ffi-check <X.dll>.slffi.json [--dll <X.dll>]    // schema + DLL 导出表比对
// dll 同目录放 .slffi.json -> @DllImport/@DllStaticImport 编译期签名校验
//（21483 符号未登记 / 21484 签名不兼容 / 21485 契约损坏）
```
