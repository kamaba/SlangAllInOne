import Std;
import Core;

# ============================================================================
# GoTest — golang 插件端到端测试（蓝本 = PythonTest.sl）
#
# 链路：@golang(){} 块 → Front 哨兵脱糖 CallAtSignLabel(124) → 导出期
# PluginManager 转调插件 frontend（parse 生成 Entry_N.go 的 func
# Entry_N_run 源码 + build 组装临时目录 go build -trimpath 出自包含
# SLGoHost.exe 部署 libDir\go\）→ CVM 经模块 atSignLabel[] 绑定懒 resolve
# 到 sl_golang labelExec → go_bridge（keep-alive SLGoHost.exe 子进程 +
# 行分隔 JSON stdio 协议 + registry 查表派发 + panic recover 转 err 事件）
# → 出通道五态（nil/bool·int/float/string/object 树）编组回推。
#
# 通道类型路由（map_go_type 五通道，Go 域 Boolean 放行——python 域同口径）：
# 整型族 → int64（方法规格 J，JSON 整数 int64 全域精确）、浮点族 → float64
#（D）、String 族 → string（S）；Boolean 族 → bool（B，Go 原生 bool，编组
# JSON true/false、SL 侧 INT 0|1）；Object/SL 类名 → plain object 树镜像
#（O，__sltype__ 键携带 SL 类名，读写双向递归，深度上限 32 同步）。
# entryMethod 完整规格 "run:(JDBO)J"（返回段 V/J/D/S/O——出通道 Boolean
# 拒收：Front MapChannelOutKind 把 Boolean 落 Object 坏路径，Go 返回
# bool 走缺省 int 出通道，块内显式转 int64）。
#
# 用法覆盖：① 无通道纯块 ② 出通道 Int ③ 入+出通道 String ④ 块内 panic
# 上抛 SL 异常 try-catch 捕获；附加：int64 全域往返、double 通道、bool
# 通道（Go 域放行）、三类型混合入通道、OBJECT 树往返、异常后子进程会话
# 存活（panic 已 recover 为 err 事件，不破坏协议管道/registry）、
# 块首 import 提升与外部源码文件合并编译（2026-11-28）。
# 前置：编译机 Go 1.22+（go.exe 在 PATH 或 SLANG_GO_EXE/GOROOT 覆盖，或
# plugin.jsonc goExe 手动指定——SLGoHost.exe 编译期产物内嵌 Go 运行时，
# 运行机器零 Go 依赖）。
# 注意：本文件 SL 层禁用行内注释（Lexer 单行 # 注释会吞换行，导致成员
# 丢失）。块体为 Go 函数体（func Entry_N_run）：块首（入通道行之后、首条
# 代码行之前）可写单行 import——非预置标准库（encoding/binary 等）、外部
# 模块（github.com/xxx，构建器 go build -mod=mod 自动解析 go.mod 依赖，
# 需联网 GOPROXY）、副作用空导入（import _ "..."）均提升到生成文件顶部；
# 预置包 fmt/math/os/regexp/sort/strconv/strings/time 已可直接使用（块首
# 裸 import 同名包自动去重跳过，带别名保留）；多行 import 组不支持（块首
# 须单行）；中段 import 报错（位置铁律）。外部 .go 文件不经 import——
# jsonc plugins.golang.sources 声明（本工程 GoCode/SlGoExtraUtil.go，
# package main 同包直调，见 testExternalSource）；块内勿遮蔽预置包名；
# <- 是 Go 原生 channel 接收操作符，块体内合法；for/if 的
# 起始 { 必须与子句同行（Go 语法硬约束，不能 SL 换行花括号风格）。
# ============================================================================

# OBJECT 树镜像往返载体：普通 SL 类，两 int 字段（镜像 PyPoint）
class GoPoint
{
    int x = 0
    int y = 0
}

class GoTest
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

    # ---------------- ① 无通道纯块（副作用型，fmt.Println 经 console 事件转发宿主 stdout） ----------------
    # 无入无出 → func Entry_N_run(){} 直接执行；块内局部计算不影响 SL 侧变量。
    static testPlainBlock()
    {
        Console.println( "===== GoTest.testPlainBlock =====" )
        int keep = 42
        @golang()
        {
            inner := 6 * 7
            fmt.Println( "hello from Go (plain block), inner =", inner )
        }
        Console.println( "keep = " + keep.toString() )
        check( "plain block: run() executed, outer variable untouched", keep == 42 )
    }

    # ---------------- ② 出通道 Int（块内 for 求和 1..10 → 55） ----------------
    # 出通道缺省类型标记 → int64；SL 侧 int 变量回写。
    static testIntOutChannel()
    {
        Console.println( "===== GoTest.testIntOutChannel =====" )
        int count = 0
        @golang()
        {
            total := int64(0)
            for i := int64(1); i <= 10; i++ {
                total += i
            }
            $count <- total;
        }
        Console.println( "sum(1..10) = " + count.toString() )
        check( "int out channel: sum 1..10 == 55", count == 55 )
    }

    # ---------------- int64 全域往返（无窄化决策回归锁） ----------------
    # 4000000000 超 int32 max（2147483647）——若链路误走 32 位窄化会回绕为负；
    # JSON 整数经 yyjson/UseNumber 双侧 int64 全域精确。
    static testInt64Roundtrip()
    {
        Console.println( "===== GoTest.testInt64Roundtrip =====" )
        long big = 4000000000
        long halfVal = 0
        @golang()
        {
            long big <- $big
            $halfVal <- big / 2;
        }
        Console.println( "4000000000 / 2 = " + halfVal.toString() )
        check( "int64 full range: 4000000000 / 2 == 2000000000 (no narrowing)", halfVal == 2000000000 )
    }

    # ---------------- double 入+出通道（math.Sqrt 3-4-5 三角 → 5.0） ----------------
    # 浮点族 → float64（规格 D）；math 为预置 import。
    static testDoubleRoundtrip()
    {
        Console.println( "===== GoTest.testDoubleRoundtrip =====" )
        double a = 3.0
        double b = 4.0
        double hyp = 0.0
        @golang()
        {
            double a <- $a
            double b <- $b
            double $hyp <- math.Sqrt( a * a + b * b );
        }
        Console.println( "hypot(3,4) = " + hyp.toString() )
        check( "double channels: math.Sqrt(3*3+4*4) == 5.0", hyp == 5.0 )
    }

    # ---------------- ③ 入+出通道 String（拼接回传） ----------------
    # String 入通道（JSON string）+ string 出通道（深拷贝 host->alloc 回推）。
    static testStringRoundtrip()
    {
        Console.println( "===== GoTest.testStringRoundtrip =====" )
        string name = "SimpleLanguage"
        string slogan = ""
        @golang()
        {
            string name <- $name
            string $slogan <- "Hello, " + name + "!";
        }
        Console.println( "slogan = " + slogan )
        check( "string channels: roundtrip == 'Hello, SimpleLanguage!'", slogan == "Hello, SimpleLanguage!" )
    }

    # ---------------- bool 入通道（Go 原生 bool 放行，规格 B） ----------------
    # Boolean 入通道编组 JSON true → Go bool 实参；出通道走缺省 int（Go 静态
    # 类型须显式转 int64——出通道 Boolean 拒收，python 先例口径）。
    static testBoolChannel()
    {
        Console.println( "===== GoTest.testBoolChannel =====" )
        bool flag = true
        int flipped = 1
        @golang()
        {
            bool flag <- $flag
            rev := int64(1)
            if flag {
                rev = 0
            }
            $flipped <- rev;
        }
        Console.println( "not True = " + flipped.toString() )
        check( "bool channel: not True == False (0)", flipped == 0 )
    }

    # ---------------- 三类型混合入通道（int + double + string 同块） ----------------
    # 生成形参 run(base int64, w float64, s string)；target 形参名与 SL 变量名分离。
    static testMixedChannels()
    {
        Console.println( "===== GoTest.testMixedChannels =====" )
        int n = 0
        double weight = 2.5
        string name = "CPython"
        @golang()
        {
            int base <- $n
            double w <- $weight
            string s <- $name
            $n <- base + int64( w * 10.0 ) + int64( len( s ) );
        }
        Console.println( "mixed = " + n.toString() )
        check( "mixed channels: 0 + int64(2.5*10) + len('CPython') == 32", n == 32 )
    }

    # ---------------- ④ 异常上抛（块内 panic → GO_PANIC -105 → try-catch 捕获） ----------------
    # Go panic 经驱动 recover 转 err kind=go 事件 → go_bridge 组 "(go) ..." 文本
    #（throw_error -105）→ VM 异常 → SL try-catch 捕获。
    static int goThrow()
    {
        @golang()
        {
            panic( "boom" )
        }
        ret 0
    }

    static testThrow()
    {
        Console.println( "===== GoTest.testThrow =====" )
        int caught = 0
        label goThrowBlock
        {
            try goThrow()
        }
        catch
        {
            caught = 1
        }
        check( "go-panic: caught (GO_PANIC -105)", caught == 1 )

        # 异常后子进程会话存活（panic 已 recover，协议管道未被破坏，
        # registry 与 keep-alive 子进程继续可用）
        int after = 0
        @golang()
        {
            $after <- 20 + 22;
        }
        Console.println( "after-throw = " + after.toString() )
        check( "after-throw session alive: 20+22 == 42", after == 42 )
    }

    # ---------------- 会话复用（keep-alive 子进程跨块复用） ----------------
    # 块间值经 SL 变量接力；每块独立 Entry_N 编进同一 SLGoHost.exe。
    static testSessionReuse()
    {
        Console.println( "===== GoTest.testSessionReuse =====" )
        int a = 0
        int b = 0
        @golang()
        {
            $a <- 40 + 2;
        }
        @golang()
        {
            int a <- $a
            $b <- a * 1;
        }
        Console.println( "reuse: a = " + a.toString() + " b = " + b.toString() )
        check( "session reuse: block1 40+2 == 42", a == 42 )
        check( "session reuse: block2 in+out echo == 42 (same host process)", b == 42 )
    }

    # ---------------- ⑤ OBJECT 树镜像往返（map 树 + __sltype__） ----------------
    # 入通道 SL 类名标记（GoPoint pv <- $p）→ sl_atsign_marshal_object 递归
    # 编组 SLLabelObject 树 → JSON plain object（__sltype__ + 字段名键）→ Go
    # map[string]any（数值已归一 int64）；出通道 map 带 __sltype__ → C 侧
    # 按树重建 GoPoint 实例（同名同型字段逐个回填）压 $q；深度上限 32 双向对称。
    static testObjectTree()
    {
        Console.println( "===== GoTest.testObjectTree =====" )
        GoPoint p = GoPoint()
        p.x = 3
        p.y = 4
        GoPoint q = GoPoint()
        @golang()
        {
            GoPoint pv <- $p
            m := pv.(map[string]any)
            sx := m["x"].(int64)
            sy := m["y"].(int64)
            GoPoint $q <- map[string]any{ "__sltype__": "GoPoint", "x": sx + sy, "y": sx * sy };
        }
        Console.println( "objectTree: q.x = " + q.x.toString() + " q.y = " + q.y.toString() )
        check( "object tree: rebuilt q.x == 7 (3+4)", q.x == 7 )
        check( "object tree: rebuilt q.y == 12 (3*4)", q.y == 12 )
    }

    # ---------------- ⑥ 块首 import 提升（2026-11-28：非预置标准库 + 预置去重） ----------------
    # 块首（入通道行之后、首条代码行之前）单行 import 收集后提升到生成文件
    # 顶部区。encoding/binary 非预置 → 提升后块内直用；import "fmt" 与预置
    # 组重复 → 裸导入自动去重跳过（带别名形态保留，Go 允许同包多名导入）。
    # 外部模块（github.com/xxx）同写法，构建器检测后 go build -mod=mod
    # 自动解析 go.mod 依赖（需联网 GOPROXY，离线跑不了网络依赖，本用例
    # 仅覆盖标准库形态）。
    static testBlockHeadImport()
    {
        Console.println( "===== GoTest.testBlockHeadImport =====" )
        int n = 0
        @golang()
        {
            import "encoding/binary"
            import "fmt"

            buf := make([]byte, 4)
            binary.LittleEndian.PutUint32(buf, 300)
            n64 := int64(binary.LittleEndian.Uint32(buf))
            fmt.Println("le-roundtrip inner =", n64)
            $n <- n64;
        }
        Console.println( "le-roundtrip = " + n.toString() )
        check( "block-head import: encoding/binary promoted, 300 == 300", n == 300 )
    }

    # ---------------- ⑦ 外部源码文件合并编译（jsonc plugins.golang.sources） ----------------
    # GoCode/SlGoExtraUtil.go（package main）经 sources 下发，构建器与条目
    # 同目录合并编译——Go 按目录整包收录，同包直调无需 import（对照 java
    # 域 SLAtSign 同包口径）；外部文件可自带 import 区（GoExtraRepeat 用
    # strings，strings 虽是条目预置包但逐文件解析互不冲突）。
    static testExternalSource()
    {
        Console.println( "===== GoTest.testExternalSource =====" )
        int m = 0
        string s = ""
        @golang()
        {
            $m <- GoExtraMul( 6, 7 );
        }
        @golang()
        {
            string $s <- GoExtraRepeat( "ab", 3 );
        }
        Console.println( "external-source: m = " + m.toString() + " s = " + s )
        check( "external source: GoExtraMul(6,7) == 42", m == 42 )
        check( "external source: GoExtraRepeat('ab',3) == 'ababab'", s == "ababab" )
    }

    static fun()
    {
        Console.println( "========== GoTest start ==========" )
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
        testBlockHeadImport()
        testExternalSource()
        Console.println( "========== GoTest end: passed=" + passed.toString() + " failed=" + failed.toString() + " ==========" )
    }
}
