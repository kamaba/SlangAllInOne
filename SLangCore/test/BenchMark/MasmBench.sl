import Std

# ============================================================================
# MasmBench — x86-64 MASM 汇编基准（@masm_x64(){} 内联块，masm_x64 插件原生汇编）
#
# 三项与 SL/C/C++ 共享基准同口径（Loop / EqBench / Fibonacci，校验和可跨
# 语言对拍），外加 SimdAVX2 一项 ASM 专列（AVX2 vpaddd 4 车道向量累加——
# 手写 SIMD 对照编译器自动向量化）。
#
# 计时（2026-11-19 修订）：asm 出通道 $ns <- rax 回传在本机实测拿不到值
#（块内 QPC printf 有精确 ns 输出，但回传到 SL 变量 ns 为 0，报告 ASM 列
# 显示空）——按「asm 无可靠计时回传方法则用 SL 计时」约定，统计值改用 SL
# 侧 Environment.sys.nowMillis() 包住整个 masm 块调用（LLM 约定口径）。
# 块内 QueryPerformanceCounter/Frequency 的 printf 保留作精确算法耗时参考
#（stdout 原始日志），SL 计时值经 recordMasm 进对比报告，保证 ASM 列有数。
# 说明：SL 毫秒粒度，asm 项多为个位数 ms，够用；含 masm 块 trampoline
# 调用开销（跨语言边界），与 C/C++ 的「净算法耗时」口径略有差异。
#
# 汇编纪律（详见 md/plugins/MasmX64.md）：非易失寄存器（rbx/rsi/rdi/r12-r15）
# 用前 push 用后 pop，各块 push 总数取偶数（偶数 push 后 RSP≡8 (mod 16)，
# API 调用统一 sub rsp,40 = 32B shadow space + 8 对齐补偿 → call 时 RSP≡0）；
# printf 前置 xor eax,eax（varargs AL=向量参数数=0）；idiv 除数不得驻留 RDX
#（cqo 会覆盖，一律先挪 R8）；QPC/printf 会破坏易失寄存器——子项结果先落
# .data 存储再复用寄存器；数据段标签全 dll 唯一（各块前缀 L_/E_/F_/S_）；
# 递归 fib 助手用双冒号全局标签 F_fib::（rcx=n → rax，内部无外部调用）。
# 块内代码约束：`<-` 序列禁用；行首 $/# 禁用；行首裸 END/ENDP/PUBLIC/PROC
# 禁用；块内不用 # 行注释（一律 ;）。
# 前置：先跑 plugin\masm_x64\cvm\build-masm-x64.ps1（含自带 LLVM 工具链
# 同步）。SLMasm.dll 为共享部署位（后编译覆盖）——运行
# BenchMark 前须最后编译本工程（同 SLCpp.dll / java classes 行为）。
# ============================================================================

MasmBench
{
	static fun()
	{
		long ns = MasmBench.loopBench()
		BenchCollector.recordMasm("Loop", "for sum 1e6 x10 / while 5e6 / step 1e6 3 子项（块内 QPC ns）", ns)

		ns = MasmBench.eqBench()
		BenchCollector.recordMasm("EqBench", "i32/i64/f64/bool 4 子项（块内 QPC ns）", ns)

		ns = MasmBench.fibonacci()
		BenchCollector.recordMasm("Fibonacci", "fib(0..21) 递归求和 x100 轮（块内 QPC ns）", ns)

		ns = MasmBench.simdAVX2()
		BenchCollector.recordMasm("SimdAVX2", "vpaddd 4 车道向量累加 5e6 次（ASM 专列，块内 QPC ns）", ns)
	}

	# 1. Loop：for sum 1..1e6 × 10 轮 / while k<5e6 / step 累加 1e6 步 三子项
	#（对齐 SL Loop / C++ loopBench 语义；校验和 = 三段求和结果合计）
	static long loopBench()
	{
		Console.println("========== Loop (ASM) (start) ==========")
		long ns = 0L
		long slT0 = Environment.sys.nowMillis()
		@masm_x64()
		{
		EXTERN QueryPerformanceCounter:PROC
		EXTERN QueryPerformanceFrequency:PROC
		EXTERN printf:PROC
		push rbx
		push rsi
		push rdi
		push r12
		push r13
		push r14
		lea rcx, L_qf
		sub rsp, 40
		call QueryPerformanceFrequency
		add rsp, 40
		mov rbx, [L_qf]
		; ---- 子项 1：for sum 1..1e6 × 10 轮（rdi 累计 10 轮总和） ----
		lea rcx, L_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor rdi, rdi
		mov rsi, 10
		L_rounds:
		xor eax, eax
		mov ecx, 1
		L_for:
		add rax, rcx
		inc rcx
		cmp rcx, 1000000
		jle L_for
		add rdi, rax
		dec rsi
		jnz L_rounds
		mov [L_sum1], rdi
		lea rcx, L_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [L_t1]
		sub rax, [L_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r12, rax
		; ---- 子项 2：while k != 5e6（rsi = 求和） ----
		lea rcx, L_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor rsi, rsi
		xor ecx, ecx
		L_while:
		add rsi, rcx
		inc rcx
		cmp rcx, 5000000
		jne L_while
		mov [L_sum2], rsi
		lea rcx, L_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [L_t1]
		sub rax, [L_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r13, rax
		; ---- 子项 3：step 累加 1e6 步（i += 3，rdx = 求和） ----
		lea rcx, L_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor ecx, ecx
		xor edx, edx
		mov rsi, 1000000
		L_step:
		add rcx, 3
		add rdx, rcx
		dec rsi
		jnz L_step
		mov [L_sum3], rdx
		lea rcx, L_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [L_t1]
		sub rax, [L_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r14, rax
		; ---- 汇总与校验输出（printf 不在计时区内） ----
		mov rax, r12
		add rax, r13
		add rax, r14
		mov [L_total], rax
		lea rcx, L_fmt
		mov rdx, [L_sum1]
		mov r8, [L_sum2]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		lea rcx, L_fmt2
		mov rdx, r12
		mov r8, r13
		mov r9, r14
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		lea rcx, L_fmt3
		mov rdx, [L_total]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		mov rax, [L_total]
		pop r14
		pop r13
		pop r12
		pop rdi
		pop rsi
		pop rbx
		ret
		.data
		align 8
		L_qf dq 0
		L_t0 dq 0
		L_t1 dq 0
		L_sum1 dq 0
		L_sum2 dq 0
		L_sum3 dq 0
		L_total dq 0
		L_fmt db "masm Loop: forsum10 checksum=%lld while5e6=%lld", 0Ah, 0
		L_fmt2 db "  [for x10 %lld ns | while %lld ns | step %lld ns]", 0Ah, 0
		L_fmt3 db "  total %lld ns", 0Ah, 0
		$ns <- rax;
		}
		long slMs = Environment.sys.nowMillis() - slT0
		ns = slMs * 1000000L
		Console.println("========== Loop (ASM) (end) [" + slMs.toString() + " ms SL] ==========")
		ret ns
	}

	# 2. EqBench：i32/i64/f64/bool 四子项（对齐 CSharp/C++ EqBench）
	# QPC 会破坏易失寄存器——各子项结果先落 .data；bool 子项条件值用 dl
	#（不用 bl——rbx 驻留 QPC 频率）。
	static long eqBench()
	{
		Console.println("========== EqBench (ASM) (start) ==========")
		long ns = 0L
		long slT0 = Environment.sys.nowMillis()
		@masm_x64()
		{
		EXTERN QueryPerformanceCounter:PROC
		EXTERN QueryPerformanceFrequency:PROC
		EXTERN printf:PROC
		push rbx
		push rsi
		push rdi
		push r12
		push r13
		push r14
		push r15
		push rbp
		lea rcx, E_qf
		sub rsp, 40
		call QueryPerformanceFrequency
		add rsp, 40
		mov rbx, [E_qf]
		; ---- i32 != 2e6 ----
		lea rcx, E_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor eax, eax
		xor ecx, ecx
		E_i32:
		add rax, rcx
		inc ecx
		cmp ecx, 2000000
		jne E_i32
		mov [E_s32], rax
		lea rcx, E_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [E_t1]
		sub rax, [E_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r12, rax
		; ---- i64 != 2e6 ----
		lea rcx, E_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor rax, rax
		xor rcx, rcx
		E_i64:
		add rax, rcx
		inc rcx
		cmp rcx, 2000000
		jne E_i64
		mov [E_s64], rax
		lea rcx, E_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [E_t1]
		sub rax, [E_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r13, rax
		; ---- f64 != 2e6（计时区内无 API 调用，xmm0-5 可自由用） ----
		lea rcx, E_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xorps xmm0, xmm0
		xorps xmm1, xmm1
		E_f64:
		movsd xmm2, [E_two_mil]
		comisd xmm0, xmm2
		je E_f64_done
		addsd xmm1, xmm0
		addsd xmm0, [E_one]
		jmp E_f64
		E_f64_done:
		movsd [E_sd], xmm1
		lea rcx, E_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [E_t1]
		sub rax, [E_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r14, rax
		; ---- bool == 1e6（if(true) cnt++ 字面形态；dl = 条件值） ----
		lea rcx, E_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov dl, 1
		xor esi, esi
		mov edi, 1000000
		E_bool:
		test dl, dl
		jz E_bool_skip
		inc rsi
		E_bool_skip:
		dec rdi
		jnz E_bool
		mov [E_cnt], rsi
		lea rcx, E_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [E_t1]
		sub rax, [E_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov r15, rax
		; ---- 汇总与校验输出 ----
		mov rax, r12
		add rax, r13
		add rax, r14
		add rax, r15
		mov [E_total], rax
		lea rcx, E_fmt
		mov rdx, [E_s32]
		mov r8, [E_s64]
		mov r9, [E_cnt]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		lea rcx, E_fmt2
		mov rdx, r12
		mov r8, r13
		mov r9, r14
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		lea rcx, E_fmt3
		mov rdx, r15
		mov r8, [E_total]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		mov rax, [E_total]
		pop rbp
		pop r15
		pop r14
		pop r13
		pop r12
		pop rdi
		pop rsi
		pop rbx
		ret
		.data
		align 8
		E_qf dq 0
		E_t0 dq 0
		E_t1 dq 0
		E_s32 dq 0
		E_s64 dq 0
		E_sd dq 0.0
		E_cnt dq 0
		E_total dq 0
		E_one dq 1.0
		E_two_mil dq 2000000.0
		E_fmt db "masm EqBench: i32=%lld i64=%lld bool=%lld", 0Ah, 0
		E_fmt2 db "  [i32 %lld ns | i64 %lld ns | f64 %lld ns", 0Ah, 0
		E_fmt3 db "   | bool %lld ns]  total %lld ns", 0Ah, 0
		$ns <- rax;
		}
		long slMs = Environment.sys.nowMillis() - slT0
		ns = slMs * 1000000L
		Console.println("========== EqBench (ASM) (end) [" + slMs.toString() + " ms SL] ==========")
		ret ns
	}

	# 3. Fibonacci：递归求和 fib(0..21) × 100 轮（sum=27059/轮，校验 2705900）
	# 递归助手 = 双冒号全局标签 F_fib::（rcx=n → rax）。
	# ⚠ ABI 纪律（本用例即回归锁）：f(n-1) 必须存**非易失寄存器 RBX**（push/pop
	# 配对保存）——第一版存 RDX（易失寄存器），第二次递归 call 的子树内部
	# `mov rdx,rax` 会把它毁掉，f(n) 退化成 f(n-2)+1 = ceil(n/2)（实测
	# fib(10)=5 翻车）。易失寄存器（RAX/RCX/RDX/R8-R11/XMM0-5）的值一律
	# 不得跨 call 存活。
	static long fibonacci()
	{
		Console.println("========== Fibonacci (ASM) (start) ==========")
		long ns = 0L
		long slT0 = Environment.sys.nowMillis()
		@masm_x64()
		{
		EXTERN QueryPerformanceCounter:PROC
		EXTERN QueryPerformanceFrequency:PROC
		EXTERN printf:PROC
		push rbx
		push rsi
		push rdi
		push r12
		push r13
		push rbp
		lea rcx, F_qf
		sub rsp, 40
		call QueryPerformanceFrequency
		add rsp, 40
		mov rbx, [F_qf]
		lea rcx, F_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xor r12, r12
		mov r13, 100
		F_rounds:
		xor esi, esi
		xor edi, edi
		F_loop:
		mov rcx, rdi
		call F_fib
		add rsi, rax
		inc rdi
		cmp rdi, 22
		jl F_loop
		add r12, rsi
		dec r13
		jnz F_rounds
		lea rcx, F_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		mov rax, [F_t1]
		sub rax, [F_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov [F_ns], rax
		lea rcx, F_fmt
		mov rdx, r12
		mov r8, [F_ns]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		mov rax, [F_ns]
		jmp F_end
		F_fib::
		cmp rcx, 1
		jbe F_fib_base
		push rbx
		push rcx
		dec rcx
		call F_fib
		mov rbx, rax
		pop rcx
		sub rcx, 2
		call F_fib
		add rax, rbx
		pop rbx
		ret
		F_fib_base:
		mov rax, rcx
		ret
		F_end:
		pop rbp
		pop r13
		pop r12
		pop rdi
		pop rsi
		pop rbx
		ret
		.data
		align 8
		F_qf dq 0
		F_t0 dq 0
		F_t1 dq 0
		F_ns dq 0
		F_fmt db "masm Fibonacci: fib(0..21) x100 sum=%lld  [%lld ns]", 0Ah, 0
		$ns <- rax;
		}
		long slMs = Environment.sys.nowMillis() - slT0
		ns = slMs * 1000000L
		Console.println("========== Fibonacci (ASM) (end) [" + slMs.toString() + " ms SL] ==========")
		ret ns
	}

	# 4. SimdAVX2（ASM 专列）：vpaddd 4 车道向量累加 5e6 次
	# xmm0 四 int32 车道累加常量向量 (1,2,3,4)——校验和 = 5e6×10 = 50000000；
	# 单条 vpaddd 一拍做 4 个 32 位加法（对照 C++ 编译器自动向量化）。
	static long simdAVX2()
	{
		Console.println("========== SimdAVX2 (ASM) (start) ==========")
		long ns = 0L
		long slT0 = Environment.sys.nowMillis()
		@masm_x64()
		{
		EXTERN QueryPerformanceCounter:PROC
		EXTERN QueryPerformanceFrequency:PROC
		EXTERN printf:PROC
		push rbx
		push rsi
		push r12
		push rbp
		lea rcx, S_qf
		sub rsp, 40
		call QueryPerformanceFrequency
		add rsp, 40
		mov rbx, [S_qf]
		lea rcx, S_t0
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		xorps xmm0, xmm0
		mov r12, 5000000
		S_loop:
		vpaddd xmm0, xmm0, xmmword ptr [S_pat]
		dec r12
		jnz S_loop
		lea rcx, S_t1
		sub rsp, 40
		call QueryPerformanceCounter
		add rsp, 40
		vmovdqu xmmword ptr [S_out], xmm0
		mov eax, [S_out]
		add eax, [S_out+4]
		add eax, [S_out+8]
		add eax, [S_out+12]
		mov [S_check], rax
		mov rax, [S_t1]
		sub rax, [S_t0]
		mov r8, 1000000000
		imul rax, r8
		mov r8, rbx
		cqo
		idiv r8
		mov [S_ns], rax
		lea rcx, S_fmt
		mov rdx, [S_check]
		mov r8, [S_ns]
		xor eax, eax
		sub rsp, 40
		call printf
		add rsp, 40
		mov rax, [S_ns]
		pop rbp
		pop r12
		pop rsi
		pop rbx
		ret
		.data
		align 16
		S_pat dd 1, 2, 3, 4
		S_out dd 4 dup(0)
		align 8
		S_qf dq 0
		S_t0 dq 0
		S_t1 dq 0
		S_check dq 0
		S_ns dq 0
		S_fmt db "masm SimdAVX2: vpaddd 5e6 checksum=%lld  [%lld ns]", 0Ah, 0
		$ns <- rax;
		}
		long slMs = Environment.sys.nowMillis() - slT0
		ns = slMs * 1000000L
		Console.println("========== SimdAVX2 (ASM) (end) [" + slMs.toString() + " ms SL] ==========")
		ret ns
	}
}
