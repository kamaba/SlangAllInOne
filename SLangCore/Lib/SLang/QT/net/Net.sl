import Core;
import Std;

# QNetworkReply / QNetworkAccessManager —— Qt6Network 封装
# （networkinformation / tls 插件随 qtRuntime 组合部署）
# 注意：QNetworkReply 必须定义在 QNetworkAccessManager 之前（同文件
# 前向引用的返回类型会被解析为 void）；error 是 Result 保留名，用 errorString。
namespace SLang
{
    public class QNetworkReply extends QObject
    {
        _init_( Int64 handle )
        {
            this.setHandle( handle )
        }

        public bool wait( int ms ) { ret SLang.QT.ffi_netReplyWait( this.handle, ms ) }
        public int status() { ret SLang.QT.ffi_netReplyStatus( this.handle ) }
        public string errorString() { ret SLang.QT.ffi_netReplyError( this.handle ) }
        public string body() { ret SLang.QT.ffi_netReplyBody( this.handle ) }
    }

    public class QNetworkAccessManager extends QObject
    {
        _init_()
        {
            this.setHandle( SLang.QT.ffi_netCreate() )
        }

        # -1 = 插件缺失（组合未部署 networkinformation）；1 在线 / 0 离线
        public int isOnline() { ret SLang.QT.ffi_netIsOnline() }
        public string backendName() { ret SLang.QT.ffi_netBackendName() }

        # get 是 SL 属性访问器关键字，方法名用 httpGet
        public QNetworkReply httpGet( string url )
        {
            QNetworkReply r = QNetworkReply( SLang.QT.ffi_netGet( this.handle, url ) )
            ret r
        }
    }
}
