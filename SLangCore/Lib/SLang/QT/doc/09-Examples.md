# slQT · 09 端到端示例（已落地版）

- 所属文档集：`plugin/slqt/doc/`（00 索引 · 01 总览 · 02 架构 · 03 绑定 · 04 符号表 · 05 封装类 · 06 信号槽 · 07 构建 · 08 打包 · **09 示例** · 10 路线 · 11 规范）
- 版本：v1（示例语法与 `QTFFI.sl` / 封装类一致，并经 `test/Other/QTTest` 编译验证）
- 前提：`slang_qt.dll` 已随模块导出（STUB 可 headless 跑通；Qt 版出真实窗口）；工程 `references` 显式引用 `SLangQT` 模块产物接入（见 08 §2）。

---

## 示例 1：Hello World 窗口（阻塞模式）

```sl
import SLangQT;

public class App
{
    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()

        SLang.QLabel label = SLang.QT.newLabel( 0, "Hello, slQT!" )
        label.resize( 300, 80 )

        SLang.QVBoxLayout layout = SLang.QT.newVBox( 0 )
        layout.addWidget( label )

        SLang.QWidget window = SLang.QT.newWidget( 0 )
        window.setLayout( layout )
        window.setTitle( "slQT Demo" )
        window.resize( 400, 200 )
        window.show()

        app.exec()        # 进入 Qt 事件循环，关闭窗口后返回
    }
}
```

## 示例 2：按钮点击计数器（信号槽）

```sl
import SLangQT;

public class CounterApp
{
    static int count = 0
    static SLang.QLabel label

    public static void onButtonClicked()
    {
        count = count + 1
        label.setText( "clicked: " + count )
    }

    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()
        CounterApp self = CounterApp()

        SLang.QPushButton btn = SLang.QT.newButton( 0, "Click me" )
        self.label = SLang.QT.newLabel( 0, "clicked: 0" )

        SLang.QVBoxLayout layout = SLang.QT.newVBox( 0 )
        layout.addWidget( btn )
        layout.addWidget( self.label )

        SLang.QWidget window = SLang.QT.newWidget( 0 )
        window.setLayout( layout )
        window.setTitle( "Counter" )
        window.resize( 300, 150 )
        window.show()

        btn.clicked( CounterApp.onButtonClicked )   # 信号绑定：handler 必须传全限定引用

        app.exec()
    }
}
```

> **handler 必须传全限定引用**（`类名.静态方法` / `实例.方法` / 匿名闭包），裸方法名（`btn.clicked( onClick )`）无法解析，编译报「节点[onClick] 没有找到」——与 `WebUITest` 的 `win.bindHandle( "greet", WebUITest.onGreet )` 同一约定（2026-11-02 实测）。
>
> 对象创建同样不带 `new`：`CounterApp self = CounterApp()`（对齐 WebUI 的 `Hooks hooks = Hooks()`）。
>
> `createCallback` 的 method 参数传完整 `Class.method` 全限定名（≤191 字符）。`btn.clicked(handler)` 内部走 `slqt_connect_sl` → Qt `connect` → 回调重入 VM（06 §1）。

## 示例 3：输入框 + 实时回显（带参数信号）

```sl
import SLangQT;

public class EchoApp
{
    static SLang.QLabel out

    public static void onText( string s )     # 对应 textChanged(QString) -> utf8
    {
        out.setText( "you typed: " + s )
    }

    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()
        EchoApp self = EchoApp()

        SLang.QLineEdit edit = SLang.QT.newLineEdit( 0, "type here" )
        self.out = SLang.QT.newLabel( 0, "" )

        SLang.QVBoxLayout layout = SLang.QT.newVBox( 0 )
        layout.addWidget( edit )
        layout.addWidget( self.out )

        SLang.QWidget w = SLang.QT.newWidget( 0 )
        w.setLayout( layout )
        w.show()

        edit.onTextChanged( EchoApp.onText )  # sig "utf8->void"，handler 全限定引用

        app.exec()
    }
}
```

> 回调体内的 `s` 仅本次有效（utf8 静态缓冲，即取即用）；需长期持有请立即拷贝。

## 示例 4：非阻塞模式（SL 自写循环）

```sl
import SLangQT;
import Std.Console;

public class TickApp
{
    public static void main()
    {
        SLang.QApplication app = SLang.QT.newApp()
        SLang.QLabel label = SLang.QT.newLabel( 0, "tick: 0" )
        SLang.QWidget w = SLang.QT.newWidget( 0 )
        w.setLayout( SLang.QT.newVBox(0).addWidget(label) )
        w.show()

        int n = 0
        while ( true )
        {
            app.processEvents()              # 单轮派发 Qt 事件
            n = n + 1
            label.setText( "tick: " + n )
            Std.Console.sleep( 100 )         # 伪：实际用 Std 的延时 API
        }
    }
}
```

> 非阻塞模式让 SL 保有主动权（动画/网络轮询）；长耗时逻辑会卡 UI（与 PyQt 同理）。

---

*示例覆盖四种典型用法（已与 `test/Other/QTTest` 同款 API 编译+运行验证，模块形态 PASS）。里程碑与限制见 10，版本与规范见 11。*
