import Core;
import Std;

# QSqlQuery / QSqlDatabase —— Qt6Sql 封装（sqldrivers 插件随组合部署）
# 注意：QSqlQuery 必须定义在 QSqlDatabase 之前（同文件前向引用的返回
# 类型会被解析为 void）；next 是 SL 关键字（游标推进用 step）；error 是
# Result 保留名（用 lastError）。
namespace SLang
{
    public class QSqlQuery extends QObject
    {
        _init_( Int64 handle )
        {
            this.setHandle( handle )
        }

        public bool exec( string sql ) { ret SLang.QT.ffi_sqlQueryExec( this.handle, sql ) }
        # 语义同 QSqlQuery::next（next 是 SL 关键字）
        public bool step() { ret SLang.QT.ffi_sqlQueryNext( this.handle ) }
        public string valueText( int i ) { ret SLang.QT.ffi_sqlQueryValueText( this.handle, i ) }
        public Int64 valueInt( int i ) { ret SLang.QT.ffi_sqlQueryValueInt( this.handle, i ) }
    }

    public class QSqlDatabase extends QObject
    {
        _init_( string type )
        {
            this.setHandle( SLang.QT.ffi_sqlAddDatabase( type ) )
        }

        public void setDatabaseName( string name ) { SLang.QT.ffi_sqlSetDatabaseName( this.handle, name ) }
        public bool open() { ret SLang.QT.ffi_sqlOpen( this.handle ) }
        public void close() { SLang.QT.ffi_sqlClose( this.handle ) }
        public string lastError() { ret SLang.QT.ffi_sqlLastError( this.handle ) }

        public QSqlQuery createQuery()
        {
            QSqlQuery q = QSqlQuery( SLang.QT.ffi_sqlQueryCreate( this.handle ) )
            ret q
        }
    }
}
