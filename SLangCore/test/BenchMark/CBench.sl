import Std

# ============================================================================
# CBench — C 惯用法基准（@cplus_clang(){} 内联块，cplus_clang 插件原生编译）
#
# 14 项与 SL/CSharp/Java/JS 共享基准逐项同算法/同参数（对齐 CsExtra/
# SlBenchLib.cs，校验和可跨语言对拍），外加 ListWalk 一项 C 专列。
# 惯用法：malloc/free、裸指针游走、行指针矩阵、函数指针、SLCPP_EXPORT
# 递归函数（fib/nqueens）、显式栈 DFS、手写 char* 拼接、sprintf。
#
# 计时：块内 QueryPerformanceCounter 纳秒（C 版 Win32 惯用计时），核心
# 算法段耗时经出通道 $ns 回传 SL 侧 recordC——C 原生太快（亚毫秒），
# SL 侧整块毫秒计时全是 0/1 统计不上，ns 出通道是精确口径的唯一路径。
# RegExpBench 例外：std::regex 秒级耗时超 int32 出通道上限，回传 us
#（SL 侧 ×1000 存 ns）。
# 块内代码约束：`<-` 序列禁用（通道标记语法）；#include 只能在块顶；
# 块内不用 # 行注释；块内字符串禁字面 # 字符（用 \x23）。
# ============================================================================

CBench
{
	# 最小探针块：无 QPC/无 windows.h/无类型标记出通道——分离坏点成分
	# （已定位：出通道 Long 类型标记是坏点，Front MapChannelOutKind 未支持
	# Long 形态；修复 = 出通道一律无标记，见各块 $ns <-）
	static long probeBlock()
	{
		Console.println("========== probeBlock (C) (start) ==========")
		long v = 0L
		@cplus_clang()
		{
			#include <cstdio>
			long long x = 123;
			printf( "probe block printf %lld\n", x );
			$v <- x;
		}
		Console.println("========== probeBlock (C) (end) ==========")
		ret v
	}

	static fun()
	{
		long ns = CBench.fibonacci()
		BenchCollector.recordC("Fibonacci", "fib(0..21) 递归求和（块内 ns）", ns)

		ns = CBench.eqBench()
		BenchCollector.recordC("EqBench", "i32/i64/f64/bool 4 子项（块内 ns）", ns)

		ns = CBench.loopBench()
		BenchCollector.recordC("Loop", "指针游走求和 x3000/while 5e6/step 1e6 3 子项（块内 ns）", ns)

		ns = CBench.levenshtein()
		BenchCollector.recordC("Levenshtein", "滚动缓冲 DP x5000（块内 ns）", ns)

		ns = CBench.dataTypes()
		BenchCollector.recordC("DataTypes", "Int32/Int64/Num/混合/bool mod 5 子项（块内 ns）", ns)

		ns = CBench.stringBench()
		BenchCollector.recordC("StringBench", "手写 char* 拼接/sprintf/指针比较 4 子项（块内 ns）", ns)

		long us = CBench.regExpBench()
		BenchCollector.recordC("RegExpBench", "std::regex 8 子项（块内 us，超 int32 出通道上限）", us * 1000L)
		ns = CBench.nQueens()
		BenchCollector.recordC("NQueens", "n=11 单轮 + n=9 x10（块内 ns）", ns)

		ns = CBench.sieve()
		BenchCollector.recordC("Sieve", "malloc 筛 1e6 单轮 + 5e5 x5（块内 ns）", ns)

		ns = CBench.quickSort()
		BenchCollector.recordC("QuickSort", "qsort 3e4 x5（块内 ns）", ns)

		ns = CBench.matrixMul()
		BenchCollector.recordC("MatrixMul", "行指针矩阵乘 100x100 x3（块内 ns）", ns)

		ns = CBench.binaryTree()
		BenchCollector.recordC("BinaryTree", "malloc 池树显式栈 DFS depth12 x10 + depth16 x2（块内 ns）", ns)

		ns = CBench.mandelbrot()
		BenchCollector.recordC("Mandelbrot", "240x180 x3（块内 ns）", ns)

		ns = CBench.listWalk()
		BenchCollector.recordC("ListWalk", "malloc 链表 build+指针遍历 1e5 x10（C 专列，块内 ns）", ns)
	}

	# 1. Fibonacci：SLCPP_EXPORT 递归 cb_fib + QPC 计时求和（sum = 17711）
	static long fibonacci()
	{
		Console.println("========== Fibonacci (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <windows.h>
			setvbuf( stdout, NULL, _IONBF, 0 );
			SLCPP_EXPORT int64_t cb_fib( int64_t n )
			{
				if ( n <= 1 ) { return n; }
				return cb_fib( n - 1 ) + cb_fib( n - 2 );
			}
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long sum = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 22; i++ )
			{
				sum += cb_fib( i );
			}
			QueryPerformanceCounter( &t1 );
			long long elapsed = ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "fib(0..21) sum = %lld  [%lld ns]\n", sum, elapsed );
			$ns <- elapsed;
		}
		Console.println("========== Fibonacci (C) (end) ==========")
		ret ns
	}

	# 2. EqBench：四种类型相等比较循环（i32/i64/f64/bool，对齐 CSharp EqBench）
	static long eqBench()
	{
		Console.println("========== EqBench (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <windows.h>
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			QueryPerformanceCounter( &t0 );
			int k = 0;
			int s = 0;
			while ( k != 2000000 ) { s += k; k++; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "i32 != 2e6 = %d  [%lld ns]\n", s, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			long long k64 = 0;
			long long s64 = 0;
			QueryPerformanceCounter( &t0 );
			while ( k64 != 2000000LL ) { s64 += k64; k64++; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "i64 != 2e6 = %lld  [%lld ns]\n", s64, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			double kd = 0.0;
			double sd = 0.0;
			QueryPerformanceCounter( &t0 );
			while ( kd != 2000000.0 ) { sd += kd; kd += 1.0; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "f64 != 2e6 = %f  [%lld ns]\n", sd, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			int cnt = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 1000000; i++ )
			{
				if ( 1 ) { cnt++; }
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "bool == 1e6 = %d  [%lld ns]\n", cnt, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			$ns <- acc;
		}
		Console.println("========== EqBench (C) (end) ==========")
		ret ns
	}

	# 3. Loop：malloc 数组指针游走求和 x3000 / while 5e6 / step 1e6 三段
	static long loopBench()
	{
		Console.println("========== Loop (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			int n = 1000;
			int* arr = (int*)malloc( n * sizeof( int ) );
			for ( int i = 0; i < n; i++ ) { arr[i] = i * i; }
			long long acc = 0;
			long long total = 0;
			QueryPerformanceCounter( &t0 );
			for ( int j = 0; j < 3000; j++ )
			{
				long long s = 0;
				for ( int* p = arr, *end = arr + n; p != end; ++p ) { s += *p; }
				total += s;
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "pointer walk sum x3000 = %lld  [%lld ns]\n", total, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			long long wsum = 0;
			int k = 0;
			QueryPerformanceCounter( &t0 );
			while ( k < 5000000 ) { wsum += k; k++; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "while sum 5e6 = %lld  [%lld ns]\n", wsum, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			long long stepSum = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 1000000; i += 7 ) { stepSum += i; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "for step +7 1e6 = %lld  [%lld ns]\n", stepSum, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			free( arr );
			$ns <- acc;
		}
		Console.println("========== Loop (C) (end) ==========")
		ret ns
	}

	# 4. Levenshtein：滚动两行缓冲 DP（malloc 一次），先单次再 x5000
	static long levenshtein()
	{
		Console.println("========== Levenshtein (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			int64_t a[6] = { 10, 20, 30, 40, 50, 60 };
			int64_t b[7] = { 10, 25, 30, 35, 40, 50, 65 };
			int m = 6;
			int n = 7;
			int* prev = (int*)malloc( (size_t)( n + 1 ) * sizeof( int ) );
			int* curr = (int*)malloc( (size_t)( n + 1 ) * sizeof( int ) );
			for ( int j = 0; j <= n; j++ ) { prev[j] = j; }
			for ( int i = 1; i <= m; i++ )
			{
				curr[0] = i;
				for ( int j = 1; j <= n; j++ )
				{
					int cost = a[i - 1] == b[j - 1] ? 0 : 1;
					int del = prev[j] + 1;
					int ins = curr[j - 1] + 1;
					int sub = prev[j - 1] + cost;
					curr[j] = del < ins && del < sub ? del : ( ins < sub ? ins : sub );
				}
				int* tmp = prev;
				prev = curr;
				curr = tmp;
			}
			printf( "levenshtein(a,b) = %d\n", prev[n] );
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long total = 0;
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 5000; r++ )
			{
				for ( int j = 0; j <= n; j++ ) { prev[j] = j; }
				for ( int i = 1; i <= m; i++ )
				{
					curr[0] = i;
					for ( int j = 1; j <= n; j++ )
					{
						int cost = a[i - 1] == b[j - 1] ? 0 : 1;
						int del = prev[j] + 1;
						int ins = curr[j - 1] + 1;
						int sub = prev[j - 1] + cost;
						curr[j] = del < ins && del < sub ? del : ( ins < sub ? ins : sub );
					}
					int* tmp = prev;
					prev = curr;
					curr = tmp;
				}
				total += prev[n];
			}
			QueryPerformanceCounter( &t1 );
			printf( "levenshtein x5000 = %lld  [%lld ns]\n", total, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			free( prev );
			free( curr );
			$ns <- ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
		}
		Console.println("========== Levenshtein (C) (end) ==========")
		ret ns
	}

	# 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段（对齐 CSharp）
	static long dataTypes()
	{
		Console.println("========== DataTypes (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <windows.h>
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			int s32 = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 2000000; i++ ) { s32 += i; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "Int32 sum 2e6 = %d  [%lld ns]\n", s32, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			long long s64 = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 2000000; i++ ) { s64 += i; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "Int64 sum 2e6 = %lld  [%lld ns]\n", s64, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			double sf = 0.0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 2000000; i++ ) { sf += i * 1.5; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "Num sum 2e6 = %f  [%lld ns]\n", sf, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			double mix = 0.0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 1000000; i++ ) { mix = mix + i / 3.0 + i % 7; }
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "Mixed ops 1e6 = %f  [%lld ns]\n", mix, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			int count = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 1000000; i++ )
			{
				if ( i % 3 == 0 && i % 5 == 0 ) { count++; }
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "bool mod 1e6 = %d  [%lld ns]\n", count, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			$ns <- acc;
		}
		Console.println("========== DataTypes (C) (end) ==========")
		ret ns
	}

	# 6. StringBench：手写 char* realloc 拼接 / sprintf 插值与格式化 / 指针比较
	static long stringBench()
	{
		Console.println("========== StringBench (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			size_t cap = 16;
			char* s = (char*)malloc( cap );
			size_t len = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 10000; i++ )
			{
				if ( len + 3 > cap ) { cap = cap * 2; s = (char*)realloc( s, cap ); }
				s[len] = 'a';
				s[len + 1] = 'b';
				len = len + 2;
				s[len] = '\0';
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "concat 1e4 (manual realloc) = %zu chars  [%lld ns]\n", len, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			char* t = (char*)malloc( 64 );
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 10000; i++ )
			{
				sprintf( t, "v=%d s=%d", i, i * 2 );
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "interp 1e4 (sprintf) = %s  [%lld ns]\n", t, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			char* u = (char*)malloc( 64 );
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 10000; i++ )
			{
				sprintf( u, "%d-%d", i, i + 1 );
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "format 1e4 (sprintf) = %s  [%lld ns]\n", u, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			int c = 0;
			QueryPerformanceCounter( &t0 );
			for ( int i = 0; i < 100000; i++ )
			{
				const char* p = s;
				const char* q = t;
				while ( *p != '\0' && *p == *q ) { ++p; ++q; }
				if ( *p == '\0' && *q == '\0' ) { c++; }
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "compare 1e5  count = %d  [%lld ns]\n", c, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			free( s );
			free( t );
			free( u );
			$ns <- acc;
		}
		Console.println("========== StringBench (C) (end) ==========")
		ret ns
	}

	# 7. RegExpBench：std::regex 8 子项（MSVC 无 POSIX regex.h，借 C++ 库；
	#    windows.h 的 min/max 宏与 <regex> 冲突，本块计时借 steady_clock）。
	#    std::regex 秒级耗时超 int32 出通道上限 → 回传 us。
	static long regExpBench()
	{
		Console.println("========== RegExpBench (C) (start) ==========")
		long us = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <string>
			#include <regex>
			#include <chrono>
			using namespace std;
			string chunk = "abc123 def456 ghi789 ";
			string text = "";
			for ( int i = 0; i < 4000; i++ )
			{
				text = text + chunk;
			}
			printf( "text bytes = %zu\n", text.size() );
			long long acc = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 2000; i++ )
			{
				std::regex re( "([a-z]+)([0-9]+)" );
			}
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "compile x2000  [%lld ns]\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			std::regex re1( "def456" );
			std::smatch m1;
			string hit = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 500; i++ )
			{
				if ( std::regex_search( text, m1, re1 ) ) { hit = m1.str(); }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "search hit x500  [%lld ns]  value=%s\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), hit.c_str() );
			std::regex re2( "zzz999" );
			bool miss = true;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 20; i++ )
			{
				miss = !std::regex_search( text, re2 );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "search miss x20  [%lld ns]  miss=%s\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), miss ? "true" : "false" );
			std::regex re3( "[a-z]+" );
			int words = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 5; i++ )
			{
				words = (int)std::distance( std::sregex_iterator( text.begin(), text.end(), re3 ), std::sregex_iterator() );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "matchAll x5  [%lld ns]  count=%d\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), words );
			std::regex re4( "[0-9]+" );
			string rep = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 5; i++ )
			{
				rep = std::regex_replace( text, re4, "\x23" );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "replace x5  [%lld ns]  len=%zu\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), rep.size() );
			std::regex re5( "([a-z]+)([0-9]+)" );
			string g1 = "";
			string g2 = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 200; i++ )
			{
				std::smatch m5;
				if ( std::regex_search( text, m5, re5 ) ) { g1 = m5[1].str(); g2 = m5[2].str(); }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "group search x200  [%lld ns]  g1=%s g2=%s\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), g1.c_str(), g2.c_str() );
			string chunk2 = "abc abc def def ";
			string text2 = "";
			for ( int i = 0; i < 2000; i++ )
			{
				text2 = text2 + chunk2;
			}
			std::regex re6( "(\\w+) \\1" );
			int pairs = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 10; i++ )
			{
				pairs = (int)std::distance( std::sregex_iterator( text2.begin(), text2.end(), re6 ), std::sregex_iterator() );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "backref matchAll x10  [%lld ns]  count=%d\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), pairs );
			string chunk3 = "中文测试123 ";
			string text3 = "";
			for ( int i = 0; i < 2000; i++ )
			{
				text3 = text3 + chunk3;
			}
			std::regex re7( "测试[0-9]+" );
			string zh = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 100; i++ )
			{
				std::smatch m7;
				if ( std::regex_search( text3, m7, re7 ) ) { zh = m7.str(); }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "utf8 search x100  [%lld ns]  value=%s\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), zh.c_str() );
			$us <- acc / 1000;
		}
		Console.println("========== RegExpBench (C) (end) ==========")
		ret us
	}

	# 8. NQueens：SLCPP_EXPORT 递归回溯 cb_solve/cb_place（n=11 单轮 + n=9 x10）
	static long nQueens()
	{
		Console.println("========== NQueens (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			SLCPP_EXPORT int64_t cb_place( int64_t* queens, int64_t row, int64_t n )
			{
				if ( row == n ) { return 1; }
				int64_t count = 0;
				for ( int64_t col = 0; col < n; col++ )
				{
					int ok = 1;
					for ( int64_t i = 0; i < row; i++ )
					{
						if ( queens[i] == col || queens[i] - i == col - row || queens[i] + i == col + row )
						{
							ok = 0;
							break;
						}
					}
					if ( ok == 1 )
					{
						queens[row] = col;
						count += cb_place( queens, row + 1, n );
					}
				}
				return count;
			}
			SLCPP_EXPORT int64_t cb_solve( int64_t n )
			{
				int64_t* queens = (int64_t*)malloc( (size_t)n * sizeof( int64_t ) );
				int64_t r = cb_place( queens, 0, n );
				free( queens );
				return r;
			}
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			QueryPerformanceCounter( &t0 );
			int64_t solutions = cb_solve( 11 );
			QueryPerformanceCounter( &t1 );
			long long acc = ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "nqueens(11) solutions = %lld  [%lld ns]\n", solutions, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			int64_t total = 0;
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 10; r++ )
			{
				total += cb_solve( 9 );
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "nqueens(9) x10 = %lld  [%lld ns]\n", total, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			$ns <- acc;
		}
		Console.println("========== NQueens (C) (end) ==========")
		ret ns
	}

	# 9. Sieve：malloc 素数筛（1e6 单轮 78498 + 5e5 x5 207690）
	static long sieve()
	{
		Console.println("========== Sieve (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			int lim = 1000000;
			int* comp = (int*)malloc( (size_t)( lim + 1 ) * sizeof( int ) );
			QueryPerformanceCounter( &t0 );
			int count = 0;
			for ( int i = 0; i <= lim; i++ ) { comp[i] = 0; }
			for ( int i = 2; i <= lim; i++ )
			{
				if ( comp[i] == 0 )
				{
					count++;
					if ( i <= lim / i )
					{
						int j = i * i;
						while ( j <= lim ) { comp[j] = 1; j += i; }
					}
				}
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "sieve 1e6 primes = %d  [%lld ns]\n", count, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			int total = 0;
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 5; r++ )
			{
				for ( int i = 0; i <= 500000; i++ ) { comp[i] = 0; }
				for ( int i = 2; i <= 500000; i++ )
				{
					if ( comp[i] == 0 )
					{
						total++;
						if ( i <= 500000 / i )
						{
							int j = i * i;
							while ( j <= 500000 ) { comp[j] = 1; j += i; }
						}
					}
				}
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "sieve 5e5 x5 = %d  [%lld ns]\n", total, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			free( comp );
			$ns <- acc;
		}
		Console.println("========== Sieve (C) (end) ==========")
		ret ns
	}

	# 10. QuickSort：qsort + 比较器函数指针（3e4 元素 x5 轮，数据生成不计时）
	static long quickSort()
	{
		Console.println("========== QuickSort (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			int n = 30000;
			long long* arr = (long long*)malloc( (size_t)n * sizeof( long long ) );
			int ( *cmp )( const void*, const void* ) =
			[]( const void* a, const void* b ) -> int
			{
				long long x = *(const long long*)a;
				long long y = *(const long long*)b;
				return ( x > y ) - ( x < y );
			};
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			long long checksum = 0;
			for ( int r = 0; r < 5; r++ )
			{
				long long seed = 42 + r;
				for ( int i = 0; i < n; i++ )
				{
					seed = ( seed * 16807 ) % 2147483647;
					arr[i] = seed;
				}
				QueryPerformanceCounter( &t0 );
				qsort( arr, (size_t)n, sizeof( long long ), cmp );
				QueryPerformanceCounter( &t1 );
				acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
				for ( int i = 0; i < n; i++ )
				{
					checksum += arr[i];
					if ( i > 0 && arr[i - 1] > arr[i] ) { printf( "SORTED CHECK FAILED at %d\n", i ); }
				}
			}
			printf( "qsort 3e4 x5  [%lld ns]  checksum = %lld\n", acc, checksum );
			free( arr );
			$ns <- acc;
		}
		Console.println("========== QuickSort (C) (end) ==========")
		ret ns
	}

	# 11. MatrixMul：int** 行指针矩阵乘（每轮清零，checksum 与他语言对齐）
	static long matrixMul()
	{
		Console.println("========== MatrixMul (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstring>
			#include <cstdint>
			#include <windows.h>
			int n = 100;
			int** a = (int**)malloc( (size_t)n * sizeof( int* ) );
			int** b = (int**)malloc( (size_t)n * sizeof( int* ) );
			int** c = (int**)malloc( (size_t)n * sizeof( int* ) );
			for ( int i = 0; i < n; i++ )
			{
				a[i] = (int*)malloc( (size_t)n * sizeof( int ) );
				b[i] = (int*)malloc( (size_t)n * sizeof( int ) );
				c[i] = (int*)malloc( (size_t)n * sizeof( int ) );
			}
			for ( int i = 0; i < n; i++ )
			{
				for ( int j = 0; j < n; j++ )
				{
					a[i][j] = ( i + j ) % 100;
					b[i][j] = ( i * 7 + j * 3 ) % 100;
				}
			}
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 3; r++ )
			{
				for ( int i = 0; i < n; i++ ) { memset( c[i], 0, (size_t)n * sizeof( int ) ); }
				for ( int i = 0; i < n; i++ )
				{
					int* ci = c[i];
					int* ai = a[i];
					for ( int k = 0; k < n; k++ )
					{
						int av = ai[k];
						int* bk = b[k];
						for ( int j = 0; j < n; j++ ) { ci[j] += av * bk[j]; }
					}
				}
			}
			QueryPerformanceCounter( &t1 );
			long long checksum = 0;
			for ( int i = 0; i < n; i++ )
			{
				for ( int j = 0; j < n; j++ ) { checksum += c[i][j]; }
			}
			printf( "matmul 100x100 x3  [%lld ns]  checksum = %lld\n", ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart, checksum );
			for ( int i = 0; i < n; i++ ) { free( a[i] ); free( b[i] ); free( c[i] ); }
			free( a );
			free( b );
			free( c );
			$ns <- ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
		}
		Console.println("========== MatrixMul (C) (end) ==========")
		ret ns
	}

	# 12. BinaryTree：malloc 节点池满二叉树（Build 值语义：v*2 / v*2+1）+ 显式栈 DFS
	static long binaryTree()
	{
		Console.println("========== BinaryTree (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			typedef struct TNode { struct TNode* l; struct TNode* r; long long v; } TNode;
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			long long acc = 0;
			QueryPerformanceCounter( &t0 );
			long long total12 = 0;
			for ( int r = 0; r < 10; r++ )
			{
				int depth = 12;
				size_t count = (size_t)( ( 1 << depth ) - 1 );
				TNode* pool = (TNode*)malloc( count * sizeof( TNode ) );
				pool[0].v = r + 1;
				for ( size_t i = 0; 2 * i + 2 < count; i++ )
				{
					pool[2 * i + 1].v = pool[i].v * 2;
					pool[2 * i + 2].v = pool[i].v * 2 + 1;
				}
				for ( size_t i = 0; i < count; i++ )
				{
					pool[i].l = ( 2 * i + 1 < count ) ? &pool[2 * i + 1] : NULL;
					pool[i].r = ( 2 * i + 2 < count ) ? &pool[2 * i + 2] : NULL;
				}
				TNode** stk = (TNode**)malloc( count * sizeof( TNode* ) );
				int sp = 0;
				stk[sp] = &pool[0];
				sp++;
				while ( sp > 0 )
				{
					sp--;
					TNode* nd = stk[sp];
					total12 += nd->v;
					if ( nd->l != NULL ) { stk[sp] = nd->l; sp++; }
					if ( nd->r != NULL ) { stk[sp] = nd->r; sp++; }
				}
				free( stk );
				free( pool );
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "tree depth12 x10 dfs sum = %lld  [%lld ns]\n", total12, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			QueryPerformanceCounter( &t0 );
			long long total16 = 0;
			for ( int r = 0; r < 2; r++ )
			{
				int depth = 16;
				size_t count = (size_t)( ( 1 << depth ) - 1 );
				TNode* pool = (TNode*)malloc( count * sizeof( TNode ) );
				pool[0].v = r + 1;
				for ( size_t i = 0; 2 * i + 2 < count; i++ )
				{
					pool[2 * i + 1].v = pool[i].v * 2;
					pool[2 * i + 2].v = pool[i].v * 2 + 1;
				}
				for ( size_t i = 0; i < count; i++ )
				{
					pool[i].l = ( 2 * i + 1 < count ) ? &pool[2 * i + 1] : NULL;
					pool[i].r = ( 2 * i + 2 < count ) ? &pool[2 * i + 2] : NULL;
				}
				TNode** stk = (TNode**)malloc( count * sizeof( TNode* ) );
				int sp = 0;
				stk[sp] = &pool[0];
				sp++;
				while ( sp > 0 )
				{
					sp--;
					TNode* nd = stk[sp];
					total16 += nd->v;
					if ( nd->l != NULL ) { stk[sp] = nd->l; sp++; }
					if ( nd->r != NULL ) { stk[sp] = nd->r; sp++; }
				}
				free( stk );
				free( pool );
			}
			QueryPerformanceCounter( &t1 );
			acc += ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
			printf( "tree depth16 x2 dfs sum = %lld  [%lld ns]\n", total16, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			$ns <- acc;
		}
		Console.println("========== BinaryTree (C) (end) ==========")
		ret ns
	}

	# 13. Mandelbrot：标准映射（对齐 SlBenchLib Render：x0=px*4/w-2, y0=py*4/h-2）
	static long mandelbrot()
	{
		Console.println("========== Mandelbrot (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <windows.h>
			int w = 240;
			int h = 180;
			int maxIter = 150;
			long long iterSum = 0;
			int inside = 0;
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 3; r++ )
			{
				for ( int py = 0; py < h; py++ )
				{
					double y0 = py * 4.0 / h - 2.0;
					for ( int px = 0; px < w; px++ )
					{
						double x0 = px * 4.0 / w - 2.0;
						double x = 0.0;
						double y = 0.0;
						int iter = 0;
						while ( iter < maxIter && x * x + y * y <= 4.0 )
						{
							double xtemp = x * x - y * y + x0;
							y = 2.0 * x * y + y0;
							x = xtemp;
							iter++;
						}
						iterSum += iter;
						if ( iter == maxIter ) { inside++; }
					}
				}
			}
			QueryPerformanceCounter( &t1 );
			printf( "mandelbrot 240x180 x3  [%lld ns]  iterSum = %lld  inside = %d\n", ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart, iterSum, inside );
			$ns <- ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
		}
		Console.println("========== Mandelbrot (C) (end) ==========")
		ret ns
	}

	# 14. ListWalk：malloc 节点单链表头插 build + 指针遍历求和（C 专列）
	static long listWalk()
	{
		Console.println("========== ListWalk (C) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdlib>
			#include <cstdint>
			#include <windows.h>
			typedef struct LNode { struct LNode* next; long long v; } LNode;
			long long total = 0;
			LARGE_INTEGER freq;
			LARGE_INTEGER t0;
			LARGE_INTEGER t1;
			QueryPerformanceFrequency( &freq );
			QueryPerformanceCounter( &t0 );
			for ( int r = 0; r < 10; r++ )
			{
				LNode* head = NULL;
				long long seed = 42 + r;
				for ( int i = 0; i < 100000; i++ )
				{
					seed = ( seed * 16807 ) % 2147483647;
					LNode* node = (LNode*)malloc( sizeof( LNode ) );
					node->v = seed;
					node->next = head;
					head = node;
				}
				LNode* p = head;
				while ( p != NULL ) { total += p->v; p = p->next; }
				while ( head != NULL ) { LNode* nx = head->next; free( head ); head = nx; }
			}
			QueryPerformanceCounter( &t1 );
			printf( "linked list 1e5 x10 walk sum = %lld  [%lld ns]\n", total, ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart );
			$ns <- ( t1.QuadPart - t0.QuadPart ) * 1000000000LL / freq.QuadPart;
		}
		Console.println("========== ListWalk (C) (end) ==========")
		ret ns
	}
}
