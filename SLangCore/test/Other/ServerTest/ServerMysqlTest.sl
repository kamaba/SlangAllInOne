import Std;
import Core;
import SLangServer;
import SLangMysql;

# ============================================================================
# ServerMysqlTest.sl -- SLangServer × SLangMysql 集成验收（ServerTest 宿主）
# HTTP 路由 handler 内执行 MySQL 查询（SERVER_DESIGN.md §8 验收矩阵）：
#
#   T1  GET /users：handler 内自开连接 → cursor.execute(SELECT) →
#       fetchone 循环取行 → 行数据拼进 res.text，经原始 HTTP 客户端往返断言
#       （列数 / 行数 / 行内容）
#   T2  GET /user/{name}：req.pathParam 路径参数 → ? 参数绑定（Tuple）
#       → fetchone 单行返回；未命中 → 404
#
# 降级模式（MysqlTest 同款）：clientVersion() <= 0 说明 sl_mysql_lib.dll
# 未静态预载（SL 兜底函数体生效）；connect 返回 null 说明连不上 MySQL
# 服务器——两种情况均打印 skip 提前返回，不产生环境依赖 FAIL。
#
# SLangMysql 的类都在 namespace SLang 下，故统一用 SLang.xxx 全名访问。
# 连接参数来自 ServerTest.jsonc 的 "data" 段，按 global.<name> 读取
# （handler 闭包内不经捕获，全部走 global.* 直读）。
# 端口：19511（P10=19501-19502 之后顺延，段位 = Mysql）。
# 编写约定同 ServerP10Test.sl（原始 HTTP 客户端助手同款实现）。
# ============================================================================

ServerMysqlTest
{
    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "[ServerMysqlTest] " + name + " : OK" )
        }
        else
        {
            Console.println( "[ServerMysqlTest] " + name + " : FAIL" )
        }
    }

    # 调试：失败时打印实际响应（P10 dump 同款，排障保留）
    static void dump( string tag, string text )
    {
        Console.println( "[ServerMysqlTest] DUMP " + tag + " >>> " + text )
    }

    # ── 通用助手（ServerP10Test 同款）──

    static Int32 sfFind( string text, string sub )
    {
        Int32 tlen = SystemStringLength( text )
        Int32 slen = SystemStringLength( sub )
        if slen == 0
        {
            ret 0
        }

        if tlen < slen
        {
            ret -1
        }

        Int32 last = tlen - slen
        for Int32 i = 0, i <= last, i = i + 1
        {
            bool matched = true
            for Int32 j = 0, j < slen, j = j + 1
            {
                if SystemStringCharCodeAt( text, i + j ) != SystemStringCharCodeAt( sub, j )
                {
                    matched = false
                    break
                }
            }

            if matched
            {
                ret i
            }
        }
        ret -1
    }

    static string rawReq( Int32 port, string reqText ) throws
    {
        PMysqlRawClient c = PMysqlRawClient.connect( port )
        c.send( reqText )
        PMysqlResp r = c.readResp()
        c.close()
        ret r._head + "\n" + r._body
    }

    # 十六进制串 → Int32（chunk size 行解析；非法返回 -1）
    static Int32 pmHex( string s )
    {
        Int32 len = SystemStringLength( s )
        if len == 0
        {
            ret -1
        }

        Int32 v = 0
        for Int32 i = 0, i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            Int32 d = -1
            if c >= 48 && c <= 57
            {
                d = c - 48
            }
            elif c >= 97 && c <= 102
            {
                d = c - 87
            }
            elif c >= 65 && c <= 70
            {
                d = c - 55
            }

            if d < 0
            {
                ret -1
            }
            v = v * 16 + d
        }
        ret v
    }

    # 头区提取整数头（如 Content-Length；未找到 -1）
    static Int32 pmHeadInt( string head, string name )
    {
        Int32 pos = ServerMysqlTest.sfFind( head, name )
        if pos < 0
        {
            ret -1
        }

        Int32 len = SystemStringLength( head )
        Int32 v = 0
        bool any = false
        for Int32 i = pos + SystemStringLength( name ), i < len, i = i + 1
        {
            Int32 c = SystemStringCharCodeAt( head, i )
            if c < 48 || c > 57
            {
                break
            }
            v = v * 10 + ( c - 48 )
            any = true
        }

        if any == false
        {
            ret -1
        }
        ret v
    }

    # ── MySQL 助手（MysqlTest 同款）──

    static SLang.MysqlConnection connectTo( string db )
    {
        ret SLang.Mysql.connect( global.mysqlHost, global.mysqlUser, global.mysqlPassword, db, global.mysqlPort, global.mysqlCharset )
    }

    # 前置：建测试库 / 建表 / 插 3 行（alice / bob / carol）
    static bool prepare()
    {
        SLang.MysqlConnection conn = ServerMysqlTest.connectTo( global.mysqlDatabase )
        if conn == null
        {
            ret false
        }
        string testdb = global.mysqlTestDb
        SLang.MysqlCursor cur = conn.cursor()
        cur.execute( "DROP DATABASE IF EXISTS " + testdb )
        cur.execute( "CREATE DATABASE " + testdb + " DEFAULT CHARACTER SET utf8mb4" )
        bool sw = conn.selectDatabase( testdb )
        if sw == false
        {
            cur.close()
            conn.close()
            ret false
        }

        string ddl = "CREATE TABLE user ("
        ddl = ddl + " id INT NOT NULL AUTO_INCREMENT,"
        ddl = ddl + " name VARCHAR(64) NOT NULL,"
        ddl = ddl + " age INT DEFAULT 0,"
        ddl = ddl + " email VARCHAR(128) NULL,"
        ddl = ddl + " PRIMARY KEY (id)"
        ddl = ddl + " ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        cur.execute( ddl )

        cur.execute( "INSERT INTO user (name, age, email) VALUES (?, ?, ?)", Tuple( "alice", 18, "alice@test.com" ) )
        cur.execute( "INSERT INTO user (name, age, email) VALUES (?, ?, ?)", Tuple( "bob", 20, "bob@test.com" ) )
        cur.execute( "INSERT INTO user (name, age, email) VALUES (?, ?, ?)", Tuple( "carol", 22, "carol@test.com" ) )

        bool ok = conn.errorCode() == 0
        cur.close()
        conn.close()
        ServerMysqlTest.check( "T0c 准备测试库/表 + 插入 3 行", ok )
        ret ok
    }

    # ── T1 GET /users：handler 内 SELECT 查询 ──

    static void t1SelectInHandler()
    {
        Console.println( "[ServerMysqlTest] T1 begin (port 19511)" )
        SLang.HttpServer app = SLang.HttpServer( 19511 )
        app.reset()

        function hUsers = function( SLang.Request req, SLang.Response res )
        {
            # handler 内自开连接（参数全部走 global.*，不经闭包捕获）
            SLang.MysqlConnection c = SLang.Mysql.connect( global.mysqlHost, global.mysqlUser, global.mysqlPassword, global.mysqlTestDb, global.mysqlPort, global.mysqlCharset )
            if c == null
            {
                res.status( 500 ).text( "mysql connect failed" )
            }
            else
            {
                SLang.MysqlCursor cur = c.cursor()
                cur.execute( "SELECT id, name, age, email FROM user ORDER BY id" )
                Int32 cols = cur.columnCount()
                Int32 n = 0
                string outText = "cols=" + cols.toString()
                SLang.MysqlRow row = cur.fetchone()
                while row != null
                {
                    # 先拆局部——字符串续链混方法调用 Front 解析坑（P10 T4 注记同款）
                    string nm = row.getString( 1 )
                    string age = row.getString( 2 )
                    string mail = row.getString( 3 )
                    outText = outText + ";" + nm + "," + age + "," + mail
                    n = n + 1
                    row = cur.fetchone()
                }
                outText = outText + ";rows=" + n.toString()
                cur.close()
                c.close()
                res.text( outText )
            }
        }
        app.onGet( "/users", hUsers )
        app.start( 19511 )

        string r = ServerMysqlTest.rawReq( 19511, "GET /users HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerMysqlTest.dump( "T1", r )
        ServerMysqlTest.check( "T1a handler 内 SELECT columnCount（cols=4）",
            ServerMysqlTest.sfFind( r, "cols=4" ) >= 0 )
        ServerMysqlTest.check( "T1b 查询行数（rows=3）",
            ServerMysqlTest.sfFind( r, ";rows=3" ) >= 0 )
        ServerMysqlTest.check( "T1c 行数据经 HTTP 往返（alice/bob/carol 三行）",
            ServerMysqlTest.sfFind( r, "alice,18,alice@test.com" ) >= 0
            && ServerMysqlTest.sfFind( r, "bob,20,bob@test.com" ) >= 0
            && ServerMysqlTest.sfFind( r, "carol,22,carol@test.com" ) >= 0 )

        app.stop()
    }

    # ── T2 GET /user/{name}：路径参数 → ? 绑定 → fetchone ──

    static void t2ParamBindQuery()
    {
        Console.println( "[ServerMysqlTest] T2 begin (port 19511)" )
        SLang.HttpServer app = SLang.HttpServer( 19511 )
        app.reset()

        function hUserByName = function( SLang.Request req, SLang.Response res )
        {
            # 路径参数 → ? 参数绑定（预编译防注入语义），fetchone 单行
            string uname = req.pathParam( "name" )
            SLang.MysqlConnection c = SLang.Mysql.connect( global.mysqlHost, global.mysqlUser, global.mysqlPassword, global.mysqlTestDb, global.mysqlPort, global.mysqlCharset )
            if c == null
            {
                res.status( 500 ).text( "mysql connect failed" )
            }
            else
            {
                SLang.MysqlCursor cur = c.cursor()
                cur.execute( "SELECT id, name, age, email FROM user WHERE name = ?", Tuple( uname ) )
                SLang.MysqlRow row = cur.fetchone()
                string rid = ""
                string rname = ""
                string rage = ""
                string remail = ""
                bool found = false
                if row != null
                {
                    found = true
                    rid = row.getString( 0 )
                    rname = row.getString( 1 )
                    rage = row.getString( 2 )
                    remail = row.getString( 3 )
                }
                cur.close()
                c.close()
                if found
                {
                    res.text( "id=" + rid + ";name=" + rname + ";age=" + rage + ";email=" + remail )
                }
                else
                {
                    res.status( 404 ).text( "not found" )
                }
            }
        }
        app.onGet( "/user/{name}", hUserByName )
        app.start( 19511 )

        string r1 = ServerMysqlTest.rawReq( 19511, "GET /user/bob HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerMysqlTest.dump( "T2-bob", r1 )
        ServerMysqlTest.check( "T2a 路径参数 + ? 绑定 + fetchone（bob 行完整返回）",
            ServerMysqlTest.sfFind( r1, "id=2;name=bob;age=20;email=bob@test.com" ) >= 0 )

        string r2 = ServerMysqlTest.rawReq( 19511, "GET /user/nosuch HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" )
        ServerMysqlTest.dump( "T2-nosuch", r2 )
        ServerMysqlTest.check( "T2b 未命中行 → 404 not found",
            ServerMysqlTest.sfFind( r2, "404" ) >= 0
            && ServerMysqlTest.sfFind( r2, "not found" ) >= 0 )

        app.stop()
    }

    # 清理：DROP 测试库
    static void cleanup()
    {
        SLang.MysqlConnection conn = ServerMysqlTest.connectTo( global.mysqlDatabase )
        if conn == null
        {
            ret
        }
        string testdb = global.mysqlTestDb
        SLang.MysqlCursor cur = conn.cursor()
        cur.execute( "DROP DATABASE IF EXISTS " + testdb )
        bool ok = conn.errorCode() == 0
        cur.close()
        conn.close()
        ServerMysqlTest.check( "TC1 清理测试库（DROP DATABASE " + testdb + "）", ok )
    }

    static fun()
    {
        # ── T0 前置：原生层 + 连接 + 数据准备（降级短路）──
        Console.println( "[ServerMysqlTest] T0 begin (precheck)" )
        Int64 ver = SLang.Mysql.clientVersion()
        ServerMysqlTest.check( "T0a clientVersion > 0（DLL 静态预载，非 SL 兜底）", ver > 0 )
        if ver <= 0
        {
            string verText = ver.toString()
            Console.println( "[ServerMysqlTest] skip：sl_mysql_lib.dll 未静态预载（clientVersion=" + verText + "），其余用例跳过" )
            ret
        }

        SLang.MysqlConnection probe = ServerMysqlTest.connectTo( global.mysqlDatabase )
        ServerMysqlTest.check( "T0b 连接 MySQL 服务器", probe != null )
        if probe == null
        {
            Console.println( "[ServerMysqlTest] skip：无法连接 MySQL 服务器，其余用例跳过" )
            ret
        }
        probe.close()

        if ServerMysqlTest.prepare() == false
        {
            Console.println( "[ServerMysqlTest] skip：测试库准备失败，其余用例跳过" )
            ret
        }

        label t1
        {
            ServerMysqlTest.t1SelectInHandler()
        }
        catch
        {
            Console.println( "[ServerMysqlTest] T1 异常" )
        }
        label t2
        {
            ServerMysqlTest.t2ParamBindQuery()
        }
        catch
        {
            Console.println( "[ServerMysqlTest] T2 异常" )
        }
        label tc
        {
            ServerMysqlTest.cleanup()
        }
        catch
        {
            Console.println( "[ServerMysqlTest] cleanup 异常" )
        }
        Console.println( "[ServerMysqlTest] all done" )
    }
}

# ============================================================================
# PMysqlResp -- 响应解析结果（P10Resp 同款）
# ============================================================================
class PMysqlResp
{
    bool _ok = false
    bool _chunked = false
    string _head = ""
    string _body = ""

    _init_()
    {
        this._ok = false
        this._chunked = false
        this._head = ""
        this._body = ""
    }
}

# ============================================================================
# PMysqlRawClient -- 原始 HTTP 测试客户端（P10RawClient 同款）
# 引用改名：ServerP10Test.sfFind→ServerMysqlTest.sfFind、p10Hex→pmHex、
#           p10HeadInt→pmHeadInt、P10RawClient→PMysqlRawClient、P10Resp→PMysqlResp
# ============================================================================
class PMysqlRawClient
{
    Net.TcpStream c = null
    string rtext = ""

    _init_()
    {
        this.c = null
        this.rtext = ""
    }

    static PMysqlRawClient connect( Int32 port ) throws
    {
        PMysqlRawClient rc = PMysqlRawClient()
        rc.c = Net.Tcp.connect( "127.0.0.1", port )
        rc.rtext = ""
        ret rc
    }

    void send( string text ) throws
    {
        ByteBuffer b = ByteBuffer.fromString( text )
        this.c.write( b )
        b.release()
    }

    # 读一行（不含行尾；EOF 无行返回 null）
    string readLine() throws
    {
        Int32 pos = ServerMysqlTest.sfFind( this.rtext, "\n" )
        while pos < 0
        {
            ByteBuffer b = ByteBuffer( 1024 )
            Int32 n = this.c.read( b )
            if n == 0
            {
                ret null
            }
            this.rtext = this.rtext + b.readString( n )
            pos = ServerMysqlTest.sfFind( this.rtext, "\n" )
        }
        Int32 cut = pos
        if cut > 0 && SystemStringCharCodeAt( this.rtext, cut - 1 ) == 13
        {
            cut = cut - 1
        }
        string line = SystemStringRange( this.rtext, 0, cut )
        this.rtext = SystemStringRange( this.rtext, pos + 1, SystemStringLength( this.rtext ) )
        ret line
    }

    # 读 n 字节（文本安全：测试数据无内嵌 NUL）
    string readN( Int32 n ) throws
    {
        while SystemStringLength( this.rtext ) < n
        {
            ByteBuffer b = ByteBuffer( 8192 )
            Int32 got = this.c.read( b )
            if got == 0
            {
                break
            }
            this.rtext = this.rtext + b.readString( got )
        }
        Int32 have = SystemStringLength( this.rtext )
        Int32 take = n
        if have < take
        {
            take = have
        }
        string part = SystemStringRange( this.rtext, 0, take )
        this.rtext = SystemStringRange( this.rtext, take, have )
        ret part
    }

    # 读完整响应（Content-Length 定长 / chunked / EOF 截止）
    PMysqlResp readResp() throws
    {
        PMysqlResp r = PMysqlResp()
        string head = ""
        bool headDone = false
        while headDone == false
        {
            string line = this.readLine()
            if line == null
            {
                ret r
            }

            if SystemStringLength( line ) == 0
            {
                headDone = true
            }
            else
            {
                head = head + line + "\n"
            }
        }
        r._head = head
        r._ok = true
        if ServerMysqlTest.sfFind( head, "Transfer-Encoding: chunked" ) >= 0
        {
            r._chunked = true
            string body = ""
            bool bodyDone = false
            while bodyDone == false
            {
                string sizeLine = this.readLine()
                if sizeLine == null
                {
                    bodyDone = true
                }
                else
                {
                    Int32 sz = ServerMysqlTest.pmHex( sizeLine )
                    if sz == 0
                    {
                        this.readLine()
                        bodyDone = true
                    }
                    else
                    {
                        body = body + this.readN( sz )
                        this.readLine()
                    }
                }
            }
            r._body = body
            ret r
        }
        Int32 cl = ServerMysqlTest.pmHeadInt( head, "Content-Length: " )
        if cl >= 0
        {
            r._body = this.readN( cl )
            ret r
        }
        # 无长度 → EOF 截止
        string all = ""
        while true
        {
            string part = this.readN( 8192 )
            if SystemStringLength( part ) == 0
            {
                break
            }
            all = all + part
        }
        r._body = all
        ret r
    }

    void close()
    {
        if this.c != null
        {
            label cl
            {
                this.c.close()
            }
            catch { }
            this.c = null
        }
    }
}
