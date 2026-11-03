import Core;
import Std;

# QHelpEngine —— Qt6Help 封装（底层依赖 Qt6Sql + qsqlite 插件）
namespace SLang
{
    public class QHelpEngine extends QObject
    {
        _init_( string collection )
        {
            this.setHandle( SLang.QT.ffi_helpEngineCreate( collection ) )
        }

        public bool setupData() { ret SLang.QT.ffi_helpSetupData( this.handle ) }
        # error 是 Result 保留名，用 lastError
        public string lastError() { ret SLang.QT.ffi_helpError( this.handle ) }
    }
}
