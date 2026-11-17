import Std;
import Core;

# ============================================================================
# TypeScriptNodeV8Test — typescript_nodev8 插件端到端测试（Node.js V8 引擎 + TypeScript）
#
# 链路：@typescript_nodev8(){} 内联块 → Front 圈地（括号/块配平原文截取）+
# 插件 frontend 解析器（sl_typescript_nodev8_frontend.dll）→ 部署
# scripts\Entry_N.mts（TS 原文，Node >= 22.6 原生类型擦除执行，零 tsc）→
# 运行期 CVM atSignLabel[] → cvm_typescript_nodev8.dll 的 node_bridge
# （keep-alive node.exe 子进程 + 行分隔 JSON stdio 协议）→ host.mts
# 动态 import 执行。
# 块语法（与 @csharp_mono / @javascript_quickjs 同构）：
#   头区入通道  Int32 a <- $a   （slType 形参名 <- $外层SL变量）
#   代码段      TypeScript 原文（interface/类型标注/泛型/await 均可擦除）
#   末行出通道  $c <- expr;     （Front 脱糖为 AtSignLabelCall 哨兵 + run 的
#                                return，J/D/S/O 四规格）
# 错误路径：JS 侧异常 → host->throw_error(-105 MANAGED_EXC) → SL try-catch；
# 脚本/函数定位失败 → -103 NOT_FOUND。
# 注意：本文件禁用行内注释（只整行使用）；块内字符串禁字面 # 字符。
# ============================================================================

class TypeScriptNodeV8Test
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

    # ---------------- Void 块：console 事件通路（log→out / error→err） ----------------
    static testVoidBlock()
    {
        Console.println( "===== TypeScriptNodeV8Test.testVoidBlock =====" )
        @typescript_nodev8()
        {
            console.log("hello from Node.js V8");
            console.error("warn line goes to err stream");
        }
        check( "void block executed (console lines above)", true )
    }

    # ---------------- J 通道：int 入出（两块连跑 = keep-alive 子进程复用） ----------------
    static testIntChannel()
    {
        Console.println( "===== TypeScriptNodeV8Test.testIntChannel =====" )
        int a = 40
        int b = 2
        int c = 0
        @typescript_nodev8()
        {
            Int32 a <- $a
            Int32 b <- $b
            const sum: number = a + b;
            Int32 $c <- sum;
        }
        check( "int channel: 40+2 == 42", c == 42 )

        int d = 0
        @typescript_nodev8()
        {
            Int32 x <- $a
            Int32 y <- $b
            let acc = 0;
            for (let i = 0; i < 3; i++) { acc += x * y; }
            Int32 $d <- acc;
        }
        check( "int channel (2nd block, same child): 3*80 == 240", d == 240 )
    }

    # ---------------- D 通道：double 入出 ----------------
    static testDoubleChannel()
    {
        Console.println( "===== TypeScriptNodeV8Test.testDoubleChannel =====" )
        double x = 1.25
        string r = ""
        @typescript_nodev8()
        {
            Double x <- $x
            const scaled: number = x * 4.0 + 0.5;
            String $r <- String(scaled);
        }
        check( "double channel (D in / S out): 1.25*4+0.5 == 5.5", r == "5.5" )
    }

    # ---------------- S 通道：string 入出 ----------------
    static testStringChannel()
    {
        Console.println( "===== TypeScriptNodeV8Test.testStringChannel =====" )
        string name = "v8"
        string r = ""
        @typescript_nodev8()
        {
            String name <- $name
            const msg = `hi ${name.toUpperCase()} ts`;
            String $r <- msg;
        }
        check( "string channel: hi V8 ts", r == "hi V8 ts" )
    }

    # ---------------- TS 类型语法：interface / 泛型 / 箭头 / await ----------------
    static testTsSyntax()
    {
        Console.println( "===== TypeScriptNodeV8Test.testTsSyntax =====" )
        string s = ""
        int n = 6
        @typescript_nodev8()
        {
            Int32 n <- $n
            interface Pt { x: number; y: number }
            const p: Pt = { x: n, y: n * 2 };
            const xs: Array<number> = [p.x, p.y, p.x + p.y];
            const doubled = xs.map((v: number): number => v * 10);
            const tag = `pt[${doubled.join(",")}]`;
            await Promise.resolve();
            String $s <- tag;
        }
        check( "ts syntax stripped and run: pt[60,120,180]", s == "pt[60,120,180]" )
    }

    # ---------------- JS 侧异常 → SL try-catch 捕获（-105 MANAGED_EXC） ----------------
    static testJsException()
    {
        Console.println( "===== TypeScriptNodeV8Test.testJsException =====" )
        int caught = 0
        label jsExcBlock
        {
            try
            {
                @typescript_nodev8()
                {
                    throw new Error("boom from js");
                }
            }
            catch
            {
                caught = 1
            }
        }
        check( "js exception caught by SL try-catch", caught == 1 )
    }

    # ---------------- 异常后栈恢复（catch 后正向调用不受实参残留污染） ----------------
    static testAfterCatch()
    {
        Console.println( "===== TypeScriptNodeV8Test.testAfterCatch =====" )
        int caught = 0
        label jsExc2
        {
            try
            {
                @typescript_nodev8()
                {
                    throw new Error("first boom");
                }
            }
            catch
            {
                caught = 1
            }
        }
        int c = 0
        @typescript_nodev8()
        {
            const v: number = 21 * 2;
            Int32 $c <- v;
        }
        check( "after catch: stack clean 21*2 == 42", c == 42 && caught == 1 )
    }

    # ---------------- 汇总入口 ----------------
    static fun()
    {
        testVoidBlock()
        testIntChannel()
        testDoubleChannel()
        testStringChannel()
        testTsSyntax()
        testJsException()
        testAfterCatch()

        Console.println( "===== TypeScriptNodeV8Test summary: passed=" + passed.toString() + " failed=" + failed.toString() + " =====" )
    }
}
