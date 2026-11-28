# MasmX64 —— @masm_x64(){} 内联汇编块（使用说明）

> 插件：`plugin/masm_x64`（Windows x64 专用，仅 signLabel 能力）。
> 作用：在 SL 源码中内联 x86-64 MASM 汇编，编译期汇编为原生库，运行期执行，
> 通道直连 SL 变量。适用于极致热点优化（SIMD、位技巧、CPU 特性指令）。

## 1. 能做什么 / 不能做什么

**能**：

- 在方法体内写 `@masm_x64(){} 块，块体为 MASM x64 汇编指令原文；
- 入通道把 SL 的 int/long/double/float/string 变量值传进寄存器；
- 出通道把 RAX（int/long/string）或 XMM0（double）的值写回 SL 变量；
- 块内声明 `.data` 数据段、`EXTERN` 外部函数（如 printf）并调用；
- 同一工程多个块合并编译为单一 `SLMasm.dll`（进程内驻留复用）。

**不能（P0）**：

- Boolean / Object（含 SL 类实例）入出通道（编译期报错）；
- 入通道超过 4 个（MS x64 ABI 寄存器传参位上限，栈传参未支持）；
- `@masm_x64( 参数 )` 小括号参数表（P0 须空参数形态）；
- 块内 FFI 直调导出（P1 计划：命名导出块）；
- Linux / 非 x64 平台（`platform` 段限定 windows+x64）。

## 2. 块的写法

```sl
@masm_x64()
{
Long a <- $a          # ① 入通道行（头区）：[SLType] 名字 <- $SL变量
Double w <- $w        #    每行一个，声明顺序 = 参数位置顺序
String s <- $s
mov rax, rcx          # ② 汇编体（中段）：纯 MASM x64 指令
; 注释用分号
mylabel:              #    自定义跳转标签须顶格（PROC 内局部，跨块不冲突）
cvttsd2si r10, xmm1
add rax, r10
ret                   #    块体须以 ret 收尾
.data                 # ③ 数据段（可选）：声明提升到代码段之前
buf db 256 dup(0)
$total <- rax;        # ④ 出通道行（尾区，必须是块内最后一行）
}
```

**四段结构**：头区入通道行 → 中段汇编体 → 尾行出通道（必须最后）→ 数据段
可在 `ret` 之后、出通道行之前。

### 2.1 入通道 → 寄存器映射（按参数位置配对）

| 位置 | int/long/string | double/float |
|------|-----------------|--------------|
| 1 | RCX | XMM0 |
| 2 | RDX | XMM1 |
| 3 | R8 | XMM2 |
| 4 | R9 | XMM3 |

⚠ **位置配对**，不是"整型一堆、浮点一堆"分开数：`Long, Double, String`
三通道 = **RCX、XMM1、R8**（位置 2 是 double，占 XMM1，RDX 空置不用）。

### 2.2 出通道

| 尾行写法 | 取值 | 说明 |
|----------|------|------|
| `$v <- rax;`（缺省/`int`/`long` 标记） | RAX | **SL 侧按 Int32 消费——出值须在 -2147483648..2147483647 内**，超出会截断 |
| `double $v <- xmm0;` | XMM0 | SL 侧截断取整消费——断言用截断无损值（如 5.0） |
| `string $v <- rax;` | RAX（char*） | 须 NUL 结尾且调用期内有效（`.data` 静态缓冲最稳）；自动深拷贝回传 |

## 3. 块内汇编的规则

- 方言 = **MASM x64（llvm-ml64，ml64 兼容）**：Intel 语法、`;` 行注释、`PROC/ENDP`、
  `.data/.code` 段（插件自带 `toolchain\bin\llvm-ml64.exe` + `clang-cl.exe` +
  `lld-link.exe`，构建不依赖机器上的 MSVC ml64/cl/link——见 §8）；
- **禁**（编译期报错）：
  - `<-` 序列出现在中段（通道标记语法保留；字符串/注释内放行）；
  - 行首 `$`（通道标记语法保留）；
  - 行首 `#`（SL 词法吞换行坑；MASM 注释一律用 `;`）；
  - 行首裸 `END`/`ENDP`/`PUBLIC`/`PROC`（生成器统一包办框架）；
- `.data`/`.data?`/`.const`/`.fardata` 行切数据段模式（声明自动提升到代码段之前），
  `.code` 行切回（该行被吸收，生成器有自己的 `.code` 段头）；
- `EXTERN name:PROC` 声明自动提升到模块顶（PROC 内不能声明）；调外部函数须
  遵守 MS x64 ABI：`sub rsp, 40`（32B shadow space + 8 对齐）、varargs 先
  `xor eax, eax`（AL=向量参数数）、用完 `add rsp, 40`；
- **数据段标签全 dll 唯一**（多块共享同一汇编模块命名空间，建议带块号后缀如
  `buf5`）；跳转标签是 PROC 内局部作用域（MASM 语义），跨块同名无冲突；
- `OFFSET 标签` 可用（`mov r8, OFFSET buf5`）：捆绑 llvm-ml64 把它汇编成
  32 位绝对地址，插件链接端以固定低基址 0x62000000 + 关 ASLR 保证其正确性
  （详见 §8 第 4 条）；推荐优先 `lea r8, buf5`（RIP 相对，与基址无关）。

## 4. 必须遵守的 ABI 纪律（违反 = 调用后随机崩溃或结果错乱）

- **易失寄存器的值不得跨 `call` 存活（★ 最易踩）**：RAX/RCX/RDX/R8-R11、
  XMM0-5 是易失寄存器——任何 `call`（含你自己的递归助手）都可能破坏它们。
  需要跨调用保存的中间值必须放**非易失寄存器**（RBX/RDI/RSI/RBP/R12-R15，
  用前 push 用后 pop）或 `.data` 内存。实测翻车例：递归 fib 把 f(n-1) 存
  RDX，第二次递归调用的子树内部又写 RDX → f(n) 退化成 f(n-2)+1（指令序列
  全对、反汇编无懈可击——错的是调用约定语义）。
- **非易失寄存器**用前必须保存、用后恢复：RBX、RDI、RSI、RBP、R12-R15、
  XMM6-XMM15 低位。示例（CPUID 会破坏 RBX）：

```sl
push rbx
xor eax, eax
cpuid
mov dword ptr [vendor], ebx
mov dword ptr [vendor+4], edx
mov dword ptr [vendor+8], ecx
mov rax, OFFSET vendor
pop rbx
ret
```

- **除法陷阱**：`cqo` 会把 RAX 符号位填进 RDX——除数不能留在 RDX，先挪
  `mov r8, rdx` 再 `cqo; idiv r8`（直接 `cqo; idiv rdx` = 除零崩溃）；
- 栈对齐：进入块时 RSP ≡ 8 (mod 16)；调外部函数前须使 call 时 RSP ≡ 0
  （入口 `sub rsp, 40` 即满足）并留 32 字节 shadow space。

## 5. 红线（显著警示）

**汇编体写错 = 进程崩溃，无任何防护。** 坏指令、坏地址、破坏非易失寄存器、
坏栈对齐都会直接带崩整个进程——`try-catch` 捕不住，错误码体系对汇编体内部
无效。这是汇编的固有性质，不是插件缺陷；无法承受崩溃风险的代码不要写进块里。

## 6. 错误码（可被 try-catch 捕获的插件级错误）

| code | 含义 |
|------|------|
| -101 | 参数/通道校验失败（计数越界、lib/entry/entry_method 为空） |
| -102 | SLMasm.dll 装载失败（未汇编？先跑 build 脚本） |
| -103 | 入口符号解析失败 |
| -104 | 入参类型/计数与通道声明不符 |

```sl
label
{
    @masm_x64() { ... }
}
try
{
    ...
}
catch
{
    # err.code 可能为 -102 等
}
```

## 7. 示例集

完整可运行用例 = `SlangAllInOne/SLangCore/test/SpecialTest/MasmX64Test.sl`
（14 断言）：纯块 + printf、int/int64/double/string 通道、三类型混合、
AVX2 SIMD、popcount、CPUID、imul/idiv、库驻留复用。

### 7.1 两数相加

```sl
int a = 27
int b = 15
int sum = 0
@masm_x64()
{
Int a <- $a
Int b <- $b
mov rax, rcx
add rax, rdx
ret
$sum <- rax;
}
# sum == 42
```

### 7.2 字符串大写转换（.data 缓冲 + 循环）

```sl
string name = "SimpleLanguage"
string upper = ""
@masm_x64()
{
String name <- $name          # 位置 1 → RCX
mov r8, OFFSET buf5
up_loop5:
movzx r9, byte ptr [rcx]
test r9, r9
jz up_done5
cmp r9b, 'a'
jb up_store5
cmp r9b, 'z'
ja up_store5
sub r9b, 32
up_store5:
mov byte ptr [r8], r9b
inc rcx
inc r8
jmp up_loop5
up_done5:
mov byte ptr [r8], 0
mov rax, OFFSET buf5
ret
.data
buf5 db 256 dup(0)
string $upper <- rax;
}
# upper == "SIMPLELANGUAGE"
```

### 7.3 AVX2 向量加倍（SIMD）

```sl
int a = 1
int b = 2
int c = 3
int d = 4
int total = 0
@masm_x64()
{
Int a <- $a                  # 位置 1..4 → ECX/EDX/R8D/R9D
Int b <- $b
Int c <- $c
Int d <- $d
mov dword ptr [arr7], ecx
mov dword ptr [arr7+4], edx
mov dword ptr [arr7+8], r8d
mov dword ptr [arr7+12], r9d
vmovdqu xmm0, xmmword ptr [arr7]
vpaddd xmm0, xmm0, xmm0      ; 单条指令同时加倍 4 个 int32
vmovdqu xmmword ptr [arr7], xmm0
mov eax, dword ptr [arr7]
add eax, dword ptr [arr7+4]
add eax, dword ptr [arr7+8]
add eax, dword ptr [arr7+12]
ret
.data
arr7 dd 16 dup(0)
$total <- rax;
}
# total == 20
```

## 8. 工程接入清单

1. 构建：`powershell -ExecutionPolicy Bypass -File plugin\masm_x64\cvm\build-masm-x64.ps1`；
2. 调用方 jsonc `plugins` 段加 `masm_x64` 条目（lib 字符串直给原位相对路径，
   模板见 `plugin/masm_x64/README.md`）；
3. AtSign 哨兵两条 systemCalls（`AtSignLabelCall`/`AtSignLabelCallVoid`，
   `cvmFunction: "atsign:label"`）调用方工程须已声明；
4. 块构建工具链走插件**自带 LLVM 工具链**（`package\windows\toolchain\bin\`：
   `llvm-ml64.exe` 汇编 + `clang-cl.exe` 编译 + `lld-link.exe` 链接，由
   `build-masm-x64.ps1` 第 2.55 步从本地 LLVM 构建树同步）；缺工具时块构建
   Info 级跳过（`SL_ML64`/`SL_CLANGCL` 环境变量可指定全路径覆盖）。MSVC
   头/库定位交 clang-cl 自身 VS auto-detect，无需 VS 开发环境提示符。
   SLMasm.dll 以**固定低基址 0x62000000 + 关 ASLR** 链接：llvm-ml64 的
   `OFFSET` 汇编成 32 位绝对地址（mov imm32 符号扩展），默认镜像基址
   0x180000000 会截断成垃圾指针，低固定基址保证 `OFFSET` 取址正确。

## 9. 基准测试（BenchMark 套件）

`BenchMark` 工程含 **MasmBench**（`SlangAllInOne/SLangCore/test/BenchMark/MasmBench.sl`）：
四项基准，块内 `QueryPerformanceCounter/Frequency`（EXTERN 声明）ns 精确计时，
经出通道回传：

| 基准 | 内容 | 参照 |
|------|------|------|
| Loop | for sum 1e6 ×10 / while 5e6 / step 1e6 | 与 SL/C/C++ 同口径跨语言对拍 |
| EqBench | i32/i64/f64/bool 4 子项 | 同上 |
| Fibonacci | 递归 fib(0..21) ×100 轮（校验 fib(23)-1 之百倍） | 同上 |
| SimdAVX2 | vpaddd 4 车道向量累加 5e6 次（校验 5e7） | ASM 专列（手写 SIMD 对照编译器自动向量化） |

运行（`BenchMark.sp` 驱动含 `MasmBench.fun()`，报告自动生成 `report/BenchmarkReport_*.md`，
多语言对比总表含 **ASM 列**）：

```powershell
powershell -ExecutionPolicy Bypass -File plugin\masm_x64\cvm\build-masm-x64.ps1   # ① 插件三件套
dotnet run --no-launch-profile --project simple_language\source\SimpleLanguageFront.csproj -- compile -p SlangAllInOne\SLangCore\test\BenchMark\BenchMark.sp -e ir --format binary --no-banner   # ② 本工程最后编译（SLMasm.dll 共享部署位）
csimple_lang\build\Debug\bin\csimple_lang.exe run --no-banner SlangAllInOne\out\export\BenchMark\BenchMark.module.slb   # ③ 运行
```

参考量级（本机单次实测）：Loop ASM ~3ms vs SL ~20s；EqBench ~2ms vs SL ~2.8s；
Fibonacci ~9ms vs SL ~151ms。
