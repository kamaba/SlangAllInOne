import Core;
import Std;

# QPrinter —— Qt6PrintSupport 封装（PDF 输出，无对话框）
namespace SLang
{
    public class QPrinter extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_printerCreate() )
        }

        public void setOutputFileName( string path ) { SLang.QT.ffi_printerSetOutputFilename( this.handle, path ) }
        public void setPageSizeA4() { SLang.QT.ffi_printerSetPageSizeA4( this.handle ) }
        public bool printText( string title, string body ) { ret SLang.QT.ffi_printerPrintText( this.handle, title, body ) }
        public string outputFile() { ret SLang.QT.ffi_printerOutputFile( this.handle ) }
    }
}
