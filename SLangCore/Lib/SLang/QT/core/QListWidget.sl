import Core;
import Std;

# QListWidget —— 列表选择控件（示例清单：currentRowChanged(int) 信号）
namespace SLang
{
    public class QListWidget extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_listCreate( parent ) )
        }

        public void addItem( string t ) { SLang.QT.ffi_listAddItem( this.handle, t ) }

        public void clear() { SLang.QT.ffi_listClear( this.handle ) }

        public int count() { ret SLang.QT.ffi_listCount( this.handle ) }

        public int currentRow() { ret SLang.QT.ffi_listCurrentRow( this.handle ) }

        public void setCurrentRow( int row ) { SLang.QT.ffi_listSetCurrentRow( this.handle, row ) }

        public string itemText( int row ) { ret SLang.QT.ffi_listItemText( this.handle, row ) }

        # 选中行变化：handler 形态 static void onRow( int row )；原生层经
        # _dispatchInt(int64,int64) 桥重入 VM（SLQT_SIG_CURRENT_ROW_CHANGED=5）
        public Int64 onCurrentRowChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_CURRENT_ROW_CHANGED, handler )
        }
    }
}
