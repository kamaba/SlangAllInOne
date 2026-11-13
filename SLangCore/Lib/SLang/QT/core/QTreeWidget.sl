import Core;
import Std;

# QTreeWidget —— 层级树（能力登记表 D-03 回补，2026-11-12）
# 路径式建模：SL 侧只传 "root/a/b" 字符串，原生层按 '/' 拆层并缓存节点，
# 不暴露 QTreeWidgetItem 句柄；选中回传完整路径（SIG_TREE_SELECTED=6，
# 经 _dispatchString(utf8) 桥重入 VM）。
namespace SLang
{
    public class QTreeWidget extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_treeCreate( parent ) )
        }

        public void setHeader( string title )
        {
            SLang.QT.ffi_treeSetHeader( this.handle, title )
        }

        public void clear() { SLang.QT.ffi_treeClear( this.handle ) }

        public void addPath( string path )
        {
            SLang.QT.ffi_treeAddPath( this.handle, path )
        }

        public int count() { ret SLang.QT.ffi_treeCount( this.handle ) }

        public string selectedPath() { ret SLang.QT.ffi_treeSelectedPath( this.handle ) }

        # handler 形态：static void onSelected( string path )
        public Int64 onSelected( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TREE_SELECTED, handler )
        }
    }
}
