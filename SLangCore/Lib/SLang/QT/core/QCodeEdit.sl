import Core;
import Std;

# QCodeEdit —— 代码编辑器复合控件（能力登记表 D-02 回补，2026-11-12）
# 原生为 QPlainTextEdit 派生类：行号区 / 断点装订线 / 当前行高亮 /
# SLang 关键字语法高亮；装订线左键点击可切换断点并回调行号。
# 信号：7=光标行变化(int)、8=装订线断点(int)，均经 _dispatchInt 桥重入。
namespace SLang
{
    public class QCodeEdit extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_codeeditCreate( parent ) )
            SLang.QT.ffi_codeeditSetHighlight( this.handle, true )
        }

        # 按已有句柄收养（多标签句柄表用；不创建新控件）
        _init_( Int64 handle, bool adopt )
        {
            this.setHandle( handle )
        }

        public static QCodeEdit fromHandle( Int64 h )
        {
            ret QCodeEdit( h, true )
        }

        public void setPlainText( string t )
        {
            SLang.QT.ffi_codeeditSetText( this.handle, t )
        }

        public string toPlainText() { ret SLang.QT.ffi_codeeditText( this.handle ) }

        public void setReadOnly( bool on )
        {
            SLang.QT.ffi_codeeditSetReadonly( this.handle, on )
        }

        public void gotoLine( int line )
        {
            SLang.QT.ffi_codeeditGotoLine( this.handle, line )
        }

        # 1-based 行号
        public int cursorLine() { ret SLang.QT.ffi_codeeditCursorLine( this.handle ) }

        public void setHighlight( bool on )
        {
            SLang.QT.ffi_codeeditSetHighlight( this.handle, on )
        }

        public void setBreakpoint( int line, bool on )
        {
            SLang.QT.ffi_codeeditSetBreakpoint( this.handle, line, on )
        }

        # 切换光标所在行断点，返回切换后状态：1=已加 0=已移除
        public int toggleBreakpoint()
        {
            ret SLang.QT.ffi_codeeditToggleBreakpoint( this.handle )
        }

        public void clearBreakpoints()
        {
            SLang.QT.ffi_codeeditClearBreakpoints( this.handle )
        }

        # 逗号分隔的升序行号串，如 "3,17,42"
        public string breakpoints() { ret SLang.QT.ffi_codeeditBreakpoints( this.handle ) }

        public void setFontPt( int pt )
        {
            SLang.QT.ffi_codeeditSetFontPt( this.handle, pt )
        }

        # 光标下单词（QTextCursor::WordUnderCursor）；符号索引用
        public string wordUnderCursor() { ret SLang.QT.ffi_codeeditWord( this.handle ) }

        # 当前选中文本；未选中返回空串
        public string selectedText() { ret SLang.QT.ffi_codeeditSelected( this.handle ) }

        # 已被调试会话确认的断点行（逗号分隔）；装订线由空心变实心
        public void setBoundBreakpoints( string csv )
        {
            SLang.QT.ffi_codeeditSetBound( this.handle, csv )
        }

        # 当前停驻行（1-based）；0 = 清除箭头与行高亮
        public void setStoppedLine( int line )
        {
            SLang.QT.ffi_codeeditSetStopped( this.handle, line )
        }

        # handler 形态：static void onLine( int line )
        public Int64 onLineChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_CODEEDIT_LINE_CHANGED, handler )
        }

        # handler 形态：static void onBreakpoint( int line )
        public Int64 onBreakpoint( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_CODEEDIT_BREAKPOINT, handler )
        }
    }
}
