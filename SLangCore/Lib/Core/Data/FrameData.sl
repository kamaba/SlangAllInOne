# 帧数据录制与调试剖析基础设施：按调用栈记录多帧 data 快照，支持帧间 diff、变化字段对比。
# 配合 Monitor / Trace 用于运行时调试、回归比对与性能剖析。

public class FrameData
{
    # 创建一个空的帧数据容器（静态工厂）。
    static DataFrame create()
    {

    }
    # 当前已记录的帧数量。
    int    frameCount()
    {
        return 0;
    }
    # 追加一帧：以已克隆的 data 快照入栈。
    void   record( string label, data snapshot ){}
    # 以命名方式批量追加一帧（key 为字段名，value 为 data）。
    void   recordMany( string label, Map<string,data> named ){}
    # 取第 idx 帧的真实 data 副本（不共享内部引用，避免误改历史帧）。
    data   getFrame( int idx ){}
    # 取第 idx 帧的标签名。
    string getLabel( int idx ){}
    # 取第 idx 帧的时间戳。
    Int64  getTimestamp( int idx ){}
    # 取第 idx 帧的压栈深度。
    int    getDepth( int idx ){}
    # 对比第 i/j 两帧（仅比较 data），返回字段级 diff 文本。
    string diff( int i, int j ){}
    # 对比第 i 帧与前一帧（等价 diff(i-1, i)）。
    string diffPrev( int i ){}
    # 返回第 i/j 帧之间发生变化的字段名列表。
    List<string> changedFields( int i, int j ){}
    # 判断第 i/j 两帧的 data 是否相等（使用 DataAllEqual）。
    bool   equals( int i, int j ){}
    # 将全部帧导出到指定路径的文件。
    void   exportToFile( string path ){}
}

# 监视器：对一组被观测 data 自动按帧录制快照；可配置采样频率、触发条件与变化断点。
public class Monitor
{
    # 创建并返回一个绑定名称为 name 的监视器（静态工厂）。
    static Monitor watch( data d, string name )
    # 为指定 data 添加监视（实例方法）。
    void watch( data d, string name )
    # 设置采样频率：每 n 次 record 才采一次。
    void setSampleEvery( int n )
    # 设置采样条件：仅当 cond 为真时才采样。
    void setCondition( bool cond )
    # 设置变化断点：被监视值发生变化时触发 Debug.Break()。
    void setBreakOnChange( bool on )
    # 对所有被监视对象：克隆后记录一帧到 DataFrame。
    void record( string label )
    # 返回累积的帧数据（DataFrame）。
    DataFrame getFrameData()
    # 清空已记录的帧。
    void clear()
}

# 调用栈追踪器：在记录日志的同时附带当前压栈作用域信息，可复用 Log 落盘并导出。
public class Trace
{
    # 创建并返回一个命名为 name 的追踪器（静态工厂）。
    static Trace  create( string name )
    # 复用 Log 的落盘通道，设置输出文件。
    void setFile( string path )
    # 记录一条带当前压栈信息的日志（level 为等级）。
    void log( string msg, int level )
    # 压入 / 弹出作用域（用于构建调用栈快照）。
    void pushScope( string scope ) / popScope( string scope )
    # 返回当前调用栈快照（作用域名数组）。
    Array<string> stackSnapshot()
    # 将追踪结果导出到指定路径。
    void export( string path )
}
