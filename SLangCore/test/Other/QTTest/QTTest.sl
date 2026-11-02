import SLangQT;
import Std;

# slQT headless smoke test（STUB 后端：FFI 回退到 SL 函数体，bind_id 返回 >0 即证明
# createCallback + slqt_connect 桥接路径打通；真实 Qt 后端会弹出窗口并触发回调）。
public class QTTest
{
    static int clicks = 0
    static string lastText = ""

    public static void onClick()
    {
        clicks = clicks + 1
        Console.println( "onClick fired, clicks=" + clicks )
    }

    public static void onText( string s )
    {
        lastText = s
        Console.println( "onText: " + s )
    }

    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()

        SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
        SLang.QLineEdit edit = SLang.QT.newLineEdit( 0, "type here" )
        SLang.QVBoxLayout box = SLang.QT.newVBox( 0 )
        box.addWidget( btn )
        box.addWidget( edit )

        SLang.QWidget w = SLang.QT.newWidget( 0 )
        w.setLayout( box )
        w.setTitle( "slQT smoke" )
        w.resize( 320, 200 )
        w.show()

        Int64 bid1 = btn.clicked( QTTest.onClick )
        Int64 bid2 = edit.onTextChanged( QTTest.onText )
        Console.println( "slQT smoke: clicked bind=" + bid1 + " textChanged bind=" + bid2 )

        if ( bid1 != 0 )
        {
            Console.println( "slQT smoke test: PASS (FFI bind + factories + hierarchy ok)" )
        }
        else
        {
            Console.println( "slQT smoke test: FAIL" )
        }

        app.exec()
    }
}
