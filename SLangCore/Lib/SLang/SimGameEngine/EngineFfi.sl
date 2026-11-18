import Core;
import Std;

# ============================================================================
# EngineFfi — C99 原生库绑定单点（doc/05 规则 11 同款：新增底层调用声明处）
# ----------------------------------------------------------------------------
# 库：sl_sim_engine_lib.dll（cvm_sim_engine_lib/sle_engine.c，sle_* 纯 C ABI）。
# 分层（同 AudioFfi.sl/ImageFfi.sl）：
#   lib* 直接映射层 —— @DllStaticImport 薄封装，绑定失败走函数体兜底
#   （0/-1/""，libVersionString() == "" 即兜底征兆）
# 封装层：EngineClock.sl（时间周期）/ NodeRegistry.sl（节点管理）。
# 签名集：i32 / i64 / utf8 / bool（引擎 API 全部整型与字符串，无浮点跨界）。
# ============================================================================

public class EngineFfi
{
    # ── 诊断 ──

    @DllStaticImport( "sl_sim_engine_lib", "sle_time_now_us", "->i64" )
    public static Int64 libTimeNowUs()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_time_mark", "->i64" )
    public static Int64 libTimeMark()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_count", "->i32" )
    public static Int32 libNodeCount()
    {
        ret 0
    }

    # ── 定时器 ──

    @DllStaticImport( "sl_sim_engine_lib", "sle_timer_create", "->i64" )
    public static Int64 libTimerCreate()
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_timer_start", "i64->i32" )
    public static Int32 libTimerStart( Int64 h )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_timer_elapsed_us", "i64->i64" )
    public static Int64 libTimerElapsedUs( Int64 h )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_timer_reset", "i64->i32" )
    public static Int32 libTimerReset( Int64 h )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_timer_destroy", "i64->i32" )
    public static Int32 libTimerDestroy( Int64 h )
    {
        ret 0
    }

    # ── 节点注册表 ──

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_register", "utf8,utf8,i32->i64" )
    public static Int64 libNodeRegister( string name, string tag, Int32 layer )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_unregister", "i64->i32" )
    public static Int32 libNodeUnregister( Int64 id )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_find_by_name", "utf8->i64" )
    public static Int64 libNodeFindByName( string name )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_set_layer", "i64,i32->i32" )
    public static Int32 libNodeSetLayer( Int64 id, Int32 layer )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_set_active", "i64,i32->i32" )
    public static Int32 libNodeSetActive( Int64 id, Int32 active )
    {
        ret 0
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_active", "i64->i32" )
    public static Int32 libNodeActive( Int64 id )
    {
        ret 0 - 1
    }

    # name/tag 读回走 ->utf8 直返形态（VM 即时拷贝为 SL string；
    # 勿用 Memory.readUtf8——其语义是读 char* 槽，对内联缓冲是解一层错指针）
    @DllStaticImport( "sl_sim_engine_lib", "sle_node_name_ref", "i64->utf8" )
    public static string libNodeName( Int64 id )
    {
        ret ""
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_node_tag_ref", "i64->utf8" )
    public static string libNodeTag( Int64 id )
    {
        ret ""
    }

    # ── Volume 参数栈混合（计算核心在 C，doc/14 §3；SL 侧只组块/解块）──
    # inPtr：每 Volume 11 float 块（布局见 sle_engine.c）；outPtr：3 float。
    # 返回贡献 Volume 数（>=0）；绑定失败走兜底体返回 -1（VolumeSystem
    # 据此降级 SL 线性混合）。
    @DllStaticImport( "sl_sim_engine_lib", "sle_volume_blend", "i64,i32,i64->i32" )
    public static Int32 libVolumeBlend( Int64 inPtr, Int32 count, Int64 outPtr )
    {
        ret 0 - 1
    }

    # ── GJK 凸点集相交（计算核心在 C，doc/11；float3 紧凑块）────────
    # libPointsTransform：行主序 4x4（16 float）× 点集（含平移）。
    # libGjkIntersect：GJK 布尔（1 相交 / 0 分离 / 参数非法 0）。
    @DllStaticImport( "sl_sim_engine_lib", "sle_points_transform", "i64,i64,i32,i64->i32" )
    public static Int32 libPointsTransform( Int64 mPtr, Int64 srcPtr, Int32 count, Int64 dstPtr )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_gjk_intersect", "i64,i32,i64,i32->i32" )
    public static Int32 libGjkIntersect( Int64 aPtr, Int32 na, Int64 bPtr, Int32 nb )
    {
        ret 0 - 1
    }

    # GJK/MTV：26 方向采样的接触法线 + 穿透深度（outPtr 4 float：
    # nx,ny,nz(B→A)+depth）。返回 1 相交且 MTV 已填 / 0 未相交。
    @DllStaticImport( "sl_sim_engine_lib", "sle_gjk_mtv", "i64,i32,i64,i32,i64->i32" )
    public static Int32 libGjkMtv( Int64 aPtr, Int32 na, Int64 bPtr, Int32 nb, Int64 outPtr )
    {
        ret 0 - 1
    }

    # 正交烘焙投影（P7 烘焙组提交）：世界 float3 → NDC pos2+uv2（stride 16B，
    # uv=0）。返回投影顶点数（>=0）；绑定失败兜底 -1。
    @DllStaticImport( "sl_sim_engine_lib", "sle_ortho_bake", "i64,f32,i64,i32,i64->i32" )
    public static Int32 libOrthoBake( Int64 centerPtr, Float32 viewSize, Int64 srcPtr, Int32 count, Int64 dstPtr )
    {
        ret 0 - 1
    }

    # 带镜头 yaw/pitch 的正交烘焙投影（Alt+拖拽旋转镜头）：cam9 =
    # [eyeX,eyeY,eyeZ, yawRad,pitchRad, viewSize, aspect, pad, pad]；
    # 世界 float3 → NDC pos2+uv2（stride 16B，C 侧内建 aspect 与视图旋转）。
    # 返回处理点数（>=0）；绑定失败兜底 -1。
    @DllStaticImport( "sl_sim_engine_lib", "sle_ortho_bake_view", "i64,i64,i32,i64->i32" )
    public static Int32 libOrthoBakeView( Int64 camPtr, Int64 srcPtr, Int32 count, Int64 dstPtr )
    {
        ret 0 - 1
    }

    # ── 形状生成（P9 shape 库；计算核心在 C，doc/17；SL 侧只组块/解块）──
    # libShapeCounts：outPtr 填 [vertCount, triCount] 两个 Int32。返回 0 成功
    # / -1 形状号非法 / -2 参数非法；绑定失败兜底 -1（ShapeFactory 返回 null）。
    # type 常量见 ShapeTypes；params 为 float 参数块指针（各形状参数个数见 doc/17）。
    @DllStaticImport( "sl_sim_engine_lib", "sle_shape_counts", "i32,i64,i32,i64->i32" )
    public static Int32 libShapeCounts( Int32 type, Int64 paramsPtr, Int32 paramCount, Int64 outCountsPtr )
    {
        ret 0 - 1
    }

    # libShapeBuild：vertPtr 布局 [pos 3V | nrm 3V | uv 2V]（float），
    # triPtr 3T 个 Int32；缓冲由 ShapeFactory 按 counts 分配。返回顶点数（>0）
    # / 负错误码；绑定失败兜底 -1。
    @DllStaticImport( "sl_sim_engine_lib", "sle_shape_build", "i32,i64,i32,i64,i64->i32" )
    public static Int32 libShapeBuild( Int32 type, Int64 paramsPtr, Int32 paramCount, Int64 vertPtr, Int64 triPtr )
    {
        ret 0 - 1
    }

    # 透视相机投影（doc/13 §2.1 专项）：camPtr 9 float（eye3/yaw/pitch/
    # tanHalfFovY/aspect/near/far）× 世界点集 → dst 每点 8 float
    # [ndcX,ndcY,depth01,visible,viewZ,projX,projY,0]。返回可见点数；
    # 绑定失败兜底 -1。
    @DllStaticImport( "sl_sim_engine_lib", "sle_camera_project", "i64,i64,i32,i64->i32" )
    public static Int32 libCameraProject( Int64 camPtr, Int64 srcPtr, Int32 count, Int64 dstPtr )
    {
        ret 0 - 1
    }

    # ── 输入状态表（SnakeGame；键码 = Qt::Key，QT 回调注入/游戏查询）──
    @DllStaticImport( "sl_sim_engine_lib", "sle_input_set_key", "i32,i32->i32" )
    public static Int32 libInputSetKey( Int32 key, Int32 down )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_down", "i32->i32" )
    public static Int32 libInputDown( Int32 key )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_pressed", "i32->i32" )
    public static Int32 libInputPressed( Int32 key )
    {
        ret 0 - 1
    }

    @DllStaticImport( "sl_sim_engine_lib", "sle_input_end_frame", "i32->i32" )
    public static Int32 libInputEndFrame()
    {
        ret 0 - 1
    }
}
