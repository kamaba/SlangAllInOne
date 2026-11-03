import Core;
import Std;

# QDomDocument —— Qt6Xml 封装（DOM 解析）
namespace SLang
{
    public class QDomDocument extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_domCreate() )
        }

        public bool setContent( string xml ) { ret SLang.QT.ffi_domSetContent( this.handle, xml ) }
        public string rootTag() { ret SLang.QT.ffi_domRootTag( this.handle ) }
        public Int64 countByTag( string tag ) { ret SLang.QT.ffi_domCountByTag( this.handle, tag ) }
        public string firstText( string tag ) { ret SLang.QT.ffi_domFirstText( this.handle, tag ) }
        public string asString() { ret SLang.QT.ffi_domToString( this.handle ) }
    }
}
