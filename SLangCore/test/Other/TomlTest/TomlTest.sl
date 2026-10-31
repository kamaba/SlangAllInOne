import Std;
#Toml 测试：BaseToml（Core）表头/点分键/数组表/内联表/多行串/转义/跨行数组解析与序列化往返，
#Text.Toml（Std）文件加载/保存往返，removeKey 结构操作，非法输入失败路径。

TomlTest
{
    static fun()
    {
        Console.println("===== TomlTest start =====")
        testBasic()
        testTables()
        testArrayTables()
        testInline()
        testStrings()
        testRoundTrip()
        testRemoveKey()
        testTomlFile()
        testFailures()
        Console.println("===== TomlTest end =====")
    }

    # 断言辅助：OK/FAIL 单行输出
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[Toml] " + name + " : OK" )
        }
        else
        {
            Console.println( "[Toml] " + name + " : FAIL" )
        }
    }

    # 基础键值对：标量/数字/bool/日期/注释/下划线/进制/类型化取值/默认值
    static testBasic()
    {
        Console.println( "----- testBasic -----" )
        string text = "# 顶部注释\nname = \"alice\"   # 行尾注释\nage = 30\nscore = 95.5\nvip = true\noff = false\nbig = 1_000_000\nhex = 0xFF\nday = 2026-10-31\n"
        BaseToml t = BaseToml( text )
        check( "解析成功非空", t.isNotEmpty )
        check( "成员数 8", t.memberCount == 8 )
        check( "getStr", t.getStr( "name" ) == "alice" )
        check( "getInt", t.getInt( "age" ) == 30 )
        check( "getFloat", t.getFloat( "score" ) == 95.5d )
        check( "getBool true", t.getBool( "vip" ) )
        check( "getBool false", !t.getBool( "off" ) )
        check( "下划线去除", t.getStr( "big" ) == "1000000" )
        check( "下划线 getInt", t.getInt( "big" ) == 1000000 )
        check( "十六进制原文", t.getStr( "hex" ) == "0xFF" )
        check( "日期原文", t.getStr( "day" ) == "2026-10-31" )
        check( "缺失路径默认", t.getStr( "nope", "d" ) == "d" )
        check( "缺失 getInt 默认", t.getInt( "nope", -1 ) == -1 )
        check( "根 isObject", BaseToml.isObject( t.root ) )
        check( "has 命中", t.has( "name" ) )
        check( "has 未命中", !t.has( "zzz" ) )
        check( "findByName", t.findByName( "name" )._value == "alice" )

        # 空实例/静态工厂/clear
        BaseToml empty = BaseToml()
        check( "空实例 isEmpty", empty.isEmpty )
        check( "静态 parse", BaseToml.parse( "a = 1" ).getStr( "a" ) == "1" )
        BaseToml c = BaseToml( "a = 1" )
        c.clear()
        check( "clear 后 isEmpty", c.isEmpty )
    }

    # 表头：[a] / [a.b] 嵌套 / 点分键 / 重复键覆盖
    static testTables()
    {
        Console.println( "----- testTables -----" )
        string text = "[server]\nhost = \"127.0.0.1\"\nport = 8080\n\n[server.auth]\nuser = \"admin\"\nsecret = \"123456\"\n\n[client]\nname = \"app\"\n"
        BaseToml t = BaseToml( text )
        check( "表取值", t.getStr( "server/host" ) == "127.0.0.1" )
        check( "表类型化", t.getInt( "server/port" ) == 8080 )
        check( "嵌套表取值", t.getStr( "server/auth/user" ) == "admin" )
        check( "嵌套表 getInt", t.getInt( "server/auth/secret" ) == 123456 )
        check( "嵌套表 isObject", BaseToml.isObject( t.select( "server/auth" ) ) )
        check( "兄弟表取值", t.getStr( "client/name" ) == "app" )
        check( "根成员数 2", t.memberCount == 2 )

        # 点分键自动建表并共享中间层
        BaseToml dk = BaseToml( "a.b.c = 1\na.b.d = 2\n" )
        check( "点分键取值", dk.getInt( "a/b/c" ) == 1 )
        check( "点分键共享层", dk.getInt( "a/b/d" ) == 2 )
        check( "点分键中间层 isObject", BaseToml.isObject( dk.select( "a/b" ) ) )

        # 重复键后者覆盖
        BaseToml dup = BaseToml( "k = 1\nk = 2\n" )
        check( "重复键覆盖", dup.getInt( "k" ) == 2 )
    }

    # 数组表：[[x]] 多元素 / 空元素 / 嵌套子表挂末元素
    static testArrayTables()
    {
        global.println( "----- testArrayTables -----" )
        string text = "[[products]]\nname = \"hammer\"\nsku = 738594947\n\n[[products]]\n\n[[products]]\nname = \"nail\"\nsku = 284758393\n\n[[products.sub]]\nlevel = 1\n"
        BaseToml t = BaseToml( text )
        check( "数组表 isArray", BaseToml.isArray( t.select( "products" ) ) )
        check( "数组表长度 3", t.select( "products" ).childCount == 3 )
        check( "数组表元素0", t.getStr( "products/0/name" ) == "hammer" )
        check( "数组表元素2", t.getStr( "products/2/name" ) == "nail" )
        check( "数组表元素 getInt", t.getInt( "products/2/sku" ) == 284758393 )
        check( "空元素 isObject", BaseToml.isObject( t.select( "products/1" ) ) )
        check( "嵌套子表挂末元素", t.getInt( "products/2/sub/0/level" ) == 1 )
    }

    # 内联表与数组：单行内联/跨行数组/尾逗号/数组内注释/数组内内联表
    static testInline()
    {
        global.println( "----- testInline -----" )
        string text = "point = { x = 1, y = 2 }\nempty = {}\nnums = [1, 2, 3]\nmixed = [\"a\", 2, true]\n"
        BaseToml t = BaseToml( text )
        check( "内联表 isObject", BaseToml.isObject( t.select( "point" ) ) )
        check( "内联表取值 x", t.getInt( "point/x" ) == 1 )
        check( "内联表取值 y", t.getInt( "point/y" ) == 2 )
        check( "空内联表", BaseToml.isObject( t.select( "empty" ) ) && t.select( "empty" ).childCount == 0 )
        check( "数组 isArray", BaseToml.isArray( t.select( "nums" ) ) )
        check( "数组取值", t.getInt( "nums/2" ) == 3 )
        check( "混合数组字符串", t.getStr( "mixed/0" ) == "a" )
        check( "混合数组 bool", t.getBool( "mixed/2" ) )

        # 跨行数组 + 尾逗号 + 元素内注释
        BaseToml cross = BaseToml( "arr = [\n  1,  # one\n  2,\n  3,\n]\n" )
        check( "跨行数组长度", cross.select( "arr" ).childCount == 3 )
        check( "跨行数组取值", cross.getInt( "arr/1" ) == 2 )

        # 数组内内联表
        BaseToml nested = BaseToml( "items = [ { id = 1 }, { id = 2 } ]\n" )
        check( "数组内内联表", nested.getInt( "items/1/id" ) == 2 )
    }

    # 字符串：转义/unicode/字面串/多行串/行尾续行
    static testStrings()
    {
        Console.println( "----- testStrings -----" )
        string text = "esc = \"a\\tb\\nc\\\"d\\\\e\"\nuni = \"\\u4F60\\u597D\"\nlit = 'C:\\path\\to'\nlitq = '''it's fine'''\nlitq2 = '''a''b'''\nml = \"\"\"\nline1\nline2\"\"\"\ncont = \"\"\"part1\\\npart2\"\"\"\n"
        BaseToml t = BaseToml( text )
        check( "转义序列", t.getStr( "esc" ) == "a\tb\nc\"d\\e" )
        check( "unicode 解码", t.getStr( "uni" ) == "你好" )
        check( "字面串原样", t.getStr( "lit" ) == "C:\\path\\to" )
        check( "字面串单引号转义", t.getStr( "litq" ) == "it's fine" )
        check( "字面串双引号原样", t.getStr( "litq2" ) == "a''b" )
        check( "多行串首换行裁剪", t.getStr( "ml" ) == "line1\nline2" )
        check( "行尾反斜杠续行", t.getStr( "cont" ) == "part1part2" )
    }

    # 序列化往返：精确文本/再解析等价/数组表往返/fromTree 门面
    static testRoundTrip()
    {
        Console.println( "----- testRoundTrip -----" )
        string text = "name = \"alice\"\nage = 30\nvip = true\nrate = 1.5\n[server]\nhost = \"0.0.0.0\"\nport = 8080\n[[items]]\nid = 1\n[[items]]\nid = 2\n"
        BaseToml t = BaseToml( text )
        string out1 = t.toToml()
        string want = "name = \"alice\"\nage = 30\nvip = true\nrate = 1.5\n"
        want = want + "\n[server]\nhost = \"0.0.0.0\"\nport = 8080\n"
        want = want + "\n[[items]]\nid = 1\n\n[[items]]\nid = 2\n"
        check( "toString == toToml", t.toString() == out1 )
        check( "序列化精确文本", out1 == want )

        BaseToml t2 = BaseToml( out1 )
        check( "再解析往返一致", t2.toToml() == out1 )
        check( "往返取值 name", t2.getStr( "name" ) == "alice" )
        check( "往返取值 port", t2.getInt( "server/port" ) == 8080 )
        check( "往返数组表", t2.getInt( "items/1/id" ) == 2 )

        # fromTree 门面：树根挂键值后可直接序列化
        var tt = BaseToml.parse( "" ).tree
        tt.addRoot( "wrap" )
        BaseToml f = BaseToml.fromTree( tt )
        check( "fromTree 根", f.root != null )
        tt.root.addChild( "k", "v" )
        check( "fromTree 序列化", f.toToml() == "k = \"v\"\n" )
    }

    # removeKey：标量/子表/不存在路径，删除后序列化再解析
    static testRemoveKey()
    {
        Console.println( "----- testRemoveKey -----" )
        string text = "keep = 1\ndrop = 2\n[server]\nhost = \"h\"\nport = 1\n[server.extra]\nx = 9\n"
        BaseToml t = BaseToml( text )
        check( "removeKey 标量", t.removeKey( "drop" ) )
        check( "removeKey 后无", !t.has( "drop" ) )
        check( "removeKey 子表", t.removeKey( "server/extra" ) )
        check( "removeKey 子表后无", !t.has( "server/extra" ) )
        check( "removeKey 不存在", !t.removeKey( "nope" ) )

        BaseToml t2 = BaseToml( t.toToml() )
        check( "删除后往返 keep", t2.getInt( "keep" ) == 1 )
        check( "删除后往返 host", t2.getStr( "server/host" ) == "h" )
        check( "删除后无 extra", !t2.has( "server/extra" ) )
    }

    # Text.Toml（Std）：saveAs -> load 往返 -> reload/save -> 失败路径
    static testTomlFile()
    {
        Console.println( "----- testTomlFile -----" )
        string path = "toml_test_out.toml"

        var tf = Text.Toml( "name = \"toml\"\nport = 9999\n[server]\nhost = \"h\"\n" )
        check( "saveAs", tf.saveAs( path ) )
        check( "path 记录", tf.path == path )
        check( "fileExists", tf.fileExists )
        check( "fileSize > 0", tf.fileSize() > 0 )

        Text.Toml loaded = Text.Toml.load( path )
        check( "load 非空", loaded.select( "name" ) != null )
        check( "load 取值", loaded.getStr( "name" ) == "toml" )
        check( "load 类型化", loaded.getInt( "port" ) == 9999 )
        check( "load 表取值", loaded.getStr( "server/host" ) == "h" )

        check( "reload", loaded.reload() )
        check( "save", loaded.save() )

        # 失败路径
        Text.Toml miss = Text.Toml.load( "no_such_toml_file.toml" )
        check( "缺失文件空实例", miss.select( "name" ) == null )
        check( "readFrom 缺失文件", !loaded.readFrom( "no_such_toml_file.toml" ) )
        check( "save 未关联路径", !miss.save() )
    }

    # 非法输入：解析失败返回空实例且 parseText 保持原树
    static testFailures()
    {
        Console.println( "----- testFailures -----" )
        BaseToml e1 = BaseToml( "" )
        check( "空文本", e1.isEmpty )
        BaseToml e2 = BaseToml( null )
        check( "null 文本", e2.isEmpty )

        BaseToml f1 = BaseToml( "= 1\n" )
        check( "缺键名非法", f1.isEmpty )
        BaseToml f2 = BaseToml( "a = \n" )
        check( "缺值非法", f2.isEmpty )
        BaseToml f3 = BaseToml( "a = \"unclosed\n" )
        check( "未闭合基本串", f3.isEmpty )
        BaseToml f4 = BaseToml( "[unclosed\n" )
        check( "未闭合表头", f4.isEmpty )
        BaseToml f5 = BaseToml( "a = [1, 2\n" )
        check( "未闭合数组", f5.isEmpty )

        # parseText 失败不清空原内容
        BaseToml keep = BaseToml( "k = \"v\"\n" )
        bool kept = !keep.parseText( "a = [" ) && keep.getStr( "k" ) == "v"
        check( "parseText 失败保持原树", kept )
    }
}
