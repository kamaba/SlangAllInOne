import Std

# ============================================================================
# CppBench — C++ 惯用法基准（@cplus_clang(){} 内联块，cplus_clang 插件原生编译）
#
# 14 项与 SL/CSharp/Java/JS 共享基准逐项同算法/同参数（对齐 CsExtra/
# SlBenchLib.cs，校验和可跨语言对拍），外加 ListWalk 一项 C++ 专列。
# 惯用法：vector 迭代器、对象与成员方法、std::sort、std::string、
# vector<vector>、unique_ptr 树、泛型递归 lambda（auto&& self）。
#
# 计时：块内 std::chrono::steady_clock 纳秒，核心算法段耗时经出通道
# $ns 回传 SL 侧 recordCpp——C++ 原生太快（亚毫秒），SL 侧整块毫秒计时
# 全是 0/1 统计不上，ns 出通道是精确口径的唯一路径。RegExpBench 例外：
# std::regex 秒级耗时超 int32 出通道上限，回传 us（SL 侧 ×1000 存 ns）。
# 块内代码约束：`<-` 序列禁用；#include 只能在块顶；块内不用 # 行注释；
# 块内字符串禁字面 # 字符（用 \x23）。
# ============================================================================

CppBench
{
	static fun()
	{
		long ns = CppBench.fibonacci()
		BenchCollector.recordCpp("Fibonacci", "fib(0..21) 递归求和（块内 ns）", ns)

		ns = CppBench.eqBench()
		BenchCollector.recordCpp("EqBench", "i32/i64/f64/bool 4 子项（块内 ns）", ns)

		ns = CppBench.loopBench()
		BenchCollector.recordCpp("Loop", "迭代器求和 x3000/while 5e6/step 1e6 3 子项（块内 ns）", ns)

		ns = CppBench.levenshtein()
		BenchCollector.recordCpp("Levenshtein", "vector 滚动 DP x5000（块内 ns）", ns)

		ns = CppBench.dataTypes()
		BenchCollector.recordCpp("DataTypes", "Int32/Int64/Num/混合/bool mod 5 子项（块内 ns）", ns)

		ns = CppBench.stringBench()
		BenchCollector.recordCpp("StringBench", "std::string 拼接/to_string/stringstream/比较 4 子项（块内 ns）", ns)

		long us = CppBench.regExpBench()
		BenchCollector.recordCpp("RegExpBench", "std::regex 8 子项（块内 us，超 int32 出通道上限）", us * 1000L)

		ns = CppBench.nQueens()
		BenchCollector.recordCpp("NQueens", "n=11 单轮 + n=9 x10（块内 ns）", ns)

		ns = CppBench.sieve()
		BenchCollector.recordCpp("Sieve", "vector 筛 1e6 单轮 + 5e5 x5（块内 ns）", ns)

		ns = CppBench.quickSort()
		BenchCollector.recordCpp("QuickSort", "std::sort 3e4 x5（块内 ns）", ns)

		ns = CppBench.matrixMul()
		BenchCollector.recordCpp("MatrixMul", "vector<vector> 矩阵乘 100x100 x3（块内 ns）", ns)

		ns = CppBench.binaryTree()
		BenchCollector.recordCpp("BinaryTree", "unique_ptr 树递归 lambda depth12 x10 + depth16 x2（块内 ns）", ns)

		ns = CppBench.mandelbrot()
		BenchCollector.recordCpp("Mandelbrot", "240x180 x3（块内 ns）", ns)

		ns = CppBench.listWalk()
		BenchCollector.recordCpp("ListWalk", "vector 对象成员方法遍历 1e5 x10（C++ 专列，块内 ns）", ns)
	}

	# 1. Fibonacci：泛型递归 lambda（auto&& self）求和（sum = 17711）
	static long fibonacci()
	{
		Console.println("========== Fibonacci (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <chrono>
			auto fib = []( int64_t n, auto&& self ) -> int64_t
			{
				if ( n <= 1 ) { return n; }
				return self( n - 1, self ) + self( n - 2, self );
			};
			long long sum = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 22; i++ )
			{
				sum += fib( i, fib );
			}
			auto t1 = std::chrono::steady_clock::now();
			long long elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "fib(0..21) sum = %lld  [%lld ns]\n", sum, elapsed );
			$ns <- elapsed;
		}
		Console.println("========== Fibonacci (C++) (end) ==========")
		ret ns
	}

	# 2. EqBench：四种类型相等比较循环（对齐 CSharp EqBench）
	static long eqBench()
	{
		Console.println("========== EqBench (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <chrono>
			long long acc = 0;
			auto t0 = std::chrono::steady_clock::now();
			int k = 0;
			int s = 0;
			while ( k != 2000000 ) { s += k; k++; }
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "i32 != 2e6 = %d  [%lld ns]\n", s, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			long long k64 = 0;
			long long s64 = 0;
			t0 = std::chrono::steady_clock::now();
			while ( k64 != 2000000LL ) { s64 += k64; k64++; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "i64 != 2e6 = %lld  [%lld ns]\n", s64, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			double kd = 0.0;
			double sd = 0.0;
			t0 = std::chrono::steady_clock::now();
			while ( kd != 2000000.0 ) { sd += kd; kd += 1.0; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "f64 != 2e6 = %f  [%lld ns]\n", sd, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			int cnt = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 1000000; i++ )
			{
				if ( true ) { cnt++; }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "bool == 1e6 = %d  [%lld ns]\n", cnt, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== EqBench (C++) (end) ==========")
		ret ns
	}

	# 3. Loop：vector 迭代器求和 x3000 / while 5e6 / step 1e6 三段
	static long loopBench()
	{
		Console.println("========== Loop (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <cstdint>
			#include <chrono>
			int n = 1000;
			std::vector<int> arr( (size_t)n );
			for ( int i = 0; i < n; i++ ) { arr[(size_t)i] = i * i; }
			long long acc = 0;
			long long total = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int j = 0; j < 3000; j++ )
			{
				long long s = 0;
				for ( auto it = arr.begin(); it != arr.end(); ++it ) { s += *it; }
				total += s;
			}
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "iterator sum x3000 = %lld  [%lld ns]\n", total, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			long long wsum = 0;
			int k = 0;
			t0 = std::chrono::steady_clock::now();
			while ( k < 5000000 ) { wsum += k; k++; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "while sum 5e6 = %lld  [%lld ns]\n", wsum, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			long long stepSum = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 1000000; i += 7 ) { stepSum += i; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "for step +7 1e6 = %lld  [%lld ns]\n", stepSum, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== Loop (C++) (end) ==========")
		ret ns
	}

	# 4. Levenshtein：vector 两种行滚动 DP，先单次再 x5000
	static long levenshtein()
	{
		Console.println("========== Levenshtein (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <cstdint>
			#include <chrono>
			std::vector<int64_t> a = { 10, 20, 30, 40, 50, 60 };
			std::vector<int64_t> b = { 10, 25, 30, 35, 40, 50, 65 };
			int m = 6;
			int n = 7;
			std::vector<int> prev( (size_t)n + 1 );
			std::vector<int> curr( (size_t)n + 1 );
			for ( int j = 0; j <= n; j++ ) { prev[(size_t)j] = j; }
			for ( int i = 1; i <= m; i++ )
			{
				curr[0] = i;
				for ( int j = 1; j <= n; j++ )
				{
					int cost = a[(size_t)i - 1] == b[(size_t)j - 1] ? 0 : 1;
					int del = prev[(size_t)j] + 1;
					int ins = curr[(size_t)j - 1] + 1;
					int sub = prev[(size_t)j - 1] + cost;
					curr[(size_t)j] = del < ins && del < sub ? del : ( ins < sub ? ins : sub );
				}
				std::swap( prev, curr );
			}
			printf( "levenshtein(a,b) = %d\n", prev[(size_t)n] );
			long long total = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int r = 0; r < 5000; r++ )
			{
				for ( int j = 0; j <= n; j++ ) { prev[(size_t)j] = j; }
				for ( int i = 1; i <= m; i++ )
				{
					curr[0] = i;
					for ( int j = 1; j <= n; j++ )
					{
						int cost = a[(size_t)i - 1] == b[(size_t)j - 1] ? 0 : 1;
						int del = prev[(size_t)j] + 1;
						int ins = curr[(size_t)j - 1] + 1;
						int sub = prev[(size_t)j - 1] + cost;
						curr[(size_t)j] = del < ins && del < sub ? del : ( ins < sub ? ins : sub );
					}
					std::swap( prev, curr );
				}
				total += prev[(size_t)n];
			}
			auto t1 = std::chrono::steady_clock::now();
			printf( "levenshtein x5000 = %lld  [%lld ns]\n", total, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
		}
		Console.println("========== Levenshtein (C++) (end) ==========")
		ret ns
	}

	# 5. DataTypes：Int32/Int64/Num/混合运算/bool 取模五段（对齐 CSharp）
	static long dataTypes()
	{
		Console.println("========== DataTypes (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <chrono>
			long long acc = 0;
			int s32 = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 2000000; i++ ) { s32 += i; }
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "Int32 sum 2e6 = %d  [%lld ns]\n", s32, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			long long s64 = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 2000000; i++ ) { s64 += i; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "Int64 sum 2e6 = %lld  [%lld ns]\n", s64, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			double sf = 0.0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 2000000; i++ ) { sf += i * 1.5; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "Num sum 2e6 = %f  [%lld ns]\n", sf, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			double mix = 0.0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 1000000; i++ ) { mix = mix + i / 3.0 + i % 7; }
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "Mixed ops 1e6 = %f  [%lld ns]\n", mix, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			int count = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 1000000; i++ )
			{
				if ( i % 3 == 0 && i % 5 == 0 ) { count++; }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "bool mod 1e6 = %d  [%lld ns]\n", count, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== DataTypes (C++) (end) ==========")
		ret ns
	}

	# 6. StringBench：std::string 拼接 / to_string 插值 / stringstream 格式化 / operator==
	static long stringBench()
	{
		Console.println("========== StringBench (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <string>
			#include <sstream>
			#include <chrono>
			long long acc = 0;
			std::string s;
			auto t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 10000; i++ )
			{
				s = s + "ab";
			}
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "concat 1e4 (std::string) = %zu chars  [%lld ns]\n", s.size(), std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			std::string t;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 10000; i++ )
			{
				t = "v=" + std::to_string( i ) + " s=" + std::to_string( i * 2 );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "interp 1e4 (to_string) = %s  [%lld ns]\n", t.c_str(), std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			std::string u;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 10000; i++ )
			{
				std::ostringstream oss;
				oss << i << "-" << ( i + 1 );
				u = oss.str();
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "format 1e4 (stringstream) = %s  [%lld ns]\n", u.c_str(), std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			int c = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 100000; i++ )
			{
				if ( s == t ) { c++; }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "compare 1e5  count = %d  [%lld ns]\n", c, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== StringBench (C++) (end) ==========")
		ret ns
	}

	# 7. RegExpBench：std::regex 8 子项（秒级耗时超 int32 出通道上限 → 回传 us）
	static long regExpBench()
	{
		Console.println("========== RegExpBench (C++) (start) ==========")
		long us = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <string>
			#include <regex>
			#include <chrono>
			std::string chunk = "abc123 def456 ghi789 ";
			std::string text = "";
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
			std::string hit = "";
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
			std::string rep = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 5; i++ )
			{
				rep = std::regex_replace( text, re4, "\x23" );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "replace x5  [%lld ns]  len=%zu\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), rep.size() );
			std::regex re5( "([a-z]+)([0-9]+)" );
			std::string g1 = "";
			std::string g2 = "";
			t0 = std::chrono::steady_clock::now();
			for ( int i = 0; i < 200; i++ )
			{
				std::smatch m5;
				if ( std::regex_search( text, m5, re5 ) ) { g1 = m5[1].str(); g2 = m5[2].str(); }
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "group search x200  [%lld ns]  g1=%s g2=%s\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), g1.c_str(), g2.c_str() );
			std::string chunk2 = "abc abc def def ";
			std::string text2 = "";
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
			std::string chunk3 = "中文测试123 ";
			std::string text3 = "";
			for ( int i = 0; i < 2000; i++ )
			{
				text3 = text3 + chunk3;
			}
			std::regex re7( "测试[0-9]+" );
			std::string zh = "";
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
		Console.println("========== RegExpBench (C++) (end) ==========")
		ret us
	}

	# 8. NQueens：递归 lambda 回溯（n=11 单轮 + n=9 x10）
	static long nQueens()
	{
		Console.println("========== NQueens (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <cstdint>
			#include <chrono>
			auto place = []( std::vector<int64_t>& queens, int64_t row, int64_t n, auto&& self ) -> int64_t
			{
				if ( row == n ) { return 1; }
				int64_t count = 0;
				for ( int64_t col = 0; col < n; col++ )
				{
					int ok = 1;
					for ( int64_t i = 0; i < row; i++ )
					{
						if ( queens[(size_t)i] == col || queens[(size_t)i] - i == col - row || queens[(size_t)i] + i == col + row )
						{
							ok = 0;
							break;
						}
					}
					if ( ok == 1 )
					{
						queens[(size_t)row] = col;
						count += self( queens, row + 1, n, self );
					}
				}
				return count;
			};
			std::vector<int64_t> queens( 16 );
			long long acc = 0;
			auto t0 = std::chrono::steady_clock::now();
			int64_t solutions = place( queens, 0, 11, place );
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "nqueens(11) solutions = %lld  [%lld ns]\n", solutions, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			int64_t total = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int r = 0; r < 10; r++ )
			{
				total += place( queens, 0, 9, place );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "nqueens(9) x10 = %lld  [%lld ns]\n", total, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== NQueens (C++) (end) ==========")
		ret ns
	}

	# 9. Sieve：vector 素数筛（1e6 单轮 78498 + 5e5 x5 207690）
	static long sieve()
	{
		Console.println("========== Sieve (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <algorithm>
			#include <cstdint>
			#include <chrono>
			long long acc = 0;
			int lim = 1000000;
			std::vector<int> comp( (size_t)lim + 1, 0 );
			auto t0 = std::chrono::steady_clock::now();
			int count = 0;
			for ( int i = 2; i <= lim; i++ )
			{
				if ( comp[(size_t)i] == 0 )
				{
					count++;
					if ( i <= lim / i )
					{
						int j = i * i;
						while ( j <= lim ) { comp[(size_t)j] = 1; j += i; }
					}
				}
			}
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "sieve 1e6 primes = %d  [%lld ns]\n", count, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			int total = 0;
			t0 = std::chrono::steady_clock::now();
			for ( int r = 0; r < 5; r++ )
			{
				std::fill( comp.begin(), comp.begin() + 500001, 0 );
				for ( int i = 2; i <= 500000; i++ )
				{
					if ( comp[(size_t)i] == 0 )
					{
						total++;
						if ( i <= 500000 / i )
						{
							int j = i * i;
							while ( j <= 500000 ) { comp[(size_t)j] = 1; j += i; }
						}
					}
				}
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "sieve 5e5 x5 = %d  [%lld ns]\n", total, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== Sieve (C++) (end) ==========")
		ret ns
	}

	# 10. QuickSort：std::vector + std::sort 比较 lambda（3e4 x5，数据生成不计时）
	static long quickSort()
	{
		Console.println("========== QuickSort (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <algorithm>
			#include <cstdint>
			#include <chrono>
			int n = 30000;
			std::vector<long long> arr( (size_t)n );
			auto cmp = []( const long long& x, const long long& y ) { return x < y; };
			long long acc = 0;
			long long checksum = 0;
			for ( int r = 0; r < 5; r++ )
			{
				long long seed = 42 + r;
				for ( int i = 0; i < n; i++ )
				{
					seed = ( seed * 16807 ) % 2147483647;
					arr[(size_t)i] = seed;
				}
				auto t0 = std::chrono::steady_clock::now();
				std::sort( arr.begin(), arr.end(), cmp );
				auto t1 = std::chrono::steady_clock::now();
				acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
				for ( int i = 0; i < n; i++ )
				{
					checksum += arr[(size_t)i];
					if ( i > 0 && arr[(size_t)i - 1] > arr[(size_t)i] ) { printf( "SORTED CHECK FAILED at %d\n", i ); }
				}
			}
			printf( "std::sort 3e4 x5  [%lld ns]  checksum = %lld\n", acc, checksum );
			$ns <- acc;
		}
		Console.println("========== QuickSort (C++) (end) ==========")
		ret ns
	}

	# 11. MatrixMul：vector<vector<int>> 矩阵乘（每轮清零，checksum 与他语言对齐）
	static long matrixMul()
	{
		Console.println("========== MatrixMul (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <algorithm>
			#include <cstdint>
			#include <chrono>
			int n = 100;
			std::vector<std::vector<int>> a( (size_t)n, std::vector<int>( (size_t)n ) );
			std::vector<std::vector<int>> b( (size_t)n, std::vector<int>( (size_t)n ) );
			std::vector<std::vector<int>> c( (size_t)n, std::vector<int>( (size_t)n ) );
			for ( int i = 0; i < n; i++ )
			{
				for ( int j = 0; j < n; j++ )
				{
					a[(size_t)i][(size_t)j] = ( i + j ) % 100;
					b[(size_t)i][(size_t)j] = ( i * 7 + j * 3 ) % 100;
				}
			}
			auto t0 = std::chrono::steady_clock::now();
			for ( int r = 0; r < 3; r++ )
			{
				for ( int i = 0; i < n; i++ ) { std::fill( c[(size_t)i].begin(), c[(size_t)i].end(), 0 ); }
				for ( int i = 0; i < n; i++ )
				{
					std::vector<int>& ci = c[(size_t)i];
					std::vector<int>& ai = a[(size_t)i];
					for ( int k = 0; k < n; k++ )
					{
						int av = ai[(size_t)k];
						std::vector<int>& bk = b[(size_t)k];
						for ( int j = 0; j < n; j++ ) { ci[(size_t)j] += av * bk[(size_t)j]; }
					}
				}
			}
			auto t1 = std::chrono::steady_clock::now();
			long long checksum = 0;
			for ( int i = 0; i < n; i++ )
			{
				for ( int j = 0; j < n; j++ ) { checksum += c[(size_t)i][(size_t)j]; }
			}
			printf( "matmul 100x100 x3  [%lld ns]  checksum = %lld\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), checksum );
			$ns <- std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
		}
		Console.println("========== MatrixMul (C++) (end) ==========")
		ret ns
	}

	# 12. BinaryTree：unique_ptr 树 + 泛型递归 lambda（Build 值语义对齐校验和）
	static long binaryTree()
	{
		Console.println("========== BinaryTree (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <memory>
			#include <cstdint>
			#include <chrono>
			struct ONode
			{
				std::unique_ptr<ONode> l;
				std::unique_ptr<ONode> r;
				long long v;
			};
			auto build = []( int depth, long long v, auto&& self ) -> std::unique_ptr<ONode>
			{
				if ( depth <= 0 ) { return nullptr; }
				auto node = std::make_unique<ONode>();
				node->v = v;
				node->l = self( depth - 1, v * 2, self );
				node->r = self( depth - 1, v * 2 + 1, self );
				return node;
			};
			auto sum = []( const ONode* n, auto&& self ) -> long long
			{
				if ( n == NULL ) { return 0; }
				return n->v + self( n->l.get(), self ) + self( n->r.get(), self );
			};
			long long acc = 0;
			auto t0 = std::chrono::steady_clock::now();
			long long total12 = 0;
			for ( int r = 0; r < 10; r++ )
			{
				std::unique_ptr<ONode> root = build( 12, r + 1, build );
				total12 += sum( root.get(), sum );
			}
			auto t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "tree depth12 x10 recursive sum = %lld  [%lld ns]\n", total12, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			t0 = std::chrono::steady_clock::now();
			long long total16 = 0;
			for ( int r = 0; r < 2; r++ )
			{
				std::unique_ptr<ONode> root = build( 16, r + 1, build );
				total16 += sum( root.get(), sum );
			}
			t1 = std::chrono::steady_clock::now();
			acc += std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
			printf( "tree depth16 x2 recursive sum = %lld  [%lld ns]\n", total16, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- acc;
		}
		Console.println("========== BinaryTree (C++) (end) ==========")
		ret ns
	}

	# 13. Mandelbrot：标准映射（对齐 SlBenchLib Render）
	static long mandelbrot()
	{
		Console.println("========== Mandelbrot (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <cstdint>
			#include <chrono>
			int w = 240;
			int h = 180;
			int maxIter = 150;
			long long iterSum = 0;
			int inside = 0;
			auto t0 = std::chrono::steady_clock::now();
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
			auto t1 = std::chrono::steady_clock::now();
			printf( "mandelbrot 240x180 x3  [%lld ns]  iterSum = %lld  inside = %d\n", std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count(), iterSum, inside );
			$ns <- std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
		}
		Console.println("========== Mandelbrot (C++) (end) ==========")
		ret ns
	}

	# 14. ListWalk：vector<对象> + const 成员方法遍历（C++ 专列）
	static long listWalk()
	{
		Console.println("========== ListWalk (C++) (start) ==========")
		long ns = 0L
		@cplus_clang()
		{
			#include <cstdio>
			#include <vector>
			#include <cstdint>
			#include <chrono>
			struct Item
			{
				long long a;
				long long b;
				long long total() const { return a + b; }
			};
			std::vector<Item> items( 100000 );
			for ( int i = 0; i < 100000; i++ )
			{
				items[(size_t)i].a = i;
				items[(size_t)i].b = (long long)i * 2;
			}
			long long total = 0;
			auto t0 = std::chrono::steady_clock::now();
			for ( int r = 0; r < 10; r++ )
			{
				for ( const Item& it : items ) { total += it.total(); }
			}
			auto t1 = std::chrono::steady_clock::now();
			printf( "object method walk 1e5 x10 = %lld  [%lld ns]\n", total, std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count() );
			$ns <- std::chrono::duration_cast<std::chrono::nanoseconds>( t1 - t0 ).count();
		}
		Console.println("========== ListWalk (C++) (end) ==========")
		ret ns
	}
}
