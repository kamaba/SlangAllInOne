import Core;
import Std;

# QTextEdit —— 多行文本编辑框（示例代码编辑 / 只读输出窗共用）
# 正文经原生大缓冲（256KB）搬运；setText/toPlainText 均为 UTF-8 直通。
namespace SLang
{
    public class QTextEdit extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_texteditCreate( parent ) )
        }

        # 整体替换正文（多行；等价 QWidget.setText 的 QTextEdit 分支 setPlainText）
        public void setPlainText( string t ) { SLang.QT.ffi_texteditSetText( this.handle, t ) }

        # 读取全部正文（大缓冲；顺序调用安全，勿在两次读取间嵌套再读）
        public string toPlainText() { ret SLang.QT.ffi_texteditText( this.handle ) }

        # 只读开关（编译输出 / 运行结果窗置 true）
        public void setReadOnly( bool on ) { SLang.QT.ffi_texteditSetReadonly( this.handle, on ) }

        # 追加一段文本（Qt append 自带换段；日志窗逐段追加用）
        public void append( string t ) { SLang.QT.ffi_texteditAppend( this.handle, t ) }

        # 清空正文
        public void clear() { SLang.QT.ffi_texteditSetText( this.handle, "" ) }
    }
}
