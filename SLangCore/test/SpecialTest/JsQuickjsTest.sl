import Std;
import Core;

# ============================================================================
# JsQuickjsTest — javascript_quickjs 插件端到端测试（外部 JS 库引入专项）
#
# 链路：@javascript_quickjs(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) →
# 导出期 PluginManager 构建段转调插件 frontend（SLPF v3：生成 "use strict"
# + function run 包裹源，QuickJS compile-only 语法检查）→ 部署
# <libDir>\scripts\Entry_N.js → CVM 经模块 atSignLabel[] 绑定懒 resolve 到
# sl_javascript_quickjs labelExec → quickjs_bridge_run_entry（lib 槽位
# JSContext 首建时按 _slqjs_libs.txt 清单装载外部库 → JS_Eval Entry →
# JS_GetPropertyStr(global, "run") → JS_Call → 出通道编组回推）。
#
# 外部库（工程 jsonc plugins.javascript_quickjs.sources = JsCode\
# SlJsExtraUtil.js）：构建器部署 scripts\CsSrc_SlJsExtraUtil.js + 清单
# _slqjs_libs.txt；运行期 lib context 首建时按清单序求值（每库仅一次），
# 块内直接调用其中全局函数——本文件全部用例建立在它之上。
#
# 用例覆盖：① 外部库函数调用（出通道 Int）② string 拼接回传 ③ 无通道
# 纯块（console.log 通路）④ 入通道 int ⑤ JS 侧异常上抛 try-catch 捕获
# ⑥ 同槽复用（库不重复求值——顶层 const 重复声明会 SyntaxError，复用
# 即证明清单只在槽位创建时装载一次）。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员
# 丢失）；块内字符串禁字面 # 字符（replace 目标字符写作 \x23）；块内勿写
# 含 <- 的正则字面量。
# ============================================================================

class JsQuickjsTest
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

    # ---------------- ① 外部库函数调用（出通道 Int：20+22 == 42） ----------------
    # slJsExtraTotal(x) = x + (slJsExtraBase() + 2) = x + 22（外部库内
    # 顶层 const 依赖库自身函数——验证清单按声明序完整求值）。
    static testExternalLibInt()
    {
        Console.println( "===== JsQuickjsTest.testExternalLibInt =====" )
        int total = 0
        @javascript_quickjs()
        {
            let base = slJsExtraBase();
            let sum = slJsExtraTotal(base);
            console.log("jsQuickjs: slJsExtraTotal(slJsExtraBase()) = " + sum);
            $total <- sum;
        }
        Console.println( "external lib int = " + total.toString() )
        check( "external lib: slJsExtraTotal(20) == 42 (base+22)", total == 42 )
    }

    # ---------------- ② string 拼接回传（外部库 + 本地拼接） ----------------
    static testExternalLibString()
    {
        Console.println( "===== JsQuickjsTest.testExternalLibString =====" )
        string banner = ""
        @javascript_quickjs()
        {
            string $banner <- slJsExtraBanner("QuickJS") + "!";
        }
        Console.println( "external lib string = " + banner )
        check( "external lib string: slJsExtraBanner('QuickJS')+'!' == '[QuickJS]!'", banner == "[QuickJS]!" )
    }

    # ---------------- ③ 无通道纯块（外部库计算 + console.log 通路） ----------------
    static testPlainBlock()
    {
        Console.println( "===== JsQuickjsTest.testPlainBlock =====" )
        int keep = 42
        @javascript_quickjs()
        {
            let acc = slJsExtraTotal(20) + slJsExtraBase();
            console.log("plain block: acc = " + acc);
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: executed, outer variable untouched", keep == 42 )
    }

    # ---------------- ④ 入通道 int（外部库函数吃参） ----------------
    static testInChannel()
    {
        Console.println( "===== JsQuickjsTest.testInChannel =====" )
        int n = 10
        @javascript_quickjs()
        {
            long n <- $n
            $n <- slJsExtraTotal(n);
        }
        Console.println( "in channel: n = " + n.toString() )
        check( "in channel: slJsExtraTotal(10) == 32", n == 32 )
    }

    # ---------------- ⑤ JS 侧异常上抛（-105 MANAGED_EXC → try-catch 捕获） ----------------
    static int jsThrow()
    {
        @javascript_quickjs()
        {
            throw new Error("js boom");
        }
        ret 0
    }

    static testThrow()
    {
        Console.println( "===== JsQuickjsTest.testThrow =====" )
        int caught = 0
        label jsThrowBlock
        {
            try jsThrow()
        }
        catch
        {
            caught = 1
        }
        check( "managed-exc: JS throw caught (-105)", caught == 1 )

        # 异常后会话存活：同槽后续块调用不受污染
        int after = 0
        @javascript_quickjs()
        {
            $after <- slJsExtraBase() + 22;
        }
        Console.println( "after-throw = " + after.toString() )
        check( "after-throw session alive: slJsExtraBase()+22 == 42", after == 42 )
    }

    # ---------------- ⑥ 同槽复用（库单次装载回归锁） ----------------
    # 第二个块命中同一 lib 槽位——外部库顶层 const（SL_JS_EXTRA）若被
    # 重复求值会 SyntaxError，本用例通过即证明清单只在槽位创建时装载
    # 一次。第二块 a 经入通道传入（块内标识符须是形参或本地声明——
    # 未声明即引用 SL 变量名会 ReferenceError）。
    static testSlotReuse()
    {
        Console.println( "===== JsQuickjsTest.testSlotReuse =====" )
        int a = 0
        @javascript_quickjs()
        {
            $a <- slJsExtraTotal(0);
        }
        int b = 0
        @javascript_quickjs()
        {
            long a <- $a
            $b <- slJsExtraTotal(a);
        }
        Console.println( "slot reuse: a = " + a.toString() + " b = " + b.toString() )
        check( "slot reuse: lib loaded once, slJsExtraTotal(0) == 22", a == 22 )
        check( "slot reuse: slJsExtraTotal(22) == 44", b == 44 )
    }

    static fun()
    {
        Console.println( "========== JsQuickjsTest start ==========" )
        testExternalLibInt()
        testExternalLibString()
        testPlainBlock()
        testInChannel()
        testThrow()
        testSlotReuse()
        Console.println( "========== JsQuickjsTest end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}
