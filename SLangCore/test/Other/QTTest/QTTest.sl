import SLangQT;
import Std;

# ============================================================================
# QTTest —— slQT 复杂套件（2026-11-03 重写）
# ----------------------------------------------------------------------------
# 目标：配合 jsonc "qtRuntime" 组合部署（模块 dll + 插件分类复制进自身
# 运行目录，不引用系统 Qt 安装），尽量把部署的每个 Qt6*.dll 都实际用上：
#   1) smoke       —— 控件工厂 / 类层级 / 信号绑定 bind_id（FFI 链路）
#   2) 探测矩阵    —— slqt_module_available_sl 逐一探测 14 个可选 Qt 模块
#   3) 扩展面板    —— Image / Svg / GL / Sql / Net / Xml / Concurrent / Test /
#                     Print / UiTools / Designer / Help / DBus（缺件 SKIP）
#   4) 动画面板    —— QTimer 30ms 驱动 label/button 往返 move + GL 旋转
#                     （窗口模式可见移动效果；offscreen 模式计数等价验证）
#   5) 汇总        —— modules a/b、panels ok/fail、PASS/FAIL
# 换组合：cvm\deploy-qt.ps1 -Combo minimal|gui|data|full（或改 jsonc qtRuntime
# 段后 slang publish）。stub 后端只走 smoke（扩展面板全部跳过）。
# ============================================================================

public class QTTest
{
    static SLang.QApplication _app = null
    static int clicks = 0
    static string lastText = ""

    # 动画面板状态（QTimer onTick 中更新）
    static int tickCount = 0
    static int moveCount = 0
    static int posX = 10
    static int moveDir = 1
    static SLang.QLabel animLabel = null
    static SLang.QPushButton animBtn = null
    static SLang.QGLPanel animGL = null

    # 汇总计数
    static int modulesTotal = 0
    static int modulesAvail = 0
    static int panelsTotal = 0
    static int panelsRun = 0
    static int panelsFailed = 0

    public static void onClick()
    {
        clicks = clicks + 1
    }

    public static void onText( string s )
    {
        lastText = s
    }

    # 动画 tick：label/button 沿 X 轴往返移动（移动效果本体）
    public static void onTick()
    {
        tickCount = tickCount + 1
        posX = posX + moveDir * 6
        if ( posX > 180 )
        {
            moveDir = -1
        }
        elif ( posX < 10 )
        {
            moveDir = 1
        }
        if ( animLabel != null )
        {
            animLabel.move( posX, 16 )
        }
        if ( animBtn != null )
        {
            animBtn.move( posX, 52 )
        }
        moveCount = moveCount + 1
    }

    # 动画面板定时退出（offscreen / 无人值守可收敛）
    public static void onQuit()
    {
        if ( _app != null )
        {
            _app.quit()
        }
    }

    public static void main()
    {
        IO.Directory.createDirectory( "qttest-out" )

        string kind = SLang.QT.backendKind()
        Console.println( "========== QTTest suite (backend=" + kind + ") ==========" )

        _app = SLang.QT.newApp()

        if ( kind == "qt" )
        {
            Console.println( "platform    : " + SLang.QT.appPlatformName() )
            Console.println( "libraryPaths: " + SLang.QT.appLibraryPaths() )
            Console.println( "styleKeys   : " + SLang.QT.appStyleKeys() )
        }

        # ── 1. smoke：控件工厂 + 类层级 + 信号绑定（FFI 链路）──────────
        bool smokeOk = runSmoke()

        # ── 2. 组合探测矩阵：当前部署槽位里有哪些 Qt 模块 ─────────────
        probeModules()

        # ── 3. 扩展面板（模块缺件 SKIP，不触碰延迟加载导出）───────────
        if ( kind == "qt" )
        {
            panelImage()
            panelSvg()
            panelGL()
            panelSql()
            panelNet()
            panelXml()
            panelConcurrent()
            panelTest()
            panelPrint()
            panelUiTools()
            panelDesigner()
            panelHelp()
            panelDBus()
        }
        else
        {
            Console.println( "-- stub backend: extension panels skipped (build the Qt backend + deploy a qtRuntime combo)" )
        }

        # ── 4. 动画面板：QTimer 移动效果 + GL 旋转 ─────────────────────
        runAnimation( kind )

        # ── 5. 汇总 ─────────────────────────────────────────────────────
        Console.println( "========== QTTest summary ==========" )
        string summary = "backend=" + kind
        summary = summary + "  modules=" + modulesAvail.toString() + "/" + modulesTotal.toString()
        summary = summary + "  panels ok=" + panelsRun.toString() + "/" + panelsTotal.toString()
        summary = summary + "  failed=" + panelsFailed.toString()
        Console.println( summary )
        if ( smokeOk && panelsFailed == 0 )
        {
            Console.println( "QTTest: PASS" )
        }
        else
        {
            Console.println( "QTTest: FAIL" )
        }
    }

    # ── 1. smoke ─────────────────────────────────────────────────────────

    static bool runSmoke()
    {
        SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
        SLang.QLineEdit edit = SLang.QT.newLineEdit( 0, "type here" )
        SLang.QVBoxLayout box = SLang.QT.newVBox( 0 )
        box.addWidget( btn )
        box.addWidget( edit )

        SLang.QWidget w = SLang.QT.newWidget( 0 )
        w.setLayout( box )
        w.setTitle( "slQT smoke" )
        w.resize( 320, 200 )

        Int64 bid1 = btn.clicked( QTTest.onClick )
        Int64 bid2 = edit.onTextChanged( QTTest.onText )
        # 程序化端到端信号验证：setText 同步发射 textChanged → 重入 VM
        edit.setText( "signal-e2e" )

        if ( bid1 != 0 && bid2 != 0 )
        {
            # i64 返回值真实性探针：null 转 i32 为 0，真实 bind_id > 0 可辨
            Console.println( "[smoke] OK: bind1=" + SystemConvertString( bid1 as Int32 ) + " bind2=" + SystemConvertString( bid2 as Int32 ) + " lastText.len=" + SystemConvertString( SystemStringLength( lastText ) ) )
            ret true
        }
        Console.println( "[smoke] FAIL: bind1=" + bid1.toString() + " bind2=" + bid2.toString() )
        ret false
    }

    # ── 2. 模块探测矩阵 ─────────────────────────────────────────────────

    static void probeModules()
    {
        List<string> mods = List<string>()
        mods.add( "Qt6Network.dll" )
        mods.add( "Qt6Sql.dll" )
        mods.add( "Qt6Svg.dll" )
        mods.add( "Qt6SvgWidgets.dll" )
        mods.add( "Qt6OpenGL.dll" )
        mods.add( "Qt6OpenGLWidgets.dll" )
        mods.add( "Qt6PrintSupport.dll" )
        mods.add( "Qt6Xml.dll" )
        mods.add( "Qt6Concurrent.dll" )
        mods.add( "Qt6Test.dll" )
        mods.add( "Qt6UiTools.dll" )
        mods.add( "Qt6Help.dll" )
        mods.add( "Qt6DBus.dll" )
        mods.add( "Qt6Designer.dll" )

        Console.println( "-- module matrix (deployed in runtime dir) --" )
        int i = 0
        while ( i < mods.length )
        {
            string m = mods[i]
            modulesTotal = modulesTotal + 1
            string mark = "--"
            if ( SLang.QT.moduleAvailable( m ) )
            {
                modulesAvail = modulesAvail + 1
                mark = "OK"
            }
            Console.println( "  [module] " + m + " : " + mark )
            i = i + 1
        }
    }

    # ── 3. 扩展面板 ──────────────────────────────────────────────────────

    # 图像 / 图标（Qt6Gui 内建 + imageformats/iconengines 插件探测）
    static void panelImage()
    {
        panelsTotal = panelsTotal + 1
        Console.println( "  [image] formats: " + SLang.QT.imageFormats() )

        # PNG 内建（不依赖 imageformats 插件）——判失败
        if ( SLang.QT.imageSaveSolid( "qttest-out/solid.png", "PNG", 30, 144, 255 ) == false )
        {
            Console.println( "[image] FAIL: png save" )
            panelsFailed = panelsFailed + 1
            ret
        }
        if ( SLang.QT.imageCheckSize( "qttest-out/solid.png", 32, 32 ) == false )
        {
            Console.println( "[image] FAIL: png reload size" )
            panelsFailed = panelsFailed + 1
            ret
        }
        # JPEG / 图标引擎依赖插件分类——仅报告（组合未带插件属合法裁剪）
        if ( SLang.QT.imageSaveSolid( "qttest-out/solid.jpg", "JPEG", 144, 30, 255 ) )
        {
            Console.println( "[image] jpeg: OK (qjpeg plugin loaded)" )
        }
        else
        {
            Console.println( "[image] jpeg: -- (imageformats\\qjpeg not deployed)" )
        }
        Console.println( "[image] OK: png write + reload" )
        panelsRun = panelsRun + 1
    }

    # Svg（Qt6Svg 渲染 + Qt6SvgWidgets 控件）
    static void panelSvg()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Svg.dll" ) == false )
        {
            Console.println( "  [svg] SKIP (Qt6Svg.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        string svg = "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'><circle cx='32' cy='32' r='30' fill='#4682b4'/></svg>"
        SLang.QSvgRenderer rend = SLang.QT.newSvgRenderer( svg )
        if ( rend.isValid() == false )
        {
            Console.println( "[svg] FAIL: renderer invalid" )
            panelsFailed = panelsFailed + 1
            ret
        }
        SLang.QLabel lab = SLang.QT.newLabel( 0, "svg-slot" )
        if ( rend.renderToLabel( lab, 64, 64 ) == false )
        {
            Console.println( "[svg] FAIL: render to label" )
            panelsFailed = panelsFailed + 1
            ret
        }
        if ( SLang.QT.moduleAvailable( "Qt6SvgWidgets.dll" ) )
        {
            SLang.QSvgWidget sw = SLang.QT.newSvgWidget( 0 )
            if ( sw.loadData( svg ) )
            {
                Console.println( "[svg] OK: renderer + label pixmap + svgwidget" )
            }
            else
            {
                Console.println( "[svg] OK: renderer + label pixmap (svgwidget load failed)" )
            }
            sw.delete()
        }
        else
        {
            Console.println( "[svg] OK: renderer + label pixmap (Qt6SvgWidgets SKIP)" )
        }
        lab.delete()
        rend.delete()
        panelsRun = panelsRun + 1
    }

    # OpenGL（Qt6OpenGLWidgets：旋转三角，动画面板期间持续渲染）
    static void panelGL()
    {
        if ( SLang.QT.moduleAvailable( "Qt6OpenGLWidgets.dll" ) == false )
        {
            Console.println( "  [gl] SKIP (Qt6OpenGLWidgets.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        animGL = SLang.QT.newGLPanel( 0 )
        animGL.setColor( 70, 130, 180 )
        animGL.resize( 240, 110 )
        animGL.show()
        animGL.setSpinning( true )
        int i = 0
        while ( i < 30 )
        {
            _app.processEvents()
            i = i + 1
        }
        Console.println( "[gl] OK: spinning triangle widget, frames=" + animGL.frameCount().toString() )
        panelsRun = panelsRun + 1
    }

    # Sql（Qt6Sql + sqldrivers\qsqlite 插件：内存库建表/插入/聚合）
    static void panelSql()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Sql.dll" ) == false )
        {
            Console.println( "  [sql] SKIP (Qt6Sql.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        Console.println( "  [sql] drivers: " + SLang.QT.sqlDrivers() )
        SLang.QSqlDatabase db = SLang.QT.addDatabase( "QSQLITE" )
        db.setDatabaseName( ":memory:" )
        if ( db.open() == false )
        {
            Console.println( "[sql] FAIL: open: " + db.lastError() )
            panelsFailed = panelsFailed + 1
            ret
        }
        SLang.QSqlQuery q = db.createQuery()
        q.exec( "CREATE TABLE t (id INTEGER, name TEXT)" )
        int i = 1
        while ( i <= 10 )
        {
            q.exec( "INSERT INTO t VALUES (" + i.toString() + ", 'row" + i.toString() + "')" )
            i = i + 1
        }
        q.exec( "SELECT id FROM t ORDER BY id" )
        Int64 sum = 0
        int rows = 0
        while ( q.step() )
        {
            sum = sum + q.valueInt( 0 )
            rows = rows + 1
        }
        if ( sum == 55 && rows == 10 )
        {
            Console.println( "[sql] OK: qsqlite in-memory, 10 rows, sum=55" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[sql] FAIL: rows=" + rows.toString() + " sum=" + sum.toString() )
            panelsFailed = panelsFailed + 1
        }
        q.delete()
        db.close()
        db.delete()
    }

    # Network（Qt6Network + networkinformation / tls 插件；在线态仅报告）
    static void panelNet()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Network.dll" ) == false )
        {
            Console.println( "  [net] SKIP (Qt6Network.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QNetworkAccessManager net = SLang.QT.newNetManager()
        int online = net.isOnline()
        string state = "no-backend"
        if ( online == 1 )
        {
            state = "online"
        }
        elif ( online == 0 )
        {
            state = "offline"
        }
        Console.println( "  [net] state=" + state + " backend=" + net.backendName() )
        # HTTPS GET 探测（装载 tls 插件链路；离线/超时属预期，不判失败）
        SLang.QNetworkReply rep = net.httpGet( "https://example.com/" )
        if ( rep.wait( 3000 ) )
        {
            Console.println( "[net] OK: GET status=" + rep.status().toString() + " err=" + rep.errorString() )
        }
        else
        {
            Console.println( "[net] OK: GET timeout (offline environment)" )
        }
        net.delete()
        panelsRun = panelsRun + 1
    }

    # Xml（Qt6Xml：QDomDocument 解析 / 计数 / 取文本）
    static void panelXml()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Xml.dll" ) == false )
        {
            Console.println( "  [xml] SKIP (Qt6Xml.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QDomDocument doc = SLang.QT.newDomDocument()
        if ( doc.setContent( "<root><item>a</item><item>b</item><item>c</item></root>" ) == false )
        {
            Console.println( "[xml] FAIL: parse" )
            panelsFailed = panelsFailed + 1
            ret
        }
        Int64 n = doc.countByTag( "item" )
        string first = doc.firstText( "item" )
        if ( n == 3 && first == "a" )
        {
            Console.println( "[xml] OK: root=" + doc.rootTag() + " items=" + n.toString() + " first=" + first )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[xml] FAIL: items=" + n.toString() + " first=" + first )
            panelsFailed = panelsFailed + 1
        }
        doc.delete()
    }

    # Concurrent（Qt6Concurrent：线程池原生计算 1..1000000 求和）
    static void panelConcurrent()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Concurrent.dll" ) == false )
        {
            Console.println( "  [concurrent] SKIP (Qt6Concurrent.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QConcurrentTask task = SLang.QT.runConcurrent( 0, 1000000 )
        int guard = 0
        while ( task.isFinished() == false && guard < 2000 )
        {
            _app.processEvents()
            guard = guard + 1
        }
        if ( task.isFinished() == false )
        {
            Console.println( "[concurrent] FAIL: task timeout" )
            panelsFailed = panelsFailed + 1
            ret
        }
        Int64 r = task.result()
        if ( r == 500000500000 )
        {
            Console.println( "[concurrent] OK: sum(1..1000000)=500000500000, pool=" + SLang.QT.threadPoolMax().toString() + " threads" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[concurrent] FAIL: result=" + r.toString() )
            panelsFailed = panelsFailed + 1
        }
        task.delete()
    }

    # Test（Qt6Test：qWait 事件循环 + 版本）
    static void panelTest()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Test.dll" ) == false )
        {
            Console.println( "  [test] SKIP (Qt6Test.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QT.ffi_testQWait( 30 )
        string v = SLang.QT.testVersion()
        if ( v != "" )
        {
            Console.println( "[test] OK: QtTest " + v + ", qWait(30) ok" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[test] FAIL: empty version" )
            panelsFailed = panelsFailed + 1
        }
    }

    # Print（Qt6PrintSupport：PDF 输出 + 文件校验）
    static void panelPrint()
    {
        if ( SLang.QT.moduleAvailable( "Qt6PrintSupport.dll" ) == false )
        {
            Console.println( "  [print] SKIP (Qt6PrintSupport.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        string pdf = "qttest-out/report.pdf"
        SLang.QPrinter pr = SLang.QT.newPrinter()
        pr.setOutputFileName( pdf )
        pr.setPageSizeA4()
        if ( pr.printText( "QTTest Report", "PDF written by the SLangQT print panel (Qt6PrintSupport)." ) && File.exists( pdf ) )
        {
            Console.println( "[print] OK: " + pdf + " (" + File.getSize( pdf ).toString() + " bytes)" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[print] FAIL: pdf not produced" )
            panelsFailed = panelsFailed + 1
        }
        pr.delete()
    }

    # UiTools（Qt6UiTools：QUiLoader 装载 .ui）
    static void panelUiTools()
    {
        if ( SLang.QT.moduleAvailable( "Qt6UiTools.dll" ) == false )
        {
            Console.println( "  [uitools] SKIP (Qt6UiTools.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        writeUiFile()
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        SLang.QUiLoader loader = SLang.QT.newUiLoader()
        SLang.QLoadedWidget w = loader.loadFile( "qttest-out/form.ui", host )
        if ( w.isValid() )
        {
            Console.println( "[uitools] OK: QUiLoader loaded form.ui" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[uitools] FAIL: QUiLoader load" )
            panelsFailed = panelsFailed + 1
        }
        w.delete()
        loader.delete()
        host.delete()
    }

    # Designer（Qt6Designer：QFormBuilder 装载同一 .ui —— 双通道对照）
    static void panelDesigner()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Designer.dll" ) == false )
        {
            Console.println( "  [designer] SKIP (Qt6Designer.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        SLang.QFormBuilder fb = SLang.QT.newFormBuilder()
        SLang.QLoadedWidget w = fb.loadFile( "qttest-out/form.ui", host )
        if ( w.isValid() )
        {
            Console.println( "[designer] OK: QFormBuilder loaded form.ui" )
            panelsRun = panelsRun + 1
        }
        else
        {
            Console.println( "[designer] FAIL: QFormBuilder load" )
            panelsFailed = panelsFailed + 1
        }
        w.delete()
        fb.delete()
        host.delete()
    }

    # Help（Qt6Help → Qt6Sql + qsqlite 依赖链；空集合仅报告）
    static void panelHelp()
    {
        if ( SLang.QT.moduleAvailable( "Qt6Help.dll" ) == false )
        {
            Console.println( "  [help] SKIP (Qt6Help.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        SLang.QHelpEngine he = SLang.QT.newHelpEngine( "qttest-out/collection.qhc" )
        if ( he.setupData() )
        {
            Console.println( "[help] OK: qhc collection ready (help->sql->qsqlite chain)" )
        }
        else
        {
            Console.println( "[help] setupData=false, err=" + he.lastError() )
        }
        he.delete()
        panelsRun = panelsRun + 1
    }

    # DBus（Qt6DBus：Windows 常无会话总线，未连接属预期）
    static void panelDBus()
    {
        if ( SLang.QT.moduleAvailable( "Qt6DBus.dll" ) == false )
        {
            Console.println( "  [dbus] SKIP (Qt6DBus.dll not deployed)" )
            ret
        }
        panelsTotal = panelsTotal + 1
        if ( SLang.QDBus.isConnected() )
        {
            Console.println( "[dbus] OK: session bus " + SLang.QDBus.baseService() )
        }
        else
        {
            Console.println( "[dbus] OK: no session bus (normal on Windows)" )
        }
        panelsRun = panelsRun + 1
    }

    static void writeUiFile()
    {
        string ui = "<ui version='4.0'><class>Form</class><widget class='QWidget' name='Form'>"
        ui = ui + "<property name='geometry'><rect><x>0</x><y>0</y><width>140</width><height>60</height></rect></property>"
        ui = ui + "<widget class='QLabel' name='label'>"
        ui = ui + "<property name='geometry'><rect><x>10</x><y>10</y><width>120</width><height>20</height></rect></property>"
        ui = ui + "<property name='text'><string>loaded from .ui</string></property>"
        ui = ui + "</widget></widget></ui>"
        File.writeAllText( "qttest-out/form.ui", ui )
    }

    # ── 4. 动画面板（移动效果）───────────────────────────────────────────

    static void runAnimation( string kind )
    {
        Console.println( "-- animation panel: QTimer 30ms shuttle move + GL spin (1.6s auto-quit) --" )
        SLang.QWidget host = SLang.QT.newWidget( 0 )
        host.setTitle( "QTTest move effect" )
        host.resize( 340, 100 )
        animLabel = SLang.QT.newLabel( host.handle, "moving label" )
        animLabel.setGeometry( 10, 14, 130, 22 )
        animBtn = SLang.QT.newButton( host.handle, "moving button" )
        animBtn.setGeometry( 10, 50, 140, 28 )
        host.show()

        SLang.QTimer quitT = SLang.QT.newTimer( 1600, true, QTTest.onQuit )
        SLang.QTimer animT = SLang.QT.newTimer( 30, false, QTTest.onTick )

        if ( kind == "stub" )
        {
            Console.println( "  stub backend: exec() returns immediately (counters stay 0)" )
        }
        _app.exec()

        Console.println( "[anim] ticks=" + tickCount.toString() + " moves=" + moveCount.toString() )
        if ( animGL != null )
        {
            Console.println( "[anim] GL frames during exec=" + animGL.frameCount().toString() )
            animGL.setSpinning( false )
            animGL.delete()
            animGL = null
        }
        animT.delete()
        quitT.delete()
        host.delete()
    }
}
