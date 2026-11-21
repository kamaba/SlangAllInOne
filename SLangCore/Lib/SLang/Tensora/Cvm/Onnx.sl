# =========================================================================
# Onnx —— cvm 的 ONNX 模型读取 FFI 中间接口（实例风格）
#
# 底层：C 手写 protobuf wire 解析器（cvm_sl_tensora_lib\sl_onnx.c，slo_*
# 前缀，零外部依赖——无 protobuf/onnx 库/SDK）。读取 ModelProto.graph.
# initializer 权重张量表，物化为连续 f32 缓冲。
#
# 上层语义（实例风格，Onnx 对象内嵌 Int64 _handle）：
#   Onnx m = Onnx.open( "model.onnx" )         # 实例（m.ok() = 是否成功）
#   Int32 n = m.count()                        # 权重张量数
#   string name = m.name( 0 )                  # 张量名
#   Int64 ptr = m.dataPtr( 0 )                 # f32 裸指针
#   Float32 v = Memory.readFloat32( ptr, 0 )   # 按指针读元素（Core 原语）
#   m.close()                                  # 整体释放（ptr 随之失效）
#
# 快路径 loadTensor：预分配 SL 数组 + pin + slo_copy_f32 一次 memcpy
# 物化 Tensor（零逐元素循环），并可直接 .to(Device) 上设备。
#
# v1 范围：dtype = FLOAT（ONNX 1）；float_data / raw_data 两路径都支持
# （raw_data 优先）。后续：节点图解析 / 前向执行器（§8 立项后另行）。
#
# 错误处理以返回值表达（0/-1/空串），原因经 lastError() / errorString()
# 取得（粘性：每次原生入口调用先清零）。DLL 不可用时兜底（lib* 函数体
# 生效）：libCount() 返回 -1 即兜底征兆。打开失败时实例 _handle == 0，
# ok() 为 false，其余实例方法在此状态下返回兜底值（不再重复探测）。
#
# 命名空间由 Tensora.jsonc struct 树定义（namespace Tensora / class Onnx），
# 文件内不声明 namespace 块（同工程其余文件约定一致）。
# =========================================================================

public class Onnx
{
    # ── 实例状态 ────────────────────────────────────────────

    # 原生模型句柄（0 = 未打开/已关闭/打开失败）
    public Int64 _handle = 0

    # ── 构造（_init_ 即打开解析）────────────────────────────

    # 构造即打开：path 打开失败时 _handle == 0（ok() == false）。
    public _init_( string path )
    {
        this._handle = Onnx.libOpen( path )
    }

    # 工厂入口：等价 Onnx( path )，语义上更贴近"打开文件"。
    public static Onnx open( string path )
    {
        ret Onnx( path )
    }

    # ── 低层绑定（sl_onnx.c slo_* 直映射；函数体 = DLL 不可用兜底）──

    @DllStaticImport( "sl_tensora_lib", "slo_open", "utf8->i64" )
    public static Int64 libOpen( string path )
    {
        ret 0
    }

    @DllStaticImport( "sl_tensora_lib", "slo_close", "i64->i32" )
    public static Int32 libClose( Int64 model )
    {
        ret 0
    }

    @DllStaticImport( "sl_tensora_lib", "slo_count", "i64->i32" )
    public static Int32 libCount( Int64 model )
    {
        ret -1
    }

    @DllStaticImport( "sl_tensora_lib", "slo_name", "i64,i32->utf8" )
    public static string libName( Int64 model, Int32 idx )
    {
        ret ""
    }

    @DllStaticImport( "sl_tensora_lib", "slo_rank", "i64,i32->i32" )
    public static Int32 libRank( Int64 model, Int32 idx )
    {
        ret -1
    }

    @DllStaticImport( "sl_tensora_lib", "slo_dim", "i64,i32,i32->i32" )
    public static Int32 libDim( Int64 model, Int32 idx, Int32 axis )
    {
        ret -1
    }

    @DllStaticImport( "sl_tensora_lib", "slo_elem_count", "i64,i32->i32" )
    public static Int32 libElemCount( Int64 model, Int32 idx )
    {
        ret -1
    }

    # ONNX TensorProto.DataType 原值（v1 恒 1 = FLOAT；其他类型 open 即报错）
    @DllStaticImport( "sl_tensora_lib", "slo_data_type", "i64,i32->i32" )
    public static Int32 libDataType( Int64 model, Int32 idx )
    {
        ret -1
    }

    # f32 数据裸指针（模型生命周期内有效；close 后失效）
    @DllStaticImport( "sl_tensora_lib", "slo_data_ptr", "i64,i32->i64" )
    public static Int64 libDataPtr( Int64 model, Int32 idx )
    {
        ret 0
    }

    # 全元素 memcpy 到 dst（pin 指针；零逐元素循环）
    @DllStaticImport( "sl_tensora_lib", "slo_copy_f32", "i64,i32,ptr->i32" )
    public static Int32 libCopyF32( Int64 model, Int32 idx, Int64 dstPtr )
    {
        ret 0
    }

    @DllStaticImport( "sl_tensora_lib", "slo_last_error", "->i32" )
    public static Int32 libLastError()
    {
        ret 0
    }

    @DllStaticImport( "sl_tensora_lib", "slo_error_string", "i32->utf8" )
    public static string libErrorString( Int32 err )
    {
        ret ""
    }

    # 生成测试用最小 ONNX（w0[2,3] float_data + w1[5] raw_data），
    # 供无现成模型文件的环境做端到端验证
    @DllStaticImport( "sl_tensora_lib", "slo_make_test_model", "utf8->i32" )
    public static Int32 libMakeTestModel( string path )
    {
        ret 0
    }

    # ── 实例方法（经 _handle 调用）──────────────────────────

    # 是否持有有效句柄（打开成功且未 close）。
    public bool ok()
    {
        ret this._handle != 0
    }

    # 关闭模型（释放全部解析产物；dataPtr 随之失效）。幂等：已关闭直接
    # 返回 true。关闭后 _handle 置 0（防悬挂二次释放）。
    public bool close()
    {
        if this._handle == 0
        {
            ret true
        }
        bool okClose = Onnx.libClose( this._handle ) != 0
        this._handle = 0
        ret okClose
    }

    # initializer（权重张量）数量。
    public Int32 count()
    {
        ret Onnx.libCount( this._handle )
    }

    # 第 idx 个张量的名字（模型生命周期内共享）。
    public string name( Int32 idx )
    {
        ret Onnx.libName( this._handle, idx )
    }

    # 第 idx 个张量的维数（rank）。
    public Int32 rank( Int32 idx )
    {
        ret Onnx.libRank( this._handle, idx )
    }

    # 第 idx 个张量第 axis 维的尺寸。
    public Int32 dim( Int32 idx, Int32 axis )
    {
        ret Onnx.libDim( this._handle, idx, axis )
    }

    # 第 idx 个张量的元素总数（dims 乘积）。
    public Int32 elemCount( Int32 idx )
    {
        ret Onnx.libElemCount( this._handle, idx )
    }

    # 第 idx 个张量的 ONNX 数据类型原值（1 = FLOAT）。
    public Int32 dataType( Int32 idx )
    {
        ret Onnx.libDataType( this._handle, idx )
    }

    # 第 idx 个张量的 f32 数据裸指针——"上层拿指针读数据"通路：
    #   Memory.readFloat32( ptr, i * 4 )
    # 指针在 close 后失效（SL 侧约定：读毕即关，或先 loadTensor 拷出）。
    public Int64 dataPtr( Int32 idx )
    {
        ret Onnx.libDataPtr( this._handle, idx )
    }

    # 快路径：第 idx 个张量物化为 Tensora Tensor（CPU 驻留，S1）。
    # 预分配数组 + pin + 一次 C memcpy（零逐元素循环）；形状从 dims 逐维
    # 构造。返回 null = 失败（原因查 errorString()）。设备迁移由调用方
    # 追加 .to( Device.gpu( 0 ) )（OQ-1 零复制直传）。
    public Tensor loadTensor( Int32 idx )
    {
        Int32 r = Onnx.libRank( this._handle, idx )
        if r <= 0
        {
            ret null
        }
        Int32 n = Onnx.libElemCount( this._handle, idx )
        if n <= 0
        {
            ret null
        }
        Array<Int32> dims = Array<Int32>( r )
        for a = 0, a < r, a++
        {
            dims[a] = Onnx.libDim( this._handle, idx, a )
        }
        Tensor t = Tensor()
        t._shape = Shape( dims )
        t._strides = t._shape.strides()
        t._data = Array<Float32>( n )
        Int64 dst = Cpu_x64.pinF32( t._data )
        if dst == 0
        {
            ret null
        }
        if Onnx.libCopyF32( this._handle, idx, dst ) == 0
        {
            ret null
        }
        ret t
    }

    # ── 静态辅助（与实例无关）──────────────────────────────

    public static Int32 lastError()
    {
        ret Onnx.libLastError()
    }

    # 错误码转文本；err == 0 时取粘性码。
    public static string errorString()
    {
        ret Onnx.libErrorString( Onnx.libLastError() )
    }

    # 生成测试用最小 ONNX 模型文件（OnnxTest 端到端验证用）。
    public static bool makeTestModel( string path )
    {
        ret Onnx.libMakeTestModel( path ) != 0
    }
}
