import Core;
import Std;

# QTableWidget —— 只读属性表（2026-11-15 第二十三轮）
# 原生层创建时设为 NoEditTriggers + SelectRows；SL 侧按行列写文本，
# 值写回仍走 CLI project set，表格不承担编辑职责。
namespace SLang
{
    public class QTableWidget extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_tableCreate( parent ) )
        }

        public void setColumnCount( int n )
        {
            SLang.QT.ffi_tableSetColumnCount( this.handle, n )
        }

        public void setRowCount( int n )
        {
            SLang.QT.ffi_tableSetRowCount( this.handle, n )
        }

        # csv = 逗号分隔的水平表头
        public void setHeaders( string csv )
        {
            SLang.QT.ffi_tableSetHeaders( this.handle, csv )
        }

        public void setItem( int row, int col, string t )
        {
            SLang.QT.ffi_tableSetItem( this.handle, row, col, t )
        }

        public void clearItems()
        {
            SLang.QT.ffi_tableClear( this.handle )
        }

        # 第二十四轮：当前行读取（stub 后端返回 -1）
        public int currentRow()
        {
            ret SLang.QT.ffi_tableCurrentRow( this.handle )
        }

        # handler 形态：static void onTableRow( int row )，点击任意单元格触发
        public Int64 onRowClicked( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TABLE_ROW_CLICKED, handler )
        }

        # 第二十五轮：值列就地编辑（默认全表只读，逐格开启）
        public void setItemEditable( int row, int col, int on )
        {
            SLang.QT.ffi_tableSetItemEditable( this.handle, row, col, on )
        }

        public string itemText( int row, int col )
        {
            ret SLang.QT.ffi_tableItemText( this.handle, row, col )
        }

        # handler 形态：static void onTableItemChanged( int row )；程序化填充由 C++ 阻断
        public Int64 onItemChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TABLE_ITEM_CHANGED, handler )
        }
    }
}
