import Core;
import Std;

# QLabel —— 标签（文本 / 位图展示）
namespace SLang
{
    public class QLabel extends QWidget
    {
        _init_( Int64 parent )
        {
            this.setHandle( SLang.QT.ffi_labelCreate( parent ) )
        }

        # setPixmapRgba(ptr, w, h) —— renderTexture 填充通道：ptr 指向
        # RGBA8 top-down 像素块（w*h*4 字节，Memory.alloc 分配；
        # SLangRender 的 RenderContext.renderFrame 回读块即此布局），
        # 经 QImage(Format_RGBA8888) -> QPixmap 显示，随窗口缩放。
        # stub 后端返回 false（无 Qt 渲染能力）。
        public bool setPixmapRgba( Int64 ptr, Int32 w, Int32 h )
        {
            ret SLang.QT.ffi_labelSetPixmapRgba( this.handle, ptr, w, h )
        }
    }
}
