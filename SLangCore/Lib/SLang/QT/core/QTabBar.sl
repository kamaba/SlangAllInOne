import Core;
import Std;

# QTabBar —— 独立标签条（2026-11-16 第二十七轮）
# QTabWidget 内含的标签条不可直接操作；需要独立标签条（面板头部、
# 过滤标签、向导步骤条等）时用本类。标签页内容区由应用侧自行联动。
# 信号：17=当前标签变化(int 下标)，经 _dispatchInt 桥重入。
namespace SLang
{
    public class QTabBar extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_tabbarCreate( parent ) )
        }

        # 返回新标签下标（追加在末尾）
        public int addTab( string title )
        {
            ret SLang.QT.ffi_tabbarAddTab( this.handle, title )
        }

        public void removeTab( int idx )
        {
            SLang.QT.ffi_tabbarRemoveTab( this.handle, idx )
        }

        # 无标签时为 -1
        public int currentIndex()
        {
            ret SLang.QT.ffi_tabbarCurrent( this.handle )
        }

        public void setCurrentIndex( int idx )
        {
            SLang.QT.ffi_tabbarSetCurrent( this.handle, idx )
        }

        public int count() { ret SLang.QT.ffi_tabbarCount( this.handle ) }

        public string tabText( int idx )
        {
            ret SLang.QT.ffi_tabbarTabText( this.handle, idx )
        }

        # handler 形态：static void onTabbarChanged( int idx )
        public Int64 onCurrentChanged( Function handler )
        {
            ret SLang.QT.connect( this.handle, SLang.QT.SIG_TABBAR_CHANGED, handler )
        }
    }
}
