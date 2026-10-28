Project
{
    _main_()
    {
        # SLangServer P0~P6 验收套件（SERVER_DESIGN.md §8；2026-10-25 自
        # NetTest/ExpendTest 迁出独立用例集，宿主选择器 ServerTest）：
        #   P0 探针=纯语言层无端口  P0 引擎 S=19371-19374
        #   P1=19401-19408  P1.5=19411-19413  P2=19421-19424
        #   P3=19431-19435  P4=19441-19443   P4.5=纯协程无端口
        #   P5=19451-19454（rateLimit/Range/心跳/Jwt/流式上传/路由树）
        #   P6=19461-19462（app 级事件钩子/WS 标签定向组播/broadcast binary）
        #   P7=19471-19472（multipart 流式解析 MultipartReader/saveAs/分帧鲁棒）
        #   P9=19491-19492（@Singleton 控制器 bind-once 单例/异步单例）
        #   P10=19501-19502（setCookie 读写往返/formAll 同名多值/路由级
        #   中间件 params 尾参形态——P3 裁剪三项补齐）
        #   MultiListen=19521-19523（多监听器 v1.1——ServerMultiListenTest）
        #   Mysql=19511（HTTP 路由 handler 内 MySQL 查询集成——ServerMysqlTest）
        #   Bench=19481-19482（M1 上传解析矩阵 stream×memory×4 档 / M2 连接矩阵
        #   keepalive×close；SERVER_DESIGN.md §25 BenchMark 实录）
        ServerProbeTest.fun()
        ServerCoreTest.fun()
        ServerP1Test.fun()
        ServerP15Test.fun()
        ServerP2Test.fun()
        ServerP3Test.fun()
        ServerP4Test.fun()
        ServerP45Test.fun()
        ServerP5Test.fun()
        ServerP6Test.fun()
        ServerP7Test.fun()
        ServerP9Test.fun()
        ServerP10Test.fun()
        ServerMultiListenTest.fun()
        ServerMysqlTest.fun()
        ServerBench.fun()
    }
    _before_()
    {
    }
    _after_()
    {
    }
}
