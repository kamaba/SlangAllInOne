import Core;
import Std;

# QTabWidget —— VS 式多标签文档区（2026-11-13）
# 每个标签页是一个 QWidget 句柄（应用侧通常放独立的 QCodeEdit）；
# SL 侧只传句柄 + 字符串标题，不暴露 QTabBar / 页索引对象。
# 信号：9=当前标签变化(int下标)、10=标签关闭请求(int下标)，均经 _dispatchInt 桥重入。
namespace SLang
{
    public class QTabWidget extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_tabCreate( parent ) )
        }

        # 返回新标签下标；page 为任意 QWidget 派生类的原生句柄（不传对象，
        # 避免 SL 跨模块按基类传参时切片破坏派生对象状态）
        public int addTab( Int64 page, string title )
        {
            ret SLang.QT.ffi_tabAdd( this.handle, page, title )
        }

        public int count() { ret SLang.QT.ffi_tabCount( this.handle ) }

        # 无标签时为 -1
        public int currentIndex() { ret SLang.QT.ffi_tabCurrent( this.handle ) }

        public void setCurrentIndex( int idx )
        {
            SLang.QT.ffi_tabSetCurrent( this.handle, idx )
        }

        public string tabText( int idx )
        {
            ret SLang.QT.ffi_tabText( this.handle, idx )
        }

        public void setTabText( int idx, string title )
        {
            SLang.QT.ffi_tabSetText( this.handle, idx, title )
        }

        # 只移除标签；page 的原生对象由应用侧显式 delete() 释放
        public void removeTab( int idx )
        {
            SLang.QT.ffi_tabRemove( this.handle, idx )
        }

        public void clear() { SLang.QT.ffi_tabClear( this.handle ) }

        public void setTabsClosable( bool on )
        {
            SLang.QT.ffi_tabSetClosable( this.handle, on )
        }

        # handler 形态：static void onTabChanged( int idx )
        public Int64 onCurrentChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TAB_CHANGED, handler )
        }

        # handler 形态：static void onTabClose( int idx )
        public Int64 onCloseRequested( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TAB_CLOSE_REQUESTED, handler )
        }

        # 第十四轮：标签区右键。handler 形态：static void onTabContext( int idx )，
        # idx = 右键所在标签下标（-1 = 非标签区域）
        public Int64 onTabContext( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TAB_CONTEXT, handler )
        }
    }
}
