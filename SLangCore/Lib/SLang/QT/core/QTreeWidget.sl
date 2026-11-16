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

        # 当前节点第 0 列显示文本（2026-11-16 第三十六轮；无选中为空串）
        public string currentText() { ret SLang.QT.ffi_treeCurrentText( this.handle ) }

        # handler 形态：static void onSelected( string path )
        public Int64 onSelected( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TREE_SELECTED, handler )
        }

        # 第十四轮：节点右键。handler 形态：static void onContext( string path )，
        # path = 右键所在节点完整路径（同时会把该节点设为 current；空白区为空串）
        public Int64 onContext( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TREE_CONTEXT, handler )
        }

        # 2026-11-14 第二十一轮：展开态 / 前景色 / tooltip / 双击（按路径定位节点）
        public void expandAll() { SLang.QT.ffi_treeExpandAll( this.handle ) }

        public void collapseAll() { SLang.QT.ffi_treeCollapseAll( this.handle ) }

        public void setItemExpanded( string path, int on )
        {
            SLang.QT.ffi_treeSetItemExpanded( this.handle, path, on )
        }

        public bool isItemExpanded( string path )
        {
            int v = SLang.QT.ffi_treeItemExpanded( this.handle, path )
            if ( v != 0 ) { ret true }
            ret false
        }

        # rgb = 0xRRGGBB（如 0x888888 灰显 / 0xC00000 标红）
        public void setItemForeground( string path, int rgb )
        {
            SLang.QT.ffi_treeSetItemForeground( this.handle, path, rgb )
        }

        public void setItemTooltip( string path, string tip )
        {
            SLang.QT.ffi_treeSetItemTooltip( this.handle, path, tip )
        }

        # 2026-11-15 第二十三轮：按累计路径选中节点（属性页默认选中 root/project）
        public void setCurrentPath( string path )
        {
            SLang.QT.ffi_treeSetCurrentPath( this.handle, path )
        }

        # 第二十四轮：淡色背景底纹 / 字体加粗（rgb = 0xRRGGBB）
        public void setItemBackground( string path, int rgb )
        {
            SLang.QT.ffi_treeSetItemBackground( this.handle, path, rgb )
        }

        public void setItemBold( string path, int on )
        {
            SLang.QT.ffi_treeSetItemBold( this.handle, path, on )
        }

        # 第二十六轮：Qt 标准图标 id（0 文件 / 1 目录 / 2 警告 / 3 应用 / 4 取消）
        public void setItemIcon( string path, int iconId )
        {
            SLang.QT.ffi_treeSetItemIcon( this.handle, path, iconId )
        }

        # handler 形态：static void onDoubleClicked( string path )
        public Int64 onDoubleClicked( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TREE_DOUBLE_CLICKED, handler )
        }
    }
}
