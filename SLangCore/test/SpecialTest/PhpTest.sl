import Std;
import Core;

# ============================================================================
# PhpTest — php_embed 插件端到端测试（蓝本 = PythonTest.sl）
#
# 链路：@php_embed(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) → 导出期
# PluginManager 转调插件 frontend（parse 生成 Entry_N.php 的 function run
# 源码 + build 免编译部署 libDir\phpsrc\）→ CVM 经模块 atSignLabel[] 绑定
# 懒 resolve 到 sl_php_embed labelExec → php_bridge（php_embed_init +
# 全局唯一函数重命名 sl_php_entry_<N>_v<K> + zend_eval_string +
# zend_call_function）→ 出通道五态编组回推。
#
# 通道类型路由（map_php_type 五通道）：整型族 → int（ZVAL_LONG，int64
# 全域无窄化，x64 TS 构建）、浮点族 → float（ZVAL_DOUBLE）、String 族 →
# string；Boolean 族 → bool（PHP 原生 bool，编组 INT 0|1）；Object/SL
# 类名 → array 树镜像（__sltype__ 键携带 SL 类名，读写双向递归，深度
# 上限 32 同步）。entryMethod 恒 "run"（PHP 动态类型，无完整方法规格）。
#
# ★ PHP 域出通道铁律：Front 出通道表达式不可以 $ 开头（防误吞入通道
# 形态），而 PHP 表达式天然以 $ 起首——故出通道表达式一律加小括号
# 包裹（`$count <- ($total);`），生成 `return ($total);` 为合法 PHP。
# 入通道目标形参名不带 $（Front 契约），C 侧生成 function run($target)。
#
# 用法覆盖：① 无通道纯块 ② 出通道 Int ③ 入+出通道 String ④ 块内
# throw new Exception 上抛 SL 异常 try-catch 捕获；附加：int64 全域
# 往返、double 通道、bool 通道、三类型混合入通道、array OBJECT 树往返、
# 异常后解释器会话存活（异常经 set_exception_handler 哨兵 drain 不
# bailout，exit 不 php_embed_shutdown）。
# 前置：插件包 package\windows\php8ts.dll（vendored，PHP 8.4 TS x64）；
# 编译期无工具链要求——PHP 免编译（zend_eval_string 解释执行）。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员丢失）。
# ============================================================================

# OBJECT 树镜像往返载体：普通 SL 类，两 int 字段（镜像 PyPoint）
class PhpPoint
{
    int x = 0
    int y = 0
}

class PhpTest
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

    # ---------------- ① 无通道纯块（副作用型，echo 直打进程控制台） ----------------
    # 无入无出 → function run() → zend_call_function 空参；块内局部
    # 计算不影响 SL 侧变量。
    static testPlainBlock()
    {
        Console.println( "===== PhpTest.testPlainBlock =====" )
        int keep = 42
        @php_embed()
        {
            echo "hello from PHP (plain block)\n";
            $inner = 6 * 7;
            echo "inner = " . $inner . "\n";
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: run() executed, outer variable untouched", keep == 42 )
    }

    # ---------------- ② 出通道 Int（块内 for 求和 1..10 → 55） ----------------
    # 出通道缺省类型标记 → int；SL 侧 int 变量回写。表达式加括号
    # 规避 Front「出通道不可以 $ 开头」铁律。
    static testIntOutChannel()
    {
        Console.println( "===== PhpTest.testIntOutChannel =====" )
        int count = 0
        @php_embed()
        {
            $total = 0;
            for ($i = 1; $i <= 10; $i++) {
                $total += $i;
            }
            $count <- ($total);
        }
        Console.println( "sum(1..10) = " + count.toString() )
        check( "int out channel: sum 1..10 == 55", count == 55 )
    }

    # ---------------- int64 全域往返（无窄化决策回归锁） ----------------
    # 4000000000 超 int32 max（2147483647）——若 C 侧误走 32 位窄化会回绕为负。
    static testInt64Roundtrip()
    {
        Console.println( "===== PhpTest.testInt64Roundtrip =====" )
        long big = 4000000000
        long halfVal = 0
        @php_embed()
        {
            long big <- $big
            $halfVal <- (intdiv($big, 2));
        }
        Console.println( "4000000000 / 2 = " + halfVal.toString() )
        check( "int64 full range: 4000000000 / 2 == 2000000000 (no narrowing)", halfVal == 2000000000 )
    }

    # ---------------- double 入+出通道（sqrt 3-4-5 三角 → 5.0） ----------------
    # 浮点族 → float（ZVAL_DOUBLE）；出通道显式 double 类型标记。
    static testDoubleRoundtrip()
    {
        Console.println( "===== PhpTest.testDoubleRoundtrip =====" )
        double a = 3.0
        double b = 4.0
        double hyp = 0.0
        @php_embed()
        {
            double a <- $a
            double b <- $b
            double $hyp <- (sqrt($a * $a + $b * $b));
        }
        Console.println( "hypot(3,4) = " + hyp.toString() )
        check( "double channels: sqrt(3*3+4*4) == 5.0", hyp == 5.0 )
    }

    # ---------------- ③ 入+出通道 String（拼接回传） ----------------
    # String 入通道（ZVAL_STRING dup）+ string 出通道（host_alloc 深拷贝
    # 回推）；出通道带 slType 标记。PHP 字符串拼接用 . 运算符。
    static testStringRoundtrip()
    {
        Console.println( "===== PhpTest.testStringRoundtrip =====" )
        string name = "SimpleLanguage"
        string slogan = ""
        @php_embed()
        {
            string name <- $name
            string $slogan <- ("Hello, " . $name . "!");
        }
        Console.println( "slogan = " + slogan )
        check( "string channels: roundtrip == 'Hello, SimpleLanguage!'", slogan == "Hello, SimpleLanguage!" )
    }

    # ---------------- bool 通道（PHP 原生 bool） ----------------
    # Boolean 入通道编组 INT 0|1 → PHP true/false；出通道 bool → INT 0|1
    #（C 侧 IS_TRUE/IS_FALSE 先于 IS_LONG 判定）。
    static testBoolChannel()
    {
        Console.println( "===== PhpTest.testBoolChannel =====" )
        bool flag = true
        int flipped = 1
        @php_embed()
        {
            bool flag <- $flag
            $flipped <- (!$flag);
        }
        Console.println( "not true = " + flipped.toString() )
        check( "bool channel: not true == false (0)", flipped == 0 )
    }

    # ---------------- 三类型混合入通道（int + float + str 同块） ----------------
    # 生成形参 run($base, $w, $s)；target 形参名与 SL 变量名分离。
    static testMixedChannels()
    {
        Console.println( "===== PhpTest.testMixedChannels =====" )
        int n = 0
        double weight = 2.5
        string name = "PHP"
        @php_embed()
        {
            int base <- $n
            double w <- $weight
            string s <- $name
            $n <- ($base + intval($w * 10.0) + strlen($s));
        }
        Console.println( "mixed = " + n.toString() )
        check( "mixed channels: 0 + intval(2.5*10) + strlen('PHP') == 28", n == 28 )
    }

    # ---------------- ④ 异常上抛（块内 throw → MANAGED_EXC -105 → try-catch 捕获） ----------------
    # PHP 未捕获异常经 set_exception_handler 哨兵（$GLOBALS['__sl_php_last_exc']）
    # drain 为消息文本（throw_error -105）→ VM 异常 → SL try-catch 捕获。
    static int phpThrow()
    {
        @php_embed()
        {
            throw new Exception( "boom" );
        }
        ret 0
    }

    static testThrow()
    {
        Console.println( "===== PhpTest.testThrow =====" )
        int caught = 0
        label phpThrowBlock
        {
            try phpThrow()
        }
        catch
        {
            caught = 1
        }
        check( "managed-exc: caught (MANAGED_EXC -105)", caught == 1 )

        # 异常后解释器会话存活：哨兵已 drain，同进程后续块调用不受污染
        int after = 0
        @php_embed()
        {
            $after <- (20 + 22);
        }
        Console.println( "after-throw = " + after.toString() )
        check( "after-throw session alive: 20+22 == 42", after == 42 )
    }

    # ---------------- 会话复用（同进程第二个块起函数缓存命中） ----------------
    # 块间值经 SL 变量接力；每块独立函数（sl_php_entry_<N>_v<K>），
    # mtime 不变复用版本号。
    static testSessionReuse()
    {
        Console.println( "===== PhpTest.testSessionReuse =====" )
        int a = 0
        int b = 0
        @php_embed()
        {
            $a <- (40 + 2);
        }
        @php_embed()
        {
            int a <- $a
            $b <- ($a * 1);
        }
        Console.println( "reuse: a = " + a.toString() + " b = " + b.toString() )
        check( "session reuse: block1 40+2 == 42", a == 42 )
        check( "session reuse: block2 in+out echo == 42 (cache hit)", b == 42 )
    }

    # ---------------- ⑤ OBJECT 树镜像往返（array 树） ----------------
    # 入通道 SL 类名标记（PhpPoint pv <- $p）→ marshal_value 递归编组
    # SLLabelObject 树 → PHP array（__sltype__ + 字段名键）；出通道
    # array（__sltype__ 作类型名）→ C 侧按树重建 PhpPoint 实例（同名同型
    # 字段逐个回填）压 $q；深度上限 32 双向对称。PHP 关联数组用 => 键值。
    static testObjectTree()
    {
        Console.println( "===== PhpTest.testObjectTree =====" )
        PhpPoint p = PhpPoint()
        p.x = 3
        p.y = 4
        PhpPoint q = PhpPoint()
        @php_embed()
        {
            PhpPoint pv <- $p
            $sx = $pv["x"];
            $sy = $pv["y"];
            PhpPoint $q <- (["__sltype__" => "PhpPoint", "x" => $sx + $sy, "y" => $sx * $sy]);
        }
        Console.println( "objectTree: q.x = " + q.x.toString() + " q.y = " + q.y.toString() )
        check( "object tree: rebuilt q.x == 7 (3+4)", q.x == 7 )
        check( "object tree: rebuilt q.y == 12 (3*4)", q.y == 12 )
    }

    static fun()
    {
        Console.println( "========== PhpTest start ==========" )
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
        Console.println( "========== PhpTest end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}