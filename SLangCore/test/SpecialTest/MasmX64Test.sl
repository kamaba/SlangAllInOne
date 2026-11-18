import Std;
import Core;

# ============================================================================
# MasmX64Test — masm_x64 插件端到端测试（MASM x64 汇编域 @tag 块）
#
# 链路：@masm_x64(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) → 导出期
# PluginManager 构建段转调插件 frontend（sl_label_parse 生成 Entry_N.asm：
# meta 头 + PUBLIC/PROC/ENDP 包裹用户指令 + 寄存器映射注释；sl_label_build
# 解析 meta 头生成 trampoline.c + ml64 /c 汇编 + cl /LD 合并链接部署
# SLMasm.dll）→ CVM 经模块 atSignLabel[] 绑定懒 resolve 到 sl_masm_x64
# labelExec → 装载 SLMasm.dll → GetProcAddress（"Entry_1_main"）固定原型
# 调用（SLMasmValue = SLLabelValue 逐字段镜像，in/out 数组零转换直拷）
# → trampoline 编译期解包/打包 → 出值回推。
#
# 通道类型路由（map_masm_in_kind 三入通道）：整型族 → int64（SL INT 槽）、
# 浮点族 → double（FLOAT 槽）、String 族 → const char*（UTF-8 NUL 结尾）。
# 入通道寄存器按 MS x64 ABI **参数位置配对**：位置 1..4 依次为 RCX/XMM0、
# RDX/XMM1、R8/XMM2、R9/XMM3（整型/str 取该位置的 GP 寄存器、浮点取该
# 位置的 XMM——如 Long,Double,String 三通道 = RCX、XMM1、R8）。
# 出通道三 kind（int/f64/str），取值寄存器尾行显式声明（int/long/string →
# rax、double → xmm0）；数值族（int/f64）在 Front 脱糖 MapChannelOutKind
# 均归 ChannelOutInt——FLOAT 出值经 sl_atsign_push_out_i32 截断，浮点出值
# 断言须选截断无损值（如 5.0）。
#
# 用例覆盖：① 无通道纯块 + EXTERN printf 外部调用（含 shadow space 与
# 栈 16 字节对齐规范）② 出通道 Int ③ int64 全域往返（无窄化回归锁）
# ④ double 入+出（3-4-5 → XMM0 sqrtsd 5.0）⑤ string 入+出（.data buffer
# 大写转换循环）⑥ 三类型混合入通道（位置配对验证）⑦ AVX2 SIMD
#（vmovdqu/vpaddd 4×int32 向量加倍）⑧ popcount 位技巧（循环版，免 CPU
# 特性依赖）⑨ CPUID 探测（vendor 串 → .data → RAX；push/pop rbx 非易失
# 寄存器保护示范）⑩ imul 大数 + idiv（RDX:RAX 约定）⑪ 库驻留复用
#（多块合并单一 SLMasm.dll 多轮调用）。
# 块内 MASM 代码约束：`<-` 序列禁用（通道标记语法）、行首 `$`/`#` 禁用、
# 行首裸 END/ENDP/PUBLIC/PROC 禁用（生成器包办）、数据段标签全 dll 唯一
#（多块共享同一汇编模块命名空间——各用例标签均已带块号后缀）、跳转标签
# PROC 内局部（MASM 语义，跨块不冲突）、非易失寄存器（RBX/RDI/RSI/RBP/
# R12-R15、XMM6-15 低位）须自行保存。
# 前置：先跑 plugin\masm_x64\cvm\build-masm-x64.ps1（插件 dll +
# frontend + refModule）；MSVC（cl + ml64 同工具集）本机可用。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员丢失）。
# ============================================================================

class MasmX64Test
{
    # 断言计数（供 fun 尾部汇总）
    static int passed = 0
    static int failed = 0

    # 简单断言辅助：打印 PASS / FAIL
    static check( string name, bool cond )
    {
        if ( cond )
        {
            passed = passed + 1
            Console.println( "  [PASS] " + name )
        }
        else
        {
            failed = failed + 1
            Console.println( "  [FAIL] " + name )
        }
    }

    # ---------------- ① 无通道纯块 + EXTERN printf 外部调用 ----------------
    # MS x64 ABI 调用规范实测：入口 RSP≡8 (mod 16)，sub 40 = 32B shadow
    # space + 8 对齐补偿 → call 时 RSP≡0；varargs 约定 AL=向量参数数（0）。
    # EXTERN 声明行被 parse 提升到模块顶（PROC 内不可声明）；.data 段
    # 标签 msg1 提升到 .code 之前。
    static testPlainBlock()
    {
        Console.println( "===== MasmX64Test.testPlainBlock =====" )
        int keep = 42
        @masm_x64()
        {
        EXTERN printf:PROC
        sub rsp, 40
        lea rcx, msg1
        xor eax, eax
        call printf
        add rsp, 40
        ret
        .data
        msg1 db "hello from masm_x64 (plain block, via EXTERN printf)", 0Ah, 0
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: executed (printf via EXTERN), outer variable untouched", keep == 42 )
    }

    # ---------------- ② 出通道 Int（两数相加 → RAX） ----------------
    # a=RCX、b=RDX（整型族前两个）；汇编体须以 ret 收尾。
    static testIntOutChannel()
    {
        Console.println( "===== MasmX64Test.testIntOutChannel =====" )
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
        Console.println( "27 + 15 = " + sum.toString() )
        check( "int out channel: add 27+15 == 42", sum == 42 )
    }

    # ---------------- ③ int64 全域往返（无窄化决策回归锁） ----------------
    # 4000000000 超 int32 max（2147483647）——若任一侧误走 int32 窄化会回绕为负。
    static testInt64Roundtrip()
    {
        Console.println( "===== MasmX64Test.testInt64Roundtrip =====" )
        long big = 4000000000
        long halfVal = 0
        @masm_x64()
        {
        Long big <- $big
        mov rax, rcx
        shr rax, 1
        ret
        $halfVal <- rax;
        }
        Console.println( "4000000000 / 2 = " + halfVal.toString() )
        check( "int64 full range: 4000000000 / 2 == 2000000000 (no narrowing)", halfVal == 2000000000 )
    }

    # ---------------- ④ double 入+出（3-4-5 → XMM0 sqrtsd 5.0） ----------------
    # 浮点族分族占位：a=XMM0、b=XMM1；出值 XMM0 经 ChannelOutInt 截断
    # 消费——5.0 截断无损（同蓝本策略）。
    static testDoubleRoundtrip()
    {
        Console.println( "===== MasmX64Test.testDoubleRoundtrip =====" )
        double a = 3.0
        double b = 4.0
        double hyp = 0.0
        @masm_x64()
        {
        Double a <- $a
        Double b <- $b
        mulsd xmm0, xmm0
        mulsd xmm1, xmm1
        addsd xmm0, xmm1
        sqrtsd xmm0, xmm0
        ret
        double $hyp <- xmm0;
        }
        Console.println( "hypot(3,4) = " + hyp.toString() )
        check( "double channels: sqrtsd(3*3+4*4) == 5.0", hyp == 5.0 )
    }

    # ---------------- ⑤ 入+出通道 String（.data buffer 大写转换） ----------------
    # RCX = const char*（str 占整型族序列）；逐字节转大写写入 .data 缓冲
    # buf5，NUL 收尾，RAX 返回缓冲地址（trampoline 深拷贝回推）。
    # 跳转标签 PROC 内局部（MASM 语义），跨块不冲突。
    static testStringRoundtrip()
    {
        Console.println( "===== MasmX64Test.testStringRoundtrip =====" )
        string name = "SimpleLanguage"
        string upper = ""
        @masm_x64()
        {
        String name <- $name
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
        Console.println( "upper = " + upper )
        check( "string channels: uppercase(SimpleLanguage) == SIMPLELANGUAGE", upper == "SIMPLELANGUAGE" )
    }

    # ---------------- ⑥ 三类型混合入通道（位置配对验证） ----------------
    # MS x64 ABI 按参数位置配对：Long n（位置 1）= RCX、Double w（位置 2）
    # = XMM1（XMM0 空置——位置 1 被 int 占用）、String s（位置 3）= R8
    #（RDX 空置——位置 2 被 double 占用）。
    # 期望 = 7 + (int)2.5 * 10 (=20) + strlen("hi") (=2) = 29。
    static testMixedChannels()
    {
        Console.println( "===== MasmX64Test.testMixedChannels =====" )
        long n = 7
        double w = 2.5
        string s = "hi"
        long mixed = 0
        @masm_x64()
        {
        Long n <- $n
        Double w <- $w
        String s <- $s
        cvttsd2si r10, xmm1
        imul r10, r10, 10
        add rcx, r10
        xor r9, r9
        len_loop6:
        cmp byte ptr [r8 + r9], 0
        je len_done6
        inc r9
        jmp len_loop6
        len_done6:
        add rcx, r9
        mov rax, rcx
        ret
        $mixed <- rax;
        }
        Console.println( "mixed = " + mixed.toString() )
        check( "mixed channels: 7 + (int)2.5*10 + strlen(hi) == 29", mixed == 29 )
    }

    # ---------------- ⑦ AVX2 SIMD（vpaddd 4×int32 向量加倍） ----------------
    # 立身点用例：单条 vpaddd 同时加倍 4 个 int32 通道值（a/b/c/d =
    # ECX/EDX/R8D/R9D），结果按 [低32=2a | 高32=2b] 打包回 RAX。
    # a=1,b=2 → 2 | (4<<32) = 17179869186。
    static testAvx2Simd()
    {
        Console.println( "===== MasmX64Test.testAvx2Simd =====" )
        int a = 1
        int b = 2
        int c = 3
        int d = 4
        long packed = 0
        @masm_x64()
        {
        Int a <- $a
        Int b <- $b
        Int c <- $c
        Int d <- $d
        mov dword ptr [arr7], ecx
        mov dword ptr [arr7+4], edx
        mov dword ptr [arr7+8], r8d
        mov dword ptr [arr7+12], r9d
        vmovdqu xmm0, xmmword ptr [arr7]
        vpaddd xmm0, xmm0, xmm0
        vmovdqu xmmword ptr [arr7], xmm0
        mov eax, dword ptr [arr7]
        mov edx, dword ptr [arr7+4]
        shl rdx, 32
        or rax, rdx
        ret
        .data
        arr7 dd 16 dup(0)
        $packed <- rax;
        }
        Console.println( "packed = " + packed.toString() )
        check( "avx2 simd: vpaddd doubles 4 lanes, packed == 17179869186 (2 | 4<<32)", packed == 17179869186 )
    }

    # ---------------- ⑧ 位技巧：popcount（循环版，免 CPU 特性依赖） ----------------
    static testPopcount()
    {
        Console.println( "===== MasmX64Test.testPopcount =====" )
        long v1 = 255
        long v2 = 1023
        long pc1 = 0
        long pc2 = 0
        @masm_x64()
        {
        Long v <- $v1
        xor rax, rax
        pop_loop8:
        test rcx, rcx
        jz pop_done8
        mov rdx, 1
        and rdx, rcx
        add rax, rdx
        shr rcx, 1
        jmp pop_loop8
        pop_done8:
        ret
        $pc1 <- rax;
        }
        @masm_x64()
        {
        Long v <- $v2
        xor rax, rax
        pop_loop8b:
        test rcx, rcx
        jz pop_done8b
        mov rdx, 1
        and rdx, rcx
        add rax, rdx
        shr rcx, 1
        jmp pop_loop8b
        pop_done8b:
        ret
        $pc2 <- rax;
        }
        Console.println( "popcount(255) = " + pc1.toString() + ", popcount(1023) = " + pc2.toString() )
        check( "popcount(255) == 8", pc1 == 8 )
        check( "popcount(1023) == 10", pc2 == 10 )
    }

    # ---------------- ⑨ CPUID 探测（vendor 串 → .data → RAX） ----------------
    # CPUID 会破坏 RBX（非易失寄存器）——push/pop rbx 是非易失保护的
    # 示范写法（违反 ABI = 调用后随机崩溃）。
    static testCpuidVendor()
    {
        Console.println( "===== MasmX64Test.testCpuidVendor =====" )
        string vendor = ""
        @masm_x64()
        {
        push rbx
        xor eax, eax
        cpuid
        mov dword ptr [vendor9], ebx
        mov dword ptr [vendor9+4], edx
        mov dword ptr [vendor9+8], ecx
        mov rax, OFFSET vendor9
        pop rbx
        ret
        .data
        vendor9 db 16 dup(0)
        string $vendor <- rax;
        }
        Console.println( "cpu vendor = " + vendor )
        check( "cpuid vendor via .data buffer (12 bytes)", vendor == "GenuineIntel" || vendor == "AuthenticAMD" )
    }

    # ---------------- ⑩ 64 位乘除（imul / cqo+idiv RDX:RAX 约定） ----------------
    static testMulDiv64()
    {
        Console.println( "===== MasmX64Test.testMulDiv64 =====" )
        long a = 123456789
        long b = 987654321
        long prod = 0
        @masm_x64()
        {
        Long a <- $a
        Long b <- $b
        mov rax, rcx
        imul rax, rdx
        ret
        $prod <- rax;
        }
        long dividend = 999999999
        long divisor = 3
        long quotient = 0
        @masm_x64()
        {
        Long dividend <- $dividend
        Long divisor <- $divisor
        mov rax, rcx
        cqo
        idiv rdx
        ret
        $quotient <- rax;
        }
        Console.println( "prod = " + prod.toString() + ", quotient = " + quotient.toString() )
        check( "imul: 123456789 * 987654321 == 121932631112635269", prod == 121932631112635269 )
        check( "idiv (cqo, RDX:RAX): 999999999 / 3 == 333333333", quotient == 333333333 )
    }

    # ---------------- ⑪ 库驻留复用（多块合并单一 SLMasm.dll） ----------------
    # 与 ②/③ 同款汇编体的新块（新 Entry_N）——验证多块合并链接与
    # HMODULE 缓存命中路径。
    static testLibResidency()
    {
        Console.println( "===== MasmX64Test.testLibResidency =====" )
        int a = 100
        int b = 200
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
        long big = 8589934592
        long halfOut = 0
        @masm_x64()
        {
        Long big <- $big
        mov rax, rcx
        shr rax, 1
        ret
        $halfOut <- rax;
        }
        Console.println( "sum = " + sum.toString() + ", halfOut = " + halfOut.toString() )
        check( "lib residency: reuse add block (merged dll)", sum == 300 )
        check( "lib residency: int64 shr across blocks (2^33 / 2 == 2^32)", halfOut == 4294967296 )
    }

    static fun()
    {
        Console.println( "========== MasmX64Test start ==========" )
        testPlainBlock()
        testIntOutChannel()
        testInt64Roundtrip()
        testDoubleRoundtrip()
        testStringRoundtrip()
        testMixedChannels()
        testAvx2Simd()
        testPopcount()
        testCpuidVendor()
        testMulDiv64()
        testLibResidency()
        Console.println( "========== MasmX64Test end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}
