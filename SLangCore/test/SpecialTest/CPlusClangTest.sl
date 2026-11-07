import Std;
import Core;

# ============================================================================
# CPlusClangTest — cplus_clang 插件端到端测试（C++ 域 @tag 块 + FFI 直调）
#
# 链路：@cplus_clang(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) → 导出期
# PluginManager 构建段转调插件 frontend（sl_label_parse 生成 Entry_N.cpp：
# 头区 #include/using 提升 + SLCPP_EXPORT 函数区提取 + 固定原型 trampoline；
# sl_label_build clang++ 优先 / MSVC cl 回退合并编译部署 SLCpp.dll +
# 伴生契约 SLCpp.dll.slffi.json）→ CVM 经模块 atSignLabel[] 绑定懒 resolve
# 到 sl_cplus_clang labelExec → 装载 SLCpp.dll → GetProcAddress
#（"Entry_1_main"）固定原型调用（SLCppValue = SLLabelValue 逐字段镜像，
# in/out 数组零转换直拷）→ trampoline 编译期解包/打包 → 出值回推。
#
# 与 java/csharp 的差异点（本插件立身点）：块内 SLCPP_EXPORT 函数入口是
# extern "C" C-ABI 导出，SL 侧经既有 FFI 机制直接按签名映射调用
#（@DllImport 别名绑定 → ProjectTest.jsonc dllImports "SLCpp" 条目 →
# 装配期 73→77 改写 + SLCpp.dll.slffi.json 编译期签名校验），不经
# labelExec 通道。
#
# 通道类型路由（map_cpp_in_kind 五入通道）：整型族 → int64_t（SL INT 槽，
# int64 全域无窄化）、浮点族 → double（FLOAT 槽）、String 族 → const char*
#（UTF-8）、Boolean → bool（INT 0|1 槽，P0 拒收）；Object/SL 类名 →
# SLCppObject 树直传（读写双向递归，深度上限 32 同步）。出通道四 kind
#（int/f64/str/obj），数值族（int/f64）在 Front 脱糖 MapChannelOutKind
# 均归 ChannelOutInt——FLOAT 出值经 sl_atsign_push_out_i32 截断，浮点出值
# 断言须选截断无损值（如 5.0）。
#
# 用例覆盖（JavaTest 对齐 + C++ 特有）：① 无通道纯块 ② 出通道 Int
# ③ int64 全域往返（无窄化回归锁）④ double 入+出（3-4-5 → 5.0）
# ⑤ string 入+出 ⑥ 三类型混合入通道 ⑦ 块内 C++ throw 上抛 try-catch 捕获
#（CPP_EXC -105）+ 会话存活 ⑧ 库驻留复用（HMODULE 缓存命中）
# ⑨ FFI 直调（SLCPP_EXPORT 导出 + @DllImport 映射）⑩ OBJECT 树镜像往返。
# C/C++ 特有特性集（⑪-⑱）：⑪ 裸指针算术 + malloc/free + new[]/delete[]
# ⑫ 函数指针（qsort 比较器/指针表/经指针调 SLCPP_EXPORT 导出函数）
# ⑬ STL 容器算法（vector/sort/accumulate/string 拼接）⑭ 位运算
#（popcount/xor 交换/IEEE754 memcpy 双关）⑮ 泛型递归 lambda + 引用传参
# ⑯ std::thread 线程池 + std::atomic 归并 ⑰ unique_ptr RAII 数组
# ⑱ std::map + 迭代器 + find。
# 块内 C++ 代码约束：`<-` 序列禁用（通道标记语法）、#include 只能在块顶
#（入通道行之后）、块内不用 # 行注释（SL lexer 吞换行）。
# 前置：先跑 plugin\cplus_clang\cvm\build-cplus-clang.ps1（插件 dll +
# frontend + refModule）；MSVC（或 clang++）本机可用。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员丢失）。
# ============================================================================

# OBJECT 树镜像往返载体：普通 SL 类，两 int 字段
class CppPoint
{
    int x = 0
    int y = 0
}

class CPlusClangTest
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

    # ---- FFI 直调声明（@DllImport 别名形态：ProjectTest.jsonc dllImports
    # "SLCpp" 条目；符号 = 块内 SLCPP_EXPORT 导出名，sig 从签名推导，
    # 编译期经部署的 SLCpp.dll.slffi.json 契约校验）。fallback 体按惯例
    # 返回哨兵值（0 / 空串）——dll 绑定不可用时走 fallback，断言真值
    #（42 / "hi"）失败即暴露；绑定正常则断言通过，证明真实走了 FFI 路径 ----
    @DllImport( "SLCpp", "cpp_ffi_add" )
    static long s_ffiAdd( long a, long b )
    {
        ret 0
    }

    @DllImport( "SLCpp", "cpp_ffi_greet" )
    static string s_ffiGreet( string name )
    {
        ret ""
    }

    # ---------------- ① 无通道纯块（printf 直打进程控制台） ----------------
    # 无入无出 → trampoline 仅 try{lambda 空}；块内局部计算不影响 SL 侧变量。
    static testPlainBlock()
    {
        Console.println( "===== CPlusClangTest.testPlainBlock =====" )
        int keep = 42
        @cplus_clang()
        {
        #include <cstdio>
        printf( "hello from SLCpp (plain block)\n" );
        int64_t inner = 6 * 7;
        printf( "inner = %lld\n", (long long)inner );
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: executed, outer variable untouched", keep == 42 )
    }

    # ---------------- ② 出通道 Int（块内 for 求和 1..10 → 55） ----------------
    # 出通道缺省类型标记 → int64_t；SL 侧 int 变量回写。
    static testIntOutChannel()
    {
        Console.println( "===== CPlusClangTest.testIntOutChannel =====" )
        int count = 0
        @cplus_clang()
        {
        int64_t total = 0;
        for ( int64_t i = 1; i <= 10; i++ ) { total += i; }
        $count <- total;
        }
        Console.println( "sum(1..10) = " + count.toString() )
        check( "int out channel: for 1..10 == 55", count == 55 )
    }

    # ---------------- ③ int64 全域往返（无窄化决策回归锁） ----------------
    # 4000000000 超 int32 max（2147483647）——若任一侧误走 int32 窄化会回绕为负。
    static testInt64Roundtrip()
    {
        Console.println( "===== CPlusClangTest.testInt64Roundtrip =====" )
        long big = 4000000000
        long halfVal = 0
        @cplus_clang()
        {
        Long big <- $big
        $halfVal <- big / 2;
        }
        Console.println( "4000000000 / 2 = " + halfVal.toString() )
        check( "int64 full range: 4000000000 / 2 == 2000000000 (no narrowing)", halfVal == 2000000000 )
    }

    # ---------------- ④ double 入+出通道（std::sqrt 3-4-5 三角 → 5.0） ----------------
    # 浮点族 → double（FLOAT 槽）；出通道显式 double 类型标记（double $hyp <- expr），
    # 值经 ChannelOutInt 截断消费——5.0 截断无损（与 JavaTest 同策略）。
    static testDoubleRoundtrip()
    {
        Console.println( "===== CPlusClangTest.testDoubleRoundtrip =====" )
        double a = 3.0
        double b = 4.0
        double hyp = 0.0
        @cplus_clang()
        {
        Double a <- $a
        Double b <- $b
        #include <cmath>
        double $hyp <- std::sqrt( a * a + b * b );
        }
        Console.println( "hypot(3,4) = " + hyp.toString() )
        check( "double channels: std::sqrt(3*3+4*4) == 5.0", hyp == 5.0 )
    }

    # ---------------- ⑤ 入+出通道 String（std::string 拼接回传） ----------------
    # const char* 入通道（宿主 UTF-8 直读）+ string 出通道（slcpp_to_cstr
    # 两态适配 std::string → c_str() → env->alloc 深拷贝回推）。
    static testStringRoundtrip()
    {
        Console.println( "===== CPlusClangTest.testStringRoundtrip =====" )
        string name = "SimpleLanguage"
        string slogan = ""
        @cplus_clang()
        {
        String name <- $name
        #include <string>
        string $slogan <- std::string( "Hello, " ) + name + "!";
        }
        Console.println( "slogan = " + slogan )
        check( "string channels: roundtrip == 'Hello, SimpleLanguage!'", slogan == "Hello, SimpleLanguage!" )
    }

    # ---------------- ⑥ 三类型混合入通道（int64 + double + const char* 同块） ----------------
    # trampoline 按通道顺序逐个 guard+解包；target 形参名与 SL 变量名分离
    #（base/w/s vs n/weight/name）。
    static testMixedChannels()
    {
        Console.println( "===== CPlusClangTest.testMixedChannels =====" )
        int n = 0
        double weight = 2.5
        string name = "SLCpp"
        @cplus_clang()
        {
        Long base <- $n
        Double w <- $weight
        String s <- $name
        #include <cstring>
        $n <- base + (int64_t)( w * 10.0 ) + (int64_t)strlen( s );
        }
        Console.println( "mixed = " + n.toString() )
        check( "mixed channels: 0 + (int64)(2.5*10) + strlen('SLCpp') == 30", n == 30 )
    }

    # ---------------- ⑦ 异常上抛（块内 throw → CPP_EXC -105 → try-catch 捕获） ----------------
    # C++ 异常被 trampoline catch(...) 就地捕获返 -105 → cvm 侧 throw_error
    # 上抛 VM 异常 → SL label{}try{}catch{} 捕获（求值栈恢复 BeginTry 快照）。
    static int cppThrow()
    {
        @cplus_clang()
        {
        #include <stdexcept>
        throw std::runtime_error( "boom" );
        }
        ret 0
    }

    static testThrow()
    {
        Console.println( "===== CPlusClangTest.testThrow =====" )
        int caught = 0
        label cppThrowBlock
        {
            try cppThrow()
        }
        catch
        {
            caught = 1
        }
        check( "cpp-exc: caught (CPP_EXC -105)", caught == 1 )

        # 异常后库会话存活：SLCpp.dll 驻留（HMODULE 缓存，exit/unload 不
        # 卸载），同进程后续块调用不受污染（无实参残留）
        int after = 0
        @cplus_clang()
        {
        $after <- 20 + 22;
        }
        Console.println( "after-throw = " + after.toString() )
        check( "after-throw session alive: 20+22 == 42", after == 42 )
    }

    # ---------------- ⑧ 库驻留复用（HMODULE 路径键控缓存命中） ----------------
    # 同进程第二个块起 LoadLibrary 命中缓存不重复装载；块间值经 SL 变量接力。
    static testSessionReuse()
    {
        Console.println( "===== CPlusClangTest.testSessionReuse =====" )
        int a = 0
        int b = 0
        @cplus_clang()
        {
        $a <- 40 + 2;
        }
        @cplus_clang()
        {
        Long a <- $a
        $b <- a * 1;
        }
        Console.println( "reuse: a = " + a.toString() + " b = " + b.toString() )
        check( "session reuse: block1 40+2 == 42", a == 42 )
        check( "session reuse: block2 in+out echo == 42 (cache hit)", b == 42 )
    }

    # ---------------- ⑨ FFI 直调（SLCPP_EXPORT 导出 + @DllImport 映射） ----------------
    # 本插件差异点：块内 SLCPP_EXPORT 函数区原样提升为 extern "C" 导出
    #（文件作用域），随 SLCpp.dll 一并链接；sl_label_build 扫描签名生成
    # slffi 契约（int64_t→I64、const char*→Utf8String），SL 侧
    # s_ffiAdd/s_ffiGreet 经装配期改写直接调导出符号（不经 labelExec）。
    # 块体本身为空 trampoline（无通道，执行无副作用）。
    static testFfiDirectCall()
    {
        Console.println( "===== CPlusClangTest.testFfiDirectCall =====" )
        @cplus_clang()
        {
        SLCPP_EXPORT int64_t cpp_ffi_add( int64_t a, int64_t b )
        {
            return a + b;
        }
        SLCPP_EXPORT const char* cpp_ffi_greet( const char* name )
        {
            return "hi";
        }
        }
        long s = s_ffiAdd( 20, 22 )
        Console.println( "ffiAdd(20,22) = " + s.toString() )
        check( "ffi direct: cpp_ffi_add(20,22) == 42", s == 42 )
        string g = s_ffiGreet( "SLang" )
        Console.println( "ffiGreet = " + g )
        check( "ffi direct: cpp_ffi_greet utf8 roundtrip == 'hi'", g == "hi" )
    }

    # ---------------- ⑩ OBJECT 树镜像往返 ----------------
    # 入通道 SL 类名标记（CppPoint pv <- $p）→ sl_atsign_marshal_object
    # 递归编组 SLLabelObject 树 → SLCppObject 布局镜像零转换直传
    #（slcpp_obj_find 按名导航）；出树经 slcpp_make_object 全 env->alloc
    # 构造，CVM 按树重建 CppPoint 实例（同名同型字段逐个回填）压 $q。
    static testObjectTree()
    {
        Console.println( "===== CPlusClangTest.testObjectTree =====" )
        CppPoint p = CppPoint()
        p.x = 3
        p.y = 4
        CppPoint q = CppPoint()
        @cplus_clang()
        {
        CppPoint pv <- $p
        const SLCppField* fx = slcpp_obj_find( pv, "x" );
        const SLCppField* fy = slcpp_obj_find( pv, "y" );
        int64_t sx = fx != NULL ? fx->value.v.i : 0;
        int64_t sy = fy != NULL ? fy->value.v.i : 0;
        SLCppObject* out = slcpp_make_object( env, "CppPoint", 2 );
        slcpp_obj_set_int( env, out, 0, "x", sx + sy );
        slcpp_obj_set_int( env, out, 1, "y", sx * sy );
        CppPoint $q <- out;
        }
        Console.println( "objectTree: q.x = " + q.x.toString() + " q.y = " + q.y.toString() )
        check( "object tree: rebuilt q.x == 7 (3+4)", q.x == 7 )
        check( "object tree: rebuilt q.y == 12 (3*4)", q.y == 12 )
    }

    # ---------------- ⑪ 裸指针算术 + 原生堆（malloc/new，C/C++ 特有） ----------------
    # 块 A：malloc 一段 int 数组填平方，指针游走（*p / p != base+10 / ++p）求和，
    # free 归还；块 B：new[]/delete[] + 指针差（ptrdiff_t = 元素个数，非字节数）。
    static testRawPointers()
    {
        Console.println( "===== CPlusClangTest.testRawPointers =====" )
        int sum = 0
        @cplus_clang()
        {
        #include <cstdlib>
        #include <cstdint>
        int* base = (int*)malloc( 10 * sizeof( int ) );
        for ( int i = 0; i < 10; i++ ) { base[i] = ( i + 1 ) * ( i + 1 ); }
        int64_t total = 0;
        for ( int* p = base; p != base + 10; ++p ) { total += *p; }
        free( base );
        $sum <- total;
        }
        Console.println( "squares sum = " + sum.toString() )
        check( "raw pointer: malloc fill/walk/free sum(1..10 squares) == 385", sum == 385 )

        int span = 0
        @cplus_clang()
        {
        #include <cstddef>
        #include <cstdint>
        int* base = new int[8];
        for ( int i = 0; i < 8; i++ ) { base[i] = i; }
        ptrdiff_t span = ( base + 8 ) - base;
        delete[] base;
        $span <- (int64_t)span;
        }
        Console.println( "new[] span = " + span.toString() )
        check( "raw pointer: new[]/delete[] ptrdiff (base+8)-base == 8", span == 8 )
    }

    # ---------------- ⑫ 函数指针（C 特有：无捕获 lambda → 函数指针） ----------------
    # 块 A：qsort + 比较器函数指针（打包 min*1000+max 解码断言）；
    # 块 B：函数指针表（add/mul 两个无捕获 lambda）；
    # 块 C：经函数指针调用本块 SLCPP_EXPORT 导出函数（同 dll 文件作用域符号）。
    static testFunctionPointers()
    {
        Console.println( "===== CPlusClangTest.testFunctionPointers =====" )
        int packed = 0
        @cplus_clang()
        {
        #include <cstdlib>
        #include <cstdint>
        int arr[8] = { 42, 7, 99, 13, 64, 28, 81, 5 };
        int ( *cmp )( const void*, const void* ) =
            []( const void* a, const void* b ) -> int
            {
                int x = *(const int*)a;
                int y = *(const int*)b;
                return ( x > y ) - ( x < y );
            };
        qsort( arr, 8, sizeof( int ), cmp );
        $packed <- (int64_t)( arr[0] * 1000 + arr[7] );
        }
        Console.println( "qsort packed = " + packed.toString() )
        check( "function pointer: qsort asc packed == 5099 (min=5, max=99)", packed == 5099 )

        int total = 0
        @cplus_clang()
        {
        #include <cstdint>
        int64_t ( *ops[2] )( int64_t, int64_t ) = {
            []( int64_t a, int64_t b ) -> int64_t { return a + b; },
            []( int64_t a, int64_t b ) -> int64_t { return a * b; }
        };
        int64_t acc = 0;
        for ( int i = 0; i < 2; i++ ) { acc += ops[i]( 20, 2 ); }
        $total <- acc;
        }
        Console.println( "fn-ptr table total = " + total.toString() )
        check( "function pointer: ops table add(20,2)+mul(20,2) == 62", total == 62 )

        int viaFp = 0
        @cplus_clang()
        {
        #include <cstdint>
        SLCPP_EXPORT int64_t cpp_fnptr_target( int64_t a, int64_t b )
        {
            return a * 10 + b;
        }
        int64_t ( *fp )( int64_t, int64_t ) = &cpp_fnptr_target;
        $viaFp <- fp( 40, 2 );
        }
        Console.println( "exported via fp = " + viaFp.toString() )
        check( "function pointer: SLCPP_EXPORT called via pointer == 402", viaFp == 402 )
    }

    # ---------------- ⑬ STL 容器与算法（C++ 特有） ----------------
    # 块 A：vector 初始化列表 + sort(降序) + accumulate（打包 max*100000+sum）；
    # 块 B：vector<string> + 运算符拼接 → string 出通道（slcpp_to_cstr 两态）。
    static testStlContainers()
    {
        Console.println( "===== CPlusClangTest.testStlContainers =====" )
        int packed = 0
        @cplus_clang()
        {
        #include <vector>
        #include <algorithm>
        #include <numeric>
        #include <functional>
        #include <cstdint>
        std::vector<int> v = { 5, 3, 9, 1, 7 };
        std::sort( v.begin(), v.end(), std::greater<int>() );
        int total = std::accumulate( v.begin(), v.end(), 0 );
        $packed <- (int64_t)( v[0] * 100000 + total );
        }
        Console.println( "stl packed = " + packed.toString() )
        check( "stl: vector sort desc + accumulate packed == 900025 (max=9, sum=25)", packed == 900025 )

        string joined = ""
        @cplus_clang()
        {
        #include <vector>
        #include <string>
        std::vector<std::string> words = { "native", "STL", "works" };
        std::string joined = words[0] + "-" + words[1] + "-" + words[2];
        string $joined <- joined;
        }
        Console.println( "stl joined = " + joined )
        check( "stl: vector<string> operator+ join == 'native-STL-works'", joined == "native-STL-works" )
    }

    # ---------------- ⑭ 位运算与 IEEE754 双关（C/C++ 特有） ----------------
    # 块 A：Kernighan popcount（x &= x-1 清最低位）；块 B：xor 原地交换；
    # 块 C：double 位模式 memcpy 双关，抽指数字段（打包 exp*10 + mantissa 命中位）。
    static testBitLevel()
    {
        Console.println( "===== CPlusClangTest.testBitLevel =====" )
        int bits = 0
        @cplus_clang()
        {
        #include <cstdint>
        uint64_t x = 0xF0F0F0F0F0F0F0F0ULL;
        int n = 0;
        while ( x ) { x &= ( x - 1 ); n++; }
        $bits <- n;
        }
        Console.println( "popcount = " + bits.toString() )
        check( "bitwise: Kernighan popcount(0xF0F0...F0) == 32", bits == 32 )

        int swapped = 0
        @cplus_clang()
        {
        #include <cstdint>
        int a = 1234;
        int b = 4321;
        a ^= b; b ^= a; a ^= b;
        $swapped <- b;
        }
        Console.println( "xor-swapped b = " + swapped.toString() )
        check( "bitwise: xor swap a=1234,b=4321 then b == 1234", swapped == 1234 )

        int ieee = 0
        @cplus_clang()
        {
        #include <cstdint>
        #include <cstring>
        double d = 2.5;
        uint64_t raw = 0;
        memcpy( &raw, &d, sizeof( raw ) );
        uint64_t expo = ( raw >> 52 ) & 0x7FFULL;
        uint64_t mant = raw & ( ( 1ULL << 52 ) - 1ULL );
        $ieee <- (int64_t)( expo * 10 + ( mant == 0x4000000000000ULL ? 1 : 0 ) );
        }
        Console.println( "ieee packed = " + ieee.toString() )
        check( "bitwise: 2.5 bit-cast packed == 10241 (exp=1024, mantissa 0x4000000000000)", ieee == 10241 )
    }

    # ---------------- ⑮ 泛型递归 lambda + 引用传参（C++ 特有） ----------------
    # 块 A：auto&& 自传递归（fib(30)，无嵌套函数声明）；块 B：lambda 引用形参
    # 原地累加（打包 a*100+b）。
    static testLambdaRecursion()
    {
        Console.println( "===== CPlusClangTest.testLambdaRecursion =====" )
        int fibv = 0
        @cplus_clang()
        {
        #include <cstdint>
        auto fib = []( int64_t n, auto&& self ) -> int64_t
        {
            if ( n <= 1 ) { return n; }
            return self( n - 1, self ) + self( n - 2, self );
        };
        $fibv <- fib( 30, fib );
        }
        Console.println( "fib(30) = " + fibv.toString() )
        check( "recursive lambda: fib(30) via auto&& self == 832040", fibv == 832040 )

        int packed = 0
        @cplus_clang()
        {
        #include <cstdint>
        int64_t a = 10;
        int64_t b = 20;
        auto bump = []( int64_t& r, int64_t v ) { r += v; };
        bump( a, 5 );
        bump( b, 6 );
        $packed <- a * 100 + b;
        }
        Console.println( "ref bump packed = " + packed.toString() )
        check( "reference params: bump a=10,b=20 packed == 1526 (15*100+26)", packed == 1526 )
    }

    # ---------------- ⑯ std::thread 线程池 + std::atomic 归并（C++ 特有） ----------------
    # 块内起 4 个 OS 线程分片求和，原子累加后 join——块同步返回，线程不触碰
    # VM 状态（无跨界内存，堆活动全在本 dll 静态 CRT 堆）。
    # 期望：sum( t*1000+i, i=0..249, t=0..3 ) = 4*31125 + 6000*250 = 1624500。
    static testThreads()
    {
        Console.println( "===== CPlusClangTest.testThreads =====" )
        int sum = 0
        @cplus_clang()
        {
        #include <thread>
        #include <atomic>
        #include <vector>
        #include <cstdint>
        std::atomic<int64_t> total{ 0 };
        std::vector<std::thread> pool;
        for ( int t = 0; t < 4; t++ )
        {
            pool.emplace_back( [ &total, t ]()
            {
                int64_t local = 0;
                for ( int i = 0; i < 250; i++ ) { local += t * 1000 + i; }
                total += local;
            } );
        }
        for ( auto& th : pool ) { th.join(); }
        $sum <- total.load();
        }
        Console.println( "4-thread atomic sum = " + sum.toString() )
        check( "threads: 4x std::thread + atomic merge == 1624500", sum == 1624500 )
    }

    # ---------------- ⑰ unique_ptr RAII 数组（C++ 特有） ----------------
    # new[] 所有权交给 unique_ptr<int64_t[]>，作用域结束自动 delete[]（无需
    # 手写 free）；sum( (i+1)*11, i=0..7 ) = 11*36 = 396。
    static testSmartPointers()
    {
        Console.println( "===== CPlusClangTest.testSmartPointers =====" )
        int sum = 0
        @cplus_clang()
        {
        #include <memory>
        #include <cstdint>
        std::unique_ptr<int64_t[]> buf( new int64_t[8] );
        for ( int i = 0; i < 8; i++ ) { buf[i] = (int64_t)( i + 1 ) * 11; }
        int64_t total = 0;
        for ( int i = 0; i < 8; i++ ) { total += buf[i]; }
        $sum <- total;
        }
        Console.println( "unique_ptr sum = " + sum.toString() )
        check( "smart pointer: unique_ptr<int64_t[]> RAII sum == 396", sum == 396 )
    }

    # ---------------- ⑱ std::map + 迭代器 + find（C++ 特有） ----------------
    # 有序关联容器：range-for 遍历求和 + find 迭代器定位（打包 total*100+grace）。
    static testMapIteration()
    {
        Console.println( "===== CPlusClangTest.testMapIteration =====" )
        int packed = 0
        @cplus_clang()
        {
        #include <map>
        #include <string>
        #include <cstdint>
        std::map<std::string, int64_t> ages;
        ages[ "ada" ] = 36;
        ages[ "linus" ] = 54;
        ages[ "grace" ] = 45;
        int64_t total = 0;
        for ( auto& kv : ages ) { total += kv.second; }
        auto it = ages.find( "grace" );
        int64_t grace = it != ages.end() ? it->second : -1;
        $packed <- total * 100 + grace;
        }
        Console.println( "map packed = " + packed.toString() )
        check( "std::map: iterate+find packed == 13545 (total=135, grace=45)", packed == 13545 )
    }

    static fun()
    {
        Console.println( "========== CPlusClangTest start ==========" )
        testPlainBlock()
        testIntOutChannel()
        testInt64Roundtrip()
        testDoubleRoundtrip()
        testStringRoundtrip()
        testMixedChannels()
        testThrow()
        testSessionReuse()
        testFfiDirectCall()
        testObjectTree()
        testRawPointers()
        testFunctionPointers()
        testStlContainers()
        testBitLevel()
        testLambdaRecursion()
        testThreads()
        testSmartPointers()
        testMapIteration()
        Console.println( "========== CPlusClangTest end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}
