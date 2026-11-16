import Core;
import Std;

# QTextBrowser —— 只读富文本/Markdown 查看器（2026-11-16 第三十轮）
# 用于内置帮助查看器等文档展示场景；Qt6 原生 setMarkdown 渲染标题/列表/
# 代码块。本身只读（QTextBrowser 天然不可编辑源文本）。
# setText/toPlainText/setReadOnly/append 继承自 QTextEdit（句柄兼容，
# 既有 slqt_textedit_* 对 QTextBrowser 子类 qobject_cast 成功）。
namespace SLang
{
    public class QTextBrowser extends QTextEdit
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_browserCreate( parent ) )
        }

        # 整体替换内容并按 Markdown 渲染（标题/列表/代码块/链接）
        public void setMarkdown( string md )
        {
            SLang.QT.ffi_browserSetMarkdown( this.handle, md )
        }

        # ── 第三十二轮：文档内链接跳转 ──
        # 以 path 所在目录为 base 展示 md；此后 md 内的相对链接（.md）可点击，
        # 加载成功发 SIG_BROWSER_NAVIGATED（int 载荷=0），handler 里用
        # currentSource() 取新路径更新标题/状态
        public void setDocument( string path, string md )
        {
            SLang.QT.ffi_browserSetDocument( this.handle, path, md )
        }

        # 当前文档绝对路径（未用 setDocument 时为空串）
        public string currentSource()
        {
            ret SLang.QT.ffi_browserCurrentSource( this.handle )
        }

        # handler 形态：static void onNavigated( int payload )
        public Int64 onNavigated( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_BROWSER_NAVIGATED, handler )
        }
    }
}
