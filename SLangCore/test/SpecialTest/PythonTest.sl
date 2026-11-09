import Std;
import Core;

# ============================================================================
# PythonTest — python_cpython 插件端到端测试（蓝本 = JavaTest.sl）
#
# 链路：@python_cpython(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) → 导出期
# PluginManager 转调插件 frontend（parse 生成 Entry_N.py 的 def run 源码 +
# build 免编译部署 libDir\pysrc\）→ CVM 经模块 atSignLabel[] 绑定懒 resolve
# 到 sl_python_cpython labelExec → py_bridge（LoadLibrary python3xx.dll +
# Py_Initialize + sys.path 挂 pysrc + mtime 失效重导入 + import Entry_N →
# getattr run → PyObject_CallObject）→ 出通道五态
#（None/bool·int/float/str/dict 树）编组回推。
#
# 通道类型路由（MapPyType 五通道，比 Java 域多 bool）：整型族 → int
#（PyLong_FromLongLong，int64 全域无窄化）、浮点族 → float、String 族 → str；
# Boolean 族 → bool（CPython 原生 bool，编组 INT 0|1——Java 域拒收，Python
# 域放行）；Object/SL 类名 → dict 树镜像（__sltype__ 键携带 SL 类名，读写
# 双向递归，深度上限 32 同步）。entryMethod 恒 "run"（Python 动态类型，
# 无 Java 式完整方法规格）。
#
# 用法覆盖：① 无通道纯块 ② 出通道 Int ③ 入+出通道 String ④ 块内 raise
# 上抛 SL 异常 try-catch 捕获；附加：int64 全域往返、double 通道、bool
# 通道（Python 特有）、三类型混合入通道、dict OBJECT 树往返、异常后解释器
# 会话存活（异常经 drain 不破坏 GIL/模块缓存，exit 不 Py_Finalize）。
# 前置：本机 CPython 3.10+（python3xx.dll 在 PATH / SL_PY_DLL 覆盖；
# 编译期无工具链要求——Python 免编译）。无 CPython 时块运行期报 -102。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员丢失）。
# ============================================================================

# OBJECT 树镜像往返载体：普通 SL 类，两 int 字段（镜像 JavaPoint）
class PyPoint
{
    int x = 0
    int y = 0
}

class PythonTest
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

    # ---------------- ① 无通道纯块（副作用型，print 直打进程控制台） ----------------
    # 无入无出 → def run(): → PyObject_CallObject(func, NULL)；块内局部
    # 计算不影响 SL 侧变量。
    static testPlainBlock()
    {
        Console.println( "===== PythonTest.testPlainBlock =====" )
        int keep = 42
        @python_cpython()
        {
            print( "hello from CPython (plain block)" )
            inner = 6 * 7
            print( "inner =", inner )
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: run() executed, outer variable untouched", keep == 42 )
    }

    # ---------------- ② 出通道 Int（块内 for 求和 1..10 → 55） ----------------
    # 出通道缺省类型标记 → int；SL 侧 int 变量回写。
    # python range 半开区间：sum(range(1, 11)) == 55。
    static testIntOutChannel()
    {
        Console.println( "===== PythonTest.testIntOutChannel =====" )
        int count = 0
        @python_cpython()
        {
            total = 0
            for i in range(1, 11):
                total += i
            $count <- total;
        }
        Console.println( "sum(1..10) = " + count.toString() )
        check( "int out channel: sum 1..10 == 55", count == 55 )
    }

    # ---------------- int64 全域往返（无窄化决策回归锁） ----------------
    # 4000000000 超 int32 max（2147483647）——若 C 侧误走 32 位窄化会回绕为负。
    static testInt64Roundtrip()
    {
        Console.println( "===== PythonTest.testInt64Roundtrip =====" )
        long big = 4000000000
        long halfVal = 0
        @python_cpython()
        {
            long big <- $big
            $halfVal <- big // 2;
        }
        Console.println( "4000000000 / 2 = " + halfVal.toString() )
        check( "int64 full range: 4000000000 / 2 == 2000000000 (no narrowing)", halfVal == 2000000000 )
    }

    # ---------------- double 入+出通道（math.sqrt 3-4-5 三角 → 5.0） ----------------
    # 浮点族 → float（PyFloat_FromDouble / PyFloat_AsDouble）；块内 import
    # 是普通 Python 语句（函数体内合法）；出通道显式 double 类型标记。
    static testDoubleRoundtrip()
    {
        Console.println( "===== PythonTest.testDoubleRoundtrip =====" )
        double a = 3.0
        double b = 4.0
        double hyp = 0.0
        @python_cpython()
        {
            double a <- $a
            double b <- $b
            import math
            double $hyp <- math.sqrt( a * a + b * b );
        }
        Console.println( "hypot(3,4) = " + hyp.toString() )
        check( "double channels: math.sqrt(3*3+4*4) == 5.0", hyp == 5.0 )
    }

    # ---------------- ③ 入+出通道 String（拼接回传） ----------------
    # String 入通道（PyUnicode_FromString）+ string 出通道
    #（PyUnicode_AsUTF8 + host->alloc 深拷贝回推）；出通道带 slType 标记。
    static testStringRoundtrip()
    {
        Console.println( "===== PythonTest.testStringRoundtrip =====" )
        string name = "SimpleLanguage"
        string slogan = ""
        @python_cpython()
        {
            string name <- $name
            string $slogan <- "Hello, " + name + "!";
        }
        Console.println( "slogan = " + slogan )
        check( "string channels: roundtrip == 'Hello, SimpleLanguage!'", slogan == "Hello, SimpleLanguage!" )
    }

    # ---------------- bool 通道（CPython 原生 bool，Python 域特有） ----------------
    # Boolean 入通道编组 INT 0|1 → Python True/False；出通道 bool → INT 0|1
    #（bool 是 PyLong_Type 子类，C 侧先于 int 精确判定 PyBool_Type）。
    static testBoolChannel()
    {
        Console.println( "===== PythonTest.testBoolChannel =====" )
        bool flag = true
        int flipped = 1
        @python_cpython()
        {
            bool flag <- $flag
            $flipped <- not flag;
        }
        Console.println( "not True = " + flipped.toString() )
        check( "bool channel: not True == False (0)", flipped == 0 )
    }

    # ---------------- 三类型混合入通道（int + float + str 同块） ----------------
    # 生成形参 run(base, w, s)；target 形参名与 SL 变量名分离。
    static testMixedChannels()
    {
        Console.println( "===== PythonTest.testMixedChannels =====" )
        int n = 0
        double weight = 2.5
        string name = "CPython"
        @python_cpython()
        {
            int base <- $n
            double w <- $weight
            string s <- $name
            $n <- base + int( w * 10.0 ) + len( s );
        }
        Console.println( "mixed = " + n.toString() )
        check( "mixed channels: 0 + int(2.5*10) + len('CPython') == 32", n == 32 )
    }

    # ---------------- ④ 异常上抛（块内 raise → MANAGED_EXC -105 → try-catch 捕获） ----------------
    # Python pending 异常经 PyErr_Fetch + NormalizeException + PyObject_Str
    # drain 为消息文本（throw_error -105）→ VM 异常 → SL try-catch 捕获。
    static int pythonThrow()
    {
        @python_cpython()
        {
            raise RuntimeError( "boom" )
        }
        ret 0
    }

    static testThrow()
    {
        Console.println( "===== PythonTest.testThrow =====" )
        int caught = 0
        label pythonThrowBlock
        {
            try pythonThrow()
        }
        catch
        {
            caught = 1
        }
        check( "managed-exc: caught (MANAGED_EXC -105)", caught == 1 )

        # 异常后解释器会话存活（探针 5.5 同款回归）：pending 已 drain，
        # 同进程后续块调用不受污染（GIL 配对释放，模块缓存有效）
        int after = 0
        @python_cpython()
        {
            $after <- 20 + 22;
        }
        Console.println( "after-throw = " + after.toString() )
        check( "after-throw session alive: 20+22 == 42", after == 42 )
    }

    # ---------------- 会话复用（同进程第二个块起 sys.modules 缓存命中） ----------------
    # 块间值经 SL 变量接力；每块独立模块（Entry_N），import 命中缓存。
    static testSessionReuse()
    {
        Console.println( "===== PythonTest.testSessionReuse =====" )
        int a = 0
        int b = 0
        @python_cpython()
        {
            $a <- 40 + 2;
        }
        @python_cpython()
        {
            int a <- $a
            $b <- a * 1;
        }
        Console.println( "reuse: a = " + a.toString() + " b = " + b.toString() )
        check( "session reuse: block1 40+2 == 42", a == 42 )
        check( "session reuse: block2 in+out echo == 42 (cache hit)", b == 42 )
    }

    # ---------------- ⑤ OBJECT 树镜像往返（dict 树） ----------------
    # 入通道 SL 类名标记（PyPoint pv <- $p）→ sl_atsign_marshal_object
    # 递归编组 SLLabelObject 树 → Python dict（__sltype__ + 字段名键）；
    # 出通道 dict（__sltype__ 作类型名）→ C 侧按树重建 PyPoint 实例
    #（同名同型字段逐个回填）压 $q；深度上限 32 双向对称。
    static testObjectTree()
    {
        Console.println( "===== PythonTest.testObjectTree =====" )
        PyPoint p = PyPoint()
        p.x = 3
        p.y = 4
        PyPoint q = PyPoint()
        @python_cpython()
        {
            PyPoint pv <- $p
            sx = pv["x"]
            sy = pv["y"]
            PyPoint $q <- {"__sltype__": "PyPoint", "x": sx + sy, "y": sx * sy};
        }
        Console.println( "objectTree: q.x = " + q.x.toString() + " q.y = " + q.y.toString() )
        check( "object tree: rebuilt q.x == 7 (3+4)", q.x == 7 )
        check( "object tree: rebuilt q.y == 12 (3*4)", q.y == 12 )
    }

    static fun()
    {
        Console.println( "========== PythonTest start ==========" )
        testPlainBlock()
        testIntOutChannel()
        testInt64Roundtrip()
        testDoubleRoundtrip()
        testStringRoundtrip()
        testBoolChannel()
        testMixedChannels()
        testThrow()
        testSessionReuse()
        testObjectTree()
        Console.println( "========== PythonTest end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}
